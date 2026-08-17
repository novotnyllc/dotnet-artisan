# gRPC

Full gRPC lifecycle for .NET applications. Covers `.proto` service definition, code generation, ASP.NET Core gRPC server implementation and endpoint hosting, `Grpc.Net.Client` client patterns, all four streaming patterns (unary, server streaming, client streaming, bidirectional streaming), authentication, load balancing, and health checks.

For detailed code examples (server implementation, client patterns, streaming, auth, interceptors, gRPC-Web), see the "Detailed Examples" section below.

## Proto Definition and Code Generation

### Project Setup

gRPC uses Protocol Buffers as its interface definition language. The `Grpc.Tools` package generates C# code from `.proto` files at build time.

**Server project:**

```xml
<ItemGroup>
  <PackageReference Include="Grpc.AspNetCore" Version="2.*" />
  <PackageReference Include="Google.Protobuf" Version="3.*" />
  <PackageReference Include="Grpc.Tools" Version="2.*" PrivateAssets="All" />
</ItemGroup>

<ItemGroup>
  <Protobuf Include="Protos\*.proto" GrpcServices="Server" />
</ItemGroup>
```

**Client project:**

```xml
<ItemGroup>
  <PackageReference Include="Google.Protobuf" Version="3.*" />
  <PackageReference Include="Grpc.Net.Client" Version="2.*" />
  <PackageReference Include="Grpc.Tools" Version="2.*" PrivateAssets="All" />
</ItemGroup>

<ItemGroup>
  <Protobuf Include="Protos\*.proto" GrpcServices="Client" />
</ItemGroup>
```

For shared contracts projects, set `GrpcServices="Both"` to generate both server and client stubs.

### Proto File Definition

```protobuf
syntax = "proto3";

option csharp_namespace = "MyApp.Grpc";

package myapp;

import "google/protobuf/timestamp.proto";
import "google/protobuf/empty.proto";

// Service definition with all 4 streaming patterns
service OrderService {
  rpc GetOrder (GetOrderRequest) returns (OrderResponse);
  rpc ListOrders (ListOrdersRequest) returns (stream OrderResponse);
  rpc UploadOrders (stream CreateOrderRequest) returns (UploadOrdersResponse);
  rpc ProcessOrders (stream CreateOrderRequest) returns (stream OrderResponse);
}

message GetOrderRequest {
  int32 id = 1;
}

message ListOrdersRequest {
  string customer_id = 1;
  int32 page_size = 2;
  string page_token = 3;
}

message CreateOrderRequest {
  string customer_id = 1;
  repeated OrderItemMessage items = 2;
}

message OrderResponse {
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

message UploadOrdersResponse {
  int32 orders_created = 1;
}
```

### Code-Gen Workflow

The `Grpc.Tools` package runs the Protobuf compiler (`protoc`) and C# gRPC plugin at build time. Generated files appear in `obj/` and are included automatically:

1. Add `.proto` files to the project via `<Protobuf>` items
2. Set `GrpcServices` to `Server`, `Client`, or `Both`
3. Build the project -- generated C# types and service stubs appear in `obj/Debug/net10.0/Protos/`
4. Implement the generated abstract base class (server) or use the generated client class

The gRPC code-gen toolchain uses source generation to produce the C# stubs from `.proto` definitions. This is conceptually similar to [skill:dotnet-csharp] but uses `protoc` rather than Roslyn incremental generators.

---

## Streaming Patterns Summary

gRPC supports four communication patterns:

| Pattern | Request | Response | Use Case |
|---------|---------|----------|----------|
| **Unary** | Single message | Single message | Standard request-response (CRUD, queries) |
| **Server streaming** | Single message | Stream of messages | Real-time feeds, large result sets, push notifications |
| **Client streaming** | Stream of messages | Single message | Bulk uploads, aggregation, telemetry ingestion |
| **Bidirectional streaming** | Stream of messages | Stream of messages | Chat, real-time collaboration, event processing |

---

## Status Codes

