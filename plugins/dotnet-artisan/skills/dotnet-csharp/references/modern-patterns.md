# Modern Patterns

Modern C# language feature guidance adapted to the project's target framework. Always run [skill:dotnet-tooling] first to determine TFM and C# version.

## Quick Reference: TFM to C# Version

| TFM | C# | Key Language Features |
|-----|----|-----------------------|
| net8.0 | 12 | Primary constructors, collection expressions, alias any type |
| net9.0 | 13 | `params` collections, `Lock` type, partial properties |
| net10.0 | 14 | `field` keyword, extension blocks, `nameof` unbound generics |
| net11.0 | 15 (preview) | Collection expression `with()` arguments |

---

## Records

Use records for immutable data transfer objects, value semantics, and domain modeling where equality is based on values rather than identity.

### Record Classes (reference type)

```csharp
// Positional record: concise, immutable, value equality
public record OrderSummary(int OrderId, decimal Total, DateOnly OrderDate);

// With additional members
public record Customer(string Name, string Email)
{
    public string DisplayName => $"{Name} <{Email}>";
}
```

### Record Structs (value type, C# 10+)

```csharp
// Positional record struct: value type with value semantics
public readonly record struct Point(double X, double Y);

// Mutable record struct (rare -- prefer readonly)
public record struct MutablePoint(double X, double Y);
```

### When to Use Records vs Classes

| Use Case | Prefer |
|----------|--------|
| DTOs, API responses | `record` |
| Domain value objects (Money, Email) | `readonly record struct` |
| Entities with identity (User, Order) | `class` |
| High-throughput, small data | `readonly record struct` |
| Inheritance needed | `record` (class-based) |

### Non-destructive Mutation

```csharp
var updated = order with { Total = order.Total + tax };
```

---

## Primary Constructors (C# 12+, net8.0+)

Capture constructor parameters directly in the class/struct body. Parameters become available throughout the type but are **not** fields or properties -- they are captured state.

### For Services (DI injection)

```csharp
public class OrderService(IOrderRepository repo, ILogger<OrderService> logger)
{
    public async Task<Order> GetAsync(int id)
    {
        logger.LogInformation("Fetching order {OrderId}", id);
        return await repo.GetByIdAsync(id);
    }
}
```

### Gotchas

- Primary constructor parameters are **mutable** captures, not `readonly` fields. If immutability matters, assign to a `readonly` field in the body.
- Do not use primary constructors when you need to validate parameters at construction time -- use a traditional constructor with guard clauses instead.
- For records, positional parameters become public properties automatically. For classes/structs, they remain private captures.

```csharp
// Explicit readonly field when immutability matters
public class Config(string connectionString)
{
    private readonly string _connectionString = connectionString
        ?? throw new ArgumentNullException(nameof(connectionString));
}
```

---

## Collection Expressions (C# 12+, net8.0+)

Unified syntax for creating collections with `[...]`.

```csharp
// Array
int[] numbers = [1, 2, 3];

// List
List<string> names = ["Alice", "Bob"];

// Span
ReadOnlySpan<byte> bytes = [0x00, 0xFF];

// Spread operator
int[] combined = [..first, ..second, 99];

// Empty collection
List<int> empty = [];
```

### Collection Expression with Arguments (C# 15 preview, net11.0+)

Specify capacity, comparers, or other constructor arguments:

```csharp
// Capacity hint
List<int> nums = [with(capacity: 1000), ..Generate()];

// Custom comparer
HashSet<string> set = [with(comparer: StringComparer.OrdinalIgnoreCase), "Alice", "bob"];

// Dictionary with comparer
Dictionary<string, int> map = [with(comparer: StringComparer.OrdinalIgnoreCase),
    new("key1", 1), new("key2", 2)];
```

> **net11.0+ only.** Requires `<LangVersion>preview</LangVersion>`. Do not use on earlier TFMs.

---

## Pattern Matching

### Switch Expressions (C# 8+)

```csharp
string GetDiscount(Customer customer) => customer switch
{
    { Tier: "Gold", YearsActive: > 5 } => "30%",
    { Tier: "Gold" } => "20%",
    { Tier: "Silver" } => "10%",
    _ => "0%"
};
```

### List Patterns (C# 11+)

```csharp
bool IsValid(int[] data) => data is [> 0, .., > 0]; // first and last positive

string Describe(int[] values) => values switch
{
    [] => "empty",
    [var single] => $"single: {single}",
    [var first, .., var last] => $"range: {first}..{last}"
};
```

### Type and Property Patterns

```csharp
decimal CalculateShipping(object package) => package switch
{
    Letter { Weight: < 50 } => 0.50m,
    Parcel { Weight: var w } when w < 1000 => 5.00m + w * 0.01m,
    Parcel { IsOversized: true } => 25.00m,
    _ => 10.00m
};
```

---

## `required` Members (C# 11+)

Force callers to initialize properties at construction via object initializers.

```csharp
public class UserDto
{
    public required string Name { get; init; }
    public required string Email { get; init; }
    public string? Phone { get; init; }
}

// Compiler enforces Name and Email
var user = new UserDto { Name = "Alice", Email = "alice@example.com" };
```

Useful for DTOs that need to be deserialized (System.Text.Json honors `required` in .NET 8+).

---

## `field` Keyword (C# 14, net10.0+)

