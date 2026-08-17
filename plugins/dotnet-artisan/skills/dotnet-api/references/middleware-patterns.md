# Middleware Patterns

ASP.NET Core middleware patterns for the HTTP request pipeline. Covers correct ordering, writing custom middleware as classes or inline delegates, short-circuit logic, request/response manipulation, exception handling middleware, and conditional middleware registration.

## Pipeline Ordering

Middleware executes in the order it is registered. The order is critical -- placing middleware in the wrong position causes subtle bugs (missing CORS headers, unhandled exceptions, auth bypasses).

### Recommended Order

```csharp
var app = builder.Build();

// 1. Exception handling (outermost -- catches everything below)
app.UseExceptionHandler("/error");

// 2. HSTS (before any response is sent)
if (!app.Environment.IsDevelopment())
{
    app.UseHsts();
}

// 3. HTTPS redirection
app.UseHttpsRedirection();

// 4. Static files (short-circuits for static content before routing)
app.UseStaticFiles();

// 5. Routing (matches endpoints but does not execute them yet)
// .NET 6+ calls UseRouting() implicitly if omitted; shown here for clarity
app.UseRouting();

// 6. CORS (must be after routing, before auth)
app.UseCors();

// 7. Authentication (identifies the user)
app.UseAuthentication();

// 8. Authorization (checks permissions against the matched endpoint)
app.UseAuthorization();

// 9. Custom middleware (runs after auth, before endpoint execution)
app.UseRequestLogging();

// 10. Endpoint execution (terminal -- executes the matched endpoint)
app.MapControllers();
app.MapRazorPages();
```

### Why Order Matters

| Mistake | Consequence |
|---------|-------------|
| `UseAuthorization()` before `UseRouting()` | Authorization has no endpoint metadata -- all requests pass |
| `UseCors()` after `UseAuthorization()` | Preflight requests fail because they lack auth tokens |
| `UseExceptionHandler()` after custom middleware | Exceptions in custom middleware are unhandled |
| `UseStaticFiles()` after `UseAuthorization()` | Static files require authentication unnecessarily |

---

## Custom Middleware Classes

Convention-based middleware uses a constructor with `RequestDelegate` and an `InvokeAsync` method. This is the standard pattern for reusable middleware.

### Basic Pattern

```csharp
public sealed class RequestTimingMiddleware
{
    private readonly RequestDelegate _next;
    private readonly ILogger<RequestTimingMiddleware> _logger;

    public RequestTimingMiddleware(
        RequestDelegate next,
        ILogger<RequestTimingMiddleware> logger)
    {
        _next = next;
        _logger = logger;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        var stopwatch = Stopwatch.StartNew();

        try
        {
            await _next(context);
        }
        finally
        {
            stopwatch.Stop();
            _logger.LogInformation(
                "Request {Method} {Path} completed in {ElapsedMs}ms with status {StatusCode}",
                context.Request.Method,
                context.Request.Path,
                stopwatch.ElapsedMilliseconds,
                context.Response.StatusCode);
        }
    }
}

// Registration via extension method (conventional pattern)
public static class RequestTimingMiddlewareExtensions
{
    public static IApplicationBuilder UseRequestTiming(
        this IApplicationBuilder app)
        => app.UseMiddleware<RequestTimingMiddleware>();
}

// Usage in Program.cs
app.UseRequestTiming();
```

### Factory-Based (IMiddleware)

For middleware that requires scoped services, implement `IMiddleware`. This uses DI to create middleware instances per-request instead of once at startup:

```csharp
public sealed class TenantMiddleware : IMiddleware
{
    private readonly TenantDbContext _db;

    // Scoped services can be injected directly
    public TenantMiddleware(TenantDbContext db)
    {
        _db = db;
    }

    public async Task InvokeAsync(
        HttpContext context, RequestDelegate next)
    {
        var tenantId = context.Request.Headers["X-Tenant-Id"]
            .FirstOrDefault();

        if (tenantId is not null)
        {
            var tenant = await _db.Tenants.FindAsync(tenantId);
            context.Items["Tenant"] = tenant;
        }

        await next(context);
    }
}

// IMiddleware requires explicit DI registration
builder.Services.AddScoped<TenantMiddleware>();

// Then register in pipeline
app.UseMiddleware<TenantMiddleware>();
```

