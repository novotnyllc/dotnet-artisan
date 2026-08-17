# Dependency Injection

Advanced Microsoft.Extensions.DependencyInjection patterns for .NET applications. Covers service lifetimes, keyed services (net8.0+), decoration, factory delegates, scope validation, and hosted service registration.

Cross-references: `references/async-patterns.md` for `BackgroundService` async patterns, `references/configuration.md` for `IOptions<T>` binding.

---

## Service Lifetimes

| Lifetime | Registration | When to Use |
|----------|-------------|-------------|
| Transient | `AddTransient<T>()` | Lightweight, stateless services. New instance per injection. |
| Scoped | `AddScoped<T>()` | Per-request state (EF Core `DbContext`, unit of work). |
| Singleton | `AddSingleton<T>()` | Thread-safe, stateless, or shared state (caches, config). |

### Lifetime Mismatches (Captive Dependencies)

Never inject a shorter-lived service into a longer-lived one:

```csharp
// WRONG -- scoped DbContext captured in singleton = same context for all requests
builder.Services.AddSingleton<OrderService>();    // singleton
builder.Services.AddScoped<AppDbContext>();        // scoped -- CAPTIVE!

// CORRECT -- use IServiceScopeFactory in singletons
public sealed class OrderService(IServiceScopeFactory scopeFactory)
{
    public async Task ProcessAsync(CancellationToken ct = default)
    {
        using var scope = scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        await db.Orders.Where(o => o.IsPending).ToListAsync(ct);
    }
}
```

### Enable Scope Validation (Development)

```csharp
var builder = WebApplication.CreateBuilder(args);
// In Development, ValidateScopes is already true by default.
// For non-web hosts:
var host = Host.CreateDefaultBuilder(args)
    .UseDefaultServiceProvider(options =>
    {
        options.ValidateScopes = true;
        options.ValidateOnBuild = true;  // Validates all registrations at startup
    })
    .Build();
```

---

## Registration Patterns

### Interface-Implementation Pair

```csharp
builder.Services.AddScoped<IOrderRepository, SqlOrderRepository>();
```

### Multiple Implementations

```csharp
// Register multiple implementations
builder.Services.AddScoped<INotifier, EmailNotifier>();
builder.Services.AddScoped<INotifier, SmsNotifier>();
builder.Services.AddScoped<INotifier, PushNotifier>();

// Inject all -- order matches registration order
public sealed class CompositeNotifier(IEnumerable<INotifier> notifiers)
{
    public async Task NotifyAsync(string message, CancellationToken ct = default)
    {
        foreach (var notifier in notifiers)
        {
            await notifier.NotifyAsync(message, ct);
        }
    }
}
```

### Factory Delegates

```csharp
builder.Services.AddScoped<IOrderService>(sp =>
{
    var repo = sp.GetRequiredService<IOrderRepository>();
    var logger = sp.GetRequiredService<ILogger<OrderService>>();
    var options = sp.GetRequiredService<IOptions<OrderOptions>>();
    return new OrderService(repo, logger, options.Value.MaxRetries);
});
```

### `TryAdd` for Library Registrations

Libraries should use `TryAdd` so applications can override:

```csharp
// Library code -- won't overwrite app registrations
builder.Services.TryAddScoped<IOrderRepository, DefaultOrderRepository>();

// Application code -- takes precedence if registered first
builder.Services.AddScoped<IOrderRepository, CustomOrderRepository>();
```

---

## Keyed Services (net8.0+)

Register and resolve services by a key, replacing the need for named service patterns.

```csharp
// Registration
builder.Services.AddKeyedScoped<ICache, RedisCache>("distributed");
builder.Services.AddKeyedScoped<ICache, MemoryCache>("local");

// Injection via attribute
public sealed class OrderService(
    [FromKeyedServices("distributed")] ICache distributedCache,
    [FromKeyedServices("local")] ICache localCache)
{
    public async Task<Order?> GetAsync(int id, CancellationToken ct = default)
    {
        // Check local cache first, then distributed
        return await localCache.GetAsync<Order>(id.ToString(), ct)
            ?? await distributedCache.GetAsync<Order>(id.ToString(), ct);
    }
}

// Manual resolution
var cache = sp.GetRequiredKeyedService<ICache>("distributed");
```

> **net8.0+ only.** On earlier TFMs, use factory patterns or a dictionary-based approach.

---

## Decoration Pattern

The built-in container does not natively support decoration. Use one of these approaches:

### Manual Decoration

