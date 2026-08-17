# WPF Migration

Context-dependent migration guidance for Windows desktop applications. Covers WPF .NET Framework to .NET 8+, WPF to WinUI 3 (Windows-only modernization), WPF to Uno Platform (cross-platform), WinForms .NET Framework to .NET 8+, UWP to WinUI 3, UWP to Uno Platform (cross-ref), and a decision matrix for choosing the right migration target based on project constraints.

**Version assumptions:** .NET 8.0+ baseline (current LTS). `dotnet-upgrade-assistant` for automated migration. .NET 9 features explicitly marked where applicable.

## Migration Path Overview

Choose a migration path based on your current framework and target goals. Each path has different trade-offs in effort, risk, and capability gain.

| Current | Target | Effort | Risk | When to Choose |
|---|---|---|---|---|
| WPF .NET Framework | WPF .NET 8+ | Low-Medium | Low | Modernize runtime, keep existing UI |
| WPF .NET Framework | WinUI 3 | High | Medium | Modern Windows UI, touch/pen, Fluent |
| WPF .NET Framework | Uno Platform | High | Medium-High | Cross-platform needed |
| WinForms .NET Framework | WinForms .NET 8+ | Low | Low | Modernize runtime, keep existing UI |
| UWP | WinUI 3 | Medium | Medium | Stay Windows-only, modern runtime |
| UWP | Uno Platform | Medium-High | Medium | Cross-platform needed from UWP |


## WPF .NET Framework to .NET 8+

The lowest-risk migration path. Keeps your existing XAML and code-behind intact while moving to modern .NET with better performance, DI support, and side-by-side deployment.

### Using dotnet-upgrade-assistant

The .NET Upgrade Assistant automates the bulk of the migration:

```bash
# Install the upgrade assistant
dotnet tool install -g upgrade-assistant

# Analyze the project first (non-destructive)
upgrade-assistant analyze MyWpfApp.sln

# Upgrade the project
upgrade-assistant upgrade MyWpfApp.sln
```

**What the upgrade assistant handles:**
- `.csproj` conversion from legacy format to SDK-style
- `packages.config` to `PackageReference` migration
- TFM change to `net8.0-windows`
- `AssemblyInfo.cs` properties moved to `.csproj`
- Common API replacements and namespace updates

**What requires manual work:**
- `App.config` settings migration to `appsettings.json` or Host builder configuration
- `Settings.settings` / `My.Settings` (VB.NET) migration
- Third-party control library updates (check vendor .NET 8 compatibility)
- WCF client references (use `CoreWCF` or migrate to gRPC/REST)
- COM interop adjustments (syntax differences in `System.Runtime.InteropServices`)
- Custom MSBuild targets and build scripts

### API Compatibility

Most WPF APIs are identical between .NET Framework and .NET 8+. Key differences:

| Area | .NET Framework | .NET 8+ | Action |
|---|---|---|---|
| Clipboard | `Clipboard.SetText()` | Same API | No change |
| Printing | `PrintDialog`, `PrintVisual` | Same API | No change |
| BitmapEffect | Deprecated (software-rendered) | Removed | Use `Effect` / `ShaderEffect` |
| `DrawingContext.PushEffect` | Available | Removed | Use `ShaderEffect` |
| XPS documents | `System.Windows.Xps` | Requires NuGet package | Add `System.Windows.Xps` PackageReference |
| Speech synthesis | `System.Speech` | Requires NuGet package | Add `System.Speech` PackageReference |

### NuGet Package Updates

After migration, update NuGet packages to .NET 8-compatible versions:

```bash
# List outdated packages
dotnet list package --outdated

# Update packages (one at a time for safer migration)
dotnet add package Newtonsoft.Json --version 13.*
dotnet add package MaterialDesignThemes --version 5.*
```

