# Release Management

Release lifecycle management for .NET projects: Nerdbank.GitVersioning (NBGV) setup with `version.json` configuration, version height calculation, and public release vs pre-release modes; SemVer 2.0 strategy for .NET libraries (when to bump major/minor/patch, API compatibility considerations) and applications (build metadata, deployment versioning); changelog generation (Keep a Changelog format, auto-generation with git-cliff and conventional commits); pre-release version workflows (alpha, beta, rc, stable progression); and release branching patterns (release branches, hotfix branches, trunk-based releases with tags).

**Version assumptions:** .NET 8.0+ baseline. `Nerdbank.GitVersioning` 3.6+ (current stable). SemVer 2.0 specification.

## NBGV (Nerdbank.GitVersioning)

NBGV calculates deterministic version numbers from git history. The version is derived from a `version.json` file and the git commit height (number of commits since the version was set), producing unique versions for every commit without manual version bumps.

### Installation

```bash
# Install NBGV CLI tool
dotnet tool install --global nbgv

# Initialize NBGV in a repository
nbgv install

# This creates version.json at the repo root
```

### version.json Configuration

```json
{
  "$schema": "https://raw.githubusercontent.com/dotnet/Nerdbank.GitVersioning/main/src/NerdBank.GitVersioning/version.schema.json",
  "version": "1.0",
  "publicReleaseRefSpec": [
    "^refs/heads/main$",
    "^refs/tags/v\\d+\\.\\d+(\\.\\d+)?(-.*)?$"
  ],
  "cloudBuild": {
    "buildNumber": {
      "enabled": true
    },
    "setVersionVariables": true
  }
}
```

### version.json Field Reference

| Field | Purpose | Example |
|-------|---------|---------|
| `version` | Base version (major.minor, optional patch) | `"1.0"`, `"2.3.0"` |
| `publicReleaseRefSpec` | Regex patterns for branches/tags that produce public versions | `["^refs/heads/main$"]` |
| `cloudBuild.buildNumber.enabled` | Set CI build number to calculated version | `true` |
| `cloudBuild.setVersionVariables` | Export version as CI environment variables | `true` |
| `nugetPackageVersion` | Override NuGet package version format | `{"semVer": 2}` |
| `assemblyVersion.precision` | Assembly version component count | `"major"`, `"minor"`, `"build"`, `"revision"` |
| `inherit` | Inherit from parent directory version.json | `true` |

### How Version Height Works

NBGV counts the number of commits since the `version` field was last changed in `version.json`. This count becomes the patch version:

```
version.json: "version": "1.2"

Commit history:
  abc1234  feat: add caching          -> 1.2.3
  def5678  fix: null check            -> 1.2.2
  ghi9012  chore: update deps         -> 1.2.1
  jkl3456  Bump version to 1.2        -> 1.2.0  (version.json changed here)
```

The version height ensures every commit has a unique version without manual intervention.

### Pre-Release vs Public Release

```json
{
  "version": "1.2-beta",
  "publicReleaseRefSpec": [
    "^refs/heads/main$",
    "^refs/tags/v\\d+\\.\\d+(\\.\\d+)?(-.*)?$"
  ]
}
```

| Branch/Ref | Computed Version | Notes |
|-----------|-----------------|-------|
| `main` (public) | `1.2.5-beta` | Public pre-release, height=5 |
| `feature/foo` (non-public) | `1.2.5-beta.gcommithash` | Includes git hash suffix |
| Tag `v1.2.5` (public) | `1.2.5` | Remove `-beta` before tagging |

To release a stable version, remove the pre-release suffix from `version.json` before the release commit:

```json
{
  "version": "1.2"
}
```

### NBGV CLI Commands

```bash
# Show the current calculated version
nbgv get-version

# Show specific version properties
nbgv get-version -v NuGetPackageVersion
nbgv get-version -v SemVer2

# Prepare for a release (creates release branch, bumps version)
nbgv prepare-release

# Set version variables for CI
nbgv cloud
```

### Monorepo NBGV Configuration

For monorepos with independently versioned projects, place `version.json` in each project directory and use `inherit`:

```
repo-root/
  version.json              <- { "version": "1.0" }
  src/
    LibraryA/
      version.json          <- { "version": "2.3", "inherit": true }
    LibraryB/
      version.json          <- { "version": "1.1-beta", "inherit": true }
```

The `inherit` field pulls settings (like `publicReleaseRefSpec` and `cloudBuild`) from the parent `version.json` while overriding the version number.

