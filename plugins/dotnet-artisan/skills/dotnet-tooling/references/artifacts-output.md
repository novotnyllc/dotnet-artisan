# Artifacts Output

Reference guide for the .NET SDK artifacts output layout, which centralizes build outputs (`bin/`, `obj/`, `publish/`, `package/`) into a single `artifacts/` directory at the repo root. Available since .NET 8 as an opt-in feature. Recommended for new projects; evaluate tradeoffs before migrating existing projects.

**Prerequisites:** Run `references/version-detection.md` first to confirm .NET 8+ SDK -- artifacts output layout is not available in earlier SDK versions.

## Why Use Artifacts Output

Traditional .NET build output scatters `bin/` and `obj/` directories throughout the source tree, one per project. The artifacts output layout consolidates all build outputs under a single `artifacts/` directory next to `Directory.Build.props`.

Benefits:
- **Simpler `.gitignore`** -- one `artifacts/` entry replaces per-project `bin/` and `obj/` entries
- **Easier clean builds** -- delete one directory instead of hunting for scattered `bin/`/`obj/` folders
- **Predictable output paths** -- tooling can anticipate where to find build outputs without traversing the source tree
- **Cleaner source tree** -- no build artifacts mixed into project directories

Tradeoffs:
- **Breaking path assumptions** -- existing CI pipelines, Dockerfiles, and tooling that reference `bin/Debug/net10.0/` paths must be updated
- **IDE/tool compatibility** -- some older tools may not resolve the new output paths correctly
- **Migration effort** -- existing projects require updating all hardcoded output path references


## Enabling Artifacts Output

Add `UseArtifactsOutput` to your `Directory.Build.props` at the repo root:

```xml
<Project>
  <PropertyGroup>
    <UseArtifactsOutput>true</UseArtifactsOutput>
  </PropertyGroup>
</Project>
```

Alternatively, generate a new `Directory.Build.props` with artifacts output pre-configured:

```bash
dotnet new buildprops --use-artifacts
```

This creates:

```xml
<Project>
  <PropertyGroup>
    <ArtifactsPath>$(MSBuildThisFileDirectory)artifacts</ArtifactsPath>
  </PropertyGroup>
</Project>
```

Setting `ArtifactsPath` directly is equivalent to `UseArtifactsOutput=true` and additionally lets you customize the root directory location.


## Output Path Structure

All build outputs are organized under `artifacts/` with three levels: output type, project name, and pivot (configuration/TFM/RID).

```
artifacts/
  bin/
    MyApp/
      debug/                          # Single-targeted project
      debug_net10.0/                  # Multi-targeted project
      release_linux-x64/              # RID-specific build
    MyApp.Core/
      debug/
  obj/
    MyApp/
      debug/
  publish/
    MyApp/
      release/                        # dotnet publish output
      release_linux-x64/              # RID-specific publish
  package/
    release/                          # NuGet .nupkg files (no project subfolder)
```

### Output Type Directories

| Directory | Contents | Traditional equivalent |
|-----------|----------|----------------------|
| `artifacts/bin/` | Compiled assemblies and dependencies | `<project>/bin/` |
| `artifacts/obj/` | Intermediate build files, generated code | `<project>/obj/` |
| `artifacts/publish/` | Published application output | `<project>/bin/<config>/<tfm>/publish/` |
| `artifacts/package/` | NuGet packages (`.nupkg`, `.snupkg`) | `<project>/bin/<config>/` |

### Pivot Naming

The pivot subfolder combines configuration, TFM, and RID joined by underscores. Components that are not present are omitted:

| Scenario | Pivot | Full path example |
|----------|-------|-------------------|
| Single-targeted, debug | `debug` | `artifacts/bin/MyApp/debug/` |
| Multi-targeted, debug | `debug_net10.0` | `artifacts/bin/MyApp/debug_net10.0/` |
| Release, RID-specific | `release_linux-x64` | `artifacts/bin/MyApp/release_linux-x64/` |
| Package output | `release` | `artifacts/package/release/` |

Note: `artifacts/package/` omits the project name subfolder. The pivot includes only the configuration.


## Customizing the Artifacts Path

### Custom Root Directory

Set `ArtifactsPath` to change the root location:

```xml
<PropertyGroup>
  <ArtifactsPath>$(MSBuildThisFileDirectory).output</ArtifactsPath>
</PropertyGroup>
```

This places all build outputs under `.output/` instead of `artifacts/`.

### Custom Pivot

Customize the pivot subfolder naming with `ArtifactsPivots`:

