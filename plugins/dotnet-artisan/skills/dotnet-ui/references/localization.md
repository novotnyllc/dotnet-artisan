# Localization

Comprehensive .NET internationalization and localization: .resx resource files and satellite assemblies, modern alternatives (JSON resources, source generators for AOT), IStringLocalizer patterns, date/number/currency formatting with CultureInfo, RTL layout support, pluralization engines, and per-framework localization integration for Blazor, MAUI, Uno Platform, and WPF.

**Version assumptions:** .NET 8.0+ baseline. IStringLocalizer stable since .NET Core 1.0; localization APIs stable since .NET 5. .NET 9+ features explicitly marked.

## .resx Resource Files

### Overview

Resource files (`.resx`) are the standard .NET localization format. They compile into satellite assemblies resolved by `ResourceManager` with automatic culture fallback.

### Culture Fallback Chain

Resources resolve in order of specificity, falling back until a match is found:

```
sr-Cyrl-RS.resx -> sr-Cyrl.resx -> sr.resx -> Resources.resx (default/neutral)
```

The default `.resx` file (no culture suffix) is the single source of truth. Translation files must not contain keys absent from the default file.

### Project Setup

```xml
<!-- MyApp.csproj -->
<PropertyGroup>
  <NeutralLanguage>en-US</NeutralLanguage>
</PropertyGroup>

<ItemGroup>
  <!-- Default resources -->
  <EmbeddedResource Include="Resources\Messages.resx" />
  <!-- Culture-specific resources -->
  <EmbeddedResource Include="Resources\Messages.fr-FR.resx" />
  <EmbeddedResource Include="Resources\Messages.de-DE.resx" />
</ItemGroup>
```

### Resource File Structure

```xml
<!-- Resources/Messages.resx (default/neutral) -->
<?xml version="1.0" encoding="utf-8"?>
<root>
  <data name="Welcome" xml:space="preserve">
    <value>Welcome to the application</value>
    <comment>Shown on the home page</comment>
  </data>
  <data name="ItemCount" xml:space="preserve">
    <value>You have {0} item(s)</value>
    <comment>{0} = number of items</comment>
  </data>
</root>
```

### Accessing Resources

```csharp
// Via generated strongly-typed class (ResXFileCodeGenerator custom tool)
string welcome = Messages.Welcome;

// Via ResourceManager directly
var rm = new ResourceManager("MyApp.Resources.Messages",
    typeof(Messages).Assembly);
string welcome = rm.GetString("Welcome", CultureInfo.CurrentUICulture);
```


## Modern Alternatives

### JSON-Based Resources

Lightweight alternative for projects already using JSON for configuration. Libraries provide `IStringLocalizer` implementations backed by JSON files.

```json
// Resources/en-US.json
{
  "Welcome": "Welcome to the application",
  "ItemCount": "You have {0} item(s)"
}
```

**Libraries:**
- `Senlin.Mo.Localization` -- JSON-backed `IStringLocalizer`
- `Embedded.Json.Localization` -- embedded JSON resources

JSON resources are popular in ASP.NET Core but lack the built-in tooling support (Visual Studio designer, satellite assembly compilation) of `.resx`.

### Source Generators for AOT Compatibility

Traditional `.resx` with `ResourceManager` uses reflection at runtime, which is problematic for Native AOT and trimming. Source generators eliminate runtime reflection by generating strongly-typed accessor classes at compile time.

**Recommended source generators:**

| Generator | Description | AOT-Safe |
|-----------|-------------|----------|
| ResXGenerator (ycanardeau) | Strongly-typed classes with `IStringLocalizer` support and DI registration | Yes |
| VocaDb.ResXFileCodeGenerator | Original strongly-typed `.resx` source generator | Yes |
| Built-in `ResXFileCodeGenerator` | Visual Studio custom tool (not a Roslyn source generator) | No -- generates static properties but still uses `ResourceManager` |

