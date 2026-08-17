# Containers

Best practices for containerizing .NET applications. Covers multi-stage Dockerfile patterns, the `dotnet publish` container image feature (.NET 8+), rootless container configuration, optimized layer caching, and container health checks.

## Multi-Stage Dockerfiles

Multi-stage builds separate the build environment from the runtime environment, producing minimal final images.

### Standard Multi-Stage Pattern

```dockerfile
# Stage 1: Build
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

# Copy project files first for layer caching
COPY ["src/MyApi/MyApi.csproj", "src/MyApi/"]
COPY ["src/MyApi.Core/MyApi.Core.csproj", "src/MyApi.Core/"]
COPY ["Directory.Build.props", "."]
COPY ["Directory.Packages.props", "."]
RUN dotnet restore "src/MyApi/MyApi.csproj"

# Copy everything else and build
COPY . .
WORKDIR "/src/src/MyApi"
RUN dotnet publish -c Release -o /app/publish --no-restore

# Stage 2: Runtime
FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app
EXPOSE 8080

COPY --from=build /app/publish .
ENTRYPOINT ["dotnet", "MyApi.dll"]
```

### Layer Caching Strategy

Order COPY instructions from least-frequently-changed to most-frequently-changed:

1. **Project files and props** -- change only when dependencies change
2. **`dotnet restore`** -- cached until project files change
3. **Source code** -- changes with every build
4. **`dotnet publish`** -- runs only when source or restore layer changes

```dockerfile
# Good: restore layer is cached when only source changes
COPY ["src/MyApi/MyApi.csproj", "src/MyApi/"]
RUN dotnet restore
COPY . .
RUN dotnet publish

# Bad: restore runs on every source change
COPY . .
RUN dotnet restore
RUN dotnet publish
```

### Solution-Level Restore

For multi-project solutions, copy all `.csproj` files and the solution file to enable a single restore:

```dockerfile
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

# Copy solution and all project files for restore caching
COPY ["MyApp.sln", "."]
COPY ["Directory.Build.props", "."]
COPY ["Directory.Packages.props", "."]
COPY ["src/MyApi/MyApi.csproj", "src/MyApi/"]
COPY ["src/MyApi.Core/MyApi.Core.csproj", "src/MyApi.Core/"]
COPY ["src/MyApi.Infrastructure/MyApi.Infrastructure.csproj", "src/MyApi.Infrastructure/"]
RUN dotnet restore

COPY . .
RUN dotnet publish "src/MyApi/MyApi.csproj" -c Release -o /app/publish --no-restore
```

---

## dotnet publish Container Images (.NET 8+)

Starting with .NET 8, `dotnet publish` can produce OCI container images directly without a Dockerfile. This uses the `Microsoft.NET.Build.Containers` SDK (included in the .NET SDK).

### Basic Usage

```bash
# Publish as a container image to local Docker daemon
dotnet publish --os linux --arch x64 /t:PublishContainer

# Publish to a remote registry
dotnet publish --os linux --arch x64 /t:PublishContainer \
  -p:ContainerRegistry=ghcr.io \
  -p:ContainerRepository=myorg/myapi
```

### MSBuild Configuration

Configure container properties in the `.csproj`:

```xml
<PropertyGroup>
  <ContainerBaseImage>mcr.microsoft.com/dotnet/aspnet:10.0</ContainerBaseImage>
  <ContainerImageName>myapi</ContainerImageName>
  <ContainerImageTag>$(Version)</ContainerImageTag>
</PropertyGroup>

<ItemGroup>
  <ContainerPort Include="8080" Type="tcp" />
</ItemGroup>
```

### Advanced Configuration

```xml
<PropertyGroup>
  <!-- Use chiseled (distroless) base image for smaller attack surface -->
  <ContainerBaseImage>mcr.microsoft.com/dotnet/aspnet:10.0-noble-chiseled</ContainerBaseImage>

  <!-- Run as non-root user (default for chiseled images) -->
  <ContainerUser>app</ContainerUser>
</PropertyGroup>

<ItemGroup>
  <!-- Environment variables -->
  <ContainerEnvironmentVariable Include="ASPNETCORE_URLS" Value="http://+:8080" />
  <ContainerEnvironmentVariable Include="DOTNET_RUNNING_IN_CONTAINER" Value="true" />

  <!-- Labels -->
  <ContainerLabel Include="org.opencontainers.image.source" Value="https://github.com/myorg/myapi" />
</ItemGroup>
```

### When to Use dotnet publish vs Dockerfile

