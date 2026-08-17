# Trimming

Trim-safe development for .NET 8+ applications and libraries: trimming annotations (`[RequiresUnreferencedCode]`, `[DynamicallyAccessedMembers]`, `[DynamicDependency]`), ILLink descriptor XML for type preservation, `TrimmerSingleWarn` for granular diagnostics, testing trimmed output, fixing IL2xxx/IL3xxx warnings, and library authoring with `IsTrimmable`.

**Version assumptions:** .NET 8.0+ baseline. Trimming shipped in .NET 6, but .NET 8 provides the most complete annotation surface and analyzer coverage. .NET 9 improved warning accuracy and library compat.

## MSBuild Properties: Apps vs Libraries

Apps and libraries use different MSBuild properties for trimming. This distinction is critical -- using the wrong property causes subtle issues.

### For Applications

```xml
<PropertyGroup>
  <!-- Enable trimming on publish -->
  <PublishTrimmed>true</PublishTrimmed>

  <!-- Enable trim analyzer during development -->
  <EnableTrimAnalyzer>true</EnableTrimAnalyzer>

  <!-- Optional: also enable AOT analyzer if targeting AOT -->
  <EnableAotAnalyzer>true</EnableAotAnalyzer>
</PropertyGroup>
```

`PublishTrimmed` tells the linker to remove unreachable code when publishing. `EnableTrimAnalyzer` enables Roslyn analyzers that warn about trim-unsafe patterns during development.

### For Libraries

```xml
<PropertyGroup>
  <!-- Declare the library is trim-safe (auto-enables trim analyzer) -->
  <IsTrimmable>true</IsTrimmable>

  <!-- Declare AOT compatibility (auto-enables AOT analyzer) -->
  <IsAotCompatible>true</IsAotCompatible>
</PropertyGroup>
```

**Key difference:** Libraries do not set `PublishTrimmed` -- they are not published as standalone applications. `IsTrimmable` tells consumers that the library's public API is annotated for trimming safety. Setting `IsTrimmable` automatically enables the trim analyzer for the library project.

| Property | Project Type | Effect |
|----------|-------------|--------|
| `PublishTrimmed` | App | Trims on publish, enables linker |
| `EnableTrimAnalyzer` | App | Enables trim warnings during build |
| `IsTrimmable` | Library | Declares trim-safe, auto-enables analyzer |
| `IsAotCompatible` | Library | Declares AOT-safe, auto-enables AOT analyzer |
| `PublishAot` | App | Enables AOT (implies `PublishTrimmed`) |


## Trimming Annotations

.NET provides attributes to annotate code that interacts with reflection, helping the trimmer understand what to preserve.

### `[RequiresUnreferencedCode]`

Marks a method as unsafe for trimming. The trimmer and analyzer produce IL2026 warnings when this method is called from trim-safe code.

```csharp
[RequiresUnreferencedCode("Uses reflection to discover plugins")]
public IPlugin LoadPlugin(string typeName)
{
    var type = Type.GetType(typeName)
        ?? throw new InvalidOperationException($"Type {typeName} not found");
    return (IPlugin)Activator.CreateInstance(type)!;
}
```

### `[DynamicallyAccessedMembers]`

Tells the trimmer which members of a type are accessed via reflection, so they are preserved:

```csharp
public T CreateInstance<[DynamicallyAccessedMembers(
    DynamicallyAccessedMemberTypes.PublicConstructors)] T>()
    where T : class
    => (T)Activator.CreateInstance(typeof(T))!;

// The trimmer preserves public constructors of T
// because the constraint tells it what's needed
```

### `[DynamicDependency]`

Explicitly preserves a specific member from trimming:

```csharp
// Preserve a method that is only called via reflection
[DynamicDependency(nameof(OnConfigChanged), typeof(ConfigWatcher))]
public void StartWatching() { /* reflects on OnConfigChanged */ }

// Preserve all public properties (e.g., for serialization)
[DynamicDependency(DynamicallyAccessedMemberTypes.PublicProperties,
    typeof(LegacyDto))]
public void SerializeLegacy(LegacyDto dto) { /* ... */ }
```

### `[UnconditionalSuppressMessage]`

Suppresses a specific trim warning when you have verified the code is safe despite the analyzer's concern:

```csharp
[UnconditionalSuppressMessage("Trimming",
    "IL2026:RequiresUnreferencedCode",
    Justification = "Type is preserved via ILLink descriptor")]
public void CallLegacyCode() { /* ... */ }
```

