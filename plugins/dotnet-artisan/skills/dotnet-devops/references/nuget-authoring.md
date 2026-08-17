# NuGet Authoring

NuGet package authoring for .NET library authors: SDK-style `.csproj` package properties (`PackageId`, `PackageTags`, `PackageReadmeFile`, `PackageLicenseExpression`), source generator NuGet packaging with `analyzers/dotnet/cs/` folder layout and `buildTransitive` targets, multi-TFM packages, symbol packages (snupkg) with deterministic builds, package signing (author signing with certificates, repository signing), package validation (`EnablePackageValidation`, `Microsoft.DotNet.ApiCompat.Task` for API compatibility), and NuGet versioning strategies (SemVer 2.0, pre-release suffixes, NBGV integration).

**Version assumptions:** .NET 8.0+ baseline. NuGet client bundled with .NET 8+ SDK. `Microsoft.DotNet.ApiCompat.Task` 8.0+ for API compatibility validation.

## SDK-Style Package Properties

Every NuGet package starts with MSBuild properties in the `.csproj`. SDK-style projects produce NuGet packages with `dotnet pack` -- no `.nuspec` file required.

### Essential Package Metadata

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <PackageId>MyCompany.Widgets</PackageId>
    <Version>1.0.0</Version>
    <Authors>My Company</Authors>
    <Description>A library for managing widgets with fluent API support.</Description>
    <PackageTags>widgets;fluent;dotnet</PackageTags>
    <PackageLicenseExpression>MIT</PackageLicenseExpression>
    <PackageProjectUrl>https://github.com/mycompany/widgets</PackageProjectUrl>
    <RepositoryUrl>https://github.com/mycompany/widgets</RepositoryUrl>
    <RepositoryType>git</RepositoryType>

    <!-- README displayed on nuget.org package page -->
    <PackageReadmeFile>README.md</PackageReadmeFile>

    <!-- Package icon (128x128 PNG recommended) -->
    <PackageIcon>icon.png</PackageIcon>

    <!-- Generate XML docs for IntelliSense -->
    <GenerateDocumentationFile>true</GenerateDocumentationFile>

    <!-- Deterministic builds for reproducibility -->
    <ContinuousIntegrationBuild Condition="'$(CI)' == 'true'">true</ContinuousIntegrationBuild>
  </PropertyGroup>

  <!-- Include README and icon in the package -->
  <ItemGroup>
    <None Include="README.md" Pack="true" PackagePath="\" />
    <None Include="icon.png" Pack="true" PackagePath="\" />
  </ItemGroup>
</Project>
```

### Property Reference

| Property | Purpose | Example |
|----------|---------|---------|
| `PackageId` | Unique package identifier on nuget.org | `MyCompany.Widgets` |
| `Version` | SemVer 2.0 version | `1.2.3-beta.1` |
| `Authors` | Comma-separated author names | `Jane Doe, My Company` |
| `Description` | Package description for nuget.org | `Fluent widget management library` |
| `PackageTags` | Semicolon-separated search tags | `widgets;fluent;dotnet` |
| `PackageLicenseExpression` | SPDX license identifier | `MIT`, `Apache-2.0` |
| `PackageLicenseFile` | License file (alternative to expression) | `LICENSE.txt` |
| `PackageReadmeFile` | Markdown readme displayed on nuget.org | `README.md` |
| `PackageIcon` | Package icon filename | `icon.png` |
| `PackageProjectUrl` | Project homepage URL | `https://github.com/mycompany/widgets` |
| `PackageReleaseNotes` | Release notes for this version | `Added widget caching support` |
| `Copyright` | Copyright statement | `Copyright 2024 My Company` |
| `RepositoryUrl` | Source repository URL | `https://github.com/mycompany/widgets` |
| `RepositoryType` | Repository type | `git` |

### Directory.Build.props for Shared Metadata

For multi-project repos, set common properties in `Directory.Build.props`:

