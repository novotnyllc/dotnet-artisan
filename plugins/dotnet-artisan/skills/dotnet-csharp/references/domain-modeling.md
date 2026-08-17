# Domain Modeling

Domain-Driven Design tactical patterns in C#. Covers aggregate roots, entities, value objects, domain events, integration events, domain services, repository contract design, and the distinction between rich and anemic domain models. These patterns apply to the domain layer itself -- the pure C# model that encapsulates business rules -- independent of any persistence technology.

## Aggregate Roots and Entities

An aggregate is a cluster of domain objects treated as a single unit for data changes. The aggregate root is the entry point -- all modifications to the aggregate pass through it.

### Entity Base Class

Entities have identity that persists across state changes. Use a base class to standardize identity and equality:

```csharp
public abstract class Entity<TId> : IEquatable<Entity<TId>>
    where TId : notnull
{
    // default! required for ORM hydration; Id is set immediately after construction
    public TId Id { get; protected set; } = default!;

    protected Entity() { } // Required for ORM hydration

    protected Entity(TId id) => Id = id;

    public override bool Equals(object? obj) =>
        obj is Entity<TId> other && Equals(other);

    public bool Equals(Entity<TId>? other) =>
        other is not null
        && GetType() == other.GetType()
        && EqualityComparer<TId>.Default.Equals(Id, other.Id);

    public override int GetHashCode() =>
        EqualityComparer<TId>.Default.GetHashCode(Id);

    public static bool operator ==(Entity<TId>? left, Entity<TId>? right) =>
        Equals(left, right);

    public static bool operator !=(Entity<TId>? left, Entity<TId>? right) =>
        !Equals(left, right);
}
```

### Aggregate Root Base Class

The aggregate root extends `Entity` and collects domain events:

```csharp
public abstract class AggregateRoot<TId> : Entity<TId>
    where TId : notnull
{
    private readonly List<IDomainEvent> _domainEvents = [];

    public IReadOnlyList<IDomainEvent> DomainEvents =>
        _domainEvents.AsReadOnly();

    protected AggregateRoot() { }
    protected AggregateRoot(TId id) : base(id) { }

    protected void RaiseDomainEvent(IDomainEvent domainEvent) =>
        _domainEvents.Add(domainEvent);

    public void ClearDomainEvents() => _domainEvents.Clear();
}
```

### Concrete Aggregate Example

```csharp
public sealed class Order : AggregateRoot<Guid>
{
    public CustomerId CustomerId { get; private set; } = default!;
    public OrderStatus Status { get; private set; }
    public Money Total { get; private set; } = Money.Zero("USD");

    private readonly List<OrderLine> _lines = [];
    public IReadOnlyList<OrderLine> Lines => _lines.AsReadOnly();

    private Order() { } // ORM constructor

    public static Order Create(CustomerId customerId)
    {
        var order = new Order(Guid.NewGuid())
        {
            CustomerId = customerId,
            Status = OrderStatus.Draft
        };

        order.RaiseDomainEvent(new OrderCreated(order.Id, customerId));
        return order;
    }

    public void AddLine(ProductId productId, int quantity, Money unitPrice)
    {
        if (Status != OrderStatus.Draft)
            throw new DomainException("Cannot modify a non-draft order.");

        if (quantity <= 0)
            throw new DomainException("Quantity must be positive.");

        var line = new OrderLine(productId, quantity, unitPrice);
        _lines.Add(line);
        RecalculateTotal();
    }

    public void Submit()
    {
        if (Status != OrderStatus.Draft)
            throw new DomainException("Only draft orders can be submitted.");

        if (_lines.Count == 0)
            throw new DomainException("Cannot submit an empty order.");

        Status = OrderStatus.Submitted;
        RaiseDomainEvent(new OrderSubmitted(Id, Total));
    }

    private void RecalculateTotal() =>
        Total = _lines.Aggregate(
            Money.Zero(Total.Currency),
            (sum, line) => sum.Add(line.LineTotal));
}
```

### Aggregate Design Rules

