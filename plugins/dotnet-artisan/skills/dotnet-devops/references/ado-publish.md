# ADO Publish

Publishing pipelines for .NET projects in Azure DevOps: NuGet package push to Azure Artifacts and nuget.org, container image build and push to Azure Container Registry (ACR) using `Docker@2`, artifact staging with `PublishBuildArtifacts@1` and `PublishPipelineArtifact@1`, and pipeline artifacts for multi-stage release pipelines.

**Version assumptions:** `DotNetCoreCLI@2` for pack/push operations. `Docker@2` for container image builds. `NuGetCommand@2` for NuGet push to external feeds. `PublishPipelineArtifact@1` (preferred over `PublishBuildArtifacts@1`).

## NuGet Push to Azure Artifacts

### Push with `DotNetCoreCLI@2`

```yaml
trigger:
  tags:
    include:
      - 'v*'

stages:
  - stage: Pack
    jobs:
      - job: PackJob
        pool:
          vmImage: 'ubuntu-latest'
        steps:
          - task: UseDotNet@2
            inputs:
              packageType: 'sdk'
              version: '8.0.x'

          - task: DotNetCoreCLI@2
            displayName: 'Pack'
            inputs:
              command: 'pack'
              packagesToPack: 'src/**/*.csproj'
              configuration: 'Release'
              outputDir: '$(Build.ArtifactStagingDirectory)/nupkgs'
              versioningScheme: 'byEnvVar'
              versionEnvVar: 'PACKAGE_VERSION'
            env:
              PACKAGE_VERSION: $(Build.SourceBranchName)

          - task: PublishPipelineArtifact@1
            displayName: 'Upload NuGet packages'
            inputs:
              targetPath: '$(Build.ArtifactStagingDirectory)/nupkgs'
              artifactName: 'nupkgs'

  - stage: PushToFeed
    dependsOn: Pack
    jobs:
      - job: PushJob
        pool:
          vmImage: 'ubuntu-latest'
        steps:
          - download: current
            artifact: nupkgs

          - task: NuGetAuthenticate@1
            displayName: 'Authenticate NuGet'

          - task: DotNetCoreCLI@2
            displayName: 'Push to Azure Artifacts'
            inputs:
              command: 'push'
              packagesToPush: '$(Pipeline.Workspace)/nupkgs/*.nupkg'
              nuGetFeedType: 'internal'
              publishVstsFeed: 'MyProject/MyFeed'
```

### Version from Git Tag

Extract the version from the triggering Git tag using a script step. `Build.SourceBranch` is a runtime variable, so use a script to parse it rather than compile-time template expressions:

```yaml
steps:
  - script: |
      set -euo pipefail
      if [[ "$(Build.SourceBranch)" == refs/tags/v* ]]; then
        VERSION="${BUILD_SOURCEBRANCH#refs/tags/v}"
      else
        VERSION="0.0.0-ci.$(Build.BuildId)"
      fi
      echo "##vso[task.setvariable variable=packageVersion]$VERSION"
    displayName: 'Extract version from tag'

  - task: DotNetCoreCLI@2
    displayName: 'Pack'
    inputs:
      command: 'pack'
      packagesToPack: 'src/**/*.csproj'
      configuration: 'Release'
      outputDir: '$(Build.ArtifactStagingDirectory)/nupkgs'
      arguments: '-p:Version=$(packageVersion)'
```

---

## NuGet Push to nuget.org

### Push with `NuGetCommand@2`

For pushing to external NuGet feeds (nuget.org), use a service connection:

```yaml
- task: NuGetCommand@2
  displayName: 'Push to nuget.org'
  inputs:
    command: 'push'
    packagesToPush: '$(Pipeline.Workspace)/nupkgs/*.nupkg'
    nuGetFeedType: 'external'
    publishFeedCredentials: 'NuGetOrgServiceConnection'
```

The service connection stores the nuget.org API key securely. Create it in Project Settings > Service Connections > NuGet.

### Conditional Push (Stable vs Pre-Release)

```yaml
- task: NuGetCommand@2
  displayName: 'Push to nuget.org (stable only)'
  condition: and(succeeded(), not(contains(variables['packageVersion'], '-')))
  inputs:
    command: 'push'
    packagesToPush: '$(Pipeline.Workspace)/nupkgs/*.nupkg'
    nuGetFeedType: 'external'
    publishFeedCredentials: 'NuGetOrgServiceConnection'

- task: DotNetCoreCLI@2
  displayName: 'Push to Azure Artifacts (all versions)'
  inputs:
    command: 'push'
    packagesToPush: '$(Pipeline.Workspace)/nupkgs/*.nupkg'
    nuGetFeedType: 'internal'
    publishVstsFeed: 'MyProject/MyFeed'
```

Pre-release versions (containing `-` like `1.2.3-preview.1`) go only to Azure Artifacts; stable versions go to both feeds.

### Skip Duplicate Packages

