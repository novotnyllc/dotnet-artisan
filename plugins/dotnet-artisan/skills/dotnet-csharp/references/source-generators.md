# Source Generators

Guidance for both **creating** and **consuming** Roslyn source generators in .NET. Creating: `IIncrementalGenerator`, syntax providers, semantic analysis, emit patterns, diagnostic reporting, testing with `CSharpGeneratorDriver`. Consuming: `[GeneratedRegex]`, `[LoggerMessage]`, System.Text.Json source generation, `[JsonSerializable]`.

Cross-references: `references/roslyn-analyzers.md` for Roslyn analyzers and code fix providers, `references/modern-patterns.md` for partial properties and related C# features, `references/coding-standards.md` for naming conventions.

---

## Creating Source Generators

### Project Setup

Source generators are shipped as analyzers targeting `netstandard2.0`.

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>netstandard2.0</TargetFramework>
    <EnforceExtendedAnalyzerRules>true</EnforceExtendedAnalyzerRules>
    <IsRoslynComponent>true</IsRoslynComponent>
    <LangVersion>latest</LangVersion>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="Microsoft.CodeAnalysis.Analyzers" Version="3.3.4" PrivateAssets="all" />
    <PackageReference Include="Microsoft.CodeAnalysis.CSharp" Version="4.12.0" PrivateAssets="all" />
  </ItemGroup>
</Project>
```

> **Always target `netstandard2.0`.** Generators load into the compiler process, which requires this TFM for compatibility. Use `LangVersion>latest` to write modern C# in the generator itself.

### `IIncrementalGenerator` (Preferred)

Always use `IIncrementalGenerator` over the legacy `ISourceGenerator`. Incremental generators are cache-aware and only re-run when inputs change, making them significantly faster in IDE scenarios.

```csharp
[Generator]
public sealed class AutoNotifyGenerator : IIncrementalGenerator
{
    public void Initialize(IncrementalGeneratorInitializationContext context)
    {
        // Step 1: Filter syntax nodes to candidate fields
        var fieldDeclarations = context.SyntaxProvider
            .ForAttributeWithMetadataName(
                "MyLib.AutoNotifyAttribute",
                predicate: static (node, _) => node is FieldDeclarationSyntax,
                transform: static (ctx, _) => GetFieldInfo(ctx))
            .Where(static info => info is not null)
            .Select(static (info, _) => info!.Value);

        // Step 2: Group fields by containing type, then emit one file per type
        context.RegisterSourceOutput(fieldDeclarations.Collect(),
            static (spc, fields) => Execute(fields, spc));
    }

    private static FieldInfo? GetFieldInfo(
        GeneratorAttributeSyntaxContext context)
    {
        var fieldSymbol = context.TargetSymbol as IFieldSymbol;
        if (fieldSymbol is null)
            return null;

        var containingType = fieldSymbol.ContainingType;

        // Use fully qualified type name to handle generic and nested types
        var fullTypeName = containingType.ToDisplayString(
            SymbolDisplayFormat.FullyQualifiedFormat
                .WithGlobalNamespaceStyle(SymbolDisplayGlobalNamespaceStyle.Omitted));

        return new FieldInfo(
            fieldSymbol.ContainingNamespace.IsGlobalNamespace
                ? ""
                : fieldSymbol.ContainingNamespace.ToDisplayString(),
            containingType.Name,
            fullTypeName,
            fieldSymbol.Name,
            fieldSymbol.Type.ToDisplayString());
    }

    private static void Execute(
        ImmutableArray<FieldInfo> fields,
        SourceProductionContext context)
    {
        // Group by fully qualified type name to emit one file per class
        foreach (var group in fields.GroupBy(f => f.FullTypeName))
        {
            var first = group.First();
            var ns = first.Namespace;
            var className = first.ClassName;
            var properties = new StringBuilder();

            foreach (var field in group)
            {
                var propertyName = GetPropertyName(field.FieldName);
                properties.AppendLine($$"""
                        public {{field.FieldType}} {{propertyName}}
                        {
                            get => {{field.FieldName}};
                            set
                            {
                                if (!global::System.Collections.Generic.EqualityComparer<{{field.FieldType}}>.Default.Equals({{field.FieldName}}, value))
                                {
                                    {{field.FieldName}} = value;
                                    PropertyChanged?.Invoke(this,
                                        new global::System.ComponentModel.PropertyChangedEventArgs(nameof({{propertyName}})));
                                }
                            }
                        }
                    """);
            }

            // Handle global namespace (no namespace declaration)
            var nsBlock = string.IsNullOrEmpty(ns) ? "" : $"namespace {ns};\n\n";

            var source = $$"""
                // <auto-generated/>
                #nullable enable

                {{nsBlock}}partial class {{className}}
                    : global::System.ComponentModel.INotifyPropertyChanged
                {
                    public event global::System.ComponentModel.PropertyChangedEventHandler? PropertyChanged;

                {{properties}}
                }
                """;

            // Include namespace in hint name to avoid collisions across namespaces
            var hintPrefix = string.IsNullOrEmpty(ns) ? className : $"{ns}.{className}";
            context.AddSource($"{hintPrefix}.AutoNotify.g.cs", source);
        }
    }

