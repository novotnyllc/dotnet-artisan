# Csproj Reading

Teaches agents to read and safely modify SDK-style .csproj files. Covers project structure, PropertyGroup conventions, ItemGroup patterns, conditional expressions, Directory.Build.props/.targets, and central package management (Directory.Packages.props). Each subsection provides annotated XML examples and common modification patterns.

## Prerequisites

.NET 8.0+ SDK. SDK-style projects only (legacy .csproj format is not covered). MSBuild (included with .NET SDK).

Cross-references: `references/project-structure.md` for project organization and SDK selection, `references/build-analysis.md` for interpreting build errors from project misconfiguration, [skill:dotnet-api] for common project structure mistakes agents make.


## Subsection 1: SDK-Style Project Structure

SDK-style projects use a `<Project Sdk="...">` declaration that imports hundreds of default targets and props. Understanding what the SDK provides implicitly is essential to avoid redundant or conflicting declarations.

### Annotated XML Example

```xml
<!-- The Sdk attribute imports default props at the top and targets at the bottom -->
<!-- This single line replaces dozens of Import statements from legacy .csproj -->
<Project Sdk="Microsoft.NET.Sdk">
  <!--
    Common SDK values:
    - Microsoft.NET.Sdk           -> Console apps, libraries, class libraries
    - Microsoft.NET.Sdk.Web       -> ASP.NET Core (adds Kestrel, MVC, Razor, shared framework)
    - Microsoft.NET.Sdk.Worker    -> Background worker services
    - Microsoft.NET.Sdk.Razor     -> Razor class libraries
    - Microsoft.NET.Sdk.BlazorWebAssembly -> Blazor WASM apps
  -->

  <!-- SDK-style projects auto-include all *.cs files via default globs -->
  <!-- No need to list individual .cs files in <Compile Include="..."> -->
  <!-- Default globs: **/*.cs for Compile, **/*.resx for EmbeddedResource -->

  <PropertyGroup>
    <TargetFramework>net9.0</TargetFramework>
  </PropertyGroup>

</Project>
```

### Common Modification Patterns

**Changing SDK type** -- when an agent creates a web project with the wrong SDK:

```xml
<!-- WRONG: console SDK for a web project -->
<Project Sdk="Microsoft.NET.Sdk">

<!-- CORRECT: Web SDK includes ASP.NET Core shared framework -->
<Project Sdk="Microsoft.NET.Sdk.Web">
```

**Disabling default globs** -- rare, but needed when migrating from legacy format or when explicit file control is required:

```xml
<PropertyGroup>
  <!-- Disable automatic inclusion of *.cs files -->
  <EnableDefaultCompileItems>false</EnableDefaultCompileItems>
  <!-- Disable all default items (Compile, EmbeddedResource, Content) -->
  <EnableDefaultItems>false</EnableDefaultItems>
</PropertyGroup>
```

**Verifying which SDK a project uses:**

```bash
# Check the first line of the .csproj for the Sdk attribute
head -1 src/MyApp/MyApp.csproj
# Output: <Project Sdk="Microsoft.NET.Sdk.Web">
```


## Subsection 2: PropertyGroup Conventions

PropertyGroup elements contain scalar MSBuild properties. The most important properties control the target framework, language features, and output type.

### Annotated XML Example

```xml
<PropertyGroup>
  <!-- Target Framework Moniker (TFM) -- determines runtime and API surface -->
  <!-- Use the latest LTS or STS release; prefer the repo's existing TFM. -->
  <TargetFramework>net9.0</TargetFramework>

  <!-- For multi-targeting, use plural form (see Subsection 4) -->
  <!-- <TargetFrameworks>net8.0;net9.0</TargetFrameworks> -->

  <!-- Enable nullable reference types (recommended for all new projects) -->
  <Nullable>enable</Nullable>

  <!-- Enable implicit global usings (System, System.Linq, etc.) -->
  <ImplicitUsings>enable</ImplicitUsings>

  <!-- Output type: Exe for apps, omit or Library for libraries -->
  <OutputType>Exe</OutputType>
  <!-- Omitting OutputType defaults to Library (produces .dll) -->

  <!-- Root namespace -- defaults to project name if omitted -->
  <RootNamespace>MyApp.Api</RootNamespace>

  <!-- Assembly name -- defaults to project name if omitted -->
  <AssemblyName>MyApp.Api</AssemblyName>

  <!-- Language version -- usually omitted (SDK sets default for TFM) -->
  <!-- Only set explicitly when using preview features -->
  <LangVersion>preview</LangVersion>
</PropertyGroup>
```