Use sparingly -- only when you have verified safety through ILLink descriptors or other means.


## ILLink Descriptors

ILLink descriptor XML files tell the trimmer to preserve types, methods, or entire assemblies. **Do not use legacy RD.xml** -- it is a .NET Native/UWP format that is silently ignored by modern .NET trimming.

### Descriptor Format

```xml
<!-- ILLink.Descriptors.xml -->
<linker>
  <!-- Preserve specific types -->
  <assembly fullname="MyApp">
    <type fullname="MyApp.Models.PluginConfig" preserve="all" />
    <type fullname="MyApp.Services.LegacyAdapter">
      <method name="Initialize" />
      <method name="ProcessRequest" />
    </type>
  </assembly>

  <!-- Preserve an entire third-party assembly -->
  <assembly fullname="LegacyLibrary" preserve="all" />
</linker>
```

### Registration

```xml
<!-- In .csproj -->
<ItemGroup>
  <TrimmerRootDescriptor Include="ILLink.Descriptors.xml" />
</ItemGroup>
```

### Alternative: TrimmerRootAssembly

For entire assemblies that must not be trimmed:

```xml
<ItemGroup>
  <!-- Preserve entire assembly (no trimming at all) -->
  <TrimmerRootAssembly Include="LegacyLibrary" />
</ItemGroup>
```


## TrimmerSingleWarn

By default, the trimmer groups warnings per assembly, showing one summary line. `TrimmerSingleWarn=false` shows every individual warning, which is essential for fixing trim issues.

```bash
# Default: one warning per assembly (hard to debug)
dotnet publish -c Release /p:PublishTrimmed=true
# warning IL2104: Assembly 'MyApp' produced trim warnings

# Detailed: per-occurrence warnings (easier to fix)
dotnet publish -c Release /p:PublishTrimmed=true /p:TrimmerSingleWarn=false
# warning IL2026: MyApp.PluginLoader.LoadPlugin(...) requires unreferenced code
# warning IL2057: Unrecognized value passed to Type.GetType(...)

# Analysis without publishing
dotnet build /p:EnableTrimAnalyzer=true /p:TrimmerSingleWarn=false
```


## IL2xxx/IL3xxx Warning Reference

### Trim Warnings (IL2xxx)

| Code | Meaning | Fix |
|------|---------|-----|
| IL2026 | Method has `[RequiresUnreferencedCode]` | Replace with trim-safe alternative or add descriptor |
| IL2046 | Trim attribute mismatch on override | Match annotation from base type |
| IL2057 | Unrecognized `Type.GetType()` argument | Use compile-time known type or `[DynamicDependency]` |
| IL2060 | `MakeGenericType` call with unknown type | Use concrete generic instantiations |
| IL2062 | Value passed to `[DynamicallyAccessedMembers]` parameter has no annotation | Add `[DynamicallyAccessedMembers]` to the source |
| IL2067 | Parameter mismatch for `[DynamicallyAccessedMembers]` | Ensure annotations flow correctly through call chain |
| IL2070 | `this` parameter of `Type.GetProperties()` etc. not annotated | Add `[DynamicallyAccessedMembers]` constraint |
| IL2072 | Return value of a method not annotated | Annotate return type with `[DynamicallyAccessedMembers]` |
| IL2104 | Assembly produced trim warnings (summary) | Use `TrimmerSingleWarn=false` for details |

### AOT Warnings (IL3xxx)

| Code | Meaning | Fix |
|------|---------|-----|
| IL3050 | Method has `[RequiresDynamicCode]` | Replace with source-gen or static alternative |
| IL3051 | `[RequiresDynamicCode]` annotation mismatch | Match annotation from base type |
| IL3052 | COM interop with dynamic code | Use `[LibraryImport]` with static marshalling |


## Testing Trimmed Output

### Publish and Test

```bash
# Publish with trimming
dotnet publish -c Release -r linux-x64 /p:PublishTrimmed=true

# Run the trimmed binary
./bin/Release/net8.0/linux-x64/publish/MyApp

# Verify functionality:
# 1. All endpoints respond correctly
# 2. JSON deserialization produces populated objects
# 3. DI-resolved services function
# 4. No MissingMethodException or MissingMetadataException
```

### Trim Test in CI

