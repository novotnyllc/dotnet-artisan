# EF Core Patterns

Tactical patterns for Entity Framework Core in .NET applications. Covers DbContext lifetime management, read-only query optimization, query splitting, migration workflows, interceptors, compiled queries, and connection resiliency. These patterns apply to EF Core 8+ and are compatible with SQL Server, PostgreSQL, and SQLite providers.

## DbContext Lifecycle

`DbContext` is a unit of work and should be short-lived. In ASP.NET Core, register it as scoped (one per request):

```csharp
builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseNpgsql(builder.Configuration.GetConnectionString("DefaultConnection")));
```

### Lifetime Rules

| Scenario | Lifetime | Registration |
|----------|----------|-------------|
| Web API / MVC request | Scoped (default) | `AddDbContext<T>()` |
| Background service | Scoped via factory | `AddDbContextFactory<T>()` |
| Blazor Server | Scoped via factory | `AddDbContextFactory<T>()` |
| Console app | Transient or manual | `new AppDbContext(options)` |

### DbContextFactory for Long-Lived Services

Background services and Blazor Server circuits outlive a single scope. Use `IDbContextFactory<T>` to create short-lived contexts on demand:

```csharp
public sealed class OrderProcessor(
    IDbContextFactory<AppDbContext> contextFactory)
{
    public async Task ProcessBatchAsync(CancellationToken ct)
    {
        // Each iteration gets its own short-lived DbContext
        await using var db = await contextFactory.CreateDbContextAsync(ct);

        var pending = await db.Orders
            .Where(o => o.Status == OrderStatus.Pending)
            .ToListAsync(ct);

        foreach (var order in pending)
        {
            order.Status = OrderStatus.Processing;
        }

        await db.SaveChangesAsync(ct);
    }
}
```

Register the factory:

```csharp
builder.Services.AddDbContextFactory<AppDbContext>(options =>
    options.UseNpgsql(builder.Configuration.GetConnectionString("DefaultConnection")));
```

**Important:** `AddDbContextFactory<T>()` also registers `AppDbContext` itself as scoped, so controllers and request-scoped services can still inject `AppDbContext` directly.

### Pooling

`AddDbContextPool<T>()` and `AddPooledDbContextFactory<T>()` reuse `DbContext` instances to reduce allocation overhead. Use pooling when throughput matters and your context has no injected scoped services:

```csharp
builder.Services.AddDbContextPool<AppDbContext>(options =>
    options.UseNpgsql(connectionString),
    poolSize: 128);  // default is 1024
```

**Pooling constraints:** Pooled contexts are reset and reused. Do not store per-request state on the `DbContext` subclass. Do not inject scoped services into the constructor -- use `IDbContextFactory<T>` with pooling (`AddPooledDbContextFactory<T>()`) if you need factory semantics.

---

## AsNoTracking for Read-Only Queries

By default, EF Core tracks all entities returned by queries, enabling change detection on `SaveChangesAsync()`. For read-only queries, disable tracking to reduce memory and CPU overhead:

```csharp
// Per-query opt-out
var orders = await db.Orders
    .AsNoTracking()
    .Where(o => o.CustomerId == customerId)
    .ToListAsync(ct);

// Per-query with identity resolution (deduplicates entities in the result set)
var ordersWithItems = await db.Orders
    .AsNoTrackingWithIdentityResolution()
    .Include(o => o.Items)
    .Where(o => o.Status == OrderStatus.Active)
    .ToListAsync(ct);
```

### Default No-Tracking at the Context Level

For read-heavy services, set no-tracking as the default:

```csharp
builder.Services.AddDbContext<ReadOnlyDbContext>(options =>
    options.UseNpgsql(connectionString)
           .UseQueryTrackingBehavior(QueryTrackingBehavior.NoTracking));
```

Then opt-in to tracking only when needed:

```csharp
var order = await readOnlyDb.Orders
    .AsTracking()
    .FirstAsync(o => o.Id == orderId, ct);
```

---

## Query Splitting

When loading collections via `Include()`, EF Core generates a single SQL query with JOINs by default. This produces a Cartesian explosion when multiple collections are included.

### The Problem: Cartesian Explosion

```csharp
// Single query: produces Cartesian product of OrderItems x Payments
var orders = await db.Orders
    .Include(o => o.Items)      // N items
    .Include(o => o.Payments)   // M payments
    .ToListAsync(ct);
// Result set: N x M rows per order
```

