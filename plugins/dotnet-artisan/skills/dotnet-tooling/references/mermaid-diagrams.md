# Mermaid Diagrams

Mermaid diagram reference for .NET projects: architecture diagrams (C4-style context, container, component views, layered architecture, microservice topology), sequence diagrams (API request flows, async/await patterns, middleware pipeline, authentication flows), class diagrams (domain models, DI registration graphs, inheritance hierarchies, interface implementations), deployment diagrams (container deployment, Kubernetes pod layout, CI/CD pipeline flow), ER diagrams (EF Core model relationships, database schema visualization), state diagrams (workflow states, order processing, saga patterns, state machine patterns), and flowcharts (decision trees, framework selection, architecture choices). Includes diagram-as-code conventions for naming, grouping, GitHub rendering, and dark mode considerations.

**Version assumptions:** Mermaid v10+ (supported by GitHub, Starlight, Docusaurus natively). GitHub renders Mermaid in Markdown files, issues, PRs, and discussions. .NET 8.0+ baseline for code examples.

For complete diagram examples, see the Detailed Examples section below.

## Supported Diagram Types

### Architecture Diagrams

- **C4-Style Context** -- system in its environment with external actors (10-12 nodes max)
- **C4-Style Component** -- internal structure of a single service (15-20 nodes max)
- **Layered Architecture** -- Presentation, Application, Domain, Infrastructure layers
- **Microservice Topology** -- services, messaging, observability connections

### Sequence Diagrams

- **API Request Flow** -- HTTP request through middleware, auth, controller, service, database
- **Async/Await Pattern** -- thread pool behavior, cache miss/hit, await points
- **Middleware Pipeline** -- request/response flow through ASP.NET Core middleware chain
- **Authentication Flow** -- OAuth 2.0/OIDC with BFF pattern

### Class Diagrams

- **Domain Model** -- entities, value objects, enumerations, relationships
- **DI Registration Graph** -- singleton/scoped/transient lifetime visualization
- **Interface Implementation Hierarchy** -- generic repository pattern with inheritance

### Deployment Diagrams

- **Container Deployment** -- Docker host with app, database, cache, reverse proxy
- **Kubernetes Pod Layout** -- cluster, namespace, deployments, services, config
- **CI/CD Pipeline Flow** -- build, test, package, deploy stages

### ER Diagrams

- **EF Core Relationship Visualization** -- one-to-many, one-to-one, many-to-many with entity details
- **Database Schema with Indexes** -- audit logs, soft delete, multi-tenant patterns

### State Diagrams

- **Order Processing Workflow** -- draft through delivery with payment states
- **Saga Pattern** -- distributed transaction with compensation steps
- **State Machine Pattern** -- event-driven state transitions

### Flowcharts

- **Framework Selection Decision Tree** -- web vs desktop, API vs UI, framework choices
- **Architecture Decision Flowchart** -- monolith vs microservices, communication patterns


## Diagram-as-Code Conventions

### Naming Conventions

- Use PascalCase for node IDs: `OrderService`, `CustomerDB`
- Use descriptive labels with technology: `API["Order API<br/>(ASP.NET Core)"]`
- Use consistent abbreviations: DB (database), API (endpoint), SVC (service), MQ (message queue)
- Prefix subgraphs with the layer or tier name: `subgraph DataTier["Data Tier"]`

### Grouping Patterns

- Group by architectural layer (Presentation, Application, Domain, Infrastructure)
- Group by deployment boundary (containers, pods, VMs)
- Group by team ownership in microservice diagrams
- Use subgraphs for visual grouping -- limit nesting to 2 levels for readability

### GitHub Rendering Tips

- GitHub renders Mermaid in fenced code blocks with the `mermaid` language identifier in Markdown files, issues, PRs, and discussions
- Maximum recommended diagram size: ~50 nodes for readable rendering
- GitHub uses a light theme by default -- avoid light-colored fill that disappears on white backgrounds
- Diagrams auto-size to container width -- keep node labels concise (under 30 characters per line)
- Use `<br/>` for line breaks within node labels (not `\n`)
- Test diagrams in GitHub before merging -- syntax errors render as raw text

### Dark Mode Considerations

