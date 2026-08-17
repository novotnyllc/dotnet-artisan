# Real-Time Communication

Real-time communication patterns for .NET applications. Compares SignalR (full-duplex over WebSockets with automatic fallback), Server-Sent Events (SSE, built-in to ASP.NET Core in .NET 10), JSON-RPC 2.0 (structured request-response over any transport), and gRPC streaming (high-performance binary streaming). Provides decision guidance for choosing the right protocol based on requirements.

## Protocol Comparison

| Protocol | Direction | Transport | Format | Browser Support | Best For |
|----------|-----------|-----------|--------|-----------------|----------|
| **SignalR** | Full-duplex | WebSocket, SSE, Long Polling (auto-negotiation) | JSON or MessagePack | Yes (JS/TS client) | Interactive apps, chat, dashboards, collaborative editing |
| **SSE (.NET 10)** | Server-to-client only | HTTP/1.1+ | Text (typically JSON lines) | Yes (native EventSource API) | Notifications, live feeds, status updates |
| **JSON-RPC 2.0** | Request-response | Any (HTTP, WebSocket, stdio) | JSON | Depends on transport | Tooling protocols (LSP), structured RPC over simple transports |
| **gRPC streaming** | All four patterns | HTTP/2 | Protobuf (binary) | Limited (gRPC-Web) | Service-to-service, high-throughput, low-latency streaming |

### When to Choose What

- **SignalR**: You need bidirectional real-time communication with browser clients. SignalR handles transport negotiation automatically (WebSocket preferred, falls back to SSE, then Long Polling). Use when clients need to both send and receive in real time.
- **SSE (.NET 10 built-in)**: You only need server-to-client push. Simpler than SignalR when bidirectional communication is not required. Built into ASP.NET Core in .NET 10 -- no additional packages needed. Works with the browser's native `EventSource` API.
- **JSON-RPC 2.0**: You need structured request-response semantics over a simple transport. Used by Language Server Protocol (LSP) and some .NET tooling. Not a streaming protocol -- use when you need named methods with typed parameters over WebSocket or stdio.
- **gRPC streaming**: Service-to-service streaming with maximum performance. Supports all four streaming patterns (unary, server streaming, client streaming, bidirectional). Best when both endpoints are .NET services or gRPC-compatible. See [skill:dotnet-api] for implementation details.

---

## SignalR

SignalR provides real-time web functionality with automatic connection management and transport negotiation.

### Server Setup

```csharp
var builder = WebApplication.CreateBuilder(args);

builder.Services.AddSignalR(options =>
{
    options.EnableDetailedErrors = builder.Environment.IsDevelopment();
    options.MaximumReceiveMessageSize = 64 * 1024; // 64 KB
    options.KeepAliveInterval = TimeSpan.FromSeconds(15);
});

var app = builder.Build();

app.MapHub<NotificationHub>("/hubs/notifications");
```

### Hub Implementation

```csharp
public sealed class NotificationHub(
    ILogger<NotificationHub> logger) : Hub
{
    public override async Task OnConnectedAsync()
    {
        var userId = Context.UserIdentifier;
        if (userId is not null)
        {
            await Groups.AddToGroupAsync(Context.ConnectionId, $"user:{userId}");
        }

        await base.OnConnectedAsync();
    }

    // Client-to-server method
    public async Task SendMessage(string channel, string message)
    {
        // Broadcast to all clients in the channel group
        await Clients.Group(channel).SendAsync("ReceiveMessage",
            Context.UserIdentifier, message);
    }

    // Server-to-client streaming
    public async IAsyncEnumerable<StockPrice> StreamPrices(
        string symbol,
        [EnumeratorCancellation] CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            yield return await GetLatestPrice(symbol, cancellationToken);
            await Task.Delay(1000, cancellationToken);
        }
    }
}
```

### Strongly-Typed Hubs

Use interfaces to get compile-time safety for client method calls:

```csharp
public interface INotificationClient
{
    Task ReceiveMessage(string user, string message);
    Task OrderStatusChanged(int orderId, string status);
}

public sealed class NotificationHub(
    ILogger<NotificationHub> logger) : Hub<INotificationClient>
{
    public async Task SendMessage(string channel, string message)
    {
        // Compile-time checked -- no magic strings
        await Clients.Group(channel).ReceiveMessage(
            Context.UserIdentifier!, message);
    }
}
```

### Sending from Outside Hubs

Inject `IHubContext` to send messages from background services or controllers:

```csharp
public sealed class OrderService(
    IHubContext<NotificationHub, INotificationClient> hubContext)
{
    public async Task UpdateOrderStatus(int orderId, string userId, string status)
    {
        // Send to specific user group
        await hubContext.Clients.Group($"user:{userId}")
            .OrderStatusChanged(orderId, status);
    }
}
```

