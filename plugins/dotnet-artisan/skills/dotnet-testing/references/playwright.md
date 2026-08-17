# Playwright

Playwright for .NET: browser automation and end-to-end testing. Covers browser lifecycle management, page interactions, assertions, CI caching of browser binaries, trace viewer for debugging failures, and codegen for rapid test scaffolding.

**Version assumptions:** Playwright 1.40+ for .NET, .NET 8.0+ baseline. Playwright supports Chromium, Firefox, and WebKit browsers.

## Package Setup

```xml
<PackageReference Include="Microsoft.Playwright" Version="1.*" />
<!-- For xUnit integration: -->
<PackageReference Include="Microsoft.Playwright.Xunit" Version="1.*" />
<!-- For NUnit integration: -->
<!-- <PackageReference Include="Microsoft.Playwright.NUnit" Version="1.*" /> -->
```

### Installing Browsers

Playwright requires downloading browser binaries before tests can run:

```bash
# After building the test project:
pwsh bin/Debug/net8.0/playwright.ps1 install

# Or install specific browsers:
pwsh bin/Debug/net8.0/playwright.ps1 install chromium
pwsh bin/Debug/net8.0/playwright.ps1 install firefox

# Using dotnet tool:
dotnet tool install --global Microsoft.Playwright.CLI
playwright install
```

---

## Basic Test Structure

### With Playwright xUnit Base Class

```csharp
using Microsoft.Playwright;
using Microsoft.Playwright.Xunit;

// PageTest provides Page, Browser, BrowserContext, and Playwright properties
public class HomePageTests : PageTest
{
    [Fact]
    public async Task HomePage_Title_ContainsAppName()
    {
        await Page.GotoAsync("https://localhost:5001");

        await Expect(Page).ToHaveTitleAsync(new Regex("My App"));
    }

    [Fact]
    public async Task HomePage_NavLinks_AreVisible()
    {
        await Page.GotoAsync("https://localhost:5001");

        var nav = Page.Locator("nav");
        await Expect(nav.GetByRole(AriaRole.Link, new() { Name = "Home" }))
            .ToBeVisibleAsync();
        await Expect(nav.GetByRole(AriaRole.Link, new() { Name = "About" }))
            .ToBeVisibleAsync();
    }
}
```

### Manual Setup (Without Base Class)

```csharp
public class ManualSetupTests : IAsyncLifetime
{
    private IPlaywright _playwright = null!;
    private IBrowser _browser = null!;
    private IBrowserContext _context = null!;
    private IPage _page = null!;

    public async ValueTask InitializeAsync()
    {
        _playwright = await Playwright.CreateAsync();
        _browser = await _playwright.Chromium.LaunchAsync(new BrowserTypeLaunchOptions
        {
            Headless = true
        });
        _context = await _browser.NewContextAsync(new BrowserNewContextOptions
        {
            ViewportSize = new ViewportSize { Width = 1280, Height = 720 },
            Locale = "en-US"
        });
        _page = await _context.NewPageAsync();
    }

    public async ValueTask DisposeAsync()
    {
        await _page.CloseAsync();
        await _context.CloseAsync();
        await _browser.CloseAsync();
        _playwright.Dispose();
    }

    [Fact]
    public async Task Login_ValidUser_RedirectsToDashboard()
    {
        await _page.GotoAsync("https://localhost:5001/login");

        await _page.FillAsync("[data-testid='email']", "user@example.com");
        await _page.FillAsync("[data-testid='password']", "P@ssw0rd!");
        await _page.ClickAsync("[data-testid='login-btn']");

        await Expect(_page).ToHaveURLAsync(new Regex("/dashboard"));
    }
}
```

---

## Locators and Interactions

### Recommended Locator Strategies

```csharp
// BEST: Role-based (accessible and semantic)
var submitBtn = Page.GetByRole(AriaRole.Button, new() { Name = "Submit Order" });

// GOOD: Test ID (stable, explicit)
var emailInput = Page.Locator("[data-testid='email-input']");

// GOOD: Label text (user-visible, accessible)
var nameField = Page.GetByLabel("Full Name");

// GOOD: Placeholder (user-visible)
var searchBox = Page.GetByPlaceholder("Search products...");

// AVOID: CSS class (fragile, changes with styling)
var card = Page.Locator(".card-primary");

// AVOID: XPath (brittle, hard to read)
var cell = Page.Locator("//table/tbody/tr[1]/td[2]");
```

### Common Interactions

