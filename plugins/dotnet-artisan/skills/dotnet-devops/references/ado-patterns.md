# ADO Patterns

Composable Azure DevOps YAML pipeline patterns for .NET projects: template references with `extends`, `stages`, `jobs`, and `steps` keywords for hierarchical pipeline composition, variable groups and variable templates for centralized configuration, conditional insertion with `${{ if }}` and `${{ each }}` expressions, multi-stage pipelines (build, test, deploy), and pipeline triggers for CI, PR, and scheduled runs.

**Version assumptions:** Azure Pipelines YAML schema. `DotNetCoreCLI@2` task for .NET 8/9/10 builds. Template expressions syntax v2.

## Template Composition

### Step Template (reusable steps inserted into a job)

```yaml
# templates/steps/dotnet-setup.yml
parameters:
  - name: dotnetVersion
    type: string
    default: '8.0.x'
  - name: nugetFeed
    type: string
    default: ''

steps:
  - task: UseDotNet@2
    displayName: 'Install .NET SDK ${{ parameters.dotnetVersion }}'
    inputs:
      packageType: 'sdk'
      version: ${{ parameters.dotnetVersion }}

  - ${{ if ne(parameters.nugetFeed, '') }}:
    - task: NuGetAuthenticate@1
```

### Extends Template (enforced pipeline structure)

```yaml
# templates/pipeline-policy.yml -- callers cannot bypass this structure
parameters:
  - name: stages
    type: stageList
    default: []

stages:
  - stage: SecurityScan
    jobs:
      - job: Scan
        steps:
          - script: echo "Running mandatory security scan"

  - ${{ each stage in parameters.stages }}:
    - ${{ stage }}
```

```yaml
# azure-pipelines.yml (caller)
extends:
  template: templates/pipeline-policy.yml
  parameters:
    stages:
      - stage: Build
        jobs:
          - job: BuildApp
            steps:
              - script: dotnet build -c Release
```

---

## Variable Groups and Templates

```yaml
# templates/variables/dotnet-defaults.yml
variables:
  dotnetVersion: '8.0.x'
  buildConfiguration: 'Release'

# azure-pipelines.yml
variables:
  - template: templates/variables/dotnet-defaults.yml
  - group: 'kv-production-secrets'   # Key Vault-linked for secrets
  - name: projectPath
    value: 'MyApp.sln'
```

Key Vault secrets resolve at runtime via `$(secret-name)`, not template expressions `${{ }}`.

---

## Pipeline Decorators

Decorators inject steps into every pipeline in an organization, enforcing policies without modifying individual pipeline files. They are defined via ADO extensions (not YAML) and cannot be overridden by callers. Debug by inspecting the expanded pipeline YAML in ADO run logs. See [skill:dotnet-devops] `references/ado-unique.md` for implementation details including extension manifests and deployment.

---

## Conditional Insertion

```yaml
parameters:
  - name: environments
    type: object
    default:
      - name: staging
        approvals: false
      - name: production
        approvals: true

stages:
  - ${{ each env in parameters.environments }}:
    - stage: Deploy_${{ env.name }}
      jobs:
        - ${{ if eq(env.approvals, true) }}:
          - job: Approve
            pool: server
            steps:
              - task: ManualValidation@0
        - deployment: DeployApp
          environment: ${{ env.name }}
          strategy:
            runOnce:
              deploy:
                steps:
                  - script: echo "Deploying to ${{ env.name }}"
```

---

## Triggers

```yaml
# CI trigger
trigger:
  branches:
    include: [main, release/*]
  paths:
    include: [src/**, tests/**]
    exclude: [docs/**, '*.md']

# PR trigger
pr:
  branches:
    include: [main]
  drafts: false

# Scheduled trigger
schedules:
  - cron: '0 6 * * 1-5'
    branches:
      include: [main]
    always: false   # only run if changes since last

# Pipeline resource trigger (downstream of another pipeline)
resources:
  pipelines:
    - pipeline: buildPipeline
      source: 'MyApp-Build'
      trigger:
        branches:
          include: [main]
```

