#!/usr/bin/env bash
#
# bump.sh -- Bump the version of a plugin and propagate to all version-bearing files.
#
# Usage:
#   ./scripts/bump.sh <patch|minor|major> [plugin-name]
#
# Arguments:
#   patch|minor|major  -- Which semver component to bump
#   plugin-name        -- Plugin to bump (default: dotnet-artisan)
#
# Version is propagated to:
#   1. plugins/<name>/.claude-plugin/plugin.json       (canonical source of truth)
#   2. plugins/<name>/.codex-plugin/plugin.json        (Codex plugin manifest)
#   3. .claude-plugin/marketplace.json                 (root, matching plugin entry)
#   4. .claude-plugin/marketplace.json  (metadata.version)
#   5. README.md                        (version badge)
#   6. CHANGELOG.md                     (promote [Unreleased], update footer links)
#
# After running, commit the changes in your PR branch. When the PR merges to
# main, the auto-tag workflow creates the git tag and triggers the release.

set -euo pipefail

# Navigate to repository root
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$REPO_ROOT"

# --- Argument parsing ---

BUMP_TYPE="${1:-}"
PLUGIN_NAME="${2:-dotnet-artisan}"

if [[ -z "$BUMP_TYPE" ]]; then
    echo "Usage: $0 <patch|minor|major> [plugin-name]"
    echo ""
    echo "  patch  -- Bump patch version (0.1.0 -> 0.1.1)"
    echo "  minor  -- Bump minor version (0.1.0 -> 0.2.0)"
    echo "  major  -- Bump major version (0.1.0 -> 1.0.0)"
    exit 1
fi

if [[ "$BUMP_TYPE" != "patch" && "$BUMP_TYPE" != "minor" && "$BUMP_TYPE" != "major" ]]; then
    echo "ERROR: Invalid bump type '$BUMP_TYPE'. Must be patch, minor, or major."
    exit 1
fi

# --- Validate paths ---

PLUGIN_DIR="$REPO_ROOT/plugins/$PLUGIN_NAME"
PLUGIN_JSON="$PLUGIN_DIR/.claude-plugin/plugin.json"
CODEX_PLUGIN_JSON="$PLUGIN_DIR/.codex-plugin/plugin.json"
ROOT_MARKETPLACE="$REPO_ROOT/.claude-plugin/marketplace.json"
README="$REPO_ROOT/README.md"
CHANGELOG="$REPO_ROOT/CHANGELOG.md"

if [ ! -f "$PLUGIN_JSON" ]; then
    echo "ERROR: plugin.json not found at $PLUGIN_JSON"
    exit 1
fi

if [ ! -f "$ROOT_MARKETPLACE" ]; then
    echo "ERROR: root marketplace.json not found at $ROOT_MARKETPLACE"
    exit 1
fi

if [ ! -f "$CODEX_PLUGIN_JSON" ]; then
    echo "ERROR: Codex plugin.json not found at $CODEX_PLUGIN_JSON"
    exit 1
fi

# --- Check jq is available ---

if ! command -v jq &>/dev/null; then
    echo "ERROR: jq is required but not found in PATH"
    exit 1
fi

# --- Read current version ---

CURRENT_VERSION=$(jq -r '.version' "$PLUGIN_JSON")
if [[ -z "$CURRENT_VERSION" || "$CURRENT_VERSION" == "null" ]]; then
    echo "ERROR: Could not read version from $PLUGIN_JSON"
    exit 1
fi

echo "Current version: $CURRENT_VERSION"

# --- Compute new version ---

IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"

# Validate components are numeric
if ! [[ "$MAJOR" =~ ^[0-9]+$ && "$MINOR" =~ ^[0-9]+$ && "$PATCH" =~ ^[0-9]+$ ]]; then
    echo "ERROR: Current version '$CURRENT_VERSION' is not valid semver (expected X.Y.Z)"
    exit 1
fi

case "$BUMP_TYPE" in
    major)
        MAJOR=$((MAJOR + 1))
        MINOR=0
        PATCH=0
        ;;
    minor)
        MINOR=$((MINOR + 1))
        PATCH=0
        ;;
    patch)
        PATCH=$((PATCH + 1))
        ;;
esac

NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}"
TODAY=$(date +%Y-%m-%d)

echo "New version:     $NEW_VERSION"
echo ""

# --- 0. Auto-generate changelog entries from conventional commits ---

GENERATE_SCRIPT="$REPO_ROOT/scripts/generate-changelog.sh"
if [ -f "$GENERATE_SCRIPT" ] && [ -x "$GENERATE_SCRIPT" ]; then
    echo "Generating changelog entries from diff vs last release ..."
    if "$GENERATE_SCRIPT" --changelog "$CHANGELOG"; then
        echo "  OK: Changelog entries generated"
    else
        echo "  WARN: Changelog generation failed (continuing with manual entries)"
    fi
    echo ""
fi

# --- 1. Update plugin.json (canonical) ---

echo "Updating $PLUGIN_JSON ..."
TMP_FILE=$(mktemp)
jq --arg v "$NEW_VERSION" '.version = $v' "$PLUGIN_JSON" > "$TMP_FILE" && mv "$TMP_FILE" "$PLUGIN_JSON"
echo "  OK: plugin.json version -> $NEW_VERSION"

# --- 2. Update Codex plugin.json ---

echo "Updating $CODEX_PLUGIN_JSON ..."
TMP_FILE=$(mktemp)
jq --arg v "$NEW_VERSION" '.version = $v' "$CODEX_PLUGIN_JSON" > "$TMP_FILE" && mv "$TMP_FILE" "$CODEX_PLUGIN_JSON"
echo "  OK: Codex plugin.json version -> $NEW_VERSION"

