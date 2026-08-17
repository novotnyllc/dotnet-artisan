# Modernize

Analyze existing .NET code for modernization opportunities. Identifies outdated target frameworks, deprecated packages, superseded API patterns, and missing modern best practices. Provides actionable recommendations for each finding.

## Modernization Checklist

Run through this checklist against the existing codebase. Each section identifies what to look for and what the modern replacement is.

### 1. Target Framework

Check `<TargetFramework>` in `.csproj` files (or `Directory.Build.props`):

| Current TFM | Status | Recommendation |
|-------------|--------|----------------|
| `net8.0` | LTS -- supported until Nov 2026 | Plan upgrade to `net10.0` (LTS) |
| `net9.0` | STS -- support ends May 2026 | Upgrade to `net10.0` promptly |
| `net7.0` | End of life | Upgrade immediately |
| `net6.0` | End of life | Upgrade immediately |
| `net5.0` or lower | End of life | Upgrade immediately |
| `netstandard2.0/2.1` | Supported (library compat) | Keep if multi-targeting for broad reach |
| `netcoreapp3.1` | End of life | Upgrade immediately |
| `.NET Framework 4.x` | Legacy | Evaluate migration feasibility |

To scan all projects:

```bash
# Find all TFMs in the solution
find . -name "*.csproj" -exec grep -h "TargetFramework" {} \; | sort -u

# Check Directory.Build.props
grep "TargetFramework" Directory.Build.props 2>/dev/null
```


### 2. Deprecated and Superseded Packages

Scan `Directory.Packages.props` (or individual `.csproj` files) for packages that have been superseded:

| Deprecated Package | Replacement | Since |
|-------------------|-------------|-------|
| `Microsoft.Extensions.Http.Polly` | `Microsoft.Extensions.Http.Resilience` | .NET 8 |
| `Newtonsoft.Json` (new projects) | `System.Text.Json` | .NET Core 3.0+ |
| `Microsoft.AspNetCore.Mvc.NewtonsoftJson` | Built-in STJ | .NET Core 3.0+ |
| `Swashbuckle.AspNetCore` | Built-in OpenAPI (`Microsoft.AspNetCore.OpenApi`) for document generation; keep Swashbuckle if using Swagger UI, filters, or codegen | .NET 9 |
| `NSwag.AspNetCore` | Built-in OpenAPI for document generation; keep NSwag if using client generation or Swagger UI features | .NET 9 |
| `Microsoft.Extensions.Logging.Log4Net.AspNetCore` | Built-in logging + `Serilog` or `OpenTelemetry` | .NET Core 2.0+ |
| `Microsoft.AspNetCore.Authentication.JwtBearer` (explicit NuGet package) | Remove explicit PackageReference — included in `Microsoft.AspNetCore.App` shared framework | .NET Core 3.0+ |
| `System.Data.SqlClient` | `Microsoft.Data.SqlClient` | .NET Core 3.0+ |
| `Microsoft.Azure.Storage.*` | `Azure.Storage.*` | 2020+ |
| `WindowsAzure.Storage` | `Azure.Storage.Blobs` / `Azure.Storage.Queues` | 2020+ |
| `Microsoft.Azure.ServiceBus` | `Azure.Messaging.ServiceBus` | 2020+ |
| `Microsoft.Azure.EventHubs` | `Azure.Messaging.EventHubs` | 2020+ |
| `EntityFramework` (EF6) | `Microsoft.EntityFrameworkCore` | .NET Core 1.0+ |
| `RestSharp` (older versions) | `HttpClient` + `System.Text.Json` | .NET Core+ |
| `AutoMapper` | Manual mapping or source-generated mappers | Preference |

To scan for deprecated packages:

```bash
# List all package references
grep -rh "PackageVersion\|PackageReference" \
  Directory.Packages.props $(find . -name "*.csproj") 2>/dev/null | \
  grep -i "Include=" | sort -u
```

**Note on Newtonsoft.Json:** Existing projects with deep Newtonsoft.Json usage (custom converters, `JObject` manipulation) may not benefit from immediate migration. Flag it but assess the migration cost.


### 3. Superseded API Patterns

Look for code patterns that have modern replacements:

#### Startup.cs / Program.cs Pattern

**Old (pre-.NET 6):**
```csharp
public class Startup
{
    public void ConfigureServices(IServiceCollection services) { }
    public void Configure(IApplicationBuilder app) { }
}
```

