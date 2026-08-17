# Version Detection

```bash
dotnet --version 2>/dev/null
```

Detects .NET version information from project files and provides version-specific guidance. This skill runs **first** before any .NET development work. All other skills depend on the detected version to adapt their guidance.

Cross-cutting skill referenced by [skill:dotnet-advisor] and virtually all specialist skills. See also [skill:dotnet-api] for .NET 10+ file-based apps that run without a `.csproj`.

## Fast Repository Scan (Optional)

For large repos, run the bundled scanner first to quickly inventory TFM/SDK signals before applying the precedence algorithm below:

```bash
python3 skills/dotnet-tooling/scripts/scan-dotnet-targets.py --root . --json
```

Use the script output (`project_target_frameworks`, `global_json.sdk_version`, `workflow_dotnet_versions`) as discovery input. The precedence rules below remain authoritative for final TFM selection.


## Detection Precedence Algorithm

Read project files in this strict order. **Higher-numbered sources are lower priority.** Stop falling through once a TFM is resolved.

### 1. Direct `<TargetFramework>` in .csproj (highest priority)

Read the nearest `.csproj` file to the current working file/directory.

```xml
<PropertyGroup>
  <TargetFramework>net10.0</TargetFramework>
</PropertyGroup>
```

If found **and the value is a literal TFM** (e.g., `net10.0`, not `$(SomeProperty)`), this is the authoritative TFM. Report it and proceed to additional detection (Step 5).

If the value is an MSBuild property expression (starts with `$(`), skip to **Step 4** for unresolved property handling.

### 2. `<TargetFrameworks>` in .csproj (multi-targeting)

```xml
<PropertyGroup>
  <TargetFrameworks>net8.0;net10.0</TargetFrameworks>
</PropertyGroup>
```

If found:
- Report **all** TFMs (semicolon-delimited)
- Guide based on the **highest** TFM (e.g., net10.0)
- Note polyfill needs for lower TFMs: "Consider `references/multi-targeting.md` for PolySharp/Polyfill to backport language features to net8.0"
- Proceed to additional detection (Step 5)

### 3. `Directory.Build.props` shared TFM

If no `<TargetFramework>` or `<TargetFrameworks>` found in the .csproj (or if the .csproj inherits from shared props), read `Directory.Build.props` in the current directory or any parent directory up to the solution root.

```xml
<!-- Directory.Build.props -->
<PropertyGroup>
  <TargetFramework>net10.0</TargetFramework>
</PropertyGroup>
```

If found, use this as the TFM. Note: per-project `.csproj` values override `Directory.Build.props`.

### 4. MSBuild Property Expressions (fallback with warning)

If the TFM value is an MSBuild property expression rather than a literal:

```xml
<TargetFramework>$(MyCustomTfm)</TargetFramework>
```

Emit warning:
> **Warning: Unresolved MSBuild property `$(MyCustomTfm)`.** Cannot determine TFM statically. Falling back to SDK version from `global.json`.

Then fall through to `global.json` SDK version (Step 4a) or `dotnet --version` (Step 4b).

#### 4a. `global.json` SDK version

```json
{
  "sdk": {
    "version": "10.0.100"
  }
}
```

Map SDK version to approximate TFM:
- `8.0.xxx` -> net8.0
- `9.0.xxx` -> net9.0
- `10.0.xxx` -> net10.0
- `11.0.xxx-preview.x` -> net11.0

Report: "Inferred TFM from `global.json` SDK version. Verify actual TFM in project file."

#### 4b. `dotnet --version` (last resort)

If no `global.json` exists, use `dotnet --version` output to infer SDK version. Same mapping as 4a.

Report: "Inferred TFM from installed SDK version. No `global.json` or `.csproj` found. Consider creating a project with `dotnet new`."


## Additional Detection (Step 5)

After resolving the TFM, also check these files for supplementary version information. Always perform these checks regardless of which precedence step resolved the TFM.

### 5a. `global.json` SDK Version

