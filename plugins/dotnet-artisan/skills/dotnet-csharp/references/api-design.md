# API Design

Design-time principles for creating public .NET APIs that are intuitive, consistent, and forward-compatible. Covers naming conventions for API surface, parameter ordering, return type selection, error reporting strategies, extension points, and wire compatibility for serialized types. This skill addresses the **design decisions** that make APIs compatible and usable in the first place, before enforcement tooling gets involved.

**Version assumptions:** .NET 8.0+ baseline. Examples use modern C# features (primary constructors, collection expressions) where appropriate.

## Naming Conventions for API Surface

### Type Naming

Follow the .NET Framework Design Guidelines naming patterns for public API types:

| Type Kind | Suffix Pattern | Example |
|-----------|---------------|---------|
| Base class | `Base` suffix only for abstract base types | `ValidatorBase` |
| Interface | `I` prefix | `IWidgetFactory` |
| Exception | `Exception` suffix | `WidgetNotFoundException` |
| Attribute | `Attribute` suffix | `RequiredPermissionAttribute` |
| Event args | `EventArgs` suffix | `WidgetCreatedEventArgs` |
| Options/config | `Options` suffix | `WidgetServiceOptions` |
| Builder | `Builder` suffix | `WidgetBuilder` |

### Method Naming

| Pattern | Convention | Example |
|---------|-----------|---------|
| Synchronous | Verb or verb phrase | `Calculate()`, `GetWidget()` |
| Asynchronous | `Async` suffix | `CalculateAsync()`, `GetWidgetAsync()` |
| Boolean query | `Is`/`Has`/`Can` prefix | `IsValid()`, `HasPermission()` |
| Try pattern | `Try` prefix, `out` parameter | `TryGetWidget(int id, out Widget widget)` |
| Factory | `Create` prefix | `CreateWidget()`, `CreateWidgetAsync()` |
| Conversion | `To`/`From` prefix | `ToDto()`, `FromEntity()` |

### Avoid Abbreviations in Public API

Spell out words in public APIs even if internal code uses abbreviations. Public APIs are consumed by developers who may not share the team's domain shorthand:

```csharp
// WRONG -- abbreviations in public surface
public IReadOnlyList<TxnResult> GetRecentTxns(int cnt);

// CORRECT -- spelled out for clarity
public IReadOnlyList<TransactionResult> GetRecentTransactions(int count);
```

---

## Parameter Ordering

Consistent parameter ordering reduces cognitive load and enables fluent usage patterns across an API surface.

### Standard Order

1. **Target/subject** -- the primary entity being operated on
2. **Required parameters** -- essential inputs without defaults
3. **Optional parameters** -- inputs with sensible defaults
4. **Cancellation token** -- always last (convention enforced by CA1068)

```csharp
// Consistent ordering across the API surface
public Task<Widget> GetWidgetAsync(
    int widgetId,                              // 1. Target
    WidgetOptions options,                     // 2. Required
    bool includeHistory = false,               // 3. Optional
    CancellationToken cancellationToken = default); // 4. Always last

public Task<Widget> UpdateWidgetAsync(
    int widgetId,                              // 1. Target
    WidgetUpdateRequest request,               // 2. Required
    bool validateFirst = true,                 // 3. Optional
    CancellationToken cancellationToken = default); // 4. Always last
```

### Overload Progression

Design overloads as a progression from simple to detailed. Each overload should delegate to the next more specific one:

```csharp
// Simple -- sensible defaults
public Task<Widget> GetWidgetAsync(int widgetId,
    CancellationToken cancellationToken = default)
    => GetWidgetAsync(widgetId, WidgetOptions.Default, cancellationToken);

// Detailed -- full control
public Task<Widget> GetWidgetAsync(int widgetId,
    WidgetOptions options,
    CancellationToken cancellationToken = default);
```

---

## Return Type Selection

### When to Return What

| Scenario | Return Type | Rationale |
|----------|------------|-----------|
| Single entity, always exists | `Widget` | Throw if not found |
| Single entity, may not exist | `Widget?` | Nullable reference type communicates optionality |
| Collection, possibly empty | `IReadOnlyList<Widget>` | Immutable, indexable, communicates no mutation |
| Streaming results | `IAsyncEnumerable<Widget>` | Avoids buffering entire result set |
| Operation result with detail | `Result<Widget>` / discriminated union | Rich error info without exceptions |
| Void with async | `Task` | Never `async void` except event handlers |
| Frequently synchronous completion | `ValueTask<Widget>` | Avoids Task allocation on cache hits |

### Prefer IReadOnlyList Over IEnumerable for Materialized Collections

