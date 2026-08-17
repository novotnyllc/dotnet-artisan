# Library API Compatibility

Binary and source compatibility rules for .NET library authors. Covers which API changes break consumers at the binary level (assembly loading, JIT resolution) versus at the source level (compilation), how to use type forwarders for assembly reorganization without breaking consumers, and how versioning decisions map to SemVer major/minor/patch increments.

**Version assumptions:** .NET 8.0+ baseline. Compatibility rules apply to all .NET versions but examples target modern SDK-style projects.

## Binary Compatibility

Binary compatibility means existing compiled assemblies continue to work at runtime without recompilation. A binary-breaking change causes `TypeLoadException`, `MissingMethodException`, `MissingFieldException`, or `TypeInitializationException` at runtime.

### Safe Changes (Binary Compatible)

| Change | Why Safe |
|--------|----------|
| Add new public type | Existing code never references it |
| Add new public method to non-sealed class | Existing call sites resolve to their original overload |
| Add new overload with different parameter count | Existing binaries bind to the original method token |
| Add optional parameter to existing method | Callers compiled against the old signature have default values embedded in their IL; the runtime resolves the same method token regardless of whether the optional parameter is supplied |
| Widen access modifier (`protected` to `public`) | Existing references remain valid at higher visibility |
| Add non-abstract interface member with default implementation | Existing implementors inherit the default; no `TypeLoadException` |
| Remove `sealed` from class | Removes a restriction; existing code never subclassed it |
| Add new `enum` member | Existing binaries that switch on the enum simply fall through to `default` |

### Breaking Changes (Binary Incompatible)

| Change | Runtime Failure | Example |
|--------|----------------|---------|
| Remove public type | `TypeLoadException` | Delete `public class Widget` |
| Remove public method | `MissingMethodException` | Remove `Widget.Calculate()` |
| Change method return type | `MissingMethodException` | `int Calculate()` to `long Calculate()` |
| Change method parameter types | `MissingMethodException` | `void Process(int id)` to `void Process(long id)` |
| Change field type | `MissingFieldException` | `public int Count` to `public long Count` |
| Reorder struct fields | Memory layout change | Breaks interop and `Unsafe.As<>` consumers |
| Add abstract member to public class | `TypeLoadException` | Existing subclasses lack the implementation |
| Add interface member without default implementation | `TypeLoadException` | Existing implementors lack the member |
| Change `virtual` method to `non-virtual` | `MissingMethodException` for overriders | Overriders compiled expecting virtual dispatch |
| Seal a previously unsealed class | `TypeLoadException` | Existing subclasses cannot load |
| Change namespace of public type | `TypeLoadException` | Unless a type forwarder is added (see below) |
| Remove `virtual` from a method | `MissingMethodException` | Consumers compiled with `callvirt` find no virtual slot |

### Default Interface Members

Default interface members (DIM) added in C# 8 allow adding members to interfaces without breaking existing implementors -- **but only at the binary level**:

```csharp
public interface IWidget
{
    string Name { get; }

    // Binary-safe: existing implementors inherit this default
    string DisplayName => Name.ToUpperInvariant();
}
```

However, if a consumer explicitly casts to the interface and the runtime cannot find the default implementation (older runtime), this fails. All runtimes in the .NET 8.0+ baseline support DIMs.

---

## Source Compatibility

Source compatibility means existing consumer code continues to compile without changes. A source-breaking change causes compiler errors or changes behavior silently (which is worse).

### Common Source-Breaking Changes

