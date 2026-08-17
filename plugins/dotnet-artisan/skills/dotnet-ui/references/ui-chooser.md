# UI Chooser

UI framework selection decision tree for .NET applications. Covers Web (Blazor Server, Blazor WebAssembly, Blazor Hybrid), cross-platform (MAUI, Uno Platform, Avalonia), and Windows-only (WinUI 3, WPF, WinForms) frameworks. Presents structured trade-off analysis across five decision factors to help teams evaluate options based on their specific constraints.

## Decision Tree

Use this structured flow to narrow framework choices based on project constraints. Each branch presents trade-offs rather than definitive answers -- the right choice depends on the weight your team assigns to each factor.

### Step 1: Target Platforms

The most significant constraint. Identify which platforms the application must support.

```
Target platforms?
|
+-- Web browser only
|   --> Blazor (Server, WebAssembly, or Auto)
|       See "Blazor Hosting Model Selection" below
|
+-- Windows only
|   --> WinUI 3, WPF, or WinForms
|       See "Windows Framework Selection" below
|
+-- Mobile (iOS / Android)
|   +-- Also need desktop?
|   |   +-- Yes --> MAUI or Uno Platform
|   |   +-- No  --> MAUI or Uno Platform
|   |
|   +-- Also need web?
|       +-- Yes --> Uno Platform (WASM target) or Blazor Hybrid in MAUI
|       +-- No  --> MAUI or Uno Platform
|
+-- All platforms (web + mobile + desktop)
|   --> Uno Platform (broadest reach)
|       or Blazor Hybrid in MAUI (web UI, native shell)
|
+-- Desktop cross-platform (Windows + macOS + Linux)
    --> Uno Platform or Avalonia
        MAUI supports macOS/Windows but not Linux
```

### Step 2: Team Expertise

Match frameworks to existing team skills to reduce ramp-up time.

| Team Strength | Strong Fit | Moderate Fit | Steeper Curve |
|---|---|---|---|
| WPF / WinUI XAML | WPF, WinUI 3 | Uno Platform (WinUI XAML surface) | Blazor (Razor syntax) |
| Web (HTML/CSS/JS) | Blazor | Uno Platform (WASM target) | WPF, WinUI (XAML) |
| Xamarin.Forms | MAUI (direct successor) | Uno Platform | Blazor, WPF |
| C# but no UI framework | WinForms (simplest), Blazor | MAUI | WPF, WinUI (XAML learning curve) |
| React / Angular | Blazor WebAssembly (SPA model) | Uno Platform (WASM) | WPF, WinUI |

### Step 3: UI Complexity

Match the UI requirements to framework rendering capabilities.

| UI Need | Best Fit | Also Consider |
|---|---|---|
| Rich native Windows UI (custom controls, animations) | WinUI 3, WPF | Uno Platform (WinUI surface) |
| Web-style layouts (responsive, CSS-based) | Blazor | Uno Platform (Skia rendering) |
| Simple data-entry forms, internal tools | WinForms | Blazor (Static SSR), WPF |
| Pixel-perfect cross-platform UI | Uno Platform (Skia rendering) | Avalonia |
| Platform-native look per OS | MAUI (native controls) | Uno Platform (native mode) |
| Embedded web content in desktop/mobile app | Blazor Hybrid in MAUI | Blazor Hybrid in WPF/WinForms |

### Step 4: Performance Needs

Framework rendering architecture affects performance characteristics.

| Performance Factor | WinUI 3 | WPF | WinForms | Blazor Server | Blazor WASM | MAUI | Uno Platform |
|---|---|---|---|---|---|---|---|
| Startup time | Fast | Fast | Fast | Fast (server) | Slow (download) | Moderate | Moderate |
| Rendering | DirectX (native) | DirectX (managed) | GDI+ | Server-side HTML | Browser DOM | Platform-native | Skia or native |
| AOT support | N/A (Windows) | N/A (Windows) | N/A (Windows) | N/A (server) | Yes (.NET 8+) | Yes (required on iOS) | Yes (WASM) |
| GPU acceleration | Yes | Yes | Limited | N/A | Browser GPU | Platform GPU | Skia GPU |
| Memory per user | Local only | Local only | Local only | Server circuit | Browser sandbox | Local only | Local only |
| Offline capable | Yes | Yes | Yes | No | Yes | Yes | Yes (native targets) |

### Step 5: Migration Path

If modernizing an existing application, the source framework constrains viable targets.

| Current Framework | Natural Target | Alternative Target | Decision Factors |
|---|---|---|---|
| UWP | WinUI 3 | Uno Platform | Windows-only: WinUI 3. Cross-platform needed: Uno Platform. |
| Xamarin.Forms | MAUI | Uno Platform | Direct API successor: MAUI. Broader platform reach: Uno Platform. |
| WPF (.NET Framework) | WPF on .NET 8+ | WinUI 3 or Uno Platform | Minimal risk: WPF .NET 8+. Modern UI: WinUI 3. Cross-platform: Uno Platform. |
| WinForms (.NET Framework) | WinForms on .NET 8+ | Blazor or WPF | Minimal risk: WinForms .NET 8+. Better UI: WPF. Web delivery: Blazor. |
| ASP.NET MVC / Razor Pages | Blazor (Static SSR) | Stay on Razor Pages | Interactive needs: Blazor. Content-heavy: Razor Pages is still valid. |
| React / Angular SPA | Blazor WebAssembly | Keep existing SPA | .NET-only team: Blazor. Existing JS team: keep SPA. |


