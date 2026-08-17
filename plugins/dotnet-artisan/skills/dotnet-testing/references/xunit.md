# xUnit

xUnit v3 testing framework features for .NET. Covers `[Fact]` and `[Theory]` attributes, test fixtures (`IClassFixture`, `ICollectionFixture`), parallel execution configuration, `IAsyncLifetime` for async setup/teardown, custom assertions, and xUnit analyzers.

**Version assumptions:** xUnit v3 primary (.NET 8.0+ baseline). Where v3 behavior differs from v2, compatibility notes are provided inline.

## Facts and Theories

### `[Fact]` -- Single Test Case

Use `[Fact]` for tests with no parameters:

```csharp
public class DiscountCalculatorTests
{
    [Fact]
    public void Apply_NegativePercentage_ThrowsArgumentOutOfRangeException()
    {
        var calculator = new DiscountCalculator();

        var ex = Assert.Throws<ArgumentOutOfRangeException>(
            () => calculator.Apply(100m, percentage: -5));

        Assert.Equal("percentage", ex.ParamName);
    }
}
```

### `[Theory]` -- Parameterized Tests

Use `[Theory]` to run the same test logic with different inputs.

#### `[InlineData]`

Best for simple value types:

```csharp
[Theory]
[InlineData(100, 10, 90)]
[InlineData(200, 25, 150)]
[InlineData(50, 0, 50)]
public void Apply_VariousInputs_ReturnsExpectedPrice(
    decimal price, decimal percentage, decimal expected)
{
    var calculator = new DiscountCalculator();
    Assert.Equal(expected, calculator.Apply(price, percentage));
}
```

#### `[MemberData]` with `TheoryData<T>`

Best for complex data or shared datasets:

```csharp
public class OrderValidatorTests
{
    public static TheoryData<Order, bool> ValidationCases => new()
    {
        { new Order { Items = [new("SKU-1", 1)], CustomerId = "C1" }, true },
        { new Order { Items = [], CustomerId = "C1" }, false },
    };

    [Theory]
    [MemberData(nameof(ValidationCases))]
    public void IsValid_VariousOrders_ReturnsExpected(Order order, bool expected)
    {
        Assert.Equal(expected, new OrderValidator().IsValid(order));
    }
}
```

#### `[ClassData]` (xUnit v3)

For data shared across multiple test classes. v3 uses `TheoryDataRow<T>` for strongly-typed rows (v2 used `IEnumerable<object[]>`):

```csharp
public class CurrencyConversionData : IEnumerable<TheoryDataRow<string, string, decimal>>
{
    public IEnumerator<TheoryDataRow<string, string, decimal>> GetEnumerator()
    {
        yield return new("USD", "EUR", 0.92m);
        yield return new("GBP", "USD", 1.27m);
    }
    IEnumerator IEnumerable.GetEnumerator() => GetEnumerator();
}

[Theory]
[ClassData(typeof(CurrencyConversionData))]
public void Convert_KnownPairs_ReturnsExpectedRate(
    string from, string to, decimal expectedRate)
{
    Assert.Equal(expectedRate, new CurrencyConverter().GetRate(from, to), precision: 2);
}
```

---

## Fixtures: Shared Setup and Teardown

### `IClassFixture<T>` -- Shared Per Test Class

Use when multiple tests in the same class share an expensive resource:

```csharp
public class DatabaseFixture : IAsyncLifetime
{
    public string ConnectionString { get; private set; } = "";

    // xUnit v3: IAsyncLifetime returns ValueTask (v2 returns Task)
    public ValueTask InitializeAsync()
    {
        ConnectionString = $"Host=localhost;Database=test_{Guid.NewGuid():N}";
        return ValueTask.CompletedTask;
    }

    public ValueTask DisposeAsync() => ValueTask.CompletedTask;
}

public class OrderRepositoryTests : IClassFixture<DatabaseFixture>
{
    private readonly DatabaseFixture _db;
    public OrderRepositoryTests(DatabaseFixture db) => _db = db;

    [Fact]
    public async Task GetById_ExistingOrder_ReturnsOrder()
    {
        var repo = new OrderRepository(_db.ConnectionString);
        Assert.NotNull(await repo.GetByIdAsync(KnownOrderId));
    }
}
```

### `ICollectionFixture<T>` -- Shared Across Test Classes

