# GC and Memory

Garbage collection and memory management for .NET applications. Covers GC modes (workstation vs server, concurrent vs non-concurrent), Large Object Heap (LOH) and Pinned Object Heap (POH), generational tuning (Gen0/1/2), memory pressure notifications, deep Span<T>/Memory<T> ownership patterns beyond basics, buffer pooling with ArrayPool<T> and MemoryPool<T>, weak references, finalizers vs IDisposable, and memory profiling with dotMemory and PerfView.

## GC Modes and Configuration

### Workstation vs Server GC

| Aspect | Workstation | Server |
|--------|-------------|--------|
| **GC threads** | Single thread | One thread per logical core |
| **Heap segments** | Single heap | One heap per core |
| **Pause latency** | Lower | Higher (more memory scanned) |
| **Throughput** | Lower | Higher |
| **Default for** | Console apps, desktop | ASP.NET Core web apps |

```xml
<!-- In the .csproj file -->
<PropertyGroup>
  <ServerGarbageCollection>true</ServerGarbageCollection>
</PropertyGroup>
```

```json
// Or in runtimeconfig.json
{
  "runtimeOptions": {
    "configProperties": {
      "System.GC.Server": true
    }
  }
}
```

### Concurrent vs Non-Concurrent GC

| Mode | Behavior | Use when |
|------|----------|----------|
| **Concurrent** (default) | Gen2 collection runs alongside application threads | Latency-sensitive (web APIs, UI) |
| **Non-concurrent** | Application threads pause during Gen2 collection | Maximum throughput, batch processing |

```json
{
  "runtimeOptions": {
    "configProperties": {
      "System.GC.Concurrent": true
    }
  }
}
```

### DATAS (Dynamic Adaptation to Application Sizes) -- .NET 8+

DATAS dynamically adjusts GC heap size based on application memory usage patterns. It is enabled by default in .NET 8+ Server GC mode. DATAS reduces memory footprint for applications with variable load by shrinking the heap during low-activity periods.

```json
{
  "runtimeOptions": {
    "configProperties": {
      "System.GC.DynamicAdaptationMode": 1
    }
  }
}
```

Set to `0` to disable DATAS if you observe excessive GC frequency in steady-state workloads.

### GC Regions -- .NET 7+

Regions replace the older segment-based heap management. Each region is a small, fixed-size block of memory that the GC can allocate and free independently. Regions are enabled by default in .NET 7+ and improve:

- Memory return to the OS after usage spikes
- Heap compaction efficiency
- Server GC scalability on high-core-count machines

No configuration is needed -- regions are the default. To revert to segments (rarely needed):

```json
{
  "runtimeOptions": {
    "configProperties": {
      "System.GC.Regions": false
    }
  }
}
```


## Generational GC (Gen0/1/2)

### How Generations Work

| Generation | Contains | Collection frequency | Collection cost |
|-----------|----------|---------------------|----------------|
| **Gen0** | Newly allocated objects | Very frequent (milliseconds) | Very cheap (small heap) |
| **Gen1** | Objects surviving Gen0 | Frequent | Cheap |
| **Gen2** | Long-lived objects | Infrequent | Expensive (full heap scan) |

Objects promote from Gen0 to Gen1 to Gen2 as they survive collections. The GC budget for Gen0 is tuned dynamically -- when Gen0 fills, a Gen0 collection triggers.

### Tuning Principles

1. **Minimize Gen0 allocation rate** -- reduce temporary object creation on hot paths. Every allocation contributes to Gen0 pressure.
2. **Avoid mid-life crisis** -- objects that live just long enough to promote to Gen1/Gen2 but then become garbage are the most expensive. They survive cheap Gen0 collections and require expensive Gen2 collections to reclaim.
3. **Reduce Gen2 collection frequency** -- Gen2 collections cause the longest pauses. Use object pooling, Span<T>, and value types to keep long-lived heap allocations low.

### Monitoring Generations

```bash
# Real-time GC metrics
dotnet-counters monitor --process-id <PID> \
  --counters System.Runtime[gen-0-gc-count,gen-1-gc-count,gen-2-gc-count,gc-heap-size]
```

