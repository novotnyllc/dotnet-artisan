# Globalization

Culture-aware C# coding patterns: string comparison semantics, culture-sensitive parsing and formatting, time zone handling (IANA and Windows IDs), DateTimeOffset, character processing (Rune, StringInfo), encoding, and globalization analyzer rules. Cross-reference [skill:dotnet-ui] `references/localization.md` for resource files (.resx/.resw), IStringLocalizer, and per-framework UI localization patterns.

**Version assumptions:** .NET 8.0+ baseline. TimeZoneInfo.TryConvertIanaIdToWindowsId available since .NET 6. Rune type since .NET Core 3.0. .NET 9+ features explicitly marked.

## String Comparison

Choosing the wrong `StringComparison` mode causes subtle bugs — security vulnerabilities (case-insensitive comparisons using Turkish locale), sort instability, and dictionary lookup failures.

### When to Use Each Mode

| Mode | Use When | Example |
|------|----------|---------|
| `Ordinal` | Comparing identifiers, keys, paths, protocol tokens, URLs, file names | Dictionary keys, JSON property names, HTTP headers |
| `OrdinalIgnoreCase` | Case-insensitive identifier matching | Config keys, enum parsing, feature flags |
| `CurrentCulture` | Displaying sorted data to the user | UI list sorting, search results |
| `CurrentCultureIgnoreCase` | User-facing case-insensitive search | Search-as-you-type, filter boxes |
| `InvariantCulture` | Persisting culture-independent sorted data | Serialized sorted lists, file formats |

### Rules

```csharp
// CORRECT: Ordinal for programmatic comparison
if (header.Equals("Content-Type", StringComparison.OrdinalIgnoreCase)) { }

// WRONG: Default string.Equals uses Ordinal, but string.Contains/StartsWith/IndexOf
// use CurrentCulture on .NET Framework and Ordinal on .NET Core+.
// Always be explicit to avoid platform-dependent behavior.
if (header.Contains("json", StringComparison.OrdinalIgnoreCase)) { }

// CORRECT: Ordinal for dictionary keys
var lookup = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);

// CORRECT: CurrentCulture for user-visible sorting
Array.Sort(names, StringComparer.CurrentCulture);

// WRONG: Don't use InvariantCulture for user-facing text
// InvariantCulture is a synthetic culture, not a real locale
Array.Sort(names, StringComparer.InvariantCulture); // Don't do this for display
```

### The Turkish-I Problem

Turkish locale maps `i` → `İ` (not `I`) and `I` → `ı` (not `i`). Code that uses `ToUpper()`/`ToLower()` without specifying a culture can break:

```csharp
// WRONG: Breaks in Turkish locale
if (input.ToUpper() == "FILE") { }

// CORRECT: Use ordinal comparison or specify invariant
if (input.Equals("file", StringComparison.OrdinalIgnoreCase)) { }
```

## Culture-Sensitive Parsing and Formatting

### Parsing Pitfalls

```csharp
// WRONG: Decimal separator varies by culture (. vs , vs ·)
double price = double.Parse("1,234.56"); // Fails in de-DE (expects 1.234,56)

// CORRECT: Specify culture for data interchange
double price = double.Parse("1234.56", CultureInfo.InvariantCulture);

// CORRECT: Specify culture for user input
double price = double.Parse(userInput, CultureInfo.CurrentCulture);

// CORRECT: Use TryParse with IFormatProvider
if (decimal.TryParse(input, NumberStyles.Currency,
    CultureInfo.CurrentCulture, out var amount)) { }
```

### Formatting Rules

```csharp
// For storage/APIs/logs: always use InvariantCulture
string serialized = price.ToString(CultureInfo.InvariantCulture);
string isoDate = date.ToString("o"); // Round-trip format, culture-independent

// For display: use CurrentCulture or explicit culture
string display = price.ToString("C", CultureInfo.CurrentCulture); // $1,234.56 or 1.234,56 €
string dateStr = date.ToString("D", new CultureInfo("ja-JP"));
```

### IFormatProvider Pattern

