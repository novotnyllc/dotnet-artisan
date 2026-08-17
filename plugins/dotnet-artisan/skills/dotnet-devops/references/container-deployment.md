# Container Deployment

Deploying .NET containers to Kubernetes and local development environments. Covers Kubernetes Deployment + Service + probe YAML, Docker Compose for local dev workflows, and CI/CD integration for building and pushing container images.

## Kubernetes Deployment

### Deployment Manifest

A production-ready Kubernetes Deployment for a .NET API:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: order-api
  labels:
    app: order-api
    app.kubernetes.io/name: order-api
    app.kubernetes.io/version: "1.0.0"
    app.kubernetes.io/component: api
spec:
  replicas: 3
  selector:
    matchLabels:
      app: order-api
  template:
    metadata:
      labels:
        app: order-api
    spec:
      containers:
        - name: order-api
          image: ghcr.io/myorg/order-api:1.0.0
          ports:
            - containerPort: 8080
              protocol: TCP
          env:
            - name: ASPNETCORE_ENVIRONMENT
              value: "Production"
            - name: OTEL_EXPORTER_OTLP_ENDPOINT
              value: "http://otel-collector.monitoring:4317"
            - name: OTEL_SERVICE_NAME
              value: "order-api"
            - name: ConnectionStrings__DefaultConnection
              valueFrom:
                secretKeyRef:
                  name: order-api-secrets
                  key: connection-string
          resources:
            requests:
              cpu: "100m"
              memory: "128Mi"
            limits:
              cpu: "500m"
              memory: "512Mi"
          livenessProbe:
            httpGet:
              path: /health/live
              port: 8080
            initialDelaySeconds: 10
            periodSeconds: 15
            timeoutSeconds: 3
            failureThreshold: 3
          readinessProbe:
            httpGet:
              path: /health/ready
              port: 8080
            initialDelaySeconds: 5
            periodSeconds: 10
            timeoutSeconds: 3
            failureThreshold: 3
          startupProbe:
            httpGet:
              path: /health/live
              port: 8080
            initialDelaySeconds: 0
            periodSeconds: 5
            failureThreshold: 30
      securityContext:
        runAsNonRoot: true
        runAsUser: 1654
        fsGroup: 1654
      terminationGracePeriodSeconds: 30
```

### Service Manifest

Expose the Deployment within the cluster:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: order-api
  labels:
    app: order-api
spec:
  type: ClusterIP
  selector:
    app: order-api
  ports:
    - port: 80
      targetPort: 8080
      protocol: TCP
      name: http
```

### ConfigMap for Non-Sensitive Configuration

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: order-api-config
data:
  ASPNETCORE_ENVIRONMENT: "Production"
  Logging__LogLevel__Default: "Information"
  Logging__LogLevel__Microsoft.AspNetCore: "Warning"
```

Reference in the Deployment:

```yaml
envFrom:
  - configMapRef:
      name: order-api-config
```

### Secrets for Sensitive Configuration

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: order-api-secrets
type: Opaque
stringData:
  connection-string: "Host=postgres;Database=orders;Username=app;Password=secret"
```

In production, use an external secrets operator (e.g., External Secrets Operator, Sealed Secrets) rather than plain Kubernetes Secrets stored in source control.

---

## Kubernetes Probes

Probes tell Kubernetes how to check application health. They map to the health check endpoints defined in your .NET application (see [skill:dotnet-devops]).

### Probe Types

| Probe | Purpose | Endpoint | Failure Action |
|-------|---------|----------|---------------|
| **Startup** | Has the app finished initializing? | `/health/live` | Keep waiting (up to `failureThreshold * periodSeconds`) |
| **Liveness** | Is the process healthy? | `/health/live` | Restart the pod |
| **Readiness** | Can the process serve traffic? | `/health/ready` | Remove from Service endpoints |

### Probe Configuration Guidelines

```yaml
# Startup probe: give the app time to initialize
# Total startup budget: failureThreshold * periodSeconds = 30 * 5 = 150s
startupProbe:
  httpGet:
    path: /health/live
    port: 8080
  initialDelaySeconds: 0
  periodSeconds: 5
  failureThreshold: 30

# Liveness probe: detect deadlocks and hangs
# Only runs after startup probe succeeds
livenessProbe:
  httpGet:
    path: /health/live
    port: 8080
  periodSeconds: 15
  timeoutSeconds: 3
  failureThreshold: 3

# Readiness probe: control traffic routing
readinessProbe:
  httpGet:
    path: /health/ready
    port: 8080
  periodSeconds: 10
  timeoutSeconds: 3
  failureThreshold: 3
```

