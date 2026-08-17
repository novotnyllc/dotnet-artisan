# Input Validation

Comprehensive input validation patterns for .NET APIs. Covers the .NET 10 built-in validation system, FluentValidation for complex business rules, Data Annotations for simple models, endpoint filters for Minimal API integration, ProblemDetails error responses, and security-focused validation techniques.

## Validation Framework Decision Tree

Choose the validation framework based on project requirements:

1. **.NET 10 Built-in Validation (`AddValidation`)** -- default for new .NET 10+ projects. Source-generator-based, AOT-compatible, auto-discovers types from Minimal API handlers. Best for: greenfield projects targeting .NET 10+.
2. **FluentValidation** -- when validation rules are complex (cross-property, conditional, database-dependent). Rich fluent API with testable validator classes. Best for: complex business rules, domain validation.
3. **Data Annotations** -- when models need simple declarative validation (`[Required]`, `[Range]`). Widely understood, works with MVC model binding and `IValidatableObject` for cross-property checks. Best for: simple DTOs, shared models.
4. **MiniValidation** -- lightweight Data Annotations runner without MVC model binding overhead. Best for: micro-services with simple validation (see [skill:dotnet-api] for details).

General guidance: prefer .NET 10 built-in validation for new projects. Use FluentValidation when rules outgrow annotations. Do not mix multiple frameworks in the same request DTO -- pick one per model type and stay consistent.

---

## .NET 10 Built-in Validation

.NET 10 introduces `Microsoft.Extensions.Validation` with source-generator-based validation that integrates directly into the Minimal API pipeline. It auto-discovers validatable types from endpoint handler parameters and runs validation via an endpoint filter.

### Setup

```csharp
// <PackageReference Include="Microsoft.Extensions.Validation" Version="10.*" />
builder.Services.AddValidation();

var app = builder.Build();
// Validation runs automatically via endpoint filter for Minimal API handlers
```

`AddValidation()` scans for types annotated with `[ValidatableType]` and generates validation logic at compile time using source generators, ensuring Native AOT compatibility.

### Defining Validatable Types

```csharp
[ValidatableType]
public partial class CreateProductRequest
{
    [Required]
    [StringLength(200, MinimumLength = 1)]
    public required string Name { get; set; }

    [Range(0.01, 1_000_000)]
    public decimal Price { get; set; }

    [Required]
    [RegularExpression(@"^[A-Z]{2,4}-\d{4,8}$", ErrorMessage = "SKU format: AA-0000")]
    public required string Sku { get; set; }
}
```

The `partial` keyword is required because the source generator emits validation logic into the same type. The `[ValidatableType]` attribute triggers code generation at compile time -- no reflection at runtime.

### How It Works

1. Source generator discovers `[ValidatableType]` classes and emits `IValidatableObject`-like validation logic.
2. `AddValidation()` registers an endpoint filter that inspects Minimal API handler parameters.
3. When a request arrives, the filter validates parameters before the handler executes.
4. On failure, returns a `ValidationProblem` response automatically.

**Gotcha:** `AddValidation()` integrates with Minimal APIs via endpoint filters. MVC controllers use their own model validation pipeline and do not participate in this filter-based system. For controllers, Data Annotations and `ModelState.IsValid` remain the standard approach.

---

## FluentValidation

FluentValidation provides a fluent API for building strongly-typed validation rules. It excels at complex business validation with cross-property rules, conditional logic, and database-dependent checks.

### Validator Definition

```csharp
// <PackageReference Include="FluentValidation" Version="11.*" />
// <PackageReference Include="FluentValidation.DependencyInjectionExtensions" Version="11.*" />
public sealed class CreateOrderValidator : AbstractValidator<CreateOrderRequest>
{
    public CreateOrderValidator()
    {
        RuleFor(x => x.CustomerId)
            .NotEmpty()
            .MaximumLength(50);

        RuleFor(x => x.OrderDate)
            .LessThanOrEqualTo(DateOnly.FromDateTime(DateTime.UtcNow))
            .WithMessage("Order date cannot be in the future");

        RuleFor(x => x.Lines)
            .NotEmpty()
            .WithMessage("Order must have at least one line item");

        RuleForEach(x => x.Lines)
            .ChildRules(line =>
            {
                line.RuleFor(l => l.ProductId).NotEmpty();
                line.RuleFor(l => l.Quantity).GreaterThan(0);
                line.RuleFor(l => l.UnitPrice).GreaterThan(0);
            });

        // Conditional rule
        When(x => x.ShippingMethod == ShippingMethod.Express, () =>
        {
            RuleFor(x => x.ShippingAddress)
                .NotNull()
                .WithMessage("Express shipping requires an address");
        });
    }
}
```

