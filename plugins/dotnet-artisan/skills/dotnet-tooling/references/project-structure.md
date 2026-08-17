# Project Structure

Reference guide for modern .NET project structure and solution layout. Use when creating new solutions, reviewing existing structure, or recommending improvements.

**Prerequisites:** Run `references/version-detection.md` first to determine TFM and SDK version — this affects which features are available (e.g., .slnx requires .NET 9+ SDK).

## Recommended Solution Layout

```
MyApp/
├── .editorconfig
├── .gitignore
├── global.json
├── nuget.config
├── Directory.Build.props
├── Directory.Build.targets
├── Directory.Packages.props
├── MyApp.slnx                       # .NET 9+ SDK / VS 17.13+
├── src/
│   ├── MyApp.Core/
│   │   └── MyApp.Core.csproj
│   ├── MyApp.Api/
│   │   ├── MyApp.Api.csproj
│   │   ├── Program.cs
│   │   └── appsettings.json
│   └── MyApp.Infrastructure/
│       └── MyApp.Infrastructure.csproj
└── tests/
    ├── MyApp.UnitTests/
    │   └── MyApp.UnitTests.csproj
    └── MyApp.IntegrationTests/
        └── MyApp.IntegrationTests.csproj
```

Key principles:
- Separate `src/` and `tests/` directories
- One project per concern (Core/Domain, Infrastructure, API/Host)
- Solution file at the repo root
- All shared build configuration at the repo root


## Solution File Formats

### .slnx (Modern — .NET 9+)

The XML-based solution format is human-readable and diff-friendly. Requires .NET 9+ SDK or Visual Studio 17.13+.

```xml
<Solution>
  <Folder Name="/src/">
    <Project Path="src/MyApp.Core/MyApp.Core.csproj" />
    <Project Path="src/MyApp.Api/MyApp.Api.csproj" />
    <Project Path="src/MyApp.Infrastructure/MyApp.Infrastructure.csproj" />
  </Folder>
  <Folder Name="/tests/">
    <Project Path="tests/MyApp.UnitTests/MyApp.UnitTests.csproj" />
    <Project Path="tests/MyApp.IntegrationTests/MyApp.IntegrationTests.csproj" />
  </Folder>
</Solution>
```

Convert existing `.sln` to `.slnx`:

```bash
dotnet sln MyApp.sln migrate
```

### .sln (Legacy — All Versions)

The traditional format remains the fallback for older tooling, CI agents, and third-party integrations that don't support `.slnx` yet. Keep `.sln` alongside `.slnx` during the transition period if needed.

```bash
dotnet new sln -n MyApp
dotnet sln add src/**/*.csproj
dotnet sln add tests/**/*.csproj
```


## Directory.Build.props

Shared MSBuild properties applied to all projects in the directory subtree. Place at the repo root.

```xml
<Project>
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <LangVersion>14</LangVersion>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <TreatWarningsAsErrors>true</TreatWarningsAsErrors>
    <EnforceCodeStyleInBuild>true</EnforceCodeStyleInBuild>
    <AnalysisLevel>latest-all</AnalysisLevel>
  </PropertyGroup>
</Project>
```

### Nested Directory.Build.props

Inner files do **not** automatically import outer files. To chain them:

```xml
<!-- src/Directory.Build.props -->
<Project>
  <Import Project="$([MSBuild]::GetPathOfFileAbove('Directory.Build.props', '$(MSBuildThisFileDirectory)../'))" />
  <PropertyGroup>
    <!-- src-specific settings -->
  </PropertyGroup>
</Project>
```

Common pattern: separate props for src vs tests:

```
repo/
├── Directory.Build.props              # Shared: LangVersion, Nullable, ImplicitUsings
├── src/
│   └── Directory.Build.props          # Imports parent + adds TreatWarningsAsErrors
└── tests/
    └── Directory.Build.props          # Imports parent + sets IsTestProject
```


## Directory.Build.targets

Imported **after** project evaluation. Use for:
- Shared analyzer package references
- Custom build targets
- Conditional logic based on project type

