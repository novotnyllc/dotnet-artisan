# Spectre.Console

Spectre.Console for building rich console output (tables, trees, progress bars, prompts, markup, live displays) and Spectre.Console.Cli for structured command-line application parsing. Cross-platform across Windows, macOS, and Linux terminals.

**Version assumptions:** .NET 8.0+ baseline. Spectre.Console 0.54.0 (latest stable). Spectre.Console.Cli 0.53.1 (latest stable). Both packages target net8.0+ and netstandard2.0.

## Package References

```xml
<ItemGroup>
  <!-- Rich console output: markup, tables, trees, progress, prompts, live displays -->
  <PackageReference Include="Spectre.Console" Version="0.54.0" />

  <!-- CLI command framework (adds command parsing, settings, DI support) -->
  <PackageReference Include="Spectre.Console.Cli" Version="0.53.1" />
</ItemGroup>
```

Spectre.Console.Cli has a dependency on Spectre.Console -- install both only when you need the CLI framework. For rich output only, Spectre.Console alone is sufficient.


## Markup and Styling

Spectre.Console uses a BBCode-inspired markup syntax for styled console output.

### Basic Markup

```csharp
using Spectre.Console;

// Styled text with markup tags
AnsiConsole.MarkupLine("[bold red]Error:[/] File not found.");
AnsiConsole.MarkupLine("[green]Success![/] Build completed in [blue]2.3s[/].");
AnsiConsole.MarkupLine("[underline]https://example.com[/]");
AnsiConsole.MarkupLine("[dim italic]This is subtle text[/]");

// Nested styles
AnsiConsole.MarkupLine("[bold [red on white]Warning:[/] check config[/]");

// Escape brackets with double brackets
AnsiConsole.MarkupLine("Use [[bold]] for bold text.");
```

### Figlet Text

```csharp
AnsiConsole.Write(
    new FigletText("Hello!")
        .Color(Color.Green)
        .Centered());
```

### Rule (Horizontal Line)

```csharp
// Simple rule
AnsiConsole.Write(new Rule());

// Titled rule
AnsiConsole.Write(new Rule("[yellow]Section Title[/]"));

// Aligned rule
AnsiConsole.Write(new Rule("[blue]Left Aligned[/]").LeftJustified());
```


## Tables

```csharp
var table = new Table();

// Add columns
table.AddColumn("Name");
table.AddColumn(new TableColumn("Age").Centered());
table.AddColumn(new TableColumn("City").RightAligned());

// Add rows
table.AddRow("Alice", "30", "Seattle");
table.AddRow("[green]Bob[/]", "25", "Portland");
table.AddRow("Charlie", "35", "Vancouver");

// Styling
table.Border(TableBorder.Rounded);
table.BorderColor(Color.Grey);
table.Title("[underline]Team Members[/]");
table.Caption("[dim]Updated daily[/]");

// Column configuration
table.Columns[0].PadLeft(2);
table.Columns[0].NoWrap();

AnsiConsole.Write(table);
```

### Nested Tables

```csharp
var innerTable = new Table()
    .AddColumn("Detail")
    .AddColumn("Value")
    .AddRow("Role", "Developer")
    .AddRow("Level", "Senior");

var outerTable = new Table()
    .AddColumn("Name")
    .AddColumn("Info")
    .AddRow("Alice", innerTable);

AnsiConsole.Write(outerTable);
```


## Trees

```csharp
var tree = new Tree("Solution");

// Add nodes
var srcNode = tree.AddNode("[yellow]src[/]");
var apiNode = srcNode.AddNode("Api");
apiNode.AddNode("Controllers/");
apiNode.AddNode("Program.cs");

var libNode = srcNode.AddNode("Library");
libNode.AddNode("Services/");

var testNode = tree.AddNode("[blue]tests[/]");
testNode.AddNode("Api.Tests/");

// Styling
tree.Style = Style.Parse("dim");

AnsiConsole.Write(tree);
```


## Panels

```csharp
var panel = new Panel("This is [green]important[/] content.")
    .Header("[bold]Notice[/]")
    .Border(BoxBorder.Rounded)
    .BorderColor(Color.Blue)
    .Padding(2, 1)    // horizontal, vertical
    .Expand();         // fill available width

AnsiConsole.Write(panel);
```

### Composing Renderables with Columns

```csharp
AnsiConsole.Write(new Columns(
    new Panel("Left panel").Expand(),
    new Panel("Right panel").Expand()));
```


## Progress Displays

### Progress Bars

