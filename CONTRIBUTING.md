# Contributing to dotnet-artisan

Welcome to **dotnet-artisan**, a Claude Code plugin for .NET development. It follows the [Agent Skills](https://github.com/anthropics/agent-skills) open standard for skill authoring and discovery.

Contributions are welcome across all areas: new skills, skill improvements, agent refinements, documentation, and tooling.

## Prerequisites

You need the following to contribute:

- **jq** -- Required for marketplace validation (`validate-marketplace.sh`)
- **Git** -- Standard version control

No .NET SDK is required for the plugin repo itself. The plugin provides guidance content (Markdown-based skills), not compiled code.

## Skill Authoring Guide

> **Comprehensive guide available:** For the full skill authoring how-to manual -- including quick start, writing effective descriptions, testing, common patterns, and troubleshooting -- see [CONTRIBUTING-SKILLS.md](CONTRIBUTING-SKILLS.md).

The section below provides a quick reference. Skills are the primary content unit. Each skill is a `SKILL.md` file with structured frontmatter and rich guidance content.

### Directory Convention

All skills follow a flat directory structure within the plugin:

```
plugins/dotnet-artisan/skills/<skill-name>/SKILL.md
```

For example: `plugins/dotnet-artisan/skills/dotnet-csharp/SKILL.md`

### SKILL.md Frontmatter

Every skill requires `name`, `description`, and `license` frontmatter fields. Additional optional fields control skill visibility and execution:

```yaml
---
name: dotnet-csharp
description: C# language patterns, coding standards, async/await, DI, config, source generators, LINQ, concurrency, SOLID, and modern syntax
license: MIT
user-invocable: false
---
```

**Required fields:**
- **`name`** (string) -- Unique skill identifier, must match the directory name
- **`description`** (string) -- One-line summary; target under 600 characters
- **`license`** (string) -- Must be `MIT`; required by Copilot CLI for skill loading

**Required by repo policy:**
- **`user-invocable`** (boolean) -- Must be explicitly set on every skill (`true` or `false`). Set to `false` to hide from the `/` menu. Required for cross-provider predictability.

**Optional fields:**
- **`disable-model-invocation`** (boolean) -- Set to `true` to prevent Claude from loading the skill
- **`context`** (string) -- Set to `fork` for isolated execution without conversation history
- **`model`** (string) -- Model override, e.g. `haiku` for lightweight detection tasks

See the [CONTRIBUTING-SKILLS.md](CONTRIBUTING-SKILLS.md) for the full field reference table.

The description budget of 600 characters per skill keeps the aggregate catalog within the context window budget (WARN at 12,000 characters, FAIL at 15,600). With 9 skills, the total budget usage is approximately 28% of the 15,600 cap.

### Cross-Reference Syntax

Reference other skills and agents using the unified cross-reference syntax:

```markdown
See [skill:dotnet-csharp] for async/await guidance (read references/async-patterns.md).
Route to [skill:dotnet-security-reviewer] for security audit.
```

Use `[skill:name]` for ALL routable references (skills and agents) -- bare text names are not machine-parseable.

### Routing Language Rules

Descriptions must follow the **Action + Domain + Differentiator** formula using third-person declarative style. No WHEN prefix, no filler phrases. Every skill must have `## Scope` and `## Out of scope` sections with attributed cross-references. See [docs/skill-routing-style-guide.md](docs/skill-routing-style-guide.md) and [CONTRIBUTING-SKILLS.md](CONTRIBUTING-SKILLS.md) for full details.

### Content Guidelines

- Use real .NET code examples, not pseudocode
- Include Mermaid diagrams for architectural concepts where appropriate
- Use YAML and Markdown formatting consistent with existing skills
- Add an **Agent Gotchas** section for common AI agent mistakes
- Mark scope boundaries with `## Scope` and `## Out of scope` headings, and include `[skill:]` attribution in out-of-scope bullets

### Skill Description Budget

The total context budget for all skill descriptions is 15,600 characters (with a warning threshold at 12,000). Each individual skill description should target under 600 characters. With 9 skills, the catalog uses approximately 28% of the budget, giving each skill rich routing signal.

## Agent Authoring

Agents are specialist personas that combine multiple skills with domain expertise. To contribute an agent:

### Agent File Structure

Place agent files at:

```
plugins/dotnet-artisan/agents/<agent-name>.md
```

### Agent Frontmatter

```yaml
---
name: dotnet-example-specialist
description: Brief description of the agent's domain expertise
capabilities:
  - capability-one
  - capability-two
tools:
  - Read
  - Grep
  - Glob
---
```

Required frontmatter fields: `name`, `description`, `capabilities`, and `tools`.

### Agent Content

- Define preloaded skills (including foundation skills like `dotnet-tooling` and `dotnet-csharp`)
- Specify a workflow with numbered steps
- Include trigger lexicon for routing from `dotnet-advisor`
- Keep agent toolsets aligned with workflow steps (do not reference tools not declared in frontmatter)

## PR Process

1. **Fork** the repository
2. **Branch** from `main` with a descriptive branch name
3. **Implement** your changes following the conventions above
4. **Validate locally** -- Run all validation commands (see below)
5. **Submit PR** with a clear description of changes

## Validation Requirements

Both validation commands must pass before a PR can be merged:

### 1. Skill Validation

```bash
./scripts/validate-skills.sh
```

Validates skill frontmatter structure, required fields (`name`, `description`, `license`, `user-invocable`), directory conventions, and cross-references.

### 2. Marketplace Validation

```bash
./scripts/validate-marketplace.sh
```

Validates `plugin.json` and `marketplace.json` consistency, skill registration, and agent registration.

Run both before submitting (from repo root):

```bash
./scripts/validate-skills.sh && ./scripts/validate-marketplace.sh
```

### Root Marketplace Validation

A separate shared script validates the root `.claude-plugin/marketplace.json` schema. It is called by both `validate-marketplace.sh` and directly by CI workflows:

```bash
./scripts/validate-root-marketplace.sh
```

### Release

#### Version Management

The canonical version source of truth is `plugins/dotnet-artisan/.claude-plugin/plugin.json`. The version field is propagated to six locations by the bump script:

1. `plugins/dotnet-artisan/.claude-plugin/plugin.json` -- canonical source
2. `plugins/dotnet-artisan/.codex-plugin/plugin.json` -- Codex plugin manifest
3. `.claude-plugin/marketplace.json` -- root marketplace plugin entry `.plugins[].version`
4. `.claude-plugin/marketplace.json` -- root marketplace `metadata.version`
5. `README.md` -- version badge
6. `CHANGELOG.md` -- promote `[Unreleased]` section and update footer links

CI validates version consistency across the Claude and Codex plugin manifests plus root marketplace metadata.

#### Bump Script

Use `scripts/bump.sh` to increment the version and propagate to all locations:

```bash
./scripts/bump.sh <patch|minor|major> [plugin-name]
```

- The second argument defaults to `dotnet-artisan`
- Run this in your **PR branch**, not directly on main

Example:

```bash
./scripts/bump.sh patch
# Review: git diff
# Commit: git add -A && git commit -m "chore(release): bump dotnet-artisan to v0.2.0"
# Push your PR branch and merge -- the release is created automatically
```

#### Tag Convention

Tags follow the format `dotnet-artisan/vX.Y.Z` (plugin-scoped, not bare `vX.Y.Z`). This allows multiple plugins to coexist in the same repo with independent version histories.

#### Release Workflow

Releases are automated via a single workflow:

1. **`auto-tag.yml`** -- On every push to `main`, reads the version from `plugin.json` and checks if a matching tag exists.
   - If the tag already exists, the workflow exits with no release work.
   - If the tag does not exist, it runs:
     - `scripts/validate-root-marketplace.sh`
     - `scripts/validate-skills.sh`
     - `scripts/validate-marketplace.sh`
   - It then creates and pushes `dotnet-artisan/vX.Y.Z`, extracts notes for that version from `CHANGELOG.md`, and creates the GitHub Release in the same run.

PRs that don't bump the version merge without triggering a release (the tag already exists, so `auto-tag.yml` is a no-op).

## Publishing to Marketplace

### Prerequisites

- GitHub repository is public (or accessible to the marketplace)
- `plugins/dotnet-artisan/.claude-plugin/plugin.json`, `plugins/dotnet-artisan/.codex-plugin/plugin.json`, and `.claude-plugin/marketplace.json` are valid
- A GitHub Release exists with the target version tag

### Publishing Steps

1. Ensure the latest release tag is pushed to the repository
2. The marketplace indexes plugins from GitHub Releases automatically
3. Verify the plugin appears in the marketplace after indexing

### Post-Publish Verification

After publishing, confirm:

- Plugin is discoverable by name (`dotnet-artisan`)
- Plugin metadata (description, keywords, categories) renders correctly
- All skills are listed and accessible

### Cross-Provider Change Policy

Skill content must behave correctly across all supported providers (Claude, Codex, Copilot). Any PR that modifies skill content, routing descriptions, or agent definitions must satisfy these requirements:

- **PR description must state:** targeted provider (if any) and expected behavior deltas across providers. Provider-targeted changes require explicit verification against non-target providers to confirm no regressions.
- **Attach CI artifact links** or paste per-provider summary lines for `claude`/`codex`/`copilot` from CI matrix output. Run `./test.sh --agents claude,codex,copilot` locally or reference the CI workflow artifacts.
- **If behavior intentionally diverges** between providers, update `provider-baseline.json` in the same PR with a justification comment explaining why the divergence is expected.

### Release Checklist

Before every release, verify:

- [ ] `plugin.json` version matches the tag
- [ ] `marketplace.json` version matches the tag
- [ ] `CHANGELOG.md` has entries for this version with correct date
- [ ] `validate-skills.sh` passes (exit code 0)
- [ ] `validate-marketplace.sh` passes (exit code 0)
- [ ] All SKILL.md files have required frontmatter (`name`, `description`, `license`, `user-invocable`)
- [ ] Budget status is OK or WARN (not FAIL)
- [ ] No broken cross-references (all `[skill:<name>]` refs resolve)
- [ ] Cross-provider verification: changes verified against `claude`/`codex`/`copilot` matrix

## Hooks and MCP Contributions

The plugin includes session hooks (session start context, user prompt routing reminder) and MCP server integrations (Context7 + Microsoft Docs).

For guidance on contributing to hooks or MCP integrations, see [docs/hooks-and-mcp-guide.md](docs/hooks-and-mcp-guide.md).

## Code of Conduct

We are committed to providing a welcoming and inclusive experience for everyone. Contributors are expected to:

- Be respectful and constructive in discussions and code reviews
- Focus on technical merit and improving the plugin
- Welcome newcomers and help them get started

Thank you for contributing to dotnet-artisan.