## Blazor Hosting Model Selection

When Blazor is the target, select a hosting model based on interactivity needs, deployment constraints, and scale.

| Concern | Static SSR | InteractiveServer | InteractiveWebAssembly | InteractiveAuto | Blazor Hybrid |
|---|---|---|---|---|---|
| Interactivity | Forms only | Full | Full (after download) | Full | Full (native) |
| Server required | Yes (render) | Yes (persistent circuit) | Static file host only | Yes (initial), then static | No |
| Offline | No | No | Yes | Partial | Yes |
| Scalability | High | Limited by circuits | High | High (after WASM) | N/A (local) |
| First paint | Fast | Fast | Slow (WASM download) | Fast (Server first) | Instant |
| SEO | Yes | Prerender | Prerender | Prerender | N/A |
| Best for | Content sites, simple forms | Dashboards, LOB apps | Public apps, offline PWAs | Best of both worlds | Desktop/mobile with web UI |

For detailed Blazor patterns, see `references/blazor-patterns.md`.


## Windows Framework Selection

When the application targets Windows only, choose based on UI richness, team expertise, and modernization goals.

### Comparison Table

| Concern | WinUI 3 | WPF (.NET 8+) | WinForms (.NET 8+) |
|---|---|---|---|
| UI paradigm | Modern XAML, Fluent Design | Classic XAML, optional Fluent (.NET 9+) | Designer-driven, drag-and-drop |
| Rendering | DirectX (Windows App SDK) | DirectX (WPF layer) | GDI+ |
| MVVM support | CommunityToolkit.Mvvm | CommunityToolkit.Mvvm, mature ecosystem | Possible but not idiomatic |
| DI / Host builder | Yes | Yes | Yes (.NET 8+) |
| High-DPI | Native | Improved in .NET 8+ | PerMonitorV2 (requires config) |
| Dark mode | Native Fluent | Application.ThemeMode (.NET 9+) | Experimental (.NET 9+) |
| Touch / pen | Full support | Basic support | Limited |
| Learning curve | Moderate (XAML) | Moderate (XAML) | Low |
| Maturity | Newer (2021+) | Very mature (2006+) | Very mature (2002+) |
| UWP migration path | Direct | Indirect (XAML differences) | N/A |

### When to Choose Each

**WinUI 3** -- best for new Windows-native applications that need modern Fluent Design, touch/pen input, and the latest Windows integration (widgets, notifications, Mica). Requires Windows 10 2004+. See `references/winui.md`.

**WPF on .NET 8+** -- best for teams with existing WPF expertise, applications that need the rich WPF control ecosystem, or projects migrating from WPF on .NET Framework. Fluent theme available in .NET 9+. See `references/wpf-modern.md`.

**WinForms on .NET 8+** -- best for rapid prototyping, internal tools, simple CRUD forms, and Windows utilities where development speed matters more than UI polish. Simplest learning curve. See `references/winforms-basics.md`.


## Cross-Platform Framework Selection

When the application must run on multiple platforms, compare reach, rendering model, and API surface.

### Comparison Table

| Concern | MAUI | Uno Platform | Avalonia |
|---|---|---|---|
| Target platforms | iOS, Android, macOS, Windows, Tizen | iOS, Android, macOS, Windows, Linux, Web (WASM) | iOS, Android, macOS, Windows, Linux, Web (WASM) |
| UI rendering | Platform-native controls | Skia (pixel-perfect) or platform-native | Skia (pixel-perfect) |
| XAML dialect | MAUI XAML (Xamarin.Forms successor) | WinUI XAML surface | Avalonia XAML (WPF-inspired) |
| Hot Reload | XAML + C# Hot Reload | XAML + C# Hot Reload | XAML Hot Reload |
| Maintainer | Microsoft (first-party) | Uno Platform (open source, commercial support) | Community (open source, commercial support) |
| Ecosystem | NuGet + MAUI Community Toolkit | NuGet + Uno Toolkit + Uno Extensions | NuGet + Avalonia community |
| Blazor Hybrid | Built-in (BlazorWebView) | Supported | Not built-in |
| Linux desktop | Not supported | Supported (Skia + GTK/Framebuffer) | Supported |
| Web (WASM) | Not supported | Supported | Supported (browser) |
| Migration from | Xamarin.Forms (direct) | UWP (direct WinUI surface) | WPF (similar XAML) |

### When to Choose Each

**MAUI** -- best for mobile-first apps targeting iOS and Android with optional Windows/macOS support. Platform-native controls provide OS-native look and feel. Direct migration path from Xamarin.Forms. See `references/maui-development.md`.

**Uno Platform** -- best for apps that need the broadest platform reach (including Linux and Web) with a single XAML codebase. Uses WinUI XAML API surface, making it a natural path for UWP or WinUI teams going cross-platform. See `references/uno-platform.md`.

