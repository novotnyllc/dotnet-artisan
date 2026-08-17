# WinUI

WinUI 3 / Windows App SDK development: project setup with `UseWinUI` and Windows 10 TFM, XAML patterns with compiled bindings (`x:Bind`) and deferred loading (`x:Load`), MVVM with CommunityToolkit.Mvvm, MSIX and unpackaged deployment modes, Windows integration (lifecycle, notifications, widgets), UWP migration guidance, and common agent pitfalls.

**Version assumptions:** .NET 8.0+ baseline. Windows App SDK 1.6+ (current stable). TFM `net8.0-windows10.0.19041.0`. .NET 9 features explicitly marked.

## Project Setup

WinUI 3 uses the Windows App SDK (formerly Project Reunion) as its runtime and API layer. Projects target a Windows 10 version-specific TFM.

```xml
<!-- MyWinUIApp.csproj -->
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>WinExe</OutputType>
    <TargetFramework>net8.0-windows10.0.19041.0</TargetFramework>
    <UseWinUI>true</UseWinUI>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>

    <!-- Windows App SDK version (auto-referenced via UseWinUI) -->
    <WindowsAppSDKSelfContained>true</WindowsAppSDKSelfContained>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="CommunityToolkit.Mvvm" Version="8.*" />
    <PackageReference Include="CommunityToolkit.WinUI.Controls.SettingsControls" Version="8.*" />
    <PackageReference Include="Microsoft.Extensions.Hosting" Version="8.*" />
  </ItemGroup>
</Project>
```

### Project Layout

```
MyWinUIApp/
  App.xaml / App.xaml.cs        # Application entry, resource dictionaries
  MainWindow.xaml / .xaml.cs    # Main window
  ViewModels/                   # MVVM ViewModels
  Views/                        # XAML pages (for Frame navigation)
  Models/                       # Data models
  Services/                     # Service interfaces and implementations
  Assets/                       # Images, icons
  Package.appxmanifest          # MSIX manifest (packaged mode)
  Properties/
    launchSettings.json
```

### Host Builder Pattern

Modern WinUI apps use the generic host for dependency injection and service configuration:

```csharp
// App.xaml.cs
public partial class App : Application
{
    private readonly IHost _host;

    public App()
    {
        this.InitializeComponent();

        _host = Host.CreateDefaultBuilder()
            .ConfigureServices((context, services) =>
            {
                // Services
                services.AddSingleton<INavigationService, NavigationService>();
                services.AddSingleton<IProductService, ProductService>();

                // ViewModels
                services.AddTransient<MainViewModel>();
                services.AddTransient<ProductDetailViewModel>();

                // Views
                services.AddTransient<MainPage>();
                services.AddTransient<ProductDetailPage>();

                // Windows
                services.AddSingleton<MainWindow>();
            })
            .Build();
    }

    protected override async void OnLaunched(LaunchActivatedEventArgs args)
    {
        await _host.StartAsync();

        var mainWindow = _host.Services.GetRequiredService<MainWindow>();
        mainWindow.Closed += async (_, _) =>
        {
            await _host.StopAsync();
            _host.Dispose();
        };
        mainWindow.Activate();
    }

    public static T GetService<T>() where T : class
    {
        var app = (App)Application.Current;
        return app._host.Services.GetRequiredService<T>();
    }
}
```

### TFM Requirements

The `net8.0-windows10.0.19041.0` TFM specifies:
- **.NET 8.0** -- the runtime version
- **Windows 10 build 19041** (version 2004) -- the minimum Windows SDK version

Windows App SDK features may require higher SDK versions:
- **Widgets (Windows 11):** `net8.0-windows10.0.22000.0` (Windows 11 build 22000)
- **Mica backdrop:** `net8.0-windows10.0.22000.0`
- **Snap layouts integration:** `net8.0-windows10.0.22000.0`


## XAML Patterns

WinUI 3 XAML is distinct from UWP XAML. The root namespace is `Microsoft.UI.Xaml`, not `Windows.UI.Xaml`.

### Compiled Bindings (x:Bind)

