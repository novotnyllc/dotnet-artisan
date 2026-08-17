# Configuration

Configuration patterns for .NET applications using Microsoft.Extensions.Configuration and Microsoft.Extensions.Options. Covers the Options pattern (`IOptions<T>`, `IOptionsMonitor<T>`, `IOptionsSnapshot<T>`), validation, user secrets, environment-based configuration, and feature flags with `Microsoft.FeatureManagement`.

Cross-references: `references/dependency-injection.md` for service registration patterns, `references/coding-standards.md` for naming conventions.

---

## Configuration Sources and Precedence

Default configuration sources in `WebApplication.CreateBuilder` (last wins):

1. `appsettings.json`
2. `appsettings.{Environment}.json`
3. User secrets (Development only)
4. Environment variables
5. Command-line arguments

```csharp
var builder = WebApplication.CreateBuilder(args);
// Sources above are loaded automatically. Add custom sources:
builder.Configuration.AddJsonFile("features.json", optional: true, reloadOnChange: true);
```

---

## Options Pattern

Bind configuration sections to strongly typed classes and inject them via DI.

### Defining Options Classes

```csharp
public sealed class SmtpOptions
{
    public const string SectionName = "Smtp";

    public string Host { get; set; } = "";
    public int Port { get; set; } = 587;
    public string FromAddress { get; set; } = "";
    public bool UseSsl { get; set; } = true;
}
```

> Options classes use `{ get; set; }` (not `init`) because the configuration binder and `PostConfigure` need to mutate properties. Use `[Required]` via data annotations for mandatory fields instead.

### Registration

```csharp
builder.Services
    .AddOptions<SmtpOptions>()
    .BindConfiguration(SmtpOptions.SectionName)
    .ValidateDataAnnotations()
    .ValidateOnStart();
```

### `appsettings.json`

```json
{
  "Smtp": {
    "Host": "smtp.example.com",
    "Port": 587,
    "FromAddress": "noreply@example.com",
    "UseSsl": true
  }
}
```

---

## Options Interfaces

| Interface | Lifetime | Reload Behavior | Use Case |
|-----------|----------|-----------------|----------|
| `IOptions<T>` | Singleton | Never reloads after startup | Static config, most services |
| `IOptionsSnapshot<T>` | Scoped | Reloads per request/scope | Per-request config in ASP.NET |
| `IOptionsMonitor<T>` | Singleton | Live reload + change notification | Singletons, background services |

### Injection Examples

```csharp
// Static -- most common, singleton-safe
public sealed class EmailService(IOptions<SmtpOptions> options)
{
    private readonly SmtpOptions _smtp = options.Value;

    public Task SendAsync(string to, string subject, string body,
        CancellationToken ct = default)
    {
        // Use _smtp.Host, _smtp.Port, etc.
        return Task.CompletedTask;
    }
}

// Live reload in singletons -- monitors config file changes
public sealed class FeatureService(IOptionsMonitor<FeatureOptions> monitor)
{
    public bool IsEnabled(string feature)
        => monitor.CurrentValue.EnabledFeatures.Contains(feature);
}

// Per-request in scoped services -- reads latest config each request
public sealed class PricingService(IOptionsSnapshot<PricingOptions> snapshot)
{
    public decimal GetMarkup() => snapshot.Value.MarkupPercent;
}
```

### Change Notifications with `IOptionsMonitor<T>`

```csharp
public sealed class CacheService : IDisposable
{
    private readonly IDisposable? _changeListener;
    private CacheOptions _current;

    public CacheService(IOptionsMonitor<CacheOptions> monitor)
    {
        _current = monitor.CurrentValue;
        _changeListener = monitor.OnChange(updated =>
        {
            _current = updated;
            // React to config change -- flush cache, resize pool, etc.
        });
    }

    public void Dispose() => _changeListener?.Dispose();
}
```

---

## Options Validation

### Data Annotations

```csharp
using System.ComponentModel.DataAnnotations;

public sealed class SmtpOptions
{
    public const string SectionName = "Smtp";

    [Required, MinLength(1)]
    public string Host { get; set; } = "";

    [Range(1, 65535)]
    public int Port { get; set; } = 587;

    [Required, EmailAddress]
    public string FromAddress { get; set; } = "";
}

builder.Services
    .AddOptions<SmtpOptions>()
    .BindConfiguration(SmtpOptions.SectionName)
    .ValidateDataAnnotations()
    .ValidateOnStart(); // Fail fast at startup, not on first use
```