### DI Registration with Assembly Scanning

```csharp
// Registers all AbstractValidator<T> implementations from the assembly
builder.Services.AddValidatorsFromAssemblyContaining<Program>(ServiceLifetime.Scoped);
```

### Manual Validation Pattern (Recommended)

FluentValidation's ASP.NET pipeline auto-validation is deprecated. Use manual validation in endpoint handlers or endpoint filters instead:

```csharp
app.MapPost("/api/orders", async (
    CreateOrderRequest request,
    IValidator<CreateOrderRequest> validator,
    AppDbContext db) =>
{
    var result = await validator.ValidateAsync(request);
    if (!result.IsValid)
    {
        return TypedResults.ValidationProblem(result.ToDictionary());
    }

    var order = new Order { CustomerId = request.CustomerId };
    db.Orders.Add(order);
    await db.SaveChangesAsync();
    return TypedResults.Created($"/api/orders/{order.Id}", order);
});
```

### FluentValidation Endpoint Filter

For reusable validation across multiple endpoints, create a generic endpoint filter (see also [skill:dotnet-api] for filter pipeline details):

```csharp
public sealed class FluentValidationFilter<T>(IValidator<T> validator) : IEndpointFilter
    where T : class
{
    public async ValueTask<object?> InvokeAsync(
        EndpointFilterInvocationContext context,
        EndpointFilterDelegate next)
    {
        var argument = context.Arguments.OfType<T>().FirstOrDefault();
        if (argument is null)
            return TypedResults.BadRequest("Request body is required");

        var result = await validator.ValidateAsync(argument);
        if (!result.IsValid)
            return TypedResults.ValidationProblem(result.ToDictionary());

        return await next(context);
    }
}

// Apply to endpoints
products.MapPost("/", CreateProduct)
    .AddEndpointFilter<FluentValidationFilter<CreateProductDto>>();
```

**Gotcha:** Do not use the deprecated `FluentValidation.AspNetCore` auto-validation pipeline. It was removed in FluentValidation 11. Use manual validation or endpoint filters as shown above.

---

## Data Annotations

Data Annotations provide declarative validation through attributes. They work with MVC model binding, Minimal API binding, and the .NET 10 `AddValidation()` source generator.

### Standard Attributes

```csharp
public sealed class UpdateProductDto
{
    [Required(ErrorMessage = "Product name is required")]
    [StringLength(200, MinimumLength = 1)]
    public required string Name { get; set; }

    [Range(0.01, 1_000_000, ErrorMessage = "Price must be between {1} and {2}")]
    public decimal Price { get; set; }

    [RegularExpression(@"^[A-Z]{2,4}-\d{4,8}$")]
    public string? Sku { get; set; }

    [EmailAddress]
    public string? ContactEmail { get; set; }

    [Url]
    public string? WebsiteUrl { get; set; }

    [Phone]
    public string? SupportPhone { get; set; }
}
```

### Custom ValidationAttribute

```csharp
[AttributeUsage(AttributeTargets.Property | AttributeTargets.Parameter)]
public sealed class FutureDateAttribute : ValidationAttribute
{
    protected override ValidationResult? IsValid(object? value, ValidationContext context)
    {
        if (value is DateOnly date && date <= DateOnly.FromDateTime(DateTime.UtcNow))
        {
            return new ValidationResult(
                ErrorMessage ?? "Date must be in the future",
                new[] { context.MemberName! });
        }
        return ValidationResult.Success;
    }
}

// Usage
public sealed class CreateEventDto
{
    [Required]
    [StringLength(200)]
    public required string Title { get; set; }

    [FutureDate(ErrorMessage = "Event date must be in the future")]
    public DateOnly EventDate { get; set; }
}
```

### IValidatableObject for Cross-Property Validation

```csharp
public sealed class DateRangeDto : IValidatableObject
{
    [Required]
    public DateOnly StartDate { get; set; }

    [Required]
    public DateOnly EndDate { get; set; }

    [Range(1, 365)]
    public int MaxDays { get; set; } = 30;

    public IEnumerable<ValidationResult> Validate(ValidationContext context)
    {
        if (EndDate < StartDate)
        {
            yield return new ValidationResult(
                "End date must be after start date",
                new[] { nameof(EndDate) });
        }

        if ((EndDate.ToDateTime(TimeOnly.MinValue) - StartDate.ToDateTime(TimeOnly.MinValue)).Days > MaxDays)
        {
            yield return new ValidationResult(
                $"Date range cannot exceed {MaxDays} days",
                new[] { nameof(StartDate), nameof(EndDate) });
        }
    }
}
```

