# Agent Routing Tests

This document describes the routing test system used to verify that Claude, Codex, and Copilot discover and use expected skills. It covers telemetry, evidence evaluation, failure taxonomy, case schema, CI provider matrix, and operator workflows.

## Files

- `tests/agent-routing/cases.json`: broad case corpus (same prompts across Claude/Codex/Copilot)
- `tests/agent-routing/check-skills.cs`: single .NET file-based runner
- `tests/agent-routing/provider-baseline.json`: per-case per-provider expected status for CI regression gating (optional; when absent, an all-pass baseline is synthesized from results)
- `tests/copilot-smoke/cases.jsonl`: deterministic Copilot smoke test cases
- `tests/copilot-smoke/baseline.json`: expected outcomes for smoke tests (regression gate)
- `tests/copilot-smoke/run_smoke.py`: Copilot smoke test runner (supports `--require-copilot`)
- `test.sh`: single entrypoint script
- `.github/workflows/validate.yml`: PR-blocking deterministic validation (structural checks only)
- `.github/workflows/agent-live-routing.yml`: manual live checks with provider matrix

## Commands

- Live full-corpus checks:
  - `./test.sh`
  - Results and proof logs are written to `<artifacts-root>/<batch_run_id>/` (default root: `tests/agent-routing/artifacts/`). Parse `ARTIFACT_DIR=<path>` from stderr to locate the batch directory.

## Source Setup (Default)

`test.sh` now prepares agent sources before running checks, so tests target this repo version:

- Claude: disables user-scope `dotnet-artisan`, points marketplace `dotnet-artisan` to this repo path, installs local scope plugin.
- Copilot: repoints marketplace `dotnet-artisan` to this repo path and reinstalls/updates `dotnet-artisan@dotnet-artisan`.
- Codex: syncs `plugins/dotnet-artisan/skills/*/` from this repo into `~/.codex/skills/<skill-name>` for direct-skill test runs. Structural smoke checks validate `plugins/dotnet-artisan/.codex-plugin/plugin.json`.
- Cleanup: removes `apps/` before and after each run to avoid persisted generated app scaffolds.
- Restore: after each run, Claude/Copilot marketplaces are restored to the public plugin source (`novotnyllc/dotnet-artisan`) and Codex skills are restored to pre-test state.

Use `--skip-source-setup` only for debugging:

- `./test.sh --skip-source-setup --agents claude --case-id advisor-routing-maintainable-app`
- `./test.sh --restore-public-marketplaces` restores Claude/Copilot marketplaces to public source and restores/removes Codex local sync state, then exits without running tests.
- `./test.sh --restore-public-marketplaces --agents codex --purge-codex-skills` force-removes all dotnet-artisan Codex skill dirs even if no snapshot/marker exists.

## Optional Filters

Pass extra runner args through `test.sh`.

Examples:

- One agent:
  - `./test.sh --agents codex`
- Specific categories:
  - `./test.sh --category api,testing`
- Fail on infra errors:
  - `./test.sh --fail-on-infra`
- Single case with extended timeout:
  - `./test.sh --case-id uno-mcp-routing-skill-id-only --timeout-seconds 180 --output /tmp/uno-routing.json`
  - Expected outcomes are defined in `provider-baseline.json`; check the baseline for the current expected status per provider.

## Run IDs and Telemetry

Every invocation of the runner generates stable identifiers for cross-referencing results with lifecycle output.

**Batch run ID:** A UUID (`batch_run_id`) generated once per `RunAsync()` call. Appears in the `ResultEnvelope` JSON, in all stderr lifecycle lines, and as the artifact subdirectory name (`<artifacts-root>/<batch_run_id>/`).

**Unit run ID:** A UUID (`unit_run_id`) generated per work item (one case x one agent). Appears in each `AgentResult` JSON entry and in all stderr lifecycle lines for that unit.

**Lifecycle transitions:** When progress is enabled (default), the runner emits lifecycle state changes to stderr per unit:

