#!/usr/bin/env bash
#
# build-marketplace-artifacts.sh -- Build per-provider marketplace artifacts for a release.
#
# Usage:
#   ./scripts/build-marketplace-artifacts.sh [version]
#
# Arguments:
#   version  -- Version to stamp on artifacts (default: reads from .claude-plugin/plugin.json)
#
# Outputs (written to artifacts/):
#   claude-marketplace-vX.Y.Z.json   -- Claude Code manifest + marketplace bundle
#   codex-marketplace-vX.Y.Z.json    -- OpenAI Codex manifest + marketplace bundle
#   copilot-manifest-vX.Y.Z.json     -- Copilot compatibility manifest with skill inventory
#   publish-manifest-vX.Y.Z.json     -- Unified publish manifest with provider map
#
# Design constraints:
#   - No network calls (offline artifact generation)
#   - Requires only jq and standard coreutils
#   - Idempotent (safe to re-run)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
VERSION="${1:-}"

if [ -z "$VERSION" ]; then
    VERSION=$(jq -r '.version' "$REPO_ROOT/.claude-plugin/plugin.json")
fi

if [ -z "$VERSION" ] || [ "$VERSION" = "null" ]; then
    echo "ERROR: Could not determine version"
    exit 1
fi

ARTIFACT_DIR="$REPO_ROOT/artifacts"
rm -rf "$ARTIFACT_DIR"
mkdir -p "$ARTIFACT_DIR"

echo "=== Building marketplace artifacts for v$VERSION ==="
echo ""

# --- 1. Claude Code marketplace bundle ---

echo "--- Claude Code marketplace ---"
CLAUDE_BUNDLE="$ARTIFACT_DIR/claude-marketplace-v${VERSION}.json"

jq -n \
    --arg v "$VERSION" \
    --arg provider "claude-code" \
    --slurpfile plugin "$REPO_ROOT/.claude-plugin/plugin.json" \
    --slurpfile mkt "$REPO_ROOT/.claude-plugin/marketplace.json" \
    '{
        provider: $provider,
        version: $v,
        plugin: $plugin[0],
        marketplace: $mkt[0]
    }' > "$CLAUDE_BUNDLE"

echo "OK: $CLAUDE_BUNDLE"

# --- 2. OpenAI Codex marketplace bundle ---

echo "--- OpenAI Codex marketplace ---"
CODEX_BUNDLE="$ARTIFACT_DIR/codex-marketplace-v${VERSION}.json"

jq -n \
    --arg v "$VERSION" \
    --arg provider "openai-codex" \
    --slurpfile plugin "$REPO_ROOT/.codex-plugin/plugin.json" \
    --slurpfile mkt "$REPO_ROOT/.agents/plugins/marketplace.json" \
    '{
        provider: $provider,
        version: $v,
        plugin: $plugin[0],
        marketplace: $mkt[0]
    }' > "$CODEX_BUNDLE"

echo "OK: $CODEX_BUNDLE"

# --- 3. Copilot CLI compatibility manifest ---

echo "--- GitHub Copilot CLI ---"
COPILOT_BUNDLE="$ARTIFACT_DIR/copilot-manifest-v${VERSION}.json"

# Enumerate flat skill directories
SKILL_NAMES="[]"
if [ -d "$REPO_ROOT/skills" ]; then
    SKILL_NAMES=$(find "$REPO_ROOT/skills" -maxdepth 1 -mindepth 1 -type d -exec basename {} \; | sort | jq -R . | jq -s .)
fi

jq -n \
    --arg v "$VERSION" \
    --arg name "dotnet-artisan" \
    --arg provider "github-copilot-cli" \
    --argjson skills "$SKILL_NAMES" \
    '{
        provider: $provider,
        version: $v,
        name: $name,
        skills: $skills,
        flat_layout: true,
        license: "MIT"
    }' > "$COPILOT_BUNDLE"

echo "OK: $COPILOT_BUNDLE"

# --- 4. Unified publish manifest ---

echo "--- Unified publish manifest ---"
MANIFEST="$ARTIFACT_DIR/publish-manifest-v${VERSION}.json"

TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
SKILL_COUNT=$(find "$REPO_ROOT/skills" -maxdepth 2 -name SKILL.md 2>/dev/null | wc -l | tr -d ' ')
AGENT_COUNT=$(find "$REPO_ROOT/agents" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')

jq -n \
    --arg v "$VERSION" \
    --arg tag "dotnet-artisan/v${VERSION}" \
    --arg ts "$TIMESTAMP" \
    --arg repo "novotnyllc/dotnet-artisan" \
    --argjson skill_count "$SKILL_COUNT" \
    --argjson agent_count "$AGENT_COUNT" \
    '{
        version: $v,
        tag: $tag,
        published_at: $ts,
        repository: $repo,
        stats: {
            skills: $skill_count,
            agents: $agent_count
        },
        providers: {
            claude: {
                manifest: ".claude-plugin/plugin.json",
                marketplace: ".claude-plugin/marketplace.json",
                discovery: "github-release"
            },
            codex: {
                manifest: ".codex-plugin/plugin.json",
                marketplace: ".agents/plugins/marketplace.json",
                discovery: "repo-manifest"
            },
            copilot: {
                manifest: ".claude-plugin/plugin.json",
                skills_layout: "flat",
                discovery: "github-release"
            }
        }
    }' > "$MANIFEST"

echo "OK: $MANIFEST"

echo ""
echo "=== All artifacts built ==="
echo ""
ls -lh "$ARTIFACT_DIR"
