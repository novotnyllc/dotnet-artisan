# Background Services

Patterns for long-running background work in .NET applications. Covers `BackgroundService`, `IHostedService`, hosted service lifecycle, and graceful shutdown handling.

## BackgroundService vs IHostedService

| Feature | `BackgroundService` | `IHostedService` |
|---------|-------------------|-----------------|
| Purpose | Long-running loop or continuous work | Startup/shutdown hooks |
| Methods | Override `ExecuteAsync` | Implement `StartAsync` + `StopAsync` |
| Lifetime | Runs until cancellation or host shutdown | `StartAsync` runs at startup, `StopAsync` at shutdown |
| Use when | Polling queues, processing streams, periodic jobs | Database migrations, cache warming, resource cleanup |

---

## BackgroundService Patterns

### Basic Polling Worker

```csharp
public sealed class OrderProcessorWorker(
    IServiceScopeFactory scopeFactory,
    ILogger<OrderProcessorWorker> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        logger.LogInformation("Order processor started");

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                using var scope = scopeFactory.CreateScope();
                var processor = scope.ServiceProvider
                    .GetRequiredService<IOrderProcessor>();

                var processed = await processor.ProcessPendingAsync(stoppingToken);

                if (processed == 0)
                {
                    // No work available -- back off to avoid tight polling
                    await Task.Delay(TimeSpan.FromSeconds(5), stoppingToken);
                }
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                // Expected during shutdown -- do not log as error
                break;
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "Error processing orders");
                // Back off on error to prevent tight failure loops
                await Task.Delay(TimeSpan.FromSeconds(30), stoppingToken);
            }
        }

        logger.LogInformation("Order processor stopped");
    }
}

// Registration
builder.Services.AddHostedService<OrderProcessorWorker>();
```

### Critical Rules for BackgroundService

1. **Always create scopes** -- `BackgroundService` is registered as a singleton. Inject `IServiceScopeFactory`, not scoped services directly.
2. **Always handle exceptions** -- by default, unhandled exceptions in `ExecuteAsync` stop the host (configurable via `HostOptions.BackgroundServiceExceptionBehavior`). Wrap the loop body in try/catch.
3. **Always respect the stopping token** -- check `stoppingToken.IsCancellationRequested` and pass the token to all async calls.
4. **Back off on empty/error** -- avoid tight polling loops that waste CPU. Use `Task.Delay` with the stopping token.

---

## IHostedService Patterns

### Startup Hook (Cache Warming, Migrations)

```csharp
public sealed class CacheWarmupService(
    IServiceScopeFactory scopeFactory,
    ILogger<CacheWarmupService> logger) : IHostedService
{
    public async Task StartAsync(CancellationToken cancellationToken)
    {
        logger.LogInformation("Warming caches");

        using var scope = scopeFactory.CreateScope();
        var cache = scope.ServiceProvider.GetRequiredService<IProductCache>();
        await cache.WarmAsync(cancellationToken);

        logger.LogInformation("Cache warmup complete");
    }

    public Task StopAsync(CancellationToken cancellationToken) => Task.CompletedTask;
}
```

### Startup + Shutdown (Resource Lifecycle)

```csharp
public sealed class MessageBusService(
    ILogger<MessageBusService> logger) : IHostedService
{
    private IConnection? _connection;

    public async Task StartAsync(CancellationToken cancellationToken)
    {
        logger.LogInformation("Connecting to message bus");
        _connection = await CreateConnectionAsync(cancellationToken);
    }

    public async Task StopAsync(CancellationToken cancellationToken)
    {
        logger.LogInformation("Disconnecting from message bus");
        if (_connection is not null)
        {
            await _connection.CloseAsync(cancellationToken);
            _connection = null;
        }
    }

    private static Task<IConnection> CreateConnectionAsync(
        CancellationToken ct)
    {
        // Connection setup logic
        throw new NotImplementedException();
    }
}
```

---

## Hosted Service Lifecycle

Understanding the startup and shutdown sequence is critical for correct behavior.

### Startup Sequence

1. `IHostedService.StartAsync` is called for each registered service **in registration order**
2. `BackgroundService.ExecuteAsync` is called after `StartAsync` completes (it runs concurrently -- the host does not wait for it to finish)
3. The host is ready to serve requests after all `StartAsync` calls complete

**Important:** `ExecuteAsync` must not block before yielding to the caller. The first `await` in `ExecuteAsync` is where control returns to the host. If you have synchronous setup before the first `await`, keep it short or move it to `StartAsync` via an override.

```csharp
public sealed class MyWorker : BackgroundService
{
    // StartAsync runs to completion before the host is ready.
    // Override only if you need guaranteed pre-ready initialization.
    public override async Task StartAsync(CancellationToken cancellationToken)
    {
        // Initialization that MUST complete before host accepts requests
        await InitializeAsync(cancellationToken);
        await base.StartAsync(cancellationToken);
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        // This runs concurrently with the host
        while (!stoppingToken.IsCancellationRequested)
        {
            await DoWorkAsync(stoppingToken);
        }
    }

    private Task InitializeAsync(CancellationToken ct) => Task.CompletedTask;
    private Task DoWorkAsync(CancellationToken ct) => Task.CompletedTask;
}
```