```xml
<!-- Using ResXGenerator -->
<ItemGroup>
  <PackageReference Include="ResXGenerator" Version="1.*"
                    PrivateAssets="all" />
</ItemGroup>
```

```csharp
// Generated at compile time -- no runtime reflection
string welcome = Messages.Welcome;

// With DI registration (ResXGenerator)
services.AddResXLocalization();
```

**Recommendation:** Use `.resx` files as the resource format (broadest tooling support) with a source generator for AOT/trimming scenarios. Use JSON resources only for lightweight or config-heavy projects.


## IStringLocalizer Patterns

### Registration

```csharp
var builder = WebApplication.CreateBuilder(args);

// Register localization services
builder.Services.AddLocalization(options =>
    options.ResourcesPath = "Resources");

var app = builder.Build();

// Configure request localization middleware
var supportedCultures = new[] { "en-US", "fr-FR", "de-DE", "ja-JP" };
app.UseRequestLocalization(options =>
{
    options.SetDefaultCulture(supportedCultures[0])
           .AddSupportedCultures(supportedCultures)
           .AddSupportedUICultures(supportedCultures);
});
```

### IStringLocalizer<T>

The primary localization interface. Injectable via DI. Use everywhere: services, controllers, Blazor components, middleware.

```csharp
public class OrderService
{
    private readonly IStringLocalizer<OrderService> _localizer;

    public OrderService(IStringLocalizer<OrderService> localizer)
    {
        _localizer = localizer;
    }

    public string GetConfirmation(int orderId)
    {
        // Indexer returns LocalizedString with implicit string conversion
        return _localizer["OrderConfirmed", orderId];
        // Resolves: "Order {0} confirmed" with orderId substituted
    }

    public bool IsTranslated(string key)
    {
        LocalizedString result = _localizer[key];
        return !result.ResourceNotFound;
    }
}
```

### IViewLocalizer (MVC Razor Views Only)

Auto-resolves resource files matching the view path. Not supported in Blazor.

```cshtml
@* Views/Home/Index.cshtml *@
@inject IViewLocalizer Localizer

<h1>@Localizer["Welcome"]</h1>
<p>@Localizer["ItemCount", Model.Count]</p>
```

Resource file location: `Resources/Views/Home/Index.en-US.resx`

### IHtmlLocalizer (MVC Only)

HTML-aware variant that HTML-encodes format arguments but preserves HTML in the resource string itself. Not supported in Blazor.

```cshtml
@inject IHtmlLocalizer<SharedResource> HtmlLocalizer

@* Resource: "Read our <a href='/terms'>terms</a>, {0}" *@
@* {0} is HTML-encoded, the <a> tag is preserved *@
<p>@HtmlLocalizer["TermsNotice", Model.UserName]</p>
```

### When to Use Each

| Interface | Scope | HTML-Safe | Blazor | MVC |
|-----------|-------|-----------|--------|-----|
| `IStringLocalizer<T>` | Everywhere | No (plain text) | Yes | Yes |
| `IViewLocalizer` | View-local strings | No | **No** | Yes |
| `IHtmlLocalizer<T>` | HTML in resources | Yes | **No** | Yes |

### Namespace Resolution

If resource lookup fails, check namespace alignment. `IStringLocalizer<T>` resolves resources using the full type name of `T` relative to the `ResourcesPath`. Use `RootNamespaceAttribute` to fix namespace/assembly mismatches:

```csharp
[assembly: RootNamespace("MyApp")]
```


## Date, Number, and Currency Formatting

### CultureInfo

`CultureInfo` is the central class for culture-specific formatting. Two distinct properties control behavior:

- `CultureInfo.CurrentCulture` -- controls **formatting** (dates, numbers, currency)
- `CultureInfo.CurrentUICulture` -- controls **resource lookup** (which `.resx` file)

