# Snapshot Testing

Snapshot (approval) testing with the Verify library for .NET. Covers verifying API responses, serialized objects, rendered emails, and other complex outputs by comparing them against approved baseline files. Includes scrubbing and filtering patterns to handle non-deterministic values (dates, GUIDs, timestamps), custom converters for domain-specific types, and strategies for organizing and reviewing snapshot files.

**Version assumptions:** Verify 20.x+ (.NET 8.0+ baseline). Examples use the `Verify.Xunit` integration package; equivalent packages exist for NUnit (`Verify.NUnit`) and MSTest (`Verify.MSTest`). Verify auto-discovers the test framework from the referenced package.

## Setup

### Packages

```xml
<PackageReference Include="Verify.Xunit" Version="20.*" />
<!-- For HTTP response verification -->
<PackageReference Include="Verify.Http" Version="6.*" />
```

### Module Initializer

Verify requires a one-time initialization per test assembly. Place this in a file at the root of your test project:

```csharp
// ModuleInitializer.cs
using System.Runtime.CompilerServices;

public static class ModuleInitializer
{
    [ModuleInitializer]
    public static void Init() =>
        VerifySourceGenerators.Initialize();
}
```

### Source Control

Add to `.gitignore`:

```gitignore
# Verify received files (test failures)
*.received.*
```

Add to `.gitattributes` so verified files diff cleanly:

```gitattributes
*.verified.txt text eol=lf
*.verified.xml text eol=lf
*.verified.json text eol=lf
```

---

## Basic Usage

### Verifying Objects

Verify serializes the object to JSON and compares against a `.verified.txt` file:

```csharp
[UsesVerify]
public class OrderSerializationTests
{
    [Fact]
    public Task Serialize_CompletedOrder_MatchesSnapshot()
    {
        var order = new Order
        {
            Id = 1,
            CustomerId = "cust-123",
            Status = OrderStatus.Completed,
            Items =
            [
                new OrderItem("SKU-001", Quantity: 2, UnitPrice: 29.99m),
                new OrderItem("SKU-002", Quantity: 1, UnitPrice: 49.99m)
            ],
            Total = 109.97m
        };

        return Verify(order);
    }
}
```

First run creates `OrderSerializationTests.Serialize_CompletedOrder_MatchesSnapshot.verified.txt`:

```txt
{
  Id: 1,
  CustomerId: cust-123,
  Status: Completed,
  Items: [
    {
      Sku: SKU-001,
      Quantity: 2,
      UnitPrice: 29.99
    },
    {
      Sku: SKU-002,
      Quantity: 1,
      UnitPrice: 49.99
    }
  ],
  Total: 109.97
}
```

### Verifying Strings and Streams

```csharp
[Fact]
public Task RenderInvoice_MatchesExpectedHtml()
{
    var html = invoiceRenderer.Render(order);
    return Verify(html, extension: "html");
}

[Fact]
public Task ExportReport_MatchesExpectedXml()
{
    var stream = reportExporter.Export(report);
    return Verify(stream, extension: "xml");
}
```

---

## Scrubbing and Filtering

Non-deterministic values (dates, GUIDs, auto-incremented IDs) change between test runs. Scrubbing replaces them with stable placeholders so snapshots remain comparable.

### Built-In Scrubbers

Verify includes scrubbers for common non-deterministic types that are active by default:

```csharp
[Fact]
public Task CreateOrder_ScrubsNonDeterministicValues()
{
    var order = new Order
    {
        Id = Guid.NewGuid(),          // Scrubbed to Guid_1
        CreatedAt = DateTime.UtcNow,  // Scrubbed to DateTime_1
        TrackingNumber = Guid.NewGuid().ToString() // Scrubbed to Guid_2
    };

    return Verify(order);
}
```

Produces stable output:

```txt
{
  Id: Guid_1,
  CreatedAt: DateTime_1,
  TrackingNumber: Guid_2
}
```

