# Performance Patterns

Performance-oriented architecture patterns for .NET applications. Covers zero-allocation coding with Span\<T\> and Memory\<T\>, buffer pooling with ArrayPool\<T\>, struct design for performance (readonly struct, ref struct, in parameters), sealed class devirtualization by the JIT, stack-based allocation with stackalloc, and string handling performance. Focuses on the **why** (performance rationale and measurement) rather than the **how** (language syntax).

**Version assumptions:** .NET 8.0+ baseline. Span\<T\> and Memory\<T\> are available from .NET Core 2.1+ but this skill targets modern usage patterns on .NET 8+.

## Span\<T\> and Memory\<T\> for Zero-Allocation Scenarios

### Why Span\<T\> Matters for Performance

`Span<T>` provides a safe, bounds-checked view over contiguous memory without allocating. It enables slicing arrays, strings, and stack memory without copying. For syntax details see [skill:dotnet-csharp]; this section focuses on performance rationale.

### Zero-Allocation String Processing

```csharp
// BAD: Substring allocates a new string on each call
public static (string Key, string Value) ParseHeader_Allocating(string header)
{
    var colonIndex = header.IndexOf(':');
    return (header.Substring(0, colonIndex), header.Substring(colonIndex + 1).Trim());
}

// GOOD: ReadOnlySpan<char> slicing avoids all allocations
public static (ReadOnlySpan<char> Key, ReadOnlySpan<char> Value) ParseHeader_ZeroAlloc(
    ReadOnlySpan<char> header)
{
    var colonIndex = header.IndexOf(':');
    return (header[..colonIndex], header[(colonIndex + 1)..].Trim());
}
```

Performance impact: for high-throughput parsing (HTTP headers, log lines, CSV rows), Span-based parsing eliminates GC pressure entirely. Measure with `[MemoryDiagnoser]` in [skill:dotnet-testing] -- the `Allocated` column should read `0 B`.

### Memory\<T\> for Async and Storage Scenarios

`Span<T>` cannot be used in async methods or stored on the heap (it is a ref struct). Use `Memory<T>` when you need to:

- Pass buffers to async I/O methods
- Store a slice reference in a field or collection
- Return a memory region from a method for later consumption

```csharp
public async Task<int> ReadAndProcessAsync(Stream stream, Memory<byte> buffer)
{
    var bytesRead = await stream.ReadAsync(buffer);
    var data = buffer[..bytesRead]; // Memory<T> slicing -- no allocation
    return ProcessData(data.Span);  // .Span for synchronous processing
}

private int ProcessData(ReadOnlySpan<byte> data)
{
    var sum = 0;
    foreach (var b in data)
        sum += b;
    return sum;
}
```


## ArrayPool\<T\> for Buffer Pooling

### Why Pool Buffers

Large array allocations (>= 85,000 bytes) go directly to the Large Object Heap (LOH), which is only collected in Gen 2 GC -- expensive and causes pauses. Even smaller arrays add GC pressure in hot paths. `ArrayPool<T>` rents and returns buffers to avoid repeated allocations.

### Usage Pattern

```csharp
using System.Buffers;

public int ProcessLargeData(Stream source)
{
    var buffer = ArrayPool<byte>.Shared.Rent(minimumLength: 81920);
    try
    {
        var bytesRead = source.Read(buffer, 0, buffer.Length);
        // IMPORTANT: Rent may return a larger buffer than requested.
        // Always use bytesRead or the requested length, never buffer.Length.
        return ProcessChunk(buffer.AsSpan(0, bytesRead));
    }
    finally
    {
        ArrayPool<byte>.Shared.Return(buffer, clearArray: true);
        // clearArray: true zeroes the buffer -- use when buffer held sensitive data
    }
}
```

### Common Mistakes

| Mistake | Impact | Fix |
|---------|--------|-----|
| Using `buffer.Length` instead of requested size | Processes uninitialized bytes beyond actual data | Track requested/actual size separately |
| Forgetting to return the buffer | Pool exhaustion, falls back to allocation | Use try/finally or a `using` wrapper |
| Returning a buffer twice | Corrupts pool state | Null out the reference after return |
| Not clearing sensitive data | Security leak from pooled buffers | Pass `clearArray: true` to `Return` |


## readonly struct, ref struct, and in Parameters

### readonly struct -- Defensive Copy Elimination

The JIT must defensively copy non-readonly structs when accessed via `in`, `readonly` fields, or `readonly` methods to prevent mutation. Marking a struct `readonly` guarantees immutability, eliminating these copies:

```csharp
// GOOD: readonly eliminates defensive copies on every access
public readonly struct Point3D
{
    public double X { get; }
    public double Y { get; }
    public double Z { get; }

    public Point3D(double x, double y, double z) => (X, Y, Z) = (x, y, z);

    // readonly struct: JIT knows this cannot mutate, no defensive copy needed
    public double DistanceTo(in Point3D other)
    {
        var dx = X - other.X;
        var dy = Y - other.Y;
        var dz = Z - other.Z;
        return Math.Sqrt(dx * dx + dy * dy + dz * dz);
    }
}
```

