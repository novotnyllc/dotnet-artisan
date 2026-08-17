# API Docs

API documentation generation for .NET projects: DocFX setup for API reference from assemblies (`docfx.json` configuration, metadata extraction, template customization, cross-referencing), OpenAPI spec as living API documentation (Scalar and Swagger UI embedding, versioned OpenAPI documents), documentation-code synchronization (CI validation with `-warnaserror:CS1591`, broken link detection, automated doc builds on PR), API changelog patterns (breaking change documentation, migration guides, deprecated API tracking), and versioned API documentation (version selectors, multi-version maintenance, URL patterns).

**Version assumptions:** DocFX v2.x (community-maintained). OpenAPI 3.x via `Microsoft.AspNetCore.OpenApi` (.NET 9+ built-in). Scalar UI for modern OpenAPI visualization. .NET 8.0+ baseline for code examples.

## DocFX Setup for .NET API Reference

DocFX generates API reference documentation directly from .NET assemblies and XML documentation comments. It is the only documentation tool with native `docfx metadata` extraction from .NET projects.

### Installation

```bash
# Install DocFX as a .NET global tool
dotnet tool install -g docfx

# Or as a local tool (recommended for team consistency)
dotnet new tool-manifest
dotnet tool install docfx
```

### Configuration (`docfx.json`)

```json
{
  "metadata": [
    {
      "src": [
        {
          "files": ["src/**/*.csproj"],
          "exclude": ["**/bin/**", "**/obj/**"],
          "src": ".."
        }
      ],
      "dest": "api",
      "properties": {
        "TargetFramework": "net8.0"
      },
      "disableGitFeatures": false,
      "disableDefaultFilter": false
    }
  ],
  "build": {
    "content": [
      {
        "files": ["api/**.yml", "api/index.md"]
      },
      {
        "files": [
          "articles/**.md",
          "articles/**/toc.yml",
          "toc.yml",
          "*.md"
        ]
      }
    ],
    "resource": [
      {
        "files": ["images/**"]
      }
    ],
    "dest": "_site",
    "globalMetadataFiles": [],
    "fileMetadataFiles": [],
    "template": ["default", "modern"],
    "postProcessors": ["ExtractSearchIndex"],
    "markdownEngineName": "markdig",
    "noLangKeyword": false,
    "keepFileLink": false,
    "cleanupCacheHistory": false,
    "disableGitFeatures": false,
    "globalMetadata": {
      "_appTitle": "My.Library API Reference",
      "_appFooter": "Copyright 2024 My Company",
      "_enableSearch": true,
      "_enableNewTab": true
    }
  }
}
```

### Metadata Extraction

The `metadata` section controls how DocFX extracts API information from .NET projects:

```bash
# Generate API metadata YAML files from projects
docfx metadata docfx.json

# This creates YAML files in the api/ directory:
#   api/MyLibrary.WidgetService.yml
#   api/MyLibrary.Widget.yml
#   api/toc.yml
```

**Key metadata configuration options:**

| Property | Purpose | Default |
|----------|---------|---------|
| `src.files` | Project files to extract from | Required |
| `dest` | Output directory for YAML | `api` |
| `properties.TargetFramework` | TFM to build against | Project default |
| `disableGitFeatures` | Skip git blame info | `false` |
| `filter` | Path to API filter YAML | None (all public APIs) |

### API Filtering

Exclude internal types from the generated documentation:

```yaml
# filterConfig.yml
apiRules:
  - exclude:
      uidRegex: ^MyLibrary\.Internal\.
      type: Namespace
  - exclude:
      hasAttribute:
          uid: System.ComponentModel.EditorBrowsableAttribute
          ctorArguments:
            - System.ComponentModel.EditorBrowsableState.Never
```

Reference the filter in `docfx.json`:

```json
{
  "metadata": [
    {
      "filter": "filterConfig.yml"
    }
  ]
}
```

### Template Customization

DocFX supports template overrides for custom branding:

```
docs/
  templates/
    custom/
      styles/
        main.css          # Custom CSS overrides
      partials/
        head.tmpl.partial # Custom head section (analytics, fonts)
        footer.tmpl.partial
```

Reference custom templates in `docfx.json`:

```json
{
  "build": {
    "template": ["default", "modern", "templates/custom"]
  }
}
```

### Cross-Referencing Between Pages

DocFX supports `uid`-based cross-references between API pages and conceptual articles:

```markdown
<!-- In a conceptual article -->
See the @MyLibrary.WidgetService.CreateWidgetAsync(System.String) method for details.

For the full API, see <xref:MyLibrary.WidgetService>.
```

```yaml
# In an API YAML override file (api/MyLibrary.WidgetService.yml)
# Add links to conceptual articles
references:
  - uid: MyLibrary.WidgetService
    seealso:
      - linkId: ../articles/getting-started.md
        commentId: getting-started
```

