---
name: dotnet-library-docs
description: Fetches current, version-accurate documentation and code examples for NuGet packages and third-party libraries (Polly, MediatR, Serilog, Npgsql, MassTransit, etc.) through the Context7 HTTP API with curl - one library search, then one topic fetch - replacing the Context7 MCP server. Do not use for official .NET/ASP.NET/Azure reference (Microsoft Learn MCP) or for writing project documentation.
license: MIT
user-invocable: true
---

# dotnet-library-docs

Look up current documentation for a library when training-data knowledge may
be stale (new major versions, renamed APIs, changed defaults). This replaces
the Context7 MCP server the plugin used to start in every session: the same
Context7 service, called with `curl` only when needed, so no Node process,
no `npx` download, and no tool schemas in the startup context.

## Scope

- Third-party and NuGet library docs: API usage, configuration, migration notes, code snippets.
- Checking how the current version of a package does something before writing code against it.
- Non-.NET libraries in the same repo (front-end packages, CLIs) - Context7 indexes those too.

## Out of scope

- Official .NET, ASP.NET Core, EF Core, and Azure reference -> the `microsoftdocs-mcp` server (Microsoft Learn) shipped with this plugin; routing via [skill:dotnet-advisor].
- Generating XML doc comments, READMEs, or API docs for the user's own code -> [skill:dotnet-docs-generator].
- Choosing which package or architecture to use -> [skill:dotnet-advisor].

## Workflow

Requires `curl` and network access. In a sandbox with network off (Codex
`workspace-write` default, some Claude Code permission modes) the harness
will ask to allow the request; that one approval covers the lookup.

1. **Resolve the library id** (skip if the user gave one like `/app-vnext/polly`):

   ```bash
   curl -fsS "https://context7.com/api/v1/search?query=polly" |
     python3 -c 'import json,sys; [print(r["id"], "|", r["title"], "| trust", r.get("trustScore"), "| snippets", r.get("totalSnippets")) for r in json.load(sys.stdin)["results"][:5]]'
   ```

   Prefer the official repository id (`/<org>/<repo>`) with a high trust
   score over mirrors (`/websites/...`, DeepWiki). If nothing fits, say so
   rather than guessing.

2. **Fetch docs for one topic**, trimmed to what you need:

   ```bash
   curl -fsS "https://context7.com/api/v1/app-vnext/polly?type=txt&topic=retry&tokens=3000"
   ```

   Drop the leading `/` of the id in the path. `topic` narrows the result;
   `tokens` caps its size (3000 is usually enough; raise to 8000-10000 only
   for broad questions). A version-specific id (`/org/repo/v8.4.0`, shown in
   search results when available) pins a release.

3. Cite the library id you used and say which version the docs cover when
   the answer depends on it.

Use one search and one or two fetches per question; do not crawl.

## API key (optional)

Anonymous requests work but are rate limited. If a `CONTEXT7_API_KEY`
environment variable is set, send it - never print it or write it to a file:

```bash
curl -fsS -H "Authorization: Bearer $CONTEXT7_API_KEY" "https://context7.com/api/v1/search?query=polly"
```

On HTTP 429 without a key, tell the user the anonymous limit was hit and that
a free key from context7.com raises it.

## Restoring the MCP server

Prefer the MCP server instead (for example, a client that cannot run shell
commands)? Add it to your own client config:
`npx -y @upstash/context7-mcp@<version>` (Claude Code:
`claude mcp add context7 -s user -- npx -y @upstash/context7-mcp@<version>`;
Codex: `codex mcp add context7 -- npx -y @upstash/context7-mcp@<version>`).
