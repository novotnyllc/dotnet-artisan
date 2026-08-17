# Project Analysis

```bash
find . -maxdepth 3 \( -name "*.csproj" -o -name "*.sln" -o -name "*.slnx" \) 2>/dev/null | head -20
```

Analyzes .NET solution structure, project references, and build configuration. This skill is foundational -- agents need to understand project layout before doing any meaningful .NET development work.

**Prerequisites:** Run `references/version-detection.md` first to determine TFM and SDK version. For .NET 10+ single-file apps without a `.csproj`, see [skill:dotnet-csharp] instead.

## Step 1: Find the Solution Root

Look for solution files in the workspace, starting from the current directory and walking up to the repository root.

### .sln (Legacy Format)

The traditional MSBuild solution format. Contains project paths and build configurations.

```
Microsoft Visual Studio Solution File, Format Version 12.00
Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "MyApp", "src\MyApp\MyApp.csproj", "{GUID}"
EndProject
Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "MyApp.Tests", "tests\MyApp.Tests\MyApp.Tests.csproj", "{GUID}"
EndProject
```

Extract project entries from `Project("...")` lines. The second quoted value is the project name, the third is the relative path to the `.csproj`.

### .slnx (Modern XML Format)

The new XML-based solution format (supported in .NET 10+ SDK, Visual Studio 17.13+). Preferred for new projects.

```xml
<Solution>
  <Folder Name="/src/">
    <Project Path="src/MyApp/MyApp.csproj" />
  </Folder>
  <Folder Name="/tests/">
    <Project Path="tests/MyApp.Tests/MyApp.Tests.csproj" />
  </Folder>
</Solution>
```

Extract project entries from `<Project Path="..." />` elements. Solution folders (`<Folder>`) indicate logical grouping.

### No Solution File

If no `.sln` or `.slnx` is found, scan for `.csproj` files recursively. Report: "No solution file found. Discovered N project files. Consider creating a solution with `dotnet new sln` and `dotnet sln add`."


## Step 2: Analyze Each Project

For every `.csproj` discovered in Step 1, read its contents and extract the following.

### Project SDK and Type

The `<Project Sdk="...">` attribute identifies the project kind:

| SDK | Project Type | Description |
|-----|-------------|-------------|
| `Microsoft.NET.Sdk` | Class Library / Console | Default SDK, check for `<OutputType>` |
| `Microsoft.NET.Sdk.Web` | Web (API / MVC / Razor Pages) | ASP.NET Core web application |
| `Microsoft.NET.Sdk.BlazorWebAssembly` | Blazor WASM | Client-side Blazor (legacy SDK) |
| `Microsoft.NET.Sdk.Worker` | Worker Service | Background service / daemon |
| `Microsoft.NET.Sdk.Razor` | Razor Class Library | Shared Razor components |
| `Microsoft.Maui.Sdk` or TFMs with `-android`/`-ios` | MAUI | Cross-platform mobile/desktop |
| Custom or `Uno.Sdk` | Uno Platform | Cross-platform UI (check for Uno references) |

### Output Type Detection

If SDK is `Microsoft.NET.Sdk`, check `<OutputType>` to distinguish:

| OutputType | Meaning |
|-----------|---------|
| `Exe` | Console application |
| `Library` (or absent) | Class library |
| `WinExe` | Windows desktop (WPF/WinForms/WinUI) |

### Test Project Detection

A project is a test project if any of the following are true:
- `<IsTestProject>true</IsTestProject>` is set
- Has a PackageReference to `xunit.v3`, `xunit`, `NUnit`, `MSTest.TestFramework`, or `Microsoft.NET.Test.Sdk`
- Project name ends with `.Tests`, `.UnitTests`, `.IntegrationTests`, or `.TestUtils`

### Blazor Project Detection

A project is Blazor if:
- SDK is `Microsoft.NET.Sdk.BlazorWebAssembly`
- Has `<PackageReference Include="Microsoft.AspNetCore.Components.WebAssembly" />`
- Has `.razor` files in the project directory
- Uses `AddInteractiveServerComponents()` or `AddInteractiveWebAssemblyComponents()` in startup

### MAUI Project Detection

A project is MAUI if:
- `<UseMaui>true</UseMaui>` is set
- SDK is `Microsoft.Maui.Sdk`
- TFM includes platform-specific targets: `net*-android`, `net*-ios`, `net*-maccatalyst`, `net*-windows` (e.g., `net8.0-android`, `net10.0-ios`)

### Uno Platform Detection

A project is Uno Platform if:
- SDK is `Uno.Sdk` or `Uno.Sdk.Private`
- Has PackageReference to `Uno.WinUI` or `Uno.UI`
- TFM includes Uno-specific targets (e.g., `net*-browserwasm`, `net*-desktop`)


## Step 3: Map Project References

Read `<ProjectReference>` elements from each `.csproj` to build the dependency graph.

```xml
<ItemGroup>
  <ProjectReference Include="..\MyApp.Core\MyApp.Core.csproj" />
  <ProjectReference Include="..\MyApp.Infrastructure\MyApp.Infrastructure.csproj" />
</ItemGroup>
```

