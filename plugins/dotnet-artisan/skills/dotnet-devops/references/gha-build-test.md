# GitHub Actions Build and Test

.NET build and test workflow patterns for GitHub Actions: `actions/setup-dotnet@v4` configuration with multi-version installs and NuGet authentication, NuGet restore caching for fast CI, `dotnet test` with result publishing via `dorny/test-reporter`, code coverage upload to Codecov and Coveralls, multi-TFM matrix testing across net8.0 and net9.0, and test sharding strategies for large projects.

**Version assumptions:** `actions/setup-dotnet@v4` for .NET 8/9/10 support. `dorny/test-reporter@v1` for test result visualization. Codecov and Coveralls GitHub Apps for coverage reporting.

## `actions/setup-dotnet@v4` Configuration

### Basic Setup

```yaml
steps:
  - uses: actions/checkout@v4

  - name: Setup .NET
    uses: actions/setup-dotnet@v4
    with:
      dotnet-version: '8.0.x'
```

### Multi-Version Install

Install multiple SDK versions for multi-TFM builds within a single job:

```yaml
- name: Setup .NET SDKs
  uses: actions/setup-dotnet@v4
  with:
    dotnet-version: |
      8.0.x
      9.0.x
```

The first listed version becomes the default `dotnet` on PATH. All installed versions are available via `--framework` targeting.

### NuGet Authentication for Private Feeds

Configure NuGet source authentication via `actions/setup-dotnet@v4`:

```yaml
- name: Setup .NET with NuGet auth
  uses: actions/setup-dotnet@v4
  with:
    dotnet-version: '8.0.x'
    source-url: https://nuget.pkg.github.com/${{ github.repository_owner }}/index.json
  env:
    NUGET_AUTH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

For multiple private feeds, configure additional sources after setup:

```yaml
- name: Setup .NET
  uses: actions/setup-dotnet@v4
  with:
    dotnet-version: '8.0.x'

- name: Add private NuGet feed
  run: |
    set -euo pipefail
    dotnet nuget add source https://pkgs.dev.azure.com/myorg/_packaging/myfeed/nuget/v3/index.json \
      --name AzureArtifacts \
      --username az \
      --password ${{ secrets.AZURE_ARTIFACTS_PAT }} \
      --store-password-in-clear-text
```

The `--store-password-in-clear-text` flag is required on Linux runners where DPAPI encryption is unavailable.

### Global.json SDK Version Pinning

When `global.json` exists in the repository root, `actions/setup-dotnet@v4` can read it automatically:

```yaml
- name: Setup .NET from global.json
  uses: actions/setup-dotnet@v4
  with:
    global-json-file: global.json
```

This ensures CI uses the same SDK version as local development.

---

## NuGet Restore Caching

### Standard Cache Configuration

```yaml
- name: Cache NuGet packages
  uses: actions/cache@v4
  with:
    path: ~/.nuget/packages
    key: nuget-${{ runner.os }}-${{ hashFiles('**/*.csproj', '**/Directory.Packages.props') }}
    restore-keys: |
      nuget-${{ runner.os }}-

- name: Restore dependencies
  run: dotnet restore MySolution.sln
```

### Built-in Cache with setup-dotnet

`actions/setup-dotnet@v4` has built-in caching support using `packages.lock.json`:

```yaml
- name: Setup .NET with caching
  uses: actions/setup-dotnet@v4
  with:
    dotnet-version: '8.0.x'
    cache: true
    cache-dependency-path: '**/packages.lock.json'
```

Generate lock files locally first: `dotnet restore --use-lock-file`. Commit `packages.lock.json` files for deterministic restore.

### Cache Key Strategy

| Key Component | Purpose |
|---------------|---------|
| `runner.os` | Prevent cross-OS cache collisions |
| `hashFiles('**/*.csproj')` | Invalidate when package references change |
| `hashFiles('**/Directory.Packages.props')` | Invalidate when centrally managed versions change |
| `restore-keys` prefix | Partial match for incremental cache reuse |

---

## Test Result Publishing

### dorny/test-reporter

Publish `dotnet test` results as GitHub Actions check annotations with inline failure details:

```yaml
- name: Test
  run: |
    set -euo pipefail
    dotnet test MySolution.sln \
      --configuration Release \
      --logger "trx;LogFileName=test-results.trx" \
      --results-directory ./test-results
  continue-on-error: true
  id: test

