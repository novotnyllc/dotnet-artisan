# CI Benchmarking

Continuous benchmarking guidance for detecting performance regressions in CI pipelines. Covers baseline file management with BenchmarkDotNet JSON exporters, GitHub Actions workflows for artifact-based baseline comparison, regression detection patterns with configurable thresholds, and alerting strategies for performance degradation.

**Version assumptions:** BenchmarkDotNet v0.14+ for JSON export, GitHub Actions runner environment. Examples use `actions/upload-artifact@v4` and `actions/download-artifact@v4`.

## Baseline File Management

### BenchmarkDotNet JSON Export

BenchmarkDotNet's JSON exporter produces machine-readable results for automated comparison. Configure the exporter in benchmark classes:

```csharp
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Exporters.Json;

[JsonExporterAttribute.Full]
[MemoryDiagnoser]
public class CriticalPathBenchmarks
{
    [Benchmark(Baseline = true)]
    public void ProcessOrder() { /* ... */ }

    [Benchmark]
    public void ProcessOrderOptimized() { /* ... */ }
}
```

Or configure via custom config for all benchmark classes:

```csharp
using BenchmarkDotNet.Configs;
using BenchmarkDotNet.Exporters.Json;
using BenchmarkDotNet.Jobs;
using BenchmarkDotNet.Running;

var config = ManualConfig.Create(DefaultConfig.Instance)
    .AddJob(Job.ShortRun)  // fewer iterations for CI speed
    .AddExporter(JsonExporter.Full)
    .WithArtifactsPath("./benchmark-results");

BenchmarkSwitcher.FromAssembly(typeof(Program).Assembly).Run(args, config);
```

### JSON Export Structure

The exported JSON file (`*-report-full.json`) contains structured benchmark results:

```json
{
  "Title": "CriticalPathBenchmarks",
  "Benchmarks": [
    {
      "FullName": "MyApp.Benchmarks.CriticalPathBenchmarks.ProcessOrder",
      "Statistics": {
        "Mean": 1234.5678,
        "Median": 1230.1234,
        "StandardDeviation": 15.234,
        "StandardError": 4.812
      },
      "Memory": {
        "BytesAllocatedPerOperation": 1024,
        "Gen0Collections": 0.0012,
        "Gen1Collections": 0,
        "Gen2Collections": 0
      }
    }
  ]
}
```

Key fields for regression comparison:

| Field | Purpose |
|-------|---------|
| `Statistics.Mean` | Average execution time (nanoseconds) |
| `Statistics.Median` | Middle execution time (more robust to outliers) |
| `Statistics.StandardDeviation` | Measurement variability |
| `Memory.BytesAllocatedPerOperation` | GC allocation per operation |

### Baseline Storage Strategies

| Strategy | Pros | Cons | Best For |
|----------|------|------|----------|
| Git-committed baseline file | Versioned, auditable, no external deps | Repo size grows; must update deliberately | Small benchmark suites, stable hardware |
| GitHub Actions artifacts | No repo bloat; automatic retention | 90-day default retention; cross-workflow access requires tokens | Large benchmark suites, shared runners |
| External storage (S3/Azure Blob) | Unlimited history; cross-repo sharing | Extra infrastructure; credential management | Multi-repo benchmark comparison |

This skill focuses on the **GitHub Actions artifact** strategy as the default. For composable workflow patterns and reusable actions, see [skill:dotnet-devops] `references/gha-patterns.md`.

---

## GitHub Actions Benchmark Workflow

### Basic Benchmark Workflow

```yaml
name: Benchmarks

on:
  pull_request:
    paths:
      - 'src/**'
      - 'benchmarks/**'
  workflow_dispatch:

permissions:
  contents: read
  actions: read   # required for artifact download

jobs:
  benchmark:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup .NET
        uses: actions/setup-dotnet@v4
        with:
          dotnet-version: '8.0.x'

      - name: Run benchmarks
        run: dotnet run -c Release --project benchmarks/MyBenchmarks.csproj -- --exporters json

      - name: Upload benchmark results
        uses: actions/upload-artifact@v4
        with:
          name: benchmark-results-${{ github.sha }}
          path: benchmarks/BenchmarkDotNet.Artifacts/results/
          retention-days: 90
```

