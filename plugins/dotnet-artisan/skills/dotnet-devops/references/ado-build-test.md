# ADO Build and Test

.NET build and test pipeline patterns for Azure DevOps: `DotNetCoreCLI@2` task for build, test, and pack operations, NuGet restore with Azure Artifacts feeds using `NuGetAuthenticate@1`, test result publishing with `PublishTestResults@2` for TRX and JUnit formats, code coverage with `PublishCodeCoverageResults@2` for Cobertura and JaCoCo formats, and multi-TFM matrix strategy across net8.0 and net9.0.

**Version assumptions:** `DotNetCoreCLI@2` task (current). `UseDotNet@2` for SDK installation. `NuGetAuthenticate@1` for Azure Artifacts. `PublishTestResults@2` and `PublishCodeCoverageResults@2` for reporting.

## `DotNetCoreCLI@2` Task

### Build

```yaml
steps:
  - task: UseDotNet@2
    displayName: 'Install .NET SDK'
    inputs:
      packageType: 'sdk'
      version: '8.0.x'

  - task: DotNetCoreCLI@2
    displayName: 'Restore'
    inputs:
      command: 'restore'
      projects: 'MyApp.sln'

  - task: DotNetCoreCLI@2
    displayName: 'Build'
    inputs:
      command: 'build'
      projects: 'MyApp.sln'
      arguments: '-c Release --no-restore'
```

### Test

```yaml
- task: DotNetCoreCLI@2
  displayName: 'Run tests'
  inputs:
    command: 'test'
    projects: '**/*Tests.csproj'
    arguments: >-
      -c Release
      --logger "trx;LogFileName=test-results.trx"
      --results-directory $(Build.ArtifactStagingDirectory)/test-results
```

### Pack

```yaml
- task: DotNetCoreCLI@2
  displayName: 'Pack NuGet packages'
  inputs:
    command: 'pack'
    packagesToPack: 'src/**/*.csproj'
    configuration: 'Release'
    outputDir: '$(Build.ArtifactStagingDirectory)/nupkgs'
    nobuild: true
```

### Custom Command

For commands not directly supported by the task (e.g., `dotnet tool install`):

```yaml
- task: DotNetCoreCLI@2
  displayName: 'Install dotnet tools'
  inputs:
    command: 'custom'
    custom: 'tool'
    arguments: 'restore'
```

### Multi-Version SDK Install

Install multiple SDK versions for multi-TFM builds:

```yaml
- task: UseDotNet@2
  displayName: 'Install .NET 8'
  inputs:
    packageType: 'sdk'
    version: '8.0.x'

- task: UseDotNet@2
  displayName: 'Install .NET 9'
  inputs:
    packageType: 'sdk'
    version: '9.0.x'
```

Each `UseDotNet@2` invocation adds the SDK version to PATH. The last installed version becomes the default, but all versions are available via `--framework` targeting.

---

## NuGet Restore with Azure Artifacts Feeds

### `NuGetAuthenticate@1` for Feed Authentication

```yaml
steps:
  - task: NuGetAuthenticate@1
    displayName: 'Authenticate NuGet feeds'

  - task: DotNetCoreCLI@2
    displayName: 'Restore'
    inputs:
      command: 'restore'
      projects: 'MyApp.sln'
      feedsToUse: 'config'
      nugetConfigPath: 'nuget.config'
```

The `NuGetAuthenticate@1` task configures credentials for all Azure Artifacts feeds referenced in `nuget.config`. No explicit PAT or API key is needed -- the task uses the pipeline's identity.

### Selecting Feeds Directly

For simple setups without a `nuget.config`, select feeds directly in the restore task:

```yaml
- task: DotNetCoreCLI@2
  displayName: 'Restore with Azure Artifacts'
  inputs:
    command: 'restore'
    projects: 'MyApp.sln'
    feedsToUse: 'select'
    vstsFeed: 'MyProject/MyFeed'
    includeNuGetOrg: true
```

### Upstream Sources

Azure Artifacts feeds can proxy nuget.org as an upstream source. When configured, a single feed reference provides access to both private packages and public NuGet packages:

```xml
<!-- nuget.config with Azure Artifacts upstream -->
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <clear />
    <add key="MyFeed" value="https://pkgs.dev.azure.com/myorg/_packaging/myfeed/nuget/v3/index.json" />
  </packageSources>
</configuration>
```

With upstream sources enabled on the feed, nuget.org packages are cached in the Azure Artifacts feed, providing a single authenticated source for all packages.

### Cross-Organization Feed Access

For feeds in different Azure DevOps organizations, use a service connection:

```yaml
- task: NuGetAuthenticate@1
  displayName: 'Authenticate external feed'
  inputs:
    nuGetServiceConnections: 'ExternalOrgFeedConnection'

- task: DotNetCoreCLI@2
  displayName: 'Restore'
  inputs:
    command: 'restore'
    projects: 'MyApp.sln'
    feedsToUse: 'config'
    nugetConfigPath: 'nuget.config'
```

---

## Test Result Publishing