- name: Publish test results
  uses: dorny/test-reporter@v1
  if: always()
  with:
    name: '.NET Test Results'
    path: 'test-results/**/*.trx'
    reporter: dotnet-trx
    fail-on-error: true
```

**Key decisions:**

- `continue-on-error: true` on the test step ensures the reporter step always runs, even on failures
- `if: always()` on the reporter step publishes results regardless of test outcome
- `fail-on-error: true` on the reporter marks the check as failed when tests fail

### Alternative: EnricoMi/publish-unit-test-result-action

For richer PR comment integration with test counts:

```yaml
- name: Publish test results
  uses: EnricoMi/publish-unit-test-result-action@v2
  if: always()
  with:
    files: 'test-results/**/*.trx'
    check_name: 'Test Results'
```

---

## Code Coverage Upload

### Codecov

```yaml
- name: Test with coverage
  run: |
    set -euo pipefail
    dotnet test MySolution.sln \
      --configuration Release \
      --collect:"XPlat Code Coverage" \
      --results-directory ./coverage

- name: Upload coverage to Codecov
  uses: codecov/codecov-action@v4
  with:
    directory: ./coverage
    fail_ci_if_error: false
    token: ${{ secrets.CODECOV_TOKEN }}
```

### Coveralls

```yaml
- name: Test with coverage
  run: |
    set -euo pipefail
    dotnet test MySolution.sln \
      --configuration Release \
      --collect:"XPlat Code Coverage" \
      --results-directory ./coverage

- name: Upload coverage to Coveralls
  uses: coverallsapp/github-action@v2
  with:
    file: coverage/**/coverage.cobertura.xml
    format: cobertura
    github-token: ${{ secrets.GITHUB_TOKEN }}
```

### Coverage Report Generation with ReportGenerator

Generate human-readable HTML coverage reports alongside CI upload:

```yaml
- name: Generate coverage report
  run: |
    set -euo pipefail
    dotnet tool install -g dotnet-reportgenerator-globaltool
    reportgenerator \
      -reports:coverage/**/coverage.cobertura.xml \
      -targetdir:coverage-report \
      -reporttypes:HtmlInline_AzurePipelines\;Cobertura

- name: Upload coverage report
  uses: actions/upload-artifact@v4
  with:
    name: coverage-report
    path: coverage-report/
    retention-days: 30
```

---

## Multi-TFM Matrix Testing

### Matrix Strategy for TFMs

```yaml
jobs:
  test:
    strategy:
      fail-fast: false
      matrix:
        tfm: [net8.0, net9.0]
        os: [ubuntu-latest, windows-latest]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4

      - name: Setup .NET
        uses: actions/setup-dotnet@v4
        with:
          dotnet-version: |
            8.0.x
            9.0.x

      - name: Cache NuGet
        uses: actions/cache@v4
        with:
          path: ~/.nuget/packages
          key: nuget-${{ runner.os }}-${{ hashFiles('**/*.csproj', '**/Directory.Packages.props') }}
          restore-keys: |
            nuget-${{ runner.os }}-

      - name: Test ${{ matrix.tfm }}
        run: |
          set -euo pipefail
          dotnet test MySolution.sln \
            --framework ${{ matrix.tfm }} \
            --configuration Release \
            --logger "trx;LogFileName=${{ matrix.tfm }}-results.trx" \
            --results-directory ./test-results

      - name: Publish test results
        uses: dorny/test-reporter@v1
        if: always()
        with:
          name: 'Tests (${{ matrix.os }} / ${{ matrix.tfm }})'
          path: 'test-results/**/*.trx'
          reporter: dotnet-trx
