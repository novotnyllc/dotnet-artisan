# Messaging Patterns

Durable messaging patterns for .NET event-driven architectures. Covers publish/subscribe, competing consumers, dead-letter queues, saga/process manager orchestration, and delivery guarantee strategies using Azure Service Bus, RabbitMQ, and Wolverine.

**Library guidance:** Use **Wolverine** (MIT) as the recommended messaging abstraction for new projects. It supports RabbitMQ, Azure Service Bus, Amazon SQS, and in-memory transport with a clean API. **Rebus** (MIT) is a lighter alternative.

## Messaging Fundamentals

### Message Types

| Type | Purpose | Example |
|------|---------|---------|
| **Command** | Request an action (one recipient) | `PlaceOrder`, `ShipPackage` |
| **Event** | Notify something happened (many recipients) | `OrderPlaced`, `PaymentReceived` |
| **Document** | Transfer data between systems | `CustomerProfile`, `ProductCatalog` |

Commands are sent to a specific queue; events are published to a topic/exchange and delivered to all subscribers. This distinction drives the choice between point-to-point and pub/sub topologies.

### Delivery Guarantees

| Guarantee | Behavior | Implementation |
|-----------|----------|----------------|
| **At-most-once** | Fire and forget; message may be lost | No ack, no retry |
| **At-least-once** | Message retried until acknowledged; duplicates possible | Ack after processing + retry on failure |
| **Exactly-once** | Each message processed exactly once | At-least-once + idempotent consumer |

**At-least-once with idempotent consumers** is the standard approach for durable messaging. True exactly-once requires distributed transactions (which most brokers do not support) or consumer-side deduplication.

---

## Publish/Subscribe

### Azure Service Bus Topics

```csharp
// Publisher -- send event to a topic
await using var client = new ServiceBusClient(connectionString);
await using var sender = client.CreateSender("order-events");

var message = new ServiceBusMessage(
    JsonSerializer.SerializeToUtf8Bytes(new OrderPlaced(orderId, total)))
{
    Subject = nameof(OrderPlaced),
    ContentType = "application/json",
    MessageId = Guid.NewGuid().ToString()
};

await sender.SendMessageAsync(message, cancellationToken);
```

```csharp
// Subscriber -- process events from a subscription
await using var processor = client.CreateProcessor(
    topicName: "order-events",
    subscriptionName: "billing-service",
    new ServiceBusProcessorOptions
    {
        MaxConcurrentCalls = 10,
        AutoCompleteMessages = false
    });

processor.ProcessMessageAsync += async args =>
{
    var body = args.Message.Body.ToObjectFromJson<OrderPlaced>();
    await HandleOrderPlacedAsync(body);
    await args.CompleteMessageAsync(args.Message);
};

processor.ProcessErrorAsync += args =>
{
    logger.LogError(args.Exception, "Error processing message");
    return Task.CompletedTask;
};

await processor.StartProcessingAsync(cancellationToken);
```

**Key packages:**

```xml
<PackageReference Include="Azure.Messaging.ServiceBus" Version="7.*" />
```

### RabbitMQ Fanout Exchange

```csharp
// Publisher -- declare exchange and publish
var factory = new ConnectionFactory { HostName = "localhost" };
await using var connection = await factory.CreateConnectionAsync();
await using var channel = await connection.CreateChannelAsync();

await channel.ExchangeDeclareAsync(
    exchange: "order-events",
    type: ExchangeType.Fanout,
    durable: true);

var body = JsonSerializer.SerializeToUtf8Bytes(
    new OrderPlaced(orderId, total));

await channel.BasicPublishAsync(
    exchange: "order-events",
    routingKey: string.Empty,
    body: body);
```

**Key packages:**

```xml
<PackageReference Include="RabbitMQ.Client" Version="7.*" />
```

### Wolverine Publish (Recommended Abstraction)

Wolverine abstracts the broker, providing a unified API for Azure Service Bus, RabbitMQ, Amazon SQS, and in-memory transport. MIT licensed.

