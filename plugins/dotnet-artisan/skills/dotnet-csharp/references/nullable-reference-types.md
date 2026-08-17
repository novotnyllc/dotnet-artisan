# Nullable Reference Types

Nullable reference type (NRT) annotation strategies, migration guidance for legacy codebases, and the most common annotation mistakes AI agents make. NRT is enabled by default in all modern .NET templates (net6.0+), but many existing codebases still need migration.

Cross-references: `references/coding-standards.md` for null-handling style, `references/modern-patterns.md` for pattern matching with nulls.

---

## Quick Reference: NRT Defaults by TFM

| TFM | `<Nullable>` default | Notes |
|-----|---------------------|-------|
| net8.0+ | `enable` (in templates) | New projects have NRT enabled by default |
| net6.0/net7.0 | `enable` (in templates) | Same as net8.0 |
| netstandard2.0/2.1 | not set | Must opt in explicitly |
| net48 / older | not set | Must opt in explicitly |

**Important:** The TFM does not enforce NRT -- the `<Nullable>enable</Nullable>` MSBuild property does. Legacy projects upgraded to net8.0 may not have it enabled.

---

## Enabling NRT

### Project-Wide (Recommended)

```xml
<!-- In .csproj or Directory.Build.props -->
<PropertyGroup>
  <Nullable>enable</Nullable>
</PropertyGroup>
```

### Per-File (Migration)

```csharp
#nullable enable   // top of file -- enables NRT for this file only
```

### Migration Strategy

For large codebases, enable NRT incrementally:

1. Set `<Nullable>enable</Nullable>` in the project
2. Add `#nullable disable` at the top of every existing file (script or IDE tooling)
3. Remove `#nullable disable` file-by-file, fixing warnings as you go
4. Track progress: count remaining `#nullable disable` directives

---

## Annotation Patterns

### Nullable and Non-Nullable

```csharp
public class UserService
{
    // Non-nullable: must never be null
    private readonly IUserRepository _repo;

    // Nullable: explicitly may be null
    public User? FindByEmail(string email)
    {
        return _repo.FindByEmail(email); // may return null
    }

    // Non-nullable parameter: caller must provide non-null
    public async Task<User> GetByIdAsync(int id, CancellationToken ct = default)
    {
        return await _repo.GetByIdAsync(id, ct)
            ?? throw new NotFoundException($"User {id} not found");
    }
}
```

### Nullable Attributes

Use attributes from `System.Diagnostics.CodeAnalysis` to express nullability contracts the compiler cannot infer:

```csharp
using System.Diagnostics.CodeAnalysis;

// Output is non-null when method returns true
public bool TryGetValue(string key, [NotNullWhen(true)] out string? value)
{
    value = _dict.GetValueOrDefault(key);
    return value is not null;
}

// Guarantees member is non-null after method returns
public class Connection
{
    public string? ConnectionString { get; private set; }

    [MemberNotNull(nameof(ConnectionString))]
    public void Initialize(string connectionString)
    {
        ConnectionString = connectionString
            ?? throw new ArgumentNullException(nameof(connectionString));
    }
}

// Return is non-null if input is non-null
[return: NotNullIfNotNull(nameof(input))]
public static string? Trim(string? input)
{
    return input?.Trim();
}

// Parameter must not be null when method returns (for assertion methods)
public static void EnsureNotNull([NotNull] object? value, string paramName)
{
    if (value is null)
    {
        throw new ArgumentNullException(paramName);
    }
}

// Method never returns normally (always throws)
[DoesNotReturn]
public static void ThrowNotFound(string message)
{
    throw new NotFoundException(message);
}
```

### Common Attributes Summary

| Attribute | Where | Meaning |
|-----------|-------|---------|
| `[NotNullWhen(true)]` | `out` parameter | Non-null when method returns `true` |
| `[NotNullWhen(false)]` | `out` parameter | Non-null when method returns `false` |
| `[MemberNotNull]` | method | Named member is non-null after call |
| `[MemberNotNullWhen(true)]` | method | Named member is non-null when returns `true` |
| `[NotNullIfNotNull]` | return | Return is non-null if named param is non-null |
| `[NotNull]` | parameter | Parameter is non-null after call (assertion) |
| `[DoesNotReturn]` | method | Method never returns (always throws) |
| `[AllowNull]` | parameter/property | Caller may pass null even if type is non-nullable |
| `[DisallowNull]` | parameter/property | Caller must not pass null even if type is nullable |
| `[MaybeNull]` | return/out | Return may be null even if type is non-nullable |
| `[MaybeNullWhen(false)]` | `out` parameter | May be null when method returns `false` |

