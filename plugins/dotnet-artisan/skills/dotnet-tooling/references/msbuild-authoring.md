# MSBuild Authoring

Guidance for authoring MSBuild project system elements: custom targets with `BeforeTargets`/`AfterTargets`/`DependsOnTargets`, incremental build with `Inputs`/`Outputs`, props vs targets import ordering, items and item metadata (`Include`/`Exclude`/`Update`/`Remove`), conditions, property functions, well-known metadata, and advanced `Directory.Build.props`/`Directory.Build.targets` patterns.

**Version assumptions:** .NET 8.0+ SDK (MSBuild 17.8+). All examples use SDK-style projects.

## Custom Targets

Targets are the unit of execution in MSBuild. Each target runs a sequence of tasks and can declare ordering relationships with other targets.

### Defining a Custom Target

```xml
<Target Name="PrintBuildInfo"
        BeforeTargets="Build">
  <Message Importance="high"
           Text="Building $(MSBuildProjectName) v$(Version) for $(TargetFramework)" />
</Target>
```

### Ordering: BeforeTargets, AfterTargets, DependsOnTargets

Three mechanisms control target execution order:

| Mechanism | Effect | Use when |
|---|---|---|
| `BeforeTargets="X"` | Runs this target before `X` | Injecting into an existing pipeline (e.g., run before `Build`) |
| `AfterTargets="X"` | Runs this target after `X` | Post-processing (e.g., copy output after `Publish`) |
| `DependsOnTargets="A;B"` | Ensures `A` and `B` run before this target | Declaring prerequisite targets within your own target graph |

```xml
<!-- Run license check before compile -->
<Target Name="CheckLicenseHeaders"
        BeforeTargets="CoreCompile">
  <Exec Command="dotnet tool run license-check -- --verify" />
</Target>

<!-- Copy native libs after publish -->
<Target Name="CopyNativeLibs"
        AfterTargets="Publish">
  <Copy SourceFiles="@(NativeLibrary)"
        DestinationFolder="$(PublishDir)runtimes/%(NativeLibrary.RuntimeIdentifier)/native/" />
</Target>

<!-- Composite target with dependencies -->
<Target Name="FullValidation"
        DependsOnTargets="CheckLicenseHeaders;RunApiCompat">
  <Message Importance="high" Text="All validations passed." />
</Target>
```

**Prefer `BeforeTargets`/`AfterTargets` over `DependsOnTargets`** for injecting into the standard build pipeline. `DependsOnTargets` is best for orchestrating your own custom target graph.

### Extending Existing DependsOn Lists

SDK targets expose `*DependsOn` properties for extension. Append your target name rather than replacing the list:

```xml
<PropertyGroup>
  <BuildDependsOn>$(BuildDependsOn);GenerateVersionInfo</BuildDependsOn>
</PropertyGroup>

<Target Name="GenerateVersionInfo">
  <WriteLinesToFile File="$(IntermediateOutputPath)Version.g.cs"
                    Lines="[assembly: System.Reflection.AssemblyInformationalVersion(&quot;$(InformationalVersion)&quot;)]"
                    Overwrite="true" />
  <ItemGroup>
    <Compile Include="$(IntermediateOutputPath)Version.g.cs" />
  </ItemGroup>
</Target>
```


## Incremental Build with Inputs/Outputs

Targets with `Inputs` and `Outputs` only run when outputs are missing or older than inputs. This is critical for build performance.

```xml
<Target Name="GenerateEmbeddedResources"
        BeforeTargets="CoreCompile"
        Inputs="@(EmbeddedTemplate)"
        Outputs="@(EmbeddedTemplate->'$(IntermediateOutputPath)%(Filename).g.cs')">
  <Exec Command="dotnet tool run template-gen -- %(EmbeddedTemplate.Identity) -o $(IntermediateOutputPath)%(EmbeddedTemplate.Filename).g.cs" />
  <ItemGroup>
    <Compile Include="$(IntermediateOutputPath)%(EmbeddedTemplate.Filename).g.cs" />
  </ItemGroup>
</Target>
```

**How incrementality works:**

1. MSBuild compares timestamps of `Inputs` items against `Outputs` items.
2. If all outputs exist and are newer than all inputs, the target is skipped entirely.
3. If any input is newer than any output, the full target runs.

**Common incrementality failures:**

