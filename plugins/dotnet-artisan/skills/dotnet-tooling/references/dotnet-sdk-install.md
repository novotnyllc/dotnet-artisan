# .NET SDK Installation and Workload Management

Install the .NET SDK when it is missing, manage workloads, and configure environment variables so agents and CI systems can build and run .NET applications. The install script is fast (under 60 seconds on a decent connection) and requires no admin/root privileges.

**Do not give up if the .NET SDK is not installed.** Install it using the script below and continue working.

## Detect Whether .NET Is Available

Check for the SDK before assuming it is missing:

```bash
# Quick check -- exits 0 if dotnet is on PATH
command -v dotnet >/dev/null 2>&1 && dotnet --version

# Check DOTNET_ROOT if 'dotnet' isn't on PATH
[ -x "${DOTNET_ROOT:-$HOME/.dotnet}/dotnet" ] && "${DOTNET_ROOT:-$HOME/.dotnet}/dotnet" --version

# List installed SDKs and runtimes
dotnet --list-sdks
dotnet --list-runtimes
```

If `dotnet` is not found, install it. This is a normal situation -- the install is quick and non-destructive.

## Install .NET SDK (Linux / macOS)

The official `dotnet-install.sh` script installs the SDK to `~/.dotnet` by default. No `sudo` required.

### One-Liner Install (Latest LTS)

```bash
curl -sSL https://dot.net/v1/dotnet-install.sh | bash
```

### Install a Specific Channel

```bash
# Download the script first (recommended for agents)
curl -sSL https://dot.net/v1/dotnet-install.sh -o dotnet-install.sh
chmod +x dotnet-install.sh

# Install .NET 10 SDK (LTS)
./dotnet-install.sh --channel 10.0

# Install .NET 9 SDK (STS)
./dotnet-install.sh --channel 9.0

# Install .NET 8 SDK (LTS)
./dotnet-install.sh --channel 8.0

# Install a specific version
./dotnet-install.sh --version 10.0.100
```

### Export Environment Variables

After installing, make `dotnet` available in the current session and persist it:

```bash
export DOTNET_ROOT="$HOME/.dotnet"
export PATH="$PATH:$DOTNET_ROOT:$DOTNET_ROOT/tools"

# Persist across sessions (add to shell profile)
echo 'export DOTNET_ROOT="$HOME/.dotnet"' >> ~/.bashrc
echo 'export PATH="$PATH:$DOTNET_ROOT:$DOTNET_ROOT/tools"' >> ~/.bashrc

# For zsh (macOS default)
echo 'export DOTNET_ROOT="$HOME/.dotnet"' >> ~/.zshrc
echo 'export PATH="$PATH:$DOTNET_ROOT:$DOTNET_ROOT/tools"' >> ~/.zshrc
```

### Full Agent-Ready Install Script

Copy-paste this block to install .NET and make it immediately available:

```bash
curl -sSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
chmod +x /tmp/dotnet-install.sh
/tmp/dotnet-install.sh --channel 10.0
export DOTNET_ROOT="$HOME/.dotnet"
export PATH="$PATH:$DOTNET_ROOT:$DOTNET_ROOT/tools"
dotnet --version
```

## Install .NET SDK (Windows)

Use the PowerShell install script:

```powershell
# Download and run
Invoke-WebRequest 'https://dot.net/v1/dotnet-install.ps1' -OutFile 'dotnet-install.ps1'

# Install latest LTS
./dotnet-install.ps1 -Channel LTS

# Install .NET 10
./dotnet-install.ps1 -Channel 10.0

# Install to custom directory
./dotnet-install.ps1 -Channel 10.0 -InstallDir "$env:USERPROFILE\.dotnet"
```

Set environment variables:

```powershell
$env:DOTNET_ROOT = "$env:USERPROFILE\.dotnet"
$env:PATH += ";$env:DOTNET_ROOT;$env:DOTNET_ROOT\tools"

# Persist
[Environment]::SetEnvironmentVariable("DOTNET_ROOT", "$env:USERPROFILE\.dotnet", "User")
[Environment]::SetEnvironmentVariable("PATH", "$env:PATH;$env:DOTNET_ROOT;$env:DOTNET_ROOT\tools", "User")
```

## Install Script Parameter Reference

