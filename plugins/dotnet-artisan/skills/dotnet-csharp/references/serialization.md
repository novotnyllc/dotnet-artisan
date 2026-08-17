# Serialization

AOT-friendly serialization patterns for .NET applications. Covers System.Text.Json source generators for compile-time serialization, Protocol Buffers (Protobuf) for efficient binary serialization, and MessagePack for high-performance compact binary format. Includes performance tradeoff guidance for choosing the right serializer and warnings about reflection-based serialization in AOT scenarios.

Cross-references: `references/source-generators.md` for understanding how STJ source generators work under the hood. See [skill:dotnet-testing] for testing serialization round-trip correctness.

---

## Serialization Format Comparison

| Format | Library | AOT-Safe | Human-Readable | Relative Size | Relative Speed | Best For |
|--------|---------|----------|----------------|---------------|----------------|----------|
| JSON | System.Text.Json (source gen) | Yes | Yes | Largest | Good | APIs, config, web clients |
| Protobuf | Google.Protobuf | Yes | No | Smallest | Fastest | Service-to-service, gRPC wire format |
| MessagePack | MessagePack-CSharp | Yes (with AOT resolver) | No | Small | Fast | High-throughput caching, real-time |
| JSON | Newtonsoft.Json | **No** (reflection) | Yes | Largest | Slower | **Legacy only -- do not use for AOT** |

### When to Choose What

- **System.Text.Json with source generators**: Default choice for APIs, configuration, and any scenario where human-readable output or web client consumption matters. AOT-safe when using source generators.
- **Protobuf**: Default wire format for gRPC. Best throughput and smallest payload size for service-to-service communication. Schema-first development with `.proto` files.
- **MessagePack**: When you need binary compactness without `.proto` schema management. Good for caching layers, real-time messaging, and high-throughput scenarios where schema evolution is managed via attributes.

---

## System.Text.Json Source Generators

System.Text.Json source generators produce compile-time serialization code, eliminating runtime reflection. This is **required** for Native AOT and strongly recommended for all new projects. See `references/source-generators.md` for the underlying incremental generator mechanics.

### Basic Setup

Define a `JsonSerializerContext` with `[JsonSerializable]` attributes for each type you serialize:

```csharp
using System.Text.Json.Serialization;

[JsonSerializable(typeof(Order))]
[JsonSerializable(typeof(List<Order>))]
[JsonSerializable(typeof(OrderStatus))]
public partial class AppJsonContext : JsonSerializerContext
{
}
```

### Using the Generated Context

```csharp
// Serialize
string json = JsonSerializer.Serialize(order, AppJsonContext.Default.Order);

// Deserialize
Order? result = JsonSerializer.Deserialize(json, AppJsonContext.Default.Order);

// With options (created once, reused)
var options = new JsonSerializerOptions
{
    PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
    TypeInfoResolver = AppJsonContext.Default
};

string json = JsonSerializer.Serialize(order, options);
```

### ASP.NET Core Integration

Register the source-generated context so Minimal APIs use it automatically. Note that `ConfigureHttpJsonOptions` applies to Minimal APIs only -- MVC controllers require separate configuration via `AddJsonOptions`:

```csharp
var builder = WebApplication.CreateBuilder(args);

// Minimal APIs: ConfigureHttpJsonOptions
builder.Services.ConfigureHttpJsonOptions(options =>
{
    options.SerializerOptions.TypeInfoResolverChain.Insert(0, AppJsonContext.Default);
});

// MVC Controllers: AddJsonOptions (if using controllers)
builder.Services.AddControllers()
    .AddJsonOptions(options =>
    {
        options.JsonSerializerOptions.TypeInfoResolverChain.Insert(0, AppJsonContext.Default);
    });

var app = builder.Build();

// Minimal API endpoints automatically use the registered context
app.MapGet("/orders/{id}", async (int id, OrderService service) =>
{
    var order = await service.GetAsync(id);
    return order is not null ? Results.Ok(order) : Results.NotFound();
});

app.MapPost("/orders", async (Order order, OrderService service) =>
{
    await service.CreateAsync(order);
    return Results.Created($"/orders/{order.Id}", order);
});
```

### Combining Multiple Contexts

When your application has multiple serialization contexts (e.g., different bounded contexts or libraries):

```csharp
builder.Services.ConfigureHttpJsonOptions(options =>
{
    options.SerializerOptions.TypeInfoResolver = JsonTypeInfoResolver.Combine(
        AppJsonContext.Default,
        CatalogJsonContext.Default,
        InventoryJsonContext.Default
    );
});
```

### Common Configuration