| Rule | Rationale |
|------|-----------|
| All mutations go through the aggregate root | Enforces invariants in one place |
| Reference other aggregates by ID only | Prevents cross-aggregate coupling; use `CustomerId` not `Customer` |
| Keep aggregates small | Large aggregates cause lock contention and slow loads |
| One aggregate per transaction | Cross-aggregate changes use domain events and eventual consistency |
| Expose collections as `IReadOnlyList<T>` | Prevents external code from bypassing root methods to mutate children |

For the EF Core persistence implications of these rules (navigation properties, owned types, cascade behavior), see [skill:dotnet-api].

---

## Value Objects

Value objects have no identity -- they are defined by their attribute values. Two value objects with the same attributes are equal. In C#, `record` and `record struct` provide natural value semantics.

### Record-Based Value Objects

```csharp
// Simple value object -- wraps a primitive to enforce constraints
public sealed record CustomerId
{
    public string Value { get; }

    public CustomerId(string value)
    {
        if (string.IsNullOrWhiteSpace(value))
            throw new DomainException("Customer ID cannot be empty.");

        Value = value;
    }

    public override string ToString() => Value;
}

// Composite value object -- multiple properties with validation
public sealed record Address
{
    public string Street { get; }
    public string City { get; }
    public string State { get; }
    public string PostalCode { get; }
    public string Country { get; }

    public Address(string street, string city, string state,
                   string postalCode, string country)
    {
        if (string.IsNullOrWhiteSpace(street))
            throw new DomainException("Street is required.");
        if (string.IsNullOrWhiteSpace(city))
            throw new DomainException("City is required.");
        if (string.IsNullOrWhiteSpace(postalCode))
            throw new DomainException("Postal code is required.");

        Street = street;
        City = city;
        State = state;
        PostalCode = postalCode;
        Country = country;
    }
}
```

### Money Value Object

Money is the canonical example of a multi-field value object with behavior:

```csharp
public sealed record Money
{
    public decimal Amount { get; }
    public string Currency { get; }

    public Money(decimal amount, string currency)
    {
        if (string.IsNullOrWhiteSpace(currency))
            throw new DomainException("Currency is required.");

        Amount = amount;
        Currency = currency.ToUpperInvariant();
    }

    public static Money Zero(string currency) => new(0m, currency);

    public Money Add(Money other)
    {
        EnsureSameCurrency(other);
        return new Money(Amount + other.Amount, Currency);
    }

    public Money Subtract(Money other)
    {
        EnsureSameCurrency(other);
        return new Money(Amount - other.Amount, Currency);
    }

    public Money Multiply(int quantity) =>
        new(Amount * quantity, Currency);

    public Money Multiply(decimal factor) =>
        new(Amount * factor, Currency);

    private void EnsureSameCurrency(Money other)
    {
        if (Currency != other.Currency)
            throw new DomainException(
                $"Cannot operate on {Currency} and {other.Currency}.");
    }

    public override string ToString() => $"{Amount:F2} {Currency}";
}
```

### Value Object EF Core Mapping

Map value objects using owned types or value conversions (implementation in [skill:dotnet-api]):

```csharp
// Owned type -- maps to columns in the parent table
builder.OwnsOne(o => o.Total, money =>
{
    money.Property(m => m.Amount).HasColumnName("TotalAmount");
    money.Property(m => m.Currency).HasColumnName("TotalCurrency")
        .HasMaxLength(3);
});

// Value conversion -- single-property value objects
builder.Property(o => o.CustomerId)
    .HasConversion(
        id => id.Value,
        value => new CustomerId(value))
    .HasMaxLength(50);
```

### When to Use Value Objects

| Use value object | Use primitive |
|-----------------|--------------|
| Domain concept with constraints (email, money, quantity) | Infrastructure IDs with no domain rules (correlation IDs, trace IDs) |
| Multiple properties that form a unit (address, date range) | Single value with no validation needed |
| Need to prevent primitive obsession in domain methods | Simple DTO fields at API boundary |