---

## SemVer Strategy for .NET Libraries

### When to Bump Versions

SemVer 2.0 specifies version format `MAJOR.MINOR.PATCH`:

| Change Type | Version Bump | Examples |
|-------------|-------------|----------|
| Breaking API changes | **Major** | Removing public types/members, changing method signatures, renaming namespaces |
| New features (backward compatible) | **Minor** | Adding public types/members, new extension methods, new overloads |
| Bug fixes (backward compatible) | **Patch** | Fixing incorrect behavior, performance improvements, internal refactors |

### .NET-Specific Breaking Change Considerations

| Change | Breaking? | Notes |
|--------|-----------|-------|
| Remove public type | Yes (Major) | Consumers referencing it will fail to compile |
| Remove public method | Yes (Major) | Direct callers will fail |
| Add required parameter to public method | Yes (Major) | Existing callers do not supply it |
| Add optional parameter to public method | No (Minor) | Binary compatible but source-breaking for callers using named arguments |
| Change return type | Yes (Major) | Binary and source breaking |
| Add new public type | No (Minor) | No existing code affected |
| Add new overload | No (Minor) | Existing calls still resolve |
| Change internal implementation | No (Patch) | No public API change |
| Change default value of optional parameter | No (Patch) | Binary compatible (value embedded at call site on recompile) |
| Seal a previously unsealed class | Yes (Major) | Consumers inheriting from it will fail |
| Make a virtual method non-virtual | Yes (Major) | Consumers overriding it will fail |

### API Compatibility Validation

Use `EnablePackageValidation` to catch accidental breaking changes. For full package validation setup, see [skill:dotnet-devops] `references/nuget-authoring.md`.

```xml
<PropertyGroup>
  <EnablePackageValidation>true</EnablePackageValidation>
  <PackageValidationBaselineVersion>1.0.0</PackageValidationBaselineVersion>
</PropertyGroup>
```

---

## SemVer Strategy for Applications

Applications (web apps, desktop apps, services) have different versioning considerations than libraries because they do not have public API consumers.

### Application Versioning Approaches

| Approach | Format | Best For |
|----------|--------|----------|
| SemVer (feature-driven) | `1.2.3` | Installed desktop/mobile apps with user-visible versioning |
| CalVer (calendar-based) | `2024.1.15` | SaaS apps with continuous deployment |
| Build number | `1.2.3+42` | CI-driven versioning with build metadata |
| NBGV height | `1.2.42` | Automated versioning from git commits |

### Build Metadata

SemVer 2.0 allows `+` suffixed build metadata that does not affect version precedence:

```
1.2.3+build.42        Build number
1.2.3+abcdef          Git commit hash
1.2.3+2024.01.15      Build date
1.2.3-beta.1+42       Pre-release with build metadata
```

Build metadata is useful for tracing a deployed binary back to its source commit. NBGV appends git metadata automatically.

### Deployment Versioning

For continuously deployed services, version stamping aids troubleshooting:

```xml
<PropertyGroup>
  <!-- Embed full version in assembly for runtime introspection -->
  <InformationalVersion>1.2.3+abcdef.2024-01-15</InformationalVersion>
</PropertyGroup>
```

Read at runtime:

```csharp
var version = typeof(Program).Assembly
    .GetCustomAttribute<System.Reflection.AssemblyInformationalVersionAttribute>()
    ?.InformationalVersion;
// Returns "1.2.3+abcdef.2024-01-15"
```

---

## Changelog Generation

### Keep a Changelog Format

