#!/usr/bin/env bash
#
# validate-skills.sh -- Validate all SKILL.md files and agent files in the
# dotnet-artisan plugin. Also runs semantic similarity detection if available.
#
# Thin wrapper that invokes the Python validation script and (optionally)
# the similarity detection script.
#
# All parsing, validation, and reporting happens in Python for:
#   - Deterministic YAML parsing (strict subset parser, no PyYAML dependency)
#   - No per-file subprocess spawning
#   - Identical behavior across all environments
#
# Requirements:
#   - python3
#
# Environment variables:
#   STRICT_REFS=1         -- Treat unresolved cross-references as errors (default: downgrade to warnings).
#   STRICT_INVOCATION=1   -- Treat invocation contract violations as errors (default: downgrade to warnings).
#
# STRICT_REFS and STRICT_INVOCATION are independent toggles:
#   - STRICT_REFS controls whether [skill:] references resolve to existing skill/agent IDs.
#   - STRICT_INVOCATION controls whether SKILL.md files satisfy the 3-rule invocation contract
#     (Scope bullets, OOS bullets, OOS [skill:] presence). See docs/skill-routing-style-guide.md section 6.
#
# During early development most skills are planned stubs, so --allow-planned-refs
# is the default. Set STRICT_REFS=1 to enforce strict cross-reference validation.
#
# Output keys (stable, CI-parseable -- validator):
#   CURRENT_DESC_CHARS=<N>
#   PROJECTED_DESC_CHARS=<N>
#   BUDGET_STATUS=OK|WARN|FAIL
#   NAME_DIR_MISMATCHES=<N>
#   EXTRA_FIELD_COUNT=<N>
#   TYPE_WARNING_COUNT=<N>
#   FILLER_PHRASE_COUNT=<N>
#   WHEN_PREFIX_COUNT=<N>
#   NAME_FORMAT_ERROR_COUNT=<N>
#   DESC_HARDCAP_ERROR_COUNT=<N>
#   DESC_PRONOUN_WARN_COUNT=<N>
#   DESC_NEGATIVE_TRIGGER_WARN_COUNT=<N>
#   SKILL_LINE_BUDGET_WARN_COUNT=<N>
#   NESTED_RESOURCE_WARN_COUNT=<N>
#   HUMAN_DOC_WARN_COUNT=<N>
#   PATH_SLASH_WARN_COUNT=<N>
#   MISSING_SCOPE_COUNT=<N>
#   MISSING_OOS_COUNT=<N>
#   SELF_REF_COUNT=<N>
#   AGENT_BARE_REF_COUNT=<N>
#   AGENTSMD_BARE_REF_COUNT=<N>
#   INVOCATION_CONTRACT_WARN_COUNT=<N>
#
# Output keys (stable, CI-parseable -- similarity, when script is present):
#   MAX_SIMILARITY_SCORE=<N>
#   PAIRS_ABOVE_WARN=<N>
#   PAIRS_ABOVE_ERROR=<N>

set -euo pipefail

if ! command -v python3 &>/dev/null; then
    echo "ERROR: python3 required but not found in PATH"
    exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLUGIN_DIR="$REPO_ROOT/plugins/dotnet-artisan"

# Default to allowing planned refs (most skills are stubs during early development).
# Set STRICT_REFS=1 to treat unresolved cross-references as errors.
ALLOW_PLANNED_FLAG="--allow-planned-refs"
if [ "${STRICT_REFS:-}" = "1" ]; then
    ALLOW_PLANNED_FLAG=""
fi

# --- Run skill/agent validator ---
VALIDATOR_EXIT=0
python3 "$REPO_ROOT/scripts/_validate_skills.py" \
    --repo-root "$PLUGIN_DIR" \
    --projected-skills 9 \
    --max-desc-chars 600 \
    --warn-threshold 12000 \
    --fail-threshold 15600 \
    $ALLOW_PLANNED_FLAG || VALIDATOR_EXIT=$?

# --- Run similarity detection (baseline regression mode) ---
SIMILARITY_EXIT=0
if [[ -f "$REPO_ROOT/scripts/validate-similarity.py" ]]; then
    echo ""
    echo "=== Similarity Detection ==="
    SIM_JSON="$(mktemp)"
    SIM_ERR="$(mktemp)"
    python3 "$REPO_ROOT/scripts/validate-similarity.py" \
        --repo-root "$PLUGIN_DIR" \
        --baseline "$REPO_ROOT/scripts/similarity-baseline.json" \
        --suppressions "$REPO_ROOT/scripts/similarity-suppressions.json" \
        >"$SIM_JSON" 2>"$SIM_ERR" || SIMILARITY_EXIT=$?
    # Emit stable CI keys (from stderr) to stdout for CI capture
    cat "$SIM_ERR"
    # Print JSON report only on failure or locally (non-CI)
    if [[ "$SIMILARITY_EXIT" -ne 0 ]] || [[ -z "${CI:-}" ]]; then
        cat "$SIM_JSON"
    fi
    rm -f "$SIM_JSON" "$SIM_ERR"
fi

# --- Compose final exit code ---
if [[ "$VALIDATOR_EXIT" -ne 0 ]] || [[ "$SIMILARITY_EXIT" -ne 0 ]]; then
    exit 1
fi

exit 0
