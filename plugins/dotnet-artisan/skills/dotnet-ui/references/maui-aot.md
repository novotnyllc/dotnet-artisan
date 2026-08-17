# MAUI AOT

Native AOT compilation for .NET MAUI on iOS and Mac Catalyst: compilation pipeline, publish profiles, up to 50% app size reduction and up to 50% startup improvement, library compatibility gaps, opt-out mechanisms, trimming interplay (RD.xml, source generators), and testing AOT builds on device.

**Version assumptions:** .NET 8.0+ baseline. Native AOT for MAUI is available on iOS and Mac Catalyst. Android uses a different compilation model (CoreCLR in .NET 11, Mono/AOT in .NET 8-10).

## iOS/Mac Catalyst AOT Compilation Pipeline

Native AOT on iOS and Mac Catalyst compiles .NET IL directly to native machine code at publish time, eliminating the need for a JIT compiler or IL interpreter at runtime. This produces a self-contained native binary that links against platform frameworks.

### How It Works

1. **IL compilation:** The .NET IL is compiled to native code by the NativeAOT compiler (ILC)
2. **Tree shaking:** Unused code is trimmed based on static analysis of reachable types and methods
3. **Native linking:** The generated native code is linked with iOS/Catalyst frameworks and the minimal .NET runtime
4. **App bundle:** The result is a standard `.app` bundle with a native executable (no IL assemblies shipped)

### Publish Configuration

```xml
<!-- Enable Native AOT for iOS/Mac Catalyst -->
<PropertyGroup Condition="'$(TargetFramework)' == 'net8.0-ios' Or
                          '$(TargetFramework)' == 'net8.0-maccatalyst'">
  <PublishAot>true</PublishAot>
  <!-- Optional: strip debug symbols for smaller binary -->
  <StripSymbols>true</StripSymbols>
</PropertyGroup>
```

```bash
# Publish with AOT for iOS
dotnet publish -f net8.0-ios -c Release -r ios-arm64

# Publish with AOT for Mac Catalyst
dotnet publish -f net8.0-maccatalyst -c Release -r maccatalyst-arm64

# Publish for iOS simulator (for AOT testing without device)
dotnet publish -f net8.0-ios -c Release -r iossimulator-arm64
```

### Entitlements and Provisioning

AOT builds require the same entitlements and provisioning profiles as regular iOS/Catalyst builds. No additional entitlements are needed for AOT specifically.

```xml
<!-- iOS entitlements (Entitlements.plist) -->
<!-- Standard entitlements; AOT does not require special entries -->
```


## Size Reduction

Native AOT can achieve **up to 50% app size reduction** compared to interpreter/JIT mode on iOS. The size improvement comes from:

- **Tree shaking:** Only reachable code is included in the final binary
- **No IL shipping:** The app bundle does not include .NET IL assemblies
- **No runtime JIT:** The JIT compiler and associated metadata are not packaged

### Typical Size Comparison

| Mode | Approximate Size | Notes |
|------|-----------------|-------|
| Interpreter (default .NET 8 iOS) | ~60-80 MB | Includes IL assemblies + interpreter |
| Native AOT | ~30-45 MB | Native binary only, no IL |
| Native AOT + StripSymbols | ~25-40 MB | Debug symbols stripped |

**Caveat:** Actual size reduction depends on app complexity, third-party library usage, and how much code is reachable after trimming. Libraries that use heavy reflection may prevent aggressive trimming and reduce size gains.


## Startup Improvement

Native AOT provides **up to 50% faster cold startup** on iOS and Mac Catalyst. The startup improvement comes from:

- **No JIT warmup:** Code is already native; no compilation at app launch
- **No IL loading:** No need to load and parse .NET assemblies
- **Reduced memory pressure:** Smaller working set during startup

### Measuring Startup

```csharp
// Instrument startup timing
public partial class App : Application
{
    private static readonly long StartTicks = Stopwatch.GetTimestamp();

    public App()
    {
        InitializeComponent();
        MainPage = new AppShell();

        var elapsed = Stopwatch.GetElapsedTime(StartTicks);
        System.Diagnostics.Debug.WriteLine(
            $"App startup: {elapsed.TotalMilliseconds:F0}ms");
    }
}
```

```bash
# Use Xcode Instruments for precise startup measurement
# Time Profiler template → measure "pre-main" + "post-main" time
# Compare AOT vs non-AOT builds on the same device
```


## Library Compatibility

Many .NET libraries are not fully AOT-compatible. Common compatibility issues stem from:

- **Reflection:** Runtime type inspection, `Type.GetType()`, `Activator.CreateInstance()`
- **Dynamic code generation:** `System.Reflection.Emit`, `System.Linq.Expressions.Compile()`
- **Serialization without source generators:** JSON/XML serializers that use reflection

### Compatibility Matrix