- Use the `neutral` theme (`%%{init: {'theme': 'neutral'}}%%`) for best cross-theme compatibility on GitHub -- it renders well in both light and dark modes
- Avoid hardcoded colors that fail in dark mode -- use Mermaid theme variables when possible
- Default Mermaid colors work in both light and dark themes on GitHub
- If using custom `style` directives, test in both GitHub light and dark modes
- Prefer semantic `classDef` styles over inline `style` for maintainability
- For doc sites (Starlight, Docusaurus), Mermaid inherits the platform's CSS theme automatically

### Diagram Size Guidelines

| Diagram Type | Recommended Max Nodes | Notes |
|---|---|---|
| C4 Context | 10-12 | One system + external actors |
| C4 Component | 15-20 | Single service internals |
| Sequence | 8 participants | More becomes unreadable |
| Class | 10-15 classes | Split into multiple diagrams |
| ER | 10-12 entities | Split by bounded context |
| State | 12-15 states | Split complex workflows |
| Flowchart | 15-20 nodes | Keep decision trees focused |


## Agent Gotchas

1. **Always use `.NET-specific content` in diagrams** -- do not generate generic diagrams. Use real .NET types (DbContext, IRepository, IMessageBus), real .NET tools (EF Core, Wolverine, YARP), and real .NET patterns (middleware pipeline, DI registration).

2. **ER diagram relationship notation follows Mermaid syntax, not UML** -- use `||--o{` for one-to-many, `||--||` for one-to-one.

3. **Sequence diagram participant names cannot contain special characters** -- use `participant DB as "SQL Server"` alias syntax for names with spaces or special characters.

4. **Nested generics (`Task~List~T~~`) require Mermaid v10.3+** -- test rendering before committing complex generic type diagrams.

5. **Do not use Font Awesome icon syntax (`fa:fa-user`) in GitHub diagrams** -- GitHub's Mermaid renderer does not load Font Awesome. Icons render as literal text.

---

# Mermaid Diagrams -- Diagram Examples

Complete Mermaid diagram examples for .NET projects. Each section provides ready-to-use diagram templates with .NET-specific content.

---

## Architecture Diagrams

### C4-Style Context Diagram

Shows the system in its environment with external actors and systems.

```mermaid
graph TB
    User["End User<br/>(Browser/Mobile)"]
    Admin["Admin<br/>(Internal)"]

    subgraph System["My .NET Application"]
        API["ASP.NET Core API<br/>(.NET 8)"]
    end

    ExtAuth["Identity Provider<br/>(Azure AD / Auth0)"]
    ExtEmail["Email Service<br/>(SendGrid)"]
    ExtPay["Payment Gateway<br/>(Stripe)"]

    User -->|"HTTPS"| API
    Admin -->|"HTTPS"| API
    API -->|"OAuth 2.0"| ExtAuth
    API -->|"SMTP/API"| ExtEmail
    API -->|"REST API"| ExtPay
```

### C4-Style Component Diagram

Shows internal structure of a single service.

```mermaid
graph TB
    subgraph OrderService["Order Service"]
        Controllers["Controllers<br/>(API Endpoints)"]
        Validators["FluentValidation<br/>(Request Validators)"]
        Handlers["Command Handlers<br/>(Business Logic)"]
        DomainModels["Domain Models<br/>(Entities, Value Objects)"]
        Repos["Repositories<br/>(EF Core)"]
        Events["Domain Events<br/>(Notifications)"]
        IntEvents["Integration Events<br/>(Wolverine)"]
    end

    Controllers --> Validators
    Controllers --> Handlers
    Handlers --> DomainModels
    Handlers --> Repos
    Handlers --> Events
    Events --> IntEvents
```

### Layered Architecture

```mermaid
graph TB
    subgraph Presentation["Presentation Layer"]
        API["ASP.NET Core Controllers / Minimal APIs"]
        Blazor["Blazor Components"]
    end

    subgraph Application["Application Layer"]
        Services["Application Services"]
        DTOs["DTOs / View Models"]
        Mappings["Mapperly Mappers"]
        CQRS["Mediator Handlers"]
    end

    subgraph Domain["Domain Layer"]
        Entities["Entities"]
        ValueObjects["Value Objects"]
        DomainEvents["Domain Events"]
        Interfaces["Repository Interfaces"]
    end

    subgraph Infrastructure["Infrastructure Layer"]
        EFCore["EF Core DbContext"]
        Repositories["Repository Implementations"]
        ExternalServices["External Service Clients"]
        Messaging["Wolverine / RabbitMQ"]
    end

    Presentation --> Application
    Application --> Domain
    Infrastructure --> Domain
    Infrastructure -.->|"implements"| Interfaces
```

