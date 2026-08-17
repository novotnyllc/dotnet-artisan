# YARP (Yet Another Reverse Proxy)

YARP is Microsoft's extensible .NET reverse proxy library built on ASP.NET Core. It provides configuration-driven routing, load balancing, health checks, transforms, and session affinity for API gateways, BFF patterns, and microservice routing.

## Setup

```xml
<PackageReference Include="Yarp.ReverseProxy" Version="2.*" />
```

```csharp
var builder = WebApplication.CreateBuilder(args);

builder.Services.AddReverseProxy()
    .LoadFromConfig(builder.Configuration.GetSection("ReverseProxy"));

var app = builder.Build();
app.MapReverseProxy();
app.Run();
```

## Configuration (appsettings.json)

```json
{
  "ReverseProxy": {
    "Routes": {
      "catalog-route": {
        "ClusterId": "catalog-cluster",
        "Match": { "Path": "/api/catalog/{**catch-all}" },
        "Transforms": [
          { "PathRemovePrefix": "/api/catalog" }
        ]
      },
      "orders-route": {
        "ClusterId": "orders-cluster",
        "Match": { "Path": "/api/orders/{**catch-all}" },
        "AuthorizationPolicy": "default",
        "CorsPolicy": "default"
      }
    },
    "Clusters": {
      "catalog-cluster": {
        "LoadBalancingPolicy": "RoundRobin",
        "Destinations": {
          "destination1": { "Address": "https://catalog-1:5001/" },
          "destination2": { "Address": "https://catalog-2:5002/" }
        }
      },
      "orders-cluster": {
        "Destinations": {
          "destination1": { "Address": "https://orders:5003/" }
        }
      }
    }
  }
}
```

Configuration is hot-reloaded when the file changes -- no restart required.

## Load Balancing Policies

| Policy | Behavior |
|--------|----------|
| `PowerOfTwoChoices` (default) | Picks two random destinations, selects the one with fewer active requests |
| `RoundRobin` | Cycles through destinations in order |
| `Random` | Random selection |
| `LeastRequests` | Selects destination with fewest active requests (examines all) |
| `FirstAlphabetical` | First alphabetically -- useful for active/passive failover |

## Health Checks

### Active (probes destinations periodically)

```json
"catalog-cluster": {
  "HealthCheck": {
    "Active": {
      "Enabled": true,
      "Interval": "00:00:10",
      "Timeout": "00:00:05",
      "Path": "/health",
      "Policy": "ConsecutiveFailures"
    }
  },
  "Destinations": { "..." : {} }
}
```

### Passive (watches real request outcomes)

```json
"catalog-cluster": {
  "HealthCheck": {
    "Passive": {
      "Enabled": true,
      "Policy": "TransportFailureRate",
      "ReactivationPeriod": "00:00:30"
    }
  }
}
```

Passive health checks run in the `MapReverseProxy` middleware pipeline automatically. Unhealthy destinations are reactivated after `ReactivationPeriod`.

## Session Affinity

```json
"catalog-cluster": {
  "SessionAffinity": {
    "Enabled": true,
    "Policy": "Cookie",
    "AffinityKeyName": ".Yarp.Affinity"
  }
}
```

Policies: `Cookie`, `CustomHeader`. The `FailurePolicy` controls what happens when the affined destination is unavailable (`Redistribute` or `Return503Error`).

## Request/Response Transforms

Transforms modify requests before forwarding and responses before returning to the client.

### Via config

```json
"Transforms": [
  { "PathPrefix": "/v2" },
  { "RequestHeadersCopy": "true" },
  { "RequestHeader": "X-Forwarded-Prefix", "Set": "/api/catalog" },
  { "ResponseHeader": "X-Proxy", "Set": "YARP", "When": "Always" },
  { "QueryValueParameter": "region", "Set": "us-east" }
]
```

### Via code

```csharp
builder.Services.AddReverseProxy()
    .LoadFromConfig(builder.Configuration.GetSection("ReverseProxy"))
    .AddTransforms(context =>
    {
        context.AddRequestHeader("X-Request-Source", "gateway");
        context.AddResponseHeader("X-Served-By", Environment.MachineName);
    });
```

## Rate Limiting Integration

```csharp
builder.Services.AddRateLimiter(options =>
{
    options.AddFixedWindowLimiter("api-limit", o =>
    {
        o.PermitLimit = 100;
        o.Window = TimeSpan.FromMinutes(1);
    });
});

var app = builder.Build();
app.UseRateLimiter();
app.MapReverseProxy();
```

