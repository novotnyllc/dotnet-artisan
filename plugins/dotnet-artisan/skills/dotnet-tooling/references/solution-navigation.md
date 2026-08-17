# Solution Navigation

```bash
find . -maxdepth 2 \( -name "*.sln" -o -name "*.slnx" \) 2>/dev/null | head -5
```

Teaches agents to orient in .NET solutions: finding entry points, parsing solution files, traversing project dependencies, locating configuration files, and recognizing common solution layouts. Each subsection includes discovery commands/heuristics and example output.

## Prerequisites

.NET 8.0+ SDK. `dotnet` CLI available on PATH. Familiarity with SDK-style projects.

Cross-references: `references/project-structure.md` for project organization guidance, `references/csproj-reading.md` for reading and modifying .csproj files found during navigation, [skill:dotnet-testing] for test project identification and test type decisions.


## Subsection 1: Entry Point Discovery

.NET applications can start from several patterns. Do not assume every app has a traditional `Program.cs` with a `Main` method.

### Pattern 1: Traditional Program.cs with Main Method

Used in older projects, worker services, and when explicit control over hosting is needed.

**Discovery command:**

```bash
# Find Program.cs files containing a Main method
grep -rn "static.*void Main\|static.*Task Main\|static.*async.*Main" --include="*.cs" .
```

**Example output:**

```
src/MyApp.Worker/Program.cs:5:    public static async Task Main(string[] args)
src/MyApp.Console/Program.cs:3:    static void Main(string[] args)
```

### Pattern 2: Top-Level Statements (C# 9+)

Modern .NET projects (templates since .NET 6) use top-level statements -- the file contains no class or Main method, just executable code.

**Discovery command:**

```bash
# Find Program.cs files that do NOT contain class/namespace declarations
# (top-level statements have no enclosing class)
for f in $(find . -name "Program.cs" -not -path "*/obj/*" -not -path "*/bin/*"); do
  if ! grep -Eq '^[[:space:]]*(class|namespace)[[:space:]]' "$f" 2>/dev/null; then
    echo "Top-level: $f"
  fi
done
```

**Example output:**

```
Top-level: ./src/MyApp.Api/Program.cs
Top-level: ./src/MyApp.Web/Program.cs
```

**Typical content of a top-level Program.cs:**

```csharp
// No namespace, no class, no Main -- this IS the entry point
var builder = WebApplication.CreateBuilder(args);
builder.Services.AddControllers();
var app = builder.Build();
app.MapControllers();
app.Run();
```

### Pattern 3: Worker Services and Background Hosts

Worker services use `Host.CreateDefaultBuilder` or `Host.CreateApplicationBuilder` without a web server. They appear as `Exe` output type with `Microsoft.NET.Sdk.Worker` SDK.

**Discovery command:**

```bash
# Find worker service projects by SDK type
grep -rn 'Sdk="Microsoft.NET.Sdk.Worker"' --include="*.csproj" .

# Or find IHostedService/BackgroundService implementations
grep -rn "BackgroundService\|IHostedService" --include="*.cs" . | grep -v "obj/" | grep -v "bin/"
```

**Example output:**

```
src/MyApp.Worker/MyApp.Worker.csproj:1:<Project Sdk="Microsoft.NET.Sdk.Worker">
src/MyApp.Worker/Services/OrderProcessor.cs:8:public class OrderProcessor : BackgroundService
src/MyApp.Worker/Services/EmailSender.cs:5:public class EmailSender : IHostedService
```

### Pattern 4: Test Projects

Test projects are entry points for `dotnet test`. They may not have a `Program.cs` at all -- the test runner provides the entry point.

**Discovery command:**

```bash
# Find test projects by IsTestProject property or test SDK references
grep -rn "<IsTestProject>true</IsTestProject>" --include="*.csproj" .
grep -rn "Microsoft.NET.Test.Sdk\|xunit\|NUnit\|MSTest" --include="*.csproj" . | grep -v "obj/"  # Matches both xunit.v3 and legacy xunit
```

