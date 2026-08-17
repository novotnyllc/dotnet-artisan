# Minimal APIs

Minimal APIs are Microsoft's recommended approach for new ASP.NET Core HTTP API projects. They provide a lightweight, lambda-based programming model with first-class OpenAPI support, endpoint filters for cross-cutting concerns, and route groups for organization at scale.

## Route Groups

Route groups organize related endpoints under a shared prefix, applying common configuration (filters, metadata, authorization) once. They replace repetitive chaining of `MapGet`/`MapPost` with shared prefixes.

```csharp
var app = builder.Build();

// Group endpoints under /api/products with shared configuration
var products = app.MapGroup("/api/products")
    .WithTags("Products")
    .RequireAuthorization();

products.MapGet("/", async (AppDbContext db) =>
    TypedResults.Ok(await db.Products.ToListAsync()));

products.MapGet("/{id:int}", async (int id, AppDbContext db) =>
    await db.Products.FindAsync(id) is Product product
        ? TypedResults.Ok(product)
        : TypedResults.NotFound());

products.MapPost("/", async (CreateProductDto dto, AppDbContext db) =>
{
    var product = new Product { Name = dto.Name, Price = dto.Price };
    db.Products.Add(product);
    await db.SaveChangesAsync();
    return TypedResults.Created($"/api/products/{product.Id}", product);
});

products.MapDelete("/{id:int}", async (int id, AppDbContext db) =>
{
    if (await db.Products.FindAsync(id) is not Product product)
        return TypedResults.NotFound();

    db.Products.Remove(product);
    await db.SaveChangesAsync();
    return TypedResults.NoContent();
});
```

### Nested Groups

Groups can be nested to compose prefixes and filters:

```csharp
var api = app.MapGroup("/api")
    .AddEndpointFilter<RequestLoggingFilter>();

var v1 = api.MapGroup("/v1");
var products = v1.MapGroup("/products").WithTags("Products");
var orders = v1.MapGroup("/orders").WithTags("Orders");

// Registers as: GET /api/v1/products
products.MapGet("/", GetProducts);
// Registers as: POST /api/v1/orders
orders.MapPost("/", CreateOrder);
```

---

## Endpoint Filters

Endpoint filters provide a pipeline for cross-cutting concerns (logging, validation, authorization enrichment) similar to MVC action filters but specific to Minimal APIs.

### IEndpointFilter Interface

```csharp
public sealed class ValidationFilter<T>(IValidator<T> validator) : IEndpointFilter
    where T : class
{
    public async ValueTask<object?> InvokeAsync(
        EndpointFilterInvocationContext context,
        EndpointFilterDelegate next)
    {
        // Extract the argument of type T from the endpoint parameters
        var argument = context.Arguments
            .OfType<T>()
            .FirstOrDefault();

        if (argument is null)
            return TypedResults.BadRequest("Request body is required");

        var result = await validator.ValidateAsync(argument);
        if (!result.IsValid)
        {
            return TypedResults.ValidationProblem(
                result.ToDictionary());
        }

        return await next(context);
    }
}
```

### Applying Filters

```csharp
// Apply to a single endpoint
products.MapPost("/", CreateProduct)
    .AddEndpointFilter<ValidationFilter<CreateProductDto>>();

// Apply to an entire route group
var products = app.MapGroup("/api/products")
    .AddEndpointFilter<RequestLoggingFilter>();

// Inline filter using a lambda
products.MapGet("/{id:int}", GetProductById)
    .AddEndpointFilter(async (context, next) =>
    {
        var id = context.GetArgument<int>(0);
        if (id <= 0)
            return TypedResults.BadRequest("ID must be positive");

        return await next(context);
    });
```

### Filter Execution Order

Filters execute in registration order (first registered = outermost). The endpoint handler runs after all filters pass:

```
Request -> Filter1 -> Filter2 -> Filter3 -> Handler
Response <- Filter1 <- Filter2 <- Filter3 <-
```

---

## TypedResults

Always use `TypedResults` (static factory) instead of `Results` (interface factory) for Minimal API return values. `TypedResults` returns concrete types that the OpenAPI metadata generator can inspect at build time, producing accurate response schemas automatically.

```csharp
// PREFERRED: TypedResults -- concrete return types, auto-generates OpenAPI metadata
products.MapGet("/{id:int}", async Task<Results<Ok<Product>, NotFound>> (
    int id, AppDbContext db) =>
    await db.Products.FindAsync(id) is Product product
        ? TypedResults.Ok(product)
        : TypedResults.NotFound());

// AVOID: Results -- returns IResult, OpenAPI generator cannot infer response types
products.MapGet("/{id:int}", async (int id, AppDbContext db) =>
    await db.Products.FindAsync(id) is Product product
        ? Results.Ok(product)
        : Results.NotFound());
```

