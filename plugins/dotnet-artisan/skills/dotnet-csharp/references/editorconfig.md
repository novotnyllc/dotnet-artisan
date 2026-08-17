# Editorconfig

Comprehensive guide to configuring .NET code analysis rules via `.editorconfig` and global AnalyzerConfig files. Covers code style rules (IDE*), code quality rules (CA*), severity levels, `AnalysisLevel`, `EnforceCodeStyleInBuild`, directory hierarchy precedence, and `.globalconfig` files.

## EditorConfig Overview

`.editorconfig` is the standard configuration file for controlling code style and analysis rule behavior in .NET projects. The .NET compiler (Roslyn) reads `.editorconfig` to determine:

- **Code style preferences** -- naming, formatting, expression-level patterns (IDE* rules)
- **Code quality rule severity** -- suppress, demote, or escalate CA* and IDE* diagnostics
- **Formatting rules** -- indentation, spacing, newlines

### Directory Hierarchy and Precedence

EditorConfig files apply hierarchically. The compiler searches upward from the source file to the filesystem root, merging settings from each `.editorconfig` found. **Closest file wins** -- a setting in `src/MyApp/.editorconfig` overrides the same setting in the repo root `.editorconfig`.

```
repo-root/
  .editorconfig              # Shared baseline (root = true)
  src/
    .editorconfig            # Overrides for production code
    MyApp.Api/
      .editorconfig          # API-specific overrides (if needed)
  tests/
    .editorconfig            # Relaxed rules for test projects
```

Set `root = true` in the topmost file to stop upward traversal. Without this, the editor traverses above the repo root into user or system-level EditorConfig files, producing non-reproducible behavior.

```ini
# repo-root/.editorconfig
root = true

[*.cs]
indent_style = space
indent_size = 4
```

### File Glob Patterns

EditorConfig sections use glob patterns to scope settings to specific files:

| Pattern | Matches |
|---------|---------|
| `[*.cs]` | All C# files |
| `[*.{cs,vb}]` | C# and Visual Basic files |
| `[**/test/**/*.cs]` | C# files under any `test` directory |
| `[Program.cs]` | Exact file name |

---

## Code Style Rules (IDE*)

IDE rules control code style preferences enforced by the Roslyn compiler and IDE. They are configured with `dotnet_style_*`, `csharp_style_*`, and `dotnet_diagnostic.IDE*.severity` entries.

### Key IDE Rule Categories

| Range | Category | Examples |
|-------|----------|----------|
| IDE0001-IDE0009 | Simplification | IDE0001 (simplify name), IDE0003 (remove `this.` qualification), IDE0005 (remove unnecessary using) |
| IDE0010-IDE0039 | Expression preferences | IDE0016 (throw expression), IDE0017 (object initializer), IDE0018 (inline variable), IDE0028 (collection initializer), IDE0034 (simplify default), IDE0039 (use local function) |
| IDE0040-IDE0069 | Modifier and access preferences | IDE0040 (add accessibility modifiers), IDE0044 (add readonly), IDE0062 (make local function static) |
| IDE0070-IDE0090+ | Pattern matching and modern syntax | IDE0071 (simplify interpolation), IDE0078 (use pattern matching), IDE0090 (simplify `new` expression) |
| IDE0100-IDE0180 | Additional simplification | IDE0130 (namespace match folder), IDE0160/IDE0161 (block vs file-scoped namespace) |
| IDE0200-IDE0260 | Lambda and method preferences | IDE0200 (remove unnecessary lambda), IDE0230 (use UTF-8 string literal) |
| IDE1005-IDE1006 | Naming rules | IDE1006 (naming rule violation) |

### Configuring Code Style Preferences

