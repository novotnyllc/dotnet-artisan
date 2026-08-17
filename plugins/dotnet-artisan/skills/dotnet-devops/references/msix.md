# MSIX Packaging

MSIX packaging pipeline for .NET desktop applications: package creation from csproj (`WindowsPackageType`) and WAP projects, certificate signing (self-signed for development, trusted CA for production, Microsoft Store signing), distribution channels (Microsoft Store submission, App Installer sideloading, enterprise deployment via SCCM/Intune), auto-update configuration (App Installer XML, version checking, differential updates), MSIX bundle format for multi-architecture (`.msixbundle`), and CI/CD MSIX build steps.

**Version assumptions:** Windows App SDK 1.6+ (current stable). Windows 10 build 19041+ minimum for MSIX with Windows App SDK. Windows 10 build 1709+ for App Installer auto-update protocol. .NET 8.0+ baseline.

## MSIX Package Creation

### From csproj (Single-Project Packaging)

Modern WinUI 3 and Windows App SDK apps can produce MSIX packages directly from the application `.csproj` without a separate Windows Application Packaging (WAP) project.

```xml
<!-- MyApp.csproj -->
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>WinExe</OutputType>
    <TargetFramework>net8.0-windows10.0.19041.0</TargetFramework>
    <UseWinUI>true</UseWinUI>

    <!-- MSIX packaging mode -->
    <WindowsPackageType>MSIX</WindowsPackageType>

    <!-- Package identity -->
    <AppxPackageDir>$(SolutionDir)AppPackages\</AppxPackageDir>
    <GenerateAppxPackageOnBuild>false</GenerateAppxPackageOnBuild>
  </PropertyGroup>
</Project>
```

Build the MSIX package:

```bash
# Build MSIX package
dotnet publish --configuration Release --runtime win-x64 \
  /p:GenerateAppxPackageOnBuild=true \
  /p:AppxPackageSigningEnabled=false

# Output: AppPackages\MyApp_1.0.0.0_x64.msix
```

### WAP Project (Desktop Bridge)

For non-WinUI desktop apps (WPF, WinForms), use a Windows Application Packaging Project to wrap the existing app as MSIX. WAP projects (`.wapproj`) are created via the Visual Studio "Windows Application Packaging Project" template -- they use a specialized project format, not the standard `Microsoft.NET.Sdk`.

The key configuration is referencing the desktop app project:

```xml
<!-- MyApp.Package.wapproj (created via VS template) -->
<!-- Key elements in the generated .wapproj file: -->
<ItemGroup>
  <!-- Reference the desktop app project to include in MSIX -->
  <ProjectReference Include="..\MyWpfApp\MyWpfApp.csproj" />
</ItemGroup>

<!-- Set target platform versions in the .wapproj PropertyGroup -->
<PropertyGroup>
  <TargetPlatformVersion>10.0.22621.0</TargetPlatformVersion>
  <TargetPlatformMinVersion>10.0.19041.0</TargetPlatformMinVersion>
  <DefaultLanguage>en-US</DefaultLanguage>
  <AppxPackageDir>$(SolutionDir)AppPackages\</AppxPackageDir>
</PropertyGroup>
```

### Package.appxmanifest

The manifest defines identity, capabilities, and visual assets:

```xml
<?xml version="1.0" encoding="utf-8"?>
<Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10"
         xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10"
         xmlns:rescap="http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities"
         IgnorableNamespaces="uap rescap">

  <Identity Name="MyCompany.MyApp"
            Publisher="CN=My Company, O=My Company, L=Seattle, S=WA, C=US"
            Version="1.0.0.0"
            ProcessorArchitecture="x64" />

  <Properties>
    <DisplayName>My App</DisplayName>
    <PublisherDisplayName>My Company</PublisherDisplayName>
    <Logo>Assets\StoreLogo.png</Logo>
  </Properties>

  <Dependencies>
    <TargetDeviceFamily Name="Windows.Desktop"
                        MinVersion="10.0.19041.0"
                        MaxVersionTested="10.0.22621.0" />
  </Dependencies>

  <Resources>
    <Resource Language="en-us" />
  </Resources>

  <Applications>
    <Application Id="App"
                 Executable="MyApp.exe"
                 EntryPoint="$targetentrypoint$">
      <uap:VisualElements DisplayName="My App"
                          Description="My application description"
                          BackgroundColor="transparent"
                          Square150x150Logo="Assets\Square150x150Logo.png"
                          Square44x44Logo="Assets\Square44x44Logo.png">
        <uap:DefaultTile Wide310x150Logo="Assets\Wide310x150Logo.png" />
      </uap:VisualElements>
    </Application>
  </Applications>

  <Capabilities>
    <Capability Name="internetClient" />
    <rescap:Capability Name="runFullTrust" />
  </Capabilities>
</Package>
```

---

## Signing with Certificates

All MSIX packages must be signed to install on Windows. The signing certificate's Subject must match the `Publisher` attribute in the package manifest.

### Self-Signed Certificate (Development)

```powershell
# Create a self-signed certificate for development
$cert = New-SelfSignedCertificate `
  -Type Custom `
  -Subject "CN=My Company, O=My Company, L=Seattle, S=WA, C=US" `
  -KeyUsage DigitalSignature `
  -FriendlyName "MyApp Dev Signing" `
  -CertStoreLocation "Cert:\CurrentUser\My" `
  -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.3", `
                    "2.5.29.19={text}")

# Export PFX for CI usage
$password = ConvertTo-SecureString -String "$env:CERT_PASSWORD" -Force -AsPlainText
Export-PfxCertificate -Cert $cert `
  -FilePath "MyApp_DevSigning.pfx" `
  -Password $password

# Find signtool.exe dynamically (SDK version varies by machine)
$signtool = Get-ChildItem "C:\Program Files (x86)\Windows Kits\10\bin\*\x64\signtool.exe" |
  Sort-Object { [version]($_.Directory.Parent.Name) } -Descending |
  Select-Object -First 1 -ExpandProperty FullName

# Sign the MSIX package
& $signtool sign /fd SHA256 /a /f "MyApp_DevSigning.pfx" `
  /p "$env:CERT_PASSWORD" `
  "AppPackages\MyApp_1.0.0.0_x64.msix"
```

### Trusted CA Certificate (Production)

For production distribution outside the Microsoft Store:

1. **Obtain a code signing certificate** from a trusted CA (DigiCert, Sectigo, GlobalSign)
2. **Subject must match** the `Publisher` in `Package.appxmanifest`
3. **Timestamp the signature** for long-term validity

```powershell
# Sign with a trusted CA certificate (from certificate store)
& signtool.exe sign /fd SHA256 /sha1 "THUMBPRINT_HERE" `
  /tr http://timestamp.digicert.com /td SHA256 `
  "AppPackages\MyApp_1.0.0.0_x64.msix"

# Sign with a PFX file
& signtool.exe sign /fd SHA256 /f "production-cert.pfx" `
  /p "$env:CERT_PASSWORD" `
  /tr http://timestamp.digicert.com /td SHA256 `
  "AppPackages\MyApp_1.0.0.0_x64.msix"
```

### Microsoft Store Signing

Apps submitted to the Microsoft Store are re-signed by Microsoft during ingestion. The development signing certificate is replaced with a Microsoft-issued certificate. No production signing certificate is needed for Store-only distribution.

```xml
<!-- For Store submission, use a test certificate during development -->
<PropertyGroup>
  <AppxPackageSigningEnabled>true</AppxPackageSigningEnabled>
  <PackageCertificateThumbprint>AUTO_GENERATED_BY_VS</PackageCertificateThumbprint>