| Library / Feature | AOT Status | Workaround |
|------------------|------------|------------|
| System.Text.Json (source gen) | Compatible | Use `[JsonSerializable]` context |
| System.Text.Json (reflection) | Breaks | Switch to source generators |
| CommunityToolkit.Mvvm | Compatible | Source-gen based, AOT-safe |
| Entity Framework Core | Partial | Precompiled queries; no dynamic LINQ |
| Newtonsoft.Json | Breaks | Migrate to System.Text.Json with source gen |
| AutoMapper | Breaks | Use Mapperly (source gen) |
| MediatR | Partial | Register handlers explicitly, avoid assembly scanning |
| HttpClient | Compatible | Standard usage works |
| MAUI Essentials | Compatible | Platform APIs are AOT-safe |
| SQLite-net | Compatible | Uses P/Invoke, AOT-safe |
| Refit | Breaks | Use Refit 7+ (includes source generator; enable with `[GenerateRefitClient]`) |
| FluentValidation | Partial | Avoid runtime expression compilation |

### Detecting Incompatible Code

```xml
<!-- Enable AOT analysis warnings during development -->
<PropertyGroup>
  <EnableAotAnalyzer>true</EnableAotAnalyzer>
  <!-- Also enable trim analyzer (AOT requires trimming) -->
  <EnableTrimAnalyzer>true</EnableTrimAnalyzer>
</PropertyGroup>
```

AOT analysis produces warnings like `IL3050` (RequiresDynamicCode) and `IL2026` (RequiresUnreferencedCode). Address these before publishing with AOT.


## Opt-Out Mechanisms

### Disabling AOT Entirely

```xml
<!-- Disable Native AOT (use interpreter/JIT mode) -->
<PropertyGroup>
  <PublishAot>false</PublishAot>
</PropertyGroup>
```

### Per-Assembly Trimming Overrides

When a specific library is not AOT-compatible, you can preserve it from trimming while still using AOT for the rest of the app:

```xml
<!-- Preserve a specific assembly from trimming -->
<ItemGroup>
  <TrimmerRootAssembly Include="IncompatibleLibrary" />
</ItemGroup>
```

### Opt-Out of .NET 11 Defaults

.NET 11 introduces new defaults that interact with AOT:

```xml
<!-- Revert XAML source gen (use legacy XAMLC) -->
<PropertyGroup>
  <MauiXamlInflator>XamlC</MauiXamlInflator>
</PropertyGroup>

<!-- Revert to Mono runtime on Android (not related to iOS AOT,
     but relevant for the overall MAUI AOT story) -->
<PropertyGroup>
  <UseMonoRuntime>true</UseMonoRuntime>
</PropertyGroup>
```


## Trimming Interplay

Native AOT requires trimming. When `PublishAot` is true, trimming is automatically enabled. Understanding trimming configuration is essential for a successful AOT build.

### ILLink Descriptors for Reflection Preservation

> **Note:** In Xamarin/Mono-era documentation, these were called "rd.xml" (Runtime Directives). In .NET 8+ Native AOT, use ILLink descriptor XML files instead.

When code uses reflection that the trimmer cannot statically analyze, use an ILLink descriptor XML file to preserve types. You can also use `[DynamicDependency]` attributes for fine-grained preservation in code.

**ILLink descriptor XML (preferred for bulk preservation):**

```xml
<!-- ILLink.Descriptors.xml -- preserve types needed at runtime -->
<linker>
  <!-- Preserve all public members of a type -->
  <assembly fullname="MyApp">
    <type fullname="MyApp.Models.LegacyConfig" preserve="all" />
    <type fullname="MyApp.Services.PluginLoader">
      <method name="LoadPlugin" />
    </type>
  </assembly>

  <!-- Preserve all types in an external assembly -->
  <assembly fullname="IncompatibleLibrary" preserve="all" />
</linker>
```

```xml
<!-- Register the descriptor in .csproj -->
<ItemGroup>
  <TrimmerRootDescriptor Include="ILLink.Descriptors.xml" />
</ItemGroup>
```

**`[DynamicDependency]` attribute (preferred for targeted preservation):**

```csharp
using System.Diagnostics.CodeAnalysis;

// Preserve a specific method on a type
[DynamicDependency(nameof(LegacyConfig.Initialize), typeof(LegacyConfig))]
public void ConfigureApp() { /* ... */ }

// Preserve all public members of a type
[DynamicDependency(DynamicallyAccessedMemberTypes.All, typeof(LegacyConfig))]
public void LoadPlugins() { /* ... */ }
```

### Source Generator Alternatives

When source generators aren't available, use `[DynamicDependency]` attributes (shown above) for targeted preservation without ILLink XML files.

Prefer source generators over reflection to avoid trimming issues entirely:

| Reflection Pattern | Source Generator Alternative |
|-------------------|---------------------------|
| `JsonSerializer.Deserialize<T>()` | `[JsonSerializable]` context (System.Text.Json) |
| `Activator.CreateInstance<T>()` | Factory pattern with explicit registration |
| `Type.GetProperties()` | CommunityToolkit.Mvvm `[ObservableProperty]` |
| Assembly scanning for DI | Explicit `services.Add*()` registrations |
| AutoMapper reflection mapping | Mapperly `[Mapper]` source generator |