Build a dependency graph and report it:

```
Project Dependency Graph
========================
MyApp.Web (Web API)
  -> MyApp.Core (Library)
  -> MyApp.Infrastructure (Library)
    -> MyApp.Core (Library)
MyApp.Tests (Test)
  -> MyApp.Web (Web API)
  -> MyApp.Core (Library)
```

Flag issues:
- **Circular references**: "Project A -> B -> A detected. This will cause build failures."
- **Test projects referencing other test projects**: "Unusual -- test projects should reference production code, not other tests."
- **Deep nesting**: More than 4 levels deep may indicate over-abstraction.


## Step 4: Detect Centralized Build Configuration

### Directory.Build.props

Search for `Directory.Build.props` starting from each project directory up to the solution root. These files set shared MSBuild properties across all projects in their directory subtree.

Common shared properties to report:
- `<TargetFramework>` / `<TargetFrameworks>` -- shared TFM (see `references/version-detection.md`)
- `<LangVersion>` -- C# language version
- `<Nullable>enable</Nullable>` -- nullable reference types
- `<ImplicitUsings>enable</ImplicitUsings>` -- implicit global usings
- `<TreatWarningsAsErrors>true</TreatWarningsAsErrors>` -- strict warnings
- `<EnforceCodeStyleInBuild>true</EnforceCodeStyleInBuild>` -- code style enforcement
- `<AnalysisLevel>latest-all</AnalysisLevel>` -- analyzer severity
- `<ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>` -- CPM indicator

Report: "Found Directory.Build.props at `<path>`. Shared settings: [list properties found]. These apply to all projects under `<directory>`."

### Directory.Build.targets

Search for `Directory.Build.targets` the same way. These run **after** project evaluation and typically contain:
- Shared `<PackageReference>` items (e.g., analyzers applied to all projects)
- Conditional logic based on project type
- Custom MSBuild targets

Report: "Found Directory.Build.targets at `<path>`. Contains: [summarize content]."

### Multiple Directory.Build Files

If multiple `Directory.Build.props` files exist at different levels (e.g., root and `src/`), report the hierarchy:

```
Build Configuration Hierarchy
==============================
/repo/Directory.Build.props           (root: Nullable, ImplicitUsings, LangVersion)
  /repo/src/Directory.Build.props     (src: TargetFramework, TreatWarningsAsErrors)
  /repo/tests/Directory.Build.props   (tests: IsTestProject, test-specific settings)
```

Note: Inner files do NOT automatically import outer files. Check for `<Import Project="$([MSBuild]::GetPathOfFileAbove('Directory.Build.props', '$(MSBuildThisFileDirectory)../'))" />` to see if chaining is configured.


## Step 5: Detect Central Package Management (CPM)

### Directory.Packages.props

Search for `Directory.Packages.props` starting from the solution root and walking **upward** toward the repository root (or filesystem root). NuGet resolves CPM hierarchically -- a monorepo may have `Directory.Packages.props` in a parent directory that governs multiple solutions. Also check for `<ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>` in any `Directory.Build.props` in the hierarchy, as CPM can be enabled there instead.

```xml
<Project>
  <PropertyGroup>
    <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
  </PropertyGroup>
  <ItemGroup>
    <PackageVersion Include="Microsoft.Extensions.Logging" Version="10.0.0" />
    <PackageVersion Include="xunit.v3" Version="3.2.2" />
  </ItemGroup>
</Project>
```

Report:
- **CPM enabled**: "Central Package Management is active. Package versions are defined in `Directory.Packages.props` at `<path>`. Individual `.csproj` files use `<PackageReference Include="..." />` without `Version` attributes."
- **Package count**: "N packages managed centrally."
- **Version overrides**: Check for `<PackageReference ... VersionOverride="...">` in individual projects -- flag these as exceptions.
- **Inherited CPM**: If `Directory.Packages.props` is above the solution root, note: "CPM is inherited from `<path>` (above solution root). This is common in monorepos."

### CPM Not Used

If no `Directory.Packages.props` is found in the upward search and `ManagePackageVersionsCentrally` is not set in any `Directory.Build.props`:
- Report: "Central Package Management is not configured. Each project defines its own package versions."
- Suggest: "Consider enabling CPM for version consistency. See `references/project-structure.md` for setup guidance."


## Step 6: Detect Additional Configuration Files

### .editorconfig

Check for `.editorconfig` at the solution root and nested levels. Report:
- Whether it exists
- Key rules: indent style/size, naming conventions, severity overrides
- .NET-specific sections: `[*.cs]` rules for `dotnet_style_*` and `csharp_style_*`

### nuget.config

Search for `nuget.config` (case-insensitive) starting from the solution root and walking **upward** through parent directories. NuGet merges configuration hierarchically (project > user > machine), so multiple files may contribute to the effective config. Report all discovered files and their contents:
- Package sources configured (e.g., nuget.org, private feeds, local folders)
- Any `<packageSourceMapping>` entries (security best practice for supply chain)
- Any `<disabledPackageSources>` entries
- Note: "User-level (`~/.nuget/NuGet/NuGet.Config`) and machine-level configs may also affect package resolution. Run `dotnet nuget list source` to see the effective merged sources."

