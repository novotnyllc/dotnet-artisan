# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.4.2] - 2026-08-02

### Fixed

- **Codex hook loading and output** -- Removed unsupported hook metadata and emitted the required SessionStart result envelope so Codex loads and executes both plugin hooks.
- **Codex manifest validation** -- Removed the unsupported `hooks` manifest field and added regression checks for both invalid hook-file keys and Codex manifest drift.

### Removed

- **Bundled WinDbg MCP server** -- Removed the Windows-only WinDbg server from the cross-platform plugin MCP configuration.

## [1.4.1] - 2026-04-30

### Added

- **Marketplace-root plugin architecture** -- The .NET Artisan distribution is now organized as a dedicated plugin package inside the repository, with the root functioning as the marketplace discovery surface for easier multi-provider discovery.

### Changed

- **Cross-provider install and discovery flow** -- Documentation and validation now align plugin discovery/installation around the package-based layout, so Claude, GitHub Copilot, and Codex consume the same plugin source of truth.
- **Release/versioning workflow** -- Version synchronization and release metadata propagation were unified through the plugin package manifest path, reducing divergence between manifests, marketplace metadata, and release artifacts.
- **Tooling and CI checks** -- Packaging-aware validation and routing smoke scripts now operate against the plugin package as the unit of source truth, including manifest checks, hook/MCP checks, and skill-count assertions.

### Fixed

- **Invalid path handling in plugin validation** -- Routing validation now rejects malformed or unsafe manifest paths, preventing incorrect plugin source references from passing checks.
- **Post-move validation reliability** -- Marketplace and hook verification now correctly locate the plugin assets and provider indexes after the repository layout shift, eliminating failures caused by stale root-level assumptions.

## [1.4.0] - 2026-04-01

### Added

- **Cross-platform hook execution** -- Converted .NET session-start and prompt-routing hooks to Node.js so hook behavior is consistent across environments and no longer depends on shell tooling.
- **Pre-release JavaScript hook validation** -- Marketplace validation now checks hook scripts with Node syntax validation, catching hook regressions during release checks instead of at runtime.

### Changed

- **Hook runtime documentation and configuration** -- Plugin registration and setup guidance now reflect the Node-based hook model and clarify the required runtime in a single model, aligning user-facing setup with actual hook execution.
- **Hook contract tests focus** -- Validation now verifies the prompt-reminder contract (including suppression behavior) directly against the new hook implementations rather than legacy jq/Python fallback scenarios.

### Fixed

- **Environment fragility in hook execution** -- Removed shell/jq/Python dependencies from hook logic, reducing failures in setups where those tools are missing or misconfigured and improving reliability of .NET routing reminders.

## [1.3.0] - 2026-03-07

### Added

- **Rich plugin identity metadata** -- Added a full user-facing plugin interface description (category, capability profile, developer info, and marketing text) so tooling can present and index the plugin with clearer marketplace context.
- **OpenCode and Codex onboarding guidance** -- Added explicit install instructions for OpenCode and Codex so users can onboard the plugin consistently across more AI coding environments.
- **Preview .NET feature coverage** -- Added C# union-type guidance, including conversion rules, exhaustive matching behavior, and preview-target code-generation advice, extending capability coverage for modern .NET scenarios.

### Changed

- **.NET assistance routing language scope** -- Updated .NET release guidance to explicitly include newer feature areas (including union types, field semantics, and extension blocks) for newer frameworks, improving framework-appropriate recommendations.
- **Guidance style for .NET responses** -- Added a simplicity-first workflow expectation so generated solutions default to direct, low-complexity implementations when possible, reducing over-engineered recommendations.
- **Plugin setup across Copilot now uses plugin flow** -- Updated Copilot-facing instructions to the current plugin installation workflow, replacing the older skill-based flow.

### Fixed

- **Marketplace validation path handling** -- Fixed validation behavior so plugin source locations are resolved correctly from the repository root, preventing install/publishing checks from failing due to path resolution mismatches.

## [1.2.0] - 2026-03-06

### Added

- **Codex plugin discovery support** -- Added explicit Codex plugin manifest and marketplace discovery capabilities so the plugin can be indexed and validated in Codex environments in addition to existing Claude flow support.
- **Gateway-based .NET routing** -- Added a dedicated pre-routing step that detects .NET intent and version context before delegating to domain skills, with clearer defaults for ambiguous “build me” requests and improved multi-domain handoff behavior.
- **Expanded backend guidance scope** -- Added new content on HybridCache, reverse-proxy/API gateway patterns, ASP.NET Identity setup, and Office/PDF document workflows, giving users guidance for caching, authentication, and document generation scenarios without leaving the skill set.