---

## Agent Gotchas

1. **Template parameter types are enforced at compile time** -- passing a string where `type: boolean` is expected causes a validation error before the pipeline runs.
2. **`extends` templates cannot be overridden** -- callers cannot inject steps before or after mandatory stages.
3. **Variable group secrets are not available in template expressions** -- `${{ variables.mySecret }}` resolves at compile time when secrets are not yet available; use `$(mySecret)` runtime syntax.
4. **`${{ each }}` iterates at compile time** -- runtime variables cannot be used as the iteration source.
5. **Omitting both `trigger` and `pr` enables default CI triggering on all branches** -- explicitly set `trigger: none` to disable.
6. **Path filters use repository root-relative paths** -- use `src/**` not `./src/**`.
7. **Scheduled triggers always run on the default branch first** -- `branches.include` applies after the schedule fires.
8. **Pipeline resource triggers require the source pipeline name** -- use the ADO pipeline name, not the YAML file path.

---

## Detailed Examples

Extended YAML pipeline examples for template references, variable groups, conditional insertion, multi-stage pipelines, and triggers.

---

### Template References

#### Stage Templates

Stage templates define reusable pipeline stages that callers insert into their multi-stage pipeline:

```yaml
# templates/stages/build-test.yml
parameters:
  - name: dotnetVersion
    type: string
    default: '8.0.x'
  - name: buildConfiguration
    type: string
    default: 'Release'
  - name: projects
    type: string
    default: '**/*.sln'

stages:
  - stage: Build
    displayName: 'Build and Test'
    jobs:
      - job: BuildJob
        pool:
          vmImage: 'ubuntu-latest'
        steps:
          - task: UseDotNet@2
            displayName: 'Install .NET SDK'
            inputs:
              packageType: 'sdk'
              version: ${{ parameters.dotnetVersion }}

          - task: DotNetCoreCLI@2
            displayName: 'Restore'
            inputs:
              command: 'restore'
              projects: ${{ parameters.projects }}

          - task: DotNetCoreCLI@2
            displayName: 'Build'
            inputs:
              command: 'build'
              projects: ${{ parameters.projects }}
              arguments: '-c ${{ parameters.buildConfiguration }} --no-restore'
```

#### Calling a Stage Template

```yaml
# azure-pipelines.yml
trigger:
  branches:
    include:
      - main

stages:
  - template: templates/stages/build-test.yml
    parameters:
      dotnetVersion: '9.0.x'
      buildConfiguration: 'Release'
      projects: 'MyApp.sln'

  - template: templates/stages/deploy.yml
    parameters:
      environment: 'staging'
```

#### Job Templates

Job templates encapsulate a complete job with its pool and steps:

```yaml
# templates/jobs/dotnet-build.yml
parameters:
  - name: dotnetVersion
    type: string
    default: '8.0.x'
  - name: projects
    type: string

jobs:
  - job: Build
    pool:
      vmImage: 'ubuntu-latest'
    steps:
      - task: UseDotNet@2
        inputs:
          packageType: 'sdk'
          version: ${{ parameters.dotnetVersion }}

      - task: DotNetCoreCLI@2
        displayName: 'Build'
        inputs:
          command: 'build'
          projects: ${{ parameters.projects }}
          arguments: '-c Release'
```

#### Step Templates

Step templates define reusable step sequences inserted into an existing job:

```yaml
# templates/steps/dotnet-setup.yml
parameters:
  - name: dotnetVersion
    type: string
    default: '8.0.x'
  - name: nugetFeed
    type: string
    default: ''

steps:
  - task: UseDotNet@2
    displayName: 'Install .NET SDK ${{ parameters.dotnetVersion }}'
    inputs:
      packageType: 'sdk'
      version: ${{ parameters.dotnetVersion }}

  - ${{ if ne(parameters.nugetFeed, '') }}:
    - task: NuGetAuthenticate@1
      displayName: 'Authenticate NuGet feed'

  - task: DotNetCoreCLI@2
    displayName: 'Restore packages'
    inputs:
      command: 'restore'
      projects: '**/*.sln'
      ${{ if ne(parameters.nugetFeed, '') }}:
        feedsToUse: 'select'
        vstsFeed: ${{ parameters.nugetFeed }}
```

