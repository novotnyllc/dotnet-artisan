---
name: dotnet-ui
description: Builds .NET UI apps across Blazor (Server, WASM, Hybrid, Auto), MAUI (XAML, MVVM, Shell, Native AOT), Uno Platform (MVUX, Extensions, Toolkit), WPF (.NET 8+, Fluent theme), WinUI 3 (Windows App SDK, MSIX, Mica/Acrylic, adaptive layout), and WinForms (high-DPI, dark mode) with JS interop, accessibility (SemanticProperties, ARIA), localization (.resx, RTL), platform bindings (Java.Interop, ObjCRuntime), and framework selection. Spans 20 topic areas. Do not use for backend API design or CI/CD pipelines.
license: MIT
user-invocable: false
---

# dotnet-ui

## Overview

.NET UI development across Blazor, MAUI, Uno Platform, WPF, WinUI 3, and WinForms. This skill covers framework selection, component architecture, XAML patterns, MVVM, platform-specific deployment, accessibility, and localization. Each framework area has a dedicated companion file with deep guidance.

## Routing Table

| Topic | Keywords | Description | Companion File |
|-------|----------|-------------|----------------|
| Blazor patterns | hosting model, render mode, routing, streaming, prerender | Hosting models, render modes, routing, streaming, prerendering, AOT-safe patterns | references/blazor-patterns.md |
| Blazor components | lifecycle, state, JS interop, EditForm, QuickGrid | Lifecycle methods, state management, JS interop, EditForm, QuickGrid | references/blazor-components.md |
| Blazor auth | AuthorizeView, Identity UI, OIDC flows | Login/logout flows, AuthorizeView, Identity UI, OIDC, role and policy auth | references/blazor-auth.md |
| Blazor testing | bUnit, rendering, events, JS mocking | bUnit component rendering, events, cascading params, JS interop mocking | references/blazor-testing.md |
| MAUI development | project structure, XAML, MVVM, platform services | Project structure, XAML/MVVM patterns, Shell navigation, platform services | references/maui-development.md |
| MAUI AOT | iOS/Catalyst, Native AOT, trimming | iOS/Catalyst Native AOT pipeline, size/startup gains, library compatibility | references/maui-aot.md |
| MAUI testing | Appium, XHarness, platform validation | Appium 2.x device automation, XHarness, platform validation | references/maui-testing.md |
| Uno Platform | Extensions, MVUX, Toolkit, Hot Reload | Extensions ecosystem, MVUX pattern, Toolkit controls, Hot Reload | references/uno-platform.md |
| Uno targets | WASM, iOS, Android, macOS, Windows, Linux | Per-target guidance for WASM, iOS, Android, macOS, Windows, Linux | references/uno-targets.md |
| Uno MCP | tool detection, search-then-fetch, init | MCP tool detection, search-then-fetch workflow, init rules, fallback | references/uno-mcp.md |
| Uno testing | Playwright WASM, platform patterns | Playwright for WASM, platform-specific test patterns, runtime heads | references/uno-testing.md |
| WPF modern | Host builder, MVVM Toolkit, Fluent theme | Host builder, MVVM Toolkit, Fluent theme, performance, modern C# | references/wpf-modern.md |
| WPF migration | WPF/WinForms to .NET 8+, UWP to WinUI | WPF/WinForms to .NET 8+, UWP to WinUI, Upgrade Assistant | references/wpf-migration.md |
| WinUI | Windows App SDK, XAML, MSIX/unpackaged | Windows App SDK, x:Bind, x:Load, MSIX/unpackaged, UWP migration | references/winui.md |
| WinForms | high-DPI, dark mode, DI, modernization | High-DPI scaling, dark mode, DI patterns, modernization | references/winforms-basics.md |
| Accessibility | SemanticProperties, ARIA, AutomationPeer | SemanticProperties, ARIA attributes, AutomationPeer, per-platform testing | references/accessibility.md |
| Localization | .resx, IStringLocalizer, pluralization, RTL | .resx resources, IStringLocalizer, source generators, pluralization, RTL | references/localization.md |
| WinUI controls/styling | CommandBar, GridView, adaptive triggers, Mica, system brushes, icons | WinUI control selection, adaptive layout, theming, materials, typography | references/winui-controls-styling.md |
| UI chooser | framework selection decision tree | Decision tree across Blazor, MAUI, Uno, WinUI, WPF, WinForms | references/ui-chooser.md |
| Platform bindings | Java.Interop, ObjCRuntime, Android AAR, iOS XCFramework, Slim Binding | Custom native SDK bindings for Android and Apple platforms | references/platform-bindings.md |

## Scope

- Blazor (Server, WASM, Hybrid, Auto) hosting models and components
- MAUI mobile/desktop development and Native AOT
- Uno Platform cross-platform development and MCP integration
- WPF on .NET 8+ and migration from .NET Framework
- WinUI 3 / Windows App SDK
- WinForms modernization (high-DPI, dark mode, DI)
- Accessibility across all UI frameworks
- Localization (.resx, IStringLocalizer, pluralization, RTL)
- UI framework selection decision tree

## Out of scope

- Server-side auth middleware and API security configuration -- see [skill:dotnet-api]
- Non-UI testing strategy (unit, integration, E2E architecture) -- see [skill:dotnet-testing]
- Cross-framework UI test patterns (page objects, selectors) -- see [skill:dotnet-testing]
- Playwright browser automation (non-framework-specific) -- see [skill:dotnet-testing]
- Backend API patterns and architecture -- see [skill:dotnet-api]
- Native AOT compilation (non-MAUI) -- see [skill:dotnet-tooling]
- Console UI (Terminal.Gui, Spectre.Console) -- see [skill:dotnet-tooling]