| Change | Compiler Impact | Example |
|--------|----------------|---------|
| Add overload causing ambiguity | CS0121 (ambiguous call) | Add `Process(long id)` when `Process(int id)` exists; callers passing `int` literal now have two candidates |
| Add extension method conflicting with instance method | New extension hides or conflicts | Adding `Where()` extension in a namespace the consumer imports |
| Change optional parameter default value | Silent behavior change | `void Log(string level = "info")` to `"debug"` -- recompiled callers get new default |
| Add member to interface (even with DIM) | CS0535 if consumer explicitly implements all members | Consumer using explicit interface implementation must add the new member |
| Remove default value from parameter (make required) | CS7036 (required argument missing) | Callers relying on default value must now pass it explicitly |
| Add required namespace import | CS0246 if consumer does not import | New public types in consumer's namespace collide |
| Change parameter name | Breaks callers using named arguments | `Process(id: 5)` fails if parameter renamed to `identifier` |
| Change `class` to `struct` (or vice versa) | Breaks `new()` constraints, `is null` checks, boxing behavior | Fundamental semantic change |
| Add new namespace that collides with existing type names | CS0104 (ambiguous reference) | Adding `MyLib.Tasks` namespace conflicts with `System.Threading.Tasks` |

### Overload Resolution Pitfalls

Adding overloads is the most common source of source-breaking changes in libraries. The C# compiler picks the "best" overload at compile time, and a new overload can change which method wins:

```csharp
// V1 -- only overload
public void Send(object message) { }

// V2 -- new overload; ALL callers passing string now bind here
public void Send(string message) { }
```

This is **source-breaking** (callers silently rebind) but **binary-compatible** (old compiled code still calls the `object` overload token).

**Mitigation:** When adding overloads to public APIs, prefer parameter types that do not create implicit conversion paths from existing parameter types. Use `[EditorBrowsable(EditorBrowsableState.Never)]` on compatibility shims that must remain for binary compatibility but should not appear in IntelliSense.

### Extension Method Conflicts

Extension methods resolve at compile time based on imported namespaces. Adding a new extension method can shadow an existing instance method or conflict with extensions from other libraries:

```csharp
// Library V1 ships in namespace MyLib.Extensions
public static class StringExtensions
{
    public static string Truncate(this string s, int maxLength) =>
        s.Length <= maxLength ? s : s[..maxLength];
}

// Library V2 adds to SAME namespace -- safe
// Library V2 adds to DIFFERENT namespace -- may conflict
// if consumer imports both namespaces
```

**Mitigation:** Keep extension methods in the same namespace across versions. Document any namespace additions in release notes.

---

## Type Forwarders

Type forwarders allow moving a public type from one assembly to another without breaking existing compiled references. The original assembly contains a forwarding entry that redirects the runtime type resolver to the new location.

### When to Use Type Forwarders

- **Splitting a large assembly** into smaller, focused assemblies
- **Merging assemblies** for packaging simplification
- **Reorganizing namespaces** across assembly boundaries
- **Moving types to a shared assembly** consumed by multiple packages

### Adding Type Forwarders

In the **original assembly** (the one types are moving FROM), add forwarding attributes after moving the types to the new assembly:

```csharp
// In the ORIGINAL assembly's AssemblyInfo.cs or a dedicated TypeForwarders.cs
// This tells the runtime: "Widget now lives in MyLib.Core"
using System.Runtime.CompilerServices;

[assembly: TypeForwardedTo(typeof(MyLib.Core.Widget))]
[assembly: TypeForwardedTo(typeof(MyLib.Core.IWidgetFactory))]
[assembly: TypeForwardedTo(typeof(MyLib.Core.WidgetOptions))]
```

The original assembly must reference the destination assembly so that `typeof()` resolves correctly.

### Receiving Type Forwarders

The **destination assembly** (the one types are moving TO) contains the actual type definitions. No special attributes are needed on the destination side. The `[TypeForwardedFrom]` attribute is optional metadata that records where the type originally lived -- useful for serialization compatibility:

```csharp
// In the DESTINATION assembly -- optional but recommended for
// types that participate in serialization
using System.Runtime.CompilerServices;

namespace MyLib.Core;

[TypeForwardedFrom("MyLib, Version=1.0.0.0, Culture=neutral, PublicKeyToken=null")]
public class Widget
{
    public string Name { get; set; } = string.Empty;
    public decimal Price { get; set; }
}
```

`[TypeForwardedFrom]` is critical for types deserialized by `BinaryFormatter`, `DataContractSerializer`, or any serializer that encodes assembly-qualified type names. Without it, deserialization of data written by older versions will fail with `TypeLoadException`.