### Common Modification Patterns

**Enabling nullable for an existing project:**

```xml
<!-- Add to the main PropertyGroup -->
<Nullable>enable</Nullable>
<!-- This enables nullable warnings project-wide. Existing code will produce warnings. -->
<!-- To adopt incrementally, use #nullable enable in individual files instead. -->
```

**Setting output type for a console app:**

```xml
<!-- Required for executable projects; without this, dotnet run fails -->
<OutputType>Exe</OutputType>
```

**Adding TreatWarningsAsErrors (recommended for CI parity):**

```xml
<PropertyGroup>
  <TreatWarningsAsErrors>true</TreatWarningsAsErrors>
  <!-- Enable unconditionally -- do NOT use CI-only conditions -->
</PropertyGroup>
```


## Subsection 3: ItemGroup Patterns

ItemGroup elements contain collections: package references, project references, file inclusions, and other build items. Understanding the three main item types prevents common agent mistakes.

### Annotated XML Example

```xml
<ItemGroup>
  <!-- PackageReference: NuGet package dependency -->
  <!-- Version attribute is required unless using central package management -->
  <PackageReference Include="Microsoft.EntityFrameworkCore" Version="9.0.0" />

  <!-- PrivateAssets="All" prevents the dependency from flowing to consumers -->
  <PackageReference Include="Microsoft.SourceLink.GitHub" Version="8.0.0" PrivateAssets="All" />

  <!-- IncludeAssets controls which assets from the package are used -->
  <PackageReference Include="Nerdbank.GitVersioning" Version="3.7.115"
                    PrivateAssets="All" IncludeAssets="runtime;build;native;analyzers" />
</ItemGroup>

<ItemGroup>
  <!-- ProjectReference: reference to another project in the solution -->
  <!-- Use forward slashes for cross-platform compatibility -->
  <ProjectReference Include="../MyApp.Core/MyApp.Core.csproj" />

  <!-- Set PrivateAssets to prevent transitive exposure to consumers -->
  <ProjectReference Include="../MyApp.Internal/MyApp.Internal.csproj"
                    PrivateAssets="All" />
</ItemGroup>

<ItemGroup>
  <!-- None: files included in the project but not compiled -->
  <!-- CopyToOutputDirectory controls deployment behavior -->
  <None Include="appsettings.json" CopyToOutputDirectory="PreserveNewest" />

  <!-- Content: files that are part of the published output -->
  <Content Include="wwwroot/**" CopyToOutputDirectory="PreserveNewest" />

  <!-- EmbeddedResource: files compiled into the assembly -->
  <EmbeddedResource Include="Resources/**/*.resx" />
</ItemGroup>
```

### Common Modification Patterns

**Adding a NuGet package:**

```bash
# Prefer CLI to avoid formatting issues
dotnet add src/MyApp/MyApp.csproj package Microsoft.EntityFrameworkCore --version 9.0.0
```

```xml
<!-- Or add manually -- ensure Version is specified -->
<PackageReference Include="Microsoft.EntityFrameworkCore" Version="9.0.0" />
```

**Adding a project reference:**

```bash
# CLI ensures correct relative path
dotnet add src/MyApp.Api/MyApp.Api.csproj reference src/MyApp.Core/MyApp.Core.csproj
```

```xml
<!-- Verify path actually resolves to an existing .csproj -->
<ProjectReference Include="../MyApp.Core/MyApp.Core.csproj" />
```

**Including non-compiled files in output:**

```xml
<!-- Copy config files to output on build -->
<None Update="config/*.json" CopyToOutputDirectory="PreserveNewest" />
<!-- Note: Update (not Include) when the file is already matched by default globs -->
```