```xml
<Project>
  <!-- Apply analyzers to all projects -->
  <ItemGroup>
    <PackageReference Include="Meziantou.Analyzer" PrivateAssets="all" />
    <PackageReference Include="Microsoft.CodeAnalysis.BannedApiAnalyzers" PrivateAssets="all" />
  </ItemGroup>
</Project>
```


## Central Package Management (CPM)

CPM centralizes all NuGet package versions in `Directory.Packages.props` at the repo root. Individual `.csproj` files reference packages **without** a `Version` attribute.

### Directory.Packages.props

```xml
<Project>
  <PropertyGroup>
    <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
    <CentralPackageTransitivePinningEnabled>true</CentralPackageTransitivePinningEnabled>
  </PropertyGroup>
  <ItemGroup>
    <!-- Shared dependencies -->
    <PackageVersion Include="Microsoft.Extensions.Logging" Version="10.0.0" />
    <PackageVersion Include="System.Text.Json" Version="10.0.0" />
  </ItemGroup>
  <ItemGroup>
    <!-- Test dependencies -->
    <PackageVersion Include="xunit.v3" Version="3.2.2" />
    <PackageVersion Include="xunit.runner.visualstudio" Version="3.1.5" />
    <PackageVersion Include="coverlet.collector" Version="8.0.0" />
    <PackageVersion Include="Microsoft.NET.Test.Sdk" Version="18.0.1" />
  </ItemGroup>
</Project>
```

### Project File with CPM

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <ItemGroup>
    <!-- No Version attribute — managed centrally -->
    <PackageReference Include="Microsoft.Extensions.Logging" />
  </ItemGroup>
</Project>
```

### Version Overrides

When a specific project needs a different version (rare), use `VersionOverride`:

```xml
<PackageReference Include="Newtonsoft.Json" VersionOverride="13.0.3" />
```

Flag version overrides during code review — they defeat the purpose of CPM.


## .editorconfig

Place at the repo root to enforce consistent code style across all editors and the build.

```ini
root = true

[*]
indent_style = space
indent_size = 4
end_of_line = lf
charset = utf-8
trim_trailing_whitespace = true
insert_final_newline = true

[*.{csproj,props,targets,xml,json,yml,yaml}]
indent_size = 2

[*.cs]
# Namespace declarations
csharp_style_namespace_declarations = file_scoped:warning

# Braces
csharp_prefer_braces = true:warning

# var preferences
csharp_style_var_for_built_in_types = true:suggestion
csharp_style_var_when_type_is_apparent = true:suggestion
csharp_style_var_elsewhere = true:suggestion

# Access modifiers
dotnet_style_require_accessibility_modifiers = always:warning

# Pattern matching
csharp_style_prefer_pattern_matching = true:suggestion
csharp_style_prefer_switch_expression = true:suggestion

# Null checking
csharp_style_prefer_null_check_over_type_check = true:suggestion
dotnet_style_prefer_is_null_check_over_reference_equality_method = true:warning

# Expression-level preferences
csharp_style_expression_bodied_methods = when_on_single_line:suggestion
csharp_style_expression_bodied_properties = true:suggestion

# Using directives
csharp_using_directive_placement = outside_namespace:warning
dotnet_sort_system_directives_first = true

# Naming conventions
dotnet_naming_rule.private_fields_should_be_camel_case.symbols = private_fields
dotnet_naming_rule.private_fields_should_be_camel_case.style = camel_case_underscore
dotnet_naming_rule.private_fields_should_be_camel_case.severity = warning
dotnet_naming_symbols.private_fields.applicable_kinds = field
dotnet_naming_symbols.private_fields.applicable_accessibilities = private
dotnet_naming_style.camel_case_underscore.required_prefix = _
dotnet_naming_style.camel_case_underscore.capitalization = camel_case
```

See `references/add-analyzers.md` for full analyzer rule configuration.


## global.json

Pin the SDK version for reproducible builds:

```json
{
  "sdk": {
    "version": "10.0.100",
    "rollForward": "latestPatch"
  }
}
```

Roll-forward policies:
- `latestPatch` — allow patch updates only (recommended for CI)
- `latestFeature` — allow feature-band updates within the major version
- `latestMajor` — use whatever is installed (development convenience, not for CI)
- `disable` — exact version only


## nuget.config

Configure package sources and security:

```xml
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <clear />
    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" />
  </packageSources>
  <packageSourceMapping>
    <packageSource key="nuget.org">
      <package pattern="*" />
    </packageSource>
  </packageSourceMapping>