`x:Bind` provides compile-time type checking and better performance than `{Binding}`. It resolves properties relative to the code-behind class (not the `DataContext`).

```xml
<Page x:Class="MyApp.Views.ProductListPage"
      xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
      xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
      xmlns:vm="using:MyApp.ViewModels">

    <Page.Resources>
        <!-- x:Bind resolves against code-behind, so expose ViewModel as property -->
    </Page.Resources>

    <StackPanel Padding="16" Spacing="12">
        <TextBox Text="{x:Bind ViewModel.SearchTerm, Mode=TwoWay, UpdateSourceTrigger=PropertyChanged}" />
        <Button Content="Search" Command="{x:Bind ViewModel.SearchCommand}" />

        <ListView ItemsSource="{x:Bind ViewModel.Products, Mode=OneWay}"
                  SelectionMode="Single">
            <ListView.ItemTemplate>
                <DataTemplate x:DataType="vm:ProductViewModel">
                    <StackPanel Orientation="Horizontal" Spacing="12" Padding="8">
                        <Image Source="{x:Bind ImageUrl}" Height="60" Width="60" />
                        <StackPanel>
                            <TextBlock Text="{x:Bind Name}" Style="{StaticResource BodyStrongTextBlockStyle}" />
                            <TextBlock Text="{x:Bind Price}" Style="{StaticResource CaptionTextBlockStyle}" />
                        </StackPanel>
                    </StackPanel>
                </DataTemplate>
            </ListView.ItemTemplate>
        </ListView>
    </StackPanel>
</Page>
```

```csharp
// Code-behind: expose ViewModel property for x:Bind
public sealed partial class ProductListPage : Page
{
    public ProductListViewModel ViewModel { get; }

    public ProductListPage()
    {
        ViewModel = App.GetService<ProductListViewModel>();
        this.InitializeComponent();
    }
}
```

**Key differences from `{Binding}`:**
- `x:Bind` is resolved at compile time (type-safe, faster)
- Default mode is `OneTime` (not `OneWay` like `{Binding}`)
- Resolves against the code-behind class, not `DataContext`
- Requires `x:DataType` in `DataTemplate` items

### Deferred Loading (x:Load)

Use `x:Load` to defer element creation until needed, reducing initial page load time:

```xml
<StackPanel>
    <TextBlock Text="Always visible" />

    <!-- This panel is not created until ShowDetails is true -->
    <StackPanel x:Load="{x:Bind ViewModel.ShowDetails, Mode=OneWay}" x:Name="DetailsPanel">
        <TextBlock Text="Detail content loaded on demand" />
        <ListView ItemsSource="{x:Bind ViewModel.DetailItems, Mode=OneWay}" />
    </StackPanel>
</StackPanel>
```

**When to use `x:Load`:** Heavy UI sections (complex lists, settings panels, detail views) that are not immediately visible. The element is created when the bound property becomes `true` and destroyed when it becomes `false`.

### NavigationView Pattern

WinUI apps typically use `NavigationView` with a `Frame` for page navigation:

```xml
<!-- MainWindow.xaml -->
<Window x:Class="MyApp.MainWindow"
        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">

    <NavigationView x:Name="NavView"
                    IsBackButtonVisible="Collapsed"
                    SelectionChanged="NavView_SelectionChanged">
        <NavigationView.MenuItems>
            <NavigationViewItem Content="Home" Tag="home" Icon="Home" />
            <NavigationViewItem Content="Products" Tag="products" Icon="Shop" />
            <NavigationViewItem Content="Settings" Tag="settings" Icon="Setting" />
        </NavigationView.MenuItems>

        <Frame x:Name="ContentFrame" />
    </NavigationView>
</Window>
```


## MVVM

WinUI 3 integrates with CommunityToolkit.Mvvm (the same MVVM Toolkit used by MAUI). Source generators eliminate boilerplate for properties and commands.

