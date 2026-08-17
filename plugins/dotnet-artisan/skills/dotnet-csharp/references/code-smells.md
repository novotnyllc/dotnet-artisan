# Code Smells

Proactive code-smell and anti-pattern detection for C# code. This skill triggers during all workflow modes -- planning, implementation, and review. Each entry identifies the smell, explains why it is harmful, provides the correct fix, and references the relevant CA rule or cross-reference.

## 1. Resource Management (IDisposable Misuse)

| Smell | Why Harmful | Fix | Rule |
|-------|-------------|-----|------|
| Missing `using` on disposable locals | Leaks unmanaged handles (sockets, files, DB connections) | Wrap in `using` declaration or `using` block | CA2000 |
| Undisposed `IDisposable` fields | Class holds disposable resource but never disposes it | Implement `IDisposable`; dispose fields in `Dispose()` | CA2213 |
| Wrong Dispose pattern (no finalizer guard) | Double-dispose or missed cleanup on GC finalization | Follow canonical `Dispose(bool)` pattern; call `GC.SuppressFinalize(this)` | CA1816 |
| Disposable created in one method, stored in field | Ownership unclear; easy to forget disposal | Document ownership; make the containing class `IDisposable` | CA2000 |
| `using` on non-owned resource | Premature disposal of shared resource (e.g., injected `HttpClient`) | Only dispose resources you create; let DI manage injected services | -- |

See the **Detailed Examples and Fixes** section below for code examples of each pattern.

---

## 2. Warning Suppression Hacks

| Smell | Why Harmful | Fix | Rule |
|-------|-------------|-----|------|
| Invoking event with `null` to suppress CS0067 | Creates misleading runtime behavior; masks real bugs | Use `#pragma warning disable CS0067` or explicit event accessors `{ add {} remove {} }` | CS0067 |
| Dummy variable assignments to suppress CS0219 | Dead code that confuses readers | Use `_ = expression;` discard or `#pragma warning disable` | CS0219 |
| Blanket `#pragma warning disable` without restore | Suppresses ALL warnings for rest of file | Always pair with `#pragma warning restore`; suppress specific codes only | -- |
| `[SuppressMessage]` without justification | Future maintainers cannot evaluate if suppression is still valid | Always include `Justification = "reason"` | CA1303 |

See the **Detailed Examples and Fixes** section below for the CS0067 motivating example (bad pattern to correct fix).

---

## 3. LINQ Anti-Patterns

| Smell | Why Harmful | Fix | Rule |
|-------|-------------|-----|------|
| Premature `.ToList()` mid-chain | Forces full materialization; wastes memory | Keep chain lazy; materialize only at the end | CA1851 |
| Multiple enumeration of `IEnumerable<T>` | Re-executes query or DB call on each enumeration | Materialize once with `.ToList()` then reuse | CA1851 |
| Client-side evaluation in EF Core | Loads entire table into memory; silent perf bomb | Rewrite query as translatable LINQ or use `AsAsyncEnumerable()` with explicit intent | -- |
| `.Count() > 0` instead of `.Any()` | Enumerates entire collection instead of short-circuiting | Use `.Any()` for existence checks | CA1827 |
| Nested `foreach` instead of `.Join()` or `.GroupJoin()` | O(n*m) when O(n+m) is possible | Use LINQ join operations or `Dictionary` lookup | -- |
| `.Where().First()` instead of `.First(predicate)` | Creates unnecessary intermediate iterator | Pass predicate directly to `.First()` or `.FirstOrDefault()` | CA1826 |

---

## 4. Event Handling Leaks

| Smell | Why Harmful | Fix | Rule |
|-------|-------------|-----|------|
| Not unsubscribing from events | Memory leak: publisher holds reference to subscriber | Unsubscribe in `Dispose()` or use weak event pattern | -- |
| Raising events in constructor | Subscribers may not be attached yet; derived class not fully constructed | Raise events only from fully initialized instances | CA2214 |
| `async void` event handler (misused) | `async void` is the only valid signature for event handlers, but exceptions are unobservable | Wrap body in try/catch; log and handle exceptions explicitly | -- |
| Event handler not checking for null | `NullReferenceException` when no subscribers | Use `event?.Invoke()` null-conditional pattern | -- |
| Static event without cleanup | Rooted references prevent GC for application lifetime | Prefer instance events or use `WeakEventManager` | -- |

