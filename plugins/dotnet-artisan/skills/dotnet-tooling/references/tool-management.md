# Tool Management

Consumer-side management of .NET CLI tools: installing global and local tools, creating and maintaining `.config/dotnet-tools.json` manifests, version pinning for team reproducibility, `dotnet tool restore` in CI pipelines, updating and uninstalling tools, and troubleshooting common tool issues.

**Version assumptions:** .NET 8.0+ baseline. Local tools and tool manifests available since .NET Core 3.0. RID-specific tool packaging available since .NET 10.

## Global Tool Installation

Global tools are installed per-user and available from any directory. The tool binaries are added to a directory on the user's PATH.

```bash
# Install a global tool
dotnet tool install -g <package-id>

# Install a specific version
dotnet tool install -g <package-id> --version 1.2.3

# Install a pre-release version
dotnet tool install -g <package-id> --version "*-rc*"

# List installed global tools
dotnet tool list -g

# Update a global tool to the latest stable version
dotnet tool update -g <package-id>

# Uninstall a global tool
dotnet tool uninstall -g <package-id>
```

**Default install locations:**

| OS | Path |
|-----|------|
| Linux/macOS | `$HOME/.dotnet/tools` |
| Windows | `%USERPROFILE%\.dotnet\tools` |

Global tools are user-scoped, not machine-wide. Each user maintains their own tool installations independently.

### Custom Install Location

Use `--tool-path` to install to a custom directory. The directory is not automatically added to PATH -- you must manage PATH yourself:

```bash
dotnet tool install <package-id> --tool-path ~/my-tools
```


## Local Tool Installation

Local tools are scoped to a directory tree and tracked in a manifest file. Different directories can use different versions of the same tool.

### Creating the Tool Manifest

The manifest file `.config/dotnet-tools.json` tracks local tool versions. Create it at the repository root:

```bash
# Create the manifest (first time only, at repo root)
dotnet new tool-manifest
```

This produces:

```json
{
  "version": 1,
  "isRoot": true,
  "tools": {}
}
```

Commit this file to source control so all team members share the same tool versions.

### Installing Local Tools

Omit the `-g` flag to install a tool locally. The tool is recorded in the nearest manifest file:

```bash
# Install a local tool (recorded in .config/dotnet-tools.json)
dotnet tool install <package-id>

# Install a specific version
dotnet tool install <package-id> --version 2.0.1

# List local tools
dotnet tool list

# Update a local tool
dotnet tool update <package-id>

# Uninstall a local tool
dotnet tool uninstall <package-id>
```

After installing two tools, the manifest looks like:

```json
{
  "version": 1,
  "isRoot": true,
  "tools": {
    "dotnet-ef": {
      "version": "9.0.3",
      "commands": [
        "dotnet-ef"
      ]
    },
    "nbgv": {
      "version": "3.7.112",
      "commands": [
        "nbgv"
      ]
    }
  }
}
```

### Running Local Tools

```bash
# Run a local tool (long form)
dotnet tool run <command-name>

# Run a local tool (short form, when command starts with dotnet-)
dotnet <command-name>

# Examples
dotnet tool run dotnet-ef migrations add Init
dotnet ef migrations add Init  # equivalent short form
```


## Version Pinning and Team Workflows

The tool manifest enables reproducible tool versions across the team.

### Pinning Strategy

1. **One team member** creates the manifest and installs tools with specific versions
2. **Commit** `.config/dotnet-tools.json` to source control
3. **All team members** run `dotnet tool restore` after cloning or pulling
4. **Updates** are explicit: one person runs `dotnet tool update <package-id>`, commits the updated manifest

### Version Ranges

Use the `--version` option with NuGet version ranges for controlled flexibility:

```bash
# Exact version (strictest)
dotnet tool install <package-id> --version 2.0.1

# Allow patch updates (recommended for most tools)
dotnet tool install <package-id> --version "2.0.*"

# Pre-release versions
dotnet tool install <package-id> --version "*-preview*"
```

The manifest always records the exact resolved version, ensuring all team members use identical versions after restore.


## CI Integration

### Tool Restore Before Build

In CI pipelines, restore tools before any build step that depends on them. Tool restore is fast and idempotent.

**GitHub Actions:**

```yaml
steps:
  - uses: actions/checkout@v4
  - uses: actions/setup-dotnet@v4
    with:
      dotnet-version: '8.0.x'
  - name: Restore tools
    run: dotnet tool restore
  - name: Build
    run: dotnet build
  - name: Run EF migrations check
    run: dotnet ef migrations has-pending-changes
```

