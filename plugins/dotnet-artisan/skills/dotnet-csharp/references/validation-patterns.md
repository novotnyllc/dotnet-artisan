# Validation Patterns

Built-in .NET validation patterns that do not require third-party packages. Covers DataAnnotations attributes, `IValidatableObject` for cross-property validation, `IValidateOptions<T>` for options validation at startup, custom `ValidationAttribute` authoring, and `Validator.TryValidateObject` for manual validation. Prefer these built-in mechanisms as the default; reserve FluentValidation for complex domain rules that outgrow declarative attributes.

## Validation Approach Decision Tree

Choose the validation approach based on complexity:

1. **DataAnnotations** (default) -- declarative `[Required]`, `[Range]`, `[StringLength]`, `[RegularExpression]` attributes. Best for: simple property-level constraints on DTOs, request models, and options classes.
2. **`IValidatableObject`** -- implement `Validate()` for cross-property rules within the same object. Best for: date range comparisons, conditional required fields, business rules that span multiple properties.
3. **Custom `ValidationAttribute`** -- subclass `ValidationAttribute` for reusable property-level rules. Best for: domain-specific constraints (SKU format, postal code, currency code) applied across multiple models.
4. **`IValidateOptions<T>`** -- validate configuration/options classes at startup with access to DI services. Best for: cross-property options checks, environment-dependent validation, fail-fast startup.
5. **FluentValidation** -- third-party library for complex, testable validation with fluent API. Best for: async validators, database-dependent rules, deeply nested object graphs. See `references/input-validation.md` for FluentValidation patterns.

General guidance: start with DataAnnotations. Add `IValidatableObject` when cross-property rules emerge. Introduce FluentValidation only when rules outgrow declarative attributes.

---

## DataAnnotations

The `System.ComponentModel.DataAnnotations` namespace provides declarative validation through attributes. These attributes work with MVC model binding, `Validator.TryValidateObject`, and the .NET 10 source-generated validation pipeline.

### Standard Attributes

```csharp
using System.ComponentModel.DataAnnotations;

public sealed class CreateProductRequest
{
    [Required(ErrorMessage = "Product name is required")]
    [StringLength(200, MinimumLength = 1)]
    public required string Name { get; set; }

    [Range(0.01, 1_000_000, ErrorMessage = "Price must be between {1} and {2}")]
    public decimal Price { get; set; }

    [RegularExpression(@"^[A-Z]{2,4}-\d{4,8}$",
        ErrorMessage = "SKU format: AA-0000 to AAAA-00000000")]
    public string? Sku { get; set; }

    [EmailAddress]
    public string? ContactEmail { get; set; }

    [Url]
    public string? WebsiteUrl { get; set; }

    [Range(0, int.MaxValue, ErrorMessage = "Quantity cannot be negative")]
    public int Quantity { get; set; }
}
```

### Attribute Reference

| Attribute | Purpose | Example |
|-----------|---------|---------|
| `[Required]` | Non-null, non-empty | `[Required]` |
| `[StringLength]` | Min/max length | `[StringLength(200, MinimumLength = 1)]` |
| `[Range]` | Numeric/date range | `[Range(1, 100)]` |
| `[RegularExpression]` | Pattern match | `[RegularExpression(@"^\d{5}$")]` |
| `[EmailAddress]` | Email format | `[EmailAddress]` |
| `[Phone]` | Phone format | `[Phone]` |
| `[Url]` | URL format | `[Url]` |
| `[CreditCard]` | Luhn check | `[CreditCard]` |
| `[Compare]` | Property equality | `[Compare(nameof(Password))]` |
| `[MaxLength]` / `[MinLength]` | Collection/string length | `[MaxLength(50)]` |
| `[AllowedValues]` (.NET 8+) | Value allowlist | `[AllowedValues("Draft", "Published")]` |
| `[DeniedValues]` (.NET 8+) | Value denylist | `[DeniedValues("Admin", "Root")]` |
| `[Length]` (.NET 8+) | Min and max in one | `[Length(1, 200)]` |
| `[Base64String]` (.NET 8+) | Base64 format | `[Base64String]` |

---

## Custom ValidationAttribute

Create reusable validation attributes for domain-specific rules.

### Property-Level Custom Attribute

```csharp
[AttributeUsage(AttributeTargets.Property | AttributeTargets.Parameter)]
public sealed class FutureDateAttribute : ValidationAttribute
{
    protected override ValidationResult? IsValid(
        object? value, ValidationContext validationContext)
    {
        if (value is DateOnly date && date <= DateOnly.FromDateTime(DateTime.UtcNow))
        {
            return new ValidationResult(
                ErrorMessage ?? "Date must be in the future",
                [validationContext.MemberName!]);
        }

        return ValidationResult.Success;
    }
}

// Usage
public sealed class CreateEventRequest
{
    [Required]
    [StringLength(200)]
    public required string Title { get; set; }

    [FutureDate(ErrorMessage = "Event date must be in the future")]
    public DateOnly EventDate { get; set; }
}
```