## Subsection 4: Condition Expressions and Multi-Targeting

MSBuild conditions enable TFM-specific properties, platform-specific package references, and build configuration logic. Understanding condition syntax prevents broken multi-targeting builds.

### Annotated XML Example

```xml
<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <!-- Multi-targeting: builds the project once per TFM -->
    <TargetFrameworks>net8.0;net9.0</TargetFrameworks>
    <!-- Note the plural 'TargetFrameworks' (not 'TargetFramework') -->
  </PropertyGroup>

  <!-- TFM-conditional property: only applies to net9.0 builds -->
  <PropertyGroup Condition="'$(TargetFramework)' == 'net9.0'">
    <AllowUnsafeBlocks>true</AllowUnsafeBlocks>
  </PropertyGroup>

  <!-- TFM-conditional package reference: only include on specific TFMs -->
  <ItemGroup Condition="'$(TargetFramework)' == 'net8.0'">
    <PackageReference Include="Backport.System.Threading.Lock" Version="2.0.5" />
    <!-- System.Threading.Lock is built-in on net9.0+; this polyfill enables it on net8.0 -->
  </ItemGroup>

  <!-- Configuration-conditional items -->
  <ItemGroup Condition="'$(Configuration)' == 'Debug'">
    <PackageReference Include="Microsoft.EntityFrameworkCore.Design" Version="9.0.0" />
  </ItemGroup>

  <!-- Platform-conditional items for MAUI/Uno -->
  <ItemGroup Condition="$(TargetFramework.StartsWith('net9.0-android'))">
    <PackageReference Include="Xamarin.AndroidX.Core" Version="1.15.0.1" />
  </ItemGroup>

  <!-- Boolean conditions -->
  <PropertyGroup Condition="'$(CI)' == 'true'">
    <ContinuousIntegrationBuild>true</ContinuousIntegrationBuild>
  </PropertyGroup>

</Project>
```

### Common Modification Patterns

**Adding a TFM:**

```xml
<!-- Change singular to plural and add new TFM -->
<!-- Before: -->
<TargetFramework>net8.0</TargetFramework>
<!-- After: -->
<TargetFrameworks>net8.0;net9.0</TargetFrameworks>
```

**Using version-agnostic TFM patterns for platform detection:**

```xml
<!-- CORRECT: version-agnostic glob handles net8.0-android, net9.0-android, etc. -->
<ItemGroup Condition="$(TargetFramework.Contains('-android'))">
  <AndroidResource Include="Resources/**" />
</ItemGroup>

<!-- WRONG: hardcoded version misses other TFMs -->
<ItemGroup Condition="'$(TargetFramework)' == 'net9.0-android'">
```

**Condition syntax reference:**

| Expression | Meaning |
|-----------|---------|
| `'$(Prop)' == 'value'` | Exact match (case-insensitive) |
| `'$(Prop)' != 'value'` | Not equal |
| `$(Prop.StartsWith('prefix'))` | String starts with |
| `$(Prop.Contains('sub'))` | String contains |
| `'$(Prop)' == ''` | Property is empty/not set |
| `Exists('path')` | File or directory exists |


## Subsection 5: Directory.Build.props and Directory.Build.targets

These files centralize shared build configuration. MSBuild automatically imports `Directory.Build.props` (before the project) and `Directory.Build.targets` (after the project) from the current directory and all parent directories up to the filesystem root.

### Annotated XML: Directory.Build.props

```xml
<!-- Directory.Build.props: imported BEFORE the project file -->
<!-- Use for properties that projects inherit but can override -->
<!-- Place at solution root to apply to all projects -->
<Project>

  <PropertyGroup>
    <!-- Common properties for all projects in the solution -->
    <TargetFramework>net9.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <TreatWarningsAsErrors>true</TreatWarningsAsErrors>

    <!-- Deterministic builds for CI -->
    <Deterministic>true</Deterministic>
    <ContinuousIntegrationBuild Condition="'$(CI)' == 'true'">true</ContinuousIntegrationBuild>
  </PropertyGroup>

  <PropertyGroup>
    <!-- Package metadata for all libraries -->
    <Authors>MyCompany</Authors>
    <Company>MyCompany</Company>
    <PackageLicenseExpression>MIT</PackageLicenseExpression>
  </PropertyGroup>

</Project>
```