**Gotcha:** Options pattern classes must use `{ get; set; }` not `{ get; init; }` because the configuration binder needs to mutate properties after construction. Validation attributes on `init`-only properties work for request DTOs but fail for options classes bound via `IConfiguration`. See `references/configuration.md` for Options pattern validation.

---

## Endpoint Filters for Validation

Endpoint filters integrate validation into the Minimal API request pipeline as a cross-cutting concern. Filters execute before the handler, enabling centralized validation logic.

### Generic Data Annotations Filter

```csharp
public sealed class DataAnnotationsValidationFilter<T> : IEndpointFilter
    where T : class
{
    public async ValueTask<object?> InvokeAsync(
        EndpointFilterInvocationContext context,
        EndpointFilterDelegate next)
    {
        var argument = context.Arguments.OfType<T>().FirstOrDefault();
        if (argument is null)
            return TypedResults.BadRequest("Request body is required");

        var validationResults = new List<ValidationResult>();
        var validationContext = new ValidationContext(argument);

        if (!Validator.TryValidateObject(argument, validationContext, validationResults, validateAllProperties: true))
        {
            var errors = validationResults
                .Where(r => r.MemberNames.Any())
                .GroupBy(r => r.MemberNames.First())
                .ToDictionary(
                    g => g.Key,
                    g => g.Select(r => r.ErrorMessage ?? "Validation failed").ToArray());

            return TypedResults.ValidationProblem(errors);
        }

        return await next(context);
    }
}

// Apply to endpoints or route groups
products.MapPost("/", CreateProduct)
    .AddEndpointFilter<DataAnnotationsValidationFilter<CreateProductDto>>();

products.MapPut("/{id:int}", UpdateProduct)
    .AddEndpointFilter<DataAnnotationsValidationFilter<UpdateProductDto>>();
```

### Combining with Route Groups

Apply validation filters at the route group level for consistent validation across all endpoints in a group (see [skill:dotnet-api] for route group patterns):

```csharp
var orders = app.MapGroup("/api/orders")
    .AddEndpointFilter<FluentValidationFilter<CreateOrderRequest>>();
```

**Gotcha:** Filter execution order matters -- first-registered filter is outermost. Register validation filters after logging but before authorization enrichment so that invalid requests are rejected early without unnecessary processing.

---

## Error Responses

Use the ProblemDetails standard (RFC 9457) for consistent API error responses. ASP.NET Core has built-in support via `TypedResults.ValidationProblem()` and `IProblemDetailsService`.

### ValidationProblem Response

```csharp
// Returns HTTP 400 with RFC 9457-compliant body
app.MapPost("/api/products", async (CreateProductDto dto, IValidator<CreateProductDto> validator) =>
{
    var result = await validator.ValidateAsync(dto);
    if (!result.IsValid)
    {
        // Produces: { "type": "...", "title": "...", "status": 400, "errors": { ... } }
        return TypedResults.ValidationProblem(result.ToDictionary());
    }

    // ... create product
    return TypedResults.Created($"/api/products/{product.Id}", product);
});
```

### Customizing ProblemDetails

```csharp
builder.Services.AddProblemDetails(options =>
{
    options.CustomizeProblemDetails = context =>
    {
        context.ProblemDetails.Extensions["traceId"] =
            context.HttpContext.TraceIdentifier;
        context.ProblemDetails.Extensions["instance"] =
            context.HttpContext.Request.Path.Value;
    };
});

var app = builder.Build();
app.UseStatusCodePages();
app.UseExceptionHandler();
```

### IProblemDetailsService for Global Error Handling

```csharp
builder.Services.AddProblemDetails();

var app = builder.Build();

app.UseExceptionHandler(exceptionApp =>
{
    exceptionApp.Run(async context =>
    {
        var problemDetailsService = context.RequestServices
            .GetRequiredService<IProblemDetailsService>();

        await problemDetailsService.WriteAsync(new ProblemDetailsContext
        {
            HttpContext = context,
            ProblemDetails =
            {
                Title = "An unexpected error occurred",
                Status = StatusCodes.Status500InternalServerError,
                Type = "https://tools.ietf.org/html/rfc9110#section-15.6.1"
            }
        });
    });
});
```