```ini
[*.cs]
# Expression-level preferences
csharp_style_expression_bodied_methods = when_on_single_line:suggestion
csharp_style_expression_bodied_properties = true:suggestion
csharp_style_expression_bodied_constructors = false:silent

# Pattern matching
csharp_style_prefer_pattern_matching = true:suggestion
csharp_style_prefer_switch_expression = true:suggestion
csharp_style_prefer_not_pattern = true:suggestion

# Null checking
csharp_style_prefer_null_check_over_type_check = true:suggestion
dotnet_style_coalesce_expression = true:suggestion
dotnet_style_null_propagation = true:suggestion

# var preferences
csharp_style_var_for_built_in_types = false:suggestion
csharp_style_var_when_type_is_apparent = true:suggestion
csharp_style_var_elsewhere = false:suggestion

# Namespace style (.NET 6+)
csharp_style_namespace_declarations = file_scoped:warning

# Using directives
csharp_using_directive_placement = outside_namespace:warning
dotnet_sort_system_directives_first = true
```

### IDE Rule Severity via dotnet_diagnostic

Each IDE rule can have its severity set independently:

```ini
[*.cs]
# Enforce removal of unnecessary usings as a build warning
dotnet_diagnostic.IDE0005.severity = warning

# Enforce file-scoped namespaces as a build error
dotnet_diagnostic.IDE0161.severity = error

# Demote new-expression simplification to suggestion
dotnet_diagnostic.IDE0090.severity = suggestion

# Disable this. qualification rule entirely
dotnet_diagnostic.IDE0003.severity = none
```

---

## Code Quality Rules (CA*)

CA rules detect design, performance, security, reliability, and usage issues. They are shipped with the .NET SDK and controlled by `AnalysisLevel`. For a complete CA rule category table and `AnalysisLevel` setup guidance, see [skill:dotnet-tooling].

The main CA categories are: Design (CA1000s), Globalization (CA1300s), Interoperability (CA1400s), Maintainability (CA1500s), Naming (CA1700s), Performance (CA1800s), Reliability (CA2000s), Security (CA2100s, CA3xxx, CA5xxx), and Usage (CA2200s).

### CA Rule Severity Configuration

```ini
[*.cs]
# Suppress rules not applicable to your project type
dotnet_diagnostic.CA1062.severity = none          # Nullable handles parameter validation
dotnet_diagnostic.CA2007.severity = none          # ConfigureAwait not needed in ASP.NET Core apps

# Escalate important rules
dotnet_diagnostic.CA1822.severity = warning       # Mark members as static
dotnet_diagnostic.CA1848.severity = warning       # Use LoggerMessage delegates
dotnet_diagnostic.CA2016.severity = warning       # Forward CancellationToken

# Error-level for security rules
dotnet_diagnostic.CA2100.severity = error         # SQL injection review
dotnet_diagnostic.CA5350.severity = error         # Weak cryptographic algorithms
```

---

## Severity Levels

The five severity levels control how a diagnostic is reported:

| Severity | Build Output | IDE Squiggles | Error List | Fails Build (`TreatWarningsAsErrors`) |
|----------|-------------|---------------|------------|---------------------------------------|
| `error` | Yes (error) | Red | Error tab | Always |
| `warning` | Yes (warning) | Green | Warning tab | Yes (with `TreatWarningsAsErrors`) |
| `suggestion` | No | Gray dots | Message tab | No |
| `silent` | No | No | No | No (code fix available, not shown in build or Error List) |
| `none` | No | No | No | No (rule fully disabled) |

### Bulk Severity Configuration

Set default severity for entire categories:

```ini
[*.cs]
# Set all design rules to warning
dotnet_analyzer_diagnostic.category-Design.severity = warning

# Set all performance rules to error
dotnet_analyzer_diagnostic.category-Performance.severity = error

# Set all naming rules to suggestion
dotnet_analyzer_diagnostic.category-Naming.severity = suggestion
```

Valid category names for `dotnet_analyzer_diagnostic.category-{Category}.severity` include: `Design`, `Documentation`, `Globalization`, `Interoperability`, `Maintainability`, `Naming`, `Performance`, `SingleFile`, `Reliability`, `Security`, `Usage`. IDE* rules do not participate in category-level bulk configuration -- configure them individually via `dotnet_diagnostic.IDE*.severity`.