```xml
<!-- Directory.Build.props (repo root) -->
<Project>
  <PropertyGroup>
    <Authors>My Company</Authors>
    <PackageLicenseExpression>MIT</PackageLicenseExpression>
    <PackageProjectUrl>https://github.com/mycompany/widgets</PackageProjectUrl>
    <RepositoryUrl>https://github.com/mycompany/widgets</RepositoryUrl>
    <RepositoryType>git</RepositoryType>
    <Copyright>Copyright 2024 My Company</Copyright>
  </PropertyGroup>
</Project>
```

Individual `.csproj` files then only set package-specific properties (`PackageId`, `Description`, `PackageTags`).

---

## Source Generator NuGet Packaging

Source generators and analyzers require a specific NuGet package layout. The generator DLL must be placed in the `analyzers/dotnet/cs/` folder, not the `lib/` folder. For Roslyn source generator authoring (IIncrementalGenerator, syntax/semantic analysis), see [skill:dotnet-csharp]. This section covers NuGet *packaging* of generators only.

### Project Setup for Source Generator Package

```xml
<!-- MyCompany.Generators.csproj -->
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>netstandard2.0</TargetFramework>
    <EnforceExtendedAnalyzerRules>true</EnforceExtendedAnalyzerRules>
    <IsRoslynComponent>true</IsRoslynComponent>

    <!-- Package metadata -->
    <PackageId>MyCompany.Generators</PackageId>
    <Description>Source generators for widget auto-registration.</Description>

    <!-- Do NOT include generator DLL in lib/ folder -->
    <IncludeBuildOutput>false</IncludeBuildOutput>
    <SuppressDependenciesWhenPacking>true</SuppressDependenciesWhenPacking>

    <!-- Generator must target netstandard2.0 for Roslyn host compat -->
    <IsPackable>true</IsPackable>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="Microsoft.CodeAnalysis.CSharp" Version="4.8.0" PrivateAssets="all" />
  </ItemGroup>

  <!-- Place generator DLL in analyzers folder -->
  <ItemGroup>
    <None Include="$(OutputPath)$(AssemblyName).dll"
          Pack="true"
          PackagePath="analyzers/dotnet/cs"
          Visible="false" />
  </ItemGroup>
</Project>
```

### Adding Build Props/Targets

When a source generator needs to set MSBuild properties in consuming projects, use the `buildTransitive` folder:

```xml
<!-- build/MyCompany.Generators.props -->
<Project>
  <PropertyGroup>
    <MyCompanyGeneratorsEnabled>true</MyCompanyGeneratorsEnabled>
  </PropertyGroup>
  <ItemGroup>
    <!-- Example: add additional files for generator to consume -->
    <CompilerVisibleProperty Include="MyCompanyGeneratorsEnabled" />
  </ItemGroup>
</Project>
```

Include `buildTransitive` content in the package:

```xml
<!-- In the .csproj -->
<ItemGroup>
  <!-- buildTransitive ensures props/targets flow through transitive dependencies -->
  <None Include="build\MyCompany.Generators.props"
        Pack="true"
        PackagePath="buildTransitive\MyCompany.Generators.props" />
  <None Include="build\MyCompany.Generators.targets"
        Pack="true"
        PackagePath="buildTransitive\MyCompany.Generators.targets" />
</ItemGroup>
```

### Multi-Target Analyzer Package (Analyzer + Library)

When shipping both an analyzer and a runtime library in the same package:

```xml
<!-- MyCompany.Widgets.csproj (ships both runtime lib + analyzer) -->
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFrameworks>net8.0;netstandard2.0</TargetFrameworks>
    <PackageId>MyCompany.Widgets</PackageId>
  </PropertyGroup>

  <!-- Reference generator project, but suppress its output from lib/ -->
  <ItemGroup>
    <ProjectReference Include="..\MyCompany.Widgets.Generators\MyCompany.Widgets.Generators.csproj"
                      OutputItemType="Analyzer"
                      ReferenceOutputAssembly="false" />
  </ItemGroup>
</Project>
```

### NuGet Package Folder Layout

```
MyCompany.Generators.1.0.0.nupkg
  analyzers/
    dotnet/
      cs/
        MyCompany.Generators.dll          <-- generator/analyzer assembly
  buildTransitive/
    MyCompany.Generators.props            <-- auto-imported MSBuild props
    MyCompany.Generators.targets          <-- auto-imported MSBuild targets
  lib/
    netstandard2.0/
      _._                                <-- empty marker (no runtime lib)
```