```csharp
// Text input
await Page.FillAsync("[data-testid='name']", "Alice Johnson");

// Click
await Page.ClickAsync("[data-testid='submit']");

// Select dropdown
await Page.SelectOptionAsync("[data-testid='country']", "US");

// Checkbox / radio
await Page.CheckAsync("[data-testid='agree-terms']");

// File upload
await Page.SetInputFilesAsync("[data-testid='avatar']", "testdata/photo.jpg");

// Keyboard
await Page.Keyboard.PressAsync("Enter");
await Page.Keyboard.TypeAsync("search query");

// Hover (for dropdowns, tooltips)
await Page.HoverAsync("[data-testid='user-menu']");
```

### Assertions (Expect API)

Playwright assertions auto-retry until the condition is met or the timeout expires:

```csharp
// Element visibility
await Expect(Page.Locator("[data-testid='success']")).ToBeVisibleAsync();
await Expect(Page.Locator("[data-testid='spinner']")).ToBeHiddenAsync();

// Text content
await Expect(Page.Locator("[data-testid='total']")).ToHaveTextAsync("$99.99");
await Expect(Page.Locator("[data-testid='status']")).ToContainTextAsync("Completed");

// Attribute
await Expect(Page.Locator("[data-testid='submit']")).ToBeEnabledAsync();
await Expect(Page.Locator("[data-testid='email']")).ToHaveValueAsync("user@example.com");

// Page-level
await Expect(Page).ToHaveURLAsync(new Regex("/orders/\\d+"));
await Expect(Page).ToHaveTitleAsync("Order Details - My App");

// Count
await Expect(Page.Locator("[data-testid='order-row']")).ToHaveCountAsync(5);
```

---

## Network Interception

### Mocking API Responses

```csharp
[Fact]
public async Task OrderList_WithMockedApi_DisplaysOrders()
{
    // Intercept API calls and return mock data
    await Page.RouteAsync("**/api/orders", async route =>
    {
        var json = JsonSerializer.Serialize(new[]
        {
            new { Id = 1, CustomerName = "Alice", Total = 99.99 },
            new { Id = 2, CustomerName = "Bob", Total = 149.50 }
        });
        await route.FulfillAsync(new RouteFulfillOptions
        {
            Status = 200,
            ContentType = "application/json",
            Body = json
        });
    });

    await Page.GotoAsync("https://localhost:5001/orders");

    await Expect(Page.Locator("[data-testid='order-row']")).ToHaveCountAsync(2);
}
```

### Waiting for Network Requests

```csharp
[Fact]
public async Task CreateOrder_SubmitForm_WaitsForApiResponse()
{
    await Page.GotoAsync("https://localhost:5001/orders/new");

    await Page.FillAsync("[data-testid='customer']", "Alice");
    await Page.FillAsync("[data-testid='amount']", "99.99");

    // Wait for the API call triggered by form submission
    var responseTask = Page.WaitForResponseAsync(
        response => response.Url.Contains("/api/orders") && response.Status == 201);

    await Page.ClickAsync("[data-testid='submit']");

    var response = await responseTask;
    Assert.Equal(201, response.Status);
}
```

---

## CI Browser Caching

Downloading browser binaries on every CI run is slow (500MB+). Cache them to speed up builds.

### GitHub Actions Caching

```yaml
# .github/workflows/e2e-tests.yml
jobs:
  e2e:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup .NET
        uses: actions/setup-dotnet@v4
        with:
          dotnet-version: '8.0.x'

      - name: Build
        run: dotnet build tests/MyApp.E2E/

      - name: Cache Playwright browsers
        id: playwright-cache
        uses: actions/cache@v4
        with:
          path: ~/.cache/ms-playwright
          key: playwright-${{ runner.os }}-${{ hashFiles('tests/MyApp.E2E/MyApp.E2E.csproj') }}

      - name: Install Playwright browsers
        if: steps.playwright-cache.outputs.cache-hit != 'true'
        run: pwsh tests/MyApp.E2E/bin/Debug/net8.0/playwright.ps1 install --with-deps

      - name: Install Playwright system deps
        if: steps.playwright-cache.outputs.cache-hit == 'true'
        run: pwsh tests/MyApp.E2E/bin/Debug/net8.0/playwright.ps1 install-deps

      - name: Run E2E tests
        run: dotnet test tests/MyApp.E2E/
```

### Azure DevOps Caching

