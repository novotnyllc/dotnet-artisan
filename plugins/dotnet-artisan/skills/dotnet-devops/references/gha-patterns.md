# GitHub Actions Patterns

Composable GitHub Actions workflow patterns for .NET projects: reusable workflows with `workflow_call`, composite actions for shared step sequences, matrix builds across TFMs and operating systems, path-based triggers, concurrency groups for duplicate run cancellation, environment protection rules, NuGet and SDK caching strategies, and `workflow_dispatch` inputs for manual triggers.

**Version assumptions:** GitHub Actions workflow syntax v2. `actions/setup-dotnet@v4` for .NET 8/9/10 support. `actions/cache@v4` for dependency caching.

## Reusable Workflows (`workflow_call`)

### Defining a Reusable Workflow

Reusable workflows allow callers to invoke an entire workflow as a single step. Define inputs, outputs, and secrets for a clean contract:

```yaml
# .github/workflows/build-reusable.yml
name: Build (Reusable)

on:
  workflow_call:
    inputs:
      dotnet-version:
        description: '.NET SDK version to install'
        required: false
        type: string
        default: '8.0.x'
      configuration:
        description: 'Build configuration'
        required: false
        type: string
        default: 'Release'
      project-path:
        description: 'Path to solution or project file'
        required: true
        type: string
    outputs:
      artifact-name:
        description: 'Name of the uploaded build artifact'
        value: ${{ jobs.build.outputs.artifact-name }}
    secrets:
      NUGET_AUTH_TOKEN:
        description: 'NuGet feed authentication token'
        required: false

jobs:
  build:
    runs-on: ubuntu-latest
    outputs:
      artifact-name: build-${{ github.sha }}
    steps:
      - uses: actions/checkout@v4

      - name: Setup .NET
        uses: actions/setup-dotnet@v4
        with:
          dotnet-version: ${{ inputs.dotnet-version }}

      - name: Restore
        run: dotnet restore ${{ inputs.project-path }}

      - name: Build
        run: dotnet build ${{ inputs.project-path }} -c ${{ inputs.configuration }} --no-restore

      - name: Upload build artifact
        uses: actions/upload-artifact@v4
        with:
          name: build-${{ github.sha }}
          path: |
            **/bin/${{ inputs.configuration }}/**
          retention-days: 7
```

### Calling a Reusable Workflow

```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  build:
    uses: ./.github/workflows/build-reusable.yml
    with:
      dotnet-version: '8.0.x'
      project-path: MyApp.sln
    secrets:
      NUGET_AUTH_TOKEN: ${{ secrets.NUGET_AUTH_TOKEN }}

  test:
    needs: build
    uses: ./.github/workflows/test-reusable.yml
    with:
      dotnet-version: '8.0.x'
      project-path: MyApp.sln
```

### Cross-Repository Reusable Workflows

Reference workflows from other repositories using the full path:

```yaml
jobs:
  build:
    uses: my-org/.github-workflows/.github/workflows/dotnet-build.yml@v1
    with:
      dotnet-version: '9.0.x'
    secrets: inherit  # pass all secrets from caller
```

Use `secrets: inherit` when the reusable workflow needs access to the same secrets as the calling workflow without explicit enumeration.

---

## Composite Actions

### Creating a Composite Action

Composite actions bundle multiple steps into a single reusable action. Use them for shared step sequences that appear across multiple workflows:

```yaml
# .github/actions/dotnet-setup/action.yml
name: 'Setup .NET Environment'
description: 'Install .NET SDK and restore NuGet packages with caching'

inputs:
  dotnet-version:
    description: '.NET SDK version'
    required: false
    default: '8.0.x'
  project-path:
    description: 'Path to solution or project'
    required: true

runs:
  using: 'composite'
  steps:
    - name: Setup .NET SDK
      uses: actions/setup-dotnet@v4
      with:
        dotnet-version: ${{ inputs.dotnet-version }}

    - name: Cache NuGet packages
      uses: actions/cache@v4
      with:
        path: ~/.nuget/packages
        key: nuget-${{ runner.os }}-${{ hashFiles('**/*.csproj', '**/Directory.Packages.props') }}
        restore-keys: |
          nuget-${{ runner.os }}-

    - name: Restore dependencies
      shell: bash
      run: dotnet restore ${{ inputs.project-path }}
```

### Using a Composite Action

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup .NET environment
        uses: ./.github/actions/dotnet-setup
        with:
          dotnet-version: '9.0.x'
          project-path: MyApp.sln

      - name: Build
        run: dotnet build MyApp.sln -c Release --no-restore
