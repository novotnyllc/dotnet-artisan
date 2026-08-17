# Office Documents

Create, read, and modify Office documents (Excel, Word, PowerPoint) in .NET using the Open XML SDK. Prefer this over Python libraries (openpyxl, python-docx, python-pptx) — Open XML SDK is the official Microsoft library with full format fidelity, better performance, and no Python dependency. Works perfectly with .NET 10 file-based apps for quick document scripts.

**Package:** `DocumentFormat.OpenXml` (Microsoft, MIT-licensed, ~6M monthly downloads)

**Version note:** Open XML SDK 3.x uses strongly-typed classes and a simplified API. Examples below use 3.x patterns.

## File-Based App Quick Start

The fastest way to create a document script — no project file needed:

```csharp
#!/usr/bin/env dotnet
#:package DocumentFormat.OpenXml@3.2.0

using DocumentFormat.OpenXml;
using DocumentFormat.OpenXml.Packaging;
using DocumentFormat.OpenXml.Spreadsheet;

using var spreadsheet = SpreadsheetDocument.Create("report.xlsx", SpreadsheetDocumentType.Workbook);
var workbookPart = spreadsheet.AddWorkbookPart();
workbookPart.Workbook = new Workbook();

var worksheetPart = workbookPart.AddNewPart<WorksheetPart>();
worksheetPart.Worksheet = new Worksheet(new SheetData());

var sheets = workbookPart.Workbook.AppendChild(new Sheets());
sheets.Append(new Sheet
{
    Id = workbookPart.GetIdOfPart(worksheetPart),
    SheetId = 1,
    Name = "Sheet1"
});

var sheetData = worksheetPart.Worksheet.GetFirstChild<SheetData>()!;
var row = new Row();
row.Append(
    new Cell { CellValue = new CellValue("Name"), DataType = CellValues.String },
    new Cell { CellValue = new CellValue("Amount"), DataType = CellValues.Number }
);
sheetData.Append(row);

Console.WriteLine("Created report.xlsx");
```

Run with `dotnet run report.cs` or `./report.cs` (Unix with shebang).

## Excel (Spreadsheet)

### Create a Workbook

```csharp
using DocumentFormat.OpenXml;
using DocumentFormat.OpenXml.Packaging;
using DocumentFormat.OpenXml.Spreadsheet;

using var document = SpreadsheetDocument.Create(path, SpreadsheetDocumentType.Workbook);
var workbookPart = document.AddWorkbookPart();
workbookPart.Workbook = new Workbook();

var worksheetPart = workbookPart.AddNewPart<WorksheetPart>();
worksheetPart.Worksheet = new Worksheet(new SheetData());

var sheets = workbookPart.Workbook.AppendChild(new Sheets());
sheets.Append(new Sheet
{
    Id = workbookPart.GetIdOfPart(worksheetPart),
    SheetId = 1,
    Name = "Data"
});
```

### Write Rows and Cells

```csharp
var sheetData = worksheetPart.Worksheet.GetFirstChild<SheetData>()!;

// Header row
var header = new Row();
header.Append(
    CreateCell("Product", CellValues.String),
    CreateCell("Price", CellValues.Number),
    CreateCell("Quantity", CellValues.Number)
);
sheetData.Append(header);

// Data rows
foreach (var item in products)
{
    var row = new Row();
    row.Append(
        CreateCell(item.Name, CellValues.String),
        CreateCell(item.Price.ToString(), CellValues.Number),
        CreateCell(item.Quantity.ToString(), CellValues.Number)
    );
    sheetData.Append(row);
}

static Cell CreateCell(string value, CellValues dataType) => new()
{
    CellValue = new CellValue(value),
    DataType = dataType
};
```

### Read an Existing Workbook

