# Service Communication

Higher-level routing skill for choosing the right service communication protocol. Provides a decision matrix mapping requirements (latency, direction, client type, payload format, browser support) to the five primary .NET communication protocols: gRPC, SignalR, SSE, JSON-RPC 2.0, and REST. Routes to specialized skills for implementation depth.

## Decision Matrix

Use this matrix to choose the right protocol based on your requirements:

| Requirement | gRPC | SignalR | SSE | JSON-RPC 2.0 | REST |
|-------------|------|---------|-----|--------------|------|
| **Direction** | All four patterns | Full-duplex | Server-to-client | Request-response | Request-response |
| **Wire format** | Protobuf (binary) | JSON or MessagePack | Text (JSON lines) | JSON | JSON/XML |
| **Browser support** | gRPC-Web (proxy needed) | Yes (JS client) | Yes (native EventSource) | Via WebSocket | Yes (fetch/XHR) |
| **Contract** | `.proto` schema | Hub interface | Convention | JSON-RPC spec | OpenAPI/Swagger |
| **Latency** | Lowest | Low | Low | Medium | Medium |
| **Throughput** | Highest | High | Moderate | Moderate | Moderate |
| **Streaming** | All 4 patterns | Server + client streaming | Server push only | No | No (chunked transfer) |
| **Connection** | HTTP/2 persistent | WebSocket (with fallback) | HTTP/1.1+ persistent | Transport-dependent | Per-request |
| **Service-to-service** | Excellent | Good | Limited | Niche | Good |
| **AOT-friendly** | Yes (Protobuf) | Yes | Yes | Yes | Yes (with STJ source gen) |

---

## Decision Flowchart

```
Is this service-to-service (no browser)?
├── Yes → Do you need streaming?
│   ├── Yes → gRPC streaming [skill:dotnet-api]
│   └── No → Is it request-response?
│       ├── High throughput / binary → gRPC (unary) [skill:dotnet-api]
│       └── Standard CRUD / public API → REST [skill:dotnet-api]
└── No (browser client) → Do you need real-time?
    ├── Yes → Do you need bidirectional?
    │   ├── Yes → SignalR [skill:dotnet-api]
    │   └── No (server push only) → SSE [skill:dotnet-api]
    └── No → REST [skill:dotnet-api]

Special cases:
- LSP / tooling protocol → JSON-RPC 2.0 [skill:dotnet-api]
- Mixed (browser + service-to-service) → REST for browser, gRPC for internal
```

---

## Protocol Profiles

### gRPC

**Best for:** Service-to-service communication, high-throughput streaming, strongly-typed contracts.

- Schema-first development with `.proto` files
- All four streaming patterns: unary, server streaming, client streaming, bidirectional
- Binary serialization (Protobuf) for smallest payloads and fastest throughput
- Built-in code generation for client and server stubs
- Native load balancing and health check protocol support

**When NOT to use:** Direct browser communication (requires gRPC-Web proxy), simple CRUD APIs consumed by external clients, scenarios where human-readable payloads are required.

See [skill:dotnet-api] for full implementation details.

### SignalR

**Best for:** Browser-facing real-time applications, interactive dashboards, chat, collaborative features.

- Automatic transport negotiation (WebSocket → SSE → Long Polling)
- Built-in group management and user targeting
- Hub abstraction with strongly-typed interfaces
- Scales with Redis backplane or Azure SignalR Service
- Supports JSON and MessagePack serialization

**When NOT to use:** Server-to-client-only push (use SSE instead), service-to-service (use gRPC instead), scenarios where the SignalR client library cannot be included.

See [skill:dotnet-api] for SignalR patterns and hub implementation.

### Server-Sent Events (SSE)

**Best for:** Simple server-to-client push notifications, live feeds, status updates.

- Built-in to ASP.NET Core in .NET 10 via `TypedResults.ServerSentEvents`
- Browser-native `EventSource` API -- no client library needed
- Automatic reconnection with `Last-Event-ID`
- Works through HTTP/1.1 proxies that block WebSocket upgrade
- Lightest-weight real-time option

**When NOT to use:** Bidirectional communication (use SignalR), high-throughput binary streaming (use gRPC), client-to-server messages needed.

See [skill:dotnet-api] for SSE implementation details.

### JSON-RPC 2.0

**Best for:** Tooling protocols (Language Server Protocol), structured RPC over simple transports.

- Transport-agnostic (HTTP, WebSocket, stdio, named pipes)
- Well-defined request/response/notification semantics
- Used by Visual Studio, VS Code, and .NET tooling via StreamJsonRpc
- Lightweight alternative to gRPC when schema management is unwanted

