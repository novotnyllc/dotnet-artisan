# UI Testing Core

Core UI testing patterns applicable across .NET UI frameworks (Blazor, MAUI, Uno Platform). Covers the page object model for maintainable test structure, test selector strategies for reliable element identification, async wait patterns for non-deterministic UI, and accessibility testing approaches.

**Version assumptions:** .NET 8.0+ baseline. Framework-specific details are delegated to dedicated skills.

## Page Object Model

The page object model (POM) encapsulates page structure and interactions behind a class, isolating tests from UI implementation details. When the UI changes, only the page object needs updating -- not every test that touches that page.

### Structure

```
PageObjects/
  LoginPage.cs           -- login form interactions
  DashboardPage.cs       -- dashboard navigation + widgets
  OrderListPage.cs       -- order list filtering + selection
  Components/
    NavigationMenu.cs     -- shared nav component
    ConfirmDialog.cs      -- reusable confirmation modal
```

### Example: Generic Page Object Base

```csharp
/// <summary>
/// Base class for page objects. Subclass per framework:
/// Playwright uses IPage, bUnit uses IRenderedComponent, Appium uses AppiumDriver.
/// </summary>
public abstract class PageObjectBase<TDriver>
{
    protected TDriver Driver { get; }

    protected PageObjectBase(TDriver driver)
    {
        Driver = driver;
    }

    /// <summary>
    /// Verifies the page/component is in the expected state after navigation.
    /// Call this in the constructor or after navigation to fail fast on wrong pages.
    /// </summary>
    protected abstract void VerifyLoaded();
}
```

### Example: Playwright Page Object

```csharp
public class LoginPage : PageObjectBase<IPage>
{
    public LoginPage(IPage page) : base(page)
    {
        VerifyLoaded();
    }

    protected override void VerifyLoaded()
    {
        // Fail fast if not on the login page
        Driver.WaitForSelectorAsync("[data-testid='login-form']")
            .GetAwaiter().GetResult();
    }

    public async Task<DashboardPage> LoginAsync(string email, string password)
    {
        await Driver.FillAsync("[data-testid='email-input']", email);
        await Driver.FillAsync("[data-testid='password-input']", password);
        await Driver.ClickAsync("[data-testid='login-button']");
        await Driver.WaitForURLAsync("**/dashboard");
        return new DashboardPage(Driver);
    }

    public async Task<string> GetErrorMessageAsync()
    {
        var error = Driver.Locator("[data-testid='login-error']");
        return await error.TextContentAsync() ?? "";
    }
}

// Usage in test
[Fact]
public async Task Login_ValidCredentials_RedirectsToDashboard()
{
    var loginPage = new LoginPage(Page);

    var dashboard = await loginPage.LoginAsync("user@example.com", "P@ssw0rd!");

    Assert.NotNull(dashboard);
}
```

### Page Object Principles

- **Return the next page object from navigation actions.** `LoginAsync` returns `DashboardPage`, guiding test authors through the application flow.
- **Never expose raw selectors from page objects.** Tests call `LoginAsync()`, not `ClickAsync("#submit")`.
- **Keep assertions in tests, not page objects.** Page objects provide data (e.g., `GetErrorMessageAsync()`); tests make assertions on that data.
- **Compose page objects from reusable components.** A `NavigationMenu` component object can be embedded in every page that has a nav bar.

---

## Test Selector Strategies

Selectors determine how tests find UI elements. Fragile selectors are the leading cause of flaky UI tests.

### Selector Priority (Most to Least Reliable)

| Priority | Selector Type | Example | Reliability |
|----------|--------------|---------|-------------|
| 1 | **`data-testid`** | `[data-testid='submit-btn']` | Highest -- survives CSS/layout changes |
| 2 | **Accessibility role + name** | `GetByRole(AriaRole.Button, new() { Name = "Submit" })` | High -- tied to visible behavior |
| 3 | **Label text** | `GetByLabel("Email address")` | High -- changes when copy changes |
| 4 | **Placeholder text** | `GetByPlaceholder("Enter email")` | Medium -- often localized |
| 5 | **CSS class** | `.btn-primary` | Low -- changes with styling |
| 6 | **XPath / DOM structure** | `//div[3]/button[1]` | Lowest -- breaks on any layout change |

