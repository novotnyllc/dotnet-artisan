# CLI Distribution and Packaging

CLI distribution strategy and multi-platform packaging for .NET tools: choosing between Native AOT single-file publish, framework-dependent deployment, and `dotnet tool` packaging. Runtime Identifier (RID) matrix planning for cross-platform targets, single-file publish configuration, binary size optimization, and packaging for Homebrew, apt/deb, winget, Scoop, Chocolatey, and `dotnet tool`.

**Version assumptions:** .NET 8.0+ baseline. Native AOT for console apps is fully supported since .NET 8. Package manager formats are stable across .NET versions.

## Distribution Strategy Decision Matrix

Choose the distribution model based on target audience and deployment constraints.

| Strategy | Startup Time | Binary Size | Runtime Required | Best For |
|----------|-------------|-------------|-----------------|----------|
| Native AOT single-file | ~10ms | 10-30 MB | None | Performance-critical CLI tools, broad distribution |
| Framework-dependent single-file | ~100ms | 1-5 MB | .NET runtime | Internal tools where runtime is guaranteed |
| Self-contained single-file | ~100ms | 60-80 MB | None | Simple distribution without AOT complexity |
| `dotnet tool` (global/local) | ~200ms | < 1 MB (NuGet) | .NET SDK | Developer tools, .NET ecosystem users |

### When to Choose Each Strategy

**Native AOT single-file** -- the gold standard for CLI distribution:
- Zero dependencies on target machine (no .NET runtime needed)
- Fastest startup (~10ms vs ~100ms+ for JIT)
- Smallest binary when combined with trimming
- Trade-off: longer build times, no reflection unless preserved
- See `references/native-aot.md` for PublishAot MSBuild configuration

**Framework-dependent deployment:**
- Smallest artifact size (only app code, no runtime)
- Users must have .NET runtime installed
- Best for internal/enterprise tools where runtime is managed
- Can still use single-file publish for convenience

**Self-contained (non-AOT):**
- Includes .NET runtime in the artifact
- Larger binary than AOT but simpler build process
- Full reflection and dynamic code support
- Good compromise when AOT compat is difficult

**`dotnet tool` packaging:**
- Distributed via NuGet -- simplest publishing workflow
- Users install with `dotnet tool install -g mytool`
- Requires .NET SDK on target (not just runtime)
- Best for developer-facing tools in the .NET ecosystem


## Runtime Identifier (RID) Matrix

### Standard CLI RID Targets

Target the four primary RIDs for broad coverage:

| RID | Platform | Notes |
|-----|----------|-------|
| `linux-x64` | Linux x86_64 | Most Linux servers, CI runners, WSL |
| `linux-arm64` | Linux ARM64 | AWS Graviton, Raspberry Pi 4+, Apple Silicon VMs |
| `osx-arm64` | macOS Apple Silicon | M1/M2/M3+ Macs (primary macOS target) |
| `win-x64` | Windows x86_64 | Windows 10+, Windows Server |

### Optional Extended Targets

| RID | When to Include |
|-----|----------------|
| `osx-x64` | Legacy Intel Mac support (declining market share) |
| `linux-musl-x64` | Alpine Linux / Docker scratch images |
| `linux-musl-arm64` | Alpine on ARM64 |
| `win-arm64` | Windows on ARM (Surface Pro X, Snapdragon laptops) |

### RID Configuration in .csproj

```xml
<!-- Set per publish, not in csproj (avoids accidental RID lock-in) -->
<!-- Use dotnet publish -r <rid> instead -->

<!-- If you must set a default for local development -->
<PropertyGroup Condition="'$(RuntimeIdentifier)' == ''">
  <RuntimeIdentifier>osx-arm64</RuntimeIdentifier>
</PropertyGroup>
```

Publish per RID from the command line:

```bash
# Publish for each target RID
dotnet publish -c Release -r linux-x64
dotnet publish -c Release -r linux-arm64
dotnet publish -c Release -r osx-arm64
dotnet publish -c Release -r win-x64
```


## Single-File Publish

Single-file publish bundles the application and its dependencies into one executable.

### Configuration

```xml
<PropertyGroup>
  <PublishSingleFile>true</PublishSingleFile>
  <!-- Required for single-file -->
  <SelfContained>true</SelfContained>
  <!-- Embed PDB for stack traces (optional, adds ~2-5 MB) -->
  <DebugType>embedded</DebugType>
  <!-- Include native libraries in the single file -->
  <IncludeNativeLibrariesForSelfExtract>true</IncludeNativeLibrariesForSelfExtract>
</PropertyGroup>
```

