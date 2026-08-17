# Add Analyzers

Add and configure .NET code analyzers to an existing project. Covers built-in Roslyn CA rules, nullable reference types enforcement, trimming/AOT compatibility analyzers, and third-party analyzer packages.

**Prerequisites:** Run `references/version-detection.md` first — analyzer features vary by SDK version. Run `references/project-analysis.md` to understand the current project layout.

## Built-in Roslyn Analyzers

.NET SDK ships built-in analyzers controlled by `AnalysisLevel`. Configure in `Directory.Build.props`:

```xml
<PropertyGroup>
  <AnalysisLevel>latest-all</AnalysisLevel>
  <EnforceCodeStyleInBuild>true</EnforceCodeStyleInBuild>
  <TreatWarningsAsErrors>true</TreatWarningsAsErrors>
</PropertyGroup>
```

### AnalysisLevel Values

| Value | Behavior |
|-------|----------|
| `latest` | Default rules only — covers correctness, not style |
| `latest-minimum` | Fewer rules than default |
| `latest-recommended` | Default + additional recommended rules |
| `latest-all` | All rules enabled — most comprehensive |
| `9-all`, `10-all` | Pin to a specific SDK version's full rule set |

`latest-all` is recommended for new projects. For existing projects with many warnings, start with `latest-recommended` and tighten over time.

### Rule Categories