### `PublishTestResults@2` with TRX Format

```yaml
- task: DotNetCoreCLI@2
  displayName: 'Run tests'
  inputs:
    command: 'test'
    projects: '**/*Tests.csproj'
    arguments: >-
      -c Release
      --logger "trx;LogFileName=results.trx"
      --results-directory $(Common.TestResultsDirectory)
  continueOnError: true

- task: PublishTestResults@2
  displayName: 'Publish test results'
  condition: always()
  inputs:
    testResultsFormat: 'VSTest'
    testResultsFiles: '$(Common.TestResultsDirectory)/**/*.trx'
    mergeTestResults: true
    testRunTitle: '.NET Unit Tests'
```

**Key decisions:**

- `continueOnError: true` on the test task ensures the publish step always runs, even on test failures
- `condition: always()` on the publish task runs regardless of previous step outcome
- `mergeTestResults: true` combines results from multiple test projects into a single test run
- `testRunTitle` provides a descriptive name in the Azure DevOps Test tab

### JUnit Format

Some third-party test frameworks output JUnit XML. Use the `JUnit` format:

```yaml
- task: PublishTestResults@2
  displayName: 'Publish JUnit results'
  condition: always()
  inputs:
    testResultsFormat: 'JUnit'
    testResultsFiles: '**/junit-results.xml'
    mergeTestResults: true
```

### Test Results with Attachments

Attach screenshots or logs to test results for debugging failed tests:

```yaml
- task: DotNetCoreCLI@2
  displayName: 'Run tests with attachments'
  inputs:
    command: 'test'
    projects: '**/*Tests.csproj'
    arguments: >-
      -c Release
      --logger "trx;LogFileName=results.trx"
      --results-directory $(Common.TestResultsDirectory)
      --collect:"XPlat Code Coverage"
  continueOnError: true

- task: PublishTestResults@2
  displayName: 'Publish test results'
  condition: always()
  inputs:
    testResultsFormat: 'VSTest'
    testResultsFiles: '$(Common.TestResultsDirectory)/**/*.trx'
    mergeTestResults: true
    testRunTitle: '.NET Tests'
    publishRunAttachments: true
```

---

## Code Coverage

### `PublishCodeCoverageResults@2` with Cobertura

```yaml
- task: DotNetCoreCLI@2
  displayName: 'Test with coverage'
  inputs:
    command: 'test'
    projects: '**/*Tests.csproj'
    arguments: >-
      -c Release
      --collect:"XPlat Code Coverage"
      --results-directory $(Agent.TempDirectory)/coverage

- task: PublishCodeCoverageResults@2
  displayName: 'Publish code coverage'
  inputs:
    summaryFileLocation: '$(Agent.TempDirectory)/coverage/**/coverage.cobertura.xml'
```

The `PublishCodeCoverageResults@2` task (v2) auto-generates HTML coverage reports in the Azure DevOps Build Summary tab without requiring `reportgenerator`.

### Coverage with ReportGenerator for Detailed Reports

For custom coverage reports beyond the built-in rendering:

```yaml
- task: DotNetCoreCLI@2
  displayName: 'Test with coverage'
  inputs:
    command: 'test'
    projects: '**/*Tests.csproj'
    arguments: >-
      -c Release
      --collect:"XPlat Code Coverage"
      --results-directory $(Agent.TempDirectory)/coverage

- script: |
    set -euo pipefail
    dotnet tool install -g dotnet-reportgenerator-globaltool
    reportgenerator \
      -reports:$(Agent.TempDirectory)/coverage/**/coverage.cobertura.xml \
      -targetdir:$(Build.ArtifactStagingDirectory)/coverage-report \
      -reporttypes:HtmlInline_AzurePipelines\;Cobertura
  displayName: 'Generate coverage report'

- task: PublishCodeCoverageResults@2
  displayName: 'Publish coverage'
  inputs:
    summaryFileLocation: '$(Build.ArtifactStagingDirectory)/coverage-report/Cobertura.xml'

- task: PublishPipelineArtifact@1
  displayName: 'Upload coverage report'
  inputs:
    targetPath: '$(Build.ArtifactStagingDirectory)/coverage-report'
    artifactName: 'coverage-report'
```

### Coverage Thresholds

Enforce minimum coverage by parsing the Cobertura XML in a script step:

```yaml
- script: |
    set -euo pipefail
    COVERAGE_FILE=$(find $(Agent.TempDirectory)/coverage -name 'coverage.cobertura.xml' | head -1)
    COVERAGE=$(python3 -c "
    import xml.etree.ElementTree as ET
    tree = ET.parse('$COVERAGE_FILE')
    print(float(tree.getroot().attrib['line-rate']) * 100)
    ")
    echo "Line coverage: ${COVERAGE}%"
    if (( $(echo "$COVERAGE < 80" | bc -l) )); then
      echo "##vso[task.logissue type=error]Coverage ${COVERAGE}% is below 80% threshold"
      exit 1
    fi
  displayName: 'Enforce coverage threshold'
```

