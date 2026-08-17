# Roslyn Analyzers

Guidance for **authoring** custom Roslyn analyzers, code fix providers, code refactoring providers, and diagnostic suppressors. Covers project setup, DiagnosticDescriptor conventions, analysis context registration, code fix actions, code refactoring actions, multi-Roslyn-version targeting (3.8 through 4.14), testing with Microsoft.CodeAnalysis.Testing, NuGet packaging, and performance best practices.

For extended code examples (CodeRefactoringProvider implementation, multi-version project structure, test matrix configuration), see the **Extended Examples** section at the end of this file.

## Project Setup

Analyzer projects **must** target `netstandard2.0`. The compiler loads analyzers into various host processes (Visual Studio on .NET Framework/Mono, MSBuild on .NET Core, `dotnet build` CLI) -- targeting `net8.0+` breaks compatibility with hosts that do not run on that runtime.

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>netstandard2.0</TargetFramework>
    <EnforceExtendedAnalyzerRules>true</EnforceExtendedAnalyzerRules>
    <IsRoslynComponent>true</IsRoslynComponent>
    <LangVersion>latest</LangVersion>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="Microsoft.CodeAnalysis.CSharp" Version="4.12.0" PrivateAssets="all" />
    <PackageReference Include="Microsoft.CodeAnalysis.Analyzers" Version="3.11.0" PrivateAssets="all" />
  </ItemGroup>
</Project>
```

- `EnforceExtendedAnalyzerRules` enables RS-series meta-diagnostics that catch common analyzer authoring mistakes.
- `IsRoslynComponent` enables IDE tooling support for the project.
- `LangVersion>latest` lets you write modern C# in the analyzer itself while still targeting `netstandard2.0`.
- All Roslyn SDK packages must use `PrivateAssets="all"` to avoid shipping them as transitive dependencies.

---

## DiagnosticAnalyzer

Every analyzer inherits from `DiagnosticAnalyzer` and must be decorated with `[DiagnosticAnalyzer(LanguageNames.CSharp)]`.

```csharp
[DiagnosticAnalyzer(LanguageNames.CSharp)]
public sealed class NoPublicFieldsAnalyzer : DiagnosticAnalyzer
{
    public const string DiagnosticId = "MYLIB001";

    private static readonly DiagnosticDescriptor Rule = new(
        id: DiagnosticId,
        title: "Public fields should be properties",
        messageFormat: "Field '{0}' is public; use a property instead",
        category: "Design",
        defaultSeverity: DiagnosticSeverity.Warning,
        isEnabledByDefault: true,
        helpLinkUri: $"https://example.com/docs/rules/{DiagnosticId}");

    public override ImmutableArray<DiagnosticDescriptor> SupportedDiagnostics { get; }
        = ImmutableArray.Create(Rule);

    public override void Initialize(AnalysisContext context)
    {
        context.EnableConcurrentExecution();
        context.ConfigureGeneratedCodeAnalysis(GeneratedCodeAnalysisFlags.None);
        context.RegisterSymbolAction(AnalyzeField, SymbolKind.Field);
    }

    private static void AnalyzeField(SymbolAnalysisContext context)
    {
        var field = (IFieldSymbol)context.Symbol;
        if (field.DeclaredAccessibility == Accessibility.Public
            && !field.IsConst && !field.IsReadOnly)
        {
            context.ReportDiagnostic(Diagnostic.Create(Rule, field.Locations[0], field.Name));
        }
    }
}
```

### Analysis Context Registration

| Method | Granularity | Use When |
|--------|-------------|----------|
| `RegisterSyntaxNodeAction` | Individual syntax nodes | Pattern matching on specific syntax |
| `RegisterSymbolAction` | Declared symbols | Checking symbol-level properties |
| `RegisterOperationAction` | IL-level operations | Analyzing semantic operations |
| `RegisterSyntaxTreeAction` | Entire syntax tree | File-level checks |
| `RegisterCompilationStartAction` | Compilation start | Accumulate state across compilation |
| `RegisterCompilationAction` | Full compilation | One-shot analysis after all files |

---

## DiagnosticDescriptor Conventions

### ID Prefix Patterns

| Pattern | Example | When |
|---------|---------|------|
| `PROJ###` | `MYLIB001` | Single-project analyzers |
| `AREA####` | `PERF0001` | Category-scoped analyzers |
| `XX####` | `MA0042` | Short-prefix convention |