</PropertyGroup>
```

### Certificate Requirements Summary

| Distribution | Certificate Type | Trusted CA Required |
|-------------|-----------------|---------------------|
| Development/testing | Self-signed | No (install cert manually) |
| Enterprise sideload | Self-signed or internal CA | No (deploy cert via Group Policy) |
| Direct download | Trusted CA (DigiCert, etc.) | Yes |
| Microsoft Store | Test cert (re-signed by MS) | No |

---

## Distribution Channels

### Microsoft Store Submission

1. **Register as a Windows developer** at the Partner Center (https://partner.microsoft.com/dashboard)
2. **Create an app reservation** to secure the app name
3. **Build the MSIX package** with Store association:

```bash
# Build for Store submission (creates .msixupload)
dotnet publish --configuration Release --runtime win-x64 \
  /p:GenerateAppxPackageOnBuild=true \
  /p:UapAppxPackageBuildMode=StoreUpload \
  /p:AppxBundle=Auto
```

4. **Submit the `.msixupload` file** through Partner Center
5. Microsoft validates, signs, and publishes the app

### App Installer Sideloading

App Installer (`.appinstaller`) enables direct distribution with auto-update support. Host the files on a web server, network share, or CDN.

```xml
<!-- MyApp.appinstaller -->
<?xml version="1.0" encoding="utf-8"?>
<AppInstaller Uri="https://mycompany.com/apps/MyApp.appinstaller"
              Version="1.0.0.0"
              xmlns="http://schemas.microsoft.com/appx/appinstaller/2021">

  <MainPackage Name="MyCompany.MyApp"
               Version="1.0.0.0"
               Publisher="CN=My Company, O=My Company, L=Seattle, S=WA, C=US"
               ProcessorArchitecture="x64"
               Uri="https://mycompany.com/apps/MyApp_1.0.0.0_x64.msix" />

  <UpdateSettings>
    <OnLaunch HoursBetweenUpdateChecks="12"
              ShowPrompt="true"
              UpdateBlocksActivation="false" />
    <AutomaticBackgroundTask />
    <ForceUpdateFromAnyVersion>false</ForceUpdateFromAnyVersion>
  </UpdateSettings>
</AppInstaller>
```

Users install via:

```
ms-appinstaller:?source=https://mycompany.com/apps/MyApp.appinstaller
```

### Enterprise Deployment

For managed enterprise environments:

| Method | Tool | Best For |
|--------|------|----------|
| Microsoft Intune | Intune portal | Cloud-managed devices |
| SCCM/MECM | Configuration Manager | On-premises managed devices |
| Group Policy | DISM / PowerShell | Domain-joined devices |
| PowerShell | `Add-AppxPackage` | Script-based deployment |

```powershell
# Enterprise deployment via PowerShell
Add-AppxPackage -Path "\\fileserver\apps\MyApp_1.0.0.0_x64.msix"

# Install for all users (requires admin)
Add-AppxProvisionedPackage -Online `
  -PackagePath "MyApp_1.0.0.0_x64.msix" `
  -SkipLicense
```

---

## Auto-Update Configuration

### App Installer Auto-Update (Windows 10 1709+)

The App Installer XML file controls automatic update behavior:

```xml
<UpdateSettings>
  <!-- Check for updates on app launch -->
  <OnLaunch HoursBetweenUpdateChecks="12"
            ShowPrompt="true"
            UpdateBlocksActivation="false" />

  <!-- Background update check (Windows 10 1803+) -->
  <AutomaticBackgroundTask />

  <!-- Allow downgrade (useful for rollback scenarios) -->
  <ForceUpdateFromAnyVersion>false</ForceUpdateFromAnyVersion>
</UpdateSettings>
```

| Setting | Description |
|---------|-------------|
| `HoursBetweenUpdateChecks` | Minimum hours between update checks (0 = every launch) |
| `ShowPrompt` | Show update dialog to user before updating |
| `UpdateBlocksActivation` | Block app launch until update completes |
| `AutomaticBackgroundTask` | Check for updates in background without launching |
| `ForceUpdateFromAnyVersion` | Allow updating from any version (including downgrades) |

### Programmatic Update Check (Windows App SDK)

For apps that need custom update UI or logic, use `Package.Current.CheckUpdateAvailabilityAsync()`:

```csharp
using Windows.ApplicationModel;