```csharp
// ViewModels/ProductListViewModel.cs
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

public partial class ProductListViewModel : ObservableObject
{
    private readonly IProductService _productService;

    public ProductListViewModel(IProductService productService)
    {
        _productService = productService;
    }

    [ObservableProperty]
    [NotifyCanExecuteChangedFor(nameof(SearchCommand))]
    private string _searchTerm = "";

    [ObservableProperty]
    private ObservableCollection<ProductViewModel> _products = [];

    [ObservableProperty]
    private bool _isLoading;

    [ObservableProperty]
    private bool _showDetails;

    [RelayCommand]
    private async Task LoadProductsAsync(CancellationToken ct)
    {
        IsLoading = true;
        try
        {
            var items = await _productService.GetProductsAsync(ct);
            Products = new ObservableCollection<ProductViewModel>(
                items.Select(p => new ProductViewModel(p)));
        }
        finally
        {
            IsLoading = false;
        }
    }

    [RelayCommand(CanExecute = nameof(CanSearch))]
    private async Task SearchAsync(CancellationToken ct)
    {
        var results = await _productService.SearchAsync(SearchTerm, ct);
        Products = new ObservableCollection<ProductViewModel>(
            results.Select(p => new ProductViewModel(p)));
    }

    private bool CanSearch() => !string.IsNullOrWhiteSpace(SearchTerm);
}
```

**Key source generator attributes:**
- `[ObservableProperty]` -- generates property with `INotifyPropertyChanged` from a backing field
- `[RelayCommand]` -- generates `ICommand` from a method (supports async, cancellation, `CanExecute`)
- `[NotifyPropertyChangedFor]` -- raises `PropertyChanged` for dependent properties
- `[NotifyCanExecuteChangedFor]` -- re-evaluates command `CanExecute` when property changes


## Packaging

WinUI 3 supports two deployment models: MSIX packaged and unpackaged. The choice affects app identity, capabilities, and distribution.

### MSIX Packaged Deployment

MSIX is the default packaging model. It provides app identity, clean install/uninstall, automatic updates, and access to full Windows integration APIs.

```xml
<!-- Package.appxmanifest declares app identity and capabilities -->
<Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10"
         xmlns:mp="http://schemas.microsoft.com/appx/2014/phone/manifest"
         xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10">

  <Identity Name="MyApp" Publisher="CN=Contoso" Version="1.0.0.0" />

  <Applications>
    <Application Id="App"
                 Executable="$targetnametoken$.exe"
                 EntryPoint="$targetentrypoint$">
      <uap:VisualElements DisplayName="My App"
                          Description="WinUI 3 application"
                          BackgroundColor="transparent"
                          Square150x150Logo="Assets\Square150x150Logo.png"
                          Square44x44Logo="Assets\Square44x44Logo.png" />
    </Application>
  </Applications>

  <Capabilities>
    <Capability Name="internetClient" />
  </Capabilities>
</Package>
```

```bash
# Build MSIX package
dotnet publish -c Release -r win-x64
```

### Unpackaged Deployment

Unpackaged mode removes MSIX requirements. The app runs as a standard Win32 executable without app identity.

```xml
<!-- .csproj: enable unpackaged mode -->
<PropertyGroup>
  <WindowsPackageType>None</WindowsPackageType>
</PropertyGroup>
```

**Trade-offs:**

| Feature | MSIX Packaged | Unpackaged |
|---------|--------------|------------|
| App identity | Yes | No |
| Clean install/uninstall | Yes (Add/Remove Programs) | Manual |
| Auto-update | Yes (Store, App Installer) | Manual |
| Background tasks | Full support | Limited |
| Toast notifications | Full support | Requires COM registration |
| Widgets (Windows 11) | Yes | No |
| File type associations | Via manifest | Via registry |
| Distribution | Store, sideload, App Installer | xcopy, installer (MSI/EXE) |
| Startup time | Slightly slower (package verification) | Faster |

**When to choose unpackaged:**
- Internal enterprise tools with existing deployment infrastructure
- Apps that need xcopy deployment or integration with existing MSI/EXE installers
- Quick prototypes where packaging overhead is unnecessary
- Apps that do not need Windows identity features


## Windows Integration

### App Lifecycle

WinUI 3 apps use the Windows App SDK activation and lifecycle model, distinct from UWP's `CoreApplication`.

