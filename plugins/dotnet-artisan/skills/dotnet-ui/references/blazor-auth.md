# Blazor Authentication

Authentication and authorization across all Blazor hosting models. Covers AuthorizeView, CascadingAuthenticationState, Identity UI scaffolding, role/policy-based authorization, per-hosting-model auth flow differences (cookie vs token), and external identity providers.

## Auth Flow per Hosting Model

Authentication patterns differ significantly across Blazor hosting models:

| Concern | InteractiveServer | InteractiveWebAssembly | InteractiveAuto | Static SSR | Hybrid |
|---|---|---|---|---|---|
| Auth mechanism | Cookie-based (server-side) | Token-based (JWT/OIDC) | Cookie (Server phase), Token (WASM phase) | Cookie-based (standard ASP.NET Core) | Platform-native or cookie |
| User state access | Direct `HttpContext` access | `AuthenticationStateProvider` | Varies by phase | `HttpContext` | Platform auth APIs |
| Token storage | Not needed (cookie) | `localStorage` or `sessionStorage` | Transition from cookie to token | Not needed (cookie) | Secure storage (Keychain, etc.) |
| Refresh handling | Circuit reconnection | Token refresh via interceptor | Automatic | Standard cookie renewal | Platform-specific |

### InteractiveServer Auth

Server-side Blazor uses cookie authentication. The user authenticates via a standard ASP.NET Core login flow, and the cookie is sent with the initial HTTP request that establishes the SignalR circuit.

```csharp
// Program.cs
builder.Services.AddAuthentication(CookieAuthenticationDefaults.AuthenticationScheme)
    .AddCookie(options =>
    {
        options.LoginPath = "/Account/Login";
        options.AccessDeniedPath = "/Account/AccessDenied";
    });

builder.Services.AddCascadingAuthenticationState();
builder.Services.AddAuthorization();
```

**Gotcha:** `HttpContext` is available during the initial HTTP request but is `null` inside interactive components after the SignalR circuit is established. Do not access `HttpContext` in interactive component lifecycle methods. Use `AuthenticationStateProvider` instead.

### InteractiveWebAssembly Auth

WASM runs in the browser. Cookie auth works for same-origin APIs (and Backend-for-Frontend / BFF patterns), but token-based auth (OIDC/JWT) is the standard approach for cross-origin APIs and delegated access scenarios:

```csharp
// Client Program.cs (WASM)
builder.Services.AddOidcAuthentication(options =>
{
    options.ProviderOptions.Authority = "https://login.example.com";
    options.ProviderOptions.ClientId = "blazor-wasm-client";
    options.ProviderOptions.ResponseType = "code";
    options.ProviderOptions.DefaultScopes.Add("api");
});
```

```csharp
// Attach tokens to API calls using BaseAddressAuthorizationMessageHandler
// (auto-attaches tokens for requests to the app's base address)
builder.Services.AddHttpClient("API", client =>
    client.BaseAddress = new Uri("https://api.example.com"))
    .AddHttpMessageHandler(sp =>
        sp.GetRequiredService<AuthorizationMessageHandler>()
            .ConfigureHandler(
                authorizedUrls: ["https://api.example.com"],
                scopes: ["api"]));

builder.Services.AddScoped(sp =>
    sp.GetRequiredService<IHttpClientFactory>().CreateClient("API"));
```

### InteractiveAuto Auth

Auto mode starts as InteractiveServer (cookie auth), then transitions to WASM (token auth). Handle both:

```csharp
// Server Program.cs
builder.Services.AddAuthentication()
    .AddCookie()
    .AddJwtBearer(); // For WASM API calls after transition

builder.Services.AddCascadingAuthenticationState();
```

### Hybrid (MAUI) Auth

```csharp
// Register platform-specific auth
builder.Services.AddAuthorizationCore();
builder.Services.AddScoped<AuthenticationStateProvider, MauiAuthStateProvider>();

// Custom provider using secure storage
public class MauiAuthStateProvider : AuthenticationStateProvider
{
    public override async Task<AuthenticationState> GetAuthenticationStateAsync()
    {
        var token = await SecureStorage.Default.GetAsync("auth_token");
        if (string.IsNullOrEmpty(token))
        {
            return new AuthenticationState(new ClaimsPrincipal(new ClaimsIdentity()));
        }

        var claims = ParseClaimsFromJwt(token);
        var identity = new ClaimsIdentity(claims, "jwt");
        return new AuthenticationState(new ClaimsPrincipal(identity));
    }
}
```


