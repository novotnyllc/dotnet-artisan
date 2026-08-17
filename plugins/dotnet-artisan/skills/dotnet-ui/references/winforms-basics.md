# WinForms Basics

WinForms on .NET 8+: updated project templates with Host builder and DI, high-DPI support with `PerMonitorV2`, dark mode via `Application.SetColorMode` (experimental in .NET 9, targeting finalization in .NET 11), when to use WinForms, modernization tips for migrating from .NET Framework, and common agent pitfalls.

**Version assumptions:** .NET 8.0+ baseline (current LTS). TFM `net8.0-windows`. .NET 9 features (dark mode experimental) explicitly marked. .NET 11 finalization targets noted.

## .NET 8+ Differences

WinForms on .NET 8+ is a significant modernization from .NET Framework WinForms, with an SDK-style project format, DI support, and updated APIs.

### New Project Template

```xml
<!-- MyWinFormsApp.csproj (SDK-style) -->
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>WinExe</OutputType>
    <TargetFramework>net8.0-windows</TargetFramework>
    <UseWindowsForms>true</UseWindowsForms>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="Microsoft.Extensions.Hosting" Version="8.*" />
  </ItemGroup>
</Project>
```

**Key differences from .NET Framework WinForms:**
- SDK-style `.csproj` (no `packages.config`, no `AssemblyInfo.cs`)
- Nullable reference types enabled by default
- Implicit usings enabled
- NuGet `PackageReference` format
- `Program.cs` uses top-level statements
- `dotnet publish` produces a single deployment artifact
- Side-by-side .NET installation (no machine-wide framework dependency)

### Host Builder Pattern

Modern WinForms apps use the generic host for dependency injection:

```csharp
// Program.cs
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

ApplicationConfiguration.Initialize();

var host = Host.CreateDefaultBuilder()
    .ConfigureServices((context, services) =>
    {
        // Services
        services.AddSingleton<IProductService, ProductService>();
        services.AddSingleton<ISettingsService, SettingsService>();

        // HTTP client
        services.AddHttpClient("api", client =>
        {
            client.BaseAddress = new Uri("https://api.example.com");
        });

        // Forms
        services.AddTransient<MainForm>();
        services.AddTransient<ProductDetailForm>();
    })
    .Build();

var mainForm = host.Services.GetRequiredService<MainForm>();
Application.Run(mainForm);
```

```csharp
// MainForm.cs -- constructor injection
public partial class MainForm : Form
{
    private readonly IProductService _productService;
    private readonly IServiceProvider _serviceProvider;

    public MainForm(IProductService productService, IServiceProvider serviceProvider)
    {
        _productService = productService;
        _serviceProvider = serviceProvider;
        InitializeComponent();
    }

    private async void btnLoad_Click(object sender, EventArgs e)
    {
        var products = await _productService.GetProductsAsync();
        dataGridProducts.DataSource = products.ToList();
    }

    private void btnDetails_Click(object sender, EventArgs e)
    {
        var detailForm = _serviceProvider.GetRequiredService<ProductDetailForm>();
        detailForm.ShowDialog();
    }
}
```

### ApplicationConfiguration.Initialize

.NET 8+ WinForms uses `ApplicationConfiguration.Initialize()` as the entry point, which consolidates multiple legacy configuration calls:

```csharp
// ApplicationConfiguration.Initialize() is equivalent to:
Application.EnableVisualStyles();
Application.SetCompatibleTextRenderingDefault(false);
Application.SetHighDpiMode(HighDpiMode.SystemAware);  // default; override below for PerMonitorV2
```


## High-DPI

WinForms on .NET 8+ has significantly improved high-DPI support. The recommended mode is `PerMonitorV2`, which handles per-monitor DPI changes automatically.

### Enabling PerMonitorV2

```csharp
// Program.cs -- set before ApplicationConfiguration.Initialize()
Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);
ApplicationConfiguration.Initialize();
// Note: SetHighDpiMode() called before Initialize() takes precedence
// over the default SystemAware mode set by Initialize().
```