### Annotated XML: Directory.Build.targets

```xml
<!-- Directory.Build.targets: imported AFTER the project file -->
<!-- Use for targets, items, and properties that depend on project-level values -->
<!-- Place at solution root alongside Directory.Build.props -->
<Project>

  <!-- Add analyzers to all projects (after project props are set) -->
  <ItemGroup>
    <PackageReference Include="Microsoft.CodeAnalysis.NetAnalyzers" Version="9.0.0"
                      PrivateAssets="All" IncludeAssets="analyzers" />
  </ItemGroup>

  <!-- Conditional item that depends on project-set properties -->
  <ItemGroup Condition="'$(IsTestProject)' == 'true'">
    <PackageReference Include="coverlet.collector" Version="8.0.0"
                      PrivateAssets="All" />
  </ItemGroup>

  <!-- Custom target that runs after build -->
  <Target Name="PrintBuildInfo" AfterTargets="Build">
    <Message Importance="high" Text="Built $(AssemblyName) for $(TargetFramework)" />
  </Target>

</Project>
```

### Common Modification Patterns

**Hierarchy and override behavior:**

```
repo-root/
  Directory.Build.props     <-- applies to ALL projects
  src/
    Directory.Build.props   <-- applies to src/ projects only
    MyApp.Api/
      MyApp.Api.csproj      <-- inherits from src/ props (NOT repo-root/)
```

MSBuild imports the nearest `Directory.Build.props` found walking upward. If a nested `Directory.Build.props` exists, it shadows the parent. To chain both, the nested file must explicitly import the parent:

```xml
<!-- src/Directory.Build.props -- import parent first, then override -->
<Project>
  <Import Project="$([MSBuild]::GetPathOfFileAbove('Directory.Build.props', '$(MSBuildThisFileDirectory)../'))" />

  <PropertyGroup>
    <!-- Override or extend parent properties for src/ projects -->
    <RootNamespace>MyApp.$(MSBuildProjectName)</RootNamespace>
  </PropertyGroup>
</Project>
```

**When to use .props vs .targets:**

| Use .props for | Use .targets for |
|---------------|-----------------|
| Property defaults (TFM, nullable, etc.) | Items that depend on project properties |
| Package metadata (authors, license) | Custom build targets (AfterTargets, BeforeTargets) |
| Properties projects can override | Analyzer packages added to all projects |


## Subsection 6: Directory.Packages.props (Central Package Management)

Central Package Management (CPM) centralizes NuGet package versions in a single `Directory.Packages.props` file. Individual projects reference packages without specifying versions.

### Annotated XML Example

```xml
<!-- Directory.Packages.props: place at solution root -->
<Project>

  <PropertyGroup>
    <!-- Enable Central Package Management -->
    <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
  </PropertyGroup>

  <ItemGroup>
    <!-- PackageVersion defines the version centrally -->
    <!-- Projects use PackageReference WITHOUT Version attribute -->
    <PackageVersion Include="Microsoft.EntityFrameworkCore" Version="9.0.0" />
    <PackageVersion Include="Microsoft.EntityFrameworkCore.SqlServer" Version="9.0.0" />
    <PackageVersion Include="Microsoft.Extensions.Hosting" Version="9.0.0" />
    <PackageVersion Include="Serilog.AspNetCore" Version="8.0.3" />

    <!-- Test packages -->
    <PackageVersion Include="xunit.v3" Version="3.2.2" />
    <PackageVersion Include="xunit.runner.visualstudio" Version="3.1.5" />
    <PackageVersion Include="Microsoft.NET.Test.Sdk" Version="18.0.1" />
    <PackageVersion Include="NSubstitute" Version="5.3.0" />
  </ItemGroup>

</Project>
```

**Project file with CPM enabled:**

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net9.0</TargetFramework>
  </PropertyGroup>

  <ItemGroup>
    <!-- No Version attribute -- version comes from Directory.Packages.props -->
    <PackageReference Include="Microsoft.EntityFrameworkCore" />
    <PackageReference Include="Microsoft.EntityFrameworkCore.SqlServer" />
  </ItemGroup>