**Example output:**

```
tests/MyApp.Api.Tests/MyApp.Api.Tests.csproj:5:    <IsTestProject>true</IsTestProject>
tests/MyApp.Core.Tests/MyApp.Core.Tests.csproj:8:    <PackageReference Include="xunit.v3" />
```

### Summary Heuristic

When orienting in a new .NET solution, run these commands in sequence:

```bash
# 1. Find all .csproj files
find . -name "*.csproj" -not -path "*/obj/*" | sort

# 2. Identify output types (Exe = app entry point, Library = dependency)
grep -rn "<OutputType>" --include="*.csproj" .

# 3. Find all Program.cs files
find . -name "Program.cs" -not -path "*/obj/*" -not -path "*/bin/*"

# 4. Identify test projects
grep -rn "<IsTestProject>true" --include="*.csproj" .
```


## Subsection 2: Solution File Formats

.NET solutions use `.sln` (text-based, legacy format) or `.slnx` (XML-based, .NET 9+ preview). Both files list projects and their relationships.

### .sln Format

The traditional solution format is a text file with a custom syntax (not XML).

**Discovery and parsing commands:**

```bash
# Find solution files
find . -name "*.sln" -maxdepth 2

# List all projects in a solution using dotnet CLI
dotnet sln list
# Or specify the solution file explicitly:
dotnet sln MyApp.sln list
```

**Example output of `dotnet sln list`:**

```
Project(s)
----------
src/MyApp.Api/MyApp.Api.csproj
src/MyApp.Core/MyApp.Core.csproj
src/MyApp.Infrastructure/MyApp.Infrastructure.csproj
tests/MyApp.Api.Tests/MyApp.Api.Tests.csproj
tests/MyApp.Core.Tests/MyApp.Core.Tests.csproj
```

**Reading the .sln file directly** (useful when `dotnet sln list` is not available):

```bash
# Extract project entries from .sln file
grep "^Project(" MyApp.sln
```

**Example output:**

```
Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "MyApp.Api", "src\MyApp.Api\MyApp.Api.csproj", "{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}"
Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "MyApp.Core", "src\MyApp.Core\MyApp.Core.csproj", "{B2C3D4E5-F6A7-8901-BCDE-F12345678901}"
```

The GUID `{FAE04EC0-...}` identifies C# projects. The second value is the relative path to the `.csproj` file.

### .slnx Format (.NET 9+)

The `.slnx` format is an XML-based solution file introduced as a preview feature in .NET 9.

**Discovery and parsing commands:**

```bash
# Find .slnx files
find . -name "*.slnx" -maxdepth 2

# dotnet sln commands work with .slnx files too
dotnet sln MyApp.slnx list
```

**Example .slnx content:**

```xml
<Solution>
  <Folder Name="/src/">
    <Project Path="src/MyApp.Api/MyApp.Api.csproj" />
    <Project Path="src/MyApp.Core/MyApp.Core.csproj" />
  </Folder>
  <Folder Name="/tests/">
    <Project Path="tests/MyApp.Api.Tests/MyApp.Api.Tests.csproj" />
  </Folder>
</Solution>
```

**Key differences from .sln:**

| Feature | .sln | .slnx |
|---------|------|-------|
| Format | Custom text | XML |
| Readability | Low (GUIDs, custom syntax) | High (clean XML) |
| Availability | All .NET versions | .NET 9+ preview |
| Tooling | Full support | Partial (growing) |
| Solution folders | Nested GUID references | `<Folder>` elements |

### When No Solution File Exists

Some repositories use individual `.csproj` files without a `.sln`. Build and run from project directories:

```bash
# If no .sln exists, find all .csproj files and build individually
find . -name "*.csproj" -not -path "*/obj/*" | sort
dotnet build src/MyApp.Api/MyApp.Api.csproj
```