```csharp
await AnsiConsole.Progress()
    .AutoClear(false)       // keep completed tasks visible
    .HideCompleted(false)
    .Columns(
        new TaskDescriptionColumn(),
        new ProgressBarColumn(),
        new PercentageColumn(),
        new RemainingTimeColumn(),
        new SpinnerColumn())
    .StartAsync(async ctx =>
    {
        var downloadTask = ctx.AddTask("[green]Downloading[/]", maxValue: 100);
        var extractTask = ctx.AddTask("[blue]Extracting[/]", maxValue: 100);

        while (!ctx.IsFinished)
        {
            await Task.Delay(50);
            downloadTask.Increment(1.5);

            if (downloadTask.Value > 50)
            {
                extractTask.Increment(0.8);
            }
        }
    });
```

### Status Spinners

```csharp
await AnsiConsole.Status()
    .Spinner(Spinner.Known.Dots)
    .SpinnerStyle(Style.Parse("green bold"))
    .StartAsync("Processing...", async ctx =>
    {
        await Task.Delay(1000);
        ctx.Status("Compiling...");
        ctx.Spinner(Spinner.Known.Star);
        await Task.Delay(1000);
        ctx.Status("Publishing...");
        await Task.Delay(1000);
    });
```


## Prompts

### Text Prompt

```csharp
// Simple typed input
var name = AnsiConsole.Ask<string>("What's your [green]name[/]?");
var age = AnsiConsole.Ask<int>("What's your [green]age[/]?");

// With default value
var city = AnsiConsole.Prompt(
    new TextPrompt<string>("Enter [green]city[/]:")
        .DefaultValue("Seattle")
        .ShowDefaultValue());

// Secret input (password)
var password = AnsiConsole.Prompt(
    new TextPrompt<string>("Enter [green]password[/]:")
        .Secret());

// With validation
var email = AnsiConsole.Prompt(
    new TextPrompt<string>("Enter [green]email[/]:")
        .Validate(input =>
            input.Contains('@') && input.Contains('.')
                ? ValidationResult.Success()
                : ValidationResult.Error("[red]Invalid email address[/]")));

// Optional (allow empty)
var nickname = AnsiConsole.Prompt(
    new TextPrompt<string>("Enter [green]nickname[/] (optional):")
        .AllowEmpty());
```

### Confirmation Prompt

```csharp
bool proceed = AnsiConsole.Confirm("Continue with deployment?");
```

### Selection Prompt

```csharp
var fruit = AnsiConsole.Prompt(
    new SelectionPrompt<string>()
        .Title("Pick a [green]fruit[/]:")
        .PageSize(10)
        .EnableSearch()
        .WrapAround()
        .AddChoices("Apple", "Banana", "Orange", "Mango", "Grape"));

// Grouped choices
var country = AnsiConsole.Prompt(
    new SelectionPrompt<string>()
        .Title("Select [green]destination[/]:")
        .AddChoiceGroup("Europe", "France", "Italy", "Spain")
        .AddChoiceGroup("Asia", "Japan", "Thailand", "Vietnam"));
```

### Multi-Selection Prompt

```csharp
var toppings = AnsiConsole.Prompt(
    new MultiSelectionPrompt<string>()
        .Title("Choose [green]toppings[/]:")
        .PageSize(10)
        .Required()
        .InstructionsText("[grey](Press [blue]<space>[/] to toggle, [green]<enter>[/] to accept)[/]")
        .AddChoices("Cheese", "Pepperoni", "Mushrooms", "Olives", "Onions"));
```


## Live Displays

Live displays update in-place for dynamic content that changes over time.

```csharp
var table = new Table()
    .AddColumn("Time")
    .AddColumn("Status");

await AnsiConsole.Live(table)
    .AutoClear(false)
    .Overflow(VerticalOverflow.Ellipsis)
    .Cropping(VerticalOverflowCropping.Bottom)
    .StartAsync(async ctx =>
    {
        table.AddRow(DateTime.Now.ToString("T"), "[yellow]Starting...[/]");
        ctx.Refresh();
        await Task.Delay(1000);

        table.AddRow(DateTime.Now.ToString("T"), "[green]Processing...[/]");
        ctx.Refresh();
        await Task.Delay(1000);

        table.AddRow(DateTime.Now.ToString("T"), "[blue]Complete![/]");
        ctx.Refresh();
    });
```

### Replacing the Target

```csharp
await AnsiConsole.Live(new Markup("[yellow]Initializing...[/]"))
    .StartAsync(async ctx =>
    {
        await Task.Delay(1000);
        ctx.UpdateTarget(new Markup("[green]Ready![/]"));
        await Task.Delay(1000);
        ctx.UpdateTarget(
            new Panel("Final result: [bold]42[/]")
                .Header("Done")
                .Border(BoxBorder.Rounded));
    });
```


## Spectre.Console.Cli Framework

Spectre.Console.Cli provides a structured command-line parsing framework with command hierarchies, typed settings, validation, and automatic help generation.