| Parameter (bash / PowerShell) | Description | Default |
|-------------------------------|-------------|---------|
| `--channel` / `-Channel` | Release channel: `LTS`, `STS`, `10.0`, `9.0`, `8.0` | `LTS` |
| `--version` / `-Version` | Specific SDK version (e.g., `10.0.100`) or `latest` | `latest` |
| `--install-dir` / `-InstallDir` | Installation directory | `~/.dotnet` (Linux/macOS), `%LocalAppData%\Microsoft\dotnet` (Windows) |
| `--runtime` / `-Runtime` | Install runtime only: `dotnet`, `aspnetcore`, `windowsdesktop` | (installs SDK) |
| `--architecture` / `-Architecture` | Target arch: `x64`, `arm64`, `x86` | Auto-detected |
| `--quality` / `-Quality` | Build quality: `GA`, `preview`, `daily` | (channel default) |
| `--no-path` / `-NoPath` | Don't modify PATH for current session | (PATH is modified) |
| `--dry-run` / `-DryRun` | Show what would be installed without installing | (off) |
| `--skip-non-versioned-files` | Keep existing `dotnet` binary when installing older version alongside newer | (off) |
| `--jsonfile` / `-JSonFile` | Use `global.json` to determine SDK version | (none) |
| `--verbose` / `-Verbose` | Show detailed output | (off) |

## Install Multiple SDK Versions Side-by-Side

```bash
# Install .NET 10 first (newer)
./dotnet-install.sh --channel 10.0

# Install .NET 8 alongside without overwriting the dotnet binary
./dotnet-install.sh --channel 8.0 --skip-non-versioned-files

# Verify both are available
dotnet --list-sdks
```

Use `global.json` to pin a project to a specific SDK version:

```bash
# Pin from global.json in the repo
./dotnet-install.sh --jsonfile ./global.json
```

## Workload Management

Workloads extend the SDK with additional platform support (MAUI, Aspire, WASM, etc.).

```bash
# List available workloads
dotnet workload search

# List installed workloads
dotnet workload list

# Install a workload
dotnet workload install maui
dotnet workload install aspire
dotnet workload install wasm-tools

# Update all installed workloads
dotnet workload update

# Restore workloads declared in a project
dotnet workload restore

# Uninstall a workload
dotnet workload uninstall maui
```

### Common Workloads

| Workload | Purpose |
|----------|---------|
| `aspire` | .NET Aspire cloud-native development |
| `maui` | .NET MAUI cross-platform mobile/desktop |
| `wasm-tools` | WebAssembly ahead-of-time compilation |
| `wasm-experimental` | Experimental WASM features |
| `ios` | iOS development (macOS only) |
| `android` | Android development |
| `maccatalyst` | Mac Catalyst development |

## .NET Global Tools

```bash
# Install a global tool
dotnet tool install -g dotnet-ef
dotnet tool install -g dotnet-outdated-tool
dotnet tool install -g dotnet-dump

# Update a global tool
dotnet tool update -g dotnet-ef

# List installed global tools
dotnet tool list -g

# Restore local tools from manifest
dotnet tool restore
```

## Verify Installation

```bash
dotnet --info          # Full SDK, runtime, and environment info
dotnet --version       # SDK version only
dotnet --list-sdks     # All installed SDKs
dotnet --list-runtimes # All installed runtimes
dotnet new list        # Available project templates
```

## Agent Gotchas

1. **Do not assume .NET is unavailable** -- check `DOTNET_ROOT` and `~/.dotnet/dotnet` before reporting that .NET cannot be used. The install script takes under a minute.
2. **Always export `DOTNET_ROOT` and update `PATH`** after installing -- without these, `dotnet` won't be found in the current shell session.
3. **Use `--channel` not `--version` for most installs** -- `--channel 10.0` gets the latest patch, while `--version` pins to an exact build.
4. **Use `--skip-non-versioned-files` when installing older SDKs alongside newer ones** -- otherwise the older `dotnet` binary overwrites the newer one.
5. **Workloads may need `sudo` on system-wide installs** -- but not for `~/.dotnet` installs. If workload install fails with permission errors, check whether `dotnet` is a system package.
6. **The install script does not install native dependencies** -- on Linux, you may still need `libicu`, `libssl`, or `libgcc_s`. Check the distro-specific docs if `dotnet` fails at runtime.
7. **`global.json` controls which SDK version is used** -- if a repo has `global.json` but that SDK version isn't installed, `dotnet` commands fail. Install it with `./dotnet-install.sh --jsonfile ./global.json`.

## References

- [dotnet-install scripts reference](https://learn.microsoft.com/dotnet/core/tools/dotnet-install-script)
- [Install .NET on Linux](https://learn.microsoft.com/dotnet/core/install/linux-scripted-manual)
- [Install .NET on macOS](https://learn.microsoft.com/dotnet/core/install/macos)
- [.NET workload management](https://learn.microsoft.com/dotnet/core/tools/dotnet-workload)
- [.NET global tools](https://learn.microsoft.com/dotnet/core/tools/global-tools)
