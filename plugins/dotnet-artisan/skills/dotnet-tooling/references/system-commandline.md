# System.CommandLine

System.CommandLine 2.0 stable API for building .NET CLI applications. Covers RootCommand, Command, Option\<T\>, Argument\<T\>, SetAction for handler binding, ParseResult-based value access, custom type parsing, validation, tab completion, and testing with TextWriter capture.

**Version assumptions:** .NET 8.0+ baseline. System.CommandLine 2.0.0+ (stable NuGet package, GA since November 2025). All examples target the 2.0.0 GA API surface.

**Breaking change note:** System.CommandLine 2.0.0 GA differs significantly from the pre-release beta4 API. Key changes: `SetHandler` replaced by `SetAction`, `ICommandHandler` removed in favor of `SynchronousCommandLineAction`/`AsynchronousCommandLineAction`, `InvocationContext` removed (ParseResult passed directly), `CommandLineBuilder` and `AddMiddleware` removed, `IConsole` removed in favor of TextWriter properties, and the `System.CommandLine.Hosting`/`System.CommandLine.NamingConventionBinder` packages discontinued. Do not use beta-era patterns.

## Package Reference

```xml
<ItemGroup>
  <PackageReference Include="System.CommandLine" Version="2.0.*" />
</ItemGroup>
```

System.CommandLine 2.0 targets .NET 8+ and .NET Standard 2.0. A single package provides all functionality -- the separate `System.CommandLine.Hosting`, `System.CommandLine.NamingConventionBinder`, and `System.CommandLine.Rendering` packages from the beta era are discontinued.


## RootCommand and Command Hierarchy

### Basic Command Structure

```csharp
using System.CommandLine;

// Root command -- the entry point
var rootCommand = new RootCommand("My CLI tool description");

// Add a subcommand via mutable collection
var listCommand = new Command("list", "List all items");
rootCommand.Subcommands.Add(listCommand);

// Nested subcommands: mycli migrate up
var migrateCommand = new Command("migrate", "Database migrations");
var upCommand = new Command("up", "Apply pending migrations");
var downCommand = new Command("down", "Revert last migration");
migrateCommand.Subcommands.Add(upCommand);
migrateCommand.Subcommands.Add(downCommand);
rootCommand.Subcommands.Add(migrateCommand);
```

### Collection Initializer Syntax

```csharp
// Fluent collection initializer (commands, options, arguments)
RootCommand rootCommand = new("My CLI tool")
{
    new Option<string>("--output", "-o") { Description = "Output file path" },
    new Argument<FileInfo>("file") { Description = "Input file" },
    new Command("list", "List all items")
    {
        new Option<int>("--limit") { Description = "Max items to return" }
    }
};
```


## Options and Arguments

### Option\<T\> -- Named Parameters

```csharp
// Option<T> -- named parameter (--output, -o)
// name is the first parameter; additional params are aliases
var outputOption = new Option<FileInfo>("--output", "-o")
{
    Description = "Output file path",
    Required = true  // was IsRequired in beta4
};

// Option with default value via DefaultValueFactory
var verbosityOption = new Option<int>("--verbosity")
{
    Description = "Verbosity level (0-3)",
    DefaultValueFactory = _ => 1
};
```

### Argument\<T\> -- Positional Parameters

```csharp
// Argument<T> -- positional parameter
// name is mandatory in 2.0 (used for help text)
var fileArgument = new Argument<FileInfo>("file")
{
    Description = "Input file to process"
};

rootCommand.Arguments.Add(fileArgument);
```

### Constrained Values

```csharp
var formatOption = new Option<string>("--format")
{
    Description = "Output format"
};
formatOption.AcceptOnlyFromAmong("json", "csv", "table");

rootCommand.Options.Add(formatOption);
```

### Aliases

```csharp
// Aliases are separate from the name in 2.0
// First constructor param is the name; rest are aliases
var verboseOption = new Option<bool>("--verbose", "-v")
{
    Description = "Enable verbose output"
};

// Or add aliases after construction
verboseOption.Aliases.Add("-V");
```

### Global Options

```csharp
// Global options are inherited by all subcommands
var debugOption = new Option<bool>("--debug")
{
    Description = "Enable debug mode",
    Recursive = true  // makes it global (inherited by subcommands)
};
rootCommand.Options.Add(debugOption);
```


## Setting Actions (Command Handlers)

