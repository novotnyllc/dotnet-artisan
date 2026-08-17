# Output Caching and Response Caching

ASP.NET Core provides two HTTP response caching mechanisms: output caching (server-controlled, .NET 7+) and response caching (HTTP-header-driven). Output caching is preferred for most scenarios because the server controls cache behavior independently of client headers.

## Output Caching vs Response Caching

| Feature | Output Caching | Response Caching |
|---------|---------------|-----------------|
| Control | Server-side policies | HTTP `Cache-Control` headers |
| Client override | No -- server decides | Yes -- client `Cache-Control: no-cache` bypasses |
| Tag invalidation | Yes | No |
| Stampede protection | Yes | No |
| Custom storage | Yes (Redis, custom `IOutputCacheStore`) | Memory only |
| Best for | APIs, server-rendered pages | Public GET endpoints where CDN/browser caching is desired |

## Output Caching Setup

```csharp
builder.Services.AddOutputCache(options =>
{
    options.AddBasePolicy(builder => builder.Expire(TimeSpan.FromSeconds(60)));

    options.AddPolicy("ByQuery", builder =>
        builder.SetVaryByQuery("culture", "page"));

    options.AddPolicy("ByHeader", builder =>
        builder.SetVaryByHeader("Accept-Language"));

    options.AddPolicy("Tagged", builder =>
        builder.Tag("products").Expire(TimeSpan.FromMinutes(5)));
});

var app = builder.Build();
app.UseOutputCache();  // After UseRouting and UseCors, before UseAuthorization
```

### Minimal API Usage

```csharp
app.MapGet("/products", async (AppDbContext db) =>
    TypedResults.Ok(await db.Products.ToListAsync()))
    .CacheOutput("Tagged");

app.MapGet("/products/{id}", async (int id, AppDbContext db) =>
    await db.Products.FindAsync(id) is Product p
        ? TypedResults.Ok(p)
        : TypedResults.NotFound())
    .CacheOutput(p => p.Expire(TimeSpan.FromMinutes(2)).Tag($"product"));
```

### Controller Usage

```csharp
[ApiController]
[Route("api/[controller]")]
public class ProductsController : ControllerBase
{
    [HttpGet]
    [OutputCache(PolicyName = "Tagged")]
    public async Task<IActionResult> GetAll([FromServices] AppDbContext db)
        => Ok(await db.Products.ToListAsync());

    [HttpGet("{id}")]
    [OutputCache(Duration = 120)]
    public async Task<IActionResult> GetById(int id, [FromServices] AppDbContext db)
        => await db.Products.FindAsync(id) is Product p ? Ok(p) : NotFound();
}
```

## Cache Key Control

By default, the full URL (scheme, host, port, path, query string) is the cache key.

```csharp
options.AddPolicy("VaryByQuery", builder =>
    builder.SetVaryByQuery("page", "sort"));    // Only these query params vary the key

options.AddPolicy("VaryByHeader", builder =>
    builder.SetVaryByHeader("Accept-Language"));

options.AddPolicy("VaryByCustom", builder =>
    builder.VaryByValue(context =>
        new KeyValuePair<string, string>("odd-even",
            (DateTime.UtcNow.Second % 2 == 0) ? "even" : "odd")));
```

## Tag-Based Cache Invalidation

```csharp
app.MapPost("/products", async (CreateProductDto dto, AppDbContext db,
    IOutputCacheStore store, CancellationToken ct) =>
{
    var product = new Product { Name = dto.Name };
    db.Products.Add(product);
    await db.SaveChangesAsync(ct);

    // Invalidate all entries tagged "products"
    await store.EvictByTagAsync("products", ct);

    return TypedResults.Created($"/products/{product.Id}", product);
});
```

## Cache Store (Redis)

The default store is in-memory. Do **not** use `IDistributedCache` for output caching -- it lacks atomic features required for tagging. Use the built-in Redis support or a custom `IOutputCacheStore`:

```csharp
// Use the output-caching-specific Redis package
builder.Services.AddStackExchangeRedisOutputCache(options =>
{
    options.Configuration = builder.Configuration.GetConnectionString("Redis");
    options.InstanceName = "output-cache:";
});

builder.Services.AddOutputCache(options =>
{
    options.AddBasePolicy(builder => builder.Expire(TimeSpan.FromMinutes(5)));
});
```

## Cache Revalidation

Output caching supports `ETag` and `If-Modified-Since` revalidation automatically. Set `ETag` in the response and the middleware returns `304 Not Modified` when appropriate:

```csharp
app.MapGet("/etag-example", async (HttpContext context) =>
{
    var etag = $"\"{Guid.NewGuid():N}\"";
    context.Response.Headers.ETag = etag;
    await context.Response.WriteAsJsonAsync(new { data = "example" });
}).CacheOutput();
```

## Response Caching (HTTP Header-Based)

For scenarios where CDN/browser caching via standard HTTP headers is desired:

```csharp
builder.Services.AddResponseCaching();

var app = builder.Build();
app.UseResponseCaching();  // Before endpoints

app.MapGet("/api/public", () => TypedResults.Ok(new { time = DateTime.UtcNow }))
    .WithMetadata(new ResponseCacheAttribute
    {
        Duration = 300,          // Cache-Control: max-age=300
        Location = ResponseCacheLocation.Any,
        VaryByQueryKeys = ["page"]
    });
```

## Response Compression

Often paired with caching for bandwidth reduction:

```csharp
builder.Services.AddResponseCompression(options =>
{
    options.EnableForHttps = true;  // Risk: BREACH attack -- only enable for non-sensitive data
    options.Providers.Add<BrotliCompressionProvider>();
    options.Providers.Add<GzipCompressionProvider>();
});

builder.Services.Configure<BrotliCompressionProviderOptions>(options =>
    options.Level = CompressionLevel.Fastest);

var app = builder.Build();
app.UseResponseCompression();  // Before UseOutputCache
```

## HybridCache vs Output Caching

| Concern | HybridCache | Output Caching |
|---------|-------------|----------------|
| What is cached | Data objects (DTOs, query results) | Full HTTP responses (headers + body) |
| Cache key | Developer-defined string | URL + vary-by rules |
| When to use | Service layer data caching | Endpoint response caching |
| Stampede protection | Yes | Yes |
| Tag invalidation | Yes | Yes |

They can be used together: HybridCache in the service layer for data, output caching at the endpoint for full responses.

---

## Agent Gotchas

1. **Do not cache authenticated or personalized responses with output caching** -- cached responses are shared across users. An authenticated response cached and served to another user is a security vulnerability. Use `builder.NoCache()` or exclude endpoints that return user-specific data.
2. **Do not use `IDistributedCache` as the output cache store** -- `IDistributedCache` lacks atomic operations needed for tag-based eviction. Use `AddStackExchangeRedisOutputCache` or a custom `IOutputCacheStore`.
3. **Do not place `UseOutputCache()` before `UseRouting()` or `UseCors()`** -- the middleware requires route metadata. It must come after both.
4. **Do not confuse response caching with output caching** -- response caching respects client `Cache-Control` headers and cannot be programmatically invalidated. Output caching ignores client cache directives and gives the server full control.
5. **Do not enable response compression over HTTPS for sensitive data** -- compression of encrypted responses enables BREACH-style attacks. Only enable `EnableForHttps` for public, non-sensitive content.
6. **Do not cache POST/PUT/DELETE responses** -- output caching only caches responses for GET and HEAD requests by default. Attempting to cache mutating operations produces no effect.

---

## References

- [Output caching middleware](https://learn.microsoft.com/aspnet/core/performance/caching/output?view=aspnetcore-10.0)
- [Response caching in ASP.NET Core](https://learn.microsoft.com/aspnet/core/performance/caching/response?view=aspnetcore-10.0)
- [Response caching middleware](https://learn.microsoft.com/aspnet/core/performance/caching/middleware?view=aspnetcore-10.0)
- [Overview of caching](https://learn.microsoft.com/aspnet/core/performance/caching/overview?view=aspnetcore-10.0)
