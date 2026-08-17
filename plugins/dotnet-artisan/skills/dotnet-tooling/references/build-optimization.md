# Build Optimization

Guidance for diagnosing and fixing build performance problems: incremental build failure diagnosis workflows, binary log analysis with MSBuild Structured Log Viewer, parallel build configuration, build caching, and restore optimization. Covers the diagnostic workflow from symptom (full rebuild on every build) through root cause (missing Inputs/Outputs, timestamp corruption, generator side effects) to fix.

**Version assumptions:** .NET 8.0+ SDK (MSBuild 17.8+). All examples use SDK-style projects.

## Incremental Build Failure Diagnosis

When a target runs on every build despite no source changes, the build is not incremental. This wastes time and masks real changes. The diagnosis workflow follows a repeatable pattern: detect the symptom, capture a binary log, identify the offending target, determine why incrementality failed, and apply the fix.

### Diagnosis Workflow

```
1. Symptom: Build takes longer than expected, or output says
   "Building target 'X' completely" on every build
2. Capture binary log:  dotnet build /bl
3. Open the .binlog in MSBuild Structured Log Viewer
4. Search for targets that ran (not skipped)
5. Check: Does the target have Inputs/Outputs?
   - No  -> Add Inputs/Outputs (see fix patterns below)
   - Yes -> Compare timestamps: are outputs older than inputs?
           -> Check for volatile writers or missing output files
6. Apply fix, rebuild, verify target is skipped
```

### Step 1: Capture a Binary Log

```bash
# Produce msbuild.binlog in the project directory
dotnet build /bl

# Named log file
dotnet build /bl:build-debug.binlog

# Binary log for restore + build (captures full pipeline)
dotnet build /bl -restore
```

The `/bl` switch records every MSBuild event -- property evaluations, item lists, target entry/exit, task execution, and timestamps -- into a compact binary format. Binary logs contain full source paths and environment variables; do not commit them to version control or share publicly.

### Step 2: Open in MSBuild Structured Log Viewer