### Single-File with Native AOT

When combined with Native AOT, single-file is implicit -- AOT always produces a single native binary:

```xml
<PropertyGroup>
  <PublishAot>true</PublishAot>
  <!-- PublishSingleFile is not needed -- AOT output is inherently single-file -->
  <!-- SelfContained is implied by PublishAot -->
</PropertyGroup>
```

See `references/native-aot.md` for the full AOT publish configuration including ILLink, type preservation, and analyzer setup.

### Publish Command

```bash
# Framework-dependent single-file (requires .NET runtime on target)
dotnet publish -c Release -r linux-x64 /p:PublishSingleFile=true --self-contained false

# Self-contained single-file (includes runtime, no AOT)
dotnet publish -c Release -r linux-x64 /p:PublishSingleFile=true --self-contained true

# Native AOT (inherently single-file, smallest and fastest)
dotnet publish -c Release -r linux-x64
# (when PublishAot=true is in csproj)
```


## Size Optimization for CLI Binaries

### Trimming (Non-AOT)

Trimming removes unused code from the published output. For self-contained non-AOT builds:

```xml
<PropertyGroup>
  <PublishTrimmed>true</PublishTrimmed>
  <TrimMode>link</TrimMode>
  <SuppressTrimAnalysisWarnings>false</SuppressTrimAnalysisWarnings>
</PropertyGroup>
```

### AOT Size Optimization

For Native AOT builds, size is controlled by AOT-specific MSBuild properties. See `references/native-aot.md` for the full configuration. Key CLI-relevant properties include `StripSymbols`, `OptimizationPreference`, `InvariantGlobalization`, and `StackTraceSupport`.

### Size Comparison (Typical CLI Tool)

| Configuration | Approximate Size |
|---------------|-----------------|
| Self-contained (no trim) | 60-80 MB |
| Self-contained + trimmed | 15-30 MB |
| Native AOT (default) | 15-25 MB |
| Native AOT + size optimized | 8-15 MB |
| Native AOT + invariant globalization + stripped | 5-10 MB |
| Framework-dependent | 1-5 MB |


## Homebrew (macOS / Linux)

Homebrew is the primary package manager for macOS and widely used on Linux. Use a binary tap formula for Native AOT CLI tools.

### Binary Tap (Formula)

A formula downloads pre-built binaries per platform:

```ruby
# Formula/mytool.rb
class Mytool < Formula
  desc "A CLI tool for managing widgets"
  homepage "https://github.com/myorg/mytool"
  version "1.2.3"
  license "MIT"

  on_macos do
    on_arm do
      url "https://github.com/myorg/mytool/releases/download/v1.2.3/mytool-1.2.3-osx-arm64.tar.gz"
      sha256 "abc123..."
    end
    on_intel do
      url "https://github.com/myorg/mytool/releases/download/v1.2.3/mytool-1.2.3-osx-x64.tar.gz"
      sha256 "def456..."
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/myorg/mytool/releases/download/v1.2.3/mytool-1.2.3-linux-arm64.tar.gz"
      sha256 "ghi789..."
    end
    on_intel do
      url "https://github.com/myorg/mytool/releases/download/v1.2.3/mytool-1.2.3-linux-x64.tar.gz"
      sha256 "jkl012..."
    end
  end

  def install
    bin.install "mytool"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/mytool --version")
  end
end
```

### Hosting a Tap

Create a repo named `homebrew-tap` with a `Formula/` directory containing the formula. Users install with:

```bash
brew tap myorg/tap
brew install mytool
```


## apt/deb (Debian/Ubuntu)

### Package Directory Structure

```
mytool_1.2.3_amd64/
  DEBIAN/
    control
  usr/
    bin/
      mytool
```

### Control File

```
Package: mytool
Version: 1.2.3
Section: utils
Priority: optional
Architecture: amd64
Maintainer: My Org <dev@myorg.com>
Description: A CLI tool for managing widgets
 MyTool provides fast widget management from the command line.
 Built with .NET Native AOT for zero-dependency execution.
Homepage: https://github.com/myorg/mytool
```

### Build Command

```bash
dpkg-deb --build --root-owner-group mytool_1.2.3_amd64
```

**RID to Debian architecture mapping:**

