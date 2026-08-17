# Structured Logging

Log pipeline design and operations for .NET distributed systems. Covers log aggregation architecture (ELK, Seq, Grafana Loki), structured query patterns for each platform, log sampling and volume management strategies, PII scrubbing and destructuring policies, and cross-service correlation beyond single-service log scopes. This skill addresses what happens _after_ log emission -- the pipeline, query, and operations layer.

## Log Aggregation Architecture

### Architecture Options

| Platform | Ingest | Storage | Query | Best for |
|----------|--------|---------|-------|----------|
| **ELK** (Elasticsearch, Logstash, Kibana) | Logstash / Filebeat | Elasticsearch | KQL in Kibana | Large-scale, flexible schema, full-text search |
| **Seq** | HTTP API / Serilog sink | Built-in | Seq signal expressions | .NET-native, developer-friendly, structured queries |
| **Grafana Loki** | Promtail / OTel Collector | Loki (label-indexed) | LogQL | Cost-effective, Grafana ecosystem, label-based queries |
| **Azure Monitor** | OTel Collector / Application Insights SDK | Log Analytics workspace | KQL (Kusto) | Azure-native, integrated alerting, cost management |

### Recommended Pipeline Patterns

**Pattern 1: OTel Collector as central router**

```
App (OTLP) --> OTel Collector --> Elasticsearch / Loki / Azure Monitor
                  |
                  +--> Sampling / filtering / PII scrub
```

The OpenTelemetry Collector acts as a vendor-neutral log router. Applications emit logs via OTLP; the collector handles filtering, sampling, enrichment, and routing to one or more backends. This decouples applications from backend choice.

```yaml
# otel-collector-config.yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: "0.0.0.0:4317"
      http:
        endpoint: "0.0.0.0:4318"

processors:
  batch:
    timeout: 5s
    send_batch_size: 1024
  filter:
    logs:
      exclude:
        match_type: strict
        bodies:
          - "Health check endpoint hit"

exporters:
  elasticsearch:
    endpoints: ["https://es-cluster:9200"]
    logs_index: "app-logs"
  loki:
    endpoint: "http://loki:3100/loki/api/v1/push"

service:
  pipelines:
    logs:
      receivers: [otlp]
      processors: [batch, filter]
      exporters: [elasticsearch, loki]
```

**Pattern 2: Direct sink (smaller deployments)**

```
App (Serilog) --> Seq / Elasticsearch sink
```

For smaller systems or development environments, Serilog sinks write directly to the aggregation platform. This avoids the OTel Collector but couples the application to the backend.

### .NET Application OTLP Configuration

For .NET application-side OTLP log export configuration (`builder.Logging.AddOpenTelemetry()`), see [skill:dotnet-devops] `references/observability.md`. The OTLP endpoint is configured via environment variables (`OTEL_EXPORTER_OTLP_ENDPOINT`), keeping application code backend-agnostic.

---

## Structured Query Patterns

Structured logs store each property as a queryable field. The query syntax differs by platform but the concepts are consistent: filter by property name, value, severity, and time range.

### Kibana KQL (Elasticsearch / ELK)

```
# Find errors for a specific order
level: "Error" AND OrderId: "abc-123"

# Find slow operations (custom Duration property)
Duration > 5000 AND ServiceName: "order-api"

# Wildcard on message template
message: "Failed to process*" AND NOT level: "Debug"

# Time-scoped with correlation
TraceId: "0af7651916cd43dd8448eb211c80319c" AND @timestamp >= "2025-01-15T10:00:00"
```

### Seq Signal Expressions

```
# Find errors for a specific order
@Level = 'Error' and OrderId = 'abc-123'

# Find slow operations
Duration > 5000 and Application = 'order-api'

# Free-text search combined with structured filter
@Message like '%timeout%' and @Level in ['Warning', 'Error']

# Correlation across services
TraceId = '0af7651916cd43dd8448eb211c80319c'
```

Seq signals are saved queries that trigger alerts. Define signals for recurring patterns (e.g., "Payment failures > 10/min") and attach notification channels.

### Grafana LogQL (Loki)

```
# Filter by labels then regex on log line
{service_name="order-api"} |= "Error" | json | OrderId="abc-123"

# Structured field extraction and filtering
{service_name="order-api"} | json | Duration > 5000

# Count errors per service over time (for dashboards)
sum(rate({service_name=~".+"} |= "Error" [5m])) by (service_name)
```

### Azure Monitor KQL (Kusto)

```kusto
// Find errors for a specific order
traces
| where severityLevel >= 3
| where customDimensions.OrderId == "abc-123"
| order by timestamp desc

// Slow operations
traces
| where toint(customDimensions.Duration) > 5000
| where cloud_RoleName == "order-api"

// Cross-service correlation
union traces, exceptions
| where operation_Id == "0af7651916cd43dd8448eb211c80319c"
| order by timestamp asc
```

