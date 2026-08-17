# Uno Targets

Per-target deployment guidance for Uno Platform applications: Web/WASM, iOS, Android, macOS (Catalyst), Windows, Linux (Skia/GTK), and Embedded (Skia/Framebuffer). Each target section covers project setup, debugging workflow, packaging/distribution, platform-specific gotchas, AOT/trimming implications, and behavior differences from other targets.

## Target Platform Overview

| Target | TFM | Tooling | Packaging | Key Constraints |
|--------|-----|---------|-----------|----------------|
| Web/WASM | `net8.0-browserwasm` | Browser DevTools | Static hosting / Azure SWA | No filesystem access, AOT recommended, limited threading |
| iOS | `net8.0-ios` | Xcode / VS Code / Rider | App Store / TestFlight | Provisioning profiles, entitlements, no JIT |
| Android | `net8.0-android` | Android SDK / Emulator | Play Store / APK sideload | SDK version targeting, permissions |
| macOS (Catalyst) | `net8.0-maccatalyst` | Xcode | Mac App Store / notarization | Sandbox restrictions, entitlements |
| Windows | `net8.0-windows10.0.19041` | Visual Studio | MSIX / Windows Store | WinAppSDK version alignment |
| Linux | `net8.0-desktop` | Skia/GTK host | AppImage / Flatpak / Snap | GTK dependencies, Skia rendering |
| Embedded | `net8.0-desktop` | Skia/Framebuffer | Direct deployment | No windowing system, headless rendering |

**TFM note:** Use version-agnostic globs (`net*-ios`, `net*-android`) when detecting platform targets programmatically to avoid false negatives on older or newer TFMs.


## Web/WASM

### Project Setup

```bash
# Run the WASM target
dotnet run -f net8.0-browserwasm --project MyApp/MyApp.csproj
```

The WASM target renders XAML controls in the browser. The renderer depends on project configuration: Skia (canvas/WebGL) or native HTML mapping. The app loads via a JavaScript bootstrap (`uno-bootstrap.js`) that initializes the .NET WASM runtime.

### Debugging

- **Browser DevTools:** Use F12 in Chrome/Edge to inspect DOM, network, console output
- **.NET debugging:** Visual Studio and VS Code support debugging the .NET WASM runtime via browser CDP
- **Uno DevServer:** `dotnet run` starts a development server with live reload support
- **Console logging:** `ILogger` output appears in the browser console

### Packaging/Distribution

```bash
# Publish for production
dotnet publish -f net8.0-browserwasm -c Release --output ./publish

# Output is a static site (HTML/JS/WASM)
# Deploy to: Azure Static Web Apps, GitHub Pages, Netlify, any static host
```

Published output is a self-contained static site. No server-side runtime required.

### Platform Gotchas

- **No filesystem access:** Use browser storage APIs (IndexedDB, localStorage) via JS interop or Uno.Storage
- **Threading limitations:** Web Workers provide limited multi-threading; `Task.Run` may not parallelize on WASM
- **CORS restrictions:** HTTP requests from WASM are subject to browser CORS policy
- **Initial load time:** The .NET WASM runtime and assemblies must download before the app is usable. Use assembly trimming to reduce download size. AOT improves runtime execution speed but increases artifact size
- **Deep linking:** Configure URL routing in the Uno Navigation Extensions for browser URL bar navigation

### AOT/Trimming

**Trimming** reduces download size by removing unused code. **AOT** pre-compiles IL to WebAssembly, improving runtime execution speed but increasing artifact size. Use both together and measure the tradeoffs for your app.

```xml
<PropertyGroup Condition="'$(TargetFramework)' == 'net8.0-browserwasm'">
  <WasmShellMonoRuntimeExecutionMode>InterpreterAndAOT</WasmShellMonoRuntimeExecutionMode>
  <RunAOTCompilation>true</RunAOTCompilation>
</PropertyGroup>
```

**Trimming is critical for WASM.** Untrimmed apps can exceed 30MB. With trimming, typical apps are 5-15MB. AOT adds to the artifact size but eliminates interpreter overhead at runtime -- profile both download time and execution speed in target conditions.

For Uno-specific AOT gotchas (linker descriptors, Uno source generators), see the AOT section. For general WASM AOT patterns, see [skill:dotnet-tooling].

### Behavior Differences

- **Navigation:** URL-based deep linking works natively; route maps should define URL patterns
- **Authentication:** OAuth flows use browser redirects (popup or redirect); no native browser available. Token storage uses browser secure storage
- **Debugging:** Full .NET debugger available via CDP; breakpoints work in Visual Studio/VS Code
- **File pickers:** Use browser file input APIs; `FileOpenPicker` maps to `<input type="file">`


