# SOLID Principles

Foundational design principles for .NET applications. Covers each SOLID principle with concrete C# anti-patterns and fixes, plus DRY guidance with nuance on when duplication is acceptable. These principles guide class design, interface contracts, and dependency management across all .NET project types.

## Single Responsibility Principle (SRP)

A class should have only one reason to change. Apply the "describe in one sentence" test: if you cannot describe what a class does in one sentence without using "and" or "or", it likely violates SRP.

### Anti-Pattern: God Class / Fat Controller

God classes and fat controllers are the same violation: one class mixes validation, business logic, persistence, and notifications. In minimal APIs this manifests as endpoint lambdas that inline all concerns instead of delegating to focused services.

```csharp
// WRONG -- OrderService handles validation, persistence, email, and PDF generation
public class OrderService
{
    private readonly AppDbContext _db;
    private readonly SmtpClient _smtp;

    public OrderService(AppDbContext db, SmtpClient smtp)
    {
        _db = db;
        _smtp = smtp;
    }

    public async Task<Order> CreateOrderAsync(CreateOrderRequest request)
    {
        // Validation logic (reason to change #1)
        if (string.IsNullOrEmpty(request.CustomerId))
            throw new ArgumentException("Customer required");

        // Persistence logic (reason to change #2)
        var order = new Order { CustomerId = request.CustomerId };
        _db.Orders.Add(order);
        await _db.SaveChangesAsync();

        // Email notification (reason to change #3)
        var message = new MailMessage("noreply@shop.com", request.Email,
            "Order Confirmed", $"Order {order.Id} created.");
        await _smtp.SendMailAsync(message);

        // PDF generation (reason to change #4)
        GenerateInvoicePdf(order);

        return order;
    }

    private void GenerateInvoicePdf(Order order) { /* ... */ }
}
```

### Fix: Separate Responsibilities

```csharp
// Each class has one reason to change
public sealed class OrderCreator(
    IOrderValidator validator,
    IOrderRepository repository,
    IOrderNotifier notifier)
{
    public async Task<Order> CreateAsync(
        CreateOrderRequest request, CancellationToken ct)
    {
        validator.Validate(request);

        var order = await repository.AddAsync(request, ct);

        await notifier.OrderCreatedAsync(order, ct);

        return order;
    }
}

public sealed class OrderValidator : IOrderValidator
{
    public void Validate(CreateOrderRequest request)
    {
        ArgumentException.ThrowIfNullOrEmpty(request.CustomerId);
        // ... validation rules
    }
}

public sealed class OrderRepository(AppDbContext db) : IOrderRepository
{
    public async Task<Order> AddAsync(
        CreateOrderRequest request, CancellationToken ct)
    {
        var order = new Order { CustomerId = request.CustomerId };
        db.Orders.Add(order);
        await db.SaveChangesAsync(ct);
        return order;
    }
}
```

For minimal API endpoints, keep the lambda thin -- delegate to a handler:

```csharp
app.MapPost("/api/orders", async (
    CreateOrderRequest request,
    IOrderHandler handler,
    CancellationToken ct) =>
{
    var result = await handler.CreateAsync(request, ct);
    return result switch
    {
        { IsSuccess: true } => Results.Created(
            $"/api/orders/{result.Value.Id}", result.Value),
        _ => Results.ValidationProblem(result.Errors)
    };
});
```

---

## Open/Closed Principle (OCP)

Classes should be open for extension but closed for modification. Add new behavior by implementing new types, not by editing existing switch/if chains.

### Anti-Pattern: Switch on Type

```csharp
// WRONG -- adding a new discount type requires modifying this method
public decimal CalculateDiscount(Order order)
{
    switch (order.DiscountType)
    {
        case "Percentage":
            return order.Total * order.DiscountValue / 100;
        case "FixedAmount":
            return order.DiscountValue;
        case "BuyOneGetOneFree":
            return order.Lines
                .Where(l => l.Quantity >= 2)
                .Sum(l => l.Price);
        default:
            return 0;
    }
}
```

### Fix: Strategy Pattern

```csharp
public interface IDiscountStrategy
{
    decimal Calculate(Order order);
}

public sealed class PercentageDiscount(decimal percentage) : IDiscountStrategy
{
    public decimal Calculate(Order order) =>
        order.Total * percentage / 100;
}

public sealed class FixedAmountDiscount(decimal amount) : IDiscountStrategy
{
    public decimal Calculate(Order order) =>
        Math.Min(amount, order.Total);
}

// New discount type -- no existing code modified
public sealed class BuyOneGetOneFreeDiscount : IDiscountStrategy
{
    public decimal Calculate(Order order) =>
        order.Lines
            .Where(l => l.Quantity >= 2)
            .Sum(l => l.Price);
}

// Usage -- resolved via DI or factory
public sealed class OrderPricing(
    IEnumerable<IDiscountStrategy> strategies)
{
    public decimal ApplyBestDiscount(Order order) =>
        strategies.Max(s => s.Calculate(order));
}
```

### Extension via Abstract Classes

When strategies share significant behavior (validation, logging), use an abstract base class with a template method:

```csharp
public abstract class NotificationSender
{
    public async Task SendAsync(Notification notification, CancellationToken ct)
    {
        ArgumentNullException.ThrowIfNull(notification);
        await SendCoreAsync(notification, ct);
    }

    protected abstract Task SendCoreAsync(Notification notification, CancellationToken ct);
}

// Each channel extends without modifying the base
public sealed class EmailNotificationSender(IEmailClient client) : NotificationSender
{
    protected override Task SendCoreAsync(Notification n, CancellationToken ct) =>
        client.SendEmailAsync(n.Recipient, n.Subject, n.Body, ct);
}
```

---

## Liskov Substitution Principle (LSP)

Subtypes must be substitutable for their base types without altering program correctness. A subclass must honor the behavioral contract of its parent -- preconditions cannot be strengthened, postconditions cannot be weakened.

### Anti-Pattern: Throwing in Override

```csharp
public class FileStorage : IStorage
{
    public virtual Stream OpenRead(string path) =>
        File.OpenRead(path);
}

// WRONG -- ReadOnlyFileStorage violates the base contract by
// throwing on a method the base type supports
public class ReadOnlyFileStorage : FileStorage
{
    public override Stream OpenRead(string path)
    {
        if (!File.Exists(path))
            throw new InvalidOperationException(
                "Cannot open files in read-only mode");
        return base.OpenRead(path);
    }

    // Surprise: callers expecting FileStorage behavior get exceptions
}
```

### LSP Compliance Checklist

- Derived classes do not throw new exception types that the base does not declare
- Overrides do not add preconditions (e.g., null checks the base does not require)
- Overrides do not weaken postconditions (e.g., returning null when base guarantees non-null)
- Behavioral contracts are preserved: if `ICollection.Add` succeeds on the base, it must succeed on the derived type

---

## Interface Segregation Principle (ISP)

Clients should not be forced to depend on methods they do not use. Prefer narrow, role-specific interfaces over wide "header" interfaces.

### Anti-Pattern: Header Interface

```csharp
// WRONG -- IWorker forces all implementations to support every capability
public interface IWorker
{
    Task DoWorkAsync(CancellationToken ct);
    void ClockIn();
    void ClockOut();
    Task<decimal> CalculatePayAsync();
    void RequestTimeOff(DateRange range);
}

// ContractWorker does not clock in/out or request time off
public class ContractWorker : IWorker
{
    public Task DoWorkAsync(CancellationToken ct) => /* ... */;
    public void ClockIn() => throw new NotSupportedException(); // ISP violation
    public void ClockOut() => throw new NotSupportedException(); // ISP violation
    public Task<decimal> CalculatePayAsync() => /* ... */;
    public void RequestTimeOff(DateRange range) =>
        throw new NotSupportedException(); // ISP violation
}
```

### Fix: Role Interfaces

Split the wide interface into focused roles. Each class implements only the interfaces it supports:

```csharp
public interface IWorkPerformer { Task DoWorkAsync(CancellationToken ct); }
public interface ITimeTrackable { void ClockIn(); void ClockOut(); }
public interface IPayable { Task<decimal> CalculatePayAsync(); }
public interface ITimeOffEligible { void RequestTimeOff(DateRange range); }

// FullTimeEmployee: IWorkPerformer, ITimeTrackable, IPayable, ITimeOffEligible
// ContractWorker only implements what it needs -- no throwing stubs
public sealed class ContractWorker : IWorkPerformer, IPayable
{
    public Task DoWorkAsync(CancellationToken ct) => /* ... */;
    public Task<decimal> CalculatePayAsync() => /* ... */;
}
```

### Practical .NET ISP

The .NET BCL demonstrates ISP well:

| Wide Interface | Segregated Alternatives |
|---|---|
| `IList<T>` (read + write) | `IReadOnlyList<T>` (read only) |
| `ICollection<T>` | `IReadOnlyCollection<T>` |
| `IDictionary<K,V>` | `IReadOnlyDictionary<K,V>` |

Accept the narrowest interface your method actually needs:

```csharp
// WRONG -- requires IList<T> but only reads
public decimal CalculateTotal(IList<OrderLine> lines) =>
    lines.Sum(l => l.Price * l.Quantity);

// RIGHT -- accept the narrowest type: IEnumerable<T> for iteration,
// IReadOnlyList<T> for indexed access, IList<T> only for mutation
public decimal CalculateTotal(IEnumerable<OrderLine> lines) =>
    lines.Sum(l => l.Price * l.Quantity);
```

---

## Dependency Inversion Principle (DIP)

High-level modules should not depend on low-level modules. Both should depend on abstractions. Abstractions should not depend on details.

### Anti-Pattern and Fix

```csharp
// WRONG -- high-level module creates low-level dependencies directly
public sealed class OrderProcessor
{
    private readonly SqlOrderRepository _repository = new(); // Tight coupling
    private readonly SmtpEmailSender _emailSender = new();   // Tight coupling
}

// RIGHT -- depend on abstractions owned by the high-level module
public interface IOrderRepository
{
    Task SaveAsync(Order order, CancellationToken ct = default);
}

public sealed class OrderProcessor(
    IOrderRepository repository,
    INotificationService notifier)
{
    public async Task ProcessAsync(Order order, CancellationToken ct)
    {
        await repository.SaveAsync(order, ct);
        await notifier.NotifyAsync(order.Email,
            "Order processed", $"Order {order.Id}", ct);
    }
}
```