Without `readonly`, calling a method on a struct through an `in` parameter forces the JIT to copy the entire struct to protect against mutation. For large structs in tight loops, this eliminates significant overhead.

### ref struct -- Stack-Only Types

`ref struct` types are constrained to the stack. They cannot be boxed, stored in fields, or used in async methods. This enables safe wrapping of Span\<T\>:

```csharp
public ref struct SpanLineEnumerator
{
    private ReadOnlySpan<char> _remaining;

    public SpanLineEnumerator(ReadOnlySpan<char> text) => _remaining = text;

    public ReadOnlySpan<char> Current { get; private set; }

    public bool MoveNext()
    {
        if (_remaining.IsEmpty)
            return false;

        var newlineIndex = _remaining.IndexOf('\n');
        if (newlineIndex == -1)
        {
            Current = _remaining;
            _remaining = default;
        }
        else
        {
            Current = _remaining[..newlineIndex];
            _remaining = _remaining[(newlineIndex + 1)..];
        }
        return true;
    }
}
```

### in Parameters -- Pass-by-Reference Without Mutation

Use `in` for large readonly structs passed to methods. The `in` modifier passes by reference (avoids copying) and prevents mutation:

```csharp
// in parameter: pass by reference, no copy, no mutation allowed
public static double CalculateDistance(in Point3D a, in Point3D b)
    => a.DistanceTo(in b);
```

**When to use `in`:**

| Struct Size | Recommendation |
|-------------|---------------|
| <= 16 bytes | Pass by value (register-friendly, no indirection overhead) |
| > 16 bytes | Use `in` to avoid copy overhead |
| Any size, readonly struct | `in` is safe (no defensive copies) |
| Any size, non-readonly struct | Avoid `in` (defensive copies negate the benefit) |


## Sealed Class Performance Rationale

### JIT Devirtualization

When a class is `sealed`, the JIT can replace virtual method calls with direct calls (devirtualization) because no subclass override is possible. This enables further inlining:

```csharp
// Without sealed: virtual dispatch through vtable
public class OpenService : IProcessor
{
    public virtual int Process(int x) => x * 2;
}

// With sealed: JIT devirtualizes + inlines Process call
public sealed class SealedService : IProcessor
{
    public int Process(int x) => x * 2;
}

public interface IProcessor { int Process(int x); }
```

Verify devirtualization with `[DisassemblyDiagnoser]` in [skill:dotnet-testing]. See [skill:dotnet-csharp] for the project convention of defaulting to sealed classes.

### Performance Impact

Devirtualization + inlining eliminates:
1. **vtable lookup** -- indirect memory access to find the method pointer
2. **Call overhead** -- the actual indirect call instruction
3. **Inlining barrier** -- virtual calls cannot be inlined; sealed methods can

In tight loops and hot paths, the cumulative effect is measurable. For framework/library types that are not designed for extension, always prefer `sealed`.


## stackalloc for Small Stack-Based Allocations

### When to Use stackalloc

`stackalloc` allocates memory on the stack, avoiding GC entirely. Use for small, fixed-size buffers in hot paths:

```csharp
public static string FormatGuid(Guid guid)
{
    // 68 bytes on the stack -- well within safe limits
    Span<char> buffer = stackalloc char[68];
    guid.TryFormat(buffer, out var charsWritten, "D");
    return new string(buffer[..charsWritten]);
}
```

### Safety Guidelines

| Guideline | Rationale |
|-----------|-----------|
| Keep allocations small (< 1 KB typical, < 4 KB absolute maximum) | Stack space is limited (~1 MB default on Windows); overflow crashes the process |
| Use constant or bounded sizes only | Runtime-variable sizes risk stack overflow from malicious/unexpected input |
| Prefer `Span<T>` assignment over raw pointer | Span provides bounds checking; raw pointers do not |
| Fall back to ArrayPool for large/variable sizes | Gracefully handle cases that exceed stack budget |

### Hybrid Pattern: stackalloc with ArrayPool Fallback

```csharp
public static string ProcessData(ReadOnlySpan<byte> input)
{
    const int stackThreshold = 256;
    char[]? rented = null;

    Span<char> buffer = input.Length <= stackThreshold
        ? stackalloc char[stackThreshold]
        : (rented = ArrayPool<char>.Shared.Rent(input.Length));

    try
    {
        var written = Encoding.UTF8.GetChars(input, buffer);
        return new string(buffer[..written]);
    }
    finally
    {
        if (rented is not null)
            ArrayPool<char>.Shared.Return(rented);
    }
}
```

This pattern is used throughout the .NET runtime libraries and is the recommended approach for methods that handle both small and large inputs.


