# WASM Interop

.NET WebAssembly interop patterns: `[JSImport]`/`[JSExport]` source-generated JavaScript interop (.NET 7+), standalone .NET WASM without Blazor or Uno, the `wasm-experimental` workload, browser API access, and module loading. For Blazor-specific JS interop (`IJSRuntime`), see [skill:dotnet-ui] `references/blazor-components.md`. For Uno Platform WASM targets, see [skill:dotnet-ui] `references/uno-targets.md`.

**Version assumptions:** .NET 7+ for `[JSImport]`/`[JSExport]`. .NET 8+ for improved WASM threading and `wasm-tools` AOT. .NET 9+ for `wasm-experimental` stability improvements.

## JSImport and JSExport (.NET 7+)

`[JSImport]` and `[JSExport]` are source-generated attributes for calling between .NET and JavaScript in WebAssembly. They replace the older `[DllImport("__Internal")]` pattern and Blazor's `IJSRuntime` for direct, low-overhead interop.

### Calling JavaScript from .NET (JSImport)

```csharp
using System.Runtime.InteropServices.JavaScript;

public static partial class BrowserInterop
{
    // Import a global JavaScript function
    [JSImport("console.log")]
    public static partial void ConsoleLog(string message);

    // Import from a specific JS module
    [JSImport("fetchData", "main.js")]
    public static partial Task<string> FetchData(string url);

    // Import with return value
    [JSImport("document.querySelector")]
    public static partial JSObject? QuerySelector(string selector);

    // Import with typed array marshalling
    [JSImport("crypto.getRandomValues")]
    public static partial void GetRandomValues([JSMarshalAs<JSType.MemoryView>] Span<byte> buffer);
}

// Usage
BrowserInterop.ConsoleLog("Hello from .NET WASM");
string data = await BrowserInterop.FetchData("/api/items");
```

### Exposing .NET to JavaScript (JSExport)

```csharp
using System.Runtime.InteropServices.JavaScript;

public static partial class DotNetExports
{
    // Called from JavaScript: globalThis.getDotnetRuntime(0).getAssemblyExports("MyAssembly")
    [JSExport]
    public static string ProcessData(string input)
    {
        return input.ToUpperInvariant();
    }

    [JSExport]
    public static async Task<string> ProcessAsync(string url)
    {
        using var client = new HttpClient();
        return await client.GetStringAsync(url);
    }

    [JSExport]
    public static int Add(int a, int b) => a + b;
}
```

JavaScript side:
```javascript
// Load and call .NET exports
const { getAssemblyExports, getConfig } = await globalThis.getDotnetRuntime(0);
const exports = await getAssemblyExports("MyAssembly.dll");

const result = exports.DotNetExports.ProcessData("hello");
console.log(result); // "HELLO"

const sum = exports.DotNetExports.Add(3, 4);
console.log(sum); // 7
```

### Type Marshalling

| .NET Type | JavaScript Type | Notes |
|-----------|----------------|-------|
| `string` | `string` | UTF-16 ↔ JS string |
| `int`, `long`, `float`, `double` | `number` | Numeric types |
| `bool` | `boolean` | |
| `byte[]` | `Uint8Array` | Copies data |
| `Span<byte>` | `MemoryView` | Zero-copy, requires `[JSMarshalAs]` |
| `Task`, `Task<T>` | `Promise` | Async interop |
| `JSObject` | `object` | Opaque JS object reference |
| `Action`, `Func<>` | `Function` | Callback marshalling |
| `DateTime` | `Date` | |
| `Exception` | `Error` | |

### JSObject for DOM Manipulation

```csharp
using System.Runtime.InteropServices.JavaScript;

public static partial class DomHelper
{
    [JSImport("document.createElement")]
    public static partial JSObject CreateElement(string tagName);

    [JSImport("Node.prototype.appendChild", "main.js")]
    public static partial void AppendChild(JSObject parent, JSObject child);

    [JSImport("globalThis.document.getElementById")]
    public static partial JSObject? GetElementById(string id);
}

// Helper module (main.js) for complex operations
// export function setTextContent(element, text) { element.textContent = text; }
// export function setAttribute(element, name, value) { element.setAttribute(name, value); }

public static partial class DomExtensions
{
    [JSImport("setTextContent", "main.js")]
    public static partial void SetTextContent(JSObject element, string text);

    [JSImport("setAttribute", "main.js")]
    public static partial void SetAttribute(JSObject element, string name, string value);
}

// Usage
var div = DomHelper.CreateElement("div");
DomExtensions.SetTextContent(div, "Hello from .NET");
DomExtensions.SetAttribute(div, "class", "greeting");
var container = DomHelper.GetElementById("app")!;
DomHelper.AppendChild(container, div);
```

### Loading JS Modules

```csharp
using System.Runtime.InteropServices.JavaScript;

// Load a JavaScript ES module before using its exports
await JSHost.ImportAsync("main.js", "./main.js");

// Now JSImport functions from "main.js" are available
var result = await BrowserInterop.FetchData("/api/data");
```

## Standalone .NET WASM (Without Blazor)

You can run .NET in the browser without Blazor or Uno — useful for computational libraries, data processing, or minimal web apps.

### Setup with wasm-experimental

```bash
# Install the workload
dotnet workload install wasm-experimental

# Create a browser WASM project
dotnet new wasmbrowser -o MyWasmApp
```

This creates a minimal project:
```
MyWasmApp/
├── MyWasmApp.csproj
├── Program.cs
├── main.js          # JS bootstrap
└── index.html       # Entry point
```

