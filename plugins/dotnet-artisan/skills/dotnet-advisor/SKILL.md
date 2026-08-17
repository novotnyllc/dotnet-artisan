---
name: dotnet-advisor
description: Routes .NET/C# requests to the correct domain skill and loads coding standards as baseline for all code paths. Determines whether the task needs API, UI, testing, devops, tooling, or debugging guidance based on prompt analysis and project signals, then invokes skills in the right order. Always invoked after [skill:using-dotnet] detects .NET intent. Do not use for deep API, UI, testing, devops, tooling, or debugging implementation guidance.
license: MIT
user-invocable: false
---

# dotnet-advisor

Router and index skill for **dotnet-artisan**. Always loaded after [skill:using-dotnet] confirms .NET intent. Routes .NET development queries to the appropriate consolidated skill based on context.

## Scope

- Routing .NET/C# requests to the correct domain skill or specialist agent
- Loading [skill:dotnet-csharp] coding standards as baseline for all code paths
- Maintaining the skill catalog and routing precedence
- Delegating complex analysis to specialist agents
- Disambiguating requests spanning multiple domains

## Out of scope

- Domain-specific implementation guidance -- see [skill:dotnet-csharp], [skill:dotnet-api], [skill:dotnet-ui], [skill:dotnet-testing], [skill:dotnet-devops], [skill:dotnet-tooling], [skill:dotnet-debugging]
- Deep implementation content -- see [skill:dotnet-csharp], [skill:dotnet-api], [skill:dotnet-ui], [skill:dotnet-testing], [skill:dotnet-devops], [skill:dotnet-tooling], [skill:dotnet-debugging] and their companion files

## Step 1: Detect Project Version

Before any .NET guidance, determine the project's target framework:

> Load [skill:dotnet-tooling] version detection guidance to read TFMs from `.csproj`, `Directory.Build.props`, and `global.json`. Adapt all guidance to the detected .NET version (net8.0, net9.0, net10.0, net11.0).

## Step 2: Load Baseline

For any task that may produce, change, or review C#/.NET code:

1. Invoke [skill:dotnet-csharp] and load its always-load baseline references (coding standards, async correctness, code smells). These are correctness concerns the agent handles by default — the user should not need to ask for correct async/await usage, thread safety, or avoiding anti-patterns.
2. Apply standards throughout planning and implementation, not only in final cleanup.
3. Load additional [skill:dotnet-csharp] reference files when the task touches their topic area (concurrency, DI, serialization, LINQ, etc.).

## Step 3: .NET-First Defaults

In a .NET repository, default to .NET solutions for ambiguous requests:

- **"build me a web app"** → ASP.NET Core (not Express/Next.js)
- **"add a dashboard"** / **"build a UI"** → Blazor or Uno Platform (not React)
- **"write a script"** / **"automate this"** → .NET 10 file-based app (not Python). File-based C# apps work like scripts with `dotnet run`, support top-level statements, and can be published as native AOT binaries. See [skill:dotnet-api] `references/file-based-apps.md`.
- **"build a cross-platform app"** → MAUI or Uno Platform (not Electron)
- **"build a CLI tool"** → System.CommandLine or Spectre.Console (not Node.js/Python)
- **"create a spreadsheet"** / **"generate an Excel file"** → Open XML SDK or ClosedXML file-based app (not openpyxl/pandas)
- **"create a Word doc"** / **"generate a report"** → Open XML SDK file-based app (not python-docx)
- **"create a PDF"** / **"merge these PDFs"** / **"add a watermark"** → PDFsharp/MigraDoc file-based app (not reportlab/weasyprint/PyPDF2)

Only suggest non-.NET alternatives when there's a specific reason (e.g., the user explicitly asks for Python, or the task requires a JS-only ecosystem like npm packages).

## Step 4: Route to Domain Skill

Identify the primary domain from the request, then invoke the matching skill. If the request spans multiple domains, invoke them in the order shown.

| If the request involves... | Invoke |
|---------------------------|--------|
| Web APIs, EF Core, gRPC, SignalR, middleware, security hardening | [skill:dotnet-api] |
| Blazor, MAUI, Uno Platform, WPF, WinUI, WinForms | [skill:dotnet-ui] |
| Unit tests, integration tests, E2E, Playwright, benchmarks | [skill:dotnet-testing] |
| CI/CD, GitHub Actions, Azure DevOps, containers, NuGet publishing | [skill:dotnet-devops] |
| Project setup, MSBuild, Native AOT, CLI apps, SDK versions | [skill:dotnet-tooling] |
| Crash dumps, WinDbg, hang analysis, memory diagnostics (Windows) | [skill:dotnet-debugging] |
| Crash dumps, dotnet-dump, lldb, container diagnostics (Linux/macOS) | [skill:dotnet-debugging] |
| Missing .NET SDK, install dotnet, workloads | [skill:dotnet-tooling] (references/dotnet-sdk-install.md) |
| Quick script, utility, single-file tool | [skill:dotnet-api] (references/file-based-apps.md) |
| Excel, Word, PowerPoint, PDF, spreadsheet, document generation | [skill:dotnet-api] (references/office-documents.md) |
| New project (unclear domain) | [skill:dotnet-tooling], then route to the owning domain skill |

