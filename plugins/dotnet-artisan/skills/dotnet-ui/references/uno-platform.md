# Uno Platform

Uno Platform core development: Extensions ecosystem (Navigation, DI, Configuration, Serialization, Localization, Logging, HTTP, Authentication), MVUX reactive pattern, Toolkit controls, Theme resources (Material/Cupertino/Fluent), Hot Reload, and single-project structure. Covers Uno Platform 5.x+ on .NET 8.0+ baseline.

## Single-Project Structure

Uno Platform 5.x uses a single-project structure with conditional TFMs for multi-targeting. One `.csproj` targets all platforms via multi-targeting.

```xml
<!-- MyApp.csproj -->
<Project Sdk="Uno.Sdk">
  <PropertyGroup>
    <TargetFrameworks>
      net8.0-browserwasm;
      net8.0-ios;
      net8.0-android;
      net8.0-maccatalyst;
      net8.0-windows10.0.19041;
      net8.0-desktop
    </TargetFrameworks>
    <OutputType>Exe</OutputType>
    <UnoFeatures>
      Extensions;
      Toolkit;
      Material;
      MVUX;
      Navigation;
      Configuration;
      Hosting;
      Http;
      Localization;
      Logging;
      LoggingSerilog;
      Serialization;
      Authentication;
      AuthenticationOidc
    </UnoFeatures>
  </PropertyGroup>
</Project>
```

The `UnoFeatures` MSBuild property controls which Uno Extensions and theming packages are included. The Uno SDK resolves these features to the correct NuGet packages automatically.

### Project Layout

```
MyApp/
  MyApp/
    App.xaml / App.xaml.cs        # Application entry, resource dictionaries
    MainPage.xaml / .xaml.cs      # Initial page
    Presentation/                 # ViewModels or MVUX Models
    Views/                        # XAML pages
    Services/                     # Service interfaces and implementations
    Strings/                      # Localization resources (.resw)
      en/Resources.resw
    Assets/                       # Images, fonts, icons
    appsettings.json              # Configuration (Extensions.Configuration)
    Platforms/                    # Platform-specific code (conditional compilation)
      Android/
      iOS/
      Wasm/
      Desktop/
  MyApp.Tests/                   # Unit tests (shared logic)
```


## Uno Extensions

Uno Extensions provide opinionated infrastructure on top of the platform. All modules are registered through the host builder pattern.

### Host Builder Setup

```csharp
// App.xaml.cs
public App()
{
    this.InitializeComponent();

    Host = UnoHost
        .CreateDefaultBuilder()
        .UseConfiguration(configure: configBuilder =>
            configBuilder.EmbeddedSource<App>()
                         .Section<AppConfig>())
        .UseLocalization()
        .UseNavigation(RegisterRoutes)
        .UseSerilog(loggerConfiguration: config =>
            config.WriteTo.Debug())
        .ConfigureServices((context, services) =>
        {
            services.AddSingleton<IProductService, ProductService>();
        })
        .Build();
}
```

### Navigation

**Package:** `Uno.Extensions.Navigation`

Region-based navigation with route maps, deep linking, and type-safe parameter passing. Navigation is driven declaratively from XAML or imperatively from code.

```csharp
// Route registration
private static void RegisterRoutes(IViewRegistry views, IRouteRegistry routes)
{
    views.Register(
        new ViewMap(ViewModel: typeof(ShellModel)),
        new ViewMap<MainPage, MainModel>(),
        new ViewMap<ProductDetailPage, ProductDetailModel>(),
        new DataViewMap<ProductDetailPage, ProductDetailModel, ProductEntity>()
    );

    routes.Register(
        new RouteMap("", View: views.FindByViewModel<ShellModel>(),
            Nested: new RouteMap[]
            {
                new("Main", View: views.FindByViewModel<MainModel>()),
                new("ProductDetail", View: views.FindByViewModel<ProductDetailModel>())
            })
    );
}
```

```xml
<!-- XAML-based navigation using attached properties -->
<Button Content="View Product"
        uen:Navigation.Request="ProductDetail"
        uen:Navigation.Data="{Binding SelectedProduct}" />
```

