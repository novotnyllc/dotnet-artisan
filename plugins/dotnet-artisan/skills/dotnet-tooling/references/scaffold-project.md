# Scaffold Project

Scaffolds a new .NET project with all modern best practices applied. Generates the full solution structure including Central Package Management, analyzers, .editorconfig, SourceLink, and deterministic builds.

**Prerequisites:** Run `references/version-detection.md` first to determine available SDK version — this affects which features and templates are available.

## Step 1: Create Solution Structure

Create the directory layout and solution file.

```bash
# Create the directory structure
mkdir -p MyApp/src MyApp/tests

# Create solution file
cd MyApp
dotnet new sln -n MyApp

# For .NET 9+ SDK, convert to .slnx
dotnet sln MyApp.sln migrate
```

### Choose Project Template

Select the appropriate template based on the application type:

| Template | Command | SDK |
|----------|---------|-----|
| Web API (minimal) | `dotnet new webapi -n MyApp.Api -o src/MyApp.Api` | `Microsoft.NET.Sdk.Web` |
| Web API (controllers) | `dotnet new webapi -n MyApp.Api -o src/MyApp.Api --use-controllers` | `Microsoft.NET.Sdk.Web` |
| Console app | `dotnet new console -n MyApp.Cli -o src/MyApp.Cli` | `Microsoft.NET.Sdk` |
| Worker service | `dotnet new worker -n MyApp.Worker -o src/MyApp.Worker` | `Microsoft.NET.Sdk.Worker` |
| Class library | `dotnet new classlib -n MyApp.Core -o src/MyApp.Core` | `Microsoft.NET.Sdk` |
| Blazor web app | `dotnet new blazor -n MyApp.Web -o src/MyApp.Web` | `Microsoft.NET.Sdk.Web` |
| MAUI app | `dotnet new maui -n MyApp.Mobile -o src/MyApp.Mobile` | `Microsoft.Maui.Sdk` |
| xUnit test | `dotnet new xunit -n MyApp.Tests -o tests/MyApp.Tests` | `Microsoft.NET.Sdk` |

```bash
# Example: Web API with class library and tests
dotnet new classlib -n MyApp.Core -o src/MyApp.Core
dotnet new webapi -n MyApp.Api -o src/MyApp.Api
dotnet new xunit -n MyApp.UnitTests -o tests/MyApp.UnitTests

# Add projects to solution
dotnet sln add src/MyApp.Core/MyApp.Core.csproj
dotnet sln add src/MyApp.Api/MyApp.Api.csproj
dotnet sln add tests/MyApp.UnitTests/MyApp.UnitTests.csproj

# Add project references
dotnet add src/MyApp.Api/MyApp.Api.csproj reference src/MyApp.Core/MyApp.Core.csproj
dotnet add tests/MyApp.UnitTests/MyApp.UnitTests.csproj reference src/MyApp.Core/MyApp.Core.csproj
```


## Step 2: Add global.json

Pin the SDK version for reproducible builds.

```json
{
  "sdk": {
    "version": "10.0.100",
    "rollForward": "latestPatch"
  }
}
```

Adjust the version to match the output of `dotnet --version`.


## Step 3: Add Directory.Build.props

Create at the repo root to share build settings across all projects.

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

  <!-- Deterministic builds and SourceLink (for libraries) -->
  <PropertyGroup>
    <PublishRepositoryUrl>true</PublishRepositoryUrl>
    <EmbedUntrackedSources>true</EmbedUntrackedSources>
    <DebugType>embedded</DebugType>
    <ContinuousIntegrationBuild Condition="'$(CI)' == 'true'">true</ContinuousIntegrationBuild>
  </PropertyGroup>

  <!-- NuGet audit -->
  <PropertyGroup>
    <NuGetAudit>true</NuGetAudit>
    <NuGetAuditLevel>low</NuGetAuditLevel>
    <NuGetAuditMode>all</NuGetAuditMode>
    <RestorePackagesWithLockFile>true</RestorePackagesWithLockFile>
  </PropertyGroup>
</Project>
```

After creating this, **remove** `<TargetFramework>`, `<Nullable>`, and `<ImplicitUsings>` from individual `.csproj` files to avoid duplication.

### Optional: Separate Test Props

```xml
<!-- tests/Directory.Build.props -->
<Project>
  <Import Project="$([MSBuild]::GetPathOfFileAbove('Directory.Build.props', '$(MSBuildThisFileDirectory)../'))" />
  <PropertyGroup>
    <IsPackable>false</IsPackable>
    <IsTestProject>true</IsTestProject>
    <!-- Use Microsoft.Testing.Platform v2 runner (requires Microsoft.NET.Test.Sdk 17.13+/18.x) -->
    <UseMicrosoftTestingPlatformRunner>true</UseMicrosoftTestingPlatformRunner>
    <!-- Tests don't need TreatWarningsAsErrors -->
    <TreatWarningsAsErrors>false</TreatWarningsAsErrors>
  </PropertyGroup>