## String Interning and StringComparison Performance

### String Comparison Performance

Ordinal comparisons are significantly faster than culture-aware comparisons because they avoid Unicode normalization:

```csharp
// FAST: ordinal comparison (byte-by-byte)
bool isMatch = str.Equals("expected", StringComparison.Ordinal);
bool containsKey = dict.ContainsKey(key); // Dictionary<string, T> uses ordinal by default

// FAST: case-insensitive ordinal (no culture overhead)
bool isMatchIgnoreCase = str.Equals("expected", StringComparison.OrdinalIgnoreCase);

// SLOW: culture-aware comparison (Unicode normalization, linguistic rules)
bool isMatchCulture = str.Equals("expected", StringComparison.CurrentCulture);
```

**Default guidance:** Use `StringComparison.Ordinal` or `StringComparison.OrdinalIgnoreCase` for internal identifiers, dictionary keys, file paths, and protocol strings. Reserve culture-aware comparison for user-visible text sorting and display.

### String Interning

The CLR interns compile-time string literals automatically. `string.Intern()` can reduce memory for runtime strings that repeat frequently:

```csharp
// Intern frequently-repeated runtime strings to share a single instance
var normalized = string.Intern(headerName.ToLowerInvariant());
```

**Caution:** Interned strings are never garbage collected. Only intern strings from a bounded, known set (HTTP headers, XML element names). Never intern user input or unbounded data.

### Efficient String Building

| Scenario | Recommended Approach | Why |
|----------|---------------------|-----|
| 2-3 concatenations | String interpolation `$"{a}{b}"` | Compiler optimizes to `string.Concat` |
| Loop concatenation | `StringBuilder` | Avoids quadratic allocation |
| Known fixed parts | `string.Create` | Single allocation, Span-based writing |
| High-throughput formatting | `Span<char>` + `TryFormat` | Zero-allocation formatting |

```csharp
// string.Create for single-allocation building
public static string FormatId(int category, int item)
{
    return string.Create(11, (category, item), static (span, state) =>
    {
        state.category.TryFormat(span, out var catWritten);
        span[catWritten] = '-';
        state.item.TryFormat(span[(catWritten + 1)..], out _);
    });
}
```


## Performance Measurement Checklist

Before applying any optimization pattern, measure first. Premature optimization without data leads to complex code with no measurable benefit.

1. **Identify the hot path** -- use [skill:dotnet-testing] to establish a baseline
2. **Measure allocations** -- enable `[MemoryDiagnoser]` and check the `Allocated` column
3. **Apply one pattern at a time** -- change one thing, re-measure, compare to baseline
4. **Check AOT impact** -- if targeting Native AOT (`references/native-aot.md`), verify patterns are trim-safe
5. **Verify with production-like data** -- synthetic benchmarks can miss real-world allocation patterns
6. **Document the tradeoff** -- every optimization trades readability or flexibility for speed; record the measured gain


## Agent Gotchas

1. **Measure before optimizing** -- never apply Span/ArrayPool/stackalloc without a benchmark showing the allocation or latency problem. Premature optimization produces unreadable code for no measurable gain.
2. **Do not use stackalloc with variable sizes from untrusted input** -- stack overflow crashes the process with no exception handler. Always validate bounds or use the hybrid stackalloc/ArrayPool pattern.
3. **Always mark value types `readonly struct` when they are immutable** -- without `readonly`, the JIT generates defensive copies on every `in` parameter access and `readonly` field access, silently negating the performance benefit of using structs.
4. **Return rented ArrayPool buffers in finally blocks** -- forgetting to return starves the pool and causes fallback allocations that negate the benefit.
5. **Use `StringComparison.Ordinal` for internal comparisons** -- omitting the comparison parameter defaults to culture-aware comparison, which is slower and produces surprising results for technical strings (file paths, identifiers).
6. **Sealed classes help performance only when the JIT can see the concrete type** -- if the object is accessed through an interface variable in a non-devirtualizable call site, sealing provides no benefit. Verify with `[DisassemblyDiagnoser]`.
7. **Do not re-teach language syntax** -- reference [skill:dotnet-csharp] for Span/Memory syntax details. This skill focuses on when and why to use these patterns for performance.


## Knowledge Sources

Performance patterns in this skill are grounded in guidance from:

- **Stephen Toub** -- .NET Performance blog series ([devblogs.microsoft.com/dotnet/author/toub](https://devblogs.microsoft.com/dotnet/author/toub/)). Authoritative source on Span\<T\>, ValueTask, ArrayPool, async internals, and runtime performance characteristics.
- **Stephen Cleary** -- Async best practices and concurrent collections guidance. Author of *Concurrency in C# Cookbook*.
- **Nick Chapsas** -- Modern .NET performance patterns and benchmarking methodology.

> These sources inform the patterns and rationale presented above. This skill does not claim to represent or speak for any individual.
