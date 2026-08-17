# C# Language Server Protocol (LSP)

C# LSP servers provide code intelligence — go to definition, find references, hover info, symbol search, and call hierarchies — that agents can use to navigate and understand .NET codebases. This reference covers available C# LSP servers, how to install and configure them, and standard LSP operations agents should use for .NET code navigation.

## Why Agents Should Use LSP

Searching codebases with text patterns (`grep`, `ripgrep`) finds string matches but misses semantic meaning. LSP provides **semantic code navigation** that understands:

- Where a symbol is defined (not just where the string appears)
- All references to a symbol across the entire solution
- The full type signature and documentation of a symbol
- Interface implementations and virtual method overrides
- Call hierarchies (who calls this method, what does this method call)

**Use LSP when:**
- Navigating unfamiliar .NET codebases
- Finding all usages of a type, method, or property before refactoring
- Understanding the type of a variable or return value
- Tracing call chains through multiple layers
- Finding implementations of an interface

**Use text search (grep/ripgrep) when:**
- Searching for string literals, comments, or configuration values
- Finding files by name pattern
- Searching across non-C# files (YAML, JSON, XML, Markdown)
- Quick keyword searches where semantic precision isn't needed

## C# LSP Servers

### csharp-ls (Recommended for Agents)

Lightweight, open-source C# language server. Fast startup, low memory, works in any editor or agent runtime that supports LSP.

```bash
# Install as a global .NET tool
dotnet tool install --global csharp-ls

# Run (listens on stdin/stdout by default)
csharp-ls

# Or specify a solution
csharp-ls --solution ./MyApp.sln
```

**Capabilities:** Go to definition, find references, hover, document/workspace symbols, rename, code actions, diagnostics. Does not support call hierarchy (limited by Roslyn APIs available to it).

**Best for:** CLI-based agents, headless environments, CI pipelines, lightweight setups.

### OmniSharp (Feature-Rich)

Full-featured C# language server built on Roslyn. Heavier than csharp-ls but supports more features.

```bash
# Install via .NET tool
dotnet tool install --global omnisharp

# Or download standalone binary
# https://github.com/OmniSharp/omnisharp-roslyn/releases
```

**Capabilities:** Full Roslyn-powered analysis including call hierarchy, refactoring, code fixes, analyzers. Higher memory usage.

**Best for:** Feature-complete environments, when call hierarchy is needed.

### C# Dev Kit LSP (VS Code Only)

Microsoft's proprietary LSP bundled with the C# Dev Kit VS Code extension. Not available outside VS Code.

**Best for:** Human developers using VS Code. Not usable by agents in headless or non-VS Code environments.

### Choosing a Server

| Server | Install | Memory | Call Hierarchy | Headless | License |
|--------|---------|--------|----------------|----------|---------|
| csharp-ls | `dotnet tool install -g csharp-ls` | Low | No | Yes | MIT |
| OmniSharp | `dotnet tool install -g omnisharp` | High | Yes | Yes | MIT |
| C# Dev Kit | VS Code extension | Medium | Yes | No | Proprietary |

**Recommendation:** Use `csharp-ls` for agent scenarios. It starts fast, uses less memory, and covers the operations agents need most (definition, references, hover, symbols).

## LSP Operations for .NET Navigation

The standard LSP protocol defines operations that map directly to .NET code navigation tasks. Agent runtimes expose these differently (e.g., Claude Code has an `LSP` tool, Codex uses internal APIs), but the concepts are universal.

### Go to Definition

Find where a symbol (type, method, property, field) is defined.

**Use when:** You see a type or method used in code and need to understand its implementation.

```
Operation: textDocument/definition
Input: file path + position (line, character) on the symbol
Output: file path + position of the definition
```

**Example scenarios:**
- Cursor on `IOrderRepository` → jumps to the interface definition
- Cursor on `CreateAsync` method call → jumps to the method declaration
- Cursor on a type in a `using` directive → jumps to the type definition

### Find References

Find all locations where a symbol is used across the workspace.

**Use when:** Before renaming, refactoring, or deleting a symbol. Also useful for understanding how widely a type/method is used.

```
Operation: textDocument/references
Input: file path + position on the symbol
Output: list of all locations (file + position) where the symbol is referenced
```

**Example scenarios:**
- Find all callers of `OrderService.CreateAsync`
- Find all classes that implement `IRepository<T>`
- Find all places that read or write a property

### Hover

Get type information, documentation, and signatures for a symbol.

**Use when:** You need to know the type of a variable, the signature of a method, or the XML doc comment for a symbol.

```
Operation: textDocument/hover
Input: file path + position on the symbol
Output: type signature, documentation, parameter info
```