---

## Domain Events

Domain events represent something meaningful that happened in the domain. They enable loose coupling between aggregates and trigger side effects (sending emails, updating read models, publishing integration events).

### Event Contracts

```csharp
// Marker interface for all domain events
public interface IDomainEvent
{
    Guid EventId { get; }
    DateTimeOffset OccurredAt { get; }
}

// Base record for convenience
public abstract record DomainEventBase : IDomainEvent
{
    public Guid EventId { get; } = Guid.NewGuid();
    public DateTimeOffset OccurredAt { get; } = DateTimeOffset.UtcNow;
}

// Concrete events
public sealed record OrderCreated(
    Guid OrderId, CustomerId CustomerId) : DomainEventBase;

public sealed record OrderSubmitted(
    Guid OrderId, Money Total) : DomainEventBase;

public sealed record OrderCancelled(
    Guid OrderId, string Reason) : DomainEventBase;
```

### Dispatching Domain Events

Dispatch events after `SaveChangesAsync` succeeds to ensure the aggregate state is persisted before side effects execute:

```csharp
public sealed class DomainEventDispatcher(
    IServiceProvider serviceProvider)
{
    public async Task DispatchAsync(
        IEnumerable<IDomainEvent> events,
        CancellationToken ct)
    {
        foreach (var domainEvent in events)
        {
            var handlerType = typeof(IDomainEventHandler<>)
                .MakeGenericType(domainEvent.GetType());

            var handlers = serviceProvider.GetServices(handlerType);

            foreach (var handler in handlers)
            {
                await ((dynamic)handler).HandleAsync(
                    (dynamic)domainEvent, ct);
            }
        }
    }
}

// Note: The (dynamic) dispatch pattern is simple but not AOT-compatible.
// For Native AOT scenarios, use a source-generated or dictionary-based
// dispatcher. See [skill:dotnet-tooling] for AOT constraints.

// Handler interface
public interface IDomainEventHandler<in TEvent>
    where TEvent : IDomainEvent
{
    Task HandleAsync(TEvent domainEvent, CancellationToken ct);
}
```

### Saving with Event Dispatch

Use an EF Core `SaveChangesInterceptor` or a wrapper to dispatch events after save:

```csharp
public sealed class EventDispatchingSaveChangesInterceptor(
    DomainEventDispatcher dispatcher)
    : SaveChangesInterceptor
{
    public override async ValueTask<int> SavedChangesAsync(
        SaveChangesCompletedEventData eventData,
        int result,
        CancellationToken ct)
    {
        if (eventData.Context is not null)
        {
            var aggregates = eventData.Context.ChangeTracker
                .Entries<AggregateRoot<Guid>>()
                .Where(e => e.Entity.DomainEvents.Count > 0)
                .Select(e => e.Entity)
                .ToList();

            var events = aggregates
                .SelectMany(a => a.DomainEvents)
                .ToList();

            foreach (var aggregate in aggregates)
            {
                aggregate.ClearDomainEvents();
            }

            await dispatcher.DispatchAsync(events, ct);
        }

        return result;
    }
}
```

### Domain Events vs Integration Events

| Aspect | Domain Event | Integration Event |
|--------|-------------|-------------------|
| Scope | Within a bounded context | Across bounded contexts / services |
| Transport | In-process (dispatcher) | Message broker (Service Bus, RabbitMQ) |
| Coupling | References domain types | Uses primitive/DTO types only |
| Reliability | Same transaction scope | At-least-once with idempotent consumers |
| Example | `OrderSubmitted` (triggers email handler) | `OrderSubmittedIntegration` (notifies shipping service) |

A domain event handler may publish an integration event to a message broker. See [skill:dotnet-api] for integration event infrastructure.