```csharp
// Programmatic GC observation
var gen0 = GC.CollectionCount(0);
var gen1 = GC.CollectionCount(1);
var gen2 = GC.CollectionCount(2);
var totalMemory = GC.GetTotalMemory(forceFullCollection: false);
var memoryInfo = GC.GetGCMemoryInfo();

logger.LogInformation(
    "GC: Gen0={Gen0} Gen1={Gen1} Gen2={Gen2} Heap={HeapMB:F1}MB",
    gen0, gen1, gen2, totalMemory / (1024.0 * 1024));
```


## Large Object Heap (LOH) and Pinned Object Heap (POH)

### LOH

Objects >= 85,000 bytes are allocated on the LOH. LOH collections only happen during Gen2 collections, and by default the LOH is not compacted (causing fragmentation).

```csharp
// Force LOH compaction (use sparingly -- expensive)
GCSettings.LargeObjectHeapCompactionMode =
    GCLargeObjectHeapCompactionMode.CompactOnce;
GC.Collect();
```

### LOH Fragmentation Prevention

| Strategy | Implementation |
|----------|---------------|
| **ArrayPool<T>** for large arrays | `ArrayPool<byte>.Shared.Rent(100_000)` |
| **MemoryPool<T>** for IMemoryOwner pattern | `MemoryPool<byte>.Shared.Rent(100_000)` |
| **Pre-allocate and reuse** | Create large buffers once at startup |
| **Avoid frequent large string concat** | Use `StringBuilder` or `string.Create` |

### POH (Pinned Object Heap) -- .NET 5+

The POH is a dedicated heap for objects that must remain at a fixed memory address (pinned). Before .NET 5, pinning objects on the regular heap prevented compaction. The POH isolates pinned objects so they do not block compaction of Gen0/1/2 heaps.

```csharp
// Allocate on POH -- useful for I/O buffers passed to native code
byte[] buffer = GC.AllocateArray<byte>(4096, pinned: true);

// The buffer's address will not change, safe for native interop
// and overlapped I/O without explicit GCHandle pinning
```

Use POH for:
- I/O buffers passed to native/unmanaged code
- Memory-mapped file backing arrays
- Buffers used with `Socket.ReceiveAsync` (overlapped I/O)


## Span<T>/Memory<T> Deep Ownership Patterns

See `references/performance-patterns.md` for Span<T>/Memory<T> introduction and basic slicing. This section covers ownership semantics and lifetime management for shared buffers.

### IMemoryOwner<T> for Pooled Buffers

```csharp
// Rent from MemoryPool and manage lifetime with IDisposable
using IMemoryOwner<byte> owner = MemoryPool<byte>.Shared.Rent(4096);
Memory<byte> buffer = owner.Memory[..4096]; // Slice to exact size needed

// Pass the Memory<T> to async I/O
int bytesRead = await stream.ReadAsync(buffer, cancellationToken);
Memory<byte> data = buffer[..bytesRead];

// Process the data
await ProcessDataAsync(data, cancellationToken);
// owner.Dispose() returns the buffer to the pool
```

### Ownership Transfer Pattern

When transferring buffer ownership between components, use `IMemoryOwner<T>` to make lifetime responsibility explicit:

```csharp
public sealed class MessageParser
{
    // Caller transfers ownership -- this method is responsible for disposal
    public async Task ProcessAsync(
        IMemoryOwner<byte> messageOwner,
        CancellationToken ct)
    {
        using (messageOwner)
        {
            Memory<byte> data = messageOwner.Memory;
            // Parse and process...
            await HandleMessageAsync(data, ct);
        }
        // Buffer returned to pool on dispose
    }
}
```

### Span<T> Stack Discipline

