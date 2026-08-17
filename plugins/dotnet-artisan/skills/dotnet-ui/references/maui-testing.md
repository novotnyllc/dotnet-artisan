# MAUI Testing

Testing .NET MAUI applications using Appium for UI automation and XHarness for cross-platform test execution. Covers device and emulator testing, platform-specific behavior validation, element location strategies for MAUI controls, and test infrastructure for mobile/desktop apps.

**Version assumptions:** .NET 8.0+ baseline, Appium 2.x with UIAutomator2 (Android) and XCUITest (iOS) drivers, XHarness 1.x. Examples use the latest Appium .NET client (5.x+).

## Appium Setup for MAUI

### Packages

```xml
<PackageReference Include="Appium.WebDriver" Version="5.*" />
<PackageReference Include="xunit.v3" Version="3.2.2" />
<PackageReference Include="xunit.runner.visualstudio" Version="3.1.5" />
```

### Driver Initialization

```csharp
public class AppiumFixture : IAsyncLifetime
{
    public AppiumDriver Driver { get; private set; } = null!;

    public ValueTask InitializeAsync()
    {
        var options = new AppiumOptions();

        if (OperatingSystem.IsAndroid() || TestConfig.TargetPlatform == "Android")
        {
            options.PlatformName = "Android";
            options.AutomationName = "UiAutomator2";
            options.App = TestConfig.AndroidApkPath;
            options.AddAdditionalAppiumOption("deviceName", "Pixel_7_API_34");
            options.AddAdditionalAppiumOption("avd", "Pixel_7_API_34");
        }
        else if (OperatingSystem.IsIOS() || TestConfig.TargetPlatform == "iOS")
        {
            options.PlatformName = "iOS";
            options.AutomationName = "XCUITest";
            options.App = TestConfig.iOSAppPath;
            options.AddAdditionalAppiumOption("deviceName", "iPhone 15");
            options.AddAdditionalAppiumOption("platformVersion", "17.2");
        }
        else if (OperatingSystem.IsWindows() || TestConfig.TargetPlatform == "Windows")
        {
            options.PlatformName = "Windows";
            options.AutomationName = "Windows";
            options.App = TestConfig.WindowsAppPath;
        }

        Driver = new AppiumDriver(
            new Uri("http://localhost:4723"), options);

        // Explicit waits only -- do not set ImplicitWait (it causes
        // additive timeout behavior when combined with WebDriverWait)
        Driver.Manage().Timeouts().ImplicitWait = TimeSpan.Zero;

        return ValueTask.CompletedTask;
    }

    public ValueTask DisposeAsync()
    {
        Driver?.Quit();
        return ValueTask.CompletedTask;
    }
}
```

### Test Configuration

```csharp
public static class TestConfig
{
    // Set via environment variables or test runsettings
    public static string TargetPlatform =>
        Environment.GetEnvironmentVariable("TEST_PLATFORM") ?? "Android";

    public static string AndroidApkPath =>
        Environment.GetEnvironmentVariable("ANDROID_APK_PATH")
        ?? Path.Combine(SolutionDir, "bin", "Release", "net8.0-android", "com.myapp-Signed.apk");

    public static string iOSAppPath =>
        Environment.GetEnvironmentVariable("IOS_APP_PATH")
        ?? Path.Combine(SolutionDir, "bin", "Release", "net8.0-ios", "MyApp.app");

    public static string WindowsAppPath =>
        Environment.GetEnvironmentVariable("WINDOWS_APP_PATH")
        ?? "com.mycompany.myapp_1.0.0.0_x64__9a0dh7ch11qe4!App";

    private static string SolutionDir =>
        Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", ".."));
}
```


## Element Location with AutomationId

MAUI's `AutomationId` property maps to the platform-native accessibility identifier. This is the most reliable selector for cross-platform tests.

### Setting AutomationId in XAML

```xml
<ContentPage xmlns="http://schemas.microsoft.com/dotnet/2021/maui"
             xmlns:x="http://schemas.microsoft.com/winfx/2009/xaml">

    <VerticalStackLayout>
        <Entry AutomationId="username-input"
               Placeholder="Username" />

        <Entry AutomationId="password-input"
               Placeholder="Password"
               IsPassword="True" />

        <Button AutomationId="login-button"
                Text="Log In"
                Clicked="OnLoginClicked" />

        <Label AutomationId="error-message"
               TextColor="Red" />
    </VerticalStackLayout>
</ContentPage>
```

### Finding Elements in Tests

