# Channels

Deep guide to `System.Threading.Channels` for high-performance, thread-safe producer/consumer communication in .NET. Covers channel creation, backpressure strategies, IAsyncEnumerable integration, and graceful shutdown patterns.

Cross-references: `references/async-patterns.md` for async patterns used in channel consumers, `references/dependency-injection.md` for integrating channels with hosted services.

---

## Channel<T> Fundamentals

A `Channel<T>` is a thread-safe data structure with separate `ChannelWriter<T>` and `ChannelReader<T>` endpoints. Writers produce items, readers consume them -- the channel handles all synchronization.

```csharp
// Create a channel and separate the endpoints
Channel<WorkItem> channel = Channel.CreateUnbounded<WorkItem>();
ChannelWriter<WorkItem> writer = channel.Writer;
ChannelReader<WorkItem> reader = channel.Reader;
```

### Bounded vs Unbounded

| Aspect | Bounded | Unbounded |
|--------|---------|-----------|
| Creation | `Channel.CreateBounded<T>(capacity)` | `Channel.CreateUnbounded<T>()` |
| Back-pressure | Yes -- `FullMode` controls behavior when full | No -- grows without limit |
| Memory safety | Capped at `capacity` items | Can exhaust memory under load |
| Use when | Production workloads, untrusted producer rates | Guaranteed-low-volume, prototyping |

```csharp
// Bounded -- preferred for production
var bounded = Channel.CreateBounded<WorkItem>(new BoundedChannelOptions(capacity: 1000)
{
    FullMode = BoundedChannelFullMode.Wait
});

// Unbounded -- use only when you control the producer rate
var unbounded = Channel.CreateUnbounded<WorkItem>();
```

---

## BoundedChannelFullMode

Controls what happens when a bounded channel is full and a producer attempts to write.

| Mode | Behavior | Use case |
|------|----------|----------|
| `Wait` | `WriteAsync` blocks until space is available | Default. Reliable delivery with back-pressure |
| `DropOldest` | Drops the oldest item in the channel to make room | Telemetry, metrics -- latest data matters most |
| `DropNewest` | Drops the newest buffered item to make room (accepts the write) | Sliding window -- keep oldest + newest, discard middle |
| `DropWrite` | Rejects the incoming write and `TryWrite` returns `false` | Rate limiting -- discard excess incoming work with overflow detection |

```csharp
// DropOldest -- telemetry pipeline where stale readings are expendable
var telemetryChannel = Channel.CreateBounded<SensorReading>(new BoundedChannelOptions(500)
{
    FullMode = BoundedChannelFullMode.DropOldest
});

// DropWrite -- non-blocking enqueue with overflow awareness
var logChannel = Channel.CreateBounded<LogEntry>(new BoundedChannelOptions(10_000)
{
    FullMode = BoundedChannelFullMode.DropWrite
});

if (!logChannel.Writer.TryWrite(entry))
{
    // Channel full -- item was dropped; track overflow metric
    overflowCounter.Add(1);
}
```

### Drop Detection with `DropWrite` + `TryWrite`

Use `DropWrite` mode to detect when the channel rejects a new item because it is full. `TryWrite` returns `false` when the item is dropped:

```csharp
var channel = Channel.CreateBounded<WorkItem>(new BoundedChannelOptions(100)
{
    FullMode = BoundedChannelFullMode.DropWrite
});

if (!channel.Writer.TryWrite(item))
{
    logger.LogWarning("Channel full, item dropped: {Id}", item.Id);
    droppedItemsCounter.Add(1);
}
```

**Note:** With `DropOldest` or `DropNewest`, the channel silently evicts an existing item and accepts the write, so `TryWrite` returns `true` even when a drop occurs. Producer-side drop detection is only reliable with `DropWrite`.

---

## Producer Patterns

### Single Producer

```csharp
// Write with back-pressure (bounded channels)
await writer.WriteAsync(item, cancellationToken);

// Non-blocking write attempt (returns false if channel is full or completed)
if (!writer.TryWrite(item))
{
    // Handle overflow -- log, retry, or discard
}
```

### Multiple Producers

Multiple producers can call `WriteAsync` or `TryWrite` concurrently without external locking. The channel is internally thread-safe.

```csharp
// Multiple API endpoints enqueueing work into a shared channel
app.MapPost("/api/orders/{id}/process", async (
    string id,
    ChannelWriter<OrderCommand> writer,
    CancellationToken ct) =>
{
    await writer.WriteAsync(new OrderCommand(id, "process"), ct);
    return Results.Accepted();
});

app.MapPost("/api/orders/{id}/cancel", async (
    string id,
    ChannelWriter<OrderCommand> writer,
    CancellationToken ct) =>
{
    await writer.WriteAsync(new OrderCommand(id, "cancel"), ct);
    return Results.Accepted();
});
```

### Signaling Completion

Call `Complete()` or `TryComplete()` when no more items will be produced. This lets consumers detect the end of the stream.