```csharp
// Span<T> enforces stack-only usage (ref struct)
// These are compile-time errors:
// Span<byte> field;              // Cannot store in class/struct field
// async Task Foo(Span<byte> s);  // Cannot use in async method
// var list = new List<Span<byte>>(); // Cannot use as generic type argument

// When you need heap storage or async, use Memory<T> instead
public async Task ProcessAsync(Memory<byte> buffer, CancellationToken ct)
{
    // Can use Memory<T> in async methods
    int bytesRead = await stream.ReadAsync(buffer, ct);

    // Convert to Span<T> for synchronous processing within a method
    Span<byte> span = buffer.Span;
    ParseHeader(span[..bytesRead]);
}
```


## ArrayPool<T> and MemoryPool<T>

### ArrayPool<T>

`ArrayPool<T>` reduces GC pressure by reusing array allocations. Always return rented arrays, and never assume the returned array is exactly the requested size.

```csharp
// Rent and return pattern
byte[] buffer = ArrayPool<byte>.Shared.Rent(minimumLength: 4096);
try
{
    // IMPORTANT: Rented array may be larger than requested
    int bytesRead = await stream.ReadAsync(
        buffer.AsMemory(0, 4096), cancellationToken);
    ProcessData(buffer.AsSpan(0, bytesRead));
}
finally
{
    // clearArray: true when buffer contained sensitive data
    ArrayPool<byte>.Shared.Return(buffer, clearArray: false);
}
```

### Custom Pool Sizing

```csharp
// Create a custom pool for specific allocation patterns
var pool = ArrayPool<byte>.Create(
    maxArrayLength: 1_048_576,  // 1 MB max array
    maxArraysPerBucket: 50);    // Keep up to 50 arrays per size bucket

// Use for workloads with predictable buffer sizes
byte[] buffer = pool.Rent(65_536);
try
{
    // Process...
}
finally
{
    pool.Return(buffer);
}
```

### MemoryPool<T>

`MemoryPool<T>` wraps `ArrayPool<T>` and returns `IMemoryOwner<T>` for RAII-style lifetime management:

```csharp
// MemoryPool returns IMemoryOwner<T> -- dispose to return
using IMemoryOwner<byte> owner = MemoryPool<byte>.Shared.Rent(8192);
Memory<byte> buffer = owner.Memory;

// Slice to exact size (owner.Memory may be larger)
int bytesRead = await stream.ReadAsync(buffer[..8192], ct);
await ProcessAsync(buffer[..bytesRead], ct);
// Dispose returns the underlying array to the pool
```

### Pool Usage Guidelines

| Guideline | Rationale |
|-----------|-----------|
| Always return rented buffers in `finally` or `using` | Leaked buffers defeat the purpose of pooling |
| Slice to exact size before processing | Rented arrays may be larger than requested |
| Use `clearArray: true` for sensitive data | Pool reuse could expose secrets to other consumers |
| Do not cache rented arrays in long-lived fields | Holds pool buffers indefinitely, reducing availability |
| Prefer `MemoryPool<T>` over raw `ArrayPool<T>` | Disposal-based lifetime is harder to misuse |


## Weak References and Caching

### WeakReference<T>

Weak references allow the GC to collect the target object when no strong references remain. Use for caches where reclamation under memory pressure is acceptable.

```csharp
public sealed class ImageCache
{
    private readonly ConcurrentDictionary<string, WeakReference<byte[]>> _cache = new();

    public byte[]? TryGet(string key)
    {
        if (_cache.TryGetValue(key, out var weakRef)
            && weakRef.TryGetTarget(out var data))
        {
            return data;
        }
        return null;
    }

    public void Set(string key, byte[] data)
    {
        _cache[key] = new WeakReference<byte[]>(data);
    }

    // Periodically clean up dead references
    public void Purge()
    {
        foreach (var key in _cache.Keys)
        {
            if (_cache.TryGetValue(key, out var weakRef)
                && !weakRef.TryGetTarget(out _))
            {
                _cache.TryRemove(key, out _);
            }
        }
    }
}
```

### When to Use Weak References

- Large object caches where memory pressure should trigger eviction
- Caches for expensive-to-compute but recreatable data (image thumbnails, rendered templates)
- Do NOT use for small objects -- the `WeakReference<T>` overhead outweighs the benefit

For most caching scenarios, prefer `MemoryCache` with size limits and expiration policies. Weak references are a last resort when you need GC-driven eviction.


