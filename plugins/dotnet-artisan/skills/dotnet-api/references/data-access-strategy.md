# Data Access Strategy

Decision framework for choosing between Entity Framework Core, Dapper, and raw ADO.NET in .NET applications. Covers performance tradeoffs, feature comparisons, AOT/trimming compatibility, hybrid approaches, and migration paths. Use this skill to make an informed technology decision before writing data access code.

## Decision Matrix

| Factor | EF Core | Dapper | Raw ADO.NET |
|--------|---------|--------|-------------|
| **Learning curve** | Moderate (LINQ, migrations, config) | Low (SQL + mapping) | Low-moderate (SQL + manual mapping) |
| **Productivity** | High (change tracking, migrations, scaffolding) | Moderate (write SQL, auto-map) | Low (everything manual) |
| **Query performance** | Good with projections; overhead from tracking | Near-ADO.NET performance | Fastest possible |
| **Startup time** | Higher (model building, compilation) | Minimal | Minimal |
| **Memory allocation** | Higher (change tracker, proxy objects) | Low (direct mapping) | Lowest |
| **AOT/trimming** | Limited (reflection-heavy, improving) | Good with source generators | Full support |
| **Change tracking** | Built-in | None | None |
| **Migrations** | Built-in | None (use FluentMigrator, DbUp, etc.) | None |
| **LINQ support** | Full (translated to SQL) | None (raw SQL) | None (raw SQL) |
| **Batch operations** | `ExecuteUpdate`/`ExecuteDelete` (EF Core 7+) | Manual batching | Manual batching |
| **Complex mappings** | Excellent (owned types, TPH/TPT/TPC) | Simple POCO mapping | Manual |

---

## When to Choose Each

### Choose EF Core When

- Building CRUD applications with standard domain models
- You need change tracking and automatic dirty detection
- You want schema migrations managed in code
- Your team prefers LINQ over raw SQL
- You are building with .NET Aspire (EF Core has first-class Aspire integration)
- Query performance is acceptable with projections and `AsNoTracking()`

```csharp
// EF Core: expressive, type-safe, with change tracking
var order = await db.Orders
    .Include(o => o.Items)
    .FirstOrDefaultAsync(o => o.Id == orderId, ct);

order!.Status = OrderStatus.Shipped;
await db.SaveChangesAsync(ct); // Automatic dirty detection
```

### Choose Dapper When

- Performance is critical and you need control over SQL
- You are writing complex queries (reporting, analytics, multi-join)
- You need thin data access with minimal abstraction
- Your team is comfortable writing and maintaining SQL
- You need AOT compatibility today (with Dapper.AOT source generator)

```csharp
// Dapper: direct SQL, minimal overhead
await using var connection = new NpgsqlConnection(connectionString);

var orders = await connection.QueryAsync<OrderDto>(
    """
    SELECT o.id, o.customer_id, o.status, o.created_at,
           COUNT(i.id) AS item_count,
           SUM(i.quantity * i.unit_price) AS total
    FROM orders o
    LEFT JOIN order_items i ON i.order_id = o.id
    WHERE o.customer_id = @CustomerId
    GROUP BY o.id, o.customer_id, o.status, o.created_at
    ORDER BY o.created_at DESC
    LIMIT @PageSize
    """,
    new { CustomerId = customerId, PageSize = pageSize });
```

### Choose Raw ADO.NET When

- Maximum performance is non-negotiable (sub-millisecond data access)
- You need full control over connection, command, and reader lifecycle
- You are building a library or framework (no app-level dependencies)
- AOT compatibility is required and no source generators are acceptable
- You are working with stored procedures or database-specific features

```csharp
// Raw ADO.NET: full control, zero abstraction overhead
await using var connection = new NpgsqlConnection(connectionString);
await connection.OpenAsync(ct);

await using var command = connection.CreateCommand();
command.CommandText = "SELECT id, name, price FROM products WHERE category_id = $1";
command.Parameters.AddWithValue(categoryId);

await using var reader = await command.ExecuteReaderAsync(ct);
var products = new List<ProductDto>();

while (await reader.ReadAsync(ct))
{
    products.Add(new ProductDto
    {
        Id = reader.GetInt32(0),
        Name = reader.GetString(1),
        Price = reader.GetDecimal(2)
    });
}
```