- **Missing `Outputs`:** Target runs every build. Always pair `Inputs` with `Outputs`.
- **Volatile outputs:** If another target writes to the output path mid-build, timestamps reset and trigger unnecessary rebuilds.
- **Generator side effects:** Code generators that write unconditionally (even when content unchanged) break incrementality. Write to a temp file and copy only if content differs.
- **File copy timestamps:** `Copy` task with `SkipUnchangedFiles="true"` preserves timestamps; without it, every copy updates the timestamp.


## Props vs Targets: Import Ordering

MSBuild evaluates project files in a specific order. Understanding this is essential for correct customization.

### Evaluation Order

```
1. Directory.Build.props          (imported by SDK early)
2. <Project Sdk="...">            (SDK props imported)
3. Explicit <Import> in project   (your .props imports)
4. Project body <PropertyGroup>,  (project-level properties)
   <ItemGroup>
5. SDK targets imported            (SDK targets)
6. Directory.Build.targets         (imported by SDK late)
7. Explicit .targets imports       (your .targets imports)
```

### Rules

- **`.props` files** set default property values and define items. They run **before** the project body, so project-level properties can override them.
- **`.targets` files** define targets and finalize item lists. They run **after** the project body, so they see all project-level settings.

```xml
<!-- MyDefaults.props -- sets defaults, project can override -->
<Project>
  <PropertyGroup>
    <TreatWarningsAsErrors Condition="'$(TreatWarningsAsErrors)' == ''">true</TreatWarningsAsErrors>
    <Nullable Condition="'$(Nullable)' == ''">enable</Nullable>
  </PropertyGroup>
</Project>
```

```xml
<!-- MyTargets.targets -- runs after project evaluation -->
<Project>
  <Target Name="ValidatePackageMetadata"
          BeforeTargets="Pack"
          Condition="'$(IsPackable)' == 'true'">
    <Error Condition="'$(Description)' == ''"
           Text="Description is required for packable projects." />
  </Target>
</Project>
```

**Key rule:** Properties in `.props` files should use `Condition="'$(Prop)' == ''"` to allow project-level overrides. Properties in `.targets` files are evaluated last and cannot be overridden by the project.


## Items and Item Metadata

Items are named collections of files or values. Each item can carry metadata (key-value pairs).

### Item Operations

```xml
<ItemGroup>
  <!-- Include: add items matching a glob -->
  <Content Include="assets/**/*.png" />

  <!-- Exclude: remove items matching a pattern from the Include -->
  <Compile Include="**/*.cs" Exclude="**/*.generated.cs" />

  <!-- Update: modify metadata on existing items (does not add new items) -->
  <Content Update="assets/logo.png">
    <CopyToOutputDirectory>PreserveNewest</CopyToOutputDirectory>
    <Pack>true</Pack>
    <PackagePath>contentFiles/any/any/</PackagePath>
  </Content>

  <!-- Remove: remove items matching a pattern from the item list -->
  <Compile Remove="legacy/**/*.cs" />
</ItemGroup>
```

**SDK-style projects auto-include `*.cs` files.** Do not add a `<Compile Include="**/*.cs" />` -- it causes `NETSDK1022` duplicate items. Use `Remove` first, then `Include` for conditional compilation scenarios:

```xml
<!-- TFM-conditional compilation -->
<ItemGroup Condition="'$(TargetFramework)' == 'net8.0'">
  <Compile Remove="Polyfills/**/*.cs" />
</ItemGroup>
```

### Well-Known Metadata

Every item has built-in metadata accessible via `%(ItemName.MetadataName)`:

| Metadata | Value | Example for `src/Models/Order.cs` |
|---|---|---|
| `%(FullPath)` | Absolute path | `/repo/src/Models/Order.cs` |
| `%(RootDir)` | Root directory | `/` |
| `%(Directory)` | Directory relative to root | `repo/src/Models/` |
| `%(Filename)` | File name without extension | `Order` |
| `%(Extension)` | File extension | `.cs` |
| `%(RecursiveDir)` | Part matched by `**` in glob | `Models/` (if glob was `src/**/*.cs`) |
| `%(Identity)` | Item spec as declared | `src/Models/Order.cs` |

### Item Metadata and Batching

Custom metadata enables per-item behavior through MSBuild batching:

```xml
<ItemGroup>
  <DbMigration Include="migrations/*.sql">
    <TargetDb>main</TargetDb>
  </DbMigration>
  <DbMigration Include="migrations/audit/*.sql">
    <TargetDb>audit</TargetDb>
  </DbMigration>
</ItemGroup>

<!-- Batching: the task runs once per unique %(TargetDb) value -->
<Target Name="RunMigrations">
  <Exec Command="sqlcmd -d %(DbMigration.TargetDb) -i %(DbMigration.Identity)"
        Condition="'@(DbMigration)' != ''" />
</Target>
```