Avoid prefixes reserved by the .NET platform: `CA`, `CS`, `RS`, `IDE`, `IL`, `SYSLIB`.

### Severity Selection

| Severity | Use When |
|----------|----------|
| `Error` | Code will not work correctly at runtime |
| `Warning` | Code works but violates best practices |
| `Info` | Suggestion for improvement |
| `Hidden` | IDE-only refactoring suggestion |

Default to `Warning` for most rules. Always provide a non-null `helpLinkUri` (RS1015 enforces this).

---

## CodeFixProvider

Code fix providers offer automated corrections for diagnostics. Key patterns:

- **EquivalenceKey:** Every `CodeAction` must have a unique `equivalenceKey` for FixAll support (RS1010, RS1011)
- **Document vs. Solution modification:** Use `createChangedDocument` for single-file fixes, `createChangedSolution` for cross-file renames
- **Trivia preservation:** Always transfer leading/trailing trivia from replaced nodes
- **FixAllProvider:** Return `WellKnownFixAllProviders.BatchFixer` for batch-applicable fixes

See the **Extended Examples** section below for the complete CodeFixProvider implementation with property conversion.

---

## DiagnosticSuppressor

Conditionally suppresses diagnostics from other analyzers when EditorConfig cannot express the suppression condition. Requires Roslyn 3.8+.

| Approach | Use When |
|----------|----------|
| EditorConfig severity override | Suppression applies unconditionally |
| `[SuppressMessage]` attribute | Suppression applies to a specific location |
| `DiagnosticSuppressor` | Suppression depends on code structure or patterns |

---

## Multi-Roslyn-Version Targeting

### Version Boundaries

| Roslyn Version | Ships With | Key APIs Added |
|---------------|------------|----------------|
| 3.8 | VS 16.8 / .NET 5 SDK | `DiagnosticSuppressor` |
| 4.2 | VS 17.2 / .NET 6 SDK | Improved incremental analysis |
| 4.4 | VS 17.4 / .NET 7 SDK | `ForAttributeWithMetadataName` |
| 4.8 | VS 17.8 / .NET 8 U1 | `CollectionExpression` support |
| 4.14 | VS 17.14 / .NET 10 SDK | Latest API surface |

Use conditional compilation constants (`ROSLYN_X_Y_OR_GREATER`) and version-specific NuGet paths (`analyzers/dotnet/roslyn{version}/cs/`). See the **Extended Examples** section below for the complete multi-version project structure.

---

## Testing Analyzers

Use `Microsoft.CodeAnalysis.Testing` for ergonomic analyzer testing:

```csharp
using Verify = Microsoft.CodeAnalysis.CSharp.Testing.CSharpAnalyzerVerifier<
    NoPublicFieldsAnalyzer,
    Microsoft.CodeAnalysis.Testing.DefaultVerifier>;

public class NoPublicFieldsAnalyzerTests
{
    [Fact]
    public async Task PublicField_ReportsDiagnostic()
    {
        var test = """
            public class MyClass
            {
                public int {|MYLIB001:Value|};
            }
            """;
        await Verify.VerifyAnalyzerAsync(test);
    }
}
```

### Diagnostic Markup Syntax

| Markup | Meaning |
|--------|---------|
| `[|text|]` | Diagnostic expected on `text` (single descriptor) |
| `{|DIAG_ID:text|}` | Diagnostic with specific ID expected |

---

## NuGet Packaging

Analyzers ship as NuGet packages with assemblies in `analyzers/dotnet/cs/`, not `lib/`.

