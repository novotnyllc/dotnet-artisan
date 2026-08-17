# WinUI Controls and Styling

WinUI 3 control selection by scenario, ScrollViewer ownership rules, adaptive layout, theming, materials, typography, icons, and resource organization. Complements `references/winui.md` which covers project setup, XAML patterns, MVVM, packaging, and UWP migration.

**Version assumptions:** Windows App SDK 1.6+. TFM `net8.0-windows10.0.19041.0`. Mica and Acrylic backdrops require Windows 11 (build 22000+).

## Control Selection

### Forms and Settings

| Control | When to use |
|---------|------------|
| `TextBox` | Single-line or multi-line plain text (names, free-form input) |
| `NumberBox` | Numeric input with optional spin buttons, validation, and inline equation evaluation |
| `PasswordBox` | Masked input for passwords, PINs, SSNs. Built-in reveal button via `PasswordRevealMode` |
| `ComboBox` | Pick one item from a long list (states, countries). Starts compact, expands on interaction |
| `ToggleSwitch` | Binary on/off setting with immediate effect. Use instead of a single checkbox for settings |
| `RadioButtons` | Pick one from 2-4 mutually exclusive options. Use the `RadioButtons` group control, not raw `RadioButton` |
| `CalendarDatePicker` | Pick a single date from a contextual dropdown calendar |
| `TimePicker` | Pick a single time value with hour/minute/AM-PM spinners |

```xml
<!-- Settings form: essential controls -->
<StackPanel Spacing="16" Padding="24">
    <TextBox Header="Display Name" Text="{x:Bind ViewModel.DisplayName, Mode=TwoWay}" />
    <NumberBox Header="Font Size" Value="{x:Bind ViewModel.FontSize, Mode=TwoWay}"
               Minimum="8" Maximum="72" SpinButtonPlacementMode="Inline" />
    <ComboBox Header="Region" ItemsSource="{x:Bind ViewModel.Regions}"
              SelectedItem="{x:Bind ViewModel.SelectedRegion, Mode=TwoWay}" />
    <ToggleSwitch Header="Dark Mode" IsOn="{x:Bind ViewModel.IsDarkMode, Mode=TwoWay}" />
</StackPanel>
```

### Command Surfaces

**CommandBar** provides layout for primary and secondary commands with automatic overflow handling.

```xml
<CommandBar DefaultLabelPosition="Right">
    <AppBarButton Icon="Add" Label="New" Command="{x:Bind ViewModel.NewCommand}" />
    <AppBarButton Icon="Save" Label="Save" Command="{x:Bind ViewModel.SaveCommand}" />
    <AppBarSeparator />
    <AppBarButton Icon="Delete" Label="Delete" Command="{x:Bind ViewModel.DeleteCommand}" />

    <CommandBar.SecondaryCommands>
        <AppBarButton Label="Export" Command="{x:Bind ViewModel.ExportCommand}" />
        <AppBarButton Label="Settings" Command="{x:Bind ViewModel.SettingsCommand}" />
    </CommandBar.SecondaryCommands>
</CommandBar>
```

Key properties: `PrimaryCommands` (always visible), `SecondaryCommands` (overflow menu), `IsOpen` (programmatic expand), `DefaultLabelPosition` (`Right`, `Bottom`, `Collapsed`).

### Large Collections

| Control | Layout | Built-in features |
|---------|--------|-------------------|
| `ListView` | Vertical stack | Selection, reorder, incremental loading, built-in ScrollViewer |
| `GridView` | Horizontal wrap grid | Same as ListView but items flow left-to-right, then wrap |
| `ItemsRepeater` | Custom (StackLayout, UniformGridLayout, or custom) | None -- no selection, no built-in ScrollViewer. Must wrap in ScrollViewer manually |

**When to use ItemsRepeater:** Building a custom collection control where you need full layout control. It provides virtualization but no interaction policy. You must provide your own ScrollViewer, selection logic, and visual states.

```xml
<!-- ItemsRepeater with explicit ScrollViewer -->
<ScrollViewer>
    <ItemsRepeater ItemsSource="{x:Bind ViewModel.Items}"
                   Layout="{StaticResource MyUniformGridLayout}">
        <ItemsRepeater.ItemTemplate>
            <DataTemplate x:DataType="models:Item">
                <Grid Padding="8">
                    <TextBlock Text="{x:Bind Name}" />
                </Grid>
            </DataTemplate>
        </ItemsRepeater.ItemTemplate>
    </ItemsRepeater>
</ScrollViewer>
```

