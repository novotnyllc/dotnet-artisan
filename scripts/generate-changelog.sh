#!/usr/bin/env bash
#
# generate-changelog.sh -- Generate changelog entries from the net diff vs last release.
#
# Usage:
#   ./scripts/generate-changelog.sh [--dry-run] [--since TAG] [--changelog FILE]
#
# Options:
#   --dry-run       Print generated entries to stdout without modifying CHANGELOG.md
#   --since TAG     Override the starting point (default: derived from plugin.json version)
#   --changelog FILE  Path to CHANGELOG.md (default: CHANGELOG.md in repo root)
#
# When run without --dry-run, inserts generated entries into the [Unreleased]
# section of CHANGELOG.md, preserving any existing manual entries.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$REPO_ROOT"

DRY_RUN=false
SINCE_TAG=""
CHANGELOG="$REPO_ROOT/CHANGELOG.md"
TAG_PREFIX="dotnet-artisan/v"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)     DRY_RUN=true; shift ;;
        --since)       SINCE_TAG="$2"; shift 2 ;;
        --changelog)   CHANGELOG="$2"; shift 2 ;;
        -h|--help)
            sed -n '2,/^$/{ s/^# //; s/^#//; p; }' "$0"
            exit 0
            ;;
        *) echo "ERROR: Unknown option: $1"; exit 1 ;;
    esac
done

# --- Determine commit range ---

if [ -z "$SINCE_TAG" ]; then
    # Try the version in plugin.json first. If its tag exists, use it.
    # If not (version was already bumped), find the nearest prior version tag.
    PLUGIN_JSON="$REPO_ROOT/plugins/dotnet-artisan/.claude-plugin/plugin.json"
    if [ -f "$PLUGIN_JSON" ] && command -v jq &>/dev/null; then
        CURRENT_VERSION=$(jq -r '.version' "$PLUGIN_JSON")
        if [ -n "$CURRENT_VERSION" ] && [ "$CURRENT_VERSION" != "null" ]; then
            CANDIDATE="${TAG_PREFIX}${CURRENT_VERSION}"
            if git rev-parse "$CANDIDATE" &>/dev/null; then
                SINCE_TAG="$CANDIDATE"
            fi
        fi
    fi

    # plugin.json tag didn't resolve -- find the most recent existing version tag
    if [ -z "$SINCE_TAG" ]; then
        SINCE_TAG=$(git tag --list "${TAG_PREFIX}*" --sort=-version:refname | head -1)
    fi
fi

if [ -n "$SINCE_TAG" ]; then
    RANGE="${SINCE_TAG}..HEAD"
    echo "Generating changelog from $SINCE_TAG to HEAD"
else
    RANGE=""
    echo "No previous tag found -- generating changelog from all commits"
fi

COMMIT_COUNT=$(git log --no-merges --format='%s' $RANGE -- | wc -l | tr -d ' ')
if [ "$COMMIT_COUNT" -eq 0 ]; then
    echo "No commits found in range -- nothing to generate"
    exit 0
fi

echo "  $COMMIT_COUNT commits in range"

# --- Collect diff and generate changelog via Claude ---
# Use the net diff (HEAD vs last release) rather than individual commit messages.
# Intermediate commits are noise -- the diff captures what actually changed.

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# File-level summary
git diff --stat $RANGE > "$TMP_DIR/diffstat.txt"

# Full diff, truncated to avoid blowing context limits
MAX_DIFF_LINES=3000
git diff $RANGE > "$TMP_DIR/full_diff.txt"
DIFF_LINES=$(wc -l < "$TMP_DIR/full_diff.txt" | tr -d ' ')
if [ "$DIFF_LINES" -gt "$MAX_DIFF_LINES" ]; then
    head -n "$MAX_DIFF_LINES" "$TMP_DIR/full_diff.txt" > "$TMP_DIR/diff.txt"
    echo "(truncated at $MAX_DIFF_LINES of $DIFF_LINES lines)" >> "$TMP_DIR/diff.txt"
    echo "  Diff truncated: $DIFF_LINES lines -> $MAX_DIFF_LINES"
else
    cp "$TMP_DIR/full_diff.txt" "$TMP_DIR/diff.txt"
fi

# Build the prompt with concrete examples from the existing changelog
cat > "$TMP_DIR/prompt.txt" << 'PROMPT_EOF'
Generate Keep-a-Changelog entries from the diff below. The diff shows the
net change between the last release and the current HEAD. Use it to
understand what changed, but write about features and capabilities, not
individual files.