```csharp
// Registration
builder.Host.UseWolverine(opts =>
{
    opts.UseRabbitMq(rabbit =>
    {
        rabbit.HostName = "localhost";
    }).AutoProvision();

    opts.PublishMessage<OrderPlaced>()
        .ToRabbitExchange("order-events");

    opts.ListenToRabbitQueue("order-processing");
});

// Publisher — inject IMessageBus
public sealed class OrderService(IMessageBus bus)
{
    public async Task PlaceOrderAsync(
        Guid orderId, decimal total, CancellationToken ct)
    {
        // Process order...
        await bus.PublishAsync(new OrderPlaced(orderId, total));
    }
}

// Handler — Wolverine discovers handlers by convention (no interface needed)
public static class OrderPlacedHandler
{
    public static async Task HandleAsync(
        OrderPlaced message, ILogger<OrderPlacedHandler> logger)
    {
        logger.LogInformation(
            "Processing order {OrderId}", message.OrderId);
        await ProcessAsync(message);
    }
}

// Message contract (use records in a shared contracts assembly)
public record OrderPlaced(Guid OrderId, decimal Total);
```

**Key packages:**

```xml
<PackageReference Include="WolverineFx" Version="3.*" />
<!-- Pick ONE transport: -->
<PackageReference Include="WolverineFx.RabbitMQ" Version="3.*" />
<!-- OR -->
<PackageReference Include="Wolverine.AzureServiceBus" Version="3.*" />
```

---

## Competing Consumers

Multiple consumer instances process messages from the same queue in parallel. The broker delivers each message to exactly one consumer, distributing load across instances.

### Pattern

```
Queue: order-processing
  ├── Consumer Instance A  (picks message 1)
  ├── Consumer Instance B  (picks message 2)
  └── Consumer Instance C  (picks message 3)
```

### Azure Service Bus -- Scaling Consumers

```csharp
// Multiple instances reading from the same queue automatically compete.
// MaxConcurrentCalls controls per-instance parallelism.
var processor = client.CreateProcessor("order-processing",
    new ServiceBusProcessorOptions
    {
        MaxConcurrentCalls = 20,
        PrefetchCount = 50,
        AutoCompleteMessages = false
    });
```

### Wolverine -- Parallelism Controls

```csharp
opts.ListenToRabbitQueue("order-processing")
    .ProcessInline()            // process on the listener thread
    .MaximumParallelMessages(10); // or limit concurrency
```

### Ordering Considerations

Competing consumers sacrifice strict ordering for throughput. When order matters:
- **Azure Service Bus**: Use sessions (`RequiresSession = true`) to guarantee FIFO within a session ID (e.g., per customer)
- **RabbitMQ**: Use a single consumer per queue, or consistent-hash exchange to partition by key
- **Wolverine**: Use `ListenToRabbitQueue().Sequential()` for strict ordering

---

## Dead-Letter Queues

Dead-letter queues (DLQs) capture messages that cannot be processed after exhausting retries. They prevent poison messages from blocking the main queue.

### Why Messages Are Dead-Lettered

| Reason | Trigger |
|--------|---------|
| Max delivery attempts exceeded | Message failed processing N times |
| TTL expired | Message sat in queue past its time-to-live |
| Consumer rejection | Consumer explicitly dead-letters the message |
| Queue length exceeded | Queue overflow policy routes to DLQ |

### Azure Service Bus DLQ

```csharp
// Dead-letter a message with reason
await args.DeadLetterMessageAsync(
    args.Message,
    deadLetterReason: "ValidationFailed",
    deadLetterErrorDescription: "Missing required field: CustomerId");

// Read from the dead-letter sub-queue
await using var dlqReceiver = client.CreateReceiver(
    "order-processing",
    new ServiceBusReceiverOptions
    {
        SubQueue = SubQueue.DeadLetter
    });

while (true)
{
    var message = await dlqReceiver.ReceiveMessageAsync(
        TimeSpan.FromSeconds(5), cancellationToken);
    if (message is null) break;

    logger.LogWarning(
        "DLQ message: {Reason} - {Description}",
        message.DeadLetterReason,
        message.DeadLetterErrorDescription);

    // Inspect, fix, and re-submit or discard
    await dlqReceiver.CompleteMessageAsync(message);
}
```

