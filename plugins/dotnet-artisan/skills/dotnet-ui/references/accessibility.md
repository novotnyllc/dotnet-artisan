# Accessibility

Cross-platform accessibility patterns for .NET UI frameworks: semantic markup, keyboard navigation, focus management, color contrast, and screen reader integration. In-depth coverage for Blazor (HTML ARIA), MAUI (SemanticProperties), and WinUI (AutomationProperties / UI Automation). Brief guidance with cross-references for WPF, Uno Platform, and TUI frameworks.

## Cross-Platform Principles

These principles apply across all .NET UI frameworks. Framework-specific implementations follow in subsequent sections.

### Semantic Markup

Provide meaningful names and descriptions for all interactive and informational elements. Screen readers rely on semantic metadata -- not visual appearance -- to convey UI structure.

- Every interactive control must have an accessible name (text label, ARIA label, or automation property)
- Images and icons must have text alternatives describing their purpose
- Decorative elements should be hidden from the accessibility tree
- Group related controls logically so screen readers announce them in context

### Keyboard Navigation

All functionality must be operable via keyboard alone. Users who cannot use a mouse, pointer, or touch depend entirely on keyboard interaction.

- Maintain a logical tab order that follows the visual reading flow
- Provide visible focus indicators on all interactive elements
- Support standard keyboard patterns: Tab/Shift+Tab for navigation, Enter/Space for activation, Escape to dismiss, arrow keys within composite controls
- Avoid keyboard traps -- users must be able to navigate away from every control

### Focus Management

Programmatic focus management ensures screen readers announce context changes correctly.

- Move focus to newly revealed content (dialogs, expanded panels, inline notifications)
- Return focus to the triggering element when dismissing overlays
- Avoid stealing focus unexpectedly during background updates
- Set initial focus on the primary action when a page or dialog loads

### Color Contrast

Ensure text and interactive elements meet WCAG contrast ratios.

| Element Type | Minimum Ratio (WCAG AA) | Enhanced Ratio (WCAG AAA) |
|---|---|---|
| Normal text (< 18pt) | 4.5:1 | 7:1 |
| Large text (>= 18pt or 14pt bold) | 3:1 | 4.5:1 |
| UI components and graphical objects | 3:1 | 3:1 |

- Do not rely on color alone to convey information (use icons, patterns, or text labels as supplements)
- Support high-contrast themes and system color overrides
- Test with color blindness simulation tools


## Blazor Accessibility (In-Depth)

Blazor renders HTML, so standard web accessibility patterns apply. Use native HTML semantics and ARIA attributes to build accessible Blazor apps.

### Semantic HTML and ARIA

```razor
@* Use semantic HTML elements for structure *@
<nav aria-label="Main navigation">
    <ul>
        <li><a href="/products">Products</a></li>
        <li><a href="/about">About</a></li>
    </ul>
</nav>

<main>
    <h1>Product Catalog</h1>

    @* Image with alt text *@
    <img src="hero.png" alt="Product showcase displaying three featured items" />

    @* Decorative image hidden from accessibility tree *@
    <img src="divider.svg" alt="" role="presentation" />

    @* Button with accessible name from content *@
    <button @onclick="AddToCart">Add to Cart</button>

    @* Icon button requires aria-label *@
    <button @onclick="ToggleFavorite" aria-label="Add to favorites">
        <span class="icon-heart" aria-hidden="true"></span>
    </button>
</main>
```

### Keyboard Event Handling

```razor
<div role="listbox"
     tabindex="0"
     aria-label="Product list"
     aria-activedescendant="@_activeId"
     @onkeydown="HandleKeyDown"
     @onkeydown:preventDefault>
    @foreach (var product in Products)
    {
        <div id="@($"product-{product.Id}")"
             role="option"
             aria-selected="@(product.Id == SelectedId)"
             @onclick="() => Select(product)">
            @product.Name
        </div>
    }
</div>

@code {
    private string _activeId = "";

    private void HandleKeyDown(KeyboardEventArgs e)
    {
        switch (e.Key)
        {
            case "ArrowDown":
                MoveSelection(1);
                break;
            case "ArrowUp":
                MoveSelection(-1);
                break;
            case "Enter":
            case " ":
                ConfirmSelection();
                break;
        }
    }
}
```