---

## Log Sampling and Volume Management

High-throughput systems can generate millions of log events per minute. Without sampling, storage costs and query performance degrade rapidly.

### Sampling Strategies

| Strategy | How it works | Use when |
|----------|-------------|----------|
| **Head-based** | Decide to sample before processing | Consistent per-request; simple to implement |
| **Tail-based** | Decide to sample after processing | Keep all errors/slow requests, drop routine logs |
| **Level-based** | Sample by severity | Always keep Warning+, sample Debug/Info |
| **Dynamic** | Adjust rate based on volume | Handle traffic spikes without config changes |

### OTel Collector Log Filtering

The `filter` processor in the OTel Collector drops log records at the pipeline level before they reach exporters. Use it to exclude noisy low-severity logs and reduce storage volume.

Note: The `tail_sampling` processor operates on **traces** (spans), not logs. For log volume management, use the `filter` and `transform` processors instead.

```yaml
processors:
  filter:
    logs:
      exclude:
        match_type: regexp
        # Drop Debug and Trace logs at the collector level
        severity_texts: ["DEBUG", "TRACE"]
      exclude:
        match_type: strict
        # Exclude health check noise
        bodies:
          - "Health check endpoint hit"
  transform:
    log_statements:
      - context: log
        conditions:
          # Keep all Warning+ logs unconditionally
          - severity_number >= SEVERITY_NUMBER_WARN
        statements: []
```

### Application-Level Sampling with Serilog

```csharp
// Serilog.Expressions package for conditional log filtering
builder.Host.UseSerilog((context, loggerConfiguration) =>
{
    loggerConfiguration
        .ReadFrom.Configuration(context.Configuration)
        // Drop health check logs entirely
        .Filter.ByExcluding("RequestPath = '/health/ready'")
        // Sample Debug logs at 10%
        .Filter.ByExcluding(
            "@Level = 'Debug' and Hash(@i) % 10 != 0");
});
```

**Key packages:**

```xml
<PackageReference Include="Serilog.Expressions" Version="5.*" />
```

### Volume Management Checklist

1. **Set retention policies** per index/stream (e.g., 30 days for Info, 90 days for Error)
2. **Use log level filtering** to suppress noisy framework categories at the source
3. **Exclude health check endpoints** from request logging
4. **Apply index lifecycle management** (ILM in Elasticsearch, retention policies in Loki)
5. **Monitor ingestion rates** and set budget alerts on storage costs

---

## PII Scrubbing and Destructuring Policies

Logs must not contain personally identifiable information (PII) in production. GDPR, HIPAA, and SOC 2 require that sensitive data is masked or excluded from log storage.

### Property-Level Masking with Enrichers

```csharp
// Enricher that masks known-sensitive properties on every log event
public sealed class PiiMaskingEnricher : ILogEventEnricher
{
    private static readonly HashSet<string> s_sensitiveKeys = new(
        StringComparer.OrdinalIgnoreCase)
    {
        "Email", "PhoneNumber", "IpAddress",
        "CreditCard", "SSN", "Password"
    };

    public void Enrich(LogEvent logEvent, ILogEventPropertyFactory factory)
    {
        var propertiesToMask = logEvent.Properties
            .Where(p => s_sensitiveKeys.Contains(p.Key))
            .Select(p => p.Key)
            .ToList();

        foreach (var key in propertiesToMask)
        {
            logEvent.AddOrUpdateProperty(
                factory.CreateProperty(key, "***REDACTED***"));
        }
    }
}

// Registration
loggerConfiguration.Enrich.With<PiiMaskingEnricher>();
```

### OTel Collector Attribute Processing

```yaml
processors:
  attributes:
    actions:
      # Mask email addresses using regex
      - key: user.email
        action: update
        value: "***@redacted.com"
      # Remove sensitive attributes entirely
      - key: http.request.header.authorization
        action: delete
      - key: user.password
        action: delete
```

### PII Scrubbing Checklist

1. **Identify PII fields** -- email, phone, IP, SSN, credit card, auth tokens, cookies
2. **Apply at the earliest point** -- enricher or OTel processor, not at query time
3. **Audit log templates** -- ensure structured log templates do not capture PII as named properties
4. **Test with compliance team** -- validate scrubbing rules against regulatory requirements
5. **Use separate retention** for audit logs that legitimately require PII (with encryption at rest)

---

## Cross-Service Correlation

In distributed systems, a single user request may traverse multiple services. Correlation enables tracing a request across all services and reconstructing the full event timeline.

### W3C Trace Context Correlation

The primary correlation mechanism is the W3C `traceparent` header, which propagates automatically through `HttpClient` when OpenTelemetry instrumentation is configured (see [skill:dotnet-devops] `references/observability.md`). All log events emitted within a traced request include `TraceId` and `SpanId` properties.

