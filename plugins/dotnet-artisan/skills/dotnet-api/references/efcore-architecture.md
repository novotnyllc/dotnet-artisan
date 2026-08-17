# EF Core Architecture

Strategic architectural patterns for EF Core data layers. Covers read/write model separation, aggregate boundary design, repository vs direct DbContext policy, N+1 query governance, row limit enforcement, and projection patterns. These patterns guide how to structure a data layer -- not how to write individual queries (see [skill:dotnet-api] for tactical usage).

## Package Prerequisites

Examples in this skill use PostgreSQL (`UseNpgsql`). Substitute the provider package for your database:

| Database | Provider Package |
|----------|-----------------|
| PostgreSQL | `Npgsql.EntityFrameworkCore.PostgreSQL` |
| SQL Server | `Microsoft.EntityFrameworkCore.SqlServer` |
| SQLite | `Microsoft.EntityFrameworkCore.Sqlite` |

All examples also require the core `Microsoft.EntityFrameworkCore` package (pulled in transitively by provider packages).

---

## Read/Write Model Separation

Separate read models (queries) from write models (commands) to optimize each path independently. This is not full CQRS -- it is a practical separation using EF Core features.

### Approach: Separate DbContext Types

```csharp
// Write context: full change tracking, navigation properties, interceptors
public sealed class WriteDbContext : DbContext
{
    public DbSet<Order> Orders => Set<Order>();
    public DbSet<Product> Products => Set<Product>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.ApplyConfigurationsFromAssembly(typeof(WriteDbContext).Assembly);
    }
}

// Read context: no-tracking by default, optimized for projections
public sealed class ReadDbContext : DbContext
{
    public DbSet<Order> Orders => Set<Order>();
    public DbSet<Product> Products => Set<Product>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.ApplyConfigurationsFromAssembly(typeof(ReadDbContext).Assembly);
    }

    protected override void OnConfiguring(DbContextOptionsBuilder optionsBuilder)
    {
        // Note: this is supplemental -- primary config is in DI registration
    }
}
```

### Registration

```csharp
// Write context: standard tracking, connection resiliency
builder.Services.AddDbContext<WriteDbContext>(options =>
    options.UseNpgsql(connectionString, npgsql =>
        npgsql.EnableRetryOnFailure(maxRetryCount: 3)));

// Read context: no-tracking, optionally pointed at a read replica
builder.Services.AddDbContext<ReadDbContext>(options =>
    options.UseNpgsql(readReplicaConnectionString ?? connectionString)
           .UseQueryTrackingBehavior(QueryTrackingBehavior.NoTracking));
```

### When to Separate

| Scenario | Recommendation |
|----------|---------------|
| Simple CRUD app | Single `DbContext` with per-query `AsNoTracking()` |
| Read-heavy API with complex queries | Separate read/write contexts |
| Read replica database | Separate contexts with different connection strings |
| CQRS architecture | Separate contexts, possibly separate models |

**Start simple.** Use a single `DbContext` and per-query `AsNoTracking()` until you have a concrete reason to split (different connection strings, divergent model shapes, or query complexity that justifies dedicated read models).

---

## Aggregate Boundaries

An aggregate is a cluster of entities that are always loaded and saved together as a consistency boundary. EF Core maps well to aggregate-oriented design when navigation properties follow aggregate boundaries.

### Defining Aggregates

```csharp
// Order is the aggregate root -- it owns OrderItems
public sealed class Order
{
    public int Id { get; private set; }
    public string CustomerId { get; private set; } = default!;
    public OrderStatus Status { get; private set; }
    public DateTimeOffset CreatedAt { get; private set; }

    // Owned collection -- part of the Order aggregate
    private readonly List<OrderItem> _items = [];
    public IReadOnlyList<OrderItem> Items => _items.AsReadOnly();

    public void AddItem(int productId, int quantity, decimal unitPrice)
    {
        if (Status != OrderStatus.Draft)
            throw new InvalidOperationException("Cannot add items to a non-draft order.");

        _items.Add(new OrderItem(productId, quantity, unitPrice));
    }
}

// OrderItem belongs to the Order aggregate -- no independent access
public sealed class OrderItem
{
    public int Id { get; private set; }
    public int ProductId { get; private set; }
    public int Quantity { get; private set; }
    public decimal UnitPrice { get; private set; }

    internal OrderItem(int productId, int quantity, decimal unitPrice)
    {
        ProductId = productId;
        Quantity = quantity;
        UnitPrice = unitPrice;
    }

    private OrderItem() { } // EF Core constructor
}
```