Cross-reference: `references/async-patterns.md` covers `async void` fire-and-forget patterns in depth.

---

## 5. Design Smells

| Smell | Threshold | Why Harmful | Fix |
|-------|-----------|-------------|-----|
| God class | >500 lines | Too many responsibilities; hard to test and maintain | Extract cohesive classes using SRP |
| Long method | >30 lines | Hard to understand, test, and review | Extract helper methods with descriptive names |
| Long parameter list | >5 parameters | Indicates missing abstraction | Introduce parameter object or builder |
| Feature envy | Method uses another class's data more than its own | Misplaced responsibility; tight coupling | Move method to the class it envies |
| Primitive obsession | Domain concepts represented as raw `string`/`int` | No type safety; validation scattered | Introduce value objects or strongly-typed IDs |
| Deep nesting | >3 levels of indentation | Hard to follow control flow | Use guard clauses (early return) and extract methods |

---

## 6. Exception Handling Gaps

| Smell | Why Harmful | Fix | Rule |
|-------|-------------|-----|------|
| Empty catch block | Silently swallows errors; masks bugs | At minimum, log the exception; prefer letting it propagate | CA1031 |
| Catching base `Exception` | Catches `OutOfMemoryException`, `StackOverflowException`, etc. | Catch specific exception types | CA1031 |
| Log-and-swallow (`catch { log; }`) | Caller never learns operation failed | Re-throw after logging, or return error result | -- |
| Throwing in `finally` | Masks original exception with the new one | Use try/catch inside finally; never throw from finally | -- |
| `throw ex;` instead of `throw;` | Resets stack trace; hides original failure location | Use bare `throw;` to preserve stack trace | CA2200 |
| Not including inner exception | Loses causal chain when wrapping exceptions | Pass original as `innerException` parameter | -- |

Cross-reference: `references/async-patterns.md` covers exception handling in fire-and-forget and async void scenarios.

---

## Quick Reference: CA Rules

| Rule | Description |
|------|-------------|
| CA1031 | Do not catch general exception types |
| CA1816 | Call `GC.SuppressFinalize` correctly |
| CA1826 | Do not use `Enumerable` methods on indexable collections |
| CA1827 | Do not use `Count()`/`LongCount()` when `Any()` can be used |
| CA1851 | Possible multiple enumerations of `IEnumerable` collection |
| CA2000 | Dispose objects before losing scope |
| CA2200 | Rethrow to preserve stack details |
| CA2213 | Disposable fields should be disposed |
| CA2214 | Do not call overridable methods in constructors |

Enable these via `<AnalysisLevel>latest-all</AnalysisLevel>` in your project. See `references/coding-standards.md` for analyzer configuration.

---

## References

