# ASP.NET Core Identity

ASP.NET Core Identity is the built-in membership system for managing users, passwords, roles, claims, tokens, email confirmation, and 2FA/MFA. It is distinct from the Microsoft Identity Platform (Azure AD/Entra ID) -- Identity is for self-hosted user stores, not federated OIDC.

## AddIdentity vs AddDefaultIdentity

```csharp
// AddDefaultIdentity = AddIdentity + AddDefaultUI + AddDefaultTokenProviders
// Use when you want the scaffolded Razor Pages UI and all token providers
builder.Services.AddDefaultIdentity<IdentityUser>(options =>
        options.SignIn.RequireConfirmedAccount = true)
    .AddEntityFrameworkStores<ApplicationDbContext>();

// AddIdentity = core services only -- no UI, no default token providers
// Use when you need roles, custom UI, or want to control token providers
builder.Services.AddIdentity<ApplicationUser, IdentityRole>(options =>
    {
        options.SignIn.RequireConfirmedAccount = true;
    })
    .AddEntityFrameworkStores<ApplicationDbContext>()
    .AddDefaultTokenProviders();
```

| Method | Includes UI | Includes Roles | Token Providers |
|--------|-------------|---------------|-----------------|
| `AddDefaultIdentity<TUser>()` | Yes (Razor Pages) | No -- add `.AddRoles<IdentityRole>()` | Yes (all defaults) |
| `AddIdentity<TUser, TRole>()` | No | Yes | No -- add `.AddDefaultTokenProviders()` |

## Database Setup

```csharp
builder.Services.AddDbContext<ApplicationDbContext>(options =>
    options.UseSqlServer(builder.Configuration.GetConnectionString("DefaultConnection")));
```

```bash
dotnet ef migrations add CreateIdentitySchema
dotnet ef database update
```

## Password Policies

```csharp
builder.Services.Configure<IdentityOptions>(options =>
{
    options.Password.RequireDigit = true;
    options.Password.RequireLowercase = true;
    options.Password.RequireNonAlphanumeric = true;
    options.Password.RequireUppercase = true;
    options.Password.RequiredLength = 8;          // Default: 6
    options.Password.RequiredUniqueChars = 4;     // Default: 1
});
```

## Account Lockout

```csharp
builder.Services.Configure<IdentityOptions>(options =>
{
    options.Lockout.DefaultLockoutTimeSpan = TimeSpan.FromMinutes(15);
    options.Lockout.MaxFailedAccessAttempts = 5;
    options.Lockout.AllowedForNewUsers = true;
});

// IMPORTANT: pass lockoutOnFailure: true in PasswordSignInAsync
var result = await signInManager.PasswordSignInAsync(
    email, password, isPersistent: false, lockoutOnFailure: true);
```

The default scaffolded template uses `lockoutOnFailure: false` -- this must be changed to enable lockout.

## Email Confirmation and Sign-In Options

```csharp
builder.Services.Configure<IdentityOptions>(options =>
{
    options.SignIn.RequireConfirmedEmail = true;
    options.SignIn.RequireConfirmedPhoneNumber = false;
    options.User.RequireUniqueEmail = true;
});
```

Implement `IEmailSender` (or `IEmailSender<TUser>` in .NET 8+) to send confirmation emails:

```csharp
builder.Services.AddTransient<IEmailSender, SmtpEmailSender>();
```

## Two-Factor Authentication (2FA/MFA)

TOTP-based 2FA is included by default with `AddDefaultTokenProviders`. Users enable it via the scaffolded Manage pages.

```csharp
// To disable TOTP and control token providers explicitly:
builder.Services.AddIdentity<ApplicationUser, IdentityRole>()
    .AddEntityFrameworkStores<ApplicationDbContext>()
    .AddTokenProvider<DataProtectorTokenProvider<ApplicationUser>>(
        TokenOptions.DefaultProvider)
    .AddTokenProvider<EmailTokenProvider<ApplicationUser>>(
        TokenOptions.DefaultEmailProvider);
    // Omit AuthenticatorTokenProvider to disable TOTP
```

## External Login Providers

```csharp
builder.Services.AddAuthentication()
    .AddGoogle(options =>
    {
        options.ClientId = builder.Configuration["Auth:Google:ClientId"]!;
        options.ClientSecret = builder.Configuration["Auth:Google:ClientSecret"]!;
    })
    .AddMicrosoftAccount(options =>
    {
        options.ClientId = builder.Configuration["Auth:Microsoft:ClientId"]!;
        options.ClientSecret = builder.Configuration["Auth:Microsoft:ClientSecret"]!;
    })
    .AddGitHub(options =>   // AspNet.Security.OAuth.GitHub package
    {
        options.ClientId = builder.Configuration["Auth:GitHub:ClientId"]!;
        options.ClientSecret = builder.Configuration["Auth:GitHub:ClientSecret"]!;
    });
```

External auth packages: `Microsoft.AspNetCore.Authentication.Google`, `Microsoft.AspNetCore.Authentication.MicrosoftAccount`, `AspNet.Security.OAuth.GitHub`.