### Microservice Topology

```mermaid
graph LR
    subgraph Ingress
        LB["Load Balancer"]
        GW["API Gateway<br/>(YARP)"]
    end

    subgraph Services
        S1["Order Service"]
        S2["Catalog Service"]
        S3["Identity Service"]
        S4["Notification Service"]
    end

    subgraph Messaging
        MQ["RabbitMQ"]
    end

    subgraph Observability
        SEQ["Seq / ELK"]
        OTEL["OpenTelemetry Collector"]
    end

    LB --> GW
    GW --> S1
    GW --> S2
    GW --> S3
    S1 -->|"publish"| MQ
    MQ -->|"subscribe"| S2
    MQ -->|"subscribe"| S4
    S1 -.->|"traces"| OTEL
    S2 -.->|"traces"| OTEL
    S1 -.->|"logs"| SEQ
    S2 -.->|"logs"| SEQ
```

---

## Sequence Diagrams

### API Request Flow

```mermaid
sequenceDiagram
    participant Client
    participant Middleware as ASP.NET Middleware
    participant Auth as Authentication
    participant Controller
    participant Service
    participant DB as Database

    Client->>Middleware: POST /api/orders
    Middleware->>Auth: Validate JWT
    Auth-->>Middleware: Claims Principal
    Middleware->>Controller: OrdersController.Create()
    Controller->>Service: CreateOrderAsync(dto)
    Service->>DB: INSERT INTO Orders
    DB-->>Service: Order entity
    Service-->>Controller: OrderResponse
    Controller-->>Client: 201 Created
```

### Async/Await Pattern

```mermaid
sequenceDiagram
    participant Caller
    participant Service as OrderService
    participant Repo as IOrderRepository
    participant DB as SQL Server
    participant Cache as Redis

    Caller->>+Service: GetOrderAsync(id)
    Service->>+Cache: GetAsync(key)
    Cache-->>-Service: null (cache miss)
    Service->>+Repo: FindByIdAsync(id)
    Repo->>+DB: SELECT ... WHERE Id = @id
    Note over Repo,DB: await - thread returned to pool
    DB-->>-Repo: Row data
    Repo-->>-Service: Order entity
    Service->>+Cache: SetAsync(key, order, expiry)
    Note over Service,Cache: Fire-and-forget or await
    Cache-->>-Service: OK
    Service-->>-Caller: Order
```

### Middleware Pipeline

```mermaid
sequenceDiagram
    participant Client
    participant ExHandler as ExceptionHandler
    participant HSTS as HSTS Middleware
    participant Auth as Authentication
    participant Authz as Authorization
    participant CORS as CORS Middleware
    participant Routing as Routing
    participant Endpoint

    Client->>ExHandler: HTTP Request
    ExHandler->>HSTS: next()
    HSTS->>Auth: next()
    Auth->>Authz: next()
    Authz->>CORS: next()
    CORS->>Routing: next()
    Routing->>Endpoint: Matched endpoint
    Endpoint-->>Routing: Response
    Routing-->>CORS: Response
    CORS-->>Authz: Response
    Authz-->>Auth: Response
    Auth-->>HSTS: Response
    HSTS-->>ExHandler: Response
    ExHandler-->>Client: HTTP Response
```

### Authentication Flow (OAuth 2.0 / OIDC)

```mermaid
sequenceDiagram
    participant User
    participant App as Blazor App
    participant BFF as BFF (ASP.NET Core)
    participant IDP as Identity Provider
    participant API as Protected API

    User->>App: Navigate to protected page
    App->>BFF: GET /api/user (no cookie)
    BFF-->>App: 401 Unauthorized
    App->>BFF: GET /login
    BFF->>IDP: Authorization Code + PKCE
    IDP->>User: Login page
    User->>IDP: Credentials
    IDP->>BFF: Authorization code
    BFF->>IDP: Exchange code for tokens
    IDP-->>BFF: Access + Refresh + ID tokens
    BFF-->>App: Set-Cookie (session)
    App->>BFF: GET /api/orders (with cookie)
    BFF->>API: GET /api/orders (Bearer token)
    API-->>BFF: Order data
    BFF-->>App: Order data
```

---

## Class Diagrams

### Domain Model