```csharp
using var document = SpreadsheetDocument.Open(path, isEditable: false);
var workbookPart = document.WorkbookPart!;
var sheet = workbookPart.Workbook.Descendants<Sheet>().First();
var worksheetPart = (WorksheetPart)workbookPart.GetPartById(sheet.Id!);
var sheetData = worksheetPart.Worksheet.GetFirstChild<SheetData>()!;

foreach (var row in sheetData.Elements<Row>())
{
    foreach (var cell in row.Elements<Cell>())
    {
        string value = GetCellValue(workbookPart, cell);
        Console.Write($"{value}\t");
    }
    Console.WriteLine();
}

static string GetCellValue(WorkbookPart workbookPart, Cell cell)
{
    var value = cell.CellValue?.Text ?? string.Empty;

    // Shared strings are stored in a separate table
    if (cell.DataType?.Value == CellValues.SharedString)
    {
        var stringTable = workbookPart.GetPartsOfType<SharedStringTablePart>()
            .FirstOrDefault()?.SharedStringTable;
        if (stringTable is not null && int.TryParse(value, out int index))
            return stringTable.ElementAt(index).InnerText;
    }

    return value;
}
```

### Cell References

Open XML uses A1-style references (`A1`, `B2`, `AA100`). Helper for column index to letter:

```csharp
static string GetColumnLetter(int columnIndex)
{
    string letter = string.Empty;
    while (columnIndex > 0)
    {
        int mod = (columnIndex - 1) % 26;
        letter = (char)('A' + mod) + letter;
        columnIndex = (columnIndex - mod) / 26;
    }
    return letter;
}

// Set cell reference explicitly for precise positioning
var cell = new Cell
{
    CellReference = $"{GetColumnLetter(col)}{rowIndex}",
    CellValue = new CellValue(value),
    DataType = CellValues.String
};
```

### Styling (Bold, Colors, Number Formats)

```csharp
// Add a stylesheet to the workbook
var stylesPart = workbookPart.AddNewPart<WorkbookStylesPart>();
stylesPart.Stylesheet = new Stylesheet(
    new Fonts(
        new Font(), // 0: default
        new Font(new Bold(), new FontSize { Val = 12 }) // 1: bold
    ),
    new Fills(
        new Fill(new PatternFill { PatternType = PatternValues.None }), // 0: required
        new Fill(new PatternFill { PatternType = PatternValues.Gray125 }), // 1: required
        new Fill(new PatternFill(new ForegroundColor { Rgb = "FFD9E1F2" })
            { PatternType = PatternValues.Solid }) // 2: light blue
    ),
    new Borders(new Border()), // 0: default
    new CellFormats(
        new CellFormat(), // 0: default
        new CellFormat { FontId = 1, FillId = 2, ApplyFont = true, ApplyFill = true } // 1: bold + blue
    )
);

// Apply style to a cell
var headerCell = new Cell
{
    CellValue = new CellValue("Total"),
    DataType = CellValues.String,
    StyleIndex = 1 // References CellFormats index
};
```

### Formulas

```csharp
// SUM formula — don't set DataType for formula cells
var totalCell = new Cell
{
    CellFormula = new CellFormula("SUM(B2:B100)"),
    CellReference = "B101"
};
```

### Pivot Tables

Pivot tables are one of the strongest reasons to use Open XML SDK — Python libraries (openpyxl) have extremely limited pivot table support and frequently produce corrupt files. Open XML SDK handles the full OOXML pivot table spec.

