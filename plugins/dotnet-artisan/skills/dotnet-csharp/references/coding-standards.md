# Coding Standards

Modern .NET coding standards based on Microsoft Framework Design Guidelines and C# Coding Conventions. This reference covers naming, file organization, and code style rules that agents should follow when generating or reviewing C# code.

This reference is a baseline dependency that should be loaded before domain-specific C#/.NET references. Load it by default for any task that plans, designs, generates, modifies, or reviews C#/.NET code.

Cross-references: `references/modern-patterns.md` for language feature usage, `references/async-patterns.md` for async naming conventions, `references/solid-principles.md` for SOLID, DRY, and SRP design principles.

## Naming Conventions

| Element | Convention | Example |
|---------|-----------|---------|
| Namespaces | PascalCase, dot-separated | `MyCompany.MyProduct.Core` |
| Classes, Records, Structs | PascalCase | `OrderService`, `OrderSummary` |
| Interfaces | `I` + PascalCase | `IOrderRepository` |
| Methods | PascalCase | `GetOrderAsync` |
| Properties | PascalCase | `OrderDate` |
| Events | PascalCase | `OrderCompleted` |
| Public constants | PascalCase | `MaxRetryCount` |
| Private fields | `_camelCase` | `_orderRepository` |
| Parameters, locals | camelCase | `orderId`, `totalAmount` |
| Type parameters | `T` or `T` + PascalCase | `T`, `TKey`, `TValue` |
| Enum members | PascalCase | `OrderStatus.Pending` |

Additional naming rules:
- Suffix async methods with `Async` (e.g., `GetOrderAsync`, `SaveChangesAsync`).
- Prefix booleans with `is`, `has`, `can`, or `should` (e.g., `IsActive`, `HasOrders`).
- Use plural nouns for collections (e.g., `Orders` not `OrderList`).

---

## File Organization

- **One type per file**, named exactly as the type. Nested types stay in the containing type's file.
- **File-scoped namespaces** (C# 10+): `namespace MyApp.Services;` -- avoid block-scoped namespaces.
- **Using directives** at top of file, outside the namespace. Order: `System.*`, third-party, project namespaces.
- **Directory structure** organized by feature or layer, matching namespace hierarchy.

---

## Code Style Rules

- **Always use braces** for control flow, even for single-line bodies.
- **Expression-bodied members** for single-expression properties and methods: `public string FullName => $"{FirstName} {LastName}";`
- **Use `var`** when type is obvious from right-hand side; use explicit type when not obvious.
- **Null handling**: Prefer `is not null` / `is null` over `!= null` / `== null`. Use null-conditional (`?.`) and null-coalescing (`??`, `??=`) operators.
- **String interpolation** over concatenation or `string.Format`.
- **Explicit access modifiers** always -- never rely on defaults. Order: access, static, extern, new, virtual/abstract/override/sealed, readonly, volatile, async, partial.
- **Seal classes** not designed for inheritance for performance and intent clarity.

---

## CancellationToken Conventions

Accept `CancellationToken` as the last parameter in async methods with `default` as the default value. Always forward the token to downstream async calls:

```csharp
public async Task<Order> GetOrderAsync(int id, CancellationToken ct = default)
{
    return await _repo.GetByIdAsync(id, ct);
}
```

---

## XML Documentation

Add XML docs to public API surfaces. Keep them concise:

```csharp
/// <summary>
/// Retrieves an order by its unique identifier.
/// </summary>
/// <param name="id">The order identifier.</param>
/// <param name="ct">Cancellation token.</param>
/// <returns>The order, or <see langword="null"/> if not found.</returns>
public Task<Order?> GetByIdAsync(int id, CancellationToken ct = default);
```

Do not add XML docs to private/internal members, self-evident members, or test methods.

---

## Analyzer Enforcement

Configure in `Directory.Build.props` for automated enforcement:

```xml
<PropertyGroup>
  <EnforceCodeStyleInBuild>true</EnforceCodeStyleInBuild>
  <AnalysisLevel>latest-all</AnalysisLevel>
  <TreatWarningsAsErrors>true</TreatWarningsAsErrors>
</PropertyGroup>
```

Key `.editorconfig` rules:
```ini
[*.cs]
csharp_style_namespace_declarations = file_scoped:warning
csharp_prefer_braces = true:warning
csharp_style_var_when_type_is_apparent = true:suggestion
dotnet_style_require_accessibility_modifiers = always:warning
csharp_style_prefer_pattern_matching = true:suggestion
```

See `references/editorconfig.md` for full editorconfig configuration. See [skill:dotnet-tooling] for analyzer package setup.

---

## References

- [Framework Design Guidelines](https://learn.microsoft.com/en-us/dotnet/standard/design-guidelines/)
- [C# Coding Conventions](https://learn.microsoft.com/en-us/dotnet/csharp/fundamentals/coding-style/coding-conventions)
- [C# Identifier Naming Rules](https://learn.microsoft.com/en-us/dotnet/csharp/fundamentals/coding-style/identifier-names)
- [.editorconfig for .NET](https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/code-style-rule-options)
