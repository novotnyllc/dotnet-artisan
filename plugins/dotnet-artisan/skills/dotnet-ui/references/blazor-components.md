# Blazor Components

Blazor component architecture: lifecycle methods, state management (cascading values, DI, browser storage), JavaScript interop (AOT-safe), EditForm validation, and QuickGrid. Covers per-render-mode behavior differences where relevant.

## Component Lifecycle

### Lifecycle Methods

```csharp
@code {
    // 1. Called when parameters are set/updated
    public override async Task SetParametersAsync(ParameterView parameters)
    {
        // Access raw parameters before they are applied
        await base.SetParametersAsync(parameters);
    }

    // 2. Called after parameters are assigned (sync)
    protected override void OnInitialized()
    {
        // One-time initialization (runs once per component instance)
    }

    // 3. Called after parameters are assigned (async)
    protected override async Task OnInitializedAsync()
    {
        // Async initialization (data fetching, service calls)
        products = await ProductService.GetProductsAsync();
    }

    // 4. Called every time parameters change
    protected override void OnParametersSet()
    {
        // React to parameter changes
    }

    // 5. Called after each render
    protected override void OnAfterRender(bool firstRender)
    {
        if (firstRender)
        {
            // JS interop safe here -- DOM is available
        }
    }

    // 6. Async version of OnAfterRender
    protected override async Task OnAfterRenderAsync(bool firstRender)
    {
        if (firstRender)
        {
            await JSRuntime.InvokeVoidAsync("initializeChart", chartElement);
        }
    }

    // 7. Cleanup
    public void Dispose()
    {
        // Unsubscribe from events, dispose resources
    }

    // 8. Async cleanup
    public async ValueTask DisposeAsync()
    {
        // Async cleanup (dispose JS object references)
        if (module is not null)
        {
            await module.DisposeAsync();
        }
    }
}
```

### Lifecycle Behavior per Render Mode

| Lifecycle Event | Static SSR | InteractiveServer | InteractiveWebAssembly | InteractiveAuto | Hybrid |
|---|---|---|---|---|---|
| `OnInitialized(Async)` | Runs on server | Runs on server | Runs in browser | Server on first load, browser after WASM cached | Runs in-process |
| `OnAfterRender(Async)` | Never called | Runs on server after SignalR confirms render | Runs in browser after DOM update | Server-side then browser-side (matches active runtime) | Runs after WebView render |
| `Dispose(Async)` | Called after response | Called when circuit ends | Called on component removal | Called when circuit ends (Server phase) or on removal (WASM phase) | Called on component removal |

**Gotcha:** In Static SSR, `OnAfterRender` never executes because there is no persistent connection. Do not place critical logic in `OnAfterRender` for Static SSR pages.


## State Management

### Cascading Values

Cascading values flow data down the component tree without explicit parameter passing.

```razor
<!-- Parent: provide a cascading value -->
<CascadingValue Value="@theme" Name="AppTheme">
    <Router AppAssembly="typeof(App).Assembly">
        <!-- All descendants can receive AppTheme -->
    </Router>
</CascadingValue>

@code {
    private ThemeSettings theme = new() { IsDarkMode = false, AccentColor = "#0078d4" };
}
```

```razor
<!-- Child: consume the cascading value -->
@code {
    [CascadingParameter(Name = "AppTheme")]
    public ThemeSettings? Theme { get; set; }
}
```

**Fixed cascading values (.NET 8+):** For values that never change after initial render, use `IsFixed="true"` to avoid re-render overhead:

```razor
<CascadingValue Value="@config" IsFixed="true">
    <ChildComponent />
</CascadingValue>
```

### Dependency Injection

```csharp
// Register services in Program.cs
builder.Services.AddScoped<IProductService, ProductService>();
builder.Services.AddSingleton<AppState>();

// Inject in components
@inject IProductService ProductService
@inject AppState State
```

**DI lifetime behavior per render mode:**

