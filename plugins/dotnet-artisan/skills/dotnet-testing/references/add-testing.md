# Add Testing

Add test infrastructure scaffolding to an existing .NET project. Creates test projects with xUnit, configures code coverage with coverlet, and sets up the conventional directory structure.

## Test Project Structure

Follow the convention of mirroring `src/` project names under `tests/`:

```
MyApp/
├── src/
│   ├── MyApp.Core/
│   ├── MyApp.Api/
│   └── MyApp.Infrastructure/
└── tests/
    ├── MyApp.Core.UnitTests/
    ├── MyApp.Api.UnitTests/
    ├── MyApp.Api.IntegrationTests/
    └── Directory.Build.props          # Test-specific build settings
```

Naming conventions:
- `*.UnitTests` -- isolated tests with no external dependencies
- `*.IntegrationTests` -- tests that use real infrastructure (database, HTTP, file system)
- `*.FunctionalTests` -- end-to-end tests through the full application stack

---

## Step 1: Create the Test Project

```bash
# Create xUnit test project
dotnet new xunit -n MyApp.Core.UnitTests -o tests/MyApp.Core.UnitTests

# Add to solution
dotnet sln add tests/MyApp.Core.UnitTests/MyApp.Core.UnitTests.csproj

# Add reference to the project under test
dotnet add tests/MyApp.Core.UnitTests/MyApp.Core.UnitTests.csproj \
  reference src/MyApp.Core/MyApp.Core.csproj
```

### Clean Up Generated Project

Remove properties already defined in `Directory.Build.props`:

```xml
<!-- tests/MyApp.Core.UnitTests/MyApp.Core.UnitTests.csproj -->
<Project Sdk="Microsoft.NET.Sdk">
  <ItemGroup>
    <PackageReference Include="Microsoft.NET.Test.Sdk" />
    <PackageReference Include="xunit.v3" />
    <PackageReference Include="xunit.runner.visualstudio" />
    <PackageReference Include="coverlet.collector" />
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="..\..\src\MyApp.Core\MyApp.Core.csproj" />
  </ItemGroup>
</Project>
```

With CPM, `Version` attributes are managed in `Directory.Packages.props`. Remove them from the generated `.csproj`.

---

## Step 2: Add Test-Specific Build Properties

Create `tests/Directory.Build.props` to customize settings for all test projects:

```xml
<!-- tests/Directory.Build.props -->
<Project>
  <Import Project="$([MSBuild]::GetPathOfFileAbove('Directory.Build.props', '$(MSBuildThisFileDirectory)../'))" />
  <PropertyGroup>
    <IsPackable>false</IsPackable>
    <IsTestProject>true</IsTestProject>
    <!-- Use Microsoft.Testing.Platform v2 runner (requires Microsoft.NET.Test.Sdk 17.13+/18.x) -->
    <UseMicrosoftTestingPlatformRunner>true</UseMicrosoftTestingPlatformRunner>
    <!-- Relax strictness for test projects -->
    <TreatWarningsAsErrors>false</TreatWarningsAsErrors>
  </PropertyGroup>
</Project>
```

This imports the root `Directory.Build.props` (for shared settings like `Nullable`, `ImplicitUsings`, `LangVersion`) and overrides test-specific properties.

---

## Step 3: Register Test Packages in CPM

Add test package versions to `Directory.Packages.props`:

```xml
<!-- In Directory.Packages.props -->
<ItemGroup>
  <!-- Test packages -->
  <PackageVersion Include="Microsoft.NET.Test.Sdk" Version="18.0.1" />
  <PackageVersion Include="xunit.v3" Version="3.2.2" />
  <PackageVersion Include="xunit.runner.visualstudio" Version="3.1.5" />
  <PackageVersion Include="coverlet.collector" Version="8.0.0" />
</ItemGroup>
```

### Optional: Mocking Library

Add a mocking library if the project needs test doubles:

```xml
<PackageVersion Include="NSubstitute" Version="5.3.0" />
```

---

## Step 4: Configure Code Coverage

### Coverlet (Collector Mode)

The `coverlet.collector` package integrates with `dotnet test` via the data collector. No additional configuration is needed for basic coverage.

Generate coverage reports:

```bash
# Collect coverage (Cobertura format by default)
dotnet test --collect:"XPlat Code Coverage"

# Results appear in TestResults/*/coverage.cobertura.xml
```

### Coverage Thresholds

For CI enforcement, use `coverlet.msbuild` for threshold checks:

```xml
<!-- In test csproj or tests/Directory.Build.props -->
<PackageReference Include="coverlet.msbuild" />
```

```bash
# Enforce minimum coverage threshold
dotnet test /p:CollectCoverage=true \
  /p:CoverageOutputFormat=cobertura \
  /p:Threshold=80 \
  /p:ThresholdType=line
```