public class AppUpdateService
{
    public async Task<bool> CheckForUpdatesAsync()
    {
        var result = await Package.Current.CheckUpdateAvailabilityAsync();
        return result.Availability == PackageUpdateAvailability.Available
            || result.Availability == PackageUpdateAvailability.Required;
    }
}
```

### Differential Updates

MSIX supports differential updates -- only changed blocks are downloaded. This is automatic when:
- The same `PackageName` and `Publisher` are used
- The `Version` is incremented
- Both old and new packages are hosted on the same server

No additional configuration is needed for differential updates.

---

## MSIX Bundle Format

MSIX bundles (`.msixbundle`) package multiple architecture-specific MSIX packages into a single downloadable artifact. Windows automatically installs the correct architecture.

### Creating a Bundle

```powershell
# Build for multiple architectures
dotnet publish -c Release -r win-x64 /p:GenerateAppxPackageOnBuild=true
dotnet publish -c Release -r win-arm64 /p:GenerateAppxPackageOnBuild=true

# Find MakeAppx.exe dynamically (SDK version varies by machine)
$makeappx = Get-ChildItem "C:\Program Files (x86)\Windows Kits\10\bin\*\x64\MakeAppx.exe" |
  Sort-Object { [version]($_.Directory.Parent.Name) } -Descending |
  Select-Object -First 1 -ExpandProperty FullName

# Create bundle
& $makeappx bundle /d "AppPackages" /p "MyApp_1.0.0.0.msixbundle"
```

### MSBuild Bundle Generation

```xml
<PropertyGroup>
  <!-- Auto-generate bundle during build -->
  <AppxBundle>Always</AppxBundle>
  <AppxBundlePlatforms>x64|arm64</AppxBundlePlatforms>
</PropertyGroup>
```

### Bundle Layout

```
MyApp_1.0.0.0.msixbundle
  MyApp_1.0.0.0_x64.msix
  MyApp_1.0.0.0_arm64.msix
```

---

## CI/CD MSIX Build Steps

### GitHub Actions MSIX Build

```yaml
# MSIX-specific build steps (embed in your CI workflow)
# For pipeline structure, see [skill:dotnet-devops] references/gha-patterns.md
jobs:
  build-msix:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup .NET
        uses: actions/setup-dotnet@v4
        with:
          dotnet-version: '8.0.x'

      - name: Decode signing certificate
        run: |
          $pfxBytes = [System.Convert]::FromBase64String("${{ secrets.SIGNING_CERT_BASE64 }}")
          [System.IO.File]::WriteAllBytes("signing-cert.pfx", $pfxBytes)
        shell: pwsh

      - name: Build MSIX package
        run: |
          dotnet publish --configuration Release --runtime win-x64 `
            /p:GenerateAppxPackageOnBuild=true `
            /p:AppxPackageSigningEnabled=true `
            /p:PackageCertificateKeyFile="${{ github.workspace }}\signing-cert.pfx" `
            /p:PackageCertificatePassword="${{ secrets.CERT_PASSWORD }}"
        shell: pwsh

      - name: Upload MSIX artifact
        uses: actions/upload-artifact@v4
        with:
          name: msix-package
          path: AppPackages/**/*.msix

      - name: Clean up certificate
        if: always()
        run: Remove-Item -Path "signing-cert.pfx" -ErrorAction SilentlyContinue
        shell: pwsh