### Union Return Types

Use `Results<T1, T2, ...>` to declare all possible response types for a single endpoint. This enables accurate OpenAPI documentation with multiple response codes:

```csharp
products.MapPost("/", async Task<Results<Created<Product>, ValidationProblem, Conflict>> (
    CreateProductDto dto, AppDbContext db) =>
{
    if (await db.Products.AnyAsync(p => p.Sku == dto.Sku))
        return TypedResults.Conflict();

    var product = new Product { Name = dto.Name, Sku = dto.Sku, Price = dto.Price };
    db.Products.Add(product);
    await db.SaveChangesAsync();
    return TypedResults.Created($"/api/products/{product.Id}", product);
});
```

---

## OpenAPI 3.1 Integration

.NET 10 adds built-in OpenAPI 3.1 support via `Microsoft.AspNetCore.OpenApi`. Minimal APIs generate OpenAPI metadata from `TypedResults`, parameter bindings, and attributes automatically.

```csharp
builder.Services.AddOpenApi();

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi(); // Serves /openapi/v1.json
}
```

### Enriching Metadata

```csharp
products.MapGet("/{id:int}", GetProductById)
    .WithName("GetProductById")
    .WithSummary("Get a product by its ID")
    .WithDescription("Returns the product details for the specified ID, or 404 if not found.")
    .Produces<Product>(StatusCodes.Status200OK)
    .ProducesProblem(StatusCodes.Status404NotFound);
```

For advanced OpenAPI customization (document transformers, operation transformers, schema customization), see [skill:dotnet-api].

---

## Organization Patterns for Scale

As an API grows beyond a handful of endpoints, organize endpoints into separate static classes or extension methods.

### Extension Method Pattern

```csharp
// ProductEndpoints.cs
public static class ProductEndpoints
{
    public static RouteGroupBuilder MapProductEndpoints(this IEndpointRouteBuilder routes)
    {
        var group = routes.MapGroup("/api/products")
            .WithTags("Products");

        group.MapGet("/", GetAll);
        group.MapGet("/{id:int}", GetById);
        group.MapPost("/", Create);
        group.MapPut("/{id:int}", Update);
        group.MapDelete("/{id:int}", Delete);

        return group;
    }

    private static async Task<Ok<List<Product>>> GetAll(AppDbContext db) =>
        TypedResults.Ok(await db.Products.ToListAsync());

    private static async Task<Results<Ok<Product>, NotFound>> GetById(
        int id, AppDbContext db) =>
        await db.Products.FindAsync(id) is Product p
            ? TypedResults.Ok(p)
            : TypedResults.NotFound();

    private static async Task<Created<Product>> Create(
        CreateProductDto dto, AppDbContext db)
    {
        var product = new Product { Name = dto.Name, Price = dto.Price };
        db.Products.Add(product);
        await db.SaveChangesAsync();
        return TypedResults.Created($"/api/products/{product.Id}", product);
    }

    private static async Task<Results<NoContent, NotFound>> Update(
        int id, UpdateProductDto dto, AppDbContext db)
    {
        var product = await db.Products.FindAsync(id);
        if (product is null) return TypedResults.NotFound();

        product.Name = dto.Name;
        product.Price = dto.Price;
        await db.SaveChangesAsync();
        return TypedResults.NoContent();
    }

    private static async Task<Results<NoContent, NotFound>> Delete(
        int id, AppDbContext db)
    {
        var product = await db.Products.FindAsync(id);
        if (product is null) return TypedResults.NotFound();

        db.Products.Remove(product);
        await db.SaveChangesAsync();
        return TypedResults.NoContent();
    }
}

// Program.cs
app.MapProductEndpoints();
app.MapOrderEndpoints();
app.MapCustomerEndpoints();
```

### Carter Library

For projects that prefer auto-discovery of endpoint modules, the Carter library provides an `ICarterModule` interface:

```csharp
// <PackageReference Include="Carter" Version="8.*" />
public sealed class ProductModule : ICarterModule
{
    public void AddRoutes(IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/products").WithTags("Products");

        group.MapGet("/", async (AppDbContext db) =>
            TypedResults.Ok(await db.Products.ToListAsync()));

        group.MapGet("/{id:int}", async (int id, AppDbContext db) =>
            await db.Products.FindAsync(id) is Product p
                ? TypedResults.Ok(p)
                : TypedResults.NotFound());
    }
}

// Program.cs
builder.Services.AddCarter();
var app = builder.Build();
app.MapCarter(); // Auto-discovers and registers all ICarterModule implementations
```