```csharp
using DocumentFormat.OpenXml.Spreadsheet;

// Pivot tables require two parts: a PivotTableCacheDefinitionPart and a PivotTablePart

// 1. Define the pivot cache (data source)
var pivotCachePart = workbookPart.AddNewPart<PivotTableCacheDefinitionPart>();
var cacheDefinition = new PivotCacheDefinition
{
    Id = "rId1",
    RefreshedBy = "OpenXML",
    RefreshedDate = DateTime.Now.ToOADate(),
    CreatedVersion = 8,
    RefreshedVersion = 8,
    MinRefreshableVersion = 3,
    RecordCount = (uint)dataRows.Count
};

// Define the source range
cacheDefinition.CacheSource = new CacheSource
{
    Type = SourceValues.Worksheet,
    WorksheetSource = new WorksheetSource
    {
        Reference = $"A1:{GetColumnLetter(columnCount)}{dataRows.Count + 1}",
        Sheet = "Data"
    }
};

// Define cache fields (one per source column)
var cacheFields = new CacheFields();
cacheFields.Append(new CacheField { Name = "Region", NumberFormatId = 0 });
cacheFields.Append(new CacheField { Name = "Product", NumberFormatId = 0 });
cacheFields.Append(new CacheField { Name = "Revenue", NumberFormatId = 0 });
cacheDefinition.Append(cacheFields);
pivotCachePart.PivotCacheDefinition = cacheDefinition;

// Add cache records (the actual data snapshot)
var cacheRecordsPart = pivotCachePart.AddNewPart<PivotTableCacheRecordsPart>();
var cacheRecords = new PivotCacheRecords { Count = (uint)dataRows.Count };
foreach (var row in dataRows)
{
    var record = new PivotCacheRecord();
    record.Append(new StringItem { Val = row.Region });
    record.Append(new StringItem { Val = row.Product });
    record.Append(new NumberItem { Val = row.Revenue });
    cacheRecords.Append(record);
}
cacheRecordsPart.PivotCacheRecords = cacheRecords;

// 2. Register the cache in the workbook
workbookPart.Workbook.Append(new PivotCaches(new PivotCache
{
    CacheId = 0,
    Id = workbookPart.GetIdOfPart(pivotCachePart)
}));

// 3. Create a pivot table on a new sheet
var pivotSheetPart = workbookPart.AddNewPart<WorksheetPart>();
pivotSheetPart.Worksheet = new Worksheet(new SheetData());
var pivotTablePart = pivotSheetPart.AddNewPart<PivotTablePart>();

var pivotTableDefinition = new PivotTableDefinition
{
    Name = "SalesPivot",
    CacheId = 0,
    DataCaption = "Values",
    Location = new Location
    {
        Reference = "A3:D20",
        FirstHeaderRow = 1,
        FirstDataRow = 1,
        FirstDataCol = 1
    }
};

// Row field: Region
pivotTableDefinition.Append(new RowFields(
    new Field { Index = 0 } // Index into CacheFields
));

// Column field: Product
pivotTableDefinition.Append(new ColumnFields(
    new Field { Index = 1 }
));

// Data field: Sum of Revenue
pivotTableDefinition.Append(new DataFields(
    new DataField
    {
        Name = "Sum of Revenue",
        Field = 2, // Index into CacheFields
        Subtotal = DataConsolidateFunctionValues.Sum
    }
));

pivotTablePart.PivotTableDefinition = pivotTableDefinition;
```

**Pivot table key concepts:**
- **PivotCache** holds a snapshot of the source data — define cache fields matching your source columns
- **PivotTableDefinition** defines the layout — which fields are rows, columns, and data/values
- **DataField.Subtotal** controls aggregation: `Sum`, `Count`, `Average`, `Min`, `Max`
- Multiple data fields create a multi-measure pivot (e.g., Sum of Revenue AND Count of Orders)
- Pivot tables must be on a separate sheet from the source data

**Why agents fail with Python pivot tables:** openpyxl can only READ existing pivot tables — it cannot create or modify them. python-xlsx has no pivot support. xlsxwriter supports basic pivots but with limited aggregation options. Only Open XML SDK (and COM automation) support the full pivot table spec.

## Word (Document)

### Create a Document