- [Microsoft Code Quality Rules](https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/)
- [Framework Design Guidelines](https://learn.microsoft.com/en-us/dotnet/standard/design-guidelines/)
- [David Fowler Async Guidance](https://github.com/davidfowl/AspNetCoreDiagnosticScenarios/blob/master/AsyncGuidance.md)

---

## Detailed Examples and Fixes

Code examples for each anti-pattern category. Each section shows the bad pattern followed by the correct fix.

---

## 1. Resource Management (IDisposable)

### Missing `using` on Disposable Local (CA2000)

```csharp
// BAD: StreamReader is never disposed if an exception occurs
public string ReadFile(string path)
{
    var reader = new StreamReader(path);
    return reader.ReadToEnd();  // reader leaked on exception or normal exit
}

// FIX: using declaration ensures disposal
public string ReadFile(string path)
{
    using var reader = new StreamReader(path);
    return reader.ReadToEnd();
}
```

### Undisposed IDisposable Fields (CA2213)

```csharp
// BAD: _timer is never disposed
public class PollingService
{
    private readonly Timer _timer = new(Callback, null, TimeSpan.Zero, TimeSpan.FromSeconds(30));

    private static void Callback(object? state) { /* ... */ }
}

// FIX: implement IDisposable and dispose the field
public sealed class PollingService : IDisposable
{
    private readonly Timer _timer = new(Callback, null, TimeSpan.Zero, TimeSpan.FromSeconds(30));

    private static void Callback(object? state) { /* ... */ }

    public void Dispose() => _timer.Dispose();
}
```

### Canonical Dispose Pattern (for unsealed classes)

```csharp
public class ResourceHolder : IDisposable
{
    private SafeHandle? _handle;
    private bool _disposed;

    public void Dispose()
    {
        Dispose(disposing: true);
        GC.SuppressFinalize(this);  // CA1816
    }

    protected virtual void Dispose(bool disposing)
    {
        if (_disposed) return;

        if (disposing)
        {
            _handle?.Dispose();
        }

        _disposed = true;
    }
}
```

---

## 2. Warning Suppression Hacks

### CS0067: Event Never Used -- Suppression via Null Invoke (Motivating Example)

This is a real-world anti-pattern where a developer invokes an event with `null` arguments solely to suppress compiler warning CS0067 ("The event is never used").

```csharp
// BAD: invoking event with null to suppress CS0067
// Creates misleading runtime behavior -- subscribers receive null args
public class SuppressWarnings
{
    public event EventHandler<EventArgs> MyEvent;

    public SuppressWarnings()
    {
        // This "works" to suppress the warning but:
        // 1. Fires the event with null sender during construction
        // 2. Subscribers (if any) receive unexpected null args
        // 3. Masks the real issue: the event may be genuinely unused
        MyEvent?.Invoke(null, EventArgs.Empty);
    }
}
```

**Correct alternatives:**

```csharp
// FIX Option 1: #pragma warning disable (preferred when event is needed for interface compliance)
public class SuppressWarnings
{
#pragma warning disable CS0067 // Event is required by INotifyPropertyChanged but raised via helper
    public event EventHandler<EventArgs> MyEvent;
#pragma warning restore CS0067
}

// FIX Option 2: Explicit event accessors (preferred when event is a no-op by design)
public class SuppressWarnings
{
    public event EventHandler<EventArgs> MyEvent { add { } remove { } }
}

// FIX Option 3: If the event is truly unused, remove it entirely
```

---

## 3. LINQ Anti-Patterns

### Premature `.ToList()` Mid-Chain

```csharp
// BAD: materializes full list before filtering
var result = orders
    .ToList()           // forces full materialization
    .Where(o => o.IsActive)
    .Select(o => o.Id)
    .ToList();

// FIX: keep chain lazy, materialize only at the end
var result = orders
    .Where(o => o.IsActive)
    .Select(o => o.Id)
    .ToList();
```

### Multiple Enumeration of IEnumerable (CA1851)

```csharp
// BAD: enumerates the sequence twice
public void Process(IEnumerable<Order> orders)
{
    Console.WriteLine($"Count: {orders.Count()}");  // first enumeration
    foreach (var order in orders)                     // second enumeration
    {
        Handle(order);
    }
}

// FIX: materialize once
public void Process(IEnumerable<Order> orders)
{
    var orderList = orders.ToList();
    Console.WriteLine($"Count: {orderList.Count}");
    foreach (var order in orderList)
    {
        Handle(order);
    }
}
```

### Client-Side Evaluation in EF Core

```csharp
// BAD: CustomFormat() cannot be translated to SQL; entire table loaded into memory
var names = dbContext.Customers
    .Where(c => CustomFormat(c.Name).StartsWith("VIP"))
    .ToListAsync();

// FIX: use translatable expressions or filter after explicit load
var names = await dbContext.Customers
    .Where(c => c.Name.StartsWith("VIP"))  // translatable to SQL
    .ToListAsync();
```

---

## 4. Event Handling Leaks

### Not Unsubscribing from Events

```csharp
// BAD: subscriber never unsubscribes; publisher holds reference forever
public class Dashboard
{
    public Dashboard(OrderService service)
    {
        service.OrderCreated += OnOrderCreated;
        // If Dashboard is disposed but OrderService lives on,
        // Dashboard is never garbage collected
    }

    private void OnOrderCreated(object? sender, OrderEventArgs e) { /* ... */ }
}

// FIX: implement IDisposable and unsubscribe
public sealed class Dashboard : IDisposable
{
    private readonly OrderService _service;

    public Dashboard(OrderService service)
    {
        _service = service;
        _service.OrderCreated += OnOrderCreated;
    }

    private void OnOrderCreated(object? sender, OrderEventArgs e) { /* ... */ }

    public void Dispose()
    {
        _service.OrderCreated -= OnOrderCreated;
    }
}
```

### Async Void Event Handler Exception Handling

```csharp
// BAD: async void with no exception handling; crashes the process
private async void OnButtonClick(object? sender, EventArgs e)
{
    await ProcessOrderAsync();  // unhandled exception terminates app
}

// FIX: wrap in try/catch since async void exceptions are unobservable
private async void OnButtonClick(object? sender, EventArgs e)
{
    try
    {
        await ProcessOrderAsync();
    }
    catch (Exception ex)
    {
        _logger.LogError(ex, "Failed to process order on button click");
        // Show user-facing error or handle gracefully
    }
}
```

---

## 5. Async Exception Routing (Motivating Example)

### TryEnqueue with Async Lambda -- Exceptions Lost

This is a real-world anti-pattern where exceptions inside an async lambda are silently lost because they are not routed through a `TaskCompletionSource`.

```csharp
// BAD: exception inside async lambda is never observed
public Task<int> ComputeOnUiThreadAsync()
{
    var tcs = new TaskCompletionSource<int>();

    dispatcherQueue.TryEnqueue(async () =>
    {
        // If DoWorkAsync() throws, the exception is swallowed.
        // The tcs never completes -- caller hangs forever.
        var result = await DoWorkAsync();
        tcs.SetResult(result);
    });

    return tcs.Task;
}

// FIX: route exceptions through the TaskCompletionSource
public Task<int> ComputeOnUiThreadAsync()
{
    var tcs = new TaskCompletionSource<int>();

    dispatcherQueue.TryEnqueue(async () =>
    {
        try
        {
            var result = await DoWorkAsync();
            tcs.SetResult(result);
        }
        catch (OperationCanceledException)
        {
            tcs.TrySetCanceled();
        }
        catch (Exception ex)
        {
            tcs.TrySetException(ex);
        }
    });

    return tcs.Task;
}
```

Cross-reference: See `references/async-patterns.md` for broader async exception handling patterns.

---

## 6. Exception Handling Gaps

### Empty Catch Block

```csharp
// BAD: silently swallows all errors
try
{
    await SaveOrderAsync(order);
}
catch (Exception)
{
    // nothing -- caller thinks save succeeded
}

// FIX: at minimum log; preferably re-throw or return error
try
{
    await SaveOrderAsync(order);
}
catch (DbUpdateException ex)
{
    _logger.LogError(ex, "Failed to save order {OrderId}", order.Id);
    throw;  // let caller handle the failure
}
```

### `throw ex;` Resets Stack Trace (CA2200)

```csharp
// BAD: resets stack trace
catch (Exception ex)
{
    _logger.LogError(ex, "Operation failed");
    throw ex;  // CA2200: stack trace lost
}

// FIX: bare throw preserves stack trace
catch (Exception ex)
{
    _logger.LogError(ex, "Operation failed");
    throw;  // preserves original stack trace
}
```

### Throwing in Finally

```csharp
// BAD: exception in finally masks the original exception
try
{
    await ProcessAsync();
}
finally
{
    CleanupThatMayThrow();  // if this throws, original exception is lost
}

// FIX: guard the finally block
try
{
    await ProcessAsync();
}
finally
{
    try
    {
        CleanupThatMayThrow();
    }
    catch (Exception ex)
    {
        _logger.LogWarning(ex, "Cleanup failed; original exception preserved");
    }
}
```

---

## 7. Design Smells

### Long Parameter List -- Introduce Parameter Object

```csharp
// BAD: 7 parameters -- hard to call correctly, easy to swap arguments
public Order CreateOrder(
    string customerId, string productId, int quantity,
    decimal price, string currency, string shippingAddress,
    DateTime requestedDelivery)
{ /* ... */ }

// FIX: introduce a parameter object
public sealed record CreateOrderRequest(
    string CustomerId,
    string ProductId,
    int Quantity,
    decimal Price,
    string Currency,
    string ShippingAddress,
    DateTime RequestedDelivery);

public Order CreateOrder(CreateOrderRequest request) { /* ... */ }
```

### Deep Nesting -- Use Guard Clauses

```csharp
// BAD: deeply nested logic
public decimal CalculateDiscount(Order order)
{
    if (order != null)
    {
        if (order.Customer != null)
        {
            if (order.Customer.IsPremium)
            {
                if (order.Total > 100)
                {
                    return order.Total * 0.1m;
                }
            }
        }
    }
    return 0;
}

// FIX: guard clauses for early return
public decimal CalculateDiscount(Order order)
{
    if (order?.Customer is not { IsPremium: true })
    {
        return 0;
    }

    if (order.Total <= 100)
    {
        return 0;
    }

    return order.Total * 0.1m;
}
```
