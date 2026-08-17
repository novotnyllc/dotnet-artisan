# Test Quality

Test quality analysis for .NET projects. Covers code coverage collection with coverlet, human-readable coverage reports with ReportGenerator, CRAP (Change Risk Anti-Patterns) score analysis to identify undertested complex code, mutation testing with Stryker.NET to evaluate test suite effectiveness, and strategies for detecting and managing flaky tests.

**Version assumptions:** Coverlet 6.x+, ReportGenerator 5.x+, Stryker.NET 4.x+ (.NET 8.0+ baseline). Coverlet supports both the MSBuild integration (`coverlet.msbuild`) and the `coverlet.collector` data collector; examples use `coverlet.collector` as the recommended approach.

## Code Coverage with Coverlet

Coverlet is the standard open-source code coverage library for .NET. It instruments assemblies at build time or via a data collector and produces coverage reports in multiple formats.

### Packages

```xml
<!-- Data collector approach (recommended) -->
<PackageReference Include="coverlet.collector" Version="8.0.0">
  <IncludeAssets>runtime; build; native; contentfiles; analyzers; buildtransitive</IncludeAssets>
  <PrivateAssets>all</PrivateAssets>
</PackageReference>
```

### Collecting Coverage

```bash
# Collect coverage with Cobertura output (default for ReportGenerator)
dotnet test --collect:"XPlat Code Coverage"

# Specify output format explicitly
dotnet test --collect:"XPlat Code Coverage" \
  -- DataCollectionRunSettings.DataCollectors.DataCollector.Configuration.Format=cobertura

# Multiple formats
dotnet test --collect:"XPlat Code Coverage" \
  -- DataCollectionRunSettings.DataCollectors.DataCollector.Configuration.Format=cobertura,opencover
```

Coverage results are written to `TestResults/<guid>/coverage.cobertura.xml` under each test project's output directory.

### Filtering Coverage

Exclude generated code, test projects, or specific namespaces:

```bash
dotnet test --collect:"XPlat Code Coverage" \
  -- DataCollectionRunSettings.DataCollectors.DataCollector.Configuration.Exclude="[*.Tests]*,[*.IntegrationTests]*" \
  DataCollectionRunSettings.DataCollectors.DataCollector.Configuration.ExcludeByAttribute="GeneratedCodeAttribute,ObsoleteAttribute,ExcludeFromCodeCoverageAttribute"
```

Or configure via a `runsettings` file for repeatability:

```xml
<!-- coverlet.runsettings -->
<?xml version="1.0" encoding="utf-8"?>
<RunSettings>
  <DataCollectionRunSettings>
    <DataCollectors>
      <DataCollector friendlyName="XPlat Code Coverage">
        <Configuration>
          <Format>cobertura</Format>
          <Exclude>[*.Tests]*,[*.IntegrationTests]*</Exclude>
          <ExcludeByAttribute>
            GeneratedCodeAttribute,ObsoleteAttribute,ExcludeFromCodeCoverageAttribute
          </ExcludeByAttribute>
          <ExcludeByFile>**/Migrations/**</ExcludeByFile>
          <IncludeTestAssembly>false</IncludeTestAssembly>
        </Configuration>
      </DataCollector>
    </DataCollectors>
  </DataCollectionRunSettings>
</RunSettings>
```

```bash
dotnet test --settings coverlet.runsettings
```

### Merge Coverage from Multiple Test Projects

When a solution has multiple test projects, merge their coverage into a single report:

```bash
# Run all tests, collecting coverage per project
dotnet test --collect:"XPlat Code Coverage"

# Find all coverage files and merge via ReportGenerator (see next section)
```

---

## Coverage Reports with ReportGenerator

ReportGenerator converts raw coverage data (Cobertura, OpenCover) into human-readable HTML reports with line-level highlighting.

### Installation

```bash
# Install as a global tool
dotnet tool install -g dotnet-reportgenerator-globaltool

# Or as a local tool
dotnet tool install dotnet-reportgenerator-globaltool
```