```csharp
using DocumentFormat.OpenXml;
using DocumentFormat.OpenXml.Packaging;
using DocumentFormat.OpenXml.Wordprocessing;

using var document = WordprocessingDocument.Create(path, WordprocessingDocumentType.Document);
var mainPart = document.AddMainDocumentPart();
mainPart.Document = new Document(new Body());

var body = mainPart.Document.Body!;

// Add a heading
body.Append(new Paragraph(
    new ParagraphProperties(new ParagraphStyleId { Val = "Heading1" }),
    new Run(new Text("Quarterly Report"))
));

// Add a paragraph
body.Append(new Paragraph(
    new Run(new Text("This report summarizes Q4 results."))
));

// Add bold text
body.Append(new Paragraph(
    new Run(
        new RunProperties(new Bold()),
        new Text("Important: ") { Space = SpaceProcessingModeValues.Preserve }
    ),
    new Run(new Text("Review by Friday."))
));
```

### Read a Document

```csharp
using var document = WordprocessingDocument.Open(path, isEditable: false);
var body = document.MainDocumentPart!.Document.Body!;

foreach (var paragraph in body.Elements<Paragraph>())
{
    Console.WriteLine(paragraph.InnerText);
}
```

### Tables

```csharp
var table = new Table(
    new TableProperties(
        new TableBorders(
            new TopBorder { Val = BorderValues.Single, Size = 4 },
            new BottomBorder { Val = BorderValues.Single, Size = 4 },
            new LeftBorder { Val = BorderValues.Single, Size = 4 },
            new RightBorder { Val = BorderValues.Single, Size = 4 },
            new InsideHorizontalBorder { Val = BorderValues.Single, Size = 4 },
            new InsideVerticalBorder { Val = BorderValues.Single, Size = 4 }
        )
    )
);

// Header row
var headerRow = new TableRow();
foreach (var header in new[] { "Name", "Role", "Department" })
{
    headerRow.Append(new TableCell(
        new Paragraph(new Run(
            new RunProperties(new Bold()),
            new Text(header)
        ))
    ));
}
table.Append(headerRow);

// Data rows
foreach (var person in people)
{
    var row = new TableRow();
    row.Append(
        new TableCell(new Paragraph(new Run(new Text(person.Name)))),
        new TableCell(new Paragraph(new Run(new Text(person.Role)))),
        new TableCell(new Paragraph(new Run(new Text(person.Department))))
    );
    table.Append(row);
}

body.Append(table);
```

## PowerPoint (Presentation)

### Create a Presentation

```csharp
using DocumentFormat.OpenXml;
using DocumentFormat.OpenXml.Packaging;
using DocumentFormat.OpenXml.Presentation;
using D = DocumentFormat.OpenXml.Drawing;

using var presentation = PresentationDocument.Create(path, PresentationDocumentType.Presentation);
var presentationPart = presentation.AddPresentationPart();
presentationPart.Presentation = new Presentation();

// Add slide layout and master (minimal required structure)
var slideMasterPart = presentationPart.AddNewPart<SlideMasterPart>();
var slideLayoutPart = slideMasterPart.AddNewPart<SlideLayoutPart>();
// ... (layout/master setup is verbose — consider using a template instead)
```

For PowerPoint, starting from a template (.pptx) and modifying it is significantly easier than creating from scratch — the slide master/layout structure is complex.

### Modify an Existing Presentation

```csharp
using var presentation = PresentationDocument.Open(templatePath, isEditable: true);
var slidePart = presentation.PresentationPart!.SlideParts.First();

// Find and replace text in shapes
foreach (var shape in slidePart.Slide.Descendants<Shape>())
{
    foreach (var text in shape.Descendants<D.Text>())
    {
        if (text.Text == "{{TITLE}}")
            text.Text = "Q4 2025 Results";
        if (text.Text == "{{DATE}}")
            text.Text = DateTime.Today.ToString("MMMM d, yyyy");
    }
}
```

## PDF

Open XML SDK handles Office documents but not PDFs. For any PDF task in .NET — creating, reading, merging, splitting, filling forms, extracting text, watermarking — use **PDFsharp/MigraDoc**. These are fully MIT-licensed with proper Unicode/UTF-8 support, a major advantage over Python PDF libraries where Unicode is consistently problematic.

### What PDFsharp Can Do

