# Native AOT

Full Native AOT compilation pipeline for .NET 8+ applications: `PublishAot` configuration, ILLink descriptor XML for type preservation, reflection-free coding patterns, P/Invoke considerations, binary size optimization, self-contained deployment with `runtime-deps` base images, and diagnostic analyzers (`EnableAotAnalyzer`/`EnableTrimAnalyzer`).

**Version assumptions:** .NET 8.0+ baseline. Native AOT for ASP.NET Core Minimal APIs and console apps shipped in .NET 8. .NET 9 improved trimming warnings and library compat. .NET 10 enhanced request delegate generator and expanded Minimal API AOT support.

## PublishAot Configuration

### Enabling Native AOT

```xml
<!-- App .csproj -->
<PropertyGroup>
  <PublishAot>true</PublishAot>
</PropertyGroup>
```

```bash
# Publish as Native AOT
dotnet publish -c Release -r linux-x64

# Publish for specific targets
dotnet publish -c Release -r win-x64
dotnet publish -c Release -r osx-arm64
```

### MSBuild Properties: Apps vs Libraries

Apps and libraries use different MSBuild properties. Do not mix them.

**For applications** (console apps, ASP.NET Core Minimal APIs):

```xml
<PropertyGroup>
  <!-- Enable Native AOT compilation on publish -->
  <PublishAot>true</PublishAot>

  <!-- Enable analyzers during development (not just publish) -->
  <EnableAotAnalyzer>true</EnableAotAnalyzer>
  <EnableTrimAnalyzer>true</EnableTrimAnalyzer>
</PropertyGroup>
```

**For libraries** (NuGet packages, shared class libraries):

```xml
<PropertyGroup>
  <!-- Declare the library is AOT-compatible (auto-enables analyzers) -->
  <IsAotCompatible>true</IsAotCompatible>
  <!-- Declare the library is trim-safe (auto-enables trim analyzer) -->
  <IsTrimmable>true</IsTrimmable>
</PropertyGroup>
```

`IsAotCompatible` and `IsTrimmable` automatically enable the AOT and trim analyzers respectively. Do not also set `PublishAot` in library projects -- libraries are not published as standalone executables.


## Diagnostic Analyzers

Enable AOT and trim analyzers during development to catch issues before publishing:

```xml
<PropertyGroup>
  <EnableAotAnalyzer>true</EnableAotAnalyzer>
  <EnableTrimAnalyzer>true</EnableTrimAnalyzer>
</PropertyGroup>
```

### Analysis Without Publishing

Run analysis during `dotnet build` without a full publish:

```bash
# Analyze AOT compatibility without publishing
dotnet build /p:EnableAotAnalyzer=true /p:EnableTrimAnalyzer=true

# See per-occurrence warnings (not grouped by assembly)
dotnet build /p:EnableAotAnalyzer=true /p:EnableTrimAnalyzer=true /p:TrimmerSingleWarn=false
```

This reports IL2xxx (trim) and IL3xxx (AOT) warnings without producing a native binary, enabling fast feedback during development.

### Common Diagnostic Codes

| Code | Category | Meaning |
|------|----------|---------|
| IL2026 | Trim | Member has `[RequiresUnreferencedCode]` -- may break after trimming |
| IL2046 | Trim | Trim attribute mismatch between base/derived types |
| IL2057-IL2072 | Trim | Various reflection usage that the trimmer cannot analyze |
| IL3050 | AOT | Member has `[RequiresDynamicCode]` -- generates code at runtime |
| IL3051 | AOT | `[RequiresDynamicCode]` attribute mismatch |


## ILLink Descriptors for Type Preservation

When code uses reflection that the trimmer cannot statically analyze, use ILLink descriptor XML to preserve types. **Do not use legacy RD.xml** -- it is a .NET Native/UWP format that is silently ignored by modern .NET AOT.

### ILLink Descriptor XML

```xml
<!-- ILLink.Descriptors.xml -->
<linker>
  <!-- Preserve all public members of a type -->
  <assembly fullname="MyApp">
    <type fullname="MyApp.Models.LegacyConfig" preserve="all" />
    <type fullname="MyApp.Services.PluginLoader">
      <method name="LoadPlugin" />
    </type>
  </assembly>

  <!-- Preserve an entire external assembly -->
  <assembly fullname="IncompatibleLibrary" preserve="all" />
</linker>
```

```xml
<!-- Register in .csproj -->
<ItemGroup>
  <TrimmerRootDescriptor Include="ILLink.Descriptors.xml" />
</ItemGroup>
```

### `[DynamicDependency]` Attribute

For targeted preservation in code (preferred over ILLink XML for small, localized cases):

```csharp
using System.Diagnostics.CodeAnalysis;

// Preserve a specific method
[DynamicDependency(nameof(LegacyConfig.Initialize), typeof(LegacyConfig))]
public void ConfigureApp() { /* ... */ }

// Preserve all public members
[DynamicDependency(DynamicallyAccessedMemberTypes.All, typeof(PluginBase))]
public void LoadPlugins() { /* ... */ }
```

### When to Use Which

