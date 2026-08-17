# Uno Testing

Testing Uno Platform applications across target heads (WASM, Desktop, Mobile). Covers Playwright-based browser automation for Uno WASM apps, platform-specific testing patterns for different runtime heads, and test infrastructure for cross-platform Uno projects.

**Version assumptions:** .NET 8.0+ baseline, Uno Platform 5.x+, Playwright 1.40+ for WASM testing. Uno Platform uses single-project structure with multiple target frameworks.

## Uno Testing Strategy by Head

Uno Platform apps run on multiple heads (WASM, Desktop/Skia, iOS, Android, Windows). Each head has different testing tools and trade-offs.

| Head | Testing Approach | Tool | Speed | Fidelity |
|------|-----------------|------|-------|----------|
| **WASM** | Browser automation | Playwright | Medium | High -- real browser rendering |
| **Desktop (Skia/GTK, WPF)** | UI automation | Appium / WinAppDriver | Medium | High -- real desktop rendering |
| **iOS** | Simulator automation | Appium + XCUITest | Slow | Highest -- real iOS rendering |
| **Android** | Emulator automation | Appium + UIAutomator2 | Slow | Highest -- real Android rendering |
| **Unit (shared logic)** | In-memory | xUnit (no UI) | Fast | N/A -- logic only |

**Recommended priority:** Test shared business logic with unit tests first. Use Playwright against the WASM head for UI verification -- it is the fastest UI testing path with the broadest coverage. Add platform-specific Appium tests only for behaviors that differ between heads.


## Playwright for Uno WASM

The WASM head renders Uno apps in a browser, making Playwright the natural choice for UI testing.

### Test Infrastructure

```csharp
// NuGet: Microsoft.Playwright
public class UnoWasmFixture : IAsyncLifetime
{
    public IPlaywright Playwright { get; private set; } = null!;
    public IBrowser Browser { get; private set; } = null!;
    public IPage Page { get; private set; } = null!;

    private Process? _serverProcess;

    public async ValueTask InitializeAsync()
    {
        // Start the WASM app (dotnet run or serve the published output)
        _serverProcess = await StartWasmServerAsync();

        Playwright = await Microsoft.Playwright.Playwright.CreateAsync();
        Browser = await Playwright.Chromium.LaunchAsync(new BrowserTypeLaunchOptions
        {
            Headless = true
        });
        Page = await Browser.NewPageAsync();

        // Wait for Uno WASM app to fully load
        await Page.GotoAsync("http://localhost:5000");
        await WaitForUnoAppReadyAsync();
    }

    public async ValueTask DisposeAsync()
    {
        await Page.CloseAsync();
        await Browser.CloseAsync();
        Playwright.Dispose();

        _serverProcess?.Kill(entireProcessTree: true);
        _serverProcess?.Dispose();
    }

    private async Task WaitForUnoAppReadyAsync()
    {
        // Uno WASM apps show a loading splash; wait for the app root to appear
        await Page.WaitForSelectorAsync(
            "[data-testid='app-root'], #uno-body",
            new() { State = WaitForSelectorState.Visible, Timeout = 30_000 });

        // Additional wait for Uno runtime initialization
        await Page.WaitForFunctionAsync(
            "() => document.querySelector('#uno-body')?.children.length > 0",
            null,
            new() { Timeout = 15_000 });
    }

    private static async Task<Process> StartWasmServerAsync()
    {
        var process = new Process
        {
            StartInfo = new ProcessStartInfo
            {
                FileName = "dotnet",
                Arguments = "run --project src/MyApp/MyApp.Wasm.csproj --no-build",
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            }
        };
        process.Start();

        // Wait for server to be ready by probing the health endpoint
        using var httpClient = new HttpClient();
        var deadline = DateTime.UtcNow.AddSeconds(30);
        while (DateTime.UtcNow < deadline)
        {
            try
            {
                var resp = await httpClient.GetAsync("http://localhost:5000");
                if (resp.IsSuccessStatusCode) break;
            }
            catch (HttpRequestException)
            {
                // Server not ready yet
            }
            await Task.Delay(500);
        }
        return process;
    }
}
```

### WASM UI Tests

