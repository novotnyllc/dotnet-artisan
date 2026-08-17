# Terminal.Gui

Terminal.Gui v2 for building full terminal user interfaces with windows, menus, dialogs, views, layout, event handling, color themes, and mouse support. Cross-platform across Windows, macOS, and Linux terminals.

**Version assumptions:** .NET 8.0+ baseline. Terminal.Gui 2.0.0-alpha (v2 Alpha is the active development line for new projects -- API is stable with comprehensive features; breaking changes possible before Beta but core architecture is solid). v1.x (1.19.0) is in maintenance mode with no new features.

For detailed code examples (views, menus, dialogs, events, themes, complete editor), see the Detailed Examples section below.

## Package Reference

```xml
<ItemGroup>
  <PackageReference Include="Terminal.Gui" Version="2.0.0-alpha.*" />
</ItemGroup>
```


## Application Lifecycle

Terminal.Gui v2 uses an instance-based model with `IApplication` and `IDisposable` for proper resource cleanup.

### Basic Application

```csharp
using Terminal.Gui;

using IApplication app = Application.Create().Init();

var window = new Window
{
    Title = "My TUI App",
    Width = Dim.Fill(),
    Height = Dim.Fill()
};

var label = new Label
{
    Text = "Hello, Terminal.Gui!",
    X = Pos.Center(),
    Y = Pos.Center()
};
window.Add(label);

app.Run(window);
```


## Layout System

Terminal.Gui v2 unifies layout into a single model. Position is controlled by `Pos` (X, Y) and size by `Dim` (Width, Height), both relative to the SuperView's content area.

### Pos Types (Positioning)

```csharp
view.X = 5;                          // Absolute
view.X = Pos.Percent(25);            // 25% from left
view.X = Pos.Center();               // Centered
view.X = Pos.AnchorEnd(10);          // 10 from right edge
view.X = Pos.Right(otherView) + 1;   // Relative to another view
view.Y = Pos.Bottom(otherView) + 1;
view.X = Pos.Align(Alignment.End);   // Align groups
view.X = Pos.Func(() => CalculateX());
```

### Dim Types (Sizing)

```csharp
view.Width = 40;                       // Absolute
view.Width = Dim.Percent(50);          // 50% of parent
view.Width = Dim.Fill();               // Fill remaining space
view.Width = Dim.Auto();               // Size based on content
view.Width = Dim.Auto(minimumContentDim: 20);
view.Width = Dim.Width(otherView);     // Relative to another view
view.Width = Dim.Func(() => CalculateWidth());
```

### Frame vs. Viewport

- **Frame** -- outermost rectangle: location and size relative to SuperView
- **Viewport** -- visible portion of content area: acts as a scrollable portal into the view's content


## Cross-Platform Considerations

| Feature | Windows Terminal | macOS Terminal.app | Linux (xterm/gnome) |
|---|---|---|---|
| TrueColor (24-bit) | Yes | Yes | Yes (most) |
| Mouse support | Yes | Yes | Yes |
| Unicode/emoji | Yes | Yes | Varies |
| Key modifiers | Full | Limited | Full |

### Platform-Specific Notes

- **macOS Terminal.app** -- limited modifier key support; iTerm2 and WezTerm provide better support
- **SSH sessions** -- terminal capabilities depend on the client terminal, not the server
- **Windows Console Host** -- legacy conhost has limited Unicode support; Windows Terminal provides full support
- **tmux/screen** -- may intercept key combinations; set `TERM=xterm-256color`


## Agent Gotchas

1. **Do not use v1 static lifecycle pattern.** v2 uses instance-based `Application.Create().Init()` with `IDisposable`. Always wrap in a `using` statement.
2. **Do not use `View.AutoSize`.** Removed in v2. Use `Dim.Auto()` instead.
3. **Do not confuse Frame with Viewport.** Frame is the outer rectangle; Viewport is the visible content area (supports scrolling).
4. **Do not use `Button.Clicked`.** Replaced by `Button.Accepting` in v2.
5. **Do not call UI operations from background threads.** Terminal.Gui is single-threaded. Use `Application.Invoke()` to marshal calls back to the UI thread.
6. **Do not forget `RequestStop()` to close windows.** Calling `Dispose()` directly corrupts terminal state.
7. **Do not hardcode terminal dimensions.** Use `Dim.Fill()`, `Dim.Percent()`, and `Pos.Center()` for responsive layouts.
8. **Do not ignore terminal state on crash.** Wrap `app.Run()` in try/catch and ensure the `using` block disposes the application.
9. **Do not use `ScrollView`.** Removed in v2. All views now support scrolling natively via `SetContentSize()`.
10. **Do not use `NStack.ustring`.** Removed in v2. Use standard `System.String`.
11. **Do not use `StatusItem`.** Removed in v2. Use `Shortcut` objects with `StatusBar.Add()` instead.


## Prerequisites

