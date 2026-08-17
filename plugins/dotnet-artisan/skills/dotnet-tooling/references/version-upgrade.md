# Version Upgrade

Comprehensive guide for .NET version upgrade planning and execution. This skill consumes the structured output from `references/version-detection.md` (current TFM, SDK version, preview flags) and provides actionable upgrade guidance based on three defined upgrade lanes. Covers TFM migration, package updates, breaking change detection, deprecated API replacement, and test validation.

## Upgrade Lanes

Select the appropriate upgrade lane based on project requirements and ecosystem constraints.

| Lane | Path | Use Case | Risk Level |
|------|------|----------|------------|
| **Production (default)** | net8.0 -> net10.0 | LTS-to-LTS, recommended for most apps | Low -- both endpoints are LTS with long support windows |
| **Staged production** | net8.0 -> net9.0 -> net10.0 | When ecosystem dependencies require incremental migration | Medium -- intermediate STS version has shorter support |
| **Experimental** | net10.0 -> net11.0 (preview) | Non-production exploration of upcoming features | High -- preview APIs may change or be removed |

### Lane Selection Decision Flow

1. Are all your NuGet dependencies available on the target LTS? **Yes** -> Production lane (direct LTS-to-LTS).
2. Do any dependencies require an intermediate version? **Yes** -> Staged production lane.
3. Are you exploring preview features for R&D or proof-of-concept? **Yes** -> Experimental lane.


## Production Lane: LTS-to-LTS (net8.0 -> net10.0)

The recommended default upgrade path. Both .NET 8 and .NET 10 are Long-Term Support releases, providing a stable migration with well-documented breaking changes.

### Upgrade Checklist

**Step 1: Update TFM in project files**

```xml
<!-- Before -->
<PropertyGroup>
  <TargetFramework>net8.0</TargetFramework>
</PropertyGroup>

<!-- After -->
<PropertyGroup>
  <TargetFramework>net10.0</TargetFramework>
</PropertyGroup>
```

For solutions with shared properties:

```xml
<!-- Directory.Build.props -->
<PropertyGroup>
  <TargetFramework>net10.0</TargetFramework>
</PropertyGroup>
```

**Step 2: Update global.json SDK version**

```json
{
  "sdk": {
    "version": "10.0.100",
    "rollForward": "latestFeature"
  }
}
```

**Step 3: Update NuGet packages**

Use `dotnet-outdated` to detect stale packages and identify which packages need updates for TFM compatibility:

```bash
# Install dotnet-outdated as a global tool
dotnet tool install -g dotnet-outdated-tool

# Check for outdated packages across the solution
dotnet outdated

# Check a specific project
dotnet outdated MyProject/MyProject.csproj

# Auto-upgrade to latest stable versions
dotnet outdated --upgrade

# Upgrade only to the latest minor/patch (safer)
dotnet outdated --upgrade --version-lock major
```

For ASP.NET Core shared framework packages, update version references to match the target TFM:

```xml
<ItemGroup>
  <!-- Match package version to TFM major version -->
  <PackageReference Include="Microsoft.AspNetCore.Mvc.Testing" Version="10.*" />
  <PackageReference Include="Microsoft.Extensions.Hosting" Version="10.*" />
</ItemGroup>
```

**Step 4: Review breaking changes**

```bash
# Build to surface warnings and errors
dotnet build --warnaserror

# Run analyzers for deprecated API usage
dotnet build /p:TreatWarningsAsErrors=true
```