| .NET RID | Debian Architecture |
|----------|-------------------|
| `linux-x64` | `amd64` |
| `linux-arm64` | `arm64` |


## winget (Windows Package Manager)

### Directory Structure

```
manifests/
  m/
    MyOrg/
      MyTool/
        1.2.3/
          MyOrg.MyTool.yaml              # Version manifest
          MyOrg.MyTool.installer.yaml    # Installer manifest
          MyOrg.MyTool.locale.en-US.yaml # Locale manifest
```

### Version Manifest (MyOrg.MyTool.yaml)

```yaml
PackageIdentifier: MyOrg.MyTool
PackageVersion: 1.2.3
DefaultLocale: en-US
ManifestType: version
ManifestVersion: 1.9.0
```

### Installer Manifest (MyOrg.MyTool.installer.yaml)

```yaml
PackageIdentifier: MyOrg.MyTool
PackageVersion: 1.2.3
InstallerType: zip
NestedInstallerType: portable
NestedInstallerFiles:
  - RelativeFilePath: mytool.exe
    PortableCommandAlias: mytool
Installers:
  - Architecture: x64
    InstallerUrl: https://github.com/myorg/mytool/releases/download/v1.2.3/mytool-1.2.3-win-x64.zip
    InstallerSha256: ABC123...
  - Architecture: arm64
    InstallerUrl: https://github.com/myorg/mytool/releases/download/v1.2.3/mytool-1.2.3-win-arm64.zip
    InstallerSha256: DEF456...
ManifestType: installer
ManifestVersion: 1.9.0
```

### Submitting to winget-pkgs

1. Fork `microsoft/winget-pkgs` on GitHub
2. Create manifest files in the correct directory structure
3. Validate locally: `winget validate --manifest <path>`
4. Submit a PR -- automated checks run against the manifest

See `references/cli-release-pipeline.md` for automating winget PR creation.


## Scoop (Windows)

Scoop is popular among Windows power users. Manifests are JSON files in a bucket repository.

```json
{
  "version": "1.2.3",
  "description": "A CLI tool for managing widgets",
  "homepage": "https://github.com/myorg/mytool",
  "license": "MIT",
  "architecture": {
    "64bit": {
      "url": "https://github.com/myorg/mytool/releases/download/v1.2.3/mytool-1.2.3-win-x64.zip",
      "hash": "abc123..."
    },
    "arm64": {
      "url": "https://github.com/myorg/mytool/releases/download/v1.2.3/mytool-1.2.3-win-arm64.zip",
      "hash": "def456..."
    }
  },
  "bin": "mytool.exe",
  "checkver": {
    "github": "https://github.com/myorg/mytool"
  },
  "autoupdate": {
    "architecture": {
      "64bit": {
        "url": "https://github.com/myorg/mytool/releases/download/v$version/mytool-$version-win-x64.zip"
      },
      "arm64": {
        "url": "https://github.com/myorg/mytool/releases/download/v$version/mytool-$version-win-arm64.zip"
      }
    }
  }
}
```

Host in a GitHub repo named `scoop-mytool` with a `bucket/` directory. Users install with:

```powershell
scoop bucket add myorg https://github.com/myorg/scoop-mytool
scoop install mytool
```


## Chocolatey

### Package Structure

```
mytool/
  mytool.nuspec
  tools/
    chocolateyInstall.ps1
    LICENSE.txt
```

### mytool.nuspec

```xml
<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://schemas.xmldata.org/2004/07/nuspec">
  <metadata>
    <id>mytool</id>
    <version>1.2.3</version>
    <title>MyTool</title>
    <authors>My Org</authors>
    <projectUrl>https://github.com/myorg/mytool</projectUrl>
    <license type="expression">MIT</license>
    <description>A CLI tool for managing widgets.</description>
    <tags>cli dotnet tools</tags>
  </metadata>
</package>
```

### tools/chocolateyInstall.ps1

```powershell
$ErrorActionPreference = 'Stop'

$packageArgs = @{
  packageName    = 'mytool'
  url64bit       = 'https://github.com/myorg/mytool/releases/download/v1.2.3/mytool-1.2.3-win-x64.zip'
  checksum64     = 'ABC123...'
  checksumType64 = 'sha256'
  unzipLocation  = "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)"
}

Install-ChocolateyZipPackage @packageArgs
```


## dotnet tool (Global and Local)

`dotnet tool` is the simplest distribution for .NET developers. Tools are distributed as NuGet packages.