---

## OpenAPI Spec as Documentation

Generated OpenAPI specifications serve as living API documentation that stays in sync with the code. This section covers using OpenAPI output as documentation; for OpenAPI generation and configuration, see [skill:dotnet-api].

### Scalar UI Embedding

Scalar provides a modern, interactive API documentation viewer:

```csharp
// Program.cs
var builder = WebApplication.CreateBuilder(args);

builder.Services.AddOpenApi();

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();         // Serves OpenAPI JSON at /openapi/v1.json
    app.MapScalarApiReference(options =>
    {
        options.WithTitle("My API Documentation")
               .WithTheme(ScalarTheme.Purple)
               .WithDefaultHttpClient(ScalarTarget.CSharp, ScalarClient.HttpClient);
    });
}

app.Run();
```

Scalar renders the OpenAPI spec as an interactive documentation page with:
- Endpoint grouping by tags
- Request/response examples
- Authentication configuration
- "Try it" functionality for testing endpoints

### Swagger UI Embedding

For projects using Swashbuckle or requiring the classic Swagger UI:

```csharp
if (app.Environment.IsDevelopment())
{
    app.UseSwaggerUI(options =>
    {
        options.SwaggerEndpoint("/openapi/v1.json", "My API v1");
        options.RoutePrefix = "api-docs";
        options.DocumentTitle = "My API Documentation";
        options.DefaultModelsExpandDepth(-1); // Hide schemas by default
    });
}
```

### Versioned OpenAPI Documents

Serve multiple OpenAPI documents for different API versions:

```csharp
builder.Services.AddOpenApi("v1", options =>
{
    options.AddDocumentTransformer((document, context, ct) =>
    {
        document.Info.Version = "1.0";
        document.Info.Title = "My API";
        return Task.CompletedTask;
    });
});

builder.Services.AddOpenApi("v2", options =>
{
    options.AddDocumentTransformer((document, context, ct) =>
    {
        document.Info.Version = "2.0";
        document.Info.Title = "My API";
        return Task.CompletedTask;
    });
});

// Serves /openapi/v1.json and /openapi/v2.json
if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
}
```

### Exporting OpenAPI for Static Documentation

Export the OpenAPI spec at build time for use in static documentation sites:

```bash
# Generate OpenAPI spec from the running application
dotnet run -- --urls "http://localhost:5099" &
APP_PID=$!
sleep 3
curl -s http://localhost:5099/openapi/v1.json > docs/openapi/v1.json
kill $APP_PID
```

Alternatively, use the `Microsoft.Extensions.ApiDescription.Server` package to generate at build time:

```xml
<PackageReference Include="Microsoft.Extensions.ApiDescription.Server" Version="8.0.0">
  <PrivateAssets>all</PrivateAssets>
  <IncludeAssets>runtime; build; native; contentfiles; analyzers</IncludeAssets>
</PackageReference>

<PropertyGroup>
  <OpenApiGenerateDocuments>true</OpenApiGenerateDocuments>
  <OpenApiDocumentsDirectory>$(MSBuildProjectDirectory)/../docs/openapi</OpenApiDocumentsDirectory>
</PropertyGroup>
```

For OpenAPI generation setup and Swashbuckle migration details, see [skill:dotnet-api].

---

## Doc Site Generation from XML Comments

### XML Docs to DocFX (Static HTML)

The primary pipeline for library API reference documentation:

```
Source Code (.cs files)
    |
    v
XML Doc Comments (/// <summary>...)
    |
    v
Build with GenerateDocumentationFile=true
    |
    v
XML Doc File (MyLibrary.xml)
    |
    v
docfx metadata (extracts API structure)
    |
    v
YAML Files (api/*.yml)
    |
    v
docfx build (generates HTML)
    |
    v
Static HTML Site (_site/)
```

For XML documentation comment authoring best practices, see [skill:dotnet-tooling].

### XML Docs to Starlight (via Markdown Extraction)

For projects using Starlight instead of DocFX, extract API documentation as Markdown:

1. **Generate the XML doc file** with `<GenerateDocumentationFile>true</GenerateDocumentationFile>`
2. **Use a conversion tool** to transform XML docs to Markdown pages:
   - `xmldoc2md` (community tool): converts XML doc files to Markdown
   - Custom script: parse the XML file and generate Markdown pages for each type

```bash
# Using xmldoc2md
dotnet tool install -g XMLDoc2Markdown
xmldoc2md MyLibrary.dll docs/src/content/docs/reference/

# Output: one Markdown file per type in the reference/ directory
```

3. **Include in Starlight build:**

```
docs/src/content/docs/
  reference/
    MyLibrary.WidgetService.md    # Auto-generated from XML docs
    MyLibrary.Widget.md
    MyLibrary.WidgetStatus.md
```