```

### Install All Required SDKs

When running multi-TFM tests in a single job instead of a matrix, install all required SDKs upfront:

```yaml
- name: Setup .NET SDKs
  uses: actions/setup-dotnet@v4
  with:
    dotnet-version: |
      8.0.x
      9.0.x

- name: Test all TFMs
  run: dotnet test MySolution.sln --configuration Release
```

Without the matching SDK installed, `dotnet test` cannot build for that TFM and fails with `NETSDK1045`.

---

## Test Sharding for Large Projects

### Splitting Tests Across Parallel Jobs

For large test suites, split test projects across parallel runners to reduce total CI time:

```yaml
jobs:
  discover:
    runs-on: ubuntu-latest
    outputs:
      projects: ${{ steps.find.outputs.projects }}
    steps:
      - uses: actions/checkout@v4
      - id: find
        shell: bash
        run: |
          set -euo pipefail
          PROJECTS=$(find tests -name '*.csproj' | jq -R . | jq -sc .)
          echo "projects=$PROJECTS" >> "$GITHUB_OUTPUT"

  test:
    needs: discover
    strategy:
      fail-fast: false
      matrix:
        project: ${{ fromJson(needs.discover.outputs.projects) }}
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup .NET
        uses: actions/setup-dotnet@v4
        with:
          dotnet-version: '8.0.x'

      - name: Test ${{ matrix.project }}
        run: |
          set -euo pipefail
          dotnet test ${{ matrix.project }} \
            --configuration Release \
            --logger "trx;LogFileName=results.trx" \
            --results-directory ./test-results

      - name: Publish test results
        uses: dorny/test-reporter@v1
        if: always()
        with:
          name: 'Tests - ${{ matrix.project }}'
          path: 'test-results/**/*.trx'
          reporter: dotnet-trx
```

### Sharding by Test Class Within a Project

For a single large test project, use `dotnet test --filter` to split by namespace:

```yaml
jobs:
  test:
    strategy:
      fail-fast: false
      matrix:
        shard: ['Unit', 'Integration', 'EndToEnd']
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup .NET
        uses: actions/setup-dotnet@v4
        with:
          dotnet-version: '8.0.x'

      - name: Test ${{ matrix.shard }}
        run: |
          set -euo pipefail
          dotnet test tests/MyApp.Tests.csproj \
            --configuration Release \
            --filter "FullyQualifiedName~${{ matrix.shard }}" \
            --logger "trx;LogFileName=${{ matrix.shard }}-results.trx" \
            --results-directory ./test-results
```

---

## Agent Gotchas

1. **Always set `set -euo pipefail` in multi-line bash `run` blocks** -- without `pipefail`, piped commands that fail do not propagate the error, producing false-green CI.
2. **Use `continue-on-error: true` on the test step, not on the reporter** -- the test step must not fail the job prematurely so the reporter can publish results, but the reporter should fail the check when tests fail.
3. **Include `runner.os` in NuGet cache keys** -- NuGet packages have OS-specific native assets; cross-OS cache hits cause restore failures.
4. **Install all required SDK versions for multi-TFM** -- `dotnet test` without the matching SDK produces `NETSDK1045`; list every required version in `dotnet-version`.
5. **Do not hardcode TFM strings in workflow files** -- use matrix variables to keep workflow files in sync with project configuration; hardcoded `net8.0` in CI breaks when the project moves to `net9.0`.
6. **Coverage collection requires `--collect:"XPlat Code Coverage"`** -- the default `dotnet test` does not produce coverage files; the `XPlat Code Coverage` collector is built into the .NET SDK.
7. **TRX logger path must match reporter glob** -- if the logger writes to `test-results/results.trx`, the reporter `path` must include that directory in its glob pattern.
8. **Never commit NuGet credentials to workflow files** -- use `${{ secrets.* }}` references for all authentication tokens; the `NUGET_AUTH_TOKEN` environment variable is the standard pattern.