```mermaid
classDiagram
    class Order {
        +Guid Id
        +DateTime CreatedAt
        +OrderStatus Status
        +decimal TotalAmount
        +List~OrderLine~ Lines
        +AddLine(product, quantity)
        +Submit()
        +Cancel(reason)
    }

    class OrderLine {
        +Guid Id
        +Guid ProductId
        +string ProductName
        +int Quantity
        +decimal UnitPrice
        +decimal LineTotal
    }

    class OrderStatus {
        <<enumeration>>
        Draft
        Submitted
        Processing
        Shipped
        Delivered
        Cancelled
    }

    class Customer {
        +Guid Id
        +string Name
        +string Email
        +Address ShippingAddress
        +List~Order~ Orders
    }

    class Address {
        <<value object>>
        +string Street
        +string City
        +string State
        +string PostalCode
        +string Country
    }

    Order "1" --> "*" OrderLine : contains
    Order --> OrderStatus : has
    Customer "1" --> "*" Order : places
    Customer --> Address : has
```

### DI Registration Graph

```mermaid
graph TB
    subgraph Singleton
        S1["IConfiguration"]
        S2["IMemoryCache"]
        S3["IHttpClientFactory"]
    end

    subgraph Scoped["Scoped (per-request)"]
        SC1["DbContext"]
        SC2["IOrderRepository"]
        SC3["ICurrentUser"]
    end

    subgraph Transient
        T1["IValidator~CreateOrderCommand~"]
        T2["INotificationSender"]
    end

    SC2 -->|"depends on"| SC1
    SC2 -->|"depends on"| S2
    T2 -->|"depends on"| S3
    SC3 -->|"depends on"| S1

    style Singleton fill:#e1f5fe
    style Scoped fill:#f3e5f5
    style Transient fill:#fff3e0
```

### Interface Implementation Hierarchy

```mermaid
classDiagram
    class IRepository~T~ {
        <<interface>>
        +GetByIdAsync(id) Task~T~
        +ListAsync() Task~List~T~~
        +AddAsync(entity) Task
        +UpdateAsync(entity) Task
        +DeleteAsync(id) Task
    }

    class IOrderRepository {
        <<interface>>
        +GetByCustomerAsync(customerId) Task~List~Order~~
        +GetPendingAsync() Task~List~Order~~
    }

    class RepositoryBase~T~ {
        <<abstract>>
        #DbContext _context
        +GetByIdAsync(id) Task~T~
        +ListAsync() Task~List~T~~
        +AddAsync(entity) Task
        +UpdateAsync(entity) Task
        +DeleteAsync(id) Task
    }

    class OrderRepository {
        +GetByCustomerAsync(customerId) Task~List~Order~~
        +GetPendingAsync() Task~List~Order~~
    }

    IRepository~T~ <|.. RepositoryBase~T~ : implements
    IOrderRepository <|.. OrderRepository : implements
    RepositoryBase~T~ <|-- OrderRepository : extends
    IRepository~T~ <|-- IOrderRepository : extends
```

---

## Deployment Diagrams

### Container Deployment

```mermaid
graph TB
    subgraph Host["Docker Host / VM"]
        subgraph AppContainer["App Container"]
            App["ASP.NET Core App<br/>mcr.microsoft.com/dotnet/aspnet:8.0"]
        end

        subgraph DBContainer["Database Container"]
            DB["SQL Server<br/>mcr.microsoft.com/mssql/server:2022"]
        end

        subgraph CacheContainer["Cache Container"]
            Redis["Redis<br/>redis:7-alpine"]
        end

        subgraph ReverseProxy["Reverse Proxy"]
            Nginx["Nginx<br/>(SSL termination)"]
        end
    end

    Internet["Internet"] -->|"443"| Nginx
    Nginx -->|"8080"| App
    App -->|"1433"| DB
    App -->|"6379"| Redis
```

### Kubernetes Pod Layout