### Custom Scrubbers

When built-in scrubbing is not sufficient, add custom scrubbers:

```csharp
[Fact]
public Task AuditLog_ScrubsTimestampsAndMachineNames()
{
    var log = auditService.GetRecentEntries();

    return Verify(log)
        .ScrubLinesWithReplace(line =>
            Regex.Replace(line, @"Machine:\s+\w+", "Machine: Scrubbed"))
        .ScrubLinesContaining("CorrelationId:");
}
```

### Ignoring Members

Exclude specific properties from verification:

```csharp
[Fact]
public Task OrderSnapshot_IgnoresVolatileFields()
{
    var order = orderService.CreateOrder(request);

    return Verify(order)
        .IgnoreMember("CreatedAt")
        .IgnoreMember("UpdatedAt")
        .IgnoreMember("ETag");
}
```

Or ignore by type across all verifications:

```csharp
// In ModuleInitializer
[ModuleInitializer]
public static void Init()
{
    VerifierSettings.IgnoreMembersWithType<DateTime>();
    VerifierSettings.IgnoreMembersWithType<DateTimeOffset>();
}
```

### Scrubbing Inline Values

Replace specific patterns in the serialized output:

```csharp
[Fact]
public Task ApiResponse_ScrubsTokens()
{
    var response = authService.GenerateTokenResponse(user);

    return Verify(response)
        .ScrubLinesWithReplace(line =>
            Regex.Replace(line, @"Bearer [A-Za-z0-9\-._~+/]+=*", "Bearer {scrubbed}"));
}
```

---

## Verifying HTTP Responses

Verify HTTP responses from WebApplicationFactory integration tests to lock down API contracts.

### Setup

```xml
<PackageReference Include="Verify.Http" Version="6.*" />
```

### Verifying Full HTTP Responses

```csharp
[UsesVerify]
public class OrdersApiSnapshotTests : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly HttpClient _client;

    public OrdersApiSnapshotTests(WebApplicationFactory<Program> factory)
    {
        _client = factory.CreateClient();
    }

    [Fact]
    public async Task GetOrders_ResponseMatchesSnapshot()
    {
        var response = await _client.GetAsync("/api/orders");

        await Verify(response);
    }
}
```

The verified file captures status code, headers, and body:

```txt
{
  Status: 200 OK,
  Headers: {
    Content-Type: application/json; charset=utf-8
  },
  Body: [
    {
      Id: 1,
      CustomerId: cust-123,
      Status: Pending,
      Total: 109.97
    }
  ]
}
```

### Verifying Specific Response Parts

```csharp
[Fact]
public async Task CreateOrder_VerifyResponseBody()
{
    var response = await _client.PostAsJsonAsync("/api/orders", request);
    var body = await response.Content.ReadFromJsonAsync<OrderDto>();

    await Verify(body)
        .IgnoreMember("Id")
        .IgnoreMember("CreatedAt");
}
```

---

## Verifying Rendered Emails

Snapshot-test email templates by verifying the rendered HTML output:

```csharp
[UsesVerify]
public class EmailTemplateTests
{
    private readonly EmailRenderer _renderer = new();

    [Fact]
    public Task OrderConfirmation_MatchesSnapshot()
    {
        var model = new OrderConfirmationModel
        {
            CustomerName = "Alice Johnson",
            OrderNumber = "ORD-001",
            Items =
            [
                new("Widget A", Quantity: 2, Price: 29.99m),
                new("Widget B", Quantity: 1, Price: 49.99m)
            ],
            Total = 109.97m
        };

        var html = _renderer.RenderOrderConfirmation(model);

        return Verify(html, extension: "html");
    }

    [Fact]
    public Task PasswordReset_MatchesSnapshot()
    {
        var model = new PasswordResetModel
        {
            UserName = "alice",
            ResetLink = "https://example.com/reset?token=test-token"
        };

        var html = _renderer.RenderPasswordReset(model);

        return Verify(html, extension: "html")
            .ScrubLinesWithReplace(line =>
                Regex.Replace(line, @"token=[^""&]+", "token={scrubbed}"));
    }
}
```