### Live Regions

Announce dynamic content changes to screen readers without moving focus:

```razor
@* Polite: announced after current speech finishes *@
<div aria-live="polite" aria-atomic="true">
    @if (_statusMessage is not null)
    {
        <p>@_statusMessage</p>
    }
</div>

@* Assertive: interrupts current speech (use sparingly) *@
<div aria-live="assertive" role="alert">
    @if (_errorMessage is not null)
    {
        <p>@_errorMessage</p>
    }
</div>
```

### Form Accessibility

```razor
<EditForm Model="@_model" OnValidSubmit="HandleSubmit">
    <DataAnnotationsValidator />

    <div>
        <label for="product-name">Product name</label>
        <InputText id="product-name"
                   @bind-Value="_model.Name"
                   aria-describedby="name-error"
                   aria-invalid="@(_nameInvalid ? "true" : null)" />
        <ValidationMessage For="() => _model.Name" id="name-error" />
    </div>

    <div>
        <label for="quantity">Quantity</label>
        <InputNumber id="quantity"
                     @bind-Value="_model.Quantity"
                     aria-describedby="quantity-help"
                     min="1" max="100" />
        <span id="quantity-help">Enter a value between 1 and 100</span>
    </div>

    <button type="submit">Submit Order</button>
</EditForm>
```

For Blazor hosting models and render mode configuration, see `references/blazor-patterns.md`. For component lifecycle and EditForm patterns, see `references/blazor-components.md`.


## MAUI Accessibility (In-Depth)

MAUI provides the `SemanticProperties` attached properties as the recommended accessibility API. These map to native platform accessibility APIs (VoiceOver on iOS/macOS, TalkBack on Android, Narrator on Windows).

### SemanticProperties

```xml
<!-- Description: primary screen reader announcement -->
<Image Source="product.png"
       SemanticProperties.Description="Product photo showing a blue widget" />

<!-- Hint: additional context about an action -->
<Button Text="Add to Cart"
        SemanticProperties.Hint="Adds the current product to your shopping cart" />

<!-- HeadingLevel: enables heading-based navigation -->
<Label Text="Order Summary"
       SemanticProperties.HeadingLevel="Level1" />
<Label Text="Items"
       SemanticProperties.HeadingLevel="Level2" />
```

**Key APIs:**
- `SemanticProperties.Description` -- short text the screen reader announces (equivalent to `accessibilityLabel` on iOS, `contentDescription` on Android)
- `SemanticProperties.Hint` -- additional purpose context (equivalent to `accessibilityHint` on iOS)
- `SemanticProperties.HeadingLevel` -- marks headings (Level1 through Level9); Android and iOS only support a single heading level, Windows supports all 9

**Platform warning:** Do not set `SemanticProperties.Description` on a `Label` -- it overrides the `Text` property for screen readers, creating a mismatch between visual and spoken text. Do not set `SemanticProperties.Description` on `Entry` or `Editor` on Android -- use `Placeholder` or `SemanticProperties.Hint` instead, because Description conflicts with TalkBack actions.

### Legacy AutomationProperties

`AutomationProperties` are the older Xamarin.Forms API, superseded by `SemanticProperties` in MAUI. Use `SemanticProperties` for new code.

| Legacy API | Replacement |
|---|---|
| `AutomationProperties.Name` | `SemanticProperties.Description` |
| `AutomationProperties.HelpText` | `SemanticProperties.Hint` |
| `AutomationProperties.LabeledBy` | Bind `SemanticProperties.Description` to the label's `Text` |

`AutomationProperties.IsInAccessibleTree` and `AutomationProperties.ExcludedWithChildren` remain useful for controlling accessibility tree inclusion.

### Programmatic Focus and Announcements

```csharp
// Move screen reader focus to a specific element
myLabel.SetSemanticFocus();

// Announce text to the screen reader without moving focus
SemanticScreenReader.Default.Announce("Item added to cart successfully.");
```

### Accessible Custom Controls

When building custom controls, ensure accessibility metadata is set:

```csharp
public class RatingControl : ContentView
{
    private int _rating;

    public int Rating
    {
        get => _rating;
        set
        {
            _rating = value;
            SemanticProperties.SetDescription(this,
                $"Rating: {value} out of 5 stars");
            SemanticScreenReader.Default.Announce(
                $"Rating changed to {value} stars");
        }
    }
}
```

For MAUI project structure, MVVM patterns, and platform services, see `references/maui-development.md`.


## WinUI Accessibility (In-Depth)

WinUI 3 / Windows App SDK builds on the Microsoft UI Automation framework. Built-in controls include automation support by default. Custom controls need automation peers.

### AutomationProperties

```xml
<!-- Name: primary accessible name for screen readers -->
<Image Source="ms-appx:///Assets/product.png"
       AutomationProperties.Name="Product photo showing a blue widget" />

<!-- HelpText: supplementary description -->
<Button Content="Add to Cart"
        AutomationProperties.HelpText="Adds the current product to your shopping cart" />

<!-- LabeledBy: associates a label with a control -->
<TextBlock x:Name="QuantityLabel" Text="Quantity:" />
<NumberBox AutomationProperties.LabeledBy="{x:Bind QuantityLabel}"
           Value="{x:Bind ViewModel.Quantity, Mode=TwoWay}" />

<!-- Hide decorative elements from accessibility tree -->
<Image Source="ms-appx:///Assets/divider.png"
       AutomationProperties.AccessibilityView="Raw" />
```

### Custom Automation Peers

For custom controls, implement an `AutomationPeer` to expose the control to UI Automation clients:

```csharp
// Custom control
public sealed class StarRating : Control
{
    public int Value
    {
        get => (int)GetValue(ValueProperty);
        set => SetValue(ValueProperty, value);
    }

    public static readonly DependencyProperty ValueProperty =
        DependencyProperty.Register(nameof(Value), typeof(int),
            typeof(StarRating), new PropertyMetadata(0, OnValueChanged));

    private static void OnValueChanged(DependencyObject d,
        DependencyPropertyChangedEventArgs e)
    {
        if (FrameworkElementAutomationPeer
                .FromElement((StarRating)d) is StarRatingAutomationPeer peer)
        {
            peer.RaiseValueChanged((int)e.OldValue, (int)e.NewValue);
        }
    }

    protected override AutomationPeer OnCreateAutomationPeer()
        => new StarRatingAutomationPeer(this);
}

// Automation peer (using Microsoft.UI.Xaml.Automation.Provider)
public sealed class StarRatingAutomationPeer
    : FrameworkElementAutomationPeer, IRangeValueProvider
{
    private StarRating Owner => (StarRating)base.Owner;

    public StarRatingAutomationPeer(StarRating owner) : base(owner) { }

    protected override string GetClassNameCore() => nameof(StarRating);
    protected override string GetNameCore()
        => $"Rating: {Owner.Value} out of 5 stars";
    protected override AutomationControlType GetAutomationControlTypeCore()
        => AutomationControlType.Slider;

    // IRangeValueProvider
    public double Value => Owner.Value;
    public double Minimum => 0;
    public double Maximum => 5;
    public double SmallChange => 1;
    public double LargeChange => 1;
    public bool IsReadOnly => false;

    public void SetValue(double value)
        => Owner.Value = (int)Math.Clamp(value, Minimum, Maximum);

    public void RaiseValueChanged(int oldValue, int newValue)
    {
        RaisePropertyChangedEvent(
            RangeValuePatternIdentifiers.ValueProperty,
            (double)oldValue, (double)newValue);
    }
}
```

### Keyboard Accessibility in WinUI

WinUI XAML controls provide built-in keyboard support. Ensure custom controls follow the same patterns:

```xml
<!-- TabIndex controls navigation order -->
<TextBox Header="First name" TabIndex="1" />
<TextBox Header="Last name" TabIndex="2" />
<Button Content="Submit" TabIndex="3" />

<!-- AccessKey provides keyboard shortcuts (Alt + key) -->
<Button Content="Save" AccessKey="S" />
<Button Content="Delete" AccessKey="D" />
```

For WinUI project setup, XAML patterns, and Windows integration, see `references/winui.md`.


## WPF Accessibility (Brief)