### Filtering and Search

| Control | Purpose |
|---------|---------|
| `AutoSuggestBox` | Text input with a dropdown suggestion list that filters as the user types. Handle `TextChanged`, `SuggestionChosen`, and `QuerySubmitted` events |
| `SelectorBar` | Switch between a small fixed set of views (e.g., Recent / Shared / Favorites). One item selected at a time |
| `BreadcrumbBar` | Show the navigation path to the current location. Items collapse into an ellipsis flyout when space is limited |

### Dialogs and Notifications

| Control | Purpose | Lifetime |
|---------|---------|----------|
| `ContentDialog` | Modal dialog requiring user decision. Use for confirmations, destructive actions, or blocking inputs | Until user dismisses |
| `InfoBar` | Persistent inline status notification. Use for connectivity loss, update availability, or background task completion | Until user closes or condition resolves |
| `TeachingTip` | Contextual onboarding tip anchored to a UI element. Supports light-dismiss. Use for first-run hints | Transient |

### Navigation

| Control | Purpose |
|---------|---------|
| `NavigationView` | Primary app navigation with left pane or top bar. Supports Compact and Minimal display modes. Adapts to window width automatically |
| `TabView` | Tabbed document interface. Users can open, close, reorder, and tear off tabs |

**Pivot is deprecated.** Removed from WinUI 3 starting with Project Reunion 0.5 Preview. Use `TabView` for tabbed content or `NavigationView` with top pane for section switching.


## ScrollViewer Ownership

**Rule:** Only one scroll owner per direction in the visual tree. Nesting a `ListView` or `GridView` inside a `ScrollViewer` in the same scroll direction causes conflicts -- the inner control's built-in ScrollViewer fights the outer one for scroll input.

### Symptoms of Nested ScrollViewer Conflicts

- Items render but do not scroll
- Scroll jumps or stutters as two scrollers compete
- Virtualization breaks because the inner control expands to full height (no viewport constraint)

### Fixes

**Option 1 -- Remove the outer ScrollViewer.** Let the collection control manage its own scrolling.

**Option 2 -- Use ItemsRepeater.** It has no built-in ScrollViewer, so you provide exactly one:

```xml
<!-- Correct: single scroll owner -->
<ScrollViewer>
    <StackPanel>
        <TextBlock Text="Header" Style="{StaticResource TitleTextBlockStyle}" />
        <ItemsRepeater ItemsSource="{x:Bind ViewModel.Items}" />
    </StackPanel>
</ScrollViewer>
```

**Option 3 -- Constrain the inner control height.** Give the ListView/GridView a fixed `Height` or `MaxHeight` so it scrolls independently within a bounded region:

```xml
<ScrollViewer>
    <StackPanel>
        <TextBlock Text="Other content" />
        <ListView ItemsSource="{x:Bind ViewModel.Items}" MaxHeight="400" />
        <TextBlock Text="More content below" />
    </StackPanel>
</ScrollViewer>
```


## Adaptive Layout

### Effective Pixels and Resolution Independence

WinUI uses effective pixels (epx), not physical pixels. The system scales UI automatically based on display DPI so that a 24 epx font is legible on both a phone screen at arm's length and a large monitor across the room. Design in effective pixels and let the platform handle scaling.

### VisualStateManager with AdaptiveTrigger

`AdaptiveTrigger` applies visual states declaratively based on window dimensions. No need to handle `SizeChanged` manually.