### Type Forwarder Chain

Type forwarders can chain: Assembly A forwards to Assembly B, which forwards to Assembly C. The runtime follows the chain. However, keep chains short (ideally one hop) to minimize assembly loading overhead.

### Multi-TFM Type Forwarder Pattern

When restructuring assemblies in a multi-TFM library, the forwarding assembly must target all TFMs that consumers might use. A common pattern:

```xml
<!-- Original assembly (MyLib.csproj) -- now just a forwarding shim -->
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFrameworks>net8.0;netstandard2.0</TargetFrameworks>
  </PropertyGroup>
  <ItemGroup>
    <ProjectReference Include="../MyLib.Core/MyLib.Core.csproj" />
  </ItemGroup>
</Project>
```

See [skill:dotnet-tooling] for multi-TFM packaging mechanics and [skill:dotnet-devops] for NuGet packaging of forwarding shims.

---

## SemVer Impact Summary

Map API changes to Semantic Versioning increments. For full SemVer rules and NuGet versioning strategies, see [skill:dotnet-devops].

| Change Category | SemVer | Reason |
|----------------|--------|--------|
| Remove public type or member | **Major** | Binary-breaking |
| Change method signature (return type, parameters) | **Major** | Binary-breaking |
| Add abstract member to public class | **Major** | Binary-breaking for subclasses |
| Add interface member without DIM | **Major** | Binary-breaking for implementors |
| Add `sealed` to a previously unsealed class | **Major** | Binary-breaking for subclasses |
| Change struct field layout | **Major** | Binary-breaking for interop consumers |
| Change namespace without type forwarder | **Major** | Binary-breaking |
| Mark member `[Obsolete]` (warning or error) | **Minor** | Binary-compatible; signals deprecation |
| Add new public type | **Minor** | Additive, no breaking impact |
| Add overload (may be source-breaking) | **Minor** | Binary-compatible; source impact is accepted at minor |
| Add optional parameter | **Minor** | Binary-compatible; recompilation picks up new default |
| Add DIM to interface | **Minor** | Binary-compatible; additive |
| Change namespace WITH type forwarder | **Minor** | Binary-compatible via forwarding |
| Widen access modifier | **Minor** | Binary-compatible; additive |
| Bug fix with no API change | **Patch** | No public API impact |
| Documentation or metadata-only change | **Patch** | No public API impact |
| Performance improvement with same API | **Patch** | No public API impact |

### Deprecation Lifecycle with `[Obsolete]`

The standard workflow for removing public API members across major versions:

| Release | Action | Effect |
|---------|--------|--------|
| v2.1 (Minor) | Add `[Obsolete("Use Widget.CalculateAsync() instead.")]` | Compiler warning CS0618; existing code compiles and runs |
| v2.3 (Minor) | Change to `[Obsolete("Use Widget.CalculateAsync() instead.", error: true)]` | Compiler error CS0619; existing binaries still run (binary-compatible) |
| v3.0 (Major) | Remove the member entirely | Binary-breaking; consumers must migrate |

```csharp
// v2.1 -- warn consumers
[Obsolete("Use CalculateAsync() instead. This method will be removed in v3.0.")]
public int Calculate() => CalculateAsync().GetAwaiter().GetResult();

// v2.3 -- block new compilation against this member
[Obsolete("Use CalculateAsync() instead. This method will be removed in v3.0.", error: true)]
public int Calculate() => CalculateAsync().GetAwaiter().GetResult();

// v3.0 -- remove the member (Major version bump)
```

Always include the replacement API and the planned removal version in the obsolete message so both humans and agents can migrate proactively.

### Multi-TFM Binary Compatibility

Adding or removing target frameworks affects binary compatibility for consumers:

- **Adding a new TFM** (e.g., adding `net9.0` to an existing `net8.0` package): **Minor** version bump. Existing consumers on `net8.0` are unaffected; new consumers on `net9.0` gain optimized code paths.
- **Removing a TFM** (e.g., dropping `netstandard2.0`): **Major** version bump. Consumers targeting the removed TFM can no longer resolve a compatible assembly.
- **Changing the lowest supported TFM** (e.g., `net6.0` to `net8.0`): **Major** version bump. Consumers on the dropped TFM lose compatibility.