```

### Reusable Workflow vs Composite Action

| Feature | Reusable Workflow | Composite Action |
|---------|------------------|-----------------|
| Scope | Entire job with runner | Steps within a job |
| Runner selection | Own `runs-on` | Caller's runner |
| Secrets access | Explicit or `inherit` | Caller's context |
| Outputs | Job-level outputs | Step-level outputs |
| Best for | Complete build/test/deploy jobs | Shared setup/teardown sequences |

---

## Matrix Builds

### Multi-TFM and Multi-OS Matrix

```yaml
jobs:
  test:
    strategy:
      fail-fast: false
      matrix:
        os: [ubuntu-latest, windows-latest, macos-latest]
        dotnet-version: ['8.0.x', '9.0.x']
        include:
          - os: ubuntu-latest
            dotnet-version: '10.0.x'
        exclude:
          - os: macos-latest
            dotnet-version: '8.0.x'
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4

      - name: Setup .NET ${{ matrix.dotnet-version }}
        uses: actions/setup-dotnet@v4
        with:
          dotnet-version: ${{ matrix.dotnet-version }}

      - name: Test
        run: dotnet test --framework net${{ matrix.dotnet-version == '8.0.x' && '8.0' || matrix.dotnet-version == '9.0.x' && '9.0' || '10.0' }}
