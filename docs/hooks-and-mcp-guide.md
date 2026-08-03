# Hooks and MCP Server Guide

This guide explains the hooks and MCP server integration included with the dotnet-artisan plugin.

---

## Hooks Overview

The dotnet-artisan plugin includes two hook configurations that fire automatically during Claude Code sessions. Hooks reinforce `using-dotnet` as the first routing step and `dotnet-advisor` as the second.

### SessionStart Hook (startup)

The `plugins/dotnet-artisan/scripts/hooks/session-start-context.js` hook fires once when a new Claude Code session starts. It detects whether the current directory is a .NET project and injects context:

- Detects `.sln`/`.slnx` solution files (up to 3 directories deep)
- Detects `.csproj` project files (up to 3 directories deep)
- Checks for `global.json`
- Extracts the target framework moniker (TFM) from the first `.csproj` found

Detection uses first-hit scans to keep hook latency low in large repositories.

If .NET project indicators are found, the hook outputs an `additionalContext` message that starts with:

> Mandatory first action for every task: invoke [skill:using-dotnet]. Mandatory second action: invoke [skill:dotnet-advisor].

This context helps Claude understand the project environment from the start of the session.

### UserPromptSubmit Hook

The `plugins/dotnet-artisan/scripts/hooks/user-prompt-dotnet-reminder.js` hook fires on every prompt submission and injects `additionalContext` routing guidance when either condition is true:

- The current directory looks like a .NET repo (`.sln`, `.slnx`, `.csproj`, `.cs`, or `global.json`)
- The prompt text contains .NET intent keywords (for example: `dotnet`, `.NET`, `C#`, `csproj`, `MSBuild`, `NuGet`, `Roslyn`, `xUnit`, `ASP.NET`, `Blazor`, `MAUI`, `WinUI`, `WPF`, `WinForms`, `EF Core`, `BenchmarkDotNet`)

This catches greenfield prompts (for example, "create a new .NET app") even when the current directory has no existing .NET files yet.
If the prompt already asks for `using-dotnet` directly, the hook suppresses the duplicate reminder.

### Hook Contract Validation

Run `scripts/validate-hooks.sh` to verify hook behavior locally. The script checks:

- Valid JSON output for all active hook scripts
- Direct invocation without piped stdin does not block
- Prompt extraction and reminder injection
- Duplicate-reminder suppression when `using-dotnet` is already requested

---

## How to Disable Hooks

Plugin hooks can be disabled in two ways:

1. **Disable all hooks globally**: Set `disableAllHooks: true` in your `.claude/settings.json` file. This disables hooks from all plugins, not just dotnet-artisan.

2. **Per-session control**: Use the `/hooks` menu within Claude Code to review and toggle individual hooks during a session. Note that hooks snapshot at session startup; changes via `/hooks` take effect immediately but do not persist across restarts.

To re-enable hooks after disabling, remove the `disableAllHooks` setting or toggle them back on via `/hooks`.

---

## MCP Server Configuration

The plugin configures these MCP servers in `plugins/dotnet-artisan/.mcp.json`:

| Server | Transport | Command / URL | Purpose |
|-------|-----------|----------------|---------|
| `context7` | stdio | `npx -y @upstash/context7-mcp@latest` | Library and framework documentation lookup |
| `microsoftdocs-mcp` | HTTP | `https://learn.microsoft.com/api/mcp` | Official Microsoft Learn search/fetch for .NET and Azure docs |

### Requirements

- **Node.js** is required to execute hook scripts (`plugins/dotnet-artisan/scripts/hooks/*.js`) and for MCP servers that use `npx` (Context7). Claude Code requires Node.js on all platforms, so this is always available. Verify with `node --version`.
- MCP servers start automatically when the plugin is enabled. After enabling or disabling the plugin, restart Claude Code to apply MCP server changes.

---

## Troubleshooting

### `npx` not available

MCP servers configured with `npx` (such as Context7) will not start if Node.js is not installed.

**Fix**: Install [Node.js](https://nodejs.org/) (LTS recommended). After installation, restart Claude Code so MCP servers can initialize.

### Hooks not firing

Hooks are snapshotted when a Claude Code session starts. If you install or update the plugin mid-session, hooks from the new version will not fire until the next session.

**Fix**: Restart Claude Code to pick up hook changes. Use `/hooks` to verify hooks are registered.

### `node` not found

Hook scripts are written in Node.js. Claude Code requires Node.js on all platforms, so this should not normally occur.

**Fix**: Install [Node.js](https://nodejs.org/) (LTS recommended). Verify with `node --version`.
