---
name: dotnet-testing
description: Defines .NET test strategy and implementation patterns across xUnit v3 (Facts, Theories, fixtures, IAsyncLifetime), integration testing (WebApplicationFactory, Testcontainers), Aspire testing (DistributedApplicationTestingBuilder), snapshot testing (Verify, scrubbing), Playwright E2E browser automation, BenchmarkDotNet microbenchmarks, code coverage (Coverlet), mutation testing (Stryker.NET), UI testing (page objects, selectors), and AOT WASM test compilation. Spans 13 topic areas. Do not use for production API architecture or CI workflow authoring.
license: MIT
user-invocable: false
---

# dotnet-testing

## Overview

Testing strategy, frameworks, and quality tooling for .NET applications. This consolidated skill spans 13 topic areas. Load the appropriate companion file from `references/` based on the routing table below.

Baseline dependency: `references/testing-strategy.md` defines the unit vs integration vs E2E decision tree and test doubles selection that inform all testing decisions. Load it by default whenever a testing approach needs to be chosen.

Most-shared companion: `references/xunit.md` covers xUnit v3 framework features used by integration, snapshot, and UI testing companions.

## Routing Table

| Topic | Keywords | Description | Companion File |
|-------|----------|-------------|----------------|
| Strategy | unit vs integration vs E2E, test doubles | Unit vs integration vs E2E decision tree, test doubles selection | references/testing-strategy.md |
| xUnit | Facts, Theories, fixtures, parallelism | xUnit v3 Facts, Theories, fixtures, parallelism, IAsyncLifetime | references/xunit.md |
| Integration | WebApplicationFactory, Testcontainers, Aspire | WebApplicationFactory, Testcontainers, Aspire, database fixtures | references/integration-testing.md |
| Snapshot | Verify, scrubbing, API responses | Verify library, scrubbing, custom converters, HTTP response snapshots | references/snapshot-testing.md |
| Playwright | E2E browser, CI caching, trace viewer | Playwright E2E browser automation, CI caching, trace viewer, codegen | references/playwright.md |
| BenchmarkDotNet | microbenchmarks, memory diagnosers | BenchmarkDotNet microbenchmarks, memory diagnosers, baselines | references/benchmarkdotnet.md |
| CI benchmarking | threshold alerts, baseline tracking | CI benchmark regression detection, threshold alerts, baseline tracking | references/ci-benchmarking.md |
| Test quality | Coverlet, Stryker.NET, flaky tests | Coverlet code coverage, Stryker.NET mutation testing, flaky tests | references/test-quality.md |
| Add testing | scaffold xUnit project, coverlet, layout | Scaffold xUnit project, coverlet setup, directory layout | references/add-testing.md |
| Slopwatch | LLM reward hacking detection | Slopwatch CLI for LLM reward hacking detection | references/slopwatch.md |
| AOT WASM | Blazor/Uno WASM AOT, size, lazy loading | Blazor/Uno WASM AOT compilation, size vs speed, lazy loading, Brotli | references/aot-wasm.md |
| UI testing core | page objects, selectors, async waits | Page object model, test selectors, async waits, accessibility testing | references/ui-testing-core.md |
| Aspire testing | DistributedApplicationTestingBuilder, Aspire test host | Aspire test host, service HTTP clients, resource health | references/aspire-testing.md |

## Scope

- Test strategy and architecture (unit, integration, E2E)
- xUnit v3 test authoring
- Integration testing (WebApplicationFactory, Testcontainers)
- E2E browser testing (Playwright)
- Snapshot testing (Verify)
- Benchmarking (BenchmarkDotNet, CI gating)
- Quality (coverage, mutation testing)
- Cross-framework UI testing patterns
- Test scaffolding

## Out of scope

- UI framework-specific testing (bUnit, Appium) -> [skill:dotnet-ui]
- CI/CD pipeline configuration -> [skill:dotnet-devops]
- Performance profiling -> [skill:dotnet-tooling]
