# Aspire Testing

Integration testing for .NET Aspire distributed applications using `DistributedApplicationTestingBuilder` from `Aspire.Hosting.Testing`. Covers creating test hosts, getting HTTP clients, waiting for resource health, environment customization, container cleanup, and when to choose Aspire testing vs WebApplicationFactory.

Cross-references: `references/integration-testing.md` for WebApplicationFactory and Testcontainers, `references/xunit.md` for xUnit fixture lifecycle.

---

## Package

```xml
<PackageReference Include="Aspire.Hosting.Testing" Version="9.*" />
```

The test project must reference the AppHost project directly:

```xml
<ProjectReference Include="..\MyApp.AppHost\MyApp.AppHost.csproj" />
```

Version follows the Aspire SDK release cadence. The API surface is stable from 9.0 onward.

---

## Basic Test Lifecycle

```csharp
public class AspireIntegrationTests
{
    private static readonly TimeSpan DefaultTimeout = TimeSpan.FromSeconds(30);

    [Fact]
    public async Task WebFrontend_ReturnsOk()
    {
        // Create builder from AppHost entry point
        var builder = await DistributedApplicationTestingBuilder
            .CreateAsync<Projects.MyApp_AppHost>();

        builder.Services.ConfigureHttpClientDefaults(http =>
            http.AddStandardResilienceHandler());

        // Build and start
        await using var app = await builder.BuildAsync();
        await app.StartAsync();

        // Wait for resource health
        await app.ResourceNotifications
            .WaitForResourceHealthyAsync("webfrontend")
            .WaitAsync(DefaultTimeout);

        // Act + Assert
        using var httpClient = app.CreateHttpClient("webfrontend");
        using var response = await httpClient.GetAsync("/");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }
}
```

`app.CreateHttpClient("resource-name")` returns an `HttpClient` with the correct base address via Aspire service discovery. The resource name must exactly match the string in `AddProject`/`AddContainer` in the AppHost.

---

## Waiting for Resources

Always wait for health before making assertions. Always apply `.WaitAsync(timeout)` to prevent indefinite hangs.

```csharp
// Single resource
await app.ResourceNotifications
    .WaitForResourceHealthyAsync("apiservice")
    .WaitAsync(TimeSpan.FromSeconds(60));

// Multiple resources in parallel
await Task.WhenAll(
    app.ResourceNotifications.WaitForResourceHealthyAsync("apiservice")
        .WaitAsync(TimeSpan.FromSeconds(60)),
    app.ResourceNotifications.WaitForResourceHealthyAsync("postgres")
        .WaitAsync(TimeSpan.FromSeconds(60)));
```

---

## Configuring the Test Host

```csharp
var builder = await DistributedApplicationTestingBuilder
    .CreateAsync<Projects.MyApp_AppHost>();

// Logging -- control verbosity
builder.Services.AddLogging(logging =>
{
    logging.SetMinimumLevel(LogLevel.Debug);
    logging.AddFilter("Aspire.", LogLevel.Debug);
});

// HTTP resilience -- retries transient 503s during startup
builder.Services.ConfigureHttpClientDefaults(http =>
    http.AddStandardResilienceHandler());
```

For xUnit, use `MartinCostello.Logging.XUnit` to route logs to `ITestOutputHelper`.

---

## xUnit Integration with IAsyncLifetime

Share an Aspire app across multiple tests in a class:

```csharp
public class OrderServiceTests : IAsyncLifetime
{
    private DistributedApplication _app = null!;
    private HttpClient _apiClient = null!;

    public async ValueTask InitializeAsync()
    {
        var builder = await DistributedApplicationTestingBuilder
            .CreateAsync<Projects.MyApp_AppHost>();
        builder.Services.ConfigureHttpClientDefaults(http =>
            http.AddStandardResilienceHandler());

        _app = await builder.BuildAsync();
        await _app.StartAsync();
        await _app.ResourceNotifications
            .WaitForResourceHealthyAsync("apiservice")
            .WaitAsync(TimeSpan.FromSeconds(60));

        _apiClient = _app.CreateHttpClient("apiservice");
    }

    [Fact]
    public async Task GetOrders_ReturnsOk()
    {
        var response = await _apiClient.GetAsync("/api/orders");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    [Fact]
    public async Task CreateOrder_Returns201()
    {
        var response = await _apiClient.PostAsJsonAsync("/api/orders",
            new { CustomerId = "cust-1", Items = new[] { new { Sku = "X", Qty = 1 } } });
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
    }

    public async ValueTask DisposeAsync()
    {
        _apiClient.Dispose();
        await _app.DisposeAsync();
    }
}
```