### Baseline Comparison Workflow

This workflow downloads the baseline from a previous run and compares against current results:

```yaml
name: Benchmark Regression Check

on:
  pull_request:
    paths:
      - 'src/**'
      - 'benchmarks/**'

permissions:
  contents: read
  actions: read

env:
  BENCHMARK_PROJECT: benchmarks/MyBenchmarks.csproj
  RESULTS_DIR: benchmarks/BenchmarkDotNet.Artifacts/results

jobs:
  benchmark:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup .NET
        uses: actions/setup-dotnet@v4
        with:
          dotnet-version: '8.0.x'

      - name: Download baseline results
        uses: actions/download-artifact@v4
        with:
          name: benchmark-baseline
          path: ./baseline-results
        continue-on-error: true
        id: download-baseline

      - name: Run benchmarks
        run: dotnet run -c Release --project ${{ env.BENCHMARK_PROJECT }} -- --exporters json

      - name: Compare with baseline
        if: steps.download-baseline.outcome == 'success'
        shell: bash
        run: |
          set -euo pipefail
          python3 scripts/compare-benchmarks.py \
            --baseline ./baseline-results \
            --current "${{ env.RESULTS_DIR }}" \
            --threshold 10 \
            --output benchmark-comparison.md

      - name: Upload current results as new baseline
        if: github.ref == 'refs/heads/main'
        uses: actions/upload-artifact@v4
        with:
          name: benchmark-baseline
          path: ${{ env.RESULTS_DIR }}/
          retention-days: 90
          overwrite: true

      - name: Upload comparison report
        if: steps.download-baseline.outcome == 'success'
        uses: actions/upload-artifact@v4
        with:
          name: benchmark-comparison-${{ github.sha }}
          path: benchmark-comparison.md
          retention-days: 30
```

**Key design decisions:**

- `continue-on-error: true` on baseline download handles first-run (no baseline exists yet)
- Baseline is only updated from `main` branch merges to prevent PR branches from polluting the baseline
- `overwrite: true` replaces the previous baseline artifact

For converting these inline workflows into reusable `workflow_call` patterns, see [skill:dotnet-devops] `references/gha-patterns.md`.

---

## Regression Detection Patterns

### Threshold-Based Comparison

Compare current benchmark results against baseline using percentage thresholds. A regression is flagged when the current mean exceeds the baseline mean by more than the configured threshold:

```python
#!/usr/bin/env python3
"""compare-benchmarks.py -- Detect benchmark regressions from BenchmarkDotNet JSON exports."""

import json
import sys
from pathlib import Path

def load_benchmarks(results_dir: str) -> dict:
    """Load benchmark results from BenchmarkDotNet JSON export files."""
    benchmarks = {}
    for json_file in Path(results_dir).glob("*-report-full.json"):
        with open(json_file) as f:
            data = json.load(f)
        for bm in data.get("Benchmarks", []):
            name = bm["FullName"]
            benchmarks[name] = {
                "mean": bm["Statistics"]["Mean"],
                "median": bm["Statistics"]["Median"],
                "stddev": bm["Statistics"]["StandardDeviation"],
                "allocated": bm.get("Memory", {}).get("BytesAllocatedPerOperation", 0),
            }
    return benchmarks

def compare(baseline_dir: str, current_dir: str, threshold_pct: float) -> list:
    """Compare current results against baseline. Returns list of regressions."""
    baseline = load_benchmarks(baseline_dir)
    current = load_benchmarks(current_dir)
    regressions = []

    for name, curr in current.items():
        if name not in baseline:
            continue  # new benchmark, no comparison possible
        base = baseline[name]
        if base["mean"] == 0:
            continue  # avoid division by zero

        time_change_pct = ((curr["mean"] - base["mean"]) / base["mean"]) * 100
        alloc_change = curr["allocated"] - base["allocated"]

        if time_change_pct > threshold_pct:
            regressions.append({
                "name": name,
                "baseline_mean": base["mean"],
                "current_mean": curr["mean"],
                "change_pct": time_change_pct,
                "alloc_change": alloc_change,
            })

    return regressions

if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Compare BenchmarkDotNet results")
    parser.add_argument("--baseline", required=True, help="Path to baseline results directory")
    parser.add_argument("--current", required=True, help="Path to current results directory")
    parser.add_argument("--threshold", type=float, default=10.0,
                        help="Regression threshold percentage (default: 10)")
    parser.add_argument("--output", default="comparison.md", help="Output markdown file")
    args = parser.parse_args()

    regressions = compare(args.baseline, args.current, args.threshold)

    with open(args.output, "w") as f:
        if regressions:
            f.write("## Benchmark Regressions Detected\n\n")
            f.write("| Benchmark | Baseline (ns) | Current (ns) | Change | Alloc Delta |\n")
            f.write("|-----------|--------------|-------------|--------|-------------|\n")
            for r in regressions:
                f.write(f"| `{r['name']}` | {r['baseline_mean']:.2f} | "
                        f"{r['current_mean']:.2f} | +{r['change_pct']:.1f}% | "
                        f"{r['alloc_change']:+d} B |\n")
            f.write(f"\nThreshold: {args.threshold}%\n")
        else:
            f.write("## Benchmark Results\n\nNo regressions detected ")
            f.write(f"(threshold: {args.threshold}%).\n")

    if regressions:
        print(f"REGRESSION: {len(regressions)} benchmark(s) exceeded "
              f"{args.threshold}% threshold", file=sys.stderr)
        sys.exit(1)
```

