# OpenAPI

OpenAPI/Swagger integration for ASP.NET Core. Microsoft.AspNetCore.OpenApi is the recommended first-party approach for .NET 9+ and is the default in new project templates. Swashbuckle is no longer actively maintained; existing projects using Swashbuckle should plan migration. NSwag remains an alternative for client generation and advanced scenarios.

## Microsoft.AspNetCore.OpenApi (Recommended)

Microsoft.AspNetCore.OpenApi is the first-party OpenAPI package for ASP.NET Core 9+ and is included by default in new project templates. .NET 10 adds OpenAPI 3.1 support with JSON Schema draft 2020-12 compliance.

### Basic Setup

```csharp
// Microsoft.AspNetCore.OpenApi -- included by default in .NET 9+ project templates
// If not present, add: <PackageReference Include="Microsoft.AspNetCore.OpenApi" Version="9.*" />
// Version must match the project's target framework major version

builder.Services.AddOpenApi();

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi(); // Serves /openapi/v1.json
}
```

### Multiple Documents

Generate separate OpenAPI documents per API version or functional group:

```csharp
builder.Services.AddOpenApi("v1", options =>
{
    options.OpenApiVersion = OpenApiSpecVersion.OpenApi3_0;
});

builder.Services.AddOpenApi("v2", options =>
{
    options.OpenApiVersion = OpenApiSpecVersion.OpenApi3_1;
});

var app = builder.Build();
app.MapOpenApi(); // Serves /openapi/v1.json and /openapi/v2.json
```

---

## Document Transformers

Document transformers modify the generated OpenAPI document after it is built. Use them to add server information, security schemes, or custom metadata.

### IOpenApiDocumentTransformer

```csharp
public sealed class SecuritySchemeTransformer : IOpenApiDocumentTransformer
{
    public Task TransformAsync(
        OpenApiDocument document,
        OpenApiDocumentTransformerContext context,
        CancellationToken cancellationToken)
    {
        document.Components ??= new OpenApiComponents();
        document.Components.SecuritySchemes["Bearer"] = new OpenApiSecurityScheme
        {
            Type = SecuritySchemeType.Http,
            Scheme = "bearer",
            BearerFormat = "JWT",
            Description = "JWT Bearer token authentication"
        };

        document.SecurityRequirements.Add(new OpenApiSecurityRequirement
        {
            [new OpenApiSecurityScheme
            {
                Reference = new OpenApiReference
                {
                    Type = ReferenceType.SecurityScheme,
                    Id = "Bearer"
                }
            }] = Array.Empty<string>()
        });

        return Task.CompletedTask;
    }
}

// Register the transformer
builder.Services.AddOpenApi(options =>
{
    options.AddDocumentTransformer<SecuritySchemeTransformer>();
});
```

### Lambda Document Transformers

For simple transformations, use the lambda overload:

```csharp
builder.Services.AddOpenApi(options =>
{
    options.AddDocumentTransformer((document, context, ct) =>
    {
        document.Info = new OpenApiInfo
        {
            Title = "Products API",
            Version = "v1",
            Description = "Product catalog management API",
            Contact = new OpenApiContact
            {
                Name = "API Support",
                Email = "api-support@example.com"
            }
        };
        return Task.CompletedTask;
    });
});
```

---

## Operation Transformers

Operation transformers modify individual operations (endpoints) in the OpenAPI document. Use them to add per-operation metadata, examples, or conditional logic.

```csharp
public sealed class DeprecationTransformer : IOpenApiOperationTransformer
{
    public Task TransformAsync(
        OpenApiOperation operation,
        OpenApiOperationTransformerContext context,
        CancellationToken cancellationToken)
    {
        var deprecatedAttr = context.Description.ActionDescriptor
            .EndpointMetadata
            .OfType<ObsoleteAttribute>()
            .FirstOrDefault();

        if (deprecatedAttr is not null)
        {
            operation.Deprecated = true;
            operation.Description = $"DEPRECATED: {deprecatedAttr.Message}";
        }

        return Task.CompletedTask;
    }
}

builder.Services.AddOpenApi(options =>
{
    options.AddOperationTransformer<DeprecationTransformer>();
});
```