```xml
<PropertyGroup>
  <ArtifactsPivots>$(ArtifactsPivots)_MyCustomPivot</ArtifactsPivots>
</PropertyGroup>
```


## Impact on .gitignore

With artifacts output enabled, simplify `.gitignore`:

```gitignore
# Artifacts output layout (replaces per-project bin/ and obj/ entries)
artifacts/
```

This single entry replaces the traditional pattern:

```gitignore
# Traditional layout (no longer needed with artifacts output)
[Bb]in/
[Oo]bj/
```

If using a custom `ArtifactsPath`, update the `.gitignore` entry to match.


## Impact on Dockerfiles

Multi-stage Dockerfiles that copy build output must reference the new path structure. See [skill:dotnet-devops] for full Dockerfile patterns.

**Traditional paths:**

```dockerfile
COPY --from=build /app/src/MyApp/bin/Release/net10.0/publish/ .
```

**Artifacts output paths:**

```dockerfile
COPY --from=build /app/artifacts/publish/MyApp/release/ .
```

Key differences in Dockerfile paths:
- Output is under `artifacts/publish/` not `bin/Release/<tfm>/publish/`
- Project name becomes a subdirectory under the output type
- Configuration pivot is lowercase (`release` not `Release`)
- TFM is omitted from single-targeted project pivots


## Impact on CI Pipelines

CI workflows that upload build artifacts or reference output paths must be updated. See [skill:dotnet-devops] for full CI workflow patterns.

**GitHub Actions -- upload build output:**

```yaml
- name: Publish
  run: dotnet publish src/MyApp/MyApp.csproj -c Release

- name: Upload artifact
  uses: actions/upload-artifact@v4
  with:
    name: app
    path: artifacts/publish/MyApp/release/
```

**GitHub Actions -- upload NuGet packages:**

```yaml
- name: Pack
  run: dotnet pack -c Release

- name: Upload packages
  uses: actions/upload-artifact@v4
  with:
    name: packages
    path: artifacts/package/release/*.nupkg
```

**Azure DevOps -- publish artifacts:**

```yaml
- script: dotnet publish src/MyApp/MyApp.csproj -c Release
  displayName: 'Publish'

- task: PublishPipelineArtifact@1
  inputs:
    targetPath: 'artifacts/publish/MyApp/release/'
    artifact: 'app'
```


## Migration Checklist

When enabling artifacts output on an existing project:

1. **Add `UseArtifactsOutput`** to `Directory.Build.props`
2. **Update `.gitignore`** -- replace `[Bb]in/` and `[Oo]bj/` with `artifacts/`
3. **Update Dockerfiles** -- change all `COPY --from=build` paths to use `artifacts/` structure
4. **Update CI pipelines** -- fix artifact upload paths, test result paths, and publish paths
5. **Update local scripts** -- fix any shell scripts that reference `bin/` or `obj/` paths
6. **Clean old output** -- delete existing `bin/` and `obj/` directories from all projects
7. **Verify builds** -- run `dotnet build` and `dotnet publish` to confirm output appears under `artifacts/`
8. **Verify tests** -- run `dotnet test` to confirm test execution with new paths


## Agent Gotchas

1. **Do not hardcode TFM in artifacts output paths for single-targeted projects.** The pivot for single-targeted projects is just the configuration (e.g., `debug`), not `debug_net10.0`. Multi-targeted projects include the TFM in the pivot.
2. **Do not use capitalized configuration names in artifacts paths.** The artifacts layout uses lowercase pivots (`debug`, `release`), not the traditional capitalized names (`Debug`, `Release`).
3. **Do not assume `artifacts/package/` has a project name subfolder.** Unlike `bin/`, `obj/`, and `publish/`, the `package/` output type omits the project name level. Packages appear directly under `artifacts/package/<config>/`.
4. **Do not enable artifacts output without updating Dockerfiles and CI pipelines first.** Path changes will break `COPY --from=build` directives and artifact upload steps that reference traditional `bin/` paths.
5. **Do not present artifacts output as the default .NET layout.** It is opt-in since .NET 8 and remains opt-in. Recommend it for new projects; for existing projects, evaluate the migration effort against the benefits.


## References

- [Artifacts output layout](https://learn.microsoft.com/en-us/dotnet/core/sdk/artifacts-output)
- [Customize your build (Directory.Build.props)](https://learn.microsoft.com/en-us/visualstudio/msbuild/customize-your-build)
- [dotnet new buildprops](https://learn.microsoft.com/en-us/dotnet/core/tools/dotnet-new-sdk-templates#buildprops)