```csharp
// Methods that format/parse should accept IFormatProvider
public string FormatOrder(Order order, IFormatProvider? provider = null)
{
    provider ??= CultureInfo.CurrentCulture;
    return string.Create(provider, $"Order #{order.Id}: {order.Total:C}");
}
```

## Time Zones

### DateTimeOffset vs DateTime

| Type | Use When |
|------|----------|
| `DateTimeOffset` | Storing timestamps, API payloads, database columns, logs — any time that needs an unambiguous point in time |
| `DateTime` with `DateTimeKind.Utc` | Internal UTC-only calculations where offset is always zero |
| `DateTime` with `DateTimeKind.Local` | Avoid in server code — "local" is the server's time zone, not the user's |
| `DateTime` with `DateTimeKind.Unspecified` | Calendar dates without time (birthdays, holidays) — use `DateOnly` (.NET 6+) instead |

```csharp
// CORRECT: Store and transmit as DateTimeOffset
DateTimeOffset now = DateTimeOffset.UtcNow;
DateTimeOffset userTime = TimeZoneInfo.ConvertTime(now, userTimeZone);

// CORRECT: Use DateOnly for dates without time
DateOnly birthday = new(1990, 3, 15);

// CORRECT: Use TimeOnly for time-of-day
TimeOnly openingTime = new(9, 0);
```

### TimeZoneInfo and IANA IDs

Windows uses proprietary time zone IDs (`"Eastern Standard Time"`), while Linux/macOS and most standards (ISO 8601, iCalendar, IANA/Olson) use IANA IDs (`"America/New_York"`). .NET 6+ can convert between them.

```csharp
// Cross-platform time zone lookup (.NET 6+)
// On Windows: finds by Windows ID directly, converts IANA → Windows
// On Linux/macOS: finds by IANA ID directly, converts Windows → IANA
TimeZoneInfo eastern = TimeZoneInfo.FindSystemTimeZoneById("America/New_York");
TimeZoneInfo easternAlt = TimeZoneInfo.FindSystemTimeZoneById("Eastern Standard Time");
// Both work on both platforms (.NET 6+)

// Convert between ID formats
if (TimeZoneInfo.TryConvertIanaIdToWindowsId("America/New_York", out string? winId))
    Console.WriteLine(winId); // "Eastern Standard Time"

if (TimeZoneInfo.TryConvertWindowsIdToIanaId("Eastern Standard Time", out string? ianaId))
    Console.WriteLine(ianaId); // "America/New_York"
```

### Common Time Zone IDs

| IANA ID | Windows ID | UTC Offset | Common Name |
|---------|-----------|------------|-------------|
| `America/New_York` | `Eastern Standard Time` | UTC-5/-4 | US Eastern |
| `America/Chicago` | `Central Standard Time` | UTC-6/-5 | US Central |
| `America/Denver` | `Mountain Standard Time` | UTC-7/-6 | US Mountain |
| `America/Los_Angeles` | `Pacific Standard Time` | UTC-8/-7 | US Pacific |
| `Europe/London` | `GMT Standard Time` | UTC+0/+1 | UK |
| `Europe/Paris` | `Romance Standard Time` | UTC+1/+2 | Central European |
| `Europe/Berlin` | `W. Europe Standard Time` | UTC+1/+2 | Western European |
| `Asia/Tokyo` | `Tokyo Standard Time` | UTC+9 | Japan |
| `Asia/Shanghai` | `China Standard Time` | UTC+8 | China |
| `Australia/Sydney` | `AUS Eastern Standard Time` | UTC+10/+11 | Australian Eastern |
| `Pacific/Auckland` | `New Zealand Standard Time` | UTC+12/+13 | New Zealand |

### Best Practices