### `IValidateOptions<T>` (Complex Validation)

Use when validation logic requires cross-property checks or external dependencies.

```csharp
public sealed class SmtpOptionsValidator : IValidateOptions<SmtpOptions>
{
    public ValidateOptionsResult Validate(string? name, SmtpOptions options)
    {
        var failures = new List<string>();

        if (options.UseSsl && options.Port == 25)
        {
            failures.Add("Port 25 does not support SSL. Use 465 or 587.");
        }

        if (string.IsNullOrWhiteSpace(options.Host))
        {
            failures.Add("SMTP host is required.");
        }

        return failures.Count > 0
            ? ValidateOptionsResult.Fail(failures)
            : ValidateOptionsResult.Success;
    }
}

// Register the validator
builder.Services.AddSingleton<IValidateOptions<SmtpOptions>, SmtpOptionsValidator>();
```

### `ValidateOnStart` (Fail Fast)

Always use `.ValidateOnStart()` to surface configuration errors at startup instead of at first resolution. Without it, invalid config only throws when `IOptions<T>.Value` is first accessed.

---

## User Secrets (Development)

Store sensitive values outside source control during development.

```bash
# Initialize (once per project)
dotnet user-secrets init

# Set values
dotnet user-secrets set "Smtp:Host" "smtp.example.com"
dotnet user-secrets set "ConnectionStrings:Default" "Server=..."

# List all secrets
dotnet user-secrets list

# Clear all
dotnet user-secrets clear
```

User secrets are stored in `~/.microsoft/usersecrets/<UserSecretsId>/secrets.json` and override `appsettings.json` values in Development.

**Key rules:**
- Never use user secrets in production -- use environment variables, Azure Key Vault, or other vault providers
- User secrets are loaded automatically when `ASPNETCORE_ENVIRONMENT=Development`
- For non-web hosts, explicitly add: `builder.Configuration.AddUserSecrets<Program>()`

---

## Environment-Based Configuration

### Environment Variables

```csharp
// Hierarchical keys use __ (double underscore) as separator
// Environment variable: Smtp__Host=smtp.prod.com
// Maps to: configuration["Smtp:Host"]
```

### Per-Environment Files

```
appsettings.json                 # Base (all environments)
appsettings.Development.json     # Overrides for dev
appsettings.Staging.json         # Overrides for staging
appsettings.Production.json      # Overrides for prod
```

```csharp
// Set environment via ASPNETCORE_ENVIRONMENT or DOTNET_ENVIRONMENT
// Defaults to "Production" if not set
var env = builder.Environment.EnvironmentName; // "Development", "Staging", "Production"
```

### Conditional Service Registration

```csharp
if (builder.Environment.IsDevelopment())
{
    builder.Services.AddSingleton<IEmailSender, ConsoleEmailSender>();
}
else
{
    builder.Services.AddSingleton<IEmailSender, SmtpEmailSender>();
}
```

---

## Feature Flags with Microsoft.FeatureManagement

`Microsoft.FeatureManagement.AspNetCore` provides structured feature flag support with filters, targeting, and gradual rollout.

### Setup

```bash
dotnet add package Microsoft.FeatureManagement.AspNetCore
```

```csharp
builder.Services.AddFeatureManagement();
```

### Configuration

```json
{
  "FeatureManagement": {
    "NewDashboard": true,
    "BetaSearch": {
      "EnabledFor": [
        {
          "Name": "Percentage",
          "Parameters": { "Value": 50 }
        }
      ]
    },
    "DarkMode": {
      "EnabledFor": [
        {
          "Name": "Targeting",
          "Parameters": {
            "Audience": {
              "Users": [ "alice@example.com" ],
              "Groups": [
                { "Name": "Beta", "RolloutPercentage": 100 }
              ],
              "DefaultRolloutPercentage": 0
            }
          }
        }
      ]
    }
  }
}
```

### Usage in Code

```csharp
// Inject IFeatureManager
public sealed class DashboardController(IFeatureManager featureManager) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> Get(CancellationToken ct = default)
    {
        if (await featureManager.IsEnabledAsync("NewDashboard"))
        {
            return Ok(new { version = "v2", dashboard = "new" });
        }

        return Ok(new { version = "v1", dashboard = "legacy" });
    }
}
```