```csharp
// Always pass explicit CultureInfo -- never rely on thread defaults in server code
var date = DateTime.Now.ToString("D", new CultureInfo("fr-FR"));
// "vendredi 14 fevrier 2026"

var price = 1234.56m.ToString("C", new CultureInfo("de-DE"));
// "1.234,56 EUR" (uses NumberFormatInfo.CurrencySymbol)

var number = 1234567.89.ToString("N2", new CultureInfo("ja-JP"));
// "1,234,567.89"
```

### Server-Side Best Practices

```csharp
// Use useUserOverride: false in server scenarios to avoid
// picking up user-customized formats
var culture = new CultureInfo("en-US", useUserOverride: false);

// Set culture per-request (ASP.NET Core middleware handles this)
CultureInfo.CurrentCulture = culture;
CultureInfo.CurrentUICulture = culture;
```

### Format Specifiers

| Specifier | Type | Example (en-US) | Example (de-DE) |
|-----------|------|-----------------|-----------------|
| `"d"` | Short date | 2/14/2026 | 14.02.2026 |
| `"D"` | Long date | Friday, February 14, 2026 | Freitag, 14. Februar 2026 |
| `"C"` | Currency | $1,234.56 | 1.234,56 EUR |
| `"N2"` | Number | 1,234.57 | 1.234,57 |
| `"P1"` | Percent | 85.5% | 85,5 % |


## RTL Support

### Detecting RTL Cultures

```csharp
bool isRtl = CultureInfo.CurrentCulture.TextInfo.IsRightToLeft;
// true for: ar-*, he-*, fa-*, ur-*, etc.
```

### Per-Framework RTL Patterns

**Blazor:** No native `FlowDirection` -- use CSS `dir` attribute:

```javascript
// wwwroot/js/app.js
window.setDocumentDirection = (dir) => document.documentElement.dir = dir;
```

```csharp
// Set via named JS function (avoid eval -- causes CSP unsafe-eval violations)
await JSRuntime.InvokeVoidAsync("setDocumentDirection",
    isRtl ? "rtl" : "ltr");
```

For deep Blazor component patterns, see `references/blazor-components.md`.

**MAUI:** `FlowDirection` property on `VisualElement` and `Window`:

```csharp
// Set at window level -- cascades to all children
window.FlowDirection = isRtl
    ? FlowDirection.RightToLeft
    : FlowDirection.LeftToRight;
```

Android requires `android:supportsRtl="true"` in AndroidManifest.xml (set by default in MAUI). For deep MAUI patterns, see `references/maui-development.md`.

**Uno Platform:** Inherits WinUI `FlowDirection` model:

```xml
<Page FlowDirection="RightToLeft">
  <!-- All children inherit RTL layout -->
</Page>
```

For Uno Extensions and x:Uid binding, see `references/uno-platform.md`.

**WPF:** `FlowDirection` property on `FrameworkElement`:

```xml
<Window FlowDirection="RightToLeft">
  <!-- All children inherit RTL layout -->
</Window>
```

For WPF on modern .NET patterns, see `references/wpf-modern.md`.


## Pluralization

### The Problem

Simple string interpolation fails for pluralization across languages:

```csharp
// WRONG: English-only, breaks in languages with complex plural rules
$"You have {count} item{(count != 1 ? "s" : "")}"
```

Languages like Arabic have six plural forms (zero, one, two, few, many, other). Polish distinguishes "few" from "many" based on number ranges.

### ICU MessageFormat (MessageFormat.NET)

CLDR-compliant pluralization using ICU plural categories. Recommended for internationalization-first projects.

```csharp
// Package: jeffijoe/messageformat.net (v5.0+, ships CLDR pluralizers)
var formatter = new MessageFormatter();

string pattern = "{count, plural, " +
    "=0 {No items}" +
    "one {# item}" +
    "other {# items}}";

formatter.Format(pattern, new { count = 0 });  // "No items"
formatter.Format(pattern, new { count = 1 });  // "1 item"
formatter.Format(pattern, new { count = 42 }); // "42 items"
```

### SmartFormat.NET