### Adding Test IDs

Add `data-testid` attributes to elements that tests interact with. They are invisible to users and stable across refactors:

**Blazor:**
```razor
<button data-testid="submit-order" @onclick="SubmitOrder">Place Order</button>
<input data-testid="search-input" @bind="SearchTerm" />
```

**MAUI XAML:**
```xml
<Button AutomationId="submit-order" Text="Place Order" Clicked="OnSubmit" />
<Entry AutomationId="search-input" Text="{Binding SearchTerm}" />
```

**Uno Platform XAML:**
```xml
<Button AutomationProperties.AutomationId="submit-order" Content="Place Order" />
```

### Selector Anti-Patterns

```csharp
// BAD: Tied to CSS implementation
await page.ClickAsync(".MuiButton-root.MuiButton-containedPrimary");

// BAD: Tied to DOM structure
await page.ClickAsync("div > form > div:nth-child(3) > button");

// BAD: Tied to dynamic content
await page.ClickAsync($"text=Order #{orderId}");

// GOOD: Stable test identifier
await page.ClickAsync("[data-testid='submit-order']");

// GOOD: Accessibility-driven (Playwright)
await page.GetByRole(AriaRole.Button, new() { Name = "Place Order" }).ClickAsync();
```

---

## Async Wait Strategies

UI tests deal with asynchronous rendering, network requests, and animations. Hardcoded delays cause flaky tests and slow suites.

### Wait Strategy Decision Tree

```
Is the element already in the DOM?
|
+-- YES --> Is it visible and actionable?
|           |
|           +-- YES --> Interact immediately
|           +-- NO  --> Wait for visibility/enabled state
|
+-- NO  --> Wait for element to appear in DOM
            |
            Is it loaded via network request?
            |
            +-- YES --> Wait for network idle or specific API response
            +-- NO  --> Wait for render cycle to complete
```

### Framework-Specific Wait Patterns

**Playwright (browser-based):**
```csharp
// Auto-waiting: Playwright waits for actionability by default
await page.ClickAsync("[data-testid='submit']"); // waits until visible + enabled

// Explicit wait for network-loaded content
await page.WaitForResponseAsync(
    response => response.Url.Contains("/api/orders") && response.Status == 200);

// Wait for element state
await page.Locator("[data-testid='results']")
    .WaitForAsync(new() { State = WaitForSelectorState.Visible });

// Wait for specific text content
await Expect(page.Locator("[data-testid='status']")).ToHaveTextAsync("Completed");
```

**bUnit (Blazor component testing):**
```csharp
// Wait for async state changes to render
var cut = RenderComponent<OrderList>();

// Wait for component to finish async operations
cut.WaitForState(() => cut.Instance.Orders.Count > 0,
    timeout: TimeSpan.FromSeconds(5));

// Wait for specific markup
cut.WaitForAssertion(() =>
    Assert.NotEmpty(cut.FindAll("[data-testid='order-row']")),
    timeout: TimeSpan.FromSeconds(5));
```

### Wait Anti-Patterns

```csharp
// BAD: Hardcoded delay -- slow and still flaky
await Task.Delay(3000);
await page.ClickAsync("[data-testid='results']");

// BAD: Polling with Thread.Sleep
while (!element.IsVisible)
{
    Thread.Sleep(100); // blocks thread, no timeout safety
}

// GOOD: Framework-native wait
await page.Locator("[data-testid='results']")
    .WaitForAsync(new() { State = WaitForSelectorState.Visible, Timeout = 5000 });

// GOOD: Assertion with retry (Playwright)
await Expect(page.Locator("[data-testid='count']")).ToHaveTextAsync("5");
```

---

## Accessibility Testing

Accessibility testing verifies that UI components are usable by people with disabilities and compatible with assistive technologies. Automated checks catch common issues; manual review is still needed for subjective criteria.

### Automated Accessibility Checks with Playwright

