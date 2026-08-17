---
name: using-dotnet
description: Detects .NET intent for any C#, ASP.NET Core, EF Core, Blazor, MAUI, Uno Platform, WPF, WinUI, SignalR, gRPC, xUnit, NuGet, or MSBuild request from prompt keywords and repository signals (.sln, .csproj, global.json, .cs files). First skill to invoke for all .NET work — loads version-specific coding standards and routes to domain skills via [skill:dotnet-advisor] before any planning or implementation. Do not use for clearly non-.NET tasks (Python, JavaScript, Go, Rust, Java).
license: MIT
user-invocable: false
---

# using-dotnet

## Scope

- Establishing .NET/C# routing discipline before clarifying questions, planning, command execution, or edits.
- Detecting .NET intent from prompt and repository signals (`.sln`, `.slnx`, `.csproj`, `global.json`, `.cs`).
- Enforcing first-step routing through [skill:dotnet-advisor] and baseline loading order.
- Defining priority and rigidity rules for downstream skill invocation.

## Out of scope

- C# implementation details and coding-standard specifics -> [skill:dotnet-csharp]
- Deep domain implementation patterns -> [skill:dotnet-api], [skill:dotnet-ui], [skill:dotnet-testing], [skill:dotnet-devops], [skill:dotnet-tooling], [skill:dotnet-debugging]
- Specialist deep-review workflows -> [skill:dotnet-security-reviewer], [skill:dotnet-performance-analyst], [skill:dotnet-testing-specialist]

## Simplicity First (KISS)

Write the simplest code that solves the problem. Agents consistently over-engineer — more abstractions, more layers, more indirection than the task warrants.

- **Do the direct thing.** If you need a file, create it — don't write code that generates it. If you need data, put it where it belongs — don't assemble it from embedded strings at runtime. When you catch yourself building something indirect (a generator, a template, a wrapper), stop and ask: "Can I just do this directly?"
- **Write readable code, not clever code.** A plain `if`/`else` over a chain of ternaries. A `foreach` over a hard-to-read LINQ expression. A flat method over nested callbacks. Clear beats compact. This does NOT mean avoiding modern C# — use latest language features (`[..4]`, list patterns, primary constructors, raw string literals, collection expressions). Modern syntax is concise AND readable. The target is convoluted logic, not concise syntax.
- **Don't add what wasn't asked for.** No extra config options, no "while we're at it" refactors, no preemptive error handling for impossible scenarios, no comments or XML docs on code unrelated to the current task.
- **Match architecture to scope.** Simple CRUD doesn't need DDD, MediatR, CQRS, or a pipeline of behaviors. A 20-line handler doesn't need 5 files. Scale the pattern to the problem.
- **Earn every abstraction.** Don't create `IOrderService` for one `OrderService`. Don't extract a helper for something that happens once. Three similar lines of code are fine — extract only when a real pattern emerges across 3+ call sites.
- **Use what the framework gives you.** `DbContext` is your Unit of Work. `DbSet<T>` is your repository. .NET has `TimeProvider`, `ILogger<T>`, `IHttpClientFactory`, `System.Text.Json`. Use them directly — don't wrap, don't abstract, don't add a NuGet package for something the framework already does.
- **Fewer files, fewer layers.** In new or small projects, don't split into Controller + Service + Repository + DTO + Mapper + Interface when one or two files will do. In existing codebases, follow the established patterns. Add layers only when the code gets hard to understand without them.

The right amount of complexity is the minimum needed to solve the current problem correctly.

## Why Routing Matters

.NET skills contain version-specific guidance (net8.0 vs net9.0 vs net10.0), coding standards, and framework-specific patterns that the model doesn't have in its training data. Skipping routing means the model confidently produces code using deprecated APIs, misses framework-specific patterns, or gives generic advice that ignores project context.

Routing before action ensures:
- **Version-aware guidance** loads before code generation (avoiding stale API suggestions)
- **Coding standards** apply from the start (not patched in after the fact)
- **Domain expertise** routes to the right specialist (avoiding generic advice for specialized problems)