</configuration>
```

The `<clear />` + explicit sources + `<packageSourceMapping>` pattern prevents supply-chain attacks by ensuring packages only come from expected sources.

For private feeds, map internal package prefixes exclusively to the private source:

```xml
<packageSources>
  <clear />
  <add key="nuget.org" value="https://api.nuget.org/v3/index.json" />
  <add key="internal" value="https://pkgs.dev.azure.com/myorg/_packaging/myfeed/nuget/v3/index.json" />
</packageSources>
<packageSourceMapping>
  <packageSource key="nuget.org">
    <package pattern="*" />
  </packageSource>
  <packageSource key="internal">
    <package pattern="MyCompany.*" />
  </packageSource>
</packageSourceMapping>
```

NuGet uses **most-specific-pattern-wins** precedence: `MyCompany.Foo` matches `MyCompany.*` (internal) over `*` (nuget.org), so internal packages restore exclusively from the private feed. This prevents dependency confusion attacks — an attacker cannot squat `MyCompany.Foo` on nuget.org because NuGet will never look there for packages matching `MyCompany.*`.

**Do not** map the same prefix to multiple sources unless you trust both — that defeats the protection.


## NuGet Audit

.NET 9+ enables `NuGetAudit` by default, which checks for known vulnerabilities during restore. Configure the severity threshold:

```xml
<!-- In Directory.Build.props -->
<PropertyGroup>
  <NuGetAudit>true</NuGetAudit>
  <NuGetAuditLevel>low</NuGetAuditLevel>
  <NuGetAuditMode>all</NuGetAuditMode>  <!-- audit direct + transitive -->
</PropertyGroup>
```


## Lock Files

Enable deterministic restores with lock files:

```xml
<!-- In Directory.Build.props -->
<PropertyGroup>
  <RestorePackagesWithLockFile>true</RestorePackagesWithLockFile>
</PropertyGroup>
```

This generates `packages.lock.json` per project. Commit these files. In CI, restore with `--locked-mode`:

```bash
dotnet restore --locked-mode
```


## SourceLink and Deterministic Builds

For libraries published to NuGet:

```xml
<!-- In Directory.Build.props -->
<PropertyGroup>
  <PublishRepositoryUrl>true</PublishRepositoryUrl>
  <EmbedUntrackedSources>true</EmbedUntrackedSources>
  <DebugType>embedded</DebugType>
  <ContinuousIntegrationBuild Condition="'$(CI)' == 'true'">true</ContinuousIntegrationBuild>
</PropertyGroup>
<ItemGroup>
  <PackageReference Include="Microsoft.SourceLink.GitHub" PrivateAssets="all" />
</ItemGroup>
```

Key properties:
- `PublishRepositoryUrl` — includes the repo URL in the NuGet package
- `EmbedUntrackedSources` — embeds generated source files
- `DebugType=embedded` — PDB embedded in the assembly (no separate symbol package needed)
- `ContinuousIntegrationBuild` — enables deterministic paths (only in CI to avoid breaking local debugging)


## References

- [.NET Library Design Guidance](https://learn.microsoft.com/en-us/dotnet/standard/library-guidance/)
- [Central Package Management](https://learn.microsoft.com/en-us/nuget/consume-packages/central-package-management)
- [.slnx Format](https://learn.microsoft.com/en-us/visualstudio/ide/reference/solution-file)
- [Directory.Build.props](https://learn.microsoft.com/en-us/visualstudio/msbuild/customize-your-build)
- [SourceLink](https://learn.microsoft.com/en-us/dotnet/standard/library-guidance/sourcelink)
- [NuGet Audit](https://learn.microsoft.com/en-us/nuget/concepts/auditing-packages)