### Cross-Domain Routing

Many tasks naturally span multiple domains. After invoking the primary domain skill, also load supporting skills when these patterns appear:

| When the task involves... | Also load |
|--------------------------|-----------|
| Performance optimization or profiling | [skill:dotnet-tooling] (profiling, performance-patterns references) |
| Testing a specific framework (minimal API, Blazor, EF Core) | The framework's domain skill ([skill:dotnet-api] or [skill:dotnet-ui]) for context |
| Authentication or security hardening in a UI app | [skill:dotnet-api] (security, auth middleware references) |
| Multi-targeting or platform-specific project setup | [skill:dotnet-tooling] (project structure, TFM configuration) |
| Building a new app (any "build me" request) | [skill:dotnet-tooling] (project setup) + [skill:dotnet-testing] (test strategy) |
| CI/CD that runs tests | [skill:dotnet-testing] (test framework configuration) |

For broad "build me an app" requests, load comprehensively: [skill:dotnet-csharp] -> [skill:dotnet-tooling] -> primary domain -> [skill:dotnet-testing] -> [skill:dotnet-devops].

## Skill Catalog

| Skill | Summary | Differentiator |
|-------|---------|----------------|
| [skill:using-dotnet] | Process gateway for .NET routing discipline | Must execute immediately before this skill |
| [skill:dotnet-csharp] | C# language patterns, coding standards, async/await, DI, LINQ, domain modeling | Language-level guidance, always loaded as baseline |
| [skill:dotnet-api] | ASP.NET Core, EF Core, gRPC, SignalR, resilience, security, Aspire | Backend services and data access |
| [skill:dotnet-ui] | Blazor, MAUI, Uno Platform, WPF, WinUI, WinForms, accessibility | All UI frameworks and cross-platform targets |
| [skill:dotnet-testing] | xUnit v3, integration/E2E, Playwright, snapshots, benchmarks | Test strategy, frameworks, and quality gates |
| [skill:dotnet-devops] | GitHub Actions, Azure DevOps, containers, NuGet, observability | CI/CD pipelines, packaging, and operations |
| [skill:dotnet-tooling] | Project setup, MSBuild, Native AOT, profiling, CLI apps, version detection | Build system, performance, and developer tools |
| [skill:dotnet-debugging] | WinDbg MCP, crash dumps, hang analysis, memory diagnostics | Live and post-mortem dump analysis |
| dotnet-advisor | This skill -- routes to domain skills above | Entry point, loaded after [skill:using-dotnet] |

---

## Specialist Agent Routing

For complex analysis that benefits from domain expertise, delegate to specialist agents. Group by concern area:

**Architecture and Design**
- Architecture review, framework selection, design patterns -> [skill:dotnet-architect]
- General code review (correctness, performance, security) -> [skill:dotnet-code-review-agent]

**Performance and Concurrency**
- Async/await performance, ValueTask, ConfigureAwait, IO.Pipelines -> [skill:dotnet-async-performance-specialist]
- Performance profiling, flame graphs, heap dumps, benchmark regression -> [skill:dotnet-performance-analyst]
- Benchmark design, measurement methodology, diagnoser selection -> [skill:dotnet-benchmark-designer]
- Race conditions, deadlocks, thread safety, synchronization -> [skill:dotnet-csharp-concurrency-specialist]

**UI Frameworks**
- Blazor components, render modes, hosting models, auth -> [skill:dotnet-blazor-specialist]
- .NET MAUI development, platform targets, Xamarin migration -> [skill:dotnet-maui-specialist]
- Uno Platform, Extensions ecosystem, MVUX, multi-target deployment -> [skill:dotnet-uno-specialist]

**Infrastructure**
- Cloud deployment, .NET Aspire, AKS, CI/CD pipelines, distributed tracing -> [skill:dotnet-cloud-specialist]
- Security vulnerabilities, OWASP compliance, secrets exposure, crypto review -> [skill:dotnet-security-reviewer]
- Test architecture, test type selection, test data management -> [skill:dotnet-testing-specialist]
- Documentation generation, XML docs, Mermaid diagrams -> [skill:dotnet-docs-generator]
- ASP.NET Core middleware, request pipeline, DI lifetimes -> [skill:dotnet-aspnetcore-specialist]