---

## Custom Converters

Custom converters control how specific types are serialized for verification. Use them for domain types that need a readable, stable representation.

### Writing a Custom Converter

```csharp
public class MoneyConverter : WriteOnlyJsonConverter<Money>
{
    public override void Write(VerifyJsonWriter writer, Money value)
    {
        writer.WriteStartObject();
        writer.WriteMember(value, value.Amount, "Amount");
        writer.WriteMember(value, value.Currency.Code, "Currency");
        writer.WriteEndObject();
    }
}
```

Register in the module initializer:

```csharp
[ModuleInitializer]
public static void Init()
{
    VerifierSettings.AddExtraSettings(settings =>
        settings.Converters.Add(new MoneyConverter()));
}
```

### Converter for Complex Domain Types

```csharp
public class AddressConverter : WriteOnlyJsonConverter<Address>
{
    public override void Write(VerifyJsonWriter writer, Address value)
    {
        // Single-line summary for compact snapshots
        writer.WriteValue($"{value.Street}, {value.City}, {value.State} {value.Zip}");
    }
}

public class DateRangeConverter : WriteOnlyJsonConverter<DateRange>
{
    public override void Write(VerifyJsonWriter writer, DateRange value)
    {
        writer.WriteStartObject();
        writer.WriteMember(value, value.Start.ToString("yyyy-MM-dd"), "Start");
        writer.WriteMember(value, value.End.ToString("yyyy-MM-dd"), "End");
        writer.WriteMember(value, value.Duration.Days, "DurationDays");
        writer.WriteEndObject();
    }
}
```

Usage in tests:

```csharp
[Fact]
public Task Customer_WithAddress_MatchesSnapshot()
{
    var customer = new Customer
    {
        Name = "Alice Johnson",
        Address = new Address("123 Main St", "Springfield", "IL", "62701"),
        MemberSince = new DateRange(
            new DateTime(2020, 1, 15),
            new DateTime(2025, 1, 15))
    };

    return Verify(customer);
}
```

Produces:

```txt
{
  Name: Alice Johnson,
  Address: 123 Main St, Springfield, IL 62701,
  MemberSince: {
    Start: 2020-01-15,
    End: 2025-01-15,
    DurationDays: 1827
  }
}
```

---

## Snapshot File Organization

### Default Naming

Verify names snapshot files based on the test class and method:

```
TestClassName.MethodName.verified.txt
```

Files are placed next to the test source file by default.

### Unique Directory

Move verified files into a dedicated directory to reduce clutter:

```csharp
// ModuleInitializer.cs
[ModuleInitializer]
public static void Init()
{
    Verifier.DerivePathInfo(
        (sourceFile, projectDirectory, type, method) =>
            new PathInfo(
                directory: Path.Combine(projectDirectory, "Snapshots"),
                typeName: type.Name,
                methodName: method.Name));
}
```

### Parameterized Tests

For `[Theory]` tests, Verify appends parameter values to the file name:

```csharp
[Theory]
[InlineData("en-US")]
[InlineData("de-DE")]
[InlineData("ja-JP")]
public Task FormatCurrency_ByLocale_MatchesSnapshot(string locale)
{
    var formatted = currencyFormatter.Format(1234.56m, locale);
    return Verify(formatted)
        .UseParameters(locale);
}
```

Creates separate files:

```
FormatCurrencyTests.FormatCurrency_ByLocale_MatchesSnapshot_locale=en-US.verified.txt
FormatCurrencyTests.FormatCurrency_ByLocale_MatchesSnapshot_locale=de-DE.verified.txt
FormatCurrencyTests.FormatCurrency_ByLocale_MatchesSnapshot_locale=ja-JP.verified.txt
```