### EF Core Configuration for Aggregates

```csharp
public sealed class OrderConfiguration : IEntityTypeConfiguration<Order>
{
    public void Configure(EntityTypeBuilder<Order> builder)
    {
        builder.HasKey(o => o.Id);

        builder.Property(o => o.CustomerId).IsRequired().HasMaxLength(50);
        builder.Property(o => o.Status).HasConversion<string>();

        // Owned collection navigation -- cascade delete, no independent DbSet
        builder.OwnsMany(o => o.Items, items =>
        {
            items.WithOwner().HasForeignKey("OrderId");
            items.Property(i => i.ProductId).IsRequired();
        });

        // Alternatively, if OrderItem needs its own table with explicit FK:
        // builder.HasMany(o => o.Items)
        //     .WithOne()
        //     .HasForeignKey("OrderId")
        //     .OnDelete(DeleteBehavior.Cascade);
        //
        // builder.Navigation(o => o.Items)
        //     .UsePropertyAccessMode(PropertyAccessMode.Field);
    }
}
```

### Aggregate Design Rules

1. **Load the entire aggregate** -- do not load partial aggregates. Use `Include()` for the owned collections.
2. **Save through the aggregate root** -- call `SaveChangesAsync()` on the root, not on child entities independently.
3. **Reference other aggregates by ID** -- do not create navigation properties between aggregate roots. Use `CustomerId` (foreign key value), not `Customer` (navigation property).
4. **Keep aggregates small** -- large aggregates cause lock contention and slow loads. If a collection grows unbounded (e.g., audit logs), it does not belong in the aggregate.
5. **One aggregate per transaction** -- modifying multiple aggregates in a single transaction creates coupling. Use domain events or eventual consistency for cross-aggregate operations.

---

## Repository Policy

Whether to use the repository pattern or access `DbContext` directly is a team decision. Both approaches are valid in .NET.

### Option A: Direct DbContext Access

```csharp
public sealed class CreateOrderHandler(WriteDbContext db)
{
    public async Task<int> HandleAsync(
        CreateOrderCommand command,
        CancellationToken ct)
    {
        var order = new Order(command.CustomerId);

        foreach (var item in command.Items)
        {
            order.AddItem(item.ProductId, item.Quantity, item.UnitPrice);
        }

        db.Orders.Add(order);
        await db.SaveChangesAsync(ct);

        return order.Id;
    }
}
```

**Pros:** Simple, no abstraction overhead, full LINQ power, easy to debug.
**Cons:** Business logic can leak into query methods, harder to unit test without a database.

### Option B: Repository per Aggregate Root

```csharp
public interface IOrderRepository
{
    Task<Order?> GetByIdAsync(int id, CancellationToken ct);
    Task AddAsync(Order order, CancellationToken ct);
    Task SaveChangesAsync(CancellationToken ct);
}

public sealed class OrderRepository(WriteDbContext db) : IOrderRepository
{
    public async Task<Order?> GetByIdAsync(int id, CancellationToken ct)
    {
        return await db.Orders
            .Include(o => o.Items)
            .FirstOrDefaultAsync(o => o.Id == id, ct);
    }

    public async Task AddAsync(Order order, CancellationToken ct)
    {
        await db.Orders.AddAsync(order, ct);
    }

    public Task SaveChangesAsync(CancellationToken ct)
    {
        return db.SaveChangesAsync(ct);
    }
}
```

**Pros:** Testable without a database, encapsulates query logic, enforces aggregate loading rules.
**Cons:** Extra abstraction layer, can become a leaky abstraction if LINQ is exposed, repository per aggregate can proliferate.

### Decision Guide

| Factor | Direct DbContext | Repository |
|--------|-----------------|------------|
| Team size | Small, aligned | Large, varied experience |
| Test strategy | Integration tests with real DB | Unit tests with mocked repos |
| Query complexity | High (reports, projections) | Low-medium (CRUD, aggregates) |
| Aggregate discipline | Enforced by convention | Enforced by interface |

**Do not create generic repositories** (`IRepository<T>`). They add abstraction without value -- the generic interface cannot express aggregate-specific loading rules (which Includes to use, which filters to apply). Repository interfaces should be specific to the aggregate root they serve.

---

## N+1 Query Governance

N+1 queries are the most common EF Core performance problem. They occur when code iterates over a collection and executes a query per element, instead of loading all data upfront.

### Detection

Enable sensitive logging in development to see SQL queries:

```csharp
builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseNpgsql(connectionString)
           .LogTo(Console.WriteLine, LogLevel.Information)
           .EnableSensitiveDataLogging()  // Development only
           .EnableDetailedErrors());      // Development only
```

### Common N+1 Patterns and Fixes

**Pattern 1: Lazy loading in a loop**

```csharp
// BAD: N+1 -- each order.Items triggers a query
var orders = await db.Orders.ToListAsync(ct);
foreach (var order in orders)
{
    var total = order.Items.Sum(i => i.Quantity * i.UnitPrice); // Lazy load!
}

// GOOD: Eager load with Include
var orders = await db.Orders
    .Include(o => o.Items)
    .ToListAsync(ct);
```

**Pattern 2: Querying inside a loop**

```csharp
// BAD: N+1 -- one query per customer
foreach (var customerId in customerIds)
{
    var orders = await db.Orders
        .Where(o => o.CustomerId == customerId)
        .ToListAsync(ct);
    // ...
}

// GOOD: Single query with Contains
var orders = await db.Orders
    .Where(o => customerIds.Contains(o.CustomerId))
    .ToListAsync(ct);
```

**Pattern 3: Missing projection**

```csharp
// BAD: Loads full entity graph, then maps in memory
var orders = await db.Orders
    .Include(o => o.Items)
    .Include(o => o.Customer)
    .ToListAsync(ct);
var dtos = orders.Select(o => new OrderDto(...));

// GOOD: Project in the query -- no tracking, no extra data loaded
var dtos = await db.Orders
    .Select(o => new OrderDto
    {
        Id = o.Id,
        CustomerName = o.Customer.Name,
        ItemCount = o.Items.Count,
        Total = o.Items.Sum(i => i.Quantity * i.UnitPrice)
    })
    .ToListAsync(ct);
```

### Governance Checklist

- **Disable lazy loading** -- do not install `Microsoft.EntityFrameworkCore.Proxies` or configure `UseLazyLoadingProxies()`. Eager loading via `Include()` or projection via `Select()` makes data access explicit.
- **Review queries in code review** -- look for loops that access navigation properties or call `FindAsync` / `FirstOrDefaultAsync` per element.
- **Use query tags** -- `db.Orders.TagWith("GetOrderSummary")` makes queries identifiable in logs and profiling tools.
- **Set up EF Core logging in development** -- every lazy load or unexpected query is visible in the console output.

---

## Row Limits and Pagination

Unbounded queries are a production risk. Always limit the number of rows returned.

### Keyset Pagination (Recommended)

Keyset pagination (also called cursor-based or seek pagination) is more efficient than offset pagination for large datasets:

```csharp
public async Task<PagedResult<OrderSummary>> GetOrdersAsync(
    string customerId,
    int? afterId,
    int pageSize,
    CancellationToken ct)
{
    const int maxPageSize = 100;
    pageSize = Math.Min(pageSize, maxPageSize);

    var query = db.Orders
        .AsNoTracking()
        .Where(o => o.CustomerId == customerId);

    if (afterId.HasValue)
    {
        query = query.Where(o => o.Id > afterId.Value);
    }

    var items = await query
        .OrderBy(o => o.Id)
        .Take(pageSize + 1)  // Fetch one extra to detect "has next page"
        .Select(o => new OrderSummary
        {
            Id = o.Id,
            Status = o.Status,
            CreatedAt = o.CreatedAt,
            Total = o.Items.Sum(i => i.Quantity * i.UnitPrice)
        })
        .ToListAsync(ct);

    var hasNext = items.Count > pageSize;
    if (hasNext)
    {
        items.RemoveAt(items.Count - 1);
    }

    return new PagedResult<OrderSummary>
    {
        Items = items,
        HasNextPage = hasNext,
        NextCursor = hasNext ? items[^1].Id : null
    };
}
```

### Offset Pagination (Simple Cases)

For admin UIs or small datasets where exact page numbers matter:

```csharp
var page = await db.Orders
    .AsNoTracking()
    .OrderBy(o => o.CreatedAt)
    .Skip((pageNumber - 1) * pageSize)
    .Take(pageSize)
    .ToListAsync(ct);
```

**Warning:** Offset pagination degrades at scale -- `OFFSET 10000` forces the database to scan and discard 10,000 rows. Prefer keyset pagination for user-facing APIs.

### Row Limit Enforcement

Set a hard upper bound on all queries to prevent accidental full-table scans:

```csharp
// Interceptor approach: enforce max rows at the DbContext level
public sealed class RowLimitInterceptor : IQueryExpressionInterceptor
{
    private const int MaxRows = 1000;

    public Expression QueryCompilationStarting(
        Expression queryExpression,
        QueryExpressionEventData eventData)
    {
        // This is a simplified illustration -- actual implementation requires
        // expression tree analysis to detect existing Take() calls.
        // Consider using a code review rule or analyzer instead.
        return queryExpression;
    }
}
```

**Practical approach:** Rather than a runtime interceptor, enforce row limits through:
1. **Code review convention** -- every `ToListAsync()` must have `Take(N)` or be a `Select()` projection with `Take(N)`.
2. **API-level page size caps** -- validate `pageSize` in the request pipeline before it reaches the query.
3. **Query tags** -- annotate queries with `TagWith()` to identify unbounded queries in monitoring.

---

## Projection Patterns

Projections (`Select()`) are the most effective optimization for read queries. They reduce data transfer, skip change tracking, and eliminate N+1 risks.

### Typed Projections

```csharp
public sealed record OrderSummary
{
    public int Id { get; init; }
    public string CustomerName { get; init; } = default!;
    public int ItemCount { get; init; }
    public decimal Total { get; init; }
    public DateTimeOffset CreatedAt { get; init; }
}

var summaries = await db.Orders
    .Select(o => new OrderSummary
    {
        Id = o.Id,
        CustomerName = o.Customer.Name,
        ItemCount = o.Items.Count,
        Total = o.Items.Sum(i => i.Quantity * i.UnitPrice),
        CreatedAt = o.CreatedAt
    })
    .OrderByDescending(o => o.CreatedAt)
    .Take(50)
    .ToListAsync(ct);
```

### Advantages Over Entity Loading

| Concern | Entity + Include | Projection (Select) |
|---------|------------------|---------------------|
| Change tracking | Yes (unless AsNoTracking) | No |
| Data transferred | All columns | Only selected columns |
| N+1 risk | Yes (lazy nav props) | No (computed in SQL) |
| Cartesian explosion | Yes (multiple Includes) | No (single query) |
| Type safety | Entity types | DTO/record types |

**Rule:** Use projections for all read-only endpoints that return DTOs. Reserve entity loading for commands that modify data.

---

## Key Principles

- **Separate read and write paths** when you have different optimization needs -- do not force a single model to serve both
- **Design aggregates around consistency boundaries** -- not around database tables
- **Reference other aggregates by ID** -- navigation properties between aggregate roots create coupling
- **Ban lazy loading** -- make all data access explicit through `Include()` or `Select()`
- **Enforce row limits** -- every query that returns a list must have an upper bound
- **Project early** -- use `Select()` to push computation to the database and reduce data transfer
- **Prefer keyset pagination** over offset pagination for scalability

---

## Agent Gotchas

1. **Do not create navigation properties between aggregate roots** -- use foreign key values (e.g., `CustomerId`) instead of navigation properties (e.g., `Customer`). Cross-aggregate navigation properties break the consistency boundary and encourage loading data that belongs to another aggregate.
2. **Do not create generic repositories** (`IRepository<T>`) -- they cannot express aggregate-specific loading rules and become leaky abstractions. Create one repository interface per aggregate root with explicit methods.
3. **Do not use `UseLazyLoadingProxies()`** -- lazy loading hides N+1 queries and makes performance unpredictable. Use `Include()` for eager loading or `Select()` for projections.
4. **Do not return `IQueryable<T>` from repositories** -- it leaks persistence concerns to callers and makes query behavior unpredictable (e.g., multiple enumeration, client-side evaluation). Return materialized results (`List<T>`, `T?`).
5. **Do not write `ToListAsync()` without `Take()` on unbounded queries** -- full table scans are a production incident waiting to happen. Always limit the result set.
6. **Do not put audit logs or event streams inside aggregates** -- unbounded collections cause slow loads and lock contention. Model them as separate entities or dedicated stores.

---

## References

- [EF Core performance best practices](https://learn.microsoft.com/en-us/ef/core/performance/)
- [EF Core loading related data](https://learn.microsoft.com/en-us/ef/core/querying/related-data/)
- [EF Core global query filters](https://learn.microsoft.com/en-us/ef/core/querying/filters)
- [Domain-driven design with EF Core](https://learn.microsoft.com/en-us/dotnet/architecture/microservices/microservice-ddd-cqrs-patterns/)
- [EF Core query tags](https://learn.microsoft.com/en-us/ef/core/querying/tags)
- [Keyset pagination in EF Core](https://learn.microsoft.com/en-us/ef/core/querying/pagination#keyset-pagination)