### Feature Gate Attribute

```csharp
// Entire endpoint gated on feature flag
[FeatureGate("BetaSearch")]
[HttpGet("search")]
public async Task<IActionResult> Search(string query, CancellationToken ct = default)
{
    var results = await _searchService.SearchAsync(query, ct);
    return Ok(results);
}
```

### Feature Filters

| Filter | Purpose |
|--------|---------|
| `Percentage` | Enable for N% of requests (random) |
| `TimeWindow` | Enable between start/end dates |
| `Targeting` | Enable for specific users, groups, or rollout percentage |
| Custom | Implement `IFeatureFilter` for domain-specific logic |

### Custom Feature Filter

```csharp
[FilterAlias("Browser")]
public sealed class BrowserFeatureFilter(IHttpContextAccessor accessor) : IFeatureFilter
{
    public Task<bool> EvaluateAsync(FeatureFilterEvaluationContext context)
    {
        var userAgent = accessor.HttpContext?.Request.Headers.UserAgent.ToString() ?? "";
        var settings = context.Parameters.Get<BrowserFilterSettings>();

        return Task.FromResult(
            settings?.AllowedBrowsers?.Any(b =>
                userAgent.Contains(b, StringComparison.OrdinalIgnoreCase)) ?? false);
    }
}

public sealed class BrowserFilterSettings
{
    public string[] AllowedBrowsers { get; init; } = [];
}

// Register
builder.Services.AddFeatureManagement()
    .AddFeatureFilter<BrowserFeatureFilter>();
```

---

## Named Options

Use named options when you need multiple instances of the same options type (e.g., multiple API clients).

```csharp
// Registration with names
builder.Services
    .AddOptions<ApiClientOptions>("GitHub")
    .BindConfiguration("ApiClients:GitHub");

builder.Services
    .AddOptions<ApiClientOptions>("Jira")
    .BindConfiguration("ApiClients:Jira");

// Resolution via IOptionsSnapshot<T> or IOptionsMonitor<T>
public sealed class ApiClientFactory(IOptionsSnapshot<ApiClientOptions> snapshot)
{
    public HttpClient CreateFor(string name)
    {
        var options = snapshot.Get(name); // "GitHub" or "Jira"
        return new HttpClient { BaseAddress = new Uri(options.BaseUrl) };
    }
}
```

---

## Post-Configuration

Apply defaults or overrides after all configuration sources have been processed.

```csharp
builder.Services.PostConfigure<SmtpOptions>(options =>
{
    // Ensure a default port if none specified
    if (options.Port == 0)
    {
        options.Port = options.UseSsl ? 465 : 25;
    }
});
```

---

## Testing Configuration

```csharp
[Fact]
public void SmtpOptions_Validates_InvalidPort()
{
    var options = new SmtpOptions
    {
        Host = "smtp.example.com",
        FromAddress = "test@example.com",
        Port = 25,
        UseSsl = true
    };

    var validator = new SmtpOptionsValidator();
    var result = validator.Validate(null, options);

    Assert.True(result.Failed);
    Assert.Contains("Port 25 does not support SSL", result.FailureMessage);
}

[Fact]
public void Configuration_BindsCorrectly()
{
    var config = new ConfigurationBuilder()
        .AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["Smtp:Host"] = "smtp.test.com",
            ["Smtp:Port"] = "465",
            ["Smtp:FromAddress"] = "test@test.com",
        })
        .Build();

    var options = new SmtpOptions();
    config.GetSection("Smtp").Bind(options);

    Assert.Equal("smtp.test.com", options.Host);
    Assert.Equal(465, options.Port);
}
```

---

## References

- [Options pattern in .NET](https://learn.microsoft.com/en-us/dotnet/core/extensions/options)
- [Configuration in .NET](https://learn.microsoft.com/en-us/dotnet/core/extensions/configuration)
- [User secrets in development](https://learn.microsoft.com/en-us/aspnet/core/security/app-secrets)
- [Feature management in .NET](https://learn.microsoft.com/en-us/azure/azure-app-configuration/use-feature-flags-dotnet-core)
- [IValidateOptions](https://learn.microsoft.com/en-us/dotnet/core/extensions/options#options-validation)
- [.NET Framework Design Guidelines](https://learn.microsoft.com/en-us/dotnet/standard/design-guidelines/)
