# AOT and WASM Testing

WebAssembly AOT compilation for Blazor WASM and Uno WASM applications: compilation pipeline, download size vs runtime speed tradeoffs, trimming interplay, lazy loading assemblies, and Brotli pre-compression for download optimization.

**Version assumptions:** .NET 8.0+ baseline. Blazor WASM AOT shipped in .NET 6 and has been refined through .NET 8-10. Uno WASM uses a similar compilation pipeline with Uno-specific tooling.

**Important tradeoff:** Trimming and AOT have **opposite effects** on WASM artifact size. Trimming reduces download size by removing unused code. AOT **increases** artifact size (native WASM code is larger than IL) but **improves** runtime execution speed. Use both together for the best balance.

## Download Size vs Runtime Speed

Understanding the size/speed tradeoff is critical for WASM AOT decisions:

| Compilation Mode | Download Size | Runtime Speed | Startup Time |
|-----------------|---------------|---------------|-------------|
| IL interpreter (no AOT) | Smallest | Slowest | Fastest startup |
| AOT (all assemblies) | **Largest** | Fastest | Slower startup |
| AOT (selective) + trimming | Balanced | Good | Moderate |
| Trimmed only (no AOT) | Small | Moderate (JIT interpretation) | Fast |

**Key insight:** Trimming reduces size by removing unused IL. AOT **increases** total artifact size because compiled native WASM code is larger than the equivalent IL bytecode. However, AOT-compiled code executes significantly faster because it skips IL interpretation at runtime.

### When to Use WASM AOT

- **CPU-intensive workloads:** Image processing, complex calculations, data transformation
- **Predictable performance:** Consistent execution speed without JIT pauses
- **Hot paths:** AOT-compile only performance-critical assemblies (selective AOT)

### When to Skip WASM AOT

- **Bandwidth-constrained users:** AOT increases download size significantly
- **Simple CRUD apps:** IL interpretation is fast enough for UI interactions and API calls
- **Rapid iteration:** AOT compilation adds significant publish time

---

## Blazor WASM AOT

### Enabling AOT

```xml
<!-- Blazor WASM .csproj -->
<PropertyGroup>
  <RunAOTCompilation>true</RunAOTCompilation>
</PropertyGroup>
```

```bash
# Publish with AOT (required -- AOT only applies during publish)
dotnet publish -c Release
```

Note: `RunAOTCompilation` is the Blazor WASM property (not `PublishAot` which is for server-side Native AOT). AOT compilation only happens during `dotnet publish`, not during `dotnet run` or `dotnet build`.

### Selective AOT via Lazy Loading

Blazor WASM AOT compiles all non-lazy-loaded assemblies. To control which assemblies are AOT-compiled, mark non-critical assemblies as lazy-loaded -- they will use IL interpretation instead:

```xml
<PropertyGroup>
  <RunAOTCompilation>true</RunAOTCompilation>
</PropertyGroup>

<ItemGroup>
  <!-- These assemblies are NOT AOT-compiled (loaded on demand via IL interpreter) -->
  <BlazorWebAssemblyLazyLoad Include="MyApp.Reporting.wasm" />
  <BlazorWebAssemblyLazyLoad Include="MyApp.Admin.wasm" />
  <!-- All other assemblies (MyApp.Core, MyApp.Calculations, etc.) ARE AOT-compiled -->
</ItemGroup>
```

### Trimming + AOT Together

For the best balance, use both trimming and AOT:

```xml
<PropertyGroup>
  <!-- Trimming reduces unused code (smaller download) -->
  <PublishTrimmed>true</PublishTrimmed>

  <!-- AOT compiles remaining code to native WASM (faster execution) -->
  <RunAOTCompilation>true</RunAOTCompilation>

  <!-- Detailed warnings during development -->
  <EnableTrimAnalyzer>true</EnableTrimAnalyzer>
</PropertyGroup>
```

The publish pipeline runs: trim unused IL first, then AOT-compile the remaining assemblies to native WASM. This produces an artifact that is larger than trimmed-only but smaller than AOT-without-trimming, with the best runtime performance.

---

## Uno WASM AOT

Uno Platform 5+ with .NET 8+ uses the standard .NET WASM workload, so the AOT configuration is the same as Blazor WASM.

