# HTTP Client

Best practices for consuming HTTP APIs in .NET applications using `IHttpClientFactory`. Covers named and typed clients, resilience pipeline integration, `DelegatingHandler` chains for cross-cutting concerns, and testing strategies.

## Why IHttpClientFactory

Creating `HttpClient` instances directly causes two problems:

1. **Socket exhaustion** -- each `HttpClient` instance holds its own connection pool. Creating and disposing many instances exhausts available sockets (`SocketException: Address already in use`).
2. **DNS staleness** -- a long-lived singleton `HttpClient` caches DNS lookups indefinitely, missing DNS changes during blue-green deployments or failovers.

`IHttpClientFactory` solves both by managing `HttpMessageHandler` lifetimes with automatic pooling and rotation (default: 2-minute handler lifetime).

```csharp
// Do not do this
var client = new HttpClient(); // Socket exhaustion risk

// Do not do this either
static readonly HttpClient _client = new(); // DNS staleness risk

// Do this -- use IHttpClientFactory
builder.Services.AddHttpClient();
```

---

## Named Clients

Register clients by name for scenarios where you consume multiple APIs with different configurations:

```csharp
// Registration
builder.Services.AddHttpClient("catalog-api", client =>
{
    client.BaseAddress = new Uri("https://catalog.internal");
    client.DefaultRequestHeaders.Add("Accept", "application/json");
    client.Timeout = TimeSpan.FromSeconds(30);
});

builder.Services.AddHttpClient("payment-api", client =>
{
    client.BaseAddress = new Uri("https://payments.internal");
    client.DefaultRequestHeaders.Add("X-Api-Version", "2");
});

// Usage
public sealed class OrderService(IHttpClientFactory clientFactory)
{
    public async Task<Product?> GetProductAsync(
        string productId, CancellationToken ct)
    {
        var client = clientFactory.CreateClient("catalog-api");
        var response = await client.GetAsync($"/products/{productId}", ct);

        if (response.StatusCode == HttpStatusCode.NotFound)
        {
            return null;
        }

        response.EnsureSuccessStatusCode();
        return await response.Content
            .ReadFromJsonAsync<Product>(ct);
    }
}
```

---

## Typed Clients

Typed clients encapsulate HTTP logic behind a strongly-typed interface. Prefer typed clients when a service consumes a single API with multiple operations:

```csharp
// Typed client class
public sealed class CatalogApiClient(HttpClient httpClient)
{
    public async Task<Product?> GetProductAsync(
        string productId, CancellationToken ct = default)
    {
        var response = await httpClient.GetAsync(
            $"/products/{productId}", ct);

        if (response.StatusCode == HttpStatusCode.NotFound)
        {
            return null;
        }

        response.EnsureSuccessStatusCode();
        return await response.Content
            .ReadFromJsonAsync<Product>(ct);
    }

    public async Task<PagedResult<Product>> ListProductsAsync(
        int page = 1,
        int pageSize = 20,
        CancellationToken ct = default)
    {
        var response = await httpClient.GetAsync(
            $"/products?page={page}&pageSize={pageSize}", ct);

        response.EnsureSuccessStatusCode();
        return (await response.Content
            .ReadFromJsonAsync<PagedResult<Product>>(ct))!;
    }

    public async Task<Product> CreateProductAsync(
        CreateProductRequest request,
        CancellationToken ct = default)
    {
        var response = await httpClient.PostAsJsonAsync(
            "/products", request, ct);

        response.EnsureSuccessStatusCode();
        return (await response.Content
            .ReadFromJsonAsync<Product>(ct))!;
    }
}

// Registration
builder.Services.AddHttpClient<CatalogApiClient>(client =>
{
    client.BaseAddress = new Uri("https://catalog.internal");
    client.DefaultRequestHeaders.Add("Accept", "application/json");
});
```

### Typed Client with Interface

For testability, define an interface:

```csharp
public interface ICatalogApiClient
{
    Task<Product?> GetProductAsync(string productId, CancellationToken ct = default);
    Task<PagedResult<Product>> ListProductsAsync(int page = 1, int pageSize = 20, CancellationToken ct = default);
}

public sealed class CatalogApiClient(HttpClient httpClient) : ICatalogApiClient
{
    // Implementation as above
}

// Registration with interface
builder.Services.AddHttpClient<ICatalogApiClient, CatalogApiClient>(client =>
{
    client.BaseAddress = new Uri("https://catalog.internal");
});
```

---

## Resilience Pipelines