---

## Multi-TFM Matrix Strategy

### Matrix Build Across TFMs and Operating Systems

```yaml
jobs:
  - job: Test
    strategy:
      matrix:
        Linux_net80:
          vmImage: 'ubuntu-latest'
          tfm: 'net8.0'
          dotnetVersion: '8.0.x'
        Linux_net90:
          vmImage: 'ubuntu-latest'
          tfm: 'net9.0'
          dotnetVersion: '9.0.x'
        Windows_net80:
          vmImage: 'windows-latest'
          tfm: 'net8.0'
          dotnetVersion: '8.0.x'
        Windows_net90:
          vmImage: 'windows-latest'
          tfm: 'net9.0'
          dotnetVersion: '9.0.x'
    pool:
      vmImage: $(vmImage)
    steps:
      - task: UseDotNet@2
        displayName: 'Install .NET $(dotnetVersion)'
        inputs:
          packageType: 'sdk'
          version: $(dotnetVersion)

      - task: DotNetCoreCLI@2
        displayName: 'Test $(tfm) on $(vmImage)'
        inputs:
          command: 'test'
          projects: '**/*Tests.csproj'
          arguments: >-
            -c Release
            --framework $(tfm)
            --logger "trx;LogFileName=$(tfm)-results.trx"
            --results-directory $(Common.TestResultsDirectory)
        continueOnError: true

      - task: PublishTestResults@2
        displayName: 'Publish $(tfm) results'
        condition: always()
        inputs:
          testResultsFormat: 'VSTest'
          testResultsFiles: '$(Common.TestResultsDirectory)/**/*.trx'
          testRunTitle: '$(tfm) on $(vmImage)'
```

### Installing Multiple SDKs for Multi-TFM in a Single Job

When running all TFMs in one job (instead of matrix), install all required SDKs:

```yaml
steps:
  - task: UseDotNet@2
    displayName: 'Install .NET 8'
    inputs:
      packageType: 'sdk'
      version: '8.0.x'

  - task: UseDotNet@2
    displayName: 'Install .NET 9'
    inputs:
      packageType: 'sdk'
      version: '9.0.x'

  - task: DotNetCoreCLI@2
    displayName: 'Test all TFMs'
    inputs:
      command: 'test'
      projects: '**/*Tests.csproj'
      arguments: '-c Release'
```

Without the matching SDK installed, `dotnet test` cannot build for that TFM and fails with `NETSDK1045`.

### Template-Based Matrix for Reusability

```yaml
# templates/jobs/matrix-test.yml
parameters:
  - name: configurations
    type: object
    default:
      - tfm: 'net8.0'
        dotnetVersion: '8.0.x'
      - tfm: 'net9.0'
        dotnetVersion: '9.0.x'

jobs:
  - ${{ each config in parameters.configurations }}:
    - job: Test_${{ replace(config.tfm, '.', '_') }}
      displayName: 'Test ${{ config.tfm }}'
      pool:
        vmImage: 'ubuntu-latest'
      steps:
        - task: UseDotNet@2
          inputs:
            packageType: 'sdk'
            version: ${{ config.dotnetVersion }}

        - task: DotNetCoreCLI@2
          displayName: 'Test ${{ config.tfm }}'
          inputs:
            command: 'test'
            projects: '**/*Tests.csproj'
            arguments: '-c Release --framework ${{ config.tfm }}'
```

---

## Agent Gotchas

1. **Use `set -euo pipefail` in multi-line `script:` steps** -- ADO `script:` tasks on Linux default to `set -e` but do not set `pipefail` or `nounset`; without `pipefail`, a failure in a piped command is silently swallowed.
2. **Use `continueOnError: true` on the test task, not on the result publisher** -- the test task must not fail the pipeline before results are published, but the publisher should reflect the actual test outcome.
3. **Install all required SDK versions for multi-TFM builds** -- `dotnet test` without the matching SDK produces `NETSDK1045`; add a `UseDotNet@2` step for each required version.
4. **`NuGetAuthenticate@1` must precede the restore step** -- authentication tokens are injected into the agent's NuGet config at task execution time; restoring before authentication fails with 401.
5. **Use `feedsToUse: 'config'` with `nuget.config` for complex feed setups** -- `feedsToUse: 'select'` supports only one Azure Artifacts feed; multi-feed scenarios require a `nuget.config` file.
6. **Coverage collection requires `--collect:"XPlat Code Coverage"`** -- the default `dotnet test` does not produce coverage files; the `XPlat Code Coverage` collector is built into the .NET SDK.
7. **`PublishCodeCoverageResults@2` expects Cobertura XML** -- passing TRX or other formats to the coverage publisher produces no output; ensure the collector outputs Cobertura format.
8. **ADO matrix syntax differs from GHA** -- ADO uses named matrix entries with key-value pairs, not arrays; each entry must define all variable names used in the job.
9. **Never hardcode credentials in pipeline YAML** -- use variable groups linked to Azure Key Vault or pipeline-level secret variables; hardcoded secrets are visible in repository history.