Download from [msbuildlog.com](https://msbuildlog.com/). Open the `.binlog` file. Key views:

| View | Use |
|---|---|
| **Timeline** | See which targets ran in parallel and how long each took |
| **Target Results** | Filter by "Built" (ran) vs "Skipped" (incremental hit) |
| **Search** | Find specific target names, property values, or file paths |
| **Properties** | Inspect evaluated property values at any point in the build |
| **Items** | Inspect item collections (Compile, Content, etc.) with metadata |

### Step 3: Find the Non-Incremental Target

In the Structured Log Viewer, search for the target name and check its result. A target that should be incremental but ran fully will show "Building target 'X' completely" with a reason:

- **"Output file does not exist"** -- an expected output file is missing or was deleted
- **"Input file is newer than output file"** -- a source file changed, or a preceding step rewrote an output
- **No Inputs/Outputs declared** -- the target always runs because MSBuild has no way to check freshness


## Common Incremental Build Failure Patterns

### Missing Inputs/Outputs on Custom Targets

**Symptom:** Custom target runs on every build.

**Root cause:** The target has no `Inputs`/`Outputs` attributes. Without them, MSBuild runs the target unconditionally.

**Fix:** Add `Inputs` and `Outputs` that reflect the actual files read and written:

```xml
<!-- BEFORE: runs every build -->
<Target Name="GenerateVersionFile" BeforeTargets="CoreCompile">
  <WriteLinesToFile File="$(IntermediateOutputPath)Version.g.cs"
                    Lines="[assembly: System.Reflection.AssemblyInformationalVersion(&quot;$(Version)&quot;)]"
                    Overwrite="true" />
</Target>

<!-- AFTER: only runs when Version property changes (via project file edit) -->
<Target Name="GenerateVersionFile"
        BeforeTargets="CoreCompile"
        Inputs="$(MSBuildProjectFullPath)"
        Outputs="$(IntermediateOutputPath)Version.g.cs">
  <WriteLinesToFile File="$(IntermediateOutputPath)Version.g.cs"
                    Lines="[assembly: System.Reflection.AssemblyInformationalVersion(&quot;$(Version)&quot;)]"
                    Overwrite="true" />
</Target>
```

See `references/msbuild-authoring.md` for full Inputs/Outputs patterns and batching.

### File Copy Timestamp Corruption

**Symptom:** Target re-runs because output file timestamps are always newer than inputs.

**Root cause:** A `Copy` task without `SkipUnchangedFiles="true"` updates the destination timestamp on every copy, even when content is identical.

**Fix:**

```xml
<!-- BEFORE: copies every build, resetting timestamps -->
<Copy SourceFiles="@(ConfigTemplate)"
      DestinationFolder="$(OutputPath)" />

<!-- AFTER: skips unchanged files, preserving timestamps -->
<Copy SourceFiles="@(ConfigTemplate)"
      DestinationFolder="$(OutputPath)"
      SkipUnchangedFiles="true" />
```

### Generators Writing Unconditionally

**Symptom:** A code generator target runs every build even though inputs have not changed.

**Root cause:** The generator writes output files unconditionally, updating their timestamps even when content is identical. The next build sees "input newer than output" (because the generator itself is an input to downstream targets).

**Fix:** Write to a temp file first, then copy only if content differs:

```xml
<Target Name="GenerateCode"
        BeforeTargets="CoreCompile"
        Inputs="@(SchemaFile)"
        Outputs="@(SchemaFile->'$(IntermediateOutputPath)%(Filename).g.cs')">
  <!-- Write to temp file -->
  <Exec Command="codegen %(SchemaFile.Identity) -o $(IntermediateOutputPath)%(SchemaFile.Filename).g.cs.tmp" />

  <!-- Copy only if content changed (preserves timestamp when unchanged) -->
  <Copy SourceFiles="$(IntermediateOutputPath)%(SchemaFile.Filename).g.cs.tmp"
        DestinationFiles="$(IntermediateOutputPath)%(SchemaFile.Filename).g.cs"
        SkipUnchangedFiles="true" />
</Target>
```

### Volatile Intermediate Files

**Symptom:** A target that depends on intermediate outputs re-runs because an earlier target always regenerates those files.

**Root cause:** An upstream target produces intermediate files (e.g., generated code, resource bundles) without proper Inputs/Outputs, causing those files to be rewritten every build. Downstream targets see them as "changed" and re-run.

**Fix:** Add Inputs/Outputs to the upstream target. If the upstream target is from the SDK or a NuGet package and cannot be modified, use `Touch` task to reset timestamps on its outputs to a stable value when content has not changed.


## Binary Log Analysis

### Capturing Binary Logs

```bash
# Basic binary log (outputs msbuild.binlog)
dotnet build /bl

# Named output file
dotnet build /bl:diagnostic.binlog

# Include restore phase
dotnet build /bl -restore

# Detailed verbosity in console + binary log
dotnet build /bl /v:minimal
```

Binary logs capture everything regardless of the `/v:` verbosity level. The `/v:` switch only controls console output. Always use `/bl` for diagnosis; console verbosity is for quick scanning.

### Preprocessed Project View

The `-pp` (preprocess) switch dumps the fully evaluated project file after all imports, conditions, and property substitutions:

```bash
# Dump the preprocessed project to stdout
dotnet msbuild MyApp.csproj -pp

# Redirect to a file for easier reading
dotnet msbuild MyApp.csproj -pp > preprocessed.xml
```

The preprocessed output shows:
- All imported `.props` and `.targets` files with their source paths
- Final evaluated property values
- Complete item lists after all Include/Exclude/Update/Remove operations
- All target definitions with resolved conditions

Use `-pp` to answer "where does this property come from?" or "which `.targets` file defines this target?" without opening a binary log.

### Key Diagnostic Searches in Binary Logs

| Search query | What it reveals |
|---|---|
| Target name (e.g., `CoreCompile`) | Whether the target ran or was skipped, and why |
| `$property` (e.g., `$TargetFramework`) | Evaluated value at each point in the build |
| File path (e.g., `Order.cs`) | Which targets processed the file and when |
| `"Building target"` | All targets that ran (not skipped) |
| `"Skipping target"` | All targets that were skipped (incremental hit) |
| Warning/error text | Source location and build context for diagnostics |


## Parallel Builds

### Solution-Level Parallelism

MSBuild can build independent projects within a solution in parallel using multiple worker nodes:

```bash
# Use all available CPU cores (default behavior for dotnet build)
dotnet build

# Explicit: 4 worker nodes
dotnet build /m:4

# Single-threaded (useful for debugging build order issues)
dotnet build /m:1
```

`dotnet build` enables `/m` (multi-process) by default. Each worker node is a separate MSBuild process that builds one project at a time. Projects with no dependency relationship build in parallel.

### Graph Build Mode

Graph build (`/graph`) analyzes the project dependency graph before building and schedules projects for maximum parallelism:

```bash
# Graph-aware parallel build
dotnet build /graph

# Graph build with explicit parallelism
dotnet build /graph /m:8
```

Graph mode advantages over default parallel build:
- **Static scheduling:** Determines the full dependency graph upfront instead of discovering dependencies during build
- **Avoids redundant evaluations:** Each project is evaluated once, not once per referencing project
- **Better node utilization:** Worker nodes receive projects as soon as dependencies are satisfied

Graph mode is particularly effective for large solutions (50+ projects) where the dependency graph has significant parallelism.

### BuildInParallel Task Attribute

Individual MSBuild tasks (like `MSBuild` task) can declare whether they support parallel invocation:

```xml
<!-- Build referenced projects in parallel -->
<MSBuild Projects="@(ProjectReference)"
         BuildInParallel="true"
         Targets="Build" />
```

`BuildInParallel="true"` allows the `MSBuild` task to distribute its project list across available worker nodes. This is the mechanism used by solution builds to parallelize project compilation.

### Diagnosing Parallel Build Issues

Parallel builds can surface latent issues that serial builds mask:

1. **Race conditions on shared files:** Two projects writing to the same output directory simultaneously. Fix: use per-project output directories (the SDK default `bin/Debug/$(TargetFramework)/`).
2. **Undeclared dependencies:** Project A depends on Project B's output but does not declare a `<ProjectReference>`. Serial builds happen to build B first; parallel builds may build A first. Fix: add explicit `<ProjectReference>`.
3. **Directory creation races:** Multiple projects creating the same intermediate directory. Fix: use `MakeDir` task with `ContinueOnError="true"` or ensure each project uses its own `$(IntermediateOutputPath)`.

Use `/m:1` to confirm a build works serially, then `/m` to check for parallelism issues. Binary logs with timeline view show project scheduling and reveal race conditions.


## Build Caching and Restore Optimization

### NuGet Restore Optimization

NuGet restore is often the slowest build step, especially in CI. These patterns reduce restore time:

```bash
# Locked restore: skip resolution if lock file is current
dotnet restore --locked-mode

# Use lock files for deterministic restores
dotnet restore --use-lock-file
```

```xml
<!-- Enable lock files project-wide in Directory.Build.props -->
<PropertyGroup>
  <RestorePackagesWithLockFile>true</RestorePackagesWithLockFile>
</PropertyGroup>
```

Lock file restore (`--locked-mode`) skips the dependency resolution algorithm entirely, reading the exact versions from `packages.lock.json`. This is faster and ensures CI uses the same versions that were tested locally. For lock file and CPM configuration details, see `references/project-structure.md`.

### SDK Build Caching

The .NET SDK caches several build artifacts to avoid redundant work:

| Cache | Location | Purpose |
|---|---|---|
| NuGet global packages | `~/.nuget/packages/` | Downloaded package contents |
| NuGet HTTP cache | `~/.local/share/NuGet/http-cache/` | HTTP response cache for feed queries |
| MSBuild project result cache | In-memory (per build session) | Skips re-evaluating already-built projects |
| `obj/` intermediate output | Per-project `obj/` directory | Compiler state, generated files, timestamps |

### CI Build Optimization

```yaml
# GitHub Actions: cache NuGet packages between runs
- name: Cache NuGet packages
  uses: actions/cache@v4
  with:
    path: ~/.nuget/packages
    key: nuget-${{ runner.os }}-${{ hashFiles('**/packages.lock.json') }}
    restore-keys: |
      nuget-${{ runner.os }}-

# Use locked restore for speed and determinism
- name: Restore
  run: dotnet restore --locked-mode
```

### NoWarn and TreatWarningsAsErrors Strategy

Build-level warning configuration affects build time when analyzers are involved:

```xml
<!-- Directory.Build.props: set warning policy for all projects -->
<PropertyGroup>
  <TreatWarningsAsErrors>true</TreatWarningsAsErrors>

  <!-- Suppress specific warnings globally (with justification) -->
  <NoWarn>$(NoWarn);CA2007</NoWarn>  <!-- ConfigureAwait: not needed in ASP.NET Core apps -->
</PropertyGroup>
```

**Rules for warning configuration:**
- Enable `TreatWarningsAsErrors` in `Directory.Build.props` so local and CI builds behave identically
- Use `NoWarn` sparingly and always with inline justification comments
- Prefer `.editorconfig` severity rules over `NoWarn` for per-rule control
- For detecting misuse of warning suppression, see `references/build-analysis.md`


## Agent Gotchas

1. **Running `dotnet build` without `/bl` when diagnosing build issues.** Console output at default verbosity omits critical information about why targets ran. Always capture a binary log (`/bl`) for diagnosis -- it records everything regardless of console verbosity level.

2. **Assuming incremental build works without Inputs/Outputs.** A target without `Inputs`/`Outputs` runs on every build unconditionally. There is no implicit incrementality in MSBuild -- you must declare what files the target reads and writes. See `references/msbuild-authoring.md` for the full pattern.

3. **Forgetting `SkipUnchangedFiles="true"` on Copy tasks.** Without this flag, `Copy` always updates the destination timestamp, which triggers downstream targets to re-run even when file content is identical.

4. **Using `/v:diagnostic` instead of `/bl` for build investigation.** Diagnostic verbosity floods the console with thousands of lines and is hard to search. Binary logs contain the same information in a structured, searchable format. Use `/bl` and the Structured Log Viewer instead.

5. **Sharing the `.binlog` file without reviewing it first.** Binary logs contain full file paths, environment variable values, and potentially secrets passed via MSBuild properties. Review or sanitize before sharing externally.

6. **Assuming `/m` (parallel build) is always faster.** For small solutions (fewer than 5 projects), the overhead of spawning worker nodes can exceed the parallelism benefit. Profile with and without `/m` to confirm. For large solutions, `/graph` mode provides better scheduling than default `/m`.

7. **Committing `packages.lock.json` without using `--locked-mode` in CI.** The lock file is only useful if CI restores in locked mode. Without `--locked-mode`, NuGet ignores the lock file and resolves normally, defeating the purpose of deterministic restores.

8. **Modifying `.csproj` properties to fix build performance without checking the binary log first.** Many "slow build" issues are caused by a single non-incremental target, not by global build configuration. Diagnose with `/bl` before making broad configuration changes.


## References

- [MSBuild Binary Log](https://learn.microsoft.com/en-us/visualstudio/msbuild/obtaining-build-logs#save-a-binary-log)
- [MSBuild Structured Log Viewer](https://msbuildlog.com/)
- [Incremental Builds](https://learn.microsoft.com/en-us/visualstudio/msbuild/incremental-builds)
- [MSBuild Parallel Builds](https://learn.microsoft.com/en-us/visualstudio/msbuild/building-multiple-projects-in-parallel-with-msbuild)
- [Graph Build](https://github.com/dotnet/msbuild/blob/main/documentation/specs/static-graph.md)
- [NuGet Lock Files](https://learn.microsoft.com/en-us/nuget/consume-packages/package-references-in-project-files#locking-dependencies)
- [Customize Your Build](https://learn.microsoft.com/en-us/visualstudio/msbuild/customize-your-build)