```csharp
// WRONG -- caller does not know if result is materialized or lazy
public IEnumerable<Widget> GetWidgets();

// CORRECT -- signals materialized, indexable collection
public IReadOnlyList<Widget> GetWidgets();

// CORRECT -- signals streaming/lazy evaluation explicitly
public IAsyncEnumerable<Widget> GetWidgetsStreamAsync(
    CancellationToken cancellationToken = default);
```

### The Try Pattern

Use the Try pattern for operations that have a common, non-exceptional failure mode:

```csharp
// Parsing, lookup, validation -- failure is expected, not exceptional
public bool TryGetWidget(int widgetId, [NotNullWhen(true)] out Widget? widget);

// Async Try pattern -- return nullable instead of out parameter
public Task<Widget?> TryGetWidgetAsync(int widgetId,
    CancellationToken cancellationToken = default);
```

---

## Error Reporting Strategies

### Exception Hierarchy

Design exception types that enable callers to catch at the right granularity:

```csharp
// Base exception for the library -- callers can catch all library errors
public class WidgetServiceException : Exception
{
    public WidgetServiceException(string message) : base(message) { }
    public WidgetServiceException(string message, Exception inner) : base(message, inner) { }
}

// Specific exceptions derive from the base
public class WidgetNotFoundException : WidgetServiceException
{
    public int WidgetId { get; }
    public WidgetNotFoundException(int widgetId)
        : base($"Widget {widgetId} not found.") => WidgetId = widgetId;
}

public class WidgetValidationException : WidgetServiceException
{
    public IReadOnlyList<string> Errors { get; }
    public WidgetValidationException(IReadOnlyList<string> errors)
        : base("Widget validation failed.") => Errors = errors;
}
```

### When to Use Exceptions vs Return Values

| Approach | When to Use |
|----------|------------|
| Throw exception | Unexpected failures, programming errors, infrastructure failures |
| Return `null` / `default` | "Not found" is a normal, expected outcome (query patterns) |
| Try pattern (`bool` + `out`) | Parsing or validation where failure is common and synchronous |
| Result object | Multiple failure modes that callers need to distinguish without try/catch |

### Argument Validation

Validate public API entry points immediately and throw the standard .NET exceptions:

```csharp
public Widget CreateWidget(string name, decimal price)
{
    ArgumentException.ThrowIfNullOrWhiteSpace(name);
    ArgumentOutOfRangeException.ThrowIfNegativeOrZero(price);

    // Proceed with creation
    return new Widget(name, price);
}
```

Use `ArgumentException.ThrowIfNullOrWhiteSpace` (.NET 8+) and `ArgumentOutOfRangeException.ThrowIfNegativeOrZero` (.NET 8+) instead of manual null checks with `throw new ArgumentNullException(...)`. These throw helpers are optimized by the JIT (no delegate allocation, better inlining).

---

## Extension Points

### Designing for Extensibility Without Inheritance

Prefer composition and interfaces over class inheritance for extension points:

```csharp
// GOOD -- interface-based extension point
public interface IWidgetValidator
{
    ValueTask<bool> ValidateAsync(Widget widget, CancellationToken ct = default);
}

// GOOD -- delegate-based extension for simple hooks
public class WidgetServiceOptions
{
    public Func<Widget, CancellationToken, ValueTask>? OnWidgetCreated { get; set; }
}

// GOOD -- builder pattern for complex configuration
public sealed class WidgetServiceBuilder
{
    private readonly List<IWidgetValidator> _validators = [];

    public WidgetServiceBuilder AddValidator(IWidgetValidator validator)
    {
        _validators.Add(validator);
        return this;
    }

    public WidgetServiceBuilder AddValidator(
        Func<Widget, CancellationToken, ValueTask<bool>> validator)
    {
        _validators.Add(new DelegateValidator(validator));
        return this;
    }

    public WidgetService Build() => new(_validators);
}
```

### Extension Method Guidelines

| Guideline | Rationale |
|-----------|-----------|
| Place extensions in the same namespace as the type they extend | Discoverable without extra `using` statements |
| Never put extensions in `System` or `System.Linq` | Namespace pollution affects all consumers |
| Prefer instance methods over extensions when you own the type | Extensions are a last resort for types you do not own |
| Keep the extension's `this` parameter as the most specific usable type | `IEnumerable<T>` not `object`; avoids polluting IntelliSense |

---

## Wire Compatibility for Serialized Types

Types that are serialized (JSON, Protobuf, MessagePack) or persisted form an implicit contract. Changing their shape breaks existing clients or stored data.

### Safe Changes (Wire Compatible)

