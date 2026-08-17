# API Versioning

API versioning strategies for ASP.NET Core using the `Asp.Versioning` library family. URL segment versioning (`/api/v1/`) is the preferred approach for simplicity and discoverability. This skill covers URL, header, and query string versioning with configuration for both Minimal APIs and MVC controllers, sunset policy enforcement, and migration from legacy packages.

## Package Landscape

| Package | Target | Status |
|---------|--------|--------|
| `Asp.Versioning.Http` | Minimal APIs | **Current** |
| `Asp.Versioning.Mvc.ApiExplorer` | MVC controllers + API Explorer | **Current** |
| `Asp.Versioning.Mvc` | MVC controllers (no API Explorer) | **Current** |
| `Microsoft.AspNetCore.Mvc.Versioning` | MVC controllers | **Legacy** -- migrate to `Asp.Versioning.Mvc` |
| `Microsoft.AspNetCore.Mvc.Versioning.ApiExplorer` | MVC + API Explorer | **Legacy** -- migrate to `Asp.Versioning.Mvc.ApiExplorer` |

Install for Minimal APIs:

```xml
<PackageReference Include="Asp.Versioning.Http" Version="8.*" />
```

Install for MVC controllers:

```xml
<PackageReference Include="Asp.Versioning.Mvc.ApiExplorer" Version="8.*" />
```

---

## URL Segment Versioning (Preferred)

URL segment versioning embeds the version in the path (`/api/v1/products`). It is the simplest strategy, works with all HTTP clients, is cacheable, and clearly visible in logs and documentation.

### Minimal APIs

```csharp
builder.Services.AddApiVersioning(options =>
{
    options.DefaultApiVersion = new ApiVersion(1, 0);
    options.AssumeDefaultVersionWhenUnspecified = true;
    options.ReportApiVersions = true; // Adds api-supported-versions header
    options.ApiVersionReader = new UrlSegmentApiVersionReader();
});

var app = builder.Build();

var versionSet = app.NewApiVersionSet()
    .HasApiVersion(new ApiVersion(1, 0))
    .HasApiVersion(new ApiVersion(2, 0))
    .ReportApiVersions()
    .Build();

var v1 = app.MapGroup("/api/v{version:apiVersion}/products")
    .WithApiVersionSet(versionSet)
    .MapToApiVersion(new ApiVersion(1, 0));

var v2 = app.MapGroup("/api/v{version:apiVersion}/products")
    .WithApiVersionSet(versionSet)
    .MapToApiVersion(new ApiVersion(2, 0));

// V1: returns basic product info
v1.MapGet("/", async (AppDbContext db) =>
    TypedResults.Ok(await db.Products
        .Select(p => new ProductV1Dto(p.Id, p.Name, p.Price))
        .ToListAsync()));

// V2: returns extended product info with category
v2.MapGet("/", async (AppDbContext db) =>
    TypedResults.Ok(await db.Products
        .Select(p => new ProductV2Dto(p.Id, p.Name, p.Price, p.Category, p.CreatedAt))
        .ToListAsync()));
```

### MVC Controllers

```csharp
builder.Services.AddApiVersioning(options =>
{
    options.DefaultApiVersion = new ApiVersion(1, 0);
    options.AssumeDefaultVersionWhenUnspecified = true;
    options.ReportApiVersions = true;
    options.ApiVersionReader = new UrlSegmentApiVersionReader();
})
.AddMvc()
.AddApiExplorer(options =>
{
    options.GroupNameFormat = "'v'VVV"; // e.g., v1, v2
    options.SubstituteApiVersionInUrl = true;
});

// V1 controller
[ApiController]
[Route("api/v{version:apiVersion}/products")]
[ApiVersion("1.0")]
public sealed class ProductsController(AppDbContext db) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> GetAll() =>
        Ok(await db.Products
            .Select(p => new ProductV1Dto(p.Id, p.Name, p.Price))
            .ToListAsync());
}

// V2 controller -- use explicit route, not [controller] token
[ApiController]
[Route("api/v{version:apiVersion}/products")]
[ApiVersion("2.0")]
public sealed class ProductsV2Controller(AppDbContext db) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> GetAll() =>
        Ok(await db.Products
            .Select(p => new ProductV2Dto(p.Id, p.Name, p.Price, p.Category, p.CreatedAt))
            .ToListAsync());
}
```

---

## Header Versioning

Header versioning reads the API version from a custom request header. Keeps URLs clean but is less discoverable and harder to test from a browser.

```csharp
builder.Services.AddApiVersioning(options =>
{
    options.DefaultApiVersion = new ApiVersion(1, 0);
    options.AssumeDefaultVersionWhenUnspecified = true;
    options.ReportApiVersions = true;
    options.ApiVersionReader = new HeaderApiVersionReader("X-Api-Version");
});
```

Client request:

```http
GET /api/products HTTP/1.1
Host: api.example.com
X-Api-Version: 2.0
```

---

## Query String Versioning

Query string versioning uses a query parameter (default: `api-version`). Simple to use but pollutes URLs and may conflict with caching strategies.

```csharp
builder.Services.AddApiVersioning(options =>
{
    options.DefaultApiVersion = new ApiVersion(1, 0);
    options.AssumeDefaultVersionWhenUnspecified = true;
    options.ReportApiVersions = true;
    options.ApiVersionReader = new QueryStringApiVersionReader("api-version");
});
```

Client request:

```http
GET /api/products?api-version=2.0 HTTP/1.1
Host: api.example.com
```

