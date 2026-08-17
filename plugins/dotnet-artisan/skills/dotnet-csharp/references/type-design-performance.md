# Type Design and Performance

Upfront type design choices that affect performance throughout an application's lifetime. Covers the struct vs class decision matrix, sealed by default for library types, readonly struct for defensive copy elimination, ref struct and Span\<T\>/Memory\<T\> selection, and collection type selection including FrozenDictionary. This skill focuses on **designing types correctly from the start**, not on optimizing existing code.

**Version assumptions:** .NET 8.0+ baseline. FrozenDictionary (requires .NET 8+) is in-scope by default.

## Struct vs Class Decision Matrix

Choosing between `struct` and `class` at design time has cascading effects on allocation, GC pressure, copying cost, and API shape. Make the decision once, correctly.

### Decision Criteria

| Criterion | Favors `struct` | Favors `class` |
|-----------|----------------|----------------|
| Size | Small (<= 16 bytes ideal, <= 64 bytes acceptable) | Large or variable size |
| Lifetime | Short-lived, method-scoped | Long-lived, shared across scopes |
| Identity | Value equality (two instances with same data are equal) | Reference identity matters |
| Mutability | Immutable (`readonly struct`) | Mutable or complex state transitions |
| Inheritance | Not needed | Requires polymorphism or base class |
| Nullable semantics | `default` is a valid zero state | Needs explicit null to signal absence |
| Collection usage | Stored in arrays/spans (contiguous memory, cache-friendly) | Stored via references (indirection on every access) |

### Size Guidelines

```
<= 16 bytes:  Ideal struct -- fits in two registers, passed efficiently
17-64 bytes:  Acceptable struct -- measure copy cost vs allocation cost
> 64 bytes:   Prefer class -- copying cost outweighs allocation avoidance
```

The 16-byte threshold comes from x64 calling conventions: two register-sized values can be passed in registers without stack spilling. Beyond that, the struct is passed by reference on the stack, and copying becomes the dominant cost.

### Common Types and Their Correct Design

| Type | Correct Choice | Why |
|------|---------------|-----|
| Point2D (8 bytes: two floats) | `readonly struct` | Small, immutable, value semantics |
| Money (16 bytes: decimal + currency enum) | `readonly struct` | Small, immutable, value equality |
| DateRange (16 bytes: two DateOnly) | `readonly struct` | Small, immutable, value semantics |
| Matrix4x4 (64 bytes: 16 floats) | `struct` (with `in` parameters) | Performance-critical math, contiguous arrays |
| CustomerDto (variable: strings, lists) | `class` or `record` | Contains references, variable size |
| HttpRequest context | `class` | Long-lived, shared across middleware |

---

## Sealed by Default

### Why Seal Library Types

For library types (code consumed by other assemblies), seal classes by default:

1. **JIT devirtualization** -- sealed classes enable the JIT to replace virtual calls with direct calls, enabling inlining. See [skill:dotnet-tooling] for benchmarking this effect.
2. **Simpler contracts** -- unsealed classes imply a promise to support inheritance, which constrains future changes.
3. **Fewer breaking changes** -- sealing a class later is a binary-breaking change. Starting sealed and unsealing later is safe.

```csharp
// GOOD -- sealed by default for library types
public sealed class WidgetService
{
    public Widget GetWidget(int id) => new(id, "Default");
}

// Only unseal when inheritance is an intentional design decision
public abstract class WidgetValidatorBase
{
    public abstract bool Validate(Widget widget);

    // Template method pattern -- intentional extension point
    protected virtual void OnValidationComplete(Widget widget) { }
}
```

### When NOT to Seal

| Scenario | Reason |
|----------|--------|
| Abstract base classes | Inheritance is the purpose |
| Framework extensibility points | Consumers need to subclass |
| Test doubles in non-mockable designs | Mocking frameworks need to subclass (prefer interfaces) |
| Application-internal classes with no consumers | Sealing adds no value (no external callers to devirtualize) |

---

## readonly struct

Mark structs `readonly` when all fields are immutable. This eliminates defensive copies the JIT creates when accessing structs through `in` parameters or `readonly` fields.

### The Defensive Copy Problem

```csharp
// NON-readonly struct -- JIT must defensively copy on every method call
public struct MutablePoint
{
    public double X;
    public double Y;
    public double Length() => Math.Sqrt(X * X + Y * Y);
}

// In a readonly context, JIT copies the struct before calling Length()
// because Length() MIGHT mutate X or Y
public double GetLength(in MutablePoint point)
{
    return point.Length(); // Hidden copy here!
}
```