```csharp
[JsonSourceGenerationOptions(
    PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase,
    DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    WriteIndented = false)]
[JsonSerializable(typeof(Order))]
[JsonSerializable(typeof(List<Order>))]
public partial class AppJsonContext : JsonSerializerContext
{
}
```

### Handling Polymorphism

```csharp
[JsonDerivedType(typeof(CreditCardPayment), "credit_card")]
[JsonDerivedType(typeof(BankTransferPayment), "bank_transfer")]
[JsonDerivedType(typeof(WalletPayment), "wallet")]
public abstract class Payment
{
    public decimal Amount { get; init; }
    public string Currency { get; init; } = "USD";
}

public class CreditCardPayment : Payment
{
    public string Last4Digits { get; init; } = "";
}

// Register the base type -- derived types are discovered via attributes
[JsonSerializable(typeof(Payment))]
public partial class AppJsonContext : JsonSerializerContext
{
}
```

---

## Protobuf Serialization

Protocol Buffers provide schema-first binary serialization. Protobuf is the default wire format for gRPC and is AOT-safe.

### Package

```xml
<PackageReference Include="Google.Protobuf" Version="3.*" />
<PackageReference Include="Grpc.Tools" Version="2.*" PrivateAssets="All" />
```

### Proto File

```protobuf
syntax = "proto3";

import "google/protobuf/timestamp.proto";

option csharp_namespace = "MyApp.Contracts";

message OrderMessage {
  int32 id = 1;
  string customer_id = 2;
  repeated OrderItemMessage items = 3;
  google.protobuf.Timestamp created_at = 4;
}

message OrderItemMessage {
  string product_id = 1;
  int32 quantity = 2;
  double unit_price = 3;
}
```

### Standalone Protobuf (Without gRPC)

Use Protobuf for binary serialization without gRPC when you need compact payloads for caching, messaging, or file storage:

```csharp
using Google.Protobuf;

// Serialize to bytes
byte[] bytes = order.ToByteArray();

// Deserialize from bytes
var restored = OrderMessage.Parser.ParseFrom(bytes);

// Serialize to stream
using var stream = File.OpenWrite("order.bin");
order.WriteTo(stream);
```

### Proto File Registration in .csproj

```xml
<ItemGroup>
  <Protobuf Include="Protos\*.proto" GrpcServices="Both" />
</ItemGroup>
```

---

## MessagePack Serialization

MessagePack-CSharp provides high-performance binary serialization with smaller payloads than JSON and good .NET integration.

### Package

```xml
<PackageReference Include="MessagePack" Version="3.*" />
<!-- For AOT support -->
<PackageReference Include="MessagePack.SourceGenerator" Version="3.*" />
```

### Basic Usage with Source Generator (AOT-Safe)

```csharp
using MessagePack;

[MessagePackObject]
public partial class Order
{
    [Key(0)]
    public int Id { get; init; }

    [Key(1)]
    public string CustomerId { get; init; } = "";

    [Key(2)]
    public List<OrderItem> Items { get; init; } = [];

    [Key(3)]
    public DateTimeOffset CreatedAt { get; init; }
}
```

### Serialization

```csharp
// Serialize
byte[] bytes = MessagePackSerializer.Serialize(order);

// Deserialize
var restored = MessagePackSerializer.Deserialize<Order>(bytes);

// With compression (LZ4)
var lz4Options = MessagePackSerializerOptions.Standard.WithCompression(
    MessagePackCompression.Lz4BlockArray);
byte[] compressed = MessagePackSerializer.Serialize(order, lz4Options);
```

### AOT Resolver Setup

For Native AOT compatibility, use the MessagePack source generator to produce a resolver:

```csharp
// In your project, the source generator automatically produces a resolver
// from types annotated with [MessagePackObject].
// Register the generated resolver at startup:
MessagePackSerializer.DefaultOptions = MessagePackSerializerOptions.Standard
    .WithResolver(GeneratedResolver.Instance);
```

---

## Anti-Patterns: Reflection-Based Serialization

**Do not use reflection-based serializers in Native AOT or trimming scenarios.** Reflection-based serialization fails at runtime when the linker removes type metadata.

### Newtonsoft.Json (JsonConvert)

Newtonsoft.Json (`JsonConvert.SerializeObject` / `JsonConvert.DeserializeObject`) relies heavily on runtime reflection. It is **incompatible** with Native AOT and trimming:

```csharp
// BAD: Reflection-based -- fails under AOT/trimming
var json = JsonConvert.SerializeObject(order);
var order = JsonConvert.DeserializeObject<Order>(json);

// GOOD: Source-generated -- AOT-safe
var json = JsonSerializer.Serialize(order, AppJsonContext.Default.Order);
var order = JsonSerializer.Deserialize(json, AppJsonContext.Default.Order);
```

### System.Text.Json Without Source Generators

Even System.Text.Json falls back to reflection without a source-generated context:

```csharp
// BAD: No context -- uses runtime reflection
var json = JsonSerializer.Serialize(order);

// GOOD: Explicit context -- uses source-generated code
var json = JsonSerializer.Serialize(order, AppJsonContext.Default.Order);
```

### Migration Path from Newtonsoft.Json

1. Replace `JsonConvert.SerializeObject` / `DeserializeObject` with `JsonSerializer.Serialize` / `Deserialize`
2. Replace `[JsonProperty]` with `[JsonPropertyName]`
3. Replace `JsonConverter` base class with `JsonConverter<T>` from System.Text.Json
4. Create a `JsonSerializerContext` with `[JsonSerializable]` for all serialized types
5. Replace `JObject` / `JToken` dynamic access with `JsonDocument` / `JsonElement` or strongly-typed models
6. Test serialization round-trips -- attribute semantics differ between libraries

---

## Performance Guidance

### Throughput Benchmarks (Approximate)

| Format | Serialize (ops/sec) | Deserialize (ops/sec) | Payload Size |
|--------|--------------------|-----------------------|-------------|
| Protobuf | Highest | Highest | Smallest |
| MessagePack | High | High | Small |
| STJ Source Gen | Good | Good | Larger (text) |
| STJ Reflection | Moderate | Moderate | Larger (text) |
| Newtonsoft.Json | Lower | Lower | Larger (text) |

### Optimization Tips

- **Reuse `JsonSerializerOptions`** -- creating options is expensive; create once and reuse
- **Use `JsonSerializerContext`** -- eliminates warm-up cost and reduces allocation
- **Use `Utf8JsonWriter` / `Utf8JsonReader`** for streaming scenarios where you process JSON without full materialization
- **Use Protobuf `ByteString`** for binary data instead of base64-encoded strings in JSON
- **Enable MessagePack LZ4 compression** for large payloads over the wire

---

## Key Principles

- **Default to System.Text.Json with source generators** for all JSON serialization -- it is AOT-safe, fast, and built into the framework
- **Use Protobuf for service-to-service binary serialization** -- especially as the wire format for gRPC
- **Use MessagePack for high-throughput caching and real-time** -- when binary compactness matters but `.proto` schema management is unwanted
- **Never use Newtonsoft.Json for new AOT-targeted projects** -- it is reflection-based and incompatible with trimming
- **Always register `JsonSerializerContext` in ASP.NET Core** -- use `ConfigureHttpJsonOptions` for Minimal APIs and `AddJsonOptions` for MVC controllers (they are separate registrations)
- **Annotate all serialized types** -- STJ source generators only generate code for types listed in `[JsonSerializable]`; MessagePack requires `[MessagePackObject]`

---

## Agent Gotchas

1. **Do not use `JsonSerializer.Serialize(obj)` without a context in AOT projects** -- it falls back to reflection and fails at runtime. Always pass the source-generated `TypeInfo`.
2. **Do not forget to list collection types in `[JsonSerializable]`** -- `[JsonSerializable(typeof(Order))]` does not cover `List<Order>`. Add `[JsonSerializable(typeof(List<Order>))]` separately.
3. **Do not use Newtonsoft.Json `[JsonProperty]` attributes with System.Text.Json** -- they are silently ignored. Use `[JsonPropertyName]` instead.
4. **Do not mix MessagePack `[Key]` integer keys with `[Key]` string keys** in the same type hierarchy -- pick one strategy and stay consistent.
5. **Do not omit `GrpcServices` attribute on `<Protobuf>` items** -- without it, both client and server stubs are generated, which may cause build errors if you only need one.

---

## References

- [System.Text.Json source generation](https://learn.microsoft.com/en-us/dotnet/standard/serialization/system-text-json/source-generation)
- [Migrate from Newtonsoft.Json to System.Text.Json](https://learn.microsoft.com/en-us/dotnet/standard/serialization/system-text-json/migrate-from-newtonsoft)
- [Protocol Buffers for .NET](https://learn.microsoft.com/en-us/dotnet/architecture/grpc-for-wcf-developers/protobuf-data-types)
- [MessagePack-CSharp](https://github.com/MessagePack-CSharp/MessagePack-CSharp)
- [Native AOT deployment](https://learn.microsoft.com/en-us/dotnet/core/deploying/native-aot/)