| Lifetime | InteractiveServer | InteractiveWebAssembly | InteractiveAuto | Hybrid |
|---|---|---|---|---|
| Singleton | Shared across all circuits on the server | One per browser tab | Server-shared during Server phase; per-tab after WASM switch | One per app instance |
| Scoped | One per circuit (acts like per-user) | One per browser tab (same as Singleton) | Per-circuit (Server phase), per-tab (WASM phase) -- state does not transfer between phases | One per app instance (same as Singleton) |
| Transient | New instance each injection | New instance each injection | New instance each injection | New instance each injection |

**Gotcha:** In Blazor Server, `Scoped` services live for the entire circuit duration (not per-request like in MVC). A circuit persists until the user navigates away or the connection drops. Long-lived scoped services may accumulate state -- use `OwningComponentBase<T>` for component-scoped DI.

### Browser Storage

```csharp
// ProtectedBrowserStorage -- encrypted, per-user storage
// Available in InteractiveServer only (not WASM -- server encrypts/decrypts)
@inject ProtectedSessionStorage SessionStorage
@inject ProtectedLocalStorage LocalStorage

protected override async Task OnAfterRenderAsync(bool firstRender)
{
    if (firstRender)
    {
        // Session storage (cleared when tab closes)
        await SessionStorage.SetAsync("cart", cartItems);
        var result = await SessionStorage.GetAsync<List<CartItem>>("cart");
        if (result.Success) { cartItems = result.Value!; }

        // Local storage (persists across sessions)
        await LocalStorage.SetAsync("preferences", userPrefs);
    }
}
```

For InteractiveWebAssembly, use JS interop to access browser storage directly:

```csharp
// WASM: Direct browser storage via JS interop
await JSRuntime.InvokeVoidAsync("localStorage.setItem", "key",
    JsonSerializer.Serialize(value, AppJsonContext.Default.UserPrefs));

var json = await JSRuntime.InvokeAsync<string?>("localStorage.getItem", "key");
if (json is not null)
{
    value = JsonSerializer.Deserialize(json, AppJsonContext.Default.UserPrefs);
}
```

**Gotcha:** `ProtectedBrowserStorage` is not available during prerendering. Always access it in `OnAfterRenderAsync(firstRender: true)`, never in `OnInitializedAsync`.


## JavaScript Interop

### Calling JavaScript from .NET

```csharp
@inject IJSRuntime JSRuntime

// Invoke a global JS function
await JSRuntime.InvokeVoidAsync("console.log", "Hello from Blazor");

// Invoke and get a return value
var width = await JSRuntime.InvokeAsync<int>("getWindowWidth");

// With timeout (important for Server to avoid hanging circuits)
var result = await JSRuntime.InvokeAsync<string>(
    "expensiveOperation",
    TimeSpan.FromSeconds(10),
    inputData);
```

### JavaScript Module Imports (AOT-Safe)

```csharp
// Import a JS module -- trim-safe, no reflection
private IJSObjectReference? module;

protected override async Task OnAfterRenderAsync(bool firstRender)
{
    if (firstRender)
    {
        module = await JSRuntime.InvokeAsync<IJSObjectReference>(
            "import", "./js/interop.js");
        await module.InvokeVoidAsync("initialize", elementRef);
    }
}

// Always dispose module references
public async ValueTask DisposeAsync()
{
    if (module is not null)
    {
        await module.DisposeAsync();
    }
}
```

```javascript
// wwwroot/js/interop.js
export function initialize(element) {
    // Set up the element
}

export function getValue(element) {
    return element.value;
}
```

### Calling .NET from JavaScript

```csharp
// Instance method callback
private DotNetObjectReference<MyComponent>? dotNetRef;

protected override void OnInitialized()
{
    dotNetRef = DotNetObjectReference.Create(this);
}

[JSInvokable]
public void OnJsEvent(string data)
{
    message = data;
    StateHasChanged();
}

public void Dispose()
{
    dotNetRef?.Dispose();
}
```