**When NOT to use:** Real-time streaming (use SignalR or gRPC), high-throughput service-to-service (use gRPC), standard web APIs (use REST).

See [skill:dotnet-api] for JSON-RPC 2.0 patterns.

### REST (HTTP APIs)

**Best for:** Public APIs, standard CRUD operations, broad client compatibility.

- Universal client support (any HTTP client)
- Human-readable payloads (JSON)
- Rich ecosystem (OpenAPI, Swagger UI, API versioning)
- Stateless request-response model
- ASP.NET Core Minimal APIs or MVC controllers

**When NOT to use:** Real-time push (use SSE or SignalR), high-throughput service-to-service (use gRPC), bidirectional streaming (use SignalR or gRPC).

See [skill:dotnet-api] for HTTP client patterns, resilience, and `IHttpClientFactory`.

---

## Common Architecture Patterns

### API Gateway with Mixed Protocols

```
Browser ─── REST/SignalR ──→ API Gateway ──→ gRPC ──→ Internal Services
                                          ──→ gRPC ──→ Order Service
                                          ──→ gRPC ──→ Inventory Service
```

Use REST for public-facing APIs and SignalR for real-time browser features. Internal service-to-service communication uses gRPC for performance. The API gateway translates between protocols.

### Event-Driven with SSE

```
Internal Services ──→ Message Broker ──→ SSE Endpoint ──→ Browser Dashboard
                                     ──→ gRPC Stream  ──→ Monitoring Service
```

Internal events flow through a message broker. Browser dashboards consume via SSE. Other services consume via gRPC streaming for higher throughput.

### Dual-Protocol Services

A single ASP.NET Core host can serve both gRPC and REST:

```csharp
var builder = WebApplication.CreateBuilder(args);

builder.Services.AddGrpc();
builder.Services.AddControllers();

var app = builder.Build();

// gRPC for internal service-to-service
app.MapGrpcService<OrderGrpcService>();

// REST for external clients
app.MapControllers();

// SSE for real-time browser updates
app.MapGet("/events/orders", (OrderEventService svc, CancellationToken ct) =>
    TypedResults.ServerSentEvents(svc.GetEventsAsync(ct)));
```

---

## Key Principles

- **Use gRPC for service-to-service** -- it provides the best throughput, strongly-typed contracts, and all streaming patterns
- **Use REST for public APIs** -- universal client support, human-readable, extensive tooling ecosystem
- **Use SignalR for browser real-time** -- automatic transport negotiation and built-in group management
- **Use SSE for simple server push** -- lightest option when bidirectional communication is not needed
- **Mix protocols when appropriate** -- a single ASP.NET Core host can serve gRPC, REST, SignalR, and SSE simultaneously
- **Route based on client type** -- browser clients get REST/SignalR/SSE; internal services get gRPC

See [skill:dotnet-tooling] for Native AOT/trimming guidance and build pipeline implications.

---

## Agent Gotchas

1. **Do not default to gRPC for browser-facing APIs** -- browsers cannot speak HTTP/2 trailers natively. Use gRPC-Web with a proxy or choose REST/SignalR/SSE.
2. **Do not use SignalR for service-to-service** -- gRPC provides better performance, code generation, and streaming for backend communication.
3. **Do not add SignalR when SSE suffices** -- if you only need server-to-client push, SSE is simpler, requires no client library, and has automatic reconnection built into browsers.
4. **Do not use REST for high-throughput internal communication** -- JSON text serialization and per-request connections add overhead vs gRPC's binary format and persistent HTTP/2 connections.
5. **Do not forget AOT considerations** -- REST endpoints using System.Text.Json need source-generated contexts for AOT. See [skill:dotnet-csharp] for details.
6. **Do not expose gRPC services to untrusted clients without gRPC-Web** -- raw gRPC requires HTTP/2, which is not universally available in all environments (e.g., some proxies, older browsers).

---

## References

- [Choose between gRPC and REST](https://learn.microsoft.com/en-us/aspnet/core/grpc/comparison?view=aspnetcore-10.0)
- [gRPC for .NET](https://learn.microsoft.com/en-us/aspnet/core/grpc/?view=aspnetcore-10.0)
- [SignalR overview](https://learn.microsoft.com/en-us/aspnet/core/signalr/introduction?view=aspnetcore-10.0)
- [Server-Sent Events in .NET 10](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/server-sent-events?view=aspnetcore-10.0)
- [Minimal APIs](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/minimal-apis?view=aspnetcore-10.0)
- [IHttpClientFactory patterns](https://learn.microsoft.com/en-us/dotnet/core/extensions/httpclient-factory)
