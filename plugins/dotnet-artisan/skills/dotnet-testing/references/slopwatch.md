# Slopwatch

Slopwatch: LLM Anti-Cheat Quality Gate for .NET

Run the `Slopwatch.Cmd` dotnet tool as an automated quality gate after code modifications to detect "slop" -- shortcuts that make builds/tests pass without fixing real problems.

## Prerequisites

- .NET 8.0+ SDK
- `Slopwatch.Cmd` NuGet package (v0.3.3+)

Cross-references: [skill:dotnet-tooling] `references/tool-management.md` for general dotnet tool installation mechanics.

---

## Installation

### Local Tool (Recommended)

Add to `.config/dotnet-tools.json`:

```json
{
  "version": 1,
  "isRoot": true,
  "tools": {
    "slopwatch.cmd": {
      "version": "0.3.3",
      "commands": ["slopwatch"],
      "rollForward": false
    }
  }
}
```

Then restore:

```bash
dotnet tool restore
```

### Global Tool

```bash
dotnet tool install --global Slopwatch.Cmd
```

See [skill:dotnet-tooling] `references/tool-management.md` for tool manifest conventions and restore patterns.

---

## Usage

### Basic Analysis

```bash
# Analyze current directory for slop
slopwatch analyze

# Analyze specific directory
slopwatch analyze -d ./src

# Strict mode -- fail on warnings too
slopwatch analyze --fail-on warning

# JSON output for tooling integration
slopwatch analyze --output json

# Show performance stats
slopwatch analyze --stats
```

### First-Time Setup: Establish a Baseline

For existing projects with pre-existing issues, create a baseline so slopwatch only catches **new** slop. The `init` command scans all files and records current findings as the accepted baseline:

```bash
slopwatch init
git add .slopwatch/baseline.json
git commit -m "Add slopwatch baseline"
```

### Updating the Baseline (Rare)

Only update when slop is **truly justified** and documented:

```bash
slopwatch analyze --update-baseline
```

Valid reasons: third-party library forces a pattern, intentional rate-limiting delay (not test flakiness), generated code that cannot be modified. Always add a code comment explaining the justification.

---

## Configuration

Create `.slopwatch/slopwatch.json` to customize rules and exclusions:

```json
{
  "minSeverity": "warning",
  "rules": {
    "SW001": { "enabled": true, "severity": "error" },
    "SW002": { "enabled": true, "severity": "warning" },
    "SW003": { "enabled": true, "severity": "error" },
    "SW004": { "enabled": true, "severity": "warning" },
    "SW005": { "enabled": true, "severity": "warning" },
    "SW006": { "enabled": true, "severity": "warning" }
  },
  "exclude": [
    "**/Generated/**",
    "**/obj/**",
    "**/bin/**"
  ]
}
```

### Strict Mode (Recommended for LLM Sessions)

Elevate all rules to errors during LLM coding sessions:

```json
{
  "minSeverity": "warning",
  "rules": {
    "SW001": { "enabled": true, "severity": "error" },
    "SW002": { "enabled": true, "severity": "error" },
    "SW003": { "enabled": true, "severity": "error" },
    "SW004": { "enabled": true, "severity": "error" },
    "SW005": { "enabled": true, "severity": "error" },
    "SW006": { "enabled": true, "severity": "error" }
  }
}
```

---

## Detection Rules

| Rule | Severity | What It Catches |
|------|----------|-----------------|
| SW001 | Error | Disabled tests (`Skip=`, `Ignore`, `#if false`) |
| SW002 | Warning | Warning suppression (`#pragma warning disable`, `SuppressMessage`) |
| SW003 | Error | Empty catch blocks that swallow exceptions |
| SW004 | Warning | Arbitrary delays in tests (`Task.Delay`, `Thread.Sleep`) |
| SW005 | Warning | Project file slop (`NoWarn`, `TreatWarningsAsErrors=false`) |
| SW006 | Warning | CPM bypass (`VersionOverride`, inline `Version` attributes) |

### When Slopwatch Flags an Issue

1. **Understand why** the shortcut was taken
2. **Request a proper fix** -- be specific about what's wrong
3. **Verify the fix** doesn't introduce different slop

```
# Example output
❌ SW001 [Error]: Disabled test detected
   File: tests/MyApp.Tests/OrderTests.cs:45
   Pattern: [Fact(Skip="Test is flaky")]
```

**Never disable tests to achieve a green build.** Fix the underlying issue.

---

## Claude Code Hook Integration

Add slopwatch as a `PostToolUse` hook to automatically validate every edit. Create or update `.claude/settings.json`:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "slopwatch analyze -d . --hook",
            "timeout": 60000
          }
        ]
      }
    ]
  }
}
```

The `--hook` flag:
- Only analyzes **git dirty files** (fast, even on large repos)
- Outputs errors to stderr in readable format
- Blocks the edit on warnings/errors (exit code 2)
- Claude sees the error and can fix it immediately

This is the pattern used by projects like BrighterCommand/Brighter.

---

## CI/CD Integration

### GitHub Actions

```yaml
jobs:
  slopwatch:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup .NET
        uses: actions/setup-dotnet@v4
        with:
          dotnet-version: '8.0.x'  # any .NET 8+ SDK works

      - name: Install Slopwatch
        run: dotnet tool install --global Slopwatch.Cmd

      - name: Run Slopwatch
        run: slopwatch analyze -d . --fail-on warning
```

### Azure Pipelines

```yaml
- task: DotNetCoreCLI@2
  displayName: 'Install Slopwatch'
  inputs:
    command: 'custom'
    custom: 'tool'
    arguments: 'install --global Slopwatch.Cmd'

- script: slopwatch analyze -d . --fail-on warning
  displayName: 'Slopwatch Analysis'
```

---

## Agent Gotchas

- **Do not suppress slopwatch findings.** If slopwatch flags an issue, fix the code -- do not update the baseline or disable the rule without explicit user approval.
- **Run after every code change**, not just at the end. Catching slop early prevents cascading shortcuts.
- **Use `--hook` flag in Claude Code hooks**, not bare `analyze`. The hook flag restricts analysis to dirty files for performance.
- **Baseline is not a wastebasket.** Adding items to the baseline requires documented justification. Never bulk-update baseline to silence warnings.
- **Local tool preferred over global.** Use `.config/dotnet-tools.json` so the version is pinned and reproducible across team members.

---

## Quick Reference

```bash
# First time setup
slopwatch init
git add .slopwatch/baseline.json

# After every code change
slopwatch analyze

# Strict mode (recommended)
slopwatch analyze --fail-on warning

# Hook mode (for Claude Code integration)
slopwatch analyze -d . --hook

# JSON output for tooling
slopwatch analyze --output json

# Update baseline (rare, document why)
slopwatch analyze --update-baseline
```

---

## References

- [Slopwatch NuGet Package](https://www.nuget.org/packages/Slopwatch.Cmd)
- [skill:dotnet-tooling] `references/tool-management.md` -- dotnet tool installation and manifest conventions
- [skill:dotnet-api] `references/agent-gotchas.md` -- manual slop pattern recognition (visual detection counterpart)
- [skill:dotnet-testing] `references/test-quality.md` -- test coverage and quality measurement