### Vertical Slice Organization

For projects using vertical slice architecture (see [skill:dotnet-api]), each feature owns its endpoints, handlers, and models in a single directory:

```
Features/
  Products/
    GetProducts.cs       # Endpoint + handler + response DTO
    CreateProduct.cs     # Endpoint + handler + request/response DTOs
    UpdateProduct.cs
    DeleteProduct.cs
    ProductEndpoints.cs  # Route group registration
```

---

## JSON Configuration

Minimal APIs use `System.Text.Json` by default. Configure JSON options globally for all Minimal API endpoints:

```csharp
// ConfigureHttpJsonOptions applies to Minimal APIs ONLY, not MVC controllers
builder.Services.ConfigureHttpJsonOptions(options =>
{
    options.SerializerOptions.PropertyNamingPolicy = JsonNamingPolicy.CamelCase;
    options.SerializerOptions.DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull;
    options.SerializerOptions.Converters.Add(new JsonStringEnumConverter());
});
```

**Gotcha:** `ConfigureHttpJsonOptions` configures JSON serialization for Minimal APIs only. MVC controllers use a separate pipeline -- configure via `builder.Services.AddControllers().AddJsonOptions(...)`. Mixing them up has no effect.

---

## Parameter Binding

Minimal APIs bind parameters from route, query, headers, body, and DI automatically based on type and attribute annotations.

```csharp
// Route parameter (from URL segment)
app.MapGet("/products/{id:int}", (int id) => ...);

// Query string
app.MapGet("/products", ([FromQuery] int page, [FromQuery] int pageSize) => ...);

// Header
app.MapGet("/products", ([FromHeader(Name = "X-Correlation-Id")] string correlationId) => ...);

// Body (JSON deserialized)
app.MapPost("/products", (CreateProductDto dto) => ...);

// DI-injected services (resolved automatically)
app.MapGet("/products", (AppDbContext db, ILogger<Program> logger) => ...);

// AsParameters: bind a complex object from multiple sources
app.MapGet("/products", ([AsParameters] ProductQuery query) => ...);

public record ProductQuery(
    [FromQuery] int Page = 1,
    [FromQuery] int PageSize = 20,
    [FromQuery] string? SortBy = null);
```

---

## Agent Gotchas

1. **Do not use `Results` when `TypedResults` is available** -- `Results.Ok(value)` returns `IResult` and the OpenAPI generator cannot infer response schemas. Use `TypedResults.Ok(value)` to enable automatic schema generation.
2. **Do not forget `ConfigureHttpJsonOptions` only applies to Minimal APIs** -- MVC controllers need `.AddControllers().AddJsonOptions()` separately.
3. **Do not apply validation logic inline in every endpoint** -- use endpoint filters or cross-reference [skill:dotnet-csharp] for centralized validation patterns.
4. **Do not register filters in the wrong order** -- first-registered filter is outermost. Put broad filters (logging) first, specific filters (validation) closer to the handler.
5. **Do not put all endpoints in `Program.cs`** -- organize into extension method classes or Carter modules once you have more than a handful of endpoints.

---

## Prerequisites

- .NET 8.0+ (LTS baseline for Minimal APIs with route groups and endpoint filters)
- .NET 10.0 for built-in OpenAPI 3.1, SSE, and built-in validation support
- `Microsoft.AspNetCore.OpenApi` for OpenAPI document generation
- `Carter` (optional) for auto-discovery endpoint modules

---

## Knowledge Sources

Minimal API patterns in this skill are grounded in guidance from:

- **David Fowler** -- AspNetCoreDiagnosticScenarios ([github.com/davidfowl/AspNetCoreDiagnosticScenarios](https://github.com/davidfowl/AspNetCoreDiagnosticScenarios)). Authoritative source on ASP.NET Core request pipeline design, middleware best practices, and diagnostic anti-patterns.

> These sources inform the patterns and rationale presented above. This skill does not claim to represent or speak for any individual.

---

## References

- [Minimal APIs Overview](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/minimal-apis?view=aspnetcore-10.0)
- [Route Groups](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/minimal-apis/route-handlers?view=aspnetcore-10.0#route-groups)
- [Endpoint Filters](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/minimal-apis/min-api-filters?view=aspnetcore-10.0)
- [OpenAPI in ASP.NET Core](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/openapi/overview?view=aspnetcore-10.0)
- [Carter Library](https://github.com/CarterCommunity/Carter)