    private static string GetPropertyName(string fieldName)
        => fieldName.TrimStart('_') is [var first, .. var rest]
            ? $"{char.ToUpperInvariant(first)}{rest}"
            : fieldName;
}

internal readonly record struct FieldInfo(
    string Namespace,
    string ClassName,
    string FullTypeName,
    string FieldName,
    string FieldType);
```

> **Scope note:** This example targets top-level, non-generic classes for clarity. A production generator should also handle generic type parameters (emitting matching `partial class Foo<T>` declarations) and nested types (emitting nested partial class hierarchies). Report a diagnostic for unsupported shapes rather than emitting invalid code.

### Key Pipeline Design Rules

1. **Filter early** -- Use `ForAttributeWithMetadataName` or `CreateSyntaxProvider` with a tight predicate to minimize work.
2. **Transform to simple data** -- Extract only the data you need (strings, records) in the transform step. Never pass `ISymbol` or `SyntaxNode` through the pipeline (they hold the compilation alive and break caching).
3. **Use value equality** -- Pipeline outputs are compared by value. Use `record struct` or implement `IEquatable<T>` for custom types.
4. **Emit deterministic output** -- Same inputs must produce identical source. Use `// <auto-generated/>` and `#nullable enable` headers.

### Syntax Providers

```csharp
// ForAttributeWithMetadataName -- most common, filters by attribute
var candidates = context.SyntaxProvider.ForAttributeWithMetadataName(
    "MyLib.GenerateMapperAttribute",
    predicate: static (node, _) => node is ClassDeclarationSyntax,
    transform: static (ctx, _) => /* extract info */);

// CreateSyntaxProvider -- general-purpose, any syntax predicate
var candidates = context.SyntaxProvider.CreateSyntaxProvider(
    predicate: static (node, _) => node is MethodDeclarationSyntax m
        && m.Modifiers.Any(SyntaxKind.PartialKeyword),
    transform: static (ctx, _) => /* extract info */);
```

### Diagnostic Reporting

Report errors and warnings through `SourceProductionContext` rather than throwing exceptions. To report location-specific diagnostics, include a `Location` in your pipeline data (captured from the syntax node in the transform step).

```csharp
private static readonly DiagnosticDescriptor InvalidFieldType = new(
    id: "AN001",
    title: "Invalid field type for AutoNotify",
    messageFormat: "Field '{0}' must be a non-pointer type",
    category: "AutoNotify",
    defaultSeverity: DiagnosticSeverity.Error,
    isEnabledByDefault: true);

// In the transform step, capture location:
var location = context.TargetNode.GetLocation();

// In the Execute method, report with location:
context.ReportDiagnostic(Diagnostic.Create(
    InvalidFieldType,
    location,       // captured from syntax node, not from projected data
    fieldName));
```

> **Note:** `Location` is not value-equatable, so including it in your pipeline record breaks incremental caching. A common pattern is to carry it as a separate field that you exclude from equality, or report diagnostics in a `CreateSyntaxProvider` step before projecting to value types.

### Emit Patterns

```csharp
// Prefer raw string literals for templates (C# 11+, in the generator project)
var source = $$"""
    // <auto-generated/>
    #nullable enable

    namespace {{ns}};

    partial class {{className}}
    {
        {{generatedMembers}}
    }
    """;

context.AddSource($"{className}.g.cs", source);
```

**File naming convention:** `{TypeName}.{Feature}.g.cs` -- the `.g.cs` suffix signals generated code and is excluded by many linters.

### Post-Init Output (Static Source)