**Gotcha:** `ConfigureHttpJsonOptions` applies to Minimal APIs only, not MVC controllers. Validation error formatting (e.g., camelCase property names in the `errors` dictionary) may differ between Minimal APIs and MVC if JSON options are not configured consistently. For MVC controllers, configure via `builder.Services.AddControllers().AddJsonOptions(...)`.

---

## Security-Focused Validation

Input validation is a first line of defense against injection and abuse. These patterns complement the OWASP security principles in [skill:dotnet-api] with practical validation techniques.

### ReDoS Prevention

Regular expressions with backtracking can be exploited to cause catastrophic performance degradation (Regular Expression Denial of Service). Always apply timeouts or use source-generated regex.

```csharp
// PREFERRED: [GeneratedRegex] -- compiled at build time, AOT-compatible (.NET 7+).
// Combine with RegexOptions.NonBacktracking or a timeout for ReDoS safety.
public static partial class InputPatterns
{
    [GeneratedRegex(@"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$",
        RegexOptions.None, matchTimeoutMilliseconds: 1000)]
    public static partial Regex EmailPattern();

    [GeneratedRegex(@"^[A-Z]{2,4}-\d{4,8}$")]
    public static partial Regex SkuPattern();
}

// Usage in validation
if (!InputPatterns.EmailPattern().IsMatch(input))
{
    return TypedResults.ValidationProblem(
        new Dictionary<string, string[]>
        {
            ["email"] = ["Invalid email format"]
        });
}
```

```csharp
// FALLBACK: Regex with explicit timeout (when source generation is not available)
var pattern = new Regex(
    @"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$",
    RegexOptions.Compiled,
    matchTimeout: TimeSpan.FromSeconds(1));

try
{
    if (!pattern.IsMatch(input))
        return TypedResults.BadRequest("Invalid format");
}
catch (RegexMatchTimeoutException)
{
    return TypedResults.BadRequest("Input validation timed out");
}
```

### Allowlist vs Denylist

Always prefer allowlist validation over denylist. Denylists are inherently incomplete because new attack vectors bypass them.

```csharp
// CORRECT: Allowlist -- only permit known-good values
private static readonly FrozenSet<string> AllowedFileExtensions =
    new HashSet<string>(StringComparer.OrdinalIgnoreCase)
    { ".jpg", ".jpeg", ".png", ".gif", ".webp" }
    .ToFrozenSet(StringComparer.OrdinalIgnoreCase);

public static bool IsAllowedExtension(string filename) =>
    AllowedFileExtensions.Contains(Path.GetExtension(filename));

// WRONG: Denylist -- attackers find extensions not in the list
// private static readonly string[] BlockedExtensions = [".exe", ".bat", ".cmd", ".ps1"];
```

```csharp
// Allowlist for input characters
public static bool IsValidUsername(string username) =>
    username.Length is >= 3 and <= 50
    && username.All(c => char.IsLetterOrDigit(c) || c is '_' or '-');
```

### Max Length Enforcement

Enforce maximum length on all user-controlled string inputs to prevent memory exhaustion and buffer-based attacks:

```csharp
[ValidatableType]
public partial class SearchRequest
{
    [Required]
    [StringLength(200)]  // Always set max length on search inputs
    public required string Query { get; set; }

    [Range(1, 100)]
    public int PageSize { get; set; } = 20;
}
```

Also enforce at the Kestrel level for defense in depth:

```csharp
// Configure BEFORE builder.Build()
builder.WebHost.ConfigureKestrel(options =>
{
    options.Limits.MaxRequestBodySize = 10 * 1024 * 1024; // 10 MB
    options.Limits.MaxRequestHeadersTotalSize = 32 * 1024; // 32 KB
});
```

### File Upload Validation

Validate file uploads by content type, size, and extension -- never trust the client-provided `Content-Type` header alone:

```csharp
app.MapPost("/api/uploads", async (IFormFile file) =>
{
    // 1. Validate extension (allowlist)
    var extension = Path.GetExtension(file.FileName);
    if (!AllowedFileExtensions.Contains(extension))
        return TypedResults.ValidationProblem(
            new Dictionary<string, string[]>
            {
                ["file"] = [$"File type '{extension}' is not allowed"]
            });

    // 2. Validate file size
    const long maxSize = 5 * 1024 * 1024; // 5 MB
    if (file.Length > maxSize)
        return TypedResults.ValidationProblem(
            new Dictionary<string, string[]>
            {
                ["file"] = [$"File size exceeds {maxSize / (1024 * 1024)} MB limit"]
            });

    // 3. Validate content by reading magic bytes (not Content-Type header)
    using var stream = file.OpenReadStream();
    const int headerSize = 12; // Need 12 bytes for WebP (RIFF + WEBP)
    var header = new byte[headerSize];

    // Guard against files shorter than header size
    int bytesRead = await stream.ReadAtLeastAsync(header, headerSize, throwOnEndOfStream: false);
    if (bytesRead < headerSize)
        return TypedResults.ValidationProblem(
            new Dictionary<string, string[]>
            {
                ["file"] = ["File is too small to be a valid image"]
            });

    stream.Position = 0;

    if (!IsValidImageHeader(header))
        return TypedResults.ValidationProblem(
            new Dictionary<string, string[]>
            {
                ["file"] = ["File content does not match an allowed image format"]
            });

    // 4. Save with a generated filename (never use the original)
    var safeName = $"{Guid.NewGuid()}{extension}";
    var path = Path.Combine("uploads", safeName);
    using var output = File.Create(path);
    await stream.CopyToAsync(output);

    return TypedResults.Ok(new { FileName = safeName });
})
.DisableAntiforgery(); // Only if using JWT/bearer auth, not cookie auth

static bool IsValidImageHeader(ReadOnlySpan<byte> header) =>
    header[..2].SequenceEqual(new byte[] { 0xFF, 0xD8 })                                   // JPEG
    || header[..8].SequenceEqual(new byte[] { 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A }) // PNG
    || header[..4].SequenceEqual("GIF8"u8)                                                  // GIF
    || (header[..4].SequenceEqual("RIFF"u8) && header[8..12].SequenceEqual("WEBP"u8));      // WebP
```

For OWASP injection prevention beyond input validation (SQL injection, XSS, command injection), see [skill:dotnet-api].

---

## Agent Gotchas

1. **Do not use FluentValidation auto-validation pipeline** -- it was deprecated and removed in FluentValidation 11. Use manual validation or endpoint filters with `IValidator<T>` instead.
2. **Do not mix validation frameworks on the same DTO** -- pick one (Data Annotations OR FluentValidation OR .NET 10 built-in) per model type. Mixing causes confusing partial validation.
3. **Do not use `Regex` without a timeout or `[GeneratedRegex]`** -- unbounded regex matching on user input enables ReDoS attacks. Always set `matchTimeout` or use source-generated regex.
4. **Do not trust client-provided `Content-Type` headers** -- validate file content by reading magic bytes. Attackers rename executables with image extensions.
5. **Do not forget `validateAllProperties: true`** -- `Validator.TryValidateObject` without this flag only validates `[Required]` attributes, silently skipping `[Range]`, `[StringLength]`, and others.
6. **Do not use denylist validation for security** -- denylists are inherently incomplete. Always validate against an allowlist of known-good values.
7. **Do not omit max length on string inputs** -- unbounded strings enable memory exhaustion. Apply `[StringLength]` or `[MaxLength]` to every user-controlled string property.

---

## Prerequisites

- .NET 8.0+ (LTS baseline for endpoint filters, ProblemDetails, Data Annotations)
- .NET 10.0 for built-in validation (`AddValidation`, `[ValidatableType]`, `Microsoft.Extensions.Validation`)
- `Microsoft.Extensions.Validation` package for .NET 10 built-in validation
- `FluentValidation` and `FluentValidation.DependencyInjectionExtensions` for FluentValidation patterns
- .NET 7+ for `[GeneratedRegex]` source-generated regular expressions

---

## References

- [Model Validation in ASP.NET Core](https://learn.microsoft.com/en-us/aspnet/core/mvc/models/validation?view=aspnetcore-10.0)
- [Minimal API Filters](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/minimal-apis/min-api-filters?view=aspnetcore-10.0)
- [FluentValidation Documentation](https://docs.fluentvalidation.net/en/latest/aspnet.html)
- [ProblemDetails (RFC 9457)](https://www.rfc-editor.org/rfc/rfc9457)
- [Handle Errors in ASP.NET Core](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/error-handling?view=aspnetcore-10.0)
- [OWASP Input Validation Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Input_Validation_Cheat_Sheet.html)
- [.NET Regular Expression Source Generators](https://learn.microsoft.com/en-us/dotnet/standard/base-types/regular-expression-source-generators)