### Changed

- **Skill catalog now includes nine capabilities** -- The plugin now documents and enforces a 9-skill catalog and updated routing/budget guidance, including explicit defaults for domain selection and invocation flow.
- **Reference delivery model clarified** -- The plugin now emphasizes on-demand loading of deep-dive references behind the high-level skill catalog, improving guidance coverage while keeping the loaded baseline predictable.
- **Backend integration defaults updated** -- Messaging recommendations were modernized toward Wolverine for new work (with explicit mappings from older patterns), and API guidance now includes updated recommendations for identity, hybrid caching, YARP routing, and file-based app scenarios.

### Fixed

- **Marketplace validation hardening** -- Validation now checks Codex manifest and marketplace metadata consistency (required fields, local resolution, plugin linkage), preventing broken plugin registration states from passing unnoticed.
- **Routing smoke-test contract** -- Routing validation no longer incorrectly excludes the dotnet advisor path from implicit invocation expectations, aligning test behavior with the actual routing model and reducing false failures.

## [1.1.1] - 2026-03-05

### Added

- **Skills execution safety** -- Added a `using-dotnet` process gate and explicit advisor ordering so skill workflows now validate .NET usage and run advisors in a predictable sequence before continuing.

## [1.1.0] - 2026-03-05

### Added
- Skill metadata quality lints for name format/length, description hard cap, and negative-trigger phrasing.
- Skill hygiene lints for one-level resource folders, forward-slash pathing, and human-doc detection in skill directories.

### Changed
- Updated all 8 consolidated skill descriptions to include explicit negative routing triggers.
- Codex metadata validation now re-validates `skills[]` paths with path-safety checks before per-skill file probing.
- CI skill-count assertion now uses correct GNU `find` option ordering (`-maxdepth` before `-name`).
- Version bump from `1.0.0` to `1.1.0` across plugin metadata, marketplace metadata, and README badge.

## [1.0.0] - 2026-02-27

### Changed
- **Skill consolidation** -- Consolidated 131 individual skills into 8 broad domain skills (dotnet-advisor, dotnet-csharp, dotnet-api, dotnet-ui, dotnet-testing, dotnet-devops, dotnet-tooling, dotnet-debugging). Each skill includes `references/` companion files preserving all source content. Description budget per skill raised from 120 to 600 characters.
- **Updated agents and routing** -- All 14 specialist agents updated with consolidated skill references. dotnet-advisor rewritten as router for 8 skills.
- **CI gates updated** -- Skill count assertion updated from 131 to 8. Validator thresholds updated (`--projected-skills 8`, `--max-desc-chars 600`).
- **Smoke tests remapped** -- Copilot smoke test cases and agent routing cases remapped to 8-skill names. Case IDs preserved for CI filter stability.
### Removed
- **Eval harness deleted** -- Removed `tests/evals/` directory (~8,100 lines of Python eval runners, datasets, rubrics, baselines, results). Structural validators (`validate-skills.sh`, `validate-marketplace.sh`) remain as the CI gates.
- **Legacy skill directories** -- Removed 30 old skill directories superseded by the 8 consolidated skills.

### Added

- **Offline skill evaluation** -- Added an offline evaluation framework with rubric schema, datasets, and runners for quality, confusion-matrix, size impact, activation, and A/B effectiveness checks to continuously measure skill behavior.
- **Evaluation orchestration** -- Added a unified suite runner and deterministic `--limit` sampling mode so evaluation runs can be executed reproducibly at scale.

### Changed

- **Skill taxonomy** -- Consolidated a very large skill set into 8 broad skill families (including dotnet and advisor areas) and updated plugin manifests/docs so users work with a cleaner, less redundant set of skill invocations.
- **Reference organization** -- Reworked reference/docs structure (including `references/` normalization and invocability tables) to align with the consolidated skill model and remove stale examples/placeholders.

### Fixed