```mermaid
graph TB
    subgraph Cluster["Kubernetes Cluster"]
        subgraph NS["namespace: myapp"]
            subgraph Deploy1["Deployment: order-api"]
                Pod1A["Pod<br/>order-api<br/>(replica 1)"]
                Pod1B["Pod<br/>order-api<br/>(replica 2)"]
            end

            subgraph Deploy2["Deployment: catalog-api"]
                Pod2A["Pod<br/>catalog-api<br/>(replica 1)"]
            end

            SVC1["Service: order-api-svc<br/>ClusterIP:80"]
            SVC2["Service: catalog-api-svc<br/>ClusterIP:80"]
            Ingress["Ingress Controller<br/>(nginx)"]
            CM["ConfigMap:<br/>appsettings"]
            Secret["Secret:<br/>connection-strings"]
        end
    end

    Internet["Internet"] --> Ingress
    Ingress -->|"/api/orders"| SVC1
    Ingress -->|"/api/catalog"| SVC2
    SVC1 --> Pod1A
    SVC1 --> Pod1B
    SVC2 --> Pod2A
    CM -.->|"mount"| Pod1A
    CM -.->|"mount"| Pod2A
    Secret -.->|"mount"| Pod1A
    Secret -.->|"mount"| Pod2A
```

### CI/CD Pipeline Flow

```mermaid
graph LR
    subgraph Trigger
        Push["Push to main"]
        PR["Pull Request"]
        Tag["Version Tag"]
    end

    subgraph Build["Build Stage"]
        Restore["dotnet restore"]
        Compile["dotnet build"]
        Test["dotnet test"]
    end

    subgraph Package["Package Stage"]
        Pack["dotnet pack"]
        Publish["dotnet publish"]
        Docker["docker build"]
    end

    subgraph Deploy["Deploy Stage"]
        NuGet["Push to NuGet"]
        ACR["Push to ACR"]
        Staging["Deploy to Staging"]
        Prod["Deploy to Production"]
    end

    Push --> Restore
    PR --> Restore
    Tag --> Restore
    Restore --> Compile --> Test
    Test --> Pack
    Test --> Publish --> Docker
    Pack -->|"tag only"| NuGet
    Docker --> ACR
    ACR --> Staging
    Staging -->|"approval"| Prod
```

---

## ER Diagrams (EF Core Models)

### EF Core Relationship Visualization

```mermaid
erDiagram
    Customer ||--o{ Order : places
    Order ||--|{ OrderLine : contains
    OrderLine }o--|| Product : references
    Product }o--|| Category : "belongs to"
    Order ||--o| ShippingAddress : "ships to"
    Customer ||--o| CustomerProfile : has

    Customer {
        guid Id PK
        string Name
        string Email UK
        datetime CreatedAt
    }

    Order {
        guid Id PK
        guid CustomerId FK
        datetime OrderDate
        string Status
        decimal TotalAmount
    }

    OrderLine {
        guid Id PK
        guid OrderId FK
        guid ProductId FK
        int Quantity
        decimal UnitPrice
    }

    Product {
        guid Id PK
        guid CategoryId FK
        string Name
        string SKU UK
        decimal Price
        int StockQuantity
    }

    Category {
        guid Id PK
        string Name UK
        string Description
        guid ParentCategoryId FK "nullable, self-ref"
    }

    ShippingAddress {
        guid Id PK
        guid OrderId FK "unique"
        string Street
        string City
        string PostalCode
        string Country
    }

    CustomerProfile {
        guid Id PK
        guid CustomerId FK "unique"
        string AvatarUrl
        string Bio
    }
```

### Database Schema with Indexes

```mermaid
erDiagram
    AuditLog {
        long Id PK "identity"
        string EntityType "indexed"
        guid EntityId "indexed"
        string Action
        string UserId FK "indexed"
        jsonb Changes
        datetime Timestamp "indexed, default GETUTCDATE()"
    }

    SoftDeleteEntity {
        guid Id PK
        string Name
        bool IsDeleted "global query filter"
        datetime DeletedAt "nullable"
        string DeletedBy "nullable"
    }

    TenantEntity {
        guid Id PK
        guid TenantId FK "global query filter, indexed"
        string Data
    }
```

---

## State Diagrams

### Order Processing Workflow

```mermaid
stateDiagram-v2
    [*] --> Draft : Create order

    Draft --> Submitted : Submit()
    Draft --> Cancelled : Cancel()

    Submitted --> PaymentPending : Process payment
    Submitted --> Cancelled : Cancel()

    PaymentPending --> PaymentFailed : Payment declined
    PaymentPending --> Paid : Payment confirmed

    PaymentFailed --> PaymentPending : Retry payment
    PaymentFailed --> Cancelled : Cancel()

    Paid --> Processing : Begin fulfillment
    Processing --> Shipped : Ship order
    Shipped --> Delivered : Confirm delivery

    Delivered --> [*]
    Cancelled --> [*]

    note right of PaymentPending
        Timeout after 30 minutes
        auto-transitions to PaymentFailed
    end note
```