Use `RegisterPostInitializationOutput` for marker attributes and helper types that do not depend on user code:

```csharp
context.RegisterPostInitializationOutput(static ctx =>
{
    ctx.AddSource("AutoNotifyAttribute.g.cs", """
        // <auto-generated/>
        namespace MyLib;

        [System.AttributeUsage(System.AttributeTargets.Field)]
        internal sealed class AutoNotifyAttribute : System.Attribute { }
        """);
});
```

---

## Testing Source Generators

Use `CSharpGeneratorDriver` to run generators in-memory and verify output.

```csharp
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;

[Fact]
public void Generator_ProducesExpectedOutput()
{
    // Arrange
    var source = """
        using MyLib;

        namespace TestApp;

        public partial class ViewModel
        {
            [AutoNotify]
            private string _name = "";
        }
        """;

    var syntaxTree = CSharpSyntaxTree.ParseText(source);
    var references = AppDomain.CurrentDomain.GetAssemblies()
        .Where(a => !a.IsDynamic && !string.IsNullOrEmpty(a.Location))
        .Select(a => MetadataReference.CreateFromFile(a.Location))
        .Cast<MetadataReference>()
        .ToList();

    var compilation = CSharpCompilation.Create("TestAssembly",
        [syntaxTree],
        references,
        new CSharpCompilationOptions(OutputKind.DynamicallyLinkedLibrary));

    var generator = new AutoNotifyGenerator();

    // Act
    GeneratorDriver driver = CSharpGeneratorDriver.Create(generator);
    driver = driver.RunGeneratorsAndUpdateCompilation(
        compilation, out var outputCompilation, out var diagnostics);

    // Assert
    Assert.Empty(diagnostics.Where(d => d.Severity == DiagnosticSeverity.Error));

    var runResult = driver.GetRunResult();
    Assert.Single(runResult.GeneratedTrees);

    var generatedSource = runResult.GeneratedTrees[0].GetText().ToString();
    Assert.Contains("public string Name", generatedSource);
}
```

### Snapshot Testing (Verify)