## AuthorizeView

`AuthorizeView` conditionally renders content based on the user's authentication and authorization state.

### Basic Usage

```razor
<AuthorizeView>
    <Authorized>
        <p>Welcome, @context.User.Identity?.Name!</p>
        <a href="/Account/Logout">Log out</a>
    </Authorized>
    <NotAuthorized>
        <a href="/Account/Login">Log in</a>
    </NotAuthorized>
    <Authorizing>
        <p>Checking authentication...</p>
    </Authorizing>
</AuthorizeView>
```

### Role-Based

```razor
<AuthorizeView Roles="Admin,Manager">
    <Authorized>
        <AdminDashboard />
    </Authorized>
    <NotAuthorized>
        <p>You do not have access to the admin dashboard.</p>
    </NotAuthorized>
</AuthorizeView>
```

### Policy-Based

```razor
<AuthorizeView Policy="CanEditProducts">
    <Authorized>
        <button @onclick="EditProduct">Edit</button>
    </Authorized>
</AuthorizeView>
```

```csharp
// Register policy in Program.cs
builder.Services.AddAuthorizationBuilder()
    .AddPolicy("CanEditProducts", policy =>
        policy.RequireClaim("permission", "products.edit"));
```


## CascadingAuthenticationState

`CascadingAuthenticationState` provides the current `AuthenticationState` as a cascading parameter to all descendant components.

### Setup

```csharp
// Program.cs -- register cascading auth state
builder.Services.AddCascadingAuthenticationState();
```

This replaces wrapping the entire app in `<CascadingAuthenticationState>` (the older pattern). The service-based registration (.NET 8+) is preferred.

### Consuming Auth State in Components

```razor
@code {
    [CascadingParameter]
    private Task<AuthenticationState>? AuthState { get; set; }

    private string? userName;

    protected override async Task OnInitializedAsync()
    {
        if (AuthState is not null)
        {
            var state = await AuthState;
            userName = state.User.Identity?.Name;
        }
    }
}
```

### Accessing Claims

```csharp
var state = await AuthState;
var user = state.User;

// Check authentication
if (user.Identity?.IsAuthenticated == true)
{
    var email = user.FindFirst(ClaimTypes.Email)?.Value;
    var roles = user.FindAll(ClaimTypes.Role).Select(c => c.Value);
    var isAdmin = user.IsInRole("Admin");
}
```


## Identity UI Scaffolding

ASP.NET Core Identity provides a complete authentication system with registration, login, email confirmation, password reset, and two-factor authentication.

### Adding Identity to a Blazor Web App

```bash
# Add Identity scaffolding
dotnet add package Microsoft.AspNetCore.Identity.EntityFrameworkCore
dotnet add package Microsoft.AspNetCore.Identity.UI
```

```csharp
// Program.cs
builder.Services.AddDbContext<ApplicationDbContext>(options =>
    options.UseSqlServer(builder.Configuration.GetConnectionString("Default")));

builder.Services.AddIdentity<ApplicationUser, IdentityRole>(options =>
{
    options.Password.RequireDigit = true;
    options.Password.RequiredLength = 8;
    options.Password.RequireNonAlphanumeric = true;
    options.SignIn.RequireConfirmedAccount = true;
})
.AddEntityFrameworkStores<ApplicationDbContext>()
.AddDefaultTokenProviders();
```

### Scaffolding Identity Pages

```bash
# Scaffold individual Identity pages for customization
dotnet aspnet-codegenerator identity -dc ApplicationDbContext --files "Account.Login;Account.Register;Account.Logout"
```

### Custom Identity UI with Blazor Components

For a fully Blazor-native auth experience, create Blazor components that call Identity APIs:

```razor
@page "/Account/Login"
@inject SignInManager<ApplicationUser> SignInManager
@inject NavigationManager Navigation

<EditForm Model="loginModel" OnValidSubmit="HandleLogin" FormName="login" Enhance>
    <DataAnnotationsValidator />
    <ValidationSummary />

    <div>
        <InputText @bind-Value="loginModel.Email" placeholder="Email" />
    </div>
    <div>
        <InputText @bind-Value="loginModel.Password" type="password" placeholder="Password" />
    </div>
    <div>
        <InputCheckbox @bind-Value="loginModel.RememberMe" /> Remember me
    </div>

    <button type="submit">Log in</button>
</EditForm>

@if (!string.IsNullOrEmpty(errorMessage))
{
    <p class="text-danger">@errorMessage</p>
}

@code {
    [SupplyParameterFromForm]
    private LoginModel loginModel { get; set; } = new();

    private string? errorMessage;

    private async Task HandleLogin()
    {
        var result = await SignInManager.PasswordSignInAsync(
            loginModel.Email, loginModel.Password,
            loginModel.RememberMe, lockoutOnFailure: true);

        if (result.Succeeded)
        {
            Navigation.NavigateTo("/", forceLoad: true);
        }
        else if (result.RequiresTwoFactor)
        {
            Navigation.NavigateTo("/Account/LoginWith2fa");
        }
        else if (result.IsLockedOut)
        {
            errorMessage = "Account is locked. Try again later.";
        }
        else
        {
            errorMessage = "Invalid login attempt.";
        }
    }
}
```

**Gotcha:** `SignInManager` uses `HttpContext` to set cookies. In Interactive render modes, `HttpContext` is not available after the circuit is established. Login/logout pages must use Static SSR (no `@rendermode`) so they have access to `HttpContext` for cookie operations.


## Role and Policy-Based Authorization

### Page-Level Authorization

```razor
@page "/admin"
@attribute [Authorize(Roles = "Admin")]

<h1>Admin Panel</h1>
```

```razor
@page "/products/manage"
@attribute [Authorize(Policy = "ProductManager")]

<h1>Manage Products</h1>
```

### Defining Policies

```csharp
builder.Services.AddAuthorizationBuilder()
    .AddPolicy("ProductManager", policy =>
        policy.RequireRole("Admin", "ProductManager"))
    .AddPolicy("CanDeleteOrders", policy =>
        policy.RequireClaim("permission", "orders.delete")
              .RequireAuthenticatedUser())
    .AddPolicy("MinimumAge", policy =>
        policy.AddRequirements(new MinimumAgeRequirement(18)));
```

### Custom Authorization Handler

```csharp
public sealed class MinimumAgeRequirement(int minimumAge) : IAuthorizationRequirement
{
    public int MinimumAge { get; } = minimumAge;
}

public sealed class MinimumAgeHandler : AuthorizationHandler<MinimumAgeRequirement>
{
    protected override Task HandleRequirementAsync(
        AuthorizationHandlerContext context,
        MinimumAgeRequirement requirement)
    {
        var dateOfBirthClaim = context.User.FindFirst("date_of_birth");
        if (dateOfBirthClaim is not null
            && DateOnly.TryParse(dateOfBirthClaim.Value, out var dob))
        {
            var age = DateOnly.FromDateTime(DateTime.UtcNow).Year - dob.Year;
            if (age >= requirement.MinimumAge)
            {
                context.Succeed(requirement);
            }
        }
        return Task.CompletedTask;
    }
}

// Register
builder.Services.AddSingleton<IAuthorizationHandler, MinimumAgeHandler>();
```

### Procedural Authorization in Components

```razor
@inject IAuthorizationService AuthorizationService

@code {
    [CascadingParameter]
    private Task<AuthenticationState>? AuthState { get; set; }

    private bool canEdit;

    protected override async Task OnInitializedAsync()
    {
        if (AuthState is not null)
        {
            var state = await AuthState;
            var result = await AuthorizationService.AuthorizeAsync(
                state.User, "CanEditProducts");
            canEdit = result.Succeeded;
        }
    }
}
```


## External Identity Providers

### Adding External Providers