## Identity UI Scaffolding

```bash
dotnet add package Microsoft.VisualStudio.Web.CodeGeneration.Design
dotnet aspnet-codegenerator identity -dc ApplicationDbContext --files \
    "Account.Register;Account.Login;Account.Manage.Index"
```

Scaffolded files land in `Areas/Identity/Pages/Account/`. Override only the pages you need.

## Identity with Minimal APIs (.NET 8+)

`MapIdentityApi<TUser>()` adds JSON API endpoints (`/register`, `/login`, `/refresh`, `/confirmEmail`, `/manage/*`) without the Razor Pages UI:

```csharp
builder.Services.AddIdentityApiEndpoints<IdentityUser>()
    .AddEntityFrameworkStores<ApplicationDbContext>();

var app = builder.Build();

app.MapIdentityApi<IdentityUser>();  // Maps /register, /login, etc.
app.MapGet("/protected", [Authorize] () => "secret data");
```

This is designed for SPA and mobile clients that do not use the server-rendered Identity UI.

## Cookie Configuration

```csharp
builder.Services.ConfigureApplicationCookie(options =>
{
    options.Cookie.HttpOnly = true;
    options.Cookie.Name = "MyApp.Auth";
    options.ExpireTimeSpan = TimeSpan.FromHours(2);
    options.SlidingExpiration = true;
    options.LoginPath = "/Identity/Account/Login";
    options.AccessDeniedPath = "/Identity/Account/AccessDenied";
});
```

`ConfigureApplicationCookie` must be called **after** `AddIdentity` / `AddDefaultIdentity`.

## User and Role Management

```csharp
public class UserService(UserManager<ApplicationUser> userManager,
                          RoleManager<IdentityRole> roleManager)
{
    public async Task CreateAdminAsync()
    {
        if (!await roleManager.RoleExistsAsync("Admin"))
            await roleManager.CreateAsync(new IdentityRole("Admin"));

        var user = new ApplicationUser { UserName = "admin@example.com", Email = "admin@example.com" };
        var result = await userManager.CreateAsync(user, "SecureP@ss1");
        if (result.Succeeded)
        {
            await userManager.AddToRoleAsync(user, "Admin");
            await userManager.AddClaimAsync(user,
                new Claim("Department", "Engineering"));
        }
    }
}
```

## Identity vs External OIDC

| Scenario | Use |
|----------|-----|
| Self-hosted user store, full control over registration/login | ASP.NET Core Identity |
| Enterprise SSO with Azure AD/Entra ID | Microsoft Identity Platform (MSAL) |
| Delegated auth to third-party IdP (Auth0, Okta) | OIDC middleware + cookie auth |
| API-only with JWT tokens (no UI) | `MapIdentityApi` or JWT Bearer auth |

## Data Protection Key Storage

Identity depends on the Data Protection system for token generation and cookie encryption. In production multi-server deployments, persist keys to a shared store:

```csharp
builder.Services.AddDataProtection()
    .PersistKeysToDbColumn(options =>
        options.UseSqlServer(connectionString))
    .SetApplicationName("MyApp");
```

Without shared key storage, tokens generated on one server cannot be validated on another.

---

## Agent Gotchas

1. **Do not use `AddDefaultIdentity` and then expect roles to work** -- `AddDefaultIdentity` does not register `RoleManager`. Chain `.AddRoles<IdentityRole>()` to enable role support.
2. **Do not forget `lockoutOnFailure: true` in `PasswordSignInAsync`** -- the default scaffolded template sets it to `false`, which silently disables account lockout.
3. **Do not call `ConfigureApplicationCookie` before `AddIdentity`** -- the cookie options will be overwritten by `AddIdentity`'s internal configuration.
4. **Do not place `UseAuthentication()` after `UseAuthorization()`** -- authentication must run first to establish the user identity. Reversed order causes all auth checks to fail.
5. **Do not store Data Protection keys in the default file system location in production** -- keys are stored in `%LOCALAPPDATA%` by default and are not shared across servers. Use a database, Redis, or Azure Blob Storage.
6. **Do not expose Identity API endpoints without rate limiting** -- `MapIdentityApi` exposes `/register` and `/login` which are brute-force targets. Always apply rate limiting.

---

## References

- [Introduction to Identity](https://learn.microsoft.com/aspnet/core/security/authentication/identity?view=aspnetcore-10.0)
- [Configure Identity](https://learn.microsoft.com/aspnet/core/security/authentication/identity-configuration?view=aspnetcore-10.0)
- [Scaffold Identity](https://learn.microsoft.com/aspnet/core/security/authentication/scaffold-identity?view=aspnetcore-10.0)
- [Identity API endpoints (.NET 8+)](https://learn.microsoft.com/aspnet/core/release-notes/aspnetcore-8.0#identity-api-endpoints)
- [External login providers](https://learn.microsoft.com/aspnet/core/security/authentication/social/?view=aspnetcore-10.0)
- [Two-factor authentication](https://learn.microsoft.com/aspnet/core/security/authentication/mfa?view=aspnetcore-10.0)