## iOS

### Project Setup

```bash
# Build for iOS simulator
dotnet build -f net8.0-ios

# Run on simulator
dotnet run -f net8.0-ios
```

Requires Xcode installed on macOS. The renderer (Skia or native) depends on project configuration and Uno version.

### Debugging

- **Visual Studio (Pair to Mac) / VS Code + C# Dev Kit / Rider:** Attach to iOS simulator or device
- **Xcode Instruments:** Profile CPU, memory, and energy usage
- **Hot Reload:** Supported via `DOTNET_MODIFIABLE_ASSEMBLIES=debug`

### Packaging/Distribution

```bash
# Publish for App Store
dotnet publish -f net8.0-ios -c Release \
  /p:CodesignKey="Apple Distribution: MyCompany" \
  /p:CodesignProvision="MyApp Distribution Profile"
```

Distribution channels: App Store (requires Apple Developer account), TestFlight (beta testing), Ad Hoc (enterprise).

**Required:** Provisioning profiles, signing certificates, entitlements file for capabilities (push notifications, HealthKit, etc.).

### Platform Gotchas

- **No JIT compilation:** iOS prohibits JIT. All code must be AOT-compiled or interpreted. The .NET runtime uses the Mono interpreter by default
- **Provisioning profiles:** Must match bundle ID, team ID, and entitlements. Expired profiles cause cryptic build failures
- **Background execution:** iOS restricts background processing. Use `BGTaskScheduler` for background work
- **App Transport Security (ATS):** HTTPS required by default; HTTP requires an `NSAppTransportSecurity` exception in `Info.plist`
- **Memory pressure:** iOS aggressively kills background apps. Handle `MemoryWarning` events

### AOT/Trimming

iOS requires AOT by default (no JIT). The .NET runtime compiles to native ARM64 code.

```xml
<PropertyGroup Condition="$([MSBuild]::GetTargetPlatformIdentifier('$(TargetFramework)')) == 'ios'">
  <PublishTrimmed>true</PublishTrimmed>
  <TrimMode>link</TrimMode>
</PropertyGroup>
```

**Gotcha:** Reflection-heavy code fails silently on iOS. Test with trimming enabled during development, not just for release builds.

### Behavior Differences

- **Navigation:** Gesture-based back navigation (swipe from left edge) is automatic with Uno Navigation
- **Authentication:** Uses `ASWebAuthenticationSession` for OAuth; biometric auth via `LocalAuthentication` framework
- **Debugging:** Simulator is fast; device debugging requires USB connection and provisioning. Remote debugging with Hot Reload supported


## Android

### Project Setup

```bash
# Build for Android
dotnet build -f net8.0-android

# Deploy to connected device or emulator
dotnet run -f net8.0-android
```

Requires Android SDK (installed via `dotnet workload install android` or Android Studio).

### Debugging

- **Android Emulator:** Use Android Studio's emulator or command-line `emulator`
- **ADB (Android Debug Bridge):** `adb logcat` for runtime logs, `adb devices` to verify connections
- **Visual Studio / VS Code:** Full debugging with breakpoints on emulator or device

### Packaging/Distribution

```bash
# Publish signed APK/AAB (use env vars or CI secrets for passwords — never hardcode)
dotnet publish -f net8.0-android -c Release \
  /p:AndroidKeyStore=true \
  /p:AndroidSigningKeyStore=mykey.keystore \
  /p:AndroidSigningStorePass="$ANDROID_KEYSTORE_PASS" \
  /p:AndroidSigningKeyAlias=myalias \
  /p:AndroidSigningKeyPass="$ANDROID_KEY_PASS"
```

Google Play requires Android App Bundle (AAB) format. Sideloading uses APK.

### Platform Gotchas

- **SDK version targeting:** `<SupportedOSPlatformVersion>` controls minimum API level. Target API 34+ for Google Play compliance
- **Runtime permissions:** Dangerous permissions (camera, location, storage) require runtime requests. Check and request in code, not just manifest
- **Activity lifecycle:** Android destroys activities on rotation by default. Uno handles this, but custom native code must be lifecycle-aware
- **ProGuard/R8:** Code shrinking may remove reflection targets. Use `@Keep` annotations or linker configuration for native interop types

### AOT/Trimming