### Choosing Thresholds

| Environment | Suggested Threshold | Rationale |
|-------------|-------------------|-----------|
| Dedicated benchmark hardware | 5% | Low noise floor; small regressions are signal |
| GitHub Actions shared runners | 10-15% | Shared runners introduce 5-10% variance from noisy neighbors |
| Self-hosted runners | 5-10% | More stable than shared, but still monitor variance |

**Calibrate thresholds empirically:** Run the same benchmark suite 5-10 times on your CI environment without code changes. The maximum observed variance sets your noise floor. Set the threshold above this noise floor (typically 2x the observed variance).

### Allocation Regression Detection

Memory allocation regressions are more reliable signals than timing regressions because allocations are deterministic (not affected by noisy neighbors):

```python
# Add to the compare function:
if alloc_change > 0:
    regressions.append({
        "name": name,
        "type": "allocation",
        "baseline_alloc": base["allocated"],
        "current_alloc": curr["allocated"],
        "alloc_change": alloc_change,
    })
```

Use allocation changes as a **hard gate** (zero tolerance for new allocations in zero-alloc paths) and timing changes as a **soft gate** (warning with threshold).

---

## Alerting Strategies

### PR Comment with Regression Summary

Post benchmark comparison results as a PR comment for reviewer visibility:

```yaml
      - name: Comment PR with results
        if: steps.download-baseline.outcome == 'success' && github.event_name == 'pull_request'
        uses: actions/github-script@v7
        with:
          script: |
            const fs = require('fs');
            const body = fs.readFileSync('benchmark-comparison.md', 'utf8');
            await github.rest.issues.createComment({
              owner: context.repo.owner,
              repo: context.repo.repo,
              issue_number: context.issue.number,
              body: body
            });
```

### Fail the Build on Regression

Exit with non-zero status from the comparison script to fail the GitHub Actions job. This prevents merging PRs that introduce performance regressions:

```yaml
      - name: Check for regressions
        if: steps.download-baseline.outcome == 'success'
        shell: bash
        run: |
          set -euo pipefail
          python3 scripts/compare-benchmarks.py \
            --baseline ./baseline-results \
            --current "${{ env.RESULTS_DIR }}" \
            --threshold 10
          # Script exits non-zero if regressions found -- fails the job
```

For required status checks and branch protection integration with benchmark gates, see [skill:dotnet-devops] `references/gha-patterns.md`.

### Trend Tracking

For long-term trend analysis beyond single-PR comparison, upload results to a persistent store and track metrics over time:

| Approach | Tool | Complexity |
|----------|------|------------|
| GitHub Actions artifacts | Built-in, 90-day retention | Low -- artifact download/upload only |
| GitHub Pages with benchmark-action | `benchmark-action/github-action-benchmark@v1` | Medium -- auto-generates trend charts |
| External time-series DB | InfluxDB, Prometheus + Grafana | High -- full observability stack |