Flexible text templating with built-in pluralization. Good for projects wanting maximum flexibility.

```csharp
// Package: axuno/SmartFormat (v3.6.1+)
using SmartFormat;

Smart.Format("{count:plural:No items|# item|# items}",
    new { count = 0 });  // "No items"
Smart.Format("{count:plural:No items|# item|# items}",
    new { count = 1 });  // "1 item"
Smart.Format("{count:plural:No items|# item|# items}",
    new { count = 5 });  // "5 items"
```

### Choosing a Pluralization Engine

| Engine | CLDR Compliance | API Style | Best For |
|--------|-----------------|-----------|----------|
| MessageFormat.NET | Full (CLDR categories) | ICU pattern strings | Multi-locale apps needing standard compliance |
| SmartFormat.NET | Partial (extensible) | .NET format string extension | Flexible templating with pluralization |
| Manual conditional | None | `string.Format` + branching | Simple English-only dual forms |


## UI Framework Integration

### Blazor Localization

Blazor supports `IStringLocalizer` only -- `IHtmlLocalizer` and `IViewLocalizer` are not available.

**Component injection:**

```razor
@inject IStringLocalizer<MyComponent> Loc

<h1>@Loc["Welcome"]</h1>
<p>@Loc["ItemCount", items.Count]</p>
```

**Culture configuration by render mode:**

| Render Mode | Culture Source |
|-------------|---------------|
| Server / SSR | `RequestLocalizationMiddleware` (server-side) |
| WebAssembly | `CultureInfo.DefaultThreadCurrentCulture` + Blazor start option `applicationCulture` |
| Auto | Both -- server middleware for initial load, WASM culture for client-side |

**WASM globalization data:**

```xml
<!-- Required for full ICU data in Blazor WASM -->
<PropertyGroup>
  <BlazorWebAssemblyLoadAllGlobalizationData>true</BlazorWebAssemblyLoadAllGlobalizationData>
</PropertyGroup>
```

Without this property, Blazor WASM loads only a subset of ICU data. For minimal download size, use `InvariantGlobalization=true` (disables localization entirely).

**Dynamic culture switching:**

```csharp
// CultureSelector component pattern:
// 1. Store selected culture in browser local storage
// 2. Set culture cookie via controller redirect (server-side)
// 3. Read cookie in RequestLocalizationMiddleware
```

For deep Blazor component patterns (lifecycle, state management, JS interop), see `references/blazor-components.md`.

### MAUI Localization

MAUI uses `.resx` files with strongly-typed generated properties.

**Resource setup:**

```
Resources/
  Strings/
    AppResources.resx              # Default (neutral) culture
    AppResources.fr-FR.resx        # French
    AppResources.ja-JP.resx        # Japanese
```

**XAML binding:**

```xml
<!-- Import namespace -->
<ContentPage xmlns:strings="clr-namespace:MyApp.Resources.Strings">

  <!-- Use x:Static for strongly-typed access -->
  <Label Text="{x:Static strings:AppResources.Welcome}" />
  <Button Text="{x:Static strings:AppResources.LoginButton}" />
</ContentPage>
```

**Code access:**

```csharp
string welcome = AppResources.Welcome;
```

**Platform requirements:**
- iOS/Mac Catalyst: Add `CFBundleLocalizations` to `Info.plist`
- Windows: Add `<Resource Language="...">` entries to `Package.appxmanifest`
- All platforms: Set `<NeutralLanguage>en-US</NeutralLanguage>` in csproj

For deep MAUI development patterns (controls, navigation, platform APIs), see `references/maui-development.md`.

### Uno Platform Localization

Uno uses `.resw` files (Windows resource format) with `x:Uid` for automatic XAML resource binding.

**Resource structure:**

```
Strings/
  en/Resources.resw
  fr-FR/Resources.resw
  ja-JP/Resources.resw
```

**Registration:**

```csharp
// In Host builder configuration
.UseLocalization()
```

**XAML binding with x:Uid:**