For more robust testing, use the [Verify.SourceGenerators](https://github.com/VerifyTests/Verify.SourceGenerators) package to snapshot-test generated output:

```csharp
[Fact]
public Task Generator_SnapshotTest()
{
    var source = """
        using MyLib;
        namespace TestApp;
        public partial class ViewModel
        {
            [AutoNotify]
            private string _name = "";
        }
        """;

    return TestHelper.Verify(source);
}
```

---

## Consuming Built-In Source Generators

### `[GeneratedRegex]` (net7.0+)

Compile-time regex generation. Zero runtime compilation cost, AOT-compatible.

```csharp
public partial class Validators
{
    [GeneratedRegex(@"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$",
        RegexOptions.Compiled | RegexOptions.IgnoreCase)]
    private static partial Regex EmailRegex();

    public static bool IsValidEmail(string email)
        => EmailRegex().IsMatch(email);
}
```

**Key rules:**
- Method must be `static partial` returning `Regex`
- Place on `partial class` (or `partial struct`)
- Replaces `new Regex(...)` with zero allocation at runtime
- Supports all `RegexOptions` except `RegexOptions.Compiled` (which is ignored -- the source generator replaces it)

### `[LoggerMessage]` (net6.0+)

High-performance structured logging with zero-allocation at log-disabled levels.

```csharp
public static partial class LogMessages
{
    [LoggerMessage(Level = LogLevel.Information,
        Message = "Processing order {OrderId} for customer {CustomerId}")]
    public static partial void OrderProcessing(
        this ILogger logger, int orderId, string customerId);

    [LoggerMessage(Level = LogLevel.Error,
        Message = "Failed to process order {OrderId}")]
    public static partial void OrderProcessingFailed(
        this ILogger logger, int orderId, Exception exception);
}

// Usage
logger.OrderProcessing(order.Id, order.CustomerId);
```

**Key rules:**
- Methods must be `static partial` in a `partial class`
- Parameters matching `{Placeholder}` in the message are logged as structured data
- `Exception` parameter is logged automatically (do not include in message template)
- Event IDs are auto-assigned if not specified; specify explicit IDs for stable telemetry

### System.Text.Json Source Generation (net6.0+)

AOT-compatible JSON serialization. Eliminates runtime reflection.

```csharp
[JsonSerializable(typeof(Order))]
[JsonSerializable(typeof(List<Order>))]
[JsonSerializable(typeof(Customer))]
[JsonSourceGenerationOptions(
    PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase,
    DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull)]
public partial class AppJsonContext : JsonSerializerContext;
```

#### Registration in ASP.NET Core

```csharp
builder.Services.ConfigureHttpJsonOptions(options =>
{
    options.SerializerOptions.TypeInfoResolverChain.Insert(0, AppJsonContext.Default);
});

// Or for Minimal APIs
app.MapGet("/orders/{id}", async (int id, IOrderService service) =>
{
    var order = await service.GetByIdAsync(id);
    return order is not null
        ? Results.Ok(order)
        : Results.NotFound();
});
```

#### Manual Serialization

```csharp
// Serialize
var json = JsonSerializer.Serialize(order, AppJsonContext.Default.Order);

// Deserialize
var order = JsonSerializer.Deserialize(json, AppJsonContext.Default.Order);

// With stream
await JsonSerializer.SerializeAsync(stream, orders,
    AppJsonContext.Default.ListOrder);
```

**Key rules:**
- Register all types that need serialization in `[JsonSerializable]` attributes
- Use `TypeInfoResolverChain` (net8.0+) to combine multiple contexts
- Required for Native AOT -- reflection-based serialization is trimmed
- See `references/modern-patterns.md` for related C# features used in generated code

### `[JsonSerializable]` with Polymorphism (net7.0+)

```csharp
[JsonDerivedType(typeof(CreditCardPayment), "credit")]
[JsonDerivedType(typeof(BankTransferPayment), "bank")]
public abstract class Payment
{
    public decimal Amount { get; init; }
}

public class CreditCardPayment : Payment
{
    public required string CardLast4 { get; init; }
}

public class BankTransferPayment : Payment
{
    public required string AccountNumber { get; init; }
}

[JsonSerializable(typeof(Payment))]
public partial class PaymentJsonContext : JsonSerializerContext;
```

---

## Generator Reference: Packaging and Consumption

### Referencing a Generator in a Consuming Project

```xml
<ItemGroup>
  <ProjectReference Include="..\MyGenerator\MyGenerator.csproj"
                    OutputItemType="Analyzer"
                    ReferenceOutputAssembly="false" />
</ItemGroup>
```

### NuGet Package Layout

When shipping a generator as a NuGet package, place the assembly under `analyzers/dotnet/cs/`:

```
MyGenerator.nupkg
  analyzers/
    dotnet/
      cs/
        MyGenerator.dll
  lib/
    netstandard2.0/
      _._   (empty placeholder if no runtime dependency)
```

```xml
<!-- In the generator .csproj -->
<PropertyGroup>
  <IncludeBuildOutput>false</IncludeBuildOutput>
  <DevelopmentDependency>true</DevelopmentDependency>
</PropertyGroup>

<ItemGroup>
  <None Include="$(OutputPath)\$(AssemblyName).dll"
        Pack="true"
        PackagePath="analyzers/dotnet/cs" />
</ItemGroup>
```

---

## Debugging Source Generators

```csharp
// Add to Initialize() for attach-debugger workflow
#if DEBUG
if (!System.Diagnostics.Debugger.IsAttached)
{
    System.Diagnostics.Debugger.Launch();
}
#endif
```

Alternatively, emit generated files to disk for inspection:

```xml
<!-- In the consuming project -->
<PropertyGroup>
  <EmitCompilerGeneratedFiles>true</EmitCompilerGeneratedFiles>
  <CompilerGeneratedFilesOutputPath>Generated</CompilerGeneratedFilesOutputPath>
</PropertyGroup>
```

Add `Generated/` to `.gitignore`.

---

## References

- [Source Generator Cookbook](https://github.com/dotnet/roslyn/blob/main/docs/features/incremental-generators.cookbook.md)
- [Incremental Generators](https://github.com/dotnet/roslyn/blob/main/docs/features/incremental-generators.md)
- [GeneratedRegex source generator](https://learn.microsoft.com/en-us/dotnet/standard/base-types/regular-expression-source-generators)
- [Compile-time logging source generation](https://learn.microsoft.com/en-us/dotnet/core/extensions/logger-message-generator)
- [System.Text.Json source generation](https://learn.microsoft.com/en-us/dotnet/standard/serialization/system-text-json/source-generation)
- [.NET Framework Design Guidelines](https://learn.microsoft.com/en-us/dotnet/standard/design-guidelines/)