| Change | Why Safe |
|--------|----------|
| Add optional property with default | Old payloads deserialize with default; old clients ignore new field |
| Add new enum member at the end | Existing serialized values map to existing members |
| Rename property with `[JsonPropertyName]` annotation | Wire name stays the same |

### Breaking Changes (Wire Incompatible)

| Change | Impact |
|--------|--------|
| Remove or rename property (without annotation) | Old payloads lose data; old clients send unrecognized fields |
| Change property type | Deserialization failure or silent data loss |
| Reorder enum members (for integer-serialized enums) | Existing stored integers map to wrong members |
| Change from class to struct or vice versa | Serializer behavior changes (null handling, default values) |

### Defensive Serialization Design

```csharp
// Version-tolerant DTO with explicit wire names
public sealed class WidgetDto
{
    [JsonPropertyName("id")]
    public int Id { get; init; }

    [JsonPropertyName("name")]
    public required string Name { get; init; }

    // V2 addition -- optional with default, old payloads work fine
    [JsonPropertyName("category")]
    public string? Category { get; init; }

    // V3 addition -- use JsonIgnoreCondition to exclude defaults from wire
    [JsonPropertyName("priority")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingDefault)]
    public int Priority { get; init; }
}
```

### Enum Serialization Strategy

```csharp
// GOOD -- string serialization is rename-safe and human-readable
[JsonConverter(typeof(JsonStringEnumConverter))]
public enum WidgetStatus
{
    Draft,
    Active,
    Archived
}

// RISKY -- integer serialization breaks when members are reordered or inserted
// Only use when wire format size is critical and members are append-only
public enum WidgetPriority
{
    Low = 0,
    Medium = 1,
    High = 2
    // New members MUST go at the end with explicit values
}
```

---

## API Design Checklist

Before shipping a new public API, verify each concern:

1. **Naming** -- follows .NET naming conventions, no abbreviations, consistent with rest of API surface
2. **Parameters** -- ordered (target, required, optional, CancellationToken), no more than ~5 parameters (use options object for complex APIs)
3. **Return types** -- appropriate for the scenario (nullable for optional, IReadOnlyList for collections, Task/ValueTask for async)
4. **Error handling** -- clear exception types, argument validation at entry points, Try pattern where failure is expected
5. **Extension points** -- interfaces or delegates, not virtual methods on concrete classes
6. **Wire safety** -- serialized types use explicit property names, additive-only evolution, enum strategy documented
7. **Compatibility** -- changes reviewed against [skill:dotnet-api] rules before release

---

## Agent Gotchas

1. **Do not use abbreviations in public API names** -- spell out words even when internal code uses shorthand. Public APIs are consumed by developers outside the team who do not share the domain vocabulary.
2. **Do not place CancellationToken before optional parameters** -- CA1068 enforces CancellationToken as the last parameter. Placing it earlier breaks the standard ordering convention and triggers analyzer warnings.
3. **Do not return mutable collections from public APIs** -- return `IReadOnlyList<T>` or `IReadOnlyCollection<T>` instead of `List<T>` or `IList<T>`. Mutable return types allow callers to corrupt internal state.
4. **Do not change serialized property names without `[JsonPropertyName]` annotations** -- renaming a C# property without preserving the wire name breaks all existing serialized data and API clients.
5. **Do not add required parameters to existing public methods** -- this is a source-breaking change. Add a new overload or use optional parameters with defaults instead.
6. **Do not use `async void` in API surface** -- return `Task` or `ValueTask`. The only valid `async void` is framework event handlers. See `references/async-patterns.md`.
7. **Do not design exception hierarchies without a base library exception** -- callers need a single catch point for all library errors. Always provide a base exception type that specific exceptions derive from.
8. **Do not put extension methods in the `System` namespace** -- namespace pollution affects every file in every consumer project. Use the library's own namespace or a dedicated `.Extensions` sub-namespace.

---

## Prerequisites

- .NET 8.0+ SDK
- Familiarity with C# naming conventions (see `references/coding-standards.md`)
- Understanding of binary/source compatibility concepts (see [skill:dotnet-api])
- System.Text.Json for wire compatibility examples

---

## References

- [Framework Design Guidelines (Microsoft Learn)](https://learn.microsoft.com/dotnet/standard/design-guidelines/)
- [API design best practices (Microsoft REST API Guidelines)](https://github.com/microsoft/api-guidelines)
- [Breaking changes reference](https://learn.microsoft.com/dotnet/core/compatibility/categories)
- [System.Text.Json serialization](https://learn.microsoft.com/dotnet/standard/serialization/system-text-json/overview)
- [CA1068: CancellationToken parameters must come last](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1068)