```csharp
builder.Services.AddAuthentication()
    .AddMicrosoftAccount(options =>
    {
        options.ClientId = builder.Configuration["Auth:Microsoft:ClientId"]!;
        options.ClientSecret = builder.Configuration["Auth:Microsoft:ClientSecret"]!;
    })
    .AddGoogle(options =>
    {
        options.ClientId = builder.Configuration["Auth:Google:ClientId"]!;
        options.ClientSecret = builder.Configuration["Auth:Google:ClientSecret"]!;
    });
```

### External Login Flow per Hosting Model

| Hosting Model | Flow | Notes |
|---|---|---|
| InteractiveServer / Static SSR | Standard OAuth redirect (server-side) | Cookie stored after callback |
| InteractiveWebAssembly | OIDC with PKCE (client-side) | Token stored in browser |
| Hybrid (MAUI) | `WebAuthenticator` or MSAL | Platform-specific secure storage |

For WASM, configure the OIDC provider in the client project:

```csharp
// Client Program.cs
builder.Services.AddOidcAuthentication(options =>
{
    options.ProviderOptions.Authority = "https://login.microsoftonline.com/{tenant}";
    options.ProviderOptions.ClientId = "{client-id}";
    options.ProviderOptions.ResponseType = "code";
});
```

For MAUI Hybrid:

```csharp
var result = await WebAuthenticator.Default.AuthenticateAsync(
    new Uri("https://login.example.com/authorize"),
    new Uri("myapp://callback"));
var token = result.AccessToken;
```


## Agent Gotchas

1. **Do not access `HttpContext` in interactive components.** `HttpContext` is only available during the initial HTTP request. After the SignalR circuit is established (InteractiveServer) or the WASM runtime loads, it is `null`. Use `AuthenticationStateProvider` or `CascadingAuthenticationState` instead.
2. **Do not rely on cookies for cross-origin or delegated API access in WASM.** Use OIDC/JWT with `AuthorizationMessageHandler` for cross-origin APIs. Same-origin and Backend-for-Frontend (BFF) cookie auth remains valid for WASM apps.
3. **Do not render login/logout pages in Interactive mode.** `SignInManager` requires `HttpContext` to set/clear cookies. Login and logout pages must use Static SSR render mode.
4. **Do not store tokens in `localStorage` without considering XSS.** If the app is vulnerable to XSS, tokens in `localStorage` can be stolen. Use `sessionStorage` (cleared on tab close) or the OIDC library's built-in storage mechanisms with PKCE.
5. **Do not forget `AddCascadingAuthenticationState()`.** Without it, `[CascadingParameter] Task<AuthenticationState>` is always `null` in components, silently breaking auth checks.
6. **Do not use `AddIdentity` and `AddDefaultIdentity` together.** `AddDefaultIdentity` includes UI scaffolding; `AddIdentity` does not. Choose one based on whether you want the default Identity UI pages.


## Prerequisites

- .NET 8.0+ (Blazor Web App with render modes, `AddCascadingAuthenticationState` service registration)
- `Microsoft.AspNetCore.Identity.EntityFrameworkCore` for Identity with EF Core
- `Microsoft.AspNetCore.Identity.UI` for default Identity UI scaffolding
- `Microsoft.AspNetCore.Authentication.MicrosoftAccount` / `.Google` for external providers
- `Microsoft.Authentication.WebAssembly.Msal` for WASM with Microsoft Identity (Azure AD/Entra)


## References

- [Blazor Authentication and Authorization](https://learn.microsoft.com/en-us/aspnet/core/blazor/security/?view=aspnetcore-10.0)
- [Blazor Server Auth](https://learn.microsoft.com/en-us/aspnet/core/blazor/security/server/?view=aspnetcore-10.0)
- [Blazor WebAssembly Auth](https://learn.microsoft.com/en-us/aspnet/core/blazor/security/webassembly/?view=aspnetcore-10.0)
- [ASP.NET Core Identity](https://learn.microsoft.com/en-us/aspnet/core/security/authentication/identity?view=aspnetcore-10.0)
- [External Login Providers](https://learn.microsoft.com/en-us/aspnet/core/security/authentication/social/?view=aspnetcore-10.0)
- [Role/Policy-Based Authorization](https://learn.microsoft.com/en-us/aspnet/core/security/authorization/roles?view=aspnetcore-10.0)