## Finalizers vs IDisposable

### IDisposable (Preferred)

Implement `IDisposable` to release unmanaged resources deterministically:

```csharp
public sealed class NativeBufferWrapper : IDisposable
{
    private IntPtr _handle;
    private bool _disposed;

    public NativeBufferWrapper(int size)
    {
        _handle = Marshal.AllocHGlobal(size);
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;

        Marshal.FreeHGlobal(_handle);
        _handle = IntPtr.Zero;
        // No GC.SuppressFinalize needed -- no finalizer
    }
}
```

### Finalizer (Safety Net Only)

Finalizers run on the GC finalizer thread when an object is collected. They are a safety net for unmanaged resources that were not disposed explicitly.

```csharp
public class UnmanagedResourceHolder : IDisposable
{
    private IntPtr _handle;
    private bool _disposed;

    public UnmanagedResourceHolder(int size)
    {
        _handle = Marshal.AllocHGlobal(size);
    }

    ~UnmanagedResourceHolder()
    {
        Dispose(disposing: false);
    }

    public void Dispose()
    {
        Dispose(disposing: true);
        GC.SuppressFinalize(this);
    }

    protected virtual void Dispose(bool disposing)
    {
        if (_disposed) return;
        _disposed = true;

        if (disposing)
        {
            // Free managed resources
        }

        // Free unmanaged resources
        if (_handle != IntPtr.Zero)
        {
            Marshal.FreeHGlobal(_handle);
            _handle = IntPtr.Zero;
        }
    }
}
```

### Finalizer Costs

| Cost | Impact |
|------|--------|
| Objects with finalizers survive at least one extra GC | Promotes to Gen1/Gen2, increasing memory pressure |
| Finalizer thread is single-threaded | Slow finalizers block all other finalization |
| Execution order is non-deterministic | Cannot depend on other finalizable objects |
| Not guaranteed to run on process exit | Critical cleanup may not execute |

**Rule:** Use `sealed` classes with `IDisposable` (no finalizer) unless you own unmanaged handles. Only add a finalizer as a safety net for unmanaged resources.


## Memory Pressure Notifications

### GC.AddMemoryPressure / RemoveMemoryPressure

Inform the GC about unmanaged memory allocations so it accounts for them in collection decisions:

```csharp
public sealed class NativeImageBuffer : IDisposable
{
    private readonly IntPtr _buffer;
    private readonly long _size;
    private bool _disposed;

    public NativeImageBuffer(long sizeBytes)
    {
        _size = sizeBytes;
        _buffer = Marshal.AllocHGlobal((IntPtr)sizeBytes);
        GC.AddMemoryPressure(sizeBytes);
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;

        Marshal.FreeHGlobal(_buffer);
        GC.RemoveMemoryPressure(_size);
    }
}
```

### GC.GetGCMemoryInfo for Adaptive Behavior

```csharp
// React to memory pressure in application logic
var memoryInfo = GC.GetGCMemoryInfo();
double loadPercent = (double)memoryInfo.MemoryLoadBytes
    / memoryInfo.TotalAvailableMemoryBytes * 100;

if (loadPercent > 85)
{
    logger.LogWarning("High memory pressure: {Load:F1}%", loadPercent);
    // Shed load: reduce cache sizes, reject non-critical requests
}
```


## Memory Profiling

### dotMemory (JetBrains)

dotMemory provides heap snapshots and allocation tracking with a visual UI. Use it for investigating memory leaks and high-allocation hot paths.

**Workflow:**
1. Attach dotMemory to the running process (or launch with profiling enabled)
2. Capture a baseline snapshot after application warm-up
3. Execute the scenario under investigation
4. Capture a second snapshot
5. Compare snapshots to identify retained objects and growth

**Key views:**
- **Sunburst** -- shows allocation tree by type hierarchy
- **Dominator tree** -- shows which objects prevent GC of retained memory
- **Survived objects** -- objects allocated between snapshots that survived GC

### PerfView

PerfView is a free Microsoft tool for detailed GC and allocation analysis. It uses ETW (Event Tracing for Windows) events for low-overhead profiling.

