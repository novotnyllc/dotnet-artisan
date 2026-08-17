# Async Patterns

Async/await best practices for .NET applications. Covers correct task usage, cancellation propagation, and the most common mistakes AI agents make when generating async code.

Cross-references: `references/concurrency-patterns.md` for thread synchronization primitives (lock, SemaphoreSlim), `references/channels.md` for Channel<T> producer/consumer patterns, `references/dependency-injection.md` for `IHostedService`/`BackgroundService` registration, `references/coding-standards.md` for `Async` suffix naming, `references/modern-patterns.md` for language-level features.

---

## Core Rules

### Always Async All the Way

Every method in the async call chain must be `async` and `await`ed. Mixing sync and async causes deadlocks or thread pool starvation.

```csharp
// Correct: async all the way
public async Task<Order> GetOrderAsync(int id, CancellationToken ct = default)
{
    var order = await _repo.GetByIdAsync(id, ct);
    return order;
}

// WRONG: blocking on async -- causes deadlocks in ASP.NET and UI contexts
public Order GetOrder(int id)
{
    return _repo.GetByIdAsync(id).Result; // DEADLOCK RISK
}
```

### Prefer `Task` and `ValueTask`

Return `Task` or `Task<T>` by default. Use `ValueTask<T>` when the method frequently completes synchronously (cache hits, buffered I/O) to avoid `Task` allocation.

```csharp
// ValueTask: frequently synchronous completion
public ValueTask<User?> GetCachedUserAsync(int id, CancellationToken ct = default)
{
    if (_cache.TryGetValue(id, out var user))
    {
        return ValueTask.FromResult<User?>(user);
    }

    return LoadUserAsync(id, ct);
}

private async ValueTask<User?> LoadUserAsync(int id, CancellationToken ct)
{
    var user = await _repo.GetByIdAsync(id, ct);
    if (user is not null)
    {
        _cache[id] = user;
    }

    return user;
}
```

**ValueTask rules:**
- Never `await` a `ValueTask` more than once
- Never use `.Result` or `.GetAwaiter().GetResult()` on an incomplete `ValueTask`
- If you need to await multiple times or pass it around, convert with `.AsTask()`

---

## Agent Gotchas

These are the most common async mistakes AI agents make when generating C# code.

### 1. Blocking on Async (`.Result`, `.Wait()`, `.GetAwaiter().GetResult()`)

```csharp
// WRONG -- all of these can deadlock
var result = GetDataAsync().Result;
GetDataAsync().Wait();
var result = GetDataAsync().GetAwaiter().GetResult();

// CORRECT
var result = await GetDataAsync();
```

The only safe place for `.GetAwaiter().GetResult()` is in `Main()` pre-C# 7.1 or in rare infrastructure code where async is impossible (static constructors, `Dispose()`).

### 2. `async void`

`async void` methods cannot be awaited, and unhandled exceptions in them crash the process.

```csharp
// WRONG -- fire-and-forget, unobserved exceptions
async void ProcessOrder(Order order)
{
    await _repo.SaveAsync(order);
}

// CORRECT
async Task ProcessOrderAsync(Order order)
{
    await _repo.SaveAsync(order);
}
```

The **only** valid use of `async void` is event handlers (WinForms, WPF, Blazor `@onclick`), where the framework requires a `void` return type.

### 3. Missing `ConfigureAwait`

In **library code**, use `ConfigureAwait(false)` to avoid capturing the synchronization context. In **application code** (ASP.NET Core, console apps), it is not needed because there is no synchronization context.

```csharp
// Library code
public async Task<byte[]> ReadFileAsync(string path, CancellationToken ct = default)
{
    var bytes = await File.ReadAllBytesAsync(path, ct).ConfigureAwait(false);
    return bytes;
}

// Application code (ASP.NET Core) -- ConfigureAwait not needed
public async Task<IActionResult> GetOrder(int id, CancellationToken ct)
{
    var order = await _service.GetOrderAsync(id, ct);
    return Ok(order);
}
```

### 4. Fire-and-Forget Without Error Handling

```csharp
// WRONG -- exception is silently swallowed
_ = SendEmailAsync(order);

// CORRECT -- use IHostedService or a background channel
await _backgroundQueue.EnqueueAsync(ct => SendEmailAsync(order, ct));
```

If fire-and-forget is truly necessary, at minimum log the exception:

```csharp
_ = Task.Run(async () =>
{
    try
    {
        await SendEmailAsync(order);
    }
    catch (Exception ex)
    {
        _logger.LogError(ex, "Failed to send email for order {OrderId}", order.Id);
    }
});
```

### 5. Forgetting `CancellationToken`

Always accept and forward `CancellationToken`. Never silently drop it.

```csharp
// WRONG -- token not forwarded
public async Task<List<Order>> GetAllAsync(CancellationToken ct = default)
{
    return await _dbContext.Orders.ToListAsync(); // missing ct!
}

// CORRECT
public async Task<List<Order>> GetAllAsync(CancellationToken ct = default)
{
    return await _dbContext.Orders.ToListAsync(ct);
}
```

---

## Cancellation Patterns

### Creating Linked Tokens

