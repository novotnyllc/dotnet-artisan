# Blazor Patterns

Blazor hosting models, render modes, project setup, routing, enhanced navigation, streaming rendering, and AOT-safe patterns. Covers all five hosting models (InteractiveServer, InteractiveWebAssembly, InteractiveAuto, Static SSR, Hybrid) with trade-off analysis for each.

## Hosting Models & Render Modes

Blazor Web App (.NET 8+) is the default project template, replacing the separate Blazor Server and Blazor WebAssembly templates. Render modes can be set globally, per-page, or per-component.

### Render Mode Overview

| Render Mode | Attribute | Interactivity | Connection | Best For |
|---|---|---|---|---|
| Static SSR | (none / default) | None -- server renders HTML, no interactivity | HTTP request only | Content pages, SEO, forms with minimal interactivity |
| InteractiveServer | `@rendermode InteractiveServer` | Full | SignalR circuit | Low-latency interactivity, full server access, small user base |
| InteractiveWebAssembly | `@rendermode InteractiveWebAssembly` | Full (after download) | None (runs in browser) | Offline-capable, large user base, reduced server load |
| InteractiveAuto | `@rendermode InteractiveAuto` | Full | SignalR initially, then WASM | Best of both -- immediate interactivity, eventual client-side |
| Blazor Hybrid | `BlazorWebView` in MAUI/WPF/WinForms | Full (native) | None (runs in-process) | Desktop/mobile apps with web UI, native API access |

### Per-Mode Trade-offs

| Concern | Static SSR | InteractiveServer | InteractiveWebAssembly | InteractiveAuto | Hybrid |
|---|---|---|---|---|---|
| First load | Fast | Fast | Slow (WASM download) | Fast (Server first) | Instant (local) |
| Server resources | Minimal | Per-user circuit | None after download | Circuit then none | None |
| Offline support | No | No | Yes | Partial | Yes |
| Full .NET API access | Yes (server) | Yes (server) | Limited (browser sandbox) | Varies by phase | Yes (native) |
| Scalability | High | Limited by circuits | High | High (after WASM) | N/A (local) |
| SEO | Yes | Prerender | Prerender | Prerender | N/A |

### Setting Render Modes

**Global (App.razor):**

```razor
<!-- Sets default render mode for all pages -->
<Routes @rendermode="InteractiveServer" />
```

**Per-page:**

```razor
@page "/dashboard"
@rendermode InteractiveServer

<h1>Dashboard</h1>
```

**Per-component:**

```razor
<Counter @rendermode="InteractiveWebAssembly" />
```

**Gotcha:** Without an explicit render mode boundary, a child component cannot request a more interactive render mode than its parent. However, interactive islands are supported: you can place an `@rendermode` attribute on a component embedded in a Static SSR page to create a render mode boundary, enabling interactive children under otherwise static content.


## Project Setup

### Blazor Web App (Default Template)

```bash
# Creates a Blazor Web App with InteractiveServer render mode
dotnet new blazor -n MyApp

# With specific interactivity options
dotnet new blazor -n MyApp --interactivity Auto    # InteractiveAuto
dotnet new blazor -n MyApp --interactivity WebAssembly  # InteractiveWebAssembly
dotnet new blazor -n MyApp --interactivity Server  # InteractiveServer (default)
dotnet new blazor -n MyApp --interactivity None    # Static SSR only
```

### Blazor Web App Project Structure

```
MyApp/
  MyApp/                     # Server project
    Program.cs               # Host builder, services, middleware
    Components/
      App.razor              # Root component (sets global render mode)
      Routes.razor           # Router component
      Layout/
        MainLayout.razor     # Main layout
      Pages/
        Home.razor            # Static SSR by default
        Counter.razor         # Can set per-page render mode
  MyApp.Client/              # Client project (only if WASM or Auto)
    Pages/
      Counter.razor           # Components that run in browser
    Program.cs                # WASM entry point
```

When using InteractiveAuto or InteractiveWebAssembly, components that must run in the browser go in the `.Client` project. Components in the server project run on the server only.

### Blazor Hybrid Setup (MAUI)