Apply resilience to HTTP clients using `Microsoft.Extensions.Http.Resilience`. See [skill:dotnet-api] for detailed pipeline configuration, strategy options, and migration guidance.

### Standard Resilience Handler (Recommended)

The standard handler applies the full pipeline (rate limiter, total timeout, retry, circuit breaker, attempt timeout) with sensible defaults:

```csharp
builder.Services
    .AddHttpClient<CatalogApiClient>(client =>
    {
        client.BaseAddress = new Uri("https://catalog.internal");
    })
    .AddStandardResilienceHandler();
```

### Standard Handler with Custom Options

```csharp
builder.Services
    .AddHttpClient<CatalogApiClient>(client =>
    {
        client.BaseAddress = new Uri("https://catalog.internal");
    })
    .AddStandardResilienceHandler(options =>
    {
        options.Retry.MaxRetryAttempts = 5;
        options.Retry.Delay = TimeSpan.FromSeconds(1);
        options.CircuitBreaker.BreakDuration = TimeSpan.FromSeconds(15);
        options.AttemptTimeout.Timeout = TimeSpan.FromSeconds(5);
        options.TotalRequestTimeout.Timeout = TimeSpan.FromSeconds(60);
    });
```

### Hedging Handler (for Read-Only APIs)

For idempotent read operations where tail latency matters:

```csharp
builder.Services
    .AddHttpClient("search-api")
    .AddStandardHedgingHandler(options =>
    {
        options.Hedging.MaxHedgedAttempts = 2;
        options.Hedging.Delay = TimeSpan.FromMilliseconds(500);
    });
```

See [skill:dotnet-api] for when to use hedging vs standard retry.

---

## DelegatingHandlers

`DelegatingHandler` provides a pipeline of message handlers that process outgoing requests and incoming responses. Use them for cross-cutting concerns that apply to HTTP traffic.

### Handler Pipeline Order

Handlers execute in registration order for requests (outermost to innermost) and reverse order for responses:

```
Request  --> Handler A --> Handler B --> Handler C --> HttpClientHandler --> Server
Response <-- Handler A <-- Handler B <-- Handler C <-- HttpClientHandler <-- Server
```

### Common Handlers

#### Request Logging

```csharp
public sealed class RequestLoggingHandler(
    ILogger<RequestLoggingHandler> logger) : DelegatingHandler
{
    protected override async Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request,
        CancellationToken cancellationToken)
    {
        var stopwatch = Stopwatch.StartNew();

        logger.LogInformation(
            "HTTP {Method} {Uri}",
            request.Method,
            request.RequestUri);

        var response = await base.SendAsync(request, cancellationToken);

        stopwatch.Stop();
        logger.LogInformation(
            "HTTP {Method} {Uri} responded {StatusCode} in {ElapsedMs}ms",
            request.Method,
            request.RequestUri,
            (int)response.StatusCode,
            stopwatch.ElapsedMilliseconds);

        return response;
    }
}

// Registration
builder.Services.AddTransient<RequestLoggingHandler>();
builder.Services
    .AddHttpClient<CatalogApiClient>(/* ... */)
    .AddHttpMessageHandler<RequestLoggingHandler>();
```

#### API Key Authentication

```csharp
public sealed class ApiKeyHandler(IConfiguration config) : DelegatingHandler
{
    protected override Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request,
        CancellationToken cancellationToken)
    {
        var apiKey = config["ExternalApi:ApiKey"]
            ?? throw new InvalidOperationException("API key not configured");

        request.Headers.Add("X-Api-Key", apiKey);

        return base.SendAsync(request, cancellationToken);
    }
}

// Registration
builder.Services.AddTransient<ApiKeyHandler>();
builder.Services
    .AddHttpClient<CatalogApiClient>(/* ... */)
    .AddHttpMessageHandler<ApiKeyHandler>();
```

#### Bearer Token (from Downstream Auth)

```csharp
public sealed class BearerTokenHandler(
    IHttpContextAccessor httpContextAccessor) : DelegatingHandler
{
    protected override Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request,
        CancellationToken cancellationToken)
    {
        var token = httpContextAccessor.HttpContext?
            .Request.Headers.Authorization
            .ToString()
            .Replace("Bearer ", "");

        if (!string.IsNullOrEmpty(token))
        {
            request.Headers.Authorization =
                new AuthenticationHeaderValue("Bearer", token);
        }

        return base.SendAsync(request, cancellationToken);
    }
}
```

