# Testing Strategy

Decision framework for choosing the right test type, organizing test projects, and selecting test doubles in .NET applications. Covers unit vs integration vs E2E trade-offs with concrete criteria, naming conventions, and when to use mocks vs fakes vs stubs.

## Test Type Decision Tree

Use this decision tree to determine which test type fits a given scenario. Start at the top and follow the first matching criterion.

```
Does the code under test depend on external infrastructure?
  (database, HTTP service, file system, message broker)
|
+-- YES --> Is the infrastructure behavior critical to correctness?
|           |
|           +-- YES --> Does it need the full application stack (middleware, auth, routing)?
|           |           |
|           |           +-- YES --> E2E / Functional Test
|           |           |           (WebApplicationFactory or Playwright)
|           |           |
|           |           +-- NO  --> Integration Test
|           |                       (WebApplicationFactory or Testcontainers)
|           |
|           +-- NO  --> Unit Test with test doubles
|                        (mock the infrastructure boundary)
|
+-- NO  --> Is this pure logic (calculations, transformations, validation)?
            |
            +-- YES --> Unit Test (no test doubles needed)
            |
            +-- NO  --> Unit Test with test doubles
                        (mock collaborator interfaces)
```

### Concrete Criteria by Test Type

| Test Type | Infrastructure | Speed | Scope | When to Use |
|-----------|---------------|-------|-------|-------------|
| **Unit** | None (mocked/faked) | <10ms per test | Single class/method | Pure logic, domain rules, value objects, transformations, validators |
| **Integration** | Real (DB, HTTP) | 100ms-5s per test | Multiple components | Repository queries, API contract verification, serialization round-trips, middleware behavior |
| **E2E / Functional** | Full stack | 1-30s per test | Entire request pipeline | Critical user flows, auth + routing + middleware combined, cross-cutting concern verification |

### Cost-Benefit Guidance

- **Prefer unit tests** for business logic. They run fast, pinpoint failures precisely, and have no infrastructure requirements.
- **Use integration tests** to verify infrastructure boundaries work correctly. A repository unit test with a mocked `DbContext` proves nothing about actual SQL generation -- use a real database via Testcontainers.
- **Use E2E tests sparingly** for critical paths only. They are slow, brittle, and expensive to maintain. Cover the happy path and one or two critical failure scenarios.
- **The testing pyramid is a guideline, not a rule.** Some applications (CRUD APIs with minimal logic) benefit from more integration tests than unit tests. Match the strategy to the application's complexity profile.

---

## Test Organization

### Project Naming Convention

Mirror the `src/` project structure under `tests/` with a suffix indicating test type:

```
MyApp/
  src/
    MyApp.Domain/
    MyApp.Application/
    MyApp.Api/
    MyApp.Infrastructure/
  tests/
    MyApp.Domain.UnitTests/
    MyApp.Application.UnitTests/
    MyApp.Api.IntegrationTests/
    MyApp.Api.FunctionalTests/
    MyApp.Infrastructure.IntegrationTests/
```

- `*.UnitTests` -- isolated tests, no external dependencies
- `*.IntegrationTests` -- real infrastructure (database, HTTP, file system)
- `*.FunctionalTests` -- full application stack via `WebApplicationFactory`

See [skill:dotnet-testing] `references/add-testing.md` for creating these projects with proper package references and build configuration.

### Test Class Organization

One test class per production class. Place test files in a namespace that mirrors the production namespace:

```csharp
// Production: src/MyApp.Domain/Orders/OrderService.cs
// Test:       tests/MyApp.Domain.UnitTests/Orders/OrderServiceTests.cs
namespace MyApp.Domain.UnitTests.Orders;

public class OrderServiceTests
{
    // Group by method, then by scenario
}
```

For large production classes, split test classes by method:

```csharp
// OrderService_CreateTests.cs
// OrderService_CancelTests.cs
// OrderService_RefundTests.cs
```

---

## Test Naming Conventions

Use the `Method_Scenario_ExpectedBehavior` pattern. This reads naturally in test explorer output and makes failures self-documenting:

```csharp
public class OrderServiceTests
{
    [Fact]
    public void CalculateTotal_WithDiscountCode_AppliesPercentageDiscount()
    {
        // ...
    }

    [Fact]
    public void CalculateTotal_WithExpiredDiscount_ThrowsInvalidOperationException()
    {
        // ...
    }

    [Fact]
    public async Task SubmitOrder_WhenInventoryInsufficient_ReturnsOutOfStockError()
    {
        // ...
    }
}
```

Alternative naming styles (choose one per project and stay consistent):

| Style | Example |
|-------|---------|
| `Method_Scenario_Expected` | `CalculateTotal_EmptyCart_ReturnsZero` |
| `Should_Expected_When_Scenario` | `Should_ReturnZero_When_CartIsEmpty` |
| `Given_When_Then` | `GivenEmptyCart_WhenCalculatingTotal_ThenReturnsZero` |

---

## Arrange-Act-Assert Pattern

Every test follows the AAA structure. Keep each section clearly separated:

```csharp
[Fact]
public async Task CreateOrder_WithValidItems_PersistsAndReturnsOrder()
{
    // Arrange
    var repository = new FakeOrderRepository();
    var service = new OrderService(repository);
    var request = new CreateOrderRequest
    {
        CustomerId = "cust-123",
        Items = [new OrderItem("SKU-001", Quantity: 2, UnitPrice: 29.99m)]
    };

    // Act
    var result = await service.CreateAsync(request);

    // Assert
    Assert.NotNull(result);
    Assert.Equal("cust-123", result.CustomerId);
    Assert.Single(result.Items);
    Assert.True(repository.SavedOrders.ContainsKey(result.Id));
}
```

**Guideline:** If you cannot clearly label the three sections, the test may be doing too much. Split into multiple tests.

---

## Test Doubles: When to Use What

### Terminology

| Double Type | Behavior | State Verification | Use When |
|-------------|----------|-------------------|----------|
| **Stub** | Returns canned data | No | You need a dependency to return specific values so the code under test can proceed |
| **Mock** | Verifies interactions | Yes (interaction) | You need to verify that the code under test called a dependency in a specific way |
| **Fake** | Working implementation | Yes (state) | You need a lightweight but functional substitute (in-memory repository, in-memory message bus) |
| **Spy** | Records calls for later assertion | Yes (interaction) | You need to verify calls happened without prescribing them upfront |

### Decision Guidance

```
Do you need to verify HOW a dependency was called?
|
+-- YES --> Do you need a working implementation too?
|           |
|           +-- YES --> Spy (record calls on a fake)
|           +-- NO  --> Mock (NSubstitute / Moq)
|
+-- NO  --> Do you need the dependency to DO something realistic?
            |
            +-- YES --> Fake (in-memory implementation)
            +-- NO  --> Stub (return canned values)
```

### Example: Stub vs Mock vs Fake

```csharp
// STUB: Returns canned data -- verifying the code under test's logic
var priceService = Substitute.For<IPriceService>();
priceService.GetPriceAsync("SKU-001").Returns(29.99m);  // canned return

var total = await calculator.CalculateTotalAsync(items);
Assert.Equal(59.98m, total);  // assert on the result, not the call

// MOCK: Verifies interaction -- ensuring a side effect happened
var emailSender = Substitute.For<IEmailSender>();

await orderService.CompleteAsync(order);

await emailSender.Received(1).SendAsync(             // assert on the call
    Arg.Is<string>(to => to == order.CustomerEmail),
    Arg.Any<string>(),
    Arg.Any<string>());

// FAKE: In-memory implementation -- realistic behavior without infrastructure
public class FakeOrderRepository : IOrderRepository
{
    public Dictionary<Guid, Order> Orders { get; } = new();

    public Task<Order?> GetByIdAsync(Guid id, CancellationToken ct = default)
        => Task.FromResult(Orders.GetValueOrDefault(id));

    public Task SaveAsync(Order order, CancellationToken ct = default)
    {
        Orders[order.Id] = order;
        return Task.CompletedTask;
    }
}
```

### When to Prefer Fakes Over Mocks

- **Domain-heavy applications:** Fakes give more realistic behavior for complex interactions. An in-memory repository catches bugs that mocks miss (e.g., duplicate key violations).
- **Overuse of mocks is a test smell.** If a test has more mock setup than actual assertions, consider whether a fake would be clearer and more maintainable.
- **Integration boundaries are better tested with real infrastructure** via [skill:dotnet-testing] `references/integration-testing.md` than with mocks. A mocked `DbContext` does not verify that your LINQ translates to valid SQL.