```csharp
builder.Services.AddScoped<SqlOrderRepository>();
builder.Services.AddScoped<IOrderRepository>(sp =>
{
    var inner = sp.GetRequiredService<SqlOrderRepository>();
    var logger = sp.GetRequiredService<ILogger<LoggingOrderRepository>>();
    return new LoggingOrderRepository(inner, logger);
});

public sealed class LoggingOrderRepository(
    IOrderRepository inner,
    ILogger<LoggingOrderRepository> logger) : IOrderRepository
{
    public async Task<Order?> GetByIdAsync(int id, CancellationToken ct = default)
    {
        logger.LogInformation("Getting order {OrderId}", id);
        return await inner.GetByIdAsync(id, ct);
    }
}
```

### Scrutor Library (Popular Alternative)

```csharp
builder.Services.AddScoped<IOrderRepository, SqlOrderRepository>();
builder.Services.Decorate<IOrderRepository, LoggingOrderRepository>();
builder.Services.Decorate<IOrderRepository, CachingOrderRepository>();
// Outer -> CachingOrderRepository -> LoggingOrderRepository -> SqlOrderRepository
```

---

## Hosted Services and Background Workers

### `BackgroundService` (Preferred)

```csharp
public sealed class QueueProcessorWorker(
    IServiceScopeFactory scopeFactory,
    ILogger<QueueProcessorWorker> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        logger.LogInformation("Queue processor starting");

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                using var scope = scopeFactory.CreateScope();
                var processor = scope.ServiceProvider
                    .GetRequiredService<IQueueProcessor>();

                await processor.ProcessNextBatchAsync(stoppingToken);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                logger.LogError(ex, "Error processing queue batch");
            }

            await Task.Delay(TimeSpan.FromSeconds(5), stoppingToken);
        }
    }
}

// Registration
builder.Services.AddHostedService<QueueProcessorWorker>();
```

### `IHostedService` (Startup/Shutdown Hooks)

```csharp
public sealed class DatabaseMigrationService(
    IServiceScopeFactory scopeFactory,
    ILogger<DatabaseMigrationService> logger) : IHostedService
{
    public async Task StartAsync(CancellationToken cancellationToken)
    {
        using var scope = scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        await db.Database.MigrateAsync(cancellationToken);
        logger.LogInformation("Database migration completed");
    }

    public Task StopAsync(CancellationToken cancellationToken) => Task.CompletedTask;
}

builder.Services.AddHostedService<DatabaseMigrationService>();
```

### Key Rules for Hosted Services

- Always use `IServiceScopeFactory` to create scopes -- hosted services are singletons
- Never inject scoped services directly into hosted service constructors
- Handle exceptions inside `ExecuteAsync` -- unhandled exceptions stop the host (net8.0+)
- See `references/async-patterns.md` for async patterns in background workers

---

## Organizing Registrations

Group related registrations into extension methods for clean `Program.cs`:

```csharp
// ServiceCollectionExtensions.cs
public static class ServiceCollectionExtensions
{
    public static IServiceCollection AddOrderServices(this IServiceCollection services)
    {
        services.AddScoped<IOrderRepository, SqlOrderRepository>();
        services.AddScoped<IOrderService, OrderService>();
        services.AddHostedService<OrderProcessorWorker>();
        return services;
    }

    public static IServiceCollection AddNotificationServices(this IServiceCollection services)
    {
        services.AddScoped<INotifier, EmailNotifier>();
        services.AddScoped<INotifier, SmsNotifier>();
        return services;
    }
}

// Program.cs
builder.Services.AddOrderServices();
builder.Services.AddNotificationServices();
```

---

## Testing with DI

```csharp
[Fact]
public async Task OrderService_UsesRepository()
{
    // Arrange -- build a service provider for integration tests
    var services = new ServiceCollection();
    services.AddScoped<IOrderRepository, InMemoryOrderRepository>();
    services.AddScoped<IOrderService, OrderService>();
    services.AddLogging();

    using var provider = services.BuildServiceProvider();
    using var scope = provider.CreateScope();
    var service = scope.ServiceProvider.GetRequiredService<IOrderService>();

    // Act
    var order = await service.GetByIdAsync(1);

    // Assert
    Assert.NotNull(order);
}
```

For unit tests, prefer direct constructor injection with mocks rather than building a full container.

---

## References

- [Dependency injection in .NET](https://learn.microsoft.com/en-us/dotnet/core/extensions/dependency-injection)
- [Keyed services in .NET 8](https://learn.microsoft.com/en-us/dotnet/core/extensions/dependency-injection#keyed-services)
- [Background tasks with hosted services](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/host/hosted-services)
- [Service lifetimes](https://learn.microsoft.com/en-us/dotnet/core/extensions/dependency-injection#service-lifetimes)
- [.NET Framework Design Guidelines](https://learn.microsoft.com/en-us/dotnet/standard/design-guidelines/)