### Generating Reports

```bash
# Single coverage file
reportgenerator \
  -reports:"tests/MyApp.Tests/TestResults/*/coverage.cobertura.xml" \
  -targetdir:"coverage-report" \
  -reporttypes:"Html;TextSummary"

# Multiple test projects (glob pattern merges automatically)
reportgenerator \
  -reports:"**/TestResults/*/coverage.cobertura.xml" \
  -targetdir:"coverage-report" \
  -reporttypes:"Html;Cobertura;TextSummary"
```

### Report Types

| Type | Description | Use Case |
|------|-------------|----------|
| `Html` | Interactive HTML with line highlighting | Local developer review |
| `HtmlInline_AzurePipelines` | HTML optimized for Azure DevOps | CI artifact |
| `Cobertura` | Merged Cobertura XML | Input for other tools |
| `TextSummary` | Plain text summary | CLI/CI output |
| `Badges` | SVG coverage badges | README badges |
| `MarkdownSummaryGithub` | GitHub-flavored markdown | PR comments |

### Example: Full Coverage Pipeline

```bash
#!/bin/bash
# clean previous results
rm -rf coverage-report TestResults

# run tests with coverage
dotnet test --collect:"XPlat Code Coverage" --results-directory TestResults

# generate merged HTML report
reportgenerator \
  -reports:"**/TestResults/*/coverage.cobertura.xml" \
  -targetdir:"coverage-report" \
  -reporttypes:"Html;TextSummary;Badges"

# display summary
cat coverage-report/Summary.txt
```

### Setting Coverage Thresholds

Enforce minimum coverage in CI by parsing the text summary or using a threshold parameter:

```bash
# ReportGenerator does not enforce thresholds directly.
# Parse the summary or use dotnet-coverage (Microsoft) for threshold enforcement.

# Alternative: use coverlet's built-in threshold via MSBuild
dotnet test /p:CollectCoverage=true \
  /p:Threshold=80 \
  /p:ThresholdType=line \
  /p:ThresholdStat=total
```

**Note:** The `/p:Threshold` parameter requires the `coverlet.msbuild` package (not `coverlet.collector`). For `coverlet.collector` workflows, enforce thresholds by parsing the ReportGenerator text summary in your CI script.

---

## CRAP Analysis

CRAP (Change Risk Anti-Patterns) scores identify methods that are both complex and poorly tested. A high CRAP score means the method has high cyclomatic complexity and low code coverage -- a risky combination.

### Formula

```
CRAP(m) = complexity(m)^2 * (1 - coverage(m)/100)^3 + complexity(m)
```

Where:
- `complexity(m)` = cyclomatic complexity of method m
- `coverage(m)` = code coverage percentage of method m (0-100)

### Interpreting CRAP Scores

| CRAP Score | Risk Level | Action |
|------------|------------|--------|
| < 5 | Low | Method is simple or well-tested |
| 5-15 | Moderate | Review -- may need additional tests |
| 15-30 | High | Prioritize: add tests or reduce complexity |
| > 30 | Critical | Refactor and add tests immediately |

### Generating CRAP Reports

ReportGenerator includes CRAP analysis when using OpenCover format as input:

```bash
# Step 1: Collect coverage in OpenCover format
dotnet test --collect:"XPlat Code Coverage" \
  -- DataCollectionRunSettings.DataCollectors.DataCollector.Configuration.Format=opencover

# Step 2: Generate report with risk hotspot analysis
reportgenerator \
  -reports:"**/TestResults/*/coverage.opencover.xml" \
  -targetdir:"coverage-report" \
  -reporttypes:"Html;RiskHotspots"
```

The Risk Hotspots report highlights methods sorted by CRAP score, showing:
- Method name and containing class
- Cyclomatic complexity
- Code coverage percentage
- Computed CRAP score

### Using CRAP Scores Effectively

