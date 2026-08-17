# Blazor Testing

bUnit testing for Blazor components. Covers component rendering and markup assertions, event handling, cascading parameters and cascading values, JavaScript interop mocking, and async component lifecycle testing. bUnit provides an in-memory Blazor renderer that executes components without a browser.

**Version assumptions:** .NET 8.0+ baseline, bUnit 1.x (stable). Examples use the latest bUnit APIs. bUnit supports both Blazor Server and Blazor WebAssembly components.

## Package Setup

```xml
<PackageReference Include="bunit" Version="1.*" />
<!-- bUnit depends on xunit internally; ensure compatible xUnit version -->
```

bUnit test classes inherit from `TestContext` (or use it via composition):

```csharp
using Bunit;
using Xunit;

// Inheritance approach (less boilerplate)
public class CounterTests : TestContext
{
    [Fact]
    public void Counter_InitialRender_ShowsZero()
    {
        var cut = RenderComponent<Counter>();

        cut.Find("[data-testid='count']").MarkupMatches("<span data-testid=\"count\">0</span>");
    }
}

// Composition approach (more flexibility)
public class CounterCompositionTests : IDisposable
{
    private readonly TestContext _ctx = new();

    [Fact]
    public void Counter_InitialRender_ShowsZero()
    {
        var cut = _ctx.RenderComponent<Counter>();
        Assert.Equal("0", cut.Find("[data-testid='count']").TextContent);
    }

    public void Dispose() => _ctx.Dispose();
}
```


## Component Rendering

### Basic Rendering and Markup Assertions

```csharp
public class AlertTests : TestContext
{
    [Fact]
    public void Alert_WithMessage_RendersCorrectMarkup()
    {
        var cut = RenderComponent<Alert>(parameters => parameters
            .Add(p => p.Message, "Order saved successfully")
            .Add(p => p.Severity, AlertSeverity.Success));

        // Assert on text content
        Assert.Contains("Order saved successfully", cut.Markup);

        // Assert on specific elements
        var alert = cut.Find("[data-testid='alert']");
        Assert.Contains("success", alert.ClassList);
    }

    [Fact]
    public void Alert_Dismissed_RendersNothing()
    {
        var cut = RenderComponent<Alert>(parameters => parameters
            .Add(p => p.Message, "Info")
            .Add(p => p.IsDismissed, true));

        Assert.Empty(cut.Markup.Trim());
    }
}
```

### Rendering with Child Content

```csharp
[Fact]
public void Card_WithChildContent_RendersChildren()
{
    var cut = RenderComponent<Card>(parameters => parameters
        .AddChildContent("<p>Card body content</p>"));

    cut.Find("p").MarkupMatches("<p>Card body content</p>");
}

[Fact]
public void Card_WithRenderFragment_RendersTemplate()
{
    var cut = RenderComponent<Card>(parameters => parameters
        .Add(p => p.Header, builder =>
        {
            builder.OpenElement(0, "h2");
            builder.AddContent(1, "Card Title");
            builder.CloseElement();
        })
        .AddChildContent("<p>Body</p>"));

    cut.Find("h2").MarkupMatches("<h2>Card Title</h2>");
}
```

### Rendering with Dependency Injection

Register services before rendering components that depend on them:

```csharp
public class OrderListTests : TestContext
{
    [Fact]
    public async Task OrderList_OnLoad_DisplaysOrders()
    {
        // Register mock service
        var mockService = Substitute.For<IOrderService>();
        mockService.GetOrdersAsync().Returns(
        [
            new OrderDto { Id = 1, CustomerName = "Alice", Total = 99.99m },
            new OrderDto { Id = 2, CustomerName = "Bob", Total = 149.50m }
        ]);
        Services.AddSingleton(mockService);

        // Render component -- DI resolves IOrderService automatically
        var cut = RenderComponent<OrderList>();

        // Wait for async data loading
        cut.WaitForState(() => cut.FindAll("[data-testid='order-row']").Count == 2);

        var rows = cut.FindAll("[data-testid='order-row']");
        Assert.Equal(2, rows.Count);
        Assert.Contains("Alice", rows[0].TextContent);
    }
}
```


## Event Handling

### Click Events

```csharp
[Fact]
public void Counter_ClickIncrement_IncreasesCount()
{
    var cut = RenderComponent<Counter>();

    cut.Find("[data-testid='increment-btn']").Click();

    Assert.Equal("1", cut.Find("[data-testid='count']").TextContent);
}

[Fact]
public void Counter_MultipleClicks_AccumulatesCount()
{
    var cut = RenderComponent<Counter>();

    var button = cut.Find("[data-testid='increment-btn']");
    button.Click();
    button.Click();
    button.Click();

    Assert.Equal("3", cut.Find("[data-testid='count']").TextContent);
}
```