Or configure via `runtimeconfig.json`:

```json
{
  "runtimeOptions": {
    "configProperties": {
      "System.Windows.Forms.ApplicationHighDpiMode": 3
    }
  }
}
```

**High-DPI modes:**

| Mode | Value | Behavior |
|------|-------|----------|
| `DpiUnaware` | 0 | No scaling; system bitmap-stretches the window |
| `SystemAware` | 1 | Scales to primary monitor DPI at startup (default in .NET 8) |
| `PerMonitor` | 2 | Adjusts when moved between monitors (basic) |
| `PerMonitorV2` | 3 | Full per-monitor scaling with non-client area support **(recommended)** |
| `DpiUnawareGdiScaled` | 4 | DPI-unaware but GDI+ text renders at native resolution |

### DPI-Unaware Designer Mode (.NET 9+)

.NET 9 introduces a DPI-unaware designer mode that prevents layout scaling issues in the Visual Studio WinForms designer. The designer renders at 96 DPI regardless of system DPI, preventing corrupted `.Designer.cs` files.

```xml
<!-- .csproj: opt in to DPI-unaware designer (.NET 9+) -->
<PropertyGroup>
  <ForceDesignerDPIUnaware>true</ForceDesignerDPIUnaware>
</PropertyGroup>
```

### Scaling Gotchas

- **Do not use absolute pixel sizes for controls.** Use `AutoScaleMode.Dpi` on forms and let the layout engine scale controls automatically.
- **Anchor and Dock layouts scale better than absolute positioning.** `TableLayoutPanel` and `FlowLayoutPanel` handle DPI changes more reliably than fixed-position controls.
- **Custom drawing (OnPaint) must use DPI-aware coordinates.** Scale drawing coordinates by `DeviceDpi / 96.0f` in `OnPaint` overrides.
- **Image resources need multiple resolutions.** Provide 1x, 1.5x, and 2x versions of icons and images, or use SVG-based rendering.

```csharp
// DPI-aware custom drawing
protected override void OnPaint(PaintEventArgs e)
{
    base.OnPaint(e);
    float scale = DeviceDpi / 96.0f;
    float fontSize = 12.0f * scale;
    using var font = new Font("Segoe UI", fontSize);
    e.Graphics.DrawString("Scaled text", font, Brushes.Black, 10 * scale, 10 * scale);
}
```


## Dark Mode

WinForms dark mode is **experimental in .NET 9** and is **targeting finalization in .NET 11**. It provides system-integrated dark mode for WinForms controls using the Windows dark mode APIs.

### Enabling Dark Mode (.NET 9+ Experimental)

```csharp
// Program.cs -- set before ApplicationConfiguration.Initialize()
Application.SetColorMode(SystemColorMode.Dark);
ApplicationConfiguration.Initialize();
```

Or follow system theme:

```csharp
// Follow system light/dark preference
Application.SetColorMode(SystemColorMode.System);
```

**SystemColorMode values:**

| Mode | Behavior |
|------|----------|
| `Classic` | Standard WinForms colors (no dark mode) |
| `System` | Follow Windows system light/dark theme setting |
| `Dark` | Force dark mode |

### Dark Mode Caveats

- **Experimental status:** The API surface may change before .NET 11 finalization. Do not depend on specific color values or rendering behavior in production.
- **Control coverage:** Not all controls support dark mode in .NET 9. Standard controls (Button, TextBox, Label, ListBox, DataGridView) have dark mode support. Third-party and custom-drawn controls may not render correctly.
- **Owner-drawn controls:** Controls using `DrawMode.OwnerDrawFixed` or custom `OnPaint` overrides must manually read `SystemColors` to respond to dark mode. They do not automatically inherit dark mode colors.
- **Windows version:** Dark mode requires Windows 10 version 1809 (build 17763) or later.
- **.NET 11 target:** Microsoft has indicated that WinForms visual styles (including dark mode) are targeting finalization in .NET 11. Plan for API stability after that release.