### Shutdown Sequence

1. `IHostApplicationLifetime.ApplicationStopping` is triggered
2. The host calls `StopAsync` on each hosted service **in reverse registration order**
3. For `BackgroundService`, the stopping token is cancelled, then `StopAsync` waits for `ExecuteAsync` to complete
4. `IHostApplicationLifetime.ApplicationStopped` is triggered

---

## Channels Integration

See [skill:dotnet-csharp] for comprehensive `Channel<T>` guidance including bounded/unbounded options, `BoundedChannelFullMode`, backpressure strategies, `itemDropped` callbacks, multiple consumers, performance tuning, and drain patterns.

The most common integration is a channel-backed background task queue consumed by a `BackgroundService`:

```csharp
// Channel-backed work queue -- register as singleton
public sealed class BackgroundTaskQueue
{
    private readonly Channel<Func<IServiceProvider, CancellationToken, Task>> _queue
        = Channel.CreateBounded<Func<IServiceProvider, CancellationToken, Task>>(
            new BoundedChannelOptions(100) { FullMode = BoundedChannelFullMode.Wait });

    public ChannelWriter<Func<IServiceProvider, CancellationToken, Task>> Writer => _queue.Writer;
    public ChannelReader<Func<IServiceProvider, CancellationToken, Task>> Reader => _queue.Reader;
}

// Consumer worker
public sealed class QueueProcessorWorker(
    BackgroundTaskQueue queue,
    IServiceScopeFactory scopeFactory,
    ILogger<QueueProcessorWorker> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (await queue.Reader.WaitToReadAsync(stoppingToken))
        {
            while (queue.Reader.TryRead(out var workItem))
            {
                try
                {
                    using var scope = scopeFactory.CreateScope();
                    await workItem(scope.ServiceProvider, stoppingToken);
                }
                catch (Exception ex)
                {
                    logger.LogError(ex, "Error executing queued work item");
                }
            }
        }
    }
}

// Registration
builder.Services.AddSingleton<BackgroundTaskQueue>();
builder.Services.AddHostedService<QueueProcessorWorker>();
```

---

## Graceful Shutdown

### Host Shutdown Timeout

By default, the host waits 30 seconds for services to stop. Configure this for long-running operations:

```csharp
builder.Services.Configure<HostOptions>(options =>
{
    options.ShutdownTimeout = TimeSpan.FromSeconds(60);
});
```

### Responding to Application Lifetime Events

```csharp
public sealed class LifecycleLogger(
    IHostApplicationLifetime lifetime,
    ILogger<LifecycleLogger> logger) : IHostedService
{
    public Task StartAsync(CancellationToken cancellationToken)
    {
        lifetime.ApplicationStarted.Register(() =>
            logger.LogInformation("Application started"));

        lifetime.ApplicationStopping.Register(() =>
            logger.LogInformation("Application stopping -- begin cleanup"));

        lifetime.ApplicationStopped.Register(() =>
            logger.LogInformation("Application stopped -- cleanup complete"));

        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken cancellationToken) => Task.CompletedTask;
}
```

---

## Periodic Work with PeriodicTimer

Use `PeriodicTimer` instead of `Task.Delay` for more accurate periodic execution:

```csharp
public sealed class HealthCheckReporter(
    IServiceScopeFactory scopeFactory,
    ILogger<HealthCheckReporter> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using var timer = new PeriodicTimer(TimeSpan.FromMinutes(1));

        while (await timer.WaitForNextTickAsync(stoppingToken))
        {
            try
            {
                using var scope = scopeFactory.CreateScope();
                var reporter = scope.ServiceProvider
                    .GetRequiredService<IHealthReporter>();
                await reporter.ReportAsync(stoppingToken);
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "Health check report failed");
            }
        }
    }
}
```

---

## Agent Gotchas

1. **Do not inject scoped services into BackgroundService constructors** -- they are singletons. Always use `IServiceScopeFactory`.
2. **Do not use `Task.Run` for background work** -- use `BackgroundService` for proper lifecycle management and graceful shutdown.
3. **Do not swallow `OperationCanceledException`** -- let it propagate or re-check the stopping token. Swallowing it prevents graceful shutdown.
4. **Do not use `Thread.Sleep`** -- use `await Task.Delay(duration, stoppingToken)` or `PeriodicTimer`.
5. **Do not forget to register** -- `AddHostedService<T>()` is required; merely implementing the interface does nothing.

---

## References

- [Background tasks with hosted services](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/host/hosted-services)
- [BackgroundService](https://learn.microsoft.com/en-us/dotnet/api/microsoft.extensions.hosting.backgroundservice)
- [IHostedService interface](https://learn.microsoft.com/en-us/dotnet/api/microsoft.extensions.hosting.ihostedservice)
- [Generic host shutdown](https://learn.microsoft.com/en-us/dotnet/core/extensions/generic-host#host-shutdown)
- [PeriodicTimer](https://learn.microsoft.com/en-us/dotnet/api/system.threading.periodictimer)