### DI Registration

Register abstractions with Microsoft.Extensions.DependencyInjection. See `references/dependency-injection.md` for lifetime management, keyed services, and decoration patterns.

```csharp
builder.Services.AddScoped<IOrderRepository, SqlOrderRepository>();
builder.Services.AddScoped<INotificationService, SmtpNotificationService>();
builder.Services.AddScoped<OrderProcessor>();
```

### DIP Boundaries

Apply DIP at module boundaries, not everywhere:

- **DO** abstract infrastructure (database, email, file system, HTTP clients)
- **DO** abstract cross-cutting concerns (logging is already abstracted via `ILogger<T>`)
- **DO NOT** abstract simple value objects, DTOs, or internal implementation details
- **DO NOT** create `IFoo`/`Foo` pairs for every class -- only abstract where substitution adds value (testing, multiple implementations, or anticipated change)

---

## DRY (Don't Repeat Yourself)

Every piece of knowledge should have a single, authoritative representation. But DRY is about knowledge duplication, not code duplication.

### When to Apply DRY

Apply DRY when two pieces of code represent the **same concept** and must change together:

```csharp
// WRONG -- tax rate 0.08m duplicated in InvoiceService and QuoteService
// If the rate changes, both must be found and updated

// RIGHT -- single source of truth
public static class TaxRates
{
    public const decimal StandardRate = 0.08m;
}
```

### Rule of Three

Do not abstract prematurely. Wait until you see the same pattern three times before extracting a shared abstraction:

1. **First occurrence** -- write it inline
2. **Second occurrence** -- note the duplication but keep it (the two usages may diverge)
3. **Third occurrence** -- extract a shared method, class, or utility

### When Duplication Is Acceptable

Not all code similarity represents knowledge duplication. A `CustomerValidator` and `SupplierValidator` may share similar null checks but represent different business concepts that will evolve independently -- do NOT merge them.

**Acceptable duplication scenarios:**
- Test setup code that looks similar across test classes (coupling tests to shared helpers makes them fragile)
- DTOs for different API versions (V1 and V2 may share fields now but diverge later)
- Configuration for different environments (dev and prod configs that happen to be similar today)
- Mapping code between layers (coupling layers to share mappers defeats the purpose of separate layers)

When you do extract, prefer composition (shared utility or extension method) over inheritance from a common base class.

---

## Decision Guide

| Symptom | Likely Violation | Fix |
|---|---|---|
| Class described with "and" | SRP | Split into focused classes |
| Modifying existing code to add features | OCP | Use strategy/plugin pattern |
| `NotSupportedException` in overrides | LSP | Redesign hierarchy or use composition |
| Empty/throwing interface methods | ISP | Split into role interfaces |
| `new` keyword for dependencies | DIP | Inject via constructor |
| Magic numbers/strings in multiple files | DRY | Extract constants or config |
| Copy-pasted code blocks (3+) | DRY | Extract shared method |

---

## Agent Gotchas

1. **Do not create `IFoo`/`Foo` pairs for every class.** DIP calls for abstractions at module boundaries (infrastructure, external services), not for every internal class. Unnecessary interfaces add indirection without value and clutter the codebase.
2. **Do not merge similar-looking code from different bounded contexts.** Two validators or DTOs that look alike but serve different business concepts should remain separate. Premature DRY creates coupling between concepts that evolve independently.
3. **Do not use inheritance to share behavior between unrelated types.** Prefer composition (injecting a shared service or using extension methods) over inheriting from a common base class. Inheritance creates tight coupling and makes LSP violations more likely.
4. **Fat controllers and god classes are SRP violations.** When generating endpoint handlers, keep them thin -- delegate to dedicated services for validation, business logic, and persistence. Apply the "one sentence" test to each class.
5. **Switch statements on type discriminators violate OCP.** Replace them with polymorphism (strategy pattern, interface dispatch) so new types can be added without modifying existing code.
6. **Accept the narrowest interface type your method needs.** Use `IEnumerable<T>` for iteration, `IReadOnlyList<T>` for indexed read access, and `IList<T>` only when mutation is required. This follows ISP and makes methods more reusable.

---

## Knowledge Sources

Grounded in publicly available content from Steve Smith (Ardalis) -- SOLID in .NET, guard clauses, clean architecture layering -- and Jimmy Bogard -- SRP for aggregate design, OCP for domain event handling. This skill applies publicly documented guidance and does not represent or speak for the named sources.

## References

- [Dependency Injection in .NET](https://learn.microsoft.com/en-us/dotnet/core/extensions/dependency-injection)
- [Clean Architecture (Ardalis)](https://github.com/ardalis/CleanArchitecture)

## Attribution

Adapted from [Aaronontheweb/dotnet-skills](https://github.com/Aaronontheweb/dotnet-skills) (MIT license).
