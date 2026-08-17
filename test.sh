#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
RUNNER="$REPO_ROOT/tests/agent-routing/check-skills.cs"
CASES="$REPO_ROOT/tests/agent-routing/cases.json"
CODEX_SKILLS_DIR="${CODEX_HOME:-$HOME/.codex}/skills"
PLUGIN_ROOT="$REPO_ROOT/plugins/dotnet-artisan"
PLUGIN_SKILLS_DIR="$PLUGIN_ROOT/skills"
APPS_DIR="$REPO_ROOT/apps"
PUBLIC_PLUGIN_SOURCE="novotnyllc/dotnet-artisan"
CODEX_RESTORE_STAGING=""
CODEX_SKILLS_MANAGED=0

log() {
    echo "[test.sh] $*"
}

have_cmd() {
    command -v "$1" >/dev/null 2>&1
}

contains_agent() {
    local needle="$1"
    local haystack="$2"
    [[ ",${haystack}," == *",${needle},"* ]]
}

SAMPLES_DIR="$REPO_ROOT/samples"

cleanup() {
    safe_remove_generated_dir "$APPS_DIR" "apps"
    safe_remove_generated_dir "$SAMPLES_DIR" "samples"
}

restore_claude_public_marketplace() {
    if ! have_cmd claude; then
        log "WARNING: claude CLI not found; skipping Claude marketplace restore."
        return 0
    fi

    log "Restoring Claude plugin marketplace to public source ($PUBLIC_PLUGIN_SOURCE)."
    claude plugin disable 'dotnet-artisan@dotnet-artisan' -s local >/dev/null 2>&1 || true
    claude plugin marketplace remove dotnet-artisan >/dev/null 2>&1 || true
    claude plugin marketplace add "$PUBLIC_PLUGIN_SOURCE" >/dev/null
    claude plugin install dotnet-artisan@dotnet-artisan -s user >/dev/null 2>&1 || \
        claude plugin install dotnet-artisan -s user >/dev/null 2>&1 || \
        claude plugin update dotnet-artisan >/dev/null 2>&1 || true

    local marketplace_output
    marketplace_output="$(claude plugin marketplace list 2>/dev/null || true)"

    if echo "$marketplace_output" | grep -F "dotnet-artisan" | grep -F "Directory (" >/dev/null; then
        log "ERROR: Claude marketplace dotnet-artisan is still local after restore."
        return 1
    fi
}

restore_copilot_public_marketplace() {
    if ! have_cmd copilot; then
        log "WARNING: copilot CLI not found; skipping Copilot marketplace restore."
        return 0
    fi

    log "Restoring Copilot plugin marketplace to public source ($PUBLIC_PLUGIN_SOURCE)."
    copilot plugin marketplace remove -f dotnet-artisan >/dev/null 2>&1 || true
    copilot plugin marketplace add "$PUBLIC_PLUGIN_SOURCE" >/dev/null
    copilot plugin install dotnet-artisan@dotnet-artisan >/dev/null 2>&1 || \
        copilot plugin update dotnet-artisan@dotnet-artisan >/dev/null 2>&1 || true

    local marketplace_output
    marketplace_output="$(copilot plugin marketplace list 2>/dev/null || true)"

    if echo "$marketplace_output" | grep -F "dotnet-artisan (Local:" >/dev/null; then
        log "ERROR: Copilot marketplace dotnet-artisan is still local after restore."
        return 1
    fi
}

restore_public_marketplaces() {
    local agents_csv="$1"
    local restore_exit=0

    if contains_agent "claude" "$agents_csv"; then
        restore_claude_public_marketplace || restore_exit=1
    fi

    if contains_agent "copilot" "$agents_csv"; then
        restore_copilot_public_marketplace || restore_exit=1
    fi

    if contains_agent "codex" "$agents_csv"; then
        restore_codex_skills "$FORCE_PURGE_CODEX" || restore_exit=1
    fi

    return "$restore_exit"
}