**Modern (minimal hosting):**
```csharp
var builder = WebApplication.CreateBuilder(args);
// ConfigureServices equivalent
var app = builder.Build();
// Configure equivalent
app.Run();
```

#### HttpClient Registration

**Old:**
```csharp
services.AddHttpClient<MyService>(client =>
{
    client.BaseAddress = new Uri("https://api.example.com");
})
.AddTransientHttpErrorPolicy(p => p.WaitAndRetryAsync(3, _ => TimeSpan.FromMilliseconds(300)));
```

**Modern (with Microsoft.Extensions.Resilience):**
```csharp
services.AddHttpClient<MyService>(client =>
{
    client.BaseAddress = new Uri("https://api.example.com");
})
.AddStandardResilienceHandler();
```

#### Synchronous I/O

**Flag:** `File.ReadAllText`, `Stream.Read`, `HttpClient` without `Async` suffix.

**Modern:** Use `async` variants -- `File.ReadAllTextAsync`, `Stream.ReadAsync`, `await httpClient.GetAsync()`.

#### String Concatenation in Hot Paths

**Flag:** String concatenation (`+`) or `String.Format` in logging, loops.

**Modern:** Use string interpolation with `LoggerMessage` source generators, or `StringBuilder`.

#### Legacy Collection Patterns

**Flag:** `Hashtable`, `ArrayList`, non-generic collections.

**Modern:** `Dictionary<TKey, TValue>`, `List<T>`, generic collections.

#### ILogger Pattern

**Old:**
```csharp
_logger.LogInformation("Processing order {OrderId}", orderId);
```

**Modern (high-performance):**
```csharp
[LoggerMessage(Level = LogLevel.Information, Message = "Processing order {OrderId}")]
static partial void LogProcessingOrder(ILogger logger, string orderId);
```


### 4. Missing Modern Build Configuration

Check for the absence of recommended build infrastructure:

| Missing | Check | Recommendation |
|---------|-------|----------------|
| Central Package Management | No `Directory.Packages.props` | See `references/project-structure.md` |
| Directory.Build.props | Properties scattered across `.csproj` files | Centralize shared properties |
| .editorconfig | No `.editorconfig` at repo root | See `references/project-structure.md` |
| global.json | No SDK pinning | Add for reproducible builds |
| NuGet audit | No `NuGetAudit` property | Enable in `Directory.Build.props` |
| Lock files | No `RestorePackagesWithLockFile` | Enable for deterministic restores |
| Package source mapping | No `packageSourceMapping` in `nuget.config` | Add for supply-chain security |
| Analyzers | No `AnalysisLevel` or `EnforceCodeStyleInBuild` | See `references/add-analyzers.md` |
| SourceLink | No SourceLink package reference | Add for debugger source navigation |
| Nullable reference types | `<Nullable>` not enabled | Enable globally |
| .slnx | Still using `.sln` with .NET 9+ SDK | Migrate with `dotnet sln migrate` |


### 5. Deprecated C# Language Patterns

| Old Pattern | Modern Replacement | Language Version |
|------------|-------------------|-----------------|
| `switch` statement with `case` | `switch` expression | C# 8 |
| `null != x` / `x != null` checks | `x is not null` | C# 9 |
| `new ClassName()` with obvious type | Target-typed `new()` | C# 9 |
| Block-scoped namespaces | File-scoped namespaces | C# 10 |
| `record class` explicit constructor | `record` with positional parameters | C# 10 |
| Manual string concatenation for multi-line | Raw string literals (`"""..."""`) | C# 11 |
| Explicit interface dispatch for `INumber<T>` | Generic math interfaces | C# 11 |
| `[Flags]` enum manual checks | Improved enum pattern matching | C# 11+ |
| Lambda without natural type | Natural function types | C# 10+ |
| `ValueTask` manual wrapping | `Task`/`ValueTask` with `ConfigureAwait` patterns | C# all |
| Primary constructor classes (manual) | Primary constructors on `class`/`struct` | C# 12 |
| Multiple `if`/`else if` type checks | `switch` on type with list patterns | C# 11+ |
| `params T[]` | `params ReadOnlySpan<T>`, `params` collections | C# 13 |
| Lock with `object` | `System.Threading.Lock` | C# 13 |


