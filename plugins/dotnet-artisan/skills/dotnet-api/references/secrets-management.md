# Secrets Management

Cloud-agnostic secrets management for .NET applications. Covers the full lifecycle: user secrets for local development, environment variables for production, IConfiguration binding patterns, secret rotation, and managed identity as a production best practice. Includes anti-patterns to avoid (secrets in source, appsettings.json, hardcoded connection strings).

## Secrets Lifecycle

| Environment | Secret Source | Mechanism |
|-------------|-------------|-----------|
| Local dev | User secrets | `dotnet user-secrets` CLI, `secrets.json` outside repo |
| CI/CD | Pipeline variables | Injected as environment variables, never in YAML |
| Staging/Production | Environment variables or vault | OS-level env vars, managed identity, or vault provider |

**Principle:** Secrets must never exist in the source repository or in any file committed to version control. Each environment tier uses the appropriate mechanism for its trust boundary.

---

## User Secrets (Local Development)

User secrets store sensitive configuration outside the project directory in the user profile, preventing accidental commits.

### Setup

```bash
# Initialize user secrets for a project (creates UserSecretsId in csproj)
dotnet user-secrets init

# Set individual secrets
dotnet user-secrets set "ConnectionStrings:DefaultDb" "Server=localhost;Database=myapp;User=sa;Password=dev123"
dotnet user-secrets set "Smtp:ApiKey" "SG.dev-key-here"
dotnet user-secrets set "Jwt:SigningKey" "dev-signing-key-min-32-chars-long!!"

# List current secrets
dotnet user-secrets list

# Remove a secret
dotnet user-secrets remove "Smtp:ApiKey"

# Clear all secrets
dotnet user-secrets clear
```

### How It Works

User secrets are stored at:
- **Windows:** `%APPDATA%\Microsoft\UserSecrets\<UserSecretsId>\secrets.json`
- **macOS/Linux:** `~/.microsoft/usersecrets/<UserSecretsId>/secrets.json`

The `secrets.json` file is plain JSON with the same structure as `appsettings.json`:

```json
{
  "ConnectionStrings": {
    "DefaultDb": "Server=localhost;Database=myapp;User=sa;Password=dev123"
  },
  "Smtp": {
    "ApiKey": "SG.dev-key-here"
  },
  "Jwt": {
    "SigningKey": "dev-signing-key-min-32-chars-long!!"
  }
}
```

### Loading in Code

User secrets are loaded automatically by `WebApplication.CreateBuilder` and `Host.CreateDefaultBuilder` when `DOTNET_ENVIRONMENT` or `ASPNETCORE_ENVIRONMENT` is `Development`:

```csharp
var builder = WebApplication.CreateBuilder(args);

// User secrets are already loaded. Access them via IConfiguration:
var connectionString = builder.Configuration.GetConnectionString("DefaultDb");
```

For non-web hosts (console apps, worker services):

```csharp
var builder = Host.CreateApplicationBuilder(args);
// User secrets are loaded automatically in Development environment.
// For explicit control:
if (builder.Environment.IsDevelopment())
{
    builder.Configuration.AddUserSecrets<Program>();
}
```

**Gotcha:** User secrets are not encrypted -- they are just stored outside the repo. They are appropriate for development only, never for production.

---

## Environment Variables (Production)

Environment variables are the standard mechanism for injecting secrets into production applications without touching the filesystem.

### Configuration Precedence

In the default ASP.NET Core configuration stack, environment variables override file-based sources (last wins):

1. `appsettings.json`
2. `appsettings.{Environment}.json`
3. User secrets (Development only)
4. **Environment variables** (overrides all above)
5. Command-line arguments

### Mapping Convention

.NET maps environment variables to configuration keys using `__` (double underscore) as the section separator:

```bash
# These environment variables map to configuration sections:
export ConnectionStrings__DefaultDb="Server=prod-db;Database=myapp;..."
export Smtp__ApiKey="SG.REPLACE_VIA_SECRETS_MANAGER"
export Jwt__SigningKey="REPLACE_VIA_SECRETS_MANAGER_MIN_32_CHARS"

# With a prefix (recommended to avoid collisions):
export MYAPP_ConnectionStrings__DefaultDb="Server=prod-db;..."
```

```csharp
// Load prefixed environment variables
builder.Configuration.AddEnvironmentVariables(prefix: "MYAPP_");

// Access the same way as any configuration source:
var smtpKey = builder.Configuration["Smtp:ApiKey"];
```

### Container Environments

```yaml
# docker-compose.yml -- inject secrets via environment
services:
  api:
    image: myapp:latest
    environment:
      - ConnectionStrings__DefaultDb=Server=db;Database=myapp;User=sa;Password=${DB_PASSWORD}
      - Smtp__ApiKey=${SMTP_API_KEY}
    env_file:
      - .env  # NOT committed to source control
```

```dockerfile
# Dockerfile -- do NOT bake secrets into images
# Use environment variables at runtime instead
ENV ASPNETCORE_URLS=http://+:8080
# NEVER: ENV ConnectionStrings__DefaultDb="Server=..."
```