```csharp
// GOOD -- readonly struct: JIT knows no mutation is possible
public readonly struct ImmutablePoint
{
    public double X { get; }
    public double Y { get; }

    public ImmutablePoint(double x, double y) => (X, Y) = (x, y);

    public double Length() => Math.Sqrt(X * X + Y * Y);
}

// No defensive copy -- JIT can call Length() directly on the reference
public double GetLength(in ImmutablePoint point)
{
    return point.Length(); // No copy, direct call
}
```

### readonly struct Checklist

- All fields are `readonly` or `{ get; }` / `{ get; init; }` properties
- No methods mutate state
- Constructor initializes all fields
- Consider `IEquatable<T>` for value comparison without boxing

---

## ref struct and Span/Memory Selection

### ref struct Constraints

`ref struct` types are stack-only: they cannot be boxed, stored in fields of non-ref-struct types, or used in async methods. This constraint enables safe wrapping of `Span<T>`.

### Span\<T\> vs Memory\<T\> Decision

| Criterion | Use `Span<T>` | Use `Memory<T>` |
|-----------|--------------|-----------------|
| Synchronous method | Yes | Yes (but Span is lower overhead) |
| Async method | No (ref struct) | Yes |
| Store in field/collection | No (ref struct) | Yes |
| Pass to callback/delegate | No | Yes |
| Slice without allocation | Yes | Yes |
| Wrap stackalloc buffer | Yes | No |

### Selection Flowchart

```
Will the buffer be used in an async method or stored in a field?
  YES -> Use Memory<T> (convert to Span<T> with .Span for synchronous processing)
  NO  -> Do you need to wrap a stackalloc buffer?
           YES -> Use Span<T>
           NO  -> Prefer Span<T> for lowest overhead; Memory<T> is also acceptable
```

### Practical Pattern

```csharp
// Public API uses Memory<T> for maximum flexibility
public async Task<int> ProcessAsync(ReadOnlyMemory<byte> data,
    CancellationToken ct = default)
{
    // Hand off to awaitable I/O
    await _stream.WriteAsync(data, ct);

    // Convert to Span for synchronous processing
    return CountNonZero(data.Span);
}

// Internal hot-path method uses Span<T> for zero overhead
private static int CountNonZero(ReadOnlySpan<byte> data)
{
    var count = 0;
    foreach (var b in data)
    {
        if (b != 0) count++;
    }
    return count;
}
```

---

## Collection Type Selection

### Decision Matrix

| Scenario | Recommended Type | Rationale |
|----------|-----------------|-----------|
| Build once, read many | `FrozenDictionary<K,V>` / `FrozenSet<T>` | Optimized read layout, immutable after creation (.NET 8+) |
| Build once, read many (pre-.NET 8) | `ImmutableDictionary<K,V>` | Thread-safe, immutable |
| Concurrent read/write | `ConcurrentDictionary<K,V>` | Thread-safe without external locking |
| Frequent modifications | `Dictionary<K,V>` | Lowest per-operation overhead for single-threaded access |
| Ordered data | `SortedDictionary<K,V>` | O(log n) lookup with sorted enumeration |
| Return from public API | `IReadOnlyList<T>` / `IReadOnlyDictionary<K,V>` | Immutable interface communicates intent |
| Stack-allocated small collection | `Span<T>` with stackalloc | Zero GC pressure for small, known-size buffers |

### FrozenDictionary (.NET 8+)

`FrozenDictionary<K,V>` optimizes the internal layout at creation time for maximum read performance. The creation cost is higher than `Dictionary`, but subsequent lookups are faster because the hash table layout is optimized for the specific keys:

```csharp
using System.Collections.Frozen;

// One-time creation cost during initialization
private static readonly FrozenDictionary<string, int> StatusCodes =
    new Dictionary<string, int>
    {
        ["OK"] = 200,
        ["NotFound"] = 404,
        ["InternalServerError"] = 500
    }.ToFrozenDictionary(StringComparer.OrdinalIgnoreCase);

// Optimized lookups on every request
public int GetStatusCode(string name) =>
    StatusCodes.TryGetValue(name, out var code) ? code : -1;
```

**When to use FrozenDictionary:**
- Configuration lookup tables populated at startup
- Static mappings (enum-to-string, error codes, feature flags)
- Any dictionary that is populated once and read many times