---

## Testing Environment Variables

Validate orchestration wiring without starting resources:
```csharp
[Fact]
public async Task WebFrontend_HasApiServiceReference()
{
    var builder = await DistributedApplicationTestingBuilder
        .CreateAsync<Projects.MyApp_AppHost>();

    var frontend = builder.CreateResourceBuilder<ProjectResource>("webfrontend");
    var config = await ExecutionConfigurationBuilder
        .Create(frontend.Resource)
        .WithEnvironmentVariablesConfig()
        .BuildAsync(new(DistributedApplicationOperation.Publish),
            NullLogger.Instance, CancellationToken.None);

    var envVars = config.EnvironmentVariables.ToDictionary();
    Assert.Contains(envVars, kvp =>
        kvp.Key == "APISERVICE_HTTPS" &&
        kvp.Value == "{apiservice.bindings.https.url}");
}
```

---

## Testing with Database and Cache Resources

Aspire manages container lifecycle automatically. Tests wait for readiness and interact through service endpoints.
```csharp
[Fact]
public async Task ApiWithPostgres_RoundTrip()
{
    var builder = await DistributedApplicationTestingBuilder
        .CreateAsync<Projects.MyApp_AppHost>();
    builder.Services.ConfigureHttpClientDefaults(http =>
        http.AddStandardResilienceHandler());

    await using var app = await builder.BuildAsync();
    await app.StartAsync();

    await Task.WhenAll(
        app.ResourceNotifications.WaitForResourceHealthyAsync("apiservice")
            .WaitAsync(TimeSpan.FromSeconds(60)),
        app.ResourceNotifications.WaitForResourceHealthyAsync("postgres")
            .WaitAsync(TimeSpan.FromSeconds(60)));

    using var client = app.CreateHttpClient("apiservice");
    var createResp = await client.PostAsJsonAsync("/api/orders",
        new { CustomerId = "test-1", Total = 42.0 });
    Assert.Equal(HttpStatusCode.Created, createResp.StatusCode);

    var getResp = await client.GetAsync(createResp.Headers.Location!.ToString());
    getResp.EnsureSuccessStatusCode();
}
```

---

## When to Use Aspire Testing vs WebApplicationFactory

| Scenario | Recommendation |
|----------|---------------|
| Single API, no distributed dependencies | **WebApplicationFactory** -- lighter, no Docker |
| Multiple services with inter-service communication | **Aspire testing** -- validates full topology |
| Testing service discovery and resource wiring | **Aspire testing** |
| Unit-testing a single endpoint with mocks | **WebApplicationFactory** |
| CI without Docker available | **WebApplicationFactory** |

---

## Container Cleanup and Test Isolation

`DistributedApplication` implements `IAsyncDisposable`. Disposing stops and removes all containers. Always use `await using` or explicit `DisposeAsync`. Each test run gets fresh containers with no shared state. To share across test classes, use `ICollectionFixture<T>` and manage data isolation at the application level.

---

## Agent Gotchas

1. **Do not forget that Docker is required.** Aspire testing starts real containers. Tests fail immediately without Docker. Guard CI with availability checks.
2. **Do not omit `.WaitAsync(timeout)` on resource waits.** Without a timeout, `WaitForResourceHealthyAsync` hangs forever if a container fails to start.
3. **Do not hardcode resource names.** Names must exactly match the AppHost's `AddProject`/`AddContainer` string. A typo causes `CreateHttpClient` to throw with an unhelpful error.
4. **Do not skip `ConfigureHttpClientDefaults` with resilience.** Without the standard resilience handler, first requests often hit 503 or connection refused during startup.
5. **Do not assume fast container startup.** Database containers take 10-30 seconds; Redis is 2-5 seconds. Set timeouts accordingly to avoid flaky CI.
6. **Do not forget to dispose `DistributedApplication`.** Undisposed apps leave orphaned containers. Always use `await using`.
7. **Do not run Aspire tests in parallel without isolation.** Port conflicts and data races occur. Use `[Collection]` to serialize test classes sharing the same AppHost.

---

## References

- [Write your first .NET Aspire test](https://learn.microsoft.com/en-us/dotnet/aspire/fundamentals/testing)
- [Aspire.Hosting.Testing on NuGet](https://www.nuget.org/packages/Aspire.Hosting.Testing)
- [DistributedApplicationTestingBuilder API](https://learn.microsoft.com/en-us/dotnet/api/aspire.hosting.testing.distributedapplicationtestingbuilder)
- [ResourceNotificationService API](https://learn.microsoft.com/en-us/dotnet/api/aspire.hosting.applicationmodel.resourcenotificationservice)