Use when multiple test classes need the same expensive resource:

```csharp
[CollectionDefinition("Database")]
public class DatabaseCollection : ICollectionFixture<DatabaseFixture> { }

[Collection("Database")]
public class OrderRepositoryTests(DatabaseFixture db)
{
    [Fact]
    public async Task Insert_ValidOrder_Persists() { /* uses db */ }
}

[Collection("Database")]
public class CustomerRepositoryTests(DatabaseFixture db) { }
```

---

## Parallel Execution

xUnit runs test classes within a collection sequentially but runs different collections in parallel. Each test class without an explicit `[Collection]` is its own implicit collection.

### Disable Parallelism for Specific Tests

```csharp
[CollectionDefinition("Sequential", DisableParallelization = true)]
public class SequentialCollection { }

[Collection("Sequential")]
public class StatefulServiceTests { /* runs sequentially */ }
```

### Assembly-Level Configuration

Create `xunit.runner.json` in the test project root (copy to output via `<Content Include="xunit.runner.json" CopyToOutputDirectory="PreserveNewest" />`):

```json
{
    "$schema": "https://xunit.net/schema/current/xunit.runner.schema.json",
    "parallelizeAssembly": false,
    "parallelizeTestCollections": true,
    "maxParallelThreads": 4
}
```

---

## Custom Assertions and Assert.Multiple

Create domain-specific assertions for cleaner test code:

```csharp
public static class OrderAssert
{
    public static void HasStatus(Order order, OrderStatus expected)
    {
        Assert.NotNull(order);
        if (order.Status != expected)
            throw Xunit.Sdk.EqualException.ForMismatchedValues(expected, order.Status);
    }
}
```

Use `Assert.Multiple` (xUnit v3 only) to evaluate all assertions even if one fails:

```csharp
[Fact]
public void CreateOrder_ValidRequest_SetsAllProperties()
{
    var order = OrderFactory.Create(request);
    Assert.Multiple(
        () => Assert.Equal("cust-123", order.CustomerId),
        () => Assert.Equal(OrderStatus.Pending, order.Status),
        () => Assert.NotEqual(Guid.Empty, order.Id)
    );
}
```

---

## xUnit Analyzers

The `xunit.analyzers` package (included with xUnit v3) catches common mistakes at compile time. Key rules:

| Rule | What it catches |
|------|----------------|
| `xUnit1025` | Duplicate `[InlineData]` within a `[Theory]` |
| `xUnit2000` | Constants should be the expected (first) argument in `Assert.Equal` |
| `xUnit2013` | Do not use equality check to verify collection size (use `Assert.Single`, `Assert.Empty`) |

Suppress per-project in `.editorconfig`:
```ini
[tests/**.cs]
dotnet_diagnostic.xUnit1004.severity = suggestion
```

---

## Key Principles

- **One fact per `[Fact]`, one concept per `[Theory]`.** Split fundamentally different scenarios into separate methods.
- **Use `IClassFixture` for expensive shared resources** within a class, `ICollectionFixture` when multiple classes share the same resource.
- **Do not disable parallelism globally.** Group tests sharing mutable state into named collections instead.
- **Use `IAsyncLifetime` for async setup/teardown** instead of constructors and `IDisposable`.
- **Keep test data close to the test.** Prefer `[InlineData]` for simple cases, `[MemberData]`/`[ClassData]` only when data is complex or shared.

---

## Agent Gotchas

1. **Do not use constructor-injected `ITestOutputHelper` in static methods.** It is per-test-instance; store in an instance field.
2. **Fixture classes must be `public` with a public parameterless constructor** (or `IAsyncLifetime`). Non-public fixtures cause silent failures.
3. **Do not mix `[Fact]` and `[Theory]` on the same method.** A method is either a fact or a theory.
4. **Async test methods must return `Task` or `ValueTask`, never `async void`.** `async void` tests report false success.
5. **`[Collection]` without a matching `[CollectionDefinition]`** silently creates an implicit collection with default behavior.

---

## References

- [xUnit Documentation](https://xunit.net/)
- [xUnit v3 migration guide](https://xunit.net/docs/getting-started/v3/migration)
- [xUnit analyzers](https://xunit.net/xunit.analyzers/rules/)
- [Shared context in xUnit](https://xunit.net/docs/shared-context)