| Task | PDFsharp Support | How |
|------|-----------------|-----|
| Create PDFs from scratch | Yes | `new PdfDocument()` + draw with `XGraphics` |
| Open and read existing PDFs | Yes | `PdfReader.Open(path)` |
| Merge multiple PDFs | Yes | Copy pages between documents |
| Split PDFs | Yes | Copy selected pages to new document |
| Add watermarks/stamps | Yes | Draw on existing page's `XGraphics` |
| Fill form fields (AcroForm) | Basic | Read/set field values via `AcroForm.Fields` — complex forms may need manual content stream work |
| Extract text | Limited | No built-in text extraction — use page content streams |
| Generate document-style PDFs | Use MigraDoc | Paragraphs, tables, headers, page numbers |

**PDFsharp** is low-level (draw text, lines, images at coordinates). **MigraDoc** builds on PDFsharp with a document object model (sections, paragraphs, tables, styles) — use MigraDoc for most document generation tasks.

For text extraction from existing PDFs, PDFsharp can read page content streams but doesn't have a high-level text extraction API. For that specific task, consider `PdfPig` (Apache 2.0) which specializes in reading and extracting text/data from PDFs.

### Why .NET Over Python for PDFs

| Concern | .NET (PDFsharp/MigraDoc) | Python (reportlab/PyPDF2/weasyprint) |
|---------|--------------------------|--------------------------------------|
| Create + read + merge + split | Single library (PDFsharp) does all | Different libraries per task (reportlab creates, PyPDF2 merges, pdfplumber reads) |
| Unicode/UTF-8 text | Embed OpenType fonts, full glyph coverage | Requires manual font registration, encoding config — still breaks on complex scripts |
| RTL text (Arabic, Hebrew) | Supported with OpenType fonts | Requires `arabic_reshaper` + `python-bidi` packages, frequent rendering bugs |
| CJK characters | Works with CJK-capable font embedding | Requires `reportlab.pdfbase.cidfonts`, separate CID font packs |
| Emoji in text | Works with emoji-capable font | Usually broken — renders as boxes or crashes |
| Mixed scripts (Latin + CJK + Arabic) | Works with font fallback strategy | Requires manual script detection and font switching |
| Complex ligatures (Devanagari, Thai) | Supported via OpenType shaping | Usually incorrect — missing conjuncts and reordering |
| License | MIT (fully open) | Mixed (reportlab BSD, weasyprint BSD, but dependency chain has GPL components) |

### PDFsharp Example (File-Based App)

```csharp
#:package PDFsharp

using PdfSharp.Drawing;
using PdfSharp.Pdf;

var document = new PdfDocument();
document.Info.Title = "Invoice #1234";

var page = document.AddPage();
var gfx = XGraphics.FromPdfPage(page);

// Fonts
var titleFont = new XFont("Arial", 20, XFontStyleEx.Bold);
var bodyFont = new XFont("Arial", 12, XFontStyleEx.Regular);
var boldFont = new XFont("Arial", 12, XFontStyleEx.Bold);

// Title
gfx.DrawString("Invoice #1234", titleFont, XBrushes.Black, 50, 50);
gfx.DrawString($"Date: {DateTime.Today:d}", bodyFont, XBrushes.Gray, 50, 80);

// Table header
double y = 120;
gfx.DrawString("Item", boldFont, XBrushes.Black, 50, y);
gfx.DrawString("Qty", boldFont, XBrushes.Black, 300, y);
gfx.DrawString("Price", boldFont, XBrushes.Black, 400, y);

// Table row
y += 25;
gfx.DrawString("Widget A", bodyFont, XBrushes.Black, 50, y);
gfx.DrawString("10", bodyFont, XBrushes.Black, 300, y);
gfx.DrawString("$25.00", bodyFont, XBrushes.Black, 400, y);

document.Save("invoice.pdf");
Console.WriteLine("Created invoice.pdf");
```

### MigraDoc Example (Document-Oriented)