#### Using Step Templates in a Pipeline

```yaml
jobs:
  - job: Build
    pool:
      vmImage: 'ubuntu-latest'
    steps:
      - checkout: self

      - template: templates/steps/dotnet-setup.yml
        parameters:
          dotnetVersion: '9.0.x'
          nugetFeed: 'MyOrg/MyFeed'

      - task: DotNetCoreCLI@2
        displayName: 'Build'
        inputs:
          command: 'build'
          arguments: '-c Release --no-restore'
```

#### Extends Templates (Enforced Pipeline Structure)

The `extends` keyword enforces a required pipeline structure defined by an organization template. Callers cannot bypass the structure:

```yaml
# templates/pipeline-policy.yml
parameters:
  - name: stages
    type: stageList
    default: []

stages:
  - stage: SecurityScan
    displayName: 'Security Scan (Required)'
    jobs:
      - job: Scan
        pool:
          vmImage: 'ubuntu-latest'
        steps:
          - script: echo "Running mandatory security scan"

  - ${{ each stage in parameters.stages }}:
    - ${{ stage }}

  - stage: Compliance
    displayName: 'Compliance Check (Required)'
    dependsOn:
      - ${{ each stage in parameters.stages }}:
        - ${{ stage.stage }}
    jobs:
      - job: Check
        pool:
          vmImage: 'ubuntu-latest'
        steps:
          - script: echo "Running compliance checks"
```

```yaml
# azure-pipelines.yml (caller)
extends:
  template: templates/pipeline-policy.yml
  parameters:
    stages:
      - stage: Build
        jobs:
          - job: BuildApp
            pool:
              vmImage: 'ubuntu-latest'
            steps:
              - script: dotnet build -c Release
```

The `extends` template wraps caller-defined stages with mandatory security and compliance stages that cannot be removed.

---

### Variable Groups and Variable Templates

#### Variable Groups

Variable groups centralize configuration shared across multiple pipelines. Link them from Azure Pipelines Library:

```yaml
variables:
  - group: 'dotnet-build-settings'
  - group: 'nuget-feed-credentials'
  - name: buildConfiguration
    value: 'Release'
```

#### Variable Templates

Variable templates define reusable variable sets in YAML files:

```yaml
# templates/variables/dotnet-defaults.yml
variables:
  dotnetVersion: '8.0.x'
  buildConfiguration: 'Release'
  testResultsDirectory: '$(Build.ArtifactStagingDirectory)/test-results'
  coverageDirectory: '$(Build.ArtifactStagingDirectory)/coverage'
```

```yaml
# azure-pipelines.yml
variables:
  - template: templates/variables/dotnet-defaults.yml
  - name: projectPath
    value: 'MyApp.sln'
```

#### Variable Group with Key Vault Integration

Link variable groups to Azure Key Vault for secret management. Secrets are fetched at pipeline runtime:

```yaml
# Reference in pipeline
variables:
  - group: 'kv-production-secrets'  # linked to Azure Key Vault
  - name: nonSecretVar
    value: 'some-value'

steps:
  - script: |
      echo "Using secret from Key Vault"
      # $(sql-connection-string) resolves at runtime from Key Vault
    env:
      CONNECTION_STRING: $(sql-connection-string)
```

Key Vault-linked variable groups require a service connection with Key Vault access. Secret names in Key Vault map to variable names (hyphens become valid variable characters).

---

### Pipeline Decorators

Pipeline decorators inject steps into every pipeline in an organization or project, enforcing policies without modifying individual pipeline files. Decorators are an ADO-exclusive feature with no GitHub Actions equivalent -- see [skill:dotnet-devops] `references/ado-unique.md` for implementation details including extension manifests, deployment guidance, and use case examples.

