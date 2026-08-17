# Aspire Patterns

.NET Aspire orchestration patterns for building cloud-ready distributed applications. Covers AppHost configuration, service discovery, the component model for integrating backing services (databases, caches, message brokers), the Aspire dashboard for local observability, distributed health checks, and when to choose Aspire vs manual container orchestration.

## Aspire Overview

.NET Aspire is an opinionated stack for building observable, production-ready distributed applications. It provides:

- **Orchestration** -- define your distributed topology in C# (the AppHost)
- **Components** -- pre-configured NuGet packages for common backing services
- **Service Defaults** -- shared configuration for OpenTelemetry, health checks, resilience
- **Dashboard** -- local development UI for traces, logs, metrics, and resource status

Aspire is not a deployment target. It orchestrates the local development and testing experience. For production, it generates manifests consumed by deployment tools (Azure Developer CLI, Kubernetes, etc.).

### When to Use Aspire

| Scenario | Recommendation |
|----------|---------------|
| Multiple .NET services + backing infrastructure | Aspire AppHost -- simplifies local dev and service wiring |
| Single API with a database | Optional -- Aspire adds overhead for simple topologies |
| Non-.NET services only (Node, Python) | Aspire can reference container images, but the tooling benefit is reduced |
| Need Kubernetes/Compose for local dev already | Evaluate migration cost; Aspire replaces docker-compose for dev scenarios |
| Team needs consistent observability defaults | Aspire ServiceDefaults standardize OTel across all projects |

---

## AppHost Configuration

The AppHost is a .NET project (`Aspire.Hosting.AppHost` SDK) that defines the distributed application topology. It references other projects and backing services, wiring them together with service discovery.

### AppHost Project Setup

```xml
<Project Sdk="Microsoft.NET.Sdk">

  <!-- Aspire SDK version is independent of .NET TFM; 9.x works on net8.0+ -->
  <Sdk Name="Aspire.AppHost.Sdk" Version="9.1.*" />

  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net10.0</TargetFramework>
    <IsAspireHost>true</IsAspireHost>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="Aspire.Hosting.AppHost" Version="9.1.*" />
    <PackageReference Include="Aspire.Hosting.PostgreSQL" Version="9.1.*" />
    <PackageReference Include="Aspire.Hosting.Redis" Version="9.1.*" />
    <PackageReference Include="Aspire.Hosting.RabbitMQ" Version="9.1.*" />
  </ItemGroup>

  <ItemGroup>
    <ProjectReference Include="..\MyApi\MyApi.csproj" />
    <ProjectReference Include="..\MyWorker\MyWorker.csproj" />
  </ItemGroup>

</Project>
```

### Defining the Topology

```csharp
var builder = DistributedApplication.CreateBuilder(args);

// Backing services -- Aspire manages containers automatically
var postgres = builder.AddPostgres("pg")
    .WithPgAdmin()              // Adds pgAdmin UI container
    .AddDatabase("ordersdb");

var redis = builder.AddRedis("cache")
    .WithRedisCommander();      // Adds Redis Commander UI

var rabbitmq = builder.AddRabbitMQ("messaging")
    .WithManagementPlugin();    // Adds RabbitMQ management UI

// Application projects -- wired with service discovery
var api = builder.AddProject<Projects.MyApi>("api")
    .WithReference(postgres)
    .WithReference(redis)
    .WithReference(rabbitmq)
    .WithExternalHttpEndpoints();  // Marks endpoints as public in deployment manifests

builder.AddProject<Projects.MyWorker>("worker")
    .WithReference(postgres)
    .WithReference(rabbitmq)
    .WaitFor(api);              // Start worker after API is healthy

builder.Build().Run();
```

### Resource Lifecycle

`WaitFor` controls startup ordering. Resources wait until dependencies report healthy before starting:

```csharp
// Worker waits for both the database and API to be ready
builder.AddProject<Projects.MyWorker>("worker")
    .WithReference(postgres)
    .WaitFor(postgres)          // Wait for database container health check
    .WaitFor(api);              // Wait for API health endpoint
```

Without `WaitFor`, resources start in parallel. Use it only when startup order matters (e.g., a worker that requires the database schema to exist).

---

## Service Discovery

Aspire automatically configures service discovery so projects can resolve each other by resource name rather than hardcoded URLs.

### How It Works