---

## Agent Gotchas

These are the most common NRT mistakes AI agents make when generating C# code.

### 1. Using `!` (Null-Forgiving Operator) to Silence Warnings

```csharp
// WRONG -- hides real null bugs
var user = _repo.FindByEmail(email)!;  // will throw NRE if null
string name = user!.Name!;            // double suppression is a red flag

// CORRECT -- handle null explicitly
var user = _repo.FindByEmail(email)
    ?? throw new NotFoundException($"User with email {email} not found");
```

The `!` operator should only be used when you have knowledge the compiler cannot verify (e.g., after a debug assertion, in test code with known data).

### 2. Ignoring Nullable Warnings

```csharp
// WRONG -- warning CS8602: Dereference of a possibly null reference
public string GetDisplayName(User? user)
{
    return user.Name; // possible NRE!
}

// CORRECT
public string GetDisplayName(User? user)
{
    return user?.Name ?? "Unknown";
}
```

### 3. Wrong Nullability on Interface Implementations

```csharp
// Interface says nullable
public interface IRepository
{
    User? FindById(int id);
}

// WRONG -- implementation changes contract
public class UserRepository : IRepository
{
    public User FindById(int id) // removed nullable -- inconsistent
    {
        return _db.Users.First(u => u.Id == id);
    }
}

// CORRECT -- preserve nullable contract
public class UserRepository : IRepository
{
    public User? FindById(int id)
    {
        return _db.Users.FirstOrDefault(u => u.Id == id);
    }
}
```

### 4. Missing `[NotNullWhen]` on Try-Pattern Methods

```csharp
// WRONG -- compiler doesn't know result is non-null on success
public bool TryParse(string input, out Order? result)
{
    // ...
}

// After call: result is still Order? even when method returned true

// CORRECT
public bool TryParse(string input, [NotNullWhen(true)] out Order? result)
{
    // ...
}

// After call: result is Order (non-nullable) when method returned true
```

### 5. Nullable Value Types vs Nullable Reference Types Confusion

```csharp
// These are different systems!
int? nullableInt = null;       // Nullable<int> -- always existed
string? nullableStr = null;    // NRT annotation -- compile-time only, no runtime type change

// typeof(int?) != typeof(int), but typeof(string?) == typeof(string)
```

---

## Generic Constraints for Nullability

```csharp
// Constrain to non-nullable reference types
public class Repository<T> where T : class
{
    public T Get(int id) => ...;        // T is non-nullable
    public T? Find(int id) => ...;      // T? is nullable
}

// Allow both nullable and non-nullable
public class Cache<T> where T : notnull
{
    public T GetOrDefault(string key, T defaultValue) => ...;
}

// Allow nullable type parameter (default)
public class Wrapper<T>
{
    public T? Value { get; set; }  // T? behavior depends on whether T is value or reference type
}
```

---

## Collections and Nullability

```csharp
// Dictionary: value might not exist
Dictionary<string, User> users = new();
if (users.TryGetValue(key, out var user))
{
    // user is non-null here (with proper NRT annotations in BCL)
}

// Array/List of nullable items
List<string?> names = ["Alice", null, "Bob"];
foreach (var name in names)
{
    if (name is not null)
    {
        Console.WriteLine(name.Length); // safe
    }
}

// Non-nullable collection with nullable lookup
IReadOnlyList<Order> orders = GetOrders();
Order? first = orders.FirstOrDefault(); // FirstOrDefault returns T? for reference types
```

---

## EF Core and NRT

EF Core respects NRT annotations for required vs optional columns:

```csharp
public class Order
{
    public int Id { get; set; }
    public string CustomerName { get; set; } = "";  // NOT NULL column
    public string? Notes { get; set; }               // NULL column
    public Address Address { get; set; } = null!;    // Required navigation (EF convention)
}
```

**Note:** `= null!` is acceptable for EF Core navigation properties where EF guarantees initialization. This is one of the few valid uses of the null-forgiving operator.

---

## References

- [Nullable reference types (C# reference)](https://learn.microsoft.com/en-us/dotnet/csharp/nullable-references)
- [Attributes for null-state static analysis](https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/attributes/nullable-analysis)
- [Nullable reference type migration](https://learn.microsoft.com/en-us/dotnet/csharp/nullable-migration-strategies)
- [.NET Framework Design Guidelines](https://learn.microsoft.com/en-us/dotnet/standard/design-guidelines/)