```csharp
public class UnoNavigationTests : IClassFixture<UnoWasmFixture>
{
    private readonly IPage _page;

    public UnoNavigationTests(UnoWasmFixture fixture)
    {
        _page = fixture.Page;
    }

    [Fact]
    public async Task MainPage_LoadsSuccessfully()
    {
        // Uno WASM renders XAML controls as HTML elements
        // Use AutomationProperties.AutomationId for selectors
        var title = _page.Locator("[data-testid='main-title']");

        await Expect(title).ToBeVisibleAsync();
        await Expect(title).ToHaveTextAsync("Welcome");
    }

    [Fact]
    public async Task Navigation_ClickSettings_ShowsSettingsPage()
    {
        await _page.ClickAsync("[data-testid='nav-settings']");

        var settingsHeader = _page.Locator("[data-testid='settings-header']");
        await Expect(settingsHeader).ToBeVisibleAsync();
        await Expect(settingsHeader).ToHaveTextAsync("Settings");
    }
}
```

### Form Interaction Tests

```csharp
[Fact]
public async Task LoginForm_SubmitValid_NavigatesToDashboard()
{
    await _page.FillAsync("[data-testid='username-input']", "testuser");
    await _page.FillAsync("[data-testid='password-input']", "P@ssw0rd!");
    await _page.ClickAsync("[data-testid='login-button']");

    // Wait for navigation after login
    var dashboard = _page.Locator("[data-testid='dashboard-title']");
    await Expect(dashboard).ToBeVisibleAsync(
        new() { Timeout = 10_000 });
}

[Fact]
public async Task TodoList_AddItem_AppearsInList()
{
    await _page.FillAsync("[data-testid='todo-input']", "Buy groceries");
    await _page.ClickAsync("[data-testid='add-todo-btn']");

    var items = _page.Locator("[data-testid='todo-item']");
    await Expect(items).ToHaveCountAsync(1);
    await Expect(items.First).ToContainTextAsync("Buy groceries");
}
```


## Platform-Specific Testing

### AutomationProperties for Cross-Platform Selectors

Uno maps `AutomationProperties.AutomationId` to each platform's native identifier:

```xml
<!-- Uno XAML -- works across all heads -->
<Page x:Class="MyApp.Views.LoginPage"
      xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
      xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">

    <StackPanel>
        <TextBox AutomationProperties.AutomationId="username-input"
                 PlaceholderText="Username" />

        <PasswordBox AutomationProperties.AutomationId="password-input"
                     PlaceholderText="Password" />

        <Button AutomationProperties.AutomationId="login-button"
                Content="Log In" />

        <TextBlock AutomationProperties.AutomationId="error-message"
                   Foreground="Red" />
    </StackPanel>
</Page>
```

Platform mapping:
- **WASM:** Rendered as `data-testid` attribute (Playwright selector)
- **Android:** Maps to `content-desc` (Appium `AccessibilityId`)
- **iOS:** Maps to `accessibilityIdentifier` (Appium `AccessibilityId`)
- **Windows:** Maps to `AutomationId` (WinAppDriver `AccessibilityId`)

### Testing Platform-Specific Code

For code that varies by platform, use conditional compilation and separate test classes:

```csharp
// Shared test -- runs on all platforms
[Fact]
public async Task Settings_ChangeTheme_UpdatesUI()
{
    await _page.ClickAsync("[data-testid='theme-toggle']");

    var body = _page.Locator("[data-testid='app-root']");
    await Expect(body).ToHaveAttributeAsync("data-theme", "dark");
}

// Platform-specific test
[Fact]
[Trait("Platform", "WASM")]
public async Task FileUpload_BrowserDialog_AcceptsFiles()
{
    // WASM uses browser file picker -- test with Playwright file chooser
    var fileChooserTask = _page.WaitForFileChooserAsync();
    await _page.ClickAsync("[data-testid='upload-btn']");
    var fileChooser = await fileChooserTask;
    await fileChooser.SetFilesAsync("testdata/sample.pdf");

    var fileName = _page.Locator("[data-testid='file-name']");
    await Expect(fileName).ToHaveTextAsync("sample.pdf");
}
```


## Runtime Head Validation

Validate that the same UI logic works correctly across different Uno runtime heads using shared test logic with platform-specific drivers.

### Shared Test Logic Pattern

