# AOT Architecture

AOT-first application design patterns for .NET 8+: preferring source generators over reflection, explicit DI registration over assembly scanning, AOT-safe serialization choices, library compatibility assessment, and factory patterns replacing `Activator.CreateInstance`.

**Version assumptions:** .NET 8.0+ baseline. Patterns apply to all AOT-capable project types (console, ASP.NET Core Minimal APIs, worker services).

## Source Generators Over Reflection

The primary AOT enabler is replacing runtime reflection with compile-time source generation. Source generators produce code at build time that the AOT compiler can analyze and include.

### Key Source Generator Replacements

| Reflection Pattern | Source Generator / AOT-Safe Alternative | Library |
|-------------------|---------------------------------------|---------|
| `JsonSerializer.Deserialize<T>()` | `[JsonSerializable]` context | System.Text.Json (built-in) |
| `Activator.CreateInstance<T>()` | Factory pattern with explicit `new` | Manual |
| `Type.GetProperties()` for mapping | `[Mapper]` attribute | Mapperly |
| `Regex` pattern compilation | `[GeneratedRegex]` attribute | Built-in (.NET 7+) |
| `ILogger.Log(...)` with string interpolation | `[LoggerMessage]` attribute | Microsoft.Extensions.Logging |
| Assembly scanning for DI | Explicit `services.Add*()` | Manual |
| `[DllImport]` P/Invoke | `[LibraryImport]` | Built-in (.NET 7+) |
| AutoMapper `CreateMap<>()` | `[Mapper]` source gen | Mapperly |

### Example: Migrating to Source Gen

```csharp
// BEFORE: Reflection-based (breaks under AOT)
var logger = loggerFactory.CreateLogger<OrderService>();
logger.LogInformation("Order {OrderId} created for {Customer}", order.Id, order.CustomerId);

// AFTER: Source-generated (AOT-safe, zero-alloc)
public partial class OrderService
{
    [LoggerMessage(Level = LogLevel.Information,
        Message = "Order {OrderId} created for {Customer}")]
    private static partial void LogOrderCreated(
        ILogger logger, int orderId, string customer);
}

// Usage:
LogOrderCreated(_logger, order.Id, order.CustomerId);
```

See [skill:dotnet-csharp] for source generator mechanics and authoring patterns.


## AOT-Safe DI Patterns

Dependency injection in AOT requires explicit service registration. Assembly scanning (`AddServicesFromAssembly`) and open-generic resolution may require reflection that AOT cannot satisfy.

### Explicit Registration (Preferred)

```csharp
var builder = WebApplication.CreateSlimBuilder(args);

// Explicit registrations -- AOT-safe
builder.Services.AddSingleton<IOrderRepository, PostgresOrderRepository>();
builder.Services.AddScoped<IOrderService, OrderService>();
builder.Services.AddTransient<IEmailSender, SmtpEmailSender>();
builder.Services.AddSingleton(TimeProvider.System);
```

### Avoid Assembly Scanning

```csharp
// BAD: Assembly scanning uses reflection -- breaks under AOT
builder.Services.Scan(scan => scan
    .FromAssemblyOf<OrderService>()
    .AddClasses(classes => classes.AssignableTo<IService>())
    .AsImplementedInterfaces()
    .WithScopedLifetime());

// GOOD: Explicit registrations grouped by concern
builder.Services.AddOrderServices();
builder.Services.AddInventoryServices();

// Extension method groups related registrations
public static class OrderServiceExtensions
{
    public static IServiceCollection AddOrderServices(
        this IServiceCollection services)
    {
        services.AddScoped<IOrderService, OrderService>();
        services.AddScoped<IOrderRepository, PostgresOrderRepository>();
        services.AddScoped<IOrderValidator, OrderValidator>();
        return services;
    }
}
```

### Keyed Services (.NET 8+)