```xml
<PropertyGroup>
  <IncludeBuildOutput>false</IncludeBuildOutput>
  <DevelopmentDependency>true</DevelopmentDependency>
  <SuppressDependenciesWhenPacking>true</SuppressDependenciesWhenPacking>
</PropertyGroup>

<ItemGroup>
  <None Include="$(OutputPath)\$(AssemblyName).dll"
        Pack="true"
        PackagePath="analyzers/dotnet/cs" />
</ItemGroup>
```

---

## Performance Best Practices

- **Resolve types once per compilation** inside `RegisterCompilationStartAction`, not per-node/symbol callbacks
- **Cache `SupportedDiagnostics`** as `ImmutableArray` field, not expression-bodied property
- **Enable concurrent execution** -- always call `context.EnableConcurrentExecution()`
- **Filter early** -- register for the most specific `SyntaxKind` possible
- **Avoid `Compilation.GetSemanticModel()`** -- use the `SemanticModel` from the analysis context (RS1030)

---

## Common Meta-Diagnostics (RS-Series)

| ID | Title | What It Catches |
|----|-------|-----------------|
| RS1001 | Missing `DiagnosticAnalyzerAttribute` | Analyzer class missing attribute |
| RS1008 | Avoid storing per-compilation data | Instance fields with compilation data |
| RS1010 | Create code actions with unique `EquivalenceKey` | Missing equivalence key |
| RS1015 | Provide non-null `helpLinkUri` | Empty help link |
| RS1016 | Code fix providers should provide FixAll support | Missing `GetFixAllProvider()` |
| RS1024 | Symbols should be compared for equality | Using `==` instead of `SymbolEqualityComparer` |
| RS1026 | Enable concurrent execution | Missing `EnableConcurrentExecution()` |
| RS1030 | Do not invoke `Compilation.GetSemanticModel()` | Using wrong semantic model source |
| RS1041 | Compiler extensions should target `netstandard2.0` | Wrong target framework |

---

## References