**Key concepts:** Region-based navigation attaches navigation behavior to visual regions (Frame, NavigationView, TabBar). Route maps define the navigation graph. Deep linking maps URLs to routes for WASM.

### Dependency Injection

**Package:** `Uno.Extensions.Hosting`

Uses Microsoft.Extensions.Hosting under the hood. Host builder pattern with service registration, keyed services, and scoped lifetimes.

```csharp
.ConfigureServices((context, services) =>
{
    // Standard DI registration
    services.AddSingleton<IAuthService, AuthService>();
    services.AddTransient<IOrderService, OrderService>();

    // Keyed services (.NET 8+)
    services.AddKeyedSingleton<ICache>("memory", new MemoryCache());
    services.AddKeyedSingleton<ICache>("distributed", new RedisCache());
})
```

### Configuration

**Package:** `Uno.Extensions.Configuration`

Loads configuration from `appsettings.json` (embedded resource), environment-specific overrides, and runtime writeable options.

```json
// appsettings.json
{
  "AppConfig": {
    "ApiBaseUrl": "https://api.example.com",
    "MaxRetries": 3
  }
}
```

```csharp
// Binding to strongly-typed options
.UseConfiguration(configure: configBuilder =>
    configBuilder
        .EmbeddedSource<App>()
        .Section<AppConfig>())

// AppConfig.cs
public record AppConfig
{
    public string ApiBaseUrl { get; init; } = "";
    public int MaxRetries { get; init; } = 3;
}
```

### Serialization

**Package:** `Uno.Extensions.Serialization`

Integrates System.Text.Json with source generators for AOT compatibility. Configures JSON serialization across the Extensions ecosystem.

```csharp
.UseSerialization(configure: serializerBuilder =>
    serializerBuilder
        .AddJsonTypeInfo(AppJsonContext.Default.ProductDto)
        .AddJsonTypeInfo(AppJsonContext.Default.OrderDto))
```

For general serialization patterns and AOT source-gen depth, see [skill:dotnet-csharp].

### Localization

**Package:** `Uno.Extensions.Localization`

Resource-based localization using `.resw` files with runtime culture switching.

```csharp
.UseLocalization()
```

```xml
<!-- Strings/en/Resources.resw -->
<!-- name: MainPage_Title.Text, value: Welcome -->
<!-- name: MainPage_LoginButton.Content, value: Log In -->

<!-- XAML: use x:Uid for automatic resource binding -->
<TextBlock x:Uid="MainPage_Title" />
<Button x:Uid="MainPage_LoginButton" />
```

Culture switching at runtime:

```csharp
// Switch culture programmatically
var localizationService = serviceProvider.GetRequiredService<ILocalizationService>();
await localizationService.SetCurrentCultureAsync(new CultureInfo("fr-FR"));
```

### Logging

**Package:** `Uno.Extensions.Logging`

Integrates with Microsoft.Extensions.Logging. Serilog integration for platform-specific sinks.

```csharp
.UseSerilog(loggerConfiguration: config =>
    config
        .MinimumLevel.Information()
        .WriteTo.Debug()
        .WriteTo.Console())
```

Platform-specific sinks: Debug output for desktop, browser console for WASM, platform logcat for Android, NSLog for iOS.

### HTTP

**Package:** `Uno.Extensions.Http`

HTTP client integration with endpoint configuration. Supports Refit for typed API clients and Kiota for OpenAPI-generated clients.

```csharp
.UseHttp(configure: (context, services) =>
    services
        .AddRefitClient<IProductApi>(context,
            configure: builder => builder
                .ConfigureHttpClient(client =>
                    client.BaseAddress = new Uri("https://api.example.com"))))
```

```csharp
// Refit interface
public interface IProductApi
{
    [Get("/products")]
    Task<List<ProductDto>> GetProductsAsync(CancellationToken ct = default);

    [Get("/products/{id}")]
    Task<ProductDto> GetProductByIdAsync(int id, CancellationToken ct = default);
}
```

### Authentication

**Package:** `Uno.Extensions.Authentication`

OIDC, custom auth providers, and token management. Integrates with navigation for login/logout flows.