**When NOT to use FrozenDictionary:**
- Data that changes at runtime (use `Dictionary` or `ConcurrentDictionary`)
- Small lookups (< 10 items) where the optimization overhead is not recouped

### ImmutableDictionary vs FrozenDictionary

| Characteristic | `ImmutableDictionary` | `FrozenDictionary` |
|---------------|----------------------|--------------------|
| Mutability | Immutable (returns new instance on "Add") | Immutable (no add/remove APIs) |
| Read performance | Good | Excellent (optimized layout) |
| Creation | Fast (incremental building) | Slower (one-time optimization) |
| Evolution | Supports Add/Remove (new instance) | No mutation -- rebuild from scratch |
| Thread safety | Inherently thread-safe | Inherently thread-safe |

---

## Record Types for Data Transfer

### record class vs record struct

| Characteristic | `record class` | `record struct` |
|---------------|---------------|-----------------|
| Allocation | Heap | Stack (or inline in arrays) |
| Equality | Reference type with value equality | Value type with value equality |
| `with` expression | Creates new heap object | Creates new stack copy |
| Nullable | `null` represents absence | `default` represents empty state |
| Size | Reference (8 bytes on x64) + heap | Full size on stack |

```csharp
// record class -- heap allocated, good for DTOs passed through layers
public record CustomerDto(string Name, string Email, DateOnly JoinDate);

// readonly record struct -- stack allocated, good for small value objects
public readonly record struct Money(decimal Amount, string Currency);

// Use readonly record struct when:
// 1. Size <= ~64 bytes
// 2. Value semantics are desired
// 3. High-throughput scenarios where allocation matters
```

---

## Agent Gotchas

1. **Do not default to `class` for every type** -- evaluate the struct vs class decision matrix. Small, immutable value objects (coordinates, money, date ranges) should be `readonly struct` to avoid unnecessary heap allocations.
2. **Do not create non-readonly structs** -- mutable structs cause subtle bugs (defensive copies, lost mutations on copy). If a struct needs mutation, reconsider whether it should be a class. Always mark structs `readonly`.
3. **Do not use `Span<T>` in async methods** -- `Span<T>` is a `ref struct` and cannot cross `await` boundaries. Use `Memory<T>` for async code and convert to `Span<T>` via `.Span` for synchronous processing sections.
4. **Do not use `FrozenDictionary` for mutable data** -- it has no add/remove APIs. It is designed for build-once-read-many scenarios. Use `Dictionary<K,V>` or `ConcurrentDictionary<K,V>` for data that changes at runtime.
5. **Do not seal abstract classes or classes designed as extension points** -- sealing is a design-time decision for concrete types. Abstract classes and intentional base classes must remain unsealed.
6. **Do not make large structs (> 64 bytes) without measuring** -- large structs are expensive to copy. If passed by value (no `in` modifier), they may be slower than a heap-allocated class. Benchmark with [skill:dotnet-tooling].
7. **Do not use `Dictionary<K,V>` for static lookup tables in hot paths** -- if the dictionary is populated at startup and never modified, use `FrozenDictionary` for optimized read performance. Requires .NET 8+.
8. **Do not forget `in` parameter for large readonly structs** -- without `in`, the struct is copied on every method call. With `in` on a `readonly struct`, the JIT passes by reference with no defensive copy.

---

## Prerequisites

- .NET 8.0+ SDK (required for `FrozenDictionary`, `FrozenSet`)
- Understanding of GC generations and heap behavior (see [skill:dotnet-tooling])
- Familiarity with performance measurement (see [skill:dotnet-tooling])
- `System.Collections.Frozen` namespace (.NET 8+)
- `System.Collections.Immutable` namespace

---

## References

- [Framework Design Guidelines: Type Design](https://learn.microsoft.com/dotnet/standard/design-guidelines/type)
- [Choosing between class and struct](https://learn.microsoft.com/dotnet/standard/design-guidelines/choosing-between-class-and-struct)
- [FrozenDictionary class](https://learn.microsoft.com/dotnet/api/system.collections.frozen.frozendictionary-2)
- [ref struct types](https://learn.microsoft.com/dotnet/csharp/language-reference/builtin-types/ref-struct)
- [Span\<T\> usage guidelines](https://learn.microsoft.com/dotnet/standard/memory-and-spans/memory-t-usage-guidelines)
- [Records (C# reference)](https://learn.microsoft.com/dotnet/csharp/language-reference/builtin-types/record)
