# .NET Releases

Quick reference for .NET and C# versions beyond the model's training data. Always check the project's TFM to determine which features are available.

## Version Matrix

| TFM | C# | Support | Status |
|-----|-----|---------|--------|
| net8.0 | 12 | LTS (Nov 2026) | Stable |
| net9.0 | 13 | STS (May 2026) | Stable |
| net10.0 | 14 | LTS (Nov 2028) | Stable (Nov 2025) |
| net11.0 | 15 | STS | Preview 1 |

## C# 14 Features (net10.0)

### Extension members (`extension` blocks)

New syntax for extension properties, static extension methods, and extension operators. Replaces the old `static class` pattern for new extension member types.

```csharp
implicit extension EnumerableExtensions for IEnumerable<TSource>
{
    public bool IsEmpty => !this.Any();
}

explicit extension EnumerableStaticExtensions for IEnumerable<TSource>
{
    public static IEnumerable<TSource> Identity => [];
}
```

### `field` keyword in properties

Access compiler-generated backing field without declaring one explicitly.

```csharp
public string Name
{
    get;
    set => field = value ?? throw new ArgumentNullException(nameof(value));
}
```

### Null-conditional assignment

```csharp
customer?.Order = GetCurrentOrder();  // Only assigns if customer is not null
customer?.Score += 10;                // Compound assignment works too
```

### Other C# 14 features

- **`nameof` with unbound generics**: `nameof(List<>)` returns `"List"`
- **Implicit `Span<T>` conversions**: first-class `Span<T>`/`ReadOnlySpan<T>` support with implicit conversions
- **Lambda parameter modifiers**: `(text, out result) => Int32.TryParse(text, out result)` without type annotations
- **Partial constructors and events**: complements partial methods/properties from C# 13
- **User-defined compound assignment**: custom `+=`, `-=` operators
- **User-defined `++`/`--` operators**

### C# 14 breaking changes

`Span<T>` overloads now applicable in more scenarios. `Enumerable.Reverse` on arrays may resolve to `MemoryExtensions.Reverse` (in-place) when targeting pre-net10.0 with C# 14. Use `ReadOnlySpan<T>` over `Span<T>` for overload safety.

## C# 15 Features (net11.0 preview)

### Union types (`union` declarations)

Type-safe unions with exhaustive pattern matching. A `union` declares a struct that holds one value from a closed set of case types. The compiler generates implicit conversions from each case type and verifies switch exhaustiveness.

```csharp
// Declare a union of existing types
public union Pet(Cat, Dog, Bird);

// Implicit conversion from case types
Pet pet = new Dog("Rex");

// Exhaustive switch — no default/discard needed
string sound = pet switch
{
    Dog d => d.Bark(),
    Cat c => c.Meow(),
    Bird b => b.Chirp(),
};
```

Union declarations lower to a `[Union]` struct with a single `object? Value` property. Value types among the case types are boxed when stored. Types that implement the optional non-boxing access pattern (`TryGetValue`/`HasValue`) allow the compiler to avoid boxing during pattern matching.

```csharp
// Union with methods — body members are preserved
public union OneOrMore<T>(T, IEnumerable<T>)
{
    public IEnumerable<T> AsEnumerable() => Value switch
    {
        IEnumerable<T> list => list,
        T value => [value],
    };
}
```

Key behaviors:

- **Union conversions**: Implicit conversion from each case type to the union type (`Pet pet = dog;`)
- **Union matching**: Patterns unwrap the union's `Value` automatically (`pet is Dog d` checks `pet.Value`)
- **Union exhaustiveness**: Switch expressions are exhaustive when all case types are handled — no fallback required
- **Nullability tracking**: Null state of `Value` flows from creation through pattern matching
- **Hand-coded unions**: Any class/struct with `[Union]` attribute that follows the union pattern gets union behaviors. The pattern requires: single-parameter public constructors (or static `Create` factory methods on a union member provider), each contributing one case type, plus a `Value` property of type `object?` (or `object`). Useful for custom storage strategies or adapting existing types.

Restrictions on union declarations: no instance fields, auto-properties, or field-like events. Explicitly declared constructors must delegate to a generated union constructor via `this(...)`.

### Collection expression arguments (`with()`)

Pass constructor arguments (capacity, comparers) inside collection expressions.

```csharp
List<string> names = [with(capacity: 100), "Alice", "Bob"];
HashSet<string> set = [with(StringComparer.OrdinalIgnoreCase), "Hello", "HELLO"];
```

Early preview — feature set will expand before November 2026 release.

## .NET 10 Runtime and Library Highlights

- **JIT**: Array interface devirtualization, improved inlining (try-finally can inline), better loop inversion, stack allocation of closures
- **NativeAOT**: Type preinitializer supports all `conv.*`/`neg` opcodes
- **Arm64**: Dynamic write-barrier switching (8-20% GC pause improvement)
- **Crypto**: Post-quantum cryptography (ML-DSA, HashML-DSA, Composite ML-DSA), AES KeyWrap with Padding
- **Networking**: `WebSocketStream`, TLS 1.3 on macOS
- **JSON**: Disallow duplicate properties, strict serialization, `PipeReader` support
- **SDK**: `dotnet tool exec` for one-shot execution, file-based apps with publish + AOT, container images from console apps

## .NET 10 Framework Highlights

- **ASP.NET Core 10**: Blazor WASM preloading, passkey support for Identity, OpenAPI enhancements, minimal API updates
- **EF Core 10**: Named query filters (multiple filters per entity, selective disabling), LINQ enhancements, performance improvements
- **MAUI 10**: MediaPicker multi-file selection, WebView request interception, Android API 35/36 support
- **SDK**: `dotnet test` with Microsoft.Testing.Platform, `--cli-schema` introspection, native tab-completion scripts

## .NET 11 Preview Highlights

- Updated minimum hardware requirements for x86/x64 and Arm64
- New string/char APIs (Rune-based operations), BFloat16 in BitConverter
- Improved Base64 APIs, new ZIP archive entry methods
- ASP.NET Core 11 preview features (see release notes)

## What This Means for Code Generation

When generating code for a detected TFM:

- **net10.0+**: Prefer `field` keyword over explicit backing fields. Use extension blocks for new extension members. Use null-conditional assignment. Use `ReadOnlySpan<T>` implicit conversions where applicable.
- **net9.0**: Use C# 13 features (params collections, `Lock` type, partial properties). Do not use C# 14 features.
- **net8.0**: Use C# 12 features (primary constructors, collection expressions). Do not use C# 13+ features.
- **Preview (net11.0)**: Use `union` declarations for closed type sets, `with()` in collection expressions. Flag as preview.