**Convention-based vs IMiddleware:**

| Aspect | Convention-based | `IMiddleware` |
|--------|-----------------|---------------|
| Lifetime | Singleton (created once) | Per-request (from DI) |
| Scoped services | Via `InvokeAsync` parameters only | Via constructor injection |
| Registration | `UseMiddleware<T>()` only | Requires `services.Add*<T>()` + `UseMiddleware<T>()` |
| Performance | Slightly faster (no per-request allocation) | Resolved from DI each request (lifetime depends on registration) |

---

## Inline Middleware

For simple, one-off middleware logic, use `app.Use()`, `app.Map()`, or `app.Run()`:

### app.Use -- Pass-Through

```csharp
// Adds a header to every response, then passes to next middleware
app.Use(async (context, next) =>
{
    context.Response.Headers["X-Request-Id"] =
        context.TraceIdentifier;

    await next(context);
});
```

### app.Run -- Terminal

```csharp
// Terminal middleware -- does NOT call next
app.Run(async context =>
{
    await context.Response.WriteAsync("Fallback response");
});
```

### app.Map -- Branch by Path

```csharp
// Branch the pipeline for requests matching /api/diagnostics
app.Map("/api/diagnostics", diagnosticApp =>
{
    diagnosticApp.Run(async context =>
    {
        var data = new
        {
            MachineName = Environment.MachineName,
            Timestamp = DateTimeOffset.UtcNow
        };
        await context.Response.WriteAsJsonAsync(data);
    });
});
```

---

## Short-Circuit Logic

Middleware can short-circuit the pipeline by not calling `next()`. Use this for early validation, rate limiting, or feature flags.

### Request Validation

```csharp
public sealed class ApiKeyMiddleware
{
    private readonly RequestDelegate _next;
    private readonly string _expectedKey;

    public ApiKeyMiddleware(
        RequestDelegate next,
        IConfiguration config)
    {
        _next = next;
        _expectedKey = config["ApiKey"]
            ?? throw new InvalidOperationException(
                "ApiKey configuration is required");
    }

    public async Task InvokeAsync(HttpContext context)
    {
        if (!context.Request.Headers.TryGetValue(
                "X-Api-Key", out var providedKey)
            || !string.Equals(
                providedKey, _expectedKey, StringComparison.Ordinal))
        {
            context.Response.StatusCode =
                StatusCodes.Status401Unauthorized;
            await context.Response.WriteAsJsonAsync(new
            {
                Error = "Invalid or missing API key"
            });
            return; // Short-circuit -- do NOT call _next
        }

        await _next(context);
    }
}
```

### Feature Flag Gate

```csharp
app.UseWhen(
    context => context.Request.Path.StartsWithSegments("/beta"),
    betaApp =>
    {
        betaApp.Use(async (context, next) =>
        {
            var featureManager = context.RequestServices
                .GetRequiredService<IFeatureManager>();

            if (!await featureManager.IsEnabledAsync("BetaFeatures"))
            {
                context.Response.StatusCode =
                    StatusCodes.Status404NotFound;
                return; // Short-circuit
            }

            await next(context);
        });
    });
```

---

## Request and Response Manipulation

### Reading the Request Body

The request body is a forward-only stream by default. Enable buffering to read it multiple times:

```csharp
public sealed class RequestLoggingMiddleware
{
    private readonly RequestDelegate _next;
    private readonly ILogger<RequestLoggingMiddleware> _logger;

    public RequestLoggingMiddleware(
        RequestDelegate next,
        ILogger<RequestLoggingMiddleware> logger)
    {
        _next = next;
        _logger = logger;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        // Enable buffering so the body can be read multiple times
        context.Request.EnableBuffering();

        if (context.Request.ContentLength > 0
            && context.Request.ContentLength < 64_000)
        {
            context.Request.Body.Position = 0;
            using var reader = new StreamReader(
                context.Request.Body, leaveOpen: true);
            var body = await reader.ReadToEndAsync();
            _logger.LogDebug(
                "Request body for {Path}: {Body}",
                context.Request.Path, body);
            context.Request.Body.Position = 0; // Reset for next reader
        }

        await _next(context);
    }
}
```

