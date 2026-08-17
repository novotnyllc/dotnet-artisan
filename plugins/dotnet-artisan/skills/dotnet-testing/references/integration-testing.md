# Integration Testing

Integration testing patterns for .NET applications using WebApplicationFactory, Testcontainers, and .NET Aspire testing. Covers in-process API testing, disposable infrastructure via containers, database fixture management, and test isolation strategies.

**Version assumptions:** .NET 8.0+ baseline, Testcontainers 3.x+, .NET Aspire 9.0+. Package versions for `Microsoft.AspNetCore.Mvc.Testing` must match the project's target framework major version (e.g., 8.x for net8.0, 9.x for net9.0, 10.x for net10.0). Examples below use Testcontainers 4.x APIs; the patterns apply equally to 3.x with minor namespace differences.

## WebApplicationFactory

`WebApplicationFactory<TEntryPoint>` creates an in-process test server for ASP.NET Core applications. Tests send HTTP requests without network overhead, exercising the full middleware pipeline, routing, model binding, and serialization.

### Package

```xml
<!-- Version must match target framework: 8.x for net8.0, 9.x for net9.0, etc. -->
<PackageReference Include="Microsoft.AspNetCore.Mvc.Testing" />
```

### Basic Usage

```csharp
public class OrdersApiTests : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly HttpClient _client;

    public OrdersApiTests(WebApplicationFactory<Program> factory)
    {
        _client = factory.CreateClient();
    }

    [Fact]
    public async Task GetOrders_ReturnsOkWithJsonArray()
    {
        var response = await _client.GetAsync("/api/orders");

        response.EnsureSuccessStatusCode();
        var orders = await response.Content
            .ReadFromJsonAsync<List<OrderDto>>();
        Assert.NotNull(orders);
    }

    [Fact]
    public async Task CreateOrder_ValidPayload_Returns201()
    {
        var request = new CreateOrderRequest
        {
            CustomerId = "cust-123",
            Items = [new("SKU-001", Quantity: 2)]
        };

        var response = await _client.PostAsJsonAsync("/api/orders", request);

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        Assert.NotNull(response.Headers.Location);
    }
}
```

**Important:** The `Program` class must be accessible to the test project. Either make it public or add an `InternalsVisibleTo` attribute:

```csharp
// In the API project (e.g., Program.cs or a separate file)
[assembly: InternalsVisibleTo("MyApp.Api.IntegrationTests")]
```

Or in the csproj:

```xml
<ItemGroup>
  <InternalsVisibleTo Include="MyApp.Api.IntegrationTests" />
</ItemGroup>
```

### Customizing the Test Server

Override services, configuration, or middleware using `WebApplicationFactory<T>.WithWebHostBuilder`:

```csharp
public class CustomWebAppFactory : WebApplicationFactory<Program>
{
    // Provide connection string from test fixture (e.g., Testcontainers)
    public string ConnectionString { get; set; } = "";

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Testing");

        builder.ConfigureAppConfiguration((context, config) =>
        {
            config.AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["ConnectionStrings:Default"] = ConnectionString,
                ["Features:EnableNewCheckout"] = "true"
            });
        });

        builder.ConfigureTestServices(services =>
        {
            // Replace real services with test doubles
            services.RemoveAll<IEmailSender>();
            services.AddSingleton<IEmailSender, FakeEmailSender>();

            // Replace database context with test database
            services.RemoveAll<DbContextOptions<AppDbContext>>();
            services.AddDbContext<AppDbContext>(options =>
                options.UseNpgsql(ConnectionString));
        });
    }
}
```

### Authenticated Requests

Test authenticated endpoints by configuring an authentication handler:

```csharp
public class AuthenticatedWebAppFactory : WebApplicationFactory<Program>
{
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.ConfigureTestServices(services =>
        {
            services.AddAuthentication("Test")
                .AddScheme<AuthenticationSchemeOptions, TestAuthHandler>(
                    "Test", options => { });
        });
    }
}

public class TestAuthHandler : AuthenticationHandler<AuthenticationSchemeOptions>
{
    public TestAuthHandler(
        IOptionsMonitor<AuthenticationSchemeOptions> options,
        ILoggerFactory logger,
        UrlEncoder encoder)
        : base(options, logger, encoder) { }

    protected override Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        var claims = new[]
        {
            new Claim(ClaimTypes.NameIdentifier, "test-user-id"),
            new Claim(ClaimTypes.Name, "Test User"),
            new Claim(ClaimTypes.Role, "Admin")
        };
        var identity = new ClaimsIdentity(claims, "Test");
        var principal = new ClaimsPrincipal(identity);
        var ticket = new AuthenticationTicket(principal, "Test");

        return Task.FromResult(AuthenticateResult.Success(ticket));
    }
}
```

---

## Testcontainers