### The Solution: Split Queries

```csharp
var orders = await db.Orders
    .Include(o => o.Items)
    .Include(o => o.Payments)
    .AsSplitQuery()
    .ToListAsync(ct);
// Executes 3 separate queries: Orders, Items, Payments
```

### Tradeoffs

| Approach | Pros | Cons |
|----------|------|------|
| Single query (default) | Atomic snapshot, one round-trip | Cartesian explosion with multiple Includes |
| Split query | No Cartesian explosion, less data transfer | Multiple round-trips, no atomicity guarantee |

**Rule of thumb:** Use `AsSplitQuery()` when including two or more collection navigations. Use the default single query for single-collection includes or when atomicity matters.

### Global Default

Set split queries as the default at the provider level:

```csharp
options.UseNpgsql(connectionString, npgsql =>
    npgsql.UseQuerySplittingBehavior(QuerySplittingBehavior.SplitQuery));
```

Then opt-in to single queries where atomicity is needed:

```csharp
var result = await db.Orders
    .Include(o => o.Items)
    .Include(o => o.Payments)
    .AsSingleQuery()
    .ToListAsync(ct);
```

---

## Migrations

### Migration Workflow

```bash
# Create a migration after model changes
dotnet ef migrations add AddOrderStatus \
    --project src/MyApp.Infrastructure \
    --startup-project src/MyApp.Api

# Review the generated SQL before applying
dotnet ef migrations script \
    --project src/MyApp.Infrastructure \
    --startup-project src/MyApp.Api \
    --idempotent \
    --output migrations.sql

# Apply in development
dotnet ef database update \
    --project src/MyApp.Infrastructure \
    --startup-project src/MyApp.Api
```

### Migration Bundles for Production

Migration bundles produce a self-contained executable for CI/CD pipelines -- no `dotnet ef` tooling needed on the deployment server:

```bash
# Build the bundle
dotnet ef migrations bundle \
    --project src/MyApp.Infrastructure \
    --startup-project src/MyApp.Api \
    --output efbundle \
    --self-contained

# Run in production -- pass connection string explicitly via --connection
./efbundle --connection "Host=prod-db;Database=myapp;Username=deploy;Password=..."

# Alternatively, configure the bundle to read from an environment variable
# by setting the connection string key in your DbContext's OnConfiguring or
# appsettings.json, then pass the env var at runtime:
# ConnectionStrings__DefaultConnection="Host=..." ./efbundle
```

### Migration Best Practices

1. **Always generate idempotent scripts** for production deployments (`--idempotent` flag).
2. **Never call `Database.Migrate()` at application startup** in production -- it races with horizontal scaling and lacks rollback. Use migration bundles or idempotent scripts applied from CI/CD.
3. **Keep migrations additive** -- add columns with defaults, add tables, add indexes. Avoid destructive changes (drop column, rename table) in the same release as code changes.
4. **Review generated code** -- EF Core migration scaffolding can produce unexpected SQL. Always review the `Up()` and `Down()` methods.
5. **Use separate migration projects** -- keep migrations in an infrastructure project, not the API project. Specify `--project` and `--startup-project` explicitly.

### Data Seeding

Use `HasData()` for reference data that should be part of migrations:

```csharp
protected override void OnModelCreating(ModelBuilder modelBuilder)
{
    modelBuilder.Entity<OrderStatus>().HasData(
        new OrderStatus { Id = 1, Name = "Pending" },
        new OrderStatus { Id = 2, Name = "Processing" },
        new OrderStatus { Id = 3, Name = "Completed" },
        new OrderStatus { Id = 4, Name = "Cancelled" });
}
```

**Important:** `HasData()` uses primary key values for identity. Changing a seed value's PK in a later migration deletes the old row and inserts a new one -- it does not update in place.

---

## Interceptors

EF Core interceptors allow cross-cutting concerns to be injected into the database pipeline without modifying entity logic. Interceptors run for every operation of their type.

### SaveChanges Interceptor: Automatic Audit Timestamps