```csharp
// Handle activation kinds (protocol, file, toast, etc.)
public partial class App : Application
{
    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        // Check for specific activation
        var activationArgs = AppInstance.GetCurrent().GetActivatedEventArgs();

        switch (activationArgs.Kind)
        {
            case ExtendedActivationKind.Protocol:
                var protocolArgs = (ProtocolActivatedEventArgs)activationArgs.Data;
                HandleProtocolActivation(protocolArgs.Uri);
                break;

            case ExtendedActivationKind.File:
                var fileArgs = (FileActivatedEventArgs)activationArgs.Data;
                HandleFileActivation(fileArgs.Files);
                break;

            default:
                // Normal launch
                break;
        }
    }
}
```

### Notifications

Toast notifications require the Windows App SDK notification APIs:

```csharp
using Microsoft.Windows.AppNotifications;
using Microsoft.Windows.AppNotifications.Builder;

// Register for notification activation
var notificationManager = AppNotificationManager.Default;
notificationManager.NotificationInvoked += OnNotificationInvoked;
notificationManager.Register();

// Send a toast notification
var builder = new AppNotificationBuilder()
    .AddText("Order Shipped")
    .AddText("Your order #12345 has shipped.")
    .AddButton(new AppNotificationButton("Track")
        .AddArgument("action", "track")
        .AddArgument("orderId", "12345"));

AppNotificationManager.Default.Show(builder.BuildNotification());
```

### Widgets (Windows 11)

Widgets require Windows 11 (build 22000+) and MSIX packaged deployment. The implementation involves creating a widget provider that implements `IWidgetProvider` and registering it in the MSIX manifest.

**Key steps:**
1. Implement `IWidgetProvider` interface (methods: `CreateWidget`, `DeleteWidget`, `OnActionInvoked`, `OnWidgetContextChanged`, `OnCustomizationRequested`, `Activate`, `Deactivate`)
2. Register the provider as a COM class in the MSIX manifest
3. Define widget templates using Adaptive Cards JSON format
4. Return updated widget content from provider methods

