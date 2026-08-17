# Architecture Patterns

Modern architecture patterns for .NET applications. Covers practical approaches to organizing minimal APIs at scale, vertical slice architecture, request pipeline composition, validation strategies, caching, error handling, and idempotency/outbox patterns.

## Agent Gotchas

1. **Idempotency must handle three states and finalize unconditionally** -- Distinguish no-record (claim), in-progress (reject 409), and completed (replay). Do NOT gate finalization on specific `IResult` subtypes -- non-value results like `Results.NoContent()` would be stuck permanently in-progress.
2. **Cache invalidation must be explicit** -- ALWAYS invalidate (evict by tag or key) after write operations. Forgetting invalidation causes stale reads.
3. **HybridCache stampede protection only works with `GetOrCreateAsync`** -- Do NOT use separate get-then-set; use the factory overload so the library serializes concurrent requests for the same key.
4. **Outbox messages must be written in the same transaction as domain data** -- A crash between separate writes loses the event. ALWAYS wrap both in `BeginTransactionAsync`.
5. **Endpoint filter order matters** -- Filters added first run outermost. Validation must run before idempotency, otherwise invalid requests get cached.
6. **Do NOT share `DbContext` across concurrent requests** -- `DbContext` is not thread-safe. Each request must resolve its own scoped instance from DI.

---

## Knowledge Sources

Grounded in publicly available content from Jimmy Bogard (vertical slice architecture, domain events) and Nick Chapsas (result types, modern .NET patterns). This skill applies publicly documented guidance and does not represent or speak for the named sources. MediatR is commercial for commercial use; patterns here use built-in .NET mechanisms.

## References