```
[check-skills] HH:mm:ss [batch:{batch_run_id}] [unit:{unit_run_id}] {agent}:{case_id} -> {state}
```

States: `queued`, `running`, `completed`, `failed`, `timeout`. The `running` state includes an ordinal counter (`[N/total]`). The `completed`/`failed`/`timeout` states include cumulative summary counters (`summary(pass=N, fail=N, infra=N)`).

**`ARTIFACT_DIR` protocol output:** Emitted once per run on stderr as a raw line: `ARTIFACT_DIR=<absolute-path>`. No prefix, no timestamp, no brackets. Emitted immediately after the batch directory is created, before any work items start. Not suppressed by `--no-progress` (it is protocol output, not lifecycle output). CI parses it with:

```bash
grep '^ARTIFACT_DIR=' stderr.log | cut -d= -f2-
```

**Artifact directory contents:** Both `results.json` and `tool-use-proof.log` are unconditionally written to `<artifacts-root>/<batch_run_id>/`. The `--output` and `--proof-log` flags write additional copies at the specified paths (backward compatibility) but the batch directory copy is the single source of truth.

`--no-progress` suppresses lifecycle transition lines only (queued/running/completed/failed/timeout). Protocol lines (`ARTIFACT_DIR`) are always emitted.

## Runner Behavior

- Expands each case across selected agents.
- Copilot skill-load evidence is now consistent with other providers after the flat layout migration; the harness uses provider-aware Tier 1 signals and CI baselines define expected outcomes per case/provider.
- Executes agent command templates with timeout.
- Evaluates evidence from stdout/stderr for tool usage + skill-file reads.
- Falls back to recent logs from agent home dirs when log scanning is enabled (see Log Fallback Policy below).
- Emits JSON with statuses: `pass`, `fail`, `infra_error`.
- Includes `batch_run_id` (UUID) on the result envelope and `unit_run_id` (UUID) per result.
- Includes `timed_out` per result so partial-output passes are visible.
- Includes `failure_kind` and `failure_category` for non-pass results (see Failure Categories below).
- Includes `tool_use_proof_lines` per result and writes a plain-text proof log file.

Evidence currently gates on:

- `required_all_evidence`: all tokens must appear. Evidence tokens differ by agent type:
  - **Claude**: Uses definitive Skill-tool invocation tokens (`"Launching skill: <skill-id>"` or `{"skill":"<skill-id>"}`). SKILL.md file-read evidence is excluded because Claude does not reliably emit file-read traces. The runner extracts launched skill IDs from structured JSON output and `Launching skill:` log lines.
  - **Non-Claude (Codex, Copilot)**: Uses skill-specific file paths (`"<skill-id>/SKILL.md"`) instead of the generic `"SKILL.md"` token. This prevents false-positive matches from incidental SKILL.md mentions in unrelated output. When `expected_skill` is set, only the skill-specific path is required. The generic `"SKILL.md"` token is used only as a fallback when no `expected_skill` is configured.
- `required_any_evidence`: at least one activity token must appear. Defaults also include Copilot log activity markers (`function_call`, MCP startup/config lines).
- `require_skill_file` (optional, default `true`): when `false`, only skill-id loading is required (useful for dedicated cross-agent routing assertions).

Proof log options:

- `--proof-log <path>`: write a plain-text log containing matched tool-use evidence lines.

## Evidence Tiers

`ComputeTier(agent, token, line, score)` is the single source of truth for evidence tier assignment. The function is pure and deterministic with no side effects or ambient state.

### Tier 1 (definitive skill invocation)

Provider-specific regex patterns with named capture groups and explicit token attribution:

- **Claude primary** (score 1000): Regex `"name"\s*:\s*"Skill"` on lines also containing `"skill"\s*:"(?<skill>[^"]+)"`. Token attribution: case-insensitive substring match of `token` in the `<skill>` capture group. This is the strongest signal -- direct skill identifier from tool_use JSON.
- **Claude secondary** (score 900): Regex `Launching skill:\s*(?<skill>\S+)`. Token attribution: case-insensitive substring match of `token` in the `<skill>` capture group. No heuristic "nearby context" parsing.
- **Codex/Copilot**: Regex `Base directory for this skill:\s*(?<path>.+)`. Token attribution: normalize `<path>` separators to `/`, then require `"/" + token.ToLowerInvariant() + "/"` present in `path.ToLowerInvariant()`. End-of-path without trailing slash also matches via `"/" + token.ToLowerInvariant()` at string end. If path does not contain the token, it is NOT Tier 1 for that token.