```csharp
// Owner-drawn controls must use SystemColors for dark mode compatibility
protected override void OnPaint(PaintEventArgs e)
{
    base.OnPaint(e);
    // Use SystemColors instead of hardcoded colors
    using var textBrush = new SolidBrush(SystemColors.ControlText);
    using var bgBrush = new SolidBrush(SystemColors.Control);
    e.Graphics.FillRectangle(bgBrush, ClientRectangle);
    e.Graphics.DrawString("Text", Font, textBrush, 10, 10);
}
```


## When to Use

WinForms is the right choice for specific scenarios. It is not a general-purpose UI framework for new customer-facing applications.

### Good Fit

- **Rapid prototyping:** Drag-and-drop designer for quick internal tools and proof-of-concept UIs
- **Internal enterprise tools:** Line-of-business forms, data entry, CRUD applications with DataGridView
- **Simple Windows-only utilities:** System tray apps, configuration tools, diagnostics dashboards
- **Existing WinForms maintenance:** Modernizing existing .NET Framework WinForms apps to .NET 8+
- **Data-heavy tabular UIs:** DataGridView with virtual mode handles millions of rows efficiently

### Not a Good Fit

- **New customer-facing applications:** Use WPF (rich Windows desktop), WinUI 3 (modern Windows), MAUI (cross-platform), or Blazor (web)
- **Complex custom UI:** WinForms controls are limited in styling; WPF or WinUI provide rich templating
- **Cross-platform requirements:** WinForms is Windows-only; use MAUI or Uno Platform
- **Accessibility-first applications:** WPF and WinUI have better accessibility APIs and screen reader support
- **Touch-optimized interfaces:** WinForms was designed for mouse/keyboard; WinUI or MAUI handle touch better

### Decision Guidance

| Scenario | Recommended Framework |
|----------|----------------------|
| Quick internal tool | WinForms |
| Data entry form (Windows) | WinForms or WPF |
| Modern Windows desktop app | WinUI 3 or WPF (.NET 9+ Fluent) |
| Cross-platform mobile + desktop | MAUI or Uno Platform |
| Cross-platform + web | Uno Platform or Blazor |
| Existing WinForms modernization | WinForms on .NET 8+ |

For the full framework decision tree, see `references/ui-chooser.md`.


## Modernization Tips

Tips for modernizing existing .NET Framework WinForms applications to .NET 8+.

### Add Dependency Injection

Replace static references and singletons with constructor injection via Host builder (see .NET 8+ Differences section above).

**Before (legacy pattern):**
```csharp
// Anti-pattern: static service references
public partial class MainForm : Form
{
    private void btnLoad_Click(object sender, EventArgs e)
    {
        var products = ProductService.Instance.GetProducts();
        dataGridProducts.DataSource = products;
    }
}
```

**After (modern pattern):**
```csharp
// Modern: constructor injection
public partial class MainForm : Form
{
    private readonly IProductService _productService;

    public MainForm(IProductService productService)
    {
        _productService = productService;
        InitializeComponent();
    }

    private async void btnLoad_Click(object sender, EventArgs e)
    {
        var products = await _productService.GetProductsAsync();
        dataGridProducts.DataSource = products.ToList();
    }
}
```

### Use Async Patterns

Replace synchronous blocking calls with async/await to keep the UI responsive:

```csharp
// Before: blocks UI thread
private void btnSave_Click(object sender, EventArgs e)
{
    var client = new HttpClient();
    var result = client.PostAsync(url, content).Result; // BLOCKS UI
    MessageBox.Show("Saved!");
}

// After: async keeps UI responsive
private async void btnSave_Click(object sender, EventArgs e)
{
    btnSave.Enabled = false;
    try
    {
        var result = await _httpClient.PostAsync(url, content);
        result.EnsureSuccessStatusCode();
        MessageBox.Show("Saved!");
    }
    catch (HttpRequestException ex)
    {
        MessageBox.Show($"Error: {ex.Message}");
    }
    finally
    {
        btnSave.Enabled = true;
    }
}
```

