# dotnet-artisan -- Plugin Instructions

<!-- BEGIN FLOW-NEXT -->
## Flow-Next

This project uses Flow-Next for task tracking. Use `.flow/bin/flowctl` instead of markdown TODOs or TodoWrite.

**Quick commands:**
```bash
.flow/bin/flowctl list                # List all epics + tasks
.flow/bin/flowctl epics               # List all epics
.flow/bin/flowctl tasks --epic fn-N   # List tasks for epic
.flow/bin/flowctl ready --epic fn-N   # What's ready
.flow/bin/flowctl show fn-N.M         # View task
.flow/bin/flowctl start fn-N.M        # Claim task
.flow/bin/flowctl done fn-N.M --summary-file s.md --evidence-json e.json
```

**Rules:**
- Use `.flow/bin/flowctl` for ALL task tracking
- Do NOT create markdown TODOs or use TodoWrite
- Re-anchor (re-read spec + status) before every task

**More info:** `.flow/bin/flowctl --help` or read `.flow/usage.md`
<!-- END FLOW-NEXT -->


This repository contains one **dotnet-artisan** plugin under `plugins/dotnet-artisan`. The plugin provides 9 skills (process + domain) and 14 specialist agents for .NET development. It follows the [Agent Skills](https://github.com/anthropics/agent-skills) open standard.

## Key Conventions

### SKILL.md Frontmatter

Every skill requires `name`, `description`, and `license` frontmatter fields. Additional optional fields control skill visibility and execution:

```yaml
---
name: dotnet-example-skill
description: One-line summary under 600 characters
license: MIT
user-invocable: false
---
```

**Required fields:**
- `name` (string) -- must match the directory name
- `description` (string) -- target under 600 characters (WARN at 12,000 total, FAIL at 15,600)
- `license` (string) -- must be `MIT`; required by Copilot CLI

**Required by repo policy:**
- `user-invocable` (boolean) -- must be explicitly set on every skill (`true` or `false`); required for cross-provider predictability

**Optional fields:**
- `disable-model-invocation` (boolean) -- set to `true` to prevent Claude from loading the skill
- `context` (string) -- set to `fork` for isolated execution without conversation history
- `model` (string) -- model override, e.g. `haiku` for lightweight detection tasks

### Cross-Reference Syntax

Reference skills and agents using machine-parseable syntax:

```markdown
See [skill:dotnet-csharp] for C# language patterns and async/await guidance.
Route to [skill:dotnet-security-reviewer] for security audit.
```

Use `[skill:name]` for ALL routable references (skills and agents) -- bare text names are not machine-parseable. The validator resolves references against the union of skill directory names and agent file stems.

### Routing Language Rules

Descriptions must follow the **Action + Domain + Differentiator** formula using third-person declarative style. No WHEN prefix, no filler phrases. Every skill must have `## Scope` and `## Out of scope` sections. See [docs/skill-routing-style-guide.md](docs/skill-routing-style-guide.md) for the full canonical rules.

### Description Budget

- Per-skill description: under 600 characters
- Total context budget: 15,600 characters (warning threshold at 12,000)

## File Structure

```
plugins/dotnet-artisan/skills/<skill-name>/SKILL.md        # 9 skills (flat layout)
plugins/dotnet-artisan/skills/<skill-name>/references/*.md # Companion files with deep content
plugins/dotnet-artisan/agents/<agent-name>.md              # 14 specialist agents
plugins/dotnet-artisan/hooks.json                          # Session hooks (startup + user prompt reminder)
plugins/dotnet-artisan/.mcp.json                           # MCP server integrations (shared by Claude + Codex)
plugins/dotnet-artisan/.claude-plugin/plugin.json          # Claude Code plugin manifest
plugins/dotnet-artisan/.codex-plugin/plugin.json           # Codex plugin manifest
.claude-plugin/marketplace.json                            # Claude Code marketplace metadata
plugins/dotnet-artisan/scripts/                            # Hook scripts used by plugin manifests
scripts/                                                    # Repo validation/release scripts
tests/                                     # Test data
docs/                                      # Plugin-specific documentation
```

Key directories:
- **`plugins/dotnet-artisan/skills/`** -- All skill content in a flat layout (one directory per skill, with `references/` companion files)
- **`plugins/dotnet-artisan/agents/`** -- Specialist agent definitions with frontmatter, preloaded skills, and workflows
- **`plugins/dotnet-artisan/hooks.json`** -- Session lifecycle hooks (startup context + user prompt reminder)
- **`plugins/dotnet-artisan/scripts/`** -- Hook scripts invoked from plugin manifests
- **`plugins/dotnet-artisan/.claude-plugin/`** -- Claude Code plugin manifest
- **`plugins/dotnet-artisan/.codex-plugin/`** -- Codex plugin manifest with plugin metadata, interface presentation fields, and component path hints
- **`.claude-plugin/`** -- Root Claude marketplace metadata

## Validation Commands

Both commands must pass before committing changes (run from repo root):

```bash
# 1. Validate skill frontmatter, required fields, directory conventions
./scripts/validate-skills.sh

# 2. Validate Claude marketplace metadata plus Claude/Codex plugin consistency
./scripts/validate-marketplace.sh
```

Run both in sequence:

```bash
./scripts/validate-skills.sh && ./scripts/validate-marketplace.sh
```

## Development Workflow

1. **Edit skills** -- Modify or create `SKILL.md` files under `plugins/dotnet-artisan/skills/<skill-name>/`
2. **Register in plugin.json** -- Add new skill paths to the `skills` array in `plugins/dotnet-artisan/.claude-plugin/plugin.json`
3. **Validate locally** -- Run both validation commands above
4. **Commit** -- Use conventional commit messages with appropriate scope
5. **CI validates** -- The `validate.yml` workflow runs the same validation commands on push and PR

## References

- See [CONTRIBUTING.md](CONTRIBUTING.md) for contribution guidelines and PR process
- See [CONTRIBUTING-SKILLS.md](CONTRIBUTING-SKILLS.md) for the comprehensive skill authoring how-to manual
- See [README.md](README.md) for the full skill catalog, architecture diagrams, and installation instructions
