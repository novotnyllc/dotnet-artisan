---
name: dotnet-api
description: Builds ASP.NET Core APIs, EF Core data access, gRPC, SignalR, and backend services with middleware, security (OAuth, JWT, OWASP), resilience, messaging, OpenAPI, .NET Aspire, Semantic Kernel, HybridCache, YARP reverse proxy, output caching, Office documents (Excel, Word, PowerPoint), PDF, and architecture patterns. Spans 32 topic areas. Do not use for UI rendering patterns or CI/CD pipeline authoring.
license: MIT
user-invocable: false
---

# dotnet-api

## Overview

ASP.NET Core APIs, data access, backend services, security, and cloud-native patterns. This consolidated skill spans 32 topic areas. Load the appropriate companion file from `references/` based on the routing table below.

Baseline dependency: `references/minimal-apis.md` defines the core ASP.NET Core Minimal API patterns (route groups, endpoint filters, TypedResults, parameter binding) that apply to most API development tasks. Load it by default when building HTTP endpoints.

Most-shared companion: `references/architecture-patterns.md` covers vertical slices, request pipelines, error handling, caching, and idempotency patterns used across nearly all ASP.NET Core projects.

## Routing Table

| Topic | Keywords | Description | Companion File |
|-------|----------|-------------|----------------|
| Minimal APIs | endpoint, route group, filter, TypedResults | Minimal API route groups, filters, TypedResults, OpenAPI | references/minimal-apis.md |
| Middleware | pipeline ordering, short-circuit, exception | Pipeline ordering, short-circuit, exception handling | references/middleware-patterns.md |
| EF Core patterns | DbContext, migrations, AsNoTracking | DbContext, AsNoTracking, query splitting, migrations | references/efcore-patterns.md |
| EF Core architecture | read/write split, aggregate boundaries, N+1 | Read/write split, aggregate boundaries, N+1 | references/efcore-architecture.md |
| Data access strategy | EF Core vs Dapper vs ADO.NET decision | EF Core vs Dapper vs ADO.NET decision matrix | references/data-access-strategy.md |
| gRPC | proto, code-gen, streaming, auth | Proto definition, code-gen, ASP.NET Core host, streaming | references/grpc.md |
| Real-time | SignalR, SSE, JSON-RPC, gRPC streaming | SignalR hubs, SSE, JSON-RPC 2.0, scaling | references/realtime-communication.md |
| Resilience | Polly v8, retry, circuit breaker, timeout | Polly v8 retry, circuit breaker, timeout, rate limiter | references/resilience.md |
| HTTP client | IHttpClientFactory, typed/named, DelegatingHandler | IHttpClientFactory, typed/named clients, DelegatingHandlers | references/http-client.md |
| API versioning | Asp.Versioning, URL/header/query, sunset | Asp.Versioning.Http/Mvc, URL/header/query, sunset | references/api-versioning.md |
| OpenAPI | MS.AspNetCore.OpenApi, Swashbuckle, NSwag | MS.AspNetCore.OpenApi, Swashbuckle migration, NSwag | references/openapi.md |
| API security | Identity, OAuth/OIDC, JWT, CORS, rate limiting | Identity, OAuth/OIDC, JWT bearer, CORS, rate limiting | references/api-security.md |
| OWASP | injection, auth, XSS, deprecated APIs | OWASP Top 10 hardening for .NET | references/security-owasp.md |
| Secrets | user secrets, env vars, rotation | User secrets, environment variables, rotation | references/secrets-management.md |
| Cryptography | AES-GCM, RSA, ECDSA, hashing, key derivation | AES-GCM, RSA, ECDSA, hashing, PQC key derivation | references/cryptography.md |
| Background services | BackgroundService, IHostedService, lifecycle | BackgroundService, IHostedService, lifecycle | references/background-services.md |
| Aspire | AppHost, service discovery, dashboard | AppHost, service discovery, components, dashboard | references/aspire-patterns.md |
| Semantic Kernel | AI/LLM plugins, prompts, memory, agents | AI/LLM plugins, prompt templates, memory, agents | references/semantic-kernel.md |
| Architecture | vertical slices, layered, pipelines, caching | Vertical slices, layered, pipelines, caching | references/architecture-patterns.md |
| Messaging | Wolverine, Azure Service Bus, RabbitMQ, pub/sub, sagas | Wolverine, Azure Service Bus, RabbitMQ, pub/sub, sagas | references/messaging-patterns.md |
| Service communication | REST vs gRPC vs SignalR decision matrix | REST vs gRPC vs SignalR decision matrix | references/service-communication.md |
| API surface validation | PublicApiAnalyzers, Verify, ApiCompat | PublicApiAnalyzers, Verify snapshots, ApiCompat | references/api-surface-validation.md |
| Library API compat | binary/source compat, type forwarders | Binary/source compat, type forwarders, SemVer | references/library-api-compat.md |
| I/O pipelines | PipeReader/PipeWriter, backpressure, Kestrel | PipeReader/PipeWriter, backpressure, Kestrel | references/io-pipelines.md |
| Agent gotchas | async misuse, NuGet errors, DI mistakes | Common agent mistakes in .NET code | references/agent-gotchas.md |
| File-based apps | .NET 10, directives, csproj migration | .NET 10 file-based C# apps | references/file-based-apps.md |
| API docs | DocFX, OpenAPI-as-docs, versioned docs | DocFX, OpenAPI-as-docs, versioned documentation | references/api-docs.md |
| HybridCache | HybridCache, L1/L2, stampede, tag eviction | HybridCache (.NET 9+), stampede protection, tag-based eviction | references/hybrid-cache.md |
| YARP | reverse proxy, load balancing, API gateway, BFF | YARP reverse proxy, load balancing, health checks, transforms | references/yarp.md |
| Output caching | OutputCache, response caching, compression | Output/response caching, compression, CDN, tag invalidation | references/output-caching.md |
| Identity | ASP.NET Core Identity, login, MFA, scaffolding | Identity setup, scaffolding, external providers, MapIdentityApi | references/identity-setup.md |
| Office documents and PDF | Excel, Word, PowerPoint, PDF, Open XML SDK, spreadsheet, docx, xlsx, PDFsharp, MigraDoc, merge PDF, split PDF, watermark | Open XML SDK, ClosedXML, PDFsharp/MigraDoc for PDF create/read/merge/split/watermark | references/office-documents.md |

## Scope

- ASP.NET Core web APIs (minimal and controller-based)
- Data access (EF Core, Dapper, ADO.NET)
- Service communication (gRPC, SignalR, SSE, messaging)
- Security (auth, OWASP, secrets, crypto)
- Cloud-native (Aspire, resilience, background services)
- AI integration (Semantic Kernel)
- Architecture patterns and API surface validation

## Out of scope

- C# language features -> [skill:dotnet-csharp]
- UI rendering -> [skill:dotnet-ui]
- Test authoring -> [skill:dotnet-testing]
- CI/CD pipelines -> [skill:dotnet-devops]
- Build tooling -> [skill:dotnet-tooling]