- **Reference validation and accuracy** -- Fixed stale/misattributed docs and made reference validation stricter (including case-insensitive slug/title checks), which reduced broken pointers and inaccurate skill references across large portions of docs.
- **Evaluation reliability** -- Fixed CLI evaluation execution to use the stable CLI path, with stronger subprocess behavior and argument compatibility (`TryWrite` flow fixes, safer defaults, no unsupported flags, better timeout/workdir handling), plus improved cost/status accounting so results are trustworthy.
- **Failure handling and reporting** -- Improved evaluation failure behavior by adding explicit status/error classifications, fail-fast behavior, abort handling, and clearer progress/triage reporting so issues are surfaced quickly and are easier to act on.

## [0.3.0] - 2026-02-21

### Added
- **GitHub Copilot CLI compatibility** -- Flat `skills/<skill-name>/` layout enables Copilot's one-level-deep skill scanning. All 131 SKILL.md files include `license: MIT` and unquoted descriptions for Copilot CLI compatibility.
- **32-skill routing strategy** -- Documented Copilot CLI display limit behavior and `dotnet-advisor` meta-routing strategy in CONTRIBUTING-SKILLS.md.
### Changed
- **Flat skill directory layout** -- Migrated from the prior nested category layout to flat `skills/<skill-name>/` to support cross-provider discovery (Claude Code, Copilot CLI, Codex).
- **Frontmatter migration** -- Removed quoted descriptions and added `license: MIT` across all 131 skills for Copilot CLI compatibility.
- **Similarity scoring** -- Removed same-category boost from similarity detection (no longer applicable with flat layout).
- **Updated documentation** -- AGENTS.md, CONTRIBUTING.md, CONTRIBUTING-SKILLS.md, README.md, and docs updated for flat layout, Copilot compatibility, and canonical skill count of 131.

### Added

- **Flat skill layout and Copilot-safe metadata** -- Reorganized skills into a single-level catalog and migrated skill frontmatter to a Copilot-safe format, including explicit user-invocable metadata, so skill discovery and routing are more reliable.
- **Copilot compatibility test coverage** -- Added Copilot activation smoke tests and cross-provider regression testing with CI integration, including per-category pass reporting and workspace isolation for clearer validation.

### Changed

- **Routing and validation for Copilot compatibility** -- Updated validators/baselines and documentation to match the new flat layout and 32-skill routing strategy, aligning required fields and guidance with actual runtime behavior.

### Fixed

- **Provider routing failures** -- Corrected the Microsoft Docs MCP key issue and updated compare-agent routing logic with sampling plus provider-specific timeouts to reduce false routing failures.
- **Metadata and baseline compatibility checks** -- Fixed metadata-last and baseline/reference handling so Copilot CLI v0.0.412 verification and safety checks behave correctly.
- **Documentation accuracy for available skills** -- Fixed stale counts, nested-path remnants, and missing catalog entries so user-facing skill metadata and documentation reflect the actual plugin state.

## [0.2.0] - 2026-02-20

### Added

- **Invocation contract enforcement** -- Added MCP invocation-contract and routing-language compliance checks (including canonical IDs and compliance reporting), so invalid skill invocation definitions are caught before execution.
- **Routing quality tooling** -- Added routing language quality checks such as semantic overlap detection plus baseline and ownership audits to reduce ambiguous or conflicting guidance between skills.
- **Agent-routing CI validation** -- Added provider-matrix CI flows and agent skill-usage checks in the test runner to catch routing regressions with stronger regression guardrails.

### Changed

- **Routing execution and telemetry** -- Updated routing execution to use provider-matrix workflows with run-ID isolation, concurrency bounds, progress logging, and lifecycle telemetry for clearer, more reliable evaluations.
- **Routing schema and gating** -- Extended routing case schemas with optional, disallowed, and provider-alias fields and introduced tier-based evidence gating with ComputeTier, producing more predictable routing outcomes.

### Fixed

- **Routing decision consistency** -- Fixed path normalization, optional/disallowed token handling, provider aliasing, and merge behavior so routing candidates are evaluated consistently across runs.
- **Failure handling accuracy** -- Fixed CLI/transport failure detection and preserved script exit codes so diagnostics are reliable, with reduced noisy or misleading failure reporting.
- **Validation accuracy** -- Fixed validator and frontmatter parsing issues plus metadata/spec drift, ensuring reported thresholds and guidance stay aligned with actual runtime behavior.

### Changed (Routing Language)