```xml
<!-- x:Uid maps to resource keys: "MainPage_Title.Text", "LoginButton.Content" -->
<TextBlock x:Uid="MainPage_Title" />
<Button x:Uid="LoginButton" />
```

**Runtime culture switching:**

```csharp
var localizationService = serviceProvider
    .GetRequiredService<ILocalizationService>();
await localizationService.SetCurrentCultureAsync(
    new CultureInfo("fr-FR"));
// Note: XAML x:Uid bindings retain old culture until app restart
```

**Known limitation:** `x:Uid`-based localization keeps the old culture until app restart, even after calling `SetCurrentCultureAsync`. Code-based `IStringLocalizer` updates immediately.

For Uno Extensions ecosystem configuration and MVUX patterns, see `references/uno-platform.md`.

### WPF Localization

**Recommended approach for .NET 8+:** `.resx` files with `DynamicResource` binding for runtime locale switching. Avoid LocBaml (works only on .NET Framework).

**Resource dictionary approach:**

```xml
<!-- Resources/Strings.en-US.xaml -->
<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                    xmlns:sys="clr-namespace:System;assembly=System.Runtime">
  <sys:String x:Key="Welcome">Welcome</sys:String>
  <sys:String x:Key="LoginButton">Log In</sys:String>
</ResourceDictionary>
```

```xml
<!-- MainWindow.xaml -->
<TextBlock Text="{DynamicResource Welcome}" />
<Button Content="{DynamicResource LoginButton}" />
```

**Runtime locale switching:**

```csharp
// Swap resource dictionary at runtime
var dict = new ResourceDictionary
{
    Source = new Uri($"Resources/Strings.{cultureName}.xaml",
                     UriKind.Relative)
};
Application.Current.Resources.MergedDictionaries.Clear();
Application.Current.Resources.MergedDictionaries.Add(dict);
```

**ResX approach (simpler, works on all .NET versions):**

```csharp
// Standard .resx with generated class
string welcome = Strings.Welcome;

// Runtime switch
Thread.CurrentThread.CurrentUICulture = new CultureInfo("fr-FR");
// Re-read after culture change
string welcomeFr = Strings.Welcome; // Now returns French
```

**Community options:**
- **WPF Localization Extensions** -- RESX files with XAML markup extensions for declarative localization
- **LocBamlCore** (h3xds1nz) -- unofficial port supporting .NET 9, for BAML localization on modern .NET

For WPF Host builder, MVVM Toolkit, and theming patterns, see `references/wpf-modern.md`.


## Agent Gotchas

1. **Do not use `IHtmlLocalizer` or `IViewLocalizer` in Blazor.** These are MVC-only features. Use `IStringLocalizer<T>` in Blazor components.
2. **Do not rely on `CultureInfo.CurrentCulture` thread defaults in server code.** Always pass explicit `CultureInfo` to formatting methods. Server thread culture may not match the request culture.
3. **Do not hardcode plural forms.** English "singular/plural" does not work for Arabic (6 forms), Polish, or other languages. Use MessageFormat.NET or SmartFormat.NET for proper CLDR pluralization.
4. **Do not use LocBaml for WPF on .NET 8+.** LocBaml is a .NET Framework-only sample tool. Use `.resx` files or resource dictionaries for modern WPF.
5. **Do not forget `BlazorWebAssemblyLoadAllGlobalizationData` for Blazor WASM.** Without it, only partial ICU data is loaded, causing incorrect date/number formatting for many cultures.
6. **Do not add translation keys absent from the default `.resx` file.** The default resource is the single source of truth; satellite assemblies must be a subset.
7. **Do not use `ResourceManager` directly in AOT/trimmed apps.** It relies on reflection. Use a source generator (ResXGenerator) for compile-time resource access.
8. **Do not forget platform-specific setup for MAUI.** iOS/Mac Catalyst need `CFBundleLocalizations` in `Info.plist`; Windows needs `Resource Language` entries.
