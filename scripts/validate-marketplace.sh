#!/usr/bin/env bash
#
# validate-marketplace.sh -- Validate plugin manifests and marketplace metadata for dotnet-artisan.
#
# Checks:
#   1. Claude plugin manifest exists and is valid JSON
#   2. Claude plugin manifest has canonical schema: skills (array), agents (array), hooks (optional string), mcpServers (optional string)
#   3. All skill directories referenced in the Claude plugin manifest contain SKILL.md
#   4. All agent files referenced in the Claude plugin manifest exist
#   5. hooks and mcpServers paths exist
#   6. hooks.json has "hooks" key
#   7. .mcp.json has "mcpServers" key
#   8. scripts/hooks/*.js have valid syntax
#   9. Codex plugin manifest exists, validates, and stays consistent with the Claude manifest
#  10. Legacy Codex skill-installer metadata is validated only when present
#  11. Root Claude marketplace.json validates (delegates to validate-root-marketplace.sh)
#  12. Claude plugin enrichment fields: author, homepage, repository, license, keywords
#
# Design constraints:
#   - Single-pass validation (no subprocess spawning per entry, no network)
#   - Runs in <5 seconds
#   - Same commands locally and in CI
#   - Exits non-zero on validation failures

set -euo pipefail

# Navigate to repository root (parent of scripts/), canonicalized for symlink safety
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
PLUGIN_DIR="$REPO_ROOT/plugins/dotnet-artisan"

PLUGIN_JSON="$PLUGIN_DIR/.claude-plugin/plugin.json"

errors=0
warnings=0

