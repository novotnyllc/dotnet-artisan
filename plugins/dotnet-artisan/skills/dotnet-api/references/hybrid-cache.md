# HybridCache

HybridCache (.NET 9+) provides a unified two-level caching API with built-in stampede protection, tag-based eviction, and configurable serialization. It replaces the manual dual-layer `IMemoryCache` + `IDistributedCache` pattern.

## What It Replaces

The legacy pattern requires manually coordinating two cache layers:

```csharp
// AVOID: manual dual-layer caching (verbose, no stampede protection)
public async Task<Product?> GetProductAsync(int id)
{
    var key = $"product:{id}";

    if (_memoryCache.TryGetValue(key, out Product? product))
        return product;

    var bytes = await _distributedCache.GetAsync(key);
    if (bytes is not null)
    {
        product = JsonSerializer.Deserialize<Product>(bytes);
        _memoryCache.Set(key, product, TimeSpan.FromMinutes(2));
        return product;
    }

    product = await _db.Products.FindAsync(id);
    var serialized = JsonSerializer.SerializeToUtf8Bytes(product);
    await _distributedCache.SetAsync(key, serialized,
        new DistributedCacheEntryOptions { AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(10) });
    _memoryCache.Set(key, product, TimeSpan.FromMinutes(2));
    return product;
}
```

HybridCache reduces this to a single call with automatic stampede protection.

## Setup

```xml
<PackageReference Include="Microsoft.Extensions.Caching.Hybrid" Version="9.*" />
```

```csharp
builder.Services.AddHybridCache(options =>
{
    options.MaximumPayloadBytes = 1024 * 1024; // 1 MB -- entries exceeding this are not cached
    options.MaximumKeyLength = 1024;           // keys exceeding this bypass cache
    options.DefaultEntryOptions = new HybridCacheEntryOptions
    {
        Expiration = TimeSpan.FromMinutes(10),           // L2 (distributed) TTL
        LocalCacheExpiration = TimeSpan.FromMinutes(2)   // L1 (in-memory) TTL
    };
});
```

## GetOrCreateAsync Usage

```csharp
public class ProductService(HybridCache cache, AppDbContext db)
{
    public async Task<Product> GetProductAsync(int id, CancellationToken ct = default)
    {
        return await cache.GetOrCreateAsync(
            $"product:{id}",
            async cancel => await db.Products.FindAsync([id], cancel)
                ?? throw new NotFoundException($"Product {id} not found"),
            token: ct
        );
    }

    // Override defaults per call
    public async Task<List<Product>> GetFeaturedAsync(CancellationToken ct = default)
    {
        var options = new HybridCacheEntryOptions
        {
            Expiration = TimeSpan.FromHours(1),
            LocalCacheExpiration = TimeSpan.FromMinutes(10)
        };

        return await cache.GetOrCreateAsync(
            "products:featured",
            async cancel => await db.Products
                .Where(p => p.IsFeatured)
                .ToListAsync(cancel),
            options,
            token: ct
        );
    }
}
```

Stampede protection is built-in: if multiple concurrent requests hit the same key, only one executes the factory and the others wait for the result.

## Tag-Based Eviction

```csharp
// Tag entries when creating them
public async Task<Product> GetProductAsync(int id, CancellationToken ct = default)
{
    var tags = new[] { "products", $"product:{id}" };

    return await cache.GetOrCreateAsync(
        $"product:{id}",
        async cancel => await db.Products.FindAsync([id], cancel)!,
        tags: tags,
        token: ct
    );
}

// Invalidate by tag
public async Task InvalidateProductAsync(int id)
{
    await cache.RemoveByTagAsync($"product:{id}");
}

// Invalidate all products
public async Task InvalidateAllProductsAsync()
{
    await cache.RemoveByTagAsync("products");
}

// Invalidate EVERYTHING (wildcard)
await cache.RemoveByTagAsync("*");
```

Tag-based eviction is logical -- it marks entries as stale so subsequent reads treat them as cache misses. Entries still expire naturally from L1/L2 based on TTL.

## Explicit Remove and Set

```csharp
// Remove by key
await cache.RemoveAsync("product:42");

// Set without get (pre-populate cache)
await cache.SetAsync("product:42", product, options, tags);
```

## Integration with Redis as L2

```csharp
// Register Redis as the IDistributedCache, then HybridCache uses it automatically
builder.Services.AddStackExchangeRedisCache(options =>
{
    options.Configuration = builder.Configuration.GetConnectionString("Redis");
});

builder.Services.AddHybridCache(options =>
{
    options.DefaultEntryOptions = new HybridCacheEntryOptions
    {
        Expiration = TimeSpan.FromMinutes(30),
        LocalCacheExpiration = TimeSpan.FromMinutes(5)
    };
});
```

Without an `IDistributedCache` registration, HybridCache still works as L1-only with stampede protection.

## Custom Serialization

Default: `System.Text.Json`. For protobuf or other formats:

```csharp
builder.Services.AddHybridCache(options => { /* ... */ })
    .AddSerializer<MyProtobufMessage, GoogleProtobufSerializer<MyProtobufMessage>>()
    .AddSerializerFactory<GoogleProtobufSerializerFactory>();  // general-purpose
```

## Object Reuse

By default, HybridCache deserializes a fresh instance per caller (matching `IDistributedCache` semantics). For immutable types, opt in to instance reuse to avoid deserialization overhead:

```csharp
[ImmutableObject(true)]
public sealed record ProductDto(int Id, string Name, decimal Price);
```

Both `sealed` and `[ImmutableObject(true)]` are required for reuse.

## When to Use What

| Scenario | Use |
|----------|-----|
| Data caching (DB results, API responses) across multiple servers | **HybridCache** |
| Full HTTP response caching on the server | **Output caching** |
| HTTP response caching delegated to client/CDN | **Response caching** |
| Single-server, simple in-memory cache | **IMemoryCache** |

---

## Agent Gotchas

1. **Do not confuse HybridCache with output caching** -- HybridCache caches data objects, output caching caches entire HTTP responses. They solve different problems.
2. **Do not expect tag eviction to actively purge L1 on other servers** -- tag invalidation is logical and affects only the current server's L1 and the L2. Other servers' L1 entries remain until their local TTL expires.
3. **Do not cache mutable objects without understanding reuse semantics** -- by default each caller gets a deserialized copy. If you mark a type as immutable but then mutate it, all callers sharing the instance see corrupted data.
4. **Do not set `LocalCacheExpiration` longer than `Expiration`** -- the L1 TTL should be shorter than L2 so the local cache refreshes from the distributed store.
5. **Do not use extremely long cache keys** -- keys exceeding `MaximumKeyLength` (default 1024) bypass caching entirely. This is logged but easy to miss.

---

## References

- [HybridCache library in ASP.NET Core](https://learn.microsoft.com/aspnet/core/performance/caching/hybrid?view=aspnetcore-10.0)
- [Caching in .NET -- Hybrid caching](https://learn.microsoft.com/dotnet/core/extensions/caching#hybrid-caching)
- [Overview of caching in ASP.NET Core](https://learn.microsoft.com/aspnet/core/performance/caching/overview?view=aspnetcore-10.0)
