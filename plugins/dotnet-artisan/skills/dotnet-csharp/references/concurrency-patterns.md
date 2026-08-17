# Concurrency Patterns

Thread synchronization primitives, concurrent data structures, and a decision framework for choosing the right concurrency mechanism. Covers `lock`/`Monitor`, `SemaphoreSlim`, `Interlocked`, `ConcurrentDictionary`, `ConcurrentQueue`, `ReaderWriterLockSlim`, and `SpinLock`. This skill is the authoritative source for synchronization and thread-safe data access patterns.

**Version assumptions:** .NET 8.0+ baseline. All primitives covered are available from .NET Core 1.0+ but examples use modern C# idioms.

## Concurrency Primitive Decision Framework

Choose the simplest primitive that meets the requirement. Complexity increases downward:

```
Is the shared state a single scalar (int, long, reference)?
  YES -> Use Interlocked (lock-free, lowest overhead)

Is the shared state a key-value lookup or queue?
  YES -> Use ConcurrentDictionary / ConcurrentQueue (thread-safe by design)

Does the critical section contain `await`?
  YES -> Use SemaphoreSlim (async-compatible via WaitAsync)
  NO  -> Does the critical section need many readers, few writers?
           YES -> Use ReaderWriterLockSlim (only if profiling shows lock contention)
           NO  -> Use lock (simplest, lowest cognitive overhead)

Is the critical section extremely short (< 100 ns) with high contention?
  YES -> Consider SpinLock (advanced, measure first)
```

### Quick Reference Table

| Primitive | Async-Safe | Reentrant | Use Case |
|-----------|-----------|-----------|----------|
| `lock` / `Monitor` | No | Yes (same thread) | Short critical sections without `await` |
| `SemaphoreSlim` | Yes (`WaitAsync`) | No | Async-compatible mutual exclusion, throttling |
| `Interlocked` | N/A (lock-free) | N/A | Atomic scalar operations (increment, compare-exchange) |
| `ConcurrentDictionary<K,V>` | N/A (thread-safe) | N/A | Thread-safe key-value cache/lookup |
| `ConcurrentQueue<T>` | N/A (thread-safe) | N/A | Thread-safe FIFO queue |
| `ReaderWriterLockSlim` | No | Optional (`LockRecursionPolicy`) | Many-readers/few-writers (profile-driven only) |
| `SpinLock` | No | No | Ultra-short critical sections under extreme contention |

---

## lock and Monitor

`lock` is syntactic sugar for `Monitor.Enter`/`Monitor.Exit`. Use it for short, synchronous critical sections.

### Correct Usage

```csharp
public sealed class Counter
{
    private readonly object _lock = new();
    private int _count;

    public void Increment()
    {
        lock (_lock)
        {
            _count++;
        }
    }

    public int GetCount()
    {
        lock (_lock)
        {
            return _count;
        }
    }
}
```

### Lock Object Rules

| Rule | Rationale |
|------|-----------|
| Use a private, dedicated `object` field | Prevents external code from locking on the same object |
| Never lock on `this` | Any external code with a reference can cause deadlocks |
| Never lock on `typeof(T)` | Global lock shared by all code in the AppDomain |
| Never lock on string literals | String interning means different code may share the same reference |
| Never lock on value types | Boxing creates a new object each time -- lock is never acquired |

### Monitor.Wait / Monitor.Pulse

For signaling between threads (producer/consumer without `Channel<T>`):

```csharp
public sealed class BoundedBuffer<T>
{
    private readonly Queue<T> _queue = new();
    private readonly object _lock = new();
    private readonly int _maxSize;

    public BoundedBuffer(int maxSize) => _maxSize = maxSize;

    public void Enqueue(T item)
    {
        lock (_lock)
        {
            while (_queue.Count >= _maxSize)
                Monitor.Wait(_lock);

            _queue.Enqueue(item);
            Monitor.Pulse(_lock);
        }
    }

    public T Dequeue()
    {
        lock (_lock)
        {
            while (_queue.Count == 0)
                Monitor.Wait(_lock);

            var item = _queue.Dequeue();
            Monitor.Pulse(_lock);
            return item;
        }
    }
}
```