See [skill:dotnet-tooling] for practical guidance on managing TFM additions and removals.

---

## Compatibility Verification

Use `EnablePackageValidation` in your `.csproj` to automatically compare the current build against the previously shipped package and detect binary/source-breaking changes:

```xml
<PropertyGroup>
  <EnablePackageValidation>true</EnablePackageValidation>
  <!-- Compare against the last shipped version -->
  <PackageValidationBaselineVersion>1.2.0</PackageValidationBaselineVersion>
</PropertyGroup>
```

Build output flags breaking changes:

```
error CP0002: Member 'MyLib.Widget.Calculate()' was removed
error CP0006: Cannot change return type of 'MyLib.Widget.GetName()'
```

To suppress known intentional breaks, generate a suppression file:

```bash
dotnet pack /p:GenerateCompatibilitySuppressionFile=true
```

This produces a `CompatibilitySuppressions.xml` file that can be checked in. If unspecified, the SDK reads `CompatibilitySuppressions.xml` from the project directory automatically. To specify explicit suppression files:

```xml
<ItemGroup>
  <ApiCompatSuppressionFile Include="CompatibilitySuppressions.xml" />
</ItemGroup>
```

Note: `ApiCompatSuppressionFile` is an **ItemGroup item**, not a PropertyGroup property. Multiple suppression files can be included.

For deeper API surface tracking with PublicApiAnalyzers and CI enforcement workflows, see [skill:dotnet-api].

---

## Agent Gotchas

1. **Do not assume adding an overload is always safe** -- it is binary-compatible but can be source-breaking due to overload resolution changes. Always check for implicit conversion paths between existing and new parameter types.
2. **Do not remove public members without a major version bump** -- even `[Obsolete]` members must be preserved until the next major version to maintain binary compatibility.
3. **Do not forget type forwarders when moving types between assemblies** -- without `[TypeForwardedTo]`, consumers get `TypeLoadException` at runtime. Always add forwarders in the original assembly.
4. **Do not change `optional` parameter default values in patch releases** -- this silently changes behavior for recompiled consumers while old binaries retain the old default, creating version-dependent behavior divergence.
5. **Do not confuse binary compatibility with source compatibility** -- a change can be binary-safe but source-breaking (new overload) or source-safe but binary-breaking (changing return type from `int` to `long`). Test both.
6. **Do not skip `[TypeForwardedFrom]` on serializable types** -- serializers that encode assembly-qualified type names (DataContractSerializer, legacy BinaryFormatter) will fail to deserialize data written by older versions.
7. **Do not put `ApiCompatSuppressionFile` in a PropertyGroup** -- it is an ItemGroup item (`<ApiCompatSuppressionFile Include="..." />`), not a property. Using PropertyGroup syntax silently does nothing.
8. **Do not remove a TFM from a library package without a major version bump** -- consumers on the removed TFM lose compatibility with no fallback.

---

## Prerequisites

- .NET 8.0+ SDK
- `EnablePackageValidation` MSBuild property for automated compatibility checking
- Understanding of SemVer 2.0 conventions (see [skill:dotnet-devops])
- Familiarity with assembly loading and binding (strong naming concepts)

---

## References

- [Microsoft Learn: Breaking changes](https://learn.microsoft.com/dotnet/core/compatibility/categories)
- [Microsoft Learn: Type forwarding in the CLR](https://learn.microsoft.com/dotnet/framework/app-domains/type-forwarding-in-the-common-language-runtime)
- [Microsoft Learn: EnablePackageValidation](https://learn.microsoft.com/dotnet/fundamentals/apicompat/package-validation/overview)
- [.NET API compatibility analyzer](https://learn.microsoft.com/dotnet/fundamentals/apicompat/overview)
- [SemVer 2.0 Specification](https://semver.org/)
- [Library guidance: Breaking changes](https://learn.microsoft.com/dotnet/standard/library-guidance/breaking-changes)