**Avalonia** -- community-driven cross-platform framework with WPF-inspired XAML. Strong Linux desktop support. Consider when WPF-style development is preferred and community-maintained tooling is acceptable. Not owned by this plugin -- see [Avalonia documentation](https://docs.avaloniaui.net/) for details.


## Trade-Off Summary Matrix

A consolidated view across all frameworks for quick reference.

| Framework | Platforms | Rendering | XAML | Offline | AOT | Best For |
|---|---|---|---|---|---|---|
| Blazor Server | Web | Server HTML | Razor | No | N/A | LOB apps, dashboards |
| Blazor WASM | Web | Browser DOM | Razor | Yes | Yes | Public web apps, PWAs |
| Blazor Hybrid | Mobile + Desktop | WebView | Razor | Yes | Partial | Web UI in native shell |
| MAUI | Mobile + Desktop | Native | MAUI XAML | Yes | iOS required | Mobile-first apps |
| Uno Platform | All | Skia / Native | WinUI XAML | Yes | WASM | Broadest reach |
| Avalonia | Desktop + Mobile | Skia | Avalonia XAML | Yes | Partial | Linux desktop, WPF teams |
| WinUI 3 | Windows | DirectX | WinUI XAML | Yes | N/A | Modern Windows apps |
| WPF | Windows | DirectX | WPF XAML | Yes | N/A | Mature Windows apps |
| WinForms | Windows | GDI+ | None (designer) | Yes | N/A | Internal tools, prototypes |


## Common Decision Scenarios

Structured guidance for frequently encountered situations. Each scenario presents the trade-offs rather than a single answer.

**Scenario: New internal business application (Windows-only users)**
- Quick delivery, minimal UI: WinForms
- Rich UI with data visualization: WPF or WinUI 3
- Web deployment preferred: Blazor Server (InteractiveServer)
- Future cross-platform possibility: Uno Platform or Blazor

**Scenario: Customer-facing mobile app**
- iOS + Android, native look: MAUI
- iOS + Android + Web: Uno Platform or Blazor Hybrid in MAUI
- Existing web team: Blazor Hybrid in MAUI

**Scenario: Modernizing a legacy .NET Framework WPF application**
- Minimal disruption: Migrate WPF to .NET 8+ (same XAML, modern runtime)
- Modern UI refresh (Windows-only): Migrate to WinUI 3
- Cross-platform needed: Migrate to Uno Platform (WinUI XAML surface)
- Web delivery needed: Rewrite critical flows in Blazor

**Scenario: Public-facing web application**
- Content-heavy, SEO: Blazor Static SSR
- Interactive SPA: Blazor WebAssembly or InteractiveAuto
- Real-time dashboards: Blazor Server (InteractiveServer)

**Scenario: Desktop application targeting Windows, macOS, and Linux**
- Pixel-perfect UI: Uno Platform (Skia) or Avalonia
- MAUI does not support Linux desktop


## Agent Gotchas

1. **Do not recommend a single framework as "the best."** Every framework has trade-offs. Present options with trade-offs and let the team decide based on their constraints.
2. **Do not recommend WinForms for new customer-facing applications.** WinForms is suitable for internal tools and prototypes but lacks modern UI capabilities for customer-facing products.
3. **Do not confuse MAUI with Uno Platform target coverage.** MAUI does not support Linux or Web (WASM). Uno Platform does. Verify the required platform list before recommending.
4. **Do not assume Blazor WebAssembly works offline by default.** WASM runs in the browser but offline support requires explicit PWA configuration (service worker, caching strategy).
5. **Do not conflate Avalonia with a Microsoft-supported framework.** Avalonia is community-maintained. It has commercial support options but is not a Microsoft product.
6. **Do not suggest migrating UWP directly to WPF.** UWP's natural migration target is WinUI 3 (same XAML API surface). WPF uses a different XAML dialect.
7. **Do not overlook Blazor Hybrid as a cross-platform option.** Blazor Hybrid in MAUI allows web UI skills to apply to mobile/desktop apps. It is a viable alternative to learning native XAML.
8. **Do not assume WPF is legacy.** WPF on .NET 8+ is actively maintained with new features (Fluent theme in .NET 9+, performance improvements). It remains a strong choice for Windows desktop.


## References

- [Blazor Overview](https://learn.microsoft.com/en-us/aspnet/core/blazor/)
- [.NET MAUI Overview](https://learn.microsoft.com/en-us/dotnet/maui/what-is-maui)
- [Uno Platform Documentation](https://platform.uno/docs/articles/intro.html)
- [WinUI 3 Overview](https://learn.microsoft.com/en-us/windows/apps/winui/winui3/)
- [WPF Overview](https://learn.microsoft.com/en-us/dotnet/desktop/wpf/)
- [WinForms Overview](https://learn.microsoft.com/en-us/dotnet/desktop/winforms/)
- [Avalonia UI](https://docs.avaloniaui.net/)
- [Choose Your .NET UI](https://learn.microsoft.com/en-us/dotnet/desktop/wpf/migration/?)