| Scenario | Recommendation |
|----------|---------------|
| Simple single-project API | `dotnet publish /t:PublishContainer` -- less boilerplate |
| Multi-stage build with native dependencies | Dockerfile -- full control over build environment |
| Need to install OS packages (e.g., `libgdiplus`) | Dockerfile -- `RUN apt-get install` not available in SDK publish |
| CI/CD with complex build steps | Dockerfile -- explicit, reproducible |
| Quick local container testing | `dotnet publish /t:PublishContainer` -- fastest iteration |

---

## Base Image Selection

### Official .NET Container Images

| Image | Use Case | Size |
|-------|----------|------|
| `mcr.microsoft.com/dotnet/aspnet:10.0` | ASP.NET Core apps (Ubuntu) | ~220 MB |
| `mcr.microsoft.com/dotnet/aspnet:10.0-alpine` | ASP.NET Core apps (Alpine, smaller) | ~110 MB |
| `mcr.microsoft.com/dotnet/aspnet:10.0-noble-chiseled` | Distroless (no shell, no package manager) | ~110 MB |
| `mcr.microsoft.com/dotnet/aspnet:10.0-noble-chiseled-extra` | Chiseled + globalization + time zones | ~130 MB |
| `mcr.microsoft.com/dotnet/runtime:10.0` | Console apps, worker services | ~190 MB |
| `mcr.microsoft.com/dotnet/runtime-deps:10.0` | Self-contained/AOT apps (runtime not needed) | ~30 MB |

### Choosing a Base Image

- **Default:** Use `aspnet` for web apps, `runtime` for worker services
- **Minimal footprint:** Use `chiseled` variants (no shell, no root user, no package manager)
- **Globalization needed:** Use `chiseled-extra` if your app uses culture-specific formatting or time zones
- **Self-contained or AOT:** Use `runtime-deps` -- the runtime is bundled in your app
- **Alpine:** Smaller than Ubuntu but uses musl libc; test for compatibility with native dependencies

---

## Rootless Containers

Running containers as non-root reduces the attack surface. .NET 8+ chiseled images run as non-root by default.

### Non-Root with Standard Images

```dockerfile
FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app

# Create non-root user and switch to it
RUN adduser --disabled-password --gecos "" --uid 1001 appuser
USER appuser

COPY --from=build --chown=appuser:appuser /app/publish .
ENTRYPOINT ["dotnet", "MyApi.dll"]
```

### Non-Root with Chiseled Images

Chiseled images include a pre-configured `app` user (UID 1654). No additional configuration needed:

```dockerfile
FROM mcr.microsoft.com/dotnet/aspnet:10.0-noble-chiseled AS runtime
WORKDIR /app
# Already runs as non-root 'app' user (UID 1654)

COPY --from=build /app/publish .
ENTRYPOINT ["dotnet", "MyApi.dll"]
```

### Port Configuration

Non-root users cannot bind to ports below 1024. ASP.NET Core defaults to port 8080 in containers (set via `ASPNETCORE_HTTP_PORTS`):

```dockerfile
# Default in .NET 8+ container images -- no explicit config needed
# ASPNETCORE_HTTP_PORTS=8080

# If you need a different port:
ENV ASPNETCORE_HTTP_PORTS=5000
EXPOSE 5000
```

---

## Container Health Checks

Health checks allow container runtimes to monitor application readiness. The application-level health check endpoints (see [skill:dotnet-devops]) are consumed by Docker and Kubernetes probes.

### Docker HEALTHCHECK

```dockerfile
FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app

# Health check using curl (not available in chiseled images)
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD curl -f http://localhost:8080/health/live || exit 1

COPY --from=build /app/publish .
ENTRYPOINT ["dotnet", "MyApi.dll"]
```

For chiseled images (no `curl`), use a dedicated health check binary or rely on orchestrator-level probes (Kubernetes `httpGet`, Docker Compose `test`):

```dockerfile
FROM mcr.microsoft.com/dotnet/aspnet:10.0-noble-chiseled AS runtime
WORKDIR /app

# No HEALTHCHECK directive -- use orchestrator probes instead
# See [skill:dotnet-devops] references/container-deployment.md for Kubernetes probe configuration

COPY --from=build /app/publish .
ENTRYPOINT ["dotnet", "MyApi.dll"]
```

### Health Check Endpoints

Register health check endpoints in your application (see [skill:dotnet-devops] for full guidance):