---

### Conditional Insertion

#### `${{ if }}` Expressions

```yaml
parameters:
  - name: runIntegrationTests
    type: boolean
    default: false
  - name: targetEnvironment
    type: string
    default: 'development'
    values:
      - development
      - staging
      - production

stages:
  - stage: Build
    jobs:
      - job: BuildJob
        steps:
          - script: dotnet build -c Release

  - ${{ if eq(parameters.runIntegrationTests, true) }}:
    - stage: IntegrationTests
      dependsOn: Build
      jobs:
        - job: IntegrationTestJob
          steps:
            - script: dotnet test --filter Category=Integration

  - ${{ if eq(parameters.targetEnvironment, 'production') }}:
    - stage: ApprovalGate
      dependsOn: Build
      jobs:
        - job: WaitForApproval
          pool: server
          steps:
            - task: ManualValidation@0
              inputs:
                notifyUsers: 'release-managers@example.com'
                instructions: 'Approve production deployment'
```

#### `${{ each }}` Iteration

```yaml
parameters:
  - name: environments
    type: object
    default:
      - name: development
        pool: 'ubuntu-latest'
        approvals: false
      - name: staging
        pool: 'ubuntu-latest'
        approvals: true
      - name: production
        pool: 'ubuntu-latest'
        approvals: true

stages:
  - stage: Build
    jobs:
      - job: BuildJob
        steps:
          - script: dotnet build -c Release

  - ${{ each env in parameters.environments }}:
    - stage: Deploy_${{ env.name }}
      displayName: 'Deploy to ${{ env.name }}'
      dependsOn: Build
      jobs:
        - ${{ if eq(env.approvals, true) }}:
          - job: Approve
            pool: server
            steps:
              - task: ManualValidation@0
                inputs:
                  instructions: 'Approve deployment to ${{ env.name }}'

        - deployment: DeployApp
          pool:
            vmImage: ${{ env.pool }}
          environment: ${{ env.name }}
          strategy:
            runOnce:
              deploy:
                steps:
                  - script: echo "Deploying to ${{ env.name }}"
```

#### Conditional Step Insertion Within Templates

```yaml
# templates/steps/dotnet-test.yml
parameters:
  - name: collectCoverage
    type: boolean
    default: false

steps:
  - task: DotNetCoreCLI@2
    displayName: 'Run tests'
    inputs:
      command: 'test'
      projects: '**/*Tests.csproj'
      ${{ if eq(parameters.collectCoverage, true) }}:
        arguments: '-c Release --collect:"XPlat Code Coverage"'
      ${{ else }}:
        arguments: '-c Release'

  - ${{ if eq(parameters.collectCoverage, true) }}:
    - task: PublishCodeCoverageResults@2
      displayName: 'Publish coverage'
      inputs:
        summaryFileLocation: '$(Agent.TempDirectory)/**/coverage.cobertura.xml'
```

---

### Multi-Stage Pipelines

#### Build, Test, Deploy Pattern