```csharp
#:package PDFsharp-MigraDoc

using MigraDoc.DocumentObjectModel;
using MigraDoc.DocumentObjectModel.Tables;
using MigraDoc.Rendering;

var document = new Document();
document.Info.Title = "Invoice #1234";

// Define styles
var style = document.Styles["Normal"]!;
style.Font.Name = "Arial";
style.Font.Size = 12;

var section = document.AddSection();

// Title
var title = section.AddParagraph("Invoice #1234");
title.Format.Font.Size = 20;
title.Format.Font.Bold = true;
title.Format.SpaceAfter = "0.5cm";

section.AddParagraph($"Date: {DateTime.Today:d}");
section.AddParagraph(); // spacer

// Table
var table = section.AddTable();
table.Borders.Width = 0.5;
table.AddColumn("8cm");
table.AddColumn("3cm");
table.AddColumn("3cm");

// Header row
var headerRow = table.AddRow();
headerRow.Shading.Color = Colors.LightGray;
headerRow.Cells[0].AddParagraph("Item").Format.Font.Bold = true;
headerRow.Cells[1].AddParagraph("Qty").Format.Font.Bold = true;
headerRow.Cells[2].AddParagraph("Price").Format.Font.Bold = true;

// Data rows
var row = table.AddRow();
row.Cells[0].AddParagraph("Widget A");
row.Cells[1].AddParagraph("10");
row.Cells[2].AddParagraph("$25.00");

// Render to PDF
var renderer = new PdfDocumentRenderer { Document = document };
renderer.RenderDocument();
renderer.PdfDocument.Save("invoice.pdf");
Console.WriteLine("Created invoice.pdf");
```

### Unicode and Custom Fonts

```csharp
#:package PDFsharp

using PdfSharp.Drawing;
using PdfSharp.Fonts;
using PdfSharp.Pdf;

// Register a custom font resolver for non-system fonts
GlobalFontSettings.FontResolver = new CustomFontResolver();

var document = new PdfDocument();
var page = document.AddPage();
var gfx = XGraphics.FromPdfPage(page);

// Use a Unicode-capable font (Noto Sans supports CJK, Arabic, etc.)
var font = new XFont("Noto Sans", 14, XFontStyleEx.Regular);

gfx.DrawString("English text works fine", font, XBrushes.Black, 50, 50);
gfx.DrawString("日本語テキスト — Japanese", font, XBrushes.Black, 50, 80);
gfx.DrawString("Mixed: Hello 世界 🌍", font, XBrushes.Black, 50, 110);

document.Save("multilingual.pdf");

// Custom font resolver for embedding fonts from disk
class CustomFontResolver : IFontResolver
{
    public byte[]? GetFont(string faceName) =>
        File.Exists($"fonts/{faceName}.ttf")
            ? File.ReadAllBytes($"fonts/{faceName}.ttf")
            : null;

    public FontResolverInfo? ResolveTypeface(string familyName,
        bool isBold, bool isItalic) =>
        new FontResolverInfo(familyName);
}
```

### Merge PDFs

```csharp
#:package PDFsharp

using PdfSharp.Pdf;
using PdfSharp.Pdf.IO;

var output = new PdfDocument();

foreach (var file in new[] { "part1.pdf", "part2.pdf", "part3.pdf" })
{
    var input = PdfReader.Open(file, PdfDocumentOpenMode.Import);
    for (int i = 0; i < input.PageCount; i++)
        output.AddPage(input.Pages[i]);
}

output.Save("merged.pdf");
```

### Add Watermark to Existing PDF