Review the official breaking change lists:
- [.NET 9 Breaking Changes](https://learn.microsoft.com/en-us/dotnet/core/compatibility/9.0)
- [.NET 10 Breaking Changes](https://learn.microsoft.com/en-us/dotnet/core/compatibility/10.0)

**Step 5: Replace deprecated APIs**

Common replacements when moving from net8.0 to net10.0:

| Deprecated | Replacement | Notes |
|-----------|-------------|-------|
| `BinaryFormatter` | `System.Text.Json` or `MessagePack` | `BinaryFormatter` throws `PlatformNotSupportedException` starting in net9.0 |
| `Thread.Abort()` | Cooperative cancellation via `CancellationToken` | `Thread.Abort()` throws `PlatformNotSupportedException` |
| `WebRequest` / `HttpWebRequest` | `HttpClient` via `IHttpClientFactory` | Obsolete (`SYSLIB0014`), migrate to `HttpClient` |

**Recommended modernizations** (not deprecated, but improve performance and AOT readiness):

| Pattern | Improvement | Notes |
|---------|-------------|-------|
| `Regex` without source gen | `[GeneratedRegex]` attribute | Source-generated regex is faster and AOT-compatible |

**Step 6: Run tests and validate**

```bash
# Run full test suite
dotnet test --configuration Release

# Enable trim/AOT analyzers to surface compatibility warnings without publishing
dotnet build --configuration Release /p:EnableTrimAnalyzer=true /p:EnableAotAnalyzer=true
```

### .NET Upgrade Assistant

The .NET Upgrade Assistant automates parts of the migration process. It is most useful for large solutions with many projects.

```bash
# Install as a global tool
dotnet tool install -g upgrade-assistant

# Analyze a project (non-destructive, reports recommendations)
upgrade-assistant analyze MyProject/MyProject.csproj

# Perform the upgrade (modifies files)
upgrade-assistant upgrade MyProject/MyProject.csproj
```

**When to use Upgrade Assistant:**
- Large solutions with many projects and complex dependency graphs
- Legacy .NET Framework-to-modern-.NET migrations
- When you need a comprehensive dependency analysis before committing to an upgrade

**Limitations:**
- May not handle all breaking changes -- manual review is still required
- Custom MSBuild extensions and third-party build tooling may need manual adjustment
- Does not update runtime behavior differences -- test coverage is essential
- Not needed for small projects with few dependencies (manual TFM update is simpler)


## Staged Production Lane: net8.0 -> net9.0 -> net10.0

Use the staged lane when direct LTS-to-LTS migration is blocked by ecosystem constraints. Staging through .NET 9 (STS) provides an incremental migration path.

### When to Stage Through .NET 9

- **Third-party package compatibility:** A critical dependency only supports net9.0 (not yet net10.0) and you need to upgrade away from net8.0 now.
- **Large breaking change surface:** The combined breaking changes from net8.0 to net10.0 are too many to address at once; incremental steps reduce risk.
- **Incremental validation:** You want to validate behavior changes at each step before proceeding.

### .NET 9 Context

.NET 9 is a Standard Term Support (STS) release:
- **GA:** November 2024
- **End of support:** May 2026 (18 months from GA)
- **C# version:** C# 13

Because .NET 9 is approaching end of support, do not stop at net9.0. Plan the second hop (net9.0 -> net10.0) before starting the first.

### Staged Upgrade Checklist

**Hop 1: net8.0 -> net9.0**

1. Update TFM to `net9.0` in .csproj / `Directory.Build.props`
2. Update `global.json` to SDK `9.0.xxx`
3. Run `dotnet outdated --upgrade` for package updates
4. Review [.NET 9 breaking changes](https://learn.microsoft.com/en-us/dotnet/core/compatibility/9.0)
5. Replace deprecated APIs flagged by `SYSLIB` diagnostics and `CS0618` warnings (e.g., `BinaryFormatter` -> `System.Text.Json`)
6. Run `dotnet test --configuration Release` to validate
7. Deploy to staging environment, validate in production with monitoring

**Hop 2: net9.0 -> net10.0**

1. Update TFM to `net10.0` in .csproj / `Directory.Build.props`
2. Update `global.json` to SDK `10.0.xxx`
3. Run `dotnet outdated --upgrade` again
4. Review [.NET 10 breaking changes](https://learn.microsoft.com/en-us/dotnet/core/compatibility/10.0)
5. Replace any additional deprecated APIs introduced between net9.0 and net10.0
6. Run `dotnet test --configuration Release` to validate
7. Deploy to staging, remove any net9.0-specific workarounds

**Timeline guidance:** Complete both hops within the .NET 9 support window (before May 2026). Running production workloads on an unsupported STS release exposes you to unpatched security vulnerabilities.


## Experimental Lane: net10.0 -> net11.0 (Preview)

For non-production exploration of upcoming features. .NET 11 is currently in preview and its APIs may change or be removed before GA.

### Guardrails

- **Non-production only.** Do not deploy preview-targeted code to production environments.
- **Separate branch or project.** Isolate experimental work from production codebases.
- **Pin the preview SDK.** Use `global.json` to lock the specific preview SDK version to avoid silent behavior changes between previews.
- **Expect breaking changes between previews.** APIs marked `[RequiresPreviewFeatures]` can change shape between preview releases.

### Enabling Preview Features

**Step 1: Install the preview SDK**

```bash
# Verify installed SDKs
dotnet --list-sdks

# Example: 11.0.100-preview.1.xxxxx should appear
```

**Step 2: Pin to preview SDK in global.json**

```json
{
  "sdk": {
    "version": "11.0.100-preview.1.25120.13",
    "rollForward": "disable"
  }
}
```

Use `"rollForward": "disable"` to prevent automatic SDK version advancement between previews.

**Step 3: Set TFM and enable preview features**

```xml
<PropertyGroup>
  <TargetFramework>net11.0</TargetFramework>
  <LangVersion>preview</LangVersion>
  <EnablePreviewFeatures>true</EnablePreviewFeatures>
</PropertyGroup>
```

**Step 4: Enable runtime-async (optional)**

Runtime-async moves async/await from compiler-generated state machines to runtime-level execution, reducing allocations and improving performance for async-heavy workloads:

```xml
<PropertyGroup>
  <TargetFramework>net11.0</TargetFramework>
  <LangVersion>preview</LangVersion>
  <EnablePreviewFeatures>true</EnablePreviewFeatures>
  <Features>$(Features);runtime-async=on</Features>
</PropertyGroup>
```

Runtime-async requires both `EnablePreviewFeatures` and the `Features` flag. It is experimental and may change significantly before GA.

### Experimental Upgrade Checklist

1. Install the .NET 11 preview SDK and pin it in `global.json` with `"rollForward": "disable"`
2. Update TFM to `net11.0` and set `<LangVersion>preview</LangVersion>` + `<EnablePreviewFeatures>true</EnablePreviewFeatures>`
3. Run `dotnet outdated` to check package compatibility with the preview TFM
4. Build and review warnings -- preview SDKs may flag new `SYSLIB` diagnostics or `CA2252` (preview feature usage)
5. Replace any deprecated APIs surfaced by the new analyzer version
6. Run `dotnet test` to validate -- expect some third-party packages to lack preview TFM support
7. Document findings for future production upgrade planning

### What to Explore in .NET 11 Preview

| Feature | Area | Notes |
|---------|------|-------|
| Runtime-async | Performance | Async/await at runtime level; requires opt-in |
| Zstandard compression | I/O | `System.IO.Compression.Zstandard`; 2-7x faster than Brotli |
| BFloat16 | Numerics | `System.Numerics.BFloat16` for AI/ML workloads |
| Happy Eyeballs | Networking | `ConnectAlgorithm.Parallel` for dual-stack IPv4/IPv6 |
| C# 15 preview features | Language | Collection expression arguments (`with()` syntax) |
| CoreCLR on WASM | Runtime | Experimental alternative to Mono for Blazor WASM |


## Breaking Change Detection

Systematic approaches to identify and resolve breaking changes during any upgrade.

### Build-Time Detection

```bash
# Clean build to surface all warnings (not just incremental)
dotnet clean && dotnet build --no-incremental

# Treat warnings as errors to catch deprecation notices
dotnet build /p:TreatWarningsAsErrors=true

# List specific obsolete API warnings
dotnet build 2>&1 | grep -E "CS0618|CS0612"
```

- `CS0618`: Use of an `[Obsolete]` member with a message
- `CS0612`: Use of an `[Obsolete]` member without a message
- `CS8073`: Expression always evaluates to the same value (type behavior change)

### Analyzer Diagnostics

Enable .NET analyzers to detect additional issues:

```xml
<PropertyGroup>
  <EnableNETAnalyzers>true</EnableNETAnalyzers>
  <AnalysisLevel>latest-recommended</AnalysisLevel>
</PropertyGroup>
```

Key analyzer categories for upgrades:
- `CA1422`: Platform compatibility (API removed on target platform)
- `CA1416`: Platform-specific API usage without guards
- `CA2252`: Opting into preview features
- `SYSLIB0XXX`: Obsolete system API diagnostics (e.g., `SYSLIB0011` for BinaryFormatter)

### API Diff Tools

For library authors, use API compatibility tools to validate public surface changes:

```bash
# Package validation detects breaking changes against a baseline
dotnet pack /p:EnablePackageValidation=true /p:PackageValidationBaselineVersion=1.0.0

# Standalone API comparison
dotnet tool install -g Microsoft.DotNet.ApiCompat.Tool
apicompat --left-assembly bin/Release/net8.0/MyLib.dll \
          --right-assembly bin/Release/net10.0/MyLib.dll
```

See `references/multi-targeting.md` for detailed API compatibility validation workflows including suppression files and CI integration.


## Package Update Strategies

### dotnet-outdated

The `dotnet-outdated` tool provides a comprehensive view of package staleness:

```bash
# Install
dotnet tool install -g dotnet-outdated-tool

# Show all outdated packages with current vs latest versions
dotnet outdated

# Lock major version, show only minor/patch updates (safer incremental upgrades)
dotnet outdated --version-lock major

# Auto-upgrade with version locking to avoid unexpected major bumps
dotnet outdated --upgrade --version-lock major

# Output as JSON for CI integration
dotnet outdated --output-format json
```

### Central Package Management

For solutions using Central Package Management (`Directory.Packages.props`), update versions centrally:

```xml
<!-- Directory.Packages.props -->
<Project>
  <PropertyGroup>
    <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
  </PropertyGroup>

  <ItemGroup>
    <!-- Update all Microsoft.Extensions.* packages to match TFM -->
    <PackageVersion Include="Microsoft.Extensions.Hosting" Version="10.*" />
    <PackageVersion Include="Microsoft.Extensions.Http" Version="10.*" />
    <PackageVersion Include="Microsoft.Extensions.Logging" Version="10.*" />
    <!-- Third-party packages: check compatibility before upgrading -->
    <PackageVersion Include="Serilog" Version="4.*" />
  </ItemGroup>
</Project>
```

`Directory.Packages.props` resolves hierarchically upward from the project directory. In monorepo structures, verify that nested `Directory.Packages.props` files are not shadowing the root-level configuration.

### ASP.NET Core Shared Framework Packages

ASP.NET Core shared framework packages must align their major version with the target TFM. Two valid approaches:

```xml
<ItemGroup>
  <!-- Option A: floating version — auto-resolves latest patch, convenient for upgrades -->
  <PackageReference Include="Microsoft.AspNetCore.Mvc.Testing" Version="10.*" />

  <!-- Option B: pinned version — deterministic CI builds, update explicitly -->
  <PackageReference Include="Microsoft.AspNetCore.Mvc.Testing" Version="10.0.1" />
</ItemGroup>
```

Pinned versions are recommended for deterministic CI; floating versions are useful during exploratory upgrades. Either way, the **major version must match the TFM** (e.g., `10.x` for `net10.0`).


## Agent Gotchas

1. **Do not skip .NET 9 without validating ecosystem compatibility.** While LTS-to-LTS (net8.0 -> net10.0) is the recommended default, some third-party packages may only support net9.0 as an intermediate step. Check package compatibility before selecting a lane.

2. **Do not run production workloads on preview SDKs.** .NET 11 preview APIs are unstable and will change between preview releases. Isolate experimental work in separate branches or projects with pinned preview SDK versions.

3. **Do not assume .NET 9 STS has 12-month support.** STS lifecycle is 18 months from GA. .NET 9 GA was November 2024, so end-of-support is May 2026. Always calculate from actual GA date, not release year.

4. **Ensure ASP.NET shared framework package major versions match the TFM.** Packages like `Microsoft.AspNetCore.Mvc.Testing` must have their major version aligned with the project TFM (e.g., `10.x` for `net10.0`). Pin exact versions for deterministic CI or float with wildcards (e.g., `10.*`) during exploratory upgrades.

5. **Do not re-implement TFM detection.** This skill consumes the structured output from `references/version-detection.md`. Never parse `.csproj` files to determine the current version -- use the detection skill's output (TFM, C# version, SDK version, warnings).

6. **Do not treat `dotnet-outdated --upgrade` as a complete solution.** It updates package versions but does not handle breaking API changes within those packages. Always build, test, and review changelogs after upgrading packages.

7. **Do not use `"rollForward": "latestMajor"` with preview SDKs.** This can silently advance to a different preview version with breaking changes. Use `"rollForward": "disable"` for preview SDKs to maintain reproducible builds.

8. **Do not forget `Directory.Packages.props` hierarchy.** In monorepo structures, nested `Directory.Packages.props` files shadow parent-level configurations. When upgrading, search upward from the project directory to find all `Directory.Packages.props` files that may affect package resolution.

9. **Do not ignore `SYSLIB` diagnostic codes during upgrade.** These system-level obsolete warnings (e.g., `SYSLIB0011` for BinaryFormatter, `SYSLIB0014` for WebRequest) indicate APIs that will throw at runtime on newer TFMs, not just compile-time warnings.


## Prerequisites

- .NET SDK for the target TFM installed (e.g., .NET 10 SDK for net10.0 upgrade)
- `dotnet-outdated-tool` (for package staleness detection): `dotnet tool install -g dotnet-outdated-tool`
- `upgrade-assistant` (optional, for automated migration): `dotnet tool install -g upgrade-assistant`
- Output from `references/version-detection.md` (current TFM, SDK version, preview flags)


## References

> **Last verified: 2026-02-12**

- [.NET Support Policy and Lifecycle](https://dotnet.microsoft.com/en-us/platform/support/policy)
- [.NET 9 Breaking Changes](https://learn.microsoft.com/en-us/dotnet/core/compatibility/9.0)
- [.NET 10 Breaking Changes](https://learn.microsoft.com/en-us/dotnet/core/compatibility/10.0)
- [.NET Upgrade Assistant](https://dotnet.microsoft.com/en-us/platform/upgrade-assistant)
- [dotnet-outdated Tool](https://github.com/dotnet-outdated/dotnet-outdated)
- [Central Package Management](https://learn.microsoft.com/en-us/nuget/consume-packages/central-package-management)
- [Target Framework Monikers](https://learn.microsoft.com/en-us/dotnet/standard/frameworks)
- [.NET Analyzers Overview](https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/overview)
- [Package Validation](https://learn.microsoft.com/en-us/dotnet/fundamentals/package-validation/overview)