### Class-Level Custom Attribute

Apply validation across the entire object when multiple properties are involved:

```csharp
[AttributeUsage(AttributeTargets.Class)]
public sealed class DateRangeAttribute : ValidationAttribute
{
    public string StartProperty { get; set; } = "StartDate";
    public string EndProperty { get; set; } = "EndDate";

    protected override ValidationResult? IsValid(
        object? value, ValidationContext validationContext)
    {
        if (value is null) return ValidationResult.Success;

        var type = value.GetType();
        var startValue = type.GetProperty(StartProperty)?.GetValue(value);
        var endValue = type.GetProperty(EndProperty)?.GetValue(value);

        if (startValue is DateOnly start && endValue is DateOnly end && end < start)
        {
            return new ValidationResult(
                ErrorMessage ?? $"{EndProperty} must be after {StartProperty}",
                [EndProperty]);
        }

        return ValidationResult.Success;
    }
}

// Usage
[DateRange(StartProperty = nameof(StartDate), EndProperty = nameof(EndDate))]
public sealed class DateRangeFilter
{
    [Required]
    public DateOnly StartDate { get; set; }

    [Required]
    public DateOnly EndDate { get; set; }
}
```

---

## IValidatableObject

Implement `IValidatableObject` for cross-property validation within the model itself. This interface runs after all individual attribute validations pass (when using MVC model binding or `Validator.TryValidateObject` with `validateAllProperties: true`).

```csharp
public sealed class CreateOrderRequest : IValidatableObject
{
    [Required]
    [StringLength(50)]
    public required string CustomerId { get; set; }

    [Required]
    public DateOnly OrderDate { get; set; }

    public DateOnly? ShipByDate { get; set; }

    [Required]
    [MinLength(1, ErrorMessage = "At least one line item is required")]
    public required List<OrderLineItem> Lines { get; set; }

    public IEnumerable<ValidationResult> Validate(ValidationContext validationContext)
    {
        if (ShipByDate.HasValue && ShipByDate.Value <= OrderDate)
        {
            yield return new ValidationResult(
                "Ship-by date must be after order date",
                [nameof(ShipByDate)]);
        }

        if (Lines.Sum(l => l.Quantity * l.UnitPrice) > 1_000_000)
        {
            yield return new ValidationResult(
                "Total order value cannot exceed 1,000,000",
                [nameof(Lines)]);
        }

        // Conditional required field
        if (Lines.Any(l => l.RequiresShipping) && ShipByDate is null)
        {
            yield return new ValidationResult(
                "Ship-by date is required when order contains shippable items",
                [nameof(ShipByDate)]);
        }
    }
}

public sealed class OrderLineItem
{
    [Required]
    public required string ProductId { get; set; }

    [Range(1, 10_000)]
    public int Quantity { get; set; }

    [Range(0.01, 100_000)]
    public decimal UnitPrice { get; set; }

    public bool RequiresShipping { get; set; }
}
```

**When to use `IValidatableObject` vs custom attribute:** Use `IValidatableObject` when the validation logic is specific to one model and involves multiple properties. Use a custom `ValidationAttribute` when the same rule applies across multiple models (reusable).

---

## IValidateOptions<T>

Use `IValidateOptions<T>` for complex validation of options/configuration classes at startup. Unlike DataAnnotations, this interface supports cross-property checks, DI-injected dependencies, and programmatic logic. See `references/configuration.md` for Options pattern binding and `ValidateOnStart()` registration.

### Basic IValidateOptions

```csharp
public sealed class DatabaseOptions
{
    public const string SectionName = "Database";

    public string ConnectionString { get; set; } = "";
    public int MaxRetryCount { get; set; } = 3;
    public int CommandTimeoutSeconds { get; set; } = 30;
    public int MaxPoolSize { get; set; } = 100;
    public int MinPoolSize { get; set; } = 0;
}

public sealed class DatabaseOptionsValidator : IValidateOptions<DatabaseOptions>
{
    public ValidateOptionsResult Validate(string? name, DatabaseOptions options)
    {
        var failures = new List<string>();

        if (string.IsNullOrWhiteSpace(options.ConnectionString))
        {
            failures.Add("Database connection string is required.");
        }

        if (options.MaxRetryCount is < 0 or > 10)
        {
            failures.Add("MaxRetryCount must be between 0 and 10.");
        }

        if (options.CommandTimeoutSeconds < 1)
        {
            failures.Add("CommandTimeoutSeconds must be at least 1.");
        }

        if (options.MinPoolSize > options.MaxPoolSize)
        {
            failures.Add(
                $"MinPoolSize ({options.MinPoolSize}) cannot exceed " +
                $"MaxPoolSize ({options.MaxPoolSize}).");
        }

        return failures.Count > 0
            ? ValidateOptionsResult.Fail(failures)
            : ValidateOptionsResult.Success;
    }
}
```