```csharp
// Signal completion -- no more items will be written
writer.Complete();

// TryComplete is idempotent -- safe to call multiple times
writer.TryComplete();

// Signal completion with an error
writer.TryComplete(new InvalidOperationException("Source failed"));
```

---

## Consumer Patterns

### Single Consumer -- ReadAsync Loop

The classic pattern: wait for an item, process it, repeat.

```csharp
while (await reader.WaitToReadAsync(cancellationToken))
{
    while (reader.TryRead(out var item))
    {
        await ProcessAsync(item, cancellationToken);
    }
}
```

This two-loop pattern is preferred over `ReadAsync` alone because it drains all available items before awaiting again, reducing async state machine overhead.

### Single Consumer -- ReadAsync (Simpler)

For simpler cases where per-item overhead is acceptable:

```csharp
try
{
    while (true)
    {
        var item = await reader.ReadAsync(cancellationToken);
        await ProcessAsync(item, cancellationToken);
    }
}
catch (ChannelClosedException)
{
    // Writer called Complete() -- no more items
}
```

### Multiple Consumers (Fan-Out)

Scale processing by running multiple consumer tasks. The channel ensures each item is read by exactly one consumer.

```csharp
public sealed class ScaledChannelProcessor(
    ChannelReader<WorkItem> reader,
    IServiceScopeFactory scopeFactory,
    ILogger<ScaledChannelProcessor> logger) : BackgroundService
{
    private const int WorkerCount = 3;

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var workers = Enumerable.Range(0, WorkerCount)
            .Select(i => ConsumeAsync(i, stoppingToken));

        await Task.WhenAll(workers);
    }

    private async Task ConsumeAsync(int workerId, CancellationToken ct)
    {
        logger.LogDebug("Consumer {WorkerId} started", workerId);

        while (await reader.WaitToReadAsync(ct))
        {
            while (reader.TryRead(out var item))
            {
                try
                {
                    using var scope = scopeFactory.CreateScope();
                    var handler = scope.ServiceProvider
                        .GetRequiredService<IWorkItemHandler>();
                    await handler.HandleAsync(item, ct);
                }
                catch (Exception ex)
                {
                    logger.LogError(ex,
                        "Consumer {WorkerId}: error processing {ItemId}",
                        workerId, item.Id);
                }
            }
        }

        logger.LogDebug("Consumer {WorkerId} stopped", workerId);
    }
}
```

---

## IAsyncEnumerable Integration

`ChannelReader<T>.ReadAllAsync()` returns an `IAsyncEnumerable<T>`, enabling `await foreach` consumption and integration with LINQ async operators.

### Basic await foreach

```csharp
await foreach (var item in reader.ReadAllAsync(cancellationToken))
{
    await ProcessAsync(item, cancellationToken);
}
// Loop exits when writer calls Complete() and all items are consumed
```

`ReadAllAsync` is the simplest consumption pattern. It handles `WaitToReadAsync`/`TryRead` internally and completes when the channel is closed.

### Streaming from an API Endpoint

Channels combine naturally with ASP.NET Core streaming responses. Return the `IAsyncEnumerable<T>` directly -- minimal APIs will stream items as JSON array elements:

```csharp
app.MapGet("/api/events/stream", (
    ChannelReader<ServerEvent> reader,
    CancellationToken ct) => reader.ReadAllAsync(ct));
```

### LINQ Async Operators

With the `System.Linq.Async` NuGet package, channel streams compose with familiar LINQ operators:

```csharp
// NuGet: System.Linq.Async
await foreach (var batch in reader.ReadAllAsync(ct)
    .Where(item => item.Priority >= Priority.High)
    .Buffer(50)  // Collect into batches of 50
    .WithCancellation(ct))
{
    await BulkProcessAsync(batch, ct);
}
```

### Producing an IAsyncEnumerable from a Channel

```csharp
async IAsyncEnumerable<PriceUpdate> StreamPricesAsync(
    string symbol,
    [EnumeratorCancellation] CancellationToken ct = default)
{
    var channel = Channel.CreateUnbounded<PriceUpdate>();

    // Start producer in background
    _ = Task.Run(async () =>
    {
        try
        {
            await foreach (var tick in marketFeed.SubscribeAsync(symbol, ct))
            {
                await channel.Writer.WriteAsync(tick, ct);
            }
            channel.Writer.TryComplete();
        }
        catch (Exception ex)
        {
            // Propagate error to reader -- ReadAllAsync will throw
            channel.Writer.TryComplete(ex);
        }
    }, ct);

    await foreach (var update in channel.Reader.ReadAllAsync(ct))
    {
        yield return update;
    }
}
```

---

## Performance

### SingleReader / SingleWriter Flags

Setting `SingleReader = true` or `SingleWriter = true` on channel options enables lock-free optimizations. The channel trusts these hints -- violating them (multiple concurrent readers when `SingleReader = true`) causes data corruption.

```csharp
// Optimal for single-producer, single-consumer pipeline
var channel = Channel.CreateBounded<T>(new BoundedChannelOptions(1000)
{
    SingleReader = true,   // One consumer task
    SingleWriter = true,   // One producer task
    FullMode = BoundedChannelFullMode.Wait
});
```