```bash
# Collect GC and allocation events for 30 seconds
PerfView.exe /GCCollectOnly /MaxCollectSec:30 collect

# Collect allocation stacks (higher overhead)
PerfView.exe /ClrEvents:GC+Stack /MaxCollectSec:30 collect
```

**Key PerfView views:**
- **GCStats** -- GC pause times, generation counts, promotion rates, fragmentation
- **GC Heap Alloc Stacks** -- call stacks responsible for allocations
- **Any Stacks** -- CPU sampling for identifying hot methods

### Profiling Workflow

1. **Identify the symptom** -- high memory usage, growing Gen2, frequent Gen2 collections, LOH fragmentation
2. **Monitor with dotnet-counters** (see `references/profiling.md`) to confirm GC metrics match the symptom
3. **Profile with dotMemory or PerfView** to identify the objects and allocation sites
4. **Apply fixes** -- pool buffers, use Span<T>, reduce allocations, fix leaks
5. **Validate with BenchmarkDotNet** (see [skill:dotnet-testing]) `[MemoryDiagnoser]` to confirm improvement
6. **Monitor in production** via OpenTelemetry runtime metrics (see [skill:dotnet-devops])


## Agent Gotchas

1. **Do not default to workstation GC for ASP.NET Core applications** -- server GC is the default and correct choice for web workloads. Workstation GC has lower throughput on multi-core servers. Only override for specific latency-sensitive scenarios.
2. **Do not forget to return ArrayPool buffers** -- leaked pool buffers are worse than regular allocations because they hold pool capacity indefinitely. Always use `try/finally` or `IMemoryOwner<T>` with `using`.
3. **Do not assume rented arrays are the requested size** -- `ArrayPool<T>.Rent()` may return an array larger than requested. Always slice to the exact size needed before processing.
4. **Do not add finalizers to classes that only use managed resources** -- finalizers promote objects to Gen1/Gen2 and add overhead to GC. Use `sealed class` with `IDisposable` (no finalizer) for managed-only cleanup.
5. **Do not call GC.Collect() in production code** -- forcing full collections causes long pauses and disrupts the GC's dynamic tuning. Use `GC.AddMemoryPressure()` to hint at unmanaged memory instead.
6. **Do not ignore LOH fragmentation** -- large arrays (>= 85,000 bytes) allocated and freed repeatedly fragment the LOH. Use `ArrayPool<T>` to rent and return large buffers instead of allocating new arrays.
7. **Do not cache IMemoryOwner<T> in long-lived fields without disposal tracking** -- the underlying pooled buffer is held indefinitely, preventing pool reuse. Transfer ownership explicitly or limit cache lifetimes.


## References

- [Fundamentals of garbage collection](https://learn.microsoft.com/en-us/dotnet/standard/garbage-collection/fundamentals)
- [Workstation and server GC](https://learn.microsoft.com/en-us/dotnet/standard/garbage-collection/workstation-server-gc)
- [Large Object Heap](https://learn.microsoft.com/en-us/dotnet/standard/garbage-collection/large-object-heap)
- [Pinned Object Heap](https://devblogs.microsoft.com/dotnet/internals-of-the-poh/)
- [Memory<T> and Span<T> usage guidelines](https://learn.microsoft.com/en-us/dotnet/standard/memory-and-spans/memory-t-usage-guidelines)
- [ArrayPool<T> class](https://learn.microsoft.com/en-us/dotnet/api/system.buffers.arraypool-1)
- [GC.GetGCMemoryInfo](https://learn.microsoft.com/en-us/dotnet/api/system.gc.getgcmemoryinfo)
- [PerfView GC analysis tutorial](https://learn.microsoft.com/en-us/dotnet/core/diagnostics/debug-highcpu?tabs=windows#analyze-with-perfview)
- [Stephen Toub -- Performance Improvements in .NET series](https://devblogs.microsoft.com/dotnet/author/toub/) (published annually)
- [IDisposable pattern](https://learn.microsoft.com/en-us/dotnet/standard/garbage-collection/implementing-dispose)
