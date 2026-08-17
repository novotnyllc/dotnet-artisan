# Profiling

Diagnostic tool guidance for investigating .NET performance problems. Covers real-time metric monitoring with dotnet-counters, event tracing and flame graph generation with dotnet-trace, and memory dump capture and analysis with dotnet-dump. Focuses on interpreting profiling data (reading flame graphs, analyzing heap dumps, correlating GC metrics) rather than just invoking tools.

**Version assumptions:** .NET SDK 8.0+ baseline. All three diagnostic tools (dotnet-counters, dotnet-trace, dotnet-dump) ship with the .NET SDK -- no separate installation required.

## dotnet-counters -- Real-Time Metric Monitoring

### Overview

`dotnet-counters` provides real-time monitoring of .NET runtime metrics without modifying application code. Use it as a first-pass triage tool to identify whether a performance problem is CPU-bound, memory-bound, or I/O-bound before reaching for heavier instrumentation.

### Monitoring Running Processes

```bash
# List running .NET processes
dotnet-counters ps

# Monitor default runtime counters for a process
dotnet-counters monitor --process-id <PID>

# Monitor with a specific refresh interval (seconds)
dotnet-counters monitor --process-id <PID> --refresh-interval 2
```

### Key Built-In Counter Providers

| Provider | Counters | What It Tells You |
|----------|----------|-------------------|
| `System.Runtime` | CPU usage, GC heap size, Gen 0/1/2 collections, threadpool queue length, exception count | Overall runtime health |
| `Microsoft.AspNetCore.Hosting` | Request rate, request duration, active requests | HTTP request throughput and latency |
| `Microsoft.AspNetCore.Http.Connections` | Connection duration, current connections | WebSocket/SignalR connection load |
| `System.Net.Http` | Requests started/failed, active requests, connection pool size | Outbound HTTP client behavior |
| `System.Net.Sockets` | Bytes sent/received, datagrams, connections | Network I/O volume |

### Monitoring Specific Providers

```bash
# Monitor runtime and ASP.NET counters together
dotnet-counters monitor --process-id <PID> \
  --counters System.Runtime,Microsoft.AspNetCore.Hosting

# Monitor only GC-related counters
dotnet-counters monitor --process-id <PID> \
  --counters System.Runtime[gc-heap-size,gen-0-gc-count,gen-1-gc-count,gen-2-gc-count]
```

### Custom EventCounters

Applications can publish custom counters for domain-specific metrics:

```csharp
using System.Diagnostics.Tracing;

[EventSource(Name = "MyApp.Orders")]
public sealed class OrderMetrics : EventSource
{
    public static readonly OrderMetrics Instance = new();

    private EventCounter? _orderProcessingTime;
    private IncrementingEventCounter? _ordersProcessed;

    private OrderMetrics()
    {
        _orderProcessingTime = new EventCounter("order-processing-time", this)
        {
            DisplayName = "Order Processing Time (ms)",
            DisplayUnits = "ms"
        };
        _ordersProcessed = new IncrementingEventCounter("orders-processed", this)
        {
            DisplayName = "Orders Processed",
            DisplayRateTimeScale = TimeSpan.FromSeconds(1)
        };
    }

    public void RecordProcessingTime(double milliseconds)
        => _orderProcessingTime?.WriteMetric(milliseconds);

    public void RecordOrderProcessed()
        => _ordersProcessed?.Increment();

    protected override void Dispose(bool disposing)
    {
        _orderProcessingTime?.Dispose();
        _ordersProcessed?.Dispose();
        base.Dispose(disposing);
    }
}
```

Monitor custom counters:

```bash
dotnet-counters monitor --process-id <PID> --counters MyApp.Orders
```

### Interpreting Counter Data

Use counter values to direct further investigation. See [skill:dotnet-devops] for correlating these runtime metrics with OpenTelemetry traces:

| Symptom | Counter Evidence | Next Step |
|---------|------------------|-----------|
| High CPU usage | `cpu-usage` > 80%, `threadpool-queue-length` low | CPU profiling with dotnet-trace |
| Memory growth | `gc-heap-size` increasing, frequent Gen 2 GC | Memory dump with dotnet-dump |
| Thread starvation | `threadpool-queue-length` growing, `threadpool-thread-count` at max | Check for sync-over-async or blocking calls |
| Request latency | `request-duration` high, `active-requests` normal | Trace individual requests with dotnet-trace |
| GC pauses | High `gen-2-gc-count`, `time-in-gc` > 10% | Allocation profiling with dotnet-trace gc-collect |