```csharp
public class LoginTests : IClassFixture<AppiumFixture>
{
    private readonly AppiumDriver _driver;

    public LoginTests(AppiumFixture fixture)
    {
        _driver = fixture.Driver;
    }

    [Fact]
    public void Login_ValidCredentials_NavigatesToHome()
    {
        // Find by AutomationId (maps to accessibility ID on each platform)
        var usernameField = _driver.FindElement(MobileBy.AccessibilityId("username-input"));
        var passwordField = _driver.FindElement(MobileBy.AccessibilityId("password-input"));
        var loginButton = _driver.FindElement(MobileBy.AccessibilityId("login-button"));

        usernameField.Clear();
        usernameField.SendKeys("testuser");
        passwordField.Clear();
        passwordField.SendKeys("P@ssw0rd!");
        loginButton.Click();

        // Wait for navigation
        var wait = new WebDriverWait(_driver, TimeSpan.FromSeconds(10));
        var homeTitle = wait.Until(d =>
            d.FindElement(MobileBy.AccessibilityId("home-title")));

        Assert.Equal("Welcome", homeTitle.Text);
    }

    [Fact]
    public void Login_InvalidCredentials_ShowsError()
    {
        var usernameField = _driver.FindElement(MobileBy.AccessibilityId("username-input"));
        var passwordField = _driver.FindElement(MobileBy.AccessibilityId("password-input"));
        var loginButton = _driver.FindElement(MobileBy.AccessibilityId("login-button"));

        usernameField.Clear();
        usernameField.SendKeys("wrong");
        passwordField.Clear();
        passwordField.SendKeys("wrong");
        loginButton.Click();

        var wait = new WebDriverWait(_driver, TimeSpan.FromSeconds(5));
        var errorLabel = wait.Until(d =>
            d.FindElement(MobileBy.AccessibilityId("error-message")));

        Assert.Contains("Invalid", errorLabel.Text);
    }
}
```


## Page Object Model for MAUI

Apply the page object model pattern (see [skill:dotnet-testing]) with Appium's driver:

```csharp
public class LoginPage
{
    private readonly AppiumDriver _driver;
    private readonly WebDriverWait _wait;

    public LoginPage(AppiumDriver driver)
    {
        _driver = driver;
        _wait = new WebDriverWait(driver, TimeSpan.FromSeconds(10));
        WaitForPageLoaded();
    }

    private AppiumElement UsernameField =>
        _driver.FindElement(MobileBy.AccessibilityId("username-input"));
    private AppiumElement PasswordField =>
        _driver.FindElement(MobileBy.AccessibilityId("password-input"));
    private AppiumElement LoginButton =>
        _driver.FindElement(MobileBy.AccessibilityId("login-button"));
    private AppiumElement ErrorMessage =>
        _driver.FindElement(MobileBy.AccessibilityId("error-message"));

    public HomePage Login(string username, string password)
    {
        UsernameField.Clear();
        UsernameField.SendKeys(username);
        PasswordField.Clear();
        PasswordField.SendKeys(password);
        LoginButton.Click();

        return new HomePage(_driver);
    }

    public string GetErrorText()
    {
        _wait.Until(d =>
        {
            var el = d.FindElement(MobileBy.AccessibilityId("error-message"));
            return !string.IsNullOrEmpty(el.Text);
        });
        return ErrorMessage.Text;
    }

    private void WaitForPageLoaded()
    {
        _wait.Until(d => d.FindElement(MobileBy.AccessibilityId("login-button")));
    }
}

// Usage
[Fact]
public void Login_ValidUser_ReachesHomePage()
{
    var loginPage = new LoginPage(_driver);
    var homePage = loginPage.Login("alice", "P@ssw0rd!");

    Assert.True(homePage.IsLoaded);
}
```


## Platform-Specific Behavior Testing

### Conditional Tests by Platform

```csharp
public class PlatformTests : IClassFixture<AppiumFixture>
{
    private readonly AppiumDriver _driver;

    public PlatformTests(AppiumFixture fixture)
    {
        _driver = fixture.Driver;
    }

    [Fact]
    [Trait("Platform", "Android")]
    public void BackButton_Android_NavigatesBack()
    {
        // xUnit v3 native skip support (no SkippableFact package needed)
        Assert.SkipWhen(TestConfig.TargetPlatform != "Android",
            "Android-only: hardware back button");

        // Navigate to details page
        _driver.FindElement(MobileBy.AccessibilityId("item-1")).Click();

        // Press Android back button
        _driver.Navigate().Back();

        // Verify we returned to the list
        var wait = new WebDriverWait(_driver, TimeSpan.FromSeconds(5));
        wait.Until(d => d.FindElement(MobileBy.AccessibilityId("item-list")));
    }

    [Fact]
    [Trait("Platform", "iOS")]
    public void SwipeToDelete_iOS_RemovesItem()
    {
        // xUnit v3 native skip support
        Assert.SkipWhen(TestConfig.TargetPlatform != "iOS",
            "iOS-only: swipe gesture");

        var item = _driver.FindElement(MobileBy.AccessibilityId("item-1"));

        // Swipe left to reveal delete action
        var swipe = new PointerInputDevice(PointerKind.Touch, "finger");
        var sequence = new ActionSequence(swipe);
        var itemLocation = item.Location;
        var itemSize = item.Size;

        sequence.AddAction(swipe.CreatePointerMove(
            item, itemSize.Width - 10, itemSize.Height / 2,
            TimeSpan.FromMilliseconds(0)));
        sequence.AddAction(swipe.CreatePointerDown(MouseButton.Left));
        sequence.AddAction(swipe.CreatePointerMove(
            item, 10, itemSize.Height / 2,
            TimeSpan.FromMilliseconds(300)));
        sequence.AddAction(swipe.CreatePointerUp(MouseButton.Left));

        _driver.PerformActions([sequence]);

        // Tap the delete button
        var deleteBtn = _driver.FindElement(MobileBy.AccessibilityId("delete-action"));
        deleteBtn.Click();

        // Verify item removed
        var wait = new WebDriverWait(_driver, TimeSpan.FromSeconds(5));
        wait.Until(d =>
        {
            var items = d.FindElements(MobileBy.AccessibilityId("item-1"));
            return items.Count == 0;
        });
    }
}
```