### Form Input Events

```csharp
[Fact]
public void SearchBox_TypeText_UpdatesResults()
{
    Services.AddSingleton(Substitute.For<ISearchService>());
    var cut = RenderComponent<SearchBox>();

    var input = cut.Find("[data-testid='search-input']");
    input.Input("wireless keyboard");

    Assert.Equal("wireless keyboard", cut.Instance.SearchTerm);
}

[Fact]
public async Task LoginForm_SubmitValid_CallsAuthService()
{
    var authService = Substitute.For<IAuthService>();
    authService.LoginAsync(Arg.Any<string>(), Arg.Any<string>())
        .Returns(new AuthResult { Success = true });
    Services.AddSingleton(authService);

    var cut = RenderComponent<LoginForm>();

    cut.Find("[data-testid='email']").Change("user@example.com");
    cut.Find("[data-testid='password']").Change("P@ssw0rd!");
    cut.Find("[data-testid='login-form']").Submit();

    // Wait for async submission
    cut.WaitForState(() => cut.Instance.IsAuthenticated);

    await authService.Received(1).LoginAsync("user@example.com", "P@ssw0rd!");
}
```

### EventCallback Parameters

```csharp
[Fact]
public void DeleteButton_Click_InvokesOnDeleteCallback()
{
    var deletedId = 0;
    var cut = RenderComponent<DeleteButton>(parameters => parameters
        .Add(p => p.ItemId, 42)
        .Add(p => p.OnDelete, EventCallback.Factory.Create<int>(
            this, id => deletedId = id)));

    cut.Find("[data-testid='delete-btn']").Click();

    Assert.Equal(42, deletedId);
}
```


## Cascading Parameters

### CascadingValue Setup

```csharp
[Fact]
public void ThemedButton_WithDarkTheme_AppliesDarkClass()
{
    var theme = new AppTheme { Mode = ThemeMode.Dark, PrimaryColor = "#1a1a2e" };

    var cut = RenderComponent<ThemedButton>(parameters => parameters
        .Add(p => p.Label, "Save")
        .AddCascadingValue(theme));

    var button = cut.Find("button");
    Assert.Contains("dark-theme", button.ClassList);
}

[Fact]
public void UserDisplay_WithCascadedAuthState_ShowsUserName()
{
    var authState = new AuthenticationState(
        new ClaimsPrincipal(new ClaimsIdentity(
        [
            new Claim(ClaimTypes.Name, "Alice"),
            new Claim(ClaimTypes.Role, "Admin")
        ], "TestAuth")));

    var cut = RenderComponent<UserDisplay>(parameters => parameters
        .AddCascadingValue(Task.FromResult(authState)));

    Assert.Contains("Alice", cut.Find("[data-testid='user-name']").TextContent);
}
```

### Named Cascading Values

```csharp
[Fact]
public void LayoutComponent_ReceivesNamedCascadingValues()
{
    var cut = RenderComponent<DashboardWidget>(parameters => parameters
        .AddCascadingValue("PageTitle", "Dashboard")
        .AddCascadingValue("SidebarCollapsed", true));

    Assert.Contains("Dashboard", cut.Find("[data-testid='widget-title']").TextContent);
}
```


## JavaScript Interop Mocking

Blazor components that call JavaScript via `IJSRuntime` require mock setup in bUnit. bUnit provides a built-in JS interop mock.

### Basic JSInterop Setup

```csharp
public class ClipboardButtonTests : TestContext
{
    [Fact]
    public void CopyButton_Click_InvokesClipboardAPI()
    {
        // Set up JS interop mock -- bUnit's JSInterop is available via this.JSInterop
        JSInterop.SetupVoid("navigator.clipboard.writeText", "Hello, World!");

        var cut = RenderComponent<CopyButton>(parameters => parameters
            .Add(p => p.TextToCopy, "Hello, World!"));

        cut.Find("[data-testid='copy-btn']").Click();

        // Verify the JS call was made
        JSInterop.VerifyInvoke("navigator.clipboard.writeText", calledTimes: 1);
    }
}
```

### JSInterop with Return Values