### Convert to .NET 8+

Use the .NET Upgrade Assistant for automated migration:

```bash
# Install upgrade assistant
dotnet tool install -g upgrade-assistant

# Analyze the project
upgrade-assistant analyze MyWinFormsApp.csproj

# Upgrade the project
upgrade-assistant upgrade MyWinFormsApp.csproj
```

**Common migration issues:**
- `App.config` settings need manual migration to `appsettings.json` or Host builder configuration
- `My.Settings` (VB.NET) and `Settings.settings` need manual migration
- Third-party controls may not have .NET 8 compatible versions
- Designer-generated code in `.Designer.cs` files usually migrates cleanly
- COM interop (`System.Runtime.InteropServices`) syntax may differ

### Adopt Modern C# Features

```csharp
// File-scoped namespaces
namespace MyApp.Forms;

// Null-conditional event invocation
PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(Value)));

// Collection expressions
var columns = new[] { "Name", "Price", "Category" };

// Primary constructors for services (C# 12)
public class ProductService(HttpClient httpClient) : IProductService
{
    public async Task<List<Product>> GetProductsAsync()
        => await httpClient.GetFromJsonAsync<List<Product>>("/products") ?? [];
}
```


## Agent Gotchas

1. **Do not recommend WinForms for new customer-facing applications.** WinForms is appropriate for internal tools, rapid prototyping, and data-centric utilities. For customer-facing apps, recommend WPF, WinUI 3, MAUI, or Blazor depending on requirements.
2. **Do not use deprecated WinForms APIs.** `Menu` (use `MenuStrip`), `MainMenu` (use `MenuStrip`), `ContextMenu` (use `ContextMenuStrip`), `StatusBar` (use `StatusStrip`), `ToolBar` (use `ToolStrip`), `DataGrid` (use `DataGridView`).
3. **Do not assume dark mode is production-ready.** Dark mode via `Application.SetColorMode` is experimental in .NET 9 and targeting finalization in .NET 11. API surface and rendering may change.
4. **Do not use `HighDpiMode.SystemAware` without testing multi-monitor scenarios.** `PerMonitorV2` is recommended for apps used on multi-monitor setups with different DPI settings.
5. **Do not block the UI thread with synchronous calls.** Use `async void` for event handlers and `async Task` for all other async methods. Never use `.Result` or `.Wait()` on the UI thread.
6. **Do not use `Control.Invoke` when `await` suffices.** In .NET 8+ WinForms, `await` automatically marshals back to the UI thread via `SynchronizationContext`. Manual `Invoke`/`BeginInvoke` is only needed when called from non-async code (timers, COM callbacks).
7. **Do not hardcode colors when dark mode is enabled.** Use `SystemColors` properties (e.g., `SystemColors.ControlText`, `SystemColors.Control`) in custom drawing and owner-drawn controls to respond correctly to theme changes.
8. **Do not forget to call `ApplicationConfiguration.Initialize()` before `Application.Run`.** Omitting it disables visual styles and high-DPI configuration.


## Prerequisites

- .NET 8.0+ with Windows desktop workload
- TFM: `net8.0-windows` (no Windows SDK version needed for WinForms)
- Visual Studio 2022+ with Windows desktop workload (for designer support)
- For dark mode: .NET 9+ (experimental), Windows 10 version 1809+
- For DPI-unaware designer: .NET 9+


## References

- [WinForms on .NET Documentation](https://learn.microsoft.com/en-us/dotnet/desktop/winforms/)
- [High DPI Support in WinForms](https://learn.microsoft.com/en-us/dotnet/desktop/winforms/high-dpi-support-in-windows-forms)
- [.NET Upgrade Assistant](https://learn.microsoft.com/en-us/dotnet/core/porting/upgrade-assistant-overview)
- [WinForms Dark Mode (.NET 9)](https://devblogs.microsoft.com/dotnet/winforms-dark-mode/)
- [Microsoft.Extensions.Hosting](https://learn.microsoft.com/en-us/dotnet/core/extensions/generic-host)