```csharp
// Domain event handler that publishes an integration event
public sealed class OrderSubmittedHandler(
    IPublishEndpoint publishEndpoint)
    : IDomainEventHandler<OrderSubmitted>
{
    public async Task HandleAsync(
        OrderSubmitted domainEvent, CancellationToken ct)
    {
        // Map domain event to integration event (no domain types)
        await publishEndpoint.Publish(
            new OrderSubmittedIntegration(
                domainEvent.OrderId,
                domainEvent.Total.Amount,
                domainEvent.Total.Currency),
            ct);
    }
}
```

---

## Rich vs Anemic Domain Models

### Rich Domain Model

Business logic lives inside the domain entities. Methods enforce invariants and return meaningful results:

```csharp
public sealed class ShoppingCart : AggregateRoot<Guid>
{
    private readonly List<CartItem> _items = [];
    public IReadOnlyList<CartItem> Items => _items.AsReadOnly();

    public void AddItem(ProductId productId, int quantity, Money unitPrice)
    {
        var existing = _items.Find(i => i.ProductId == productId);

        if (existing is not null)
        {
            existing.IncreaseQuantity(quantity);
        }
        else
        {
            _items.Add(new CartItem(productId, quantity, unitPrice));
        }
    }

    public void RemoveItem(ProductId productId)
    {
        var item = _items.Find(i => i.ProductId == productId)
            ?? throw new DomainException(
                $"Product {productId} not in cart.");

        _items.Remove(item);
    }

    public Money GetTotal(string currency) =>
        _items.Aggregate(
            Money.Zero(currency),
            (sum, item) => sum.Add(item.LineTotal));
}
```

### Anemic Domain Model (Anti-Pattern)

Entities are data bags with public setters. Business logic lives in external services:

```csharp
// ANTI-PATTERN: Entity is just a data container
public class ShoppingCart
{
    public Guid Id { get; set; }
    public List<CartItem> Items { get; set; } = [];
}

// All logic lives here -- the entity has no behavior
public class ShoppingCartService
{
    public void AddItem(ShoppingCart cart, string productId,
        int quantity, decimal unitPrice)
    {
        var existing = cart.Items.Find(i => i.ProductId == productId);
        if (existing != null)
            existing.Quantity += quantity;
        else
            cart.Items.Add(new CartItem { ... });
    }
}
```

### Decision Guide

| Factor | Rich model | Anemic model |
|--------|-----------|--------------|
| Complex invariants | Enforced in entity | Scattered across services |
| Testability | Test entity behavior directly | Test service + entity together |
| Discoverability | Methods on entity show capabilities | Must find the right service class |
| Persistence coupling | Requires ORM-friendly private setters | Simple property mapping |
| Team familiarity | DDD experience required | Familiar to most developers |

**Recommendation:** Start with a rich model for aggregates with complex business rules. Anemic models are acceptable for simple CRUD entities where the domain logic is minimal (e.g., reference data, configuration records).

---

## Domain Services

Domain services encapsulate business logic that does not naturally belong to a single entity or value object. They operate on domain types and enforce cross-aggregate rules.

```csharp
public sealed class PricingService
{
    public Money CalculateDiscount(
        Order order,
        CustomerTier tier,
        IReadOnlyList<PromotionRule> activePromotions)
    {
        var discount = Money.Zero(order.Total.Currency);

        // Tier-based discount
        discount = tier switch
        {
            CustomerTier.Gold => discount.Add(
                order.Total.Multiply(0.10m)),
            CustomerTier.Platinum => discount.Add(
                order.Total.Multiply(0.15m)),
            _ => discount
        };

        // Promotion-based discounts
        foreach (var promo in activePromotions)
        {
            if (promo.AppliesTo(order))
            {
                discount = discount.Add(promo.Calculate(order));
            }
        }

        return discount;
    }
}
```

### When to Use Domain Services

- Logic requires data from **multiple aggregates** that should not reference each other
- A business rule does not belong to any single entity (e.g., pricing across products and customer tiers)
- External policy or configuration drives the logic (e.g., tax calculation rules)

Domain services should remain **pure** -- no infrastructure dependencies. If the logic needs a database or external API, place it in an application service that calls the domain service with pre-loaded data.

---

## Repository Contracts