### Transport Negotiation

SignalR automatically negotiates the best transport:

1. **WebSocket** (preferred) -- full-duplex, lowest latency
2. **Server-Sent Events** -- server-to-client only, falls back when WebSockets unavailable
3. **Long Polling** -- universal fallback, highest latency

Force a specific transport when needed:

```csharp
// Server: disable specific transports
app.MapHub<NotificationHub>("/hubs/notifications", options =>
{
    options.Transports = HttpTransportType.WebSockets |
                         HttpTransportType.ServerSentEvents;
    // Disables Long Polling
});
```

### MessagePack Protocol

Use MessagePack for smaller payloads and faster serialization:

```csharp
// Server
builder.Services.AddSignalR()
    .AddMessagePackProtocol();

// Client (JavaScript)
// new signalR.HubConnectionBuilder()
//     .withUrl("/hubs/notifications")
//     .withHubProtocol(new signalR.protocols.msgpack.MessagePackHubProtocol())
//     .build();
```

### Connection Lifecycle

Override `OnConnectedAsync` and `OnDisconnectedAsync` to manage connection state:

```csharp
public sealed class NotificationHub(
    ILogger<NotificationHub> logger,
    IConnectionTracker tracker) : Hub<INotificationClient>
{
    public override async Task OnConnectedAsync()
    {
        var userId = Context.UserIdentifier;
        var connectionId = Context.ConnectionId;

        logger.LogInformation("Client {ConnectionId} connected (user: {UserId})",
            connectionId, userId);

        // Track connection for presence features
        if (userId is not null)
        {
            await tracker.AddConnectionAsync(userId, connectionId);
            await Groups.AddToGroupAsync(connectionId, $"user:{userId}");
        }

        await base.OnConnectedAsync();
    }

    public override async Task OnDisconnectedAsync(Exception? exception)
    {
        var userId = Context.UserIdentifier;
        var connectionId = Context.ConnectionId;

        if (exception is not null)
        {
            logger.LogWarning(exception,
                "Client {ConnectionId} disconnected with error", connectionId);
        }

        if (userId is not null)
        {
            await tracker.RemoveConnectionAsync(userId, connectionId);
        }

        await base.OnDisconnectedAsync(exception);
    }
}
```

### Groups Management

Groups provide a lightweight pub/sub mechanism. Connections can belong to multiple groups and group membership is managed per-connection:

```csharp
public sealed class ChatHub : Hub<IChatClient>
{
    // Join a room (called by clients)
    public async Task JoinRoom(string roomName)
    {
        await Groups.AddToGroupAsync(Context.ConnectionId, roomName);
        await Clients.Group(roomName).UserJoined(Context.UserIdentifier!, roomName);
    }

    // Leave a room
    public async Task LeaveRoom(string roomName)
    {
        await Groups.RemoveFromGroupAsync(Context.ConnectionId, roomName);
        await Clients.Group(roomName).UserLeft(Context.UserIdentifier!, roomName);
    }

    // Send to specific group
    public async Task SendToRoom(string roomName, string message)
    {
        await Clients.Group(roomName).ReceiveMessage(
            Context.UserIdentifier!, message);
    }

    // Send to all except caller
    public async Task BroadcastExceptSelf(string message)
    {
        await Clients.Others.ReceiveMessage(
            Context.UserIdentifier!, message);
    }
}
```

Groups are not persisted -- they are cleared when a connection disconnects. Re-add connections to groups in `OnConnectedAsync` if needed (e.g., from a database or cache).

### Client-to-Server Streaming

Clients can stream data to the hub using `IAsyncEnumerable<T>` or `ChannelReader<T>`:

```csharp
public sealed class UploadHub : Hub
{
    // Accept a stream of items from the client
    public async Task UploadData(
        IAsyncEnumerable<SensorReading> stream,
        CancellationToken cancellationToken)
    {
        await foreach (var reading in stream.WithCancellation(cancellationToken))
        {
            await ProcessReading(reading);
        }
    }
}
```

### Authentication

SignalR uses the same authentication as the ASP.NET Core host. For WebSocket connections, the access token is sent via query string because WebSocket does not support custom headers:

```csharp
// Server: configure JWT for SignalR
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.Authority = "https://identity.example.com";
        options.Events = new JwtBearerEvents
        {
            OnMessageReceived = context =>
            {
                // Read token from query string for WebSocket requests
                var accessToken = context.Request.Query["access_token"];
                var path = context.HttpContext.Request.Path;
                if (!string.IsNullOrEmpty(accessToken) &&
                    path.StartsWithSegments("/hubs"))
                {
                    context.Token = accessToken;
                }
                return Task.CompletedTask;
            }
        };
    });

builder.Services.AddAuthorization();

var app = builder.Build();

app.UseAuthentication();
app.UseAuthorization();

app.MapHub<NotificationHub>("/hubs/notifications")
    .RequireAuthorization();
```

