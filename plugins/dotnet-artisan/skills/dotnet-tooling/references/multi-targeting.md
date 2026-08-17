# Multi-Targeting

Comprehensive guide for .NET multi-targeting strategies with a polyfill-first approach. This skill consumes the structured output from `references/version-detection.md` (TFM, C# version, preview flags) and provides actionable guidance on backporting language features, handling runtime gaps, and validating API compatibility across target frameworks.

## Decision Matrix: Polyfill vs Conditional Compilation

Use this matrix to select the correct strategy for each type of gap between your highest and lowest TFMs.

| Gap Type | Strategy | When to Use | Example |
|----------|----------|-------------|---------|
| Language/syntax feature | Polyfill (PolySharp) | Compiler needs attribute/type stubs to emit newer syntax on older TFMs | `required` modifier, `init` properties, `SetsRequiredMembers` on net8.0 |
| BCL API addition | Polyfill (SimonCropp/Polyfill) if available, else `#if` | A newer BCL type or method is missing on older TFMs | `System.Threading.Lock` on net8.0, `Index`/`Range` on netstandard2.0 |
| Runtime behavior difference | Conditional compilation (`#if`) or adapter pattern | Behavior differs at runtime regardless of compilation | Runtime-async (net11.0 only), different GC modes, `SearchValues<T>` runtime optimizations |
| Platform API divergence | Conditional compilation with `[SupportedOSPlatform]` | API exists only on specific OS targets | Windows Registry APIs, Android-specific intents, iOS keychain |

**Decision flow:**
1. Can a compile-time polyfill satisfy the gap? Use PolySharp or SimonCropp/Polyfill.
2. Is the gap a missing BCL API with no polyfill available? Use `#if` with TFM-specific code.
3. Is the gap a runtime behavior difference? Use `#if` or the adapter pattern to isolate divergent code paths.
4. Is the gap platform-specific? Use `#if` with `[SupportedOSPlatform]` attributes.


## PolySharp (Compiler-Synthesized Polyfills)

PolySharp is a source generator that synthesizes the attribute and type stubs the C# compiler needs to emit newer language features when targeting older TFMs. It operates entirely at compile time -- no runtime dependencies are added.

### What PolySharp Provides

- `required` modifier support (C# 11+)
- `init` property accessors (C# 9+)
- `SetsRequiredMembers` attribute
- `CompilerFeatureRequired` attribute
- `IsExternalInit` type
- `CallerArgumentExpression` attribute
- `StackTraceHidden` attribute
- `UnscopedRef` attribute
- `InterpolatedStringHandler` attributes
- `ModuleInitializer` attribute
- Index and Range support types

### Setup

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFrameworks>net8.0;net10.0</TargetFrameworks>
    <!-- Use the highest C# version across all TFMs -->
    <LangVersion>14</LangVersion>
  </PropertyGroup>

  <ItemGroup>
    <!-- PolySharp is a source generator; it adds no runtime dependency -->
    <PackageReference Include="PolySharp" Version="1.*">
      <PrivateAssets>all</PrivateAssets>
      <IncludeAssets>runtime; build; native; contentfiles; analyzers</IncludeAssets>
    </PackageReference>
  </ItemGroup>
</Project>
```

### How It Works

PolySharp detects which polyfill types are missing for the current TFM and generates source for only those types. On net10.0, where `required` is natively supported, the generator emits nothing -- zero overhead.

```csharp
// This compiles on net8.0 WITH PolySharp installed,
// because PolySharp generates the required CompilerFeatureRequired
// and IsExternalInit types that the compiler needs.
public class UserProfile
{
    public required string DisplayName { get; init; }
    public required string Email { get; init; }
    public string? Bio { get; set; }
}
```

### PolySharp Limitations

- PolySharp provides **compiler stubs only**. It does not backport runtime behavior.
- Features that require runtime support (e.g., runtime-async, `SearchValues<T>` hardware acceleration) cannot be polyfilled.
- If a feature needs both a compiler attribute AND a BCL API (e.g., collection expressions with `Span<T>` overloads), you may need both PolySharp and SimonCropp/Polyfill.


## SimonCropp/Polyfill (BCL API Polyfills)

SimonCropp/Polyfill provides source-generated implementations of newer BCL APIs for older TFMs. Unlike PolySharp (which provides compiler attribute stubs), Polyfill provides actual method and type implementations.

### What Polyfill Provides

Key polyfilled APIs (non-exhaustive):

- `System.Threading.Lock` (C# 13 / net9.0+)
- `String.Contains(char)`, `String.Contains(string, StringComparison)`
- `String.ReplaceLineEndings()`
- `HashCode` struct
- `SkipLocalsInit` attribute
- `TaskCompletionSource` (non-generic)
- `Stream.ReadExactly`, `Stream.ReadAtLeast`
- `Memory<T>` and `Span<T>` extensions
- `IReadOnlySet<T>` interface
- Various LINQ additions (`TryGetNonEnumeratedCount`, `DistinctBy`, `Chunk`, etc.)

### Setup

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFrameworks>net8.0;net10.0</TargetFrameworks>
    <LangVersion>14</LangVersion>
  </PropertyGroup>

  <ItemGroup>
    <!-- Polyfill is a source generator; no runtime dependency -->
    <PackageReference Include="Polyfill" Version="7.*">
      <PrivateAssets>all</PrivateAssets>
      <IncludeAssets>runtime; build; native; contentfiles; analyzers</IncludeAssets>
    </PackageReference>
  </ItemGroup>
</Project>
```

### Usage Example

```csharp
// System.Threading.Lock is a net9.0+ type.
// With Polyfill installed, this compiles on net8.0.
public class ThrottledProcessor
{
    private readonly Lock _lock = new();

    public void Process(string item)
    {
        lock (_lock)
        {
            // Lock provides better diagnostics than object-based locking
            Console.WriteLine($"Processing: {item}");
        }
    }
}
```

### Combining PolySharp and Polyfill

For maximum compatibility, use both packages together. They are complementary and do not conflict:

```xml
<ItemGroup>
  <!-- PolySharp: compiler attribute stubs (required, init, etc.) -->
  <PackageReference Include="PolySharp" Version="1.*">
    <PrivateAssets>all</PrivateAssets>
    <IncludeAssets>runtime; build; native; contentfiles; analyzers</IncludeAssets>
  </PackageReference>

  <!-- Polyfill: BCL API implementations (Lock, LINQ additions, etc.) -->
  <PackageReference Include="Polyfill" Version="7.*">
    <PrivateAssets>all</PrivateAssets>
    <IncludeAssets>runtime; build; native; contentfiles; analyzers</IncludeAssets>
  </PackageReference>
</ItemGroup>
```

With both installed, you get full language feature support (PolySharp) **and** BCL API backporting (Polyfill) on older TFMs.


## Conditional Compilation

Use conditional compilation (`#if`) when the gap is a runtime behavior difference or a platform API that cannot be polyfilled at compile time.

### TFM-Based Conditionals

The compiler defines preprocessor symbols for each TFM. Use `NET8_0_OR_GREATER`-style symbols (available since .NET 5) for version range checks:

```csharp
public static class PerformanceHelper
{
#if NET10_0_OR_GREATER
    // net10.0+ has optimized SearchValues with hardware acceleration
    private static readonly SearchValues<char> s_vowels =
        SearchValues.Create("aeiouAEIOU");

    public static int CountVowels(ReadOnlySpan<char> text)
        => text.Count(s_vowels);
#else
    // Fallback for net8.0: manual loop
    public static int CountVowels(ReadOnlySpan<char> text)
    {
        int count = 0;
        foreach (char c in text)
        {
            if ("aeiouAEIOU".Contains(c))
                count++;
        }
        return count;
    }
#endif
}
```

### Available Preprocessor Symbols

| Symbol | True When |
|--------|-----------|
| `NET8_0` | Exactly net8.0 |
| `NET8_0_OR_GREATER` | net8.0 or any higher version |
| `NET9_0_OR_GREATER` | net9.0 or any higher version |
| `NET10_0_OR_GREATER` | net10.0 or any higher version |
| `NET11_0_OR_GREATER` | net11.0 or any higher version |
| `NETSTANDARD2_0` | Exactly netstandard2.0 |
| `NETSTANDARD2_0_OR_GREATER` | netstandard2.0 or higher |

### When #if Is Correct

1. **Runtime behavior gap:** The API exists on both TFMs but behaves differently at runtime (e.g., `GC.Collect` modes, `HttpClient` connection pooling behavior).
2. **No polyfill available:** The BCL API is not covered by SimonCropp/Polyfill and cannot be stubbed.
3. **Performance-critical path:** You want to use a TFM-specific optimized API path (e.g., `SearchValues<T>`, `FrozenDictionary<K,V>`).
4. **Platform API:** The API is available only on a specific OS platform target.

### When #if Is Wrong

- **Language syntax feature** (e.g., `required`, `init`): Use PolySharp instead.
- **Missing BCL method** that has a polyfill (e.g., `System.Threading.Lock`): Use SimonCropp/Polyfill instead.
- Wrapping entire files in `#if` blocks -- use TFM-specific source files instead (see below).


## Multi-Targeting .csproj Patterns

### Basic Multi-Targeting

```xml
<PropertyGroup>
  <!-- Semicolon-delimited list of TFMs -->
  <TargetFrameworks>net8.0;net10.0</TargetFrameworks>
  <!-- Use the highest C# version to access all language features -->
  <LangVersion>14</LangVersion>
</PropertyGroup>
```

### Conditional Package References

Some packages are only needed on specific TFMs:

```xml
<ItemGroup>
  <!-- Polyfill packages: only needed on older TFMs, but safe to reference
       unconditionally because they emit nothing when features are native -->
  <PackageReference Include="PolySharp" Version="1.*">
    <PrivateAssets>all</PrivateAssets>
    <IncludeAssets>runtime; build; native; contentfiles; analyzers</IncludeAssets>
  </PackageReference>

  <!-- TFM-conditional package: only available/needed on specific TFMs -->
  <PackageReference Include="System.Text.Json" Version="9.*"
                    Condition="'$(TargetFramework)' == 'net8.0'" />
</ItemGroup>
```

### TFM-Specific Source Files

For large blocks of TFM-specific code, use dedicated source files instead of `#if` blocks:

```xml
<ItemGroup>
  <!-- SDK-style projects auto-include all *.cs files. Remove TFM-specific
       directories first to avoid NETSDK1022 duplicate compile items. -->
  <Compile Remove="Compatibility\**\*.cs" />

  <!-- Then conditionally include only the files for the current TFM -->
  <Compile Include="Compatibility\Net8\**\*.cs"
           Condition="'$(TargetFramework)' == 'net8.0'" />
  <Compile Include="Compatibility\Net10\**\*.cs"
           Condition="$([MSBuild]::IsTargetFrameworkCompatible('$(TargetFramework)', 'net10.0'))" />
</ItemGroup>
```

Directory structure:
```
MyLibrary/
  Compatibility/
    Net8/
      SearchValuesCompat.cs
    Net10/
      SearchValuesNative.cs
  Services/
    TextAnalyzer.cs          # shared code, references interface
  MyLibrary.csproj
```

### Platform-Specific TFMs

For projects targeting platform-specific TFMs (MAUI, Uno):

```xml
<PropertyGroup>
  <!-- Use version-agnostic platform globs where possible -->
  <TargetFrameworks>net10.0;net10.0-android;net10.0-ios;net10.0-windows10.0.19041.0</TargetFrameworks>
</PropertyGroup>

<ItemGroup Condition="$([MSBuild]::GetTargetPlatformIdentifier('$(TargetFramework)')) == 'android'">
  <PackageReference Include="Xamarin.AndroidX.Core" Version="1.*" />
</ItemGroup>
```

### Shared Properties via Directory.Build.props

For multi-project solutions, centralize multi-targeting configuration:

```xml
<!-- Directory.Build.props -->
<Project>
  <PropertyGroup>
    <LangVersion>14</LangVersion>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="PolySharp" Version="1.*">
      <PrivateAssets>all</PrivateAssets>
      <IncludeAssets>runtime; build; native; contentfiles; analyzers</IncludeAssets>
    </PackageReference>
    <PackageReference Include="Polyfill" Version="7.*">
      <PrivateAssets>all</PrivateAssets>
      <IncludeAssets>runtime; build; native; contentfiles; analyzers</IncludeAssets>
    </PackageReference>
  </ItemGroup>
</Project>
```

This ensures all projects in the solution share the same polyfill setup. Individual projects set their own `<TargetFrameworks>`.


## API Compatibility Validation

When publishing a NuGet package that targets multiple TFMs, validate that the public API surface is consistent and that you have not accidentally broken consumers.

### EnablePackageValidation

Package validation runs automatically during `dotnet pack` and checks:
- **Baseline validation:** Compares the current package against a previous version to detect breaking changes.
- **Compatible framework validation:** Ensures APIs available on one TFM are available on all compatible TFMs.

```xml
<PropertyGroup>
  <TargetFrameworks>net8.0;net10.0</TargetFrameworks>
  <!-- Enable package validation during pack -->
  <EnablePackageValidation>true</EnablePackageValidation>
  <!-- Compare against last published version for breaking change detection -->
  <PackageValidationBaselineVersion>1.2.0</PackageValidationBaselineVersion>
</PropertyGroup>
```

### API Compatibility Workflow

**Step 1: Enable validation in .csproj**

```xml
<PropertyGroup>
  <EnablePackageValidation>true</EnablePackageValidation>
</PropertyGroup>
```

**Step 2: Set baseline version (for existing packages)**

```xml
<PropertyGroup>
  <!-- The last published stable version to compare against -->
  <PackageValidationBaselineVersion>2.0.0</PackageValidationBaselineVersion>
</PropertyGroup>
```

**Step 3: Pack and check**

```bash
# Pack triggers validation automatically
dotnet pack --configuration Release

# Success: no output about compatibility issues
# Failure: error messages listing incompatible API changes
```

**Step 4: Interpret results**

| Result | Meaning | Action |
|--------|---------|--------|
| Clean pack | All TFMs expose compatible API surfaces; no breaking changes from baseline | Ship |
| `CP0001` | Missing type on a compatible TFM | Add the type to the TFM or use `#if` to exclude it from the public API |
| `CP0002` | Missing member on a compatible TFM | Add the member or suppress if intentional |
| `CP0003` | Breaking change from baseline version | Bump major version or revert the change |
| `PKV004` | Compatible TFM has different API surface | Ensure conditional APIs are intentional |

### Suppressing Known Differences

For intentional API differences between TFMs, use a suppression file. Package validation can generate one when suppression generation is enabled:

```bash
# Build with suppression-file generation enabled
dotnet pack /p:ApiCompatGenerateSuppressionFile=true
# Creates CompatibilitySuppressions.xml in the project directory
```

The generated `CompatibilitySuppressions.xml` contains targeted suppressions:

```xml
<?xml version="1.0" encoding="utf-8"?>
<Suppressions xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
              xmlns:xsd="http://www.w3.org/2001/XMLSchema">
  <Suppression>
    <DiagnosticId>CP0002</DiagnosticId>
    <Target>M:MyLib.PerformanceHelper.CountVowels(System.ReadOnlySpan{System.Char})</Target>
    <Left>lib/net8.0/MyLib.dll</Left>
    <Right>lib/net10.0/MyLib.dll</Right>
  </Suppression>
</Suppressions>
```

Reference the suppression file in .csproj (automatic when file is at project root):

```xml
<PropertyGroup>
  <!-- Explicit path if suppression file is not at project root -->
  <ApiCompatSuppressionFile>CompatibilitySuppressions.xml</ApiCompatSuppressionFile>
</PropertyGroup>
```

**Prefer targeted suppression files over blanket `<NoWarn>$(NoWarn);CP0002</NoWarn>`** -- blanket suppression hides real issues. Commit the suppression file to source control so reviewers can see intentional API differences.

### ApiCompat Standalone Tool

For CI pipelines that validate without packing:

```bash
# Install as a global tool
dotnet tool install -g Microsoft.DotNet.ApiCompat.Tool

# Global tool invocation (after install -g)
apicompat --left-assembly bin/Release/net8.0/MyLib.dll \
          --right-assembly bin/Release/net10.0/MyLib.dll

# Or install as a local tool (preferred for CI reproducibility)
dotnet new tool-manifest   # if .config/dotnet-tools.json doesn't exist
dotnet tool install Microsoft.DotNet.ApiCompat.Tool

# Local tool invocation
dotnet tool run apicompat --left-assembly bin/Release/net8.0/MyLib.dll \
                          --right-assembly bin/Release/net10.0/MyLib.dll
```


## Agent Gotchas

1. **Do not use `#if` for language feature polyfills.** If the gap is a compiler attribute or syntax feature (e.g., `required`, `init`, `SetsRequiredMembers`), use PolySharp. `#if` blocks for language features create unnecessary code duplication and maintenance burden.

2. **Do not omit `<PrivateAssets>all</PrivateAssets>` on polyfill packages.** PolySharp and SimonCropp/Polyfill are source generators meant for compile time only. Without `PrivateAssets=all`, the polyfill types leak into your package's dependency graph and can conflict with consumers' own polyfills.

3. **Do not hardcode TFM versions in conditional compilation.** Use `NET10_0_OR_GREATER`-style range symbols instead of `NET10_0` exact symbols. Exact symbols break when a new TFM is added (e.g., net11.0 would skip the net10.0-specific path). Range symbols automatically include future TFMs.

4. **Do not set `<LangVersion>` per TFM.** Set it once to the highest version needed across all TFMs (e.g., `<LangVersion>14</LangVersion>`). PolySharp and Polyfill handle the backporting. Per-TFM LangVersion causes confusing syntax errors.

5. **Do not skip `EnablePackageValidation` for multi-targeted NuGet packages.** Without it, you can accidentally expose different API surfaces on different TFMs, causing consumer build failures when they switch TFMs.

6. **Do not use `$(TargetFramework)` string equality for range checks in MSBuild conditions.** Use `$([MSBuild]::IsTargetFrameworkCompatible('$(TargetFramework)', 'net10.0'))` for forward-compatible range checks. String equality (e.g., `== 'net10.0'`) misses net11.0 and higher.

7. **Do not re-implement TFM detection.** This skill consumes the structured output from `references/version-detection.md`. Never parse `.csproj` files to determine TFMs -- use the detection skill's output (TFM, C# version, SDK version, warnings).

8. **Do not assume polyfills cover runtime behavior.** PolySharp and Polyfill provide compile-time stubs and source-generated implementations. Features that require runtime changes (e.g., runtime-async, GC improvements, JIT optimizations) cannot be polyfilled -- use `#if` for these.

9. **Do not use version-specific TFM globs for platform targets.** Use `net*-android` pattern matching (version-agnostic) instead of `net10.0-android` in documentation and tooling to avoid false negatives when users target different .NET versions.


## Prerequisites

- .NET 8.0+ SDK (multi-targeting requires the highest targeted SDK installed)
- `PolySharp` NuGet package (for language feature polyfills)
- `Polyfill` NuGet package by Simon Cropp (for BCL API polyfills)
- `Microsoft.DotNet.ApiCompat.Tool` (optional, for standalone API compatibility checks)
- Output from `references/version-detection.md` (TFM, C# version, SDK version)


## References

> **Last verified: 2026-02-12**

- [PolySharp - Source Generator for Polyfill Attributes](https://github.com/Sergio0694/PolySharp)
- [SimonCropp/Polyfill - Source-Only BCL Polyfills](https://github.com/SimonCropp/Polyfill)
- [.NET Target Framework Monikers](https://learn.microsoft.com/en-us/dotnet/standard/frameworks)
- [Multi-Targeting in .NET](https://learn.microsoft.com/en-us/dotnet/standard/library-guidance/cross-platform-targeting)
- [C# Preprocessor Directives](https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/preprocessor-directives)
- [Package Validation Overview](https://learn.microsoft.com/en-us/dotnet/fundamentals/package-validation/overview)
- [API Compatibility Overview](https://learn.microsoft.com/en-us/dotnet/fundamentals/apicompat/overview)
- [MSBuild Target Framework Properties](https://learn.microsoft.com/en-us/dotnet/core/project-sdk/msbuild-props#targetframework)