### Tier 2 (moderate confidence)

Score 60-800, or Tier 1 regex match that fails token attribution. Generic file reads (e.g. `dotnet-xunit/SKILL.md`) remain Tier 2 for all providers. Path tokens (containing `/`) skip Tier 1 base-directory regex.

### Tier 3 (low confidence)

Score < 60. Weak mentions without structural evidence.

### Tier gating for requirements

- `required_skills[]` (explicit) and `expected_skill` (implicit): Tier 1 gated. Use `expected_skill_min_tier: 2` to opt out.
- `required_files[]`: Tier 2 gated.
- Legacy `required_all_evidence`: Tier 2 by default; tokens that are also required skills (e.g. coincide with `expected_skill` or `required_skills`) are Tier-gated accordingly.
- Log fallback evidence is capped at Tier 2 (cannot satisfy Tier 1 requirements).

### Per-token evidence model

`EvidenceEvaluation` carries `Dictionary<string, EvidenceHit>` (TokenHits) where each `EvidenceHit` includes `BestScore`, `Tier`, `SourceKind`, `SourceDetail`, and `ProofLine`. During evaluation, the runner scans all output lines and selects the best hit per token. Tie-breaker ordering: lower tier number (stronger) > higher score > `cli_output` over `log_fallback` > stable ordering.

### Self-test

Run `--self-test` to verify ComputeTier against built-in fixtures covering at least:

- Claude primary Tier 1 via `"skill":"..."` field in tool_use JSON
- Claude secondary Tier 1 via `Launching skill:` prefix
- Claude Tier 2 fallback (Tier 1 regex without token attribution)
- Codex Tier 1 hit (path contains `/<token>/`)
- Codex Tier 1 miss becoming Tier 2 (path lacks token)
- Codex Tier 1 with backslash path normalization
- Tier 3 low score

```bash
dotnet run --file tests/agent-routing/check-skills.cs -- --self-test
```

## Log Fallback Policy

When CLI output does not contain sufficient evidence, the runner can fall back to scanning recent log files from agent home directories.

**Log scan enable/disable:**
- Default: on when serial (`--max-parallel 1`), off when parallel (`--max-parallel > 1`).
- Override: `--enable-log-scan` forces scanning on; `--disable-log-scan` forces it off.

**Log snapshot:** Captured once per agent per batch (before any work items start). Only files modified since the snapshot are considered, preventing stale log data from producing false positives.

**Tier cap:** Log fallback evidence is capped at Tier 2. A log-sourced hit can never satisfy a Tier 1 requirement regardless of its raw score or regex match. The cap is applied during evaluation (before the pass/fail decision), not post-hoc.

**Diagnostics-only mode (parallel):** When `--max-parallel > 1` and `--allow-log-fallback-pass` is not set, log fallback evidence is diagnostics-only. It appears in `TokenHits` and proof lines for debugging but does not promote a CLI-failing result to pass. The runner preserves the CLI evidence source's `MissingAll`/`MissingAny` for accurate failure classification and merges only observability data (proof lines, TokenHits, matched log file) from the log source.

**`--allow-log-fallback-pass`:** Explicitly allows log fallback to promote results to pass even when parallel. Auto-enabled when running serial (max_parallel = 1). Default: false.

**Log file selection:** Files with extensions `.json`, `.jsonl`, `.log`, `.txt`, `.md`, or no extension. Up to `--log-max-files` (default: 60) most recently modified files, each capped at `--log-max-bytes` (default: 300,000 bytes) from the tail.

## Case Schema