Access `Context.UserIdentifier` in the hub to identify the authenticated user. By default this maps to the `ClaimTypes.NameIdentifier` claim. Customize with `IUserIdProvider`:

```csharp
public sealed class EmailUserIdProvider : IUserIdProvider
{
    public string? GetUserId(HubConnectionContext connection)
    {
        return connection.User?.FindFirst(ClaimTypes.Email)?.Value;
    }
}

// Register
builder.Services.AddSingleton<IUserIdProvider, EmailUserIdProvider>();
```

### Scaling with Backplane

For multi-server deployments, use a backplane to synchronize messages across instances. Without a backplane, messages sent on one server are not visible to connections on other servers.

**Redis backplane:**

```csharp
builder.Services.AddSignalR()
    .AddStackExchangeRedis(builder.Configuration.GetConnectionString("Redis")!,
        options =>
        {
            options.Configuration.ChannelPrefix =
                RedisChannel.Literal("MyApp:");
        });
```

**Azure SignalR Service (managed backplane):**

```csharp
builder.Services.AddSignalR()
    .AddAzureSignalR(builder.Configuration["Azure:SignalR:ConnectionString"]);
```

Azure SignalR Service offloads connection management entirely -- the ASP.NET Core server handles hub logic while Azure manages WebSocket connections, scaling, and message routing.

---

## Server-Sent Events (SSE) -- .NET 10

.NET 10 adds built-in SSE support to ASP.NET Core, making server-to-client streaming straightforward without additional packages.

### Minimal API Endpoint

```csharp
app.MapGet("/events/orders", async (
    OrderEventService eventService,
    CancellationToken cancellationToken) =>
{
    // TypedResults.ServerSentEvents returns an SSE response
    return TypedResults.ServerSentEvents(
        eventService.GetOrderEventsAsync(cancellationToken));
});
```

### Event Source Implementation

```csharp
public sealed class OrderEventService
{
    public async IAsyncEnumerable<SseItem<OrderEvent>> GetOrderEventsAsync(
        [EnumeratorCancellation] CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            var evt = await WaitForNextEvent(cancellationToken);
            yield return new SseItem<OrderEvent>(evt, "order-update");
        }
    }
}
```

### Browser Client

```javascript
const source = new EventSource('/events/orders');

source.addEventListener('order-update', (event) => {
    const order = JSON.parse(event.data);
    updateDashboard(order);
});

source.onerror = () => {
    // EventSource automatically reconnects
    console.log('SSE connection lost, reconnecting...');
};
```

### When to Use SSE Over SignalR

- **One-way push only** -- SSE is simpler when you do not need client-to-server messages
- **Browser native** -- no JavaScript library needed (uses `EventSource` API)
- **Automatic reconnection** -- browsers reconnect automatically with `Last-Event-ID`
- **HTTP/1.1 compatible** -- works through proxies that do not support WebSocket upgrade

---

## JSON-RPC 2.0

JSON-RPC 2.0 is a stateless, transport-agnostic remote procedure call protocol encoded in JSON. It is the foundation of the Language Server Protocol (LSP) and is used in some .NET tooling scenarios.

### Protocol Structure

```json
// Request
{"jsonrpc": "2.0", "method": "textDocument/completion", "params": {...}, "id": 1}

// Response
{"jsonrpc": "2.0", "result": {...}, "id": 1}

// Notification (no response expected)
{"jsonrpc": "2.0", "method": "textDocument/didChange", "params": {...}}

// Error
{"jsonrpc": "2.0", "error": {"code": -32600, "message": "Invalid Request"}, "id": 1}
```

### StreamJsonRpc (.NET Library)

`StreamJsonRpc` is the primary .NET library for JSON-RPC 2.0:

```xml
<PackageReference Include="StreamJsonRpc" Version="2.*" />
```

```csharp
// Server: expose methods via JSON-RPC over a stream
using StreamJsonRpc;

public sealed class CalculatorService
{
    public int Add(int a, int b) => a + b;
    public Task<double> DivideAsync(double a, double b) =>
        b == 0 ? throw new ArgumentException("Division by zero")
               : Task.FromResult(a / b);
}

// Wire up over a WebSocket -- UseWebSockets() is required for upgrade handling
app.UseWebSockets();
app.Map("/jsonrpc", async (HttpContext context) =>
{
    if (!context.WebSockets.IsWebSocketRequest)
    {
        context.Response.StatusCode = 400;
        return;
    }

    var ws = await context.WebSockets.AcceptWebSocketAsync();
    using var rpc = new JsonRpc(new WebSocketMessageHandler(ws));
    rpc.AddLocalRpcTarget(new CalculatorService());
    rpc.StartListening();
    await rpc.Completion;
});
```