---

## Multi-TFM Packages

Multi-targeting produces a single NuGet package with assemblies for each target framework. Consumers automatically get the best-matching assembly.

### When to Multi-Target

| Scenario | Approach |
|----------|----------|
| Library works on net8.0 only | Single TFM: `<TargetFramework>net8.0</TargetFramework>` |
| Library needs netstandard2.0 + net8.0 APIs | Multi-TFM: `<TargetFrameworks>netstandard2.0;net8.0</TargetFrameworks>` |
| Library uses net9.0-specific APIs (e.g., `SearchValues`) | Multi-TFM with polyfills or conditional code |
| Library targets .NET Framework consumers | Include `net472` or `netstandard2.0` TFM |

### Multi-TFM Configuration

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFrameworks>netstandard2.0;net8.0;net9.0</TargetFrameworks>
  </PropertyGroup>

  <!-- API differences per TFM -->
  <ItemGroup Condition="'$(TargetFramework)' == 'netstandard2.0'">
    <PackageReference Include="System.Memory" Version="4.6.0" />
    <PackageReference Include="System.Text.Json" Version="8.0.5" />
  </ItemGroup>
</Project>
```

### Conditional Compilation

```csharp
public static class StringExtensions
{
    public static bool ContainsIgnoreCase(this string source, string value)
    {
#if NET8_0_OR_GREATER
        return source.Contains(value, StringComparison.OrdinalIgnoreCase);
#else
        return source.IndexOf(value, StringComparison.OrdinalIgnoreCase) >= 0;
#endif
    }
}
```

### NuGet Package Folder Layout (Multi-TFM)

```
MyCompany.Widgets.1.0.0.nupkg
  lib/
    netstandard2.0/
      MyCompany.Widgets.dll
    net8.0/
      MyCompany.Widgets.dll
    net9.0/
      MyCompany.Widgets.dll
```

---

## Symbol Packages and Deterministic Builds

Symbol packages (`.snupkg`) enable source-level debugging for package consumers via the NuGet symbol server.

### Enabling Symbol Packages

```xml
<PropertyGroup>
  <!-- Generate .snupkg alongside .nupkg -->
  <IncludeSymbols>true</IncludeSymbols>
  <SymbolPackageFormat>snupkg</SymbolPackageFormat>

  <!-- Deterministic builds (required for reproducible packages) -->
  <Deterministic>true</Deterministic>
  <ContinuousIntegrationBuild Condition="'$(CI)' == 'true'">true</ContinuousIntegrationBuild>

  <!-- Embed source in PDB for debugging without source server -->
  <EmbedUntrackedSources>true</EmbedUntrackedSources>
</PropertyGroup>
```

The `snupkg` is pushed alongside the `nupkg` automatically when using `dotnet nuget push`:

```bash
# Push both .nupkg and .snupkg to nuget.org
dotnet nuget push "bin/Release/*.nupkg" \
  --source https://api.nuget.org/v3/index.json \
  --api-key "$NUGET_API_KEY"
```

**SourceLink integration:** For source-level debugging with links to the actual source repository, configure SourceLink in your project. See [skill:dotnet-tooling] for SourceLink setup -- do not duplicate that configuration here.

### Embedded PDB Alternative

For packages where a separate symbol package is undesirable:

```xml
<PropertyGroup>
  <DebugType>embedded</DebugType>
</PropertyGroup>
```

This embeds the PDB directly in the assembly DLL. The tradeoff is larger package size but simpler distribution.

---

## Package Signing

NuGet supports author signing (proving package origin) and repository signing (proving it came from a specific feed).

### Author Signing with a Certificate

```bash
# Sign a package with a PFX certificate
dotnet nuget sign "MyCompany.Widgets.1.0.0.nupkg" \
  --certificate-path ./signing-cert.pfx \
  --certificate-password "$CERT_PASSWORD" \
  --timestamper http://timestamp.digicert.com

