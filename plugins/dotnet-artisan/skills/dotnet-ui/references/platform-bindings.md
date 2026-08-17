# Platform Bindings

Custom native bindings for Android (Java.Interop) and Apple (ObjCRuntime) platforms in .NET MAUI and Uno Platform. Covers when to create custom bindings vs using community packages, binding library project setup, Slim Bindings (.NET 9+), and common patterns for wrapping native SDKs.

For P/Invoke, LibraryImport, and COM interop (ComWrappers), see [skill:dotnet-csharp] `references/native-interop.md`.

## When to Create Custom Bindings

| Scenario | Approach |
|----------|----------|
| Popular SDK (Firebase, Google Maps, Stripe) | Use existing NuGet binding (check [ABI compatibility](https://github.com/ABI-Compatibility)) |
| Internal/proprietary native SDK | Create custom binding |
| SDK with no existing .NET binding | Create custom binding or Slim Binding |
| Simple native API (few methods) | P/Invoke with `[LibraryImport]` (skip binding project) |
| Need only a subset of a large SDK | Slim Binding (.NET 9+) |

## Android: Java.Interop

### How It Works

.NET Android uses **Android Callable Wrappers (ACW)** and **Managed Callable Wrappers (MCW)** to bridge between .NET and Java/Kotlin:

- **MCW** (Java → .NET direction): Generated C# classes that wrap Java types, allowing .NET code to call Java APIs
- **ACW** (NET → Java direction): Generated Java classes that expose .NET types to the Android runtime

### Binding Library Project

```bash
# Create an Android binding library
dotnet new android-bindinglib -o MyNativeSdk.Binding
```

```xml
<!-- MyNativeSdk.Binding.csproj -->
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net10.0-android</TargetFramework>
  </PropertyGroup>
  <ItemGroup>
    <!-- AAR file (Android Archive) — most common -->
    <AndroidLibrary Include="libs/mynativesdk.aar" />

    <!-- Or JAR file -->
    <AndroidLibrary Include="libs/legacy-sdk.jar" />
  </ItemGroup>
</Project>
```

The build generates C# wrapper classes from the Java bytecode in the AAR/JAR.

### Metadata Transforms

The generated bindings often need adjustments. Use `Transforms/Metadata.xml`:

```xml
<!-- Transforms/Metadata.xml -->
<metadata>
  <!-- Rename a class to follow .NET conventions -->
  <attr path="/api/package[@name='com.example.sdk']/class[@name='SDKManager']"
        name="managedName">SdkManager</attr>

  <!-- Remove a problematic type that won't bind correctly -->
  <remove-node path="/api/package[@name='com.example.sdk']/class[@name='InternalHelper']" />

  <!-- Change parameter type -->
  <attr path="/api/package[@name='com.example.sdk']/class[@name='Callback']/method[@name='onResult']/parameter[@name='data']"
        name="managedType">byte[]</attr>

  <!-- Fix enum binding -->
  <attr path="/api/package[@name='com.example.sdk']/class[@name='Status']"
        name="enumFields">true</attr>

  <!-- Change visibility -->
  <attr path="/api/package[@name='com.example.sdk']/class[@name='Config']/method[@name='setDebug']"
        name="visibility">public</attr>
</metadata>
```

### Implementing Java Interfaces in C#

```csharp
using Android.Runtime;

// Implement a Java callback interface
public class MyCallback : Java.Lang.Object, IMyNativeCallback
{
    public void OnSuccess(string result)
    {
        Console.WriteLine($"Native callback: {result}");
    }

    public void OnError(Java.Lang.Throwable error)
    {
        Console.WriteLine($"Native error: {error.Message}");
    }
}

// Register with native SDK
var sdk = new SdkManager();
sdk.Initialize(Android.App.Application.Context, new MyCallback());
```

### Subclassing Java Classes

```csharp
using Android.Runtime;

// Extend a Java class
[Register("com/example/app/CustomView")]
public class CustomView : Android.Views.View
{
    public CustomView(Android.Content.Context context)
        : base(context) { }

    // Override a Java method
    protected override void OnDraw(Android.Graphics.Canvas? canvas)
    {
        base.OnDraw(canvas);
        // Custom drawing
    }
}
```

### Common Binding Issues

| Problem | Fix |
|---------|-----|
| `Java.Lang.NoClassDefFoundError` | AAR dependencies missing — add transitive AARs/JARs |
| Duplicate class errors | Exclude duplicate classes in Metadata.xml with `<remove-node>` |
| Parameter type mismatch | Use Metadata.xml `managedType` to fix types |
| Obfuscated names | Use `<attr name="managedName">` to rename |
| Missing methods after binding | Check if methods use unsupported generics or annotation types |

## Apple: ObjCRuntime

### How It Works

.NET iOS/macOS uses **Objective-C bindings** to bridge between .NET and Apple frameworks:

- **Registrar** maps .NET types to Objective-C classes at build time
- **Selectors** map .NET methods to Objective-C message sends
- **Protocols** map to .NET interfaces

### Binding Library Project

```bash
# Create an iOS binding library
dotnet new ios-bindinglib -o MyNativeSdk.iOS.Binding
```

```xml
<!-- MyNativeSdk.iOS.Binding.csproj -->
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net10.0-ios</TargetFramework>
  </PropertyGroup>
  <ItemGroup>
    <!-- XCFramework (preferred — supports multiple architectures) -->
    <NativeReference Include="MyNativeSdk.xcframework">
      <Kind>Framework</Kind>
      <SmartLink>true</SmartLink>
    </NativeReference>

    <!-- Or static library -->
    <NativeReference Include="libmynativesdk.a">
      <Kind>Static</Kind>
      <ForceLoad>true</ForceLoad>
    </NativeReference>
  </ItemGroup>
</Project>
```

### API Definition

Define the binding in an `ApiDefinition.cs` file:

```csharp
using Foundation;
using ObjCRuntime;

namespace MyNativeSdk
{
    // Bind an Objective-C class
    // @interface MNSManager : NSObject
    [BaseType(typeof(NSObject))]
    interface MNSManager
    {
        // @property (nonatomic, readonly) NSString *version;
        [Export("version")]
        string Version { get; }

        // - (void)initializeWithApiKey:(NSString *)key;
        [Export("initializeWithApiKey:")]
        void Initialize(string apiKey);

        // - (void)fetchDataWithCompletion:(void (^)(NSArray *, NSError *))completion;
        [Export("fetchDataWithCompletion:")]
        [Async] // Generates a Task-returning wrapper
        void FetchData(Action<NSObject[], NSError> completion);

        // + (MNSManager *)sharedInstance;
        [Static]
        [Export("sharedInstance")]
        MNSManager SharedInstance { get; }
    }

    // Bind an Objective-C protocol (→ C# interface)
    // @protocol MNSDelegate <NSObject>
    [Protocol, Model]
    [BaseType(typeof(NSObject))]
    interface MNSDelegate
    {
        // @required - (void)manager:(MNSManager *)manager didReceiveData:(NSData *)data;
        [Abstract]
        [Export("manager:didReceiveData:")]
        void DidReceiveData(MNSManager manager, NSData data);

        // @optional - (void)manager:(MNSManager *)manager didFailWithError:(NSError *)error;
        [Export("manager:didFailWithError:")]
        void DidFailWithError(MNSManager manager, NSError error);
    }
}
```

### Implementing Protocols (Delegates)

```csharp
using Foundation;

// Implement the native delegate pattern
public class MyDelegate : MNSDelegate
{
    public override void DidReceiveData(MNSManager manager, NSData data)
    {
        var bytes = new byte[data.Length];
        System.Runtime.InteropServices.Marshal.Copy(data.Bytes, bytes, 0, (int)data.Length);
        Console.WriteLine($"Received {bytes.Length} bytes");
    }

    public override void DidFailWithError(MNSManager manager, NSError error)
    {
        Console.WriteLine($"Error: {error.LocalizedDescription}");
    }
}

// Usage
var manager = MNSManager.SharedInstance;
manager.Delegate = new MyDelegate();
manager.Initialize("my-api-key");
```

### Key Attributes

| Attribute | Purpose |
|-----------|---------|
| `[BaseType(typeof(NSObject))]` | Maps to Objective-C base class |
| `[Export("selectorName:")]` | Maps method to ObjC selector |
| `[Static]` | Class method (+ prefix in ObjC) |
| `[Protocol]` | ObjC protocol binding |
| `[Model]` | Abstract base for protocol implementation |
| `[Abstract]` | Required protocol method |
| `[Async]` | Generates Task-returning async wrapper |
| `[NullAllowed]` | Parameter/return can be null |
| `[Verify]` | Needs manual verification (generated by Objective Sharpie) |

### Objective Sharpie

Automates API definition generation from Objective-C headers:

```bash
# Generate bindings from a framework
sharpie bind -framework MyNativeSdk.framework -sdk iphoneos17.0

# From headers
sharpie bind -sdk iphoneos17.0 MyNativeSdk/*.h
```

Review the generated `ApiDefinition.cs` — Sharpie marks uncertain bindings with `[Verify]` attributes that must be resolved manually.

## Slim Bindings (.NET 9+)

Slim Bindings let you wrap only the specific native APIs you need, without binding an entire SDK. This is faster, produces less generated code, and avoids binding errors for APIs you don't use.

### Android Slim Binding

```csharp
using Java.Interop;

// Directly call a Java method without a full binding library
var javaClass = JNIEnv.FindClass("com/example/sdk/Analytics");
var methodId = JNIEnv.GetStaticMethodID(javaClass, "trackEvent",
    "(Ljava/lang/String;)V");
JNIEnv.CallStaticVoidMethod(javaClass, methodId,
    new JValue(new Java.Lang.String("button_click")));
```

### Apple Slim Binding

```csharp
using ObjCRuntime;

// Call an Objective-C method directly
var cls = new Class("MNSAnalytics");
var sel = new Selector("trackEvent:");
void_objc_msgSend(cls.Handle, sel.Handle, NSString.CreateNative("button_click"));

[DllImport("/usr/lib/libobjc.dylib", EntryPoint = "objc_msgSend")]
static extern void void_objc_msgSend(IntPtr receiver, IntPtr selector, IntPtr arg);
```

Slim Bindings are best for:
- Calling 1-5 methods from a native SDK
- Wrapping analytics, crash reporting, or feature flag SDKs
- Avoiding binding entire SDKs when you need minimal surface area

## Agent Gotchas

1. **Don't create custom bindings before checking NuGet.** Many popular native SDKs already have community-maintained .NET bindings. Search NuGet first.
2. **Don't forget transitive native dependencies.** An AAR/XCFramework may depend on other native libraries. Missing dependencies cause runtime `NoClassDefFoundError` (Android) or linker errors (iOS).
3. **Don't skip Metadata.xml transforms.** Raw Java-to-C# name mapping produces non-idiomatic names. Always review and apply naming transforms.
4. **Don't use `[Verify]` attributes in production.** Objective Sharpie adds `[Verify]` to mark uncertain bindings. Resolve each one before shipping.
5. **Don't assume Kotlin APIs bind cleanly.** Kotlin-specific features (extension functions, coroutines, sealed classes, default parameters) may require manual Metadata.xml adjustments or Slim Bindings.
6. **Don't bind entire SDKs when you need 2-3 methods.** Use Slim Bindings (.NET 9+) to wrap only what you need — it's faster and avoids binding errors for unused APIs.