### Project Configuration for Tool Packaging

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net8.0</TargetFramework>

    <!-- Tool packaging properties -->
    <PackAsTool>true</PackAsTool>
    <ToolCommandName>mytool</ToolCommandName>
    <PackageId>MyOrg.MyTool</PackageId>
    <Version>1.2.3</Version>
    <Description>A CLI tool for managing widgets</Description>
    <Authors>My Org</Authors>
    <PackageLicenseExpression>MIT</PackageLicenseExpression>
    <PackageProjectUrl>https://github.com/myorg/mytool</PackageProjectUrl>
    <PackageReadmeFile>README.md</PackageReadmeFile>
  </PropertyGroup>

  <ItemGroup>
    <None Include="../../README.md" Pack="true" PackagePath="/" />
  </ItemGroup>
</Project>
```

### Building and Publishing

```bash
# Pack the tool
dotnet pack -c Release

# Publish to NuGet.org
dotnet nuget push bin/Release/MyOrg.MyTool.1.2.3.nupkg \
  --source https://api.nuget.org/v3/index.json \
  --api-key "$NUGET_API_KEY"
```

### Installing dotnet Tools

```bash
# Global tool (available system-wide)
dotnet tool install -g MyOrg.MyTool

# Local tool (per-project, tracked in .config/dotnet-tools.json)
dotnet new tool-manifest  # first time only
dotnet tool install MyOrg.MyTool

# Update
dotnet tool update -g MyOrg.MyTool

# Run local tool
dotnet tool run mytool
# or just:
dotnet mytool
```

### Global vs Local Tools

| Aspect | Global Tool | Local Tool |
|--------|------------|------------|
| Scope | System-wide (per user) | Per-project directory |
| Install location | `~/.dotnet/tools` | `.config/dotnet-tools.json` |
| Version management | Manual update | Tracked in source control |
| CI/CD | Must install before use | `dotnet tool restore` restores all |
| Best for | Personal productivity tools | Project-specific build tools |


## Agent Gotchas

1. **Do not set RuntimeIdentifier in the .csproj for multi-platform CLI tools.** Hardcoding a RID in the project file prevents building for other platforms. Pass `-r <rid>` at publish time instead.
2. **Do not use PublishSingleFile with PublishAot.** Native AOT output is inherently single-file. Setting both is redundant and may cause confusing build warnings.
3. **Do not skip InvariantGlobalization for size-sensitive CLI tools.** Globalization data adds ~25 MB to AOT binaries. Most CLI tools that do not format locale-specific dates/currencies should enable `InvariantGlobalization=true`.
4. **Do not hardcode SHA-256 hashes in package manifests.** Generate checksums from actual release artifacts, not placeholder values. All package managers validate checksums against downloaded files.
5. **Do not use `InstallerType: exe` for portable CLI tools in winget.** Use `InstallerType: zip` with `NestedInstallerType: portable` for standalone executables. The `exe` type implies an installer with silent flags.
6. **Do not forget `PackAsTool` for dotnet tool projects.** Without `<PackAsTool>true</PackAsTool>`, `dotnet pack` produces a library package, not an installable tool.


## References

- [.NET application publishing overview](https://learn.microsoft.com/en-us/dotnet/core/deploying/)
- [Single-file deployment](https://learn.microsoft.com/en-us/dotnet/core/deploying/single-file/overview)
- [Native AOT deployment](https://learn.microsoft.com/en-us/dotnet/core/deploying/native-aot/)
- [Runtime Identifier (RID) catalog](https://learn.microsoft.com/en-us/dotnet/core/rid-catalog)
- [Trimming options](https://learn.microsoft.com/en-us/dotnet/core/deploying/trimming/trimming-options)
- [Homebrew Formula Cookbook](https://docs.brew.sh/Formula-Cookbook)
- [Homebrew Taps](https://docs.brew.sh/Taps)
- [dpkg-deb manual](https://man7.org/linux/man-pages/man1/dpkg-deb.1.html)
- [winget manifest schema](https://learn.microsoft.com/en-us/windows/package-manager/package/manifest)
- [Scoop Wiki](https://github.com/ScoopInstaller/Scoop/wiki)
- [Chocolatey package creation](https://docs.chocolatey.org/en-us/create/create-packages)
- [.NET tool packaging](https://learn.microsoft.com/en-us/dotnet/core/tools/global-tools-how-to-create)