```csharp
// Example: a method with high complexity and low coverage
// Cyclomatic complexity: 12, Coverage: 20%
// CRAP = 12^2 * (1 - 0.20)^3 + 12 = 144 * 0.512 + 12 = 85.7 (Critical)
public decimal CalculateShipping(Order order)
{
    if (order.Items.Count == 0) return 0;

    decimal baseRate = order.DestinationCountry switch
    {
        "US" => 5.99m,
        "CA" => 9.99m,
        "UK" => 12.99m,
        _ => 19.99m
    };

    if (order.Total > 100) baseRate *= 0.5m;
    if (order.IsPriority) baseRate *= 2.0m;
    if (order.Items.Any(i => i.IsFragile)) baseRate += 4.99m;
    if (order.Items.Any(i => i.IsOversized)) baseRate += 14.99m;
    if (order.HasInsurance) baseRate += order.Total * 0.02m;
    if (order.IsExpedited && order.DestinationCountry != "US") baseRate *= 1.5m;

    return Math.Round(baseRate, 2);
}
```

Address high CRAP scores by:
1. **Adding targeted tests** for uncovered branches to reduce the score via higher coverage
2. **Reducing complexity** by extracting methods (e.g., separate `CalculateBaseRate` and `ApplySurcharges` methods)
3. **Both** -- the most effective approach combines better coverage with simpler methods

---

## Mutation Testing with Stryker.NET

Mutation testing evaluates test suite quality by introducing small changes (mutations) to production code and checking whether tests detect them. If a mutation survives (tests still pass), the test suite has a gap.

### Installation

```bash
# Install as a global tool
dotnet tool install -g dotnet-stryker

# Or as a local tool (recommended for team consistency)
dotnet tool install dotnet-stryker
```

### Running Stryker.NET

```bash
# From the test project directory
cd tests/MyApp.Tests
dotnet stryker

# Specify the source project explicitly
dotnet stryker --project MyApp.csproj

# Target specific files
dotnet stryker --mutate "src/Services/**/*.cs"
```

### Configuration File

Create `stryker-config.json` in the test project directory:

```json
{
  "$schema": "https://raw.githubusercontent.com/stryker-mutator/stryker-net/master/src/Stryker.Core/Stryker.Core/stryker-config.schema.json",
  "stryker-config": {
    "project": "MyApp.csproj",
    "reporters": ["html", "progress", "cleartext"],
    "mutation-level": "Standard",
    "thresholds": {
      "high": 80,
      "low": 60,
      "break": 50
    },
    "mutate": [
      "src/Services/**/*.cs",
      "!src/Services/Migrations/**/*.cs"
    ],
    "ignore-mutations": [
      "string",
      "linq"
    ]
  }
}
```

### Understanding Mutation Results

Stryker reports mutations in four categories:

| Status | Meaning | Action |
|--------|---------|--------|
| **Killed** | A test detected the mutation (failed) | Good -- test suite caught the defect |
| **Survived** | No test detected the mutation (all passed) | Gap -- add or strengthen tests |
| **No Coverage** | No test covers the mutated code | Gap -- add tests for this code |
| **Timeout** | Mutation caused an infinite loop or timeout | Usually killed (counts as detected) |

### Mutation Score

```
Mutation Score = Killed / (Killed + Survived + NoCoverage) * 100
```

A mutation score of 80%+ indicates a strong test suite. Below 60% suggests significant gaps.

### Example: Identifying Test Gaps

Given this production code:

```csharp
public class PricingService
{
    public decimal CalculateDiscount(decimal price, CustomerTier tier) =>
        tier switch
        {
            CustomerTier.Bronze => price * 0.05m,
            CustomerTier.Silver => price * 0.10m,
            CustomerTier.Gold => price * 0.15m,
            CustomerTier.Platinum => price * 0.20m,
            _ => 0m
        };
}
```