- **NuGet package:** `Terminal.Gui` 2.0.0-alpha (v2) or 1.19.x (v1 maintenance)
- **Target framework:** net8.0 or later
- **Terminal:** Any terminal emulator supporting ANSI escape sequences


## References

- [Terminal.Gui GitHub](https://github.com/gui-cs/Terminal.Gui)
- [Terminal.Gui v2 Documentation](https://gui-cs.github.io/Terminal.Gui/)
- [Terminal.Gui NuGet](https://www.nuget.org/packages/Terminal.Gui)
- [Terminal.Gui v2 What's New](https://gui-cs.github.io/Terminal.Gui/docs/newinv2)
- [v1 to v2 Migration Guide](https://github.com/gui-cs/Terminal.Gui/blob/v2_develop/docfx/docs/migratingfromv1.md)

---

# Terminal.Gui -- Detailed Examples

Extended code examples for Terminal.Gui v2 views, layout, menus, dialogs, event handling, themes, and complete application patterns.

---

## Core Views

### Container Views

```csharp
var window = new Window
{
    Title = "Main Window",
    Width = Dim.Fill(),
    Height = Dim.Fill()
};

var frame = new FrameView
{
    Title = "Settings",
    X = 1, Y = 1,
    Width = Dim.Fill(1),
    Height = 10
};
window.Add(frame);
```

### Text and Input Views

```csharp
var label = new Label
{
    Text = "Username:",
    X = 1, Y = 1
};

var textField = new TextField
{
    X = Pos.Right(label) + 1,
    Y = Pos.Top(label),
    Width = 30,
    Text = ""
};

var textView = new TextView
{
    X = 1, Y = 3,
    Width = Dim.Fill(1),
    Height = Dim.Fill(1),
    Text = "Multi-line\nediting area"
};
```

### Button

```csharp
var button = new Button
{
    Text = "OK",
    X = Pos.Center(),
    Y = Pos.Bottom(textField) + 1
};

button.Accepting += (sender, args) =>
{
    MessageBox.Query(button.App!, "Info", $"You entered: {textField.Text}", "OK");
    args.Handled = true;
};
```

### ListView and TableView

```csharp
var items = new List<string> { "Item 1", "Item 2", "Item 3" };
var listView = new ListView
{
    X = 1, Y = 1,
    Width = Dim.Fill(1),
    Height = Dim.Fill(1),
    Source = new ListWrapper<string>(new ObservableCollection<string>(items))
};

listView.SelectedItemChanged += (sender, args) =>
{
    // args.Value is the selected item index
};
```

### CheckBox and RadioGroup

```csharp
var checkbox = new CheckBox
{
    Text = "Enable notifications",
    X = 1, Y = 1
};

checkbox.CheckedStateChanging += (sender, args) =>
{
    // args.NewValue is the new CheckState
};

var radioGroup = new RadioGroup
{
    X = 1, Y = 3,
    RadioLabels = ["Option A", "Option B", "Option C"]
};
```

### Additional v2 Views

```csharp
var datePicker = new DatePicker
{
    X = 1, Y = 1,
    Date = DateTime.Today
};

var spinner = new NumericUpDown<int>
{
    X = 1, Y = 3,
    Value = 42
};

var colorPicker = new ColorPicker
{
    X = 1, Y = 5,
    SelectedColor = new Color(0, 120, 215)
};
```

---

## Menus and Status Bar

### MenuBar

```csharp
var menuBar = new MenuBar([
    new MenuBarItem("_File",
    [
        new MenuItem("_New", "Create new file", () => NewFile()),
        new MenuItem("_Open", "Open existing file", () => OpenFile()),
        new MenuBarItem("_Recent",
        [
            new MenuItem("file1.txt", "", () => Open("file1.txt")),
            new MenuItem("file2.txt", "", () => Open("file2.txt"))
        ]),
        null,  // separator
        new MenuItem
        {
            Title = "_Quit",
            HelpText = "Exit application",
            Key = Application.QuitKey,
            Command = Command.Quit
        }
    ]),
    new MenuBarItem("_Edit",
    [
        new MenuItem("_Copy", "", () => Copy(), Key.C.WithCtrl),
        new MenuItem("_Paste", "", () => Paste(), Key.V.WithCtrl)
    ]),
    new MenuBarItem("_Help",
    [
        new MenuItem("_About", "About this app", () =>
            MessageBox.Query(app, "", "My TUI App v1.0", "OK"))
    ])
]);
window.Add(menuBar);
```

### StatusBar

```csharp
var statusBar = new StatusBar();

var helpShortcut = new Shortcut
{
    Title = "Help",
    Key = Key.F1,
    CanFocus = false
};
helpShortcut.Accepting += (sender, args) =>
{
    ShowHelp();
    args.Handled = true;
};

var saveShortcut = new Shortcut
{
    Title = "Save",
    Key = Key.F2,
    CanFocus = false
};
saveShortcut.Accepting += (sender, args) =>
{
    Save();
    args.Handled = true;
};

var quitShortcut = new Shortcut
{
    Title = "Quit",
    Key = Application.QuitKey,
    CanFocus = false
};

statusBar.Add(helpShortcut, saveShortcut, quitShortcut);
window.Add(statusBar);
```

---

## Dialogs and MessageBox

### Dialog

```csharp
var dialog = new Dialog
{
    Title = "Confirm",
    Width = 50,
    Height = 10
};

var label = new Label
{
    Text = "Are you sure?",
    X = Pos.Center(),
    Y = 1
};
dialog.Add(label);

var okButton = new Button { Text = "OK" };
okButton.Accepting += (sender, args) =>
{
    dialog.RequestStop();
    args.Handled = true;
};

var cancelButton = new Button { Text = "Cancel" };
cancelButton.Accepting += (sender, args) =>
{
    dialog.RequestStop();
    args.Handled = true;
};

dialog.AddButton(okButton);
dialog.AddButton(cancelButton);
app.Run(dialog);
```

### MessageBox

```csharp
int result = MessageBox.Query(app, "Confirm Delete",
    "Delete this file permanently?",
    "Yes", "No");

if (result == 0)
{
    // User clicked "Yes"
}

MessageBox.ErrorQuery(app, "Error",
    "Failed to save file.\nCheck permissions.",
    "OK");
```

### FileDialog

```csharp
var fileDialog = new FileDialog
{
    Title = "Open File",
    AllowedTypes = [new AllowedType("C# Files", ".cs", ".csx")],
    MustExist = true
};

app.Run(fileDialog);

if (!fileDialog.Canceled)
{
    string selectedPath = fileDialog.FilePath;
}
```

---

## Event Handling and Key Bindings

### Key Bindings with Commands

```csharp
view.AddCommand(Command.Accept, (args) =>
{
    return true;
});
view.KeyBindings.Add(Key.Enter, Command.Accept);

view.KeyBindings.Add(Key.S.WithCtrl, Command.Save);
view.AddCommand(Command.Save, (args) =>
{
    SaveDocument();
    return true;
});
```

### Key Event Handling

```csharp
view.KeyDown += (sender, args) =>
{
    if (args.KeyCode == Key.F5)
    {
        RefreshData();
        args.Handled = true;
    }
};
```

### Mouse Events

```csharp
view.MouseClick += (sender, args) =>
{
    int col = args.Position.X;
    int row = args.Position.Y;
};

view.MouseEvent += (sender, args) =>
{
    if (args.Flags.HasFlag(MouseFlags.Button1DoubleClicked))
    {
        // Handle double-click
    }
};
```

---

## Color Themes and Styling

```csharp
var customColor = new Color(0xFF, 0x99, 0x00);

var attr = new Attribute(
    new Color(255, 255, 255),
    new Color(0, 0, 128)
);

view.ColorScheme = new ColorScheme
{
    Normal = attr,
    Focus = new Attribute(Color.Black, Color.BrightCyan),
    HotNormal = new Attribute(Color.Red, Color.Blue),
    HotFocus = new Attribute(Color.BrightRed, Color.BrightCyan)
};
```

### Theme Configuration

```csharp
ConfigurationManager.RuntimeConfig = """{ "Theme": "Amber Phosphor" }""";
ConfigurationManager.Enable(ConfigLocations.All);
IApplication app = Application.Create().Init();
```

---

## Adornments (Borders, Margins, Padding)

```csharp
var view = new View
{
    X = 1, Y = 1,
    Width = 40, Height = 10
};

view.Border.LineStyle = LineStyle.Rounded;
view.Border.Thickness = new Thickness(1);
view.Margin.Thickness = new Thickness(1);
view.Padding.Thickness = new Thickness(1, 0);
```

---

## Complete Example: Simple Editor

```csharp
using Terminal.Gui;

using IApplication app = Application.Create().Init();

var window = new Window
{
    Title = $"Simple Editor ({Application.QuitKey} to quit)",
    Width = Dim.Fill(),
    Height = Dim.Fill()
};

var textView = new TextView
{
    X = 0, Y = 1,
    Width = Dim.Fill(),
    Height = Dim.Fill(1),
    Text = ""
};

var menuBar = new MenuBar([
    new MenuBarItem("_File",
    [
        new MenuItem("_New", "Clear editor", () => textView.Text = ""),
        null,
        new MenuItem
        {
            Title = "_Quit",
            HelpText = "Exit",
            Key = Application.QuitKey,
            Command = Command.Quit
        }
    ])
]);

var statusBar = new StatusBar();
var helpShortcut = new Shortcut { Title = "Help", Key = Key.F1, CanFocus = false };
helpShortcut.Accepting += (s, e) =>
{
    MessageBox.Query(app, "Help", "Simple text editor.", "OK");
    e.Handled = true;
};
statusBar.Add(helpShortcut);

window.Add(menuBar, textView, statusBar);
app.Run(window);
```