---

## Schema Customization

Customize how .NET types map to OpenAPI schemas using schema transformers:

```csharp
builder.Services.AddOpenApi(options =>
{
    options.AddSchemaTransformer((schema, context, ct) =>
    {
        // Add example values for known types
        if (context.JsonTypeInfo.Type == typeof(ProductDto))
        {
            schema.Example = new OpenApiObject
            {
                ["id"] = new OpenApiInteger(1),
                ["name"] = new OpenApiString("Widget"),
                ["price"] = new OpenApiDouble(19.99)
            };
        }
        return Task.CompletedTask;
    });
});
```

### Enriching Endpoint Metadata

Use fluent methods on endpoint builders to provide richer OpenAPI metadata:

```csharp
products.MapGet("/{id:int}", GetProductById)
    .WithName("GetProductById")
    .WithSummary("Get a product by its ID")
    .WithDescription("Returns the product details for the specified ID, or 404 if not found.")
    .WithTags("Products")
    .Produces<Product>(StatusCodes.Status200OK)
    .ProducesProblem(StatusCodes.Status404NotFound);
```

---

## Swashbuckle Migration

Swashbuckle (`Swashbuckle.AspNetCore`) is no longer actively maintained. It does not support OpenAPI 3.1. Existing projects should plan migration to `Microsoft.AspNetCore.OpenApi`.

**When Swashbuckle is still needed:** Projects on .NET 8 that cannot upgrade to .NET 9+, or projects that depend on Swashbuckle-specific features (SwaggerUI with deep customization, ISchemaFilter pipelines) may continue using Swashbuckle while planning migration.

### Migration Steps

1. Remove Swashbuckle packages:

```xml
<!-- Remove these -->
<!-- <PackageReference Include="Swashbuckle.AspNetCore" Version="..." /> -->
<!-- <PackageReference Include="Swashbuckle.AspNetCore.Annotations" Version="..." /> -->
```

2. Replace service registration:

```csharp
// Before (Swashbuckle)
builder.Services.AddSwaggerGen(options =>
{
    options.SwaggerDoc("v1", new OpenApiInfo { Title = "My API", Version = "v1" });
});

// After (Microsoft.AspNetCore.OpenApi)
builder.Services.AddOpenApi();
```

3. Replace middleware:

```csharp
// Before (Swashbuckle)
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

// After (built-in)
if (app.Environment.IsDevelopment())
{
    app.MapOpenApi(); // Serves raw OpenAPI JSON at /openapi/v1.json
}
```

4. For Swagger UI, add a standalone UI package or use Scalar:

```csharp
if (app.Environment.IsDevelopment())
{
    // Option 1: Scalar (modern, built-in support in .NET 10)
    // <PackageReference Include="Aspire.Dashboard.Components.Scalar" ... /> or use MapScalarApiReference
    app.MapScalarApiReference(); // .NET 10

    // Option 2: Swagger UI standalone
    // <PackageReference Include="Swashbuckle.AspNetCore.SwaggerUI" Version="..." />
    app.UseSwaggerUI(options =>
    {
        options.SwaggerEndpoint("/openapi/v1.json", "v1");
    });
}
```

5. Migrate Swashbuckle filters to transformers:

| Swashbuckle concept | Built-in replacement |
|---------------------|---------------------|
| `IDocumentFilter` | `IOpenApiDocumentTransformer` |
| `IOperationFilter` | `IOpenApiOperationTransformer` |
| `ISchemaFilter` | Schema transformers via `AddSchemaTransformer` |
| `[SwaggerOperation]` | `.WithSummary()`, `.WithDescription()` |
| `[SwaggerResponse]` | `.Produces<T>()`, `TypedResults` |

---

## NSwag