```yaml
# azure-pipelines.yml
steps:
  - task: Cache@2
    inputs:
      key: 'playwright | "$(Agent.OS)" | tests/MyApp.E2E/MyApp.E2E.csproj'
      path: $(HOME)/.cache/ms-playwright
      restoreKeys: |
        playwright | "$(Agent.OS)"
      cacheHitVar: PLAYWRIGHT_CACHE_RESTORED
    displayName: Cache Playwright browsers

  - script: pwsh tests/MyApp.E2E/bin/Debug/net8.0/playwright.ps1 install --with-deps
    condition: ne(variables.PLAYWRIGHT_CACHE_RESTORED, 'true')
    displayName: Install Playwright browsers

  - script: pwsh tests/MyApp.E2E/bin/Debug/net8.0/playwright.ps1 install-deps
    condition: eq(variables.PLAYWRIGHT_CACHE_RESTORED, 'true')
    displayName: Install Playwright system deps (cached browsers)

  - script: dotnet test tests/MyApp.E2E/
    displayName: Run E2E tests
```

### Cache Key Strategy

The cache key should include:
- **OS:** Browser binaries are platform-specific
- **Project file hash:** Playwright version determines browser versions; changing the package version invalidates the cache
- **Fallback key:** Allows partial cache restoration when the project file changes

---

## Trace Viewer

Playwright's trace viewer captures a full recording of test execution for debugging failures. Each trace includes screenshots, DOM snapshots, network logs, and console output.

### Enabling Traces

```csharp
public class TracedTests : IAsyncLifetime
{
    private IPlaywright _playwright = null!;
    private IBrowser _browser = null!;
    private IBrowserContext _context = null!;

    public IPage Page { get; private set; } = null!;

    public async ValueTask InitializeAsync()
    {
        _playwright = await Playwright.CreateAsync();
        _browser = await _playwright.Chromium.LaunchAsync();
        _context = await _browser.NewContextAsync();

        // Start tracing before each test
        await _context.Tracing.StartAsync(new TracingStartOptions
        {
            Screenshots = true,
            Snapshots = true,
            Sources = true
        });

        Page = await _context.NewPageAsync();
    }

    public async ValueTask DisposeAsync()
    {
        // Save trace on failure (check test result in xUnit requires custom wrapper)
        await _context.Tracing.StopAsync(new TracingStopOptions
        {
            Path = Path.Combine("test-results", "traces",
                $"trace-{DateTime.UtcNow:yyyyMMdd-HHmmss}.zip")
        });

        await Page.CloseAsync();
        await _context.CloseAsync();
        await _browser.CloseAsync();
        _playwright.Dispose();
    }
}
```

### Viewing Traces

```bash
# Open trace file in browser
pwsh bin/Debug/net8.0/playwright.ps1 show-trace test-results/traces/trace-20260101-120000.zip

# Or use the online trace viewer
# Upload the .zip to https://trace.playwright.dev/
```

### Trace on Failure Only

Save traces only when tests fail to reduce storage:

```csharp
// In a custom test class or middleware
public async Task RunWithTrace(Func<IPage, Task> testAction, string testName)
{
    await _context.Tracing.StartAsync(new TracingStartOptions
    {
        Screenshots = true,
        Snapshots = true,
        Sources = true
    });

    try
    {
        await testAction(Page);
        // Test passed -- discard trace
        await _context.Tracing.StopAsync();
    }
    catch
    {
        // Test failed -- save trace for debugging
        await _context.Tracing.StopAsync(new TracingStopOptions
        {
            Path = $"test-results/traces/{testName}.zip"
        });
        throw;
    }
}
```

---

## Codegen

Playwright's code generator records browser interactions and generates test code. Use it to scaffold tests quickly, then refine the generated code.

### Running Codegen

```bash
# Open codegen with your app URL
pwsh bin/Debug/net8.0/playwright.ps1 codegen https://localhost:5001

# With specific browser
pwsh bin/Debug/net8.0/playwright.ps1 codegen --browser firefox https://localhost:5001

# With device emulation
pwsh bin/Debug/net8.0/playwright.ps1 codegen --device "iPhone 15" https://localhost:5001

# With saved authentication state
pwsh bin/Debug/net8.0/playwright.ps1 codegen --save-storage auth.json https://localhost:5001
```

### Codegen Best Practices

1. **Use codegen as a starting point,** not the final test. Generated code often uses fragile selectors and lacks proper assertions.
2. **Replace generated selectors** with `data-testid` or role-based locators immediately after generating.
3. **Add meaningful assertions.** Codegen records actions but does not know what to verify. Add `Expect()` calls for expected outcomes.
4. **Extract page objects** from generated code. Group related interactions into page object methods.

### Before and After Codegen Refinement