```javascript
// Call .NET from JS
export function registerCallback(dotNetRef) {
    document.addEventListener('custom-event', (e) => {
        dotNetRef.invokeMethodAsync('OnJsEvent', e.detail);
    });
}
```

### JS Interop per Render Mode

| Concern | InteractiveServer | InteractiveWebAssembly | InteractiveAuto | Hybrid |
|---|---|---|---|---|
| JS call timing | After SignalR confirms render | After WASM runtime loads | SignalR initially, then direct after WASM switch | After WebView loads |
| `OnAfterRender` available | Yes | Yes | Yes | Yes |
| IJSRuntime sync calls | Not supported (async only) | `IJSInProcessRuntime` available | Async-only during Server phase; `IJSInProcessRuntime` after WASM switch | `IJSInProcessRuntime` available |
| Module imports | Via SignalR (latency) | Direct (fast) | SignalR (Server phase), direct (WASM phase) | Direct (fast) |

**Gotcha:** In InteractiveServer, all JS interop calls travel over SignalR, adding network latency. Minimize round trips by batching operations into a single JS function call.


## EditForm Validation

### Basic EditForm with Data Annotations

```razor
<EditForm Model="product" OnValidSubmit="HandleSubmit" FormName="product-form">
    <DataAnnotationsValidator />
    <ValidationSummary />

    <div>
        <label for="name">Name:</label>
        <InputText id="name" @bind-Value="product.Name" />
        <ValidationMessage For="() => product.Name" />
    </div>

    <div>
        <label for="price">Price:</label>
        <InputNumber id="price" @bind-Value="product.Price" />
        <ValidationMessage For="() => product.Price" />
    </div>

    <div>
        <label for="category">Category:</label>
        <InputSelect id="category" @bind-Value="product.Category">
            <option value="">Select...</option>
            <option value="Electronics">Electronics</option>
            <option value="Clothing">Clothing</option>
        </InputSelect>
        <ValidationMessage For="() => product.Category" />
    </div>

    <button type="submit">Save</button>
</EditForm>

@code {
    private ProductModel product = new();

    private async Task HandleSubmit()
    {
        await ProductService.CreateAsync(product);
        Navigation.NavigateTo("/products");
    }
}
```

### Model with Validation Attributes

```csharp
public sealed class ProductModel
{
    [Required(ErrorMessage = "Product name is required")]
    [StringLength(200, MinimumLength = 1)]
    public string Name { get; set; } = "";

    [Range(0.01, 1_000_000, ErrorMessage = "Price must be between {1} and {2}")]
    public decimal Price { get; set; }

    [Required(ErrorMessage = "Category is required")]
    public string Category { get; set; } = "";
}
```

### EditForm with Enhanced Form Handling (.NET 8+)

Static SSR forms require `FormName` and use `[SupplyParameterFromForm]`:

```razor
@page "/products/create"

<EditForm Model="product" OnValidSubmit="HandleSubmit" FormName="create-product" Enhance>
    <DataAnnotationsValidator />
    <!-- form fields -->
    <button type="submit">Create</button>
</EditForm>

@code {
    [SupplyParameterFromForm]
    private ProductModel product { get; set; } = new();

    private async Task HandleSubmit()
    {
        await ProductService.CreateAsync(product);
        Navigation.NavigateTo("/products");
    }
}
```

The `Enhance` attribute enables enhanced form handling -- the form submits via fetch and patches the DOM without a full page reload.

**Gotcha:** `FormName` must be unique across all forms on the page. Duplicate `FormName` values cause ambiguous form submission errors.


## QuickGrid

QuickGrid is a high-performance grid component built into Blazor (.NET 8+). It supports sorting, filtering, pagination, and virtualization.

### Basic QuickGrid