```csharp
// Query all logs for a distributed operation across services
// In Seq:
TraceId = '0af7651916cd43dd8448eb211c80319c'

// In Kibana:
TraceId: "0af7651916cd43dd8448eb211c80319c"

// In Azure Monitor:
traces | where operation_Id == "0af7651916cd43dd8448eb211c80319c"
```

### Custom Correlation IDs

When trace context is insufficient (e.g., async workflows spanning message queues, batch jobs, or external system callbacks), add custom correlation IDs:

```csharp
// Propagate a business correlation ID through Serilog LogContext
public sealed class CorrelationIdMiddleware(RequestDelegate next)
{
    private const string CorrelationHeader = "X-Correlation-Id";

    public async Task InvokeAsync(HttpContext context)
    {
        var correlationId = context.Request.Headers[CorrelationHeader]
            .FirstOrDefault() ?? Guid.NewGuid().ToString("N");

        context.Response.Headers[CorrelationHeader] = correlationId;

        using (LogContext.PushProperty("CorrelationId", correlationId))
        {
            await next(context);
        }
    }
}

// Registration
app.UseMiddleware<CorrelationIdMiddleware>();
```

### Message Queue Correlation

For asynchronous messaging (Azure Service Bus, RabbitMQ), propagate correlation through message properties:

```csharp
// Producer -- attach correlation to message
var message = new ServiceBusMessage(payload)
{
    CorrelationId = Activity.Current?.TraceId.ToString()
        ?? Guid.NewGuid().ToString("N"),
    ApplicationProperties =
    {
        ["BusinessCorrelationId"] = orderId.ToString()
    }
};

// Consumer -- restore correlation in log scope
processor.ProcessMessageAsync += async args =>
{
    using var scope = logger.BeginScope(new Dictionary<string, object>
    {
        ["CorrelationId"] = args.Message.CorrelationId,
        ["BusinessCorrelationId"] =
            args.Message.ApplicationProperties["BusinessCorrelationId"]
    });

    logger.LogInformation("Processing message {MessageId}", args.Message.MessageId);
    await ProcessAsync(args.Message, args.CancellationToken);
};
```

### Correlation Best Practices

| Practice | Rationale |
|----------|-----------|
| Always include `TraceId` in log output | Enables log-to-trace joins in observability platforms |
| Use `CorrelationId` for business flows | Survives async gaps where trace context resets |
| Store correlation IDs in message headers | Enables end-to-end tracing through queues |
| Include correlation in error responses | Enables support teams to look up the full trace |
| Use Serilog `LogContext.PushProperty` or MEL `BeginScope` | Automatically attaches to all log events in scope |

---

## Agent Gotchas

1. **Do not conflate log emission with log pipeline** -- this skill covers pipeline, query, and operations. For Serilog/MEL configuration, enrichers, sink registration, and source-generated LoggerMessage, see [skill:dotnet-devops] `references/observability.md`.
2. **Do not store PII in production logs** -- apply masking enrichers or OTel processor rules at the pipeline level. Redacting after storage is insufficient for compliance.
3. **Do not skip log sampling for high-throughput services** -- unsampled Debug/Info logs in a service handling thousands of requests per second will overwhelm storage and degrade query performance. Use tail-based sampling to keep all errors and slow requests.
4. **Do not hardcode aggregation platform endpoints in application code** -- use environment variables (`OTEL_EXPORTER_OTLP_ENDPOINT`) or configuration so the same image works across environments.
5. **Do not rely solely on TraceId for business correlation** -- trace context resets at async boundaries (message queues, scheduled jobs). Add explicit business correlation IDs for workflows that span these boundaries.
6. **Do not forget retention policies** -- logs without retention policies accumulate indefinitely, increasing costs and slowing queries. Set per-severity retention (e.g., 30 days for Info, 90 days for Error).

---

## References

- [OpenTelemetry Collector configuration](https://opentelemetry.io/docs/collector/configuration/)
- [Seq documentation](https://docs.datalust.co/docs)
- [Seq signal expressions](https://docs.datalust.co/docs/the-seq-query-language)
- [Grafana Loki LogQL](https://grafana.com/docs/loki/latest/query/)
- [Elasticsearch KQL syntax](https://www.elastic.co/guide/en/kibana/current/kuery-query.html)
- [Serilog.Expressions](https://github.com/serilog/serilog-expressions)
- [Serilog PII masking](https://github.com/serilog/serilog/wiki/Structured-Data#masking-sensitive-data)
- [Azure Monitor KQL reference](https://learn.microsoft.com/en-us/azure/data-explorer/kusto/query/)
- [W3C Trace Context specification](https://www.w3.org/TR/trace-context/)