### Exporting Counter Data

```bash
# Export to CSV for analysis
dotnet-counters collect --process-id <PID> \
  --format csv \
  --output counters.csv \
  --counters System.Runtime

# Export to JSON for programmatic consumption
dotnet-counters collect --process-id <PID> \
  --format json \
  --output counters.json
```


## dotnet-trace -- Event Tracing and Flame Graphs

### Overview

`dotnet-trace` captures detailed event traces from a running .NET process. Traces can be analyzed as flame graphs to identify CPU hot paths, or configured for allocation tracking to find GC pressure sources.

### CPU Sampling

CPU sampling records stack frames at a fixed interval to build a statistical profile of where the application spends time:

```bash
# Collect a CPU sampling trace (default profile)
dotnet-trace collect --process-id <PID> --duration 00:00:30

# Collect with the cpu-sampling profile (explicit)
dotnet-trace collect --process-id <PID> \
  --profile cpu-sampling \
  --output cpu-trace.nettrace
```

### CPU Sampling vs Instrumentation

| Approach | Overhead | Best For | Tool |
|----------|----------|----------|------|
| CPU sampling | Low (~2-5%) | Finding CPU hot paths in production | dotnet-trace `--profile cpu-sampling` |
| Instrumentation | High (10-50%+) | Exact call counts, method entry/exit timing | Rider/VS profiler, PerfView |

CPU sampling is safe for production use due to low overhead. Use it as the default approach. Reserve instrumentation for development environments where exact call counts matter.

### Flame Graph Generation

Trace files (`.nettrace`) must be converted to a flame graph format for visual analysis:

**Using Speedscope (browser-based, recommended):**

```bash
# Convert to Speedscope format
dotnet-trace convert cpu-trace.nettrace --format Speedscope

# Opens cpu-trace.speedscope.json -- load at https://www.speedscope.app/
```

**Using PerfView (Windows, deep .NET integration):**

```bash
# Convert to Chromium trace format (also viewable in chrome://tracing)
dotnet-trace convert cpu-trace.nettrace --format Chromium
```

### Reading Flame Graphs

Flame graphs display call stacks where:

- **Width** of a frame represents the proportion of total sample time spent in that function (wider = more time)
- **Height** represents call stack depth (taller stacks = deeper call chains)
- **Color** is typically arbitrary (not meaningful) unless the tool uses a specific color scheme

**Analysis workflow:**

1. Look for **wide plateaus** -- functions that consume a large proportion of samples
2. Follow the widest frames **upward** to find which callers contribute the most time
3. Identify **unexpected width** -- framework methods that should be fast appearing wide indicate misuse
4. Compare **before/after** traces to validate optimizations reduced the width of target functions

**Common patterns in .NET flame graphs:**

| Pattern | Likely Cause | Investigation |
|---------|-------------|---------------|
| Wide `System.Linq` frames | LINQ-heavy hot path with delegate overhead | Replace with foreach loops or Span-based processing |
| Wide `JIT_New` / `gc_heap::allocate` | Excessive allocations triggering GC | Allocation profiling with `--profile gc-collect` |
| Wide `Monitor.Enter` / `SpinLock` | Lock contention | Review synchronization strategy |
| Wide `System.Text.RegularExpressions` | Regex backtracking | Use `RegexOptions.NonBacktracking` or compile regex |
| Deep async state machine frames | Async overhead in tight loops | Consider sync path for CPU-bound work |

### Allocation Tracking with gc-collect Profile

The `gc-collect` profile captures allocation events to identify what code paths allocate the most memory:

```bash
# Collect allocation data
dotnet-trace collect --process-id <PID> \
  --profile gc-collect \
  --duration 00:00:30 \
  --output alloc-trace.nettrace
```

This produces a trace that shows:

- Which methods allocate the most bytes
- Which types are allocated most frequently
- Allocation sizes and the call stacks that trigger them

Correlate allocation data with GC counter evidence from dotnet-counters. If `gen-2-gc-count` is high, the allocation trace shows which code paths produce long-lived objects that survive to Gen 2. See `references/performance-patterns.md` for zero-allocation patterns to apply once hot allocation sites are identified.

### Custom Trace Providers

Target specific event providers for focused tracing:

