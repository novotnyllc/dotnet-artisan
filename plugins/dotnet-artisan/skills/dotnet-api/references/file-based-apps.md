# File-Based Apps

.NET 10 SDK file-based apps let you build, run, and publish C# applications from a single `.cs` file without creating a `.csproj` project file. The SDK auto-generates project configuration from `#:` directives embedded in the source file. This feature targets scripts, utilities, and small applications where traditional project scaffolding is unnecessary.

**This is NOT file I/O.** For FileStream, RandomAccess, FileSystemWatcher, and path handling, see [skill:dotnet-csharp].

**Prerequisites:** Requires .NET 10 SDK or later. Run [skill:dotnet-tooling] to confirm SDK version.


## Directives Overview

File-based apps use `#:` directives to configure the build. Directives are **SDK-level instructions, not C# syntax**. They must appear at the top of the `.cs` file, before any C# code.

Four directive types are supported:

| Directive | Purpose | Example |
|-----------|---------|---------|
| `#:package` | Add a NuGet package reference | `#:package Serilog@3.1.1` |
| `#:sdk` | Set the SDK (default: `Microsoft.NET.Sdk`) | `#:sdk Microsoft.NET.Sdk.Web` |
| `#:property` | Set an MSBuild property | `#:property PublishAot=false` |
| `#:project` | Reference another project file | `#:project ../Lib/Lib.csproj` |

---

## `#:package` Directive

Adds a NuGet package reference. Specify the package name, optionally followed by `@version`.

```csharp
#:package Newtonsoft.Json
#:package Serilog@3.1.1
#:package Spectre.Console@*
```

Version behavior:
- **`@version`** -- pins to a specific version
- **`@*`** -- uses the latest stable version (NuGet floating version)
- **No version** -- only works when Central Package Management (CPM) is configured with a `Directory.Packages.props` file; otherwise, specify a version explicitly or use `@*`

---

## `#:sdk` Directive

Specifies which SDK to use. Defaults to `Microsoft.NET.Sdk` if omitted.

```csharp
#:sdk Microsoft.NET.Sdk.Web
```

```csharp
#:sdk Aspire.AppHost.Sdk@9.2.0
```

Use this directive to access SDK-specific features. For example, `Microsoft.NET.Sdk.Web` enables ASP.NET Core features and automatically includes `*.json` configuration files in the build.

---

## `#:property` Directive

Sets an MSBuild property value. Use this to customize build behavior.

```csharp
#:property TargetFramework=net10.0
#:property PublishAot=false
```

### Conditional Property Values

Property directives support MSBuild property functions and expressions for conditional configuration.

**Environment variables with defaults:**

```csharp
#:property LogLevel=$([MSBuild]::ValueOrDefault('$(LOG_LEVEL)', 'Information'))
```

**Conditional expressions:**

```csharp
#:property EnableLogging=$([System.Convert]::ToBoolean($([MSBuild]::ValueOrDefault('$(ENABLE_LOGGING)', 'true'))))
```

---

## `#:project` Directive

References another project file or directory containing a project file. Use this to share code between a file-based app and a traditional project.

```csharp
#:project ../SharedLibrary/SharedLibrary.csproj
```

The referenced project is built and linked as a project reference, just like `<ProjectReference>` in a `.csproj`.

---

## CLI Commands

The .NET CLI supports file-based apps through familiar commands.

### Run

```bash
# Preferred: pass file directly
dotnet run app.cs

# Explicit --file option
dotnet run --file app.cs

# Shorthand (no 'run' subcommand)
dotnet app.cs

# Pass arguments after --
dotnet run app.cs -- arg1 arg2
```

When a `.csproj` exists in the current directory, `dotnet run app.cs` (without `--file`) runs the project and passes `app.cs` as an argument to preserve backward compatibility. Use `dotnet run --file app.cs` to force file-based execution.

### Pipe from stdin

```bash
echo 'Console.WriteLine("hello");' | dotnet run -
```

The `-` argument reads C# code from standard input. Useful for quick testing and shell script integration.

### Build

```bash
dotnet build app.cs
```

Build output goes to a cached location under the system temp directory by default. Override with `--output` or `#:property OutputPath=./output`.

### Clean

```bash
# Clean build artifacts for a specific file
dotnet clean app.cs

# Clean all file-based app caches in the current directory
dotnet clean file-based-apps

# Clean caches unused for N days (default: 30)
dotnet clean file-based-apps --days 7
```

### Publish

```bash
dotnet publish app.cs
```

File-based apps enable **native AOT by default**. The output goes to an `artifacts` directory next to the `.cs` file. Disable AOT with `#:property PublishAot=false`.

### Pack as .NET Tool

```bash
dotnet pack app.cs
```

File-based apps set `PackAsTool=true` by default. Disable with `#:property PackAsTool=false`.

### Restore

```bash
dotnet restore app.cs
```

Restore runs implicitly on build/run. Pass `--no-restore` to `dotnet build` or `dotnet run` to skip it.

---

## Shell Execution (Unix)

Enable direct execution on Unix-like systems with a shebang line.

```csharp
#!/usr/bin/env dotnet
#:package Spectre.Console

using Spectre.Console;

AnsiConsole.MarkupLine("[green]Hello, World![/]");
```

```bash
chmod +x app.cs
./app.cs
```

The file must use `LF` line endings (not `CRLF`) and must not include a BOM.

---

## Launch Profiles

File-based apps support launch profiles via a flat `[AppName].run.json` file in the same directory as the source file. For `app.cs`, create `app.run.json`:

```json
{
  "profiles": {
    "https": {
      "commandName": "Project",
      "launchBrowser": true,
      "applicationUrl": "https://localhost:5001;http://localhost:5000",
      "environmentVariables": {
        "ASPNETCORE_ENVIRONMENT": "Development"
      }
    }
  }
}
```

Select a profile with `--launch-profile`:

```bash
dotnet run app.cs --launch-profile https
```

If both `app.run.json` and `Properties/launchSettings.json` exist, the traditional location takes priority.

---

## User Secrets

File-based apps generate a stable user secrets ID from the file's full path.

```bash
dotnet user-secrets set "ApiKey" "your-secret-value" --file app.cs
dotnet user-secrets list --file app.cs
```

---

## Implicit Build Files

File-based apps respect MSBuild and NuGet configuration files in the same or parent directories:

- **`Directory.Build.props`** -- inherited MSBuild properties
- **`Directory.Build.targets`** -- inherited MSBuild targets
- **`Directory.Packages.props`** -- Central Package Management versions
- **`nuget.config`** -- NuGet package source configuration
- **`global.json`** -- SDK version pinning

Be mindful of these files when placing file-based apps in a repository that also contains traditional projects. Inherited properties may cause unexpected build behavior.

---

## Build Caching

The SDK caches build outputs based on source content, directives, SDK version, and implicit build files. Caching improves repeated `dotnet run` performance.

Known caching pitfalls:
- Changes to implicit build files (`Directory.Build.props`, etc.) may not trigger rebuilds
- Moving files to different directories does not invalidate the cache
- **Concurrent execution** of the same file-based app can cause build contention errors -- build first with `dotnet build app.cs`, then run multiple instances with `dotnet run app.cs --no-build`

Clear the cache with `dotnet clean app.cs` or `dotnet clean file-based-apps`.

---

## Folder Layout

Do not place file-based apps inside a `.csproj` project's directory tree. The project's implicit build configuration will interfere.

```
# Recommended layout
repo/
  src/
    MyProject/
      MyProject.csproj
      Program.cs
  scripts/           # Separate directory for file-based apps
    utility.cs
    tool.cs
```

---

## Migration: File-Based to Project-Based

When a file-based app outgrows a single file, convert to a traditional project.

### Automatic Conversion

```bash
dotnet project convert app.cs
```

This creates a new directory named after the app, containing:
- A `.csproj` with equivalent SDK, properties, and package references derived from the `#:` directives
- A copy of the `.cs` file with `#:` directives removed

The original `.cs` file is left untouched.

### When to Convert

Convert to a project-based app when:
- Multiple source files are needed
- Complex MSBuild customization is required beyond what `#:property` supports
- The app needs `dotnet test` with a test framework
- The app needs integration with CI/CD workflows that expect a `.csproj`
- Team members need IDE project support (Solution Explorer, etc.)

---

## Default Behaviors

File-based apps differ from project-based apps in several default settings:

| Setting | File-based default | Project-based default |
|---------|-------------------|----------------------|
| Native AOT (`PublishAot`) | `true` | `false` |
| Pack as tool (`PackAsTool`) | `true` | `false` |
| Build output location | System temp directory | `bin/` in project directory |
| Publish output location | `artifacts/` next to `.cs` file | `bin/<config>/<tfm>/publish/` |

---

## Agent Gotchas

1. **Do not confuse file-based apps with file I/O** -- `dotnet-file-based-apps` covers running C# without a project file (`.NET 10 SDK feature`). For FileStream, RandomAccess, and path handling, use [skill:dotnet-csharp].
2. **Do not use `#:` directives after C# code** -- all directives must appear at the top of the file, before any C# statements, `using` directives, or namespace declarations. The SDK ignores directives placed later in the file.
3. **Do not omit package versions without CPM** -- `#:package SomePackage` without a version only works when Central Package Management is configured via `Directory.Packages.props`. Without CPM, use `#:package SomePackage@1.0.0` or `#:package SomePackage@*`.
4. **Do not assume `dotnet build` and `dotnet test` work the same** -- `dotnet build app.cs` compiles via a virtual project, but `dotnet test` does not apply to file-based apps. Convert to a project for test framework support.
5. **Do not place file-based apps inside a `.csproj` project directory** -- the project's implicit build files (`Directory.Build.props`, etc.) will affect the file-based app, causing unexpected behavior. Use a separate directory.
6. **Do not run concurrent instances without pre-building** -- parallel execution of the same file-based app causes build output contention. Build first with `dotnet build app.cs`, then run instances with `dotnet run app.cs --no-build`.
7. **Do not forget backward compatibility** -- when a `.csproj` exists in the current directory, `dotnet run app.cs` passes `app.cs` as an argument to the project rather than running it as a file-based app. Use `dotnet run --file app.cs` to force file-based execution.
8. **Do not use `CRLF` line endings with shebang** -- Unix shebang execution requires `LF` line endings and no BOM. Files with `CRLF` will fail with `/usr/bin/env: 'dotnet\r': No such file or directory`.

---

## References

- [File-based apps - .NET](https://learn.microsoft.com/en-us/dotnet/core/sdk/file-based-apps)
- [Native AOT deployment](https://learn.microsoft.com/en-us/dotnet/core/deploying/native-aot/)
- [Central Package Management](https://learn.microsoft.com/en-us/nuget/consume-packages/central-package-management)
- [MSBuild property functions](https://learn.microsoft.com/en-us/visualstudio/msbuild/property-functions)