**Common package replacements:**
- `Unity` container -> `Microsoft.Extensions.DependencyInjection` (built-in)
- `Autofac` -> update to latest (supports .NET 8)
- `log4net` / `NLog` -> consider `Microsoft.Extensions.Logging` with Serilog or NLog provider
- `EntityFramework` (EF6) -> `Microsoft.EntityFrameworkCore` 8.x

### Breaking Changes Checklist

- **Default high-DPI behavior changed.** .NET 8 WPF enables `PerMonitorV2` DPI awareness by default (not `SystemAware` like .NET Framework).
- **Nullable reference types.** New projects enable NRT. Existing code may produce warnings. Suppress with `<Nullable>disable</Nullable>` initially, then fix incrementally.
- **Implicit usings.** New SDK-style projects enable implicit usings. May conflict with existing `using` statements. Disable with `<ImplicitUsings>disable</ImplicitUsings>` if needed.
- **Assembly loading.** `AssemblyLoadContext` replaces `AppDomain` for assembly isolation. Plugin architectures using `AppDomain.CreateDomain` need rework.
- **Runtime behavior.** .NET 8 GC is more aggressive with Gen0/Gen1 collections. Finalizer-dependent code may behave differently.

For post-migration WPF patterns (Host builder, MVVM Toolkit, modern C#), see `references/wpf-modern.md`.


## WPF to WinUI 3

Migrate when you need modern Windows-native UI: Fluent Design, touch/pen input, Windows 11 integration (widgets, Mica), or UWP-style APIs on modern .NET. This is a **partial rewrite** -- XAML concepts transfer but APIs and namespaces differ.

### When This Path Makes Sense

- Application is **Windows-only** and will stay Windows-only
- Need modern **Fluent Design** controls, touch/pen support, or Windows 11 features
- Team is willing to invest in **XAML rewrite** effort
- Application is **actively developed** with ongoing feature work (justifies the investment)

### When to Consider Alternatives

- If **cross-platform** is needed -> migrate to Uno Platform instead (WinUI XAML surface)
- If application is in **maintenance mode** -> migrate to WPF .NET 8+ instead (lower effort)
- If WPF Fluent theme (.NET 9+) is sufficient -> stay on WPF .NET 8+ with `ThemeMode = ThemeMode.System`

### XAML Differences

| WPF XAML | WinUI 3 XAML | Notes |
|---|---|---|
| `xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"` | Same URI (but resolves to `Microsoft.UI.Xaml` types, not `System.Windows`) | No xmlns change, but runtime types differ |
| `{Binding Path=Name}` | `{x:Bind Name, Mode=OneWay}` | Prefer `x:Bind` (compiled, type-safe) |
| `DataContext` binding | Code-behind property + `x:Bind` | `x:Bind` resolves against code-behind |
| `Window` inherits from `System.Windows.Window` | `Window` inherits from `Microsoft.UI.Xaml.Window` | Different base class and API |
| `UserControl` | `UserControl` (Microsoft.UI.Xaml namespace) | Same concept, different namespace |
| `Style` with `TargetType` | Same | Works the same way |
| `DataTemplate` | Needs `x:DataType` for `x:Bind` | Required for compiled bindings |
| `ContextMenu` | `MenuFlyout` | Different control type |
| `StatusBar` | No built-in equivalent | Use custom `CommandBar` or `InfoBar` |
| `RibbonControl` | No built-in equivalent | Use `NavigationView` + `CommandBar` |

### Migration Strategy

1. **Create a new WinUI 3 project** alongside the existing WPF project
2. **Migrate shared logic first** -- Models, Services, ViewModels (if using MVVM Toolkit, they work in both)
3. **Migrate views incrementally** -- start with simpler pages, then complex ones
4. **Replace WPF-specific controls** with WinUI equivalents (see table above)
5. **Update data binding** from `{Binding}` to `{x:Bind}` for compile-time safety
6. **Test Windows integration** features (notifications, lifecycle, file associations)
7. **Choose deployment model** -- MSIX (app identity) or unpackaged (xcopy)

For WinUI 3 patterns and project setup, see `references/winui.md`.


## WPF to Uno Platform

Migrate when you need cross-platform reach from a WPF codebase. Uno Platform uses the WinUI XAML API surface, so WPF XAML skills transfer partially, but the migration involves adapting to WinUI XAML patterns.

### When This Path Makes Sense

- Application needs to run on **multiple platforms** (Windows, macOS, Linux, Web, mobile)
- Team has **WPF/XAML expertise** that transfers to WinUI XAML surface
- Willing to invest in **cross-platform adaptation** (platform-specific behaviors, responsive layouts)

### When to Consider Alternatives

- If **Windows-only** -> migrate to WinUI 3 (simpler, no cross-platform overhead)
- If application is in **maintenance mode** -> migrate to WPF .NET 8+ (lowest effort)
- If team has **web skills** -> consider Blazor for web delivery

### Migration Approach

The migration from WPF to Uno Platform is similar to WPF to WinUI 3 (since Uno uses the WinUI API surface), with additional cross-platform considerations:

1. **Create an Uno Platform project** with the desired target platforms
2. **Migrate ViewModels and services** -- these are platform-independent
3. **Adapt XAML** to WinUI syntax (same changes as WPF to WinUI migration)
4. **Handle platform-specific features** using conditional compilation or Uno platform extensions
5. **Replace Windows-only APIs** with cross-platform alternatives (file dialogs, notifications, etc.)
6. **Test each target platform** -- rendering and behavior may differ across Skia and native targets

### Uno Extensions for Common Patterns

Uno Extensions provides cross-platform replacements for common WPF patterns:

| WPF Pattern | Uno Extensions Replacement |
|---|---|
| Custom navigation | `Uno.Extensions.Navigation` |
| Manual DI setup | `Uno.Extensions.DependencyInjection` (wraps MS DI) |
| `appsettings.json` config | `Uno.Extensions.Configuration` |
| Manual HTTP clients | `Uno.Extensions.Http` (typed clients with Refit) |
| Manual serialization | `Uno.Extensions.Serialization` |

For Uno Platform development patterns, see `references/uno-platform.md`. For per-target deployment guidance, see `references/uno-targets.md`.


## WinForms .NET Framework to .NET 8+

Similar to WPF migration but typically simpler due to WinForms' less complex project structure.

### Using dotnet-upgrade-assistant

```bash
# Analyze first
upgrade-assistant analyze MyWinFormsApp.sln

# Upgrade
upgrade-assistant upgrade MyWinFormsApp.sln
```

**What the upgrade assistant handles:**
- `.csproj` conversion to SDK-style with `<UseWindowsForms>true</UseWindowsForms>`
- TFM change to `net8.0-windows`
- `packages.config` to `PackageReference`
- `AssemblyInfo.cs` migration to project properties

**What requires manual work:**
- `App.config` / `Settings.settings` migration
- `My.Settings` (VB.NET) migration to modern configuration
- Third-party control library updates (some WinForms controls may lack .NET 8 support)
- Crystal Reports or other legacy reporting tools (evaluate alternatives)
- COM interop adjustments

### Designer Compatibility

WinForms designer files (`.Designer.cs`) generally migrate cleanly. The Visual Studio WinForms designer for .NET 8+ is fully supported.

**Known designer issues:**
- Custom designer serializers may need updates
- Some third-party controls may not render in the .NET 8 designer
- DPI-unaware designer mode available in .NET 9+ (`<ForceDesignerDPIUnaware>true</ForceDesignerDPIUnaware>`)

### Post-Migration Modernization

After migrating to .NET 8+, consider adopting modern patterns incrementally:
- **Add dependency injection** via Host builder (see `references/winforms-basics.md`)
- **Replace synchronous calls** with async/await
- **Enable high-DPI** with `PerMonitorV2` mode
- **Enable dark mode** (experimental in .NET 9+)

For WinForms .NET 8+ patterns, see `references/winforms-basics.md`.


## UWP to WinUI 3

UWP's natural migration target. WinUI 3 uses the same XAML API surface with namespace changes.

### Namespace Changes

The primary migration task is updating namespaces from `Windows.UI.*` to `Microsoft.UI.*`:

| UWP Namespace | WinUI 3 Namespace |
|---|---|
| `Windows.UI.Xaml` | `Microsoft.UI.Xaml` |
| `Windows.UI.Xaml.Controls` | `Microsoft.UI.Xaml.Controls` |
| `Windows.UI.Xaml.Media` | `Microsoft.UI.Xaml.Media` |
| `Windows.UI.Composition` | `Microsoft.UI.Composition` |
| `Windows.UI.Text` | `Microsoft.UI.Text` |

**Keep as-is:** `Windows.Storage`, `Windows.Networking`, `Windows.Security`, `Windows.ApplicationModel`, `Windows.Devices` -- these WinRT APIs remain unchanged.

### App Model Differences

| Concern | UWP | WinUI 3 |
|---|---|---|
| App lifecycle | `CoreApplication` + suspension | Windows App SDK `AppInstance` |
| Window management | `Window.Current` (singleton) | Track window references manually |
| Dispatcher | `CoreDispatcher.RunAsync` | `DispatcherQueue.TryEnqueue` |
| Background tasks | Built-in, requires package identity | Available with MSIX, limited without |
| File access | Broad capabilities via manifest | Standard Win32 file access + `StorageFile` |
| Store APIs | `Windows.Services.Store` | Same (still available) |

### Migration Steps

1. **Create a new WinUI 3 project** using the Windows App SDK template
2. **Copy source files** and update namespaces (`Windows.UI.Xaml` to `Microsoft.UI.Xaml`)
3. **Replace deprecated APIs** (`Window.Current` to manual tracking, `CoreDispatcher` to `DispatcherQueue`)
4. **Update MSIX manifest** from UWP format to Windows App SDK format
5. **Migrate capabilities** -- review and update capability declarations
6. **Update NuGet packages** to Windows App SDK-compatible versions
7. **Test Windows integration** -- notifications, background tasks, file associations may behave differently

**UWP .NET 9 preview path:** Microsoft announced UWP support on .NET 9 as a preview. If full WinUI 3 migration is too costly, this allows UWP apps to use modern .NET runtime features without migrating the UI framework.

For WinUI 3 development patterns, see `references/winui.md`.


## UWP to Uno Platform

When cross-platform reach is needed from a UWP codebase. Uno Platform implements the WinUI XAML API surface, making it the most natural cross-platform migration path for UWP.

Since Uno Platform uses the same WinUI XAML API surface that UWP XAML is based on, much of the UWP code transfers with fewer changes than migrating to other cross-platform frameworks:

- **XAML files** often work with minimal changes (Uno supports `x:Bind`, `x:Load`, etc.)
- **ViewModels and services** transfer directly (platform-independent code)
- **Windows-specific APIs** need cross-platform alternatives for non-Windows targets

### Key Considerations

- **Platform-specific code** using `Windows.*` APIs needs conditional compilation or abstraction for non-Windows targets
- **WinRT APIs** (sensors, geolocation, media capture) need Uno implementations or platform-specific alternatives
- **MSIX packaging** is Windows-only -- other platforms use their native distribution mechanisms

For Uno Platform development patterns, see `references/uno-platform.md`. For per-target deployment, see `references/uno-targets.md`.


## Decision Matrix

Use this matrix when deciding which migration path to take. The right choice depends on your specific constraints -- there is no universal "best" migration target.

### By Primary Goal

| Goal | Recommended Path | Alternative |
|---|---|---|
| Lowest risk, fastest migration | WPF/WinForms to .NET 8+ | -- |
| Modern Windows UI | WPF to WinUI 3 | WPF .NET 9+ with Fluent theme |
| Cross-platform from Windows app | WPF to Uno Platform | Rewrite critical paths in Blazor |
| Cross-platform from UWP | UWP to Uno Platform | UWP to WinUI 3 (stay Windows-only) |
| UWP modernization (Windows-only) | UWP to WinUI 3 | UWP on .NET 9 preview |
| Legacy WinForms modernization | WinForms to .NET 8+ | Gradual rewrite in Blazor or WPF |

### By Constraint

| Constraint | Best Path | Rationale |
|---|---|---|
| Limited budget/time | .NET 8+ migration (same framework) | Lowest effort, same codebase |
| Must stay Windows-only | WinUI 3 or WPF .NET 8+ | WinUI for modern UI; WPF for minimal change |
| Must go cross-platform | Uno Platform | Broadest reach with WinUI XAML surface |
| Large existing WPF codebase | WPF .NET 8+ first, then evaluate | Stabilize on modern runtime before UI rewrite |
| Existing UWP codebase | WinUI 3 (Windows) or Uno (cross-platform) | Closest API surface to existing code |
| Team has web skills | Blazor (rewrite) | Leverage web expertise for desktop/mobile |

### Staged Migration Strategy

For large applications, a staged approach reduces risk:

1. **Stage 1: Runtime migration** -- Move from .NET Framework to .NET 8+ (same UI framework). Validates compatibility, gains performance, enables modern NuGet packages.
2. **Stage 2: Modernize patterns** -- Adopt Host builder, DI, MVVM Toolkit, modern C#. See `references/wpf-modern.md` or `references/winforms-basics.md`.
3. **Stage 3: UI migration** (if needed) -- Migrate to WinUI 3, Uno Platform, or Blazor based on requirements. Only pursue if Stage 1 and 2 are stable.

This approach avoids the "big bang" rewrite risk and delivers incremental value at each stage.


## Agent Gotchas

1. **Do not recommend a single migration target as "the right choice" without understanding constraints.** Always present options with trade-offs. Budget, timeline, team expertise, and platform requirements all affect the decision.
2. **Do not skip the .NET 8+ runtime migration before suggesting a UI framework change.** Moving from .NET Framework to .NET 8+ (same UI framework) should be Stage 1. A WPF-to-WinUI migration from .NET Framework is significantly harder than from .NET 8+.
3. **Do not assume WPF is "legacy" and must be migrated away.** WPF on .NET 8+ is actively maintained with new features (Fluent theme in .NET 9+, performance improvements). Many applications are well-served by staying on WPF.
4. **Do not use `dotnet-upgrade-assistant` without running `analyze` first.** Always analyze before upgrading to understand the scope of changes and potential issues.
5. **Do not conflate WPF XAML with WinUI XAML.** While concepts are similar, the API surfaces differ (`Window`, `DataContext` vs `x:Bind`, `NavigationView` patterns). Migration requires more than namespace changes.
6. **Do not forget that UWP to WinUI 3 migration involves app model changes, not just namespace updates.** `Window.Current`, `CoreDispatcher`, `CoreApplication` APIs are all replaced with different patterns.
7. **Do not recommend Uno Platform for simple Windows-only apps.** If the application does not need cross-platform reach, WinUI 3 or WPF .NET 8+ is simpler and has lower maintenance overhead.


## References

- [.NET Upgrade Assistant](https://learn.microsoft.com/en-us/dotnet/core/porting/upgrade-assistant-overview)
- [WPF Migration to .NET](https://learn.microsoft.com/en-us/dotnet/desktop/wpf/migration/)
- [UWP to WinUI Migration](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/migrate-to-windows-app-sdk/)
- [WinForms Migration to .NET](https://learn.microsoft.com/en-us/dotnet/desktop/winforms/migration/)
- [Uno Platform Migration](https://platform.uno/docs/articles/howto-migrate-existing-code.html)
- [Windows App SDK](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/)