**Azure DevOps Pipelines:**

```yaml
steps:
  - task: UseDotNet@2
    inputs:
      packageType: sdk
      version: '8.0.x'
  - script: dotnet tool restore
    displayName: 'Restore tools'
  - script: dotnet build
    displayName: 'Build'
```

### CI Best Practices

- **Always run `dotnet tool restore` before build** -- do not rely on tools being pre-installed on CI agents
- **Commit `.config/dotnet-tools.json`** -- the manifest ensures CI uses the same tool versions as local development
- **Do not install tools globally in CI** -- use local tool manifests for reproducibility; global installs may conflict across concurrent jobs
- **Cache NuGet packages** to speed up tool restore (`~/.nuget/packages` on Linux/macOS, `%USERPROFILE%\.nuget\packages` on Windows)


## RID-Specific Tools

Starting with .NET 10, tool authors can publish RID-specific, self-contained, or Native AOT versions of their tools. From a consumer perspective, this is transparent -- the `dotnet tool install` command automatically selects the best package for your platform.

```bash
# RID selection is automatic -- no extra flags needed
dotnet tool install -g <package-id>
```

The .NET CLI detects your platform and downloads the appropriate RID-specific package. If no RID-specific package matches your platform, the CLI falls back to a framework-dependent package (if the tool author provided one).

For details on authoring and packaging RID-specific tools, see `references/cli-distribution.md`.


## Troubleshooting

### Common Issues

**"Tool already installed"** -- Uninstall first or use `dotnet tool update`:

```bash
dotnet tool update -g <package-id>
```

**"No manifest file found"** -- Run `dotnet new tool-manifest` to create one, or check that you are in a directory at or below the manifest location.

**"Tool not found after install"** -- For global tools, verify `~/.dotnet/tools` is on your PATH. For local tools, ensure you are in the directory tree containing the manifest.

**"Version mismatch in CI"** -- Verify `.config/dotnet-tools.json` is committed and `dotnet tool restore` runs before any tool usage.


## Global vs Local Tools Decision Guide

| Aspect | Global Tool | Local Tool |
|--------|------------|------------|
| Scope | System-wide (per user) | Per-project directory tree |
| Install location | `~/.dotnet/tools` | `.config/dotnet-tools.json` manifest |
| Version management | Manual `dotnet tool update -g` | Tracked in source control |
| CI/CD | Must install before use (not reproducible) | `dotnet tool restore` restores all (reproducible) |
| Team consistency | Each developer manages independently | Manifest ensures identical versions |
| Best for | Personal productivity tools, one-off utilities | Project-specific build/dev tools |

**Prefer local tools** for anything used in a project's build, test, or development workflow. Reserve global tools for personal utilities not tied to a specific project.


## Agent Gotchas

1. **Do not install project-specific tools globally in CI.** Use local tool manifests and `dotnet tool restore` for reproducible builds. Global installs may conflict across concurrent CI jobs and drift from the team's pinned versions.
2. **Do not skip `dotnet tool restore` in CI pipelines.** Tools are not pre-installed on CI agents. Always restore before any step that invokes a local tool, or the build will fail with "tool not found."
3. **Do not omit `.config/dotnet-tools.json` from source control.** The manifest is the single source of truth for tool versions. Without it, `dotnet tool restore` has nothing to restore and each developer gets different versions.
4. **Do not specify RID flags when installing tools as a consumer.** The .NET CLI automatically selects the correct RID-specific package for your platform. Manual RID selection is unnecessary and may cause installation failures.
5. **Do not confuse tool command names with package IDs.** The package ID (e.g., `dotnet-ef`) may differ from the command name (e.g., `dotnet ef`). Use `dotnet tool list` to see the mapping between package IDs and commands.


## References

- [.NET tools overview](https://learn.microsoft.com/en-us/dotnet/core/tools/global-tools)
- [How to manage .NET local tools](https://learn.microsoft.com/en-us/dotnet/core/tools/local-tools-how-to-use)
- [dotnet tool install command](https://learn.microsoft.com/en-us/dotnet/core/tools/dotnet-tool-install)
- [dotnet tool restore command](https://learn.microsoft.com/en-us/dotnet/core/tools/dotnet-tool-restore)
- [RID-specific .NET tools](https://learn.microsoft.com/en-us/dotnet/core/tools/rid-specific-tools)
- [Troubleshoot .NET tool usage issues](https://learn.microsoft.com/en-us/dotnet/core/tools/troubleshoot-usage-issues)