For modern code, prefer `Channel<T>` (see `references/channels.md`) over Monitor.Wait/Pulse.

---

## SemaphoreSlim

The only built-in .NET synchronization primitive that supports `await`. Use it whenever a critical section contains async operations.

### Mutual Exclusion (1,1)

```csharp
public sealed class AsyncCache
{
    private readonly SemaphoreSlim _semaphore = new(1, 1);
    private readonly Dictionary<string, object> _cache = new();

    public async Task<T> GetOrAddAsync<T>(string key,
        Func<CancellationToken, Task<T>> factory,
        CancellationToken ct = default)
    {
        await _semaphore.WaitAsync(ct);
        try
        {
            if (_cache.TryGetValue(key, out var existing))
                return (T)existing;

            var value = await factory(ct);
            _cache[key] = value!;
            return value;
        }
        finally
        {
            _semaphore.Release();
        }
    }
}
```

### Throttling (N concurrent operations)

```csharp
public sealed class ThrottledProcessor
{
    private readonly SemaphoreSlim _throttle;

    public ThrottledProcessor(int maxConcurrency)
        => _throttle = new SemaphoreSlim(maxConcurrency, maxConcurrency);

    public async Task ProcessAllAsync(IEnumerable<WorkItem> items,
        CancellationToken ct = default)
    {
        var tasks = items.Select(async item =>
        {
            await _throttle.WaitAsync(ct);
            try
            {
                await ProcessItemAsync(item, ct);
            }
            finally
            {
                _throttle.Release();
            }
        });

        await Task.WhenAll(tasks);
    }

    private Task ProcessItemAsync(WorkItem item, CancellationToken ct) =>
        Task.CompletedTask; // implementation
}
```

### SemaphoreSlim Disposal

`SemaphoreSlim` implements `IDisposable`. Dispose it when the owning object is disposed:

```csharp
public sealed class ManagedResource : IDisposable
{
    private readonly SemaphoreSlim _semaphore = new(1, 1);

    public void Dispose() => _semaphore.Dispose();
}
```

---

## Interlocked Operations

Lock-free atomic operations for scalar values. The lowest-overhead synchronization mechanism.

### Common Operations

```csharp
private int _counter;
private long _totalBytes;
private object? _current;

// Atomic increment / decrement
Interlocked.Increment(ref _counter);
Interlocked.Decrement(ref _counter);

// Atomic add
Interlocked.Add(ref _totalBytes, bytesRead);

// Atomic exchange -- returns the old value
var previous = Interlocked.Exchange(ref _current, newValue);

// Compare-and-swap -- only writes if current value matches expected
var original = Interlocked.CompareExchange(ref _counter,
    newValue: 10,
    comparand: 0); // Sets to 10 only if current value is 0
```

### Volatile Read/Write

For visibility guarantees without atomicity (reading the latest value written by another thread):

```csharp
private int _flag;

// Write with release semantics (all prior writes visible to readers)
Volatile.Write(ref _flag, 1);

// Read with acquire semantics (sees all writes prior to the last Volatile.Write)
var value = Volatile.Read(ref _flag);
```

### Interlocked vs volatile vs lock

| Mechanism | Atomicity | Ordering | Use Case |
|-----------|----------|----------|----------|
| `Interlocked` | Yes | Full fence | Counters, flags, CAS loops |
| `Volatile.Read/Write` | No (single read/write is naturally atomic for aligned <= pointer-size) | Acquire/release | Signal flags, publication patterns |
| `lock` | Yes (for entire block) | Full fence | Multi-step operations on shared state |

---

## ConcurrentDictionary