Configure the sidebar to auto-generate from the reference directory:

```javascript
// astro.config.mjs
sidebar: [
  {
    label: 'API Reference',
    autogenerate: { directory: 'reference' },
  },
],
```

---

## Keeping Docs in Sync with Code

### CI Validation of Doc Completeness

Enforce XML documentation completeness in CI by treating CS1591 as an error:

```xml
<!-- Directory.Build.props -->
<PropertyGroup>
  <GenerateDocumentationFile>true</GenerateDocumentationFile>
</PropertyGroup>

<!-- For public library projects only -->
<PropertyGroup Condition="'$(IsPublicLibrary)' == 'true'">
  <WarningsAsErrors>$(WarningsAsErrors);CS1591</WarningsAsErrors>
</PropertyGroup>
```

```bash
# CI command: build with warnings-as-errors for doc completeness
dotnet build -warnaserror:CS1591
```

This fails the build if any public member is missing XML documentation. Use the `IsPublicLibrary` condition (or per-project configuration) to apply only to published NuGet packages, not test projects or internal tools.

### Broken Link Detection

Validate documentation links in CI:

```bash
# Build DocFX and check for broken cross-references
docfx build docfx.json --warningsAsErrors

# DocFX reports broken xref links as warnings -- the flag promotes them to errors
```

For Starlight or Docusaurus sites, use a link checker after building:

```bash
# Build the doc site
npm run build

# Check for broken links in the built output
npx broken-link-checker-local ./_site --recursive
```

### Automated Doc Builds on PR

Validate documentation builds on every pull request without deploying. For the deployment workflow configuration, see [skill:dotnet-devops]. The validation step typically runs as part of the CI workflow:

```bash
# In CI: verify docs build without errors
dotnet build -warnaserror:CS1591          # XML doc completeness
docfx metadata docfx.json                 # API metadata extraction
docfx build docfx.json --warningsAsErrors # Full doc site build
```

This catches documentation regressions (missing docs, broken cross-references) before they reach the main branch.

---

## API Changelog Patterns

### Breaking Change Documentation

Document breaking changes with a structured format that consumers can quickly scan:

```markdown
## Breaking Changes in v3.0

### Removed APIs

| API | Replacement | Migration |
|-----|-------------|-----------|
| `WidgetService.Create(string)` | `WidgetService.CreateAsync(string, CancellationToken)` | Add `await` and `CancellationToken` parameter |
| `Widget.Name` setter | `WidgetService.RenameAsync(Guid, string)` | Use service method instead of direct property mutation |
| `IWidgetRepository` (interface) | `IWidgetRepository<T>` (generic) | Update implementations to use generic interface |

### Changed Behavior

- `WidgetService.CreateAsync` now validates name uniqueness within a category.
  Previously, duplicate names were silently allowed.
- `Widget.Status` defaults to `Draft` instead of `Active`.
  Existing code that assumes newly created widgets are active must call `widget.Activate()`.

### New Required Dependencies

- `Microsoft.Extensions.Caching.Memory` is now a required dependency for `WidgetService`.
  Register with `builder.Services.AddMemoryCache()`.
```

### Migration Guides Between Major Versions

Structure migration guides by the action required:

```markdown
# Migrating from v2.x to v3.0

## Step 1: Update Package References

```xml
<!-- Before -->
<PackageReference Include="My.Library" Version="2.*" />

<!-- After -->
<PackageReference Include="My.Library" Version="3.0.0" />
```

## Step 2: Fix Compilation Errors

### Async API Changes

All synchronous methods have been removed. Replace synchronous calls with async equivalents:

```csharp
// Before (v2.x)
var widget = service.Create("name");

// After (v3.0)
var widget = await service.CreateAsync("name", cancellationToken);
```

### Generic Repository Interface

```csharp
// Before (v2.x)
public class MyRepo : IWidgetRepository { }

// After (v3.0)
public class MyRepo : IWidgetRepository<Widget> { }
```

## Step 3: Update Behavioral Assumptions

- Check all code paths that assume `Widget.Status == Active` after creation
- Add `builder.Services.AddMemoryCache()` to DI registration
```

### Deprecated API Tracking

Use the `[Obsolete]` attribute with message pointing to the replacement. Document deprecation timelines:

```csharp
/// <summary>
/// Creates a widget synchronously.
/// </summary>
/// <remarks>
/// This method will be removed in v4.0. Use
/// <see cref="CreateAsync(string, CancellationToken)"/> instead.
/// </remarks>
[Obsolete("Use CreateAsync instead. This method will be removed in v4.0.", error: false)]
public Widget Create(string name)
{
}
```

Track deprecated APIs in a dedicated document:

