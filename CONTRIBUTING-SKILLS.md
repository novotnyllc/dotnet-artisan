# Skill Authoring Guide

This guide covers everything you need to create, test, and ship a skill for **dotnet-artisan**. It merges the patterns from the [Anthropic Skill Authoring Guide](https://github.com/anthropics/agent-skills/blob/main/docs/skill-authoring-guide.md) with dotnet-artisan conventions.

For the general contribution workflow (prerequisites, PRs, code of conduct), see [CONTRIBUTING.md](CONTRIBUTING.md). For the canonical routing language rules (description formula, scope format, cross-reference conventions), see the [Skill Routing Style Guide](docs/skill-routing-style-guide.md).

---

## 1. Quick Start

Create a working skill in five minutes using `dotnet-csharp` as a reference.

**Step 1 -- Create the folder:**

```bash
mkdir -p plugins/dotnet-artisan/skills/dotnet-my-new-skill
```

**Step 2 -- Write the SKILL.md:**

```markdown
---
name: dotnet-my-new-skill
description: Detects common pitfalls in X during C# development
license: MIT
user-invocable: false
---

# dotnet-my-new-skill

Guidance body goes here. See section 4 for writing instructions.

Cross-references: See [skill:dotnet-csharp] for baseline C# conventions.
```

**Step 3 -- Register in plugin.json:**

Open `plugins/dotnet-artisan/.claude-plugin/plugin.json` and add your skill path to the `skills` array:

```json
"./skills/dotnet-my-new-skill"
```

**Step 4 -- Validate:**

```bash
./scripts/validate-skills.sh && ./scripts/validate-marketplace.sh
```

**Step 5 -- Commit and PR.**

That's it. Read on for the details behind each step.

---

## 2. Skill Anatomy

### Folder Structure

Every skill lives in a flat directory under `plugins/dotnet-artisan/skills/`:

```
plugins/dotnet-artisan/skills/<skill-name>/
  SKILL.md              # Required -- main skill file (casing matters)
  scripts/              # Optional -- deterministic helper CLIs
  references/           # Optional -- companion files for extended content
  assets/               # Optional -- templates/schemas/static outputs
  agents/               # Optional -- provider metadata (for example openai.yaml)
```

The `<skill-name>` directory name must match the `name` field in SKILL.md frontmatter exactly.
Use lowercase letters, numbers, and single hyphens only (1-64 chars).

### SKILL.md Format

A skill file has two parts: **frontmatter** and **body**.

```markdown
---
name: dotnet-csharp-code-smells
description: Detects code smells and anti-patterns in C# code during writing and review
license: MIT
user-invocable: false
---

# dotnet-csharp-code-smells

Body content starts here...
```

**Frontmatter fields** (YAML between `---` fences):

| Field | Required | Type | Rules |
|-------|----------|------|-------|
| `name` | Yes | string | Must match directory name exactly; 1-64 chars; regex `^[a-z0-9]+(-[a-z0-9]+)*$` |
| `description` | Yes | string | Target under 600 characters (see section 3) |
| `license` | Yes | string | Must be `MIT` for this repo. Required by Copilot CLI for skill loading. |
| `user-invocable` | Yes (repo policy) | boolean | Must be explicitly set on every skill (`true` or `false`). Set to `false` to hide from the `/` menu. Not required by the upstream Agent Skills spec, but required in this repo for cross-provider predictability. |
| `disable-model-invocation` | No | boolean | Set to `true` to prevent Claude from loading the skill. The description is excluded from the context budget. Use only for non-guidance meta-skills. |
| `context` | No | string | Execution context. Set to `fork` for self-contained detection/analysis skills that do not need conversation history. |
| `model` | No | string | Model override. Set to `haiku` for lightweight detection tasks that do not require full reasoning. Only meaningful with `context: fork`. |

The `name`, `description`, and `license` fields are required. The optional fields control skill visibility and execution behavior. Boolean fields must use bare `true`/`false` (not quoted strings like `"false"`).

**Important:** All skills must have an explicit `user-invocable` field (either `true` or `false`). Do not omit it and rely on the default. This ensures predictable behavior across all agent runtimes.
**Hard cap:** Description length must be <= 1,024 characters for discovery metadata safety.

### Companion Files

When a skill needs extended code examples, diagnostic tables, or deep-dive content that would bloat the main SKILL.md, extract it into files under `references/`. Reference them from the body:

```markdown
See `references/async-patterns.md` for async/await code examples and common pitfalls.
```

This keeps the primary skill lean while making extended content available to agents that need depth. See `plugins/dotnet-artisan/skills/dotnet-csharp/references/` for working examples of companion files.

### Copilot CLI 32-Skill Display Limit

GitHub Copilot CLI has a system prompt token budget that limits how many skills appear in the `<available_skills>` section visible to the model. Upstream reports indicate approximately 32 skills are shown, and the visible ordering appears to be alphabetical ([copilot-cli#1464](https://github.com/github/copilot-cli/issues/1464), [copilot-cli#1130](https://github.com/github/copilot-cli/issues/1130)). Skills beyond the cutoff may not be discoverable by the model.

**Verification results (Copilot CLI v0.0.412):** Tested with the installed plugin. With the consolidated 9-skill layout, the 32-skill display limit is no longer a concern. All 9 skills fit comfortably within any provider's visible window.

**Current status (9 skills):**

| Category | Count | Skills |
|----------|-------|--------|
| `user-invocable: true` | 4 | dotnet-advisor, dotnet-ui, dotnet-tooling, dotnet-debugging |
| `user-invocable: false` | 5 | using-dotnet, dotnet-csharp, dotnet-api, dotnet-testing, dotnet-devops |

**Routing strategy:** `dotnet-advisor` is the meta-router. We intentionally keep it early in **both** plausible orderings:
- **Manifest order:** it is listed first in `plugins/dotnet-artisan/.claude-plugin/plugin.json`.
- **Reported alphabetical order:** its name (`dotnet-advisor`) is chosen to sort early among `dotnet-*` skills.

This increases the likelihood it stays within Copilot's visible window if the ~32-skill truncation applies broadly. The advisor includes `[skill:]` cross-references to the full catalog. If Copilot supports loading skills referenced from an activated skill body, this provides a fallback path to reach skills beyond the visible window; verify this behavior with the procedure below.

**Behavior scenarios:**

- **If `user-invocable: false` skills are excluded from the 32-slot budget:** Only 4 user-invocable skills compete for the window. All 4 fit comfortably. The limit is a non-issue, and the advisor provides additional meta-routing as a bonus.
- **If all 9 skills count against the budget:** All 9 fit comfortably within any provider's visible window. The advisor provides additional meta-routing as a bonus.

**Rules for maintaining Copilot compatibility:**

1. **Keep `dotnet-advisor` user-invocable.** It must remain in the visible window to serve as the meta-router.
2. **Do not rename `dotnet-advisor`** to anything that sorts late alphabetically among all skills. The name is chosen to sort early in the `dotnet-*` namespace.
3. **New user-invocable skills** should be added sparingly. The current count of 4 is well within the 32-slot budget, but adding many more increases the risk of crowding the window in Copilot environments.
4. **All skills must have explicit `user-invocable`** (true or false) to avoid ambiguity about which skills count against the budget.
5. **Skill ordering is manifest-order or alphabetical.** Verified in v0.0.412: skills appear in plugin.json array order when the model reads the manifest, or alphabetical when using filesystem glob. If you create a new user-invocable skill, ensure it's registered in plugin.json and check its position in both orderings.

**Verification procedure:**

To verify the 32-skill limit behavior with a specific Copilot CLI version:

1. Install the plugin in `~/.copilot/skills/` or `.github/skills/`
2. Start a Copilot CLI session and ask: "List all available skills"
3. Check the system prompt for `<!-- Showing N of M skills due to token limits -->`
4. Verify `dotnet-advisor` appears in the visible set
5. Test that advisor-routed skills (outside the visible set) can be activated via the advisor

---

## 3. Writing Effective Descriptions

The `description` field is the most important line in your skill. It determines when Claude activates your skill from the catalog.

### The Formula

Structure descriptions as: **Action + Domain + Differentiator**

Use **third-person declarative** style. Front-load the most specific action verb or present participle. Do not start with `WHEN`, `A skill that`, `Helps with`, or other filler. See [docs/skill-routing-style-guide.md](docs/skill-routing-style-guide.md) for the full canonical rules.

Include an explicit negative trigger in every description (for example, `Do not use for ...`) so routing has a clear exclusion boundary.

```yaml
# Good -- declarative, specific domain, clear scope
description: Detects code smells and anti-patterns in C# code during writing and review

# Bad -- vague, no activation context
description: Helps with code quality stuff
```

Add disambiguation when helpful:

```yaml
description: Detects code smells and anti-patterns in C# code during writing and review. Don't use for ASP.NET pipeline design or CI workflow authoring.
```

### Good vs. Bad Examples

| Quality | Description | Problem |
|---------|-------------|---------|
| Good | `Writing async/await code. Task patterns, ConfigureAwait, cancellation, and common agent pitfalls.` | Clear trigger, specific scope |
| Good | `Detects and fixes common .NET dependency injection lifetime misuse and registration errors.` | Actionable, precise |
| Bad | `WHEN writing C# async code. Patterns for async/await.` | WHEN prefix -- violates style rule |
| Bad | `C# patterns` | Too vague; matches everything and nothing |
| Bad | `Complete guide to everything about async programming in C# including all patterns, best practices, and common mistakes that developers make.` | 146 chars, over budget |

### The 600-Character Target

Each description must be **at most 600 characters**. This is a budget constraint, not a style preference.

**Budget math:** The plugin loads all skill descriptions into Claude's context window at session start. With 9 skills, the projected maximum is 5,400 characters (9 * 600). The validator enforces a FAIL threshold at 15,600 characters and a WARN threshold at 12,000 characters. With only 9 skills, each description can be significantly richer (up to 600 characters) while staying well under the budget (~28% of the 15,600 cap).

The validation script reports the current budget:

```
CURRENT_DESC_CHARS=~2400
PROJECTED_DESC_CHARS=4800
BUDGET_STATUS=OK
```

- **BUDGET_STATUS** is determined by `CURRENT_DESC_CHARS` only: `OK` if below 12,000, `WARN` at 12,000 or above, `FAIL` at 15,600 or above.
- **PROJECTED_DESC_CHARS** is informational (8 * 600 = 4,800). Not part of `BUDGET_STATUS` determination.

If your description pushes the budget over the warning threshold, shorten it or shorten other descriptions to compensate.

### Avoiding Description Overlap

When two descriptions share too much vocabulary, the routing model may pick the wrong skill. The plugin includes a **semantic similarity detection tool** that flags overlapping description pairs.

**Running locally:**

```bash
# Basic check (error-only mode)
python3 scripts/validate-similarity.py --repo-root .

# Full baseline regression check (as CI runs it)
python3 scripts/validate-similarity.py --repo-root . \
  --baseline scripts/similarity-baseline.json \
  --suppressions scripts/similarity-suppressions.json
```

**Thresholds:**

| Level | Composite Score | Meaning |
|-------|----------------|---------|
| INFO | >= 0.40 | Reported, no action needed |
| WARN | >= 0.55 | Needs review -- differentiate descriptions |
| ERROR | >= 0.75 | Must be differentiated or suppressed |

The composite score combines set Jaccard similarity (shared tokens) and character-level similarity (SequenceMatcher). With the flat skill layout, there is no category-based boost; all pairs are scored uniformly.

**If your PR introduces a new WARN or ERROR pair:**

1. Differentiate the descriptions -- use distinct action verbs and domain keywords
2. If the pair is intentionally similar (e.g., parallel CI system skills), request a suppression by adding an entry to `scripts/similarity-suppressions.json` with a rationale
3. Regenerate the baseline after description changes: run the similarity tool and update `scripts/similarity-baseline.json`

**Suppression format** (`scripts/similarity-suppressions.json`):

```json
[
  {
    "id_a": "dotnet-skill-a",
    "id_b": "dotnet-skill-b",
    "rationale": "Intentional parallel descriptions for different platforms"
  }
]
```

Note: `id_a` must sort before `id_b` alphabetically.

---

## 4. Writing Instructions

The body of SKILL.md contains the guidance Claude uses when the skill is active.

### Progressive Disclosure

Structure content in layers of increasing depth:

1. **Frontmatter** -- Name and description (always loaded in catalog)
2. **SKILL.md body** -- Core guidance, patterns, decision trees (loaded when skill activates)
3. **`references/`** -- Extended examples, edge cases, per-topic companion files (available on demand)

This mirrors the Anthropic guide's recommendation: keep the primary skill focused on actionable guidance, and push verbose examples into companion files.

### Structural Constraints

- Keep `SKILL.md` under **500 lines** when practical. Move dense catalogs, long templates, and schema blocks into `references/` or `assets/`.
- Keep `references/`, `scripts/`, and `assets/` **one level deep**. Avoid nested subfolders.
- Do not add human-centric docs inside a skill directory (`README.md`, `CHANGELOG.md`, `INSTALLATION*.md`).
- Use relative paths with forward slashes (`references/foo.md`, not `references\\foo.md`).

### Cross-Reference Syntax

Reference other skills using the machine-parseable syntax:

```markdown
See [skill:dotnet-csharp] for async/await guidance (read references/async-patterns.md).
```

Rules:
- Always use `[skill:skill-name]` -- bare text skill names are not machine-parseable
- The referenced name must match an existing skill directory name (which should match that skill's `name` frontmatter)
- Unresolved references produce validation warnings

### Content Patterns

- Use real .NET code examples, not pseudocode
- Include tables for pattern catalogs (smell/fix/rule format works well)
- Add an **Agent Gotchas** section for common AI agent mistakes
- Mark scope boundaries with `## Scope` and `## Out of scope` headings, and include `[skill:]` attribution in out-of-scope bullets
- Include a **References** section linking to Microsoft Learn and authoritative sources

### Size Limit

Treat **500 lines** as the working budget for `SKILL.md`. A soft upper limit of **5,000 words** still applies, but large files should be refactored before reaching it.

---

## 5. Testing Your Skill

### Triggering Test

Before validating, manually test that your skill activates correctly:

1. Start a Claude Code session in a .NET project with dotnet-artisan installed
2. Ask a question that should trigger your skill
3. Verify Claude references your skill's guidance in the response

### Validation Commands

Both commands must pass before merging. Run them from the repo root:

**1. Skill validation** -- Checks frontmatter structure, required fields, directory naming, description length, cross-references, and budget:

```bash
./scripts/validate-skills.sh
```

**2. Marketplace validation** -- Verifies `plugin.json` and `marketplace.json` consistency, confirms every registered skill path exists on disk:

```bash
./scripts/validate-marketplace.sh
```

**Run both in sequence:**

```bash
./scripts/validate-skills.sh && ./scripts/validate-marketplace.sh
```

If either command fails, fix the issue before committing. The same commands run in CI on every push and PR.

### LLM-Guided Validation Loop

Use this quick 4-pass loop before opening a PR:

1. **Discovery validation:** Paste only the `name`/`description` and ask an LLM for prompts that should trigger vs not trigger.
2. **Logic simulation:** Paste `SKILL.md` and ask the LLM to simulate execution step-by-step; patch any hallucination gaps.
3. **Edge-case attack:** Ask the LLM to act as QA and produce failure-mode questions.
4. **Refinement:** Move bulky details to `references/`/`assets/`, keep the top-level workflow concise and deterministic.

### Cross-Provider Verification

After validation passes, verify your skill behaves correctly across all supported providers by checking the CI provider matrix output. Run the test harness locally with multiple agents:

```bash
./test.sh --agents claude,codex,copilot
```

Review the per-provider summary lines in the output to confirm your skill triggers correctly for each provider. If any provider shows unexpected behavior, see the [Cross-Provider Change Policy](CONTRIBUTING.md#cross-provider-change-policy) for PR requirements.

---

## 6. Common Patterns

These five patterns from the Anthropic skill authoring guide apply directly to dotnet-artisan skills.

### Sequential Workflow

Guide Claude through ordered steps. Used in scaffolding and migration skills.

```markdown
## Workflow
1. Detect project type with [skill:dotnet-tooling] (read references/project-analysis.md)
2. Check target framework via [skill:dotnet-tooling] (read references/version-detection.md)
3. Apply migration steps based on detected version
```

Example: [skill:dotnet-tooling] (read `references/version-upgrade.md`) walks through SDK upgrade steps in order.

### Multi-MCP Coordination

Combine MCP server data with skill guidance. The plugin integrates Context7, Uno Platform, and Microsoft Learn MCP servers.

```markdown
Use `mcp__context7__query-docs` to fetch current API documentation,
then apply the patterns from this skill.
```

Example: [skill:dotnet-ui] (read `references/uno-mcp.md`) coordinates Uno Platform MCP tools with skill guidance.

### Iterative Refinement

Build-test-fix loops for quality skills. Structure guidance so Claude can iterate.

```markdown
1. Run analyzers: `dotnet build /warnaserror`
2. Review each warning against the table below
3. Apply the fix pattern
4. Re-run to confirm resolution
```

Example: [skill:dotnet-csharp] provides coding standards and code quality tables for iterative cleanup.

### Context-Aware Tool Selection

Help Claude choose the right tool based on project context.

```markdown
## Decision Tree
- If `*.csproj` contains `<OutputType>Exe</OutputType>` -> console app patterns
- If `*.csproj` contains `<Project Sdk="Microsoft.NET.Sdk.Web">` -> web API patterns
```

Example: [skill:dotnet-api] (read `references/efcore-patterns.md`) selects between EF Core, Dapper, and raw ADO.NET based on project characteristics.

### Domain-Specific Intelligence

Encode domain expertise that general LLMs lack.

```markdown
## CA Rules Quick Reference
| Rule | Description |
|------|-------------|
| CA2000 | Dispose objects before losing scope |
```

Example: [skill:dotnet-csharp] encodes Roslyn analyzer rule knowledge with fix patterns via `references/coding-standards.md`.

---

## 7. Troubleshooting

### SKILL.md Casing

The file must be named exactly `SKILL.md` (uppercase). The validation script looks for this exact casing. `skill.md`, `Skill.md`, and other variants will not be found.

### YAML Frontmatter

- Frontmatter must be enclosed between two `---` lines
- The `name` value must match the directory name exactly
- Do not quote descriptions -- Copilot CLI requires unquoted YAML values for reliable parsing
- Only use recognized frontmatter fields: `name`, `description`, `license`, `user-invocable`, `disable-model-invocation`, `context`, `model`
- Boolean fields (`user-invocable`, `disable-model-invocation`) must use bare `true`/`false`, not quoted strings

### Skill Not Triggering

If your skill is not activating in Claude Code sessions:

1. Verify the skill is registered in `plugins/dotnet-artisan/.claude-plugin/plugin.json`
2. Check that the `description` contains clear activation triggers (see section 3)
3. Confirm the `name` field matches the directory name
4. Run `./scripts/validate-marketplace.sh` to verify registration

### Description Budget Exceeded

If validation reports `BUDGET_STATUS=WARN` or `BUDGET_STATUS=FAIL`:

1. Check `CURRENT_DESC_CHARS` in the validation output
2. Shorten your description -- remove filler words, focus on triggers
3. If still over budget, audit other skills for descriptions that can be tightened

### Cross-Reference Resolution

If validation reports unresolved cross-references:

1. Verify the target skill ID matches an existing skill directory name (which should match that skill's `name` frontmatter)
2. Check for typos in `[skill:exact-name-here]`
3. If the target skill does not exist yet, the reference will produce a warning

---

## 8. Pre-Commit Checklist

Before committing a new or modified skill:

- [ ] **Folder created** at `plugins/dotnet-artisan/skills/<skill-name>/`
- [ ] **SKILL.md** exists with correct casing
- [ ] **Frontmatter** has `name`, `description`, `license`, and `user-invocable` fields
- [ ] **`name` matches** the directory name exactly and satisfies `^[a-z0-9]+(-[a-z0-9]+)*$` (1-64 chars)
- [ ] **Description follows style guide** -- Action + Domain + Differentiator formula, third-person declarative, no WHEN prefix, and explicit negative trigger (`Do not use for ...`) (see [Skill Routing Style Guide](docs/skill-routing-style-guide.md))
- [ ] **Description limits** -- target <= 600 chars, hard cap <= 1,024 chars
- [ ] **No description overlap** -- run `python3 scripts/validate-similarity.py --repo-root .` and verify no new WARN/ERROR pairs
- [ ] **Cross-references** use `[skill:skill-name]` syntax (for both skills and agents)
- [ ] **Scope sections** present -- `## Scope` and `## Out of scope` with attributed cross-references
- [ ] **Invocation contract** -- Scope has >=1 unordered bullet, OOS has >=1 unordered bullet, at least one OOS bullet contains `[skill:]` (see [Invocation Contract](docs/skill-routing-style-guide.md#6-invocation-contract))
- [ ] **No self-references** -- skill does not reference itself via `[skill:]`
- [ ] **Skill file hygiene** -- prefer <= 500 lines, one-level `references/`/`scripts/`/`assets/`, forward-slash paths only
- [ ] **Registered in plugin.json** -- skill path added to the `skills` array
- [ ] **Validation passes** -- both commands run clean:
  ```bash
  ./scripts/validate-skills.sh && ./scripts/validate-marketplace.sh
  ```
- [ ] **Commit message** follows conventional commits (`feat(<scope>): ...`)

---

## References

- [Skill Routing Style Guide](docs/skill-routing-style-guide.md) -- canonical rules for descriptions, scope sections, and cross-references
- [Anthropic Skill Authoring Guide](https://github.com/anthropics/agent-skills/blob/main/docs/skill-authoring-guide.md) -- the complete six-chapter guide this manual adapts
- [skills-best-practices](https://github.com/mgechev/skills-best-practices) -- metadata, progressive-disclosure, and validation-loop optimizations
- [Agent Skills Open Standard](https://github.com/anthropics/agent-skills) -- specification for skill format and discovery
- [CONTRIBUTING.md](CONTRIBUTING.md) -- general contribution workflow, prerequisites, and PR process
- [CLAUDE.md](CLAUDE.md) -- plugin conventions and validation commands
- Example skill: [`plugins/dotnet-artisan/skills/dotnet-csharp/SKILL.md`](plugins/dotnet-artisan/skills/dotnet-csharp/SKILL.md) -- well-structured skill with `references/` companion files