```xml
<PropertyGroup Condition="$([MSBuild]::GetTargetPlatformIdentifier('$(TargetFramework)')) == 'android'">
  <PublishTrimmed>true</PublishTrimmed>
  <RunAOTCompilation>true</RunAOTCompilation>
</PropertyGroup>
```

AOT on Android improves startup time. Unlike iOS, JIT is available as fallback for untrimmed code paths.

### Behavior Differences

- **Navigation:** Hardware/software back button triggers Uno navigation back. `BackRequested` event fires automatically
- **Authentication:** Uses `CustomTabs` (Chrome) for OAuth; biometric auth via `AndroidX.Biometric`
- **Debugging:** Emulator is slower than iOS Simulator but supports more API levels. Use hardware acceleration (HAXM/KVM) for performance


## macOS (Catalyst)

### Project Setup

```bash
# Build for macOS
dotnet build -f net8.0-maccatalyst

# Run on macOS
dotnet run -f net8.0-maccatalyst
```

Uses Mac Catalyst (iOS APIs adapted for macOS). Requires Xcode on macOS.

### Debugging

- **Visual Studio (Pair to Mac) / VS Code + C# Dev Kit / Rider:** Native macOS debugging
- **Xcode Instruments:** Profile performance and memory
- **Console.app:** View system logs for the app process

### Packaging/Distribution

```bash
# Publish for distribution
dotnet publish -f net8.0-maccatalyst -c Release \
  /p:CodesignKey="Developer ID Application: MyCompany" \
  /p:CodesignProvision="MyApp Mac Profile"
```

Distribution channels: Mac App Store, direct download with notarization, enterprise deployment.

**Notarization required:** macOS Gatekeeper requires notarized apps for distribution outside the App Store. Use `xcrun notarytool` to submit.

### Platform Gotchas

- **Sandbox restrictions:** Mac App Store apps run in a sandbox. File access requires entitlements and user grants
- **Catalyst limitations:** Not all iOS APIs translate to macOS. Check `SupportedOSPlatform` attributes
- **Menu bar:** macOS expects a proper menu bar. Uno provides default menus; customize via platform-specific code
- **Window management:** macOS apps support multiple windows. Uno's single-window model may need adaptation for multi-window scenarios

### AOT/Trimming

Same profile as iOS (AOT by default for Catalyst). Trimming recommended for distribution builds.

### Behavior Differences