```json
"catalog-route": {
  "RateLimiterPolicy": "api-limit",
  "ClusterId": "catalog-cluster",
  "Match": { "Path": "/api/catalog/{**catch-all}" }
}
```

## Authentication/Authorization Passthrough

```json
"orders-route": {
  "AuthorizationPolicy": "default",
  "ClusterId": "orders-cluster",
  "Match": { "Path": "/api/orders/{**catch-all}" }
}
```

Set `"AuthorizationPolicy": "default"` to require the default auth policy, or name a specific policy. Set `"anonymous"` to explicitly allow unauthenticated access.

## Direct Forwarding (IHttpForwarder)

For simple cases that do not need routes/clusters configuration:

```csharp
builder.Services.AddHttpForwarder();

var app = builder.Build();

var httpClient = new HttpMessageInvoker(new SocketsHttpHandler
{
    UseProxy = false,
    AllowAutoRedirect = false,
    AutomaticDecompression = DecompressionMethods.None,
    UseCookies = false
});

var requestConfig = new ForwarderRequestConfig { ActivityTimeout = TimeSpan.FromSeconds(100) };

app.Map("/api/{**catch-all}", async (HttpContext context, IHttpForwarder forwarder) =>
{
    var error = await forwarder.SendAsync(context,
        "https://backend:5001/", httpClient, requestConfig);

    if (error != ForwarderError.None)
    {
        var errorFeature = context.GetForwarderErrorFeature();
        // Log errorFeature?.Exception
    }
});
```

Use `HttpMessageInvoker` (not `HttpClient`) -- `HttpClient` buffers responses, breaking streaming.

## Configuration via Code

```csharp
var routes = new[]
{
    new RouteConfig
    {
        RouteId = "catalog",
        ClusterId = "catalog-cluster",
        Match = new RouteMatch { Path = "/api/catalog/{**catch-all}" }
    }
};

var clusters = new[]
{
    new ClusterConfig
    {
        ClusterId = "catalog-cluster",
        LoadBalancingPolicy = "RoundRobin",
        Destinations = new Dictionary<string, DestinationConfig>
        {
            ["dest1"] = new() { Address = "https://catalog-1:5001/" },
            ["dest2"] = new() { Address = "https://catalog-2:5002/" }
        }
    }
};

builder.Services.AddReverseProxy()
    .LoadFromMemory(routes, clusters);
```

Update at runtime via `InMemoryConfigProvider.Update(routes, clusters)`.

## When to Use YARP

| Scenario | YARP? | Alternative |
|----------|-------|-------------|
| .NET API gateway with custom C# logic | Yes | -- |
| BFF (Backend for Frontend) pattern | Yes | -- |
| Microservice routing within .NET | Yes | -- |
| Static CDN / edge caching | No | Azure Front Door, Cloudflare |
| Non-.NET infrastructure proxy | No | Nginx, Envoy, HAProxy |

---

## Agent Gotchas

1. **Do not use `HttpClient` for direct forwarding** -- use `HttpMessageInvoker`. `HttpClient` buffers response bodies, breaking streaming (WebSocket, SSE, gRPC) and increasing memory usage.
2. **Do not forget middleware ordering** -- `UseAuthentication()` and `UseAuthorization()` must come before `MapReverseProxy()` for auth policies to apply.
3. **Do not mix partial config from multiple sources for the same route/cluster** -- YARP does not merge config from different providers for the same route or cluster ID.
4. **Do not enable passive health checks without the passive health middleware** -- the parameterless `MapReverseProxy()` includes it automatically, but if you build a custom pipeline you must call `UsePassiveHealthChecks()`.
5. **Do not set `AuthorizationPolicy` on routes expecting CORS preflights without also configuring `CorsPolicy`** -- preflight OPTIONS requests carry no auth tokens and will be rejected.

---

## References

- [YARP Overview](https://learn.microsoft.com/aspnet/core/fundamentals/servers/yarp/yarp-overview)
- [Getting Started](https://learn.microsoft.com/aspnet/core/fundamentals/servers/yarp/getting-started)
- [Configuration Files](https://learn.microsoft.com/aspnet/core/fundamentals/servers/yarp/config-files)
- [Load Balancing](https://learn.microsoft.com/aspnet/core/fundamentals/servers/yarp/load-balancing)
- [Health Checks](https://learn.microsoft.com/aspnet/core/fundamentals/servers/yarp/dests-health-checks)
- [Direct Forwarding](https://learn.microsoft.com/aspnet/core/fundamentals/servers/yarp/direct-forwarding)
- [Request Transforms](https://learn.microsoft.com/aspnet/core/fundamentals/servers/yarp/transforms-request)