**Gotcha:** Environment variables are visible to all processes under the same user. In multi-tenant container environments, use container-level isolation (Kubernetes secrets, Docker secrets) rather than host-level env vars.

---

## IConfiguration Binding Patterns

Bind secrets to strongly typed options classes for compile-time safety and validation.

```csharp
public sealed class JwtOptions
{
    public const string SectionName = "Jwt";

    [Required, MinLength(32)]
    public string SigningKey { get; set; } = "";

    /// <summary>
    /// Previous signing key retained during rotation window.
    /// Set this when rotating keys so tokens signed with the old key
    /// remain valid until they expire. Remove after rotation completes.
    /// </summary>
    public string? PreviousSigningKey { get; set; }

    [Required]
    public string Issuer { get; set; } = "";

    [Required]
    public string Audience { get; set; } = "";

    [Range(1, 1440)]
    public int ExpirationMinutes { get; set; } = 60;
}

// Registration with validation
builder.Services
    .AddOptions<JwtOptions>()
    .BindConfiguration(JwtOptions.SectionName)
    .ValidateDataAnnotations()
    .ValidateOnStart(); // Fail fast if secrets are missing
```

```csharp
// Inject and use
public sealed class TokenService(IOptions<JwtOptions> jwtOptions)
{
    private readonly JwtOptions _jwt = jwtOptions.Value;

    public string GenerateToken(string userId)
    {
        var key = new SymmetricSecurityKey(
            Encoding.UTF8.GetBytes(_jwt.SigningKey));
        var credentials = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);

        var token = new JwtSecurityToken(
            issuer: _jwt.Issuer,
            audience: _jwt.Audience,
            claims: [new Claim(ClaimTypes.NameIdentifier, userId)],
            expires: DateTime.UtcNow.AddMinutes(_jwt.ExpirationMinutes),
            signingCredentials: credentials);

        return new JwtSecurityTokenHandler().WriteToken(token);
    }
}
```

> Options classes must use `{ get; set; }` (not `{ get; init; }`) because the configuration binder and `PostConfigure` need to mutate properties after construction. Use data annotation attributes (`[Required]`, `[MinLength]`) for validation.

**Gotcha:** `ValidateOnStart()` catches missing secrets at application startup rather than at first use. Always use it for secrets-bearing options to fail fast with a clear error message.

---

## Secret Rotation

Design applications to handle secret rotation without downtime.

### Rotation-Friendly Patterns

```csharp
// Use IOptionsMonitor<T> for secrets that may change at runtime
public sealed class EmailService(IOptionsMonitor<SmtpOptions> smtpOptions, ILogger<EmailService> logger)
{
    public async Task SendAsync(string to, string subject, string body)
    {
        // CurrentValue reads the latest configuration on every call
        var options = smtpOptions.CurrentValue;
        logger.LogDebug("Using SMTP host {Host}", options.Host);

        // ... send email using current options ...
    }
}

// Audit-log configuration changes via a hosted service.
// IHostedService is always activated by the host, so the subscription is guaranteed.
public sealed class SmtpOptionsChangeLogger(
    IOptionsMonitor<SmtpOptions> monitor,
    ILogger<SmtpOptionsChangeLogger> logger) : IHostedService, IDisposable
{
    private IDisposable? _subscription;

    public Task StartAsync(CancellationToken cancellationToken)
    {
        _subscription = monitor.OnChange(options =>
        {
            logger.LogInformation("SMTP configuration reloaded at {Time}", DateTime.UtcNow);
        });
        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken cancellationToken) => Task.CompletedTask;

    public void Dispose() => _subscription?.Dispose();
}

// Registration:
builder.Services.AddHostedService<SmtpOptionsChangeLogger>();
```

```csharp
// Dual-key validation for zero-downtime rotation
// Accept both old and new signing keys during rotation window
public sealed class DualKeyTokenValidator(IOptionsMonitor<JwtOptions> optionsMonitor)
{
    public TokenValidationParameters GetParameters()
    {
        // Read CurrentValue on every call so rotated keys are picked up
        // without restarting the application
        var options = optionsMonitor.CurrentValue;

        var keys = new List<SecurityKey>
        {
            new SymmetricSecurityKey(Encoding.UTF8.GetBytes(options.SigningKey))
        };

        if (!string.IsNullOrEmpty(options.PreviousSigningKey))
        {
            keys.Add(new SymmetricSecurityKey(
                Encoding.UTF8.GetBytes(options.PreviousSigningKey)));
        }

        return new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidIssuer = options.Issuer,
            ValidateAudience = true,
            ValidAudience = options.Audience,
            ValidateLifetime = true,
            IssuerSigningKeys = keys
        };
    }
}
```

### Rotation Checklist

1. Deploy the new secret alongside the old one (dual-key window)
2. Update the application to accept both old and new secrets
3. Roll the deployment so all instances use the new secret for signing/encrypting
4. After all clients have rotated, remove the old secret
5. Audit-log every rotation event

---

## Managed Identity (Production Best Practice)

Managed identity eliminates secrets entirely for cloud-hosted applications by using the platform's identity system to authenticate to services.