Even if TFM was resolved from .csproj, read `global.json` for:
- `sdk.version` -- the pinned SDK version
- `sdk.rollForward` -- the rollForward policy (e.g., `latestFeature`, `latestPatch`)

Report the SDK version alongside the TFM. Flag inconsistencies:
> **Warning: TFM `net10.0` but `global.json` pins SDK `9.0.100`.** The project targets a newer framework than the pinned SDK. Update `global.json` or verify the build environment has the correct SDK.

### 5b. C# Language Version

Check for explicit `<LangVersion>` in .csproj or `Directory.Build.props`:

```xml
<LangVersion>preview</LangVersion>
```

- If `preview` -- report "C# preview features enabled. Unlocks the next C# version available in the installed SDK (e.g., C# 15 preview features with a .NET 11 preview SDK)."
- If `latest` -- report the default C# version for the detected TFM
- If explicit version (e.g., `12.0`) -- report that version, warn if it's below the TFM default
- If absent -- use the default C# version for the TFM (see reference data below)

### 5c. Preview Feature Detection

Check for these properties in .csproj or `Directory.Build.props`:

**EnablePreviewFeatures:**
```xml
<EnablePreviewFeatures>true</EnablePreviewFeatures>
```
Report: ".NET preview features enabled. Access to preview APIs and types."

**Runtime-async feature flag (.NET 11+):**
```xml
<Features>$(Features);runtime-async=on</Features>
```
Report: "Runtime-async enabled. Async/await uses runtime-level execution instead of compiler state machines."

Note: runtime-async requires `<EnablePreviewFeatures>true</EnablePreviewFeatures>` as well.

### 5d. Multi-targeting Details

If multi-targeting was detected (Step 2), also note:
- Which TFMs are LTS vs STS vs Preview
- Which TFMs are approaching end-of-support
- Suggest `references/multi-targeting.md` for polyfill guidance


## Structured Output Format

After detection, present results in this structured format:

```
.NET Version Detection Results
==============================
TFM:              net10.0 (or net8.0;net10.0 for multi-targeting)
Highest TFM:      net10.0
C# Version:       14 (default for net10.0)
SDK Version:      10.0.100 (from global.json)
Preview Features: none
Runtime-Async:    not enabled
Warnings:         none

Guidance: This project targets .NET 10 LTS with C# 14. Use modern patterns
including field-backed properties, collection expressions, and primary
constructors. All guidance will target net10.0 capabilities.
```

For multi-targeting:

```
.NET Version Detection Results
==============================
TFMs:             net8.0;net10.0
Highest TFM:      net10.0
C# Version:       14 (default for highest TFM)
SDK Version:      10.0.100 (from global.json)
Preview Features: none
Warnings:         net8.0 reaches end of support Nov 2026

Guidance: Multi-targeting net8.0 and net10.0. Guide on net10.0 patterns.
For net8.0 compatibility, use PolySharp/Polyfill for language features.
See `references/multi-targeting.md` for detailed polyfill guidance.
```


## Edge Cases

### No .csproj Found
If no `.csproj` exists in the workspace:
- Check for `.sln` or `.slnx` files and look for referenced projects
- If no project files found, continue the fallback chain:
  1. Read `global.json` for SDK version (Step 4a) and infer TFM from it
  2. If no `global.json`, use `dotnet --version` (Step 4b) to infer TFM
  3. Only if both inference methods fail: "No .NET project or SDK detected. Defaulting guidance to net10.0 (current LTS). Use `dotnet new` to create a project."

### MSBuild Property Indirection
If `<TargetFramework>` contains `$(PropertyName)`:
- Emit: "**Unresolved property: `$(PropertyName)`.** Cannot determine TFM from static analysis."
- Fall back to `global.json` SDK version, then `dotnet --version`
- Recommend verifying TFM via `dotnet --list-sdks` or `dotnet msbuild -getProperty:TargetFramework`

### Inconsistent Files
If .csproj says `net10.0` but `global.json` pins SDK `9.0.100`:
- Prefer the .csproj TFM (higher precedence)
- Warn about the mismatch
- Suggest updating `global.json` to match