Thread-safe key-value store. The most commonly used concurrent collection.

### Safe Patterns

```csharp
private readonly ConcurrentDictionary<int, Widget> _cache = new();

// Atomic get-or-add
var widget = _cache.GetOrAdd(id, key => LoadWidget(key));

// Atomic add-or-update
var updated = _cache.AddOrUpdate(id,
    addValueFactory: key => CreateDefault(key),
    updateValueFactory: (key, existing) => existing with { LastAccessed = DateTime.UtcNow });

// Safe removal
if (_cache.TryRemove(id, out var removed))
{
    // Process removed item
}
```

### Delegate Execution Caveats

`GetOrAdd` and `AddOrUpdate` factory delegates may execute multiple times under contention. Only one result is stored, but the factory runs for each competing thread:

```csharp
// WRONG -- factory has side effects (database write) that may run multiple times
var widget = _cache.GetOrAdd(id, key =>
{
    var w = new Widget(key);
    _db.Insert(w); // May execute more than once!
    return w;
});

// CORRECT -- use Lazy<T> to ensure factory runs exactly once
private readonly ConcurrentDictionary<int, Lazy<Widget>> _cache = new();

var widget = _cache.GetOrAdd(id,
    key => new Lazy<Widget>(() => LoadAndSaveWidget(key))).Value;
```

### Composite Operations Are Not Atomic

```csharp
// WRONG -- check-then-act race condition
if (!_cache.ContainsKey(key))
{
    _cache[key] = ComputeValue(key); // Another thread may have added between check and set
}

// CORRECT -- single atomic operation
var value = _cache.GetOrAdd(key, k => ComputeValue(k));
```

---

## ReaderWriterLockSlim

Allows concurrent reads while serializing writes. Only beneficial when reads significantly outnumber writes AND profiling shows `lock` contention on the read path.

```csharp
public sealed class ReadHeavyCache<TKey, TValue> : IDisposable
    where TKey : notnull
{
    private readonly ReaderWriterLockSlim _rwLock = new();
    private readonly Dictionary<TKey, TValue> _data = new();

    public TValue? TryGet(TKey key)
    {
        _rwLock.EnterReadLock();
        try
        {
            return _data.TryGetValue(key, out var value) ? value : default;
        }
        finally
        {
            _rwLock.ExitReadLock();
        }
    }

    public void Set(TKey key, TValue value)
    {
        _rwLock.EnterWriteLock();
        try
        {
            _data[key] = value;
        }
        finally
        {
            _rwLock.ExitWriteLock();
        }
    }

    public void Dispose() => _rwLock.Dispose();
}
```

**When NOT to use ReaderWriterLockSlim:**
- Reads and writes are roughly equal -- `lock` is simpler and faster
- Critical sections contain `await` -- not async-compatible; use `SemaphoreSlim`
- You need a concurrent dictionary -- use `ConcurrentDictionary` directly

---

## SpinLock

A low-level primitive for ultra-short critical sections where thread switching overhead exceeds the wait time. **Measure before using.**

```csharp
private SpinLock _spinLock = new(enableThreadOwnerTracking: false);

public void UpdateCounter()
{
    bool lockTaken = false;
    try
    {
        _spinLock.Enter(ref lockTaken);
        _counter++; // Must be extremely fast -- no I/O, no allocations
    }
    finally
    {
        if (lockTaken)
            _spinLock.Exit(useMemoryBarrier: false);
    }
}
```

**Rules:**
- Never use `SpinLock` for anything longer than ~100 nanoseconds
- Never use in async code (thread affinity required)
- Never use `enableThreadOwnerTracking: true` in production (debug only -- adds overhead)
- `SpinLock` is a `struct` -- always pass by reference, never copy

---

## Thread-Safe Patterns

### Immutable Snapshots

Prefer immutable data for sharing across threads without synchronization:

```csharp
// Thread-safe via immutability -- no locks needed for reads
private ImmutableList<Widget> _widgets = ImmutableList<Widget>.Empty;

public void AddWidget(Widget widget)
{
    // Atomic swap using Interlocked.CompareExchange loop
    ImmutableList<Widget> original, updated;
    do
    {
        original = _widgets;
        updated = original.Add(widget);
    }
    while (Interlocked.CompareExchange(ref _widgets, updated, original) != original);
}

public ImmutableList<Widget> GetWidgets() => _widgets; // No lock needed
```

### Double-Checked Locking

For lazy initialization when `Lazy<T>` is not appropriate:

```csharp
private volatile Widget? _instance;
private readonly object _lock = new();

public Widget GetInstance()
{
    var instance = _instance;
    if (instance is not null)
        return instance;

    lock (_lock)
    {
        instance = _instance;
        if (instance is not null)
            return instance;

        instance = CreateWidget();
        _instance = instance;
        return instance;
    }
}
```

For most cases, prefer `Lazy<T>` which handles this correctly:

```csharp
private readonly Lazy<Widget> _instance = new(() => CreateWidget());
public Widget Instance => _instance.Value;
```

---

## Agent Gotchas

1. **Do not use `lock` inside `async` methods** -- `lock` is thread-affine; the continuation after `await` may resume on a different thread, causing `SynchronizationLockException`. Use `SemaphoreSlim.WaitAsync` instead.
2. **Do not assume `volatile` provides atomicity** -- `volatile` only provides ordering guarantees (acquire/release semantics). Compound operations like `_counter++` are still non-atomic on volatile fields. Use `Interlocked` for atomic operations.
3. **Do not use `ConcurrentDictionary.ContainsKey` followed by indexer set** -- this is a check-then-act race condition. Use `GetOrAdd`, `AddOrUpdate`, or `TryAdd` for atomic composite operations.
4. **Do not use `ReaderWriterLockSlim` without profiling evidence** -- it has higher overhead than `lock` and is only beneficial when reads significantly outnumber writes. Default to `lock` and only switch if contention is measured.
5. **Do not copy `SpinLock`** -- it is a struct. Copying creates a new, unlocked instance. Always pass by reference and store in a field (not a local variable that gets captured by a lambda).
6. **Do not use `lock(this)` or `lock(typeof(T))`** -- external code can acquire the same lock, causing unexpected contention or deadlocks. Always use a private, dedicated lock object.
7. **Do not forget to release `SemaphoreSlim` in `finally`** -- if an exception occurs between `WaitAsync` and `Release`, the semaphore stays acquired permanently, blocking all subsequent callers.
8. **Do not assume `GetOrAdd` factory executes exactly once** -- under contention, the factory delegate may run on multiple threads simultaneously. Only one result is stored, but side effects in the factory execute multiple times. Use `Lazy<T>` wrapping for exactly-once semantics.

---

## Prerequisites

- .NET 8.0+ SDK
- Understanding of async/await patterns (see `references/async-patterns.md`)
- Understanding of producer/consumer patterns (see `references/channels.md`)
- `System.Collections.Concurrent` namespace
- `System.Collections.Immutable` namespace (for immutable collection patterns)

---

## References

- [Threading in C# (Joseph Albahari)](https://www.albahari.com/threading/)
- [Concurrency in C# Cookbook (Stephen Cleary)](https://blog.stephencleary.com/)
- [System.Threading.Interlocked](https://learn.microsoft.com/dotnet/api/system.threading.interlocked)
- [ConcurrentDictionary best practices](https://learn.microsoft.com/dotnet/api/system.collections.concurrent.concurrentdictionary-2)
- [SemaphoreSlim class](https://learn.microsoft.com/dotnet/api/system.threading.semaphoreslim)
- [ReaderWriterLockSlim class](https://learn.microsoft.com/dotnet/api/system.threading.readerwriterlockslim)