| Scenario | Approach |
|----------|----------|
| One or two methods/types | `[DynamicDependency]` attribute |
| Entire assembly or many types | ILLink descriptor XML |
| Third-party library not AOT-safe | ILLink descriptor XML or `<TrimmerRootAssembly>` |
| Your own code with analyzed reflection | Refactor to source generators (best long-term) |


## Reflection-Free Patterns

Native AOT works best with code that avoids runtime reflection entirely. Replace reflection patterns with compile-time alternatives.

| Reflection Pattern | AOT-Safe Replacement |
|-------------------|---------------------|
| `Activator.CreateInstance<T>()` | Factory method or explicit `new T()` |
| `Type.GetProperties()` for mapping | Mapperly source generator or manual mapping |
| `Assembly.GetTypes()` for DI scanning | Explicit `services.AddScoped<T>()` |
| `JsonSerializer.Deserialize<T>(json)` | `JsonSerializer.Deserialize(json, Context.Default.T)` |
| `MethodInfo.Invoke()` for dispatch | `switch` on type or interface dispatch |

See `references/aot-architecture.md` for comprehensive AOT-first design patterns.


## P/Invoke Considerations

P/Invoke (platform invoke) calls to native libraries generally work with Native AOT, but require attention:

### Direct P/Invoke (Preferred)

```csharp
// Direct P/Invoke -- AOT-compatible, no runtime marshalling overhead
[LibraryImport("libsqlite3", EntryPoint = "sqlite3_open")]
internal static partial int Sqlite3Open(
    [MarshalAs(UnmanagedType.LPStr)] string filename,
    out nint db);
```

Use `[LibraryImport]` (.NET 7+) instead of `[DllImport]` -- it generates marshalling code at compile time via source generators, making it fully AOT-compatible.

### DllImport vs LibraryImport

| Attribute | AOT Compatibility | Marshalling |
|-----------|------------------|-------------|
| `[DllImport]` | Partial -- some marshalling requires runtime codegen | Runtime marshalling |
| `[LibraryImport]` | Full -- compile-time source gen | Compile-time marshalling |

```csharp
// Migrate from DllImport to LibraryImport
// Before:
[DllImport("kernel32.dll", SetLastError = true)]
static extern bool CloseHandle(IntPtr hObject);

// After:
[LibraryImport("kernel32.dll", SetLastError = true)]
[return: MarshalAs(UnmanagedType.Bool)]
internal static partial bool CloseHandle(IntPtr hObject);
```

### Native Library Deployment

When publishing as Native AOT, native libraries (`.so`, `.dylib`, `.dll`) must be alongside the binary:

```xml
<ItemGroup>
  <!-- Include native library in publish output -->
  <NativeLibrary Include="libs/libcustom.so" />
</ItemGroup>
```


## Size Optimization

### Binary Size Reduction Options

```xml
<PropertyGroup>
  <PublishAot>true</PublishAot>

  <!-- Strip debug symbols (significant size reduction) -->
  <StripSymbols>true</StripSymbols>

  <!-- Optimize for size over speed -->
  <OptimizationPreference>Size</OptimizationPreference>

  <!-- Enable invariant globalization (removes ICU data) -->
  <InvariantGlobalization>true</InvariantGlobalization>

  <!-- Remove stack trace strings (reduces size, harder debugging) -->
  <StackTraceSupport>false</StackTraceSupport>

  <!-- Remove EventSource/EventPipe (if not using diagnostics) -->
  <EventSourceSupport>false</EventSourceSupport>
</PropertyGroup>
```

### Typical Binary Sizes

| Configuration | Console App | ASP.NET Minimal API |
|--------------|-------------|---------------------|
| Default AOT | ~10-15 MB | ~15-25 MB |
| + StripSymbols | ~8-12 MB | ~12-20 MB |
| + Size optimization | ~6-10 MB | ~10-18 MB |
| + InvariantGlobalization | ~4-8 MB | ~8-15 MB |

### Size Analysis

```bash
# Analyze what contributes to binary size
dotnet publish -c Release -r linux-x64 /p:PublishAot=true

# Use sizoscope (community tool) for detailed size analysis
# https://github.com/AdrianEddy/sizoscope
```


## Self-Contained Deployment with runtime-deps

Native AOT produces self-contained binaries that include the .NET runtime. Use the `runtime-deps` base image for minimal container size since the runtime is already embedded in the binary.

```dockerfile
# Build stage
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY . .
RUN dotnet publish -c Release -r linux-x64 -o /app/publish

# Runtime stage -- use runtime-deps, not aspnet or runtime
FROM mcr.microsoft.com/dotnet/runtime-deps:10.0-noble-chiseled AS runtime
WORKDIR /app
COPY --from=build /app/publish .
ENTRYPOINT ["./MyApp"]
```

The `runtime-deps` image contains only OS-level dependencies (libc, OpenSSL, etc.) -- no .NET runtime. This is the smallest possible base image for AOT-published apps (~30 MB). See [skill:dotnet-devops] for full container patterns.


## ASP.NET Core Native AOT

### Minimal API Support (.NET 8+)