```csharp
[Fact]
public void GeoLocation_OnLoad_DisplaysCoordinates()
{
    // Mock JS call that returns a value
    var location = new { Latitude = 47.6062, Longitude = -122.3321 };
    JSInterop.Setup<object>("getGeoLocation").SetResult(location);

    var cut = RenderComponent<LocationDisplay>();

    cut.WaitForState(() => cut.Find("[data-testid='coordinates']").TextContent.Contains("47.6"));
    Assert.Contains("47.6062", cut.Find("[data-testid='coordinates']").TextContent);
}
```

### Catch-All JSInterop Mode

For components with many JS calls, use loose mode to avoid setting up every call:

```csharp
[Fact]
public void RichEditor_Render_DoesNotThrowJSErrors()
{
    // Loose mode: unmatched JS calls return default values instead of throwing
    JSInterop.Mode = JSRuntimeMode.Loose;

    var cut = RenderComponent<RichTextEditor>(parameters => parameters
        .Add(p => p.Content, "Initial content"));

    // Component renders without JS exceptions
    Assert.NotEmpty(cut.Markup);
}
```


## Async Component Lifecycle

### Testing OnInitializedAsync

```csharp
[Fact]
public void ProductList_WhileLoading_ShowsSpinner()
{
    var tcs = new TaskCompletionSource<List<ProductDto>>();
    var productService = Substitute.For<IProductService>();
    productService.GetProductsAsync().Returns(tcs.Task);
    Services.AddSingleton(productService);

    var cut = RenderComponent<ProductList>();

    // Component is still loading -- spinner should be visible
    Assert.NotNull(cut.Find("[data-testid='loading-spinner']"));

    // Complete the async operation
    tcs.SetResult([new ProductDto { Name = "Widget", Price = 9.99m }]);
    cut.WaitForState(() => cut.FindAll("[data-testid='product-item']").Count > 0);

    // Spinner gone, products visible
    Assert.Throws<ElementNotFoundException>(
        () => cut.Find("[data-testid='loading-spinner']"));
    Assert.Single(cut.FindAll("[data-testid='product-item']"));
}
```

### Testing Error States

```csharp
[Fact]
public void ProductList_ServiceError_ShowsErrorMessage()
{
    var productService = Substitute.For<IProductService>();
    productService.GetProductsAsync()
        .ThrowsAsync(new HttpRequestException("Service unavailable"));
    Services.AddSingleton(productService);

    var cut = RenderComponent<ProductList>();

    cut.WaitForState(() =>
        cut.Find("[data-testid='error-message']").TextContent.Length > 0);

    Assert.Contains("Service unavailable",
        cut.Find("[data-testid='error-message']").TextContent);
}
```


## Key Principles

- **Render components in isolation.** bUnit tests individual components without a browser, making them fast and deterministic. Use this for component logic; use [skill:dotnet-testing] for full-app E2E flows.
- **Register all dependencies before rendering.** Any service the component injects via `[Inject]` must be registered in `Services` before `RenderComponent` is called.
- **Use `WaitForState` and `WaitForAssertion` for async components.** Do not use `Task.Delay` -- bUnit provides purpose-built waiting mechanisms.
- **Mock JS interop explicitly.** Unhandled JS interop calls throw by default in bUnit strict mode. Set up expected calls or switch to loose mode for JS-heavy components.
- **Test the rendered output, not component internals.** Assert on markup, text content, and element attributes -- not on private fields or internal state.


## Agent Gotchas

1. **Do not forget to register services before `RenderComponent`.** bUnit throws at render time if an `[Inject]`-ed service is missing. Register mocks or fakes for every injected dependency.
2. **Do not use `cut.Instance` to access private members.** `Instance` exposes the component's public API only. If you need to test internal state, expose it through public properties or test through rendered output.
3. **Do not forget to call `cut.WaitForState()` after triggering async operations.** Without it, assertions run before the component re-renders, causing false failures.
4. **Do not mix bUnit and Playwright in the same test class.** bUnit runs components in-memory (no browser); Playwright runs in a real browser. They serve different purposes and have incompatible lifecycles.
5. **Do not forget cascading values for components that expect them.** A component with `[CascadingParameter]` will receive `null` if no `CascadingValue` is provided, which may cause `NullReferenceException` during rendering.


## References

- [bUnit Documentation](https://bunit.dev/)
- [bUnit Getting Started](https://bunit.dev/docs/getting-started/)
- [bUnit JS Interop](https://bunit.dev/docs/test-doubles/emulating-ijsruntime)
- [Blazor Component Testing](https://learn.microsoft.com/en-us/aspnet/core/blazor/test)
- [Testing Blazor Components with bUnit (tutorial)](https://bunit.dev/docs/providing-input/)