## Subsection 3: Project Dependency Traversal

Understanding `ProjectReference` chains is critical for determining build order, finding shared code, and identifying the impact of changes.

### Discovery Commands

```bash
# Find all ProjectReference entries across the solution
grep -rn "<ProjectReference" --include="*.csproj" . | grep -v "obj/"
```

**Example output:**

```
src/MyApp.Api/MyApp.Api.csproj:12:    <ProjectReference Include="../MyApp.Core/MyApp.Core.csproj" />
src/MyApp.Api/MyApp.Api.csproj:13:    <ProjectReference Include="../MyApp.Infrastructure/MyApp.Infrastructure.csproj" />
src/MyApp.Infrastructure/MyApp.Infrastructure.csproj:10:    <ProjectReference Include="../MyApp.Core/MyApp.Core.csproj" />
tests/MyApp.Api.Tests/MyApp.Api.Tests.csproj:14:    <ProjectReference Include="../../src/MyApp.Api/MyApp.Api.csproj" />
```

### Building a Dependency Graph

From the above output, the dependency graph is:

```
MyApp.Api.Tests
  -> MyApp.Api
       -> MyApp.Core
       -> MyApp.Infrastructure
            -> MyApp.Core
```

**Automated traversal using `dotnet list reference`:**

```bash
# List direct references for a specific project
dotnet list src/MyApp.Api/MyApp.Api.csproj reference
```

**Example output:**

```
Project reference(s)
--------------------
../MyApp.Core/MyApp.Core.csproj
../MyApp.Infrastructure/MyApp.Infrastructure.csproj
```

**Full transitive dependency analysis:**

```bash
# Build the full dependency tree by traversing transitively
# Start from the top-level project and follow each reference
dotnet list src/MyApp.Api/MyApp.Api.csproj reference
dotnet list src/MyApp.Infrastructure/MyApp.Infrastructure.csproj reference
# Continue until you reach projects with no ProjectReference entries
```

### Impact Analysis

When modifying a shared project like `MyApp.Core`, all projects that reference it (directly or transitively) are affected:

```bash
# Find all projects that reference a specific project
grep -rn "MyApp.Core.csproj" --include="*.csproj" . | grep -v "obj/"
```

**Example output:**

```
src/MyApp.Api/MyApp.Api.csproj:12:    <ProjectReference Include="../MyApp.Core/MyApp.Core.csproj" />
src/MyApp.Infrastructure/MyApp.Infrastructure.csproj:10:    <ProjectReference Include="../MyApp.Core/MyApp.Core.csproj" />
tests/MyApp.Core.Tests/MyApp.Core.Tests.csproj:14:    <ProjectReference Include="../../src/MyApp.Core/MyApp.Core.csproj" />
```

This means changes to `MyApp.Core` require testing `MyApp.Api`, `MyApp.Infrastructure`, and `MyApp.Core.Tests`.


## Subsection 4: Configuration File Locations

.NET projects use several configuration files scattered across the solution. Knowing where to find them is essential for understanding application behavior.

### appsettings*.json

**Discovery command:**

```bash
# Find all appsettings files
find . -name "appsettings*.json" -not -path "*/obj/*" -not -path "*/bin/*" | sort
```

**Example output:**

```
./src/MyApp.Api/appsettings.json
./src/MyApp.Api/appsettings.Development.json
./src/MyApp.Api/appsettings.Production.json
./src/MyApp.Worker/appsettings.json
```

**Key behavior:** Environment-specific files (`appsettings.{ENVIRONMENT}.json`) override values from the base `appsettings.json`. The environment is set via `DOTNET_ENVIRONMENT` or `ASPNETCORE_ENVIRONMENT`.

### launchSettings.json

**Discovery command:**

```bash
# Find launch settings (inside Properties/ folder of each project)
find . -name "launchSettings.json" -not -path "*/obj/*" -not -path "*/bin/*"
```

**Example output:**