```xml
<!-- .csproj for MAUI Blazor Hybrid -->
<Project Sdk="Microsoft.NET.Sdk.Razor">
  <PropertyGroup>
    <TargetFrameworks>net10.0-android;net10.0-ios;net10.0-maccatalyst</TargetFrameworks>
    <OutputType>Exe</OutputType>
    <UseMaui>true</UseMaui>
  </PropertyGroup>
</Project>
```

```csharp
// MainPage.xaml.cs hosts BlazorWebView
public partial class MainPage : ContentPage
{
    public MainPage()
    {
        InitializeComponent();
    }
}
```

```xml
<!-- MainPage.xaml -->
<ContentPage xmlns="http://schemas.microsoft.com/dotnet/2021/maui"
             xmlns:b="clr-namespace:Microsoft.AspNetCore.Components.WebView.Maui;assembly=Microsoft.AspNetCore.Components.WebView.Maui">
    <b:BlazorWebView HostPage="wwwroot/index.html">
        <b:BlazorWebView.RootComponents>
            <b:RootComponent Selector="#app" ComponentType="{x:Type local:Routes}" />
        </b:BlazorWebView.RootComponents>
    </b:BlazorWebView>
</ContentPage>
```


## Routing

### Basic Routing

```razor
@page "/products"
@page "/products/{Category}"

<h1>Products</h1>
@if (!string.IsNullOrEmpty(Category))
{
    <p>Category: @Category</p>
}

@code {
    [Parameter]
    public string? Category { get; set; }
}
```

### Route Constraints

```razor
@page "/products/{Id:int}"
@page "/orders/{Date:datetime}"
@page "/search/{Query:minlength(3)}"

@code {
    [Parameter] public int Id { get; set; }
    [Parameter] public DateTime Date { get; set; }
    [Parameter] public string Query { get; set; } = "";
}
```

### Query String Parameters

```razor
@page "/search"

@code {
    [SupplyParameterFromQuery]
    public string? Term { get; set; }

    [SupplyParameterFromQuery(Name = "page")]
    public int CurrentPage { get; set; } = 1;
}
```

### NavigationManager

```csharp
@inject NavigationManager Navigation

// Programmatic navigation
Navigation.NavigateTo("/products/electronics");

// With query string
Navigation.NavigateTo("/search?term=keyboard&page=2");

// Force full page reload (bypasses enhanced navigation)
Navigation.NavigateTo("/external-page", forceLoad: true);
```


## Enhanced Navigation (.NET 8+)

Enhanced navigation intercepts link clicks and form submissions to update only the changed DOM content, preserving page state and avoiding full page reloads. This applies to Static SSR and prerendered pages.

### How It Works

1. User clicks a link within the Blazor app
2. Blazor intercepts the navigation
3. A fetch request loads the new page content
4. Blazor patches the DOM with only the differences
5. Scroll position and focus state are preserved

### Opting Out

```razor
<!-- Disable enhanced navigation for a specific link -->
<a href="/legacy-page" data-enhance-nav="false">Legacy Page</a>

<!-- Disable enhanced form handling for a specific form -->
<form method="post" data-enhance="false">
    ...
</form>
```

**Gotcha:** Enhanced navigation may interfere with third-party JavaScript libraries that expect full page loads. Use `data-enhance-nav="false"` on links that navigate to pages with JS that initializes on `DOMContentLoaded`.


## Streaming Rendering (.NET 8+)

Streaming rendering sends initial HTML immediately (with placeholder content), then streams updates as async operations complete. Useful for pages with slow data sources.

```razor
@page "/dashboard"
@attribute [StreamRendering]

<h1>Dashboard</h1>

@if (orders is null)
{
    <p>Loading orders...</p>
}
else
{
    <table>
        @foreach (var order in orders)
        {
            <tr><td>@order.Id</td><td>@order.Total</td></tr>
        }
    </table>
}

@code {
    private List<OrderDto>? orders;

    protected override async Task OnInitializedAsync()
    {
        // Initial HTML sent immediately with "Loading orders..."
        // Updated HTML streamed when this completes
        orders = await OrderService.GetRecentOrdersAsync();
    }
}
```

**Behavior per render mode:**
- **Static SSR:** Streaming rendering sends the initial response, then patches the DOM via chunked transfer encoding. The page is not interactive.
- **InteractiveServer/WebAssembly/Auto:** Streaming rendering is less impactful because components re-render automatically after async operations. The `[StreamRendering]` attribute primarily benefits the prerender phase.