### Project File

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <RuntimeIdentifier>browser-wasm</RuntimeIdentifier>
    <OutputType>Exe</OutputType>
    <!-- Optional: enable AOT for faster execution -->
    <RunAOTCompilation>true</RunAOTCompilation>
    <!-- Optional: enable threading (experimental) -->
    <WasmEnableThreads>true</WasmEnableThreads>
  </PropertyGroup>
</Project>
```

### Program.cs

```csharp
using System;
using System.Runtime.InteropServices.JavaScript;

Console.WriteLine("Hello from .NET WASM!");

// Export .NET functions for JS consumption
public static partial class MyApp
{
    [JSExport]
    public static string Greet(string name) => $"Hello, {name}!";

    [JSExport]
    public static double Calculate(double a, double b, string op) => op switch
    {
        "+" => a + b,
        "-" => a - b,
        "*" => a * b,
        "/" => b != 0 ? a / b : double.NaN,
        _ => throw new ArgumentException($"Unknown operator: {op}")
    };
}
```

### main.js

```javascript
import { dotnet } from './_framework/dotnet.js';

const { getAssemblyExports, getConfig } = await dotnet.create();
const exports = await getAssemblyExports(getConfig().mainAssemblyName);

// Call .NET from JavaScript
const greeting = exports.MyApp.Greet("World");
document.getElementById("output").textContent = greeting;

const result = exports.MyApp.Calculate(10, 3, "+");
console.log(`10 + 3 = ${result}`);

await dotnet.run();
```

### Run and Publish

```bash
# Development
dotnet run

# Publish (produces static files for any web server)
dotnet publish -c Release

# Output in bin/Release/net10.0/browser-wasm/AppBundle/
# Deploy the AppBundle directory to any static hosting (GitHub Pages, S3, nginx)
```

### Console WASM (Node.js / Deno)

For running .NET WASM outside the browser (server-side JS runtimes):

```bash
dotnet new wasmconsole -o MyConsoleWasm
```

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <RuntimeIdentifier>wasi-wasm</RuntimeIdentifier>
    <OutputType>Exe</OutputType>
  </PropertyGroup>
</Project>
```

## WASM AOT Compilation

AOT compilation converts IL to native WASM code, improving runtime performance at the cost of larger download size.

```xml
<PropertyGroup>
  <!-- Full AOT — all code compiled to WASM -->
  <RunAOTCompilation>true</RunAOTCompilation>
</PropertyGroup>
```

Requires the `wasm-tools` workload:
```bash
dotnet workload install wasm-tools
```

| Mode | Download Size | Startup | Runtime Perf | Build Time |
|------|--------------|---------|-------------|-----------|
| Interpreted (default) | Small (~2 MB) | Fast | Slow | Fast |
| AOT | Large (~10-30 MB) | Slower | Fast | Slow |
| Mixed (AOT hot paths) | Medium | Medium | Good | Medium |

For mixed-mode AOT (only AOT-compile performance-critical assemblies):
```xml
<ItemGroup>
  <WasmAssembliesToAot Include="MyMathLibrary" />
</ItemGroup>
```

## WASM Threading (.NET 8+)

Experimental multi-threading support for browser WASM:

```xml
<PropertyGroup>
  <WasmEnableThreads>true</WasmEnableThreads>
</PropertyGroup>
```

Requirements:
- Browser must support `SharedArrayBuffer` (requires `Cross-Origin-Opener-Policy: same-origin` and `Cross-Origin-Embedder-Policy: require-corp` headers)
- Not all .NET APIs are thread-safe in WASM — test carefully
- Web Workers are used for background threads

## When to Use Standalone WASM

| Scenario | Use Standalone WASM | Use Blazor WASM | Use Uno WASM |
|----------|--------------------|--------------------|-------------|
| Computational library for JS apps | Yes | No | No |
| Minimal UI, mostly DOM manipulation | Yes | Maybe | No |
| Rich interactive SPA | No | Yes | Yes |
| Cross-platform app (also mobile/desktop) | No | No | Yes |
| Existing JS app, add .NET logic | Yes | No | No |
| Team knows Blazor/Razor | No | Yes | No |
| Need .NET UI component model | No | Yes | Yes |

## Agent Gotchas

1. **Don't confuse `[JSImport]` with `IJSRuntime`.** `IJSRuntime` is Blazor-specific and uses JSON serialization. `[JSImport]`/`[JSExport]` are source-generated, lower-overhead, and work without Blazor.
2. **Don't use P/Invoke in WASM.** `[LibraryImport]` and `[DllImport]` do not work in browser WASM. Use `[JSImport]` for JavaScript interop.
3. **Don't forget `await JSHost.ImportAsync()`** before calling `[JSImport]` functions from a named module. Without it, the module isn't loaded and calls fail.
4. **Don't assume threading works in WASM.** `WasmEnableThreads` is experimental and requires specific HTTP headers. Default WASM is single-threaded.
5. **Don't serve WASM files without proper MIME types.** The web server must serve `.wasm` files with `application/wasm` content type and `.dll` files with `application/octet-stream`.
6. **Don't use `JSObject` after disposal.** `JSObject` wraps a GC handle to a JS object. Once disposed, accessing it throws. Use `using` or explicit disposal.
7. **Don't AOT-compile everything for small apps.** AOT significantly increases download size. For small apps, the interpreter is fast enough and downloads much faster.