### WaitToReadAsync + TryRead Pattern

The most efficient consumer pattern. `WaitToReadAsync` suspends until data is available, then `TryRead` drains all buffered items synchronously -- avoiding per-item async state machine overhead.

```csharp
while (await reader.WaitToReadAsync(ct))
{
    // Drain all currently buffered items synchronously
    while (reader.TryRead(out var item))
    {
        Process(item);
    }
}
```

### TryWrite Fast Path

`TryWrite` is synchronous and allocation-free when the channel has space. Prefer it over `WriteAsync` in hot paths where you can handle the `false` return.

```csharp
// Hot path -- avoid async overhead when channel has space
if (!writer.TryWrite(item))
{
    // Slow path -- wait for space (or handle overflow)
    await writer.WriteAsync(item, ct);
}
```

### Bounded Channel Memory Behavior

Bounded channels pre-allocate an internal array of `capacity` slots. Items are stored by reference (for reference types), so the channel holds references until consumed. For memory-sensitive workloads:

- Choose capacity based on expected item size multiplied by count
- Items are eligible for GC as soon as `TryRead`/`ReadAsync` returns them
- Drop modes (`DropOldest`, `DropNewest`) keep memory stable but lose data

---

## Cancellation and Graceful Shutdown

### Basic Cancellation

Pass a `CancellationToken` to all async channel operations. When cancelled, operations throw `OperationCanceledException`.

```csharp
try
{
    await foreach (var item in reader.ReadAllAsync(stoppingToken))
    {
        await ProcessAsync(item, stoppingToken);
    }
}
catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
{
    // Expected during shutdown
}
```

### Drain Pattern

Complete the writer to signal no more items will arrive, then drain remaining items before stopping. This prevents data loss during shutdown.

```csharp
public sealed class DrainableProcessor(
    Channel<WorkItem> channel,
    IServiceScopeFactory scopeFactory,
    ILogger<DrainableProcessor> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var reader = channel.Reader;

        try
        {
            while (await reader.WaitToReadAsync(stoppingToken))
            {
                while (reader.TryRead(out var item))
                {
                    using var scope = scopeFactory.CreateScope();
                    var handler = scope.ServiceProvider
                        .GetRequiredService<IWorkItemHandler>();
                    await handler.HandleAsync(item, stoppingToken);
                }
            }
        }
        catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
        {
            // Shutdown requested -- fall through to drain
        }

        // Signal producers to stop -- any concurrent WriteAsync will throw ChannelClosedException
        channel.Writer.TryComplete();

        // Drain remaining items with a deadline
        logger.LogInformation("Draining remaining work items");
        using var drainCts = new CancellationTokenSource(TimeSpan.FromSeconds(25));

        while (reader.TryRead(out var remaining))
        {
            try
            {
                using var scope = scopeFactory.CreateScope();
                var handler = scope.ServiceProvider
                    .GetRequiredService<IWorkItemHandler>();
                await handler.HandleAsync(remaining, drainCts.Token);
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "Error during drain");
            }
        }

        logger.LogInformation("Drain complete");
    }
}
```

### Host Shutdown Timeout

The default host shutdown timeout is 30 seconds. If your drain needs more time, configure it:

```csharp
builder.Services.Configure<HostOptions>(options =>
{
    options.ShutdownTimeout = TimeSpan.FromSeconds(60);
});
```

---

## Agent Gotchas

1. **Do not use unbounded channels in production without rate control** -- they can exhaust memory under sustained producer pressure. Always prefer bounded channels with explicit capacity.
2. **Do not violate SingleReader/SingleWriter promises** -- these flags enable lock-free optimizations. Multiple concurrent readers with `SingleReader = true` causes data corruption, not exceptions.
3. **Do not forget to call `Complete()` on the writer** -- without completion, consumers using `ReadAllAsync()` or `WaitToReadAsync` will wait indefinitely after the last item.
4. **Do not catch `ChannelClosedException` globally** -- it signals that the writer called `Complete()`, possibly with an error. Catch it only around `ReadAsync` calls; `WaitToReadAsync`/`TryRead` loops handle completion via `false` return.
5. **Do not use `ReadAsync` in hot paths** -- prefer the `WaitToReadAsync` + `TryRead` pattern to drain buffered items synchronously and reduce async state machine allocations.
6. **Do not block in `TryWrite == false` overflow handling** -- keep overflow accounting cheap (increment counter, log). Offload heavy work to avoid stalling the producer thread.

---

## References

- [System.Threading.Channels overview](https://learn.microsoft.com/en-us/dotnet/core/extensions/channels)
- [Channel<T> API reference](https://learn.microsoft.com/en-us/dotnet/api/system.threading.channels.channel-1)
- [BoundedChannelOptions](https://learn.microsoft.com/en-us/dotnet/api/system.threading.channels.boundedchanneloptions)
- [ChannelReader.ReadAllAsync](https://learn.microsoft.com/en-us/dotnet/api/system.threading.channels.channelreader-1.readallasync)