```csharp
public sealed class AuditTimestampInterceptor : SaveChangesInterceptor
{
    public override ValueTask<InterceptionResult<int>> SavingChangesAsync(
        DbContextEventData eventData,
        InterceptionResult<int> result,
        CancellationToken ct = default)
    {
        if (eventData.Context is null)
            return ValueTask.FromResult(result);

        var now = DateTimeOffset.UtcNow;

        foreach (var entry in eventData.Context.ChangeTracker.Entries<IAuditable>())
        {
            switch (entry.State)
            {
                case EntityState.Added:
                    entry.Entity.CreatedAt = now;
                    entry.Entity.UpdatedAt = now;
                    break;
                case EntityState.Modified:
                    entry.Entity.UpdatedAt = now;
                    break;
            }
        }

        return ValueTask.FromResult(result);
    }
}

public interface IAuditable
{
    DateTimeOffset CreatedAt { get; set; }
    DateTimeOffset UpdatedAt { get; set; }
}
```

### Soft Delete Interceptor

```csharp
public sealed class SoftDeleteInterceptor : SaveChangesInterceptor
{
    public override ValueTask<InterceptionResult<int>> SavingChangesAsync(
        DbContextEventData eventData,
        InterceptionResult<int> result,
        CancellationToken ct = default)
    {
        if (eventData.Context is null)
            return ValueTask.FromResult(result);

        foreach (var entry in eventData.Context.ChangeTracker.Entries<ISoftDeletable>())
        {
            if (entry.State == EntityState.Deleted)
            {
                entry.State = EntityState.Modified;
                entry.Entity.IsDeleted = true;
                entry.Entity.DeletedAt = DateTimeOffset.UtcNow;
            }
        }

        return ValueTask.FromResult(result);
    }
}
```

Combine with a global query filter so soft-deleted entities are excluded by default:

```csharp
protected override void OnModelCreating(ModelBuilder modelBuilder)
{
    modelBuilder.Entity<Product>()
        .HasQueryFilter(p => !p.IsDeleted);
}

// Bypass the filter when needed (e.g., admin queries)
var allProducts = await db.Products
    .IgnoreQueryFilters()
    .ToListAsync(ct);
```

### Connection Interceptor: Dynamic Connection Strings

```csharp
public sealed class TenantConnectionInterceptor(
    ITenantProvider tenantProvider) : DbConnectionInterceptor
{
    public override ValueTask<InterceptionResult> ConnectionOpeningAsync(
        DbConnection connection,
        ConnectionEventData eventData,
        InterceptionResult result,
        CancellationToken ct = default)
    {
        var tenant = tenantProvider.GetCurrentTenant();
        connection.ConnectionString = tenant.ConnectionString;
        return ValueTask.FromResult(result);
    }
}
```

### Registering Interceptors

```csharp
builder.Services.AddDbContext<AppDbContext>((sp, options) =>
    options.UseNpgsql(connectionString)
           .AddInterceptors(
               sp.GetRequiredService<AuditTimestampInterceptor>(),
               sp.GetRequiredService<SoftDeleteInterceptor>()));

// Register interceptors in DI
builder.Services.AddSingleton<AuditTimestampInterceptor>();
builder.Services.AddSingleton<SoftDeleteInterceptor>();
```

---

## Compiled Queries

For queries executed very frequently with the same shape, compiled queries eliminate the overhead of expression tree translation on every call:

```csharp
public static class CompiledQueries
{
    // Single-result compiled query -- delegate does NOT accept CancellationToken
    public static readonly Func<AppDbContext, int, Task<Order?>>
        GetOrderById = EF.CompileAsyncQuery(
            (AppDbContext db, int orderId) =>
                db.Orders
                    .AsNoTracking()
                    .Include(o => o.Items)
                    .FirstOrDefault(o => o.Id == orderId));

    // Multi-result compiled query returns IAsyncEnumerable
    public static readonly Func<AppDbContext, string, IAsyncEnumerable<Order>>
        GetOrdersByCustomer = EF.CompileAsyncQuery(
            (AppDbContext db, string customerId) =>
                db.Orders
                    .AsNoTracking()
                    .Where(o => o.CustomerId == customerId)
                    .OrderByDescending(o => o.CreatedAt));
}

// Usage
var order = await CompiledQueries.GetOrderById(db, orderId);

// IAsyncEnumerable results support cancellation via WithCancellation:
await foreach (var o in CompiledQueries.GetOrdersByCustomer(db, customerId)
    .WithCancellation(ct))
{
    // Process each order
}
```

**When to use:** Compiled queries provide measurable benefit for queries that execute thousands of times per second. For typical CRUD endpoints, standard LINQ is sufficient -- do not prematurely optimize.

