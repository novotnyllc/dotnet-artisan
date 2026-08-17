# MSBuild Tasks

Guidance for authoring custom MSBuild tasks: implementing the `ITask` interface, extending `ToolTask` for CLI wrappers, using `IIncrementalTask` (MSBuild 17.8+) for incremental execution, defining inline tasks with `CodeTaskFactory`, registering tasks via `UsingTask`, declaring task parameters, debugging tasks, and packaging tasks as NuGet packages.

**Version assumptions:** .NET 8.0+ SDK (MSBuild 17.8+). `IIncrementalTask` requires MSBuild 17.8+ (VS 2022 17.8+, .NET 8 SDK). All examples use SDK-style projects. All C# examples assume `using Microsoft.Build.Framework;` and `using Microsoft.Build.Utilities;` are in scope unless shown explicitly.

## ITask Interface

All MSBuild tasks implement `Microsoft.Build.Framework.ITask`. The simplest approach is to inherit from `Microsoft.Build.Utilities.Task`, which provides default implementations for `BuildEngine` and `HostObject`.

### Minimal Custom Task

```csharp
using Microsoft.Build.Framework;
using Microsoft.Build.Utilities;

public class GenerateFileHash : Task
{
    [Required]
    public string InputFile { get; set; } = string.Empty;

    [Output]
    public string Hash { get; set; } = string.Empty;

    public override bool Execute()
    {
        if (!File.Exists(InputFile))
        {
            Log.LogError("Input file not found: {0}", InputFile);
            return false;
        }

        using var stream = File.OpenRead(InputFile);
        var bytes = System.Security.Cryptography.SHA256.HashData(stream);
        Hash = Convert.ToHexString(bytes).ToLowerInvariant();

        Log.LogMessage(MessageImportance.Normal,
            "SHA-256 hash for {0}: {1}", InputFile, Hash);
        return true;
    }
}
```

### ITask Contract

| Member | Purpose |
|---|---|
| `BuildEngine` | Provides logging, error reporting, and build context |
| `HostObject` | Host-specific data (rarely used) |
| `Execute()` | Runs the task. Return `true` for success, `false` for failure |

The `Task` base class exposes a `Log` property (`TaskLoggingHelper`) with convenience methods:

| Method | When to use |
|---|---|
| `Log.LogMessage(importance, msg)` | Informational output (Normal, High, Low) |
| `Log.LogWarning(msg)` | Non-fatal issues |
| `Log.LogError(msg)` | Fatal errors (causes build failure) |
| `Log.LogWarningFromException(ex)` | Warning from caught exception |
| `Log.LogErrorFromException(ex)` | Error from caught exception |


For detailed code examples (ToolTask, IIncrementalTask, task parameters, inline tasks, UsingTask, debugging, NuGet packaging), see the Detailed Examples section below.

## Agent Gotchas

1. **Returning `false` without logging an error.** If `Execute()` returns `false` but `Log.LogError` was never called, MSBuild reports a generic "task failed" with no actionable message. Always log an error before returning `false`.

2. **Using `Console.WriteLine` instead of `Log.LogMessage`.** Console output bypasses MSBuild's logging infrastructure and may not appear in build logs, binary logs, or IDE error lists. Always use `Log.LogMessage`, `Log.LogWarning`, or `Log.LogError`.

3. **Referencing `IIncrementalTask` without version-gating.** This interface requires MSBuild 17.8+ (.NET 8 SDK). Tasks referencing it will fail to load on older MSBuild versions with a `TypeLoadException`. If supporting older SDKs, use target-level `Inputs`/`Outputs` instead. If the task must support both old and new MSBuild, ship separate task assemblies per MSBuild version range or use `#if` conditional compilation with a version constant.

4. **Placing task DLLs in the NuGet `lib/` folder.** This adds the assembly as a compile reference to consuming projects, polluting their type namespace. Set `IncludeBuildOutput=false` and pack into `tools/` instead.

5. **Forgetting `PrivateAssets="all"` on MSBuild framework package references.** Without it, `Microsoft.Build.Framework` and `Microsoft.Build.Utilities.Core` become transitive dependencies of consuming projects, causing version conflicts.

6. **Using `AssemblyFile` with a path relative to the project.** In NuGet packages, the `.targets` file is in a different location than the consuming project. Use `$(MSBuildThisFileDirectory)` to build paths relative to the `.targets` file itself.