### Graceful Shutdown

.NET responds to `SIGTERM` and begins graceful shutdown. Configure `terminationGracePeriodSeconds` to allow in-flight requests to complete:

```yaml
spec:
  terminationGracePeriodSeconds: 30
```

In your application, use `IHostApplicationLifetime` to handle shutdown:

```csharp
app.Lifetime.ApplicationStopping.Register(() =>
{
    // Perform cleanup: flush telemetry, close connections
    Log.CloseAndFlush();
});
```

Ensure the `Host.ShutdownTimeout` allows in-flight requests to complete:

```csharp
builder.Host.ConfigureHostOptions(options =>
{
    options.ShutdownTimeout = TimeSpan.FromSeconds(25);
});
```

Set `ShutdownTimeout` to a value less than `terminationGracePeriodSeconds` to ensure the app shuts down before Kubernetes sends `SIGKILL`.

---

## Docker Compose for Local Development

Docker Compose provides a local development environment that mirrors production dependencies.

### Basic Compose File

```yaml
# docker-compose.yml
services:
  order-api:
    build:
      context: .
      dockerfile: src/OrderApi/Dockerfile
    ports:
      - "8080:8080"
    environment:
      # WARNING: Use "Production" for deployed environments. Development mode
      # exposes detailed error pages and stack traces.
      - ASPNETCORE_ENVIRONMENT=Development
      - ConnectionStrings__DefaultConnection=Host=postgres;Database=orders;Username=app;Password=devpassword
      - OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    # Note: CMD-SHELL + curl requires a base image with shell and curl installed.
    # Chiseled/distroless images lack both. For chiseled images, either use a
    # non-chiseled dev target in the Dockerfile or omit the healthcheck and rely
    # on depends_on ordering (acceptable for local dev).
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:8080/health/live || exit 1"]
      interval: 10s
      timeout: 3s
      retries: 3
      start_period: 10s

  postgres:
    image: postgres:17
    environment:
      POSTGRES_DB: orders
      POSTGRES_USER: app
      POSTGRES_PASSWORD: devpassword
    ports:
      - "5432:5432"
    volumes:
      - postgres-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U app -d orders"]
      interval: 5s
      timeout: 3s
      retries: 5

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 5

volumes:
  postgres-data:
```

### Development Override

Use a separate override file for development-specific settings:

```yaml
# docker-compose.override.yml (auto-loaded by docker compose up)
services:
  order-api:
    build:
      target: build  # Stop at build stage for faster rebuilds
    volumes:
      - .:/src       # Mount source for hot reload
    environment:
      - ASPNETCORE_ENVIRONMENT=Development
      - DOTNET_USE_POLLING_FILE_WATCHER=true
    command: ["dotnet", "watch", "run", "--project", "src/OrderApi/OrderApi.csproj"]
```

### Observability Stack

Add an OpenTelemetry collector and Grafana for local observability:

```yaml
# docker-compose.observability.yml
services:
  otel-collector:
    image: otel/opentelemetry-collector-contrib:latest
    command: ["--config=/etc/otelcol-config.yaml"]
    volumes:
      - ./infra/otelcol-config.yaml:/etc/otelcol-config.yaml
    ports:
      - "4317:4317"   # OTLP gRPC
      - "4318:4318"   # OTLP HTTP

  grafana:
    image: grafana/grafana:latest
    ports:
      - "3000:3000"
    volumes:
      - grafana-data:/var/lib/grafana

volumes:
  grafana-data:
```

Run with the observability stack:

```bash
docker compose -f docker-compose.yml -f docker-compose.observability.yml up
```

---

## CI/CD Integration

Basic CI/CD patterns for building and pushing .NET container images. Advanced CI patterns (matrix builds, environment promotion, deploy pipelines) -- see [skill:dotnet-devops] `references/gha-publish.md`, `references/gha-deploy.md`, and `references/ado-publish.md`.

### GitHub Actions: Build and Push

