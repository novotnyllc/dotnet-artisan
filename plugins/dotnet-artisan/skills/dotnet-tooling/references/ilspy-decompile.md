# ILSpy Decompilation

Decompile .NET assemblies to understand API internals, inspect NuGet package source, view framework implementation details, or analyze compiled binaries. Uses `ilspycmd` (the CLI for ILSpy).

## Quick Start

```bash
# .NET 10+: run via dnx without installing
dnx ilspycmd MyLibrary.dll

# Or install as a global tool
dotnet tool install -g ilspycmd
ilspycmd MyLibrary.dll
```

## Common Assembly Locations

### NuGet Packages

```bash
# Global packages cache
~/.nuget/packages/<package-name>/<version>/lib/<tfm>/

# Examples
~/.nuget/packages/newtonsoft.json/13.0.3/lib/netstandard2.0/Newtonsoft.Json.dll
~/.nuget/packages/microsoft.extensions.dependencyinjection/9.0.0/lib/net9.0/Microsoft.Extensions.DependencyInjection.dll
~/.nuget/packages/polly.core/8.5.0/lib/net8.0/Polly.Core.dll
```

### .NET Runtime Libraries

```bash
# Find install location
dotnet --list-runtimes

# Runtime assemblies
# Linux/macOS
/usr/share/dotnet/shared/Microsoft.NETCore.App/<version>/
/usr/share/dotnet/shared/Microsoft.AspNetCore.App/<version>/

# macOS (Homebrew)
/usr/local/share/dotnet/shared/Microsoft.NETCore.App/<version>/

# Windows
C:/Program Files/dotnet/shared/Microsoft.NETCore.App/<version>/
C:/Program Files/dotnet/shared/Microsoft.AspNetCore.App/<version>/

# Home-dir install
~/.dotnet/shared/Microsoft.NETCore.App/<version>/
```

### Project Build Output

```bash
./bin/Debug/net10.0/<AssemblyName>.dll
./bin/Release/net10.0/publish/<AssemblyName>.dll
```

## Commands

### Basic Decompilation

```bash
# Decompile to stdout
ilspycmd MyLibrary.dll

# Decompile to output directory
ilspycmd -o ./decompiled MyLibrary.dll

# Decompile as compilable project
ilspycmd -p -o ./project MyLibrary.dll

# Decompile with nested namespace folders
ilspycmd -p -o ./project --nested-directories MyLibrary.dll
```

### Targeted Decompilation

```bash
# Decompile a specific type
ilspycmd -t Namespace.ClassName MyLibrary.dll

# Decompile with specific C# version
ilspycmd -lv CSharp12_0 MyLibrary.dll

# Decompile with reference path for dependencies
ilspycmd -r ./dependencies MyLibrary.dll
```

### View IL Code

```bash
# Show IL instead of C#
ilspycmd -il MyLibrary.dll

# Show IL for specific type
ilspycmd -il -t Namespace.ClassName MyLibrary.dll
```

### List Types

```bash
ilspycmd -l class MyLibrary.dll       # List all classes
ilspycmd -l interface MyLibrary.dll   # List interfaces
ilspycmd -l struct MyLibrary.dll      # List structs
ilspycmd -l enum MyLibrary.dll        # List enums
ilspycmd -l delegate MyLibrary.dll    # List delegates
```

## Workflow

1. Identify the API, class, or method to understand
2. Locate the assembly (NuGet cache, runtime, or build output)
3. List types to find the exact name: `ilspycmd -l class MyLib.dll`
4. Decompile the specific type: `ilspycmd -t Full.TypeName MyLib.dll`
5. If dependencies are missing, add reference paths: `ilspycmd -r ./deps -t Type MyLib.dll`

## Common Scenarios

### Understand how a framework API works

```bash
# How does JsonSerializer.Serialize work?
ilspycmd -t System.Text.Json.JsonSerializer \
  ~/.dotnet/shared/Microsoft.NETCore.App/10.0.0/System.Text.Json.dll

# How does WebApplication.CreateBuilder work?
ilspycmd -t Microsoft.AspNetCore.Builder.WebApplication \
  ~/.dotnet/shared/Microsoft.AspNetCore.App/10.0.0/Microsoft.AspNetCore.dll
```

### Inspect a NuGet package implementation

```bash
# Decompile entire package to a project for exploration
ilspycmd -p -o ./polly-src \
  ~/.nuget/packages/polly.core/8.5.0/lib/net8.0/Polly.Core.dll
```

### Compare C# and IL

```bash
# C# view
ilspycmd -t MyNamespace.MyClass MyLibrary.dll

# IL view for the same type (see what the compiler actually generates)
ilspycmd -il -t MyNamespace.MyClass MyLibrary.dll
```

## C# Language Versions

Use `-lv` to control the C# version used for decompilation output:

| Flag | Version |
|------|---------|
| `CSharp1` through `CSharp12_0` | Specific C# version |
| `Latest` | Latest stable |
| `Preview` | Preview features |

Higher versions produce more idiomatic code (records, pattern matching, etc.). Lower versions show the expanded form.

## Agent Gotchas

1. **Use `dnx ilspycmd` on .NET 10+** — no global tool install needed. Fall back to `dotnet tool install -g ilspycmd` on older SDKs.
2. **Reference assemblies are stubs** — files under `packs/Microsoft.NETCore.App.Ref/` are design-time facades with no method bodies. Decompile from `shared/Microsoft.NETCore.App/` instead.
3. **Dependencies may be needed** — if decompilation shows unresolved types, use `-r` to point to a directory containing the dependency DLLs.
4. **NuGet cache paths vary by platform** — `~/.nuget/packages/` is the default on all platforms, but can be overridden via `NUGET_PACKAGES` env var.
5. **Don't decompile to stdout for large assemblies** — use `-o` to write to a directory, or `-t` to target a specific type.

## References

- [ILSpy GitHub](https://github.com/icsharpcode/ILSpy)
- [ilspycmd NuGet](https://www.nuget.org/packages/ilspycmd)