#### Correlation ID Propagation

```csharp
public sealed class CorrelationIdHandler : DelegatingHandler
{
    private const string HeaderName = "X-Correlation-Id";

    protected override Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request,
        CancellationToken cancellationToken)
    {
        if (!request.Headers.Contains(HeaderName))
        {
            var correlationId = Activity.Current?.Id
                ?? Guid.NewGuid().ToString();
            request.Headers.Add(HeaderName, correlationId);
        }

        return base.SendAsync(request, cancellationToken);
    }
}
```

### Chaining Multiple Handlers

Handlers are added in execution order:

```csharp
builder.Services.AddTransient<CorrelationIdHandler>();
builder.Services.AddTransient<BearerTokenHandler>();
builder.Services.AddTransient<RequestLoggingHandler>();

builder.Services
    .AddHttpClient<CatalogApiClient>(client =>
    {
        client.BaseAddress = new Uri("https://catalog.internal");
    })
    .AddHttpMessageHandler<CorrelationIdHandler>()   // 1st (outermost): add correlation ID
    .AddHttpMessageHandler<BearerTokenHandler>()     // 2nd: add auth token
    .AddHttpMessageHandler<RequestLoggingHandler>()  // 3rd: log request/response
    .AddStandardResilienceHandler();                 // 4th (innermost): resilience pipeline
```

**Note:** In `IHttpClientFactory`, handlers registered first are outermost. `.AddStandardResilienceHandler()` added last is innermost -- it wraps the actual HTTP call directly. This means retries happen inside the resilience handler without re-executing the outer DelegatingHandlers. This is typically correct: correlation IDs and auth tokens are set once by the outer handlers, and the resilience layer retries the raw HTTP call. If you need per-retry token refresh (e.g., expired bearer tokens), move the token handler inside the resilience boundary or use a custom `ResiliencePipelineBuilder` callback.

---

## Configuration Patterns

### Base Address from Configuration

```csharp
builder.Services.AddHttpClient<CatalogApiClient>(client =>
{
    var baseUrl = builder.Configuration["Services:CatalogApi:BaseUrl"]
        ?? throw new InvalidOperationException(
            "CatalogApi base URL not configured");
    client.BaseAddress = new Uri(baseUrl);
});
```

```json
{
  "Services": {
    "CatalogApi": {
      "BaseUrl": "https://catalog.internal"
    }
  }
}
```

### Handler Lifetime

The default handler lifetime is 2 minutes. Adjust for services with different DNS characteristics:

```csharp
builder.Services
    .AddHttpClient<CatalogApiClient>(/* ... */)
    .SetHandlerLifetime(TimeSpan.FromMinutes(5));
```

**Shorter lifetime** (1 min): for services behind load balancers with frequent DNS changes.
**Longer lifetime** (5-10 min): for stable internal services where connection reuse improves performance.

---

## Testing HTTP Clients

### Unit Testing with MockHttpMessageHandler

Test typed clients by providing a mock handler that returns controlled responses:

```csharp
public sealed class CatalogApiClientTests
{
    [Fact]
    public async Task GetProductAsync_ReturnsProduct_WhenFound()
    {
        // Arrange
        var expectedProduct = new Product { Id = "p1", Name = "Widget" };
        var handler = new MockHttpMessageHandler(
            new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = JsonContent.Create(expectedProduct)
            });

        var httpClient = new HttpClient(handler)
        {
            BaseAddress = new Uri("https://test.local")
        };

        var client = new CatalogApiClient(httpClient);

        // Act
        var result = await client.GetProductAsync("p1");

        // Assert
        Assert.NotNull(result);
        Assert.Equal("Widget", result.Name);
    }

    [Fact]
    public async Task GetProductAsync_ReturnsNull_WhenNotFound()
    {
        var handler = new MockHttpMessageHandler(
            new HttpResponseMessage(HttpStatusCode.NotFound));

        var httpClient = new HttpClient(handler)
        {
            BaseAddress = new Uri("https://test.local")
        };

        var client = new CatalogApiClient(httpClient);

        var result = await client.GetProductAsync("missing");

        Assert.Null(result);
    }
}

// Reusable mock handler
public sealed class MockHttpMessageHandler(
    HttpResponseMessage response) : HttpMessageHandler
{
    private HttpRequestMessage? _lastRequest;

    public HttpRequestMessage? LastRequest => _lastRequest;

    protected override Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request,
        CancellationToken cancellationToken)
    {
        _lastRequest = request;
        return Task.FromResult(response);
    }
}
```