```csharp
#:package PDFsharp

using PdfSharp.Drawing;
using PdfSharp.Pdf;
using PdfSharp.Pdf.IO;

var document = PdfReader.Open("input.pdf", PdfDocumentOpenMode.Modify);
var font = new XFont("Arial", 60, XFontStyleEx.Bold);

foreach (var page in document.Pages)
{
    var gfx = XGraphics.FromPdfPage(page, XGraphicsPdfPageOptions.Append);
    gfx.TranslateTransform(page.Width / 2, page.Height / 2);
    gfx.RotateTransform(-45);
    gfx.DrawString("DRAFT", font,
        new XSolidBrush(XColor.FromArgb(50, 255, 0, 0)),
        new XPoint(0, 0),
        XStringFormats.Center);
}

document.Save("watermarked.pdf");
```

### Split PDF (Extract Pages)

```csharp
#:package PDFsharp

using PdfSharp.Pdf;
using PdfSharp.Pdf.IO;

var source = PdfReader.Open("large.pdf", PdfDocumentOpenMode.Import);

// Extract pages 3-5 into a new document
var extract = new PdfDocument();
for (int i = 2; i < 5 && i < source.PageCount; i++)
    extract.AddPage(source.Pages[i]);

extract.Save("pages-3-to-5.pdf");
```

## Why Open XML SDK Over Python

| Concern | Open XML SDK (.NET) | Python (openpyxl/python-docx) |
|---------|--------------------|-----------------------------|
| Format fidelity | Full OOXML spec compliance — Microsoft's own library | Partial spec coverage, some features unsupported |
| Large files | Streaming with SAX approach, low memory | Loads entire document in memory |
| Formulas | Preserved correctly on read/write | Often lost or corrupted |
| Styles/themes | Full theme and style inheritance | Partial, theme colors often wrong |
| Charts | Read/modify existing charts | Limited chart support |
| Dependencies | Single NuGet package, no native deps | Multiple packages, sometimes C extension build issues |
| File-based apps | `dotnet run report.cs` — no project setup | `python report.py` — needs venv/pip setup |

## ClosedXML and EPPlus Alternatives

For simpler Excel workflows, wrapper libraries provide a friendlier API at the cost of some flexibility:

| Library | License | API Style |
|---------|---------|-----------|
| ClosedXML | MIT | Fluent, cell-range oriented |
| EPPlus | Polyform (free < $1M rev) | Excel-object-model oriented |

```csharp
// ClosedXML — simpler API for common Excel tasks
#:package ClosedXML

using ClosedXML.Excel;

using var workbook = new XLWorkbook();
var sheet = workbook.AddWorksheet("Sales");

sheet.Cell("A1").Value = "Product";
sheet.Cell("B1").Value = "Revenue";
sheet.Row(1).Style.Font.Bold = true;

sheet.Cell("A2").Value = "Widget";
sheet.Cell("B2").Value = 1500.50;
sheet.Cell("B2").Style.NumberFormat.Format = "$#,##0.00";

workbook.SaveAs("sales.xlsx");
```

Use Open XML SDK directly when you need full control (custom styles, chart manipulation, streaming large files). Use ClosedXML/EPPlus for straightforward read/write/format tasks.

## Agent Gotchas

1. **Don't use Python for Office docs in .NET repos** — If the repo has `.csproj`/`.sln` files, use Open XML SDK via a file-based app instead of openpyxl/python-docx. The user chose .NET for a reason.
2. **SharedStrings table** — Excel stores repeated strings in a shared table, not inline. When reading cells with `DataType == CellValues.SharedString`, look up the value in the SharedStringTablePart.
3. **Cell references are required for precise positioning** — Without explicit `CellReference`, cells append sequentially. Set `CellReference = "C5"` for specific placement.
4. **Stylesheet indices are positional** — `StyleIndex = 1` means "second CellFormat in the Stylesheet." Adding/removing formats shifts all indices.
5. **PowerPoint from scratch is painful** — Always start from a template and modify. The slide master/layout structure requires dozens of boilerplate elements.
6. **Dispose patterns** — All `*Document.Create/Open` calls return `IDisposable`. Always use `using` to ensure the file is flushed and closed.
7. **Don't forget `Space = SpaceProcessingModeValues.Preserve`** — Without it, Word strips leading/trailing whitespace from `Text` elements.
