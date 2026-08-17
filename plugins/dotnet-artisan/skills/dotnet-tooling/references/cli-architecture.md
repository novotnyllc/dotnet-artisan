# CLI Architecture

Layered CLI application architecture for .NET: command/handler/service separation following clig.dev principles, configuration precedence (appsettings → environment variables → CLI arguments), structured logging in CLI context, exit code conventions, stdin/stdout/stderr patterns, and testing CLI applications via in-process invocation with output capture.

**Version assumptions:** .NET 8.0+ baseline. Patterns apply to CLI tools built with System.CommandLine 2.0 and generic host.

## clig.dev Principles for .NET CLI Tools

The [Command Line Interface Guidelines](https://clig.dev/) provide language-agnostic principles for well-behaved CLI tools. These translate directly to .NET patterns.

### Core Principles

| Principle | Implementation |
|-----------|---------------|
| Human-first output by default | Use `Console.Out` for data, `Console.Error` for diagnostics |
| Machine-readable output with `--json` | Add a `--json` global option that switches output format |
| Stderr for status/diagnostics | Logging, progress bars, and prompts go to stderr |
| Stdout for data only | Piped output (`mycli list \| jq .`) must not contain log noise |
| Non-zero exit on failure | Return specific exit codes (see conventions below) |
| Fail early, fail loudly | Validate inputs before doing work |
| Respect `NO_COLOR` | Check `Environment.GetEnvironmentVariable("NO_COLOR")` |
| Support `--verbose` and `--quiet` | Global options controlling output verbosity |

### Stdout vs Stderr in .NET

```csharp
// Data output -- goes to stdout (can be piped)
Console.Out.WriteLine(JsonSerializer.Serialize(result, jsonContext.Options));

// Status/diagnostic output -- goes to stderr (user sees it, pipe ignores it)
Console.Error.WriteLine("Processing 42 files...");

// With ILogger (when using hosting)
// ILogger writes to stderr via console provider by default
logger.LogInformation("Connected to {Endpoint}", endpoint);
```


## Layered Command → Handler → Service Architecture

Separate CLI concerns into three layers:

```
┌─────────────────────────────────────┐
│  Commands (System.CommandLine)      │  Parse args, wire options
│  ─ RootCommand, Command, Option<T>  │
├─────────────────────────────────────┤
│  Handlers (orchestration)           │  Coordinate services, format output
│  ─ SetAction delegates / classes    │
├─────────────────────────────────────┤
│  Services (business logic)          │  Pure logic, no CLI concerns
│  ─ Interfaces + implementations     │
└─────────────────────────────────────┘
```

### Why Three Layers

- **Commands** know about CLI syntax (options, arguments, subcommands) but not business logic
- **Handlers** bridge CLI inputs to service calls and format results for output
- **Services** contain domain logic and are reusable outside the CLI (tests, libraries, APIs)

### Example Structure

```
src/
  MyCli/
    MyCli.csproj
    Program.cs                    # RootCommand + SetAction wiring
    Commands/
      SyncCommandDefinition.cs    # Command, options, arguments
    Handlers/
      SyncHandler.cs              # Orchestrates services, formats output
    Services/
      ISyncService.cs             # Business logic interface
      SyncService.cs              # Implementation (no CLI awareness)
    Output/
      ConsoleFormatter.cs         # Table/JSON output formatting
```

### Command Definition Layer

```csharp
// Commands/SyncCommandDefinition.cs
public static class SyncCommandDefinition
{
    public static readonly Option<Uri> SourceOption = new(
        "--source", "Source endpoint URL") { Required = true };

    public static readonly Option<bool> DryRunOption = new(
        "--dry-run", "Preview changes without applying");

    public static Command Create()
    {
        var command = new Command("sync", "Synchronize data from source");
        command.Options.Add(SourceOption);
        command.Options.Add(DryRunOption);
        return command;
    }
}
```

### Handler Layer (System.CommandLine 2.0 GA)

In System.CommandLine 2.0, handlers are registered via `SetAction` on the command. The action receives a `ParseResult` for accessing option values and a `CancellationToken`.

```csharp
// Handlers/SyncHandler.cs
public class SyncHandler
{
    private readonly ISyncService _syncService;
    private readonly ILogger<SyncHandler> _logger;

    public SyncHandler(ISyncService syncService, ILogger<SyncHandler> logger)
    {
        _syncService = syncService;
        _logger = logger;
    }

    public async Task<int> HandleAsync(
        Uri source, bool dryRun, CancellationToken ct)
    {
        _logger.LogInformation("Syncing from {Source}", source);

        var result = await _syncService.SyncAsync(source, dryRun, ct);

        if (result.HasErrors)
        {
            Console.Error.WriteLine($"Sync failed: {result.ErrorMessage}");
            return ExitCodes.SyncFailed;
        }

        Console.Out.WriteLine($"Synced {result.ItemCount} items.");
        return ExitCodes.Success;
    }
}
```

### Wiring Commands to Handlers with SetAction

```csharp
// Program.cs
var syncCommand = SyncCommandDefinition.Create();
syncCommand.SetAction(async (parseResult, ct) =>
{
    var source = parseResult.GetValue(SyncCommandDefinition.SourceOption)!;
    var dryRun = parseResult.GetValue(SyncCommandDefinition.DryRunOption);

    // Build services (or use a DI container)
    var handler = new SyncHandler(syncService, logger);
    return await handler.HandleAsync(source, dryRun, ct);
});

var rootCommand = new RootCommand("MyCli tool");
rootCommand.Subcommands.Add(syncCommand);
await rootCommand.InvokeAsync(args);
```

### Service Layer

```csharp
// Services/ISyncService.cs -- no CLI dependency
public interface ISyncService
{
    Task<SyncResult> SyncAsync(Uri source, bool dryRun, CancellationToken ct);
}

// Services/SyncService.cs
public class SyncService : ISyncService
{
    private readonly HttpClient _httpClient;

    public SyncService(HttpClient httpClient)
    {
        _httpClient = httpClient;
    }

    public async Task<SyncResult> SyncAsync(
        Uri source, bool dryRun, CancellationToken ct)
    {
        // Pure business logic -- testable without CLI infrastructure
        var data = await _httpClient.GetFromJsonAsync<SyncData>(source, ct);
        // ...
        return new SyncResult(ItemCount: data.Items.Length);
    }
}
```


## Configuration Precedence

CLI tools use a specific configuration precedence (lowest to highest priority):

1. **Compiled defaults** -- hardcoded fallback values
2. **appsettings.json** -- shipped with the tool
3. **appsettings.{Environment}.json** -- environment-specific overrides
4. **Environment variables** -- set by shell or CI
5. **CLI arguments** -- explicit user input (highest priority)

### Implementation with Configuration

```csharp
// Build configuration with proper precedence
var config = new ConfigurationBuilder()
    .AddJsonFile("appsettings.json", optional: true)           // Layer 2
    .AddJsonFile($"appsettings.{env}.json", optional: true)    // Layer 3
    .AddEnvironmentVariables()                                  // Layer 4
    .Build();

// Layer 4b: User-specific config file
var userConfigPath = Path.Combine(
    Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
    ".mycli", "config.json");
if (File.Exists(userConfigPath))
{
    config = new ConfigurationBuilder()
        .AddConfiguration(config)
        .AddJsonFile(userConfigPath, optional: true)
        .Build();
}

// Layer 5: CLI args override everything via ParseResult
syncCommand.SetAction(async (parseResult, ct) =>
{
    var source = parseResult.GetValue(sourceOption)
        ?? new Uri(config["DefaultSource"] ?? "https://fallback.example.com");
    // CLI arg > config > compiled default
});
```

### User-Level Configuration

Many CLI tools support user-level config (e.g., `~/.mycli/config.json`, `~/.config/mycli/config.yaml`). Follow platform conventions:

| Platform | Location |
|----------|----------|
| Linux/macOS | `~/.config/mycli/` or `~/.mycli/` |
| Windows | `%APPDATA%\mycli\` |
| XDG-compliant | `$XDG_CONFIG_HOME/mycli/` |


## Structured Logging in CLI Context

### Configuring Logging for CLI

CLI tools need different logging than web apps: logs go to stderr, and verbosity is controlled by flags.

```csharp
using var loggerFactory = LoggerFactory.Create(logging =>
{
    logging.ClearProviders();
    logging.AddConsole(options =>
    {
        // Write to stderr, not stdout
        options.LogToStandardErrorThreshold = LogLevel.Trace;
    });
});

var logger = loggerFactory.CreateLogger<Program>();
```

### Verbosity Mapping

Map `--verbose`/`--quiet` flags to log levels:

```csharp
public static class VerbosityMapping
{
    public static LogLevel ToLogLevel(bool verbose, bool quiet) => (verbose, quiet) switch
    {
        (true, _) => LogLevel.Debug,
        (_, true) => LogLevel.Warning,
        _ => LogLevel.Information  // default
    };
}

// Apply verbosity from CLI flags
var verboseOption = new Option<bool>("--verbose", "Enable debug logging");
var quietOption = new Option<bool>("--quiet", "Suppress info logging");

syncCommand.SetAction(async (parseResult, ct) =>
{
    var verbose = parseResult.GetValue(verboseOption);
    var quiet = parseResult.GetValue(quietOption);
    var level = VerbosityMapping.ToLogLevel(verbose, quiet);

    using var loggerFactory = LoggerFactory.Create(logging =>
    {
        logging.SetMinimumLevel(level);
        logging.AddConsole(o => o.LogToStandardErrorThreshold = LogLevel.Trace);
    });
    // ...
});
```


## Exit Code Conventions

### Standard Exit Codes

```csharp
public static class ExitCodes
{
    public const int Success = 0;
    public const int GeneralError = 1;
    public const int InvalidUsage = 2;    // Bad arguments or options
    public const int IoError = 3;         // File not found, permission denied
    public const int NetworkError = 4;    // Connection failed, timeout
    public const int AuthError = 5;       // Authentication/authorization failure

    // Tool-specific codes start at 10+
    public const int SyncFailed = 10;
    public const int ValidationFailed = 11;
}
```

### Guidelines

- **0** = success (always)
- **1** = general/unspecified error
- **2** = invalid usage (bad arguments) -- System.CommandLine returns this for parse errors automatically
- **3-9** = reserved for common categories
- **10+** = tool-specific error codes
- Never use exit codes > 125 (reserved by shells; 126 = not executable, 127 = not found, 128+N = killed by signal N)

### Propagating Exit Codes

```csharp
syncCommand.SetAction(async (parseResult, ct) =>
{
    try
    {
        await service.ProcessAsync(ct);
        return ExitCodes.Success;
    }
    catch (HttpRequestException ex)
    {
        logger.LogError(ex, "Network error");
        Console.Error.WriteLine($"Error: {ex.Message}");
        return ExitCodes.NetworkError;
    }
    catch (UnauthorizedAccessException ex)
    {
        Console.Error.WriteLine($"Permission denied: {ex.Message}");
        return ExitCodes.IoError;
    }
});
```


## Stdin/Stdout/Stderr Patterns

### Reading from Stdin

Support piped input as an alternative to file arguments:

```csharp
var inputFileOption = new Option<FileInfo?>("--file", "Input file path");

processCommand.SetAction(async (parseResult, ct) =>
{
    var inputFile = parseResult.GetValue(inputFileOption);
    string input;

    if (inputFile is not null)
    {
        input = await File.ReadAllTextAsync(inputFile.FullName, ct);
    }
    else if (Console.IsInputRedirected)
    {
        // Read from stdin: echo '{"data":1}' | mycli process
        input = await Console.In.ReadToEndAsync();
    }
    else
    {
        Console.Error.WriteLine("Error: Provide input via --file or stdin.");
        return ExitCodes.InvalidUsage;
    }

    var result = processor.Process(input);
    Console.Out.WriteLine(JsonSerializer.Serialize(result));
    return ExitCodes.Success;
});
```

### Machine-Readable Output

```csharp
// Global --json option for machine-readable output
var jsonOption = new Option<bool>("--json", "Output as JSON");
rootCommand.Options.Add(jsonOption);

// In handler
if (useJson)
{
    Console.Out.WriteLine(JsonSerializer.Serialize(result, jsonContext.Options));
}
else
{
    // Human-friendly table format
    ConsoleFormatter.WriteTable(result, Console.Out);
}
```

### Progress to Stderr

```csharp
// Progress reporting goes to stderr (does not pollute piped stdout)
await foreach (var item in _service.StreamAsync(ct))
{
    Console.Error.Write($"\rProcessing {item.Index}/{total}...");
    Console.Out.WriteLine(item.ToJson());
}
Console.Error.WriteLine();  // Clear progress line
```


## Testing CLI Applications

### In-Process Invocation with Output Capture

Test the full CLI pipeline without spawning a child process. System.CommandLine 2.0 uses `InvocationConfiguration` for output capture:

```csharp
public class CliTestHarness
{
    private readonly RootCommand _rootCommand;

    public CliTestHarness()
    {
        _rootCommand = Program.BuildRootCommand();
    }

    public async Task<(int ExitCode, string Stdout, string Stderr)> InvokeAsync(
        string commandLine)
    {
        var stdoutWriter = new StringWriter();
        var stderrWriter = new StringWriter();

        var exitCode = await _rootCommand.InvokeAsync(
            commandLine,
            new InvocationConfiguration
            {
                Output = stdoutWriter,
                Error = stderrWriter
            });

        return (exitCode, stdoutWriter.ToString(), stderrWriter.ToString());
    }
}
```

### Testing with Service Mocks

Inject test doubles by building the root command with a factory that accepts service overrides:

```csharp
[Fact]
public async Task Sync_WithValidSource_ReturnsZero()
{
    var fakeSyncService = new FakeSyncService(
        new SyncResult(ItemCount: 5));

    // Build command with test service
    var rootCommand = Program.BuildRootCommand(syncService: fakeSyncService);
    var stdoutWriter = new StringWriter();

    var exitCode = await rootCommand.InvokeAsync(
        "sync --source https://api.example.com",
        new InvocationConfiguration { Output = stdoutWriter });

    Assert.Equal(0, exitCode);
    Assert.Contains("Synced 5 items", stdoutWriter.ToString());
}

[Fact]
public async Task Sync_WithMissingSource_ReturnsNonZero()
{
    var rootCommand = Program.BuildRootCommand();
    var stderrWriter = new StringWriter();

    var exitCode = await rootCommand.InvokeAsync(
        "sync",
        new InvocationConfiguration { Error = stderrWriter });

    Assert.NotEqual(0, exitCode);
    Assert.Contains("--source", stderrWriter.ToString());
}
```

### Exit Code Assertion

```csharp
[Theory]
[InlineData("sync --source https://valid.example.com", 0)]
[InlineData("sync", 2)]  // Missing required option
[InlineData("invalid-command", 1)]
public async Task ExitCode_MatchesExpected(string args, int expectedExitCode)
{
    var rootCommand = Program.BuildRootCommand();
    var exitCode = await rootCommand.InvokeAsync(args);
    Assert.Equal(expectedExitCode, exitCode);
}
```

### Testing Output Format

```csharp
[Fact]
public async Task List_WithJsonFlag_OutputsValidJson()
{
    var fakeRepo = new FakeItemRepository([new Item(1, "Widget")]);
    var rootCommand = Program.BuildRootCommand(itemRepository: fakeRepo);
    var stdoutWriter = new StringWriter();

    var exitCode = await rootCommand.InvokeAsync(
        "list --json",
        new InvocationConfiguration { Output = stdoutWriter });

    Assert.Equal(0, exitCode);
    var items = JsonSerializer.Deserialize<Item[]>(stdoutWriter.ToString());
    Assert.NotNull(items);
    Assert.Single(items);
}

[Fact]
public async Task List_StderrContainsLogs_StdoutContainsDataOnly()
{
    var rootCommand = Program.BuildRootCommand();
    var stdoutWriter = new StringWriter();
    var stderrWriter = new StringWriter();

    await rootCommand.InvokeAsync(
        "list --json --verbose",
        new InvocationConfiguration { Output = stdoutWriter, Error = stderrWriter });

    // Stdout must be valid JSON (no log noise)
    var doc = JsonDocument.Parse(stdoutWriter.ToString());
    Assert.NotNull(doc);

    // Stderr contains diagnostic output
    Assert.Contains("Connected to", stderrWriter.ToString());
}
```


## Agent Gotchas

1. **Do not write diagnostic output to stdout.** Logs, progress, and errors go to stderr. Stdout is reserved for data output that can be piped. A CLI tool that mixes logs into stdout breaks shell pipelines.
2. **Do not hardcode exit code 1 for all errors.** Use distinct exit codes for different failure categories (I/O, network, auth, validation). Callers and scripts rely on exit codes to determine what went wrong.
3. **Do not put business logic in command handlers.** Handlers should orchestrate calls to injected services and format output. Business logic in handlers cannot be reused or unit-tested independently.
4. **Do not test CLI tools only via process spawning.** Use in-process invocation with `RootCommand.InvokeAsync` and `InvocationConfiguration` for fast, reliable tests. Reserve process-level tests for smoke testing the published binary.
5. **Do not ignore `Console.IsInputRedirected` when accepting stdin.** Without checking, the tool may hang waiting for input when invoked without piped data.
6. **Do not use exit codes above 125.** Codes 126-255 have special meanings in Unix shells (126 = not executable, 127 = not found, 128+N = killed by signal N). Tool-specific codes should be in the 1-125 range.


## References

- [Command Line Interface Guidelines (clig.dev)](https://clig.dev/)
- [System.CommandLine overview](https://learn.microsoft.com/en-us/dotnet/standard/commandline/)
- [12 Factor CLI Apps](https://medium.com/@jdxcode/12-factor-cli-apps-dd3c227a0e46)
- [Generic Host in .NET](https://learn.microsoft.com/en-us/dotnet/core/extensions/generic-host)
- [Console logging in .NET](https://learn.microsoft.com/en-us/dotnet/core/extensions/console-log-formatter)