```csharp
/// <summary>
/// Abstract base that defines UI tests once. Concrete subclasses provide
/// the driver for each platform (Playwright for WASM, Appium for mobile).
/// </summary>
public abstract class LoginTestsBase
{
    protected abstract Task FillFieldAsync(string automationId, string value);
    protected abstract Task ClickAsync(string automationId);
    protected abstract Task<string> GetTextAsync(string automationId);
    protected abstract Task WaitForElementAsync(string automationId, int timeoutMs = 5000);

    [Fact]
    public async Task Login_ValidCredentials_ShowsDashboard()
    {
        await FillFieldAsync("username-input", "alice");
        await FillFieldAsync("password-input", "P@ssw0rd!");
        await ClickAsync("login-button");

        await WaitForElementAsync("dashboard-title");
        var title = await GetTextAsync("dashboard-title");
        Assert.Equal("Dashboard", title);
    }

    [Fact]
    public async Task Login_EmptyPassword_ShowsValidationError()
    {
        await FillFieldAsync("username-input", "alice");
        await ClickAsync("login-button");

        await WaitForElementAsync("error-message");
        var error = await GetTextAsync("error-message");
        Assert.Contains("required", error, StringComparison.OrdinalIgnoreCase);
    }
}

// WASM implementation
public class LoginTestsWasm : LoginTestsBase, IClassFixture<UnoWasmFixture>
{
    private readonly IPage _page;
    public LoginTestsWasm(UnoWasmFixture fixture) => _page = fixture.Page;

    protected override async Task FillFieldAsync(string automationId, string value) =>
        await _page.FillAsync($"[data-testid='{automationId}']", value);

    protected override async Task ClickAsync(string automationId) =>
        await _page.ClickAsync($"[data-testid='{automationId}']");

    protected override async Task<string> GetTextAsync(string automationId) =>
        await _page.Locator($"[data-testid='{automationId}']").TextContentAsync() ?? "";

    protected override async Task WaitForElementAsync(string automationId, int timeoutMs = 5000) =>
        await _page.WaitForSelectorAsync(
            $"[data-testid='{automationId}']",
            new() { Timeout = timeoutMs });
}
```


## Key Principles

- **Test shared logic with unit tests first.** Uno's MVVM pattern means most business logic is testable without any UI framework.
- **Use Playwright + WASM as the primary UI testing path.** It is faster than mobile emulators and provides real rendering fidelity in a browser.
- **Use `AutomationProperties.AutomationId` on all testable controls.** It is the only selector strategy that works identically across all Uno heads.
- **Separate shared tests from platform-specific tests.** Use abstract base classes for shared test logic, concrete subclasses per platform.
- **Add platform-specific tests only for platform-divergent behavior.** File pickers, hardware buttons, gestures, and notifications differ across platforms; test these separately.


## Agent Gotchas

1. **Do not assume Uno WASM apps load instantly.** The Uno runtime must initialize (mono WASM bootstrap), which takes several seconds. Always wait for the app root element before interacting.
2. **Do not use CSS selectors for Uno WASM elements.** Uno generates its own DOM structure; CSS classes are internal and unstable. Use `data-testid` (from `AutomationProperties.AutomationId`) exclusively.
3. **Do not forget to build the WASM head before running Playwright tests.** `dotnet run` builds on demand, but `dotnet publish` is needed for production-like testing. Stale builds cause confusing test failures.
4. **Do not test mobile-specific features in the WASM head.** File system access, push notifications, biometrics, and NFC are not available in the browser. Skip or mock these in WASM tests.
5. **Do not run all platform tests in a single CI job.** Each platform requires its own SDK (Android SDK, Xcode, WinAppDriver). Use separate CI jobs per platform with appropriate runners.


## References

- [Uno Platform Testing Documentation](https://platform.uno/docs/articles/features/working-with-accessibility.html)
- [Playwright for .NET](https://playwright.dev/dotnet/)
- [Uno Platform WASM Head](https://platform.uno/docs/articles/getting-started/wizard/wasm.html)
- [AutomationProperties in UWP/WinUI](https://learn.microsoft.com/en-us/windows/apps/design/accessibility/basic-accessibility-information)
- [Uno Platform GitHub](https://github.com/unoplatform/uno)
