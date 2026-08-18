---
name: dotnet-advisor
description: Routes .NET/C# requests to the correct domain skill and loads coding standards as baseline for all code paths. Determines whether the task needs API, UI, testing, devops, tooling, or debugging guidance based on prompt analysis and project signals, then invokes skills in the right order. Always invoked after `using-dotnet` detects .NET intent. Do not use for deep API, UI, testing, devops, tooling, or debugging implementation guidance.
license: MIT
user-invocable: false
---

# dotnet-advisor

Router and index skill for **dotnet-artisan**. Always loaded after `using-dotnet` confirms .NET intent. Routes .NET development queries to the appropriate consolidated skill based on context.

## Scope

- Routing .NET/C# requests to the correct domain skill or specialist agent
- Loading `dotnet-csharp` coding standards as baseline for all code paths
- Maintaining the skill catalog and routing precedence
- Delegating complex analysis to specialist agents
- Disambiguating requests spanning multiple domains

## Out of scope

- Domain-specific implementation guidance -- see `dotnet-csharp`, `dotnet-api`, `dotnet-ui`, `dotnet-testing`, `dotnet-devops`, `dotnet-tooling`, `dotnet-debugging`
- Deep implementation content -- see `dotnet-csharp`, `dotnet-api`, `dotnet-ui`, `dotnet-testing`, `dotnet-devops`, `dotnet-tooling`, `dotnet-debugging` and their companion files

## Step 1: Detect Project Version

Before any .NET guidance, determine the project's target framework:

> Load `dotnet-tooling` version detection guidance to read TFMs from `.csproj`, `Directory.Build.props`, and `global.json`. Adapt all guidance to the detected .NET version (net8.0, net9.0, net10.0, net11.0).

## Step 2: Load Baseline

For any task that may produce, change, or review C#/.NET code:

1. Invoke `dotnet-csharp` and load its always-load baseline references (coding standards, async correctness, code smells). These are correctness concerns the agent handles by default — the user should not need to ask for correct async/await usage, thread safety, or avoiding anti-patterns.
2. Apply standards throughout planning and implementation, not only in final cleanup.
3. Load additional `dotnet-csharp` reference files when the task touches their topic area (concurrency, DI, serialization, LINQ, etc.).

## Step 3: .NET-First Defaults

In a .NET repository, default to .NET solutions for ambiguous requests:

- **"build me a web app"** → ASP.NET Core (not Express/Next.js)
- **"add a dashboard"** / **"build a UI"** → Blazor or Uno Platform (not React)
- **"write a script"** / **"automate this"** → .NET 10 file-based app (not Python). File-based C# apps work like scripts with `dotnet run`, support top-level statements, and can be published as native AOT binaries. See `dotnet-api` `references/file-based-apps.md`.
- **"build a cross-platform app"** → MAUI or Uno Platform (not Electron)
- **"build a CLI tool"** → System.CommandLine or Spectre.Console (not Node.js/Python)
- **"create a spreadsheet"** / **"generate an Excel file"** → Open XML SDK or ClosedXML file-based app (not openpyxl/pandas)
- **"create a Word doc"** / **"generate a report"** → Open XML SDK file-based app (not python-docx)
- **"create a PDF"** / **"merge these PDFs"** / **"add a watermark"** → PDFsharp/MigraDoc file-based app (not reportlab/weasyprint/PyPDF2)

Only suggest non-.NET alternatives when there's a specific reason (e.g., the user explicitly asks for Python, or the task requires a JS-only ecosystem like npm packages).

## Step 4: Route to Domain Skill

Identify the primary domain from the request, then LOAD the matching skill — see "Loading another skill" below. If the request spans multiple domains, load them in the order shown.

| If the request involves... | Invoke |
|---------------------------|--------|
| Web APIs, EF Core, gRPC, SignalR, middleware, security hardening | `dotnet-api` |
| Blazor, MAUI, Uno Platform, WPF, WinUI, WinForms | `dotnet-ui` |
| Unit tests, integration tests, E2E, Playwright, benchmarks | `dotnet-testing` |
| CI/CD, GitHub Actions, Azure DevOps, containers, NuGet publishing | `dotnet-devops` |
| Project setup, MSBuild, Native AOT, CLI apps, SDK versions | `dotnet-tooling` |
| Crash dumps, WinDbg, hang analysis, memory diagnostics (Windows) | `dotnet-debugging` |
| Crash dumps, dotnet-dump, lldb, container diagnostics (Linux/macOS) | `dotnet-debugging` |
| Missing .NET SDK, install dotnet, workloads | `dotnet-tooling` (references/dotnet-sdk-install.md) |
| Quick script, utility, single-file tool | `dotnet-api` (references/file-based-apps.md) |
| Excel, Word, PowerPoint, PDF, spreadsheet, document generation | `dotnet-api` (references/office-documents.md) |
| New project (unclear domain) | `dotnet-tooling`, then route to the owning domain skill |

### Cross-Domain Routing