---

## Performance Comparison

Approximate overhead per query (relative to raw ADO.NET baseline):

| Operation | ADO.NET | Dapper | EF Core (NoTracking) | EF Core (Tracking) |
|-----------|---------|--------|----------------------|-------------------|
| Simple SELECT by PK | 1x | ~1.05x | ~1.3x | ~1.5x |
| SELECT 100 rows | 1x | ~1.1x | ~1.4x | ~2x |
| INSERT single row | 1x | ~1.1x | ~1.5x | ~2x |
| Complex JOIN query | 1x | ~1.05x | ~1.3-2x (depends on LINQ translation) | ~1.5-2.5x |

**Notes:**
- These are rough relative comparisons -- actual numbers depend on query complexity, database, network latency, and hardware.
- Network latency to the database typically dwarfs ORM overhead. A 1ms query with 5ms network latency is 6ms regardless of ORM.
- EF Core with `Select()` projections and `AsNoTracking()` approaches Dapper performance for most queries.
- Measure your actual workload before choosing based on performance alone.

---

## AOT and Trimming Compatibility

### EF Core

EF Core relies heavily on reflection for model building, change tracking, and query translation. AOT compatibility is improving but not complete:

| Feature | AOT Status (.NET 9+) |
|---------|---------------------|
| Model building | Partial -- requires compiled model (`dotnet ef dbcontext optimize`) |
| Query translation | Not AOT-safe (expression tree compilation) |
| Change tracking | Not AOT-safe (proxy generation, snapshot creation) |
| Migrations | Design-time only -- not needed at runtime |

**Compiled models** pre-generate the model configuration at build time, reducing startup cost and improving trim-friendliness:

```bash
dotnet ef dbcontext optimize \
    --project src/MyApp.Infrastructure \
    --startup-project src/MyApp.Api \
    --output-dir CompiledModels
```

```csharp
options.UseNpgsql(connectionString)
       .UseModel(AppDbContextModel.Instance);  // Pre-compiled model
```