```csharp
.UseAuthentication(auth =>
    auth.AddOidc(oidc =>
    {
        oidc.Authority = "https://login.example.com";
        oidc.ClientId = "my-app";
        oidc.Scope = "openid profile email";
    }))
```

Token management is automatic: tokens are stored securely per platform (Keychain on iOS/macOS, KeyStore on Android, Credential Manager on Windows, browser storage on WASM) and refreshed transparently.


## MVUX (Model-View-Update-eXtended)

MVUX is Uno's recommended reactive pattern, distinct from MVVM. It uses immutable records, Feeds, and States to model data flow declaratively. Source generators produce bindable proxies from plain model classes.

### Core Concepts

| Concept | Purpose | MVVM Equivalent |
|---------|---------|-----------------|
| **Model** | Immutable record defining UI state | ViewModel |
| **Feed** | Async data source (loading/data/error states) | ObservableCollection + loading flag |
| **State** | Mutable reactive state with change tracking | INotifyPropertyChanged property |
| **ListFeed** | Feed specialized for collections | ObservableCollection |
| **Command** | Auto-generated from public async methods | ICommand |

### Model Example

```csharp
// ProductModel.cs -- MVUX model (source generators produce the bindable proxy)
public partial record ProductModel(IProductService ProductService)
{
    // Feed: async data source with loading/error/data states
    public IFeed<IImmutableList<ProductDto>> Products => Feed
        .Async(async ct => await ProductService.GetProductsAsync(ct));

    // State: mutable reactive value
    public IState<string> SearchTerm => State<string>.Value(this, () => "");

    // ListFeed with selection support
    public IListFeed<ProductDto> FilteredProducts => SearchTerm
        .SelectAsync(async (term, ct) =>
            await ProductService.SearchProductsAsync(term, ct))
        .AsListFeed();

    // Command: auto-generated from async method signature
    public async ValueTask AddProduct(CancellationToken ct)
    {
        var term = await SearchTerm;
        await ProductService.AddProductAsync(term, ct);
    }
}
```

```xml
<!-- ProductPage.xaml -- binds to generated proxy -->
<Page x:Class="MyApp.Views.ProductPage"
      xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
      xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">

    <StackPanel>
        <TextBox Text="{Binding SearchTerm, Mode=TwoWay}" />

        <FeedView Source="{Binding FilteredProducts}">
            <FeedView.ValueTemplate>
                <DataTemplate>
                    <ListView ItemsSource="{Binding Data}">
                        <ListView.ItemTemplate>
                            <DataTemplate>
                                <TextBlock Text="{Binding Name}" />
                            </DataTemplate>
                        </ListView.ItemTemplate>
                    </ListView>
                </DataTemplate>
            </FeedView.ValueTemplate>
            <FeedView.ProgressTemplate>
                <DataTemplate>
                    <ProgressRing IsActive="True" />
                </DataTemplate>
            </FeedView.ProgressTemplate>
            <FeedView.ErrorTemplate>
                <DataTemplate>
                    <TextBlock Text="Error loading products" Foreground="Red" />
                </DataTemplate>
            </FeedView.ErrorTemplate>
        </FeedView>

        <Button Content="Add Product" Command="{Binding AddProduct}" />
    </StackPanel>
</Page>
```

### MVUX vs MVVM

| Concern | MVUX | MVVM |
|---------|------|------|
| Model definition | Immutable `record` types | Mutable classes with `INotifyPropertyChanged` |
| Data loading | `IFeed<T>` with built-in loading/error states | Manual loading flags and try/catch |
| Collections | `IListFeed<T>` with immutable snapshots | `ObservableCollection<T>` with mutation |
| Commands | Auto-generated from `async` methods | `ICommand` implementations (RelayCommand) |
| State changes | `IState<T>` with explicit update semantics | Property setters firing `PropertyChanged` |
| Boilerplate | Minimal (source generators) | Significant (base classes, attributes) |

**When to use MVUX:** New Uno Platform projects, especially those with async data sources and complex loading states. MVUX eliminates most boilerplate and handles loading/error states declaratively.