```

### Azure DevOps MSIX Build

```yaml
# MSIX-specific build steps (embed in your ADO pipeline)
# For pipeline structure, see [skill:dotnet-devops] references/ado-patterns.md
steps:
  - task: UseDotNet@2
    inputs:
      packageType: 'sdk'
      version: '8.0.x'

  - task: DownloadSecureFile@1
    name: signingCert
    inputs:
      secureFile: 'signing-cert.pfx'

  - task: DotNetCoreCLI@2
    displayName: 'Build MSIX'
    inputs:
      command: 'publish'
      publishWebProjects: false
      projects: '**/MyApp.csproj'
      arguments: >-
        --configuration Release
        --runtime win-x64
        /p:GenerateAppxPackageOnBuild=true
        /p:AppxPackageSigningEnabled=true
        /p:PackageCertificateKeyFile=$(signingCert.secureFilePath)
        /p:PackageCertificatePassword=$(CERT_PASSWORD)

  - task: PublishBuildArtifacts@1
    inputs:
      pathToPublish: 'AppPackages'
      artifactName: 'msix-package'
```

### AOT + MSIX

MSIX packages can contain AOT-compiled binaries for faster startup and smaller runtime footprint. Combine `PublishAot` with MSIX packaging:

```xml
<PropertyGroup>
  <PublishAot>true</PublishAot>
  <WindowsPackageType>MSIX</WindowsPackageType>
</PropertyGroup>
```

For AOT MSBuild configuration details (ILLink descriptors, trimming options, platform considerations), see [skill:dotnet-tooling].

---

## Windows SDK Version Requirements

| Feature | Minimum Windows Version | Build Number |
|---------|------------------------|--------------|
| MSIX with Windows App SDK | Windows 10 | Build 19041 (2004) |
| App Installer protocol | Windows 10 | Build 1709 (Fall Creators Update) |
| Auto-update (OnLaunch) | Windows 10 | Build 1709 |
| Background auto-update | Windows 10 | Build 1803 (April 2018 Update) |
| ForceUpdateFromAnyVersion | Windows 10 | Build 1809 |
| MSIX bundle format | Windows 10 | Build 1709 |
| Optional packages | Windows 10 | Build 1709 |
| Modification packages | Windows 10 | Build 1809 |
| App Installer file hosting | Windows 10 | Build 1709 |
| Microsoft Store submission | Windows App SDK 1.6+ | N/A |

### Target Platform Version Configuration

```xml
<PropertyGroup>
  <!-- Minimum supported version (features below this are unavailable) -->
  <TargetFramework>net8.0-windows10.0.19041.0</TargetFramework>

  <!-- Maximum tested version (for adaptive version checks) -->
  <TargetPlatformVersion>10.0.22621.0</TargetPlatformVersion>
</PropertyGroup>
```

---

## Agent Gotchas

1. **The manifest `Publisher` must exactly match the signing certificate Subject** -- mismatches cause `SignTool Error: SignerSign() failed` at build or sign time.

2. **Self-signed certificates require manual trust installation** -- users must install the certificate to `Trusted People` or `Trusted Root Certification Authorities` before the MSIX will install.

3. **Never commit PFX files or certificate passwords to source control** -- store certificates as CI secrets (GitHub Secrets, Azure DevOps Secure Files) and decode them during the build pipeline.

4. **`AppxBundle=Auto` produces a bundle only when multiple architectures are built** -- for single-architecture builds, it produces a flat `.msix` file, not a bundle.

5. **MSIX apps run in a container-like sandbox** -- file system access is virtualized. Apps writing to `AppData` get redirected to the package-specific location. Use `ApplicationData.Current` APIs, not hardcoded paths.

6. **Store submission uses `.msixupload` not `.msix`** -- set `/p:UapAppxPackageBuildMode=StoreUpload` to generate the correct upload format.

7. **CI builds on `windows-latest` include the Windows SDK** -- no separate SDK installation step is needed for `signtool.exe` and `MakeAppx.exe`.

8. **Do not hardcode TFM paths in CI examples** -- use variable references (e.g., `${{ github.workspace }}`) so examples work across .NET versions.