- **Navigation:** No swipe-back gesture; relies on toolbar back button or keyboard shortcuts (Cmd+[)
- **Authentication:** Uses `ASWebAuthenticationSession` (shared with iOS); supports Touch ID via Secure Enclave
- **Debugging:** Native macOS process; standard .NET debugging tools work. No simulator -- runs as native app


## Windows

### Project Setup

```bash
# Build for Windows
dotnet build -f net8.0-windows10.0.19041

# Run on Windows
dotnet run -f net8.0-windows10.0.19041
```

The Windows target can use either the Skia renderer or native WinAppSDK/WinUI 3 rendering.

### Debugging

- **Visual Studio:** Full debugging with XAML Hot Reload, Live Visual Tree, Live Property Explorer
- **WinUI diagnostics:** Built-in diagnostic overlay for layout inspection

### Packaging/Distribution

```bash
# Package as MSIX
dotnet publish -f net8.0-windows10.0.19041 -c Release \
  /p:PackageOutputPath=./packages
```

Distribution: Microsoft Store (MSIX), sideloading (MSIX with certificate), ClickOnce, or direct EXE.

### Platform Gotchas

- **WinAppSDK version alignment:** The Windows TFM version must match the minimum Windows version. `10.0.19041` = Windows 10 2004+
- **UAC and elevation:** Apps cannot self-elevate. Design for standard user permissions
- **Windows-specific APIs:** `Windows.Storage`, `Windows.Networking` APIs are available only on Windows target. Use conditional compilation or Uno abstractions
- **MSIX signing:** MSIX packages must be signed for installation. Use a code signing certificate for distribution

### AOT/Trimming

```xml
<PropertyGroup Condition="$([MSBuild]::GetTargetPlatformIdentifier('$(TargetFramework)')) == 'windows'">
  <PublishTrimmed>true</PublishTrimmed>
  <PublishAot>true</PublishAot>
</PropertyGroup>
```

Windows supports both JIT and AOT. AOT produces a single native EXE with faster startup.

### Behavior Differences

- **Navigation:** Standard Windows navigation (Alt+Left for back, title bar back button)
- **Authentication:** Uses system browser or WAM (Web Account Manager) for SSO with Microsoft accounts
- **Debugging:** Richest debugging experience with Visual Studio Live Visual Tree and XAML Hot Reload


## Linux (Skia/GTK)

### Project Setup

```bash
# Build for Linux desktop
dotnet build -f net8.0-desktop

# Run on Linux
dotnet run -f net8.0-desktop
```

The Linux target uses the Skia renderer with a GTK host window. All XAML rendering is done by Skia -- GTK provides only the window and input handling.

### Debugging

- **VS Code with C# Dev Kit:** Remote debugging on Linux
- **JetBrains Rider:** Full Linux debugging support
- **Console logging:** `dotnet run` outputs logs to terminal

### Packaging/Distribution

```bash
# Publish self-contained for Linux
dotnet publish -f net8.0-desktop -c Release \
  --self-contained \
  -r linux-x64

# Package as AppImage, Flatpak, or Snap
```

Distribution: AppImage (portable, no install), Flatpak (sandboxed), Snap (Ubuntu Store), DEB/RPM packages.

### Platform Gotchas

- **GTK dependencies:** The app requires GTK3 libraries at runtime. Package or document the dependency: `libgtk-3-0`, `libskia*`
- **Skia rendering:** All rendering is Skia-based. Native GTK widgets are not used. This ensures pixel-perfect cross-platform rendering but means the app does not follow the host GTK theme
- **Font rendering:** Ensure fonts are available on the target system. Embed fonts in the app or declare font dependencies
- **Display scaling:** HiDPI support works via Skia; test with `GDK_SCALE=2` environment variable

### AOT/Trimming

```xml
<PropertyGroup Condition="'$(TargetFramework)' == 'net8.0-desktop'">
  <PublishTrimmed>true</PublishTrimmed>
  <PublishAot>true</PublishAot>
</PropertyGroup>
```

AOT on Linux produces a native binary. Self-contained deployment avoids requiring a system-wide .NET runtime.

### Behavior Differences

- **Navigation:** Keyboard-driven (Alt+Left for back). No gesture-based navigation
- **Authentication:** Uses system browser for OAuth flows. No platform-specific auth APIs
- **Debugging:** Standard .NET debugging. No platform-specific debugger tools


## Embedded (Skia/Framebuffer)

### Project Setup

The Embedded target uses the Skia renderer with a framebuffer backend, enabling headless or kiosk-style rendering without a windowing system.

```bash
# Build for embedded (same TFM as desktop)
dotnet build -f net8.0-desktop -r linux-arm64

# Run directly on embedded device
dotnet run -f net8.0-desktop
```

The embedded target shares the `net8.0-desktop` TFM with Linux desktop. Platform-specific configuration selects the framebuffer backend.

```csharp
// Program.cs -- framebuffer host configuration
public static void Main(string[] args)
{
    SkiaHostBuilder.Create()
        .UseFrameBuffer()  // Use framebuffer instead of GTK
        .App(() => new App())
        .Build()
        .Run();
}
```

### Debugging

- **SSH remote debugging:** Use VS Code Remote or `dotnet-trace` for remote profiling
- **Serial console:** Redirect logs to serial output for headless debugging
- **Remote logging:** Configure Serilog with network sink for remote log aggregation

### Packaging/Distribution

```bash
# Publish self-contained for ARM64
dotnet publish -f net8.0-desktop -c Release \
  --self-contained \
  -r linux-arm64

# Deploy binary directly to device filesystem
scp -r ./publish/* pi@device:/opt/myapp/
```

Direct deployment to device filesystem. No app store or package manager.

### Platform Gotchas

- **No windowing system:** No X11/Wayland. The app renders directly to the Linux framebuffer (`/dev/fb0`)
- **Input handling:** Touch input via Linux input events (`/dev/input/event*`). No mouse cursor by default
- **Limited resources:** Embedded devices often have constrained RAM and CPU. Profile memory usage carefully
- **No browser:** OAuth flows that require a browser are not available. Use device-code flow or pre-provisioned tokens
- **Display resolution:** Must match the framebuffer resolution. Set via kernel boot parameters or `fbset`

### AOT/Trimming

**AOT is strongly recommended for embedded** due to limited resources and startup time requirements.

```xml
<PropertyGroup Condition="'$(RuntimeIdentifier)' == 'linux-arm64'">
  <PublishTrimmed>true</PublishTrimmed>
  <PublishAot>true</PublishAot>
  <InvariantGlobalization>true</InvariantGlobalization>
</PropertyGroup>
```

`InvariantGlobalization` reduces binary size by removing ICU data (~28MB). Only use if the app does not need locale-specific formatting.

### Behavior Differences

- **Navigation:** Touch or hardware button only. No keyboard shortcuts or gesture bars
- **Authentication:** Device-code flow or pre-provisioned credentials. No browser-based OAuth
- **Debugging:** Remote only. No local IDE. Use SSH debugging or remote logging


## Cross-Target Behavior Differences

### Navigation

| Target | Back Navigation | Deep Linking | Gesture Navigation |
|--------|----------------|--------------|-------------------|
| Web/WASM | Browser back button / Alt+Left | URL-based routing | None |
| iOS | Swipe from left edge | URL schemes / Universal Links | Full gesture support |
| Android | Hardware/software back button | Intent filters / App Links | System back gesture (Android 13+) |
| macOS | Cmd+[ / toolbar back | URL schemes | None |
| Windows | Alt+Left / title bar back | Protocol activation | None |
| Linux | Alt+Left / keyboard | None | None |
| Embedded | Hardware button only | None | Touch only |

### Authentication

| Target | OAuth Flow | Token Storage | Biometric |
|--------|-----------|---------------|-----------|
| Web/WASM | Browser redirect/popup | Browser secure storage | WebAuthn (limited) |
| iOS | `ASWebAuthenticationSession` | Keychain | Touch ID / Face ID |
| Android | Chrome Custom Tabs | Android Keystore | BiometricPrompt |
| macOS | `ASWebAuthenticationSession` | Keychain | Touch ID |
| Windows | System browser / WAM | Credential Manager | Windows Hello |
| Linux | System browser | Secret Service API | None |
| Embedded | Device-code flow | File-based (encrypt) | None |

### Debugging Tools

| Target | IDE Debugger | Hot Reload | Profiling |
|--------|-------------|-----------|-----------|
| Web/WASM | VS / VS Code (CDP) | Yes | Browser DevTools |
| iOS | VS (Pair to Mac) / VS Code / Rider | Yes | Xcode Instruments |
| Android | VS / VS Code | Yes | Android Profiler |
| macOS | VS (Pair to Mac) / VS Code / Rider | Yes | Xcode Instruments |
| Windows | Visual Studio | Yes (+ Live Visual Tree) | VS Diagnostic Tools |
| Linux | VS Code / Rider | Yes | dotnet-counters / dotnet-trace |
| Embedded | VS Code Remote | Yes (SSH) | dotnet-trace (remote) |


## Agent Gotchas

1. **Do not hardcode TFM versions in detection logic.** Use version-agnostic globs (`net*-ios`, `net*-android`) to handle both .NET 8 and future .NET versions.
2. **Do not assume all targets share the same debugging workflow.** iOS requires provisioning; Android requires ADB; WASM uses browser DevTools. Each target has distinct tooling.
3. **Do not use JIT-dependent patterns on iOS.** iOS prohibits JIT compilation. Code that uses `Reflection.Emit`, `Expression.Compile()`, or dynamic assembly loading will fail at runtime.
4. **Do not forget platform-specific permissions.** Android runtime permissions, iOS entitlements, macOS sandbox permissions, and WASM CORS policy are all different and must be handled per-target.
5. **Do not deploy untrimmed WASM apps.** Untrimmed WASM bundles exceed 30MB. Always enable trimming and consider AOT for production WASM deployments.
6. **Do not assume file system access on all targets.** WASM has no filesystem; iOS/macOS have sandbox restrictions; embedded may have read-only storage. Use Uno Storage abstractions.
7. **Do not use the same authentication flow for all targets.** WASM uses browser redirects, mobile uses native auth sessions, embedded uses device-code flow. Auth must be configured per-target.


## Prerequisites

- .NET 8.0+ with platform workloads: `dotnet workload install ios android maccatalyst wasm-tools`
- Platform SDKs: Xcode (iOS/macOS), Android SDK (Android), GTK3 (Linux)
- Uno Platform 5.x+


## References

- [Uno Platform Getting Started](https://platform.uno/docs/articles/get-started.html)
- [Uno Platform Targets](https://platform.uno/docs/articles/getting-started/requirements.html)
- [WASM Deployment](https://platform.uno/docs/articles/features/using-il-linker-webassembly.html)
- [iOS Deployment](https://learn.microsoft.com/en-us/dotnet/maui/ios/deployment/)
- [Android Deployment](https://learn.microsoft.com/en-us/dotnet/maui/android/deployment/)
- [Linux with Skia/GTK](https://platform.uno/docs/articles/get-started-with-linux.html)