`%(Metadata)` in a task attribute triggers batching. MSBuild groups items by the metadata value and invokes the task once per group.


## Conditions

Conditions control whether properties, items, targets, and tasks are evaluated.

### Property Conditions

```xml
<PropertyGroup>
  <!-- Default: set only if not already defined -->
  <LangVersion Condition="'$(LangVersion)' == ''">latest</LangVersion>

  <!-- TFM condition -->
  <DefineConstants Condition="$(TargetFramework.StartsWith('net8'))">$(DefineConstants);NET8_OR_GREATER</DefineConstants>

  <!-- Configuration condition -->
  <Optimize Condition="'$(Configuration)' == 'Release'">true</Optimize>

  <!-- OS condition -->
  <RuntimeIdentifier Condition="$([MSBuild]::IsOSPlatform('Windows'))">win-x64</RuntimeIdentifier>
</PropertyGroup>
```

### Item and Target Conditions

```xml
<!-- Conditional item inclusion -->
<ItemGroup Condition="'$(TargetFramework)' == 'net8.0'">
  <PackageReference Include="Microsoft.Extensions.Hosting" Version="8.0.0" />
</ItemGroup>

<!-- Conditional target execution -->
<Target Name="SignAssembly"
        AfterTargets="Build"
        Condition="'$(Configuration)' == 'Release' AND '$(SignAssembly)' == 'true'">
  <Exec Command="signtool sign /fd SHA256 $(TargetPath)" />
</Target>
```

### Condition Operators

| Operator | Example |
|---|---|
| `==` / `!=` | `'$(Config)' == 'Release'` |
| `AND` / `OR` | `'$(A)' == '1' AND '$(B)' != ''` |
| `!` (negation) | `!Exists('$(OutDir)')` |
| `Exists()` | `Exists('$(SolutionDir)global.json')` |
| `HasTrailingSlash()` | `HasTrailingSlash('$(OutputPath)')` |

**Always single-quote both sides of comparisons.** `'$(Prop)' == 'value'` is correct. Unquoted comparisons fail when the property is empty.


## Property Functions

MSBuild properties can call .NET static methods and MSBuild intrinsic functions inline.

### .NET Static Method Calls

```xml
<PropertyGroup>
  <!-- String manipulation -->
  <NormalizedName>$([System.String]::Copy('$(PackageId)').ToLowerInvariant())</NormalizedName>

  <!-- Path combination (prefer over string concatenation) -->
  <ToolPath>$([System.IO.Path]::Combine('$(MSBuildThisFileDirectory)', 'tools', 'analyzer.dll'))</ToolPath>

  <!-- GUID generation -->
  <BuildId>$([System.Guid]::NewGuid().ToString('N'))</BuildId>

  <!-- Regex replacement -->
  <CleanVersion>$([System.Text.RegularExpressions.Regex]::Replace('$(Version)', '-.*$', ''))</CleanVersion>

  <!-- Environment variable -->
  <CiServer>$([System.Environment]::GetEnvironmentVariable('CI'))</CiServer>
</PropertyGroup>
```

### MSBuild Intrinsic Functions

```xml
<PropertyGroup>
  <!-- OS detection -->
  <IsWindows>$([MSBuild]::IsOSPlatform('Windows'))</IsWindows>
  <IsLinux>$([MSBuild]::IsOSPlatform('Linux'))</IsLinux>
  <IsMacOS>$([MSBuild]::IsOSPlatform('OSX'))</IsMacOS>

  <!-- Arithmetic -->
  <NextVersion>$([MSBuild]::Add($(PatchVersion), 1))</NextVersion>

  <!-- Version comparison (MSBuild 17.0+) -->
  <HasModernSdk>$([MSBuild]::VersionGreaterThanOrEquals('$(NETCoreSdkVersion)', '8.0.100'))</HasModernSdk>

  <!-- Stable hash for deterministic output -->
  <InputHash>$([MSBuild]::StableStringHash('$(InputFile)'))</InputHash>

  <!-- Path resolution: find file by walking up directory tree -->
  <SharedPropsPath>$([MSBuild]::GetPathOfFileAbove('SharedConfig.props', '$(MSBuildProjectDirectory)'))</SharedPropsPath>

  <!-- Normalize path separators -->
  <SafePath>$([MSBuild]::NormalizePath('$(MSBuildProjectDirectory)', '..', 'shared'))</SafePath>
</PropertyGroup>
```