### Enabling AOT (Uno 5+ / .NET 8+)

```xml
<!-- Uno WASM head .csproj -->
<PropertyGroup Condition="'$(TargetFramework)' == 'net8.0-browserwasm'">
  <RunAOTCompilation>true</RunAOTCompilation>
</PropertyGroup>
```

Older Uno versions using `Uno.Wasm.Bootstrap` had a separate `WasmShellMonoRuntimeExecutionMode` property with `Interpreter`, `InterpreterAndAOT`, and `FullAOT` modes. On .NET 8+, use `RunAOTCompilation` instead.

### Trimming in Uno WASM

```xml
<PropertyGroup>
  <PublishTrimmed>true</PublishTrimmed>
  <TrimMode>link</TrimMode>
</PropertyGroup>
```

See [skill:dotnet-ui] `references/uno-platform.md` for Uno Platform architecture patterns.

---

## Lazy Loading Assemblies

Lazy loading defers downloading assemblies until they are needed, reducing initial download size. This is especially effective when combined with AOT (which increases per-assembly size).

### Blazor WASM Lazy Loading

```xml
<!-- Mark assemblies for lazy loading in .csproj -->
<ItemGroup>
  <BlazorWebAssemblyLazyLoad Include="MyApp.Reporting.wasm" />
  <BlazorWebAssemblyLazyLoad Include="MyApp.Admin.wasm" />
  <BlazorWebAssemblyLazyLoad Include="ChartLibrary.wasm" />
</ItemGroup>
```

```csharp
// Load assemblies on demand in a component or router
@inject LazyAssemblyLoader LazyLoader

@code {
    private List<Assembly> _lazyLoadedAssemblies = new();

    private async Task LoadReportingModule()
    {
        var assemblies = await LazyLoader.LoadAssembliesAsync(new[]
        {
            "MyApp.Reporting.wasm"
        });
        _lazyLoadedAssemblies.AddRange(assemblies);
    }
}
```

### Router-Based Lazy Loading

```csharp
<!-- App.razor -->
@inject LazyAssemblyLoader LazyLoader

<Router AppAssembly="typeof(App).Assembly"
        AdditionalAssemblies="@_lazyLoadedAssemblies"
        OnNavigateAsync="@OnNavigateAsync">
    <Navigating>
        <div class="loading">Loading module...</div>
    </Navigating>
</Router>

@code {
    private List<Assembly> _lazyLoadedAssemblies = new();

    private async Task OnNavigateAsync(NavigationContext context)
    {
        if (context.Path.StartsWith("admin"))
        {
            var assemblies = await LazyLoader.LoadAssembliesAsync(new[]
            {
                "MyApp.Admin.wasm"
            });
            _lazyLoadedAssemblies.AddRange(assemblies);
        }
        else if (context.Path.StartsWith("reports"))
        {
            var assemblies = await LazyLoader.LoadAssembliesAsync(new[]
            {
                "MyApp.Reporting.wasm"
            });
            _lazyLoadedAssemblies.AddRange(assemblies);
        }
    }
}
```

### Lazy Loading Strategy

| Strategy | Initial Load | Feature Load | Best For |
|----------|-------------|-------------|----------|
| No lazy loading | All at once | Instant | Small apps (<5 MB total) |
| Route-based lazy loading | Core only | On navigation | Multi-module apps |
| Feature-based lazy loading | Core only | On demand | Apps with optional features |

---

## Brotli Pre-Compression

Brotli pre-compression reduces WASM download size by 60-80%. Blazor WASM automatically generates Brotli-compressed files during publish.

### How It Works

During `dotnet publish`, Blazor WASM generates `.br` (Brotli) and `.gz` (gzip) compressed versions of all static files in `_framework/`. The web server serves the pre-compressed file when the browser supports it.

```bash
# After publish, check compressed sizes
ls -la bin/Release/net8.0/publish/wwwroot/_framework/

# You'll see:
# MyApp.wasm       (original)
# MyApp.wasm.br    (Brotli compressed, ~60-80% smaller)
# MyApp.wasm.gz    (gzip compressed, ~50-70% smaller)
```

### Server Configuration

The web server must be configured to serve pre-compressed files. Most Blazor hosting setups handle this automatically.