### Modifying the Response

To capture or modify the response body, replace `context.Response.Body` with a `MemoryStream`:

```csharp
public async Task InvokeAsync(HttpContext context)
{
    var originalBodyStream = context.Response.Body;

    using var responseBody = new MemoryStream();
    context.Response.Body = responseBody;

    await _next(context);

    // Read the response written by downstream middleware
    context.Response.Body.Seek(0, SeekOrigin.Begin);
    var responseText = await new StreamReader(
        context.Response.Body).ReadToEndAsync();
    context.Response.Body.Seek(0, SeekOrigin.Begin);

    // Copy back to original stream
    await responseBody.CopyToAsync(originalBodyStream);
}
```

**Caution:** Response body replacement adds memory overhead and should only be used for diagnostics or specific transformation requirements, not in high-throughput paths.

---

## Exception Handling Middleware

### Built-in Exception Handler

ASP.NET Core provides `UseExceptionHandler` for production-grade exception handling. This should always be the outermost middleware:

```csharp
app.UseExceptionHandler(exceptionApp =>
{
    exceptionApp.Run(async context =>
    {
        context.Response.StatusCode =
            StatusCodes.Status500InternalServerError;
        context.Response.ContentType = "application/json";

        var exceptionFeature = context.Features
            .Get<IExceptionHandlerFeature>();

        var logger = context.RequestServices
            .GetRequiredService<ILogger<Program>>();
        logger.LogError(
            exceptionFeature?.Error,
            "Unhandled exception for {Path}",
            context.Request.Path);

        await context.Response.WriteAsJsonAsync(new
        {
            Error = "An internal error occurred",
            TraceId = context.TraceIdentifier
        });
    });
});
```

### IExceptionHandler (.NET 8+)

.NET 8 introduced `IExceptionHandler` for DI-friendly, composable exception handling. Multiple handlers can be registered and are invoked in order until one handles the exception:

```csharp
public sealed class ValidationExceptionHandler : IExceptionHandler
{
    public async ValueTask<bool> TryHandleAsync(
        HttpContext context,
        Exception exception,
        CancellationToken ct)
    {
        if (exception is not ValidationException validationException)
            return false; // Not handled -- pass to next handler

        context.Response.StatusCode =
            StatusCodes.Status400BadRequest;
        await context.Response.WriteAsJsonAsync(new
        {
            Error = "Validation failed",
            Details = validationException.Errors
        }, ct);

        return true; // Handled -- stop the chain
    }
}

public sealed class GlobalExceptionHandler(
    ILogger<GlobalExceptionHandler> logger) : IExceptionHandler
{
    public async ValueTask<bool> TryHandleAsync(
        HttpContext context,
        Exception exception,
        CancellationToken ct)
    {
        logger.LogError(exception, "Unhandled exception");

        context.Response.StatusCode =
            StatusCodes.Status500InternalServerError;
        await context.Response.WriteAsJsonAsync(new
        {
            Error = "An internal error occurred",
            TraceId = context.TraceIdentifier
        }, ct);

        return true;
    }
}

// Register handlers in order (first match wins)
builder.Services.AddExceptionHandler<ValidationExceptionHandler>();
builder.Services.AddExceptionHandler<GlobalExceptionHandler>();
builder.Services.AddProblemDetails();

app.UseExceptionHandler();
```

### StatusCodePages for Non-Exception Errors

For HTTP error status codes that are not caused by exceptions (404, 403), use `UseStatusCodePages`:

```csharp
app.UseStatusCodePagesWithReExecute("/error/{0}");

// Or inline
app.UseStatusCodePages(async context =>
{
    context.HttpContext.Response.ContentType = "application/json";
    await context.HttpContext.Response.WriteAsJsonAsync(new
    {
        Error = $"HTTP {context.HttpContext.Response.StatusCode}",
        TraceId = context.HttpContext.TraceIdentifier
    });
});
```

---

## Conditional Middleware

### UseWhen -- Conditional Branch (Rejoins Pipeline)

`UseWhen` branches the pipeline based on a predicate. The branch rejoins the main pipeline after execution:

```csharp
// Only apply rate limiting headers for API routes
app.UseWhen(
    context => context.Request.Path.StartsWithSegments("/api"),
    apiApp =>
    {
        // Requires builder.Services.AddRateLimiter() in service registration
        apiApp.UseRateLimiter();
    });
```