```yaml
- task: DotNetCoreCLI@2
  displayName: 'Push (skip duplicates)'
  inputs:
    command: 'push'
    packagesToPush: '$(Pipeline.Workspace)/nupkgs/*.nupkg'
    nuGetFeedType: 'internal'
    publishVstsFeed: 'MyProject/MyFeed'
  continueOnError: true  # Azure Artifacts returns 409 for duplicates
```

Azure Artifacts returns HTTP 409 for duplicate package versions. Use `continueOnError: true` for idempotent pipeline reruns, or configure the feed to allow overwriting pre-release versions in Feed Settings.

---

## Container Image Build and Push to ACR

### `Docker@2` Task

Build and push a container image to Azure Container Registry. See [skill:dotnet-devops] `references/containers.md` for Dockerfile authoring guidance:

```yaml
stages:
  - stage: BuildContainer
    jobs:
      - job: DockerBuild
        pool:
          vmImage: 'ubuntu-latest'
        steps:
          - task: Docker@2
            displayName: 'Login to ACR'
            inputs:
              command: 'login'
              containerRegistry: 'MyACRServiceConnection'

          - task: Docker@2
            displayName: 'Build and push'
            inputs:
              command: 'buildAndPush'
              repository: 'myapp'
              containerRegistry: 'MyACRServiceConnection'
              dockerfile: 'src/MyApp/Dockerfile'
              buildContext: '.'
              tags: |
                $(Build.BuildId)
                latest
```

### Tagging Strategy

```yaml
- task: Docker@2
  displayName: 'Build and push with semver tags'
  inputs:
    command: 'buildAndPush'
    repository: 'myapp'
    containerRegistry: 'MyACRServiceConnection'
    dockerfile: 'src/MyApp/Dockerfile'
    buildContext: '.'
    tags: |
      $(packageVersion)
      $(Build.SourceVersion)
      latest
```

Use semantic version tags for release images and commit SHA tags for traceability. The `latest` tag should only be applied to stable releases.

### SDK Container Publish (Dockerfile-Free)

Use .NET SDK container publish for projects without a Dockerfile. See [skill:dotnet-devops] `references/containers.md` for `PublishContainer` MSBuild configuration:

```yaml
- task: Docker@2
  displayName: 'Login to ACR'
  inputs:
    command: 'login'
    containerRegistry: 'MyACRServiceConnection'

- task: UseDotNet@2
  inputs:
    packageType: 'sdk'
    version: '8.0.x'

- script: |
    dotnet publish src/MyApp/MyApp.csproj \
      -c Release \
      -p:PublishProfile=DefaultContainer \
      -p:ContainerRegistry=$(ACR_LOGIN_SERVER) \
      -p:ContainerRepository=myapp \
      -p:ContainerImageTags='"$(packageVersion);latest"'
  displayName: 'Publish container via SDK'
  env:
    ACR_LOGIN_SERVER: $(acrLoginServer)
```

### Native AOT Container Publish

Publish a Native AOT binary as a container image. AOT configuration is owned by [skill:dotnet-tooling]; this shows the CI pipeline step only:

```yaml
- script: |
    dotnet publish src/MyApp/MyApp.csproj \
      -c Release \
      -r linux-x64 \
      -p:PublishAot=true \
      -p:PublishProfile=DefaultContainer \
      -p:ContainerRegistry=$(ACR_LOGIN_SERVER) \
      -p:ContainerRepository=myapp \
      -p:ContainerBaseImage=mcr.microsoft.com/dotnet/runtime-deps:8.0-noble-chiseled \
      -p:ContainerImageTags='"$(packageVersion)"'
  displayName: 'Publish AOT container'
```

The `runtime-deps` base image is sufficient for AOT binaries since they include the runtime.

---

## Artifact Staging

### `PublishPipelineArtifact@1` (Recommended)

Pipeline artifacts are the modern replacement for build artifacts, offering faster upload/download and deduplication:

```yaml
steps:
  - task: DotNetCoreCLI@2
    displayName: 'Publish app'
    inputs:
      command: 'publish'
      projects: 'src/MyApp/MyApp.csproj'
      arguments: '-c Release -o $(Build.ArtifactStagingDirectory)/app'

  - task: PublishPipelineArtifact@1
    displayName: 'Upload app artifact'
    inputs:
      targetPath: '$(Build.ArtifactStagingDirectory)/app'
      artifactName: 'app'

  - task: PublishPipelineArtifact@1
    displayName: 'Upload NuGet packages'
    inputs:
      targetPath: '$(Build.ArtifactStagingDirectory)/nupkgs'
      artifactName: 'nupkgs'
```

### `PublishBuildArtifacts@1` (Legacy)

Use only when integrating with classic release pipelines that require build artifacts:

```yaml
- task: PublishBuildArtifacts@1
  displayName: 'Upload build artifact (legacy)'
  inputs:
    pathToPublish: '$(Build.ArtifactStagingDirectory)/app'
    artifactName: 'app'
    publishLocation: 'Container'
```

### Downloading Artifacts in Downstream Stages