NSwag is an alternative OpenAPI toolchain that includes document generation, client generation (C#, TypeScript), and a UI. It is useful when you need generated API clients or when integrating with non-.NET consumers.

### Document Generation

```csharp
// <PackageReference Include="NSwag.AspNetCore" Version="14.*" />
builder.Services.AddOpenApiDocument(options =>
{
    options.Title = "Products API";
    options.Version = "v1";
    options.DocumentName = "v1";
});

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.UseOpenApi();    // Serves /swagger/v1/swagger.json
    app.UseSwaggerUi(); // Serves /swagger UI
}
```

### Client Generation

NSwag generates typed C# or TypeScript clients from OpenAPI specs:

```bash
# Install NSwag CLI
dotnet tool install --global NSwag.ConsoleCore

# Generate C# client from OpenAPI spec
nswag openapi2csclient /input:https://api.example.com/openapi/v1.json \
    /output:GeneratedClient.cs \
    /namespace:MyApp.ApiClient \
    /generateClientInterfaces:true
```

**Recommendation:** Use `Microsoft.AspNetCore.OpenApi` for document generation. Use NSwag CLI or Kiota for client generation from the resulting OpenAPI spec. Avoid using NSwag for both generation and serving in new projects.

---

## OpenAPI 3.1 (.NET 10)

.NET 10 introduces full OpenAPI 3.1 support with JSON Schema draft 2020-12 compliance. Key improvements over 3.0:

- **Nullable types:** Uses JSON Schema `type: ["string", "null"]` instead of `nullable: true`
- **Discriminator improvements:** Better oneOf/anyOf support for polymorphic types
- **Webhooks:** First-class webhook definitions
- **JSON Schema alignment:** Full compatibility with JSON Schema draft 2020-12 tooling

```csharp
// .NET 10: OpenAPI 3.1 is the default
// <PackageReference Include="Microsoft.AspNetCore.OpenApi" Version="10.*" />
builder.Services.AddOpenApi(options =>
{
    // Explicitly set version if needed (3.1 is default in .NET 10)
    options.OpenApiVersion = OpenApiSpecVersion.OpenApi3_1;
});
```

**Gotcha:** Swashbuckle does not support OpenAPI 3.1. Projects requiring 3.1 features must migrate to `Microsoft.AspNetCore.OpenApi`.

---

## Agent Gotchas

1. **Do not pin mismatched major versions of `Microsoft.AspNetCore.OpenApi`** -- the package version must match the project's target framework major version. Do not mix incompatible OpenAPI stacks (e.g., Swashbuckle + built-in) in the same project.
2. **Do not recommend Swashbuckle for new .NET 9+ projects** -- it is no longer actively maintained. Use the built-in `Microsoft.AspNetCore.OpenApi` instead.
3. **Do not say Swashbuckle is "deprecated"** -- it is not formally deprecated, but it is no longer actively maintained. Say "preferred" or "recommended" when referring to the built-in alternative.
4. **Do not forget the Swagger UI replacement** -- `MapOpenApi()` only serves the raw JSON spec. Add Scalar, Swagger UI standalone, or another UI separately.
5. **Do not mix Swashbuckle and built-in OpenAPI in the same project** -- they generate conflicting documents. Choose one approach.
6. **Do not hardcode ASP.NET shared-framework package versions** -- packages like `Microsoft.AspNetCore.OpenApi` must match the project TFM major version.

---

## Prerequisites

- .NET 9.0+ for `Microsoft.AspNetCore.OpenApi` (included in default project templates)
- .NET 10.0 for OpenAPI 3.1, JSON Schema draft 2020-12, and Scalar integration
- `NSwag.AspNetCore` (optional) for NSwag-based generation and UI
- `Swashbuckle.AspNetCore` (legacy) for existing projects not yet migrated

---

## References

- [OpenAPI in ASP.NET Core](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/openapi/overview?view=aspnetcore-10.0)
- [Microsoft.AspNetCore.OpenApi](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/openapi/aspnetcore-openapi?view=aspnetcore-10.0)
- [OpenAPI Document Transformers](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/openapi/customize-openapi?view=aspnetcore-10.0)
- [Migrate from Swashbuckle](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/openapi/aspnetcore-openapi?view=aspnetcore-10.0#migrate-from-swashbuckle)
- [NSwag](https://github.com/RicoSuter/NSwag)
- [Scalar API Reference](https://github.com/ScalarHQ/scalar)
