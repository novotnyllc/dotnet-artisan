---
name: dotnet-csharp
description: Baseline C# skill loaded for every .NET code path. Guides language patterns (records, pattern matching, primary constructors, C# 8-15), coding standards, async/await, DI, LINQ, serialization, domain modeling, concurrency, Roslyn analyzers, globalization, native interop (P/Invoke, LibraryImport, ComWrappers), WASM interop (JSImport/JSExport), and type design. Spans 25 topics. Do not use for ASP.NET endpoint architecture, UI framework patterns, or CI/CD guidance.
license: MIT
user-invocable: false
---

# dotnet-csharp

## Overview

C# language patterns, coding standards, and .NET runtime features for idiomatic, performant code. This consolidated skill spans 25 topic areas. Load the appropriate companion file from `references/` based on the routing table below.

### Always-Load Baseline

These references define correctness and quality standards that apply to all C# code — load them by default whenever producing or reviewing code, regardless of what the user asked for:

- `references/coding-standards.md` — naming conventions, file layout, style rules
- `references/async-patterns.md` — async/await correctness, ConfigureAwait, cancellation propagation (nearly all .NET code uses async)
- `references/solid-principles.md` — SOLID, DRY, single responsibility, dependency inversion, anti-pattern detection
- `references/code-smells.md` — common mistakes the agent should avoid without being told (async void, DI lifetime misuse, swallowed exceptions)
- `references/dotnet-releases.md` — .NET 10/11 and C# 14/15 features, version matrix, TFM-specific code generation rules (compensates for training data cutoff)

### On-Demand References

Load these when the topic matches (see Routing Table keywords):

## Routing Table

| Topic | Keywords | Description | Companion File |
|-------|----------|-------------|----------------|
| Coding standards | naming, file layout, style rules | Baseline C# conventions (naming, layout, style rules) | references/coding-standards.md |
| Async/await | async, Task, ConfigureAwait, cancellation | async/await, Task patterns, ConfigureAwait, cancellation | references/async-patterns.md |
| Dependency injection | DI, services, scopes, keyed, lifetimes | MS DI, keyed services, scopes, decoration, lifetimes | references/dependency-injection.md |
| Configuration | Options pattern, user secrets, feature flags | Options pattern, user secrets, feature flags, IOptions\<T\> | references/configuration.md |
| Source generators | IIncrementalGenerator, GeneratedRegex, LoggerMessage | IIncrementalGenerator, GeneratedRegex, LoggerMessage, STJ | references/source-generators.md |
| Nullable reference types | annotations, migration, agent mistakes | Annotation strategies, migration, agent mistakes | references/nullable-reference-types.md |
| Serialization | System.Text.Json, Protobuf, MessagePack, AOT | System.Text.Json source generators, Protobuf, MessagePack | references/serialization.md |
| Channels | Channel\<T\>, bounded/unbounded, backpressure | Channel\<T\>, bounded/unbounded, backpressure, drain | references/channels.md |
| LINQ optimization | IQueryable vs IEnumerable, compiled queries | IQueryable vs IEnumerable, compiled queries, allocations | references/linq-optimization.md |
| Domain modeling | aggregates, value objects, domain events | Aggregates, value objects, domain events, repositories | references/domain-modeling.md |
| SOLID principles | SRP, DRY, anti-patterns, compliance checks | SOLID and DRY principles, C# anti-patterns, fixes | references/solid-principles.md |
| Concurrency | lock, SemaphoreSlim, Interlocked, concurrent collections | lock, SemaphoreSlim, Interlocked, concurrent collections | references/concurrency-patterns.md |
| Roslyn analyzers | DiagnosticAnalyzer, CodeFixProvider, multi-version | DiagnosticAnalyzer, CodeFixProvider, CodeRefactoring | references/roslyn-analyzers.md |
| Editorconfig | IDE/CA severity, AnalysisLevel, globalconfig | IDE/CA severity, AnalysisLevel, globalconfig, enforcement | references/editorconfig.md |
| File I/O | FileStream, RandomAccess, FileSystemWatcher, paths | FileStream, RandomAccess, FileSystemWatcher, MemoryMappedFile | references/file-io.md |
| Native interop | P/Invoke, LibraryImport, ComWrappers, marshalling | P/Invoke, LibraryImport, ComWrappers, marshalling, cross-platform | references/native-interop.md |
| Input validation | .NET 10 AddValidation, FluentValidation | .NET 10 AddValidation, FluentValidation, ProblemDetails | references/input-validation.md |
| Validation patterns | DataAnnotations, IValidatableObject, IValidateOptions | DataAnnotations, IValidatableObject, IValidateOptions\<T\> | references/validation-patterns.md |
| Modern patterns | records, pattern matching, primary constructors | Records, pattern matching, primary constructors, C# 12-15 | references/modern-patterns.md |
| API design | naming, parameter ordering, return types, extensions | Naming, parameter ordering, return types, error patterns | references/api-design.md |
| Type design/perf | struct vs class, sealed, Span/Memory, collections | struct vs class, sealed, Span/Memory, collections | references/type-design-performance.md |
| Code smells | anti-patterns, async misuse, DI mistakes, fixes | Anti-patterns, async misuse, DI mistakes, fixes | references/code-smells.md |
| .NET releases | .NET 10, .NET 11, C# 14, C# 15, TFM, version, union, extension blocks, field keyword | Version matrix, new features, TFM-specific code generation | references/dotnet-releases.md |
| Globalization | CultureInfo, StringComparison, TimeZoneInfo, Rune, encoding | Culture-aware coding, string comparison, time zones, character processing | references/globalization.md |
| WASM interop | JSImport, JSExport, standalone WASM, wasm-experimental, browser | JSImport/JSExport, standalone .NET WASM, browser APIs, WASM AOT | references/wasm-interop.md |

## Scope

- C# language features (C# 8-15)
- .NET runtime patterns (async, DI, config, serialization, channels, LINQ)
- Code quality (analyzers, editorconfig, code smells, SOLID)
- Type design and domain modeling
- File I/O and native interop
- Globalization (string comparison, CultureInfo, time zones, character processing, encoding)
- Input validation at the model level (DataAnnotations, IValidatableObject, FluentValidation, Options validation)

## Out of scope

- ASP.NET Core / web API patterns (request-level validation, endpoint filters) -> [skill:dotnet-api]
- UI framework patterns -> [skill:dotnet-ui]
- Testing patterns -> [skill:dotnet-testing]
- Build/MSBuild/project setup -> [skill:dotnet-tooling]
- Performance profiling tools -> [skill:dotnet-tooling]