```xml
<Page>
    <VisualStateManager.VisualStateGroups>
        <VisualStateGroup>
            <!-- Wide: side-by-side layout -->
            <VisualState x:Name="WideState">
                <VisualState.StateTriggers>
                    <AdaptiveTrigger MinWindowWidth="1008" />
                </VisualState.StateTriggers>
                <VisualState.Setters>
                    <Setter Target="ContentGrid.Orientation" Value="Horizontal" />
                    <Setter Target="SidePanel.Visibility" Value="Visible" />
                    <Setter Target="ContentGrid.Padding" Value="48,24" />
                </VisualState.Setters>
            </VisualState>

            <!-- Narrow: stacked, minimal padding -->
            <VisualState x:Name="NarrowState">
                <VisualState.StateTriggers>
                    <AdaptiveTrigger MinWindowWidth="0" />
                </VisualState.StateTriggers>
                <VisualState.Setters>
                    <Setter Target="ContentGrid.Orientation" Value="Vertical" />
                    <Setter Target="SidePanel.Visibility" Value="Collapsed" />
                    <Setter Target="ContentGrid.Padding" Value="16,8" />
                </VisualState.Setters>
            </VisualState>
        </VisualStateGroup>
    </VisualStateManager.VisualStateGroups>

    <StackPanel x:Name="ContentGrid" Orientation="Horizontal" Padding="48,24">
        <StackPanel x:Name="SidePanel" Width="300">
            <!-- Sidebar content -->
        </StackPanel>
        <Grid>
            <!-- Main content -->
        </Grid>
    </StackPanel>
</Page>
```

### Breakpoint Planning

| Breakpoint | MinWindowWidth | Typical layout |
|-----------|----------------|----------------|
| Wide | 1008 epx | Side-by-side panels, full padding, expanded navigation |
| Medium | 641 epx | Single column, reduced padding, navigation pane visible |
| Narrow | 0 epx | Stacked content, minimal padding, hide secondary controls |

### Responsive NavigationView

`NavigationView` adapts automatically via `CompactModeThresholdWidth` and `ExpandedModeThresholdWidth`. At narrow widths it switches to `LeftMinimal` (hamburger button only).

```xml
<NavigationView x:Name="NavView" PaneDisplayMode="Auto">
    <!-- PaneDisplayMode="Auto" enables automatic adaptation -->
    <!-- CompactModeThresholdWidth defaults to 641 -->
    <!-- ExpandedModeThresholdWidth defaults to 1008 -->
</NavigationView>
```


## Theme Support

WinUI 3 supports Light, Dark, and HighContrast themes out of the box. All built-in controls automatically adjust their visuals when the theme changes.

### ThemeResource vs StaticResource

- **`{ThemeResource}`** -- Re-evaluated when the theme changes at runtime. Use for all color and brush references that should adapt to light/dark/high-contrast.
- **`{StaticResource}`** -- Evaluated once at load time. Use for non-theme-dependent values (font families, spacing constants, styles).

```xml
<!-- Correct: brush adapts when user switches theme -->
<Border Background="{ThemeResource CardBackgroundFillColorDefaultBrush}" />

<!-- Wrong: brush is locked to the value resolved at load time -->
<Border Background="{StaticResource CardBackgroundFillColorDefaultBrush}" />
```

### Setting the App Theme

Set `RequestedTheme` on `Application` in App.xaml to override the system default. `RequestedTheme` on `Application` can only be set at startup -- setting it after launch throws `NotSupportedException`. To allow runtime theme switching, set `RequestedTheme` on individual `FrameworkElement` instances:

```csharp
// Switch theme at runtime for the entire window content
(Content as FrameworkElement).RequestedTheme = ElementTheme.Dark;
```

### Detecting Theme Changes

Use `ActualThemeChanged` to react when the effective theme changes:

```csharp
rootElement.ActualThemeChanged += (sender, _) =>
{
    var currentTheme = ((FrameworkElement)sender).ActualTheme;
    // Update non-XAML visuals, analytics, or custom rendering
};
```

### Custom Theme Dictionaries

Define per-theme resources using `ThemeDictionaries` with keys `Default` (Dark), `Light`, and `HighContrast`:

```xml
<ResourceDictionary.ThemeDictionaries>
    <ResourceDictionary x:Key="Light">
        <SolidColorBrush x:Key="AppHeaderBrush" Color="#F3F3F3" />
    </ResourceDictionary>
    <ResourceDictionary x:Key="Default">
        <SolidColorBrush x:Key="AppHeaderBrush" Color="#2D2D2D" />
    </ResourceDictionary>
    <ResourceDictionary x:Key="HighContrast">
        <SolidColorBrush x:Key="AppHeaderBrush"
                         Color="{ThemeResource SystemColorWindowColor}" />
    </ResourceDictionary>
</ResourceDictionary.ThemeDictionaries>
```

Note: In `ThemeDictionaries`, use `{ThemeResource}` in the `HighContrast` dictionary (system colors update dynamically) and `{StaticResource}` in `Light`/`Default` dictionaries to avoid shared-brush pollution across theme sub-trees.


