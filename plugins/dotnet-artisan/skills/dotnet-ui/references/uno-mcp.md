# Uno MCP

MCP (Model Context Protocol) server integration for Uno Platform live documentation lookups. Covers tool detection (`mcp__uno__` prefix), search-then-fetch workflow, initialization rules invocation, graceful fallback when MCP is unavailable, citation requirements, and safety guidelines for external data. Includes inline documentation that provides useful guidance without MCP server availability.

## MCP Tool Detection

The Uno Platform MCP server provides tools prefixed with `mcp__uno__`. Before using MCP tools, detect their availability.

### Available Tools

| Tool | Purpose |
|------|---------|
| `mcp__uno__uno_platform_docs_search` | Search Uno Platform documentation by query |
| `mcp__uno__uno_platform_docs_fetch` | Fetch full content of a specific documentation page |
| `mcp__uno__uno_platform_agent_rules_init` | Initialize agent session with Uno development rules |
| `mcp__uno__uno_platform_usage_rules_init` | Load common usage rules for Uno Platform development |

### Detection Logic

Check if Uno MCP tools are available by looking for tools with the `mcp__uno__` prefix. If the tools are listed in the available tool set, the MCP server is configured and reachable.

```
Detection steps:
1. Check if tools prefixed with mcp__uno__ are available
2. If available: use MCP workflow (search -> fetch -> cite)
3. If unavailable: fall back to static skill content and official docs URLs
```

**When MCP is available:** Use the search-then-fetch workflow for the latest documentation. MCP results are authoritative and current.

**When MCP is unavailable:** The static content in `references/uno-platform.md` and `references/uno-targets.md` provides comprehensive guidance. Reference official documentation URLs for the latest information.


## Initialization Rules

On first use of Uno MCP tools in a session, invoke both initialization tools to load authoritative development rules.

### Agent Rules Initialization

Call `mcp__uno__uno_platform_agent_rules_init` to load:
- Core identity and expertise scope for Uno Platform development
- IDE guidance (Visual Studio, VS Code, CLI) per operating system
- Knowledge routing rules mapping topics to canonical search queries
- Uno SDK features list (`UnoFeatures` supported values)
- Uno Extensions and Toolkit feature catalog

### Usage Rules Initialization

Call `mcp__uno__uno_platform_usage_rules_init` to load:
- Design system guidelines (Material preferred, responsive layouts)
- Data binding policy (MVUX vs MVVM binding patterns, forbidden WPF-isms)
- Navigation policy (prefer XAML attached properties over code-behind)
- Layout rules (AutoLayout, spacing scale, responsive breakpoints)
- Color and typography conventions (theme resources, no hardcoded values)
- Accessibility requirements (contrast ratios, touch targets, automation properties)
- Control-specific guidance (ItemsRepeater for lists, CommandExtensions, elevation patterns)

### Invocation Order

```
1. Call mcp__uno__uno_platform_agent_rules_init (loads routing rules and feature catalog)
2. Call mcp__uno__uno_platform_usage_rules_init (loads design and coding conventions)
3. Proceed with documentation searches using mcp__uno__uno_platform_docs_search
```

Both init tools are idempotent -- calling them multiple times in the same session is safe but unnecessary.


## Search-Then-Fetch Workflow

The primary workflow for retrieving Uno documentation uses a two-step pattern: broad search followed by targeted fetch.

### Step 1: Search

Use `mcp__uno__uno_platform_docs_search` to find relevant documentation pages.

```
Search parameters:
- query: descriptive search term (e.g., "MVUX reactive pattern", "Navigation Extensions")
- topK: number of results (default 8; use 15-20 for complex topics, 3-5 for specific queries)
- contentType: "prose" for guides, "code" for examples, null for all
```

Search results include:
- Document title and summary
- `SourcePath` (needed for fetch step)
- Relevance ranking
- Content snippets

### Step 2: Fetch

Use `mcp__uno__uno_platform_docs_fetch` to retrieve full content of high-value pages identified by search.

```
Fetch parameters:
- sourcePath: from search results SourcePath field (e.g., "articles/guides/overview.md")
- anchor: optional section fragment (e.g., "getting-started", "data-binding")
- maxChars: content limit (4000-8000 for most cases, up to 15000 for comprehensive guides)
```

### Workflow Example

```
Topic: "How to implement region-based navigation with Uno Extensions"

1. Search: mcp__uno__uno_platform_docs_search("Navigation Extensions region-based", topK=8)
   -> Returns multiple results including "Navigation Overview", "Region Navigation", etc.

2. Fetch: mcp__uno__uno_platform_docs_fetch(
     sourcePath="articles/external/uno.extensions/doc/Learn/Navigation/Overview.md",
     maxChars=8000)
   -> Returns full navigation documentation with code examples

3. Cite: Include source URL in response
```