```yaml
# .github/workflows/docker-publish.yml
name: Build and Push Container

on:
  push:
    branches: [main]
    tags: ["v*"]

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

jobs:
  build-and-push:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write

    steps:
      - uses: actions/checkout@v4

      - name: Log in to container registry
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Extract metadata
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
          tags: |
            type=ref,event=branch
            type=semver,pattern={{version}}
            type=semver,pattern={{major}}.{{minor}}
            type=sha

      - name: Build and push
        uses: docker/build-push-action@v6
        with:
          context: .
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

### Image Tagging Strategy

| Tag Pattern | Example | Use Case |
|-------------|---------|----------|
| `latest` | `myapi:latest` | Development only -- never use in production |
| Semver | `myapi:1.2.3` | Release versions -- immutable |
| Major.Minor | `myapi:1.2` | Floating tag for patch updates |
| SHA | `myapi:sha-abc1234` | Unique per commit -- traceability |
| Branch | `myapi:main` | CI builds -- latest from branch |

### dotnet publish Container in CI

For projects using `dotnet publish /t:PublishContainer` instead of Dockerfiles:

```yaml
steps:
  - uses: actions/checkout@v4

  - uses: actions/setup-dotnet@v4
    with:
      dotnet-version: "10.0.x"

  - name: Publish container image
    run: |
      dotnet publish src/OrderApi/OrderApi.csproj \
        --os linux --arch x64 \
        /t:PublishContainer \
        -p:ContainerRegistry=${{ env.REGISTRY }} \
        -p:ContainerRepository=${{ env.IMAGE_NAME }} \
        -p:ContainerImageTag=${{ github.sha }}
```

---

## Key Principles

- **Use startup probes** to decouple initialization time from liveness detection -- without a startup probe, slow-starting apps get killed before they are ready
- **Separate liveness from readiness** -- liveness checks should not include dependency health (see [skill:dotnet-devops] for endpoint patterns)
- **Set resource requests and limits** -- without them, pods can starve other workloads or get OOM-killed unpredictably
- **Run as non-root** -- set `runAsNonRoot: true` in the pod security context and use chiseled images (see [skill:dotnet-devops] `references/containers.md`)
- **Use `depends_on` with health checks** in Docker Compose -- prevents app startup before dependencies are ready
- **Keep secrets out of manifests** -- use Kubernetes Secrets with external secrets operators, not plain values in source control
- **Match ShutdownTimeout to terminationGracePeriodSeconds** -- ensure the app finishes cleanup before Kubernetes sends SIGKILL

---

## Agent Gotchas

1. **Do not omit the startup probe** -- without it, the liveness probe runs during initialization and may restart slow-starting apps. Calculate startup budget as `failureThreshold * periodSeconds`.
2. **Do not include dependency checks in liveness probes** -- a database outage should not restart your app. Liveness endpoints must only check the process itself. See [skill:dotnet-devops] for the liveness vs readiness pattern.
3. **Do not use `latest` tag in Kubernetes manifests** -- `latest` is mutable and `imagePullPolicy: IfNotPresent` may serve stale images. Use immutable tags (semver or SHA).
4. **Do not hardcode connection strings in Kubernetes manifests** -- use Secrets or ConfigMaps referenced via `secretKeyRef`/`configMapRef`.
5. **Do not set `terminationGracePeriodSeconds` lower than `Host.ShutdownTimeout`** -- the app needs time to drain in-flight requests before Kubernetes sends SIGKILL.
6. **Do not forget `condition: service_healthy` in Docker Compose `depends_on`** -- without the condition, Compose starts dependent services immediately without waiting for health checks.

---

## References

- [Deploy ASP.NET Core to Kubernetes](https://learn.microsoft.com/en-us/aspnet/core/host-and-deploy/linux-nginx)
- [Kubernetes Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
- [Kubernetes probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)
- [Docker Compose overview](https://docs.docker.com/compose/)
- [ASP.NET Core health checks](https://learn.microsoft.com/en-us/aspnet/core/host-and-deploy/health-checks)
- [Graceful shutdown in .NET](https://learn.microsoft.com/en-us/dotnet/core/extensions/generic-host#host-shutdown)
- [GitHub Actions: Publishing Docker images](https://docs.github.com/en/actions/use-cases-and-examples/publishing-packages/publishing-docker-images)