### global.json

Already read by `references/version-detection.md`. Report relevant details here:
- `sdk.version` and `sdk.rollForward` policy
- `msbuild-sdks` section if present (custom SDK versions)

### .config/dotnet-tools.json

Check for local tool manifest. Report installed tools:
- `dotnet-ef` -- Entity Framework Core tools
- `dotnet-format` -- code formatting
- `nbgv` -- Nerdbank.GitVersioning
- Any other tools and their versions


## Step 7: Identify Entry Points and Key Files

Guide the agent to the most important files based on project type.

### Web API / MVC / Razor Pages
- **Entry point**: `Program.cs` (top-level statements, service registration, middleware pipeline)
- **Configuration**: `appsettings.json`, `appsettings.{Environment}.json`
- **Startup**: Look for `builder.Services` registrations and `app.Map*` endpoint definitions
- **Endpoints**: Minimal API endpoints in `Program.cs` or `*.cs` files under an `Endpoints/` directory; Controller-based in `Controllers/` directory

### Console Application
- **Entry point**: `Program.cs` (top-level statements or `static void Main`)
- **Configuration**: `appsettings.json` if using `IHostBuilder` / Generic Host

### Worker Service
- **Entry point**: `Program.cs` with `builder.Services.AddHostedService<Worker>()`
- **Worker**: Class inheriting `BackgroundService` with `ExecuteAsync` override

### Class Library
- **No entry point**: Document the public API surface (public classes/interfaces)
- **Key files**: Look for the primary namespace's types

### Blazor
- **Entry point**: `Program.cs` with component registration
- **Root component**: `App.razor` or `Routes.razor`
- **Layout**: `MainLayout.razor` in `Layout/` or `Shared/`
- **Pages**: `.razor` files with `@page` directive

### MAUI
- **Entry point**: `MauiProgram.cs` with `CreateMauiApp()`
- **App shell**: `AppShell.xaml` for navigation structure
- **Pages**: Files under `Views/` or `Pages/` directories
- **Platform-specific**: `Platforms/` directory with Android, iOS, Windows, Mac Catalyst folders

### Test Project
- **Test files**: `*.cs` files with `[Fact]`, `[Theory]`, `[Test]`, or `[TestMethod]` attributes
- **Fixtures**: Classes implementing `IClassFixture<T>` or `ICollectionFixture<T>`
- **Configuration**: Look for `WebApplicationFactory<T>` usage for integration tests


## Structured Output Format

After completing analysis, present results in this format:

```
.NET Project Analysis Results
==============================
Solution:         MyApp.slnx (or MyApp.sln)
Projects:         5 (2 libraries, 1 web API, 1 console, 1 test)
CPM:              enabled (42 packages in Directory.Packages.props)
Shared Config:    Directory.Build.props (Nullable, ImplicitUsings, LangVersion=14)
Code Style:       .editorconfig present
Package Sources:  nuget.org + private feed (packageSourceMapping configured)
Local Tools:      dotnet-ef 10.0.0, nbgv 3.7.0

Project Dependency Graph
------------------------
MyApp.Api (Web API, net10.0) -> entry: src/MyApp.Api/Program.cs
  -> MyApp.Core (Library)
  -> MyApp.Infrastructure (Library)
    -> MyApp.Core (Library)
MyApp.Console (Console, net10.0) -> entry: src/MyApp.Console/Program.cs
  -> MyApp.Core (Library)
MyApp.Tests (Test, xUnit) -> entry: tests/MyApp.Tests/
  -> MyApp.Api (Web API)
  -> MyApp.Core (Library)

Key Files
---------
- Solution root:    /repo/MyApp.slnx
- Shared props:     /repo/Directory.Build.props
- Package versions: /repo/Directory.Packages.props
- API entry point:  /repo/src/MyApp.Api/Program.cs
- API config:       /repo/src/MyApp.Api/appsettings.json
```


## Edge Cases

### Mixed Solution Formats
If both `.sln` and `.slnx` exist, prefer `.slnx` (modern format). Note: "Both `.sln` and `.slnx` found. Using `.slnx` as primary. The `.sln` may be maintained for older tooling compatibility."

### Monorepo with Multiple Solutions
If multiple `.sln`/`.slnx` files exist, report all of them and ask the user which solution to analyze. If one is at the repository root, default to that one.

### Projects Not in Solution
If `.csproj` files exist that are not referenced by any solution file, report them as orphaned: "Found N project files not included in any solution. These may be experimental or unused."

### Conditional ProjectReferences
If `<ProjectReference>` is inside a `<When>` or has a `Condition` attribute:
```xml
<ProjectReference Include="..\MyApp.DevTools\MyApp.DevTools.csproj"
                  Condition="'$(Configuration)' == 'Debug'" />
```
Report: "Conditional reference to MyApp.DevTools (Debug only)."

### Web Project Without launchSettings.json
If a web project has no `Properties/launchSettings.json`, note: "No `launchSettings.json` found. The project uses default Kestrel settings. Consider adding launch profiles for development."