### Trimming Warnings

```bash
# Build with detailed trim warnings
dotnet publish -f net8.0-ios -c Release /p:PublishAot=true /p:TrimmerSingleWarn=false

# TrimmerSingleWarn=false shows per-occurrence warnings instead of
# one summary warning per assembly, making it easier to fix issues
```

Common trim warnings:
- **IL2026:** Member with `RequiresUnreferencedCode` -- the member does something not guaranteed to work after trimming
- **IL2046:** Trim attribute mismatch between base/derived types
- **IL3050:** Member with `RequiresDynamicCode` -- the member generates code at runtime (incompatible with AOT)


## Testing AOT Builds

AOT builds can behave differently from Debug/JIT builds. Always test on a real device or simulator with an AOT-published build before release.

### Common AOT-Only Failures

| Failure | Symptom | Fix |
|---------|---------|-----|
| Missing type metadata | `MissingMetadataException` at runtime | Add type to ILLink descriptor or use `[DynamicDependency]` |
| Trimmed method | `MissingMethodException` | Add `[DynamicDependency]` or ILLink descriptor entry |
| Dynamic code gen | `PlatformNotSupportedException` | Replace with source generator alternative |
| Reflection-based serialization | Empty/null deserialized objects | Use `[JsonSerializable]` source gen |
| Assembly scanning | Missing services at runtime | Register services explicitly in DI |

### Testing Workflow

```bash
# 1. Build and publish with AOT for simulator (faster iteration)
dotnet publish -f net8.0-ios -c Release -r iossimulator-arm64

# 2. Install and test on simulator
# (Use Xcode or Visual Studio to deploy the .app to simulator)

# 3. Run smoke tests -- focus on:
#    - App startup (no MissingMetadataException)
#    - JSON deserialization (all properties populated)
#    - Navigation (all pages render)
#    - Platform services (biometric, camera, location)
#    - Third-party SDK integration

# 4. Test on physical device before release
dotnet publish -f net8.0-ios -c Release -r ios-arm64
# Deploy via Xcode with provisioning profile
```

### CI Integration

```bash
# CI pipeline: build AOT and run device tests via XHarness
dotnet publish -f net8.0-ios -c Release -r iossimulator-arm64 /p:PublishAot=true

xharness apple test \
    --app bin/Release/net8.0-ios/iossimulator-arm64/publish/MyApp.app \
    --target ios-simulator-64 \
    --timeout 00:10:00 \
    --output-directory test-results/aot
```

For MAUI testing patterns (Appium, XHarness), see `references/maui-testing.md`.


## Agent Gotchas

1. **Do not enable `PublishAot` without also enabling trim analyzers.** AOT requires trimming. Set `<EnableTrimAnalyzer>true</EnableTrimAnalyzer>` and `<EnableAotAnalyzer>true</EnableAotAnalyzer>` during development to catch issues early.
2. **Do not assume all NuGet packages are AOT-compatible.** Check for `IsAotCompatible` in the package's `.csproj` or look for trim/AOT warnings when building. Many popular packages still use reflection internally.
3. **Do not use `Newtonsoft.Json` with AOT.** It relies entirely on reflection. Migrate to `System.Text.Json` with `[JsonSerializable]` source gen contexts for AOT-safe serialization.
4. **Do not skip device testing for AOT builds.** Simulator testing catches most issues, but physical device behavior can differ -- especially for startup timing, memory constraints, and platform service integration.
5. **Do not confuse MAUI iOS AOT with Android AOT.** MAUI Native AOT (`PublishAot`) targets iOS and Mac Catalyst only. Android uses a different compilation model (Mono AOT in .NET 8-10, CoreCLR in .NET 11+). They are configured separately.


## Prerequisites

- .NET 8.0+ with MAUI workload
- Xcode and iOS/Mac Catalyst SDKs (macOS only)
- Apple Developer account for physical device deployment
- Provisioning profile and signing certificate for device testing


## References

- [MAUI Native AOT](https://learn.microsoft.com/en-us/dotnet/maui/deployment/nativeaot)
- [Native AOT Deployment](https://learn.microsoft.com/en-us/dotnet/core/deploying/native-aot/)
- [Trim Self-Contained Applications](https://learn.microsoft.com/en-us/dotnet/core/deploying/trimming/trimming-options)
- [Prepare .NET Libraries for Trimming](https://learn.microsoft.com/en-us/dotnet/core/deploying/trimming/prepare-libraries-for-trimming)
- [Trimming Descriptor Format](https://learn.microsoft.com/en-us/dotnet/core/deploying/trimming/trimming-options#descriptor-format)
- [.NET 11 Preview 1 Announcement](https://devblogs.microsoft.com/dotnet/dotnet-11-preview-1/)
