# BenchmarkDotNet

Microbenchmarking guidance for .NET using BenchmarkDotNet v0.14+. Covers benchmark class setup, memory and disassembly diagnosers, exporters for CI artifact collection, baseline comparisons, and common pitfalls that invalidate measurements.

**Version assumptions:** BenchmarkDotNet v0.14+ on .NET 8.0+ baseline. Examples use current stable APIs.

## Package Setup

```xml
<!-- Benchmarks.csproj -->
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net8.0</TargetFramework>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="BenchmarkDotNet" Version="0.14.*" />
  </ItemGroup>
</Project>
```

Keep benchmark projects separate from production code. Use a `benchmarks/` directory at the solution root.

---

## Benchmark Class Setup

### Basic Benchmark with [Benchmark] Attribute

```csharp
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Running;

[MemoryDiagnoser]
public class StringConcatBenchmarks
{
    private readonly string[] _items = Enumerable.Range(0, 100)
        .Select(i => i.ToString())
        .ToArray();

    [Benchmark(Baseline = true)]
    public string StringConcat()
    {
        var result = string.Empty;
        foreach (var item in _items)
            result += item;
        return result;
    }

    [Benchmark]
    public string StringBuilder()
    {
        var sb = new System.Text.StringBuilder();
        foreach (var item in _items)
            sb.Append(item);
        return sb.ToString();
    }

    [Benchmark]
    public string StringJoin() => string.Join(string.Empty, _items);
}
```

### Running Benchmarks

```csharp
// Program.cs
using BenchmarkDotNet.Running;

BenchmarkRunner.Run<StringConcatBenchmarks>();
```

Run in Release mode (mandatory for valid results):

```bash
dotnet run -c Release
```

### Parameterized Benchmarks

```csharp
[MemoryDiagnoser]
public class CollectionBenchmarks
{
    [Params(10, 100, 1000)]
    public int Size { get; set; }

    private int[] _data = null!;

    [GlobalSetup]
    public void Setup()
    {
        _data = Enumerable.Range(0, Size).ToArray();
    }

    [Benchmark(Baseline = true)]
    public int ForLoop()
    {
        var sum = 0;
        for (var i = 0; i < _data.Length; i++)
            sum += _data[i];
        return sum;
    }

    [Benchmark]
    public int LinqSum() => _data.Sum();
}
```

---

## Memory Diagnosers

### MemoryDiagnoser

Tracks GC allocations and collection counts per benchmark invocation. Apply at class level to all benchmarks:

```csharp
[MemoryDiagnoser]
public class AllocationBenchmarks
{
    [Benchmark]
    public byte[] AllocateArray() => new byte[1024];

    [Benchmark]
    public int UseStackalloc()
    {
        Span<byte> buffer = stackalloc byte[1024];
        buffer[0] = 42;
        return buffer[0];
    }
}
```

Output columns:

| Column | Meaning |
|--------|---------|
| `Allocated` | Bytes allocated per operation |
| `Gen0` | Gen 0 GC collections per 1000 operations |
| `Gen1` | Gen 1 GC collections per 1000 operations |
| `Gen2` | Gen 2 GC collections per 1000 operations |

Zero in `Allocated` column confirms zero-allocation code paths.

### DisassemblyDiagnoser

Inspects JIT-compiled assembly to verify optimizations (devirtualization, inlining):

```csharp
[DisassemblyDiagnoser(maxDepth: 2)]
[MemoryDiagnoser]
public class DevirtualizationBenchmarks
{
    // sealed enables JIT devirtualization -- verify in disassembly output
    // See [skill:dotnet-csharp] `references/coding-standards.md` for sealed class conventions
    [Benchmark]
    public int SealedCall()
    {
        var obj = new SealedService();
        return obj.Calculate(42);
    }

    [Benchmark]
    public int VirtualCall()
    {
        IService obj = new SealedService();
        return obj.Calculate(42);
    }
}

public interface IService { int Calculate(int x); }
public sealed class SealedService : IService
{
    public int Calculate(int x) => x * 2;
}
```