**Cancellation limitation:** Single-result compiled query delegates (`Task<T?>`) do not accept `CancellationToken`. If per-call cancellation is required, use standard async LINQ (`FirstOrDefaultAsync(ct)`) instead of a compiled query. Multi-result compiled queries (`IAsyncEnumerable<T>`) support cancellation via `.WithCancellation(ct)` on the async enumerable.

---

## Connection Resiliency

Transient database failures (network blips, failovers) should be handled with automatic retry. Each provider has a built-in execution strategy:

```csharp
// PostgreSQL
options.UseNpgsql(connectionString, npgsql =>
    npgsql.EnableRetryOnFailure(
        maxRetryCount: 3,
        maxRetryDelay: TimeSpan.FromSeconds(30),
        errorCodesToAdd: null));

// SQL Server
options.UseSqlServer(connectionString, sqlServer =>
    sqlServer.EnableRetryOnFailure(
        maxRetryCount: 3,
        maxRetryDelay: TimeSpan.FromSeconds(30),
        errorNumbersToAdd: null));
```

### Manual Execution Strategies

When you need to wrap multiple `SaveChangesAsync` calls in a single logical transaction with retries:

```csharp
var strategy = db.Database.CreateExecutionStrategy();

await strategy.ExecuteAsync(async () =>
{
    await using var transaction = await db.Database.BeginTransactionAsync(ct);

    var order = await db.Orders.FindAsync([orderId], ct);
    order!.Status = OrderStatus.Completed;
    await db.SaveChangesAsync(ct);

    var payment = new Payment { OrderId = orderId, Amount = order.Total };
    db.Payments.Add(payment);
    await db.SaveChangesAsync(ct);

    await transaction.CommitAsync(ct);
});
```

**Important:** The entire delegate is re-executed on retry, including the transaction. Ensure the logic is idempotent or uses database-level uniqueness constraints to prevent duplicates.

---

## Key Principles

- **Keep DbContext short-lived** -- one per request in web apps, one per unit of work in background services via `IDbContextFactory<T>`
- **Default to AsNoTracking for reads** -- opt in to tracking only when you need change detection
- **Use split queries for multiple collection Includes** -- avoid Cartesian explosion
- **Never call Database.Migrate() at startup in production** -- use migration bundles or idempotent scripts
- **Register interceptors via DI** -- avoid creating interceptor instances manually
- **Enable connection resiliency** -- transient failures are a fact of life in cloud databases

---

## Agent Gotchas

1. **Do not inject `DbContext` into singleton services** -- `DbContext` is scoped. Injecting it into a singleton captures a stale instance. Use `IDbContextFactory<T>` instead.
2. **Do not forget `CancellationToken` propagation** -- pass `ct` to all `ToListAsync()`, `FirstOrDefaultAsync()`, `SaveChangesAsync()`, and other async EF Core methods. Omitting it prevents graceful request cancellation.
3. **Do not use `Database.EnsureCreated()` alongside migrations** -- `EnsureCreated()` creates the schema without migration history, making subsequent migrations fail. Use it only in test scenarios without migrations.
4. **Do not assume `SaveChangesAsync` is implicitly transactional across multiple calls** -- each `SaveChangesAsync()` is its own transaction. Wrap multiple saves in an explicit `BeginTransactionAsync()` / `CommitAsync()` block when atomicity is required.
5. **Do not hardcode connection strings** -- read from configuration (`builder.Configuration.GetConnectionString("...")`) and inject via environment variables in production.
6. **Do not forget to list required NuGet packages** -- EF Core provider packages (`Microsoft.EntityFrameworkCore.SqlServer`, `Npgsql.EntityFrameworkCore.PostgreSQL`) and the design-time package (`Microsoft.EntityFrameworkCore.Design`) must be referenced explicitly.

---

## References

- [EF Core performance best practices](https://learn.microsoft.com/en-us/ef/core/performance/)
- [DbContext lifetime, configuration, and initialization](https://learn.microsoft.com/en-us/ef/core/dbcontext-configuration/)
- [EF Core interceptors](https://learn.microsoft.com/en-us/ef/core/logging-events-diagnostics/interceptors)
- [EF Core migrations overview](https://learn.microsoft.com/en-us/ef/core/managing-schemas/migrations/)
- [EF Core compiled queries](https://learn.microsoft.com/en-us/ef/core/performance/advanced-performance-topics#compiled-queries)
- [EF Core connection resiliency](https://learn.microsoft.com/en-us/ef/core/miscellaneous/connection-resiliency)