The [Keep a Changelog](https://keepachangelog.com/) format is a widely adopted standard:

```markdown
# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Widget caching support for improved throughput

## [1.2.0] - 2024-03-15

### Added
- Fluent API for widget configuration
- Batch processing support

### Changed
- Improved error messages for invalid widget states

### Fixed
- Memory leak in widget pool under high concurrency
- Timezone handling in scheduled widget operations

### Deprecated
- `Widget.Create()` static method -- use `WidgetBuilder` instead

## [1.1.0] - 2024-01-10

### Added
- Widget serialization support

[Unreleased]: https://github.com/mycompany/widgets/compare/v1.2.0...HEAD
[1.2.0]: https://github.com/mycompany/widgets/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/mycompany/widgets/releases/tag/v1.1.0
```

### Section Types

| Section | Purpose |
|---------|---------|
| `Added` | New features |
| `Changed` | Changes to existing functionality |
| `Deprecated` | Features that will be removed in future versions |
| `Removed` | Features removed in this release |
| `Fixed` | Bug fixes |
| `Security` | Vulnerability fixes |

### Auto-Generation with git-cliff

[git-cliff](https://git-cliff.org/) generates changelogs from conventional commits:

```bash
# Install git-cliff
cargo install git-cliff

# Generate changelog for all versions
git cliff --output CHANGELOG.md

# Generate changelog for unreleased changes only
git cliff --unreleased --output CHANGELOG.md

# Generate notes for a specific tag range
git cliff --tag v1.2.0 --unreleased
```

Configure `cliff.toml` for .NET conventional commit patterns:

```toml
# cliff.toml
[changelog]
header = """
# Changelog\n
All notable changes to this project will be documented in this file.\n
"""
body = """
{% if version %}\
    ## [{{ version | trim_start_matches(pat="v") }}] - {{ timestamp | date(format="%Y-%m-%d") }}
{% else %}\
    ## [Unreleased]
{% endif %}\
{% for group, commits in commits | group_by(attribute="group") %}
    ### {{ group | upper_first }}
    {% for commit in commits %}
        - {{ commit.message | upper_first }}\
    {% endfor %}
{% endfor %}\n
"""
trim = true

[git]
conventional_commits = true
filter_unconventional = true
commit_parsers = [
    { message = "^feat", group = "Added" },
    { message = "^fix", group = "Fixed" },
    { message = "^perf", group = "Changed" },
    { message = "^refactor", group = "Changed" },
    { message = "^docs", group = "Documentation" },
    { message = "^chore\\(deps\\)", group = "Dependencies" },
    { message = "^chore", skip = true },
    { message = "^ci", skip = true },
    { message = "^test", skip = true },
]
```

### Conventional Commit Format

```
feat: add widget caching support
fix: correct timezone handling in scheduler
feat!: rename Widget.Create() to WidgetBuilder.Build()
chore(deps): update System.Text.Json to 8.0.5
docs: update API reference for caching

Breaking change in body:
feat: redesign widget API

BREAKING CHANGE: Widget.Create() has been removed. Use WidgetBuilder instead.
```

| Prefix | SemVer Impact | Changelog Section |
|--------|--------------|-------------------|
| `feat:` | Minor | Added |
| `fix:` | Patch | Fixed |
| `feat!:` or `BREAKING CHANGE:` | Major | Breaking Changes |
| `perf:` | Patch | Changed |
| `refactor:` | Patch | Changed |
| `docs:` | None | Documentation |
| `chore:` | None | (skipped) |

---

## Pre-Release Version Workflows

### Standard Pre-Release Progression

```
alpha -> beta -> rc -> stable

1.0.0-alpha.1  Early development, API unstable
1.0.0-alpha.2  Continued alpha iteration
1.0.0-beta.1   Feature-complete, API stabilizing
1.0.0-beta.2   Beta bug fixes
1.0.0-rc.1     Release candidate, final validation
1.0.0-rc.2     RC bug fix (if needed)
1.0.0          Stable release
```

### NBGV Pre-Release Workflow

```bash
# Start with pre-release suffix in version.json
# version.json: { "version": "1.0-alpha" }
# Produces: 1.0.1-alpha, 1.0.2-alpha, ...

# Promote to beta
# Edit version.json: { "version": "1.0-beta" }
# Produces: 1.0.1-beta, 1.0.2-beta, ...

# Promote to rc
# Edit version.json: { "version": "1.0-rc" }
# Produces: 1.0.1-rc, 1.0.2-rc, ...

# Promote to stable
# Edit version.json: { "version": "1.0" }
# Produces: 1.0.1, 1.0.2, ...
```

### Manual Pre-Release Workflow

For projects not using NBGV:

```xml
<!-- In .csproj or Directory.Build.props -->
<PropertyGroup>
  <VersionPrefix>1.0.0</VersionPrefix>
  <VersionSuffix>beta.1</VersionSuffix>
  <!-- Produces: 1.0.0-beta.1 -->
</PropertyGroup>
```

Override from CI:

```bash
# CI sets the pre-release suffix
dotnet pack /p:VersionSuffix="beta.$(BUILD_NUMBER)"

# Stable release: omit VersionSuffix
dotnet pack
```

### NuGet Pre-Release Ordering

NuGet follows SemVer 2.0 pre-release precedence:

```
1.0.0-alpha < 1.0.0-alpha.1 < 1.0.0-alpha.2
1.0.0-alpha.2 < 1.0.0-beta
1.0.0-beta < 1.0.0-beta.1
1.0.0-rc.1 < 1.0.0
```

Numeric identifiers are compared as integers; alphabetic identifiers are compared lexically.

---

## Release Branching Patterns

### Trunk-Based with Tags

The simplest release model. All development happens on `main`, releases are marked with tags.

```
main:  A -- B -- C -- D -- E -- F -- G
                 |              |
              v1.0.0         v1.1.0
```

```bash
# Tag and push for release
git tag -a v1.0.0 -m "Release v1.0.0"
git push origin v1.0.0
```

**Best for:** Libraries, small teams, continuous delivery.

### Release Branches

Create a release branch for stabilization while `main` continues development.

```
main:      A -- B -- C -- D -- E -- F -- G
                      \
release/1.0:           C' -- D' -- E'
                              |
                           v1.0.0
```

```bash
# Create release branch
git checkout -b release/1.0 main

# Stabilize on release branch (bug fixes only)
git commit -m "fix: correct null check in widget pool"

# Tag and release
git tag -a v1.0.0 -m "Release v1.0.0"
git push origin release/1.0 v1.0.0

# Merge fixes back to main
git checkout main
git merge release/1.0
```

**Best for:** Products with support contracts, LTS versions, teams needing parallel development and stabilization.

### NBGV prepare-release

NBGV automates release branch creation and version bumping:

```bash
# Creates release/v1.0 branch, bumps main to 1.1-alpha
nbgv prepare-release

# What this does:
# 1. Creates branch "release/v1.0" from current commit
# 2. On release branch: removes pre-release suffix (version: "1.0")
# 3. On main: bumps to "1.1-alpha" (next development version)
```

### Hotfix Branches

Emergency fixes for released versions:

```
main:         A -- B -- C -- D -- E
                         \
release/1.0:              C' -- v1.0.0
                                  \
hotfix/1.0.1:                      F' -- v1.0.1
```

```bash
# Branch from the release tag
git checkout -b hotfix/1.0.1 v1.0.0

# Fix the critical issue
git commit -m "fix: critical security vulnerability in auth handler"

# Tag and release the hotfix
git tag -a v1.0.1 -m "Hotfix v1.0.1"
git push origin hotfix/1.0.1 v1.0.1

# Merge hotfix back to main
git checkout main
git merge hotfix/1.0.1
```

### Branching Pattern Comparison

| Pattern | Release Cadence | Parallel Versions | Complexity |
|---------|----------------|-------------------|------------|
| Trunk + tags | Continuous | No | Low |
| Release branches | Scheduled | Yes | Medium |
| GitFlow (full) | Scheduled | Yes | High |

For most .NET open-source libraries, trunk-based with tags and NBGV is sufficient. Reserve release branches for products that maintain multiple supported versions simultaneously.

---

## Agent Gotchas

1. **NBGV `version.json` uses major.minor only (not major.minor.patch)** -- the patch version is calculated from commit height. Setting `"version": "1.2.3"` fixes the patch to 3, defeating the purpose of automatic versioning.

2. **NBGV requires git history to calculate version height** -- shallow clones (`git clone --depth 1`) produce incorrect versions. In CI, use `fetch-depth: 0` with `actions/checkout` to get full history.

3. **`publicReleaseRefSpec` patterns are regex, not globs** -- use `^refs/heads/main$` not `main`. Missing anchors will match unintended refs.

4. **SemVer pre-release ordering is lexical for non-numeric segments** -- `alpha` < `beta` < `rc` because of alphabetical comparison. Numeric segments are compared as integers, so `beta.2` < `beta.10` (because 2 < 10). Do not assume lexical ordering for numeric identifiers.

5. **Do not use CalVer for NuGet libraries** -- NuGet resolution depends on SemVer ordering. CalVer versions like `2024.1.0` work mechanically but violate consumer expectations for API stability signals.

6. **`VersionPrefix` + `VersionSuffix` combine to form `Version`** -- setting all three causes conflicts. Use either `Version` alone or `VersionPrefix`/`VersionSuffix` together, not both.

7. **Keep a Changelog `[Unreleased]` section must be updated before release** -- move entries from `[Unreleased]` to the new version section, update comparison links, and add a new empty `[Unreleased]` section.

8. **`nbgv prepare-release` modifies both the new branch and the current branch** -- it bumps the version on the current branch to the next minor. Run it from the branch you want to continue development on (usually `main`).