Use `DisassemblyDiagnoser` to verify that `sealed` classes receive devirtualization from the JIT, confirming the performance rationale documented in [skill:dotnet-csharp] `references/coding-standards.md`.

---

## Exporters for CI Integration

### Configuring Exporters

```csharp
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Exporters;
using BenchmarkDotNet.Exporters.Json;

[MemoryDiagnoser]
[JsonExporterAttribute.Full]
[HtmlExporter]
[MarkdownExporter]
public class CiBenchmarks
{
    [Benchmark]
    public void MyOperation()
    {
        // benchmark code
    }
}
```

### Exporter Output

| Exporter | File | Use Case |
|----------|------|----------|
| `JsonExporterAttribute.Full` | `BenchmarkDotNet.Artifacts/results/*-report-full.json` | CI regression comparison (machine-readable) |
| `HtmlExporter` | `BenchmarkDotNet.Artifacts/results/*-report.html` | Human-readable PR review artifact |
| `MarkdownExporter` | `BenchmarkDotNet.Artifacts/results/*-report-github.md` | Paste into PR comments |

### Custom Config for CI

```csharp
using BenchmarkDotNet.Configs;
using BenchmarkDotNet.Exporters.Json;
using BenchmarkDotNet.Jobs;

var config = ManualConfig.Create(DefaultConfig.Instance)
    .AddJob(Job.ShortRun)  // fewer iterations for CI speed
    .AddExporter(JsonExporter.Full)
    .WithArtifactsPath("./benchmark-results");

BenchmarkRunner.Run<CiBenchmarks>(config);
```

### GitHub Actions Artifact Upload

```yaml
- name: Run benchmarks
  run: dotnet run -c Release --project benchmarks/MyBenchmarks.csproj

- name: Upload benchmark results
  uses: actions/upload-artifact@v4
  with:
    name: benchmark-results
    path: benchmarks/BenchmarkDotNet.Artifacts/results/
    retention-days: 30
```

---

## Baseline Comparison

### Setting a Baseline

Mark one benchmark as the baseline for ratio comparison:

```csharp
[MemoryDiagnoser]
public class SerializationBenchmarks
{
    // Serialization format choice -- see [skill:dotnet-csharp] `references/serialization.md` for API details
    private readonly JsonSerializerOptions _options = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
    };

    private readonly WeatherForecast _data = new()
    {
        Date = DateOnly.FromDateTime(DateTime.Now),
        TemperatureC = 25,
        Summary = "Warm"
    };

    [Benchmark(Baseline = true)]
    public string SystemTextJson()
        => System.Text.Json.JsonSerializer.Serialize(_data, _options);

    [Benchmark]
    public byte[] Utf8Serialization()
        => System.Text.Json.JsonSerializer.SerializeToUtf8Bytes(_data, _options);
}

public record WeatherForecast
{
    public DateOnly Date { get; init; }
    public int TemperatureC { get; init; }
    public string? Summary { get; init; }
}
```

The `Ratio` column in output shows performance relative to the baseline (1.00). Values below 1.00 indicate faster than baseline; above 1.00 indicate slower.

### Benchmark Categories

Group benchmarks with `[BenchmarkCategory]` and filter at runtime:

```csharp
[MemoryDiagnoser]
[GroupBenchmarksBy(BenchmarkLogicalGroupRule.ByCategory)]
public class CategorizedBenchmarks
{
    [Benchmark, BenchmarkCategory("Serialization")]
    public string JsonSerialize() => "...";

    [Benchmark, BenchmarkCategory("Allocation")]
    public byte[] ArrayAlloc() => new byte[1024];
}
```

Run a specific category:

```bash
dotnet run -c Release -- --filter *Serialization*
```

---

## BenchmarkRunner.Run Patterns

### Running Specific Benchmarks

```csharp
// Run a single benchmark class
BenchmarkRunner.Run<StringConcatBenchmarks>();

// Run all benchmarks in assembly
BenchmarkSwitcher.FromAssembly(typeof(Program).Assembly).Run(args);
```

### Command-Line Filtering