# Sign with a certificate from the certificate store (Windows)
dotnet nuget sign "MyCompany.Widgets.1.0.0.nupkg" \
  --certificate-fingerprint "ABC123..." \
  --timestamper http://timestamp.digicert.com
```

### Certificate Requirements

| Requirement | Detail |
|-------------|--------|
| Key usage | Code signing (1.3.6.1.5.5.7.3.3) |
| Algorithm | RSA 2048-bit minimum |
| Timestamping | Required for long-term validity |
| Trusted CA | DigiCert, Sectigo, or other trusted CA for nuget.org |
| Self-signed | Accepted for private feeds; rejected by nuget.org |

### Repository Signing

Repository signing is applied by feed operators (e.g., nuget.org signs all packages). Package authors do not need to configure repository signing -- it is applied automatically by the feed infrastructure.

### Verifying Package Signatures

```bash
# Verify a signed package
dotnet nuget verify "MyCompany.Widgets.1.0.0.nupkg"

# Verify with verbose output
dotnet nuget verify "MyCompany.Widgets.1.0.0.nupkg" --verbosity detailed
```

---

## Package Validation

Package validation catches API breaks, invalid package layouts, and compatibility issues before publishing.

### Built-in Pack Validation

```xml
<PropertyGroup>
  <!-- Enable package validation on dotnet pack -->
  <EnablePackageValidation>true</EnablePackageValidation>
</PropertyGroup>
```

This validates:
- All TFMs have compatible API surface
- No accidental API removals between package versions
- Package layout follows NuGet conventions

### API Compatibility with Baseline Version

Compare the current package against a previously published baseline version to detect breaking changes:

```xml
<PropertyGroup>
  <EnablePackageValidation>true</EnablePackageValidation>
  <!-- Compare against last released version -->
  <PackageValidationBaselineVersion>1.0.0</PackageValidationBaselineVersion>
</PropertyGroup>
```

### Microsoft.DotNet.ApiCompat.Task

For advanced API compatibility checking across assemblies:

```xml
<ItemGroup>
  <PackageReference Include="Microsoft.DotNet.ApiCompat.Task" Version="8.0.0" PrivateAssets="all" />
</ItemGroup>

<PropertyGroup>
  <!-- Enable API compat analysis -->
  <ApiCompatEnableRuleAttributesMustMatch>true</ApiCompatEnableRuleAttributesMustMatch>
  <ApiCompatEnableRuleCannotChangeParameterName>true</ApiCompatEnableRuleCannotChangeParameterName>
</PropertyGroup>
```

### Suppressing Known Breaks

When intentional API changes are made, generate and commit a suppression file:

```bash
# Generate suppression file for known breaks
dotnet pack /p:GenerateCompatibilitySuppressionFile=true
```

This creates `CompatibilitySuppressions.xml`:

```xml
<!-- CompatibilitySuppressions.xml (committed to source control) -->
<?xml version="1.0" encoding="utf-8"?>
<Suppressions xmlns:ns="https://learn.microsoft.com/dotnet/fundamentals/package-validation/diagnostic-ids">
  <Suppression>
    <DiagnosticId>CP0002</DiagnosticId>
    <Target>M:MyCompany.Widgets.Widget.OldMethod</Target>
    <Left>lib/net8.0/MyCompany.Widgets.dll</Left>
    <Right>lib/net8.0/MyCompany.Widgets.dll</Right>
  </Suppression>
</Suppressions>
```

Reference the suppression file:

```xml
<ItemGroup>
  <ApiCompatSuppressionFile Include="CompatibilitySuppressions.xml" />
</ItemGroup>
```

---

## NuGet Versioning Strategies

### SemVer 2.0 for NuGet

NuGet follows Semantic Versioning 2.0:

| Version | Meaning |
|---------|---------|
| `1.0.0` | Stable release |
| `1.0.1` | Patch (bug fixes, no API changes) |
| `1.1.0` | Minor (new features, backward compatible) |
| `2.0.0` | Major (breaking changes) |
| `1.0.0-alpha.1` | Pre-release alpha |
| `1.0.0-beta.1` | Pre-release beta |
| `1.0.0-rc.1` | Release candidate |

### Pre-release Suffixes

```xml
<!-- Stable release -->
<Version>1.2.3</Version>