```razor
@using Microsoft.AspNetCore.Components.QuickGrid

<QuickGrid Items="products">
    <PropertyColumn Property="p => p.Name" Sortable="true" />
    <PropertyColumn Property="p => p.Price" Format="C2" Sortable="true" />
    <PropertyColumn Property="p => p.Category" Sortable="true" />
    <TemplateColumn Title="Actions">
        <button @onclick="() => Edit(context)">Edit</button>
    </TemplateColumn>
</QuickGrid>

@code {
    private IQueryable<Product> products = Enumerable.Empty<Product>().AsQueryable();

    protected override async Task OnInitializedAsync()
    {
        var list = await ProductService.GetAllAsync();
        products = list.AsQueryable();
    }

    private void Edit(Product product) => Navigation.NavigateTo($"/products/{product.Id}/edit");
}
```

### QuickGrid with Pagination

```razor
<QuickGrid Items="products" Pagination="pagination">
    <PropertyColumn Property="p => p.Name" Sortable="true" />
    <PropertyColumn Property="p => p.Price" Format="C2" />
</QuickGrid>

<Paginator State="pagination" />

@code {
    private PaginationState pagination = new() { ItemsPerPage = 20 };
    private IQueryable<Product> products = default!;
}
```

### QuickGrid with Virtualization

For large datasets, virtualization renders only visible rows:

```razor
<QuickGrid Items="products" Virtualize="true" ItemSize="50">
    <PropertyColumn Property="p => p.Name" />
    <PropertyColumn Property="p => p.Price" Format="C2" />
</QuickGrid>
```

<!-- net11-preview -->
### QuickGrid OnRowClick (.NET 11 Preview)

.NET 11 adds `OnRowClick` to QuickGrid for row-level click handling without template columns:

```razor
<QuickGrid Items="products" OnRowClick="HandleRowClick">
    <PropertyColumn Property="p => p.Name" />
    <PropertyColumn Property="p => p.Price" Format="C2" />
</QuickGrid>

@code {
    private void HandleRowClick(GridRowClickEventArgs<Product> args)
    {
        Navigation.NavigateTo($"/products/{args.Item.Id}");
    }
}
```

**Fallback (net10.0):** Use a `TemplateColumn` with a click handler or wrap each row in a clickable element.