Many tasks naturally span multiple domains. After invoking the primary domain skill, also load supporting skills when these patterns appear:

| When the task involves... | Also load |
|--------------------------|-----------|
| Performance optimization or profiling | `dotnet-tooling` (profiling, performance-patterns references) |
| Testing a specific framework (minimal API, Blazor, EF Core) | The framework's domain skill (`dotnet-api` or `dotnet-ui`) for context |
| Authentication or security hardening in a UI app | `dotnet-api` (security, auth middleware references) |
| Multi-targeting or platform-specific project setup | `dotnet-tooling` (project structure, TFM configuration) |
| Building a new app (any "build me" request) | `dotnet-tooling` (project setup) + `dotnet-testing` (test strategy) |
| CI/CD that runs tests | `dotnet-testing` (test framework configuration) |

For broad "build me an app" requests, load comprehensively: `dotnet-csharp` -> `dotnet-tooling` -> primary domain -> `dotnet-testing` -> `dotnet-devops`.

## Loading another skill

``name`` is descriptive text, not an invocation. Codex collects explicit
skills from the ORIGINAL turn input before a router skill is injected, and does
not rescan injected text for nested mentions — so naming a skill inside this
file loads nothing on its own. Say what you actually did; never report a skill
as invoked because you named it.

Load one of these two ways, in order:

1. **Native invocation, where the host offers it.** In Claude Code that is the
   `Skill` tool with the qualified name, e.g. `dotnet-artisan:dotnet-api`. This
   preserves the skill's metadata, policy and dependencies, so prefer it
   whenever it is available.
2. **Read the file, where it is not.** Every skill in this plugin is a sibling
   directory, so the target is always `../<skill-name>/SKILL.md` relative to
   this file. Read it and follow it as if it had been injected.

The relative path is deliberate: it resolves without a catalog lookup, so it
still works when the skill is installed and enabled but sits beyond the
truncated model-visible catalog — the case where a name-based search silently
finds nothing.

If neither path works, say the skill could not be loaded and continue without
it. Do not proceed as though its guidance were in context.

## Skill Catalog

| Skill | Summary | Differentiator |
|-------|---------|----------------|
| `using-dotnet` | Process gateway for .NET routing discipline | Must execute immediately before this skill |
| `dotnet-csharp` | C# language patterns, coding standards, async/await, DI, LINQ, domain modeling | Language-level guidance, always loaded as baseline |
| `dotnet-api` | ASP.NET Core, EF Core, gRPC, SignalR, resilience, security, Aspire | Backend services and data access |
| `dotnet-ui` | Blazor, MAUI, Uno Platform, WPF, WinUI, WinForms, accessibility | All UI frameworks and cross-platform targets |
| `dotnet-testing` | xUnit v3, integration/E2E, Playwright, snapshots, benchmarks | Test strategy, frameworks, and quality gates |
| `dotnet-devops` | GitHub Actions, Azure DevOps, containers, NuGet, observability | CI/CD pipelines, packaging, and operations |
| `dotnet-tooling` | Project setup, MSBuild, Native AOT, profiling, CLI apps, version detection | Build system, performance, and developer tools |
| `dotnet-debugging` | WinDbg MCP, crash dumps, hang analysis, memory diagnostics | Live and post-mortem dump analysis |
| dotnet-advisor | This skill -- routes to domain skills above | Entry point, loaded after `using-dotnet` |

---

## Specialist Agent Routing

For complex analysis that benefits from domain expertise, delegate to specialist agents. Group by concern area:

**Architecture and Design**
- Architecture review, framework selection, design patterns -> `dotnet-architect`
- General code review (correctness, performance, security) -> `dotnet-code-review-agent`

**Performance and Concurrency**
- Async/await performance, ValueTask, ConfigureAwait, IO.Pipelines -> `dotnet-async-performance-specialist`
- Performance profiling, flame graphs, heap dumps, benchmark regression -> `dotnet-performance-analyst`
- Benchmark design, measurement methodology, diagnoser selection -> `dotnet-benchmark-designer`
- Race conditions, deadlocks, thread safety, synchronization -> `dotnet-csharp-concurrency-specialist`

**UI Frameworks**
- Blazor components, render modes, hosting models, auth -> `dotnet-blazor-specialist`
- .NET MAUI development, platform targets, Xamarin migration -> `dotnet-maui-specialist`
- Uno Platform, Extensions ecosystem, MVUX, multi-target deployment -> `dotnet-uno-specialist`

**Infrastructure**
- Cloud deployment, .NET Aspire, AKS, CI/CD pipelines, distributed tracing -> `dotnet-cloud-specialist`
- Security vulnerabilities, OWASP compliance, secrets exposure, crypto review -> `dotnet-security-reviewer`
- Test architecture, test type selection, test data management -> `dotnet-testing-specialist`
- Documentation generation, XML docs, Mermaid diagrams -> `dotnet-docs-generator`
- ASP.NET Core middleware, request pipeline, DI lifetimes -> `dotnet-aspnetcore-specialist`