```csharp
// AOT-safe keyed service registration
builder.Services.AddKeyedSingleton<INotificationSender, EmailSender>("email");
builder.Services.AddKeyedSingleton<INotificationSender, SmsSender>("sms");

// Resolve by key
app.MapPost("/notify", ([FromKeyedServices("email")] INotificationSender sender) =>
    sender.SendAsync("Hello"));
```

See [skill:dotnet-csharp] for full DI patterns.


## Serialization Choices for AOT

### Decision Matrix

| Serializer | AOT-Safe | Setup Required | Best For |
|-----------|----------|---------------|----------|
| System.Text.Json + source gen | Yes | `[JsonSerializable]` context | APIs, config, JSON interop |
| Protobuf (Google.Protobuf) | Yes | `.proto` schema files | gRPC, service-to-service |
| MessagePack + source gen | Yes | `[MessagePackObject]` + source gen resolver | Caching, real-time |
| Newtonsoft.Json | **No** | N/A | **Do not use for AOT** |
| STJ without source gen | **No** | N/A | **Falls back to reflection** |

### STJ Source Gen Setup

```csharp
// Define serializable types
[JsonSerializable(typeof(Product))]
[JsonSerializable(typeof(List<Product>))]
[JsonSourceGenerationOptions(
    PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase)]
internal partial class AppJsonContext : JsonSerializerContext { }

// Register in ASP.NET Core
builder.Services.ConfigureHttpJsonOptions(options =>
{
    options.SerializerOptions.TypeInfoResolverChain.Insert(0,
        AppJsonContext.Default);
});
```

See [skill:dotnet-csharp] for comprehensive serialization patterns.


## Factory Patterns Replacing Activator.CreateInstance

`Activator.CreateInstance` uses runtime reflection to create instances and is incompatible with AOT. Replace with factory patterns that use explicit construction.

### Simple Factory

```csharp
// BAD: Reflection-based creation -- breaks under AOT
public T CreateHandler<T>() where T : class
    => (T)Activator.CreateInstance(typeof(T))!;

// GOOD: Factory with explicit registration
public class HandlerFactory
{
    private readonly Dictionary<Type, Func<IHandler>> _factories = new();

    public void Register<T>(Func<T> factory) where T : IHandler
        => _factories[typeof(T)] = () => factory();

    public IHandler Create<T>() where T : IHandler
        => _factories[typeof(T)]();
}

// Registration
var factory = new HandlerFactory();
factory.Register<OrderHandler>(() => new OrderHandler(repository, logger));
factory.Register<PaymentHandler>(() => new PaymentHandler(gateway));
```

### Strategy Pattern via DI

```csharp
// BAD: Dynamic type resolution
public IPaymentProcessor GetProcessor(string type)
{
    var processorType = Type.GetType($"MyApp.Payments.{type}Processor");
    return (IPaymentProcessor)Activator.CreateInstance(processorType!)!;
}

// GOOD: Keyed services (.NET 8+)
builder.Services.AddKeyedScoped<IPaymentProcessor, CreditCardProcessor>("CreditCard");
builder.Services.AddKeyedScoped<IPaymentProcessor, BankTransferProcessor>("BankTransfer");
builder.Services.AddKeyedScoped<IPaymentProcessor, WalletProcessor>("Wallet");

// Resolve at runtime without reflection
app.MapPost("/pay", (
    [FromQuery] string type,
    IServiceProvider sp) =>
{
    var processor = sp.GetRequiredKeyedService<IPaymentProcessor>(type);
    return processor.ProcessAsync();
});
```

### Enum-Based Factory

```csharp
// For a fixed set of types, use a switch expression
public static IExporter CreateExporter(ExportFormat format) => format switch
{
    ExportFormat.Csv => new CsvExporter(),
    ExportFormat.Json => new JsonExporter(),
    ExportFormat.Pdf => new PdfExporter(),
    _ => throw new ArgumentOutOfRangeException(nameof(format))
};
```


## Library Compatibility Assessment

### Assessment Checklist

Before adopting a NuGet package in an AOT project:

1. **Check for `IsAotCompatible` in the package source** -- packages that set this are validated against AOT analyzers
2. **Check for `[RequiresDynamicCode]` / `[RequiresUnreferencedCode]` annotations** -- these indicate AOT-incompatible APIs
3. **Run AOT analyzers against your usage** -- `dotnet build /p:EnableAotAnalyzer=true`
4. **Check the package's GitHub issues for AOT/trimming reports** -- search for "Native AOT", "trimming", "IL2026", "IL3050"
5. **Look for source-generated alternatives** -- many reflection-based libraries now have source-gen companions

### Common Library Status

| Library | AOT Status | AOT-Safe Alternative |
|---------|-----------|---------------------|
| AutoMapper | Breaks | Mapperly |
| MediatR | Partial (explicit registration) | Direct method calls or factory |
| FluentValidation | Partial | Manual validation or source gen |
| Dapper | Compatible (.NET 8+ AOT support) | -- |
| Entity Framework Core | Partial (precompiled queries) | Dapper for AOT-heavy paths |
| Refit | Compatible (7+ with source gen) | -- |
| Polly | Compatible (v8+) | -- |
| Serilog | Partial | `[LoggerMessage]` source gen |
| Hangfire | Breaks | Custom `IHostedService` |

### Testing Compatibility

```bash
# Build with all analyzers enabled
dotnet build /p:EnableAotAnalyzer=true /p:EnableTrimAnalyzer=true /p:TrimmerSingleWarn=false

# Warnings indicate AOT-incompatible usage
# IL3050 = RequiresDynamicCode (definitely breaks)
# IL2026 = RequiresUnreferencedCode (may break)
```


## AOT Application Architecture Template

```
src/
  MyApp/
    Program.cs                   # CreateSlimBuilder, explicit DI
    MyApp.csproj                 # PublishAot=true, EnableAotAnalyzer=true
    JsonContext.cs               # [JsonSerializable] for all API types
    Endpoints/
      OrderEndpoints.cs          # Minimal API route groups
      ProductEndpoints.cs
    Services/
      OrderService.cs            # Business logic (no reflection)
      IOrderService.cs
    Repositories/
      OrderRepository.cs         # Data access (Dapper or EF precompiled)
    Extensions/
      ServiceCollectionExtensions.cs  # Grouped DI registrations
```


## Agent Gotchas

1. **Do not use `Activator.CreateInstance` in AOT projects.** It requires runtime reflection that is not available. Use factory patterns, DI keyed services, or switch expressions instead.
2. **Do not use assembly scanning for DI registration** (`Scan`, `RegisterAssemblyTypes`, `FromAssemblyOf`). These use reflection to discover types at runtime. Register services explicitly.
3. **Do not use `System.Text.Json` without a `[JsonSerializable]` context in AOT.** Without a source-generated context, STJ falls back to reflection and fails at runtime.
4. **Do not assume a library is AOT-compatible without testing.** Run `dotnet build /p:EnableAotAnalyzer=true` and check for IL3050/IL2026 warnings against your specific usage.
5. **Do not use `Type.GetType()` or `Assembly.GetTypes()` for runtime discovery.** These rely on metadata that may be trimmed. Use compile-time known types.


## References

- [Native AOT deployment](https://learn.microsoft.com/en-us/dotnet/core/deploying/native-aot/)
- [Source generation in .NET](https://learn.microsoft.com/en-us/dotnet/csharp/roslyn-sdk/source-generators-overview)
- [System.Text.Json source generation](https://learn.microsoft.com/en-us/dotnet/standard/serialization/system-text-json/source-generation)
- [LoggerMessage source generation](https://learn.microsoft.com/en-us/dotnet/core/extensions/logger-message-generator)
- [Mapperly object mapper](https://mapperly.riok.app/)
- [Prepare .NET libraries for trimming](https://learn.microsoft.com/en-us/dotnet/core/deploying/trimming/prepare-libraries-for-trimming)
