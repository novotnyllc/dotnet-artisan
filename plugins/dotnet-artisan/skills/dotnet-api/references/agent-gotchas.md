# Agent Gotchas

Common mistakes AI agents make when generating or modifying .NET code, organized by category. Each category provides a brief warning, anti-pattern code, corrected code, and a cross-reference to the canonical skill that owns the deep guidance. This skill does NOT provide full implementation walkthroughs -- it surfaces the mistake and points to the right skill.

## Prerequisites

.NET 8.0+ SDK. Familiarity with SDK-style projects and C# language features.


---

## Category 1: Async/Await Misuse

**Warning:** Agents frequently block on async methods using `.Result` or `.Wait()`, causing deadlocks in ASP.NET Core and UI contexts. Another common mistake is fire-and-forget calls that silently swallow exceptions.

### Anti-Pattern

```csharp
// WRONG: blocking on async -- deadlock risk in synchronization contexts
public Order GetOrder(int id)
{
    var order = _repository.GetOrderAsync(id).Result; // DEADLOCK
    return order;
}

// WRONG: fire-and-forget with no error handling
public void ProcessOrder(Order order)
{
    _ = _emailService.SendConfirmationAsync(order); // exception silently lost
}
```

### Corrected

```csharp
// CORRECT: async all the way
public async Task<Order> GetOrderAsync(int id, CancellationToken ct = default)
{
    var order = await _repository.GetOrderAsync(id, ct);
    return order;
}

// CORRECT: background work via IHostedService or explicit error handling
public async Task ProcessOrderAsync(Order order, CancellationToken ct = default)
{
    await _emailService.SendConfirmationAsync(order, ct);
}
```

See [skill:dotnet-csharp] for full async/await guidance including `ValueTask`, `ConfigureAwait`, and cancellation propagation.

---

## Category 2: NuGet Package Errors

**Warning:** Agents generate incorrect package names, reference pre-release versions without opt-in, or add packages that have been deprecated/replaced. ASP.NET Core shared-framework packages must match the project TFM major version.

### Anti-Pattern

```xml
<!-- WRONG: package name does not exist (correct: Microsoft.EntityFrameworkCore) -->
<PackageReference Include="EntityFrameworkCore" Version="9.0.0" />

<!-- WRONG: hardcoded version for shared-framework package -- must match TFM -->
<PackageReference Include="Microsoft.AspNetCore.Mvc.Testing" Version="9.0.0" />
<!-- This breaks on net8.0 projects -->

<!-- WRONG: agents add Swashbuckle by default; .NET 9+ templates use built-in OpenAPI -->
<PackageReference Include="Swashbuckle.AspNetCore" Version="7.0.0" />
<!-- Swashbuckle is still valid when Swagger UI is needed, but not the default choice -->
```

### Corrected

```xml
<!-- CORRECT: exact package ID -->
<PackageReference Include="Microsoft.EntityFrameworkCore" Version="9.0.0" />

<!-- CORRECT: use version variable or central package management to match TFM -->
<PackageReference Include="Microsoft.AspNetCore.Mvc.Testing" />
<!-- Version managed via Directory.Packages.props matching project TFM -->

<!-- CORRECT: .NET 9+ templates prefer built-in OpenAPI support -->
<PackageReference Include="Microsoft.AspNetCore.OpenApi" Version="9.0.0" />
<!-- Swashbuckle remains a valid choice when Swagger UI features are needed -->
```

See [skill:dotnet-tooling] for project file conventions and central package management guidance.

---

## Category 3: Deprecated API Usage

**Warning:** Agents generate code using deprecated and insecure APIs: `BinaryFormatter` (CVE-prone deserialization), `WebClient` (replaced by `HttpClient`), and older cryptography APIs (`RNGCryptoServiceProvider`, `SHA1CryptoServiceProvider`).

### Anti-Pattern

```csharp
// WRONG: BinaryFormatter is banned in .NET 8+ (SYSLIB0011)
var formatter = new BinaryFormatter();
formatter.Serialize(stream, data);

// WRONG: WebClient is obsolete -- use HttpClient via IHttpClientFactory
var client = new WebClient();
var html = client.DownloadString("https://example.com");

// WRONG: obsolete crypto API (SYSLIB0023)
using var rng = new RNGCryptoServiceProvider();
rng.GetBytes(buffer);
```

### Corrected