WPF on .NET 8+ uses the same UI Automation framework as WinUI. The APIs are nearly identical with namespace differences.

- `AutomationProperties.Name`, `AutomationProperties.HelpText`, `AutomationProperties.LabeledBy` work the same as in WinUI
- Custom controls override `OnCreateAutomationPeer()` and return a `FrameworkElementAutomationPeer` subclass
- WPF Fluent theme (.NET 9+) includes high-contrast support automatically
- Use `AutomationProperties.LiveSetting` for live region announcements

```xml
<!-- WPF accessibility follows the same pattern as WinUI -->
<Image Source="product.png"
       AutomationProperties.Name="Product photo" />

<TextBlock x:Name="StatusLabel"
           AutomationProperties.LiveSetting="Polite"
           Text="{Binding StatusText}" />
```

For WPF development patterns on .NET 8+, see `references/wpf-modern.md`.


## Uno Platform Accessibility (Brief)

Uno Platform follows UWP/WinUI `AutomationProperties` patterns since its API surface is WinUI-compatible.

- `AutomationProperties.Name`, `AutomationProperties.HelpText`, `AutomationProperties.LabeledBy` work cross-platform
- Custom `AutomationPeer` implementations follow the WinUI pattern
- On WebAssembly, Uno maps `AutomationProperties` to HTML ARIA attributes automatically
- Platform-specific behavior may vary -- test on each target (Windows, iOS, Android, WASM)

For Uno Platform development patterns, see `references/uno-platform.md`. For per-target deployment and testing, see `references/uno-targets.md`.


## TUI Accessibility (Brief)

Terminal UI frameworks have inherent accessibility limitations. Screen reader support depends on the terminal emulator and operating system.

**Terminal.Gui (v2):**
- Screen readers can read terminal text content via the terminal emulator's accessibility support
- No programmatic accessibility API equivalent to ARIA or AutomationProperties
- Logical tab order follows the `TabIndex` property on views
- High contrast is managed by terminal color themes, not the app

**Spectre.Console:**
- Output-only library -- screen readers read terminal text buffer directly
- Use plain text fallbacks for complex visual elements (tables, trees) when accessibility is critical
- `AnsiConsole.Profile.Capabilities` can detect terminal features but not screen reader presence

**Honest constraint:** TUI apps cannot programmatically control screen reader behavior. Terminal emulators provide varying levels of accessibility support. For applications where accessibility is a hard requirement, consider a GUI framework (Blazor, MAUI, WinUI) instead.

For Terminal.Gui patterns, see [skill:dotnet-tooling]. For Spectre.Console patterns, see [skill:dotnet-tooling].


## Accessibility Testing Tools

### Per-Platform Testing

