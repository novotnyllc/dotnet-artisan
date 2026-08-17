# Add CI

Add starter CI/CD workflows to an existing .NET project. Detects the hosting platform (GitHub Actions or Azure DevOps) and generates an appropriate starter workflow for build, test, and pack.

## Platform Detection

Detect the CI platform from existing repo indicators:

| Indicator | Platform |
|-----------|----------|
| `.github/` directory exists | GitHub Actions |
| `azure-pipelines.yml` exists | Azure DevOps |
| `.github/workflows/` has YAML files | GitHub Actions (already configured) |
| Neither | Ask the user which platform to target |

---

## GitHub Actions Starter Workflow

Create `.github/workflows/build.yml`:

```yaml
name: Build and Test

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

permissions:
  contents: read

env:
  DOTNET_NOLOGO: true
  DOTNET_CLI_TELEMETRY_OPTOUT: true
  DOTNET_SKIP_FIRST_TIME_EXPERIENCE: true

jobs:
  build:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - name: Setup .NET
        uses: actions/setup-dotnet@v4
        with:
          global-json-file: global.json

      - name: Restore
        run: dotnet restore --locked-mode

      - name: Build
        run: dotnet build --no-restore -c Release

      - name: Test
        run: dotnet test --no-build -c Release --logger trx --results-directory TestResults

      - name: Upload test results
        uses: actions/upload-artifact@v4
        if: always()
        with:
          name: test-results
          path: TestResults/**/*.trx
```

### Key Decisions Explained

- **`global-json-file`** -- uses the repo's `global.json` to install the exact SDK version. If the project has no `global.json`, replace with `dotnet-version: '10.0.x'` (or the appropriate version)
- **`--locked-mode`** -- ensures `packages.lock.json` files are respected; fails if they're out of date. If the project doesn't use lock files, replace with plain `dotnet restore`
- **`-c Release`** -- builds in Release mode so `ContinuousIntegrationBuild` takes effect
- **`permissions: contents: read`** -- principle of least privilege
- **Environment variables** -- suppress .NET CLI noise in logs

### Adding NuGet Pack (Libraries)

For projects that publish to NuGet, add a pack step:

```yaml
      - name: Pack
        run: dotnet pack --no-build -c Release -o artifacts

      - name: Upload packages
        uses: actions/upload-artifact@v4
        with:
          name: nuget-packages
          path: artifacts/*.nupkg
```

---

## Azure DevOps Starter Pipeline

Create `azure-pipelines.yml` at the repo root:

```yaml
trigger:
  branches:
    include:
      - main

pr:
  branches:
    include:
      - main

pool:
  vmImage: 'ubuntu-latest'

variables:
  DOTNET_NOLOGO: true
  DOTNET_CLI_TELEMETRY_OPTOUT: true
  DOTNET_SKIP_FIRST_TIME_EXPERIENCE: true
  buildConfiguration: 'Release'

steps:
  - task: UseDotNet@2
    displayName: 'Setup .NET SDK'
    inputs:
      useGlobalJson: true

  - script: dotnet restore --locked-mode
    displayName: 'Restore'

  - script: dotnet build --no-restore -c $(buildConfiguration)
    displayName: 'Build'

  - task: DotNetCoreCLI@2
    displayName: 'Test'
    inputs:
      command: 'test'
      arguments: '--no-build -c $(buildConfiguration) --logger trx'
      publishTestResults: true
```

### Adding NuGet Pack (Libraries)

```yaml
  - script: dotnet pack --no-build -c $(buildConfiguration) -o $(Build.ArtifactStagingDirectory)
    displayName: 'Pack'

  - task: PublishBuildArtifacts@1
    displayName: 'Publish NuGet packages'
    inputs:
      pathToPublish: '$(Build.ArtifactStagingDirectory)'
      artifactName: 'nuget-packages'
```

---

## Adapting the Starter Workflow

### Multi-TFM Projects

If the project multi-targets, the default workflow works without changes -- `dotnet build` and `dotnet test` handle all TFMs automatically. No matrix is needed for the starter.

### Windows-Only Projects (MAUI, WPF, WinForms)

Change the runner:

```yaml
# GitHub Actions
runs-on: windows-latest

# Azure DevOps
pool:
  vmImage: 'windows-latest'
```

### Solution Filter

If the repo has multiple solutions or uses solution filters:

```yaml
      - name: Build
        run: dotnet build MyApp.slnf --no-restore -c Release
```

---

## Verification

After adding the workflow, verify locally:

```bash
# GitHub Actions -- validate YAML syntax
# Install: gh extension install moritztomasi/gh-workflow-validator
gh workflow-validator .github/workflows/build.yml

# Or simply verify the build steps work locally
dotnet restore --locked-mode
dotnet build --no-restore -c Release
dotnet test --no-build -c Release
```

Push a branch and open a PR to trigger the workflow.

---

## What's Next

This starter covers build-test-pack. For advanced scenarios, see the CI/CD depth skills:
- Reusable composite actions and workflow templates
- Matrix builds across OS/TFM combinations
- Deployment pipelines with environment gates
- NuGet publishing with signing
- Container image builds
- Code coverage reporting and enforcement

---

## References

- [GitHub Actions for .NET](https://docs.github.com/en/actions/use-cases-and-examples/building-and-testing/building-and-testing-net)
- [Azure Pipelines for .NET](https://learn.microsoft.com/en-us/azure/devops/pipelines/ecosystems/dotnet-core)
- [setup-dotnet Action](https://github.com/actions/setup-dotnet)
- [UseDotNet Task](https://learn.microsoft.com/en-us/azure/devops/pipelines/tasks/reference/use-dotnet-v2)