```csharp
// CORRECT: use System.Text.Json for serialization
var json = JsonSerializer.Serialize(data);
await File.WriteAllTextAsync("data.json", json);

// CORRECT: use IHttpClientFactory (registered via DI)
public class MyService(HttpClient httpClient)
{
    public async Task<string> GetHtmlAsync(CancellationToken ct = default)
        => await httpClient.GetStringAsync("https://example.com", ct);
}

// CORRECT: modern RandomNumberGenerator (static API)
RandomNumberGenerator.Fill(buffer);
```

See [skill:dotnet-api] for the full deprecated security pattern catalog and OWASP mitigations.

---

## Category 4: Project Structure Mistakes

**Warning:** Agents use wrong SDK types, add `PackageReference` entries for framework-included libraries, or create broken `ProjectReference` paths.

### Anti-Pattern

```xml
<!-- WRONG: using Microsoft.NET.Sdk for a web project -->
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net9.0</TargetFramework>
  </PropertyGroup>
  <!-- Missing WebApplication APIs, Kestrel, etc. -->
</Project>

<!-- WRONG: referencing a package already in the shared framework -->
<PackageReference Include="Microsoft.Extensions.Logging" Version="9.0.0" />
<!-- This is included in Microsoft.NET.Sdk.Web; explicit reference causes version conflicts -->

<!-- WRONG: relative path that doesn't match actual project location -->
<ProjectReference Include="..\..\Core\MyApp.Core.csproj" />
<!-- Actual location is ../MyApp.Core/MyApp.Core.csproj -->
```

### Corrected

```xml
<!-- CORRECT: use the Web SDK for ASP.NET Core projects -->
<Project Sdk="Microsoft.NET.Sdk.Web">
  <PropertyGroup>
    <TargetFramework>net9.0</TargetFramework>
  </PropertyGroup>
</Project>

<!-- CORRECT: don't add explicit PackageReference for shared-framework packages -->
<!-- Microsoft.Extensions.Logging is implicitly available via Sdk.Web -->

<!-- CORRECT: verify the actual project path before adding a reference -->
<ProjectReference Include="..\MyApp.Core\MyApp.Core.csproj" />
```

See [skill:dotnet-tooling] for SDK types, project organization, and project reference conventions.

---

## Category 5: Nullable Reference Type Annotation Errors

**Warning:** Agents misuse the null-forgiving operator (`!`) to silence warnings instead of fixing nullability, or forget to enable the nullable context.

### Anti-Pattern

```csharp
// WRONG: null-forgiving operator hides a real null risk
public string GetUserName(int id)
{
    var user = _db.Users.Find(id);
    return user!.Name; // NullReferenceException if user not found
}

// WRONG: nullable not enabled, so annotations are meaningless
// Missing <Nullable>enable</Nullable> in .csproj
public string? GetOptionalValue() => null; // no compiler warnings without nullable context
```

### Corrected

```csharp
// CORRECT: handle null explicitly
public string GetUserName(int id)
{
    var user = _db.Users.Find(id);
    if (user is null)
    {
        throw new InvalidOperationException($"User {id} not found.");
    }

    return user.Name;
}
```

```xml
<!-- CORRECT: enable nullable context in .csproj -->
<PropertyGroup>
  <Nullable>enable</Nullable>
</PropertyGroup>
```

See [skill:dotnet-csharp] for full NRT usage patterns and annotation strategies.

---

## Category 6: Source Generator Misconfiguration

**Warning:** Agents forget to mark classes as `partial` when source generators need to augment them, or use incorrect output types that prevent generator output from compiling.

### Anti-Pattern

```csharp
// WRONG: missing partial keyword -- source generator cannot augment this class
[JsonSerializable(typeof(WeatherForecast))]
internal class WeatherJsonContext : JsonSerializerContext
{
}

// WRONG: generator expects a class but agent declared a struct
[LoggerMessage(EventId = 1, Level = LogLevel.Information, Message = "Processing {Item}")]
public static partial struct LogMessages // struct is invalid for LoggerMessage
{
}
```

### Corrected

```csharp
// CORRECT: partial class allows source generator to emit companion code
[JsonSerializable(typeof(WeatherForecast))]
internal partial class WeatherJsonContext : JsonSerializerContext
{
}

// CORRECT: LoggerMessage requires partial method in a partial class
public static partial class Log
{
    [LoggerMessage(EventId = 1, Level = LogLevel.Information, Message = "Processing {Item}")]
    public static partial void ProcessingItem(ILogger logger, string item);
}
```