```bash
# Trace specific providers with keywords and verbosity
dotnet-trace collect --process-id <PID> \
  --providers "Microsoft-Diagnostics-DiagnosticSource:::FilterAndPayloadSpecs=[AS]System.Net.Http"

# Trace EF Core queries (useful with [skill:dotnet-api])
dotnet-trace collect --process-id <PID> \
  --providers Microsoft.EntityFrameworkCore

# Trace ASP.NET Core request processing
dotnet-trace collect --process-id <PID> \
  --providers Microsoft.AspNetCore
```

### Trace File Management

| Format | Extension | Viewer | Cross-Platform |
|--------|-----------|--------|----------------|
| NetTrace | `.nettrace` | PerfView, VS, dotnet-trace convert | Yes (capture); Windows (PerfView) |
| Speedscope | `.speedscope.json` | https://www.speedscope.app/ | Yes |
| Chromium | `.chromium.json` | Chrome DevTools (chrome://tracing) | Yes |


## dotnet-dump -- Memory Dump Analysis

### Overview

`dotnet-dump` captures and analyzes process memory dumps. Use it to investigate memory leaks, large object heap fragmentation, and object reference chains. Unlike dotnet-trace, dumps capture a point-in-time snapshot of the entire managed heap.

### Capturing Dumps

```bash
# Capture a full heap dump
dotnet-dump collect --process-id <PID> --output app-dump.dmp

# Capture a minimal dump (faster, smaller, but less detail)
dotnet-dump collect --process-id <PID> --type Mini --output app-mini.dmp
```

**When to capture:**

- Memory usage has grown beyond expected baseline (compare against dotnet-counters `gc-heap-size`)
- Application is approaching OOM conditions
- Suspected memory leak after load testing
- Investigating finalizer queue backlog

### Analyzing Dumps with SOS Commands

Open the dump in the interactive analyzer:

```bash
dotnet-dump analyze app-dump.dmp
```

### !dumpheap -- Heap Object Summary

Lists objects on the managed heap grouped by type, sorted by total size:

```
> dumpheap -stat

Statistics:
              MT    Count    TotalSize Class Name
00007fff2c6a4320      125        4,000 System.String[]
00007fff2c6a1230    8,432      269,824 System.String
00007fff2c7b5640    2,100      504,000 MyApp.Models.OrderEntity
00007fff2c6a0988   15,230    1,218,400 System.Byte[]
```

**Analysis approach:**

1. Look for unexpectedly high counts or sizes for application types
2. Compare counts against expected cardinality (e.g., 2,100 OrderEntity objects -- is that expected for current load?)
3. Large `System.Byte[]` counts often indicate unbounded buffering or stream handling issues

Filter by type:

```
> dumpheap -type MyApp.Models.OrderEntity
> dumpheap -type System.Byte[] -min 85000
```

The `-min 85000` filter shows Large Object Heap entries (objects >= 85,000 bytes that cause Gen 2 GC pressure).

### !gcroot -- Finding Object Retention

Traces the reference chain from a GC root to a specific object, explaining why it is not collected:

```
> gcroot 00007fff3c4a2100

HandleTable:
    00007fff3c010010 (strong handle)
        -> 00007fff3c3a1000 MyApp.Services.CacheService
            -> 00007fff3c3a1020 System.Collections.Generic.Dictionary`2
                -> 00007fff3c4a2100 MyApp.Models.OrderEntity

Found 1 unique root(s).
```

**Common root types and their meaning:**

| Root Type | Meaning | Likely Issue |
|-----------|---------|-------------|
| `strong handle` | Static field or GC handle | Static collection growing without eviction |
| `pinned handle` | Pinned for native interop | Buffer pinned longer than needed |
| `async state machine` | Captured in async closure | Long-running async operation holding references |
| `finalizer queue` | Waiting for finalizer thread | Finalizer backlog blocking collection |
| `threadpool` | Referenced from thread-local storage | Thread-static cache without cleanup |

### !finalizequeue -- Finalizer Queue Analysis

Shows objects waiting for finalization, which delays their collection by at least one GC cycle:

```
> finalizequeue

SyncBlocks to be cleaned up: 0
Free-Threaded Interfaces to be released: 0
MTA Interfaces to be released: 0
STA Interfaces to be released: 0
----------------------------------
generation 0 has 12 finalizable objects
generation 1 has 45 finalizable objects
generation 2 has 230 finalizable objects
Ready for finalization 8 objects
```

**Key indicators:**

- High count in "Ready for finalization" means the finalizer thread is falling behind
- Objects in Gen 2 finalizable list are expensive -- they survive two GC cycles minimum (one to schedule finalization, one to collect after finalization runs)
- Types implementing `~Destructor()` without `IDisposable.Dispose()` being called are the primary cause

### Additional SOS Commands for Heap Analysis

| Command | Purpose | When to Use |
|---------|---------|-------------|
| `dumpobj <address>` | Display field values of a specific object | Inspect object state after finding it with dumpheap |
| `dumparray <address>` | Display array contents | Investigate large arrays found in heap stats |
| `eeheap -gc` | Show GC heap segment layout | Investigate LOH fragmentation |
| `gcwhere <address>` | Show which GC generation holds an object | Determine if an object is pinned or in LOH |
| `dumpmt <MT>` | Display method table details | Investigate type metadata |
| `threads` | List all managed threads with stack traces | Identify deadlocks or blocking |
| `clrstack` | Display managed call stack for current thread | Correlate thread state with heap data |

### Memory Leak Investigation Workflow

1. **Baseline:** Capture a dump after application startup and initial warm-up
2. **Load:** Run the workload scenario suspected of leaking
3. **Compare:** Capture a second dump after the workload completes
4. **Diff:** Compare `dumpheap -stat` output between the two dumps -- look for types whose count or total size grew significantly
5. **Root:** Use `gcroot` on instances of the growing type to find the retention chain
6. **Fix:** Break the retention chain (remove from static collections, dispose event subscriptions, fix async lifetime issues)

```bash
# Tip: save dumpheap output for comparison
# In dump 1:
> dumpheap -stat > /tmp/heap-before.txt
# In dump 2:
> dumpheap -stat > /tmp/heap-after.txt
# Compare externally:
# diff /tmp/heap-before.txt /tmp/heap-after.txt
```


## Profiling Workflow Summary

Use the diagnostic tools in a structured investigation workflow:

```
1. dotnet-counters (triage)
   ├── CPU high?         → dotnet-trace --profile cpu-sampling
   │                       → Convert to flame graph (Speedscope)
   │                       → Identify hot methods
   ├── Memory growing?   → dotnet-dump collect
   │                       → dumpheap -stat (find large/numerous types)
   │                       → gcroot (find retention chains)
   │                       → Fix retention + verify with second dump
   ├── GC pressure?      → dotnet-trace --profile gc-collect
   │                       → Identify allocation hot paths
   │                       → Apply zero-alloc patterns `references/performance-patterns.md`
   └── Thread starvation? → dotnet-dump analyze
                            → threads (list all managed threads)
                            → clrstack (check for blocking calls)
```

After profiling identifies the bottleneck, use [skill:dotnet-testing] to create targeted benchmarks that quantify the improvement from fixes.


## Agent Gotchas

1. **Start with dotnet-counters, not dotnet-trace** -- counters have near-zero overhead and identify the category of problem (CPU, memory, threads). Only reach for trace or dump after counters narrow the investigation.
2. **Use CPU sampling (not instrumentation) in production** -- sampling overhead is 2-5% and safe for production. Instrumentation adds 10-50%+ overhead and should be limited to development environments.
3. **Always convert traces to flame graphs for analysis** -- reading raw `.nettrace` event logs is impractical. Use `dotnet-trace convert --format Speedscope` and open in https://www.speedscope.app/ for visual analysis.
4. **Capture two dumps for leak investigation** -- a single dump shows current state but cannot distinguish normal resident objects from leaked ones. Compare heap statistics across two dumps taken before and after the suspected leak scenario.
5. **Filter dumpheap by `-min 85000` to find LOH objects** -- objects >= 85,000 bytes go to the Large Object Heap, which is only collected in Gen 2 GC. Large LOH counts indicate potential fragmentation.
6. **Interpret GC counter data with [skill:dotnet-devops]** -- runtime GC/threadpool counters overlap with OpenTelemetry metrics. Use the observability skill for correlating profiling findings with distributed trace context.
7. **Do not confuse dotnet-trace gc-collect with dotnet-dump** -- gc-collect traces allocation events over time (which methods allocate); dotnet-dump captures a point-in-time heap snapshot (what objects exist). Use gc-collect for allocation rate analysis; use dotnet-dump for retention/leak analysis.