Map domain errors to gRPC status codes:

| gRPC Status | HTTP Equivalent | Use When |
|-------------|----------------|----------|
| `OK` | 200 | Success |
| `NotFound` | 404 | Resource does not exist |
| `InvalidArgument` | 400 | Client sent bad data |
| `PermissionDenied` | 403 | Caller lacks permission |
| `Unauthenticated` | 401 | No valid credentials |
| `AlreadyExists` | 409 | Duplicate creation attempt |
| `ResourceExhausted` | 429 | Rate limited |
| `Internal` | 500 | Unhandled server error |
| `Unavailable` | 503 | Transient failure -- safe to retry |
| `DeadlineExceeded` | 504 | Operation timed out |

---

## gRPC-Web Limitations

- **Unary and server streaming only** -- client streaming and bidirectional streaming are not supported
- **CORS required** -- cross-origin requests need explicit CORS configuration on the server
- **Consider SignalR for full-duplex browser communication** -- see [skill:dotnet-api] for alternatives

---

## Key Principles

- **Use `.proto` files as the contract** -- they are the single source of truth for the API shape, shared between client and server
- **Set `GrpcServices` on `<Protobuf>` items** -- `Server` for service projects, `Client` for consumer projects, `Both` for shared contracts
- **Register gRPC clients via DI** -- `AddGrpcClient` integrates with `IHttpClientFactory` for connection pooling and resilience
- **Always set deadlines** -- calls without deadlines can hang indefinitely if the server is slow or unreachable
- **Use L7 load balancers** -- L4 load balancers pin all traffic to one backend because HTTP/2 multiplexes on a single TCP connection
- **Implement the gRPC health check protocol** -- enables Kubernetes probes and load balancers to monitor service health

See [skill:dotnet-tooling] for Native AOT compilation pipeline and AOT-compatible patterns when building gRPC services.

---

## Agent Gotchas

1. **Do not omit `GrpcServices` on `<Protobuf>` items** -- the default is `Both`, which bloats client projects with unused server code and vice versa.
2. **Do not throw generic `Exception` from gRPC services** -- throw `RpcException` with appropriate `StatusCode`. Unhandled exceptions become `StatusCode.Internal` with no useful detail.
3. **Do not forget to call `CompleteAsync()` on client streams** -- the server waits for stream completion before sending its response. Forgetting this causes the call to hang.
4. **Do not enable gRPC-Web globally without CORS** -- `UseGrpcWeb()` without a CORS policy allows any origin to call your gRPC services. Always pair with explicit `RequireCors()`.
5. **Do not attempt client streaming or bidirectional streaming with gRPC-Web** -- the gRPC-Web protocol only supports unary and server streaming.

---

## Attribution