1. The AppHost injects endpoint information as environment variables and configuration
2. The `Aspire.ServiceDefaults` project configures `Microsoft.Extensions.ServiceDiscovery`
3. Application code resolves services by name via `HttpClient` or connection strings

### Consuming Discovered Services

```csharp
// In MyApi/Program.cs
var builder = WebApplication.CreateBuilder(args);

// AddServiceDefaults registers service discovery, OpenTelemetry, health checks
builder.AddServiceDefaults();

// HttpClient resolves "worker" via service discovery
builder.Services.AddHttpClient("worker-client", client =>
{
    client.BaseAddress = new Uri("https+http://worker");
});
```

The `https+http://` scheme prefix tells the service discovery provider to try HTTPS first, falling back to HTTP. This is the recommended pattern for inter-service communication in Aspire.

### Connection Strings

For backing services (databases, caches), Aspire injects connection strings via the standard `ConnectionStrings` configuration section:

```csharp
// AppHost: .WithReference(postgres) on the API project
// injects ConnectionStrings__ordersdb automatically

// In MyApi/Program.cs
builder.AddNpgsqlDbContext<OrdersDbContext>("ordersdb");
// Resolves ConnectionStrings:ordersdb from configuration
```

---

## Component Model

Aspire components are NuGet packages that provide pre-configured client integrations for backing services. They handle connection management, health checks, telemetry, and resilience.

### Hosting Packages vs Client Packages

| Package Type | Installed In | Purpose |
|---|---|---|
| `Aspire.Hosting.*` | AppHost project | Define and configure the resource (container, connection) |
| `Aspire.* (client)` | Service projects | Consume the resource with health checks and telemetry |

```xml
<!-- AppHost project -->
<PackageReference Include="Aspire.Hosting.PostgreSQL" Version="9.1.*" />

<!-- API project -->
<PackageReference Include="Aspire.Npgsql.EntityFrameworkCore.PostgreSQL" Version="9.1.*" />
```

### Common Components

| Component | Hosting Package | Client Package |
|-----------|----------------|----------------|
| PostgreSQL (EF Core) | `Aspire.Hosting.PostgreSQL` | `Aspire.Npgsql.EntityFrameworkCore.PostgreSQL` |
| PostgreSQL (Npgsql) | `Aspire.Hosting.PostgreSQL` | `Aspire.Npgsql` |
| Redis (caching) | `Aspire.Hosting.Redis` | `Aspire.StackExchange.Redis` |
| Redis (output cache) | `Aspire.Hosting.Redis` | `Aspire.StackExchange.Redis.OutputCaching` |
| RabbitMQ | `Aspire.Hosting.RabbitMQ` | `Aspire.RabbitMQ.Client` |
| Azure Service Bus | `Aspire.Hosting.Azure.ServiceBus` | `Aspire.Azure.Messaging.ServiceBus` |
| SQL Server (EF Core) | `Aspire.Hosting.SqlServer` | `Aspire.Microsoft.EntityFrameworkCore.SqlServer` |
| MongoDB | `Aspire.Hosting.MongoDB` | `Aspire.MongoDB.Driver` |

### Client Registration

```csharp
var builder = WebApplication.CreateBuilder(args);
builder.AddServiceDefaults();

// Each Add* method registers the client, health check, and telemetry
builder.AddNpgsqlDbContext<OrdersDbContext>("ordersdb");
builder.AddRedisClient("cache");
builder.AddRabbitMQClient("messaging");
```

Component `Add*` methods:
1. Register the client/DbContext in DI
2. Add a health check for the resource
3. Configure OpenTelemetry instrumentation for the client
4. Apply default resilience settings (retries, timeouts)

---

## Service Defaults

The `ServiceDefaults` project is a shared library referenced by all service projects. It standardizes cross-cutting concerns.

### What ServiceDefaults Configures