### Wolverine Error Handling

Wolverine has built-in retry and dead-letter policies per handler or globally:

```csharp
opts.OnException<ValidationException>()
    .MoveToErrorQueue();

opts.OnException<TimeoutException>()
    .RetryWithCooldown(
        TimeSpan.FromSeconds(1),
        TimeSpan.FromSeconds(5),
        TimeSpan.FromSeconds(15))
    .Then.MoveToErrorQueue();
```

### DLQ Monitoring

Always monitor DLQ depth with alerts. Unmonitored DLQs accumulate silently until data is lost or stale.

---

## Saga / Process Manager

Sagas coordinate multi-step business processes across services. Each step publishes events that trigger the next step, with compensation logic for failures.

### Choreography vs Orchestration

| Style | How it works | Use when |
|-------|-------------|----------|
| **Choreography** | Services react to events independently; no central coordinator | Simple flows, few steps, loosely coupled |
| **Orchestration** | A saga/process manager directs each step | Complex flows, compensation needed, visibility required |

### Wolverine Saga

Wolverine supports sagas via its durable messaging and handler chain model:

```csharp
// Saga state — persisted automatically by Wolverine
public class OrderSaga : Saga
{
    public Guid Id { get; set; } // Correlation ID
    public Guid OrderId { get; set; }
    public decimal Total { get; set; }
    public DateTime? PaymentReceivedAt { get; set; }

    // Start the saga
    public static (OrderSaga, RequestPayment) Start(OrderSubmitted submitted)
    {
        var saga = new OrderSaga
        {
            Id = submitted.OrderId,
            OrderId = submitted.OrderId,
            Total = submitted.Total
        };

        var command = new RequestPayment(submitted.OrderId, submitted.Total);
        return (saga, command);
    }

    // Handle payment received
    public FulfillOrder Handle(PaymentReceived received)
    {
        PaymentReceivedAt = DateTime.UtcNow;
        MarkCompleted(); // Ends the saga
        return new FulfillOrder(OrderId);
    }

    // Handle payment failure — compensate
    public CancelOrder Handle(PaymentFailed failed)
    {
        MarkCompleted();
        return new CancelOrder(OrderId);
    }
}
```

```csharp
// Registration with EF Core persistence
builder.Host.UseWolverine(opts =>
{
    opts.PersistMessagesWithEntityFrameworkCore();
    opts.UseEntityFrameworkCoreTransactions();
});
```

### Saga Persistence

| Store | Wolverine Package | Use when |
|-------|-------------------|----------|
| Entity Framework Core | `WolverineFx.EntityFrameworkCore` | Already using EF Core; need transactions |
| Marten (PostgreSQL) | `WolverineFx.Marten` | Event-sourced state; document-oriented |
| In-Memory | Built-in | Testing only -- state lost on restart |

### Compensation Pattern

When a saga step fails, publish compensating commands to undo prior steps:

```
OrderSubmitted -> RequestPayment -> PaymentReceived -> ReserveInventory
                                                          |
                                                     InventoryFailed
                                                          |
                                                    RefundPayment (compensation)
                                                          |
                                                    CancelOrder (compensation)
```

---

## Idempotent Consumers

At-least-once delivery means consumers may receive the same message multiple times. Idempotent consumers ensure repeated processing produces the same result.

### Database-Based Deduplication