```bash
# CI script: publish trimmed and run integration tests
dotnet publish src/MyApp -c Release -r linux-x64 /p:PublishTrimmed=true -o ./publish

# Run smoke tests against trimmed binary
./publish/MyApp &
APP_PID=$!
sleep 3

curl -f http://localhost:8080/health/live || (kill $APP_PID; exit 1)
curl -f http://localhost:8080/api/products || (kill $APP_PID; exit 1)

kill $APP_PID
```

### Trim Warning CI Gate

```bash
# Fail CI if any trim warnings exist
dotnet build /p:EnableTrimAnalyzer=true /p:TrimmerSingleWarn=false \
  /warnaserror:IL2026,IL2057,IL2060,IL2067,IL2070,IL3050
```


## Library Authoring for Trimming

### Making a Library Trim-Safe

1. Set `<IsTrimmable>true</IsTrimmable>` in the library `.csproj`
2. Annotate all reflection-using APIs with `[RequiresUnreferencedCode]`
3. Add `[DynamicallyAccessedMembers]` to parameters that receive types used reflectively
4. Replace reflection with source generators where possible
5. Test by consuming the library from a trimmed application

```xml
<!-- Library .csproj -->
<PropertyGroup>
  <!-- Auto-enables trim analyzer -->
  <IsTrimmable>true</IsTrimmable>
  <!-- Auto-enables AOT analyzer; implies IsTrimmable in .NET 8+ -->
  <IsAotCompatible>true</IsAotCompatible>
</PropertyGroup>
```

### Annotating Public APIs

```csharp
// Method that uses reflection internally -- annotate honestly
[RequiresUnreferencedCode(
    "Uses reflection to discover plugin types. " +
    "Use RegisterPlugin<T>() for trim-safe plugin registration.")]
public IPlugin LoadPlugin(string typeName) { /* ... */ }

// Trim-safe alternative
public void RegisterPlugin<[DynamicallyAccessedMembers(
    DynamicallyAccessedMemberTypes.PublicConstructors)] T>()
    where T : class, IPlugin
{
    _plugins[typeof(T).Name] = () => (IPlugin)Activator.CreateInstance<T>();
}
```

### Conditional APIs

Provide both reflection-based and trim-safe APIs when possible:

```csharp
public class ServiceRegistry
{
    // Trim-safe: explicit type
    public void Register<[DynamicallyAccessedMembers(
        DynamicallyAccessedMemberTypes.PublicConstructors)] TService,
        TImplementation>()
        where TImplementation : class, TService
    { /* ... */ }

    // Not trim-safe: assembly scanning
    [RequiresUnreferencedCode("Scans assembly for service types")]
    public void RegisterFromAssembly(Assembly assembly)
    { /* ... */ }
}
```


## Agent Gotchas

1. **Do not use `PublishTrimmed` in library projects.** Libraries use `IsTrimmable` to declare they are trim-safe. `PublishTrimmed` is for applications.
2. **Do not use RD.xml for type preservation.** RD.xml is a .NET Native/UWP format that is silently ignored by modern .NET trimming. Use ILLink descriptor XML files instead.
3. **Do not suppress trim warnings without verifying safety.** `[UnconditionalSuppressMessage]` hides warnings but does not fix the underlying issue. Only suppress when you have verified the code is safe (e.g., via ILLink descriptors).
4. **Do not forget `TrimmerSingleWarn=false` when debugging trim issues.** Without it, you get one summary warning per assembly, making it impossible to find the specific problematic call site.
5. **Do not confuse `IsTrimmable` with `PublishTrimmed`.** `IsTrimmable` declares a library is trim-safe and enables the analyzer. `PublishTrimmed` enables the linker in applications. They serve different purposes.
6. **Do not add `[RequiresUnreferencedCode]` to methods that do not use reflection.** The annotation propagates virally -- callers must also be annotated or suppress the warning. Only annotate methods that actually use trim-unsafe reflection.


## References

- [Trim self-contained applications](https://learn.microsoft.com/en-us/dotnet/core/deploying/trimming/trimming-options)
- [Prepare libraries for trimming](https://learn.microsoft.com/en-us/dotnet/core/deploying/trimming/prepare-libraries-for-trimming)
- [Introduction to trim warnings](https://learn.microsoft.com/en-us/dotnet/core/deploying/trimming/fixing-warnings)
- [Trimming annotation attributes](https://learn.microsoft.com/en-us/dotnet/core/deploying/trimming/prepare-libraries-for-trimming#trimming-annotation-attributes)
- [ILLink descriptor format](https://learn.microsoft.com/en-us/dotnet/core/deploying/trimming/trimming-options#descriptor-format)