### Coverage Report Generation

Use `reportgenerator` for human-readable HTML reports:

```bash
# Install globally
dotnet tool install -g dotnet-reportgenerator-globaltool

# Generate HTML report
reportgenerator \
  -reports:"tests/**/coverage.cobertura.xml" \
  -targetdir:coverage-report \
  -reporttypes:Html
```

---

## Step 5: Add EditorConfig Overrides for Tests

In the root `.editorconfig`, add test-specific relaxations:

```ini
[tests/**.cs]
# Allow underscores in test method names (Given_When_Then or Should_Behavior)
dotnet_diagnostic.CA1707.severity = none

# Test parameters are validated by the framework
dotnet_diagnostic.CA1062.severity = none

# ConfigureAwait not relevant in test context
dotnet_diagnostic.CA2007.severity = none

# Tests often have intentionally unused variables for assertions
dotnet_diagnostic.IDE0059.severity = suggestion
```

---

## Step 6: Write a Starter Test

Replace the template-generated `UnitTest1.cs` with a properly structured test:

```csharp
namespace MyApp.Core.UnitTests;

public class SampleServiceTests
{
    [Fact]
    public void Method_Condition_ExpectedResult()
    {
        // Arrange
        var sut = new SampleService();

        // Act
        var result = sut.DoWork();

        // Assert
        Assert.NotNull(result);
    }

    [Theory]
    [InlineData(1, 2, 3)]
    [InlineData(0, 0, 0)]
    [InlineData(-1, 1, 0)]
    public void Add_TwoNumbers_ReturnsSum(int a, int b, int expected)
    {
        var result = Calculator.Add(a, b);
        Assert.Equal(expected, result);
    }
}
```

### Test Naming Convention

Use the pattern `Method_Condition_ExpectedResult`:
- `CreateUser_WithValidInput_ReturnsUser`
- `GetById_WhenNotFound_ReturnsNull`
- `Delete_WithoutPermission_ThrowsUnauthorized`

---

## Verify

After adding test infrastructure, verify everything works:

```bash
# Restore (regenerate lock files if using CPM)
dotnet restore

# Build (verifies project references and analyzer config)
dotnet build --no-restore

# Run tests
dotnet test --no-build

# Run with coverage
dotnet test --collect:"XPlat Code Coverage"
```

---

## Adding Integration Test Projects

For integration tests that need `WebApplicationFactory` or database access:

```bash
dotnet new xunit -n MyApp.Api.IntegrationTests -o tests/MyApp.Api.IntegrationTests
dotnet sln add tests/MyApp.Api.IntegrationTests/MyApp.Api.IntegrationTests.csproj
dotnet add tests/MyApp.Api.IntegrationTests/MyApp.Api.IntegrationTests.csproj \
  reference src/MyApp.Api/MyApp.Api.csproj
```

Add integration test packages to CPM (match the `Microsoft.AspNetCore.Mvc.Testing` major version to the target framework -- e.g., `8.x` for `net8.0`, `9.x` for `net9.0`, `10.x` for `net10.0`):

```xml
<!-- Version must match the project's target framework major version -->
<PackageVersion Include="Microsoft.AspNetCore.Mvc.Testing" Version="10.0.0" />
<PackageVersion Include="Testcontainers" Version="4.3.0" />
```

Integration test depth (WebApplicationFactory patterns, test containers, database fixtures) -- see [skill:dotnet-testing] `references/integration-testing.md`.

---

## What's Next

This skill covers test project scaffolding. For deeper testing guidance:
- **xUnit v3 features and patterns** -- [skill:dotnet-testing] `references/xunit.md`
- **Integration testing with WebApplicationFactory** -- [skill:dotnet-testing] `references/integration-testing.md`
- **UI testing (Blazor, MAUI, Uno)** -- [skill:dotnet-ui] `references/blazor-testing.md`, `references/maui-testing.md`, `references/uno-testing.md`
- **Snapshot testing** -- [skill:dotnet-testing] `references/snapshot-testing.md`
- **Test quality and coverage enforcement** -- [skill:dotnet-testing] `references/test-quality.md`
- **CI test reporting** -- [skill:dotnet-devops] `references/add-ci.md` for starter, `references/gha-build-test.md` and `references/ado-build-test.md` for advanced

---

## References

- [xUnit Documentation](https://xunit.net/)
- [Coverlet](https://github.com/coverlet-coverage/coverlet)
- [.NET Testing Best Practices](https://learn.microsoft.com/en-us/dotnet/core/testing/unit-testing-best-practices)
- [Microsoft.NET.Test.Sdk](https://www.nuget.org/packages/Microsoft.NET.Test.Sdk)
- [ReportGenerator](https://github.com/danielpalme/ReportGenerator)