Each entry in `cases.json` defines a routing test case. The full schema:

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `case_id` | string | required | Unique identifier for the test case |
| `category` | string | required | Category for filtering (`--category`) |
| `prompt` | string | required | Prompt sent to the agent |
| `expected_skill` | string | `""` | Primary skill expected to be invoked. Implicitly Tier 1 gated (added to `required_skills`) unless `expected_skill_min_tier` is set to 2 |
| `expected_skill_min_tier` | int? | `null` (= 1) | Opt-out from implicit Tier 1 for `expected_skill`. Set to `2` to accept Tier 2 evidence |
| `required_all_evidence` | string[] | `[]` | Legacy: all tokens must appear (Tier 2 default; tokens coinciding with `expected_skill`/`required_skills` are Tier-gated accordingly) |
| `required_any_evidence` | string[] | `[]` | At least one token must appear |
| `required_evidence` | string[] | `[]` | Legacy alias |
| `require_skill_file` | bool | `true` | When `false`, only skill-id loading is required |
| `required_skills` | string[] | `[]` | Tier 1 gated skill tokens. Require definitive skill invocation evidence |
| `required_files` | string[] | `[]` | Tier 2 gated file tokens. Require file-read or path evidence |
| `optional_skills` | string[] | `[]` | Tracked in `optional_hits` for observability but excluded from pass/fail gating |
| `disallowed_skills` | string[] | `[]` | If detected with evidence strength Tier N or stronger (tier number <= `disallowed_min_tier`), the result becomes `disallowed_hit`. Tier 3 matches are diagnostics only when default min_tier=2 |
| `disallowed_min_tier` | int | `2` | Maximum tier (weakest) that causes disallowed failure. `1` = only definitive invocation fails; `2` = moderate confidence fails; `3` = all mentions fail |
| `provider_aliases` | object? | `null` | Per-agent alias maps: `{ "agent": { "alias": "canonical" } }`. Resolved before evidence matching to normalize provider-specific skill names |

### Typed evidence requirements

The runner supports three tiers of evidence requirements:

- **`required_skills[]`** (Tier 1): Tokens that must have definitive skill invocation evidence (tool_use JSON, Launching skill prefix, or Base directory path containing the token).
- **`required_files[]`** (Tier 2): Tokens that must have at least moderate-confidence file-read evidence.
- **`expected_skill`** (implicit Tier 1): Automatically added to `required_skills` unless `expected_skill_min_tier: 2` opts out. This ensures existing cases enforce actual skill invocation without bulk-editing `cases.json`.
- **Legacy `required_all_evidence`**: Preserved for backward compatibility. Tokens default to Tier 2 gating; tokens that coincide with `expected_skill` or `required_skills` are Tier-gated accordingly.

### Provider aliases

The `provider_aliases` field maps agent-specific token names to canonical names:

```json
{
  "provider_aliases": {
    "copilot": {
      "dotnet-alt-name": "dotnet-canonical-name"
    }
  }
}
```

Aliases are resolved before evidence matching, tier computation, and optional/disallowed evaluation.

## Failure Categories

Two orthogonal classification fields exist on non-pass results.

### `failure_kind` (routing mismatch type)

| Kind | Description |
|------|-------------|
| `weak_evidence_only` | All evidence hits are Tier 3 (very low confidence). Checked first |
| `evidence_too_weak` | Token found but at weaker tier than required (e.g. Tier 2 when Tier 1 needed) |
| `missing_required` | A `required_skills` or `required_files` token was not found |
| `disallowed_hit` | A `disallowed_skills` token was detected with evidence strength at or stronger than `disallowed_min_tier` (tier number <= min_tier) |
| `optional_only` | Only optional skill tokens matched; no required evidence present |
| `mixed` | Multiple mismatch conditions present (e.g. missing required + disallowed hit) |
| `skill_not_loaded` | Expected skill ID not found in output (activity evidence was present) |
| `missing_skill_file_evidence` | Skill-specific file path token missing, but skill ID matched |
| `missing_activity_evidence` | No activity tokens found, but skill evidence was present |
| `mixed_evidence_missing` | Both skill ID and activity evidence missing |
| `unknown` | None of the above patterns matched |