Access the compiler-generated backing field directly in property accessors.

```csharp
public class TemperatureSensor
{
    public double Reading
    {
        get => field;
        set => field = value >= -273.15
            ? value
            : throw new ArgumentOutOfRangeException(nameof(value));
    }
}
```

Replaces the manual pattern of declaring a private field plus a property with custom logic. Use when you need validation or transformation in a setter without a separate backing field.

> **net10.0+ only.** On earlier TFMs, use a traditional private field.

---

## Extension Blocks (C# 14, net10.0+)

Group extension members for a type in a single block.

```csharp
public static class EnumerableExtensions
{
    extension<T>(IEnumerable<T> source) where T : class
    {
        public IEnumerable<T> WhereNotNull()
            => source.Where(x => x is not null);

        public bool IsEmpty()
            => !source.Any();
    }
}
```

> **net10.0+ only.** On earlier TFMs, use traditional `static` extension methods.

---

## Alias Any Type (`using`, C# 12+, net8.0+)

```csharp
using Point = (double X, double Y);
using UserId = System.Guid;

Point origin = (0, 0);
UserId id = UserId.NewGuid();
```

Useful for tuple aliases and domain type aliases without creating a full type.

---

## `params` Collections (C# 13, net9.0+)

`params` now supports additional collection types beyond arrays, including `Span<T>`, `ReadOnlySpan<T>`, and types implementing certain collection interfaces.

```csharp
public void Log(params ReadOnlySpan<string> messages)
{
    foreach (var msg in messages)
        Console.WriteLine(msg);
}

// Callers: compiler may avoid heap allocation with span-based params
Log("hello", "world");
```

> **net9.0+ only.** On net8.0, `params` only supports arrays.

---

## `Lock` Type (C# 13, net9.0+)

Use `System.Threading.Lock` instead of `object` for locking.

```csharp
private readonly Lock _lock = new();

public void DoWork()
{
    lock (_lock)
    {
        // thread-safe operation
    }
}
```

`Lock` provides a `Scope`-based API for advanced scenarios and is more expressive than `lock (object)`.

> **net9.0+ only.** On net8.0, use `private readonly object _gate = new();` and `lock (_gate)`.

---

## Partial Properties (C# 13, net9.0+)

Partial properties enable source generators to define property signatures that users implement, or vice versa.

```csharp
// In generated file
public partial class ViewModel
{
    public partial string Name { get; set; }
}

// In user file
public partial class ViewModel
{
    private string _name = "";
    public partial string Name
    {
        get => _name;
        set => SetProperty(ref _name, value);
    }
}
```

> **net9.0+ only.** See `references/source-generators.md` for generator patterns.

---

## `nameof` for Unbound Generic Types (C# 14, net10.0+)

```csharp
string name = nameof(List<>);      // "List"
string name2 = nameof(Dictionary<,>); // "Dictionary"
```

Useful in logging, diagnostics, and reflection scenarios.

> **net10.0+ only.**

---

## Polyfill Guidance for Multi-Targeting

When targeting multiple TFMs, newer language features may not compile on older targets. Use these approaches:

1. **PolySharp** -- Polyfills compiler-required types (`IsExternalInit`, `RequiredMemberAttribute`, etc.) so language features like `init`, `required`, and `record` work on older TFMs.
2. **Polyfill** -- Polyfills runtime APIs (e.g., `string.Contains(char)` for netstandard2.0).
3. **Conditional compilation** -- Use `#if` for features that cannot be polyfilled:

```csharp
#if NET10_0_OR_GREATER
    // Use field keyword
    public double Value { get => field; set => field = Math.Max(0, value); }
#else
    private double _value;
    public double Value { get => _value; set => _value = Math.Max(0, value); }
#endif
```

See [skill:dotnet-tooling] for comprehensive polyfill guidance.

---

## Knowledge Sources

Feature guidance in this skill is grounded in publicly available language design rationale from:

- **C# Language Design Notes (Mads Torgersen et al.)** -- Design decisions behind each C# version's features. Key rationale relevant to this skill: primary constructors (reducing boilerplate for DI-heavy services), collection expressions (unifying collection initialization syntax), `field` keyword (eliminating backing field ceremony), and extension blocks (grouping extensions by target type). Each feature balances expressiveness with safety -- e.g., primary constructor parameters are intentionally mutable captures (not readonly) to keep the feature simple; use explicit readonly fields when immutability is needed. Source: https://github.com/dotnet/csharplang/tree/main/meetings
- **C# Language Proposals Repository** -- Detailed specifications and design rationale for accepted and proposed features. Source: https://github.com/dotnet/csharplang/tree/main/proposals

> **Note:** This skill applies publicly documented design rationale. It does not represent or speak for the named sources.

## References

- [C# Language Reference](https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/)
- [What's new in C# 12](https://learn.microsoft.com/en-us/dotnet/csharp/whats-new/csharp-12)
- [What's new in C# 13](https://learn.microsoft.com/en-us/dotnet/csharp/whats-new/csharp-13)
- [What's new in C# 14](https://learn.microsoft.com/en-us/dotnet/csharp/whats-new/csharp-14)
- [C# Language Design Notes](https://github.com/dotnet/csharplang/tree/main/meetings)
- [.NET Framework Design Guidelines](https://learn.microsoft.com/en-us/dotnet/standard/design-guidelines/)