safe_remove_generated_dir() {
    local target_dir="$1"
    local label="$2"

    if [[ -z "${target_dir:-}" || -z "${REPO_ROOT:-}" ]]; then
        log "WARNING: target directory or REPO_ROOT unset; skipping cleanup for $label."
        return
    fi

    local resolved_repo resolved_target
    resolved_repo="$(cd "$REPO_ROOT" 2>/dev/null && pwd -P)" || resolved_repo=""

    if [[ -z "$resolved_repo" ]]; then
        log "WARNING: Unable to resolve REPO_ROOT; skipping cleanup for $label."
        return
    fi

    if [[ ! -d "$target_dir" ]]; then
        return
    fi

    resolved_target="$(cd "$target_dir" 2>/dev/null && pwd -P)" || resolved_target=""
    if [[ -z "$resolved_target" ]]; then
        log "WARNING: Unable to resolve target directory ($target_dir); skipping cleanup for $label."
        return
    fi

    case "$resolved_target" in
        "$resolved_repo"/*)
            log "Cleaning generated $label directory: $resolved_target"
            rm -rf -- "$resolved_target"
            ;;
        *)
            log "WARNING: Refusing to clean $label outside repo: $resolved_target"
            ;;
    esac
}

prepare_claude_plugin() {
    if ! have_cmd claude; then
        log "WARNING: claude CLI not found; skipping Claude plugin source setup."
        return
    fi

    log "Preparing Claude plugin source (local repo)."
    claude plugin disable 'dotnet-artisan@dotnet-artisan' -s user >/dev/null 2>&1 || true
    claude plugin marketplace remove dotnet-artisan >/dev/null 2>&1 || true
    claude plugin marketplace add "$REPO_ROOT" >/dev/null
    claude plugin install dotnet-artisan -s local >/dev/null 2>&1 || \
        claude plugin update dotnet-artisan >/dev/null 2>&1 || true

    if ! claude plugin marketplace list | grep -F "Source: Directory ($REPO_ROOT)" >/dev/null; then
        log "ERROR: Claude marketplace dotnet-artisan is not pointing at $REPO_ROOT"
        return 1
    fi
}

prepare_copilot_plugin() {
    if ! have_cmd copilot; then
        log "WARNING: copilot CLI not found; skipping Copilot plugin source setup."
        return
    fi

    log "Preparing Copilot plugin source (local repo)."
    if ! copilot plugin marketplace list | grep -F "dotnet-artisan (Local: $REPO_ROOT)" >/dev/null 2>&1; then
        copilot plugin marketplace remove -f dotnet-artisan >/dev/null 2>&1 || true
        copilot plugin marketplace add "$REPO_ROOT" >/dev/null
    fi

    copilot plugin install dotnet-artisan@dotnet-artisan >/dev/null 2>&1 || \
        copilot plugin update dotnet-artisan@dotnet-artisan >/dev/null 2>&1 || true

    if ! copilot plugin marketplace list | grep -F "dotnet-artisan (Local: $REPO_ROOT)" >/dev/null; then
        log "ERROR: Copilot marketplace dotnet-artisan is not pointing at $REPO_ROOT"
        return 1
    fi
}

prepare_codex_skills() {
    if ! have_cmd codex; then
        log "WARNING: codex CLI not found; skipping Codex skill sync."
        return
    fi

    if [[ ! -d "$PLUGIN_SKILLS_DIR" ]]; then
        log "ERROR: skills directory not found at $PLUGIN_SKILLS_DIR"
        return 1
    fi

    if ! have_cmd rsync; then
        log "ERROR: rsync is required to sync Codex skills."
        return 1
    fi

    local -a skill_dirs=()
    while IFS= read -r skill_dir; do
        [[ -f "$skill_dir/SKILL.md" ]] || continue
        skill_dirs+=("$skill_dir")
    done < <(find "$PLUGIN_SKILLS_DIR" -mindepth 1 -maxdepth 1 -type d | sort)

    local total_skills="${#skill_dirs[@]}"
    if (( total_skills == 0 )); then
        log "ERROR: No skill directories found under $PLUGIN_SKILLS_DIR"
        return 1
    fi

    log "Syncing $total_skills repo skills into Codex skill home: $CODEX_SKILLS_DIR"
    mkdir -p "$CODEX_SKILLS_DIR"

    CODEX_RESTORE_STAGING="$(mktemp -d "${TMPDIR:-/tmp}/dotnet-artisan-codex-restore.XXXXXX")"
    mkdir -p "$CODEX_RESTORE_STAGING/original"
    : > "$CODEX_RESTORE_STAGING/skills.list"
    CODEX_SKILLS_MANAGED=1

    for skill_dir in "${skill_dirs[@]}"; do
        skill_name="$(basename "$skill_dir")"
        skill_dest="$CODEX_SKILLS_DIR/$skill_name"
        echo "$skill_name" >> "$CODEX_RESTORE_STAGING/skills.list"

        if [[ -d "$skill_dest" ]]; then
            mkdir -p "$CODEX_RESTORE_STAGING/original/$skill_name"
            rsync -a "$skill_dest"/ "$CODEX_RESTORE_STAGING/original/$skill_name"/
        fi
    done

    local sync_started_at
    sync_started_at="$(date +%s)"

    local synced_count=0
    for skill_dir in "${skill_dirs[@]}"; do
        synced_count=$((synced_count + 1))
        skill_name="$(basename "$skill_dir")"
        skill_dest="$CODEX_SKILLS_DIR/$skill_name"
        mkdir -p "$skill_dest"
        rsync -a --delete "$skill_dir"/ "$skill_dest"/

        if (( synced_count % 25 == 0 || synced_count == total_skills )); then
            log "Codex skill sync progress: $synced_count/$total_skills"
        fi
    done

    local repo_sha
    repo_sha="$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
    printf '%s\n' "$REPO_ROOT@$repo_sha" > "$CODEX_SKILLS_DIR/.dotnet-artisan-source"

    local sync_finished_at
    sync_finished_at="$(date +%s)"
    log "Codex skill sync finished in $((sync_finished_at - sync_started_at))s."
}

restore_codex_skills() {
    local skill_name
    local skill_dest
    local force_purge="${1:-0}"

    if [[ ! -d "$CODEX_SKILLS_DIR" ]]; then
        return 0
    fi

    if [[ "$CODEX_SKILLS_MANAGED" == "1" && -n "$CODEX_RESTORE_STAGING" && -f "$CODEX_RESTORE_STAGING/skills.list" ]]; then
        log "Restoring Codex skills to pre-test state."

        while IFS= read -r skill_name; do
            [[ -n "$skill_name" ]] || continue
            skill_dest="$CODEX_SKILLS_DIR/$skill_name"
            rm -rf -- "$skill_dest"

            if [[ -d "$CODEX_RESTORE_STAGING/original/$skill_name" ]]; then
                mkdir -p "$skill_dest"
                rsync -a "$CODEX_RESTORE_STAGING/original/$skill_name"/ "$skill_dest"/
            fi
        done < "$CODEX_RESTORE_STAGING/skills.list"

        rm -f "$CODEX_SKILLS_DIR/.dotnet-artisan-source"
        rm -rf -- "$CODEX_RESTORE_STAGING"
        CODEX_RESTORE_STAGING=""
        CODEX_SKILLS_MANAGED=0
        return 0
    fi

    if [[ "$force_purge" == "1" ]]; then
        log "Force-purging local dotnet-artisan Codex skills (no snapshot required)."

        while IFS= read -r skill_dir; do
            [[ -d "$skill_dir" ]] || continue
            skill_name="$(basename "$skill_dir")"
            rm -rf -- "$CODEX_SKILLS_DIR/$skill_name"
        done < <(find "$PLUGIN_SKILLS_DIR" -mindepth 1 -maxdepth 1 -type d | sort)

        rm -f "$CODEX_SKILLS_DIR/.dotnet-artisan-source"
        return 0
    fi

    # Best-effort cleanup path for restore-only mode (no pre-run snapshot):
    # if the marker points at this repo, remove synced repo skills so Codex
    # stops resolving against this local checkout.
    if [[ -f "$CODEX_SKILLS_DIR/.dotnet-artisan-source" ]] && grep -Fq "$REPO_ROOT@" "$CODEX_SKILLS_DIR/.dotnet-artisan-source"; then
        log "Removing local dotnet-artisan Codex skill sync."

        while IFS= read -r skill_dir; do
            [[ -d "$skill_dir" ]] || continue
            skill_name="$(basename "$skill_dir")"
            rm -rf -- "$CODEX_SKILLS_DIR/$skill_name"
        done < <(find "$PLUGIN_SKILLS_DIR" -mindepth 1 -maxdepth 1 -type d | sort)

        rm -f "$CODEX_SKILLS_DIR/.dotnet-artisan-source"
    fi
}

prepare_agent_sources() {
    local agents_csv="$1"
    local do_setup="${2:-1}"
    if [[ "$do_setup" != "1" ]]; then
        log "Skipping local source setup (--skip-source-setup)."
        return
    fi

    if contains_agent "claude" "$agents_csv"; then
        prepare_claude_plugin
    fi
    if contains_agent "copilot" "$agents_csv"; then
        prepare_copilot_plugin
    fi
    if contains_agent "codex" "$agents_csv"; then
        prepare_codex_skills
    fi
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'EOF'
Usage:
  ./test.sh [options] [runner args...]

Examples:
  ./test.sh
  ./test.sh --agents codex --category api
  ./test.sh --skip-source-setup --agents claude --case-id advisor-routing-maintainable-app
  ./test.sh --agents claude --max-parallel 4

Wrapper options:
  --skip-source-setup   Do not repoint/sync local plugin and skill sources before run
  --restore-public-marketplaces
                        Restore Claude/Copilot plugin marketplaces to public
                        sources and restore Codex skill sync, then exit
  --purge-codex-skills  With --restore-public-marketplaces, force-remove all
                        dotnet-artisan Codex skill dirs even without snapshot

Runner options (passed through to check-skills.cs):
  --agents <csv>            Agents filter (default: claude,codex,copilot)
  --category <csv>          Category filter
  --case-id <csv>           Case-id filter
  --timeout-seconds <int>   Global per-invocation timeout (default: 300)
  --provider-model <p:m>    Per-provider model (e.g. copilot:gpt-4.1, claude:sonnet)
  --provider-timeout <p:s>  Per-provider timeout in seconds (e.g. copilot:300)
  --sample <N>              Randomly sample N cases after filtering
  --max-parallel <int>      Max concurrent runs (default: 4; env MAX_CONCURRENCY fallback)
  --artifacts-root <path>   Base directory for per-batch artifact isolation
                            (default: tests/agent-routing/artifacts)
  --enable-log-scan         Enable log file scanning (default: on serial, off parallel)
  --disable-log-scan        Disable log file scanning
  --allow-log-fallback-pass Allow log fallback to promote pass when parallel
  --log-max-files <int>     Max log files to scan per agent (default: 60)
  --log-max-bytes <int>     Max bytes to read per log file (default: 300000)
  --no-progress             Disable stderr lifecycle progress output
  --self-test               Run ComputeTier self-test fixtures and exit
  --output <path>           Optional additional JSON output path (backward compat)
  --proof-log <path>        Optional additional proof log path (backward compat)
  --fail-on-infra           Exit non-zero when infra_error exists
  --help                    Show this help

Environment:
  MAX_CONCURRENCY           Fallback for --max-parallel (flag takes precedence)

Artifacts:
  Results and proof logs are always written to <artifacts-root>/<batch_run_id>/.
  ARTIFACT_DIR=<path> is emitted on stderr (parseable via: grep '^ARTIFACT_DIR=' stderr.log).
EOF
    exit 0
fi

RUNNER_ARGS=()
SELECTED_AGENTS="claude,codex,copilot"
DO_SOURCE_SETUP=1
RESTORE_PUBLIC_ONLY=0
FORCE_PURGE_CODEX=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-source-setup)
            DO_SOURCE_SETUP=0
            shift
            ;;
        --restore-public-marketplaces)
            RESTORE_PUBLIC_ONLY=1
            shift
            ;;
        --purge-codex-skills)
            FORCE_PURGE_CODEX=1
            shift
            ;;
        --agents)
            if [[ $# -lt 2 ]]; then
                echo "ERROR: Missing value for --agents"
                exit 1
            fi
            SELECTED_AGENTS="$2"
            RUNNER_ARGS+=("$1" "$2")
            shift 2
            ;;
        *)
            RUNNER_ARGS+=("$1")
            shift
            ;;
    esac
done

if [[ "$FORCE_PURGE_CODEX" == "1" && "$RESTORE_PUBLIC_ONLY" != "1" ]]; then
    echo "ERROR: --purge-codex-skills requires --restore-public-marketplaces"
    exit 1
fi

if [[ "$RESTORE_PUBLIC_ONLY" == "1" ]]; then
    restore_public_marketplaces "$SELECTED_AGENTS"
    exit $?
fi

if [[ ! -f "$RUNNER" ]]; then
    echo "ERROR: Runner not found: $RUNNER"
    exit 1
fi

RESTORE_ON_EXIT=0
if [[ "$DO_SOURCE_SETUP" == "1" ]] && (contains_agent "claude" "$SELECTED_AGENTS" || contains_agent "copilot" "$SELECTED_AGENTS" || contains_agent "codex" "$SELECTED_AGENTS"); then
    RESTORE_ON_EXIT=1
fi

on_exit() {
    local exit_code=$?
    trap - EXIT INT TERM

    cleanup

    if [[ "$RESTORE_ON_EXIT" == "1" ]]; then
        restore_public_marketplaces "$SELECTED_AGENTS" || {
            if [[ "$exit_code" -eq 0 ]]; then
                exit_code=1
            fi
        }
    fi

    exit "$exit_code"
}

trap on_exit EXIT INT TERM
prepare_agent_sources "$SELECTED_AGENTS" "$DO_SOURCE_SETUP"
cleanup

set +e
dotnet run --file "$RUNNER" -- \
    --input "$CASES" \
    --run-all \
    "${RUNNER_ARGS[@]}" \
    >/dev/null
run_exit=$?
set -e

exit "$run_exit"