**Concept:** Instead of storing a connection string with a password, the application authenticates to the database/service using its platform-assigned identity. No secret to manage, rotate, or leak.

```csharp
// Example: passwordless connection to SQL Server using DefaultAzureCredential
// This pattern works across Azure, and similar patterns exist for AWS and GCP
var connectionString = "Server=myserver.database.windows.net;Database=mydb;Authentication=Active Directory Default";
builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseSqlServer(connectionString));
// No password in the connection string -- identity is resolved from the environment
```

**When to use managed identity:**
- Production and staging environments hosted on cloud platforms
- Any service-to-service communication where the platform supports identity federation
- Database connections, message queue access, storage access

**When you still need secrets:**
- Third-party APIs that only support API keys
- Legacy systems without identity federation
- Local development (use user secrets as a fallback)

---

## Anti-Patterns

### Secrets in Source Control

```csharp
// NEVER: hardcoded secrets in source code
private const string ApiKey = "sk-live-abc123def456";           // WRONG
private const string ConnectionString = "Server=prod;Password=secret"; // WRONG
```

**Fix:** Use user secrets (dev) or environment variables (production). See sections above.

### Secrets in appsettings.json

```json
// NEVER: real credentials in appsettings.json (committed to repo)
{
  "ConnectionStrings": {
    "DefaultDb": "Server=prod-db;Password=RealPassword123!"
  }
}
```

**Fix:** `appsettings.json` should contain only non-sensitive defaults. Use placeholder values that fail visibly:

```json
{
  "ConnectionStrings": {
    "DefaultDb": "Server=localhost;Database=myapp;Integrated Security=true"
  },
  "Smtp": {
    "ApiKey": "REPLACE_VIA_ENV_OR_USER_SECRETS"
  }
}
```

### Hardcoded Connection Strings

```csharp
// NEVER: connection strings directly in code
var connection = new SqlConnection("Server=prod-db;Database=myapp;User=sa;Password=P@ssw0rd!");
```

**Fix:** Always resolve connection strings from `IConfiguration`:

```csharp
// Correct: resolve from configuration
public sealed class OrderRepository(IConfiguration configuration)
{
    private readonly string _connectionString =
        configuration.GetConnectionString("DefaultDb")
        ?? throw new InvalidOperationException("ConnectionStrings:DefaultDb is not configured");
}

// Better: use Options pattern with validation
public sealed class OrderRepository(IOptions<DatabaseOptions> options)
{
    private readonly string _connectionString = options.Value.ConnectionString;
}
```

### Logging Secrets

```csharp
// NEVER: log secret values
logger.LogInformation("Using API key: {ApiKey}", apiKey);       // WRONG
logger.LogDebug("Connection string: {Conn}", connectionString); // WRONG
```

**Fix:** Log that a secret was loaded, not its value:

```csharp
logger.LogInformation("API key configured: {IsConfigured}", !string.IsNullOrEmpty(apiKey));
logger.LogInformation("Database connection configured for {Server}", new SqlConnectionStringBuilder(connectionString).DataSource);
```

---

## Agent Gotchas

1. **Do not generate code with hardcoded secrets** -- always use `IConfiguration` or `IOptions<T>` to resolve secrets. Even in examples, use placeholder values.
2. **Do not put real secrets in `appsettings.json`** -- it is committed to source control. Use user secrets for development, environment variables for production.
3. **Do not use `{ get; init; }` on Options classes** -- the configuration binder requires mutable setters. Use `{ get; set; }` with data annotation validation instead.
4. **Do not skip `ValidateOnStart()`** -- without it, missing secrets cause runtime failures at first use rather than a clear startup error.
5. **Do not log secret values** -- log whether a secret is configured (`IsConfigured: true/false`) or metadata (server name from connection string), never the value.
6. **Do not use `IOptions<T>` for secrets that rotate** -- use `IOptionsMonitor<T>` for runtime-reloadable secrets so rotation does not require a restart.
7. **Do not bake secrets into Docker images** -- use environment variables or mounted secrets at container runtime.

---

## Prerequisites

- .NET 8.0+ (LTS baseline)
- `Microsoft.Extensions.Configuration.UserSecrets` (included in ASP.NET Core SDK; add manually for console apps)
- `Microsoft.Extensions.Options.DataAnnotations` for `ValidateDataAnnotations()`

---

## References

- [Safe Storage of App Secrets in Development](https://learn.microsoft.com/en-us/aspnet/core/security/app-secrets?view=aspnetcore-10.0)
- [Configuration in ASP.NET Core](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/configuration/?view=aspnetcore-10.0)
- [Options Pattern in ASP.NET Core](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/configuration/options?view=aspnetcore-10.0)
- [ASP.NET Core Security](https://learn.microsoft.com/en-us/aspnet/core/security/?view=aspnetcore-10.0)
- [Secure Coding Guidelines for .NET](https://learn.microsoft.com/en-us/dotnet/standard/security/secure-coding-guidelines)
- [Use Managed Identities](https://learn.microsoft.com/en-us/entra/identity/managed-identities-azure-resources/overview)