ASP.NET Core Minimal APIs support Native AOT. MVC controllers are **not** AOT-compatible (they rely on reflection for model binding, filters, and routing).

```csharp
var builder = WebApplication.CreateSlimBuilder(args);

// Use source-generated JSON context
builder.Services.ConfigureHttpJsonOptions(options =>
{
    options.SerializerOptions.TypeInfoResolverChain.Insert(0, AppJsonContext.Default);
});

var app = builder.Build();

app.MapGet("/api/products/{id}", (int id) =>
    Results.Ok(new Product(id, "Widget")));

app.Run();

[JsonSerializable(typeof(Product))]
internal partial class AppJsonContext : JsonSerializerContext { }

record Product(int Id, string Name);
```

### CreateSlimBuilder vs CreateBuilder

| Method | AOT Support | Includes |
|--------|-------------|----------|
| `WebApplication.CreateSlimBuilder()` | Full | Minimal services, no MVC, no Razor |
| `WebApplication.CreateBuilder()` | Partial | Full feature set, some features need reflection |

Use `CreateSlimBuilder` for Native AOT applications. It excludes features that require runtime code generation.

### .NET 10 ASP.NET Core AOT Improvements

.NET 10 brings improvements across the ASP.NET Core and runtime Native AOT stack. Target `net10.0` to benefit automatically.

```xml
<PropertyGroup>
  <TargetFramework>net10.0</TargetFramework>
  <PublishAot>true</PublishAot>
</PropertyGroup>
```

**Request Delegate Generator improvements:** The source generator that creates request delegates for Minimal API endpoints handles more parameter binding scenarios in .NET 10, including additional `TypedResults` return types and complex binding patterns. This reduces the need for manual workarounds that were required in .NET 8/9 when the generator could not produce AOT-safe code for certain endpoint signatures.

**Reduced linker warning surface:** Many ASP.NET Core framework APIs that previously emitted trim/AOT warnings (IL2xxx/IL3xxx) have been annotated or refactored for AOT compatibility. Projects upgrading from .NET 9 to .NET 10 will see fewer false-positive linker warnings when publishing with `PublishAot`.

**OpenAPI in the `webapiaot` template:** The `webapiaot` project template now includes OpenAPI document generation via `Microsoft.AspNetCore.OpenApi` by default, so AOT-published APIs get auto-generated API documentation without additional setup.

**Runtime NativeAOT code generation:** The .NET 10 runtime improves AOT code generation for struct arguments, enhances loop inversion optimizations, and improves method devirtualization -- resulting in better throughput for AOT-published applications without code changes.

**Blazor Server and SignalR:** Blazor Server and SignalR remain **not supported** with Native AOT in .NET 10. Blazor WebAssembly AOT (client-side compilation) is a separate concern covered by [skill:dotnet-ui]. For Blazor Server apps, continue using JIT deployment.

**Compatibility snapshot (.NET 10):**

| Feature | AOT Support |
|---------|-------------|
| gRPC | Fully supported |
| Minimal APIs | Partially supported (most scenarios work) |
| MVC | Not supported |
| Blazor Server | Not supported |
| SignalR | Not supported |
| JWT Authentication | Fully supported |
| CORS, HealthChecks, OutputCaching | Fully supported |
| WebSockets, StaticFiles | Fully supported |


## Agent Gotchas

1. **Do not use `PublishAot` in library projects.** Libraries use `IsAotCompatible` (which auto-enables the AOT analyzer). `PublishAot` is for applications that produce standalone executables.
2. **Do not use legacy RD.xml for type preservation.** RD.xml is a .NET Native/UWP format that is silently ignored by modern .NET AOT. Use ILLink descriptor XML files and `[DynamicDependency]` attributes instead.
3. **Do not use `[DllImport]` in new AOT code.** Use `[LibraryImport]` (.NET 7+) which generates marshalling at compile time. `[DllImport]` may require runtime marshalling that is not available in AOT.
4. **Do not use `WebApplication.CreateBuilder()` for AOT APIs.** Use `CreateSlimBuilder()` which excludes reflection-heavy features. `CreateBuilder()` includes MVC infrastructure that is not AOT-compatible.
5. **Do not use `dotnet publish --no-actual-publish` for analysis.** That flag does not exist. Use `dotnet build /p:EnableAotAnalyzer=true /p:EnableTrimAnalyzer=true` to get diagnostic warnings without publishing.
6. **Do not assume MVC controllers work with Native AOT.** MVC relies on reflection for model binding, action filters, and routing. Use Minimal APIs for AOT-published web applications.


## References

- [Native AOT deployment](https://learn.microsoft.com/en-us/dotnet/core/deploying/native-aot/)
- [ASP.NET Core Native AOT](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/native-aot)
- [ILLink descriptor format](https://learn.microsoft.com/en-us/dotnet/core/deploying/trimming/trimming-options#descriptor-format)
- [LibraryImport source generation](https://learn.microsoft.com/en-us/dotnet/standard/native-interop/pinvoke-source-generation)
- [Optimize AOT deployments](https://learn.microsoft.com/en-us/dotnet/core/deploying/native-aot/optimizing)