If tests only verify `Gold` tier, Stryker generates mutations like:
- Replace `0.05m` with `0.06m` (survived -- no Bronze test)
- Replace `0.10m` with `0.11m` (survived -- no Silver test)
- Replace `0.15m` with `0.16m` (killed -- Gold test catches this)
- Replace `0.20m` with `0.21m` (survived -- no Platinum test)
- Replace `0m` with `1m` (survived -- no default test)

The HTML report highlights each surviving mutation with the exact code change, guiding where to add tests.

### Stryker Thresholds

```json
{
  "thresholds": {
    "high": 80,   // Green: mutation score >= 80%
    "low": 60,    // Yellow: 60% <= mutation score < 80%
    "break": 50   // Red: mutation score < 50% -> exit code 1
  }
}
```

The `break` threshold causes Stryker to return a non-zero exit code, useful for CI gates.

---

## Flaky Test Detection

Flaky tests pass and fail intermittently without code changes. They erode trust in the test suite and slow development.

### Common Causes

| Cause | Symptom | Fix |
|-------|---------|-----|
| **Shared mutable state** | Tests fail when run in specific order | Use proper test isolation (see [skill:dotnet-testing] `references/xunit.md` for fixtures) |
| **Time-dependent logic** | Tests fail near midnight or at specific times | Inject `TimeProvider` (or `ISystemClock`) instead of using `DateTime.Now` |
| **Race conditions** | Tests fail intermittently under parallel execution | Use `ICollectionFixture` for shared resources; avoid shared static state |
| **External dependencies** | Tests fail when network/services unavailable | Mock external calls; use Testcontainers for infrastructure |
| **Port conflicts** | Tests fail when another process uses the same port | Use dynamic port allocation (WebApplicationFactory handles this) |
| **File system contention** | Tests fail under parallel execution | Use unique temp directories per test (see [skill:dotnet-testing] `references/xunit.md` `IAsyncLifetime` patterns) |

### Detecting Flaky Tests

#### Repeated Runs

```bash
# Run tests multiple times to surface flakiness
for i in $(seq 1 10); do
  dotnet test --logger "trx;LogFileName=run-$i.trx" || echo "Run $i failed"
done
```

#### xUnit Conditional Skip

**xUnit v3** has built-in conditional skip via `Skip` on `[Fact]`:

```csharp
// xUnit v3 — built-in conditional skip
[Fact(Skip = "Requires external service")]
public async Task ExternalApi_ReturnsData()
{
    var result = await _client.GetDataAsync();
    Assert.NotEmpty(result);
}

// xUnit v3 — runtime skip via Assert.Skip
[Fact]
public async Task ExternalApi_ReturnsData()
{
    if (!await IsServiceAvailable())
        Assert.Skip("External service unavailable");

    var result = await _client.GetDataAsync();
    Assert.NotEmpty(result);
}
```

### Time-Dependent Tests

Replace `DateTime.Now`/`DateTime.UtcNow` with .NET 8's `TimeProvider`:

```csharp
// Production code
public class SubscriptionService(TimeProvider timeProvider)
{
    public bool IsExpired(Subscription sub)
    {
        var now = timeProvider.GetUtcNow();
        return sub.ExpiresAt < now;
    }
}

// Test code
[Fact]
public void IsExpired_PastExpiry_ReturnsTrue()
{
    var fakeTime = new FakeTimeProvider(
        new DateTimeOffset(2025, 6, 15, 0, 0, 0, TimeSpan.Zero));

    var service = new SubscriptionService(fakeTime);
    var sub = new Subscription
    {
        ExpiresAt = new DateTimeOffset(2025, 6, 14, 0, 0, 0, TimeSpan.Zero)
    };

    Assert.True(service.IsExpired(sub));
}

[Fact]
public void IsExpired_FutureExpiry_ReturnsFalse()
{
    var fakeTime = new FakeTimeProvider(
        new DateTimeOffset(2025, 6, 15, 0, 0, 0, TimeSpan.Zero));

    var service = new SubscriptionService(fakeTime);
    var sub = new Subscription
    {
        ExpiresAt = new DateTimeOffset(2025, 6, 16, 0, 0, 0, TimeSpan.Zero)
    };

    Assert.False(service.IsExpired(sub));
}
```