The simplest approach for most projects is the artifact-based baseline comparison shown in this skill. Graduate to trend tracking when you need historical regression analysis across many releases.

---

## CI-Specific BenchmarkDotNet Configuration

### ShortRun for CI Speed

Full benchmark runs take 10-30+ minutes. Use `Job.ShortRun` in CI to reduce iteration counts while retaining regression detection capability:

```csharp
using BenchmarkDotNet.Configs;
using BenchmarkDotNet.Jobs;

public class CiConfig : ManualConfig
{
    public CiConfig()
    {
        AddJob(Job.ShortRun
            .WithWarmupCount(3)
            .WithIterationCount(5)
            .WithInvocationCount(1));

        AddExporter(BenchmarkDotNet.Exporters.Json.JsonExporter.Full);
    }
}
```

Apply conditionally based on environment:

```csharp
var config = Environment.GetEnvironmentVariable("CI") is not null
    ? new CiConfig()
    : DefaultConfig.Instance;

BenchmarkRunner.Run<CriticalPathBenchmarks>(config);
```

### Filtering Benchmarks for CI

Run only critical-path benchmarks in CI to reduce pipeline duration:

```bash
# Run only benchmarks in the "Critical" category
dotnet run -c Release --project benchmarks/MyBenchmarks.csproj -- \
  --filter *Critical* --exporters json
```

```csharp
[BenchmarkCategory("Critical")]
[MemoryDiagnoser]
[JsonExporterAttribute.Full]
public class CriticalPathBenchmarks
{
    [Benchmark]
    public void ProcessOrder() { /* ... */ }
}

[BenchmarkCategory("Extended")]
[MemoryDiagnoser]
public class ExtendedBenchmarks
{
    [Benchmark]
    public void RareCodePath() { /* ... */ }
}
```

Run `Critical` benchmarks on every PR; run `Extended` benchmarks on a nightly schedule.

### Nightly Benchmark Schedule

```yaml
name: Nightly Benchmarks (Full Suite)

on:
  schedule:
    - cron: '0 3 * * *'  # 3 AM UTC daily
  workflow_dispatch:

jobs:
  benchmark-full:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup .NET
        uses: actions/setup-dotnet@v4
        with:
          dotnet-version: '8.0.x'

      - name: Run full benchmark suite
        run: dotnet run -c Release --project benchmarks/MyBenchmarks.csproj -- --exporters json
        # No --filter: runs all benchmarks including Extended category

      - name: Upload full results
        uses: actions/upload-artifact@v4
        with:
          name: benchmark-full-${{ github.run_number }}
          path: benchmarks/BenchmarkDotNet.Artifacts/results/
          retention-days: 90
```

For scheduled workflow patterns and matrix builds across TFMs, see [skill:dotnet-devops] `references/gha-patterns.md`.

---

## Agent Gotchas

1. **Use `Job.ShortRun` in CI, not `Job.Default`** -- default benchmark jobs run many iterations for statistical precision, taking 10-30+ minutes per benchmark class. CI pipelines need faster feedback with `ShortRun` (3 warmup, 5 iteration).
2. **Set threshold above measured noise floor** -- shared CI runners introduce 5-10% timing variance from noisy neighbors. A 5% threshold on shared runners produces false positives. Calibrate by running the same code multiple times and measuring variance.
3. **Use allocation changes as hard gates** -- allocation counts are deterministic and unaffected by runner noise. A zero-to-nonzero allocation change is always a real regression, unlike timing variations.
4. **Only update baselines from main branch** -- if PR branches can update the baseline, a regression in one PR becomes the new baseline, masking it from subsequent comparisons.
5. **Always set `set -euo pipefail` in bash steps** -- without `pipefail`, a regression detection script that exits non-zero in a pipeline (e.g., `script | tee`) does not fail the GitHub Actions step.
6. **Handle missing baselines gracefully** -- the first CI run has no baseline to compare against. Use `continue-on-error: true` on the baseline download step and skip comparison when no baseline exists.
7. **Export JSON, not just Markdown** -- Markdown reports are human-readable but not machine-parseable for automated regression detection. Always include `[JsonExporterAttribute.Full]` or `JsonExporter.Full` in the config.