```csharp
// Store IANA IDs in databases and configs (cross-platform, standard)
public record UserPreferences(string TimeZoneId); // "America/New_York"

// Convert to user's local time for display
public DateTimeOffset ToUserTime(DateTimeOffset utcTime, string ianaTimeZoneId)
{
    var tz = TimeZoneInfo.FindSystemTimeZoneById(ianaTimeZoneId);
    return TimeZoneInfo.ConvertTime(utcTime, tz);
}

// List all available time zones (for dropdowns)
foreach (var tz in TimeZoneInfo.GetSystemTimeZones())
{
    // tz.Id is Windows ID on Windows, IANA ID on Linux/macOS
    // tz.DisplayName gives localized display string
    // Use tz.HasIanaId (.NET 8+) to check format
}
```

### NodaTime Alternative

For complex calendar/time zone scenarios (recurring events, historical zone rules, non-Gregorian calendars), consider NodaTime:

```csharp
// NodaTime provides immutable, unambiguous time types
using NodaTime;

Instant now = SystemClock.Instance.GetCurrentInstant();
DateTimeZone zone = DateTimeZoneProviders.Tzdb["America/New_York"];
ZonedDateTime userTime = now.InZone(zone);
LocalDate today = userTime.Date; // Date without time zone
```

NodaTime is recommended for scheduling, calendar, and time-sensitive domain models. For simple UTC storage and display, `DateTimeOffset` + `TimeZoneInfo` is sufficient.

## Character Processing

### Rune (Unicode Scalar Value)

`char` is a UTF-16 code unit, not a Unicode character. Characters outside the Basic Multilingual Plane (emoji, CJK extensions) require surrogate pairs (two `char` values). `Rune` represents a single Unicode scalar value correctly. The type was introduced in .NET Core 3.0 and significantly expanded in .NET 11 with new Rune-based string/char APIs. **Prefer `Rune` over `char` for Unicode-aware processing** — use it whenever working with text that may contain non-ASCII characters.

```csharp
string text = "Hello 🌍"; // 🌍 is a surrogate pair (2 chars)

// WRONG: char-based iteration splits surrogates
foreach (char c in text) { } // Sees 🌍 as two separate chars

// CORRECT: Rune-based iteration handles all Unicode
foreach (Rune rune in text.EnumerateRunes())
{
    Console.WriteLine($"U+{rune.Value:X4}: {rune}");
}

// Character classification — prefer Rune methods over char methods
Rune.IsLetter(new Rune('A'));  // true
Rune.IsDigit(new Rune('5'));   // true
Rune.GetUnicodeCategory(new Rune('€')); // CurrencySymbol
```

### StringInfo (Grapheme Clusters)

Even `Rune` doesn't handle grapheme clusters — visual characters that combine multiple Unicode scalars (flag emoji, skin-tone modifiers, combining marks). Use `StringInfo` for user-perceived character counting.

```csharp
string flag = "🇺🇸";  // Two regional indicator symbols
string family = "👨‍👩‍👧‍👦"; // Family emoji with ZWJ sequences

// char count vs grapheme count
Console.WriteLine(flag.Length);                        // 4 (chars)
Console.WriteLine(new StringInfo(flag).LengthInTextElements); // 1 (grapheme)
Console.WriteLine(family.Length);                      // 11 (chars)
Console.WriteLine(new StringInfo(family).LengthInTextElements); // 1 (grapheme)

// Iterate grapheme clusters
var enumerator = StringInfo.GetTextElementEnumerator(text);
while (enumerator.MoveNext())
{
    string grapheme = enumerator.GetTextElement();
}
```

### When to Use Each

| API | Represents | Use For |
|-----|-----------|---------|
| `char` | UTF-16 code unit | Low-level byte processing, ASCII-only text |
| `Rune` | Unicode scalar value | Character classification, Unicode-aware processing |
| `StringInfo` | Grapheme cluster | User-visible character counting, text truncation, cursor positioning |

## Encoding

```csharp
// UTF-8 without BOM (preferred for new files, APIs, cross-platform)
var utf8NoBom = new UTF8Encoding(encoderShouldEmitUTF8Identifier: false);
await File.WriteAllTextAsync(path, content, utf8NoBom);

// UTF-8 with BOM (required by some Windows tools, legacy XML)
await File.WriteAllTextAsync(path, content, Encoding.UTF8); // Includes BOM

// Read with encoding detection
using var reader = new StreamReader(stream, detectEncodingFromByteOrderMarks: true);

// For high-performance scenarios, use Utf8JsonWriter or UTF8 spans
ReadOnlySpan<byte> utf8Bytes = "hello"u8; // UTF-8 string literal (C# 11+)
```