Adapted from [Aaronontheweb/dotnet-skills](https://github.com/Aaronontheweb/dotnet-skills) (MIT license).

---

## References

- [gRPC for .NET overview](https://learn.microsoft.com/en-us/aspnet/core/grpc/?view=aspnetcore-10.0)
- [gRPC client factory integration](https://learn.microsoft.com/en-us/aspnet/core/grpc/clientfactory?view=aspnetcore-10.0)
- [gRPC services with ASP.NET Core](https://learn.microsoft.com/en-us/aspnet/core/grpc/aspnetcore?view=aspnetcore-10.0)
- [gRPC-Web for .NET](https://learn.microsoft.com/en-us/aspnet/core/grpc/grpcweb?view=aspnetcore-10.0)
- [Protocol Buffers language guide](https://protobuf.dev/programming-guides/proto3/)

---

# gRPC -- Detailed Examples

Extended code examples for gRPC server implementation, client patterns, streaming, authentication, load balancing, health checks, interceptors, error handling, deadlines, and gRPC-Web.

---

## ASP.NET Core gRPC Server

### Service Implementation

Implement the generated abstract base class:

```csharp
using Grpc.Core;
using MyApp.Grpc;

public sealed class OrderGrpcService(
    OrderRepository repository,
    ILogger<OrderGrpcService> logger) : OrderService.OrderServiceBase
{
    // Unary
    public override async Task<OrderResponse> GetOrder(
        GetOrderRequest request,
        ServerCallContext context)
    {
        var order = await repository.GetByIdAsync(request.Id, context.CancellationToken);
        if (order is null)
        {
            throw new RpcException(new Status(StatusCode.NotFound,
                $"Order {request.Id} not found"));
        }

        return MapToResponse(order);
    }

    // Server streaming
    public override async Task ListOrders(
        ListOrdersRequest request,
        IServerStreamWriter<OrderResponse> responseStream,
        ServerCallContext context)
    {
        await foreach (var order in repository.ListByCustomerAsync(
            request.CustomerId, context.CancellationToken))
        {
            await responseStream.WriteAsync(MapToResponse(order),
                context.CancellationToken);
        }
    }

    // Client streaming
    public override async Task<UploadOrdersResponse> UploadOrders(
        IAsyncStreamReader<CreateOrderRequest> requestStream,
        ServerCallContext context)
    {
        var count = 0;
        await foreach (var request in requestStream.ReadAllAsync(
            context.CancellationToken))
        {
            await repository.CreateAsync(MapFromRequest(request),
                context.CancellationToken);
            count++;
        }

        return new UploadOrdersResponse { OrdersCreated = count };
    }

    // Bidirectional streaming
    public override async Task ProcessOrders(
        IAsyncStreamReader<CreateOrderRequest> requestStream,
        IServerStreamWriter<OrderResponse> responseStream,
        ServerCallContext context)
    {
        await foreach (var request in requestStream.ReadAllAsync(
            context.CancellationToken))
        {
            var order = await repository.CreateAsync(MapFromRequest(request),
                context.CancellationToken);
            await responseStream.WriteAsync(MapToResponse(order),
                context.CancellationToken);
        }
    }

    private static OrderResponse MapToResponse(Order order) =>
        new()
        {
            Id = order.Id,
            CustomerId = order.CustomerId,
            CreatedAt = Google.Protobuf.WellKnownTypes.Timestamp.FromDateTimeOffset(
                order.CreatedAt)
        };

    private static Order MapFromRequest(CreateOrderRequest request) =>
        new()
        {
            CustomerId = request.CustomerId,
            Items = request.Items.Select(i => new OrderItem
            {
                ProductId = i.ProductId,
                Quantity = i.Quantity,
                UnitPrice = (decimal)i.UnitPrice
            }).ToList()
        };
}
```

### Endpoint Hosting

```csharp
var builder = WebApplication.CreateBuilder(args);

builder.Services.AddGrpc(options =>
{
    options.MaxReceiveMessageSize = 4 * 1024 * 1024; // 4 MB
    options.MaxSendMessageSize = 4 * 1024 * 1024;
    options.EnableDetailedErrors = builder.Environment.IsDevelopment();
});

var app = builder.Build();
app.MapGrpcService<OrderGrpcService>();
app.Run();
```

### gRPC Reflection (Development)

```csharp
builder.Services.AddGrpc();
builder.Services.AddGrpcReflection();

var app = builder.Build();
app.MapGrpcService<OrderGrpcService>();

if (app.Environment.IsDevelopment())
{
    app.MapGrpcReflectionService();
}
```

---

## Client Patterns

### DI-Registered Client with IHttpClientFactory

```csharp
builder.Services
    .AddGrpcClient<OrderService.OrderServiceClient>(options =>
    {
        options.Address = new Uri("https://order-service:5001");
    })
    .ConfigureChannel(options =>
    {
        options.MaxReceiveMessageSize = 4 * 1024 * 1024;
    });
```

Apply resilience via [skill:dotnet-api]:

```csharp
builder.Services
    .AddGrpcClient<OrderService.OrderServiceClient>(options =>
    {
        options.Address = new Uri("https://order-service:5001");
    })
    .AddStandardResilienceHandler();
```

### Reading Server Streams

```csharp
using var call = client.ListOrders(
    new ListOrdersRequest { CustomerId = "cust-123" });

await foreach (var order in call.ResponseStream.ReadAllAsync())
{
    Console.WriteLine($"Order {order.Id}: {order.CustomerId}");
}
```

### Client Streaming

```csharp
using var call = client.UploadOrders();

foreach (var order in ordersToCreate)
{
    await call.RequestStream.WriteAsync(new CreateOrderRequest
    {
        CustomerId = order.CustomerId
    });
}

await call.RequestStream.CompleteAsync();
var response = await call;
Console.WriteLine($"Created {response.OrdersCreated} orders");
```

### Bidirectional Streaming

```csharp
using var call = client.ProcessOrders();

var readTask = Task.Run(async () =>
{
    await foreach (var response in call.ResponseStream.ReadAllAsync())
    {
        Console.WriteLine($"Processed order {response.Id}");
    }
});

foreach (var order in ordersToProcess)
{
    await call.RequestStream.WriteAsync(new CreateOrderRequest
    {
        CustomerId = order.CustomerId
    });
}

await call.RequestStream.CompleteAsync();
await readTask;
```

---

## Authentication

### Bearer Token (JWT)

Server-side:

```csharp
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.Authority = "https://identity.example.com";
        options.TokenValidationParameters.ValidAudience = "order-api";
    });

builder.Services.AddAuthorization();
builder.Services.AddGrpc();

var app = builder.Build();
app.UseAuthentication();
app.UseAuthorization();
app.MapGrpcService<OrderGrpcService>().RequireAuthorization();
```

Client-side token propagation:

```csharp
builder.Services
    .AddGrpcClient<OrderService.OrderServiceClient>(options =>
    {
        options.Address = new Uri("https://order-service:5001");
    })
    .AddCallCredentials(async (context, metadata, serviceProvider) =>
    {
        var tokenProvider = serviceProvider.GetRequiredService<ITokenProvider>();
        var token = await tokenProvider.GetTokenAsync(context.CancellationToken);
        metadata.Add("Authorization", $"Bearer {token}");
    });
```

### Certificate Authentication (mTLS)

```csharp
// Server: require client certificates
builder.WebHost.ConfigureKestrel(kestrel =>
{
    kestrel.ConfigureHttpsDefaults(https =>
    {
        https.ClientCertificateMode = ClientCertificateMode.RequireCertificate;
    });
});

builder.Services.AddAuthentication(CertificateAuthenticationDefaults.AuthenticationScheme)
    .AddCertificate(options =>
    {
        options.AllowedCertificateTypes = CertificateTypes.Chained;
        options.RevocationMode = X509RevocationMode.NoCheck;
    });
```

```csharp
// Client: provide client certificate via DI
builder.Services
    .AddGrpcClient<OrderService.OrderServiceClient>(options =>
    {
        options.Address = new Uri("https://order-service:5001");
    })
    .ConfigurePrimaryHttpMessageHandler(() =>
    {
        var handler = new HttpClientHandler();
        handler.ClientCertificates.Add(
            new X509Certificate2("client.pfx", "password"));
        return handler;
    });
```

---

## Load Balancing

### Proxy-Based Load Balancing (Recommended)

```csharp
builder.Services
    .AddGrpcClient<OrderService.OrderServiceClient>(options =>
    {
        options.Address = new Uri("https://order-service-lb:5001");
    })
    .ConfigurePrimaryHttpMessageHandler(() => new SocketsHttpHandler
    {
        EnableMultipleHttp2Connections = true
    });
```

---

## Health Checks

### gRPC Health Check Protocol with ASP.NET Core Integration

```csharp
builder.Services.AddHealthChecks()
    .AddNpgSql(
        builder.Configuration.GetConnectionString("OrderDb")!,
        name: "order-db",
        tags: ["ready"]);

builder.Services.AddGrpc();
builder.Services.AddGrpcHealthChecks()
    .AddAsyncCheck("order-db", async (sp, ct) =>
    {
        var healthCheckService = sp.GetRequiredService<HealthCheckService>();
        var report = await healthCheckService.CheckHealthAsync(
            r => r.Tags.Contains("ready"), ct);
        return report.Status == HealthStatus.Healthy
            ? HealthCheckResult.Healthy()
            : HealthCheckResult.Unhealthy();
    });

var app = builder.Build();
app.MapGrpcService<OrderGrpcService>();
app.MapGrpcHealthChecksService();
```

### Kubernetes Probes for gRPC

```yaml
livenessProbe:
  grpc:
    port: 5001
  initialDelaySeconds: 10
  periodSeconds: 15

readinessProbe:
  grpc:
    port: 5001
  initialDelaySeconds: 5
  periodSeconds: 10
```

---

## Interceptors

### Server Interceptor

```csharp
public sealed class LoggingInterceptor(ILogger<LoggingInterceptor> logger)
    : Interceptor
{
    public override async Task<TResponse> UnaryServerHandler<TRequest, TResponse>(
        TRequest request,
        ServerCallContext context,
        UnaryServerMethod<TRequest, TResponse> continuation)
    {
        var stopwatch = Stopwatch.StartNew();
        try
        {
            var response = await continuation(request, context);
            logger.LogInformation(
                "gRPC {Method} completed in {ElapsedMs}ms",
                context.Method, stopwatch.ElapsedMilliseconds);
            return response;
        }
        catch (RpcException ex)
        {
            logger.LogError(ex,
                "gRPC {Method} failed with {StatusCode}",
                context.Method, ex.StatusCode);
            throw;
        }
    }
}

// Register
builder.Services.AddGrpc(options =>
{
    options.Interceptors.Add<LoggingInterceptor>();
});
```

---

## Error Handling

### Rich Error Details

```csharp
// Server: throw with metadata
var status = new Status(StatusCode.InvalidArgument, "Validation failed");
var metadata = new Metadata
{
    { "field", "customer_id" },
    { "reason", "Customer ID is required" }
};
throw new RpcException(status, metadata);

// Client: read error metadata
try
{
    var response = await client.GetOrderAsync(request);
}
catch (RpcException ex) when (ex.StatusCode == StatusCode.InvalidArgument)
{
    var field = ex.Trailers.GetValue("field");
    var reason = ex.Trailers.GetValue("reason");
    logger.LogWarning("Validation error on {Field}: {Reason}", field, reason);
}
```

---

## Deadlines and Cancellation

```csharp
// Client: set a deadline
var deadline = DateTime.UtcNow.AddSeconds(10);
var response = await client.GetOrderAsync(
    new GetOrderRequest { Id = 42 },
    deadline: deadline);

// Server: check deadline and propagate cancellation
public override async Task<OrderResponse> GetOrder(
    GetOrderRequest request,
    ServerCallContext context)
{
    var order = await repository.GetByIdAsync(request.Id, context.CancellationToken);
    // ...
}
```

---

## gRPC-Web for Browser Clients

### Server Configuration

```csharp
var builder = WebApplication.CreateBuilder(args);

builder.Services.AddGrpc();
builder.Services.AddCors(options =>
{
    options.AddPolicy("GrpcWeb", policy =>
    {
        policy.WithOrigins("https://app.example.com")
              // Production: prefer explicit header/method lists over AllowAny*
              // to follow the principle of least privilege (see api-security.md).
              // gRPC-Web requires at minimum: Content-Type, X-Grpc-Web, X-User-Agent
              .AllowAnyHeader()
              .AllowAnyMethod()
              .WithExposedHeaders("Grpc-Status", "Grpc-Message", "Grpc-Encoding");
    });
});

var app = builder.Build();

app.UseRouting();
app.UseCors();
app.UseGrpcWeb();

app.MapGrpcService<OrderGrpcService>()
    .EnableGrpcWeb()
    .RequireCors("GrpcWeb");
```