**ASP.NET Core hosting:**

```csharp
// In the server project hosting Blazor WASM
app.UseBlazorFrameworkFiles();
app.UseStaticFiles();
// Blazor framework files are served with compression headers automatically
```

**Nginx:**

```nginx
location /_framework/ {
    # Serve Brotli-compressed files when available
    gzip_static on;
    brotli_static on;

    # Set correct MIME types
    types {
        application/wasm wasm;
    }

    # Cache aggressively (files are content-hashed)
    add_header Cache-Control "public, max-age=31536000, immutable";
}
```

**Azure Static Web Apps / GitHub Pages:**

Pre-compressed `.br` files are served automatically when the `Accept-Encoding: br` header is present.

### Compression Impact

| Content | Original | Brotli (.br) | Reduction |
|---------|----------|-------------|-----------|
| .NET WASM runtime | ~2.5 MB | ~0.8 MB | ~68% |
| App assemblies (IL) | varies | ~70% smaller | ~70% |
| App assemblies (AOT) | varies | ~65% smaller | ~65% |
| JavaScript glue code | ~100 KB | ~25 KB | ~75% |

### Disabling Compression (Rarely Needed)

```xml
<!-- Disable Brotli pre-compression -->
<PropertyGroup>
  <BlazorEnableCompression>false</BlazorEnableCompression>
</PropertyGroup>
```

---

## WASM Size Optimization Checklist

1. **Enable trimming** -- removes unused IL before AOT compilation
2. **Use lazy loading** -- defer non-critical assemblies
3. **Enable Brotli pre-compression** -- 60-80% reduction in transfer size (on by default)
4. **Use selective AOT** -- only AOT-compile performance-critical assemblies
5. **Enable invariant globalization** if culture-specific formatting is not needed:
   ```xml
   <PropertyGroup>
     <InvariantGlobalization>true</InvariantGlobalization>
   </PropertyGroup>
   ```
6. **Remove unused framework features:**
   ```xml
   <PropertyGroup>
     <!-- Disable features you don't use -->
     <EventSourceSupport>false</EventSourceSupport>
     <HttpActivityPropagationSupport>false</HttpActivityPropagationSupport>
   </PropertyGroup>
   ```
7. **Verify compression is served** -- check browser DevTools Network tab for `content-encoding: br`

---

## Agent Gotchas

1. **Do not confuse `RunAOTCompilation` with `PublishAot`.** Blazor WASM uses `RunAOTCompilation` for WASM AOT. `PublishAot` is for server-side Native AOT and produces a different kind of binary.
2. **Do not assume AOT reduces WASM download size.** AOT **increases** artifact size because native WASM code is larger than IL bytecode. Use trimming to reduce size and AOT to improve runtime speed.
3. **Do not forget to publish when testing AOT.** WASM AOT only runs during `dotnet publish`, not `dotnet run`. Debug builds always use IL interpretation.
4. **Do not lazy-load assemblies that are needed at startup.** Only lazy-load assemblies for features accessed after initial navigation. Loading a lazy assembly triggers a network request.
5. **Do not skip Brotli compression verification.** Ensure your web server serves `.br` files. Without compression, WASM downloads are 3-5x larger than necessary. Check browser DevTools for `content-encoding: br` header.
6. **Do not AOT-compile all assemblies when download size matters.** Use `BlazorWebAssemblyLazyLoad` to defer non-critical assemblies -- lazy-loaded assemblies use IL interpretation instead of AOT.

---

## References

- [ASP.NET Core Blazor WebAssembly AOT](https://learn.microsoft.com/en-us/aspnet/core/blazor/host-and-deploy/webassembly-aot)
- [Lazy load assemblies in Blazor WASM](https://learn.microsoft.com/en-us/aspnet/core/blazor/webassembly-lazy-load-assemblies)
- [Host and deploy Blazor WASM](https://learn.microsoft.com/en-us/aspnet/core/blazor/host-and-deploy/webassembly)
- [Trim self-contained applications](https://learn.microsoft.com/en-us/dotnet/core/deploying/trimming/trimming-options)
- [Uno Platform WASM](https://platform.uno/docs/articles/features/using-wasm-aot.html)
