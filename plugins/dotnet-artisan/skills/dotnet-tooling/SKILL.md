---
name: dotnet-tooling
description: Manages .NET SDK installation (dotnet-install, workloads), project setup (.slnx, Directory.Build.props, CPM), MSBuild authoring, build optimization, performance (Span, ArrayPool, stackalloc), profiling (dotnet-counters, dotnet-trace), Native AOT/trimming, GC tuning, CLI apps (System.CommandLine, Spectre.Console, Terminal.Gui), ILSpy decompilation, VS Code debug config (launch.json, coreclr, remote), C# LSP (csharp-ls, OmniSharp), and version detection/upgrade. Spans 34 topic areas. Do not use for UI implementation or API security design.
license: MIT
user-invocable: false
---

# dotnet-tooling

## Overview

.NET project setup, build systems, performance, CLI apps, and developer tooling. This consolidated skill spans 34 topic areas. Load the appropriate companion file from `references/` based on the routing table below.

## Routing Table

| Topic | Keywords | Description | Companion File |
|-------|----------|-------------|----------------|
| Project structure | solution, .slnx, CPM, analyzers | .slnx, Directory.Build.props, CPM, analyzers | references/project-structure.md |
| Scaffold project | dotnet new, CPM, SourceLink, editorconfig | dotnet new with CPM, analyzers, editorconfig, SourceLink | references/scaffold-project.md |
| Csproj reading | PropertyGroup, ItemGroup, CPM, props | SDK-style .csproj, PropertyGroup, ItemGroup, CPM | references/csproj-reading.md |
| MSBuild authoring | targets, props, conditions, Directory.Build | Targets, props, conditions, Directory.Build patterns | references/msbuild-authoring.md |
| MSBuild tasks | ITask, ToolTask, inline tasks, UsingTask | ITask, ToolTask, IIncrementalTask, inline tasks | references/msbuild-tasks.md |
| Build analysis | MSBuild output, NuGet errors, analyzer warnings | MSBuild output, NuGet errors, analyzer warnings | references/build-analysis.md |
| Build optimization | slow builds, binary logs, parallel, restore | Slow builds, binary logs, parallel, restore | references/build-optimization.md |
| Artifacts output | UseArtifactsOutput, ArtifactsPath, CI/Docker | UseArtifactsOutput, ArtifactsPath, CI/Docker impact | references/artifacts-output.md |
| Multi-targeting | multiple TFMs, polyfills, conditional compilation | Multiple TFMs, PolySharp, conditional compilation | references/multi-targeting.md |
| Performance patterns | Span, ArrayPool, ref struct, sealed, stackalloc | Span, ArrayPool, ref struct, sealed, stackalloc | references/performance-patterns.md |
| Profiling | dotnet-counters, dotnet-trace, flame graphs | dotnet-counters, dotnet-trace, dotnet-dump, flame graphs | references/profiling.md |
| Native AOT | PublishAot, ILLink, P/Invoke, size optimization | PublishAot, ILLink descriptors, P/Invoke, size optimization | references/native-aot.md |
| AOT architecture | source gen, AOT-safe DI, serialization | Source gen over reflection, AOT-safe DI, factories | references/aot-architecture.md |
| Trimming | annotations, ILLink, IL2xxx warnings, IsTrimmable | Annotations, ILLink, IL2xxx warnings, IsTrimmable | references/trimming.md |
| GC/memory | GC modes, LOH/POH, Span/Memory, ArrayPool | GC modes, LOH/POH, Gen0/1/2, Span/Memory, ArrayPool | references/gc-memory.md |
| CLI architecture | command/handler/service, clig.dev, exit codes | Command/handler/service, clig.dev, exit codes | references/cli-architecture.md |
| System.CommandLine | RootCommand, Option<T>, SetAction, parsing | System.CommandLine 2.0, RootCommand, Option<T> | references/system-commandline.md |
| Spectre.Console | tables, trees, progress, prompts, live displays | Tables, trees, progress, prompts, live displays | references/spectre-console.md |
| Terminal.Gui | views, layout, menus, dialogs, bindings, themes | Terminal.Gui v2, views, layout, menus, dialogs | references/terminal-gui.md |
| CLI distribution | AOT vs framework-dependent, RID matrix, Homebrew, winget, Scoop, dotnet tool | Distribution strategy, single-file publish, per-platform packaging | references/cli-distribution.md |
| CLI release pipeline | GHA build matrix, artifact staging, checksums | GHA build matrix, artifact staging, checksums | references/cli-release-pipeline.md |
| Documentation strategy | Starlight, Docusaurus, DocFX decision tree | Starlight, Docusaurus, DocFX decision tree | references/documentation-strategy.md |
| Tool management | global, local, manifests, restore, pinning | Global/local tools, manifests, restore, pinning | references/tool-management.md |
| Version detection | TFM/SDK from .csproj, global.json | TFM/SDK from .csproj, global.json, Directory.Build | references/version-detection.md |
| Version upgrade | LTS-to-LTS, staged, preview, upgrade paths | LTS-to-LTS, staged through STS, preview paths | references/version-upgrade.md |
| Solution navigation | entry points, .sln/.slnx, dependency graphs | Entry points, .sln/.slnx, dependency graphs | references/solution-navigation.md |
| Project analysis | solution layout, build config analysis | Solution layout, build config, .csproj analysis | references/project-analysis.md |
| Modernize | outdated TFMs, deprecated packages, patterns | Outdated TFMs, deprecated packages, superseded patterns | references/modernize.md |
| Add analyzers | nullable, trimming, AOT compat, severity config | Nullable, trimming, AOT compat analyzers, severity | references/add-analyzers.md |
| SDK installation | install .NET, dotnet-install, workloads, missing SDK | .NET SDK install script, workloads, env vars, side-by-side | references/dotnet-sdk-install.md |
| ILSpy decompile | ilspycmd, decompile, assembly, disassemble, IL | ILSpy/ilspycmd decompilation, type listing, IL view | references/ilspy-decompile.md |
| Mermaid diagrams | architecture, sequence, class, ER, flowcharts | Architecture, sequence, class, deployment, ER diagrams | references/mermaid-diagrams.md |
| VS Code debugging | launch.json, tasks.json, coreclr, attach, debug | VS Code launch/attach configs, tasks, multi-project, hot reload | references/vscode-debug.md |
| C# LSP | language server, csharp-ls, OmniSharp, go to definition | C# LSP servers, code navigation, agent usage patterns | references/csharp-lsp.md |

## Scope

- Solution structure and project scaffolding
- MSBuild authoring and build optimization
- Performance patterns and profiling
- Native AOT, trimming, and GC tuning
- CLI app development (System.CommandLine, Spectre.Console, Terminal.Gui)
- Documentation generation (DocFX)
- Tool management and version detection/upgrade
- Solution navigation and project analysis
- Code modernization and analyzer configuration
- Mermaid diagram generation
- VS Code debug configuration (launch.json, tasks.json, coreclr)
- C# LSP servers (csharp-ls, OmniSharp) for agent code navigation

## Out of scope

- Crash dump analysis, hang/deadlock triage, live debugger attach -> [skill:dotnet-debugging]
- Web API patterns -> [skill:dotnet-api]
- Test authoring -> [skill:dotnet-testing]
- CI/CD pipelines -> [skill:dotnet-devops]
- C# language patterns -> [skill:dotnet-csharp]
- UI framework development -> [skill:dotnet-ui]

## Scripts

- `scripts/scan-dotnet-targets.py` -- Scan repository for .NET TFM and SDK version signals