| Platform | Primary Tool | Secondary Tools |
|---|---|---|
| Windows | [Accessibility Insights for Windows](https://accessibilityinsights.io/) | Narrator (Win+Ctrl+Enter), Inspect.exe (Windows SDK) |
| Web (Blazor) | [axe-core](https://github.com/dequelabs/axe-core) / axe DevTools | Lighthouse (Chrome), WAVE, NVDA, VoiceOver (macOS) |
| Android | [Accessibility Scanner](https://support.google.com/accessibility/android/answer/6376570) | TalkBack, Android Studio Layout Inspector |
| iOS / macOS | Accessibility Inspector (Xcode) | VoiceOver (built-in), XCUITest accessibility assertions |

### Automated Testing Integration

```csharp
// Blazor: integrate axe-core with Playwright for automated accessibility testing
// Requires: Deque.AxeCore.Playwright NuGet package
// Install: dotnet add package Deque.AxeCore.Playwright
var axeResults = await new Deque.AxeCore.Playwright.AxeBuilder(page)
    .AnalyzeAsync();

// Check for violations
Assert.Empty(axeResults.Violations);

// WinUI/WPF: use Accessibility Insights for Windows CLI in CI pipelines
// Requires: AccessibilityInsights.CLI (available via Microsoft Store or direct download)
```

### Manual Testing Checklist

1. **Keyboard-only navigation** -- tab through entire app without mouse; verify all functionality is reachable
2. **Screen reader walkthrough** -- enable Narrator/VoiceOver/TalkBack and navigate the full workflow
3. **High contrast** -- enable system high-contrast theme and verify all content remains visible
4. **Zoom/scaling** -- increase text size to 200% and verify layout does not break or clip content
5. **Color contrast** -- verify all text and interactive elements meet WCAG AA ratios (4.5:1 for text, 3:1 for large text and UI components)


## WCAG Reference

This skill references the [Web Content Accessibility Guidelines (WCAG)](https://www.w3.org/WAI/standards-guidelines/wcag/) as the global accessibility standard. WCAG 2.1 is the current baseline; WCAG 2.2 adds additional criteria for mobile and cognitive accessibility.

**Four principles (POUR):**
1. **Perceivable** -- information must be presentable in ways all users can perceive
2. **Operable** -- UI components must be operable by all users
3. **Understandable** -- information and UI operation must be understandable
4. **Robust** -- content must be robust enough to work with assistive technologies

**Conformance levels:** A (minimum), AA (recommended target for most apps), AAA (enhanced). Most legal requirements and industry standards target WCAG 2.1 Level AA.

**Note:** This skill provides technical implementation guidance. It does not constitute legal advice regarding accessibility compliance requirements, which vary by jurisdiction and application type.


## Agent Gotchas

1. **Do not set `SemanticProperties.Description` on MAUI `Label` controls.** It overrides the `Text` property for screen readers, causing a mismatch between visual and spoken content. Labels are already accessible via their `Text` property.
2. **Do not set `SemanticProperties.Description` on MAUI `Entry`/`Editor` on Android.** Use `Placeholder` or `SemanticProperties.Hint` instead -- `Description` conflicts with TalkBack actions on these controls.
3. **Do not use `AutomationProperties.Name` or `AutomationProperties.HelpText` for new MAUI code.** Use `SemanticProperties` instead (the MAUI-native API). `AutomationProperties.IsInAccessibleTree` and `ExcludedWithChildren` remain valid for controlling accessibility tree inclusion.
4. **Do not omit `aria-label` on icon-only Blazor buttons.** Buttons without visible text content are invisible to screen readers unless `aria-label` or `aria-labelledby` is set.
5. **Do not use `aria-live="assertive"` for routine status updates.** Assertive interrupts the screen reader immediately. Use `aria-live="polite"` for non-critical updates; reserve assertive for errors and time-critical alerts.
6. **Do not assume TUI apps are accessible by default.** Terminal screen reader support varies dramatically by emulator and OS. Always provide alternative output formats for critical accessibility scenarios.
7. **Do not hardcode colors without verifying contrast ratios.** Use tools (Accessibility Insights, Lighthouse) to verify WCAG AA compliance. System high-contrast themes must also be tested.
8. **Do not forget `AccessKey` on frequently used WinUI/WPF buttons.** Access keys (Alt+key shortcuts) are essential for keyboard-dependent users and are trivial to add.


## Prerequisites

- .NET 8.0+ (baseline for all frameworks)
- Framework-specific SDKs: MAUI workload, Windows App SDK (WinUI), Blazor project template
- Testing tools: Accessibility Insights (Windows), axe-core (web), Xcode Accessibility Inspector (macOS/iOS)
- Screen readers for manual testing: Narrator (Windows), VoiceOver (macOS/iOS), TalkBack (Android), NVDA (Windows, free)


## References

- [WCAG 2.1 Guidelines](https://www.w3.org/WAI/WCAG21/quickref/)
- [WCAG 2.2 Guidelines](https://www.w3.org/TR/WCAG22/)
- [MAUI Accessibility (SemanticProperties)](https://learn.microsoft.com/en-us/dotnet/maui/fundamentals/accessibility)
- [WinUI Accessibility Overview](https://learn.microsoft.com/en-us/windows/apps/design/accessibility/accessibility-overview)
- [Blazor Accessibility](https://learn.microsoft.com/en-us/aspnet/core/blazor/components/accessibility)
- [UI Automation Overview](https://learn.microsoft.com/en-us/windows/desktop/WinAuto/uiauto-uiautomationoverview)
- [Accessibility Insights](https://accessibilityinsights.io/)
- [axe-core (Deque)](https://github.com/dequelabs/axe-core)