**Note:** `FakeTimeProvider` is available in `Microsoft.Extensions.TimeProvider.Testing` (NuGet).

### Quarantine Strategy

When a flaky test cannot be fixed immediately:

```csharp
// Mark as skipped with a tracking issue
[Fact(Skip = "Flaky: tracking in #1234 -- race condition in event handler")]
public async Task EventHandler_ConcurrentEvents_ProcessesAll()
{
    // ...
}
```

Do not delete flaky tests. Skip them with an issue reference and fix them systematically.

---

## Key Principles

- **Coverage is a lagging indicator, not a target.** High coverage does not guarantee good tests. A test suite with 90% coverage can still miss critical bugs if the assertions are weak.
- **Use CRAP scores to prioritize.** Focus testing effort on methods with high complexity and low coverage rather than chasing overall coverage percentage.
- **Run mutation testing on critical paths.** Mutation testing is computationally expensive. Focus on business-critical code (pricing, authentication, data validation) rather than running it on the entire codebase.
- **Fix flaky tests immediately or quarantine them.** A flaky test that remains in the suite trains developers to ignore failures, undermining the entire test suite's value.
- **Measure trends, not snapshots.** Track coverage and mutation scores over time. A declining trend indicates test quality erosion even if absolute numbers look acceptable.
- **Exclude generated code from coverage.** Migrations, generated clients, and scaffolded code inflate or deflate coverage numbers without reflecting actual test quality.

---

## Agent Gotchas

1. **Do not confuse `coverlet.collector` with `coverlet.msbuild`.** The `coverlet.collector` package uses the `--collect:"XPlat Code Coverage"` CLI flag. The `coverlet.msbuild` package uses `/p:CollectCoverage=true` MSBuild properties. Do not mix flags across packages -- they are independent integration points.
2. **Do not hardcode coverage result paths.** The GUID in `TestResults/<guid>/coverage.cobertura.xml` changes every run. Always use glob patterns (`**/TestResults/*/coverage.cobertura.xml`) when referencing coverage output files.
3. **Do not set coverage thresholds too high initially.** Starting with 90%+ thresholds on an existing project blocks all PRs. Begin with the current baseline and increase incrementally (e.g., 5% per quarter).
4. **Do not run Stryker.NET on the entire solution for CI.** Mutation testing is CPU-intensive. In CI, limit mutations to changed files (`--since:main`) or critical paths. Reserve full runs for nightly builds.
5. **Do not ignore survived mutations in trivial code.** While some survived mutations are in code that does not warrant testing (logging, `ToString()`), review each one. Configure `ignore-mutations` in `stryker-config.json` for categories you have consciously decided not to test.
6. **Do not use `[ExcludeFromCodeCoverage]` as a blanket fix for low coverage.** This attribute hides the problem rather than solving it. Use it only for genuinely untestable code (platform interop, generated code) and ensure the reason is documented.

---

## References

- [Coverlet GitHub repository](https://github.com/coverlet-coverage/coverlet)
- [ReportGenerator GitHub repository](https://github.com/danielpalme/ReportGenerator)
- [ReportGenerator usage guide](https://github.com/danielpalme/ReportGenerator/wiki)
- [Stryker.NET documentation](https://stryker-mutator.io/docs/stryker-net/introduction/)
- [Stryker.NET configuration](https://stryker-mutator.io/docs/stryker-net/configuration/)
- [TimeProvider in .NET 8](https://learn.microsoft.com/en-us/dotnet/api/system.timeprovider)
- [Microsoft.Extensions.TimeProvider.Testing](https://www.nuget.org/packages/Microsoft.Extensions.TimeProvider.Testing)
- [CRAP metric explanation](https://testing.googleblog.com/2011/02/this-code-is-crap.html)