- [Tutorial: Write your first analyzer and code fix](https://learn.microsoft.com/en-us/dotnet/csharp/roslyn-sdk/tutorials/how-to-write-csharp-analyzer-code-fix)
- [Roslyn SDK overview](https://learn.microsoft.com/en-us/dotnet/csharp/roslyn-sdk/)
- [Microsoft.CodeAnalysis.Testing](https://github.com/dotnet/roslyn-sdk/tree/main/src/Microsoft.CodeAnalysis.Testing)
- [Analyzer NuGet packaging conventions](https://learn.microsoft.com/en-us/nuget/guides/analyzers-conventions)
- [dotnet/roslyn-analyzers (RS diagnostic source)](https://github.com/dotnet/roslyn-analyzers)
- [Meziantou.Analyzer (exemplar project)](https://github.com/meziantou/Meziantou.Analyzer)

---

## Extended Examples

Extended code examples for CodeRefactoringProvider authoring, multi-Roslyn-version targeting, and multi-version test matrix configuration.

---

## CodeRefactoringProvider: Full Extract Interface Example

A complete `CodeRefactoringProvider` that extracts an interface from a class. The provider is offered when the cursor is on a class identifier and the class has at least one public method.

```csharp
using System.Collections.Generic;
using System.Collections.Immutable;
using System.Composition;
using System.Linq;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CodeActions;
using Microsoft.CodeAnalysis.CodeRefactorings;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;

[ExportCodeRefactoringProvider(LanguageNames.CSharp, Name = nameof(ExtractInterfaceRefactoring))]
[Shared]
public sealed class ExtractInterfaceRefactoring : CodeRefactoringProvider
{
    public override async Task ComputeRefactoringsAsync(CodeRefactoringContext context)
    {
        var root = await context.Document
            .GetSyntaxRootAsync(context.CancellationToken)
            .ConfigureAwait(false);

        var node = root?.FindNode(context.Span);
        var classDecl = node?.FirstAncestorOrSelf<ClassDeclarationSyntax>();

        if (classDecl is null)
            return;

        // Only offer when cursor is on the class identifier
        if (!classDecl.Identifier.Span.IntersectsWith(context.Span))
            return;

        var publicMethods = classDecl.Members
            .OfType<MethodDeclarationSyntax>()
            .Where(m => m.Modifiers.Any(SyntaxKind.PublicKeyword))
            .ToList();

        if (publicMethods.Count == 0)
            return;

        context.RegisterRefactoring(
            CodeAction.Create(
                title: $"Extract interface I{classDecl.Identifier.Text}",
                createChangedSolution: ct =>
                    ExtractInterfaceAsync(context.Document, classDecl, publicMethods, ct),
                equivalenceKey: "ExtractInterface"));
    }

    private static async Task<Solution> ExtractInterfaceAsync(
        Document document,
        ClassDeclarationSyntax classDecl,
        List<MethodDeclarationSyntax> methods,
        CancellationToken cancellationToken)
    {
        // Build interface members from public method signatures
        var interfaceMembers = methods.Select(m =>
            SyntaxFactory.MethodDeclaration(m.ReturnType, m.Identifier)
                .WithParameterList(m.ParameterList)
                .WithSemicolonToken(SyntaxFactory.Token(SyntaxKind.SemicolonToken))
                .WithLeadingTrivia(SyntaxFactory.ElasticCarriageReturnLineFeed)
            ).Cast<MemberDeclarationSyntax>();

        var interfaceName = $"I{classDecl.Identifier.Text}";
        var interfaceDecl = SyntaxFactory.InterfaceDeclaration(interfaceName)
            .WithModifiers(SyntaxFactory.TokenList(
                SyntaxFactory.Token(SyntaxKind.PublicKeyword)))
            .WithMembers(SyntaxFactory.List(interfaceMembers));

        // Add interface to the same document after the class
        var root = await document.GetSyntaxRootAsync(cancellationToken)
            .ConfigureAwait(false);
        var newRoot = root!.InsertNodesAfter(classDecl, new[] { interfaceDecl });

        // Add base type to the class
        var updatedClass = newRoot.DescendantNodes()
            .OfType<ClassDeclarationSyntax>()
            .First(c => c.Identifier.Text == classDecl.Identifier.Text);

        var baseList = updatedClass.BaseList ?? SyntaxFactory.BaseList();
        var newBaseList = baseList.AddTypes(
            SyntaxFactory.SimpleBaseType(SyntaxFactory.ParseTypeName(interfaceName)));

        newRoot = newRoot.ReplaceNode(updatedClass,
            updatedClass.WithBaseList(newBaseList));

        return document.WithSyntaxRoot(newRoot).Project.Solution;
    }
}
```

---

## CodeRefactoringProvider Testing

Use `CSharpCodeRefactoringVerifier<T>` to test refactoring providers. Use the framework-agnostic package with `DefaultVerifier` (the framework-specific `.XUnit` suffix packages are obsolete):

```xml
<PropertyGroup>
  <!-- Enable Microsoft.Testing.Platform v2 runner -->
  <UseMicrosoftTestingPlatformRunner>true</UseMicrosoftTestingPlatformRunner>
</PropertyGroup>

<ItemGroup>
  <!-- NuGet: Microsoft.CodeAnalysis.CSharp.CodeRefactoring.Testing (framework-agnostic) -->
  <PackageReference Include="Microsoft.CodeAnalysis.CSharp.CodeRefactoring.Testing" Version="1.1.3" />
  <!-- NuGet: xunit.v3 (xUnit v3 test framework) -->
  <PackageReference Include="xunit.v3" Version="3.2.2" />
</ItemGroup>
```

```csharp
using Microsoft.CodeAnalysis.Testing;
using Verify = Microsoft.CodeAnalysis.CSharp.Testing.CSharpCodeRefactoringVerifier<
    ExtractInterfaceRefactoring,
    Microsoft.CodeAnalysis.Testing.DefaultVerifier>;

public class ExtractInterfaceRefactoringTests
{
    [Fact]
    public async Task ClassWithPublicMethods_OffersRefactoring()
    {
        var test = new Verify.Test
        {
            TestCode = """
                public class [|MyService|]
                {
                    public void DoWork() { }
                    public int Calculate(int x) => x * 2;
                    private void InternalHelper() { }
                }
                """,
            FixedCode = """
                public class MyService : IMyService
                {
                    public void DoWork() { }
                    public int Calculate(int x) => x * 2;
                    private void InternalHelper() { }
                }
                public interface IMyService
                {
                    void DoWork();
                    int Calculate(int x);
                }
                """
        };

        await test.RunAsync();
    }

    [Fact]
    public async Task ClassWithNoPublicMethods_NoRefactoring()
    {
        var test = """
            public class [|MyService|]
            {
                private void InternalHelper() { }
            }
            """;

        // Verify no refactoring is offered (no expected FixedCode)
        var verifyTest = new Verify.Test
        {
            TestCode = test,
            FixedCode = test
        };

        await verifyTest.RunAsync();
    }
}
```

The markup `[|text|]` indicates where the cursor/selection triggers the refactoring. The verifier checks that the refactoring is offered and produces the expected `FixedCode`.

---

## Multi-Roslyn-Version Project Structure

A complete multi-version analyzer solution structure following the Meziantou.Analyzer pattern:

```
MyAnalyzers/
  Directory.Build.props          # Shared properties
  Directory.Build.targets        # Conditional compilation constants
  src/
    MyAnalyzers/
      MyAnalyzers.csproj         # Analyzer project
      MyAnalyzer.cs
    MyAnalyzers.CodeFixes/
      MyAnalyzers.CodeFixes.csproj
      MyCodeFix.cs
  test/
    MyAnalyzers.Tests/
      MyAnalyzers.Tests.csproj   # Test project
      MyAnalyzerTests.cs
  pack/
    MyAnalyzers.Package/
      MyAnalyzers.Package.csproj # Packaging project
```

### Directory.Build.props

```xml
<Project>
  <PropertyGroup>
    <TargetFramework>netstandard2.0</TargetFramework>
    <LangVersion>latest</LangVersion>
    <EnforceExtendedAnalyzerRules>true</EnforceExtendedAnalyzerRules>
    <IsRoslynComponent>true</IsRoslynComponent>
    <RoslynVersion Condition="'$(RoslynVersion)' == ''">3.8</RoslynVersion>
  </PropertyGroup>
</Project>
```

### Directory.Build.targets

```xml
<Project>
  <!-- Roslyn version conditional compilation constants -->
  <PropertyGroup Condition="'$(RoslynVersion)' >= '3.8'">
    <DefineConstants>$(DefineConstants);ROSLYN_3_8;ROSLYN_3_8_OR_GREATER</DefineConstants>
  </PropertyGroup>
  <PropertyGroup Condition="'$(RoslynVersion)' >= '4.2'">
    <DefineConstants>$(DefineConstants);ROSLYN_4_2;ROSLYN_4_2_OR_GREATER</DefineConstants>
  </PropertyGroup>
  <PropertyGroup Condition="'$(RoslynVersion)' >= '4.4'">
    <DefineConstants>$(DefineConstants);ROSLYN_4_4;ROSLYN_4_4_OR_GREATER</DefineConstants>
  </PropertyGroup>
  <PropertyGroup Condition="'$(RoslynVersion)' >= '4.6'">
    <DefineConstants>$(DefineConstants);ROSLYN_4_6;ROSLYN_4_6_OR_GREATER</DefineConstants>
  </PropertyGroup>
  <PropertyGroup Condition="'$(RoslynVersion)' >= '4.8'">
    <DefineConstants>$(DefineConstants);ROSLYN_4_8;ROSLYN_4_8_OR_GREATER</DefineConstants>
  </PropertyGroup>
  <PropertyGroup Condition="'$(RoslynVersion)' >= '4.14'">
    <DefineConstants>$(DefineConstants);ROSLYN_4_14;ROSLYN_4_14_OR_GREATER</DefineConstants>
  </PropertyGroup>
</Project>
```

### CI Multi-Version Test Matrix (GitHub Actions)

Uses xUnit v3 with Microsoft.Testing.Platform v2 (MTP2). Set `UseMicrosoftTestingPlatformRunner` in the test project (see CodeRefactoringProvider Testing above) and parameterize `$(RoslynVersion)`:

```yaml
jobs:
  test:
    strategy:
      matrix:
        roslyn-version: ['3.8', '4.2', '4.4', '4.6', '4.8']
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-dotnet@v4
        with:
          dotnet-version: '10.0.x'
      - name: Test with Roslyn ${{ matrix.roslyn-version }}
        run: >
          dotnet test
          -p:RoslynVersion=${{ matrix.roslyn-version }}
          --logger "trx;LogFileName=results-${{ matrix.roslyn-version }}.trx"
```

### Packaging Project (.csproj)

The packaging project references each version-specific build output and places them in the correct NuGet paths:

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>netstandard2.0</TargetFramework>
    <IncludeBuildOutput>false</IncludeBuildOutput>
    <DevelopmentDependency>true</DevelopmentDependency>
    <SuppressDependenciesWhenPacking>true</SuppressDependenciesWhenPacking>
    <PackageId>MyAnalyzers</PackageId>
  </PropertyGroup>

  <ItemGroup>
    <!-- Fallback: lowest supported Roslyn version -->
    <None Include="..\build\roslyn3.8\MyAnalyzers.dll"
          Pack="true" PackagePath="analyzers/dotnet/cs" />
    <!-- Version-specific overrides -->
    <None Include="..\build\roslyn3.8\MyAnalyzers.dll"
          Pack="true" PackagePath="analyzers/dotnet/roslyn3.8/cs" />
    <None Include="..\build\roslyn4.2\MyAnalyzers.dll"
          Pack="true" PackagePath="analyzers/dotnet/roslyn4.2/cs" />
    <None Include="..\build\roslyn4.4\MyAnalyzers.dll"
          Pack="true" PackagePath="analyzers/dotnet/roslyn4.4/cs" />
  </ItemGroup>

  <ItemGroup>
    <None Include="_._" Pack="true" PackagePath="lib/netstandard2.0" />
  </ItemGroup>
</Project>
```

### Version-Gated API Usage

```csharp
public sealed class MyAdvancedAnalyzer : DiagnosticAnalyzer
{
    public override void Initialize(AnalysisContext context)
    {
        context.EnableConcurrentExecution();
        context.ConfigureGeneratedCodeAnalysis(GeneratedCodeAnalysisFlags.None);

        // Base registration works on all versions
        context.RegisterSymbolAction(AnalyzeSymbol, SymbolKind.Method);

#if ROSLYN_3_8_OR_GREATER
        // DiagnosticSuppressor support (Roslyn 3.8+)
        // Register compilation-level suppression analysis
        context.RegisterCompilationStartAction(compilationCtx =>
        {
            compilationCtx.RegisterSymbolAction(
                AnalyzeForSuppression, SymbolKind.NamedType);
        });
#endif

#if ROSLYN_4_8_OR_GREATER
        // CollectionExpression operation kind available in Roslyn 4.8+
        context.RegisterOperationAction(AnalyzeCollectionExpression,
            OperationKind.CollectionExpression);
#endif
    }

    // ... analysis methods
}
```

### Pack Verification for Multi-Version Packages

```bash
dotnet pack -c Release
# Verify version-specific paths exist
unzip -l ./bin/Release/MyAnalyzers.1.0.0.nupkg | grep 'analyzers/'
# Expected output:
#   analyzers/dotnet/cs/MyAnalyzers.dll
#   analyzers/dotnet/roslyn3.8/cs/MyAnalyzers.dll
#   analyzers/dotnet/roslyn4.2/cs/MyAnalyzers.dll
#   analyzers/dotnet/roslyn4.4/cs/MyAnalyzers.dll
```