Combine external cancellation with a timeout:

```csharp
public async Task<Result> ProcessWithTimeoutAsync(CancellationToken ct = default)
{
    using var cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
    cts.CancelAfter(TimeSpan.FromSeconds(30));

    return await DoWorkAsync(cts.Token);
}
```

### Responding to Cancellation

```csharp
public async Task ProcessBatchAsync(IEnumerable<Item> items, CancellationToken ct = default)
{
    foreach (var item in items)
    {
        ct.ThrowIfCancellationRequested();
        await ProcessItemAsync(item, ct);
    }
}
```

---

## Parallel Async

### `Task.WhenAll` for Independent Operations

```csharp
public async Task<Dashboard> LoadDashboardAsync(int userId, CancellationToken ct = default)
{
    var ordersTask = _orderService.GetRecentAsync(userId, ct);
    var profileTask = _profileService.GetAsync(userId, ct);
    var statsTask = _statsService.GetAsync(userId, ct);

    await Task.WhenAll(ordersTask, profileTask, statsTask);

    return new Dashboard(await ordersTask, await profileTask, await statsTask);
}
```

### `Parallel.ForEachAsync` (.NET 6+) for Bounded Parallelism

```csharp
await Parallel.ForEachAsync(items, new ParallelOptions
{
    MaxDegreeOfParallelism = 4,
    CancellationToken = ct
}, async (item, token) =>
{
    await ProcessItemAsync(item, token);
});
```

---

## `IAsyncEnumerable<T>` Streaming

Use `IAsyncEnumerable<T>` for streaming results instead of buffering entire collections:

```csharp
public async IAsyncEnumerable<Order> GetOrdersStreamAsync(
    [EnumeratorCancellation] CancellationToken ct = default)
{
    await foreach (var order in _dbContext.Orders.AsAsyncEnumerable().WithCancellation(ct))
    {
        yield return order;
    }
}
```

---

## Background Work

For background processing, use `BackgroundService` (or `IHostedService`) instead of `Task.Run` or fire-and-forget patterns. See `references/dependency-injection.md` for registration patterns.

```csharp
public sealed class OrderProcessorWorker(
    IServiceScopeFactory scopeFactory,
    ILogger<OrderProcessorWorker> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            using var scope = scopeFactory.CreateScope();
            var processor = scope.ServiceProvider.GetRequiredService<IOrderProcessor>();

            await processor.ProcessPendingAsync(stoppingToken);
            await Task.Delay(TimeSpan.FromSeconds(30), stoppingToken);
        }
    }
}
```

---

## Testing Async Code

```csharp
[Fact]
public async Task GetOrderAsync_WhenFound_ReturnsOrder()
{
    // Arrange
    var repo = Substitute.For<IOrderRepository>();
    repo.GetByIdAsync(42, Arg.Any<CancellationToken>())
        .Returns(new Order { Id = 42 });
    var service = new OrderService(repo);

    // Act
    var result = await service.GetOrderAsync(42);

    // Assert
    Assert.NotNull(result);
    Assert.Equal(42, result.Id);
}

[Fact]
public async Task ProcessAsync_WhenCancelled_ThrowsOperationCanceled()
{
    using var cts = new CancellationTokenSource();
    cts.Cancel();

    await Assert.ThrowsAsync<OperationCanceledException>(
        () => _service.ProcessAsync(cts.Token));
}
```

---

## Knowledge Sources

Async patterns in this reference are grounded in publicly available content from:

- **Stephen Cleary's "Concurrency in C#" and Blog** -- Definitive async best practices for .NET. Key guidance applied: "async all the way" (never block on async), "there is no thread" (async I/O does not consume a thread while waiting), correct CancellationToken propagation, async disposal via IAsyncDisposable, and BackgroundService patterns for long-running work. Source: https://blog.stephencleary.com/
- **David Fowler's Async Guidance** -- Practical async anti-patterns and diagnostic scenarios for ASP.NET Core. Source: https://github.com/davidfowl/AspNetCoreDiagnosticScenarios/blob/master/AsyncGuidance.md
- **Stephen Toub's ConfigureAwait FAQ** -- Canonical reference for ConfigureAwait behavior across application types. Source: https://devblogs.microsoft.com/dotnet/configureawait-faq/

> **Note:** This reference applies publicly documented guidance. It does not represent or speak for the named sources.

## References

- [Async/await best practices (David Fowler)](https://github.com/davidfowl/AspNetCoreDiagnosticScenarios/blob/master/AsyncGuidance.md)
- [Stephen Cleary's Async Blog](https://blog.stephencleary.com/)
- [Asynchronous programming patterns](https://learn.microsoft.com/en-us/dotnet/csharp/asynchronous-programming/)
- [Task-based asynchronous pattern (TAP)](https://learn.microsoft.com/en-us/dotnet/standard/asynchronous-programming-patterns/task-based-asynchronous-pattern-tap)
- [ConfigureAwait FAQ](https://devblogs.microsoft.com/dotnet/configureawait-faq/)
- [Framework Design Guidelines](https://learn.microsoft.com/en-us/dotnet/standard/design-guidelines/)