```csharp
public static class Extensions
{
    public static IHostApplicationBuilder AddServiceDefaults(
        this IHostApplicationBuilder builder)
    {
        // Service discovery
        builder.ConfigureOpenTelemetry();
        builder.AddDefaultHealthChecks();
        builder.Services.AddServiceDiscovery();

        // Resilience for HttpClient
        builder.Services.ConfigureHttpClientDefaults(http =>
        {
            http.AddStandardResilienceHandler();
            http.AddServiceDiscovery();
        });

        return builder;
    }

    public static IHostApplicationBuilder ConfigureOpenTelemetry(
        this IHostApplicationBuilder builder)
    {
        builder.Logging.AddOpenTelemetry(logging =>
        {
            logging.IncludeFormattedMessage = true;
            logging.IncludeScopes = true;
        });

        builder.Services.AddOpenTelemetry()
            .WithMetrics(metrics => metrics
                .AddAspNetCoreInstrumentation()
                .AddHttpClientInstrumentation()
                .AddRuntimeInstrumentation())
            .WithTracing(tracing => tracing
                .AddAspNetCoreInstrumentation()
                .AddGrpcClientInstrumentation()
                .AddHttpClientInstrumentation());

        builder.AddOpenTelemetryExporters();
        return builder;
    }

    public static IHostApplicationBuilder AddDefaultHealthChecks(
        this IHostApplicationBuilder builder)
    {
        builder.Services.AddHealthChecks()
            .AddCheck("self", () => HealthCheckResult.Healthy());

        return builder;
    }

    public static WebApplication MapDefaultEndpoints(
        this WebApplication app)
    {
        app.MapHealthChecks("/health");
        app.MapHealthChecks("/alive", new HealthCheckOptions
        {
            Predicate = r => r.Tags.Contains("live")
        });

        return app;
    }
}
```

### Using ServiceDefaults

Every service project references the ServiceDefaults project and calls the extension methods:

```csharp
var builder = WebApplication.CreateBuilder(args);
builder.AddServiceDefaults();

// ... service-specific registrations

var app = builder.Build();
app.MapDefaultEndpoints();

// ... middleware and endpoints

app.Run();
```

---

## Dashboard

The Aspire dashboard provides a local observability UI that starts automatically with the AppHost. It displays:

- **Resources** -- status of all projects, containers, and executables
- **Console logs** -- aggregated stdout/stderr from all resources
- **Structured logs** -- OpenTelemetry log records with structured properties
- **Traces** -- distributed traces across all services
- **Metrics** -- real-time metric charts

### Accessing the Dashboard

When you run the AppHost (`dotnet run --project MyApp.AppHost`), the dashboard URL is printed to the console:

```
info: Aspire.Hosting.DistributedApplication[0]
      Login to the dashboard at https://localhost:17043/login?t=<token>
```

### Dashboard in Non-Aspire Projects

The dashboard is available as a standalone container for projects not using the full Aspire stack:

```bash
docker run --rm -it -p 18888:18888 -p 4317:18889 \
  -d --name aspire-dashboard \
  mcr.microsoft.com/dotnet/aspire-dashboard:9.1
```

Configure your app to export OTLP telemetry to `http://localhost:4317` and view it at `http://localhost:18888`.

---

## Health Checks and Distributed Tracing

### Component Health Checks

Each Aspire component automatically registers health checks. The AppHost uses these to determine resource readiness:

```csharp
// In AppHost -- WaitFor uses health checks to gate startup
builder.AddProject<Projects.MyApi>("api")
    .WithReference(postgres)
    .WaitFor(postgres);     // Waits for Npgsql health check to pass
```

### Custom Health Checks

Add application-specific health checks alongside Aspire defaults:

```csharp
builder.Services.AddHealthChecks()
    .AddCheck<OrderProcessingHealthCheck>(
        "order-processing",
        tags: ["ready"]);
```

See [skill:dotnet-devops] for detailed health check patterns (liveness vs readiness, custom checks, health check publishing).

### Distributed Tracing Integration

Aspire configures OpenTelemetry tracing through ServiceDefaults. Traces propagate automatically across HTTP boundaries. For custom spans:

```csharp
private static readonly ActivitySource s_activitySource = new("MyApp.Orders");

public async Task<Order> ProcessOrderAsync(CreateOrderRequest request, CancellationToken ct)
{
    using var activity = s_activitySource.StartActivity("ProcessOrder");
    activity?.SetTag("order.customer_id", request.CustomerId);

    // Calls to other Aspire services carry trace context automatically
    var inventory = await _httpClient.GetFromJsonAsync<InventoryResponse>(
        $"https+http://inventory-api/api/stock/{request.ProductId}", ct);

    // ... process order
    return order;
}
```

See [skill:dotnet-devops] for comprehensive distributed tracing guidance (custom ActivitySource, trace context propagation, span events).

---

## Container Resources

### Adding Container Images

For services not available as Aspire components, add arbitrary container images:

```csharp
var seq = builder.AddContainer("seq", "datalust/seq")
    .WithHttpEndpoint(port: 5341, targetPort: 80)
    .WithEnvironment("ACCEPT_EULA", "Y");

// Reference the container from a project
builder.AddProject<Projects.MyApi>("api")
    .WithReference(seq);
```

### Persistent Volumes

By default, Aspire containers use ephemeral storage. Add volumes for data persistence across restarts:

```csharp
var postgres = builder.AddPostgres("pg")
    .WithDataVolume("pg-data")     // Named volume for data persistence
    .AddDatabase("ordersdb");
```

### External Resources

Reference existing infrastructure not managed by Aspire:

```csharp
// Connection string from configuration (not an Aspire-managed container)
var existingDb = builder.AddConnectionString("legacydb");

builder.AddProject<Projects.MyApi>("api")
    .WithReference(existingDb);
```

---

## Aspire vs Manual Container Orchestration

| Concern | Aspire | Docker Compose / Manual |
|---------|--------|------------------------|
| Configuration language | C# (strongly typed) | YAML |
| Service discovery | Automatic (env var injection) | Manual DNS/env config |
| Health checks | Automatic per component | Manual HEALTHCHECK per service |
| Observability | Pre-configured OTel + dashboard | Manual OTel collector setup |
| IDE integration | Hot reload, F5 debugging | Attach debugger manually |
| Production deployment | Generates manifests (AZD, K8s) | Write manifests directly |
| Non-.NET services | Container references (less integrated) | Equal support for all languages |
| Learning curve | .NET-specific abstractions | Industry-standard tooling |

Choose Aspire when your stack is primarily .NET and you want standardized observability, service discovery, and a simplified local dev experience. Choose manual orchestration when you need fine-grained control, polyglot services, or your team is already proficient with Compose/Kubernetes.

---

## Key Principles

- **AppHost is dev-time only** -- it orchestrates local development, not production deployment
- **Use components over raw connection strings** -- components add health checks, telemetry, and resilience automatically
- **ServiceDefaults is non-negotiable** -- every Aspire service project must reference it for consistent observability
- **WaitFor for ordered startup** -- use it for real dependencies (schema migrations, seed data), not for every resource
- **Do not duplicate OTel config** -- Aspire ServiceDefaults configure OpenTelemetry; manual configuration causes double-collection

---

## Agent Gotchas

1. **Do not manually configure OpenTelemetry in Aspire service projects** -- ServiceDefaults already registers OTel providers. Adding manual `.AddOpenTelemetry()` calls causes duplicate trace/metric collection and inflated telemetry costs.
2. **Do not hardcode connection strings in Aspire service projects** -- use `builder.AddNpgsqlDbContext<T>("name")` or `builder.Configuration.GetConnectionString("name")`. Aspire injects connection strings via environment variables; hardcoded values bypass service discovery.
3. **Do not use `WaitFor` on every resource** -- it serializes startup and increases launch time. Use it only when a service genuinely cannot start without the dependency (e.g., database migration on startup).
4. **Do not reference `Aspire.Hosting.*` packages from service projects** -- hosting packages belong in the AppHost only. Service projects use client packages (`Aspire.Npgsql`, `Aspire.StackExchange.Redis`, etc.).
5. **Do not confuse the AppHost with a production host** -- the AppHost runs locally (or in CI) to orchestrate resources. Production deployment uses generated manifests or infrastructure-as-code.
6. **Do not omit `AddServiceDefaults()` in new service projects** -- without it, the project lacks service discovery, health checks, and telemetry, breaking Aspire integration silently.

---

## Prerequisites

- .NET 10 SDK (or .NET 8/9 with Aspire workload)
- Docker Desktop or Podman (for container resources)
- Aspire workload: `dotnet workload install aspire`

---

## References

- [.NET Aspire overview](https://learn.microsoft.com/en-us/dotnet/aspire/get-started/aspire-overview)
- [.NET Aspire components](https://learn.microsoft.com/en-us/dotnet/aspire/fundamentals/components-overview)
- [.NET Aspire service discovery](https://learn.microsoft.com/en-us/dotnet/aspire/fundamentals/service-discovery)
- [.NET Aspire dashboard](https://learn.microsoft.com/en-us/dotnet/aspire/fundamentals/dashboard/overview)
- [.NET Aspire orchestration](https://learn.microsoft.com/en-us/dotnet/aspire/fundamentals/app-host-overview)
- [Aspire samples repository](https://github.com/dotnet/aspire-samples)