```csharp
var builder = WebApplication.CreateBuilder(args);

builder.Services.AddHealthChecks()
    .AddCheck("self", () => HealthCheckResult.Healthy(), tags: ["live"])
    .AddNpgSql(
        builder.Configuration.GetConnectionString("DefaultConnection")!,
        name: "database",
        tags: ["ready"]);

var app = builder.Build();

app.MapHealthChecks("/health/live", new HealthCheckOptions
{
    Predicate = check => check.Tags.Contains("live")
});

app.MapHealthChecks("/health/ready", new HealthCheckOptions
{
    Predicate = check => check.Tags.Contains("ready")
});
```

---

## Container Optimization

### .dockerignore

Always include a `.dockerignore` to exclude unnecessary files from the build context:

```
**/.git
**/.vs
**/.vscode
**/bin
**/obj
**/node_modules
**/*.user
**/*.suo
**/Dockerfile*
**/docker-compose*
**/.dockerignore
**/README.md
**/LICENSE
```

### Globalization and Time Zones

If your app needs globalization support (culture-specific formatting, time zones), configure ICU:

```dockerfile
# Option 1: Use the chiseled-extra image (includes ICU + tzdata)
FROM mcr.microsoft.com/dotnet/aspnet:10.0-noble-chiseled-extra

# Option 2: Disable globalization for smaller images (if not needed)
ENV DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=true
```

### Memory Limits

Configure .NET to respect container memory limits:

```dockerfile
# .NET automatically detects container memory limits and adjusts GC heap size.
# Override only if needed:
ENV DOTNET_GCHeapHardLimit=0x10000000  # 256 MB hard limit
```

.NET automatically reads cgroup memory limits. The GC adjusts its heap size to stay within the container memory budget. Avoid setting `DOTNET_GCHeapHardLimit` unless you have a specific reason.

### ReadOnlyRootFilesystem

For defense-in-depth, run with a read-only root filesystem. Ensure writable paths for temp files:

```dockerfile
ENV DOTNET_EnableDiagnostics=0
# Or mount a tmpfs at /tmp for diagnostics support
```

---

## Key Principles

- **Use multi-stage builds** -- keep build tools out of the final image
- **Order COPY for layer caching** -- project files and restore before source code
- **Prefer chiseled images** for production -- no shell, no root, minimal attack surface
- **Use `dotnet publish /t:PublishContainer`** for simple projects -- skip Dockerfile boilerplate
- **Run as non-root** -- use `USER` directive or chiseled images (non-root by default)
- **Set health check endpoints** -- enable orchestrators to monitor application state (see [skill:dotnet-devops])
- **Include `.dockerignore`** -- keep build context small and exclude secrets

---

## Agent Gotchas

1. **Do not use `mcr.microsoft.com/dotnet/sdk` as the final image** -- SDK images are 800+ MB and include build tools. Always use `aspnet`, `runtime`, or `runtime-deps` for the final stage.
2. **Do not hardcode image tags to a patch version** (e.g., `10.0.1`) -- use `10.0` to receive security patches. Pin to patch versions only if you have a specific compatibility requirement.
3. **Do not use `HEALTHCHECK` with chiseled images** -- chiseled images have no `curl` or shell. Use orchestrator-level probes (Kubernetes `httpGet`, Docker Compose `test`) instead.
4. **Do not forget `--no-restore` on `dotnet publish` after a separate `dotnet restore` step** -- without it, restore runs again and breaks layer caching.
5. **Do not bind to ports below 1024 in non-root containers** -- .NET defaults to port 8080 in container images. If you override `ASPNETCORE_HTTP_PORTS`, ensure the port is >= 1024.
6. **Do not omit `.dockerignore`** -- without it, the build context includes `.git`, `bin/obj`, and potentially secrets, increasing build time and image size.

---

## References

- [.NET container images](https://learn.microsoft.com/en-us/dotnet/core/docker/build-container)
- [Containerize a .NET app with dotnet publish](https://learn.microsoft.com/en-us/dotnet/core/docker/publish-as-container)
- [.NET container image variants](https://learn.microsoft.com/en-us/dotnet/core/docker/container-images)
- [Chiseled Ubuntu containers for .NET](https://devblogs.microsoft.com/dotnet/dotnet-6-is-now-in-ubuntu-2204/#chiseled-ubuntu-containers)
- [ASP.NET Core health checks](https://learn.microsoft.com/en-us/aspnet/core/host-and-deploy/health-checks)
- [Docker multi-stage builds](https://docs.docker.com/build/building/multi-stage/)