OUTPUT FORMAT -- raw markdown only, no commentary, no code fences, no preamble:

### Added

- **Feature name** -- What new capability was added and why it matters to users
- **Another feature** -- Concise user-facing description

### Changed

- **Feature or behavior** -- What changed and the practical effect for users

### Fixed

- **Bug or issue** -- What was broken and how it's fixed

RULES:
- Describe features, behaviors, and capabilities -- never individual files or paths.
- Omit empty sections entirely.
- Synthesize related changes into ONE bullet about the feature they serve.
- Skip: whitespace-only changes, comment-only edits, flow/task tracker state, internal refactoring with no user-facing effect.
- Write for users of the plugin, not contributors. "Consolidated WinUI reference files" is bad. "Streamlined WinUI guidance covering controls, layout, and theming" is good.
- Bold the feature area, use " -- " separator, then describe the change.
- Aim for 3-10 bullets total. Fewer is better.
- Output ONLY the markdown. No analysis, no explanations, no "here's what I found" preamble.

EXAMPLE of good output (from a prior release):

### Added

- **Version bump automation** -- `scripts/bump.sh` propagates version to plugin.json, marketplace.json, README badge, and CHANGELOG footer links
- **Root marketplace validation** -- `scripts/validate-root-marketplace.sh` as shared validation used by both local and CI workflows

### Changed

- **Marketplace restructure** -- Flat marketplace layout with root `.claude-plugin/marketplace.json` discovery file
- **Per-plugin versioning** -- Release workflow uses `dotnet-artisan/v*` tag format instead of `v*`
- **Description budget trimmed** from 13,481 to 11,948 chars -- now below the 12,000-char warning threshold

FILE SUMMARY:

PROMPT_EOF

cat "$TMP_DIR/diffstat.txt" >> "$TMP_DIR/prompt.txt"
echo "" >> "$TMP_DIR/prompt.txt"
echo "FULL DIFF:" >> "$TMP_DIR/prompt.txt"
echo "" >> "$TMP_DIR/prompt.txt"
cat "$TMP_DIR/diff.txt" >> "$TMP_DIR/prompt.txt"

echo "  Calling Codex ..."

codex exec -m gpt-5.3-codex-spark --color never --ephemeral \
    --skip-git-repo-check -C "$TMP_DIR" \
    -o "$TMP_DIR/output.txt" \
    - < "$TMP_DIR/prompt.txt" >"$TMP_DIR/stderr.txt" 2>&1

if [ $? -ne 0 ]; then
    echo "ERROR: Codex call failed"
    cat "$TMP_DIR/stderr.txt" >&2
    exit 1
fi

OUTPUT=$(cat "$TMP_DIR/output.txt")

if [ -z "$OUTPUT" ]; then
    echo "ERROR: Codex returned empty output"
    exit 1
fi

# Strip code fences if Claude added them
OUTPUT=$(echo "$OUTPUT" | sed '/^```/d')

# --- Dry-run or insert ---

if [ "$DRY_RUN" = true ]; then
    echo ""
    echo "$OUTPUT"
    exit 0
fi

# Insert into CHANGELOG.md [Unreleased] section
if [ ! -f "$CHANGELOG" ]; then
    echo "ERROR: CHANGELOG.md not found at $CHANGELOG"
    exit 1
fi

# Extract existing [Unreleased] content
EXISTING=$(awk '/^## \[Unreleased\]/{flag=1;next}/^## \[/{flag=0}flag' "$CHANGELOG" | sed '/^[[:space:]]*$/d')

if [ -n "$EXISTING" ]; then
    NEW_CONTENT="${EXISTING}

${OUTPUT}"
else
    NEW_CONTENT="${OUTPUT}"
fi

# Write content to temp file for awk (awk -v can't handle multi-line strings)
CONTENT_FILE=$(mktemp)
echo "$NEW_CONTENT" > "$CONTENT_FILE"

TMP_FILE=$(mktemp)
awk -v "cfile=$CONTENT_FILE" '
/^## \[Unreleased\]/ {
    print
    print ""
    while ((getline cline < cfile) > 0) print cline
    close(cfile)
    print ""
    # Skip old content until next ## [ header
    while ((getline line) > 0) {
        if (line ~ /^## \[/) { print line; break }
    }
    next
}
{print}
' "$CHANGELOG" > "$TMP_FILE" && mv "$TMP_FILE" "$CHANGELOG"
rm -f "$CONTENT_FILE"

echo "  Updated [Unreleased] section"