### Useful MSBuild Properties

| Property | Value |
|---|---|
| `$(MSBuildProjectDirectory)` | Directory containing the current `.csproj` |
| `$(MSBuildThisFileDirectory)` | Directory containing the current `.props`/`.targets` file |
| `$(MSBuildProjectName)` | Project name without extension |
| `$(IntermediateOutputPath)` | `obj/` output path |
| `$(OutputPath)` | `bin/` output path |
| `$(TargetFramework)` | Current TFM (e.g., `net10.0`) |
| `$(TargetFrameworks)` | Multi-TFM list (e.g., `net8.0;net10.0`) |
| `$(Configuration)` | `Debug` or `Release` |
| `$(SolutionDir)` | Solution directory (only set when building from solution) |

**Use `$(MSBuildThisFileDirectory)` in `.props`/`.targets` files**, not `$(MSBuildProjectDirectory)`. The former resolves to the file's own location, which is correct when the file is imported from a NuGet package or a different directory.


## Directory.Build.props/targets Advanced Patterns

Basic Directory.Build layout is covered in `references/project-structure.md`. This section covers advanced patterns for multi-repo and monorepo scenarios.

### Import Chain with GetPathOfFileAbove

In monorepos with nested directories, each level can define its own `Directory.Build.props` that chains to the parent:

```
repo/
  Directory.Build.props            (repo-wide defaults)
  src/
    Directory.Build.props          (src-specific overrides)
    MyApp/
      MyApp.csproj
  tests/
    Directory.Build.props          (test-specific overrides)
    MyApp.Tests/
      MyApp.Tests.csproj
```

```xml
<!-- src/Directory.Build.props -->
<Project>
  <!-- Chain to parent Directory.Build.props (with existence guard) -->
  <PropertyGroup>
    <_ParentBuildProps>$([MSBuild]::GetPathOfFileAbove('Directory.Build.props', '$(MSBuildThisFileDirectory)..'))</_ParentBuildProps>
  </PropertyGroup>
  <Import Project="$(_ParentBuildProps)" Condition="'$(_ParentBuildProps)' != ''" />

  <PropertyGroup>
    <!-- Source-specific overrides -->
    <GenerateDocumentationFile>true</GenerateDocumentationFile>
  </PropertyGroup>
</Project>
```

```xml
<!-- tests/Directory.Build.props -->
<Project>
  <!-- Chain to parent Directory.Build.props (with existence guard) -->
  <PropertyGroup>
    <_ParentBuildProps>$([MSBuild]::GetPathOfFileAbove('Directory.Build.props', '$(MSBuildThisFileDirectory)..'))</_ParentBuildProps>
  </PropertyGroup>
  <Import Project="$(_ParentBuildProps)" Condition="'$(_ParentBuildProps)' != ''" />

  <PropertyGroup>
    <IsPackable>false</IsPackable>
    <IsTestProject>true</IsTestProject>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="Microsoft.NET.Test.Sdk" />
    <PackageReference Include="xunit.v3" />
    <PackageReference Include="xunit.runner.visualstudio" />
  </ItemGroup>
</Project>
```

### Condition Guards

Prevent property values from being overridden by child imports:

```xml
<!-- repo/Directory.Build.props -->
<Project>
  <PropertyGroup>
    <!-- Defaults: can be overridden by child Directory.Build.props or project -->
    <TreatWarningsAsErrors Condition="'$(TreatWarningsAsErrors)' == ''">true</TreatWarningsAsErrors>
    <Nullable Condition="'$(Nullable)' == ''">enable</Nullable>
    <ImplicitUsings Condition="'$(ImplicitUsings)' == ''">enable</ImplicitUsings>
  </PropertyGroup>
</Project>
```

**Rule:** Properties in `.props` files should use the `Condition="'$(Prop)' == ''"` guard so that inner `.props` files and project-level properties can override them. Properties you want to enforce unconditionally belong in `Directory.Build.targets` (which evaluates last).

### Preventing Double Imports

When multiple `Directory.Build.props` files chain upward, a shared import could be evaluated twice. Use a sentinel property to guard against this:

```xml
<!-- shared/Common.props -->
<Project>
  <!-- Guard: only evaluate once -->
  <PropertyGroup Condition="'$(_CommonPropsImported)' != 'true'">
    <_CommonPropsImported>true</_CommonPropsImported>
    <Authors>My Company</Authors>
    <Company>My Company</Company>
    <Copyright>Copyright (c) My Company. All rights reserved.</Copyright>
  </PropertyGroup>
</Project>
```

The sentinel and content properties must be in the **same** `PropertyGroup` with the `!= 'true'` condition. Putting content in a separate block with `== 'true'` does not prevent re-evaluation -- it runs on every import because the sentinel is already set.

A cleaner approach uses `Condition` on the `<Import>` element:

```xml
<!-- Only import if not already imported -->
<Import Project="$(SharedPropsPath)"
        Condition="'$(_CommonPropsImported)' != 'true' AND Exists('$(SharedPropsPath)')" />
```

### Enforcing Settings in Directory.Build.targets

Properties set in `.targets` files cannot be overridden by project-level `PropertyGroup` elements because they evaluate after the project body:

```xml
<!-- Directory.Build.targets -->
<Project>
  <!-- Enforced: projects cannot override these -->
  <PropertyGroup>
    <EnforceCodeStyleInBuild>true</EnforceCodeStyleInBuild>
    <AnalysisLevel>latest-recommended</AnalysisLevel>
  </PropertyGroup>

  <!-- Conditional enforcement: only for src projects -->
  <PropertyGroup Condition="'$(IsTestProject)' != 'true' AND '$(IsPackable)' != 'false'">
    <GenerateDocumentationFile>true</GenerateDocumentationFile>
  </PropertyGroup>
</Project>
```


## Agent Gotchas

1. **Unquoted condition comparisons.** Always quote both sides: `'$(Prop)' == 'value'`. Unquoted `$(Prop) == value` fails silently when the property is empty or contains spaces.

2. **Using `$(MSBuildProjectDirectory)` in shared `.props`/`.targets` files.** This resolves to the importing project's directory, not the file's own directory. Use `$(MSBuildThisFileDirectory)` to reference paths relative to the `.props`/`.targets` file itself.

3. **Setting properties in `.targets` and expecting project overrides.** Properties in `.targets` evaluate after the project body and override project-level values. If a property should be overridable, set it in `.props` with a `Condition="'$(Prop)' == ''"` guard.

4. **Adding `<Compile Include="**/*.cs" />` in SDK-style projects.** SDK-style projects auto-include all `*.cs` files. Explicit inclusion causes `NETSDK1022` duplicate items. Use `Remove` then `Include` for conditional scenarios.

5. **Missing `Outputs` on targets with `Inputs`.** A target with `Inputs` but no `Outputs` runs every build. Always pair them for incremental behavior.

6. **Using `$(SolutionDir)` in `.props`/`.targets` files.** This property is only set when building through a solution file. Command-line `dotnet build MyProject.csproj` leaves it empty. Use `$([MSBuild]::GetPathOfFileAbove('*.sln', '$(MSBuildProjectDirectory)'))` or pass paths relative to `$(MSBuildThisFileDirectory)`.

7. **Putting items in `PropertyGroup` or properties in `ItemGroup`.** Items (using `Include=`) must be in `<ItemGroup>`. Properties (using element value) must be in `<PropertyGroup>`. Mixing them produces silent evaluation failures.

8. **Forgetting `Condition` guard on parent import chain.** `GetPathOfFileAbove` returns empty string when no file is found. The `<Import>` must have `Condition="Exists('$(ResolvedPath)')"` or the build fails with a file-not-found error.


## References

- [MSBuild Reference](https://learn.microsoft.com/en-us/visualstudio/msbuild/msbuild-reference)
- [MSBuild Targets](https://learn.microsoft.com/en-us/visualstudio/msbuild/msbuild-targets)
- [MSBuild Items](https://learn.microsoft.com/en-us/visualstudio/msbuild/msbuild-items)
- [MSBuild Conditions](https://learn.microsoft.com/en-us/visualstudio/msbuild/msbuild-conditions)
- [MSBuild Property Functions](https://learn.microsoft.com/en-us/visualstudio/msbuild/property-functions)
- [MSBuild Well-Known Item Metadata](https://learn.microsoft.com/en-us/visualstudio/msbuild/msbuild-well-known-item-metadata)
- [Customize Your Build](https://learn.microsoft.com/en-us/visualstudio/msbuild/customize-your-build)
- [Directory.Build.props and Directory.Build.targets](https://learn.microsoft.com/en-us/visualstudio/msbuild/customize-by-directory)