Testcontainers spins up real infrastructure (databases, message brokers, caches) in Docker containers for tests. Each test run gets a fresh, disposable environment.

### Packages

```xml
<PackageReference Include="Testcontainers" Version="4.*" />
<!-- Database-specific modules -->
<PackageReference Include="Testcontainers.PostgreSql" Version="4.*" />
<PackageReference Include="Testcontainers.MsSql" Version="4.*" />
<PackageReference Include="Testcontainers.Redis" Version="4.*" />
```

### PostgreSQL Example

```csharp
public class PostgresFixture : IAsyncLifetime
{
    private readonly PostgreSqlContainer _container = new PostgreSqlBuilder()
        .WithImage("postgres:16-alpine")
        .WithDatabase("testdb")
        .WithUsername("test")
        .WithPassword("test")
        .Build();

    public string ConnectionString => _container.GetConnectionString();

    public async ValueTask InitializeAsync()
    {
        await _container.StartAsync();
    }

    public async ValueTask DisposeAsync()
    {
        await _container.DisposeAsync();
    }
}

[CollectionDefinition("Postgres")]
public class PostgresCollection : ICollectionFixture<PostgresFixture> { }

[Collection("Postgres")]
public class OrderRepositoryTests
{
    private readonly PostgresFixture _postgres;

    public OrderRepositoryTests(PostgresFixture postgres)
    {
        _postgres = postgres;
    }

    [Fact]
    public async Task Insert_ValidOrder_CanBeRetrieved()
    {
        await using var context = CreateContext(_postgres.ConnectionString);
        await context.Database.EnsureCreatedAsync();

        var order = new Order { CustomerId = "cust-1", Total = 99.99m };
        context.Orders.Add(order);
        await context.SaveChangesAsync();

        var retrieved = await context.Orders.FindAsync(order.Id);
        Assert.NotNull(retrieved);
        Assert.Equal(99.99m, retrieved.Total);
    }

    private static AppDbContext CreateContext(string connectionString)
    {
        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseNpgsql(connectionString)
            .Options;
        return new AppDbContext(options);
    }
}
```

### SQL Server Example

```csharp
public class SqlServerFixture : IAsyncLifetime
{
    private readonly MsSqlContainer _container = new MsSqlBuilder()
        .WithImage("mcr.microsoft.com/mssql/server:2022-latest")
        .Build();

    public string ConnectionString => _container.GetConnectionString();

    public async ValueTask InitializeAsync()
    {
        await _container.StartAsync();
    }

    public async ValueTask DisposeAsync()
    {
        await _container.DisposeAsync();
    }
}
```

### Combining WebApplicationFactory with Testcontainers

The most common pattern: use Testcontainers for the database and WebApplicationFactory for the API:

```csharp
public class ApiTestFactory : WebApplicationFactory<Program>, IAsyncLifetime
{
    private readonly PostgreSqlContainer _postgres = new PostgreSqlBuilder()
        .WithImage("postgres:16-alpine")
        .Build();

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.ConfigureTestServices(services =>
        {
            services.RemoveAll<DbContextOptions<AppDbContext>>();
            services.AddDbContext<AppDbContext>(options =>
                options.UseNpgsql(_postgres.GetConnectionString()));
        });
    }

    public async ValueTask InitializeAsync()
    {
        await _postgres.StartAsync();
    }

    public new async ValueTask DisposeAsync()
    {
        await _postgres.DisposeAsync();
        await base.DisposeAsync();
    }
}

public class OrdersApiIntegrationTests : IClassFixture<ApiTestFactory>
{
    private readonly HttpClient _client;
    private readonly ApiTestFactory _factory;

    public OrdersApiIntegrationTests(ApiTestFactory factory)
    {
        _factory = factory;
        _client = factory.CreateClient();
    }

    [Fact]
    public async Task CreateAndRetrieveOrder_RoundTrip()
    {
        // Ensure schema exists
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        await db.Database.EnsureCreatedAsync();

        // Create
        var createResponse = await _client.PostAsJsonAsync("/api/orders",
            new { CustomerId = "cust-1", Items = new[] { new { Sku = "SKU-1", Quantity = 2 } } });
        createResponse.EnsureSuccessStatusCode();
        var location = createResponse.Headers.Location!.ToString();

        // Retrieve
        var getResponse = await _client.GetAsync(location);
        getResponse.EnsureSuccessStatusCode();
        var order = await getResponse.Content.ReadFromJsonAsync<OrderDto>();

        Assert.Equal("cust-1", order!.CustomerId);
    }
}
```

---

## .NET Aspire Testing

.NET Aspire provides `DistributedApplicationTestingBuilder` for testing multi-service applications orchestrated with Aspire. This tests the actual distributed topology including service discovery, configuration, and health checks.

### Package