```yaml
trigger:
  branches:
    include:
      - main
      - release/*

stages:
  - stage: Build
    displayName: 'Build'
    jobs:
      - job: BuildJob
        pool:
          vmImage: 'ubuntu-latest'
        steps:
          - task: UseDotNet@2
            inputs:
              packageType: 'sdk'
              version: '8.0.x'

          - task: DotNetCoreCLI@2
            displayName: 'Build'
            inputs:
              command: 'build'
              projects: 'MyApp.sln'
              arguments: '-c Release'

          - task: DotNetCoreCLI@2
            displayName: 'Publish'
            inputs:
              command: 'publish'
              projects: 'src/MyApp/MyApp.csproj'
              arguments: '-c Release -o $(Build.ArtifactStagingDirectory)/app'

          - task: PublishPipelineArtifact@1
            displayName: 'Upload artifact'
            inputs:
              targetPath: '$(Build.ArtifactStagingDirectory)/app'
              artifactName: 'app'

  - stage: Test
    displayName: 'Test'
    dependsOn: Build
    jobs:
      - job: UnitTests
        pool:
          vmImage: 'ubuntu-latest'
        steps:
          - task: UseDotNet@2
            inputs:
              packageType: 'sdk'
              version: '8.0.x'

          - task: DotNetCoreCLI@2
            displayName: 'Run tests'
            inputs:
              command: 'test'
              projects: '**/*Tests.csproj'
              arguments: '-c Release --logger "trx;LogFileName=results.trx"'

          - task: PublishTestResults@2
            displayName: 'Publish test results'
            condition: always()
            inputs:
              testResultsFormat: 'VSTest'
              testResultsFiles: '**/results.trx'

  - stage: DeployStaging
    displayName: 'Deploy to Staging'
    dependsOn: Test
    jobs:
      - deployment: DeployStaging
        pool:
          vmImage: 'ubuntu-latest'
        environment: 'staging'
        strategy:
          runOnce:
            deploy:
              steps:
                - download: current
                  artifact: app
                - script: echo "Deploying to staging"

  - stage: DeployProduction
    displayName: 'Deploy to Production'
    dependsOn: DeployStaging
    condition: and(succeeded(), eq(variables['Build.SourceBranch'], 'refs/heads/main'))
    jobs:
      - deployment: DeployProduction
        pool:
          vmImage: 'ubuntu-latest'
        environment: 'production'
        strategy:
          runOnce:
            deploy:
              steps:
                - download: current
                  artifact: app
                - script: echo "Deploying to production"
```

#### Stage Dependencies and Conditions

```yaml
stages:
  - stage: Build
    jobs:
      - job: BuildJob
        steps:
          - script: dotnet build -c Release

  - stage: UnitTests
    dependsOn: Build
    jobs:
      - job: UnitTestJob
        steps:
          - script: dotnet test --filter Category!=Integration

  - stage: IntegrationTests
    dependsOn: Build
    jobs:
      - job: IntegrationTestJob
        steps:
          - script: dotnet test --filter Category=Integration

  # Deploy only if BOTH test stages succeed
  - stage: Deploy
    dependsOn:
      - UnitTests
      - IntegrationTests
    condition: and(succeeded('UnitTests'), succeeded('IntegrationTests'))
    jobs:
      - deployment: DeployApp
        environment: 'production'
        strategy:
          runOnce:
            deploy:
              steps:
                - script: echo "Deploying"
```

---

### Pipeline Triggers

#### CI Triggers

```yaml
trigger:
  branches:
    include:
      - main
      - release/*
    exclude:
      - feature/experimental/*
  paths:
    include:
      - src/**
      - tests/**
      - '*.sln'
      - Directory.Build.props
      - Directory.Packages.props
    exclude:
      - docs/**
      - '*.md'
  tags:
    include:
      - 'v*'
```

#### PR Triggers

```yaml
pr:
  branches:
    include:
      - main
      - release/*
  paths:
    include:
      - src/**
      - tests/**
    exclude:
      - docs/**
  drafts: false  # do not trigger on draft PRs
```

#### Scheduled Triggers

```yaml
schedules:
  - cron: '0 6 * * 1-5'
    displayName: 'Weekday nightly build'
    branches:
      include:
        - main
    always: false  # only run if there are changes since last run

  - cron: '0 0 * * 0'
    displayName: 'Weekly full validation'
    branches:
      include:
        - main
    always: true  # run even without changes
```

#### Pipeline Resource Triggers

Trigger a pipeline when another pipeline completes:

```yaml
resources:
  pipelines:
    - pipeline: buildPipeline
      source: 'MyApp-Build'
      trigger:
        branches:
          include:
            - main

stages:
  - stage: DeployAfterBuild
    jobs:
      - deployment: Deploy
        environment: 'staging'
        strategy:
          runOnce:
            deploy:
              steps:
                - download: buildPipeline
                  artifact: app
                - script: echo "Deploying build from upstream pipeline"
```

---