## AOT-Safe Patterns

When targeting Blazor WebAssembly with Native AOT (ahead-of-time compilation) or IL trimming, avoid patterns that rely on runtime reflection.

### Source-Generator-First Serialization

```csharp
// CORRECT: Source-generated JSON serialization (AOT-compatible)
[JsonSerializable(typeof(ProductDto))]
[JsonSerializable(typeof(List<ProductDto>))]
[JsonSourceGenerationOptions(PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase)]
public partial class AppJsonContext : JsonSerializerContext { }

// Register in Program.cs
builder.Services.ConfigureHttpJsonOptions(options =>
{
    options.SerializerOptions.TypeInfoResolverChain.Insert(0, AppJsonContext.Default);
});

// Usage in HttpClient calls
var products = await Http.GetFromJsonAsync<List<ProductDto>>(
    "/api/products",
    AppJsonContext.Default.ListProductDto);
```

```csharp
// WRONG: Reflection-based serialization (fails under AOT/trimming)
var products = await Http.GetFromJsonAsync<List<ProductDto>>("/api/products");
```

### Trim-Safe JS Interop

```csharp
// CORRECT: Use IJSRuntime with explicit method names (no dynamic dispatch)
await JSRuntime.InvokeVoidAsync("localStorage.setItem", "key", "value");
var value = await JSRuntime.InvokeAsync<string>("localStorage.getItem", "key");

// CORRECT: Use IJSObjectReference for module imports (.NET 8+)
var module = await JSRuntime.InvokeAsync<IJSObjectReference>(
    "import", "./js/chart.js");
await module.InvokeVoidAsync("initChart", elementRef, data);
await module.DisposeAsync();
```

```csharp
// WRONG: Dynamic dispatch via reflection (trimmed away)
// var method = typeof(JSRuntime).GetMethod("InvokeAsync");
// method.MakeGenericMethod(returnType).Invoke(...)
```

### Linker Configuration

```xml
<!-- Preserve types used dynamically in components -->
<ItemGroup>
  <TrimmerRootAssembly Include="MyApp.Client" />
</ItemGroup>
```

For types that must be preserved from trimming:

```csharp
// Mark types that are accessed via reflection
[DynamicallyAccessedMembers(DynamicallyAccessedMemberTypes.All)]
public class DynamicFormModel
{
    // Properties discovered at runtime for form generation
    public string Name { get; set; } = "";
    public int Age { get; set; }
}
```

### Anti-Patterns to Avoid

1. **Reflection-based DI** -- Do not use `Activator.CreateInstance` or `Type.GetType` to resolve services. Use the built-in DI container with explicit registrations.
2. **Dynamic type loading** -- Do not use `Assembly.Load` or `Assembly.GetTypes()` at runtime. Register all types at startup.
3. **Runtime code generation** -- Do not use `System.Reflection.Emit` or `System.Linq.Expressions.Expression.Compile()`. Use source generators instead.
4. **Untyped JSON deserialization** -- Do not use `JsonSerializer.Deserialize<T>(json)` without a `JsonSerializerContext`. Always provide a source-generated context.


## Prerendering

Prerendering generates HTML on the server before the interactive runtime loads. This improves perceived performance and SEO.

### Prerender with Interactive Modes

```razor
<!-- Component prerenders on server, then becomes interactive -->
<Counter @rendermode="InteractiveServer" />
```

By default, interactive components prerender. To disable:

```razor
@rendermode @(new InteractiveServerRenderMode(prerender: false))
```

### Persisting State Across Prerender

State computed during prerendering is lost when the component reinitializes interactively. Use `PersistentComponentState` to preserve it:

```razor
@inject PersistentComponentState ApplicationState
@implements IDisposable

@code {
    private List<ProductDto>? products;
    private PersistingComponentStateSubscription _subscription;

    protected override async Task OnInitializedAsync()
    {
        _subscription = ApplicationState.RegisterOnPersisting(PersistState);

        if (!ApplicationState.TryTakeFromJson<List<ProductDto>>(
            "products", out var restored))
        {
            products = await ProductService.GetProductsAsync();
        }
        else
        {
            products = restored;
        }
    }

    private Task PersistState()
    {
        ApplicationState.PersistAsJson("products", products);
        return Task.CompletedTask;
    }

    public void Dispose() => _subscription.Dispose();
}
```