```csharp
// GENERATED by codegen (fragile, no assertions):
await page.GotoAsync("https://localhost:5001/orders");
await page.Locator("#root > div > main > div:nth-child(2) > button").ClickAsync();
await page.GetByPlaceholder("Customer name").FillAsync("Alice");
await page.GetByPlaceholder("Amount").FillAsync("99.99");
await page.Locator("form > button[type='submit']").ClickAsync();

// REFINED (stable selectors, proper assertions):
await Page.GotoAsync("https://localhost:5001/orders");
await Page.ClickAsync("[data-testid='new-order-btn']");
await Page.FillAsync("[data-testid='customer-name']", "Alice");
await Page.FillAsync("[data-testid='amount']", "99.99");
await Page.ClickAsync("[data-testid='submit-order']");

await Expect(Page.Locator("[data-testid='success-toast']"))
    .ToBeVisibleAsync();
await Expect(Page).ToHaveURLAsync(new Regex("/orders/\\d+"));
```

---

## Multi-Browser Testing

### Running Tests Across Browsers

```csharp
// Using Playwright xUnit base class with environment variable
// Set BROWSER=chromium|firefox|webkit via CLI or CI config
public class CrossBrowserTests : PageTest
{
    [Fact]
    public async Task OrderFlow_WorksAcrossBrowsers()
    {
        // This test runs in whichever browser BROWSER env var specifies
        await Page.GotoAsync("https://localhost:5001/orders/new");
        await Page.FillAsync("[data-testid='customer']", "Alice");
        await Page.ClickAsync("[data-testid='submit']");

        await Expect(Page.Locator("[data-testid='success']")).ToBeVisibleAsync();
    }
}
```

```bash
# Run tests in each browser
BROWSER=chromium dotnet test
BROWSER=firefox dotnet test
BROWSER=webkit dotnet test
```

### CI Matrix Strategy

```yaml
# GitHub Actions matrix for multi-browser
strategy:
  matrix:
    browser: [chromium, firefox, webkit]
steps:
  - name: Run E2E tests
    run: dotnet test tests/MyApp.E2E/
    env:
      BROWSER: ${{ matrix.browser }}
```

---

## Key Principles

- **Use Playwright assertions (`Expect`) instead of raw xUnit `Assert`.** Playwright assertions auto-retry with configurable timeouts, eliminating flaky timing issues.
- **Cache browser binaries in CI.** Downloading 500MB+ of browsers per run wastes time and bandwidth. Cache by OS + Playwright version.
- **Enable trace viewer for debugging CI failures.** Traces capture everything needed to reproduce a failure without re-running the test.
- **Use codegen to bootstrap tests, then refine.** Generated code gets you started fast; manual refinement makes tests maintainable.
- **Prefer role-based or `data-testid` locators** over CSS classes or XPath. See [skill:dotnet-testing] `references/ui-testing-core.md` for the full selector priority guide.

---

## Agent Gotchas

1. **Do not forget to install browsers after adding the Playwright package.** The NuGet package does not include browser binaries. Run the install script after building.
2. **Do not use `Task.Delay` for waiting.** Playwright's auto-waiting and `Expect` assertions handle timing automatically. Adding delays makes tests slow and still flaky.
3. **Do not hardcode `localhost` ports.** Use configuration or environment variables for the base URL. CI environments may use different ports than local development.
4. **Do not skip `--with-deps` on first CI install.** Playwright browsers need system libraries (libgbm, libasound, etc.) on Linux. The `--with-deps` flag installs them. Subsequent cached runs only need `install-deps`.
5. **Do not store trace files in the repository.** Traces are large binary files. Write them to a `test-results/` directory that is git-ignored, and upload them as CI artifacts.
6. **Do not create a new browser instance per test.** Browser launch is expensive. Use `IClassFixture` or the Playwright xUnit base class to share a browser across tests in a class. Create a new `BrowserContext` per test for isolation.

---

## References

- [Playwright for .NET Documentation](https://playwright.dev/dotnet/)
- [Playwright Locators](https://playwright.dev/dotnet/docs/locators)
- [Playwright Assertions](https://playwright.dev/dotnet/docs/test-assertions)
- [Playwright Trace Viewer](https://playwright.dev/dotnet/docs/trace-viewer)
- [Playwright Codegen](https://playwright.dev/dotnet/docs/codegen)
- [Playwright CI Configuration](https://playwright.dev/dotnet/docs/ci)
- [Playwright Browser Downloads](https://playwright.dev/dotnet/docs/browsers)