See [skill:dotnet-csharp] for source generator configuration, diagnostics, and debugging.

---

## Category 7: Trimming/AOT Warning Suppression

**Warning:** Agents suppress trimming and AOT warnings with `#pragma` or `[UnconditionalSuppressMessage]` instead of fixing the underlying reflection/dynamic usage. Suppression hides runtime failures in published apps.

### Anti-Pattern

```csharp
// WRONG: suppressing trim warning instead of fixing it
#pragma warning disable IL2026
var type = Type.GetType(typeName); // reflection not trim-safe
var instance = Activator.CreateInstance(type!);
#pragma warning restore IL2026

// WRONG: app-level suppression in .csproj hides all trim warnings
// <NoWarn>IL2026;IL2046;IL3050</NoWarn>
```

### Corrected

```csharp
// CORRECT: use compile-time type resolution or [DynamicallyAccessedMembers]
public T CreateInstance<T>() where T : new()
{
    return new T(); // no reflection, trim-safe
}

// For unavoidable reflection, annotate correctly:
public object CreateInstance(
    [DynamicallyAccessedMembers(DynamicallyAccessedMemberTypes.PublicConstructors)] Type type)
{
    return Activator.CreateInstance(type)
        ?? throw new InvalidOperationException($"Cannot create {type.Name}");
}
```

```xml
<!-- CORRECT: enable trim/AOT analyzers to catch issues early -->
<!-- For apps: -->
<PublishTrimmed>true</PublishTrimmed>
<EnableTrimAnalyzer>true</EnableTrimAnalyzer>
<!-- For libraries: -->
<IsTrimmable>true</IsTrimmable>
<!-- IsTrimmable auto-enables trim analyzer for libraries -->
```

See [skill:dotnet-tooling] for MSBuild property guidance on trimming and AOT configuration.

---

## Category 8: Test Organization Anti-Patterns

**Warning:** Agents put test classes in production projects, use wrong test SDK configurations, or mix test framework attributes incorrectly.

### Anti-Pattern

```csharp
// WRONG: test class in the production project (not in a separate test project)
// File: src/MyApp.Api/OrderServiceTests.cs
namespace MyApp.Api;

public class OrderServiceTests
{
    [Fact] // xUnit attribute in production code -- ships test dependencies to users
    public void CalculateTotal_ReturnsCorrectSum() { }
}
```

```xml
<!-- WRONG: test project missing Microsoft.NET.Test.Sdk and runner -->
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net9.0</TargetFramework>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="xunit.v3" Version="3.2.2" />
    <!-- Missing Microsoft.NET.Test.Sdk and runner -- dotnet test will find zero tests -->
  </ItemGroup>
</Project>
```

### Corrected

```xml
<!-- CORRECT: test project in tests/ directory with proper configuration -->
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net9.0</TargetFramework>
    <IsTestProject>true</IsTestProject>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="xunit.v3" Version="3.2.2" />
    <PackageReference Include="xunit.runner.visualstudio" Version="3.1.5" />
    <PackageReference Include="Microsoft.NET.Test.Sdk" Version="18.0.1" />
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="..\..\src\MyApp.Api\MyApp.Api.csproj" />
  </ItemGroup>
</Project>
```

See [skill:dotnet-testing] for test organization, naming conventions, and test type decision guidance.

---

## Category 9: DI Registration Errors

**Warning:** Agents forget to register services, use wrong lifetimes (singleton capturing scoped), or create captive dependencies that cause memory leaks and concurrency bugs.

### Anti-Pattern

```csharp
// WRONG: scoped service injected into singleton -- captive dependency
builder.Services.AddSingleton<OrderProcessor>(); // singleton
builder.Services.AddScoped<IOrderRepository, OrderRepository>(); // scoped

public class OrderProcessor(IOrderRepository repo) // repo is captured as singleton!
{
    public async Task ProcessAsync(int orderId, CancellationToken ct)
    {
        var order = await repo.GetByIdAsync(orderId, ct); // same DbContext forever
    }
}

// WRONG: missing registration causes runtime exception
// builder.Services.AddScoped<IOrderRepository, OrderRepository>(); // forgot this line
// InvalidOperationException: Unable to resolve service for type 'IOrderRepository'
```

### Corrected