Per-rule entries override category-level settings. Category-level settings override `AnalysisLevel` defaults.

**Precedence order** (highest to lowest):
1. Per-rule: `dotnet_diagnostic.CA1822.severity = error`
2. Per-category: `dotnet_analyzer_diagnostic.category-Performance.severity = warning`
3. `AnalysisLevel` baseline (set in MSBuild properties)

---

## AnalysisLevel and EnforceCodeStyleInBuild

`AnalysisLevel` controls which built-in CA rules are enabled and their default severities. Values range from `latest` (default, correctness only) through `latest-all` (all rules). Pin to a specific .NET SDK major version (e.g., `8-all`, `10-all`) to lock the rule set across SDK upgrades. Use `preview-all` for the broadest coverage including experimental rules. For the full AnalysisLevel values table and setup guidance, see [skill:dotnet-tooling].

### EnforceCodeStyleInBuild

By default, IDE* rules only run in the IDE, not during `dotnet build`. Enable build enforcement:

```xml
<PropertyGroup>
  <EnforceCodeStyleInBuild>true</EnforceCodeStyleInBuild>
</PropertyGroup>
```

This is critical for CI enforcement -- without it, code style violations slip through even if configured as warnings or errors in `.editorconfig`. Combine with `TreatWarningsAsErrors` for strict enforcement:

```xml
<PropertyGroup>
  <AnalysisLevel>latest-all</AnalysisLevel>
  <EnforceCodeStyleInBuild>true</EnforceCodeStyleInBuild>
  <TreatWarningsAsErrors>true</TreatWarningsAsErrors>
</PropertyGroup>
```

---

## Global AnalyzerConfig Files (.globalconfig)

Global AnalyzerConfig files (`.globalconfig`) provide an alternative to `.editorconfig` for analyzer configuration. They apply globally to all files in the compilation without requiring directory-relative placement.

### When to Use .globalconfig vs .editorconfig

| Aspect | `.editorconfig` | `.globalconfig` |
|--------|-----------------|-----------------|
| Scope | Directory-relative (file glob sections) | Entire compilation (no file sections) |
| Hierarchy | Merges upward through directories | Flat -- no directory traversal |
| IDE support | Full (formatting, refactoring, analysis) | Analysis rules only |
| Use case | Per-directory formatting + analysis | Shared rule configuration across projects or NuGet packages |

### .globalconfig Syntax

```ini
# Filename: .globalconfig (or any name with is_global = true)
is_global = true

# Global level determines priority (higher number = higher priority)
global_level = 100

# Configure rules (same syntax as .editorconfig, without [*.cs] sections)
dotnet_diagnostic.CA1822.severity = warning
dotnet_diagnostic.CA2007.severity = none
dotnet_diagnostic.IDE0005.severity = warning
```

### Including .globalconfig in a Project

Reference via MSBuild `GlobalAnalyzerConfigFiles` item:

```xml
<!-- Directory.Build.props -->
<ItemGroup>
  <GlobalAnalyzerConfigFiles Include="$(MSBuildThisFileDirectory).globalconfig" />
</ItemGroup>
```

NuGet analyzer packages can ship `.globalconfig` files in `buildTransitive/` to apply default severities to consumers.

### global_level Precedence

When multiple `.globalconfig` files apply, the `global_level` value determines which one wins. Higher values take precedence. The SDK default global config uses `global_level = -1`. User configs should use `global_level = 0` or higher (default when omitted is 0). NuGet-shipped configs use negative values to allow user overrides.

**Full precedence order** (highest to lowest):
1. Per-rule `.editorconfig` entries
2. Per-category `.editorconfig` entries
3. `.globalconfig` with highest `global_level`
4. `.globalconfig` with lower `global_level`
5. SDK default configuration (`AnalysisLevel`)

---

## Naming Rules (IDE1006)