The cost of routing is a few skill invocations. The cost of skipping is rework, stale advice, or subtle bugs.

## Routing Sequence

When a request likely involves .NET or C#, follow this sequence before any other action:

1. **Detect .NET intent** — Look for prompt keywords (C#, .NET, ASP.NET, EF Core, Blazor, MAUI, NuGet, csproj) or repository signals (`.sln`, `.slnx`, `.csproj`, `global.json`, `.cs` files). If either is present, continue.
2. **In a .NET repository, .NET is the default** — When repo signals are present, ambiguous requests like "build me a web app", "add a dashboard", "write a script", or "create a spreadsheet" should use .NET solutions (ASP.NET Core, Blazor, .NET file-based apps, Open XML SDK) rather than defaulting to JavaScript/Python. The user chose a .NET project for a reason.
3. **Check SDK availability** — If `dotnet --version` fails and no `DOTNET_ROOT` is set, install the SDK before proceeding. This takes under a minute with no privileges required. See [skill:dotnet-tooling] `references/dotnet-sdk-install.md` for the full install script reference, or use this one-liner: `curl -sSL https://dot.net/v1/dotnet-install.sh | bash && export DOTNET_ROOT="$HOME/.dotnet" && export PATH="$PATH:$DOTNET_ROOT:$DOTNET_ROOT/tools"`. Do not treat a missing SDK as a blocker — install it and continue.
4. **Invoke [skill:dotnet-advisor]** — This routes the request to the correct domain skills and loads coding standards.
5. **Follow advisor routing** — Load [skill:dotnet-csharp] baseline, then the domain skill(s) the advisor selects.
6. **Now respond** — Clarify, plan, explore, or implement with the right context loaded.

## Prefer File-Based Apps for Scripts and Utilities

For quick scripts, utilities, prototypes, and single-file tools, prefer .NET 10 file-based apps (`dotnet run script.cs`) over creating a full project with `.csproj`. File-based apps:

- Need only a single `.cs` file — no project file, no solution, no boilerplate
- Support NuGet packages via `#:package` directives
- Support ASP.NET Core via `#:sdk Microsoft.NET.Sdk.Web`
- Enable native AOT publish by default
- Work as Unix shebangs (`#!/usr/bin/env dotnet`)

When the user asks to "write a script", "make a quick tool", "create a utility", or any small single-purpose program, default to a file-based app unless the task clearly needs multiple source files or test projects. See [skill:dotnet-api] `references/file-based-apps.md` for the full directive and CLI reference.

```csharp
// Example: a file-based ASP.NET Core API
#:sdk Microsoft.NET.Sdk.Web

var app = WebApplication.Create(args);
app.MapGet("/", () => "Hello from a single .cs file!");
app.Run();
```

```csharp
// Example: a file-based CLI tool with a NuGet package
#:package Spectre.Console

using Spectre.Console;
AnsiConsole.MarkupLine("[green]Hello[/] from a file-based app!");
```

Routing applies even for "simple" questions and clarification requests. The skill loading is lightweight and ensures consistent quality.

## Skill Priority

When multiple skills could apply, use this order:

1. **Process skills first**: this skill, then [skill:dotnet-advisor].
2. **Baseline skill second**: [skill:dotnet-csharp] for any code path.
3. **Domain skills third**: [skill:dotnet-api], [skill:dotnet-ui], [skill:dotnet-testing], [skill:dotnet-devops], [skill:dotnet-tooling], [skill:dotnet-debugging].
4. **Specialist agents fourth**: use only when deeper analysis is required after routing.

## Skill Types

**Rigid** (must follow exactly): this skill, [skill:dotnet-advisor], and baseline-first ordering.

**Flexible** (adapt to context): Domain skills and their companion references.

User instructions define WHAT to do. This process defines HOW to route and load skills before execution.