### MapWhen -- Conditional Branch (Does Not Rejoin)

`MapWhen` creates a terminal branch that does not rejoin the main pipeline:

```csharp
// Serve a special handler for WebSocket upgrade requests
app.MapWhen(
    context => context.WebSockets.IsWebSocketRequest,
    wsApp =>
    {
        wsApp.Run(async context =>
        {
            using var ws = await context.WebSockets
                .AcceptWebSocketAsync();
            // Handle WebSocket connection
        });
    });
```

### Environment-Specific Middleware

```csharp
if (app.Environment.IsDevelopment())
{
    app.UseDeveloperExceptionPage();
    app.UseSwagger();
    app.UseSwaggerUI();
}
else
{
    app.UseExceptionHandler("/error");
    app.UseHsts();
}
```

---

## Key Principles

- **Order is everything** -- middleware executes top-to-bottom for requests and bottom-to-top for responses; incorrect order causes auth bypasses, missing headers, and unhandled exceptions
- **Exception handler goes first** -- `UseExceptionHandler` must be the outermost middleware to catch exceptions from all downstream components
- **Prefer classes over inline for reusable middleware** -- convention-based middleware classes are testable, composable, and follow the single-responsibility principle
- **Use `IMiddleware` for scoped dependencies** -- convention-based middleware is singleton; if you need scoped services (DbContext, user-scoped caches), use `IMiddleware`
- **Short-circuit intentionally** -- always document why a middleware does not call `next()` and ensure it writes a complete response
- **Avoid response body manipulation in hot paths** -- replacing `Response.Body` with `MemoryStream` doubles memory usage per request

---

## Agent Gotchas

1. **Do not place `UseAuthorization()` before `UseRouting()`** -- authorization requires endpoint metadata from routing to evaluate policies. Without routing, all authorization checks are skipped.
2. **Do not place `UseCors()` after `UseAuthorization()`** -- CORS preflight (OPTIONS) requests do not carry auth tokens. If auth runs first, preflights are rejected with 401.
3. **Do not forget to call `next()` in pass-through middleware** -- forgetting `await _next(context)` silently short-circuits the pipeline, causing downstream middleware and endpoints to never execute.
4. **Do not read `Request.Body` without `EnableBuffering()`** -- the request body stream is forward-only by default. Reading it without buffering consumes it, causing model binding and subsequent reads to fail with empty data.
5. **Do not register `IMiddleware` implementations without DI registration** -- unlike convention-based middleware, `IMiddleware` requires explicit `services.AddScoped<T>()` or `services.AddTransient<T>()`. Without it, `UseMiddleware<T>()` throws at startup.
6. **Do not write to `Response.Body` after calling `next()` if downstream middleware has already started the response** -- once headers are sent (response has started), modifications throw `InvalidOperationException`. Check `context.Response.HasStarted` before writing.

---

## Knowledge Sources

Middleware patterns in this skill are grounded in publicly available content from:

- **Andrew Lock's "Exploring ASP.NET Core" Blog Series** -- Deep coverage of middleware authoring patterns, including IMiddleware vs convention-based trade-offs, pipeline ordering pitfalls, endpoint routing internals, and IExceptionHandler composition. Source: https://andrewlock.net/
- **Official ASP.NET Core Middleware Documentation** -- Middleware fundamentals, factory-based activation, and error handling patterns. Source: https://learn.microsoft.com/en-us/aspnet/core/fundamentals/middleware/

> **Note:** This skill applies publicly documented guidance. It does not represent or speak for the named sources.

## References

- [ASP.NET Core middleware](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/middleware/)
- [Write custom ASP.NET Core middleware](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/middleware/write)
- [Factory-based middleware activation](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/middleware/extensibility)
- [Handle errors in ASP.NET Core](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/error-handling)
- [IExceptionHandler in .NET 8](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/error-handling#iexceptionhandler)
- [Exploring ASP.NET Core (Andrew Lock)](https://andrewlock.net/)

---

## Attribution

Adapted from [Aaronontheweb/dotnet-skills](https://github.com/Aaronontheweb/dotnet-skills) (MIT license).