</Project>
```

### Common Modification Patterns

**Enabling CPM in an existing solution:**

1. Create `Directory.Packages.props` at the solution root with `<ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>`.
2. Move all `Version` attributes from `PackageReference` items into `PackageVersion` entries in the central file.
3. Remove `Version` from all `PackageReference` items in individual `.csproj` files.

```bash
# Find all PackageReference entries with Version attributes
grep -rn 'PackageReference Include=.*Version=' --include="*.csproj" src/
```

**Overriding a version in a specific project** (escape hatch):

```xml
<!-- In the individual .csproj -- use VersionOverride when a project needs a different version -->
<PackageReference Include="Microsoft.EntityFrameworkCore" VersionOverride="8.0.11" />
```

**Hierarchical resolution:** `Directory.Packages.props` resolves upward from the project directory, the same as `Directory.Build.props`. In monorepos, place the central file at the repo root. Sub-directories can have their own `Directory.Packages.props` -- the nearest one wins.

**Migrating from per-project versions:**

```bash
# List all unique packages and versions across the solution
dotnet list src/MyApp.sln package --format json
# Use this output to build the central PackageVersion list
```


## Slopwatch Anti-Patterns

These patterns in project files indicate an agent is hiding problems rather than fixing them. See [skill:dotnet-testing] for the automated quality gate that detects these patterns.

### NoWarn in .csproj

```xml
<!-- RED FLAG: blanket warning suppression in project file -->
<PropertyGroup>
  <NoWarn>CS8600;CS8602;CS8604;IL2026;IL2046;IL3050</NoWarn>
</PropertyGroup>
```

`<NoWarn>` in the project file suppresses warnings for the entire project, making issues invisible. This is worse than `#pragma` because it has no scope boundary and cannot be audited per-file.

**Fix:** Remove `<NoWarn>` entries and fix the underlying issues. For warnings that genuinely do not apply project-wide, configure severity in `.editorconfig` instead:

```ini
# .editorconfig -- preferred over <NoWarn> for controlled suppression
[*.cs]
dotnet_diagnostic.CA2007.severity = none  # No SynchronizationContext in ASP.NET Core
```

### Suppressed Analyzers in Directory.Build.props

```xml
<!-- RED FLAG: disabling analyzers for all projects via shared props -->
<PropertyGroup>
  <NoWarn>$(NoWarn);CA1062;CA1822;CA2007</NoWarn>
  <!-- OR -->
  <RunAnalyzers>false</RunAnalyzers>
  <!-- OR -->
  <EnableNETAnalyzers>false</EnableNETAnalyzers>
</PropertyGroup>
```

Disabling analyzers in `Directory.Build.props` silences them across every project in the solution, including new projects added later. Agents sometimes do this to achieve a clean build quickly.

**Fix:** Keep analyzers enabled globally. Address warnings per-project or per-file. If a specific rule category does not apply (e.g., CA2007 in ASP.NET Core apps), suppress it in `.editorconfig` at the appropriate scope with a comment explaining why.


## Cross-References

- `references/project-structure.md` -- SDK selection, project organization, solution layout
- `references/build-analysis.md` -- interpreting build errors caused by project misconfiguration
- [skill:dotnet-api] -- common project structure mistakes agents make (wrong SDK, broken refs)

## References

- [MSBuild Project SDK](https://learn.microsoft.com/en-us/dotnet/core/project-sdk/overview)
- [MSBuild Reference](https://learn.microsoft.com/en-us/visualstudio/msbuild/msbuild)
- [Central Package Management](https://learn.microsoft.com/en-us/nuget/consume-packages/Central-Package-Management)
- [Directory.Build.props/targets](https://learn.microsoft.com/en-us/visualstudio/msbuild/customize-by-directory)
- [MSBuild Conditions](https://learn.microsoft.com/en-us/visualstudio/msbuild/msbuild-conditions)
- [SDK-style Project Format](https://learn.microsoft.com/en-us/dotnet/core/project-sdk/overview)