## Materials

Materials are visual effects that add depth and hierarchy to surfaces.

### Mica

An opaque material that incorporates the user's desktop wallpaper and theme. Use for **long-lived base surfaces** such as the main window background.

```xml
<!-- XAML: set Mica as window backdrop -->
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
    <Window.SystemBackdrop>
        <MicaBackdrop />
    </Window.SystemBackdrop>
    <!-- Content here -- set Background="Transparent" on root to see Mica -->
</Window>
```

```csharp
// Code-behind: set Mica with MicaKind
SystemBackdrop = new MicaBackdrop { Kind = MicaKind.Base };
```

**MicaKind.Base** -- Standard Mica, slightly tinted by wallpaper. Best for the primary window surface.

**MicaKind.BaseAlt** -- Darker, more subdued variant. Use when the content layer on top needs stronger contrast (e.g., card pattern with `LayerFillColorDefaultBrush`).

### Acrylic

A semi-transparent frosted-glass material. Use for **transient, light-dismiss surfaces** such as flyouts, context menus, and dialog overlays.

```xml
<Window.SystemBackdrop>
    <DesktopAcrylicBackdrop />
</Window.SystemBackdrop>
```

For in-app acrylic on specific UI elements (not the window background), use `AcrylicBrush` theme resources directly on panels or controls.

### Fallback Behavior

On Windows 10 or systems that do not support composition effects, Mica and Acrylic fall back to a solid color automatically. No special handling is needed, but test on Windows 10 to verify the fallback appearance is acceptable.

**Rules:**
- Apply backdrop material only once per window. Do not layer multiple backdrop materials.
- Set `Background="Transparent"` on all layers between the window and the content area where Mica should show through.
- Mica should be visible in the title bar -- extend content into the non-client area for a seamless look.


## System Brushes

Use system brushes instead of hard-coded colors. They adapt to Light, Dark, and HighContrast themes automatically.

| Category | Brush | Purpose |
|----------|-------|---------|
| Surface | `CardBackgroundFillColorDefaultBrush` | Card surface backgrounds |
| Surface | `CardStrokeColorDefaultBrush` | Card border/outline |
| Surface | `LayerFillColorDefaultBrush` | Content layer on top of Mica |
| Surface | `LayerOnMicaBaseAltFillColorDefaultBrush` | Content layer on Mica BaseAlt |
| Surface | `SolidBackgroundFillColorBaseBrush` | Solid opaque background when transparency is not desired |
| Text | `TextFillColorPrimaryBrush` | Primary text (titles, body) |
| Text | `TextFillColorSecondaryBrush` | Secondary text (subtitles, descriptions) |
| Text | `TextFillColorTertiaryBrush` | Tertiary text (hints, placeholders, disabled labels) |

Always reference these via `{ThemeResource}` markup extension:

```xml
<Border Background="{ThemeResource CardBackgroundFillColorDefaultBrush}"
        BorderBrush="{ThemeResource CardStrokeColorDefaultBrush}"
        BorderThickness="1" CornerRadius="8" Padding="16">
    <TextBlock Text="Product Name"
               Foreground="{ThemeResource TextFillColorPrimaryBrush}"
               Style="{StaticResource BodyStrongTextBlockStyle}" />
</Border>
```


## Typography

**Segoe UI Variable** is the default WinUI 3 system font. It adjusts weight and optical size dynamically. Do not override the font family unless the app has specific branding requirements.

### Type Ramp

| Style | Weight | Size (epx) |
|-------|--------|-----------|
| `CaptionTextBlockStyle` | Regular | 12 |
| `BodyTextBlockStyle` | Regular | 14 |
| `BodyStrongTextBlockStyle` | Semibold | 14 |
| `BodyLargeTextBlockStyle` | Regular | 18 |
| `SubtitleTextBlockStyle` | Semibold | 20 |
| `TitleTextBlockStyle` | Semibold | 28 |
| `TitleLargeTextBlockStyle` | Semibold | 40 |
| `DisplayTextBlockStyle` | Semibold | 68 |

**Typography rules:** Use sentence casing for all UI text. Minimum legible size: 14 epx Regular or 12 epx Semibold. Do not hard-code font sizes -- always use the type ramp styles for consistency and accessibility scaling.


## Icons