```yaml
stages:
  - stage: Build
    jobs:
      - job: BuildJob
        steps:
          - script: dotnet publish -c Release -o $(Build.ArtifactStagingDirectory)/app
          - task: PublishPipelineArtifact@1
            inputs:
              targetPath: '$(Build.ArtifactStagingDirectory)/app'
              artifactName: 'app'

  - stage: Deploy
    dependsOn: Build
    jobs:
      - deployment: DeployJob
        environment: 'staging'
        strategy:
          runOnce:
            deploy:
              steps:
                - download: current
                  artifact: app
                - script: echo "Deploying from $(Pipeline.Workspace)/app"
```

The `download: current` keyword downloads artifacts from the current pipeline run. Use `download: pipelineName` for artifacts from a different pipeline.

---

## Pipeline Artifacts for Release Pipelines

### Multi-Stage Release with Artifact Promotion

```yaml
trigger:
  tags:
    include:
      - 'v*'

stages:
  - stage: Build
    jobs:
      - job: BuildAndPack
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

          - task: DotNetCoreCLI@2
            displayName: 'Pack'
            inputs:
              command: 'pack'
              packagesToPack: 'src/MyLibrary/MyLibrary.csproj'
              configuration: 'Release'
              outputDir: '$(Build.ArtifactStagingDirectory)/nupkgs'

          - task: PublishPipelineArtifact@1
            displayName: 'Upload app'
            inputs:
              targetPath: '$(Build.ArtifactStagingDirectory)/app'
              artifactName: 'app'

          - task: PublishPipelineArtifact@1
            displayName: 'Upload packages'
            inputs:
              targetPath: '$(Build.ArtifactStagingDirectory)/nupkgs'
              artifactName: 'nupkgs'

  - stage: DeployStaging
    dependsOn: Build
    jobs:
      - deployment: DeployStaging
        environment: 'staging'
        pool:
          vmImage: 'ubuntu-latest'
        strategy:
          runOnce:
            deploy:
              steps:
                - download: current
                  artifact: app
                - script: echo "Deploying to staging from $(Pipeline.Workspace)/app"

  - stage: PublishPackages
    dependsOn: DeployStaging
    jobs:
      - job: PushPackages
        pool:
          vmImage: 'ubuntu-latest'
        steps:
          - download: current
            artifact: nupkgs

          - task: NuGetAuthenticate@1

          - task: NuGetCommand@2
            displayName: 'Push to nuget.org'
            inputs:
              command: 'push'
              packagesToPush: '$(Pipeline.Workspace)/nupkgs/*.nupkg'
              nuGetFeedType: 'external'
              publishFeedCredentials: 'NuGetOrgServiceConnection'

  - stage: DeployProduction
    dependsOn: DeployStaging
    condition: and(succeeded(), eq(variables['Build.SourceBranch'], 'refs/heads/main'))
    jobs:
      - deployment: DeployProduction
        environment: 'production'
        pool:
          vmImage: 'ubuntu-latest'
        strategy:
          runOnce:
            deploy:
              steps:
                - download: current
                  artifact: app
                - script: echo "Deploying to production from $(Pipeline.Workspace)/app"
```

### Cross-Pipeline Artifact Consumption

Consume artifacts from a different pipeline (e.g., a shared build pipeline):

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
  - stage: Deploy
    jobs:
      - deployment: DeployFromBuild
        environment: 'staging'
        strategy:
          runOnce:
            deploy:
              steps:
                - download: buildPipeline
                  artifact: app
                - script: echo "Deploying from $(Pipeline.Workspace)/buildPipeline/app"
```

---

## Agent Gotchas

1. **Use `PublishPipelineArtifact@1` over `PublishBuildArtifacts@1`** -- pipeline artifacts are faster, support deduplication, and work with multi-stage YAML pipelines; build artifacts are legacy and required only for classic release pipelines.
2. **Azure Artifacts returns 409 for duplicate package versions** -- use `continueOnError: true` for idempotent reruns, or handle duplicates in feed settings by allowing pre-release version overwrites.
3. **`NuGetCommand@2` with `external` feed type requires a service connection** -- do not hardcode API keys in pipeline YAML; create a NuGet service connection in Project Settings that stores the key securely.
4. **SDK container publish requires Docker on the agent** -- `dotnet publish` with `PublishProfile=DefaultContainer` needs Docker; hosted `ubuntu-latest` agents include Docker, but self-hosted agents may not.
5. **AOT publish requires matching RID** -- `dotnet publish -r linux-x64` must match the agent OS; do not use `-r win-x64` on a Linux agent.
6. **`download: current` uses `$(Pipeline.Workspace)` not `$(Build.ArtifactStagingDirectory)`** -- artifacts downloaded in deployment jobs are at `$(Pipeline.Workspace)/artifactName`, not the staging directory.
7. **Never hardcode registry credentials in pipeline YAML** -- use Docker service connections for ACR/DockerHub authentication; service connections store credentials securely and rotate independently.
8. **Tag triggers require explicit `tags.include` in the trigger section** -- tags are not included by default CI triggers; add `tags: include: ['v*']` to trigger on version tags.