### Basic Command App

```csharp
using Spectre.Console.Cli;

var app = new CommandApp<GreetCommand>();
return app.Run(args);

// Command with typed settings
public sealed class GreetSettings : CommandSettings
{
    [CommandArgument(0, "<name>")]
    [Description("The person to greet")]
    public string Name { get; init; } = string.Empty;

    [CommandOption("-c|--count")]
    [Description("Number of times to greet")]
    [DefaultValue(1)]
    public int Count { get; init; }

    [CommandOption("--shout")]
    [Description("Greet in uppercase")]
    public bool Shout { get; init; }
}

public sealed class GreetCommand : Command<GreetSettings>
{
    public override int Execute(CommandContext context, GreetSettings settings)
    {
        for (int i = 0; i < settings.Count; i++)
        {
            var greeting = $"Hello, {settings.Name}!";
            AnsiConsole.MarkupLine(settings.Shout
                ? $"[bold]{greeting.ToUpperInvariant()}[/]"
                : greeting);
        }
        return 0;  // exit code
    }
}
```

### Command Hierarchy with Branches

```csharp
var app = new CommandApp();
app.Configure(config =>
{
    config.AddBranch<RemoteSettings>("remote", remote =>
    {
        remote.AddCommand<RemoteAddCommand>("add")
            .WithDescription("Add a remote");
        remote.AddCommand<RemoteRemoveCommand>("remove")
            .WithDescription("Remove a remote");
    });

    config.AddCommand<CloneCommand>("clone")
        .WithDescription("Clone a repository");
});

return app.Run(args);

// Shared settings for the branch -- inherited by subcommands
public class RemoteSettings : CommandSettings
{
    [CommandOption("-v|--verbose")]
    [Description("Verbose output")]
    public bool Verbose { get; init; }
}

// Subcommand settings inherit from branch settings
public sealed class RemoteAddSettings : RemoteSettings
{
    [CommandArgument(0, "<name>")]
    public string Name { get; init; } = string.Empty;

    [CommandArgument(1, "<url>")]
    public string Url { get; init; } = string.Empty;
}

public sealed class RemoteAddCommand : Command<RemoteAddSettings>
{
    public override int Execute(CommandContext context, RemoteAddSettings settings)
    {
        if (settings.Verbose)
        {
            AnsiConsole.MarkupLine($"[dim]Adding remote...[/]");
        }
        AnsiConsole.MarkupLine($"Added remote [green]{settings.Name}[/] -> {settings.Url}");
        return 0;
    }
}
```

### Settings Validation

```csharp
public sealed class DeploySettings : CommandSettings
{
    [CommandArgument(0, "<environment>")]
    public string Environment { get; init; } = string.Empty;

    [CommandOption("--timeout")]
    [DefaultValue(30)]
    public int TimeoutSeconds { get; init; }

    public override ValidationResult Validate()
    {
        var validEnvs = new[] { "dev", "staging", "prod" };
        if (!validEnvs.Contains(Environment, StringComparer.OrdinalIgnoreCase))
        {
            return ValidationResult.Error(
                $"Environment must be one of: {string.Join(", ", validEnvs)}");
        }

        if (TimeoutSeconds <= 0)
        {
            return ValidationResult.Error("Timeout must be positive");
        }

        return ValidationResult.Success();
    }
}
```

### Async Commands

```csharp
public sealed class FetchCommand : AsyncCommand<FetchSettings>
{
    public override async Task<int> ExecuteAsync(
        CommandContext context, FetchSettings settings)
    {
        await AnsiConsole.Status()
            .StartAsync("Fetching data...", async ctx =>
            {
                await Task.Delay(2000); // simulate work
            });

        AnsiConsole.MarkupLine("[green]Done![/]");
        return 0;
    }
}
```

### Dependency Injection with ITypeRegistrar

```csharp
using Microsoft.Extensions.DependencyInjection;
using Spectre.Console.Cli;

// Set up DI container
var services = new ServiceCollection();
services.AddSingleton<IGreetingService, GreetingService>();
services.AddSingleton<IAnsiConsole>(AnsiConsole.Console);

var registrar = new TypeRegistrar(services);
var app = new CommandApp<GreetCommand>(registrar);
return app.Run(args);

// TypeRegistrar bridges Microsoft DI to Spectre.Console.Cli
public sealed class TypeRegistrar(IServiceCollection services) : ITypeRegistrar
{
    public ITypeResolver Build() => new TypeResolver(services.BuildServiceProvider());

    public void Register(Type service, Type implementation)
        => services.AddSingleton(service, implementation);

    public void RegisterInstance(Type service, object implementation)
        => services.AddSingleton(service, implementation);

    public void RegisterLazy(Type service, Func<object> factory)
        => services.AddSingleton(service, _ => factory());
}

public sealed class TypeResolver(IServiceProvider provider) : ITypeResolver
{
    public object? Resolve(Type? type)
        => type is null ? null : provider.GetService(type);
}

// Command receives services via constructor injection
public sealed class GreetCommand(IGreetingService greetingService) : Command<GreetSettings>
{
    public override int Execute(CommandContext context, GreetSettings settings)
    {
        var message = greetingService.GetGreeting(settings.Name);
        AnsiConsole.MarkupLine(message);
        return 0;
    }
}
```