</Project>
```


## Step 4: Add Directory.Build.targets

Apply shared package references (SourceLink, analyzers) to all projects. Items go in `.targets` so they are imported after project evaluation.

```xml
<Project>
  <ItemGroup>
    <!-- SourceLink for debugger source navigation -->
    <PackageReference Include="Microsoft.SourceLink.GitHub" PrivateAssets="all" />
  </ItemGroup>
</Project>
```

The built-in Roslyn analyzers are already enabled by the `AnalysisLevel` and `EnforceCodeStyleInBuild` properties in Directory.Build.props (Step 3). For additional third-party analyzers, see `references/add-analyzers.md`.


## Step 5: Set Up Central Package Management

Create `Directory.Packages.props` at the repo root.

```xml
<Project>
  <PropertyGroup>
    <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
    <CentralPackageTransitivePinningEnabled>true</CentralPackageTransitivePinningEnabled>
  </PropertyGroup>
  <ItemGroup>
    <!-- Framework packages -->
    <PackageVersion Include="Microsoft.SourceLink.GitHub" Version="9.0.0" />
  </ItemGroup>
  <ItemGroup>
    <!-- Test packages -->
    <PackageVersion Include="Microsoft.NET.Test.Sdk" Version="18.0.1" />
    <PackageVersion Include="xunit.v3" Version="3.2.2" />
    <PackageVersion Include="xunit.runner.visualstudio" Version="3.1.5" />
    <PackageVersion Include="coverlet.collector" Version="8.0.0" />
  </ItemGroup>
</Project>
```

After creating this, **remove** `Version` attributes from all `<PackageReference>` elements in `.csproj` files.


## Step 6: Add .editorconfig

Create at the repo root. See `references/project-structure.md` for the full recommended config.

Minimal starter:

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
csharp_style_namespace_declarations = file_scoped:warning
csharp_prefer_braces = true:warning
dotnet_style_require_accessibility_modifiers = always:warning
dotnet_sort_system_directives_first = true
csharp_using_directive_placement = outside_namespace:warning
```


## Step 7: Add nuget.config

Configure package sources with supply-chain security:

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


## Step 8: Add .gitignore

```bash
dotnet new gitignore
```

This generates the standard .NET `.gitignore` covering `bin/`, `obj/`, `*.user`, etc.


## Step 9: Clean Up Generated Projects

After scaffolding, apply the shared configuration:

1. **Remove duplicated properties** from individual `.csproj` files (TargetFramework, Nullable, ImplicitUsings — these are in Directory.Build.props)
2. **Remove Version attributes** from PackageReference elements (managed by CPM)
3. **Delete template-generated Class1.cs** from class libraries
4. **Set file-scoped namespaces** in all generated `.cs` files

### Cleaned csproj Example

Before (template-generated):
```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
  </PropertyGroup>
</Project>
```

After (with shared props and CPM):
```xml
<Project Sdk="Microsoft.NET.Sdk">
</Project>
```

For web projects that need `Microsoft.NET.Sdk.Web`, the csproj still specifies the SDK but inherits everything else.


## Step 10: Verify

Run these commands to verify the scaffolded project:

```bash
# Restore and verify lock files generated
dotnet restore
find . -name "packages.lock.json" -type f

# Build with all analyzers
dotnet build --no-restore

# Run tests
dotnet test --no-build

# Verify CPM is active (no Version attributes in project PackageReferences)
# Should only find versions in Directory.Packages.props, not in csproj files
find . -name "*.csproj" -exec grep -l 'Version=' {} \;  # expect no output
```


## Final Structure

```
MyApp/
├── .editorconfig
├── .gitignore
├── global.json
├── nuget.config
├── MyApp.slnx
├── Directory.Build.props
├── Directory.Build.targets
├── Directory.Packages.props
├── src/
│   ├── MyApp.Core/
│   │   └── MyApp.Core.csproj
│   └── MyApp.Api/
│       ├── MyApp.Api.csproj
│       ├── Program.cs
│       └── appsettings.json
└── tests/
    └── MyApp.UnitTests/
        ├── MyApp.UnitTests.csproj
        └── SampleTest.cs
```


## References

- [.NET Library Design Guidance](https://learn.microsoft.com/en-us/dotnet/standard/library-guidance/)
- [Central Package Management](https://learn.microsoft.com/en-us/nuget/consume-packages/central-package-management)
- [SourceLink](https://learn.microsoft.com/en-us/dotnet/standard/library-guidance/sourcelink)
- [NuGet Audit](https://learn.microsoft.com/en-us/nuget/concepts/auditing-packages)
- [dotnet new Templates](https://learn.microsoft.com/en-us/dotnet/core/tools/dotnet-new)