### `failure_category` (failure cause)

Deterministic priority-order mapping (evaluated in order, first match wins):

| Category | Condition | Priority |
|----------|-----------|----------|
| `timeout` | `timed_out == true` | Highest |
| `transport` | Process failed to start, CLI missing (exit 126/127), or status is `infra_error` | Middle |
| `assertion` | Evidence gating failed and not timed out | Lowest |
| `null` | Result is pass | N/A |

`failure_category` is orthogonal to `failure_kind`. A timed-out result may also have a mismatch kind (e.g. `missing_required`) but the category will be `timeout` because it has the highest priority.

## Targeted Reruns

Filter runs to specific agents and/or cases for fast iteration:

```bash
# Single agent, single case
./test.sh --agents claude --case-id foundation-version-detection

# Single agent, full corpus
./test.sh --agents codex

# Multiple cases
./test.sh --agents claude --case-id foundation-version-detection --case-id testing-xunit-strategy

# Single category across all agents
./test.sh --category api

# Combined filters
./test.sh --agents claude,codex --category testing --max-parallel 2
```

Targeted reruns use the same artifact isolation, telemetry, and evidence evaluation as full runs. The batch directory contains only the filtered results.

## Provider Matrix and Deltas

### CI matrix

The GitHub Actions workflow (`agent-live-routing.yml`) runs each provider as a separate matrix job:

```yaml
strategy:
  fail-fast: false
  matrix:
    agent: [claude, codex, copilot]
```

- `fail-fast: false`: All provider jobs run to completion regardless of individual failures.
- All providers (including Copilot) are hard-gated: no `continue-on-error`. Copilot failures surface immediately.
- Each job uploads artifacts with `if: always()` so the summarize step always has data.
- Checkout uses `fetch-depth: 0` for full history access during baseline comparison.

### Baseline schema

`tests/agent-routing/provider-baseline.json` defines expected outcomes per case per provider:

```json
{
  "case-id": {
    "provider": {
      "expected_status": "pass|fail|infra_error",
      "allow_timeout": false
    }
  }
}
```

When `provider-baseline.json` exists, every `(case_id, provider)` tuple in results MUST have an entry. Missing entries produce a hard failure with the message: `ERROR: No baseline entry for case '<case_id>' provider '<provider>'. Update provider-baseline.json.` When the file is absent, a synthetic all-pass baseline is generated from the result set (every case expected to pass, no timeouts allowed).

### Regression rules

The summarize job compares results against TWO baselines:

1. **Ref baseline:** Loaded from `git show origin/<baseline_ref>:tests/agent-routing/provider-baseline.json`. Default `baseline_ref` is `main`, overridable via `workflow_dispatch` input.
2. **Current baseline:** The checked-in `provider-baseline.json` in the working tree.

Regression detection:
- `pass -> fail` or `pass -> infra_error`: Regression.
- `timed_out && !allow_timeout`: Timeout regression.
- `fail -> pass` or `infra_error -> pass`: Improvement (logged, not blocking).
- Entry present in current baseline but absent from ref baseline: **NEW** coverage (logged in delta table, no regression comparison). This prevents deadlocking case evolution.
- Missing result for any `(case_id, provider)` tuple: Hard failure.

The delta report is written to `$GITHUB_STEP_SUMMARY` as a markdown table:

```
| case_id | claude | codex | copilot | delta |
|---------|--------|-------|---------|-------|
| foundation-version-detection | pass | pass | pass | OK |
| new-case-added | pass | pass | fail | NEW |
```

### Timeout handling

- Timeout is tracked per result via the `timed_out` boolean.
- `allow_timeout: false` in the baseline means any timeout is a regression.
- `allow_timeout: true` permits timeouts without regression classification (useful for known-slow cases).

### Missing artifact behavior

- If a provider matrix job fails to produce `results.json` (e.g. runner crash, setup failure), the summarize step reports `ERROR: No results found for provider '<provider>'. Missing artifact or results.json.` and sets the hard fail flag.
- Missing result rows for specific `(case_id, provider)` tuples within an otherwise-present results file also cause hard failure.