```csharp
// Client
using var ws = new ClientWebSocket();
await ws.ConnectAsync(new Uri("ws://localhost:5000/jsonrpc"),
    CancellationToken.None);

using var rpc = new JsonRpc(new WebSocketMessageHandler(ws));
rpc.StartListening();

var result = await rpc.InvokeAsync<int>("Add", 2, 3);
// result == 5
```

### When to Use JSON-RPC 2.0

- Building or integrating with Language Server Protocol (LSP) implementations
- Simple RPC over WebSocket or stdio where gRPC is too heavyweight
- Interoperating with non-.NET systems that speak JSON-RPC
- Tooling and editor integrations

---

## gRPC Streaming

See [skill:dotnet-api] for complete gRPC implementation details including all four streaming patterns (unary, server streaming, client streaming, bidirectional streaming), authentication, load balancing, and health checks.

### Quick Decision: gRPC Streaming vs SignalR vs SSE

| Requirement | Choose |
|-------------|--------|
| Service-to-service, both .NET | gRPC streaming |
| Browser client needs bidirectional | SignalR |
| Browser client needs server push only | SSE |
| Maximum throughput, binary payloads | gRPC streaming |
| Automatic reconnection with browser clients | SSE (native) or SignalR (built-in) |
| Multiple client platforms (JS, mobile, .NET) | SignalR |

---

## Key Principles

- **Default to SignalR for browser-facing real-time** -- it handles transport negotiation, reconnection, and grouping out of the box
- **Use SSE for simple server push** -- .NET 10 built-in support makes it the lightest option for one-way notifications
- **Use gRPC streaming for service-to-service** -- highest performance, strongly typed contracts, all four streaming patterns
- **Use JSON-RPC 2.0 for tooling protocols** -- when you need structured RPC over simple transports (WebSocket, stdio)
- **Use strongly-typed hubs** -- `Hub<T>` catches method name typos at compile time instead of runtime
- **Scale SignalR with a backplane** -- Redis or Azure SignalR Service for multi-server deployments

See [skill:dotnet-tooling] for AOT compilation pipeline and [skill:dotnet-tooling] for AOT-compatible real-time communication patterns.

---

## Agent Gotchas

1. **Do not use SignalR when SSE suffices** -- if you only need server-to-client push without bidirectional communication, SSE is simpler and lighter.
2. **Do not forget `AddMessagePackProtocol()` on the server when the client uses MessagePack** -- mismatched protocols cause silent connection failures.
3. **Do not use Long Polling transport with SignalR unless required** -- it has significantly higher latency and server resource usage compared to WebSockets.
4. **Do not store connection IDs long-term** -- SignalR connection IDs change on reconnection. Use user identifiers or groups for addressing.
5. **Do not use gRPC streaming to browsers directly** -- browsers do not support HTTP/2 trailers natively. Use gRPC-Web with a proxy or choose SignalR/SSE instead.
6. **Do not confuse SSE with WebSocket** -- SSE is unidirectional (server-to-client only). If you need client-to-server messages, use SignalR or WebSocket directly.
7. **Do not forget `OnMessageReceived` for JWT with SignalR** -- WebSocket connections cannot send custom HTTP headers after the initial handshake. The access token must be read from the query string in `JwtBearerEvents.OnMessageReceived`.
8. **Do not assume group membership persists across reconnections** -- groups are tied to connection IDs, which change on reconnect. Re-add connections to groups in `OnConnectedAsync`.
9. **Do not deploy multi-server SignalR without a backplane** -- without Redis or Azure SignalR Service, messages sent on one server instance are invisible to connections on other instances.

---

## Attribution

Adapted from [Aaronontheweb/dotnet-skills](https://github.com/Aaronontheweb/dotnet-skills) (MIT license).

---

## References

- [SignalR overview](https://learn.microsoft.com/en-us/aspnet/core/signalr/introduction?view=aspnetcore-10.0)
- [SignalR hubs](https://learn.microsoft.com/en-us/aspnet/core/signalr/hubs?view=aspnetcore-10.0)
- [Server-Sent Events in .NET 10](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/server-sent-events?view=aspnetcore-10.0)
- [StreamJsonRpc](https://github.com/microsoft/vs-streamjsonrpc)
- [gRPC streaming](https://learn.microsoft.com/en-us/aspnet/core/grpc/client?view=aspnetcore-10.0)
- [SignalR scaling with Redis](https://learn.microsoft.com/en-us/aspnet/core/signalr/redis-backplane?view=aspnetcore-10.0)
- [SignalR authentication and authorization](https://learn.microsoft.com/en-us/aspnet/core/signalr/authn-and-authz?view=aspnetcore-10.0)
- [Azure SignalR Service](https://learn.microsoft.com/en-us/azure/azure-signalr/signalr-overview)