```csharp
// Works with any messaging library — Wolverine, raw broker clients, etc.
public static class IdempotentOrderHandler
{
    public static async Task HandleAsync(
        OrderPlaced message,
        AppDbContext db,
        ILogger logger,
        IMessageContext context)
    {
        var messageId = context.Envelope!.Id;

        // Check if already processed
        var exists = await db.ProcessedMessages
            .AnyAsync(m => m.MessageId == messageId);

        if (exists)
        {
            logger.LogInformation(
                "Duplicate message {MessageId}, skipping", messageId);
            return;
        }

        // Process the message
        await ProcessOrderAsync(message);

        // Record as processed
        db.ProcessedMessages.Add(new ProcessedMessage
        {
            MessageId = messageId,
            ProcessedAt = DateTime.UtcNow,
            ConsumerType = nameof(IdempotentOrderHandler)
        });

        await db.SaveChangesAsync();
    }
}
```

### Natural Idempotency

Prefer operations that are naturally idempotent:
- **Upserts** (`INSERT ... ON CONFLICT UPDATE`) instead of blind inserts
- **Conditional updates** (`UPDATE ... WHERE Status = 'Pending'`) instead of unconditional
- **Deterministic IDs** derived from message content instead of auto-generated

---

## Message Envelope Pattern

Wrap message payloads in a standard envelope with metadata for tracing, versioning, and routing.

```csharp
public sealed record MessageEnvelope<T>(
    string MessageId,
    string MessageType,
    DateTimeOffset Timestamp,
    string CorrelationId,
    string Source,
    int Version, // Schema version for backward-compatible deserialization
    T Payload);
```

Wolverine provides envelope metadata automatically via `IMessageContext` (MessageId, CorrelationId, Headers). When using raw broker clients, implement envelopes explicitly.

---

## Existing MassTransit Codebases

MassTransit is widely used in existing .NET projects. If you encounter MassTransit code, its patterns map directly to Wolverine:

| MassTransit | Wolverine | Notes |
|-------------|-----------|-------|
| `IConsumer<T>` | `Handle(T message)` method | Wolverine uses convention, no interface |
| `IPublishEndpoint.Publish()` | `IMessageBus.PublishAsync()` | Same concept |
| `ISendEndpoint.Send()` | `IMessageBus.SendAsync()` | Same concept |
| `MassTransitStateMachine<T>` | `Saga` base class | Wolverine sagas are simpler |
| `AddMassTransit(x => ...)` | `UseWolverine(opts => ...)` | Host builder pattern |
| `_error` / `_skipped` queues | Dead-letter queue policies | Built-in error handling |

---

## Agent Gotchas

1. **Do not use auto-complete with Azure Service Bus** -- set `AutoCompleteMessages = false` and call `CompleteMessageAsync` after successful processing. Auto-complete acknowledges before processing finishes, risking data loss on failure.
2. **Do not forget to handle poison messages** -- always configure max delivery count and DLQ monitoring. Without these, a single bad message blocks the entire queue indefinitely.
3. **Do not use in-memory saga persistence in production** -- saga state is lost on restart, leaving business processes in unknown states. Use Entity Framework, Marten, or other durable persistence.
4. **Do not assume message ordering across partitions** -- competing consumers and topic subscriptions deliver messages out of order by default. Use sessions or partitioning when order matters.
5. **Do not skip idempotency for at-least-once consumers** -- brokers may redeliver on timeout, network glitch, or consumer restart. Every consumer must handle duplicate messages safely.
6. **Do not hardcode connection strings** -- use environment variables or Azure Key Vault references. For local development, use user secrets or `.env` files excluded from source control.

---

## References

- [Azure Service Bus documentation](https://learn.microsoft.com/en-us/azure/service-bus-messaging/)
- [Azure Service Bus client library for .NET](https://learn.microsoft.com/en-us/dotnet/api/overview/azure/messaging.servicebus-readme)
- [RabbitMQ .NET client documentation](https://www.rabbitmq.com/client-libraries/dotnet-api-guide)
- [Wolverine documentation](https://wolverine.netlify.app/)
- [Wolverine messaging](https://wolverine.netlify.app/guide/messaging/)
- [Enterprise Integration Patterns](https://www.enterpriseintegrationpatterns.com/)