In 2.0.0 GA, `SetHandler` is replaced by `SetAction`. Actions receive a `ParseResult` directly (no `InvocationContext`).

### Synchronous Action

```csharp
var outputOption = new Option<FileInfo>("--output", "-o")
{
    Description = "Output file path",
    Required = true
};
var verbosityOption = new Option<int>("--verbosity")
{
    DefaultValueFactory = _ => 1
};

rootCommand.Options.Add(outputOption);
rootCommand.Options.Add(verbosityOption);

rootCommand.SetAction(parseResult =>
{
    var output = parseResult.GetValue(outputOption)!;
    var verbosity = parseResult.GetValue(verbosityOption);
    Console.WriteLine($"Output: {output.FullName}, Verbosity: {verbosity}");
    return 0; // exit code
});
```

### Asynchronous Action with CancellationToken

```csharp
// Async actions receive ParseResult AND CancellationToken
rootCommand.SetAction(async (ParseResult parseResult, CancellationToken ct) =>
{
    var output = parseResult.GetValue(outputOption)!;
    var verbosity = parseResult.GetValue(verbosityOption);
    await ProcessAsync(output, verbosity, ct);
    return 0;
});
```

### Getting Values by Name

```csharp
// Values can also be retrieved by symbol name (requires type parameter)
rootCommand.SetAction(parseResult =>
{
    int delay = parseResult.GetValue<int>("--delay");
    string? message = parseResult.GetValue<string>("--message");
    Console.WriteLine($"Delay: {delay}, Message: {message}");
});
```

### Parsing and Invoking

```csharp
// Program.cs entry point -- parse then invoke
static int Main(string[] args)
{
    var rootCommand = BuildCommand();
    ParseResult parseResult = rootCommand.Parse(args);
    return parseResult.Invoke();
}

// Async entry point
static async Task<int> Main(string[] args)
{
    var rootCommand = BuildCommand();
    ParseResult parseResult = rootCommand.Parse(args);
    return await parseResult.InvokeAsync();
}
```

### Parse Without Invoking

```csharp
// Parse-only mode: inspect results without running actions
ParseResult parseResult = rootCommand.Parse(args);
if (parseResult.Errors.Count > 0)
{
    foreach (var error in parseResult.Errors)
    {
        Console.Error.WriteLine(error.Message);
    }
    return 1;
}

FileInfo? file = parseResult.GetValue(fileOption);
// Process directly without SetAction
```


For detailed examples (custom parsing, validation, configuration, tab completion, DI, testing, migration), see the Detailed Examples section below.

## Agent Gotchas

1. **Do not use beta4 API patterns.** The 2.0.0 GA API is fundamentally different. There is no `SetHandler` -- use `SetAction`. There is no `InvocationContext` -- actions receive `ParseResult` directly. There is no `CommandLineBuilder` -- configuration uses `ParserConfiguration`/`InvocationConfiguration`.
2. **Do not reference discontinued packages.** `System.CommandLine.Hosting`, `System.CommandLine.NamingConventionBinder`, and `System.CommandLine.Rendering` are discontinued. Use the single `System.CommandLine` package.
3. **Do not confuse `Option<T>` with `Argument<T>`.** Options are named (`--output file.txt`), arguments are positional (`mycli file.txt`). Using the wrong type produces confusing parse errors.
4. **Do not use `AddOption`/`AddCommand`/`AddAlias` methods.** These were replaced by mutable collection properties: `Options.Add`, `Subcommands.Add`, `Aliases.Add`. The old methods do not exist in 2.0.0.
5. **Do not use `IConsole` or `TestConsole` for testing.** These interfaces were removed. Use `InvocationConfiguration` with `StringWriter` for `Output`/`Error` to capture test output.
6. **Do not ignore the `CancellationToken` in async actions.** In 2.0.0 GA, `CancellationToken` is a mandatory second parameter for async `SetAction` delegates. The compiler warns (CA2016) when it is not propagated.
7. **Do not write `Console.Out` directly in command actions.** Write to `InvocationConfiguration.Output` for testability. If no configuration is provided, output goes to `Console.Out` by default, but direct writes bypass test capture.
8. **Do not set default values via constructors.** Use the `DefaultValueFactory` property instead. The old `getDefaultValue` constructor parameter does not exist in 2.0.0.


## References