**When to use MVVM:** Projects migrating from existing WPF/UWP/WinUI codebases, teams familiar with MVVM patterns, or projects using CommunityToolkit.Mvvm.


## Uno Toolkit Controls

The Uno Toolkit provides cross-platform controls and helpers beyond stock WinUI controls. Enabled via `UnoFeatures` with `Toolkit`.

### Key Controls

| Control | Purpose |
|---------|---------|
| `AutoLayout` | Flexbox-like layout with spacing, padding, and alignment |
| `Card` / `CardContentControl` | Material-style card surfaces with elevation |
| `Chip` / `ChipGroup` | Filter chips, action chips, selection chips |
| `Divider` | Horizontal/vertical separator lines |
| `DrawerControl` | Side drawer (hamburger menu) |
| `LoadingView` | Loading state wrapper with skeleton/shimmer |
| `NavigationBar` | Cross-platform navigation bar |
| `ResponsiveView` | Adaptive layout based on screen width breakpoints |
| `SafeArea` | Insets for notches, status bars, navigation bars |
| `ShadowContainer` | Cross-platform drop shadows via `ThemeShadow` |
| `TabBar` | Bottom or top tab navigation |
| `ZoomContentControl` | Pinch-to-zoom container |

### Toolkit Helpers

| Helper | Purpose |
|--------|---------|
| `CommandExtensions` | Attach commands to any control (not just Button) |
| `ItemsRepeaterExtensions` | Selection and command support for ItemsRepeater |
| `InputExtensions` | Auto-focus, return key command, input scope |
| `ResponsiveMarkupExtensions` | Responsive values in XAML markup (e.g., `Responsive.Narrow`) |
| `StatusBarExtensions` | Control status bar appearance per-platform |
| `AncestorBinding` | Bind to ancestor DataContext in templates |

### AutoLayout Example

```xml
<!-- Vertical stack with spacing, padding, and alignment -->
<utu:AutoLayout Spacing="16" Padding="24"
                PrimaryAxisAlignment="Start"
                CounterAxisAlignment="Stretch">

    <TextBlock Text="Product List"
               Style="{StaticResource HeadlineMedium}" />

    <utu:AutoLayout Spacing="8" Orientation="Horizontal">
        <TextBox PlaceholderText="Search..."
                 utu:AutoLayout.PrimaryLength="*" />
        <Button Content="Search"
                utu:AutoLayout.CounterAlignment="Center" />
    </utu:AutoLayout>

    <ListView ItemsSource="{Binding Products}"
              utu:AutoLayout.PrimaryLength="*" />
</utu:AutoLayout>
```


## Theme Resources

Uno supports Material, Cupertino, and Fluent design systems as theme packages. Themes provide consistent colors, typography, elevation, and control styles across all platforms.

### Theme Configuration

```xml
<!-- UnoFeatures in .csproj -->
<UnoFeatures>Material</UnoFeatures>   <!-- or Cupertino, or both -->
```

```xml
<!-- App.xaml -- theme resource dictionaries -->
<Application.Resources>
    <ResourceDictionary>
        <ResourceDictionary.MergedDictionaries>
            <!-- Material theme resources -->
            <MaterialTheme />

            <!-- Optional: color palette override -->
            <ResourceDictionary Source="ms-appx:///Themes/ColorPaletteOverride.xaml" />
        </ResourceDictionary.MergedDictionaries>
    </ResourceDictionary>
</Application.Resources>
```

### Color Customization

Override Material theme colors through `ColorPaletteOverride.xaml`:

```xml
<!-- Themes/ColorPaletteOverride.xaml -->
<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
    <Color x:Key="PrimaryColor">#6750A4</Color>
    <Color x:Key="SecondaryColor">#625B71</Color>
    <Color x:Key="TertiaryColor">#7D5260</Color>
    <Color x:Key="ErrorColor">#B3261E</Color>
</ResourceDictionary>
```

### Typography

Use existing TextBlock styles from the theme system. Never set explicit font sizes -- use the Material type scale:

```xml
<TextBlock Text="Headline" Style="{StaticResource HeadlineMedium}" />
<TextBlock Text="Body text" Style="{StaticResource BodyLarge}" />
<TextBlock Text="Caption" Style="{StaticResource LabelSmall}" />
```