```xml
<PackageReference Include="Aspire.Hosting.Testing" Version="9.*" />
```

### Basic Aspire Test

```csharp
public class AspireIntegrationTests
{
    [Fact]
    public async Task ApiService_ReturnsHealthy()
    {
        var builder = await DistributedApplicationTestingBuilder
            .CreateAsync<Projects.MyApp_AppHost>();

        await using var app = await builder.BuildAsync();
        await app.StartAsync();

        var httpClient = app.CreateHttpClient("api-service");

        var response = await httpClient.GetAsync("/health");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    [Fact]
    public async Task ApiService_WithDatabase_ReturnsOrders()
    {
        var builder = await DistributedApplicationTestingBuilder
            .CreateAsync<Projects.MyApp_AppHost>();

        await using var app = await builder.BuildAsync();
        await app.StartAsync();

        // Wait for resources to be healthy
        var resourceNotification = app.Services
            .GetRequiredService<ResourceNotificationService>();
        await resourceNotification
            .WaitForResourceHealthyAsync("api-service")
            .WaitAsync(TimeSpan.FromSeconds(60));

        var httpClient = app.CreateHttpClient("api-service");
        var response = await httpClient.GetAsync("/api/orders");

        response.EnsureSuccessStatusCode();
    }
}
```

### Aspire with Service Overrides

Replace services in the Aspire app model for testing:

```csharp
[Fact]
public async Task ApiService_WithMockedExternalDependency()
{
    var builder = await DistributedApplicationTestingBuilder
        .CreateAsync<Projects.MyApp_AppHost>();

    // Override configuration for the API service
    builder.Services.ConfigureHttpClientDefaults(http =>
    {
        http.AddStandardResilienceHandler();
    });

    await using var app = await builder.BuildAsync();
    await app.StartAsync();

    var httpClient = app.CreateHttpClient("api-service");
    var response = await httpClient.GetAsync("/api/orders");

    response.EnsureSuccessStatusCode();
}
```

---

## Database Fixture Patterns

### Per-Test Isolation with Transactions

Roll back each test's changes using a transaction scope:

```csharp
public class TransactionalTestBase : IClassFixture<PostgresFixture>, IAsyncLifetime
{
    private readonly PostgresFixture _postgres;
    private AppDbContext _context = null!;
    private IDbContextTransaction _transaction = null!;

    public TransactionalTestBase(PostgresFixture postgres)
    {
        _postgres = postgres;
    }

    protected AppDbContext Context => _context;

    public async ValueTask InitializeAsync()
    {
        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseNpgsql(_postgres.ConnectionString)
            .Options;
        _context = new AppDbContext(options);
        await _context.Database.EnsureCreatedAsync();
        _transaction = await _context.Database.BeginTransactionAsync();
    }

    public async ValueTask DisposeAsync()
    {
        await _transaction.RollbackAsync();
        await _transaction.DisposeAsync();
        await _context.DisposeAsync();
    }
}

public class OrderTests : TransactionalTestBase
{
    public OrderTests(PostgresFixture postgres) : base(postgres) { }

    [Fact]
    public async Task Insert_ValidOrder_Persists()
    {
        Context.Orders.Add(new Order { CustomerId = "cust-1", Total = 50m });
        await Context.SaveChangesAsync();

        var count = await Context.Orders.CountAsync();
        Assert.Equal(1, count);
        // Transaction rolls back after test -- database stays clean
    }
}
```

### Per-Test Isolation with Respawn

Use Respawn to reset database state between tests by deleting data instead of rolling back transactions. This is useful when transaction rollback is not feasible (e.g., testing code that commits its own transactions):

```csharp
// NuGet: Respawn
// Combined fixture: owns the container AND the respawner
public class RespawnablePostgresFixture : IAsyncLifetime
{
    private readonly PostgreSqlContainer _container = new PostgreSqlBuilder()
        .WithImage("postgres:16-alpine")
        .Build();

    private Respawner _respawner = null!;
    private NpgsqlConnection _connection = null!;

    public string ConnectionString => _container.GetConnectionString();

    public async ValueTask InitializeAsync()
    {
        await _container.StartAsync();

        _connection = new NpgsqlConnection(ConnectionString);
        await _connection.OpenAsync();

        // Run migrations or EnsureCreated before creating respawner
        // so it knows which tables to clean
        _respawner = await Respawner.CreateAsync(_connection, new RespawnerOptions
        {
            DbAdapter = DbAdapter.Postgres,
            TablesToIgnore = ["__EFMigrationsHistory"]
        });
    }

    public async Task ResetDatabaseAsync()
    {
        await _respawner.ResetAsync(_connection);
    }

    public async ValueTask DisposeAsync()
    {
        await _connection.DisposeAsync();
        await _container.DisposeAsync();
    }
}
```

---

## Test Isolation Strategies

### Strategy Comparison