```csharp
// NuGet: Deque.AxeCore.Playwright
[Fact]
public async Task HomePage_PassesAccessibilityAudit()
{
    await Page.GotoAsync("/");

    var results = await Page.RunAxe();

    Assert.Empty(results.Violations);
}

[Fact]
public async Task OrderForm_NoAccessibilityViolations()
{
    await Page.GotoAsync("/orders/new");

    // Scope to specific component
    var form = Page.Locator("[data-testid='order-form']");
    var results = await Page.RunAxe(new AxeRunOptions
    {
        // Focus on WCAG 2.1 AA rules
        RunOnly = new RunOnlyOptions
        {
            Type = "tag",
            Values = ["wcag2a", "wcag2aa", "wcag21aa"]
        }
    });

    // Report violations with details for debugging
    foreach (var violation in results.Violations)
    {
        // Log: violation.Id, violation.Description, violation.Nodes
    }
    Assert.Empty(results.Violations);
}
```

### Accessibility Checklist for UI Tests

| Check | How to Test | Tool |
|-------|------------|------|
| **Color contrast** | Automated axe-core rule | Deque.AxeCore.Playwright |
| **Keyboard navigation** | Tab through all interactive elements | Playwright `page.Keyboard` |
| **ARIA labels** | Verify `aria-label` / `aria-labelledby` present | Playwright locators + assertions |
| **Focus management** | Verify focus moves to dialogs/modals | Playwright `page.Locator(':focus')` |
| **Screen reader text** | Verify `aria-live` regions update | Manual + assertion on ARIA attributes |

### Keyboard Navigation Test Example

```csharp
[Fact]
public async Task OrderForm_TabOrder_FollowsLogicalSequence()
{
    await Page.GotoAsync("/orders/new");

    // Tab through form fields and verify focus order
    await Page.Keyboard.PressAsync("Tab");
    await Expect(Page.Locator("[data-testid='customer-name']")).ToBeFocusedAsync();

    await Page.Keyboard.PressAsync("Tab");
    await Expect(Page.Locator("[data-testid='customer-email']")).ToBeFocusedAsync();

    await Page.Keyboard.PressAsync("Tab");
    await Expect(Page.Locator("[data-testid='order-items']")).ToBeFocusedAsync();

    // Verify Enter submits the form
    await Page.Keyboard.PressAsync("Tab"); // focus submit button
    await Expect(Page.Locator("[data-testid='submit-order']")).ToBeFocusedAsync();
}
```

---

## Key Principles

- **Use the page object model for any UI test suite with more than a handful of tests.** The upfront cost pays for itself quickly in reduced maintenance.
- **Prefer `data-testid` or accessibility-based selectors over CSS or DOM-structure selectors.** Stable selectors are the single most effective defense against flaky tests.
- **Never use `Thread.Sleep` or `Task.Delay` as a wait strategy.** Use framework-native waits that poll for conditions with timeouts.
- **Run accessibility checks as part of the standard test suite,** not as a separate audit. Catching violations early prevents accessibility debt.
- **Keep page objects framework-agnostic where possible.** The patterns (POM, selector strategy, wait patterns) are universal; only the driver API changes between Playwright, bUnit, and Appium.

---

## Agent Gotchas

1. **Do not add `data-testid` attributes to production code without team agreement.** Some teams strip them in production builds; others keep them. Check the project's conventions first.
2. **Do not use `WaitForTimeout` (hardcoded delay) in Playwright tests.** It masks timing issues and makes tests slow. Use `WaitForSelectorAsync`, `Expect(...).ToBeVisibleAsync()`, or `WaitForResponseAsync` instead.
3. **Do not assert on element count without waiting for the list to load.** `FindAll("[data-testid='row']").Count` returns zero if the component has not finished rendering. Use `WaitForState` or `WaitForAssertion` first.
4. **Do not skip accessibility testing because "it's not a requirement."** WCAG compliance is increasingly a legal requirement. Automated checks catch the low-hanging fruit at near-zero cost.
5. **Do not create deeply nested page objects.** If a page object has page objects inside page objects, flatten the hierarchy. One level of component composition (page -> components) is sufficient.

---

## References

- [Page Object Model (Martin Fowler)](https://martinfowler.com/bliki/PageObject.html)
- [Playwright Locators Best Practices](https://playwright.dev/dotnet/docs/locators)
- [axe-core Accessibility Rules](https://dequeuniversity.com/rules/axe/)
- [WCAG 2.1 Guidelines](https://www.w3.org/WAI/WCAG21/quickref/)
- [Testing Library Guiding Principles](https://testing-library.com/docs/guiding-principles)