- [ASP.NET Core Best Practices](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/best-practices?view=aspnetcore-10.0)
- [HybridCache library](https://learn.microsoft.com/en-us/aspnet/core/performance/caching/hybrid)
- [Endpoint filters in minimal APIs](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/minimal-apis/min-api-filters)
- [Vertical Slice Architecture (Jimmy Bogard)](https://www.jimmybogard.com/vertical-slice-architecture/)

---

# Architecture Patterns -- Detailed Examples

Extended code examples for vertical slices, minimal API organization, request pipeline, error handling, validation, caching, idempotency, and outbox patterns.

---

## Vertical Slice Architecture

Organize code by feature (vertical slice) rather than by technical layer (controllers, services, repositories). Each slice owns its endpoint, handler, validation, and data access.

### Directory Structure

```
Features/
  Orders/
    CreateOrder/
      CreateOrderEndpoint.cs
      CreateOrderHandler.cs
      CreateOrderRequest.cs
      CreateOrderValidator.cs
    GetOrder/
      GetOrderEndpoint.cs
      GetOrderHandler.cs
    ListOrders/
      ListOrdersEndpoint.cs
      ListOrdersHandler.cs
  Products/
    GetProduct/
      ...
```

**Benefits:** Low coupling (feature changes don't ripple), easy navigation, independent testability, team scalability.

Each slice contains: **Request/Response DTOs** (contract), **Validator** (input rules), **Handler** (business logic), **Endpoint** (HTTP mapping).

```csharp
public sealed record CreateOrderRequest(
    string CustomerId, List<OrderLineRequest> Lines);
public sealed record OrderLineRequest(string ProductId, int Quantity);
public sealed record CreateOrderResponse(
    string OrderId, decimal Total, DateTimeOffset CreatedAt);
```

---

## Minimal API Organization at Scale

### Route Group Pattern

Use `MapGroup` to organize related endpoints and apply shared filters:

```csharp
// Program.cs -- register feature groups
app.MapGroup("/api/orders").WithTags("Orders").MapOrderEndpoints();
app.MapGroup("/api/products").WithTags("Products").MapProductEndpoints();

// Features/Orders/OrderEndpoints.cs
public static class OrderEndpoints
{
    public static RouteGroupBuilder MapOrderEndpoints(this RouteGroupBuilder group)
    {
        group.MapPost("/", CreateOrderEndpoint.Handle)
             .WithName("CreateOrder")
             .Produces<CreateOrderResponse>(StatusCodes.Status201Created)
             .ProducesValidationProblem();

        group.MapGet("/{id}", GetOrderEndpoint.Handle)
             .WithName("GetOrder")
             .Produces<OrderResponse>()
             .ProducesProblem(StatusCodes.Status404NotFound);

        return group;
    }
}
```

### Endpoint Classes

Keep each endpoint in its own static class with a single `Handle` method:

```csharp
public static class CreateOrderEndpoint
{
    public static async Task<IResult> Handle(
        CreateOrderRequest request,
        IValidator<CreateOrderRequest> validator,
        IOrderService orderService,
        CancellationToken ct)
    {
        var validation = await validator.ValidateAsync(request, ct);
        if (!validation.IsValid)
        {
            return Results.ValidationProblem(validation.ToDictionary());
        }

        var order = await orderService.CreateAsync(request, ct);

        return Results.Created($"/api/orders/{order.OrderId}", order);
    }
}
```

---

## Request Pipeline Composition

### Endpoint Filters (Middleware for Endpoints)

Use endpoint filters for cross-cutting concerns scoped to specific routes:

```csharp
// Validation filter applied to a route group
public sealed class ValidationFilter<TRequest> : IEndpointFilter
    where TRequest : class
{
    public async ValueTask<object?> InvokeAsync(
        EndpointFilterInvocationContext context,
        EndpointFilterDelegate next)
    {
        var request = context.Arguments.OfType<TRequest>().FirstOrDefault();
        if (request is null)
        {
            return Results.BadRequest();
        }

        var validator = context.HttpContext.RequestServices
            .GetService<IValidator<TRequest>>();

        if (validator is not null)
        {
            var result = await validator.ValidateAsync(request);
            if (!result.IsValid)
            {
                return Results.ValidationProblem(result.ToDictionary());
            }
        }

        return await next(context);
    }
}

// Usage
group.MapPost("/", CreateOrderEndpoint.Handle)
     .AddEndpointFilter<ValidationFilter<CreateOrderRequest>>();
```

### Pipeline Order

The standard middleware pipeline order matters:

```csharp
app.UseExceptionHandler();       // 1. Global error handling
app.UseStatusCodePages();        // 2. Status code formatting
app.UseRateLimiter();            // 3. Rate limiting
app.UseAuthentication();         // 4. Authentication
app.UseAuthorization();          // 5. Authorization
// Endpoint routing happens here
```

---

## Error Handling

### Problem Details (RFC 9457)

Use the built-in Problem Details support for consistent error responses:

```csharp
// Program.cs
builder.Services.AddProblemDetails(options =>
{
    options.CustomizeProblemDetails = context =>
    {
        context.ProblemDetails.Extensions["traceId"] =
            context.HttpContext.TraceIdentifier;
    };
});

app.UseExceptionHandler();
app.UseStatusCodePages();
```

### Result Pattern for Business Logic

Return a result type from handlers instead of throwing exceptions for expected business failures:

```csharp
public abstract record Result<T>
{
    public sealed record Success(T Value) : Result<T>;
    public sealed record NotFound(string Message) : Result<T>;
    public sealed record ValidationFailed(IDictionary<string, string[]> Errors) : Result<T>;
    public sealed record Conflict(string Message) : Result<T>;
}

// In the handler
public async Task<Result<Order>> CreateAsync(
    CreateOrderRequest request,
    CancellationToken ct)
{
    var customer = await _db.Customers.FindAsync([request.CustomerId], ct);
    if (customer is null)
    {
        return new Result<Order>.NotFound($"Customer {request.CustomerId} not found");
    }

    // ... create order
    return new Result<Order>.Success(order);
}

// In the endpoint -- map result to HTTP response
return result switch
{
    Result<Order>.Success s => Results.Created($"/api/orders/{s.Value.Id}", s.Value),
    Result<Order>.NotFound n => Results.Problem(n.Message, statusCode: 404),
    Result<Order>.ValidationFailed v => Results.ValidationProblem(v.Errors),
    Result<Order>.Conflict c => Results.Problem(c.Message, statusCode: 409),
    _ => Results.Problem("Unexpected error", statusCode: 500)
};
```

---

## Validation Strategy

Choose validation based on complexity. For .NET 10+, prefer the built-in `AddValidation()` source-generator pipeline (see [skill:dotnet-csharp]). For detailed framework guidance, see [skill:dotnet-csharp].

**Data Annotations (simple):** Use `[Required]`, `[MaxLength]`, `[Range]` on record properties. In minimal APIs, validate via `MiniValidation` (`MiniValidator.TryValidate`) or the .NET 10+ built-in pipeline.

**FluentValidation (complex):** Use for cross-property rules, conditional logic, or database-dependent checks:

```csharp
builder.Services.AddValidatorsFromAssemblyContaining<Program>(ServiceLifetime.Scoped);

public sealed class CreateOrderValidator : AbstractValidator<CreateOrderRequest>
{
    public CreateOrderValidator()
    {
        RuleFor(x => x.CustomerId).NotEmpty().MaximumLength(50);
        RuleFor(x => x.Lines).NotEmpty()
            .WithMessage("Order must have at least one line item");
        RuleForEach(x => x.Lines).ChildRules(line =>
        {
            line.RuleFor(l => l.ProductId).NotEmpty();
            line.RuleFor(l => l.Quantity).GreaterThan(0);
        });
    }
}
```

---

## Caching Strategy

Choose the right caching level:

- **Output Caching** -- HTTP response caching via `AddOutputCache()`. Use `.CacheOutput("PolicyName")` on endpoints and `EvictByTagAsync` to invalidate after writes. Best for read-heavy GET endpoints.
- **Distributed Caching** -- Application-level caching via `IDistributedCache` (e.g., `AddStackExchangeRedisCache()`). Manual get/set with serialization. Use when sharing cached data across app instances.
- **HybridCache (.NET 9+)** -- Preferred for new projects. Combines L1 (in-memory) + L2 (distributed) with built-in stampede protection.

### HybridCache (Primary Pattern)

```csharp
builder.Services.AddHybridCache(options =>
{
    options.DefaultEntryOptions = new HybridCacheEntryOptions
    {
        Expiration = TimeSpan.FromMinutes(10),
        LocalCacheExpiration = TimeSpan.FromMinutes(2)
    };
});

// Stampede-safe, two-tier -- always use GetOrCreateAsync (not separate get/set)
public sealed class ProductService(HybridCache cache, AppDbContext db)
{
    public async Task<Product?> GetByIdAsync(
        string id, CancellationToken ct = default)
    {
        return await cache.GetOrCreateAsync(
            $"product:{id}",
            async cancel => await db.Products.FindAsync([id], cancel),
            cancellationToken: ct);
    }
}
```

### Output Caching Example

```csharp
builder.Services.AddOutputCache(options =>
{
    options.AddBasePolicy(p => p.NoCache());
    options.AddPolicy("ProductList", p =>
        p.Expire(TimeSpan.FromMinutes(5)).Tag("products"));
});

app.UseOutputCache();

group.MapGet("/", ListProductsEndpoint.Handle)
     .CacheOutput("ProductList");

// Always invalidate after writes
app.MapPost("/api/products", async (IOutputCacheStore cache, /* ... */) =>
{
    // ... create product
    await cache.EvictByTagAsync("products", ct);
    return Results.Created(/* ... */);
});
```

---

## Idempotency and Outbox Pattern

### Idempotency Keys

Prevent duplicate processing of retried requests. A robust idempotency implementation must:

1. **Scope keys** by route + user/tenant to prevent cross-endpoint collisions
2. **Atomically claim** the key before executing, so concurrent duplicates are rejected
3. **Store a concrete response envelope** (not an `IResult` reference) for safe replay

#### Database-Backed Idempotency (Recommended)

Use a database row with a unique constraint for atomic claim-then-execute:

```csharp
public sealed class IdempotencyRecord
{
    public required string Key { get; init; }
    public required string RequestRoute { get; init; }
    public required string? UserId { get; init; }
    public int StatusCode { get; set; }
    public string? ResponseBody { get; set; }
    public string? ContentType { get; set; }
    public DateTimeOffset CreatedAt { get; init; } = DateTimeOffset.UtcNow;
    public bool IsCompleted { get; set; }
}

public sealed class IdempotencyFilter(AppDbContext db) : IEndpointFilter
{
    public async ValueTask<object?> InvokeAsync(
        EndpointFilterInvocationContext context,
        EndpointFilterDelegate next)
    {
        var httpContext = context.HttpContext;
        if (!httpContext.Request.Headers.TryGetValue(
            "Idempotency-Key", out var keyValues))
            return await next(context);

        var clientKey = keyValues.ToString();
        if (string.IsNullOrWhiteSpace(clientKey) || clientKey.Length > 256)
            return Results.Problem("Invalid Idempotency-Key", statusCode: 400);

        // Scope key: route + user + client key
        var route = $"{httpContext.Request.Method}:{httpContext.Request.Path}";
        var userId = httpContext.User.FindFirst("sub")?.Value ?? "anonymous";
        var scopedKey = $"{route}:{userId}:{clientKey}";

        var existing = await db.IdempotencyRecords
            .FirstOrDefaultAsync(r => r.Key == scopedKey);

        // Completed: replay cached response
        if (existing is { IsCompleted: true })
        {
            return existing.ResponseBody is not null
                ? Results.Text(existing.ResponseBody,
                    existing.ContentType ?? "application/json",
                    statusCode: existing.StatusCode)
                : Results.StatusCode(existing.StatusCode);
        }

        // In-progress: reject duplicate
        if (existing is { IsCompleted: false })
            return Results.Problem("Duplicate request in progress", statusCode: 409);

        // Claim: unique constraint prevents concurrent duplicates
        var record = new IdempotencyRecord
        {
            Key = scopedKey, RequestRoute = route,
            UserId = userId, IsCompleted = false
        };
        db.IdempotencyRecords.Add(record);

        try { await db.SaveChangesAsync(); }
        catch (DbUpdateException)
        {
            return Results.Problem("Duplicate request in progress", statusCode: 409);
        }

        var result = await next(context);

        // Finalize unconditionally -- handles value and non-value results
        record.StatusCode = result is IStatusCodeHttpResult sc
            ? sc.StatusCode ?? 200 : 200;
        record.ResponseBody = result is IValueHttpResult vr
            ? JsonSerializer.Serialize(vr.Value) : null;
        record.ContentType = record.ResponseBody is not null
            ? "application/json" : null;
        record.IsCompleted = true;
        await db.SaveChangesAsync();

        return result;
    }
}
```

**Key design choices:**
- **Three states**: no record (claim), in-progress (reject 409), completed (replay)
- Unique constraint on `Key` provides atomic claim without distributed locks
- Scoped key (`route:userId:clientKey`) prevents cross-endpoint and cross-tenant collisions
- Response envelope stores serialized body + status code (not `IResult` references)
- Consider a cleanup job for abandoned in-progress records (process crash scenarios)

### Transactional Outbox Pattern

Guarantee at-least-once delivery of domain events alongside database writes:

```csharp
// 1. Store outbox messages in the same transaction as the domain write
public sealed class OutboxMessage
{
    public Guid Id { get; init; } = Guid.NewGuid();
    public required string EventType { get; init; }
    public required string Payload { get; init; }
    public DateTimeOffset CreatedAt { get; init; } = DateTimeOffset.UtcNow;
    public DateTimeOffset? ProcessedAt { get; set; }
}

// 2. In the handler -- same DbContext transaction
public async Task<Order> CreateOrderAsync(
    CreateOrderRequest request,
    CancellationToken ct)
{
    await using var transaction = await _db.Database
        .BeginTransactionAsync(ct);

    var order = new Order { /* ... */ };
    _db.Orders.Add(order);

    _db.OutboxMessages.Add(new OutboxMessage
    {
        EventType = "OrderCreated",
        Payload = JsonSerializer.Serialize(
            new OrderCreatedEvent(order.Id, order.Total))
    });

    await _db.SaveChangesAsync(ct);
    await transaction.CommitAsync(ct);

    return order;
}

// 3. Background processor publishes outbox messages
// See [skill:dotnet-api] (`references/background-services.md`) for the
// Channels-based processor that polls and publishes these messages.
```

The outbox pattern ensures that if the database write succeeds, the event is guaranteed to be published (eventually), even if the message broker is temporarily unavailable.

---

## Key Principles

- **Prefer composition** -- endpoint filters, middleware, and pipeline composition over base classes
- **Keep slices independent** -- DRY applies to knowledge duplication, not code similarity across features
- **Validate early, fail fast** -- validate at the boundary before entering business logic
- **Use Problem Details everywhere** -- consistent error format via RFC 9457
- **Make writes idempotent** -- use idempotency keys for retryable operations
- See [skill:dotnet-csharp] for SOLID anti-patterns and compliance guidance

---