<!-- Pre-release with SemVer 2.0 dot-separated suffix -->
<Version>1.2.3-beta.1</Version>

<!-- CI build with commit height (NBGV pattern) -->
<!-- Produces: 1.2.3-beta.42+abcdef -->
```

### NBGV Integration

Nerdbank.GitVersioning (NBGV) calculates versions from git history. For NBGV setup and `version.json` configuration, see [skill:dotnet-devops] `references/release-management.md`. This skill covers how NBGV-generated versions interact with NuGet packaging:

```xml
<PropertyGroup>
  <!-- NBGV sets Version, PackageVersion, AssemblyVersion automatically -->
  <!-- Do NOT set Version explicitly when using NBGV -->
</PropertyGroup>
```

NBGV produces versions like `1.2.42-beta+abcdef` where:
- `1.2` comes from `version.json`
- `42` is git commit height
- `-beta` is the pre-release suffix from `version.json`
- `+abcdef` is the git commit hash (build metadata, ignored by NuGet resolution)

### Version Properties Reference

| Property | Purpose | Set By |
|----------|---------|--------|
| `Version` | Full SemVer version (drives PackageVersion) | Manual or NBGV |
| `PackageVersion` | NuGet package version (defaults to Version) | Manual or NBGV |
| `AssemblyVersion` | CLR assembly version | Manual or NBGV |
| `FileVersion` | Windows file version | Manual or NBGV |
| `InformationalVersion` | Full version string with metadata | Manual or NBGV |

---

## Packing and Local Testing

### Building the Package

```bash
# Pack in Release configuration
dotnet pack --configuration Release

# Pack with specific version override
dotnet pack --configuration Release /p:Version=1.2.3-beta.1

# Output to specific directory
dotnet pack --configuration Release --output ./artifacts
```

### Local Feed Testing

Test a package locally before publishing:

```bash
# Create a local feed directory
mkdir -p ~/local-nuget-feed

# Add the package to the local feed
dotnet nuget push "bin/Release/MyCompany.Widgets.1.0.0.nupkg" \
  --source ~/local-nuget-feed

# In the consuming project, add the local feed
dotnet nuget add source ~/local-nuget-feed --name LocalFeed
```

### Package Content Inspection

```bash
# List package contents (nupkg is a zip file)
unzip -l MyCompany.Widgets.1.0.0.nupkg

# Verify analyzer placement
unzip -l MyCompany.Generators.1.0.0.nupkg | grep analyzers/
```

---

## Agent Gotchas

1. **Do not set both `PackageLicenseExpression` and `PackageLicenseFile`** -- they are mutually exclusive. Use `PackageLicenseExpression` for standard SPDX identifiers, `PackageLicenseFile` for custom licenses only.

2. **Source generators MUST target `netstandard2.0`** -- the Roslyn host requires this. Do not multi-target generators themselves; multi-target the runtime library that references the generator project.

3. **Do not set `IncludeBuildOutput` to `false` on library projects** -- only on pure analyzer/generator projects that should not contribute runtime assemblies.

4. **`buildTransitive` vs `build` folder** -- use `buildTransitive` for props/targets that should flow through transitive `PackageReference` dependencies. The `build` folder only affects direct consumers.

5. **Package validation suppression uses `ApiCompatSuppressionFile` with `CompatibilitySuppressions.xml`** -- not a `PackageValidationSuppression` MSBuild item. Generate the file with `/p:GenerateCompatibilitySuppressionFile=true`.

6. **SDK-style projects auto-include all `*.cs` files** -- adding TFM-conditional `Compile Include` without a preceding `Compile Remove` causes NETSDK1022 duplicate items.

7. **Never hardcode API keys in CLI examples** -- always use environment variable placeholders (`$NUGET_API_KEY`) with a note about CI secret storage.

8. **`ContinuousIntegrationBuild` must be conditional on CI** -- setting it unconditionally breaks local debugging by making PDBs non-reproducible with local file paths.