- **Standardized routing language** across the full skill catalog and 14 agents for reliable skill discovery. Descriptions follow Action + Domain + Differentiator formula, all cross-references use `[skill:name]` syntax, and every skill has explicit Scope and Out-of-scope sections.
- **Added semantic similarity detection** to prevent description overlap between skills. CI gates on baseline regression with suppression list for known-acceptable pairs.
- **Tightened CI quality gates** -- agent bare-reference counts gated at zero, per-key baseline regression check, similarity baseline regression enabled.
- **Updated contributor documentation** -- CONTRIBUTING-SKILLS.md, CONTRIBUTING.md, and AGENTS.md updated with canonical routing-language conventions and similarity avoidance guidance.

## [0.1.1] - 2026-02-17

### Added

- **dotnet-file-io** skill (Core C#) -- FileStream async patterns, RandomAccess API, FileSystemWatcher debouncing, MemoryMappedFile, path traversal prevention, secure temp files, cross-platform considerations
- `.agents/openai.yaml` at repo root for Codex skill discovery
- **Version bump automation** -- `scripts/bump.sh` propagates version to plugin.json, marketplace.json (plugin entry + metadata), README badge, and CHANGELOG footer links
- **Root marketplace validation** -- `scripts/validate-root-marketplace.sh` as shared validation (used by both `validate-marketplace.sh` and CI workflows directly)
- **Plugin.json enrichment fields** -- `author`, `homepage`, `repository`, `license`, `keywords` validated by `validate-marketplace.sh`

### Changed

- **Marketplace restructure** -- Converted repo to flat marketplace layout with root `.claude-plugin/marketplace.json` discovery file listing dotnet-artisan as the available plugin (`"source": "./"`)
- **Removed dist pipeline** -- Deleted `scripts/generate_dist.py`, `scripts/validate_cross_agent.py`, and all `dist/` generation. Source files ARE the plugin; no build step needed
- **Per-plugin versioning** -- Release workflow now uses `dotnet-artisan/v*` tag format instead of `v*`
- **CI updated** -- `validate.yml` no longer runs dist generation or cross-agent conformance; added root marketplace.json validation and 3-way version consistency check. `release.yml` removed Pages deployment, now extracts release notes from CHANGELOG.md dynamically
- **Marketplace metadata** -- Root marketplace.json restructured to official Anthropic schema (`$schema`, `name`, `owner`, `metadata`, per-plugin `category`/`homepage`/`keywords`). Plugin.json enriched with `author`, `homepage`, `repository`, `license`, `keywords`
- **Validation deduplication** -- `validate-marketplace.sh` root marketplace section now delegates to `scripts/validate-root-marketplace.sh` instead of duplicating checks
- **Release documentation** -- CONTRIBUTING.md expanded with version management, bump script usage, tag convention (`dotnet-artisan/vX.Y.Z`), and release workflow documentation
- **Agent count corrected** -- README now lists all 14 specialist agents (was 9)
- **Description budget trimmed** from 13,481 to 11,948 chars (84 descriptions trimmed, removed filler words and redundant phrases) -- now below the 12,000-char WARN threshold
- Updated `--projected-skills` parameter in `validate-skills.sh` from 100 to 121 to match actual registered skill count
- Quality-checked 12 new skills from fn-30 through fn-36 for description formula compliance and cross-reference syntax

### Removed

- Root-level `plugin.json` (replaced by marketplace.json + per-plugin plugin.json)
- Cross-agent dist generation pipeline (`generate_dist.py`, `validate_cross_agent.py`) -- source files are the plugin, no transformation needed
- GitHub Pages deployment from release workflow
- Stale files: `docs/fleet-review-rubric.md`, `docs/review-reports/`, `scripts/ralph/runs/`, dist pipeline scripts
- Archived fleet review rubric and consolidated findings as historical snapshots (fn-29 audit, fn-37 cleanup, fn-40 resolution)

## [0.1.0] - 2026-02-14

### Added

- Plugin skeleton and infrastructure with `plugin.json`, `marketplace.json`, and validation scripts
- **Foundation skills** (4) -- Advisor routing, version detection, project analysis, self-publish
- **Core C# skills** (7) -- Modern patterns, coding standards, async/await, nullable reference types, dependency injection, configuration, source generators
- **Project structure skills** (6) -- Project structure, scaffolding, analyzers, CI setup, testing setup, modernization
- **Architecture skills** (10) -- Architecture patterns, background services, resilience, HTTP client, observability, EF Core patterns, EF Core architecture, data access strategy, containers, container deployment
- **Serialization and communication skills** (4) -- gRPC, real-time communication (SignalR/WebSockets), serialization, service communication
- **Testing skills** (10) -- Testing strategy, xUnit, integration testing, UI testing core, Blazor testing, MAUI testing, Uno testing, Playwright, snapshot testing, test quality
- **API development skills** (5) -- Minimal APIs, API versioning, OpenAPI, API security, input validation
- **Security skills** (3) -- OWASP compliance, secrets management, cryptography
- **UI framework skills** (13) -- Blazor patterns, Blazor components, Blazor auth, Uno Platform, Uno targets, Uno MCP, MAUI development, MAUI AOT, WinUI, WPF modern, WPF migration, WinForms basics, UI chooser
- **Native AOT skills** (4) -- Native AOT, AOT architecture, trimming, AOT WASM
- **CLI tools skills** (5) -- System.CommandLine, CLI architecture, CLI distribution, CLI packaging, CLI release pipeline
- **Agent meta-skills** (4) -- Agent gotchas, build analysis, csproj reading, solution navigation
- **Performance skills** (4) -- BenchmarkDotNet, performance patterns, profiling, CI benchmarking
- **CI/CD skills** (8) -- GitHub Actions patterns, build/test, publish, deploy; Azure DevOps patterns, build/test, publish, unique features
- **Packaging and publishing skills** (3) -- NuGet authoring, MSIX, GitHub Releases
- **Release management skill** (1) -- Release management
- **Documentation skills** (5) -- Documentation strategy, Mermaid diagrams, GitHub docs, XML docs, API docs
- **Localization skill** (1) -- Localization
- 9 specialist agents: dotnet-architect, concurrency specialist, security reviewer, Blazor specialist, Uno specialist, MAUI specialist, performance analyst, benchmark designer, docs generator
- Session hooks for start context and post-edit validation
- MCP server integrations for Context7, Uno Platform, and Microsoft Learn
- Cross-agent build pipeline generating dist outputs for Claude Code, GitHub Copilot, and OpenAI Codex
- Validation scripts for skills, marketplace, distribution generation, and cross-agent conformance
- README with skill catalog, Mermaid architecture diagrams, and cross-agent documentation
- CONTRIBUTING guide with skill authoring conventions and PR process

[unreleased]: https://github.com/novotnyllc/dotnet-artisan/compare/dotnet-artisan/v1.4.2...HEAD
[1.4.2]: https://github.com/novotnyllc/dotnet-artisan/compare/dotnet-artisan/v1.4.1...dotnet-artisan/v1.4.2
[1.4.1]: https://github.com/novotnyllc/dotnet-artisan/compare/dotnet-artisan/v1.4.0...dotnet-artisan/v1.4.1
[1.4.0]: https://github.com/novotnyllc/dotnet-artisan/compare/dotnet-artisan/v1.3.0...dotnet-artisan/v1.4.0
[1.3.0]: https://github.com/novotnyllc/dotnet-artisan/compare/dotnet-artisan/v1.2.0...dotnet-artisan/v1.3.0
[1.2.0]: https://github.com/novotnyllc/dotnet-artisan/compare/dotnet-artisan/v1.1.1...dotnet-artisan/v1.2.0
[1.1.1]: https://github.com/novotnyllc/dotnet-artisan/compare/dotnet-artisan/v1.1.0...dotnet-artisan/v1.1.1
[1.1.0]: https://github.com/novotnyllc/dotnet-artisan/compare/dotnet-artisan/v1.0.0...dotnet-artisan/v1.1.0
[1.0.0]: https://github.com/novotnyllc/dotnet-artisan/compare/dotnet-artisan/v0.3.0...dotnet-artisan/v1.0.0
[0.3.0]: https://github.com/novotnyllc/dotnet-artisan/compare/dotnet-artisan/v0.2.0...dotnet-artisan/v0.3.0
[0.2.0]: https://github.com/novotnyllc/dotnet-artisan/compare/dotnet-artisan/v0.1.1...dotnet-artisan/v0.2.0
[0.1.1]: https://github.com/novotnyllc/dotnet-artisan/releases/tag/dotnet-artisan/v0.1.1
[0.1.0]: https://github.com/novotnyllc/dotnet-artisan/commits/main  <!-- no release tag for 0.1.0; links to main branch history -->