### 6. Security and Compliance

| Issue | Detection | Fix |
|-------|-----------|-----|
| Known vulnerabilities | `dotnet list package --vulnerable` | Update affected packages |
| Deprecated packages | `dotnet list package --deprecated` | Replace with successors |
| Outdated packages | `dotnet list package --outdated` | Evaluate updates |
| Missing HTTPS redirection | No `app.UseHttpsRedirection()` | Add to pipeline |
| Missing HSTS | No `app.UseHsts()` | Add for production |
| Hardcoded secrets | Connection strings in `appsettings.json` | Use User Secrets or Key Vault |

```bash
# Run all NuGet audits
dotnet list package --vulnerable --include-transitive
dotnet list package --deprecated
dotnet list package --outdated
```


## Running a Modernization Scan

Combine the checks into a systematic scan:

```bash
# 1. Check TFMs
echo "=== Target Frameworks ==="
find . -name "*.csproj" -exec grep -Hl "TargetFramework" {} \; | while read f; do
  echo "$f: $(grep -o '<TargetFramework[s]*>[^<]*' "$f" | head -1)"
done

# 2. Check for deprecated packages
echo "=== Package Audit ==="
dotnet list package --deprecated 2>/dev/null
dotnet list package --vulnerable --include-transitive 2>/dev/null

# 3. Check build infrastructure
echo "=== Build Infrastructure ==="
test -f Directory.Build.props && echo "OK: Directory.Build.props" || echo "MISSING: Directory.Build.props"
test -f Directory.Packages.props && echo "OK: Directory.Packages.props (CPM)" || echo "MISSING: Directory.Packages.props"
test -f .editorconfig && echo "OK: .editorconfig" || echo "MISSING: .editorconfig"
test -f global.json && echo "OK: global.json" || echo "MISSING: global.json"
test -f nuget.config && echo "OK: nuget.config" || echo "MISSING: nuget.config"

# 4. Check for old patterns in code
echo "=== Code Patterns ==="
grep -rl "class Startup" --include="*.cs" . 2>/dev/null && echo "FOUND: Legacy Startup.cs pattern"
grep -rl "Microsoft.Extensions.Http.Polly" --include="*.csproj" --include="*.props" . 2>/dev/null && echo "FOUND: Deprecated Polly package"
grep -rl "Swashbuckle" --include="*.csproj" --include="*.props" . 2>/dev/null && echo "FOUND: Swashbuckle (consider built-in OpenAPI for .NET 9+)"
grep -rl "System.Data.SqlClient" --include="*.csproj" --include="*.props" . 2>/dev/null && echo "FOUND: System.Data.SqlClient (use Microsoft.Data.SqlClient)"
```


## Prioritizing Modernization

Not all modernization is equally urgent. Prioritize by impact:

1. **Security** -- vulnerable packages, end-of-life TFMs (no security patches)
2. **Supportability** -- deprecated packages with no upstream maintenance
3. **Performance** -- patterns with significant perf impact (sync-over-async, legacy collections in hot paths)
4. **Developer experience** -- build infrastructure (CPM, analyzers, editorconfig) improves daily workflow
5. **Code style** -- language pattern updates are lowest priority but reduce cognitive load over time


## What's Next

This skill flags modernization opportunities. For executing upgrades:
- **TFM version upgrades and migration paths** -- `references/version-upgrade.md`
- **Multi-targeting strategies** -- `references/multi-targeting.md`
- **Polyfill packages for cross-version support** -- `references/multi-targeting.md`
- **Adding missing build infrastructure** -- `references/project-structure.md`, `references/scaffold-project.md`
- **Configuring analyzers** -- `references/add-analyzers.md`
- **Adding CI/CD** -- [skill:dotnet-devops]


## References

- [.NET Support Policy](https://dotnet.microsoft.com/platform/support/policy/dotnet-core)
- [Breaking Changes in .NET](https://learn.microsoft.com/en-us/dotnet/core/compatibility/breaking-changes)
- [.NET Upgrade Assistant](https://learn.microsoft.com/en-us/dotnet/core/porting/upgrade-assistant-overview)
- [NuGet Package Vulnerability Auditing](https://learn.microsoft.com/en-us/nuget/concepts/auditing-packages)
- [Modern C# Features](https://learn.microsoft.com/en-us/dotnet/csharp/whats-new/)