| Category | Prefix | Examples |
|----------|--------|----------|
| Design | CA1xxx | CA1002 (don't expose generic lists), CA1062 (validate arguments) |
| Globalization | CA1300–CA1399 | CA1304 (specify CultureInfo) |
| Performance | CA1800–CA1899 | CA1822 (mark members static), CA1848 (use LoggerMessage) |
| Reliability | CA2000–CA2099 | CA2000 (dispose objects), CA2007 (ConfigureAwait) |
| Security | CA2100–CA2199, CA3xxx, CA5xxx | CA2100 (SQL injection), CA3075 (XML processing) |
| Usage | CA2200–CA2299 | CA2211 (non-constant static fields), CA2245 (don't assign to self) |
| Naming | CA1700–CA1799 | CA1707 (no underscores in identifiers) |
| Style | IDE0xxx | IDE0003 (this qualification), IDE0063 (using declaration) |


## EditorConfig Severity Overrides

Fine-tune analyzer severity per-rule in `.editorconfig`:

```ini
[*.cs]
# Suppress specific rules
dotnet_diagnostic.CA1062.severity = none          # Nullable handles this
dotnet_diagnostic.CA2007.severity = none          # Not needed in ASP.NET Core apps

# Escalate to error
dotnet_diagnostic.CA1822.severity = error         # Mark members as static
dotnet_diagnostic.CA1848.severity = warning       # Use LoggerMessage delegates

# Style enforcement
dotnet_diagnostic.IDE0005.severity = warning      # Remove unnecessary usings
dotnet_diagnostic.IDE0063.severity = warning      # Use simple using statement
dotnet_diagnostic.IDE0090.severity = warning      # Simplify new expression
```

### Common Suppressions by Project Type

**ASP.NET Core apps** — suppress ConfigureAwait warnings:
```ini
dotnet_diagnostic.CA2007.severity = none
```

**Libraries** — keep CA2007 as warning (callers may not have a SynchronizationContext):
```ini
dotnet_diagnostic.CA2007.severity = warning
```

**Test projects** — relax certain rules:
```ini
dotnet_diagnostic.CA1707.severity = none          # Allow underscores in test names
dotnet_diagnostic.CA1062.severity = none          # Parameters validated by test framework
dotnet_diagnostic.CA2007.severity = none          # ConfigureAwait not relevant
```


## Nullable Reference Types

Enable globally in `Directory.Build.props`:

```xml
<PropertyGroup>
  <Nullable>enable</Nullable>
</PropertyGroup>
```

Nullable analysis produces warnings (CS86xx) not CA rules. Related settings:

```xml
<PropertyGroup>
  <!-- Treat nullable warnings as errors -->
  <WarningsAsErrors>$(WarningsAsErrors);nullable</WarningsAsErrors>
</PropertyGroup>
```

For gradual adoption in existing codebases, enable per-file:

```csharp
#nullable enable
```

See [skill:dotnet-csharp] for annotation strategies and patterns.


## Trimming and AOT Compatibility Analyzers

### Applications

For apps published with trimming or Native AOT, enable the analyzers alongside the publish properties:

```xml
<PropertyGroup>
  <!-- Enable trimmed publishing + analysis -->
  <PublishTrimmed>true</PublishTrimmed>
  <EnableTrimAnalyzer>true</EnableTrimAnalyzer>

  <!-- Enable AOT publishing + analysis -->
  <PublishAot>true</PublishAot>
  <EnableAotAnalyzer>true</EnableAotAnalyzer>

  <!-- Single-file analysis (subset of trim analysis) -->
  <EnableSingleFileAnalyzer>true</EnableSingleFileAnalyzer>
</PropertyGroup>
```

Enable the analyzers early (even before publishing trimmed) to catch issues during development. `EnableTrimAnalyzer` and `EnableAotAnalyzer` can be set independently of `PublishTrimmed`/`PublishAot`.

### Libraries

Libraries use `IsTrimmable` and `IsAotCompatible` to declare compatibility to consumers. Enable these even if consumers don't trim yet:

```xml
<PropertyGroup>
  <IsTrimmable>true</IsTrimmable>
  <IsAotCompatible>true</IsAotCompatible>
</PropertyGroup>
```

Setting `IsTrimmable`/`IsAotCompatible` automatically enables the corresponding analyzers. This ensures the library works correctly when consumers eventually enable trimming/AOT.

### What the Analyzers Flag

These analyzers flag:
- Reflection usage that breaks trimming (IL2xxx warnings)
- P/Invoke patterns incompatible with AOT
- Dynamic code generation (`Reflection.Emit`, `System.Linq.Expressions` compilation)
- Types not annotated with `[DynamicallyAccessedMembers]`


## Third-Party Analyzers

Add via `Directory.Build.targets` so they apply to all projects:

```xml
<!-- Directory.Build.targets -->
<Project>
  <ItemGroup>
    <PackageReference Include="Meziantou.Analyzer" PrivateAssets="all" />
    <PackageReference Include="Microsoft.CodeAnalysis.BannedApiAnalyzers" PrivateAssets="all" />
  </ItemGroup>
</Project>
```

With CPM, add version entries in `Directory.Packages.props`:

```xml
<PackageVersion Include="Meziantou.Analyzer" Version="2.0.187" />
<PackageVersion Include="Microsoft.CodeAnalysis.BannedApiAnalyzers" Version="3.11.0-beta1.25058.1" />
```

### Recommended Analyzer Packages

| Package | Focus |
|---------|-------|
| `Meziantou.Analyzer` | Security, performance, best practices (broad coverage) |
| `Microsoft.CodeAnalysis.BannedApiAnalyzers` | Ban specific APIs via `BannedSymbols.txt` |
| `Microsoft.CodeAnalysis.PublicApiAnalyzers` | Track public API surface (library authors) |
| `SonarAnalyzer.CSharp` | Security, reliability, maintainability |

### BannedSymbols.txt

When using `BannedApiAnalyzers`, create `BannedSymbols.txt` at the repo root and include it:

```xml
<!-- Directory.Build.targets -->
<ItemGroup>
  <AdditionalFiles Include="$(MSBuildThisFileDirectory)BannedSymbols.txt"
                   Condition="Exists('$(MSBuildThisFileDirectory)BannedSymbols.txt')" />
</ItemGroup>
```

Example `BannedSymbols.txt`:

```
T:System.DateTime;Use DateTimeOffset instead
M:System.DateTime.Now;Use DateTimeOffset.UtcNow instead
T:System.GC;Do not call GC methods directly
```


## Adding Analyzers to an Existing Project

1. **Enable built-in analyzers** — set `AnalysisLevel` and `EnforceCodeStyleInBuild` in `Directory.Build.props`
2. **Start at recommended level** — use `latest-recommended` if `latest-all` produces too many warnings
3. **Add EditorConfig overrides** — suppress rules that don't apply to your project type
4. **Add third-party analyzers** — via `Directory.Build.targets` with CPM versions
5. **Fix incrementally** — enable `TreatWarningsAsErrors` only after addressing existing warnings, or use `<NoWarn>` temporarily for categories being addressed

### Incremental Adoption Pattern

For large codebases, avoid fixing all warnings at once:

```xml
<!-- Directory.Build.props — temporary during migration -->
<PropertyGroup>
  <AnalysisLevel>latest-recommended</AnalysisLevel>
  <!-- Fix these categories first, then remove NoWarn entries -->
  <NoWarn>$(NoWarn);CA1822;CA1848</NoWarn>
</PropertyGroup>
```

Remove `NoWarn` entries as each category is addressed. Track progress with:

```bash
dotnet build 2>&1 | grep -oE 'CA[0-9]+' | sort | uniq -c | sort -rn
```


## References

- [Code Analysis Overview](https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/overview)
- [Configure Analyzers](https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/configuration-options)
- [Trimming Analyzer](https://learn.microsoft.com/en-us/dotnet/core/deploying/trimming/prepare-libraries-for-trimming)
- [AOT Compatibility](https://learn.microsoft.com/en-us/dotnet/core/deploying/native-aot/)
- [EditorConfig for .NET](https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/code-style-rule-options)