| Strategy | Speed | Isolation | Complexity | Best For |
|----------|-------|-----------|------------|----------|
| **Transaction rollback** | Fastest | High | Low | Tests that use a single DbContext |
| **Respawn (data deletion)** | Fast | High | Medium | Tests where code commits its own transactions |
| **Fresh container per class** | Slow | Highest | Low | Tests that modify schema or need complete isolation |
| **Shared container + cleanup** | Moderate | Medium | Medium | Test suites with many classes sharing infrastructure |

### Container Lifecycle Recommendations

```
Per-test:       Too slow. Never spin up a container per test.
Per-class:      Good isolation, acceptable speed with ICollectionFixture.
Per-collection: Best balance -- share one container across related test classes.
Per-assembly:   Fastest but requires careful cleanup between tests.
```

Use `ICollectionFixture<T>` (see [skill:dotnet-testing] `references/xunit.md`) to share a single container across multiple test classes while running those classes sequentially to avoid data conflicts.

---

## Testing with Redis

```csharp
public class RedisFixture : IAsyncLifetime
{
    private readonly RedisContainer _container = new RedisBuilder()
        .WithImage("redis:7-alpine")
        .Build();

    public string ConnectionString => _container.GetConnectionString();

    public async ValueTask InitializeAsync() => await _container.StartAsync();
    public async ValueTask DisposeAsync() => await _container.DisposeAsync();
}

[CollectionDefinition("Redis")]
public class RedisCollection : ICollectionFixture<RedisFixture> { }

[Collection("Redis")]
public class CacheServiceTests
{
    private readonly RedisFixture _redis;

    public CacheServiceTests(RedisFixture redis) => _redis = redis;

    [Fact]
    public async Task SetAndGet_RoundTrip_ReturnsOriginalValue()
    {
        var multiplexer = await ConnectionMultiplexer.ConnectAsync(
            _redis.ConnectionString);
        var cache = new RedisCacheService(multiplexer);

        await cache.SetAsync("key-1", new Order { Id = 1, Total = 99m });
        var result = await cache.GetAsync<Order>("key-1");

        Assert.NotNull(result);
        Assert.Equal(99m, result.Total);
    }
}
```

---

## Key Principles

- **Use WebApplicationFactory for API tests.** It is faster, more reliable, and more deterministic than testing against a deployed instance.
- **Use Testcontainers for real infrastructure.** Do not mock `DbContext` -- test against a real database to verify LINQ-to-SQL translation and constraint enforcement.
- **Share containers across test classes** via `ICollectionFixture` to avoid the overhead of starting a new container per class.
- **Choose the right isolation strategy.** Transaction rollback is fastest and simplest; use Respawn when you cannot control transaction boundaries.
- **Always clean up test data.** Leftover data from one test causes flaky failures in another. Use transaction rollback, Respawn, or fresh containers.
- **Match `Microsoft.AspNetCore.Mvc.Testing` version to TFM.** Using the wrong version causes runtime binding failures.

---

## Agent Gotchas

1. **Do not hardcode `Microsoft.AspNetCore.Mvc.Testing` versions.** The package version must match the project's target framework major version. Specifying e.g. `Version="8.0.0"` breaks net9.0 projects.
2. **Do not forget `InternalsVisibleTo` for the `Program` class.** Without it, `WebApplicationFactory<Program>` cannot access the entry point and tests fail at compile time.
3. **Do not use `EnsureCreated()` with Respawn.** `EnsureCreated()` does not track migrations. Use `Database.MigrateAsync()` for production schemas, or `EnsureCreated()` only for simple test schemas.
4. **Do not dispose `WebApplicationFactory` before `HttpClient`.** The factory owns the test server; disposing it invalidates all clients. Let xUnit manage disposal via `IClassFixture`.
5. **Do not use `localhost` ports with Testcontainers.** Testcontainers maps random host ports to container ports. Always use the connection string from the container object (e.g., `_container.GetConnectionString()`), never hardcoded ports.
6. **Do not skip Docker availability checks in CI.** Testcontainers requires a running Docker daemon. Ensure your CI environment has Docker available, or use conditional test skipping when Docker is unavailable.

---

## References

- [Integration tests in ASP.NET Core](https://learn.microsoft.com/en-us/aspnet/core/test/integration-tests)
- [WebApplicationFactory](https://learn.microsoft.com/en-us/dotnet/api/microsoft.aspnetcore.mvc.testing.webapplicationfactory-1)
- [Testcontainers for .NET](https://dotnet.testcontainers.org/)
- [.NET Aspire testing](https://learn.microsoft.com/en-us/dotnet/aspire/fundamentals/testing)
- [Respawn](https://github.com/jbogard/Respawn)
- [Testcontainers PostgreSQL module](https://dotnet.testcontainers.org/modules/postgres/)