```markdown
# Deprecated APIs

| API | Deprecated In | Removed In | Replacement |
|-----|---------------|------------|-------------|
| `WidgetService.Create(string)` | v2.5 | v4.0 (planned) | `CreateAsync(string, CancellationToken)` |
| `Widget.Name` setter | v3.0 | v4.0 (planned) | `WidgetService.RenameAsync(Guid, string)` |
| `WidgetOptions.EnableCache` | v3.1 | v5.0 (planned) | `WidgetOptions.CachePolicy` |
```

For changelog format conventions and SemVer versioning strategy, see [skill:dotnet-devops].

---

## Versioned API Documentation

### Version Selectors in Doc Sites

**DocFX versioned docs:**

DocFX supports version-specific metadata extraction by targeting different project versions:

```json
{
  "metadata": [
    {
      "src": [{ "files": ["src/**/*.csproj"], "src": ".." }],
      "dest": "api/v2",
      "properties": { "TargetFramework": "net8.0" },
      "globalNamespaceId": "v2"
    }
  ]
}
```

Maintain separate branches or tags for each major version, and build documentation from each:

```bash
# Build docs for v2.x (current branch)
docfx build docfx.json

# Build docs for v1.x (from tag)
git checkout v1.x
docfx build docfx.json --output _site/v1
git checkout main
```

**Starlight versioned docs:**

Use directory-based versioning or the `@lorenzo_lewis/starlight-utils` plugin. See [skill:dotnet-tooling] for Starlight versioning setup.

**Docusaurus versioned docs:**

Docusaurus has built-in versioning with `npx docusaurus docs:version`. See [skill:dotnet-tooling] for Docusaurus versioning setup.

### Maintaining Docs for Multiple Active Versions

When supporting multiple active major versions simultaneously:

1. **Branch-per-major-version strategy:** Maintain `docs/v1`, `docs/v2` directories on the main branch, or separate `v1.x`, `v2.x` branches
2. **Shared conceptual docs:** Keep version-independent guides (architecture, concepts) in a shared location, version-specific API reference in separate directories
3. **Version banner:** Add a notification banner on older version docs pointing to the latest version

### URL Patterns

Consistent URL patterns for versioned API docs:

```
https://docs.mylib.dev/                     # Latest stable version
https://docs.mylib.dev/v2/                  # Specific version
https://docs.mylib.dev/v2/api/WidgetService # Specific type in specific version
https://docs.mylib.dev/latest/              # Alias for latest stable
https://docs.mylib.dev/next/                # Pre-release / unreleased docs
```

Configure redirects so unversioned URLs point to the latest stable version. This ensures existing links remain valid when a new version is published.

---

## Agent Gotchas

1. **Do not generate OpenAPI spec configuration** -- OpenAPI generation setup (`builder.Services.AddOpenApi()`, document transformers, Swashbuckle migration) belongs to [skill:dotnet-api]. This skill covers using the generated OpenAPI output as documentation.

2. **Do not write XML doc comment syntax guidance** -- XML tag syntax, conventions, `<inheritdoc>`, and `GenerateDocumentationFile` belong to [skill:dotnet-tooling]. This skill covers the pipeline from XML docs to generated documentation sites.

3. **Do not generate CI deployment YAML** -- doc site deployment workflows (GitHub Pages actions, DocFX deploy) belong to [skill:dotnet-devops]. This skill covers doc build validation and local generation.

4. **`docfx metadata` requires a buildable project** -- the project must compile successfully for DocFX to extract API metadata. Always run `dotnet build` before `docfx metadata` in CI pipelines.

5. **DocFX is community-maintained since November 2022** -- Microsoft transferred the repository. It remains actively maintained and widely used. For new projects evaluating alternatives, see [skill:dotnet-tooling].

6. **DocFX `modern` template requires v2.75+** -- earlier versions use the `default` template which does not include Mermaid support or modern styling. Check the installed version with `docfx --version`.

7. **`-warnaserror:CS1591` should apply only to public library projects** -- applying it to test projects, console apps, or internal tools creates unnecessary documentation burden. Use MSBuild conditions to target only published packages.

8. **API filtering with `filterConfig.yml` uses UID regex, not namespace strings** -- the pattern `^MyLibrary\.Internal\.` matches UIDs that start with that prefix. Test filter patterns with `docfx metadata --log verbose` to verify correct filtering.

9. **Breaking change documentation must include migration code examples** -- a table listing removed APIs without showing the replacement code is insufficient. Always include before/after code snippets.

10. **Versioned doc URLs must redirect unversioned paths to latest stable** -- do not break existing links when publishing a new version. Configure server-side redirects or a client-side redirect page at the root URL.

11. **OpenAPI UI (Scalar, Swagger UI) should only be exposed in development** -- wrap `MapScalarApiReference` and `UseSwaggerUI` in `if (app.Environment.IsDevelopment())` guards. Production exposure of interactive API docs is a security consideration.