**Segoe Fluent Icons** is the icon font for WinUI 3 apps. Use it for consistency with the Windows shell.

```xml
<!-- FontIcon with unicode glyph -->
<FontIcon FontFamily="{StaticResource SymbolThemeFontFamily}" Glyph="&#xE721;" />

<!-- SymbolIcon for common symbols -->
<SymbolIcon Symbol="Save" />

<!-- In AppBarButton -->
<AppBarButton Icon="Add" Label="New Item" />
```

`SymbolIcon` provides a simplified API for common icons. Use `FontIcon` with the Glyph property for the full Segoe Fluent Icons set. For custom icons, use `PathIcon` or `BitmapIcon` and match the visual weight of Segoe Fluent Icons.

**Rules:** Keep visual weight consistent across all icons in a surface. Do not mix filled and outline variants randomly. Use a single icon font throughout the app.


## Resource Organization

Group custom brushes, typography overrides, and spacing values into dedicated resource dictionary files under a `Styles/` directory:

```xml
<Application.Resources>
    <ResourceDictionary>
        <ResourceDictionary.MergedDictionaries>
            <XamlControlsResources xmlns="using:Microsoft.UI.Xaml.Controls" />
            <ResourceDictionary Source="Styles/Colors.xaml" />
            <ResourceDictionary Source="Styles/Typography.xaml" />
            <ResourceDictionary Source="Styles/Spacing.xaml" />
        </ResourceDictionary.MergedDictionaries>
    </ResourceDictionary>
</Application.Resources>
```

**Rules:** Always include `<XamlControlsResources />` first in `MergedDictionaries`. Do not scatter theme overrides across page-level resource dictionaries. Use `x:Key` names following the WinUI naming convention (`[Category][Property][State]Brush`).


## Anti-patterns

1. **Do not nest ScrollViewers in the same scroll direction.** This breaks virtualization and causes erratic scrolling. Use ItemsRepeater with a single ScrollViewer or constrain inner control height.
2. **Do not hard-code colors.** Hard-coded hex values break Dark mode and HighContrast accessibility. Use `{ThemeResource}` system brushes.
3. **Do not use `{StaticResource}` for theme-dependent brushes.** The brush value will not update when the user switches between Light and Dark mode at runtime.
4. **Do not use Pivot.** It is deprecated and removed from WinUI 3. Use `TabView` or `NavigationView` with top pane mode.
5. **Do not hard-code pixel widths for responsive layouts.** Use `AdaptiveTrigger` with `MinWindowWidth` and flexible layout panels. Hard-coded widths break on different screen sizes and DPI settings.
6. **Do not hard-code font sizes.** Use the type ramp styles (`BodyTextBlockStyle`, `CaptionTextBlockStyle`, etc.) to maintain visual hierarchy and support accessibility text scaling.
7. **Do not wrap cards inside cards.** Nesting elements that both use `CardBackgroundFillColorDefaultBrush` creates a double-border effect that muddles visual hierarchy.
8. **Do not set `Application.RequestedTheme` after app launch.** It throws `NotSupportedException`. Use `FrameworkElement.RequestedTheme` for runtime theme changes.


## References

- [Controls for Windows apps](https://learn.microsoft.com/windows/apps/develop/ui/controls/)
- [ListView and GridView](https://learn.microsoft.com/windows/apps/develop/ui/controls/listview-and-gridview)
- [ItemsRepeater](https://learn.microsoft.com/windows/apps/develop/ui/controls/items-repeater)
- [CommandBar](https://learn.microsoft.com/windows/apps/design/controls/command-bar)
- [Responsive layouts with XAML](https://learn.microsoft.com/windows/apps/develop/ui/layouts-with-xaml)
- [Theming in Windows apps](https://learn.microsoft.com/windows/apps/develop/ui/theming)
- [Materials in Windows apps](https://learn.microsoft.com/windows/apps/develop/ui/materials)
- [Apply Mica or Acrylic](https://learn.microsoft.com/windows/apps/develop/ui/system-backdrops)
- [Typography in Windows](https://learn.microsoft.com/windows/apps/design/signature-experiences/typography)
- [Segoe Fluent Icons font](https://learn.microsoft.com/windows/apps/design/style/segoe-fluent-icons-font)
- [Contrast themes](https://learn.microsoft.com/windows/apps/design/accessibility/high-contrast-themes)