**Example scenarios:**
- Hover over `var order` → reveals `Order` type
- Hover over a method → shows full signature with parameter types and return type
- Hover over a generic type → shows resolved type parameters

### Document Symbols

List all symbols (classes, methods, properties, fields) in a file.

**Use when:** Getting an overview of a file's structure without reading every line.

```
Operation: textDocument/documentSymbol
Input: file path
Output: hierarchical list of symbols with their kinds and positions
```

### Workspace Symbol Search

Search for symbols by name across the entire workspace/solution.

**Use when:** Looking for a class, interface, or method by name across a large codebase.

```
Operation: workspace/symbol
Input: search query string
Output: list of matching symbols with file paths and positions
```

**Example scenarios:**
- Search for `OrderService` → finds the class definition
- Search for `IRepository` → finds the interface and all related types
- Search for `Configure` → finds all Configure methods across the solution

### Go to Implementation

Find concrete implementations of an interface or abstract method.

**Use when:** You see an interface type and need to find the classes that implement it.

```
Operation: textDocument/implementation
Input: file path + position on an interface or abstract member
Output: list of implementing types/methods
```

**Example scenarios:**
- Cursor on `IOrderRepository` → finds `SqlOrderRepository`, `InMemoryOrderRepository`
- Cursor on abstract `ProcessAsync` → finds all override implementations

### Call Hierarchy

Trace incoming calls (who calls this) and outgoing calls (what does this call).

**Use when:** Understanding the flow of execution through a codebase. Requires OmniSharp or C# Dev Kit (csharp-ls does not support this).

```
Operation: callHierarchy/incomingCalls
Input: file path + position on a method
Output: list of methods that call this method

Operation: callHierarchy/outgoingCalls
Input: file path + position on a method
Output: list of methods called by this method
```

## Agent Navigation Patterns

### Pattern 1: Understand a Type

1. **Workspace symbol search** for the type name
2. **Go to definition** to read the type
3. **Document symbols** to see all members
4. **Find references** on key methods to understand usage patterns

### Pattern 2: Trace a Feature

1. **Find the entry point** (API endpoint, command handler, event handler)
2. **Go to definition** on each dependency/service used
3. **Go to implementation** on interfaces to find concrete classes
4. **Outgoing calls** to trace the execution chain

### Pattern 3: Prepare for Refactoring

1. **Find references** on the symbol being refactored
2. **Go to implementation** to find all concrete implementations
3. **Incoming calls** to understand who depends on this
4. Review each reference location before making changes

### Pattern 4: Explore Unfamiliar Codebase

1. **Document symbols** on `Program.cs` or `Startup.cs` to find entry points
2. **Workspace symbol search** for key domain types (e.g., `Order`, `Customer`)
3. **Go to definition** on DI registrations to find service implementations
4. **Hover** on `var` declarations to reveal types

## Configuration

### Editor-Agnostic LSP Client Configuration

Most LSP clients can be configured to use any C# server. The server communicates via stdin/stdout using the LSP JSON-RPC protocol.

```json
// Generic LSP client configuration
{
    "languageId": "csharp",
    "command": "csharp-ls",
    "args": ["--solution", "./MyApp.sln"],
    "rootUri": "file:///path/to/project"
}
```

### VS Code settings.json

```json
{
    "omnisharp.path": "latest",
    "omnisharp.enableRoslynAnalyzers": true,
    "omnisharp.enableEditorConfigSupport": true
}
```

### Neovim (nvim-lspconfig)

```lua
require('lspconfig').csharp_ls.setup({
    cmd = { "csharp-ls" },
    root_dir = function(fname)
        return require('lspconfig.util').root_pattern("*.sln", "*.csproj")(fname)
    end
})
```

## Agent Gotchas

1. **LSP requires a running server** — agents cannot use LSP operations without first ensuring a C# language server is available. Check if one is running or start one.
2. **Solution context matters** — LSP servers resolve symbols relative to a solution or project. If the server is started without `--solution`, it may not find cross-project references.
3. **LSP positions are typically 0-based** — the protocol uses 0-based line and character offsets, but some agent runtimes (like Claude Code) use 1-based positions. Check the agent runtime's documentation.
4. **Go to definition on NuGet types goes to metadata** — you'll see decompiled source or metadata signatures, not editable source. Use ILSpy/ilspycmd for full decompilation (see `references/ilspy-decompile.md`).
5. **LSP is slower than text search for simple queries** — don't use LSP when `grep` for a string literal would suffice. Reserve LSP for semantic navigation.
6. **The server needs time to initialize** — on first start, the C# LSP loads the solution and builds a semantic model. Large solutions may take 10-30 seconds. Subsequent operations are fast.
7. **csharp-ls is preferred over OmniSharp for headless agents** — lower memory footprint, faster startup, and sufficient for most navigation tasks.