7. **Leaving `Debugger.Launch()` in release builds.** Shipping a task with unconditional `Debugger.Launch()` halts builds on CI/CD servers. Guard with `#if DEBUG` or remove before packaging.

8. **Inline tasks with complex dependencies.** `CodeTaskFactory` compiles code at build time with limited assembly references. For tasks that need NuGet packages or complex type hierarchies, compile a standalone task assembly instead.


## References

- [MSBuild Task Writing](https://learn.microsoft.com/en-us/visualstudio/msbuild/task-writing)
- [MSBuild Task Reference](https://learn.microsoft.com/en-us/visualstudio/msbuild/msbuild-task-reference)
- [ToolTask Class](https://learn.microsoft.com/en-us/dotnet/api/microsoft.build.utilities.tooltask)
- [MSBuild Inline Tasks](https://learn.microsoft.com/en-us/visualstudio/msbuild/msbuild-inline-tasks)
- [UsingTask Element](https://learn.microsoft.com/en-us/visualstudio/msbuild/usingtask-element-msbuild)
- [MSBuild Task Parameters](https://learn.microsoft.com/en-us/visualstudio/msbuild/task-writing#task-parameters)
- [Creating a NuGet Package with MSBuild Tasks](https://learn.microsoft.com/en-us/nuget/create-packages/creating-a-package-msbuild)
- [Debugging MSBuild Tasks](https://learn.microsoft.com/en-us/visualstudio/msbuild/how-to-debug-msbuild-custom-task)

---

# MSBuild Tasks -- Detailed Examples

Extended code examples for ToolTask, IIncrementalTask, task parameters, inline tasks, UsingTask registration, debugging, and NuGet packaging.

---

## ToolTask Base Class

`ToolTask` extends `Task` for wrapping external command-line tools. It handles process invocation, output capture, and exit code interpretation.

```csharp
using Microsoft.Build.Framework;
using Microsoft.Build.Utilities;

public class RunLintTool : ToolTask
{
    [Required]
    public string SourceDirectory { get; set; } = string.Empty;

    public string Severity { get; set; } = "warning";

    // Required: name of the executable
    protected override string ToolName => "dotnet-lint";

    // Required: full path or tool name (OS resolves via PATH)
    protected override string GenerateFullPathToTool()
    {
        // Return tool name; the OS resolves it via PATH at process start
        return ToolName;
    }

    // Required: build the command-line arguments
    protected override string GenerateCommandLineCommands()
    {
        var builder = new CommandLineBuilder();
        builder.AppendSwitch("--check");
        builder.AppendSwitchIfNotNull("--severity ", Severity);
        builder.AppendFileNameIfNotNull(SourceDirectory);
        return builder.ToString();
    }

    // Optional: interpret non-zero exit codes
    protected override bool HandleTaskExecutionErrors()
    {
        Log.LogError("{0} found lint violations in {1}",
            ToolName, SourceDirectory);
        return false;
    }
}
```

### Key ToolTask Overrides

| Override | Purpose |
|---|---|
| `ToolName` | Executable file name (e.g., `dotnet-lint`) |
| `GenerateFullPathToTool()` | Full path to executable, or return `ToolName` to let the OS resolve via `PATH` |
| `GenerateCommandLineCommands()` | Build argument string for the tool |
| `GenerateResponseFileCommands()` | Arguments written to a response file (for long command lines) |
| `HandleTaskExecutionErrors()` | Custom handling of non-zero exit codes |
| `StandardOutputLoggingImportance` | Log level for stdout (default: `Low`) |
| `StandardErrorLoggingImportance` | Log level for stderr (default: `Normal`) |

### Response Files for Long Command Lines

When the argument list is too long for the OS command line (common with many source files), use `GenerateResponseFileCommands()` to write arguments to a temporary response file:

```csharp
protected override string GenerateResponseFileCommands()
{
    var builder = new CommandLineBuilder();
    // These arguments go into a @response.rsp file
    foreach (var source in SourceFiles)
    {
        builder.AppendFileNameIfNotNull(source.ItemSpec);
    }
    return builder.ToString();
}

protected override string GenerateCommandLineCommands()
{
    // These arguments stay on the command line (before the @file ref)
    var builder = new CommandLineBuilder();
    builder.AppendSwitchIfNotNull("--config ", ConfigFile);
    return builder.ToString();
}
```

MSBuild creates the response file, passes `@responsefile.rsp` to the tool, and cleans up afterward. The tool must support `@file` syntax (most .NET tools do).

**When to use ToolTask vs Task:** Use `ToolTask` when wrapping an external CLI tool. Use `Task` (ITask) when the logic is pure .NET code with no external process.

---

## IIncrementalTask

`Microsoft.Build.Framework.IIncrementalTask` (MSBuild 17.8+, VS 2022 17.8+, .NET 8 SDK) signals to the MSBuild engine that a task supports receiving pre-filtered inputs. When a target declares `Inputs`/`Outputs` and the engine determines which inputs have changed, it passes only the changed items to an `IIncrementalTask`-implementing task instead of the full item list.

### Version Gate

`IIncrementalTask` requires:
- MSBuild 17.8+ (ships with VS 2022 17.8+)
- .NET 8.0 SDK or later

Tasks targeting older MSBuild versions must not reference this interface. Use target-level `Inputs`/`Outputs` for incrementality on older versions. See `references/msbuild-authoring.md` for target-level incremental patterns.

### How It Works

1. The target declares `Inputs` and `Outputs` (required -- the engine uses these for change detection).
2. MSBuild compares timestamps and determines which inputs are out of date.
3. If the task implements `IIncrementalTask`, MSBuild passes only the changed items to the task's `ITaskItem[]` parameters instead of the full set.
4. The task processes only those items -- no manual timestamp logic needed.

The `FailIfIncrementalBuildIsNotPossible` property controls fallback behavior:
- `false` (default): If the engine cannot determine changed inputs (e.g., missing `Outputs`), it falls back to passing all inputs. The task runs in full-rebuild mode.
- `true`: If the engine cannot provide incremental inputs, the task logs an error and fails. Use this when full rebuilds are unacceptably slow.

### Implementation

```csharp
using Microsoft.Build.Framework;
using Microsoft.Build.Utilities;

public class TransformTemplates : Task, IIncrementalTask
{
    [Required]
    public ITaskItem[] Templates { get; set; } = [];

    [Output]
    public ITaskItem[] GeneratedFiles { get; set; } = [];

    // IIncrementalTask: if true, the task errors when the engine
    // cannot provide filtered inputs (falls back to full set if false)
    public bool FailIfIncrementalBuildIsNotPossible { get; set; }

    public override bool Execute()
    {
        // Templates contains ONLY changed items (filtered by engine)
        // when the target has Inputs/Outputs and incremental build is possible
        var outputs = new List<ITaskItem>();

        foreach (var template in Templates)
        {
            var inputPath = template.GetMetadata("FullPath");
            var outputPath = Path.ChangeExtension(inputPath, ".g.cs");

            var content = ProcessTemplate(File.ReadAllText(inputPath));
            File.WriteAllText(outputPath, content);

            Log.LogMessage(MessageImportance.Normal,
                "Transformed: {0} -> {1}", inputPath, outputPath);
            outputs.Add(new TaskItem(outputPath));
        }

        GeneratedFiles = outputs.ToArray();
        return true;
    }

    private static string ProcessTemplate(string input)
    {
        // Template transformation logic
        return $"// Auto-generated\n{input}";
    }
}
```

```xml
<!-- Target MUST declare Inputs/Outputs for engine-level change detection -->
<Target Name="TransformAllTemplates"
        BeforeTargets="CoreCompile"
        Inputs="@(Template)"
        Outputs="@(Template->'%(RootDir)%(Directory)%(Filename).g.cs')">
  <TransformTemplates Templates="@(Template)">
    <Output TaskParameter="GeneratedFiles" ItemName="Compile" />
  </TransformTemplates>
</Target>
```

**IIncrementalTask vs target-level Inputs/Outputs alone:** Without `IIncrementalTask`, target-level incrementality is all-or-nothing: if any input changed, the entire target re-runs with all items. With `IIncrementalTask`, the engine pre-filters the item list so the task receives only changed items, which is faster for targets that process large collections of files.

---

## Task Parameters

Task parameters are public properties on the task class. MSBuild maps XML attributes to these properties automatically.

### Parameter Attributes

| Attribute | Effect |
|---|---|
| `[Required]` | Build fails if the parameter is not provided |
| `[Output]` | Value is available to subsequent tasks/targets via `%(TaskName.PropertyName)` |
| No attribute | Optional parameter with default value |

### Parameter Types

| .NET Type | MSBuild XML | Example |
|---|---|---|
| `string` | Scalar value | `InputFile="src/app.cs"` |
| `bool` | `true`/`false` | `Verbose="true"` |
| `int` | Numeric value | `MaxRetries="3"` |
| `string[]` | Semicolon-separated | `Assemblies="a.dll;b.dll"` |
| `ITaskItem` | Single item | `SourceFile="@(MainSource)"` |
| `ITaskItem[]` | Item collection | `SourceFiles="@(Compile)"` |

### ITaskItem Metadata Access

`ITaskItem` carries rich metadata beyond the file path:

```csharp
public class ProcessAssets : Task
{
    [Required]
    public ITaskItem[] Assets { get; set; } = [];

    [Output]
    public ITaskItem[] ProcessedAssets { get; set; } = [];

    public override bool Execute()
    {
        var results = new List<ITaskItem>();

        foreach (var asset in Assets)
        {
            // ItemSpec = the Include value (relative path)
            var relativePath = asset.ItemSpec;

            // Built-in metadata
            var fullPath = asset.GetMetadata("FullPath");
            var filename = asset.GetMetadata("Filename");
            var extension = asset.GetMetadata("Extension");

            // Custom metadata set in MSBuild XML
            var category = asset.GetMetadata("Category");

            Log.LogMessage(MessageImportance.Normal,
                "Processing {0} (category: {1})", filename, category);

            var output = new TaskItem(
                Path.ChangeExtension(fullPath, ".processed" + extension));
            // Copy all metadata from input to output
            asset.CopyMetadataTo(output);
            // Add new metadata
            output.SetMetadata("ProcessedAt",
                DateTime.UtcNow.ToString("o"));

            results.Add(output);
        }

        ProcessedAssets = results.ToArray();
        return true;
    }
}
```

```xml
<!-- MSBuild usage -->
<ItemGroup>
  <GameAsset Include="textures/*.png">
    <Category>texture</Category>
  </GameAsset>
  <GameAsset Include="models/*.fbx">
    <Category>model</Category>
  </GameAsset>
</ItemGroup>

<Target Name="ProcessGameAssets" BeforeTargets="Build">
  <ProcessAssets Assets="@(GameAsset)">
    <Output TaskParameter="ProcessedAssets" ItemName="ProcessedGameAsset" />
  </ProcessAssets>
</Target>
```

---

## Inline Tasks (CodeTaskFactory)

For simple tasks that do not warrant a separate assembly, use `CodeTaskFactory` to define task logic inline in MSBuild XML. The code is compiled at build time.

```xml
<UsingTask TaskName="GetTimestamp"
           TaskFactory="CodeTaskFactory"
           AssemblyFile="$(MSBuildToolsPath)\Microsoft.Build.Tasks.Core.dll">
  <ParameterGroup>
    <Format ParameterType="System.String" Required="false" />
    <Timestamp ParameterType="System.String" Output="true" />
  </ParameterGroup>
  <Task>
    <Code Type="Fragment" Language="cs">
      <![CDATA[
        var format = string.IsNullOrEmpty(Format) ? "yyyyMMdd-HHmmss" : Format;
        Timestamp = DateTime.UtcNow.ToString(format);
      ]]>
    </Code>
  </Task>
</UsingTask>

<!-- Usage -->
<Target Name="StampBuild" BeforeTargets="CoreCompile">
  <GetTimestamp Format="yyyy.MMdd.HHmm">
    <Output TaskParameter="Timestamp" PropertyName="BuildTimestamp" />
  </GetTimestamp>
  <Message Importance="high" Text="Build timestamp: $(BuildTimestamp)" />
</Target>
```

### CodeTaskFactory Code Types

| `Type` | Description |
|---|---|
| `Fragment` | Code runs inside the `Execute()` method body. Access parameters as local variables. |
| `Method` | Code is a complete method body. Must include `return true;` or `return false;`. |
| `Class` | Code is a full class. Must implement `ITask` or inherit from `Task`. |

### Adding Assembly References

```xml
<UsingTask TaskName="ValidateJson"
           TaskFactory="CodeTaskFactory"
           AssemblyFile="$(MSBuildToolsPath)\Microsoft.Build.Tasks.Core.dll">
  <ParameterGroup>
    <JsonFile ParameterType="System.String" Required="true" />
    <IsValid ParameterType="System.Boolean" Output="true" />
  </ParameterGroup>
  <Task>
    <Reference Include="System.Text.Json" />
    <Code Type="Fragment" Language="cs">
      <![CDATA[
        try
        {
            var content = System.IO.File.ReadAllText(JsonFile);
            System.Text.Json.JsonDocument.Parse(content);
            IsValid = true;
        }
        catch (System.Text.Json.JsonException)
        {
            IsValid = false;
            Log.LogWarning("Invalid JSON: {0}", JsonFile);
        }
      ]]>
    </Code>
  </Task>
</UsingTask>
```

**When to use inline tasks vs compiled tasks:** Inline tasks are best for simple, self-contained logic (timestamps, file checks, string manipulation). For complex logic, multiple dependencies, or reuse across projects, compile a task assembly and distribute via NuGet.

---

## UsingTask Registration

`UsingTask` tells MSBuild where to find a custom task implementation. It must appear before any target that uses the task.

### From a Compiled Assembly

```xml
<!-- Register a task from a specific DLL -->
<UsingTask TaskName="MyCompany.Build.GenerateFileHash"
           AssemblyFile="$(MSBuildThisFileDirectory)..\tools\MyCompany.Build.Tasks.dll" />

<!-- Register using assembly name (GAC or resolved via AssemblySearchPaths) -->
<UsingTask TaskName="MyCompany.Build.GenerateFileHash"
           AssemblyName="MyCompany.Build.Tasks, Version=1.0.0.0, Culture=neutral" />
```

### Task Name Resolution

| Attribute | Value | Effect |
|---|---|---|
| `TaskName` | `GenerateFileHash` | Short name; first match wins |
| `TaskName` | `MyCompany.Build.GenerateFileHash` | Fully qualified; exact match |
| `AssemblyFile` | Relative or absolute path | Load from file path |
| `AssemblyName` | Strong name or simple name | Load by assembly identity |

**Use `AssemblyFile` with `$(MSBuildThisFileDirectory)`** for tasks distributed via NuGet packages. The path resolves relative to the `.targets` file, not the consuming project.

### Conditional Registration

```xml
<!-- Only register task when the assembly exists (e.g., optional tooling) -->
<UsingTask TaskName="MyCompany.Build.CodeGen"
           AssemblyFile="$(MSBuildThisFileDirectory)..\tools\MyCompany.Build.Tasks.dll"
           Condition="Exists('$(MSBuildThisFileDirectory)..\tools\MyCompany.Build.Tasks.dll')" />
```

---

## Task Debugging

Debugging custom MSBuild tasks requires attaching a debugger to the MSBuild process.

### MSBUILDDEBUGONSTART

Set the `MSBUILDDEBUGONSTART` environment variable before running the build:

| Value | Behavior |
|---|---|
| `1` | MSBuild calls `Debugger.Launch()` at startup -- shows the JIT debugger attach dialog |
| `2` | MSBuild waits for a debugger to attach (prints PID to console), then continues |

```bash
# Option 1: Launch debugger dialog (Windows)
set MSBUILDDEBUGONSTART=1
dotnet build

# Option 2: Wait for debugger attach (cross-platform)
export MSBUILDDEBUGONSTART=2
dotnet build
# MSBuild prints: "Waiting for debugger to attach (PID: 12345)..."
# Attach from VS or VS Code, then execution continues
```

### Debugging Workflow

1. Set `MSBUILDDEBUGONSTART=2` in the terminal.
2. Run `dotnet build` on the project that uses the custom task.
3. MSBuild pauses and prints the process ID.
4. Attach your debugger (Visual Studio: Debug > Attach to Process; VS Code: .NET Attach).
5. Set breakpoints in the task's `Execute()` method.
6. Continue execution -- the debugger hits your breakpoints.

### Programmatic Debugger Launch

For development builds, add a conditional debugger launch inside the task:

```csharp
public override bool Execute()
{
#if DEBUG
    if (!System.Diagnostics.Debugger.IsAttached)
    {
        System.Diagnostics.Debugger.Launch();
    }
#endif
    // Task logic ...
    return true;
}
```

**Remove or guard debugger launches before publishing.** Ship only Release builds of task assemblies. The `#if DEBUG` guard ensures no debugger prompts in production.

---

## Task NuGet Packaging

Custom MSBuild tasks are typically distributed as NuGet packages. The package must place `.props`/`.targets` files and task assemblies in the correct folders.

### Package Layout

```
MyCompany.Build.Tasks.nupkg
  build/
    MyCompany.Build.Tasks.props       (optional: set defaults)
    MyCompany.Build.Tasks.targets     (UsingTask + target definitions)
  buildTransitive/
    MyCompany.Build.Tasks.props       (optional: set defaults)
    MyCompany.Build.Tasks.targets     (UsingTask + target definitions)
  tools/
    net8.0/                           (matches csproj TargetFramework)
      MyCompany.Build.Tasks.dll       (task assembly)
      (other dependencies)
```

### build vs buildTransitive

| Folder | Scope |
|---|---|
| `build/` | Targets/props apply to the **direct consumer** only |
| `buildTransitive/` | Targets/props apply to the **direct consumer and all projects that transitively reference it** |

Use `buildTransitive/` for tasks that must run in every project in the dependency graph (e.g., code analyzers, source generators). Use `build/` for tasks specific to the consuming project.

### .targets File for NuGet Package

```xml
<!-- build/MyCompany.Build.Tasks.targets -->
<Project>
  <!-- TFM in path must match the csproj's TargetFramework -->
  <UsingTask TaskName="MyCompany.Build.GenerateFileHash"
             AssemblyFile="$(MSBuildThisFileDirectory)..\tools\net8.0\MyCompany.Build.Tasks.dll" />

  <Target Name="_MyCompanyHashOutputs"
          AfterTargets="Build"
          Condition="'$(GenerateOutputHashes)' == 'true'">
    <GenerateFileHash InputFile="$(TargetPath)">
      <Output TaskParameter="Hash" PropertyName="_OutputHash" />
    </GenerateFileHash>
    <Message Importance="high"
             Text="Output hash: $(_OutputHash)" />
  </Target>
</Project>
```

### .props File for NuGet Package

```xml
<!-- build/MyCompany.Build.Tasks.props -->
<Project>
  <PropertyGroup>
    <!-- Default: consumers can override in their project file -->
    <GenerateOutputHashes Condition="'$(GenerateOutputHashes)' == ''">false</GenerateOutputHashes>
  </PropertyGroup>
</Project>
```

### Project File for the Task Package

```xml
<!-- MyCompany.Build.Tasks.csproj -->
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <IsPackable>true</IsPackable>
    <PackageId>MyCompany.Build.Tasks</PackageId>
    <PackageVersion>1.0.0</PackageVersion>
    <Description>Custom MSBuild tasks for MyCompany build pipeline</Description>

    <!-- Do not add as a lib dependency -->
    <IncludeBuildOutput>false</IncludeBuildOutput>

    <!-- Suppress NU5100: task DLLs are in tools/, not lib/ -->
    <NoWarn>$(NoWarn);NU5100</NoWarn>

    <!-- Mark as a development dependency -->
    <DevelopmentDependency>true</DevelopmentDependency>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="Microsoft.Build.Framework" Version="17.8.3"
                      PrivateAssets="all" />
    <PackageReference Include="Microsoft.Build.Utilities.Core" Version="17.8.3"
                      PrivateAssets="all" />
  </ItemGroup>

  <!-- Pack task assembly into tools/ (uses TFM from project) -->
  <ItemGroup>
    <None Include="$(OutputPath)/**/*.dll" Pack="true"
          PackagePath="tools/$(TargetFramework)/" />
  </ItemGroup>

  <!-- Pack .props and .targets into build/ and buildTransitive/ -->
  <ItemGroup>
    <None Include="build/**" Pack="true" PackagePath="build/" />
    <None Include="buildTransitive/**" Pack="true" PackagePath="buildTransitive/" />
  </ItemGroup>
</Project>
```

**Key csproj settings:**
- `IncludeBuildOutput=false` prevents the task DLL from appearing in the `lib/` folder (which would add it as a compile reference to consumers).
- `DevelopmentDependency=true` marks the package as build-time only, so it does not flow to consumers' runtime dependencies.
- `PrivateAssets="all"` on MSBuild framework references prevents them from becoming transitive dependencies.

---