# Reject paths that escape the plugin directory (traversal, absolute, symlink escape)
validate_path_safe() {
    local path="$1"
    local label="$2"

    # Reject absolute paths
    if [[ "$path" = /* ]]; then
        echo "ERROR: $label contains absolute path: $path"
        return 1
    fi

    # Reject parent traversal
    if [[ "$path" == *".."* ]]; then
        echo "ERROR: $label contains path traversal (..): $path"
        return 1
    fi

    # Resolve canonical path (following symlinks) and verify it stays under PLUGIN_DIR
    local full_path="$PLUGIN_DIR/$path"
    if [ -e "$full_path" ]; then
        local resolved
        # Use python3 for portable symlink-resolving realpath (macOS lacks GNU realpath)
        resolved="$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$full_path")"
        case "$resolved" in
            "$PLUGIN_DIR"/*) ;;  # OK - under plugin dir
            *)
                echo "ERROR: $label resolves outside plugin directory: $path -> $resolved"
                return 1
                ;;
        esac
    fi

    return 0
}

echo "=== Marketplace Validation ==="
echo ""

# --- plugin.json validation ---

echo "--- plugin.json ---"

if [ ! -f "$PLUGIN_JSON" ]; then
    echo "ERROR: plugin.json not found at $PLUGIN_JSON"
    errors=$((errors + 1))
else
    # Validate JSON is well-formed
    if ! jq empty "$PLUGIN_JSON" 2>/dev/null; then
        echo "ERROR: plugin.json is not valid JSON"
        errors=$((errors + 1))
    else
        echo "OK: plugin.json is valid JSON"

        # Check required top-level fields (must be non-empty strings)
        for field in name version description; do
            if ! jq -e ".$field | type == \"string\" and length > 0" "$PLUGIN_JSON" >/dev/null 2>&1; then
                echo "ERROR: plugin.json.$field must be a non-empty string"
                errors=$((errors + 1))
            else
                value=$(jq -r ".$field" "$PLUGIN_JSON")
                echo "OK: plugin.json.$field = \"$value\""
            fi
        done

        # Validate skills is an array of string paths
        skills_valid=$(jq -e '.skills | type == "array" and all(.[]; type == "string")' "$PLUGIN_JSON" 2>/dev/null) || skills_valid="false"
        if [ "$skills_valid" != "true" ]; then
            echo "ERROR: plugin.json.skills must be an array of string paths"
            errors=$((errors + 1))
        else
            skill_count=$(jq -r '.skills | length' "$PLUGIN_JSON")
            echo "OK: plugin.json.skills is an array of strings ($skill_count entries)"

            # Check each skill directory exists and contains SKILL.md
            while IFS= read -r skill_path; do
                if ! validate_path_safe "$skill_path" "skills[]"; then
                    errors=$((errors + 1))
                    continue
                fi
                full_path="$PLUGIN_DIR/$skill_path"
                if [ ! -d "$full_path" ]; then
                    echo "ERROR: skill directory not found: $skill_path"
                    errors=$((errors + 1))
                elif [ ! -f "$full_path/SKILL.md" ]; then
                    echo "ERROR: SKILL.md not found in skill directory: $skill_path"
                    errors=$((errors + 1))
                else
                    echo "OK: $skill_path/SKILL.md exists"
                fi
            done < <(jq -r '.skills[]' "$PLUGIN_JSON" 2>/dev/null)
        fi

        # Validate agents is an array of string paths
        agents_valid=$(jq -e '.agents | type == "array" and all(.[]; type == "string")' "$PLUGIN_JSON" 2>/dev/null) || agents_valid="false"
        if [ "$agents_valid" != "true" ]; then
            echo "ERROR: plugin.json.agents must be an array of string paths"
            errors=$((errors + 1))
        else
            agent_count=$(jq -r '.agents | length' "$PLUGIN_JSON")
            echo "OK: plugin.json.agents is an array of strings ($agent_count entries)"

            # Check each agent file exists
            while IFS= read -r agent_path; do
                if ! validate_path_safe "$agent_path" "agents[]"; then
                    errors=$((errors + 1))
                    continue
                fi
                full_path="$PLUGIN_DIR/$agent_path"
                if [ ! -f "$full_path" ]; then
                    echo "ERROR: agent file not found: $agent_path"
                    errors=$((errors + 1))
                else
                    echo "OK: $agent_path exists"
                fi
            done < <(jq -r '.agents[]' "$PLUGIN_JSON" 2>/dev/null)
        fi

        # Validate hooks (optional in plugin.json; auto-discovered from hooks.json)
        if jq -e '.hooks' "$PLUGIN_JSON" >/dev/null 2>&1; then
            hooks_type=$(jq -r '.hooks | type' "$PLUGIN_JSON" 2>/dev/null)
            if [ "$hooks_type" != "string" ]; then
                echo "ERROR: plugin.json.hooks must be a string path (got: $hooks_type)"
                errors=$((errors + 1))
            else
                hooks_path=$(jq -r '.hooks' "$PLUGIN_JSON")
                if ! validate_path_safe "$hooks_path" "hooks"; then
                    errors=$((errors + 1))
                else
                    full_path="$PLUGIN_DIR/$hooks_path"
                    if [ ! -f "$full_path" ]; then
                        echo "ERROR: hooks file not found: $hooks_path"
                        errors=$((errors + 1))
                    else
                        echo "OK: $hooks_path exists"
                    fi
                fi
            fi
        else
            echo "OK: hooks omitted (auto-discovered from hooks.json)"
        fi

        # Validate mcpServers (optional in plugin.json; auto-discovered from .mcp.json)
        if jq -e '.mcpServers' "$PLUGIN_JSON" >/dev/null 2>&1; then
            mcp_type=$(jq -r '.mcpServers | type' "$PLUGIN_JSON" 2>/dev/null)
            if [ "$mcp_type" != "string" ]; then
                echo "ERROR: plugin.json.mcpServers must be a string path (got: $mcp_type)"
                errors=$((errors + 1))
            else
                mcp_path=$(jq -r '.mcpServers' "$PLUGIN_JSON")
                if ! validate_path_safe "$mcp_path" "mcpServers"; then
                    errors=$((errors + 1))
                else
                    full_path="$PLUGIN_DIR/$mcp_path"
                    if [ ! -f "$full_path" ]; then
                        echo "ERROR: mcpServers file not found: $mcp_path"
                        errors=$((errors + 1))
                    else
                        echo "OK: $mcp_path exists"
                    fi
                fi
            fi
        else
            echo "OK: mcpServers omitted (auto-discovered from .mcp.json)"
        fi

        # --- plugin.json enrichment fields (recommended for discoverability) ---

        echo ""
        echo "--- plugin.json enrichment fields ---"

        # author (object with name string)
        if jq -e '.author.name | type == "string" and length > 0' "$PLUGIN_JSON" >/dev/null 2>&1; then
            author_name=$(jq -r '.author.name' "$PLUGIN_JSON")
            echo "OK: plugin.json.author.name = \"$author_name\""
        else
            echo "WARN: plugin.json.author.name is missing or empty"
            warnings=$((warnings + 1))
        fi

        # homepage (string URL)
        if jq -e '.homepage | type == "string" and length > 0' "$PLUGIN_JSON" >/dev/null 2>&1; then
            echo "OK: plugin.json.homepage present"
        else
            echo "WARN: plugin.json.homepage is missing or empty"
            warnings=$((warnings + 1))
        fi

        # repository (string URL)
        if jq -e '.repository | type == "string" and length > 0' "$PLUGIN_JSON" >/dev/null 2>&1; then
            echo "OK: plugin.json.repository present"
        else
            echo "WARN: plugin.json.repository is missing or empty"
            warnings=$((warnings + 1))
        fi

        # license (string)
        if jq -e '.license | type == "string" and length > 0' "$PLUGIN_JSON" >/dev/null 2>&1; then
            license_val=$(jq -r '.license' "$PLUGIN_JSON")
            echo "OK: plugin.json.license = \"$license_val\""
        else
            echo "WARN: plugin.json.license is missing or empty"
            warnings=$((warnings + 1))
        fi

        # keywords (array of strings)
        if jq -e '.keywords | type == "array" and length > 0 and all(.[]; type == "string")' "$PLUGIN_JSON" >/dev/null 2>&1; then
            kw_count=$(jq '.keywords | length' "$PLUGIN_JSON")
            echo "OK: plugin.json.keywords has $kw_count entries"
        else
            echo "WARN: plugin.json.keywords is missing or not a non-empty array of strings"
            warnings=$((warnings + 1))
        fi
    fi
fi

echo ""

# --- hooks content validation ---

echo "--- hooks/MCP content ---"

# 1. Validate hooks.json has a "hooks" key
HOOKS_FILE="$PLUGIN_DIR/hooks.json"
if [ -f "$HOOKS_FILE" ]; then
    if ! jq -e '.hooks' "$HOOKS_FILE" >/dev/null 2>&1; then
        echo "ERROR: hooks.json missing 'hooks' key"
        errors=$((errors + 1))
    else
        echo "OK: hooks.json has 'hooks' key"
    fi
else
    echo "WARN: hooks.json not found (skipping content validation)"
    warnings=$((warnings + 1))
fi

# 2. Validate .mcp.json has "mcpServers" key
MCP_FILE="$PLUGIN_DIR/.mcp.json"
if [ -f "$MCP_FILE" ]; then
    if ! jq -e '.mcpServers' "$MCP_FILE" >/dev/null 2>&1; then
        echo "ERROR: .mcp.json missing 'mcpServers' key"
        errors=$((errors + 1))
    else
        echo "OK: .mcp.json has 'mcpServers' key"
    fi
else
    echo "WARN: .mcp.json not found (skipping content validation)"
    warnings=$((warnings + 1))
fi

# 3. Check all scripts/hooks/*.js exist and are valid
HOOKS_SCRIPT_DIR="$PLUGIN_DIR/scripts/hooks"
if ls "$HOOKS_SCRIPT_DIR"/*.js 1>/dev/null 2>&1; then
    for script in "$HOOKS_SCRIPT_DIR"/*.js; do
        if node -c "$script" 2>/dev/null; then
            echo "OK: $(basename "$script") has valid syntax"
        else
            echo "ERROR: $(basename "$script") has invalid syntax"
            errors=$((errors + 1))
        fi
    done
else
    echo "WARN: no scripts/hooks/*.js files found"
    warnings=$((warnings + 1))
fi

echo ""

# --- Codex plugin manifest (.codex-plugin/plugin.json) ---

echo "--- Codex plugin manifest ---"

CODEX_MANIFEST="$PLUGIN_DIR/.codex-plugin/plugin.json"
if [ ! -f "$CODEX_MANIFEST" ]; then
    echo "ERROR: .codex-plugin/plugin.json not found"
    errors=$((errors + 1))
else
    if ! jq empty "$CODEX_MANIFEST" 2>/dev/null; then
        echo "ERROR: .codex-plugin/plugin.json is not valid JSON"
        errors=$((errors + 1))
    else
        echo "OK: .codex-plugin/plugin.json is valid JSON"
        for field in name version description; do
            if ! jq -e ".$field | type == \"string\" and length > 0" "$CODEX_MANIFEST" >/dev/null 2>&1; then
                echo "ERROR: .codex-plugin/plugin.json.$field must be a non-empty string"
                errors=$((errors + 1))
            else
                value=$(jq -r ".$field" "$CODEX_MANIFEST")
                echo "OK: .codex-plugin/plugin.json.$field = \"$value\""
            fi
        done

        if jq -e '.author.name | type == "string" and length > 0' "$CODEX_MANIFEST" >/dev/null 2>&1; then
            echo "OK: .codex-plugin/plugin.json.author.name present"
        else
            echo "WARN: .codex-plugin/plugin.json.author.name is missing or empty"
            warnings=$((warnings + 1))
        fi

        if jq -e '.skills | type == "string" and length > 0' "$CODEX_MANIFEST" >/dev/null 2>&1; then
            CODEX_SKILLS_PATH=$(jq -r '.skills' "$CODEX_MANIFEST")
            if ! validate_path_safe "$CODEX_SKILLS_PATH" "codex.skills"; then
                errors=$((errors + 1))
            else
                CODEX_SKILLS_FULL="$PLUGIN_DIR/$CODEX_SKILLS_PATH"
                if [ ! -d "$CODEX_SKILLS_FULL" ]; then
                    echo "ERROR: Codex skills path does not exist: $CODEX_SKILLS_PATH"
                    errors=$((errors + 1))
                else
                    echo "OK: Codex skills path resolves: $CODEX_SKILLS_PATH"
                fi
            fi
        else
            echo "ERROR: .codex-plugin/plugin.json.skills must be a non-empty string path"
            errors=$((errors + 1))
        fi

        if jq -e '.hooks' "$CODEX_MANIFEST" >/dev/null 2>&1; then
            CODEX_HOOKS_TYPE=$(jq -r '.hooks | type' "$CODEX_MANIFEST" 2>/dev/null)
            if [ "$CODEX_HOOKS_TYPE" != "string" ]; then
                echo "ERROR: .codex-plugin/plugin.json.hooks must be a string path"
                errors=$((errors + 1))
            else
                CODEX_HOOKS_PATH=$(jq -r '.hooks' "$CODEX_MANIFEST")
                if ! validate_path_safe "$CODEX_HOOKS_PATH" "codex.hooks"; then
                    errors=$((errors + 1))
                elif [ ! -f "$PLUGIN_DIR/$CODEX_HOOKS_PATH" ]; then
                    echo "ERROR: Codex hooks path does not exist: $CODEX_HOOKS_PATH"
                    errors=$((errors + 1))
                else
                    echo "OK: Codex hooks path resolves: $CODEX_HOOKS_PATH"
                fi
            fi
        fi

        if jq -e '.mcpServers' "$CODEX_MANIFEST" >/dev/null 2>&1; then
            CODEX_MCP_TYPE=$(jq -r '.mcpServers | type' "$CODEX_MANIFEST" 2>/dev/null)
            if [ "$CODEX_MCP_TYPE" != "string" ]; then
                echo "ERROR: .codex-plugin/plugin.json.mcpServers must be a string path"
                errors=$((errors + 1))
            else
                CODEX_MCP_PATH=$(jq -r '.mcpServers' "$CODEX_MANIFEST")
                if ! validate_path_safe "$CODEX_MCP_PATH" "codex.mcpServers"; then
                    errors=$((errors + 1))
                elif [ ! -f "$PLUGIN_DIR/$CODEX_MCP_PATH" ]; then
                    echo "ERROR: Codex mcpServers path does not exist: $CODEX_MCP_PATH"
                    errors=$((errors + 1))
                else
                    echo "OK: Codex mcpServers path resolves: $CODEX_MCP_PATH"
                fi
            fi
        fi

        if jq -e '.interface.displayName | type == "string" and length > 0' "$CODEX_MANIFEST" >/dev/null 2>&1; then
            echo "OK: .codex-plugin/plugin.json.interface.displayName present"
        else
            echo "ERROR: .codex-plugin/plugin.json.interface.displayName must be a non-empty string"
            errors=$((errors + 1))
        fi

        if jq -e '.interface.capabilities | type == "array" and length > 0 and all(.[]; type == "string")' "$CODEX_MANIFEST" >/dev/null 2>&1; then
            echo "OK: .codex-plugin/plugin.json.interface.capabilities present"
        else
            echo "ERROR: .codex-plugin/plugin.json.interface.capabilities must be a non-empty array of strings"
            errors=$((errors + 1))
        fi

        if jq -e '.interface.defaultPrompt' "$CODEX_MANIFEST" >/dev/null 2>&1; then
            if jq -e '.interface.defaultPrompt | type == "array" and length <= 3 and all(.[]; type == "string")' "$CODEX_MANIFEST" >/dev/null 2>&1; then
                echo "OK: .codex-plugin/plugin.json.interface.defaultPrompt is well-formed"
            else
                echo "ERROR: .codex-plugin/plugin.json.interface.defaultPrompt must be an array of up to 3 strings"
                errors=$((errors + 1))
            fi
        fi

        if [ -f "$PLUGIN_JSON" ]; then
            for field in name version description homepage repository license; do
                CLAUDE_VALUE=$(jq -r ".$field // empty" "$PLUGIN_JSON" 2>/dev/null)
                CODEX_VALUE=$(jq -r ".$field // empty" "$CODEX_MANIFEST" 2>/dev/null)
                if [ -n "$CLAUDE_VALUE" ] && [ -n "$CODEX_VALUE" ] && [ "$CLAUDE_VALUE" != "$CODEX_VALUE" ]; then
                    echo "ERROR: Codex manifest $field \"$CODEX_VALUE\" does not match Claude manifest \"$CLAUDE_VALUE\""
                    errors=$((errors + 1))
                fi
            done
        fi
    fi
fi

# --- Codex skill-installer metadata (legacy compatibility) ---

echo "--- Codex legacy metadata ---"

ROOT_OPENAI="$PLUGIN_DIR/.agents/openai.yaml"
if [ ! -f "$ROOT_OPENAI" ]; then
    echo "OK: .agents/openai.yaml not present; plugin discovery uses .codex-plugin/plugin.json"
elif [ -f "$PLUGIN_JSON" ] && jq -e '.skills | type == "array"' "$PLUGIN_JSON" >/dev/null 2>&1; then
    echo "OK: legacy .agents/openai.yaml exists"
    while IFS= read -r skill_path; do
        if ! validate_path_safe "$skill_path" "skills[]"; then
            errors=$((errors + 1))
            continue
        fi
        full_skill_path="$PLUGIN_DIR/$skill_path"
        skill_openai="$full_skill_path/agents/openai.yaml"
        if [ ! -f "$skill_openai" ]; then
            echo "ERROR: missing legacy per-skill Codex metadata: ${skill_path}/agents/openai.yaml"
            errors=$((errors + 1))
        else
            echo "OK: ${skill_path}/agents/openai.yaml exists"
        fi
    done < <(jq -r '.skills[]' "$PLUGIN_JSON" 2>/dev/null)
else
    echo "WARN: .agents/openai.yaml exists but plugin.json.skills could not be evaluated"
    warnings=$((warnings + 1))
fi

echo ""

# --- root marketplace.json validation (delegated to shared script) ---

echo "--- root marketplace.json ---"

ROOT_MARKETPLACE_SCRIPT="$REPO_ROOT/scripts/validate-root-marketplace.sh"
if [ -x "$ROOT_MARKETPLACE_SCRIPT" ]; then
    # Delegate to shared validation script; capture its exit code
    if ! "$ROOT_MARKETPLACE_SCRIPT"; then
        echo "ERROR: root marketplace.json validation failed (via validate-root-marketplace.sh)"
        errors=$((errors + 1))
    fi
else
    echo "ERROR: validate-root-marketplace.sh not found or not executable at $ROOT_MARKETPLACE_SCRIPT"
    errors=$((errors + 1))
fi

echo ""
echo "=== Summary ==="
echo "Errors: $errors"
echo "Warnings: $warnings"

if [ "$errors" -gt 0 ]; then
    echo ""
    echo "FAILED: $errors error(s) found"
    exit 1
fi

echo ""
echo "PASSED"
exit 0