```bash
# Run benchmarks matching a pattern
dotnet run -c Release -- --filter *StringBuilder*

# List all available benchmarks without running
dotnet run -c Release -- --list flat

# Dry run (validates setup without full benchmark)
dotnet run -c Release -- --filter *StringBuilder* --job Dry
```

### AOT Benchmark Considerations

When benchmarking Native AOT scenarios, the JIT diagnosers are not available (there is no JIT). Use wall-clock time and memory comparisons instead. See [skill:dotnet-tooling] `references/native-aot.md` for AOT compilation setup:

```csharp
[MemoryDiagnoser]
// Do NOT use DisassemblyDiagnoser with AOT -- no JIT to disassemble
public class AotBenchmarks
{
    [Benchmark]
    public string SourceGenSerialize()
        => System.Text.Json.JsonSerializer.Serialize(
            new { Value = 42 },
            AppJsonContext.Default.Options);
}
```

---

## Common Pitfalls

### Dead Code Elimination

The JIT may eliminate benchmark code whose result is unused. Always **return** or **consume** the result:

```csharp
// BAD: JIT may eliminate the entire loop
[Benchmark]
public void DeadCode()
{
    var sum = 0;
    for (var i = 0; i < 1000; i++)
        sum += i;
    // sum is never used -- JIT removes the loop
}

// GOOD: return the value to prevent elimination
[Benchmark]
public int LiveCode()
{
    var sum = 0;
    for (var i = 0; i < 1000; i++)
        sum += i;
    return sum;
}
```

### Measurement Bias

| Pitfall | Cause | Fix |
|---------|-------|-----|
| Running in Debug mode | No JIT optimizations applied | Always use `-c Release` |
| Shared mutable state | Benchmarks interfere with each other | Use `[IterationSetup]` or immutable data |
| Cold-start measurement | First run includes JIT compilation | BenchmarkDotNet handles warmup automatically -- do not add manual warmup |
| Allocations in setup | Setup allocations inflate `Allocated` column | Use `[GlobalSetup]` (runs once) vs `[IterationSetup]` (runs per iteration) |
| Environment noise | Background processes skew results | BenchmarkDotNet detects and warns about environment issues; use `Job.MediumRun` for noisy environments |

### Setup vs Iteration Lifecycle

```csharp
[MemoryDiagnoser]
public class LifecycleBenchmarks
{
    private byte[] _data = null!;

    [GlobalSetup]    // Runs once before all benchmark iterations
    public void GlobalSetup() => _data = new byte[1024];

    [IterationSetup] // Runs before each benchmark iteration
    public void IterationSetup() => Array.Fill(_data, (byte)0);

    [Benchmark]
    public int Process()
    {
        // uses _data
        return _data.Length;
    }

    [GlobalCleanup]    // Runs once after all iterations
    public void GlobalCleanup() { /* dispose resources */ }
}
```

Prefer `[GlobalSetup]` over `[IterationSetup]` unless the benchmark mutates shared state. `[IterationSetup]` adds overhead that BenchmarkDotNet excludes from timing, but it still affects GC pressure measurement.

---

## Agent Gotchas

1. **Always run benchmarks in Release mode** -- `dotnet run -c Release`. Debug mode disables JIT optimizations and produces meaningless results.
2. **Never benchmark in a test project** -- xUnit/NUnit test runners interfere with BenchmarkDotNet's measurement harness. Use a standalone console project.
3. **Return values from benchmark methods** to prevent dead code elimination. The JIT will remove computation whose result is discarded.
4. **Do not add manual Thread.Sleep or Task.Delay in benchmarks** -- BenchmarkDotNet manages warmup and iteration timing automatically.
5. **Use `[GlobalSetup]` not constructor** for initialization -- BenchmarkDotNet creates benchmark instances multiple times during a run; constructor code runs repeatedly.
6. **Prefer `[Params]` over manual loops** for parameterized benchmarks. BenchmarkDotNet runs each parameter combination independently with proper statistical analysis.
7. **Export JSON for CI** -- use `[JsonExporterAttribute.Full]` to produce machine-readable artifacts for regression detection, not just Markdown.