## Testable Console Output

Spectre.Console provides `IAnsiConsole` for testable output instead of writing directly to the real console.

```csharp
// Production: use AnsiConsole.Console (the real console)
IAnsiConsole console = AnsiConsole.Console;

// Testing: use a recording console
var console = AnsiConsole.Create(new AnsiConsoleSettings
{
    Out = new AnsiConsoleOutput(new StringWriter())
});

// Use the abstraction instead of static AnsiConsole methods
console.MarkupLine("[green]Testable output[/]");
console.Write(new Table().AddColumn("Col").AddRow("Val"));
```


## Agent Gotchas

1. **Do not use `AnsiConsole.Markup*` in redirected output.** When stdout is redirected (piped to a file or another process), ANSI escape codes corrupt the output. Check `AnsiConsole.Profile.Capabilities.Ansi` before using markup, or use `IAnsiConsole` with appropriate settings. See [skill:dotnet-csharp] for async pipeline patterns.
2. **Do not assume ANSI support in CI environments.** CI runners (GitHub Actions, Azure Pipelines) may not support ANSI escape codes. Set `TERM=dumb` or use `AnsiConsole.Create()` with `ColorSystemSupport.NoColors` for CI-safe output. Spectre.Console auto-detects capabilities, but explicit configuration prevents flaky rendering.
3. **Do not mix `AnsiConsole` static calls with `IAnsiConsole` instance calls.** Static `AnsiConsole.Write()` always targets the real console. When using DI with `IAnsiConsole`, consistently use the injected instance. Mixing the two produces duplicated or interleaved output.
4. **Do not modify a renderable from a background thread during `Live()`.** Live displays are not thread-safe. Mutate the target renderable only inside the `Start`/`StartAsync` callback, then call `ctx.Refresh()`. Concurrent mutations cause corrupted terminal output.
5. **Do not use prompts in non-interactive contexts.** `TextPrompt`, `SelectionPrompt`, and `ConfirmationPrompt` block waiting for user input. In CI or automated scripts, use environment variables or command-line arguments for input instead of prompts. Check `AnsiConsole.Profile.Capabilities.Interactive` before prompting.
6. **Do not confuse Spectre.Console.Cli with System.CommandLine.** They are independent frameworks with different APIs. Spectre.Console.Cli uses `CommandSettings` classes with `[CommandArgument]`/`[CommandOption]` attributes, while System.CommandLine uses `Option<T>` and `Argument<T>` builder pattern. Do not mix APIs. For System.CommandLine, see `references/system-commandline.md`.
7. **Do not forget `ctx.Refresh()` after modifying live display content.** Changes to tables, trees, or panels inside a `Live()` callback are not rendered until `ctx.Refresh()` is called. Omitting it produces stale displays.
8. **Do not hardcode color values without fallback.** Terminals with limited color support silently degrade TrueColor values. Use named colors (`Color.Green`) when possible and test with `NO_COLOR=1` environment variable to verify graceful degradation.


## Prerequisites

- **NuGet packages:** `Spectre.Console` 0.54.0 for rich output; add `Spectre.Console.Cli` 0.53.1 for CLI framework
- **Target framework:** net8.0 or later (also supports netstandard2.0)
- **Terminal:** Any terminal emulator supporting ANSI escape sequences. Windows Terminal, iTerm2, or modern Linux terminal recommended for best experience (TrueColor, Unicode). Console output degrades gracefully on limited terminals.
- **For DI with Spectre.Console.Cli:** `Microsoft.Extensions.DependencyInjection` package for the `ITypeRegistrar`/`ITypeResolver` bridge


## References

- [Spectre.Console GitHub](https://github.com/spectreconsole/spectre.console) -- source code, issues, samples
- [Spectre.Console Documentation](https://spectreconsole.net/) -- official guides and API reference
- [Spectre.Console NuGet](https://www.nuget.org/packages/Spectre.Console) -- package downloads and version history
- [Spectre.Console.Cli NuGet](https://www.nuget.org/packages/Spectre.Console.Cli) -- CLI framework package
- [Spectre.Console Examples](https://github.com/spectreconsole/spectre.console/tree/main/examples) -- official example projects