## Environment Variables

Command template overrides:

- `AGENT_CLAUDE_TEMPLATE`
- `AGENT_CODEX_TEMPLATE`
- `AGENT_COPILOT_TEMPLATE`

Default templates are used when unset.

Log fallback root overrides (path-separated list):

- `AGENT_CLAUDE_LOG_DIRS`
- `AGENT_CODEX_LOG_DIRS`
- `AGENT_COPILOT_LOG_DIRS`

Concurrency:

- `MAX_CONCURRENCY`: Fallback for `--max-parallel` (flag takes precedence). Default: 4.

## GitHub Workflows

### `validate.yml` (PR-blocking)

Runs on `push` and `pull_request` to `main`. Contains:

- **`lint` job**: Structural validation (plugin/hook/MCP JSON checks, skill/agent validation, routing quality gates, dynamic skill count assertion from plugin.json, provider structural smoke checks).
- **`hooks-smoke` job**: Cross-OS hook contract checks (`ubuntu`, `macos`, `windows`).
- **`build-test` job**: Deterministic compile + self-test for the routing runner (`check-skills.cs`).

### `agent-live-routing.yml` (comprehensive)

Runs via `workflow_dispatch` only.

- Provider matrix: separate jobs for `claude`, `codex`, `copilot` (all hard-gated, no `continue-on-error`).
- `baseline_ref` input (default: `main`) controls regression comparison ref.
- `fail_on_infra` input (default: `true`) controls whether infra errors fail the run.
- Summarize job runs `if: always()` and produces a delta report in the job summary. `infra_error` results count as "failed" when `fail_on_infra=true`, "skipped" when `fail_on_infra=false` (manual override only).

## Optional Copilot Smoke Checks

Copilot smoke checks remain available via `tests/copilot-smoke/run_smoke.py`, but they are no longer PR-blocking in `validate.yml`.

### What a Copilot smoke pass means

1. **Copilot CLI is installed** and `copilot --version` exits 0 (health check gate).
2. **Plugin registration succeeds**: `copilot plugin marketplace add` + `copilot plugin install dotnet-artisan@dotnet-artisan` complete, and `copilot plugin marketplace list` contains `dotnet-artisan`.
3. **Smoke tests produce no regressions**: Results for each deterministic case match the committed `tests/copilot-smoke/baseline.json` (status comparison, not percentage thresholds).
4. **Evidence patterns**: Each passing case shows `Base directory for this skill:` lines in stdout/stderr containing the expected skill path under `plugins/dotnet-artisan/skills/<skill-name>/`.

### How to update baselines when intentional behavior changes

1. **Copilot smoke baseline** (`tests/copilot-smoke/baseline.json`):
   - Run smoke tests locally: `python tests/copilot-smoke/run_smoke.py --output /tmp/smoke-results.json`
   - Review results and update `baseline.json` entries for cases with intentional status changes.
   - Every case ID in `cases.jsonl` must have a corresponding entry in `baseline.json`.

2. **Agent routing baseline** (`tests/agent-routing/provider-baseline.json`):
   - Run full test suite: `./test.sh --agents copilot`
   - Update `provider-baseline.json` entries for cases with intentional changes.
   - Every `(case_id, provider)` tuple must have a baseline entry.

3. **Commit baseline changes**: Baseline updates should be committed alongside the code changes that cause the behavior change, not separately.

## Troubleshooting

- `infra_error` means the runner could not start the command (for example, missing CLI or invalid template).
- `fail` with `timed_out: true` means the agent ran but did not produce required skill/tool evidence before timeout.
- If evidence is present in logs but not stdout/stderr, ensure fallback log paths are correct.
- For local debugging, write output to a file:
  - `./test.sh --output /tmp/live-routing.json`
- Run `--self-test` to verify ComputeTier logic without any agent invocations:
  - `dotnet run --file tests/agent-routing/check-skills.cs -- --self-test`