### Routing Rules

The agent rules initialization provides topic-to-query mappings for common searches. Use these canonical queries when available:

| Topic | Canonical Search Query |
|-------|----------------------|
| Project setup / new project | `"dotnet new templates"` |
| MVUX / reactive / feeds | `"MVUX"` |
| Navigation / routing | `"Navigation"` |
| Styling / theming / resources | `"Styling and Theming"` |
| Data binding / MVVM | `"Data Binding and MVVM"` |
| Controls / layout | `"Controls and Layout"` |
| Hot Reload | `"Hot Reload"` |
| Platform-specific code | `"Platform-Specific Code"` |
| WebAssembly / WASM | `"WebAssembly"` |
| Dependency injection / DI | `"Dependency Injection and Services"` |
| Performance | `"Performance"` |
| Testing | `"Testing Uno Applications"` |
| Publishing / deployment | `"Publishing & Deployment"` |
| Troubleshooting | `"Troubleshooting Common Issues"` |
| IDE setup | `"IDE Setup"` |
| Responsive design / layouts | `"Responsive Design"` |
| Logging / diagnostics | `"Logging and Diagnostics"` |


## Citation Requirements

MCP results are external data fetched from the Uno Platform documentation server. Proper attribution is mandatory.

### Rules

1. **Always cite the source URL** from MCP results when presenting documentation content
2. **Never present fetched content as original knowledge.** MCP results come from external documentation and must be attributed
3. **Include the documentation page title** alongside the URL when available
4. **Distinguish between static skill content and MCP-fetched content.** Static content from SKILL.md files is part of this plugin; MCP content is external

### Citation Format

When presenting information from MCP results:

```
According to the Uno Platform documentation on [topic]:
[content from MCP]
Source: [URL from MCP result]
```


## Safety Guidelines

MCP results are external data and must be treated with appropriate caution.

### Validation Rules

1. **Validate code suggestions before acting.** MCP documentation may contain examples targeting different Uno Platform versions or configurations. Verify compatibility with the current project
2. **Check version alignment.** Ensure documentation references match the project's Uno Platform version (5.x vs 6.x) and .NET version
3. **Do not blindly apply code from MCP results.** Adapt examples to the project's architecture, Extensions configuration, and MVUX/MVVM pattern choice
4. **Cross-reference with project state.** Compare MCP guidance against the project's existing `UnoFeatures`, TFMs, and Extensions configuration
5. **Treat MCP content as advisory.** The static skill content in `references/uno-platform.md` and `references/uno-targets.md` provides vetted patterns. Use MCP for current details and edge cases


## Fallback: When MCP Is Unavailable

When the Uno MCP server is not configured or not reachable, all Uno Platform guidance remains available through static skill content and official documentation URLs.

### Static Skill Coverage

The following topics are fully covered by static skills without MCP:

| Topic | Static Skill |
|-------|-------------|
| Extensions ecosystem (Navigation, DI, Config, Serialization, Localization, Logging, HTTP, Auth) | `references/uno-platform.md` |
| MVUX reactive pattern (Feeds, States, ListFeeds, Commands) | `references/uno-platform.md` |
| Toolkit controls (AutoLayout, Card, Chip, NavigationBar, TabBar, etc.) | `references/uno-platform.md` |
| Theme resources (Material, Cupertino, Fluent, color customization) | `references/uno-platform.md` |
| Hot Reload configuration | `references/uno-platform.md` |
| Single-project structure and UnoFeatures | `references/uno-platform.md` |
| Per-target setup (WASM, iOS, Android, macOS, Windows, Linux, Embedded) | `references/uno-targets.md` |
| Per-target debugging workflows | `references/uno-targets.md` |
| Per-target packaging and distribution | `references/uno-targets.md` |
| Per-target AOT/trimming configuration | `references/uno-targets.md` |
| Cross-target behavior differences (navigation, auth, debugging) | `references/uno-targets.md` |
| Uno Platform testing (Playwright WASM, platform-specific testing) | `references/uno-testing.md` |

### Official Documentation URLs

When MCP is unavailable, reference these canonical documentation URLs:

| Topic | URL |
|-------|-----|
| Getting Started | https://platform.uno/docs/articles/get-started.html |
| Uno Extensions | https://platform.uno/docs/articles/external/uno.extensions/ |
| MVUX Pattern | https://platform.uno/docs/articles/external/uno.extensions/doc/Overview/Mvux/Overview.html |
| Navigation | https://platform.uno/docs/articles/external/uno.extensions/doc/Learn/Navigation/Overview.html |
| Toolkit Controls | https://platform.uno/docs/articles/external/uno.toolkit.ui/ |
| Theme Resources | https://platform.uno/docs/articles/external/uno.themes/ |
| Uno SDK Features | https://platform.uno/docs/articles/features/uno-sdk.html |
| WASM Deployment | https://platform.uno/docs/articles/features/using-il-linker-webassembly.html |
| Hot Reload | https://platform.uno/docs/articles/features/working-with-hot-reload.html |
| Platform Requirements | https://platform.uno/docs/articles/getting-started/requirements.html |

### Fallback Workflow

```
1. Check if mcp__uno__ tools are available
2. If NOT available:
   a. Load `references/uno-platform.md` for core development patterns
   b. Load `references/uno-targets.md` for deployment guidance
   c. Reference official documentation URLs for latest information
   d. Note to user: "Uno MCP server is not configured. Using static documentation.
      For the latest information, visit: [relevant URL]"
3. If available:
   a. Call init rules (agent rules + usage rules)
   b. Use search-then-fetch workflow
   c. Cite sources from MCP results
   d. Supplement with static skill content for vetted patterns
```


## Uno SDK Features Reference

When MCP is unavailable, the following `UnoFeatures` values are supported in `.csproj`. This serves as a quick reference for project configuration.

### Extensions Features

| Feature | Description |
|---------|------------|
| `Extensions` | All Uno Extensions (meta-package) |
| `Authentication` | Base authentication framework |
| `AuthenticationMsal` | MSAL-based authentication |
| `AuthenticationOidc` | OIDC-based authentication |
| `Configuration` | Configuration from appsettings.json |
| `ExtensionsCore` | Core Extensions without full package |
| `Hosting` | Host builder and DI |
| `Http` | HTTP client extensions |
| `HttpKiota` | Kiota-based HTTP client (preferred) |
| `HttpRefit` | Refit-based HTTP client |
| `Localization` | Resource-based localization |
| `Logging` | Microsoft.Extensions.Logging |
| `LoggingSerilog` | Serilog integration |
| `MVUX` | MVUX reactive pattern |
| `Navigation` | Region-based navigation |
| `Serialization` | System.Text.Json integration |
| `Storage` | Cross-platform storage |
| `ThemeService` | Programmatic theme switching |

### UI Features

| Feature | Description |
|---------|------------|
| `Toolkit` | Uno Toolkit controls and helpers |
| `Material` | Material Design theme resources |
| `Cupertino` | Cupertino (iOS-style) theme |
| `Dsp` | Design System Package support |
| `Mvvm` | CommunityToolkit.Mvvm integration |
| `Prism` | Prism framework integration |

### Rendering Features

| Feature | Description |
|---------|------------|
| `Skia` | Skia rendering backend |
| `SkiaRenderer` | Force Skia renderer |
| `NativeRenderer` | Force native renderer |

### Media & Graphics

| Feature | Description |
|---------|------------|
| `Maps` | Map control support |
| `MediaElement` | Media playback |
| `WebView` | Embedded web view |
| `Lottie` | Lottie animation support |
| `Svg` | SVG rendering |
| `GLCanvas` | OpenGL canvas |


## Agent Gotchas

1. **Do not call MCP tools without checking availability first.** Always verify `mcp__uno__` tools exist before invoking them. Missing tools indicate the MCP server is not configured.
2. **Do not skip the init rules on first use.** The agent rules and usage rules provide critical routing tables and coding conventions. Skipping them leads to suboptimal search queries and convention violations.
3. **Do not present MCP-fetched content as your own knowledge.** Always cite the source URL. MCP results are external documentation, not built-in knowledge.
4. **Do not rely solely on MCP for Uno guidance.** Static skills (`references/uno-platform.md`, `references/uno-targets.md`) provide vetted patterns that work without MCP. Use MCP to supplement with current details.
5. **Do not ignore version differences in MCP results.** Documentation may reference Uno Platform 6.x features not available in 5.x projects. Check the project's Uno SDK version before applying guidance.
6. **Do not fetch without searching first.** The fetch tool requires a `sourcePath` from search results. Direct fetching with guessed paths may return wrong or missing content.


## Prerequisites

- Uno MCP server configured in the project's MCP configuration (`.mcp.json` or IDE settings)
- For fallback: `references/uno-platform.md` and `references/uno-targets.md` loaded as static skills


## References

- [Uno Platform Documentation](https://platform.uno/docs/)
- [MCP Protocol Specification](https://modelcontextprotocol.io/)
- [Uno Platform GitHub](https://github.com/unoplatform/uno)