---

## Combining Version Readers

Multiple readers can be combined. The first reader that resolves a version wins. This is useful during migration from one strategy to another:

```csharp
options.ApiVersionReader = ApiVersionReader.Combine(
    new UrlSegmentApiVersionReader(),
    new HeaderApiVersionReader("X-Api-Version"),
    new QueryStringApiVersionReader("api-version"));
```

---

## Sunset Policies

Sunset policies communicate to consumers that an API version is deprecated and will be removed. The `Sunset` HTTP response header follows [RFC 8594](https://datatracker.ietf.org/doc/html/rfc8594).

```csharp
builder.Services.AddApiVersioning(options =>
{
    options.DefaultApiVersion = new ApiVersion(2, 0);
    options.ReportApiVersions = true;
    options.Policies.Sunset(1.0)
        .Effective(new DateTimeOffset(2026, 6, 1, 0, 0, 0, TimeSpan.Zero))
        .Link("https://docs.example.com/api/migration-v1-to-v2")
            .Title("V1 to V2 Migration Guide")
            .Type("text/html");
});
```

Response headers for a v1 request:

```http
api-supported-versions: 1.0, 2.0
api-deprecated-versions: 1.0
Sunset: Sun, 01 Jun 2026 00:00:00 GMT
Link: <https://docs.example.com/api/migration-v1-to-v2>; rel="sunset"; title="V1 to V2 Migration Guide"; type="text/html"
```

### Deprecating a Version

Mark a version as deprecated using the version set (Minimal APIs) or attribute (MVC):

```csharp
// Minimal APIs
var versionSet = app.NewApiVersionSet()
    .HasApiVersion(new ApiVersion(1, 0))
    .HasDeprecatedApiVersion(new ApiVersion(1, 0))
    .HasApiVersion(new ApiVersion(2, 0))
    .ReportApiVersions()
    .Build();

// MVC controllers
[ApiVersion("1.0", Deprecated = true)]
[ApiVersion("2.0")]
public sealed class ProductsController : ControllerBase { }
```

---

## Migration from Legacy Packages

Projects using `Microsoft.AspNetCore.Mvc.Versioning` should migrate to `Asp.Versioning.Mvc` (or `Asp.Versioning.Http` for Minimal APIs). The API surface is largely compatible with namespace changes:

| Legacy namespace | Current namespace |
|-----------------|-------------------|
| `Microsoft.AspNetCore.Mvc.Versioning` | `Asp.Versioning` |
| `Microsoft.AspNetCore.Mvc.ApiExplorer` | `Asp.Versioning.ApiExplorer` |

Key migration steps:
1. Replace NuGet package references
2. Update `using` directives from `Microsoft.AspNetCore.Mvc.Versioning` to `Asp.Versioning`
3. Update service registration from `services.AddApiVersioning()` (legacy extension) to the current extension from `Asp.Versioning`
4. Review any custom `IApiVersionReader` implementations for breaking changes

See the [migration guide](https://github.com/dotnet/aspnet-api-versioning/wiki/Migration-Guide) for detailed steps.

---

## Version Strategy Decision Guide

| Strategy | Pros | Cons | Best for |
|----------|------|------|----------|
| **URL segment** (`/api/v1/`) | Simple, visible, cacheable, works everywhere | URL changes per version | Public APIs, most projects (preferred) |
| **Header** (`X-Api-Version: 1.0`) | Clean URLs, no path changes | Less discoverable, harder to test | Internal APIs with controlled clients |
| **Query string** (`?api-version=1.0`) | Easy to add, no path changes | Pollutes URL, cache key issues | Quick prototyping, legacy compatibility |

**Recommendation:** Start with URL segment versioning for all new projects. Add header or query string readers only when migrating from an existing strategy or when specific client constraints require it.

---

## Agent Gotchas

1. **Do not use the legacy `Microsoft.AspNetCore.Mvc.Versioning` package for new projects** -- use `Asp.Versioning.Http` (Minimal APIs) or `Asp.Versioning.Mvc` (MVC controllers).
2. **Do not hardcode version numbers in package references** -- use version ranges (e.g., `8.*`) so the package version matches the latest compatible release.
3. **Do not forget `ReportApiVersions = true`** -- without it, clients cannot discover available versions from response headers.
4. **Do not mix `MapToApiVersion` and route group prefixes inconsistently** -- each route group should target exactly one API version.
5. **Do not deprecate a version without a sunset policy** -- always provide a sunset date and migration link so consumers can plan.
6. **Do not use `AssumeDefaultVersionWhenUnspecified = true` for public APIs** -- it hides versioning requirements from consumers. Require explicit version selection instead.

---

## Prerequisites

- .NET 8.0+ (LTS baseline)
- `Asp.Versioning.Http` for Minimal APIs
- `Asp.Versioning.Mvc.ApiExplorer` for MVC controllers with API Explorer integration

---

## References

- [ASP.NET API Versioning](https://github.com/dotnet/aspnet-api-versioning)
- [API Versioning Wiki](https://github.com/dotnet/aspnet-api-versioning/wiki)
- [Asp.Versioning.Http NuGet](https://www.nuget.org/packages/Asp.Versioning.Http)
- [Asp.Versioning.Mvc NuGet](https://www.nuget.org/packages/Asp.Versioning.Mvc)
- [RFC 8594 - The Sunset HTTP Header](https://datatracker.ietf.org/doc/html/rfc8594)