### Screen Size and Orientation

```csharp
[Fact]
public void Dashboard_LandscapeMode_ShowsSidePanel()
{
    // Rotate to landscape
    _driver.Orientation = ScreenOrientation.Landscape;

    try
    {
        var wait = new WebDriverWait(_driver, TimeSpan.FromSeconds(5));
        var sidePanel = wait.Until(d =>
            d.FindElement(MobileBy.AccessibilityId("side-panel")));

        Assert.True(sidePanel.Displayed);
    }
    finally
    {
        // Restore portrait
        _driver.Orientation = ScreenOrientation.Portrait;
    }
}
```


## XHarness Test Execution

XHarness is a command-line tool for running tests on devices and emulators across platforms. It handles app installation, test execution, and result collection.

### Running Tests with XHarness

```bash
# Install XHarness
dotnet tool install --global Microsoft.DotNet.XHarness.CLI

# Run on Android emulator
xharness android test \
    --app bin/Release/net8.0-android/com.myapp-Signed.apk \
    --package-name com.myapp \
    --instrumentation devicerunner.AndroidInstrumentation \
    --output-directory test-results/android

# Run on iOS simulator
xharness apple test \
    --app bin/Release/net8.0-ios/MyApp.app \
    --target ios-simulator-64 \
    --output-directory test-results/ios

# Run with specific device
xharness android test \
    --app app.apk \
    --package-name com.myapp \
    --device-id emulator-5554 \
    --output-directory test-results
```

### XHarness with Device Runner

For xUnit tests running directly on device, add the device runner NuGet package:

```xml
<PackageReference Include="Microsoft.DotNet.XHarness.TestRunners.Xunit" Version="1.*" />
```

```csharp
// In the MAUI test app's MauiProgram.cs
public static MauiApp CreateMauiApp()
{
    var builder = MauiApp.CreateBuilder();
    builder.UseVisualRunner(); // XHarness visual test runner
    return builder.Build();
}
```


## Key Principles

- **Use `AutomationId` for all testable elements.** It is the cross-platform equivalent of `data-testid` and maps to the native accessibility identifier on every platform.
- **Run tests against real emulators/simulators, not just unit tests.** MAUI rendering, navigation, and platform services behave differently than in-memory tests.
- **Use explicit waits, never implicit waits or delays.** `WebDriverWait` with a condition is reliable; `Thread.Sleep` and implicit waits hide timing issues.
- **Tag platform-specific tests with `[Trait]` and `Assert.SkipWhen`.** xUnit v3's native skip support allows running the correct tests per platform in CI without failures from unsupported features.
- **Apply the page object model for maintainability.** MAUI apps have complex navigation flows; page objects keep tests readable as the app grows.


## Agent Gotchas

1. **Do not use `FindElement` without a wait strategy.** Elements may not be available immediately after navigation. Always use `WebDriverWait` for elements that appear after async operations or page transitions.
2. **Do not hardcode emulator/simulator names.** Use environment variables or test configuration so CI can specify the available device. Different CI environments have different emulators installed.
3. **Do not forget to set `AutomationId` on MAUI controls.** Without it, Appium falls back to platform-specific selectors (XPath, class name) that differ across Android, iOS, and Windows -- breaking cross-platform tests.
4. **Do not run iOS tests on non-macOS machines.** iOS simulators require Xcode, which is macOS-only. Use platform-conditional test skipping or separate CI pipelines per platform.
5. **Do not leave the Appium server unmanaged.** Start Appium as a fixture or CI service, not manually. Forgotten Appium processes cause port conflicts and test hangs.


## References

- [Appium Documentation](https://appium.io/docs/en/latest/)
- [Appium .NET Client](https://github.com/appium/dotnet-client)
- [.NET MAUI Testing](https://learn.microsoft.com/en-us/dotnet/maui/fundamentals/uitest)
- [XHarness](https://github.com/dotnet/xharness)
- [UIAutomator2 Driver](https://github.com/appium/appium-uiautomator2-driver)
- [XCUITest Driver](https://github.com/appium/appium-xcuitest-driver)