### Registration

```csharp
builder.Services
    .AddOptions<DatabaseOptions>()
    .BindConfiguration(DatabaseOptions.SectionName)
    .ValidateOnStart(); // Fail fast at startup

// Register the validator -- runs automatically with ValidateOnStart
builder.Services.AddSingleton<
    IValidateOptions<DatabaseOptions>, DatabaseOptionsValidator>();
```

### Combining DataAnnotations with IValidateOptions

Use DataAnnotations for simple property constraints and `IValidateOptions<T>` for cross-property or environment-dependent logic:

```csharp
public sealed class SmtpOptions
{
    public const string SectionName = "Smtp";

    [Required, MinLength(1)]
    public string Host { get; set; } = "";

    [Range(1, 65535)]
    public int Port { get; set; } = 587;

    [Required, EmailAddress]
    public string FromAddress { get; set; } = "";

    public bool UseSsl { get; set; } = true;
}

public sealed class SmtpOptionsValidator : IValidateOptions<SmtpOptions>
{
    public ValidateOptionsResult Validate(string? name, SmtpOptions options)
    {
        if (options.UseSsl && options.Port == 25)
        {
            return ValidateOptionsResult.Fail(
                "Port 25 does not support SSL. Use 465 or 587.");
        }

        return ValidateOptionsResult.Success;
    }
}

// Registration -- both run
builder.Services
    .AddOptions<SmtpOptions>()
    .BindConfiguration(SmtpOptions.SectionName)
    .ValidateDataAnnotations()  // Simple property checks
    .ValidateOnStart();

builder.Services.AddSingleton<
    IValidateOptions<SmtpOptions>, SmtpOptionsValidator>(); // Cross-property checks
```

---

## Manual Validation with Validator.TryValidateObject

Run DataAnnotations validation programmatically outside the MVC/Minimal API pipeline. Useful for validating objects in background services, console apps, or domain logic.

```csharp
public static class ValidationHelper
{
    public static (bool IsValid, IReadOnlyList<ValidationResult> Errors) Validate<T>(
        T instance) where T : notnull
    {
        var results = new List<ValidationResult>();
        var context = new ValidationContext(instance);

        // validateAllProperties: true is required to check all attributes
        bool isValid = Validator.TryValidateObject(
            instance, context, results, validateAllProperties: true);

        return (isValid, results);
    }
}

// Usage in a background service
public sealed class OrderImportWorker(
    IServiceScopeFactory scopeFactory,
    ILogger<OrderImportWorker> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            var order = await ReadNextOrderFromQueue(stoppingToken);
            var (isValid, errors) = ValidationHelper.Validate(order);

            if (!isValid)
            {
                logger.LogWarning(
                    "Invalid order skipped: {Errors}",
                    string.Join("; ", errors.Select(e => e.ErrorMessage)));
                continue;
            }

            using var scope = scopeFactory.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            db.Orders.Add(order);
            await db.SaveChangesAsync(stoppingToken);
        }
    }

    private Task<Order> ReadNextOrderFromQueue(CancellationToken ct) =>
        throw new NotImplementedException();
}
```

**Critical:** Without `validateAllProperties: true`, `Validator.TryValidateObject` only checks `[Required]` attributes, silently skipping `[Range]`, `[StringLength]`, `[RegularExpression]`, and all other attributes.

---

## Recursive Validation for Nested Objects

`Validator.TryValidateObject` does not recurse into nested objects or collections by default. Implement recursive validation when models contain nested complex types:

```csharp
public static class RecursiveValidator
{
    public static bool TryValidateObjectRecursive(
        object instance,
        List<ValidationResult> results)
    {
        var visited = new HashSet<object>(ReferenceEqualityComparer.Instance);
        return ValidateRecursive(instance, results, visited, prefix: "");
    }

    private static bool ValidateRecursive(
        object instance,
        List<ValidationResult> results,
        HashSet<object> visited,
        string prefix)
    {
        if (!visited.Add(instance))
            return true; // Already validated -- avoid circular reference loops

        var context = new ValidationContext(instance);
        bool isValid = Validator.TryValidateObject(
            instance, context, results, validateAllProperties: true);

        foreach (var property in instance.GetType().GetProperties())
        {
            if (IsSimpleType(property.PropertyType))
                continue;

            var value = property.GetValue(instance);
            if (value is null) continue;

            var memberPrefix = string.IsNullOrEmpty(prefix)
                ? property.Name
                : $"{prefix}.{property.Name}";

            if (value is IEnumerable<object> collection)
            {
                int index = 0;
                foreach (var item in collection)
                {
                    var itemResults = new List<ValidationResult>();
                    if (!ValidateRecursive(
                        item, itemResults, visited,
                        $"{memberPrefix}[{index}]"))
                    {
                        isValid = false;
                        foreach (var result in itemResults)
                        {
                            results.Add(new ValidationResult(
                                result.ErrorMessage,
                                result.MemberNames.Select(
                                    m => $"{memberPrefix}[{index}].{m}").ToArray()));
                        }
                    }
                    index++;
                }
            }
            else if (property.PropertyType.IsClass)
            {
                var nestedResults = new List<ValidationResult>();
                if (!ValidateRecursive(value, nestedResults, visited, memberPrefix))
                {
                    isValid = false;
                    foreach (var result in nestedResults)
                    {
                        results.Add(new ValidationResult(
                            result.ErrorMessage,
                            result.MemberNames.Select(
                                m => $"{memberPrefix}.{m}").ToArray()));
                    }
                }
            }
        }

        return isValid;
    }

    private static bool IsSimpleType(Type type) =>
        type.IsPrimitive
        || type.IsEnum
        || type == typeof(string)
        || type == typeof(decimal)
        || type == typeof(DateTime)
        || type == typeof(DateTimeOffset)
        || type == typeof(DateOnly)
        || type == typeof(TimeOnly)
        || type == typeof(TimeSpan)
        || type == typeof(Guid)
        || (Nullable.GetUnderlyingType(type) is { } underlying
            && IsSimpleType(underlying));
}
```

**Note:** This implementation tracks visited objects via `HashSet<object>` with `ReferenceEqualityComparer` to safely handle circular reference graphs without stack overflow.

---

## Agent Gotchas

1. **Always pass `validateAllProperties: true`** to `Validator.TryValidateObject`. Without it, only `[Required]` is checked; `[Range]`, `[StringLength]`, and custom attributes are silently skipped.
2. **Options classes must use `{ get; set; }` not `{ get; init; }`** because the configuration binder and `PostConfigure` need to mutate properties after construction. Use `[Required]` for mandatory fields instead of `init`.
3. **`IValidatableObject.Validate()` runs only after all attribute validations pass.** This requires MVC model binding or `Validator.TryValidateObject` with `validateAllProperties: true`. If attribute validation fails, `Validate()` is never called. Do not rely on it for primary validation.
4. **Do not inject services into `ValidationAttribute` via constructor.** Attributes are instantiated by the runtime and cannot participate in DI. Use `validationContext.GetService<T>()` inside `IsValid()` if service access is needed, but prefer `IValidateOptions<T>` for DI-dependent validation.
5. **Do not use `[RegularExpression]` without `[GeneratedRegex]` awareness.** The attribute internally creates `Regex` instances. For performance-critical paths, validate with `[GeneratedRegex]` in a custom attribute or `IValidatableObject` instead. See `references/input-validation.md` for ReDoS prevention.
6. **Register `IValidateOptions<T>` as singleton.** The options validation infrastructure resolves validators as singletons. Registering as scoped or transient causes resolution failures.
7. **Do not forget `ValidateOnStart()`.** Without it, options validation only runs on first access to `IOptions<T>.Value`, which may be minutes into the application lifecycle. Always chain `.ValidateOnStart()` for fail-fast behavior.

---

## Prerequisites

- .NET 8.0+ (LTS baseline for `[AllowedValues]`, `[DeniedValues]`, `[Length]`, `[Base64String]`)
- `System.ComponentModel.DataAnnotations` (included in .NET SDK, no extra package)
- `Microsoft.Extensions.Options` (included in ASP.NET Core shared framework, no extra package)
- .NET 10.0 for `[ValidatableType]` source-generated validation (see `references/input-validation.md`)

---

## References

- [Model Validation in ASP.NET Core](https://learn.microsoft.com/en-us/aspnet/core/mvc/models/validation)
- [System.ComponentModel.DataAnnotations](https://learn.microsoft.com/en-us/dotnet/api/system.componentmodel.dataannotations)
- [IValidateOptions](https://learn.microsoft.com/en-us/dotnet/core/extensions/options#options-validation)
- [Options Pattern in .NET](https://learn.microsoft.com/en-us/dotnet/core/extensions/options)
- [Validator.TryValidateObject](https://learn.microsoft.com/en-us/dotnet/api/system.componentmodel.dataannotations.validator.tryvalidateobject)

## Attribution

Adapted from [Aaronontheweb/dotnet-skills](https://github.com/Aaronontheweb/dotnet-skills) (MIT license).