## .NET 10 Stable Features

These features are available when `net10.0` TFM is detected. They are stable and require no preview opt-in.

### WebAssembly Preloading

.NET 10 adds `blazor.web.js` preloading of WebAssembly assemblies during the Server phase of InteractiveAuto. When the user first loads a page, the WASM runtime and app assemblies download in the background while the Server circuit handles interactivity. Subsequent navigations switch to WASM faster because assemblies are already cached.

```razor
<!-- No code changes needed -- preloading is automatic in .NET 10 -->
<!-- Verify in browser DevTools Network tab: assemblies download during Server phase -->
```

### Enhanced Form Validation

.NET 10 extends `EditForm` validation with improved error message formatting and support for `IValidatableObject` in Static SSR forms. Validation messages render correctly with enhanced form handling (`Enhance` attribute) without requiring a full page reload.

```csharp
// IValidatableObject works in Static SSR enhanced forms in .NET 10
public sealed class OrderModel : IValidatableObject
{
    [Required]
    public string ProductId { get; set; } = "";

    [Range(1, 100)]
    public int Quantity { get; set; }

    public IEnumerable<ValidationResult> Validate(ValidationContext context)
    {
        if (ProductId == "DISCONTINUED" && Quantity > 0)
        {
            yield return new ValidationResult(
                "Cannot order discontinued products",
                [nameof(ProductId), nameof(Quantity)]);
        }
    }
}
```

### Blazor Diagnostics Middleware

.NET 10 adds `MapBlazorDiagnostics` middleware for inspecting Blazor circuit and component state in development:

```csharp
// Program.cs -- available in .NET 10
if (app.Environment.IsDevelopment())
{
    app.MapBlazorDiagnostics(); // Exposes /_blazor/diagnostics endpoint
}
```

The diagnostics endpoint shows active circuits, component tree, render mode assignments, and timing data. Use it to debug render mode boundaries and component lifecycle issues during development.


## Agent Gotchas

1. **Do not default to InteractiveServer for every page.** Static SSR is the default and most efficient render mode. Only add interactivity where user interaction requires it.
2. **Do not put WASM-targeted components in the server project.** Components that must run in the browser (InteractiveWebAssembly or InteractiveAuto) belong in the `.Client` project.
3. **Do not forget `PersistentComponentState` when prerendering.** Without it, data fetched during prerender is discarded and re-fetched when the component becomes interactive, causing a visible flicker.
4. **Do not use reflection-based serialization in WASM.** Always use `JsonSerializerContext` with source-generated serializers for AOT compatibility and trimming safety.
5. **Do not force-load navigation unless leaving the Blazor app.** `NavigateTo("/page", forceLoad: true)` bypasses enhanced navigation and causes a full page reload.
6. **Do not nest interactive render modes incorrectly.** A child component cannot request a more interactive mode than its parent. Plan render mode boundaries from the layout down.


## Prerequisites

- .NET 8.0+ (Blazor Web App template, render modes, enhanced navigation, streaming rendering)
- .NET 10.0 for stable enhanced features (WebAssembly preloading, enhanced form validation, diagnostics middleware)
- MAUI workload for Blazor Hybrid (`dotnet workload install maui`)


## References

- [Blazor Overview](https://learn.microsoft.com/en-us/aspnet/core/blazor/?view=aspnetcore-10.0)
- [Blazor Render Modes](https://learn.microsoft.com/en-us/aspnet/core/blazor/components/render-modes?view=aspnetcore-10.0)
- [Blazor Routing](https://learn.microsoft.com/en-us/aspnet/core/blazor/fundamentals/routing?view=aspnetcore-10.0)
- [Enhanced Navigation](https://learn.microsoft.com/en-us/aspnet/core/blazor/fundamentals/routing?view=aspnetcore-10.0#enhanced-navigation-and-form-handling)
- [Streaming Rendering](https://learn.microsoft.com/en-us/aspnet/core/blazor/components/rendering?view=aspnetcore-10.0#streaming-rendering)
- [Blazor Hybrid](https://learn.microsoft.com/en-us/aspnet/core/blazor/hybrid/?view=aspnetcore-10.0)
- [AOT Deployment](https://learn.microsoft.com/en-us/dotnet/core/deploying/native-aot/)