See the [Windows App SDK Widget documentation](https://learn.microsoft.com/en-us/windows/apps/develop/widgets/widget-providers) for the complete interface contract and manifest registration.

### Taskbar Integration

Taskbar progress in WinUI 3 requires Win32 COM interop via the `ITaskbarList3` interface. Unlike UWP which had a managed `TaskbarManager`, WinUI 3 does not expose a managed wrapper.

```csharp
// Taskbar progress requires COM interop in WinUI 3
// Use CsWin32 source generator or manual P/Invoke for ITaskbarList3
// 1. Add CsWin32: <PackageReference Include="Microsoft.Windows.CsWin32" Version="0.3.*" />
// 2. Add to NativeMethods.txt: ITaskbarList3
// See: https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nn-shobjidl_core-itaskbarlist3
```


## UWP Migration

Migrating from UWP to WinUI 3 involves namespace changes, API replacements, and project restructuring.

### Namespace Changes

| UWP Namespace | WinUI 3 Namespace |
|---------------|-------------------|
| `Windows.UI.Xaml` | `Microsoft.UI.Xaml` |
| `Windows.UI.Xaml.Controls` | `Microsoft.UI.Xaml.Controls` |
| `Windows.UI.Xaml.Media` | `Microsoft.UI.Xaml.Media` |
| `Windows.UI.Xaml.Input` | `Microsoft.UI.Xaml.Input` |
| `Windows.UI.Composition` | `Microsoft.UI.Composition` |
| `Windows.UI.Text` | `Microsoft.UI.Text` |
| `Windows.UI.Colors` | `Microsoft.UI.Colors` |

**Keep as-is:** `Windows.Storage`, `Windows.Networking`, `Windows.Security`, `Windows.ApplicationModel`, `Windows.Devices` -- these WinRT APIs remain in the `Windows.*` namespace.

### API Replacements

| UWP API | WinUI 3 Replacement |
|---------|---------------------|
| `CoreApplication.MainView` | `App.MainWindow` (track your own window reference) |
| `CoreDispatcher.RunAsync` | `DispatcherQueue.TryEnqueue` |
| `Window.Current` | Track window reference manually in App class |
| `ApplicationView.Title` | `window.Title = "..."` |
| `CoreWindow.GetForCurrentThread` | Not available; use `InputKeyboardSource` for keyboard APIs |
| `SystemNavigationManager.BackRequested` | `NavigationView.BackRequested` |

### Migration Steps

1. **Create a new WinUI 3 project** using the Windows App SDK template
2. **Copy source files** and update namespaces (`Windows.UI.Xaml` to `Microsoft.UI.Xaml`)
3. **Update XAML namespaces** in all `.xaml` files
4. **Replace deprecated APIs** (see table above)
5. **Migrate packaging** from `.appxmanifest` UWP format to Windows App SDK format
6. **Update NuGet packages** to Windows App SDK-compatible versions
7. **Test Windows integration** features (notifications, background tasks, file associations)

For comprehensive migration path guidance across frameworks, see `references/wpf-migration.md`.

**UWP .NET 9 preview path:** Microsoft announced UWP support on .NET 9 as a preview. This allows UWP apps to use modern .NET without migrating to WinUI 3. Evaluate this path if full WinUI migration is too costly but you need modern .NET runtime features.


## Agent Gotchas

1. **Do not confuse UWP XAML with WinUI 3 XAML.** The root namespace changed from `Windows.UI.Xaml` to `Microsoft.UI.Xaml`. Code using `Windows.UI.Xaml.*` types will not compile in WinUI 3 projects.
2. **Do not use `Window.Current`.** WinUI 3 does not have a static `Window.Current` property. Track your window reference manually in the `App` class and pass it via DI or a static property.
3. **Do not use `CoreDispatcher`.** Replace `CoreDispatcher.RunAsync()` with `DispatcherQueue.TryEnqueue()`. `CoreDispatcher` is a UWP API not available in WinUI 3.
4. **Do not assume MSIX is required.** WinUI 3 supports unpackaged deployment via `<WindowsPackageType>None</WindowsPackageType>`. Only use MSIX when you need app identity, Store distribution, or Windows integration features that require it.
5. **Do not forget `x:Bind` defaults to `OneTime`.** Unlike `{Binding}` which defaults to `OneWay`, `x:Bind` defaults to `OneTime`. Always specify `Mode=OneWay` or `Mode=TwoWay` for properties that change after initial binding.
6. **Do not target Windows 10 builds below 19041.** Windows App SDK 1.6+ requires a minimum of build 19041 (version 2004). Targeting lower builds causes runtime failures.
7. **Do not use Widgets or Mica in unpackaged apps.** These features require MSIX packaged deployment with app identity. Attempting to use them in unpackaged mode fails silently or throws.
8. **Do not mix CommunityToolkit.Mvvm with manual INotifyPropertyChanged.** Use `[ObservableProperty]` consistently. Mixing source-generated and hand-written implementations causes subtle binding bugs.
9. **Do not forget the Host builder lifecycle.** Call `_host.StartAsync()` in `OnLaunched` and `_host.StopAsync()` when the window closes. Forgetting lifecycle management causes DI-registered `IHostedService` instances to never start or stop.


## Prerequisites

- .NET 8.0+ with Windows desktop workload
- Windows App SDK 1.6+ (auto-referenced via `UseWinUI`)
- Windows 10 version 2004 (build 19041) or later
- Visual Studio 2022+ with Windows App SDK workload, or VS Code with C# Dev Kit
- For widgets: Windows 11 (build 22000+)


## References

- [WinUI 3 Documentation](https://learn.microsoft.com/en-us/windows/apps/winui/winui3/)
- [Windows App SDK](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/)
- [CommunityToolkit.Mvvm](https://learn.microsoft.com/en-us/dotnet/communitytoolkit/mvvm/)
- [UWP to WinUI Migration](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/migrate-to-windows-app-sdk/)
- [MSIX Packaging](https://learn.microsoft.com/en-us/windows/msix/)
- [Windows App SDK Deployment Guide](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/deploy-overview)