| Style | Typical Use |
|-------|------------|
| `DisplayLarge/Medium/Small` | Hero text, splash screens |
| `HeadlineLarge/Medium/Small` | Page titles, section headers |
| `TitleLarge/Medium/Small` | Card titles, dialog titles |
| `BodyLarge/Medium/Small` | Paragraph text, descriptions |
| `LabelLarge/Medium/Small` | Button labels, captions, metadata |

### ThemeService

Switch between light and dark themes programmatically:

```csharp
var themeService = serviceProvider.GetRequiredService<IThemeService>();
await themeService.SetThemeAsync(AppTheme.Dark);
var currentTheme = themeService.Theme;
```


## Hot Reload

Uno Platform provides Hot Reload across all targets via its custom implementation. Changes to XAML and C# code-behind are reflected without restarting the app.

### Supported Changes

| Change Type | Hot Reload Support |
|-------------|-------------------|
| XAML layout/styling | Full reload, instant |
| C# code-behind (method bodies) | Supported via MetadataUpdateHandler |
| New properties/methods | Requires rebuild |
| Resource dictionary changes | Full reload |
| Navigation route changes | Requires rebuild |

### Enabling Hot Reload

```bash
# Set environment variable before dotnet run
export DOTNET_MODIFIABLE_ASSEMBLIES=debug

# Run with Hot Reload
dotnet run -f net8.0-desktop --project MyApp/MyApp.csproj
```

Hot Reload is automatically configured by Visual Studio and VS Code (with Uno extension). For CLI usage, set `DOTNET_MODIFIABLE_ASSEMBLIES=debug` before running.

**Gotcha:** Hot Reload does not support adding new types, changing inheritance hierarchies, or modifying `UnoFeatures`. These require a full rebuild.


## Agent Gotchas

1. **Do not confuse MVUX with MVVM.** MVUX uses immutable records, Feeds, and States -- not `INotifyPropertyChanged`. Do not add `ObservableProperty` attributes to MVUX models.
2. **Do not hardcode NuGet package versions for Uno Extensions.** The `UnoFeatures` MSBuild property resolves packages automatically via the Uno SDK. Adding explicit `PackageReference` items for Extensions can cause version conflicts.
3. **Do not use `{Binding StringFormat=...}`** in Uno XAML. It is a WPF-only feature. Use converters or multiple `<Run>` elements for formatted text.
4. **Do not use `x:Static` or `{x:Reference}` in bindings.** These are WPF-only markup extensions not available in WinUI/Uno.
5. **Do not set explicit font sizes or weights.** Use the theme's TextBlock styles (e.g., `HeadlineMedium`, `BodyLarge`) to maintain design system consistency.
6. **Do not use hardcoded hex colors.** Always reference theme resources (`PrimaryColor`, `SecondaryColor`) or semantic brushes to maintain theme compatibility.
7. **Do not use `AppBarButton` outside a `CommandBar`.** Use regular `Button` with icon content for standalone icon buttons.
8. **Do not forget `x:Uid` for localization.** Every user-visible string should use `x:Uid` referencing `.resw` resources, not hardcoded text.


## Prerequisites

- .NET 8.0+ (Uno Platform 5.x baseline)
- Uno SDK (`Uno.Sdk` project SDK)
- Platform workloads as needed: `dotnet workload install ios android maccatalyst wasm-tools`
- Visual Studio 2022+ or VS Code with Uno Platform extension


## References

- [Uno Platform Documentation](https://platform.uno/docs/)
- [Uno Extensions Overview](https://platform.uno/docs/articles/external/uno.extensions/)
- [MVUX Pattern](https://platform.uno/docs/articles/external/uno.extensions/doc/Overview/Mvux/Overview.html)
- [Uno Toolkit](https://platform.uno/docs/articles/external/uno.toolkit.ui/)
- [Uno Themes](https://platform.uno/docs/articles/external/uno.themes/)
- [Uno SDK Features](https://platform.uno/docs/articles/features/uno-sdk.html)