### Saga Pattern (Distributed Transaction)

```mermaid
stateDiagram-v2
    [*] --> OrderCreated : Start saga

    OrderCreated --> InventoryReserved : ReserveInventory
    OrderCreated --> OrderFailed : ReserveInventory failed

    InventoryReserved --> PaymentProcessed : ProcessPayment
    InventoryReserved --> InventoryReleased : ProcessPayment failed

    InventoryReleased --> OrderFailed : Compensate

    PaymentProcessed --> ShipmentScheduled : ScheduleShipment
    PaymentProcessed --> PaymentRefunded : ScheduleShipment failed

    PaymentRefunded --> InventoryReleased : Compensate

    ShipmentScheduled --> OrderCompleted : All steps succeeded
    OrderCompleted --> [*]
    OrderFailed --> [*]

    note left of InventoryReleased
        Compensation step:
        release reserved stock
    end note

    note left of PaymentRefunded
        Compensation step:
        refund payment
    end note
```

### State Machine Pattern (Event-Driven)

```mermaid
stateDiagram-v2
    [*] --> New

    state "Awaiting Validation" as Validating
    state "Awaiting Payment" as AwaitingPayment
    state "Payment Failed" as PaymentFailed

    New --> Validating : OrderSubmitted event
    Validating --> AwaitingPayment : OrderValidated event
    Validating --> Cancelled : ValidationFailed event

    AwaitingPayment --> Confirmed : PaymentReceived event
    AwaitingPayment --> PaymentFailed : PaymentDeclined event

    PaymentFailed --> AwaitingPayment : PaymentRetried event
    PaymentFailed --> Cancelled : MaxRetriesExceeded

    Confirmed --> Shipped : OrderShipped event
    Shipped --> Completed : OrderDelivered event

    Completed --> [*]
    Cancelled --> [*]
```

---

## Flowcharts

### Framework Selection Decision Tree

```mermaid
flowchart TD
    Start["New .NET Project"] --> WebOrDesktop{"Web or Desktop?"}

    WebOrDesktop -->|"Web"| APIOnly{"API only?"}
    WebOrDesktop -->|"Desktop"| DesktopPlatform{"Target platforms?"}

    APIOnly -->|"Yes"| MinimalOrMVC{"Preference?"}
    APIOnly -->|"No, needs UI"| UIFramework{"Server or Client rendering?"}

    MinimalOrMVC -->|"Simple, few endpoints"| MinimalAPI["Minimal APIs"]
    MinimalOrMVC -->|"Complex, many controllers"| MVC["ASP.NET Core MVC/API"]

    UIFramework -->|"Server"| BlazorServer["Blazor Server / SSR"]
    UIFramework -->|"Client"| BlazorWASM["Blazor WebAssembly"]
    UIFramework -->|"Both"| BlazorAuto["Blazor Auto (SSR + WASM)"]

    DesktopPlatform -->|"Windows only"| WPFOrWinUI{"Modern UI needed?"}
    DesktopPlatform -->|"Cross-platform"| MAUI["MAUI"]

    WPFOrWinUI -->|"Legacy compat"| WPF["WPF"]
    WPFOrWinUI -->|"Modern"| WinUI["WinUI 3"]
```

### Architecture Decision Flowchart

```mermaid
flowchart TD
    Start["Service Design Decision"] --> Scale{"Expected scale?"}

    Scale -->|"Single team, moderate load"| Monolith["Modular Monolith"]
    Scale -->|"Multiple teams, high load"| Micro["Microservices"]

    Monolith --> MonoComm{"Communication pattern?"}
    MonoComm -->|"In-process"| Mediator["Mediator + Vertical Slices"]
    MonoComm -->|"Async events"| MonoBus["Wolverine (in-memory)"]

    Micro --> MicroComm{"Communication pattern?"}
    MicroComm -->|"Synchronous"| gRPC["gRPC / REST"]
    MicroComm -->|"Asynchronous"| MsgBus["Message Bus<br/>(RabbitMQ / Azure SB)"]
    MicroComm -->|"Both"| Hybrid["gRPC + Message Bus"]

    Micro --> DataStrategy{"Data strategy?"}
    DataStrategy -->|"Shared DB"| SharedDB["Shared Database<br/>(simpler, less isolation)"]
    DataStrategy -->|"DB per service"| OwnDB["Database per Service<br/>(more isolation, eventual consistency)"]
```