Source: [ASP.NET Core .NET 11 Preview - QuickGrid enhancements](https://learn.microsoft.com/en-us/aspnet/core/release-notes/aspnetcore-11.0)


<!-- net11-preview -->
## .NET 11 Preview Features

### EnvironmentBoundary Component

`EnvironmentBoundary` conditionally renders content based on the hosting environment (Development, Staging, Production):

```razor
<EnvironmentBoundary Include="Development">
    <p>Debug panel -- only visible in Development</p>
    <DebugToolbar />
</EnvironmentBoundary>

<EnvironmentBoundary Exclude="Production">
    <p>Testing controls -- hidden in Production</p>
</EnvironmentBoundary>
```

**Fallback (net10.0):** Inject `IWebHostEnvironment` and use conditional rendering in `@code`.

Source: [ASP.NET Core .NET 11 Preview - EnvironmentBoundary](https://learn.microsoft.com/en-us/aspnet/core/release-notes/aspnetcore-11.0)

### Label and DisplayName Support

.NET 11 adds `[DisplayName]` support for input components, automatically generating `<label>` elements:

```razor
<EditForm Model="model" FormName="contact">
    <!-- Automatically renders <label> from [DisplayName] -->
    <InputText @bind-Value="model.FullName" />
    <InputText @bind-Value="model.EmailAddress" />
</EditForm>

@code {
    private ContactModel model = new();
}

// Model
public sealed class ContactModel
{
    [DisplayName("Full Name")]
    [Required]
    public string FullName { get; set; } = "";

    [DisplayName("Email Address")]
    [EmailAddress]
    public string EmailAddress { get; set; } = "";
}
```

**Fallback (net10.0):** Add explicit `<label for="...">` elements manually.

Source: [ASP.NET Core .NET 11 Preview - Label/DisplayName](https://learn.microsoft.com/en-us/aspnet/core/release-notes/aspnetcore-11.0)

### IHostedService in WebAssembly

.NET 11 allows `IHostedService` implementations to run in Blazor WebAssembly, enabling background tasks in the browser:

```csharp
// Register in WASM Program.cs
builder.Services.AddHostedService<DataSyncService>();

public sealed class DataSyncService : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            await SyncDataFromServer();
            await Task.Delay(TimeSpan.FromMinutes(5), stoppingToken);
        }
    }
}
```

**Fallback (net10.0):** Use a `Timer` in a component or inject a singleton service that starts background work on first use.

Source: [ASP.NET Core .NET 11 Preview - IHostedService in WASM](https://learn.microsoft.com/en-us/aspnet/core/release-notes/aspnetcore-11.0)

<!-- net11-preview -->
### SignalR ConfigureConnection

.NET 11 adds `ConfigureConnection` to the Blazor Server circuit hub, allowing customization of the SignalR connection (e.g., adding custom headers, configuring reconnection):

```csharp
// Program.cs
app.MapBlazorHub(options =>
{
    options.ConfigureConnection = connection =>
    {
        connection.Metadata["tenant"] = "default";
    };
});
```

**Fallback (net10.0):** Use `IHubFilter` or middleware to inspect/modify connections at the hub level.

Source: [ASP.NET Core .NET 11 Preview - SignalR ConfigureConnection](https://learn.microsoft.com/en-us/aspnet/core/release-notes/aspnetcore-11.0)


## Agent Gotchas

1. **Do not call JS interop in `OnInitializedAsync`.** The DOM is not available yet. Use `OnAfterRenderAsync(firstRender: true)` for JS calls that need DOM elements.
2. **Do not forget `StateHasChanged()` after external state changes.** When state changes from a non-Blazor context (timer, event handler, JS callback), call `StateHasChanged()` or `InvokeAsync(StateHasChanged)` to trigger re-render.
3. **Do not use `ProtectedBrowserStorage` during prerendering.** It throws because no interactive circuit exists yet. Access it only in `OnAfterRenderAsync`.
4. **Do not forget `FormName` on Static SSR forms.** Without it, form submissions in Static SSR mode are not routed to the correct handler.
5. **Do not dispose `DotNetObjectReference` before JS is done with it.** Premature disposal causes `JSException` when JavaScript tries to invoke the callback. Dispose in `Dispose()` or `DisposeAsync()`.
6. **Do not assume Scoped services are per-request in Blazor Server.** Scoped services live for the entire circuit. Use `OwningComponentBase<T>` when you need component-scoped service lifetimes.


## Prerequisites

- .NET 8.0+ (QuickGrid, enhanced form handling, cascading values with `IsFixed`)
- `Microsoft.AspNetCore.Components.QuickGrid` package for QuickGrid
- .NET 11 preview for EnvironmentBoundary, Label/DisplayName, QuickGrid OnRowClick, IHostedService in WASM


## Knowledge Sources

Blazor component patterns in this skill are grounded in guidance from:

- **Damian Edwards** -- Razor and Blazor component design patterns, render mode architecture, and performance best practices. Principal architect on the ASP.NET team.

> These sources inform the patterns and rationale presented above. This skill does not claim to represent or speak for any individual.


## References

- [Blazor Component Lifecycle](https://learn.microsoft.com/en-us/aspnet/core/blazor/components/lifecycle?view=aspnetcore-10.0)
- [Blazor State Management](https://learn.microsoft.com/en-us/aspnet/core/blazor/state-management?view=aspnetcore-10.0)
- [Blazor JS Interop](https://learn.microsoft.com/en-us/aspnet/core/blazor/javascript-interoperability/?view=aspnetcore-10.0)
- [Blazor Forms and Validation](https://learn.microsoft.com/en-us/aspnet/core/blazor/forms/?view=aspnetcore-10.0)
- [QuickGrid Component](https://learn.microsoft.com/en-us/aspnet/core/blazor/components/quickgrid?view=aspnetcore-10.0)
- [Cascading Values and Parameters](https://learn.microsoft.com/en-us/aspnet/core/blazor/components/cascading-values-and-parameters?view=aspnetcore-10.0)
