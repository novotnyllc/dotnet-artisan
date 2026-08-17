# ADO Unique Features

Azure DevOps-exclusive features not available in GitHub Actions: Environments with approvals and gates (pre-deployment checks, business hours restrictions), deployment groups vs environments (when to use each), service connections (Azure Resource Manager, Docker Registry, NuGet), classic release pipelines (legacy migration guidance to YAML), variable groups and library (linked to Azure Key Vault), pipeline decorators for organization-wide policy, and Azure Artifacts universal packages.

**Version assumptions:** Azure DevOps Services (cloud). YAML pipelines with multi-stage support. Classic release pipelines for legacy migration context only.

## Environments with Approvals and Gates

### Defining Environments in YAML

Environments are first-class Azure DevOps resources that provide deployment targeting, approval gates, and deployment history:

```yaml
stages:
  - stage: DeployStaging
    jobs:
      - deployment: DeployToStaging
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
    dependsOn: DeployStaging
    jobs:
      - deployment: DeployToProduction
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

Environments are created automatically on first reference. Configure approvals and gates in Azure DevOps > Pipelines > Environments > (select environment) > Approvals and checks.

### Approval Checks

| Check Type | Purpose | Configuration |
|-----------|---------|---------------|
| Approvals | Manual sign-off before deployment | Assign approver users/groups |
| Branch control | Restrict deployments to specific branches | Allow only `main`, `release/*` |
| Business hours | Deploy only during allowed time windows | Define hours and timezone |
| Template validation | Require pipeline to extend a specific template | Specify required template path |
| Invoke Azure Function | Custom validation via Azure Function | Provide function URL and key |
| Invoke REST API | Custom validation via HTTP endpoint | Provide URL and success criteria |
| Required template | Enforce pipeline structure | Specify required extends template |

### Configuring Approval Checks

Approval checks are configured in the Azure DevOps UI, not in YAML. The YAML pipeline references the environment, and the checks are applied:

```yaml
# Pipeline YAML -- environment reference triggers checks
- deployment: DeployToProduction
  environment: 'production'  # checks configured in UI
  strategy:
    runOnce:
      deploy:
        steps:
          - script: echo "This runs only after all checks pass"
```

**Approval configuration (UI):**
- Navigate to Pipelines > Environments > production > Approvals and checks
- Add "Approvals" check: assign individuals or groups
- Set minimum number of approvers (e.g., 2 for production)
- Enable "allow approvers to approve their own runs" only if appropriate

### Business Hours Gate

Restrict deployments to specific time windows to reduce risk:

- Navigate to Pipelines > Environments > production > Approvals and checks
- Add "Business Hours" check
- Configure: Monday-Friday, 09:00-17:00 (team timezone)
- Pipelines will queue and wait until the window opens

### Pre-Deployment Validation with Azure Functions

```yaml
# The environment's "Invoke Azure Function" check calls:
# https://myvalidation.azurewebsites.net/api/pre-deploy
# with the pipeline context as payload.
# Returns 200 to approve, non-200 to reject.

- deployment: DeployToProduction
  environment: 'production'  # Azure Function check configured in UI
  strategy:
    runOnce:
      preDeploy:
        steps:
          - script: echo "Pre-deploy hook (in-pipeline)"
      deploy:
        steps:
          - script: echo "Deploying"
      routeTraffic:
        steps:
          - script: echo "Routing traffic"
      postRouteTraffic:
        steps:
          - script: echo "Post-route validation"
```

The `preDeploy`, `routeTraffic`, and `postRouteTraffic` lifecycle hooks execute within the pipeline. Environment checks (approvals, Azure Function gates) execute before the deployment job starts.

---

## Deployment Groups vs Environments

### When to Use Each

| Feature | Deployment Groups | Environments |
|---------|------------------|--------------|
| Target | Physical/virtual machines with agents | Any target (VMs, Kubernetes, cloud services) |
| Agent model | Self-hosted agents on target machines | Pool agents or target-specific resources |
| Pipeline type | Classic release pipelines (legacy) | YAML multi-stage pipelines (modern) |
| Approvals | Per-stage in classic UI | Checks and approvals on environment |
| Rolling deployment | Built-in rolling strategy | `strategy: rolling` in YAML |
| Recommendation | Legacy workloads only | All new projects |

### Deployment Group Example (Legacy)

Deployment groups install an agent on each target machine. Use only for existing on-premises deployments:

```yaml
# Classic release pipeline (not YAML) -- for reference only
# Deployment groups are configured in Project Settings > Deployment Groups
# Each target server runs the ADO agent registered to the group
```

### Environment with Kubernetes Resource

```yaml
- deployment: DeployToK8s
  environment: 'production.my-k8s-namespace'
  strategy:
    runOnce:
      deploy:
        steps:
          - task: KubernetesManifest@1
            inputs:
              action: 'deploy'
              manifests: 'k8s/*.yml'
              containers: '$(ACR_LOGIN_SERVER)/myapp:$(Build.BuildId)'
```

Environments can target Kubernetes clusters and namespaces. Register the cluster as a resource under the environment in the Azure DevOps UI.

### Migration from Deployment Groups to Environments

1. Create environments matching existing deployment group names
2. Configure the same approval gates in the environment's Approvals and checks
3. Convert classic release pipeline stages to YAML `deployment` jobs targeting the new environments
4. Use `strategy: rolling` for incremental deployments equivalent to deployment group behavior

---

## Service Connections

### Azure Resource Manager (ARM)

Service connections provide authenticated access to external services. ARM connections enable Azure resource deployments:

```yaml
- task: AzureWebApp@1
  displayName: 'Deploy to Azure App Service'
  inputs:
    azureSubscription: 'MyAzureServiceConnection'
    appType: 'webAppLinux'
    appName: 'myapp-staging'
    package: '$(Pipeline.Workspace)/app'
```

**Creating an ARM service connection:**
- Navigate to Project Settings > Service Connections > New service connection > Azure Resource Manager
- Choose "Service principal (automatic)" for automatic credential management
- Select the subscription and resource group scope
- ADO creates an app registration and assigns Contributor role

### Workload Identity Federation (Recommended)

Use workload identity federation for passwordless Azure authentication (no client secret):

- Navigate to Project Settings > Service Connections > New service connection > Azure Resource Manager
- Choose "Workload Identity federation (automatic)"
- This creates a federated credential that trusts Azure DevOps pipeline tokens
- No secret rotation required -- the credential uses short-lived pipeline tokens

### Docker Registry Service Connection

```yaml
- task: Docker@2
  displayName: 'Login to ACR'
  inputs:
    command: 'login'
    containerRegistry: 'MyACRServiceConnection'

- task: Docker@2
  displayName: 'Build and push'
  inputs:
    command: 'buildAndPush'
    containerRegistry: 'MyACRServiceConnection'
    repository: 'myapp'
    dockerfile: 'src/MyApp/Dockerfile'
```

**Creating a Docker registry connection:**
- Project Settings > Service Connections > New service connection > Docker Registry
- For ACR: select "Azure Container Registry" and choose the registry
- For DockerHub: provide username and access token

### NuGet Service Connection

For pushing to external NuGet feeds (e.g., nuget.org):

```yaml
- task: NuGetCommand@2
  displayName: 'Push to nuget.org'
  inputs:
    command: 'push'
    packagesToPush: '$(Pipeline.Workspace)/nupkgs/*.nupkg'
    nuGetFeedType: 'external'
    publishFeedCredentials: 'NuGetOrgServiceConnection'
```

**Creating a NuGet connection:**
- Project Settings > Service Connections > New service connection > NuGet
- Provide the feed URL (`https://api.nuget.org/v3/index.json`) and API key

---

## Classic Release Pipelines (Legacy Migration)

### Why Migrate to YAML

Classic release pipelines use a visual designer and are not stored in source control. Migrate to YAML multi-stage pipelines for:

- **Source control:** Pipeline definitions live alongside code
- **Code review:** Pipeline changes go through PR review
- **Branch-specific pipelines:** YAML pipelines can vary by branch
- **Reusability:** Templates and extends for composable pipelines
- **Modern features:** Environments, deployment strategies, pipeline decorators

### Migration Pattern

**Classic release structure:**
```
Build Pipeline -> Release Pipeline
                    Stage 1: Dev (auto-deploy)
                    Stage 2: Staging (manual approval)
                    Stage 3: Production (scheduled + approval)
```

**Equivalent YAML multi-stage pipeline:**

```yaml
trigger:
  branches:
    include:
      - main

stages:
  - stage: Build
    jobs:
      - job: BuildJob
        pool:
          vmImage: 'ubuntu-latest'
        steps:
          - task: DotNetCoreCLI@2
            inputs:
              command: 'publish'
              projects: 'src/MyApp/MyApp.csproj'
              arguments: '-c Release -o $(Build.ArtifactStagingDirectory)/app'
          - task: PublishPipelineArtifact@1
            inputs:
              targetPath: '$(Build.ArtifactStagingDirectory)/app'
              artifactName: 'app'

  - stage: DeployDev
    dependsOn: Build
    jobs:
      - deployment: DeployDev
        environment: 'development'
        strategy:
          runOnce:
            deploy:
              steps:
                - download: current
                  artifact: app
                - script: echo "Deploy to dev"

  - stage: DeployStaging
    dependsOn: DeployDev
    jobs:
      - deployment: DeployStaging
        environment: 'staging'  # approvals configured in UI
        strategy:
          runOnce:
            deploy:
              steps:
                - download: current
                  artifact: app
                - script: echo "Deploy to staging"

  - stage: DeployProduction
    dependsOn: DeployStaging
    condition: and(succeeded(), eq(variables['Build.SourceBranch'], 'refs/heads/main'))
    jobs:
      - deployment: DeployProduction
        environment: 'production'  # approvals + business hours in UI
        strategy:
          runOnce:
            deploy:
              steps:
                - download: current
                  artifact: app
                - script: echo "Deploy to production"
```

### Migration Checklist

1. **Identify all classic release stages** and map to YAML stages
2. **Convert environment variables** to YAML variable groups or templates
3. **Replace classic approval gates** with environment checks
4. **Convert artifact sources** to `download: current` or pipeline resources
5. **Replace task groups** with YAML step or job templates
6. **Test the YAML pipeline** on a non-production branch before decommissioning the classic release

---

## Variable Groups and Library

### Variable Groups Linked to Azure Key Vault

Variable groups can pull secrets directly from Azure Key Vault at pipeline runtime:

```yaml
variables:
  - group: 'kv-production-secrets'
  - group: 'build-settings'
  - name: buildConfiguration
    value: 'Release'

steps:
  - script: |
      echo "Building with configuration $(buildConfiguration)"
    displayName: 'Build'
    env:
      SQL_CONNECTION: $(sql-connection-string)  # from Key Vault
      API_KEY: $(api-key)                        # from Key Vault
```

**Setting up Key Vault-linked variable groups:**
1. Navigate to Pipelines > Library > Variable Groups > New variable group
2. Enable "Link secrets from an Azure key vault as variables"
3. Select the Azure subscription (service connection) and Key Vault
4. Choose which secrets to include
5. Secrets are fetched at pipeline runtime and available as `$(secret-name)`

### Scoping Variable Groups to Environments

Use conditional variable group references based on pipeline stage:

```yaml
stages:
  - stage: DeployStaging
    variables:
      - group: 'staging-config'
      - group: 'kv-staging-secrets'
    jobs:
      - deployment: Deploy
        environment: 'staging'
        strategy:
          runOnce:
            deploy:
              steps:
                - script: echo "Deploying with staging config"
                  env:
                    CONNECTION_STRING: $(sql-connection-string)

  - stage: DeployProduction
    variables:
      - group: 'production-config'
      - group: 'kv-production-secrets'
    jobs:
      - deployment: Deploy
        environment: 'production'
        strategy:
          runOnce:
            deploy:
              steps:
                - script: echo "Deploying with production config"
                  env:
                    CONNECTION_STRING: $(sql-connection-string)
```

### Secure Files in Library

Store certificates, SSH keys, and other binary secrets in the Pipelines Library:

```yaml
- task: DownloadSecureFile@1
  displayName: 'Download signing certificate'
  name: signingCert
  inputs:
    secureFile: 'code-signing.pfx'

- script: |
    dotnet nuget sign ./nupkgs/*.nupkg \
      --certificate-path $(signingCert.secureFilePath) \
      --certificate-password $(CERT_PASSWORD) \
      --timestamper http://timestamp.digicert.com
  displayName: 'Sign NuGet packages'
```

---

## Pipeline Decorators

Pipeline decorators inject steps into every pipeline in an organization or project without modifying individual pipeline files. They enforce organizational policies:

### Decorator Use Cases

| Use Case | Implementation |
|----------|---------------|
| Mandatory security scanning | Inject credential scanner before every job |
| Compliance audit logging | Inject telemetry step after every job |
| Required code analysis | Inject SonarQube analysis on main branch builds |
| License compliance | Inject dependency license scanner |

### Decorator Definition

Decorators are packaged as Azure DevOps extensions:

```yaml
# vss-extension.json (extension manifest)
{
  "contributions": [
    {
      "id": "required-security-scan",
      "type": "ms.azure-pipelines.pipeline-decorator",
      "targets": ["ms.azure-pipelines-agent-job"],
      "properties": {
        "template": "decorator.yml",
        "targetsExecutionOrder": "PreJob"
      }
    }
  ]
}
```

```yaml
# decorator.yml
steps:
  - task: CredentialScanner@1
    displayName: '[Policy] Credential scan'
    condition: always()
```

### Deployment Limitations

- Decorators require Azure DevOps organization admin permissions to install
- They apply to all pipelines in the organization (or selected projects)
- Pipeline authors cannot override or skip decorator steps
- Decorator steps run under the pipeline's agent pool and service connection context

---

## Azure Artifacts Universal Packages

Universal packages store arbitrary files (binaries, tools, datasets) in Azure Artifacts feeds, not limited to NuGet/npm/Maven formats:

### Publish a Universal Package

```yaml
- task: UniversalPackages@0
  displayName: 'Publish universal package'
  inputs:
    command: 'publish'
    publishDirectory: '$(Build.ArtifactStagingDirectory)/tools'
    feedsToUsePublish: 'internal'
    vstsFeedPublish: 'MyProject/MyFeed'
    vstsFeedPackagePublish: 'my-dotnet-tool'
    versionOption: 'custom'
    versionPublish: '$(Build.BuildNumber)'
    packagePublishDescription: '.NET CLI tool binaries'
```

### Download a Universal Package

```yaml
- task: UniversalPackages@0
  displayName: 'Download universal package'
  inputs:
    command: 'download'
    feedsToUse: 'internal'
    vstsFeed: 'MyProject/MyFeed'
    vstsFeedPackage: 'my-dotnet-tool'
    vstsPackageVersion: '*'
    downloadDirectory: '$(Pipeline.Workspace)/tools'
```

### Use Cases for .NET Projects

- **CLI tool distribution:** Publish self-contained .NET CLI tool binaries for cross-team consumption
- **Build tool caching:** Store custom MSBuild tasks or analyzers used across repositories
- **Test fixture data:** Publish large test datasets that should not be stored in Git
- **AOT binaries:** Distribute pre-built Native AOT binaries for platforms where on-demand compilation is impractical

---

## Agent Gotchas

1. **Environment checks (approvals, gates) are configured in the UI, not YAML** -- the YAML pipeline references the environment name; all checks are managed through the Azure DevOps web UI.
2. **Deployment groups are legacy** -- use environments for all new projects; deployment groups exist only for backward compatibility with classic release pipelines.
3. **Service connection scope matters** -- ARM connections scoped to a resource group cannot deploy to resources outside that group; use subscription-level scope for cross-resource-group deployments.
4. **Workload identity federation is preferred over service principal secrets** -- federated credentials eliminate secret rotation; use automatic federation for new connections.
5. **Key Vault-linked variable groups fetch secrets at runtime** -- template expressions (`${{ }}`) cannot access Key Vault secrets because they resolve at compile time; use runtime expressions (`$()`) instead.
6. **Classic release pipelines are not stored in source control** -- this is a primary motivation for migration; YAML pipelines enable PR review and branch-specific definitions.
7. **Pipeline decorators cannot be bypassed by pipeline authors** -- this is intentional for policy enforcement; test decorator changes in a separate organization or project to avoid breaking all pipelines.
8. **Universal packages have a 4 GiB size limit per file** -- for larger artifacts, split files or use Azure Blob Storage with a SAS token instead.