Repository interfaces belong in the **domain layer** and express aggregate loading and saving semantics. Implementation details (EF Core, Dapper) live in the infrastructure layer.

```csharp
// Domain layer -- defines the contract
public interface IOrderRepository
{
    Task<Order?> FindByIdAsync(Guid id, CancellationToken ct);
    Task AddAsync(Order order, CancellationToken ct);
    Task SaveChangesAsync(CancellationToken ct);
}

// Domain layer -- unit of work abstraction (optional)
public interface IUnitOfWork
{
    Task<int> SaveChangesAsync(CancellationToken ct);
}
```

For EF Core repository implementations, see [skill:dotnet-api].

### Repository Design Rules

| Rule | Rationale |
|------|-----------|
| One repository per aggregate root | Child entities are accessed through the root |
| No `IQueryable<T>` return types | Prevents persistence concerns from leaking into domain |
| No generic `IRepository<T>` | Cannot express aggregate-specific loading rules |
| Return domain types, not DTOs | Repositories serve the domain; read models use projections |
| Include `CancellationToken` on all async methods | Required for proper cancellation propagation |

---

## Domain Exceptions

Use domain-specific exceptions to signal invariant violations. This separates domain errors from infrastructure errors:

```csharp
public class DomainException : Exception
{
    public DomainException(string message) : base(message) { }
    public DomainException(string message, Exception inner)
        : base(message, inner) { }
}

// Specific domain exceptions for different invariant violations
public sealed class InsufficientStockException(
    ProductId productId, int requested, int available)
    : DomainException(
        $"Insufficient stock for {productId}: " +
        $"requested {requested}, available {available}")
{
    public ProductId ProductId => productId;
    public int Requested => requested;
    public int Available => available;
}
```

Map domain exceptions to HTTP responses at the API boundary (e.g., `DomainException` to 422 Unprocessable Entity). Do not let infrastructure concerns like HTTP status codes leak into the domain layer.

---

## Agent Gotchas

1. **Do not expose public setters on aggregate properties** -- all state changes must go through methods on the aggregate root that enforce invariants. Use `private set` or `init` for properties.
2. **Do not create navigation properties between aggregate roots** -- reference other aggregates by ID value objects (e.g., `CustomerId`) not by entity navigation. Cross-aggregate navigation breaks bounded context isolation.
3. **Do not dispatch domain events inside the transaction** -- dispatch after `SaveChangesAsync` succeeds. Dispatching before save means side effects fire even if the save fails.
4. **Do not use domain types in integration events** -- integration events cross bounded context boundaries and must use primitives or DTOs. Domain type changes would break other services.
5. **Do not put validation logic only in the API layer** -- domain invariants belong in the domain model. API validation (`references/validation-patterns.md`) catches malformed input; domain validation enforces business rules.
6. **Do not create anemic entities with public `List<T>` properties** -- expose collections as `IReadOnlyList<T>` and provide mutation methods on the aggregate root that enforce business rules.
7. **Do not inject infrastructure services into domain entities** -- entities should be pure C# objects. Use domain services for logic that needs external data, and application services for infrastructure orchestration.

---

## References

- [Domain-driven design with EF Core](https://learn.microsoft.com/en-us/dotnet/architecture/microservices/microservice-ddd-cqrs-patterns/)
- [Implementing domain events](https://learn.microsoft.com/en-us/dotnet/architecture/microservices/microservice-ddd-cqrs-patterns/domain-events-design-implementation)
- [Value objects in DDD](https://learn.microsoft.com/en-us/dotnet/architecture/microservices/microservice-ddd-cqrs-patterns/implement-value-objects)
- [Aggregate design rules (Vaughn Vernon)](https://www.dddcommunity.org/library/vernon_2011/)
- [EF Core owned entity types](https://learn.microsoft.com/en-us/ef/core/modeling/owned-entities)
- [Repository pattern in .NET](https://learn.microsoft.com/en-us/dotnet/architecture/microservices/microservice-ddd-cqrs-patterns/infrastructure-persistence-layer-design)