EditorConfig supports custom naming rules that enforce naming conventions at build time (when `EnforceCodeStyleInBuild` is enabled):

```ini
[*.cs]
# Define symbol groups
dotnet_naming_symbols.public_members.applicable_kinds = property, method, field, event
dotnet_naming_symbols.public_members.applicable_accessibilities = public

dotnet_naming_symbols.private_fields.applicable_kinds = field
dotnet_naming_symbols.private_fields.applicable_accessibilities = private

dotnet_naming_symbols.interfaces.applicable_kinds = interface

# Define naming styles
dotnet_naming_style.pascal_case.capitalization = pascal_case

dotnet_naming_style.underscore_prefix.capitalization = camel_case
dotnet_naming_style.underscore_prefix.required_prefix = _

dotnet_naming_style.interface_prefix.capitalization = pascal_case
dotnet_naming_style.interface_prefix.required_prefix = I

# Bind rules (lower number = higher priority)
dotnet_naming_rule.interfaces_must_start_with_i.symbols = interfaces
dotnet_naming_rule.interfaces_must_start_with_i.style = interface_prefix
dotnet_naming_rule.interfaces_must_start_with_i.severity = warning

dotnet_naming_rule.public_members_pascal_case.symbols = public_members
dotnet_naming_rule.public_members_pascal_case.style = pascal_case
dotnet_naming_rule.public_members_pascal_case.severity = warning

dotnet_naming_rule.private_fields_underscore.symbols = private_fields
dotnet_naming_rule.private_fields_underscore.style = underscore_prefix
dotnet_naming_rule.private_fields_underscore.severity = warning
```

---

## Common Configuration Templates

### Recommended Baseline (.editorconfig)

```ini
root = true

[*]
indent_style = space
indent_size = 4
end_of_line = lf
charset = utf-8
trim_trailing_whitespace = true
insert_final_newline = true

[*.cs]
# Namespace and using preferences
csharp_style_namespace_declarations = file_scoped:warning
csharp_using_directive_placement = outside_namespace:warning
dotnet_sort_system_directives_first = true

# Code style enforcement in build
dotnet_diagnostic.IDE0005.severity = warning
dotnet_diagnostic.IDE0161.severity = warning
dotnet_diagnostic.IDE0090.severity = suggestion

# CA rule adjustments
dotnet_diagnostic.CA1848.severity = warning
dotnet_diagnostic.CA2016.severity = warning
```

### Test Project Overrides (tests/.editorconfig)

Place a separate `.editorconfig` in the `tests/` directory to relax rules that conflict with test readability. For common per-project-type suppression patterns (ASP.NET Core apps, libraries, test projects), see [skill:dotnet-tooling].

```ini
[*.cs]
# Relax rules for test readability
dotnet_diagnostic.CA1707.severity = none          # Allow underscores in test names
dotnet_diagnostic.CA1822.severity = none          # Test methods often not static
dotnet_diagnostic.IDE0058.severity = none         # Expression value is never used
```

---

## Generated Code Configuration

Source generators and scaffolding tools produce code that often triggers IDE/CA warnings. Use the `generated_code = true` setting or file glob patterns to suppress analysis on generated files:

```ini
# Suppress warnings in generated code files
[*.g.cs]
generated_code = true

[*.generated.cs]
generated_code = true
```

When `generated_code = true` is set, Roslyn treats the file as generated code and applies the `GeneratedCodeAnalysisFlags` configured in each analyzer (most analyzers skip generated code by default). This is particularly relevant when using source generators -- see `references/source-generators.md`.

---

## References

- [EditorConfig for .NET code style rules](https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/code-style-rule-options)
- [Code quality rules (CA*)](https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/)
- [Code style rules (IDE*)](https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/style-rules/)
- [Configuration options for code analysis](https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/configuration-options)
- [Global AnalyzerConfig files](https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/configuration-files#global-analyzerconfig)
- [Naming rule configuration](https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/style-rules/naming-rules)