### Testing DelegatingHandlers

Test handlers in isolation by providing an inner handler:

```csharp
public sealed class ApiKeyHandlerTests
{
    [Fact]
    public async Task AddsApiKeyHeader()
    {
        // Arrange
        var config = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["ExternalApi:ApiKey"] = "test-key-123"
            })
            .Build();

        var innerHandler = new MockHttpMessageHandler(
            new HttpResponseMessage(HttpStatusCode.OK));

        var handler = new ApiKeyHandler(config)
        {
            InnerHandler = innerHandler
        };

        var client = new HttpClient(handler)
        {
            BaseAddress = new Uri("https://test.local")
        };

        // Act
        await client.GetAsync("/test");

        // Assert
        Assert.NotNull(innerHandler.LastRequest);
        Assert.Equal(
            "test-key-123",
            innerHandler.LastRequest.Headers
                .GetValues("X-Api-Key").Single());
    }
}
```

### Integration Testing with WebApplicationFactory

Test the full HTTP client pipeline including DI registration:

```csharp
// See [skill:dotnet-testing] (`references/integration-testing.md`) for
// WebApplicationFactory patterns
```

---

## Named vs Typed Clients -- Decision Guide

| Factor | Named Client | Typed Client |
|--------|-------------|--------------|
| API surface | Simple (1-2 calls) | Rich (multiple operations) |
| Type safety | Requires string name | Strongly typed |
| Encapsulation | HTTP logic in consuming class | HTTP logic in client class |
| Testability | Mock `IHttpClientFactory` | Mock the client interface |
| Multiple APIs | One name per API | One class per API |
| Recommendation | Ad-hoc or simple calls | Primary pattern for API consumption |

**Default to typed clients.** Use named clients only for simple, one-off HTTP calls where a full typed client class adds unnecessary ceremony.

---

## Key Principles

- **Always use IHttpClientFactory** -- never `new HttpClient()` in application code
- **Prefer typed clients** -- encapsulate HTTP logic behind a strongly-typed interface
- **Apply resilience via pipeline** -- use `AddStandardResilienceHandler()` (see [skill:dotnet-api]) rather than manual retry loops
- **Keep handlers focused** -- each `DelegatingHandler` should do one thing (auth, logging, correlation)
- **Register handlers as Transient** -- DelegatingHandlers are created per-client-instance and should not hold state across requests
- **Pass CancellationToken everywhere** -- from endpoint to typed client to HTTP call
- **Use ReadFromJsonAsync / PostAsJsonAsync** -- avoid manual serialization with `StringContent`

---

## Agent Gotchas

1. **Do not create HttpClient with `new`** -- always inject `IHttpClientFactory` or a typed client. Direct instantiation causes socket exhaustion.
2. **Do not dispose typed clients** -- the factory manages handler lifetimes. Disposing the `HttpClient` instance is harmless (it does not close pooled connections), but wrapping it in `using` is misleading.
3. **Do not set `BaseAddress` with a trailing path** -- `new Uri("https://api.example.com/v2")` will drop `/v2` when combining with relative URIs. Use `new Uri("https://api.example.com/v2/")` (trailing slash) or use absolute URIs in calls.
4. **Understand that resilience added last is innermost** -- `AddStandardResilienceHandler()` registered after `AddHttpMessageHandler` calls wraps the HTTP call directly. Retries do not re-execute outer DelegatingHandlers. This is correct for most cases (tokens/correlation IDs set once). If you need per-retry token refresh, place the token handler after the resilience handler or use a custom pipeline callback.
5. **Do not register DelegatingHandlers as Singleton** -- they are pooled with the `HttpMessageHandler` pipeline and must be Transient.

---

## References

- [IHttpClientFactory with .NET](https://learn.microsoft.com/en-us/dotnet/core/extensions/httpclient-factory)
- [Use HttpClientFactory to implement resilient HTTP requests](https://learn.microsoft.com/en-us/dotnet/architecture/microservices/implement-resilient-applications/use-httpclientfactory-to-implement-resilient-http-requests)
- [HttpClient message handlers](https://learn.microsoft.com/en-us/aspnet/web-api/overview/advanced/httpclient-message-handlers)
- [Typed clients](https://learn.microsoft.com/en-us/dotnet/core/extensions/httpclient-factory#typed-clients)
- [Microsoft.Extensions.Http.Resilience](https://learn.microsoft.com/en-us/dotnet/core/resilience/http-resilience)