### No SDK Installed
If `dotnet --version` fails or is not found:
- Report: "No .NET SDK detected on this system. Install from https://dot.net"
- If project files exist, still report the TFM from project files
- Note that builds will fail without the SDK

### `.fsproj` and `.vbproj`
The same detection logic applies to F# (`.fsproj`) and VB.NET (`.vbproj`) projects. The `<TargetFramework>` element is identical across all .NET project types.


## Caching Behavior

Version detection results should be cached per-project (per .csproj path). Re-detect when:
- The user switches to a different project within the solution
- The user explicitly asks to re-detect
- A `.csproj`, `Directory.Build.props`, or `global.json` file is modified


## Version-to-Feature Reference Data

> **Last updated: 2026-02-11**

This reference data maps .NET versions to their C# language versions, key features, and support lifecycle. This section is **separate from the detection logic above** -- detection determines which version is in use; this data maps that version to available features.

### Version Matrix

| .NET Version | Status | C# Version | TFM | Support End | Notes |
|-------------|--------|-------------|-----|-------------|-------|
| .NET 8 | LTS (active) | C# 12 | net8.0 | Nov 2026 | Approaching end of support |
| .NET 9 | STS | C# 13 | net9.0 | May 2026 | Approaching end of support |
| .NET 10 | LTS (current) | C# 14 | net10.0 | Nov 2028 | Recommended for new projects |
| .NET 11 | Preview 1 | C# 15 (preview) | net11.0 | TBD (expected STS end: ~May 2028 if Nov 2026 GA) | Preview only -- not for production |

### C# Version Feature Highlights

**C# 12 (net8.0)**
- Primary constructors for classes/structs
- Collection expressions (`[1, 2, 3]`)
- `ref readonly` parameters
- Default lambda parameters
- Alias any type with `using`
- Inline arrays
- Interceptors (experimental)

**C# 13 (net9.0)**
- `params` collections (any collection type)
- `Lock` type (`System.Threading.Lock`)
- New escape sequence `\e`
- Method group natural type improvements
- Implicit indexer access in object initializers
- `ref` and `unsafe` in iterators/async
- Partial properties

**C# 14 (net10.0)**
- Field-backed properties (`field` contextual keyword)
- `nameof` for unbound generic types
- Extension improvements (extension blocks)
- First-class `Span<T>` in more contexts
- `allows ref struct` anti-constraint for generics

**C# 15 preview (net11.0)**
- Collection expression arguments (`with()` syntax for capacity/comparers):
  ```csharp
  List<int> nums = [with(capacity: 32), 0, ..evens, ..odds];
  HashSet<string> names = [with(comparer: StringComparer.OrdinalIgnoreCase), "Alice"];
  ```
- Additional features expected as .NET 11 progresses through preview

### .NET 11 Preview 1 Notable Features

These features are available when `net11.0` TFM is detected with preview features enabled:

- **Runtime-async**: Async/await at runtime level (requires `<EnablePreviewFeatures>true</EnablePreviewFeatures>` + `<Features>$(Features);runtime-async=on</Features>`)
- **Zstandard compression**: `System.IO.Compression.Zstandard` (2-7x faster than Brotli/Deflate)
- **BFloat16**: `System.Numerics.BFloat16` for AI/ML workloads
- **Happy Eyeballs**: `ConnectAlgorithm.Parallel` for dual-stack networking
- **CoreCLR for Android**: Default runtime for MAUI Android Release builds
- **XAML source generation**: Default in MAUI (replaces XAMLC)
- **EF Core**: Complex types + JSON columns with TPT/TPC inheritance
- **CoreCLR on WASM**: Experimental alternative to Mono for Blazor WASM

### Support Lifecycle Guidance

When reporting version information, include lifecycle context:
- **End-of-support approaching** (within 6 months): Warn and suggest `references/version-upgrade.md`
- **Preview/RC**: Warn "not for production use" unless user explicitly opted in
- **STS reaching end**: Note shorter support window compared to LTS
- **Current LTS**: Confirm as recommended target for new projects