```
./src/MyApp.Api/Properties/launchSettings.json
./src/MyApp.Web/Properties/launchSettings.json
```

**Key behavior:** Used by `dotnet run` and Visual Studio to configure launch profiles (ports, environment variables, launch URLs). Not deployed to production.

### Directory.Build.props and Directory.Build.targets

**Discovery command:**

```bash
# Find all Directory.Build.props/targets files (may exist at multiple levels)
find . -name "Directory.Build.props" -o -name "Directory.Build.targets" | sort
```

**Example output:**

```
./Directory.Build.props
./Directory.Build.targets
./src/Directory.Build.props
./tests/Directory.Build.props
```

**Key behavior:** MSBuild imports the nearest file found walking upward from the project directory. Nested files shadow parent files unless they explicitly import the parent (see `references/csproj-reading.md` for chaining).

### Other Configuration Files

```bash
# Find all .NET configuration files in one sweep
find . \( -name "nuget.config" -o -name "global.json" -o -name ".editorconfig" \
  -o -name "Directory.Packages.props" \) -not -path "*/obj/*" | sort
```

**Example output:**

```
./.editorconfig
./Directory.Packages.props
./global.json
./nuget.config
./src/.editorconfig
```

| File | Purpose | Resolution |
|------|---------|-----------|
| `nuget.config` | NuGet package sources and mappings | Hierarchical upward from project dir |
| `global.json` | SDK version pinning | Nearest file walking upward |
| `.editorconfig` | Code style and analyzer severity | Hierarchical (sections merge upward) |
| `Directory.Packages.props` | Central package version management | Hierarchical upward from project dir |


## Subsection 5: Common Solution Layouts

Recognizing the layout pattern helps agents navigate unfamiliar codebases faster.

### Pattern 1: src/tests Layout

The most common layout. Source projects in `src/`, test projects in `tests/`, mirroring names.

```
MyApp/
  MyApp.sln
  Directory.Build.props
  Directory.Packages.props
  global.json
  nuget.config
  .editorconfig
  src/
    MyApp.Api/
      MyApp.Api.csproj
      Program.cs
      Controllers/
      Services/
    MyApp.Core/
      MyApp.Core.csproj
      Models/
      Interfaces/
    MyApp.Infrastructure/
      MyApp.Infrastructure.csproj
      Data/
      Repositories/
  tests/
    MyApp.Api.Tests/
      MyApp.Api.Tests.csproj
    MyApp.Core.Tests/
      MyApp.Core.Tests.csproj
  docs/
    architecture.md
```

**Heuristics:**
- `src/` and `tests/` directories at root level.
- Test project names mirror source project names with `.Tests` suffix.
- Shared build config (`Directory.Build.props`, `global.json`) at the root.

**Discovery:**

```bash
# Detect src/tests layout
ls -d src/ tests/ 2>/dev/null && echo "src/tests layout detected"
```

### Pattern 2: Vertical Slice Layout

Organizes code by feature rather than by technical layer. Each slice contains its own models, handlers, and endpoints.

```
MyApp/
  MyApp.sln
  src/
    MyApp.Api/
      MyApp.Api.csproj
      Program.cs
      Features/
        Orders/
          CreateOrder.cs          # Handler + request + response
          GetOrder.cs
          OrderValidator.cs
          OrderEndpoints.cs       # Minimal API endpoint mapping
        Products/
          CreateProduct.cs
          ListProducts.cs
          ProductEndpoints.cs
      Common/
        Behaviors/
          ValidationBehavior.cs
        Middleware/
          ExceptionMiddleware.cs
  tests/
    MyApp.Api.Tests/
      Features/
        Orders/
          CreateOrderTests.cs
          GetOrderTests.cs
```

**Heuristics:**
- `Features/` directory within a project.
- Each feature folder contains multiple related files (handler, validator, endpoint).
- Tests mirror the feature folder structure.

**Discovery:**