**Bottom line:** EF Core Native AOT support is partial and version-dependent. As of .NET 9, compiled models improve startup and trim-friendliness, but query translation and change tracking still rely on runtime code generation. Check the [current limitations](https://learn.microsoft.com/en-us/ef/core/performance/advanced-performance-topics#compiled-models) for your target version before committing to EF Core in an AOT deployment. Use compiled models to improve startup time where possible, but plan for Dapper.AOT or ADO.NET fallbacks on AOT-critical paths.

### Dapper

Dapper traditionally uses runtime reflection and emit for POCO mapping. The `Dapper.AOT` source generator provides a trim- and AOT-compatible alternative:

| Package | AOT Status |
|---------|-----------|
| `Dapper` (standard) | Not AOT-safe (uses Reflection.Emit) |
| `Dapper.AOT` | AOT-safe (source-generated mappers) |

```xml
<PackageReference Include="Dapper" Version="2.*" />
<PackageReference Include="Dapper.AOT" Version="1.*" />
```

```csharp
// Dapper.AOT generates the mapping code at compile time
// Usage is the same as standard Dapper -- the source generator intercepts calls

[DapperAot]  // Attribute enables AOT generation for this class
public sealed class OrderRepository(NpgsqlDataSource dataSource)
{
    public async Task<OrderDto?> GetByIdAsync(int id, CancellationToken ct)
    {
        await using var connection = await dataSource.OpenConnectionAsync(ct);
        return await connection.QuerySingleOrDefaultAsync<OrderDto>(
            "SELECT id, customer_id, status FROM orders WHERE id = @Id",
            new { Id = id });
    }
}
```

### Raw ADO.NET

Full AOT and trimming support. No reflection, no code generation -- all mapping is explicit.

### AOT Decision Guide

| Requirement | Recommendation |
|-------------|---------------|
| Must publish AOT today | Dapper.AOT or raw ADO.NET |
| Prefer ORM, AOT not required | EF Core |
| Prefer ORM, AOT planned for future | EF Core now, evaluate AOT support as it improves |
| Building a library consumed by AOT apps | Raw ADO.NET or Dapper.AOT |

---

## Hybrid Approaches

Most production applications benefit from using multiple data access technologies. EF Core and Dapper can coexist in the same project, sharing the same database connection.

### EF Core for Commands, Dapper for Queries

```csharp
// Command: use EF Core for change tracking and validation
public sealed class CreateOrderHandler(WriteDbContext db)
{
    public async Task<int> HandleAsync(CreateOrderCommand command, CancellationToken ct)
    {
        var order = new Order(command.CustomerId);
        // ... business logic ...
        db.Orders.Add(order);
        await db.SaveChangesAsync(ct);
        return order.Id;
    }
}

// Query: use Dapper for complex read-only queries
public sealed class OrderReportHandler(NpgsqlDataSource dataSource)
{
    public async Task<IReadOnlyList<OrderReportRow>> HandleAsync(
        OrderReportQuery query,
        CancellationToken ct)
    {
        await using var connection = await dataSource.OpenConnectionAsync(ct);
        var rows = await connection.QueryAsync<OrderReportRow>(
            """
            SELECT
                date_trunc('day', o.created_at) AS day,
                COUNT(*) AS order_count,
                SUM(i.quantity * i.unit_price) AS revenue
            FROM orders o
            JOIN order_items i ON i.order_id = o.id
            WHERE o.created_at >= @StartDate AND o.created_at < @EndDate
            GROUP BY date_trunc('day', o.created_at)
            ORDER BY day
            """,
            new { query.StartDate, query.EndDate });
        return rows.AsList();
    }
}
```

### Sharing the Database Connection

Use `DbContext.Database.GetDbConnection()` to get the underlying `DbConnection` for Dapper queries within an EF Core transaction:

```csharp
public async Task ProcessWithBothAsync(int orderId, CancellationToken ct)
{
    var connection = db.Database.GetDbConnection();
    await db.Database.OpenConnectionAsync(ct);

    await using var transaction = await db.Database.BeginTransactionAsync(ct);

    // EF Core operation
    var order = await db.Orders.FindAsync([orderId], ct);
    order!.Status = OrderStatus.Processing;
    await db.SaveChangesAsync(ct);

    // Dapper operation on the same connection and transaction
    await connection.ExecuteAsync(
        """
        INSERT INTO audit_log (entity_type, entity_id, action, timestamp)
        VALUES (@Type, @Id, @Action, @Timestamp)
        """,
        new { Type = "Order", Id = orderId, Action = "StatusChange",
              Timestamp = DateTimeOffset.UtcNow },
        transaction: transaction.GetDbTransaction());

    await transaction.CommitAsync(ct);
}
```

### NpgsqlDataSource Registration

When using Dapper with PostgreSQL, register `NpgsqlDataSource` as a singleton in DI (it manages connection pooling internally):

```csharp
builder.Services.AddNpgsqlDataSource(
    builder.Configuration.GetConnectionString("DefaultConnection")!);
```

The `Npgsql.DependencyInjection` package provides `AddNpgsqlDataSource()`. This also integrates with EF Core -- `UseNpgsql()` can accept the registered data source:

```csharp
builder.Services.AddDbContext<AppDbContext>((sp, options) =>
    options.UseNpgsql(sp.GetRequiredService<NpgsqlDataSource>()));
```

---

## Migration Paths

### From Raw ADO.NET to Dapper

Dapper wraps `IDbConnection` extension methods around existing ADO.NET code. Migration is incremental:

1. Replace `DbDataReader` loops with `QueryAsync<T>()` calls.
2. Replace `command.Parameters.AddWithValue()` with anonymous objects.
3. No schema changes, no new dependencies beyond the `Dapper` NuGet package.

### From Dapper to EF Core

1. Add EF Core packages and create a `DbContext` with entity configurations.
2. Generate initial migration from existing database: `dotnet ef dbcontext scaffold`.
3. Gradually replace Dapper queries with EF Core in new features.
4. Keep Dapper for complex reporting queries -- hybrid is fine.

### From EF Core to Dapper/ADO.NET (Performance-Critical Paths)

1. Identify hot paths via profiling (OpenTelemetry traces, database query stats).
2. Replace specific queries with Dapper, sharing the same connection.
3. Keep EF Core for CRUD operations that benefit from change tracking.

---

## Package Reference

| Package | Purpose | NuGet |
|---------|---------|-------|
| `Microsoft.EntityFrameworkCore` | Core EF framework | `Microsoft.EntityFrameworkCore` |
| `Microsoft.EntityFrameworkCore.Design` | CLI tooling (migrations, scaffolding) | Design-time only |
| `Npgsql.EntityFrameworkCore.PostgreSQL` | PostgreSQL EF Core provider | `Npgsql.EntityFrameworkCore.PostgreSQL` |
| `Microsoft.EntityFrameworkCore.SqlServer` | SQL Server EF Core provider | `Microsoft.EntityFrameworkCore.SqlServer` |
| `Microsoft.EntityFrameworkCore.Sqlite` | SQLite EF Core provider | `Microsoft.EntityFrameworkCore.Sqlite` |
| `Dapper` | Micro-ORM | `Dapper` |
| `Dapper.AOT` | AOT-compatible source generator for Dapper | `Dapper.AOT` |
| `Npgsql.DependencyInjection` | `NpgsqlDataSource` DI registration | `Npgsql.DependencyInjection` |
| `Npgsql` | PostgreSQL ADO.NET provider | `Npgsql` |
| `Microsoft.Data.SqlClient` | SQL Server ADO.NET provider | `Microsoft.Data.SqlClient` |
| `FluentMigrator` | Code-based migrations (non-EF) | `FluentMigrator` |
| `DbUp` | SQL script-based migrations (non-EF) | `dbup` |

---

## Key Principles

- **Choose based on your actual needs** -- not on performance benchmarks. Network latency to the database dwarfs ORM overhead for most applications.
- **EF Core is the default choice** for .NET applications -- it provides productivity, safety, and migrations. Optimize with Dapper when profiling identifies specific bottlenecks.
- **Hybrid is the pragmatic answer** -- use EF Core for commands and Dapper for complex queries. They share connections and transactions.
- **AOT compatibility matters if you need it** -- if publishing AOT is a hard requirement today, use Dapper.AOT or raw ADO.NET. EF Core AOT support is improving but incomplete.
- **Do not prematurely optimize** -- start with EF Core, use `AsNoTracking()` and `Select()` projections, and measure before introducing Dapper.
- **Migrations are a real productivity feature** -- if you choose Dapper, plan your migration strategy separately (FluentMigrator, DbUp, or manual scripts).

---

## Agent Gotchas

1. **Do not recommend Dapper purely for performance** without first checking whether EF Core with `AsNoTracking()` and `Select()` projections meets the performance requirement. The difference is often negligible when EF Core is used correctly.
2. **Do not use standard `Dapper` in AOT-published applications** -- it uses `Reflection.Emit` which is not AOT-compatible. Use `Dapper.AOT` with the `[DapperAot]` attribute for AOT scenarios.
3. **Do not forget to list required NuGet packages** -- both EF Core providers (e.g., `Npgsql.EntityFrameworkCore.PostgreSQL`) and Dapper packages must be explicitly referenced. Agents that generate code without package references produce non-compiling projects.
4. **Do not create new `NpgsqlConnection` instances manually in DI-registered services** -- use `NpgsqlDataSource` (registered via `AddNpgsqlDataSource()`) which manages connection pooling. Creating connections manually bypasses pool management.
5. **Do not mix EF Core and Dapper on separate connections within the same logical transaction** -- use `DbContext.Database.GetDbConnection()` to share the connection and `transaction.GetDbTransaction()` to share the transaction.
6. **Do not assume EF Core LINQ translates all C# expressions to SQL** -- unsupported expressions silently evaluate client-side in older versions or throw in newer versions. Check the generated SQL with `ToQueryString()` during development.

---

## References

- [EF Core performance best practices](https://learn.microsoft.com/en-us/ef/core/performance/)
- [EF Core compiled models](https://learn.microsoft.com/en-us/ef/core/performance/advanced-performance-topics#compiled-models)
- [Dapper documentation](https://github.com/DapperLib/Dapper)
- [Dapper.AOT](https://aot.dapperlib.dev/)
- [NpgsqlDataSource and dependency injection](https://www.npgsql.org/doc/basic-usage.html#data-source)
- [ADO.NET overview](https://learn.microsoft.com/en-us/dotnet/framework/data/adonet/)
- [Native AOT deployment](https://learn.microsoft.com/en-us/dotnet/core/deploying/native-aot/)