```csharp
// CORRECT: lifetimes must not capture shorter-lived dependencies
builder.Services.AddScoped<OrderProcessor>(); // scoped, matches repository lifetime
builder.Services.AddScoped<IOrderRepository, OrderRepository>();

// Or if OrderProcessor must be singleton, inject IServiceScopeFactory:
builder.Services.AddSingleton<OrderProcessor>();

public class OrderProcessor(IServiceScopeFactory scopeFactory)
{
    public async Task ProcessAsync(int orderId, CancellationToken ct)
    {
        await using var scope = scopeFactory.CreateAsyncScope();
        var repo = scope.ServiceProvider.GetRequiredService<IOrderRepository>();
        var order = await repo.GetByIdAsync(orderId, ct);
    }
}
```

See [skill:dotnet-csharp] for lifetime rules, registration patterns, and service scope management.

---

## Slopwatch Anti-Patterns

These are patterns that indicate an agent is hiding problems rather than fixing them. Every code review should check for these. See [skill:dotnet-testing] for the automated quality gate that detects these patterns.

### 1. Disabled or Skipped Tests

```csharp
// RED FLAG: skipping tests to make the build pass
[Fact(Skip = "Flaky, will fix later")] // test never gets fixed
public void CriticalBusinessLogic_WorksCorrectly() { }

// RED FLAG: commenting out failing tests
// [Fact]
// public void CalculateTotal_HandlesNegative() { ... }

// RED FLAG: conditional compilation to hide tests
#if false
[Fact]
public void ImportantEdgeCase() { }
#endif
```

**Fix:** Investigate and fix the underlying issue. If a test is genuinely flaky due to timing, use `[Retry]` (xUnit v3) or fix the non-determinism. Never disable tests to achieve a green build.

### 2. Warning Suppressions

```csharp
// RED FLAG: blanket warning suppression
#pragma warning disable CS8600, CS8602, CS8604 // suppress all nullability warnings
var result = GetData();
result.Process();
#pragma warning restore CS8600, CS8602, CS8604

// RED FLAG: project-level suppression hiding real issues
// <NoWarn>CS8618;CS8625;IL2026</NoWarn>
```

**Fix:** Address the underlying nullability or trim issues. Add proper null checks, use nullable annotations correctly, or apply `[DynamicallyAccessedMembers]` for trim warnings.

### 3. Empty Catch Blocks

```csharp
// RED FLAG: swallowing exceptions silently
try
{
    await _service.ProcessAsync(data, ct);
}
catch (Exception) { } // failure is invisible

// RED FLAG: catch-and-ignore with misleading comment
catch (Exception ex)
{
    // TODO: add logging
}
```

**Fix:** At minimum, log the exception. Prefer catching specific exception types and handling them appropriately.

### 4. Silenced Analyzers Without Justification

```csharp
// RED FLAG: suppressing analyzer with no explanation
[SuppressMessage("Design", "CA1062")]
public void Process(string input) { }

// RED FLAG: disabling analyzer rules in .editorconfig globally
// dotnet_diagnostic.CA1062.severity = none
```

**Fix:** Fix the code to satisfy the analyzer rule, or provide a documented justification in the suppression attribute: `[SuppressMessage("Design", "CA1062", Justification = "Input validated by middleware")]`.

### 5. Removed Assertions from Tests

```csharp
// RED FLAG: test with no assertions -- always passes
[Fact]
public async Task CreateOrder_Succeeds()
{
    var service = new OrderService();
    await service.CreateOrderAsync(new Order());
    // no Assert -- this test proves nothing
}
```

**Fix:** Every test must have at least one assertion that validates the expected behavior. If the test is for side effects, assert on the side effect (database state, published events, log output).

---

## Cross-References

- [skill:dotnet-csharp] -- async/await deep patterns, `ValueTask`, cancellation
- [skill:dotnet-csharp] -- DI lifetime rules, registration patterns, scope management
- [skill:dotnet-csharp] -- NRT annotations, nullable context, flow analysis
- [skill:dotnet-csharp] -- generator configuration, partial class requirements, diagnostics
- [skill:dotnet-testing] -- test type decisions, organization, naming conventions
- [skill:dotnet-api] -- OWASP mitigations, deprecated security API catalog

## References

- [Common .NET Compiler Errors](https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/compiler-messages/)
- [.NET Trimming Warnings](https://learn.microsoft.com/en-us/dotnet/core/deploying/trimming/fixing-warnings)
- [NuGet Package Reference](https://learn.microsoft.com/en-us/nuget/consume-packages/package-references-in-project-files)
- [Dependency Injection Lifetime Guidelines](https://learn.microsoft.com/en-us/dotnet/core/extensions/dependency-injection-guidelines)