# --- 3. Update root marketplace.json (plugin entry version) ---

echo "Updating $ROOT_MARKETPLACE ..."
TMP_FILE=$(mktemp)
jq --arg name "$PLUGIN_NAME" --arg v "$NEW_VERSION" \
    '(.plugins[] | select(.name == $name)).version = $v' \
    "$ROOT_MARKETPLACE" > "$TMP_FILE" && mv "$TMP_FILE" "$ROOT_MARKETPLACE"
echo "  OK: root marketplace.json plugin '$PLUGIN_NAME' version -> $NEW_VERSION"

# --- 4. Update root marketplace.json (metadata.version) ---

TMP_FILE=$(mktemp)
jq --arg v "$NEW_VERSION" '.metadata.version = $v' "$ROOT_MARKETPLACE" > "$TMP_FILE" && mv "$TMP_FILE" "$ROOT_MARKETPLACE"
echo "  OK: root marketplace.json metadata.version -> $NEW_VERSION"

# --- 5. Update README.md version badge ---

if [ -f "$README" ]; then
    # Match shields.io badge pattern: version-X.Y.Z-color
    if grep -q "version-${CURRENT_VERSION}-" "$README"; then
        TMP_FILE=$(mktemp)
        sed "s/version-${CURRENT_VERSION}-/version-${NEW_VERSION}-/g" "$README" > "$TMP_FILE" && mv "$TMP_FILE" "$README"
        echo "  OK: README.md badge version -> $NEW_VERSION"
    else
        echo "  WARN: No version badge found in README.md (looked for 'version-${CURRENT_VERSION}-')"
    fi
else
    echo "  WARN: README.md not found at $README"
fi

# --- 6. Update CHANGELOG.md ---

if [ -f "$CHANGELOG" ]; then
    echo "Updating $CHANGELOG ..."

    # Promote [Unreleased] to [NEW_VERSION] - YYYY-MM-DD
    # Insert new empty [Unreleased] section after the header
    TMP_FILE=$(mktemp)

    awk -v version="$NEW_VERSION" -v date="$TODAY" -v plugin="$PLUGIN_NAME" '
    /^## \[Unreleased\]/ {
        # Print new [Unreleased] header with empty sections
        print "## [Unreleased]"
        print ""
        # Print the versioned section header
        print "## [" version "] - " date
        next
    }
    {print}
    ' "$CHANGELOG" > "$TMP_FILE" && mv "$TMP_FILE" "$CHANGELOG"

    # Update footer comparison links
    # Replace [unreleased] link to compare from new tag
    # Add new version link
    TAG_PREFIX="${PLUGIN_NAME}/v"

    # Update the [unreleased] comparison link
    TMP_FILE=$(mktemp)
    sed "s|\[unreleased\]:.*|[unreleased]: https://github.com/novotnyllc/dotnet-artisan/compare/${TAG_PREFIX}${NEW_VERSION}...HEAD|" "$CHANGELOG" > "$TMP_FILE" && mv "$TMP_FILE" "$CHANGELOG"

    # Check if a version link for the new version already exists
    if ! grep -q "^\[${NEW_VERSION}\]:" "$CHANGELOG"; then
        # Find the previous version tag for comparison
        # If current version had a tag, link from that; otherwise link to first commit
        if [ "$CURRENT_VERSION" = "0.1.0" ]; then
            # First release scenario: no prior tag exists, link to the tag directly
            VERSION_LINK="[${NEW_VERSION}]: https://github.com/novotnyllc/dotnet-artisan/releases/tag/${TAG_PREFIX}${NEW_VERSION}"
        else
            VERSION_LINK="[${NEW_VERSION}]: https://github.com/novotnyllc/dotnet-artisan/compare/${TAG_PREFIX}${CURRENT_VERSION}...${TAG_PREFIX}${NEW_VERSION}"
        fi

        # Insert the new version link after the [unreleased] link
        TMP_FILE=$(mktemp)
        awk -v link="$VERSION_LINK" '/^\[unreleased\]:/{print; print link; next}{print}' "$CHANGELOG" > "$TMP_FILE" && mv "$TMP_FILE" "$CHANGELOG"
    fi

    # Fix old footer links that use wrong tag format (e.g., v0.1.0 instead of dotnet-artisan/v0.1.0)
    TMP_FILE=$(mktemp)
    sed "s|compare/v${CURRENT_VERSION}\.\.\.|compare/${TAG_PREFIX}${CURRENT_VERSION}...|g" "$CHANGELOG" > "$TMP_FILE" && mv "$TMP_FILE" "$CHANGELOG"
    TMP_FILE=$(mktemp)
    sed "s|/tag/v${CURRENT_VERSION}$|/tag/${TAG_PREFIX}${CURRENT_VERSION}|" "$CHANGELOG" > "$TMP_FILE" && mv "$TMP_FILE" "$CHANGELOG"

    echo "  OK: CHANGELOG.md [Unreleased] promoted to [$NEW_VERSION] - $TODAY"
    echo "  OK: CHANGELOG.md footer links updated to ${TAG_PREFIX}* format"
else
    echo "  WARN: CHANGELOG.md not found at $CHANGELOG"
fi

echo ""
echo "=== Version bump complete: $CURRENT_VERSION -> $NEW_VERSION ==="
echo ""
echo "Next steps:"
echo ""
echo "  1. Review changes:"
echo "     git diff"
echo ""
echo "  2. Commit in your PR branch:"
echo "     git add -A && git commit -m \"chore(release): bump $PLUGIN_NAME to v$NEW_VERSION\""
echo ""
echo "  3. Merge to main -- the auto-tag workflow will create tag ${TAG_PREFIX}${NEW_VERSION} and trigger the release."
echo ""