- [System.CommandLine overview](https://learn.microsoft.com/en-us/dotnet/standard/commandline/)
- [System.CommandLine migration guide (beta5+)](https://learn.microsoft.com/en-us/dotnet/standard/commandline/migration-guide-2.0.0-beta5)
- [How to parse and invoke](https://learn.microsoft.com/en-us/dotnet/standard/commandline/how-to-parse-and-invoke)
- [How to customize parsing and validation](https://learn.microsoft.com/en-us/dotnet/standard/commandline/how-to-customize-parsing-and-validation)
- [System.CommandLine GitHub](https://github.com/dotnet/command-line-api)


## Attribution

Adapted from [Aaronontheweb/dotnet-skills](https://github.com/Aaronontheweb/dotnet-skills) (MIT license).

---

# System.CommandLine -- Detailed Examples

Extended code examples for custom type parsing, validation, configuration, tab completion, DI integration, testing, response files, and migration from beta4.

---

## Custom Type Parsing

### CustomParser Property

For types without built-in parsers, use the `CustomParser` property on `Option<T>` or `Argument<T>`.

```csharp
public record ConnectionInfo(string Host, int Port);

var connectionOption = new Option<ConnectionInfo?>("--connection")
{
    Description = "Connection as host:port",
    CustomParser = result =>
    {
        var raw = result.Tokens.SingleOrDefault()?.Value;
        if (raw is null)
        {
            result.AddError("--connection requires a value");
            return null;
        }

        var parts = raw.Split(':');
        if (parts.Length != 2 || !int.TryParse(parts[1], out var port))
        {
            result.AddError("Expected format: host:port");
            return null;
        }

        return new ConnectionInfo(parts[0], port);
    }
};
```

### DefaultValueFactory

```csharp
var portOption = new Option<int>("--port")
{
    Description = "Server port",
    DefaultValueFactory = _ => 8080  // type-safe default
};
```

### Combining CustomParser with Validation

```csharp
var uriOption = new Option<Uri?>("--uri")
{
    Description = "Target URI",
    CustomParser = result =>
    {
        var raw = result.Tokens.SingleOrDefault()?.Value;
        if (raw is null) return null;

        if (!Uri.TryCreate(raw, UriKind.Absolute, out var uri))
        {
            result.AddError("Invalid URI format");
            return null;
        }

        if (uri.Scheme != "https")
        {
            result.AddError("Only HTTPS URIs are accepted");
            return null;
        }

        return uri;
    }
};
```

---

## Validation

### Option and Argument Validators

```csharp
// Validators use Validators.Add (not AddValidator in 2.0)
var portOption = new Option<int>("--port") { Description = "Port number" };
portOption.Validators.Add(result =>
{
    var value = result.GetValue(portOption);
    if (value < 1 || value > 65535)
    {
        result.AddError("Port must be between 1 and 65535");
    }
});

// Arity constraints
var tagsOption = new Option<string[]>("--tag")
{
    Arity = new ArgumentArity(1, 5),  // 1 to 5 tags
    AllowMultipleArgumentsPerToken = true
};
```

### Built-In Validators

```csharp
// Accept only existing files/directories
var inputOption = new Option<FileInfo>("--input");
inputOption.AcceptExistingOnly();

// Accept only legal file names
var nameArg = new Argument<string>("name");
nameArg.AcceptLegalFileNamesOnly();

// Accept only from a set of values (moved from FromAmong)
var envOption = new Option<string>("--env");
envOption.AcceptOnlyFromAmong("dev", "staging", "prod");
```

---

## Configuration

In 2.0.0 GA, `CommandLineBuilder` is removed. Configuration uses `ParserConfiguration` (for parsing) and `InvocationConfiguration` (for invocation).

### Parser Configuration

```csharp
using System.CommandLine;

var config = new ParserConfiguration
{
    EnablePosixBundling = true,  // -abc == -a -b -c (default: true)
};

// Response files enabled by default; disable with:
// config.ResponseFileTokenReplacer = null;

ParseResult parseResult = rootCommand.Parse(args, config);
```

### Invocation Configuration

```csharp
var invocationConfig = new InvocationConfiguration
{
    // Redirect output for testing or customization
    Output = Console.Out,
    Error = Console.Error,

    // Process termination handling (default: 2 seconds)
    ProcessTerminationTimeout = TimeSpan.FromSeconds(5),

    // Disable default exception handler for custom try/catch
    EnableDefaultExceptionHandler = false
};

int exitCode = parseResult.Invoke(invocationConfig);
```

---

## Tab Completion

### Enabling Completion

Tab completion is built into RootCommand via the SuggestDirective (included by default).

Users register completions for their shell:

```bash
# Bash -- add to ~/.bashrc
source <(mycli [suggest:bash])

# Zsh -- add to ~/.zshrc
source <(mycli [suggest:zsh])

# PowerShell -- add to $PROFILE
mycli [suggest:powershell] | Out-String | Invoke-Expression

# Fish
mycli [suggest:fish] | source
```

### Custom Completions

```csharp
// Static completions
var envOption = new Option<string>("--environment");
envOption.CompletionSources.Add("development", "staging", "production");

// Dynamic completions
var branchOption = new Option<string>("--branch");
branchOption.CompletionSources.Add(ctx =>
[
    new CompletionItem("main"),
    new CompletionItem("develop"),
    // Dynamically fetch branches
    .. GetGitBranches().Select(b => new CompletionItem(b))
]);
```

---

## Automatic --version and --help

### Version

`--version` is automatically available on RootCommand via `VersionOption`. It reads from:
1. `AssemblyInformationalVersionAttribute` (preferred -- includes SemVer metadata)
2. `AssemblyVersionAttribute` (fallback)

```xml
<!-- Set in .csproj for automatic --version output -->
<PropertyGroup>
  <Version>1.2.3</Version>
  <!-- Or use source link / CI-generated version -->
  <InformationalVersion>1.2.3+abc123</InformationalVersion>
</PropertyGroup>
```

### Help

Help is automatically provided via `HelpOption` on RootCommand. Descriptions from constructors and `Description` properties flow into help text.

---

## Directives

Directives replace some beta-era `CommandLineBuilder` extensions. RootCommand exposes a `Directives` collection.

```csharp
// Built-in directives (included by default on RootCommand):
// [suggest] -- tab completion suggestions
// Other available directives:
rootCommand.Directives.Add(new DiagramDirective());           // [diagram] -- shows parse tree
rootCommand.Directives.Add(new EnvironmentVariablesDirective()); // [env:VAR=value]
```

### Parse Error Handling

```csharp
// Customize parse error behavior
ParseResult result = rootCommand.Parse(args);
if (result.Action is ParseErrorAction parseError)
{
    parseError.ShowTypoCorrections = true;
    parseError.ShowHelp = false;
}
int exitCode = result.Invoke();
```

---

## Dependency Injection Pattern

The `System.CommandLine.Hosting` package is discontinued in 2.0.0 GA. For DI integration, use `Microsoft.Extensions.Hosting` directly and compose services before parsing.

```csharp
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using System.CommandLine;

var host = Host.CreateDefaultBuilder(args)
    .ConfigureServices(services =>
    {
        services.AddSingleton<ISyncService, SyncService>();
        services.AddSingleton<IFileSystem, PhysicalFileSystem>();
    })
    .Build();

var serviceProvider = host.Services;

var sourceOption = new Option<string>("--source") { Description = "Source endpoint" };
var syncCommand = new Command("sync", "Synchronize data");
syncCommand.Options.Add(sourceOption);

syncCommand.SetAction(async (ParseResult parseResult, CancellationToken ct) =>
{
    var syncService = serviceProvider.GetRequiredService<ISyncService>();
    var source = parseResult.GetValue(sourceOption);
    await syncService.SyncAsync(source!, ct);
    return 0;
});

var rootCommand = new RootCommand("My CLI tool");
rootCommand.Subcommands.Add(syncCommand);

return await rootCommand.Parse(args).InvokeAsync();
```

---

## Testing

### Testing with InvocationConfiguration (TextWriter Capture)

`IConsole` is removed in 2.0.0 GA. For testing, redirect output via `InvocationConfiguration`.

```csharp
[Fact]
public void ListCommand_WritesItems_ToOutput()
{
    // Arrange
    var outputWriter = new StringWriter();
    var errorWriter = new StringWriter();
    var config = new InvocationConfiguration
    {
        Output = outputWriter,
        Error = errorWriter
    };

    var rootCommand = BuildRootCommand();

    // Act
    ParseResult parseResult = rootCommand.Parse("list --format json");
    int exitCode = parseResult.Invoke(config);

    // Assert
    Assert.Equal(0, exitCode);
    Assert.Contains("json", outputWriter.ToString());
    Assert.Empty(errorWriter.ToString());
}
```

### Testing Parsed Values Without Invocation

```csharp
[Fact]
public void ParseResult_ExtractsOptionValues()
{
    var portOption = new Option<int>("--port") { DefaultValueFactory = _ => 8080 };
    var rootCommand = new RootCommand { portOption };

    ParseResult result = rootCommand.Parse("--port 3000");

    Assert.Equal(3000, result.GetValue(portOption));
    Assert.Empty(result.Errors);
}

[Fact]
public void ParseResult_ReportsErrors_ForInvalidInput()
{
    var portOption = new Option<int>("--port");
    var rootCommand = new RootCommand { portOption };

    ParseResult result = rootCommand.Parse("--port not-a-number");

    Assert.NotEmpty(result.Errors);
}
```

### Testing Custom Parsers

```csharp
[Fact]
public void CustomParser_ParsesConnectionInfo()
{
    var connOption = new Option<ConnectionInfo?>("--connection")
    {
        CustomParser = result =>
        {
            var parts = result.Tokens.Single().Value.Split(':');
            return new ConnectionInfo(parts[0], int.Parse(parts[1]));
        }
    };
    var rootCommand = new RootCommand { connOption };

    ParseResult result = rootCommand.Parse("--connection localhost:5432");

    var conn = result.GetValue(connOption);
    Assert.Equal("localhost", conn!.Host);
    Assert.Equal(5432, conn.Port);
}
```

### Testing with DI Services

```csharp
[Fact]
public async Task SyncCommand_CallsService()
{
    var mockService = new Mock<ISyncService>();
    var services = new ServiceCollection()
        .AddSingleton(mockService.Object)
        .BuildServiceProvider();

    var sourceOption = new Option<string>("--source");
    var syncCommand = new Command("sync") { sourceOption };
    syncCommand.SetAction(async (ParseResult pr, CancellationToken ct) =>
    {
        var svc = services.GetRequiredService<ISyncService>();
        await svc.SyncAsync(pr.GetValue(sourceOption)!, ct);
        return 0;
    });

    var root = new RootCommand { syncCommand };
    int exitCode = await root.Parse("sync --source https://api.example.com")
        .InvokeAsync();

    Assert.Equal(0, exitCode);
    mockService.Verify(s => s.SyncAsync("https://api.example.com",
        It.IsAny<CancellationToken>()), Times.Once);
}
```

---

## Response Files

System.CommandLine supports response files (`@filename`) for passing large sets of arguments. Response file support is enabled by default; disable via `ParserConfiguration.ResponseFileTokenReplacer = null`.

```bash
# args.rsp
--source https://api.example.com
--output /tmp/results.json
--verbose

# Invoke with response file
mycli sync @args.rsp
```

---

## Migration from Beta4 to 2.0.0 GA

| Beta4 API | 2.0.0 GA Replacement |
|---|---|
| `command.SetHandler(...)` | `command.SetAction(...)` |
| `command.AddOption(opt)` | `command.Options.Add(opt)` |
| `command.AddCommand(sub)` | `command.Subcommands.Add(sub)` |
| `command.AddArgument(arg)` | `command.Arguments.Add(arg)` |
| `option.AddAlias("-x")` | `option.Aliases.Add("-x")` |
| `option.AddValidator(...)` | `option.Validators.Add(...)` |
| `option.IsRequired = true` | `option.Required = true` |
| `option.IsHidden = true` | `option.Hidden = true` |
| `InvocationContext context` | `ParseResult parseResult` (in SetAction) |
| `context.GetCancellationToken()` | `CancellationToken ct` (second param in async SetAction) |
| `context.Console` | `InvocationConfiguration.Output / .Error` |
| `IConsole` / `TestConsole` | `StringWriter` via `InvocationConfiguration` |
| `new CommandLineBuilder(root).UseDefaults().Build()` | `root.Parse(args)` (middleware built-in) |
| `builder.AddMiddleware(...)` | Removed -- use `ParseResult.Action` inspection or wrap `Invoke` |
| `CommandLineBuilder` | `ParserConfiguration` + `InvocationConfiguration` |
| `UseCommandHandler<T,T>` (Hosting) | Build host directly, resolve services in SetAction |
| `Parser` class | `CommandLineParser` (static class) |
| `FindResultFor(symbol)` | `GetResult(symbol)` |
| `ErrorMessage = "..."` | `result.AddError("...")` |
| `getDefaultValue: () => val` | `DefaultValueFactory = _ => val` |
| `ParseArgument<T>` delegate | `CustomParser` property |

---