---

## Testing Anti-Patterns

### 1. Testing Implementation Details

```csharp
// BAD: Breaks when refactoring internals
repository.Received(1).GetByIdAsync(Arg.Is<Guid>(id => id == orderId));
repository.Received(1).SaveAsync(Arg.Any<Order>());
// ... five more Received() calls verifying the exact call sequence

// GOOD: Test the observable outcome
var result = await service.ProcessAsync(orderId);
Assert.Equal(OrderStatus.Completed, result.Status);
```

### 2. Excessive Mock Setup

```csharp
// BAD: Mock setup is longer than the actual test
var repo = Substitute.For<IOrderRepository>();
var pricing = Substitute.For<IPricingService>();
var inventory = Substitute.For<IInventoryService>();
var shipping = Substitute.For<IShippingService>();
var notification = Substitute.For<INotificationService>();
var audit = Substitute.For<IAuditService>();
// ... 20 lines of .Returns() setup

// BETTER: Use a builder or fake that encapsulates setup
var fixture = new OrderServiceFixture()
    .WithOrder(testOrder)
    .WithPrice("SKU-001", 29.99m);
var result = await fixture.Service.ProcessAsync(testOrder.Id);
```

### 3. Non-Deterministic Tests

Tests must not depend on system clock, random values, or external network. Inject abstractions:

```csharp
// BAD: Uses DateTime.UtcNow directly
public bool IsExpired() => ExpiresAt < DateTime.UtcNow;

// GOOD: Inject TimeProvider (.NET 8+)
public bool IsExpired(TimeProvider time) => ExpiresAt < time.GetUtcNow();

// In test
var fakeTime = new FakeTimeProvider(new DateTimeOffset(2025, 6, 15, 0, 0, 0, TimeSpan.Zero));
Assert.True(order.IsExpired(fakeTime));
```

---

## Key Principles

- **Test behavior, not implementation.** Assert on observable outcomes (return values, state changes, published events), not internal method calls.
- **One logical assertion per test.** Multiple `Assert` calls are fine if they verify one logical concept (e.g., all properties of a returned object). Multiple unrelated assertions indicate the test should be split.
- **Keep tests independent.** No test should depend on another test's execution or ordering. Use fresh fixtures for each test.
- **Name tests so failures are self-documenting.** A failing test name should tell you what broke without reading the test body.
- **Match test type to risk.** High-risk code (payments, auth) deserves integration and E2E coverage. Low-risk code (simple mapping) needs only unit tests.
- **Use `TimeProvider` for time-dependent logic** (.NET 8+). It is the framework-provided abstraction; do not create custom `IClock` interfaces.

---

## Agent Gotchas

1. **Do not mock types you do not own.** Mocking `HttpClient`, `DbContext`, or framework types leads to brittle tests that do not reflect real behavior. Use `WebApplicationFactory` or Testcontainers instead -- see [skill:dotnet-testing] `references/integration-testing.md`.
2. **Do not create test projects without checking for existing structure.** Run [skill:dotnet-tooling] `references/project-analysis.md` first; duplicating test infrastructure causes build conflicts.
3. **Do not use `Thread.Sleep` in tests.** Use `Task.Delay` with a cancellation token, or better, use `FakeTimeProvider.Advance()` to control time deterministically.
4. **Do not test private methods directly.** If a private method needs its own tests, it should be extracted into its own class. Test through the public API.
5. **Do not hard-code connection strings in integration tests.** Use Testcontainers for disposable infrastructure or `WebApplicationFactory` for in-process testing -- see [skill:dotnet-testing] `references/integration-testing.md`.

---

## References

- [.NET Testing Best Practices](https://learn.microsoft.com/en-us/dotnet/core/testing/unit-testing-best-practices)
- [Unit testing C# with xUnit](https://learn.microsoft.com/en-us/dotnet/core/testing/unit-testing-with-dotnet-test)
- [Integration tests in ASP.NET Core](https://learn.microsoft.com/en-us/aspnet/core/test/integration-tests)
- [NSubstitute documentation](https://nsubstitute.github.io/help/getting-started/)
- [TimeProvider in .NET 8](https://learn.microsoft.com/en-us/dotnet/api/system.timeprovider)