## .resx vs .resw

Both are XML-based resource file formats. Choose based on the target framework:

| Format | Used By | Build Output | Tool Support |
|--------|---------|-------------|-------------|
| `.resx` | .NET (all), MAUI, WPF, WinForms, ASP.NET | Satellite assemblies (`.resources.dll`) | Visual Studio designer, ResXGenerator |
| `.resw` | UWP, WinUI 3, Uno Platform | PRI (Package Resource Index) | Visual Studio, x:Uid XAML binding |

`.resx` is the default for most .NET projects. `.resw` is required for WinUI 3 and Uno Platform apps that use `x:Uid` binding. See [skill:dotnet-ui] `references/localization.md` for detailed patterns.

## InvariantGlobalization

The `InvariantGlobalization` MSBuild property disables ICU culture data, reducing binary size significantly for Native AOT and Blazor WASM builds.

```xml
<PropertyGroup>
  <InvariantGlobalization>true</InvariantGlobalization>
</PropertyGroup>
```

**Effects:**
- All `CultureInfo` instances behave as `InvariantCulture`
- `CultureInfo.CurrentCulture` returns invariant
- Culture-specific formatting (date, number, currency) uses invariant rules
- String comparison uses ordinal rules
- ICU data not bundled (~28 MB savings on AOT, ~2-4 MB on WASM)

**Use when:** CLI tools, microservices, and apps that don't need locale-specific formatting. **Don't use when:** User-facing apps with localized content, multi-language sites, financial apps with currency formatting.

## Globalization Analyzers

The CA1300 series flags globalization issues. Enable at `warning` severity for internationalized apps.

```ini
# .editorconfig
dotnet_analyzer_diagnostic.category-Globalization.severity = warning
```

| Rule | Description | Fix |
|------|-------------|-----|
| CA1304 | Specify CultureInfo | Add explicit `CultureInfo` parameter |
| CA1305 | Specify IFormatProvider | Add explicit `IFormatProvider` parameter |
| CA1307 | Specify StringComparison for clarity | Add explicit `StringComparison` |
| CA1309 | Use ordinal StringComparison | Switch to `StringComparison.Ordinal` |
| CA1310 | Specify StringComparison for correctness | Add explicit `StringComparison` |
| CA1311 | Specify culture or use invariant for ToUpper/ToLower | Use `ToUpperInvariant()` or specify culture |

**Pragmatic guidance:** For internal tools and English-only apps, consider setting CA1304/CA1305 to `suggestion` and CA1307/CA1310 to `warning`. For internationalized apps, set all to `warning`.

## Agent Gotchas

1. **Always specify `StringComparison` explicitly.** Default behavior differs between .NET Framework and .NET Core for `Contains`, `StartsWith`, `IndexOf`. Being explicit prevents cross-platform bugs.
2. **Use `DateTimeOffset` for timestamps, not `DateTime`.** `DateTime` loses time zone context during serialization. `DateTimeOffset` preserves the offset.
3. **Store IANA time zone IDs, not Windows IDs.** IANA IDs are the cross-platform standard. .NET 6+ can convert to/from Windows IDs when needed.
4. **Don't use `char` to count or truncate user-visible text.** Emoji and many scripts use surrogate pairs or combining characters. Use `StringInfo.LengthInTextElements` for user-visible length.
5. **Don't call `ToString()` without `CultureInfo` for data that will be persisted or transmitted.** Use `CultureInfo.InvariantCulture` for serialization, `CultureInfo.CurrentCulture` for display.
6. **Don't use `InvariantCulture` for user-facing sorting or display.** `InvariantCulture` is a synthetic culture based on English — use `CurrentCulture` for user-visible text.
7. **Prefer `DateOnly` and `TimeOnly` (.NET 6+)** over `DateTime` when you genuinely don't need time or date information respectively.