---

## Workflow: Accepting Changes

When a snapshot test fails, Verify creates a `.received.txt` file alongside the `.verified.txt` file. Review the diff and accept or reject:

### Diff Tool Integration

Verify launches a diff tool automatically when a test fails. Configure the preferred tool:

```csharp
[ModuleInitializer]
public static void Init()
{
    // Verify auto-detects installed diff tools
    // Override if needed:
    DiffTools.UseOrder(DiffTool.VisualStudioCode, DiffTool.Rider);
}
```

### CLI Acceptance

Install the Verify CLI tool (one-time setup), then accept pending changes after review:

```bash
# Install the Verify CLI tool (one-time)
dotnet tool install -g verify.tool

# Accept all received files in the solution
verify accept

# Accept for a specific test project
verify accept --project tests/MyApp.Tests
```

### CI Behavior

In CI, Verify should fail tests without launching a diff tool. Set the environment variable:

```yaml
env:
  DiffEngine_Disabled: true
```

Or in the module initializer:

```csharp
[ModuleInitializer]
public static void Init()
{
    if (Environment.GetEnvironmentVariable("CI") is not null)
    {
        DiffRunner.Disabled = true;
    }
}
```

---

## Key Principles

- **Snapshot test complex outputs, not simple values.** If the expected value fits in a single `Assert.Equal`, prefer that over a snapshot. Snapshots shine for multi-field objects, API responses, and rendered content.
- **Scrub all non-deterministic values.** Dates, GUIDs, timestamps, and machine-specific values must be scrubbed or ignored. Unscrubbed snapshots cause flaky tests.
- **Commit `.verified.txt` files to source control.** These are the approved baselines. Never add `.received.txt` files -- they represent unapproved changes.
- **Review snapshot diffs carefully.** Accepting a snapshot change without review can silently approve regressions. Treat snapshot diffs like code review.
- **Use custom converters for domain readability.** Default JSON serialization may be verbose or unclear for domain types. Converters produce focused, human-readable snapshots.
- **Keep snapshots focused.** Verify only the parts that matter. Use `IgnoreMember` to exclude volatile or irrelevant fields rather than verifying the entire object graph.

---

## Agent Gotchas

1. **Do not forget `[UsesVerify]` on the test class.** Without this attribute, `Verify()` calls compile but fail at runtime with an initialization error. Every test class using Verify must have this attribute.
2. **Do not commit `.received.txt` files.** These represent test failures and unapproved changes. Add `*.received.*` to `.gitignore` to prevent accidental commits.
3. **Do not skip `UseParameters()` in parameterized tests.** Without it, all parameter combinations write to the same snapshot file, overwriting each other. Always call `UseParameters()` with the theory data values.
4. **Do not scrub values that are part of the contract.** If an API always returns a specific date format or a known GUID, verify those values rather than scrubbing them. Only scrub values that are genuinely non-deterministic between runs.
5. **Do not use snapshot testing for rapidly evolving APIs.** During early development when the API shape changes frequently, snapshot tests create excessive churn. Wait until the API stabilizes.
6. **Do not hardcode Verify package versions across different test frameworks.** `Verify.Xunit`, `Verify.NUnit`, and `Verify.MSTest` have independent version lines. Always use version ranges (e.g., `20.*`) rather than pinning to a specific version.

---

## References

- [Verify GitHub repository](https://github.com/VerifyTests/Verify)
- [Verify documentation](https://github.com/VerifyTests/Verify/blob/main/docs/readme.md)
- [Verify.Http for HTTP response testing](https://github.com/VerifyTests/Verify.Http)
- [Scrubbing and filtering](https://github.com/VerifyTests/Verify/blob/main/docs/scrubbers.md)
- [Custom converters](https://github.com/VerifyTests/Verify/blob/main/docs/converters.md)
- [DiffEngine (diff tool integration)](https://github.com/VerifyTests/DiffEngine)