```bash
# Detect vertical slice layout
find . -type d -name "Features" -not -path "*/obj/*" -not -path "*/bin/*"
```

### Pattern 3: Modular Monolith

Multiple bounded contexts as separate projects within a single solution, communicating through explicit interfaces or a shared message bus.

```
MyApp/
  MyApp.sln
  src/
    MyApp.Host/
      MyApp.Host.csproj          # Composition root -- references all modules
      Program.cs
    Modules/
      Ordering/
        MyApp.Ordering/
          MyApp.Ordering.csproj
          OrderingModule.cs       # Module registration (DI, endpoints)
          Domain/
          Application/
          Infrastructure/
        MyApp.Ordering.Tests/
      Catalog/
        MyApp.Catalog/
          MyApp.Catalog.csproj
          CatalogModule.cs
          Domain/
          Application/
          Infrastructure/
        MyApp.Catalog.Tests/
    MyApp.Shared/
      MyApp.Shared.csproj        # Cross-cutting contracts (events, interfaces)
```

**Heuristics:**
- `Modules/` directory with self-contained bounded contexts.
- A `Host` or `Startup` project that references all modules.
- A `Shared` project for cross-module contracts.

**Discovery:**

```bash
# Detect modular monolith layout
find . -type d -name "Modules" -not -path "*/obj/*" -not -path "*/bin/*"
# Or look for module registration patterns
grep -rn "Module\|AddModule\|RegisterModule" --include="*.cs" . | grep -v "obj/" | head -10
```


## Slopwatch Anti-Patterns

These patterns in test project discovery indicate an agent is hiding testing gaps rather than addressing them. See [skill:dotnet-testing] for the automated quality gate that detects these patterns.

### Disabled or Skipped Tests in Test Project Discovery

When navigating a solution and identifying test projects, watch for tests that exist but are silently disabled:

```csharp
// RED FLAG: skipped tests that will not run during dotnet test
[Fact(Skip = "Flaky -- revisit later")]
public async Task ProcessOrder_ConcurrentRequests_HandledCorrectly() { }

// RED FLAG: entire test class disabled via conditional compilation
#if false
public class OrderIntegrationTests
{
    [Fact]
    public async Task CreateOrder_PersistsToDatabase() { }
}
#endif

// RED FLAG: commented-out test methods
// [Fact]
// public void CalculateDiscount_NegativeAmount_ThrowsException() { }
```

**Discovery commands to check for disabled tests:**

```bash
# Find skipped tests
grep -rEn 'Skip[[:space:]]*=' --include="*.cs" . | grep -v "obj/" | grep -v "bin/"

# Find tests hidden behind #if false
grep -rn "#if false" --include="*.cs" . | grep -v "obj/" | grep -v "bin/"

# Find commented-out test attributes
grep -rEn '//[[:space:]]*\[(Fact|Theory|Test)\]' --include="*.cs" . | grep -v "obj/" | grep -v "bin/"
```

**Fix:** Investigate why tests are disabled. If they are flaky due to timing, fix the non-determinism or use `[Retry]` (xUnit v3). If they test removed functionality, delete them. Never leave disabled tests as invisible technical debt.


## Cross-References

- `references/project-structure.md` -- project organization, SDK selection, solution layout decisions
- `references/csproj-reading.md` -- reading and modifying .csproj files found during navigation
- [skill:dotnet-testing] -- test project identification, test types, test organization

## References

- [.NET Project SDK Overview](https://learn.microsoft.com/en-us/dotnet/core/project-sdk/overview)
- [dotnet sln Command](https://learn.microsoft.com/en-us/dotnet/core/tools/dotnet-sln)
- [.slnx Solution Format](https://learn.microsoft.com/en-us/visualstudio/ide/reference/solution-file-slnx)
- [Configuration in ASP.NET Core](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/configuration/)
- [Directory.Build.props/targets](https://learn.microsoft.com/en-us/visualstudio/msbuild/customize-by-directory)