```

**Key decisions:**

- `fail-fast: false` ensures all matrix combinations run even if one fails, giving full signal on which platforms/TFMs are broken
- `include` adds specific combinations not in the Cartesian product
- `exclude` removes combinations that are unnecessary or unsupported

### Dynamic Matrix from JSON

Generate matrix values dynamically for complex scenarios:

```yaml
jobs:
  compute-matrix:
    runs-on: ubuntu-latest
    outputs:
      matrix: ${{ steps.set-matrix.outputs.matrix }}
    steps:
      - uses: actions/checkout@v4
      - id: set-matrix
        shell: bash
        run: |
          set -euo pipefail
          # Extract TFMs from Directory.Build.props or csproj files
          TFMS=$(grep -rh '<TargetFrameworks\?>' **/*.csproj | \
            sed 's/.*<TargetFrameworks\?>//' | sed 's/<.*//' | \
            tr ';' '\n' | sort -u | jq -R . | jq -sc .)
          echo "matrix={\"tfm\":$TFMS}" >> "$GITHUB_OUTPUT"

  test:
    needs: compute-matrix
    strategy:
      matrix: ${{ fromJson(needs.compute-matrix.outputs.matrix) }}
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: dotnet test --framework ${{ matrix.tfm }}
```

---

## Path-Based Triggers

### Selective Workflow Execution

Trigger workflows only when relevant files change. Reduces CI cost and feedback time:

```yaml
on:
  push:
    branches: [main]
    paths:
      - 'src/**'
      - 'tests/**'
      - '*.sln'
      - 'Directory.Build.props'
      - 'Directory.Packages.props'
      - '.github/workflows/ci.yml'
  pull_request:
    branches: [main]
    paths:
      - 'src/**'
      - 'tests/**'
      - '*.sln'
      - 'Directory.Build.props'
      - 'Directory.Packages.props'
```

### Ignoring Non-Code Changes

Use `paths-ignore` to skip builds for documentation-only changes:

```yaml
on:
  push:
    branches: [main]
    paths-ignore:
      - 'docs/**'
      - '*.md'
      - 'LICENSE'
      - '.editorconfig'
```

**Choose `paths` or `paths-ignore`, not both.** When both are specified on the same event, `paths-ignore` is ignored. Use `paths` (allowlist) for focused workflows; use `paths-ignore` (denylist) for broad workflows.

---

## Concurrency Groups

### Cancelling Duplicate Runs

Prevent wasted CI time by cancelling in-progress runs when new commits are pushed to the same branch or PR:

```yaml
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true
```

### Environment-Scoped Concurrency

Prevent parallel deployments to the same environment:

```yaml
concurrency:
  group: deploy-production
  cancel-in-progress: false  # queue, do not cancel deployments
```

Use `cancel-in-progress: true` for build/test (newer commit supersedes older), but `cancel-in-progress: false` for deployments (do not cancel an in-progress deploy).

---

## Environment Protection Rules

### Configuring Environments

```yaml
jobs:
  deploy-staging:
    runs-on: ubuntu-latest
    environment:
      name: staging
      url: https://staging.example.com
    steps:
      - name: Deploy to staging
        run: echo "Deploying..."

  deploy-production:
    needs: deploy-staging
    runs-on: ubuntu-latest
    environment:
      name: production
      url: https://example.com
    steps:
      - name: Deploy to production
        run: echo "Deploying..."
```

Configure protection rules in GitHub Settings > Environments:

| Rule | Purpose |
|------|---------|
| Required reviewers | Manual approval before deployment |
| Wait timer | Cooldown period (e.g., 15 minutes) |
| Branch restrictions | Only `main` or `release/*` branches can deploy |
| Custom deployment protection rules | Third-party integrations (monitoring checks) |

### Environment Secrets

Environments can have their own secrets that override repository-level secrets. Use environment-scoped secrets for deployment credentials:

```yaml
jobs:
  deploy:
    environment: production
    runs-on: ubuntu-latest
    steps:
      - name: Deploy
        env:
          # These resolve to environment-specific values
          CONNECTION_STRING: ${{ secrets.CONNECTION_STRING }}
          API_KEY: ${{ secrets.API_KEY }}
        run: ./deploy.sh
```

---

## Caching Strategies

### NuGet Package Cache

```yaml
- name: Cache NuGet packages
  uses: actions/cache@v4
  with:
    path: ~/.nuget/packages
    key: nuget-${{ runner.os }}-${{ hashFiles('**/*.csproj', '**/Directory.Packages.props') }}
    restore-keys: |
      nuget-${{ runner.os }}-
```

The `restore-keys` prefix match ensures a partial cache hit when csproj files change (most packages remain cached).

### .NET SDK Cache

For self-hosted runners or scenarios where SDK installation is slow:

```yaml
- name: Setup .NET with cache
  uses: actions/setup-dotnet@v4
  with:
    dotnet-version: '8.0.x'
    cache: true
    cache-dependency-path: '**/packages.lock.json'
```

The `cache: true` option in `actions/setup-dotnet@v4` enables built-in NuGet caching using `packages.lock.json` as the cache key.

### Build Output Cache (.NET 9+)

.NET 9 introduced MSBuild build-check caching. For incremental CI builds:

```yaml
- name: Cache build output
  uses: actions/cache@v4
  with:
    path: |
      **/bin/
      **/obj/
    key: build-${{ runner.os }}-${{ hashFiles('**/*.csproj', '**/*.cs') }}
    restore-keys: |
      build-${{ runner.os }}-
```

Use build output caching cautiously -- stale caches can mask build errors. Prefer NuGet caching as the primary CI speed optimization.

---

## `workflow_dispatch` Inputs

### Manual Trigger with Parameters

```yaml
on:
  workflow_dispatch:
    inputs:
      environment:
        description: 'Target deployment environment'
        required: true
        type: choice
        options:
          - staging
          - production
        default: staging
      version:
        description: 'Version to deploy (e.g., 1.2.3)'
        required: true
        type: string
      dry-run:
        description: 'Simulate deployment without applying changes'
        required: false
        type: boolean
        default: false

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: ${{ inputs.environment }}
    steps:
      - uses: actions/checkout@v4
        with:
          ref: v${{ inputs.version }}

      - name: Deploy
        env:
          DRY_RUN: ${{ inputs.dry-run }}
        run: |
          set -euo pipefail
          if [ "$DRY_RUN" = "true" ]; then
            echo "DRY RUN: would deploy v${{ inputs.version }} to ${{ inputs.environment }}"
          else
            ./deploy.sh --version ${{ inputs.version }}
          fi
```

Input types: `string`, `boolean`, `choice`, `environment` (selects from configured environments).

---

## Agent Gotchas

1. **Do not mix `paths` and `paths-ignore` on the same event** -- when both are specified, `paths-ignore` is silently ignored. Use one or the other.
2. **Set `fail-fast: false` on matrix builds** -- default `fail-fast: true` cancels sibling jobs when one fails, hiding which other combinations also break.
3. **Use `set -euo pipefail` in all bash steps** -- without `pipefail`, a non-zero exit from a piped command (e.g., `script | tee`) does not fail the step.
4. **Reusable workflow inputs are strings by default** -- boolean and number types must be explicitly declared with `type:` in the workflow_call inputs.
5. **Cache keys must include `runner.os`** -- NuGet packages are OS-dependent; a Linux-built cache restoring on Windows causes restore failures.
6. **Do not hardcode TFMs in workflow files** -- use matrix variables or extract from csproj to keep workflows in sync with project configuration.
7. **`secrets: inherit` passes all caller secrets** -- use explicit secret declarations for security-sensitive reusable workflows to limit exposure.
8. **Concurrency groups for deploys must use `cancel-in-progress: false`** -- cancelling an in-progress deployment can leave infrastructure in an inconsistent state.
