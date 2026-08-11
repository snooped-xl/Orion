using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Primitives;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Threading;
using Avalonia.VisualTree;
using Forms = System.Windows.Forms;
using System.Runtime.InteropServices;

namespace OrbitAvalonia;

public sealed partial class MainWindow
{
    internal const string MidnightId = "midnight";
    internal const string MidnightLegacyId = "legacy";
    internal const string PitchBlackId = "pitchblack";
    internal const string CrimsonId = "crimson";
    internal const string SnowfallId = "snowfall";

    private sealed record ThemeTokenDefinition(string Key, string Label, string Group, string Hint);

    private sealed class ThemeColourRow
    {
        public ThemeColourRow(ThemeTokenDefinition definition, string colour)
        {
            Definition = definition;
            Colour = colour;
        }

        public ThemeTokenDefinition Definition { get; }
        public string Colour { get; set; }
    }

    private sealed record ThemeLiveTarget(Control Control, string TokenKey, string Label);

    private static readonly IReadOnlyList<ThemeTokenDefinition> ThemeTokens =
    [
        new("OrbitChromeStartColor", "Title bar", "Window", "The top of the app"),
        new("OrbitChromeEndColor", "Background", "Window", "The main area behind everything"),
        new("OrbitChromeBorderBrush", "Window outline", "Window", "The solid line around the outer window"),
        new("OrbitRailStartColor", "Sidebar top", "Sidebar", "Top of the side menu"),
        new("OrbitRailEndColor", "Sidebar bottom", "Sidebar", "Bottom of the side menu"),
        new("OrbitBorderBrush", "Page & card stroke", "Outlines", "Solid outlines around pages, editor and cards"),
        new("OrbitControlBorderBrush", "Button stroke", "Outlines", "Solid outlines around clickable buttons"),
        new("OrbitDividerBrush", "Section dividers", "Outlines", "Solid lines between sections"),
        new("OrbitSurfaceStartColor", "Page top", "Pages", "Top of each page"),
        new("OrbitSurfaceEndColor", "Page bottom", "Pages", "Bottom of each page"),
        new("OrbitPanelBrush", "Panels", "Pages", "Settings and popup backgrounds"),
        new("OrbitDeepBrush", "Action bar", "Pages", "The bar at the bottom of pages"),
        new("OrbitEditorBrush", "Code area", "Editor", "Where you write code"),
        new("OrbitChoiceBrush", "Active tab", "Editor", "The background of the active script tab"),
        new("OrbitDeepBrush", "Inactive tab", "Editor", "The background of unselected script tabs"),
        new("OrbitSearchBrush", "Search box", "Buttons", "Where you type to search"),
        new("OrbitCardBrush", "Cards", "Buttons", "Script cards in the hub"),
        new("OrbitCardHoverBrush", "Cards (hover)", "Buttons", "Cards when you hover over them"),
        new("OrbitControlBrush", "Buttons", "Buttons", "All the clickable buttons"),
        new("OrbitControlHoverBrush", "Buttons (hover)", "Buttons", "Buttons when you hover over them"),
        new("OrbitTextBrush", "Main text", "Text", "Headings and titles"),
        new("OrbitSubtextBrush", "Secondary text", "Text", "Labels, descriptions and hints")
    ];

    private readonly List<OrbitThemeProfile> _customThemeProfiles = [];
    private readonly List<ThemeLiveTarget> _themeLiveTargets = [];
    private string _activeThemeId = OrbitThemeStore.LoadActiveThemeId() ?? MidnightId;
    private bool _themeStudioInitialized;
    private bool _themeLiveEditInputReady;
    private bool _themePickerUpdating;
    private Canvas _themeLiveEditOverlay = null!;
    private Border _themeLiveEditHighlight = null!;
    private Border _themeLiveEditBadge = null!;
    private TextBlock _themeLiveEditBadgeText = null!;
    private StackPanel _themesLibraryPanel = null!;
    private ContentControl _themesStudioContentHost = null!;
    private TextBlock _themeStudioStatus = null!;
    private TextBox _themeNameEditor = null!;
    private Flyout? _themeColourFlyout;
    private ScreenColourPickerWindow? _screenColourPicker;

    private void InitializeThemeStudio()
    {
        _themesLibraryPanel = this.FindControl<StackPanel>("ThemesLibraryPanel") ?? new StackPanel();
        _themesStudioContentHost = this.FindControl<ContentControl>("ThemesStudioContentHost") ?? new ContentControl();
        _themeLiveEditOverlay = this.FindControl<Canvas>("ThemeLiveEditOverlay") ?? new Canvas();
        _themeLiveEditHighlight = this.FindControl<Border>("ThemeLiveEditHighlight") ?? new Border();
        _themeLiveEditBadge = this.FindControl<Border>("ThemeLiveEditBadge") ?? new Border();
        _themeLiveEditBadgeText = this.FindControl<TextBlock>("ThemeLiveEditBadgeText") ?? new TextBlock();

        _customThemeProfiles.AddRange(OrbitThemeStore.LoadCustomThemes());
        _themeStudioInitialized = true;
        RegisterThemeLiveTargets();
        SetThemeLiveEditEnabled(OrbitThemeStore.LoadLiveEdit(), updateButton: false);
        RefreshThemeStudio();
        Dispatcher.UIThread.Post(() => _themeLiveEditInputReady = true, DispatcherPriority.Background);

        AddHandler(InputElement.PointerMovedEvent, ThemeLiveEdit_PointerMoved, RoutingStrategies.Tunnel, handledEventsToo: true);
        AddHandler(InputElement.PointerPressedEvent, ThemeLiveEdit_PointerPressed, RoutingStrategies.Tunnel, handledEventsToo: true);
    }

    private void RegisterThemeLiveTargets()
    {
        _themeLiveTargets.Clear();
        if (this.FindControl<Border>("MainWindowChrome") is { } chrome)
            AddThemeLiveTarget(chrome, "OrbitChromeStartColor", "Window chrome");
        if (this.FindControl<Canvas>("EditorPage") is { } editor)
            AddThemeLiveTarget(editor, "OrbitSurfaceStartColor", "Editor page");
        if (this.FindControl<Canvas>("ScriptHubPage") is { } scriptHub)
            AddThemeLiveTarget(scriptHub, "OrbitSurfaceStartColor", "Script Hub page");
        if (this.FindControl<Canvas>("RobotPage") is { } robot)
            AddThemeLiveTarget(robot, "OrbitSurfaceStartColor", "Orbit Chat page");
        if (this.FindControl<Canvas>("SettingsPage") is { } settings)
            AddThemeLiveTarget(settings, "OrbitSurfaceStartColor", "Settings page");
    }

    private void AddThemeLiveTarget(Control control, string tokenKey, string label) =>
        _themeLiveTargets.Add(new ThemeLiveTarget(control, tokenKey, label));

    private IReadOnlyList<OrbitThemeProfile> AllThemeProfiles()
    {
        var builtIn = new[]
        {
            new OrbitThemeProfile { Id = MidnightId, Name = "Midnight Navy", BaseThemeId = MidnightId, Colours = GetThemeDefaults(MidnightId) },
            new OrbitThemeProfile { Id = MidnightLegacyId, Name = "Legacy Graphite", BaseThemeId = MidnightLegacyId, Colours = GetThemeDefaults(MidnightLegacyId) },
            new OrbitThemeProfile { Id = PitchBlackId, Name = "Pitch Black", BaseThemeId = PitchBlackId, Colours = GetThemeDefaults(PitchBlackId) },
            new OrbitThemeProfile { Id = CrimsonId, Name = "Crimson", BaseThemeId = CrimsonId, Colours = GetThemeDefaults(CrimsonId) },
            new OrbitThemeProfile { Id = SnowfallId, Name = "Snowfall", BaseThemeId = SnowfallId, Colours = GetThemeDefaults(SnowfallId) }
        };
        return builtIn.Concat(_customThemeProfiles).ToList();
    }

    private OrbitThemeProfile CurrentThemeProfile() =>
        AllThemeProfiles().FirstOrDefault(theme => theme.Id == _activeThemeId)
        ?? AllThemeProfiles()[0];

    private static Dictionary<string, string> GetThemeDefaults(string themeId)
    {
        if (BuiltInThemePalettes.TryGetValue(themeId, out var palette))
            return new Dictionary<string, string>(palette, StringComparer.Ordinal);

        var legacy = themeId == MidnightLegacyId;
        var values = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var (key, value) in OrbitBrushTheme)
        {
            values[key] = legacy ? value.Legacy : value.Midnight;
        }
        foreach (var (key, value) in OrbitColorTheme)
        {
            values[key] = legacy ? value.Legacy : value.Midnight;
        }
        return values;
    }

    private static readonly IReadOnlyDictionary<string, Dictionary<string, string>> BuiltInThemePalettes =
        new Dictionary<string, Dictionary<string, string>>(StringComparer.Ordinal)
        {
            [PitchBlackId] = new(StringComparer.Ordinal)
            {
                // Window — pure OLED pitch black
                ["OrbitChromeStartColor"] = "#000000",
                ["OrbitChromeEndColor"] = "#000000",
                ["OrbitMainChromeEndColor"] = "#000000",
                ["OrbitChromeBorderBrush"] = "#3A3A3A",
                // Sidebar — pure pitch black
                ["OrbitRailStartColor"] = "#000000",
                ["OrbitRailEndColor"] = "#000000",
                // Surfaces — pure pitch black
                ["OrbitBorderBrush"] = "#242424",
                ["OrbitDividerBrush"] = "#141414",
                ["OrbitSurfaceStartColor"] = "#000000",
                ["OrbitSurfaceEndColor"] = "#000000",
                ["OrbitPanelBrush"] = "#040404",
                ["OrbitDeepBrush"] = "#000000",
                // Editor — pure pitch black
                ["OrbitEditorBrush"] = "#000000",
                // Controls — pure pitch black with sharp outlines
                ["OrbitSearchBrush"] = "#040404",
                ["OrbitCardBrush"] = "#040404",
                ["OrbitCardHoverBrush"] = "#0D0D0D",
                ["OrbitControlBrush"] = "#040404",
                ["OrbitControlHoverBrush"] = "#0F0F0F",
                ["OrbitControlPressedBrush"] = "#000000",
                ["OrbitControlBorderBrush"] = "#2A2A2A",
                ["OrbitChoiceBrush"] = "#080808",
                ["OrbitChoiceDisabledBrush"] = "#000000",
                ["OrbitChoiceDisabledBorderBrush"] = "#181818",
                ["OrbitChoiceDisabledHoverBrush"] = "#050505",
                ["OrbitChoiceDisabledHoverBorderBrush"] = "#202020",
                ["OrbitRaisedBrush"] = "#040404",
                ["OrbitChipBrush"] = "#000000",
                ["OrbitDialogHeaderBrush"] = "#040404",
                ["OrbitDialogStartColor"] = "#040404",
                ["OrbitDialogMidColor"] = "#020202",
                ["OrbitDialogEndColor"] = "#000000",
                ["OrbitInputBrush"] = "#000000",
                ["OrbitMutedSurfaceBrush"] = "#030303",
                ["OrbitCloseBackdropBrush"] = "#000000",
                ["OrbitTextBrush"] = "#FFFFFF",
                ["OrbitSubtextBrush"] = "#888888",
                ["OrbitMutedTextBrush"] = "#555555"
            },
            [CrimsonId] = new(StringComparer.Ordinal)
            {
                // Window — same darkness as navy but red-shifted
                ["OrbitChromeStartColor"] = "#1C0E12",
                ["OrbitChromeEndColor"] = "#120810",
                ["OrbitMainChromeEndColor"] = "#100710",
                ["OrbitChromeBorderBrush"] = "#6B3545",
                // Sidebar
                ["OrbitRailStartColor"] = "#241218",
                ["OrbitRailEndColor"] = "#130910",
                // Surfaces
                ["OrbitBorderBrush"] = "#3A1E2A",
                ["OrbitDividerBrush"] = "#2A1520",
                ["OrbitSurfaceStartColor"] = "#140A10",
                ["OrbitSurfaceEndColor"] = "#0F070C",
                ["OrbitPanelBrush"] = "#160B12",
                ["OrbitDeepBrush"] = "#0A050A",
                // Editor
                ["OrbitEditorBrush"] = "#0E0710",
                // Controls
                ["OrbitSearchBrush"] = "#1C0F16",
                ["OrbitCardBrush"] = "#180C14",
                ["OrbitCardHoverBrush"] = "#261420",
                ["OrbitControlBrush"] = "#170C13",
                ["OrbitControlHoverBrush"] = "#22121C",
                ["OrbitControlPressedBrush"] = "#0E0710",
                ["OrbitControlBorderBrush"] = "#4A2535",
                ["OrbitChoiceBrush"] = "#150B12",
                ["OrbitChoiceDisabledBrush"] = "#120910",
                ["OrbitChoiceDisabledBorderBrush"] = "#301A24",
                ["OrbitChoiceDisabledHoverBrush"] = "#170C14",
                ["OrbitChoiceDisabledHoverBorderBrush"] = "#3A2030",
                ["OrbitRaisedBrush"] = "#160B12",
                ["OrbitChipBrush"] = "#0F0810",
                ["OrbitDialogHeaderBrush"] = "#1A0E16",
                ["OrbitDialogStartColor"] = "#1E1018",
                ["OrbitDialogMidColor"] = "#160B14",
                ["OrbitDialogEndColor"] = "#0F080E",
                ["OrbitInputBrush"] = "#0F0810",
                ["OrbitMutedSurfaceBrush"] = "#110910",
                ["OrbitCloseBackdropBrush"] = "#0E0710"
            },
            [SnowfallId] = new(StringComparer.Ordinal)
            {
                // Window — light/white theme
                ["OrbitChromeStartColor"] = "#F0F2F5",
                ["OrbitChromeEndColor"] = "#E4E7EC",
                ["OrbitMainChromeEndColor"] = "#E0E3E8",
                ["OrbitChromeBorderBrush"] = "#C0C6D0",
                // Sidebar
                ["OrbitRailStartColor"] = "#E8EBF0",
                ["OrbitRailEndColor"] = "#DDE0E6",
                // Surfaces
                ["OrbitBorderBrush"] = "#D0D4DC",
                ["OrbitDividerBrush"] = "#D5D9E0",
                ["OrbitSurfaceStartColor"] = "#F5F6F8",
                ["OrbitSurfaceEndColor"] = "#EEF0F4",
                ["OrbitPanelBrush"] = "#EBEDF2",
                ["OrbitDeepBrush"] = "#E0E2E8",
                // Editor
                ["OrbitEditorBrush"] = "#FAFBFC",
                // Controls
                ["OrbitSearchBrush"] = "#ECEEF2",
                ["OrbitCardBrush"] = "#F0F1F4",
                ["OrbitCardHoverBrush"] = "#E4E6EC",
                ["OrbitControlBrush"] = "#E8EAF0",
                ["OrbitControlHoverBrush"] = "#DDE0E8",
                ["OrbitControlPressedBrush"] = "#D4D8E0",
                ["OrbitControlBorderBrush"] = "#C4CAD4",
                ["OrbitChoiceBrush"] = "#ECEEF3",
                ["OrbitChoiceDisabledBrush"] = "#E8EAF0",
                ["OrbitChoiceDisabledBorderBrush"] = "#D0D4DC",
                ["OrbitChoiceDisabledHoverBrush"] = "#E4E7EE",
                ["OrbitChoiceDisabledHoverBorderBrush"] = "#C8CCD6",
                ["OrbitRaisedBrush"] = "#ECEFF3",
                ["OrbitChipBrush"] = "#E6E9EF",
                ["OrbitDialogHeaderBrush"] = "#EDEEF3",
                ["OrbitDialogStartColor"] = "#F2F3F6",
                ["OrbitDialogMidColor"] = "#ECEFF3",
                ["OrbitDialogEndColor"] = "#E6E9EE",
                ["OrbitInputBrush"] = "#F4F5F8",
                ["OrbitMutedSurfaceBrush"] = "#F0F2F5",
                ["OrbitCloseBackdropBrush"] = "#ECEEF2"
            }
        };

    private void ApplyActiveThemeOverrides()
    {
        if (_activeThemeId.StartsWith("custom-", StringComparison.Ordinal))
        {
            var profile = _customThemeProfiles.FirstOrDefault(theme => theme.Id == _activeThemeId);
            if (profile is null) return;
            foreach (var (key, value) in profile.Colours)
            {
                ApplyThemeColourResource(key, value);
            }
        }
        else if (BuiltInThemePalettes.TryGetValue(_activeThemeId, out var palette))
        {
            foreach (var (key, value) in palette)
            {
                ApplyThemeColourResource(key, value);
            }
        }
    }

    private void ApplyThemeColourResource(string key, string value)
    {
        if (!TryNormalizeHex(value, out var normalized)) return;
        var colour = Color.Parse(normalized);
        if (OrbitBrushTheme.ContainsKey(key))
        {
            Resources[key] = new SolidColorBrush(colour);
        }
        else if (OrbitColorTheme.ContainsKey(key))
        {
            Resources[key] = colour;
        }
    }

    private void RefreshThemeStudio()
    {
        if (!_themeStudioInitialized) return;
        RebuildThemeLibrary();
        _themesStudioContentHost.Content = BuildThemeStudioContent(CurrentThemeProfile());
    }

    private IBrush FindThemeBrush(string key, string fallbackHex) =>
        Resources.TryGetValue(key, out var res) && res is IBrush brush ? brush : Brush(fallbackHex);

    private void RebuildThemeLibrary()
    {
        _themesLibraryPanel.Children.Clear();
        foreach (var profile in AllThemeProfiles())
        {
            var selected = profile.Id == _activeThemeId;
            var isCustom = profile.Id.StartsWith("custom-", StringComparison.Ordinal);

            var selectButton = new Button
            {
                Height = 46,
                HorizontalAlignment = HorizontalAlignment.Stretch,
                HorizontalContentAlignment = HorizontalAlignment.Stretch,
                VerticalContentAlignment = VerticalAlignment.Center,
                Padding = new Thickness(12, 6, isCustom ? 36 : 12, 6),
                Background = selected ? FindThemeBrush("OrbitChoiceBrush", "#0E1523") : FindThemeBrush("OrbitControlBrush", "#0F1726"),
                BorderBrush = selected ? FindThemeBrush("OrbitChromeBorderBrush", "#435675") : FindThemeBrush("OrbitControlBorderBrush", "#28364F"),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(10),
                Content = new StackPanel
                {
                    Spacing = 2,
                    VerticalAlignment = VerticalAlignment.Center,
                    Children =
                    {
                        new TextBlock { Text = profile.Name, FontSize = 11.5, FontWeight = FontWeight.SemiBold, Foreground = FindThemeBrush("OrbitTextBrush", "#FFFFFF"), TextTrimming = TextTrimming.CharacterEllipsis },
                        new TextBlock { Text = isCustom ? "Custom palette" : "Built-in palette", FontSize = 9.5, Foreground = FindThemeBrush("OrbitSubtextBrush", "#7F8CA2"), TextTrimming = TextTrimming.CharacterEllipsis }
                    }
                }
            };
            selectButton.Click += (_, _) => SelectTheme(profile.Id);

            if (!isCustom)
            {
                _themesLibraryPanel.Children.Add(selectButton);
                continue;
            }

            var row = new Grid
            {
                Height = 46,
                ColumnDefinitions = new ColumnDefinitions("*,Auto")
            };
            Grid.SetColumn(selectButton, 0);
            row.Children.Add(selectButton);

            var deleteButton = new Button
            {
                Width = 28,
                Height = 28,
                Padding = new Thickness(0),
                Margin = new Thickness(0, 9, 6, 9),
                HorizontalContentAlignment = HorizontalAlignment.Center,
                VerticalContentAlignment = VerticalAlignment.Center,
                Background = Brushes.Transparent,
                BorderBrush = Brushes.Transparent,
                BorderThickness = new Thickness(0),
                Content = new Viewbox
                {
                    Width = 12,
                    Height = 14,
                    Child = new Avalonia.Controls.Shapes.Path
                    {
                        Fill = Brush("#7787A0"),
                        Data = Geometry.Parse("M1 3H4V2C4 0.9 4.9 0 6 0H12C13.1 0 14 0.9 14 2V3H17C17.55 3 18 3.45 18 4C18 4.55 17.55 5 17 5H16V18C16 19.1 15.1 20 14 20H4C2.9 20 2 19.1 2 18V5H1C0.45 5 0 4.55 0 4C0 3.45 0.45 3 1 3ZM4 5V18H14V5H4ZM6 3H12V2H6V3ZM6 7H8V16H6V7ZM10 7H12V16H10V7Z")
                    }
                }
            };
            ToolTip.SetTip(deleteButton, "Delete custom theme");
            deleteButton.PointerEntered += (_, _) => deleteButton.Background = Brush("#3A1D27");
            deleteButton.PointerExited += (_, _) => deleteButton.Background = Brushes.Transparent;
            deleteButton.Click += (_, _) => DeleteCustomTheme(profile.Id);
            Grid.SetColumn(deleteButton, 1);
            row.Children.Add(deleteButton);
            _themesLibraryPanel.Children.Add(row);
        }
    }

    private Control BuildThemeStudioContent(OrbitThemeProfile profile)
    {
        var isCustom = profile.Id.StartsWith("custom-", StringComparison.Ordinal);
        var root = new Grid
        {
            Margin = new Thickness(24, 20, 24, 16),
            RowDefinitions = new RowDefinitions("Auto,*,Auto"),
            RowSpacing = 16
        };

        // ── Header ──
        var header = new StackPanel { Spacing = 14 };

        // Title row: heading + action buttons
        var titleRow = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto,Auto"), ColumnSpacing = 8 };
        var titleText = new TextBlock { Text = "Theme studio", FontSize = 20, FontWeight = FontWeight.SemiBold, Foreground = FindThemeBrush("OrbitTextBrush", "#FFFFFF"), VerticalAlignment = VerticalAlignment.Center };
        Grid.SetColumn(titleText, 0);
        titleRow.Children.Add(titleText);

        var liveButton = ThemeActionButton(OrbitThemeStore.LoadLiveEdit() ? "Live edit · On" : "Live edit · Off");
        liveButton.Click += (_, _) => SetThemeLiveEditEnabled(!OrbitThemeStore.LoadLiveEdit(), updateButton: true);
        Grid.SetColumn(liveButton, 1);
        titleRow.Children.Add(liveButton);

        var resetButton = ThemeActionButton("Reset all");
        resetButton.Click += (_, _) => ResetActiveTheme();
        Grid.SetColumn(resetButton, 2);
        titleRow.Children.Add(resetButton);
        header.Children.Add(titleRow);

        // Theme name + status
        var infoRow = new Grid { ColumnDefinitions = new ColumnDefinitions("Auto,*"), ColumnSpacing = 12 };
        _themeNameEditor = new TextBox
        {
            Width = 160,
            Height = 32,
            Text = profile.Name,
            FontSize = 11,
            Padding = new Thickness(10, 0),
            VerticalContentAlignment = VerticalAlignment.Center,
            Classes = { "orbit-dialog-input" }
        };
        _themeNameEditor.LostFocus += (_, _) => CommitThemeName();
        _themeNameEditor.KeyDown += (_, args) =>
        {
            if (args.Key == Key.Enter) CommitThemeName();
        };
        Grid.SetColumn(_themeNameEditor, 0);
        infoRow.Children.Add(_themeNameEditor);

        _themeStudioStatus = new TextBlock
        {
            FontSize = 10,
            Foreground = FindThemeBrush("OrbitSubtextBrush", "#7F8CA2"),
            VerticalAlignment = VerticalAlignment.Center,
            Text = isCustom ? "Your changes save automatically" : "Pick a colour to start customising"
        };
        Grid.SetColumn(_themeStudioStatus, 1);
        infoRow.Children.Add(_themeStudioStatus);
        header.Children.Add(infoRow);

        Grid.SetRow(header, 0);
        root.Children.Add(header);

        // ── Colour palette ──
        var paletteScroll = new ScrollViewer
        {
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto
        };
        var palette = new StackPanel { Spacing = 12 };
        var grouped = ThemeTokens.GroupBy(token => token.Group);
        foreach (var group in grouped)
        {
            var card = new Border
            {
                Background = FindThemeBrush("OrbitPanelBrush", "#0C1527"),
                BorderBrush = FindThemeBrush("OrbitBorderBrush", "#1C2B44"),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(12),
                Padding = new Thickness(18, 14, 18, 14)
            };
            var cardStack = new StackPanel { Spacing = 0 };
            cardStack.Children.Add(new TextBlock
            {
                Text = group.Key.ToUpperInvariant(),
                FontSize = 10,
                FontWeight = FontWeight.SemiBold,
                Foreground = FindThemeBrush("OrbitSubtextBrush", "#55698A"),
                LetterSpacing = 1.2,
                Margin = new Thickness(0, 0, 0, 10)
            });
            var rows = group.ToList();
            for (var i = 0; i < rows.Count; i++)
            {
                var token = rows[i];
                var colour = profile.Colours.TryGetValue(token.Key, out var value) ? value : GetThemeDefaults(profile.BaseThemeId).GetValueOrDefault(token.Key, "#202A3A");
                cardStack.Children.Add(BuildThemeColourRow(new ThemeColourRow(token, colour), isLast: i == rows.Count - 1));
            }
            card.Child = cardStack;
            palette.Children.Add(card);
        }
        paletteScroll.Content = palette;
        Grid.SetRow(paletteScroll, 1);
        root.Children.Add(paletteScroll);

        // ── Footer ──
        var footerText = new TextBlock
        {
            Text = "Turn on Live edit to pick colours right on the app.",
            FontSize = 10,
            Foreground = FindThemeBrush("OrbitMutedTextBrush", "#55698A"),
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new Thickness(0, 4, 0, 0)
        };
        Grid.SetRow(footerText, 2);
        root.Children.Add(footerText);
        return root;
    }

    private Control BuildThemeColourRow(ThemeColourRow row, bool isLast = false)
    {
        var wrapper = new StackPanel { Spacing = 0 };
        var grid = new Grid
        {
            ColumnDefinitions = new ColumnDefinitions("*,Auto"),
            ColumnSpacing = 16,
            MinHeight = 44,
            Margin = new Thickness(0, 1)
        };

        // Label + hint
        var label = new StackPanel { Spacing = 2, VerticalAlignment = VerticalAlignment.Center };
        label.Children.Add(new TextBlock { Text = row.Definition.Label, FontSize = 12, Foreground = FindThemeBrush("OrbitTextBrush", "#FFFFFF") });
        label.Children.Add(new TextBlock { Text = row.Definition.Hint, FontSize = 9.5, Foreground = FindThemeBrush("OrbitMutedTextBrush", "#4E6280") });
        Grid.SetColumn(label, 0);
        grid.Children.Add(label);

        // Colour swatch button
        var swatch = new Button
        {
            Width = 120,
            Height = 34,
            Padding = new Thickness(0),
            HorizontalContentAlignment = HorizontalAlignment.Center,
            VerticalContentAlignment = VerticalAlignment.Center,
            Background = Brush(row.Colour),
            BorderBrush = FindThemeBrush("OrbitControlBorderBrush", "#2A3B56"),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(8),
            Content = new TextBlock { Text = row.Colour, FontSize = 11, Foreground = ContrastBrush(row.Colour), HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center }
        };
        swatch.Click += (_, _) => OpenThemeColourFlyout(row, swatch);
        Grid.SetColumn(swatch, 1);
        grid.Children.Add(swatch);

        wrapper.Children.Add(grid);
        if (!isLast)
        {
            wrapper.Children.Add(new Border { Height = 1, Background = FindThemeBrush("OrbitDividerBrush", "#111B2C"), Margin = new Thickness(4, 3, 4, 3) });
        }
        return wrapper;
    }

    private Button ThemeActionButton(string text) => new()
    {
        Content = new TextBlock
        {
            Text = text,
            TextTrimming = TextTrimming.CharacterEllipsis,
            VerticalAlignment = VerticalAlignment.Center
        },
        Height = 32,
        MinWidth = 60,
        Padding = new Thickness(12, 0),
        Classes = { "plugin-action" },
        HorizontalContentAlignment = HorizontalAlignment.Center,
        VerticalContentAlignment = VerticalAlignment.Center
    };

    private void SelectTheme(string id)
    {
        if (string.Equals(_activeThemeId, id, StringComparison.Ordinal)) return;
        _activeThemeId = id;
        OrbitThemeStore.SaveActiveThemeId(id);
        OrbitPreferences.SetLegacyColours(id == MidnightLegacyId);
        ApplyOrbitColourScheme(id == MidnightLegacyId, refreshGeneratedControls: true);
        RefreshThemeStudio();
    }

    private void ThemesCreate_Click(object? sender, RoutedEventArgs e)
    {
        var source = CurrentThemeProfile();
        var profile = new OrbitThemeProfile
        {
            Id = OrbitThemeStore.NewId(),
            Name = source.Name + " Copy",
            BaseThemeId = source.Id == MidnightLegacyId ? MidnightLegacyId : MidnightId,
            Colours = new Dictionary<string, string>(source.Colours, StringComparer.Ordinal)
        };
        _customThemeProfiles.Add(profile);
        _activeThemeId = profile.Id;
        OrbitThemeStore.SaveCustomThemes(_customThemeProfiles);
        OrbitThemeStore.SaveActiveThemeId(_activeThemeId);
        OrbitPreferences.SetLegacyColours(false);
        ApplyOrbitColourScheme(false, refreshGeneratedControls: true);
        RefreshThemeStudio();
    }

    private void CommitThemeName()
    {
        var profile = _customThemeProfiles.FirstOrDefault(theme => theme.Id == _activeThemeId);
        if (profile is null || string.IsNullOrWhiteSpace(_themeNameEditor.Text)) return;
        profile.Name = _themeNameEditor.Text.Trim();
        OrbitThemeStore.SaveCustomThemes(_customThemeProfiles);
        RebuildThemeLibrary();
        _themeStudioStatus.Text = "Name saved";
    }

    private void ResetActiveTheme()
    {
        var profile = CurrentThemeProfile();
        if (profile.Id.StartsWith("custom-", StringComparison.Ordinal))
        {
            profile.Colours = GetThemeDefaults(profile.BaseThemeId);
            OrbitThemeStore.SaveCustomThemes(_customThemeProfiles);
            ApplyOrbitColourScheme(false, refreshGeneratedControls: false);
        }
        else
        {
            ApplyOrbitColourScheme(profile.Id == MidnightLegacyId, refreshGeneratedControls: true);
        }
        RefreshThemeStudio();
    }

    private void DeleteCustomTheme(string id)
    {
        if (!id.StartsWith("custom-", StringComparison.Ordinal)) return;
        if (_customThemeProfiles.All(theme => theme.Id != id)) return;

        var deletingActive = _activeThemeId == id;
        _customThemeProfiles.RemoveAll(theme => theme.Id == id);
        OrbitThemeStore.SaveCustomThemes(_customThemeProfiles);
        if (deletingActive)
        {
            _activeThemeId = MidnightId;
            OrbitThemeStore.SaveActiveThemeId(_activeThemeId);
            OrbitPreferences.SetLegacyColours(false);
            ApplyOrbitColourScheme(false, refreshGeneratedControls: true);
        }
        RefreshThemeStudio();
    }

    private void ResetThemeToken(string key)
    {
        var profile = EnsureEditableTheme();
        var baseId = profile.BaseThemeId;
        if (!GetThemeDefaults(baseId).TryGetValue(key, out var value)) return;
        profile.Colours[key] = value;
        ApplyThemeColourResource(key, value);
        OrbitThemeStore.SaveCustomThemes(_customThemeProfiles);
        RefreshThemeStudio();
    }

    private OrbitThemeProfile EnsureEditableTheme()
    {
        var existing = _customThemeProfiles.FirstOrDefault(theme => theme.Id == _activeThemeId);
        if (existing is not null) return existing;

        var source = CurrentThemeProfile();
        var profile = new OrbitThemeProfile
        {
            Id = OrbitThemeStore.NewId(),
            Name = source.Name + " Custom",
            BaseThemeId = source.Id == MidnightLegacyId ? MidnightLegacyId : MidnightId,
            Colours = new Dictionary<string, string>(source.Colours, StringComparer.Ordinal)
        };
        _customThemeProfiles.Add(profile);
        _activeThemeId = profile.Id;
        OrbitThemeStore.SaveCustomThemes(_customThemeProfiles);
        OrbitThemeStore.SaveActiveThemeId(_activeThemeId);
        OrbitPreferences.SetLegacyColours(false);
        RebuildThemeLibrary();
        return profile;
    }

    private void OpenThemeColourFlyout(ThemeColourRow row, Control anchor)
    {
        var profile = EnsureEditableTheme();
        if (!profile.Colours.TryGetValue(row.Definition.Key, out var colour)) colour = row.Colour;
        if (!TryNormalizeHex(colour, out var normalized)) normalized = "#202A3A";
        var hex = new TextBox { Text = normalized, Height = 32, Classes = { "orbit-dialog-input" }, PlaceholderText = "#RRGGBB" };
        var preview = new Border { Width = 42, Height = 42, CornerRadius = new CornerRadius(10), Background = Brush(normalized), BorderBrush = Brush("#435675"), BorderThickness = new Thickness(1) };
        var status = new TextBlock { FontSize = 9, Foreground = Brush("#7F8CA2"), Text = row.Definition.Label };

        var spectrum = new ThemeSpectrumControl { Height = 144, HorizontalAlignment = HorizontalAlignment.Stretch };
        var hueStrip = new ThemeHueStrip { Width = 20, Height = 144 };
        spectrum.SetColor(Color.Parse(normalized));
        hueStrip.SetHue(spectrum.Hue);

        void SetPickerColour(Color value, string message = "Live · saved")
        {
            var valueHex = ToHex(value);
            hex.Text = valueHex;
            ApplyThemePickerValue(row, valueHex, preview);
            status.Text = message;
        }

        spectrum.ColorChanged += (_, value) =>
        {
            hueStrip.SetHue(spectrum.Hue);
            SetPickerColour(value);
        };
        hueStrip.HueChanged += (_, hue) =>
        {
            spectrum.SetHue(hue, raiseChanged: false);
            SetPickerColour(spectrum.CurrentColour);
        };

        var spectrumGrid = new Grid
        {
            Height = 144,
            ColumnDefinitions = new ColumnDefinitions("*,20"),
            ColumnSpacing = 8
        };
        var spectrumFrame = new Border
        {
            CornerRadius = new CornerRadius(9),
            BorderBrush = Brush("#435675"),
            BorderThickness = new Thickness(1),
            ClipToBounds = true,
            Child = spectrum
        };
        Grid.SetColumn(spectrumFrame, 0);
        spectrumGrid.Children.Add(spectrumFrame);
        var hueFrame = new Border
        {
            CornerRadius = new CornerRadius(9),
            BorderBrush = Brush("#435675"),
            BorderThickness = new Thickness(1),
            ClipToBounds = true,
            Child = hueStrip
        };
        Grid.SetColumn(hueFrame, 1);
        spectrumGrid.Children.Add(hueFrame);

        var swatches = new WrapPanel { Orientation = Orientation.Horizontal, ItemWidth = 27, ItemHeight = 27, Margin = new Thickness(0, 4, 0, 0) };
        foreach (var value in QuickThemeSwatches)
        {
            var swatch = new Button { Width = 22, Height = 22, Margin = new Thickness(0, 0, 5, 5), Padding = new Thickness(0), Background = Brush(value), BorderBrush = Brush("#435675"), BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(6) };
            swatch.Click += (_, _) => SetPickerColour(Color.Parse(value), "Swatch selected");
            swatches.Children.Add(swatch);
        }

        var copyButton = ThemeActionButton("Copy hex");
        copyButton.Height = 28;
        copyButton.Click += async (_, _) =>
        {
            if (string.IsNullOrWhiteSpace(hex.Text)) return;
            await Dispatcher.UIThread.InvokeAsync(() => Forms.Clipboard.SetText(hex.Text));
            status.Text = "Copied";
        };
        var screenButton = ThemeActionButton("Pick from screen");
        screenButton.Height = 28;
        screenButton.Click += (_, _) =>
        {
            status.Text = "Move over a colour and click · Esc cancels";
            _screenColourPicker?.Close();
            var picker = new ScreenColourPickerWindow(this);
            _screenColourPicker = picker;
            picker.Picked += (_, value) =>
            {
                SetPickerColour(value, "Picked from screen");
                _screenColourPicker = null;
            };
            picker.Cancelled += (_, _) =>
            {
                status.Text = "Screen pick cancelled";
                _screenColourPicker = null;
            };
            picker.Closed += (_, _) =>
            {
                if (ReferenceEquals(_screenColourPicker, picker)) _screenColourPicker = null;
            };
            picker.Show(this);
        };
        var resetButton = ThemeActionButton("Reset colour");
        resetButton.Height = 28;
        resetButton.Click += (_, _) =>
        {
            var defaults = GetThemeDefaults(profile.BaseThemeId);
            if (defaults.TryGetValue(row.Definition.Key, out var value))
            {
                SetPickerColour(Color.Parse(value), "Reset to base");
            }
        };

        var actions = new Grid { ColumnDefinitions = new ColumnDefinitions("*,*,*"), ColumnSpacing = 6 };
        Grid.SetColumn(copyButton, 0); actions.Children.Add(copyButton);
        Grid.SetColumn(screenButton, 1); actions.Children.Add(screenButton);
        Grid.SetColumn(resetButton, 2); actions.Children.Add(resetButton);
        var body = new StackPanel { Width = 286, Spacing = 8 };
        var top = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10, Children = { preview, new StackPanel { Spacing = 2, Children = { new TextBlock { Text = "Colour", FontSize = 13, Foreground = Brushes.White }, status } } } };
        body.Children.Add(top);
        body.Children.Add(spectrumGrid);
        body.Children.Add(hex);
        body.Children.Add(swatches);
        body.Children.Add(actions);
        hex.TextChanged += (_, _) =>
        {
            if (!TryNormalizeHex(hex.Text ?? string.Empty, out var value)) return;
            var parsed = Color.Parse(value);
            spectrum.SetColor(parsed);
            hueStrip.SetHue(spectrum.Hue);
            ApplyThemePickerValue(row, value, preview);
            status.Text = "Live · saved";
        };

        _themePickerUpdating = false;
        var flyout = new Flyout { Content = new Border { Padding = new Thickness(14), Background = Brush("#10192B"), BorderBrush = Brush("#435675"), BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(14), Child = body } };
        _themeColourFlyout = flyout;
        flyout.Closed += (_, _) =>
        {
            _themeColourFlyout = null;
            RefreshThemeStudio();
        };
        flyout.ShowAt(anchor);
    }

    private void ApplyThemePickerValue(ThemeColourRow row, string raw, Border preview)
    {
        if (_themePickerUpdating || !TryNormalizeHex(raw, out var normalized)) return;
        _themePickerUpdating = true;
        try
        {
            var profile = EnsureEditableTheme();
            profile.Colours[row.Definition.Key] = normalized;
            row.Colour = normalized;
            preview.Background = Brush(normalized);
            ApplyThemeColourResource(row.Definition.Key, normalized);
            OrbitThemeStore.SaveCustomThemes(_customThemeProfiles);
            _themeStudioStatus.Text = "Live · saved";
        }
        finally
        {
            _themePickerUpdating = false;
        }
    }

    private void SetThemeLiveEditEnabled(bool enabled, bool updateButton)
    {
        OrbitThemeStore.SaveLiveEdit(enabled);
        _themeLiveEditOverlay.IsVisible = enabled;
        _themeLiveEditBadge.IsVisible = enabled;
        _themeLiveEditHighlight.IsVisible = false;
        if (updateButton) RefreshThemeStudio();
    }

    private void ThemeLiveEdit_PointerMoved(object? sender, PointerEventArgs e)
    {
        if (!_themeLiveEditInputReady || !OrbitThemeStore.LoadLiveEdit() || !_mainInterface.IsVisible) return;
        var target = FindThemeLiveTarget(e.GetPosition(_mainInterface));
        if (target is null)
        {
            _themeLiveEditHighlight.IsVisible = false;
            return;
        }

        var point = target.Control.TranslatePoint(new Point(0, 0), _mainInterface);
        if (point is null)
        {
            _themeLiveEditHighlight.IsVisible = false;
            return;
        }
        Canvas.SetLeft(_themeLiveEditHighlight, point.Value.X - 3);
        Canvas.SetTop(_themeLiveEditHighlight, point.Value.Y - 3);
        _themeLiveEditHighlight.Width = target.Control.Bounds.Width + 6;
        _themeLiveEditHighlight.Height = target.Control.Bounds.Height + 6;
        _themeLiveEditHighlight.IsVisible = true;
        _themeLiveEditBadgeText.Text = $"LIVE EDIT  ·  {target.Label}";
    }

    private void ThemeLiveEdit_PointerPressed(object? sender, PointerPressedEventArgs e)
    {
        if (!_themeLiveEditInputReady || !OrbitThemeStore.LoadLiveEdit() || e.GetCurrentPoint(this).Properties.PointerUpdateKind != PointerUpdateKind.LeftButtonPressed) return;
        if (IsInteractiveThemeSource(e.Source as Visual)) return;
        var target = FindThemeLiveTarget(e.GetPosition(_mainInterface));
        if (target is null) return;
        e.Handled = true;
        var token = ThemeTokens.FirstOrDefault(item => item.Key == target.TokenKey);
        if (token is null) return;
        var row = new ThemeColourRow(token, CurrentThemeProfile().Colours.GetValueOrDefault(token.Key, "#202A3A"));
        OpenThemeColourFlyout(row, target.Control);
    }

    private ThemeLiveTarget? FindThemeLiveTarget(Point point)
    {
        ThemeLiveTarget? best = null;
        var bestArea = double.MaxValue;
        foreach (var target in _themeLiveTargets)
        {
            if (!IsThemeTargetVisible(target.Control)) continue;
            var topLeft = target.Control.TranslatePoint(new Point(0, 0), _mainInterface);
            if (topLeft is null) continue;
            var rect = new Rect(topLeft.Value, target.Control.Bounds.Size);
            if (!rect.Contains(point)) continue;
            var area = Math.Max(1, rect.Width * rect.Height);
            if (area < bestArea)
            {
                best = target;
                bestArea = area;
            }
        }
        return best;
    }

    private static bool IsThemeTargetVisible(Control control)
    {
        for (Visual? current = control; current is not null; current = current.GetVisualParent())
        {
            if (current is Control parent && !parent.IsVisible) return false;
        }
        return control.Bounds.Width > 2 && control.Bounds.Height > 2;
    }

    private static bool IsInteractiveThemeSource(Visual? source)
    {
        for (Visual? current = source; current is not null; current = current.GetVisualParent())
        {
            if (current is Button or TextBox or Slider or ScrollViewer) return true;
        }
        return false;
    }

    private static SolidColorBrush Brush(string hex) => new(Color.Parse(hex));

    private static IBrush ContrastBrush(string hex)
    {
        if (!TryNormalizeHex(hex, out var normalized)) return Brushes.White;
        var colour = Color.Parse(normalized);
        var luminance = (0.299 * colour.R) + (0.587 * colour.G) + (0.114 * colour.B);
        return luminance > 158 ? Brushes.Black : Brushes.White;
    }

    private static bool TryNormalizeHex(string raw, out string normalized)
    {
        normalized = string.Empty;
        raw = raw.Trim();
        if (!raw.StartsWith('#')) raw = "#" + raw;
        try
        {
            var colour = Color.Parse(raw);
            normalized = $"#{colour.R:X2}{colour.G:X2}{colour.B:X2}";
            return true;
        }
        catch (FormatException) { return false; }
    }

    private static string ToHex(Color colour) => $"#{colour.R:X2}{colour.G:X2}{colour.B:X2}";

    private sealed class ThemeSpectrumControl : Control
    {
        private double _hue;
        private double _saturation;
        private double _value;

        public event EventHandler<Color>? ColorChanged;

        public double Hue => _hue;
        public Color CurrentColour => HsvColor.ToRgb(_hue, _saturation, _value, 1);

        public void SetColor(Color colour)
        {
            var hsv = colour.ToHsv();
            _hue = hsv.H;
            _saturation = hsv.S;
            _value = hsv.V;
            InvalidateVisual();
        }

        public void SetHue(double hue, bool raiseChanged = true)
        {
            _hue = NormalizeHue(hue);
            InvalidateVisual();
            if (raiseChanged) ColorChanged?.Invoke(this, CurrentColour);
        }

        protected override void OnPointerPressed(PointerPressedEventArgs e)
        {
            base.OnPointerPressed(e);
            if (!e.GetCurrentPoint(this).Properties.IsLeftButtonPressed) return;
            e.Pointer.Capture(this);
            SetFromPointer(e.GetPosition(this));
            e.Handled = true;
        }

        protected override void OnPointerMoved(PointerEventArgs e)
        {
            base.OnPointerMoved(e);
            if (!e.GetCurrentPoint(this).Properties.IsLeftButtonPressed) return;
            SetFromPointer(e.GetPosition(this));
            e.Handled = true;
        }

        protected override void OnPointerReleased(PointerReleasedEventArgs e)
        {
            base.OnPointerReleased(e);
            e.Pointer.Capture(null);
        }

        private void SetFromPointer(Point point)
        {
            if (Bounds.Width <= 0 || Bounds.Height <= 0) return;
            _saturation = Math.Clamp(point.X / Bounds.Width, 0, 1);
            _value = 1 - Math.Clamp(point.Y / Bounds.Height, 0, 1);
            InvalidateVisual();
            ColorChanged?.Invoke(this, CurrentColour);
        }

        public override void Render(DrawingContext context)
        {
            base.Render(context);
            var rect = new Rect(Bounds.Size);
            if (rect.Width <= 0 || rect.Height <= 0) return;

            var hue = HsvColor.ToRgb(_hue, 1, 1, 1);
            var horizontal = new LinearGradientBrush
            {
                StartPoint = new RelativePoint(0, 0, RelativeUnit.Relative),
                EndPoint = new RelativePoint(1, 0, RelativeUnit.Relative),
                GradientStops = new GradientStops
                {
                    new(Colors.White, 0),
                    new(hue, 1)
                }
            };
            context.FillRectangle(horizontal, rect);

            var vertical = new LinearGradientBrush
            {
                StartPoint = new RelativePoint(0, 0, RelativeUnit.Relative),
                EndPoint = new RelativePoint(0, 1, RelativeUnit.Relative),
                GradientStops = new GradientStops
                {
                    new(Color.FromArgb(0, 0, 0, 0), 0),
                    new(Color.FromArgb(255, 0, 0, 0), 1)
                }
            };
            context.FillRectangle(vertical, rect);

            var point = new Point(_saturation * rect.Width, (1 - _value) * rect.Height);
            context.DrawEllipse(null, new Pen(Brushes.Black, 3), point, 6, 6);
            context.DrawEllipse(null, new Pen(Brushes.White, 1.5), point, 6, 6);
        }

        private static double NormalizeHue(double hue)
        {
            hue %= 360;
            return hue < 0 ? hue + 360 : hue;
        }
    }

    private sealed class ThemeHueStrip : Control
    {
        private double _hue;

        public event EventHandler<double>? HueChanged;
        public double Hue => _hue;

        public void SetHue(double hue)
        {
            _hue = NormalizeHue(hue);
            InvalidateVisual();
        }

        protected override void OnPointerPressed(PointerPressedEventArgs e)
        {
            base.OnPointerPressed(e);
            if (!e.GetCurrentPoint(this).Properties.IsLeftButtonPressed) return;
            e.Pointer.Capture(this);
            SetFromPointer(e.GetPosition(this));
            e.Handled = true;
        }

        protected override void OnPointerMoved(PointerEventArgs e)
        {
            base.OnPointerMoved(e);
            if (!e.GetCurrentPoint(this).Properties.IsLeftButtonPressed) return;
            SetFromPointer(e.GetPosition(this));
            e.Handled = true;
        }

        protected override void OnPointerReleased(PointerReleasedEventArgs e)
        {
            base.OnPointerReleased(e);
            e.Pointer.Capture(null);
        }

        private void SetFromPointer(Point point)
        {
            if (Bounds.Height <= 0) return;
            _hue = NormalizeHue(Math.Clamp(point.Y / Bounds.Height, 0, 1) * 360);
            InvalidateVisual();
            HueChanged?.Invoke(this, _hue);
        }

        public override void Render(DrawingContext context)
        {
            base.Render(context);
            var rect = new Rect(Bounds.Size);
            if (rect.Width <= 0 || rect.Height <= 0) return;
            var stops = new GradientStops();
            for (var index = 0; index <= 6; index++)
            {
                stops.Add(new GradientStop(HsvColor.ToRgb(index * 60, 1, 1, 1), index / 6d));
            }
            context.FillRectangle(new LinearGradientBrush
            {
                StartPoint = new RelativePoint(0, 0, RelativeUnit.Relative),
                EndPoint = new RelativePoint(0, 1, RelativeUnit.Relative),
                GradientStops = stops
            }, rect);

            var y = Math.Clamp(_hue / 360, 0, 1) * rect.Height;
            context.DrawLine(new Pen(Brushes.White, 2), new Point(0, y), new Point(rect.Width, y));
        }

        private static double NormalizeHue(double hue)
        {
            hue %= 360;
            return hue < 0 ? hue + 360 : hue;
        }
    }

    private sealed class ScreenColourPickerWindow : Window
    {
        private readonly MainWindow _owner;

        public event EventHandler<Color>? Picked;
        public event EventHandler? Cancelled;

        public ScreenColourPickerWindow(MainWindow owner)
        {
            _owner = owner;
            Background = Brushes.Transparent;
            TransparencyLevelHint = [WindowTransparencyLevel.Transparent];
            WindowDecorations = WindowDecorations.None;
            ShowInTaskbar = false;
            CanResize = false;
            Topmost = true;
            WindowStartupLocation = WindowStartupLocation.Manual;
            Cursor = new Cursor(StandardCursorType.Cross);
            Content = new Border { Background = Brushes.Transparent };
            ConfigureBounds();
            Opened += (_, _) => Focus();
            PointerPressed += OnPointerPressed;
            KeyDown += OnKeyDown;
        }

        private void ConfigureBounds()
        {
            var screens = _owner.Screens.All;
            if (screens.Count == 0) return;
            var left = screens.Min(screen => screen.Bounds.X);
            var top = screens.Min(screen => screen.Bounds.Y);
            var right = screens.Max(screen => screen.Bounds.Right);
            var bottom = screens.Max(screen => screen.Bounds.Bottom);
            var scaling = Math.Max(1, (_owner.Screens.ScreenFromWindow(_owner) ?? _owner.Screens.Primary ?? screens[0]).Scaling);
            Position = new PixelPoint(left, top);
            Width = Math.Max(1, (right - left) / scaling);
            Height = Math.Max(1, (bottom - top) / scaling);
        }

        private void OnPointerPressed(object? sender, PointerPressedEventArgs e)
        {
            if (!e.GetCurrentPoint(this).Properties.IsLeftButtonPressed) return;
            if (TrySampleScreen(out var colour))
            {
                Picked?.Invoke(this, colour);
            }
            else
            {
                Cancelled?.Invoke(this, EventArgs.Empty);
            }
            e.Handled = true;
            Close();
        }

        private void OnKeyDown(object? sender, KeyEventArgs e)
        {
            if (e.Key != Key.Escape) return;
            Cancelled?.Invoke(this, EventArgs.Empty);
            e.Handled = true;
            Close();
        }

        private static bool TrySampleScreen(out Color colour)
        {
            colour = Colors.Transparent;
            if (!GetCursorPos(out var point)) return false;
            var hdc = GetDC(IntPtr.Zero);
            if (hdc == IntPtr.Zero) return false;
            try
            {
                var pixel = GetPixel(hdc, point.X, point.Y);
                if (pixel == 0xFFFFFFFF) return false;
                colour = Color.FromRgb((byte)(pixel & 0xFF), (byte)((pixel >> 8) & 0xFF), (byte)((pixel >> 16) & 0xFF));
                return true;
            }
            finally
            {
                ReleaseDC(IntPtr.Zero, hdc);
            }
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct NativePoint
        {
            public int X;
            public int Y;
        }

        [DllImport("user32.dll")]
        private static extern bool GetCursorPos(out NativePoint point);

        [DllImport("user32.dll")]
        private static extern IntPtr GetDC(IntPtr hWnd);

        [DllImport("user32.dll")]
        private static extern int ReleaseDC(IntPtr hWnd, IntPtr hDc);

        [DllImport("gdi32.dll")]
        private static extern uint GetPixel(IntPtr hDc, int x, int y);
    }

    private static readonly string[] QuickThemeSwatches =
    [
        "#FFFFFF", "#000000", "#0B1220", "#16233B", "#243B63", "#435675",
        "#5F82B4", "#8DB7FF", "#7DD3FC", "#8B5CF6", "#22C55E", "#F59E0B",
        "#EF4444", "#EC4899", "#6B7280", "#A5A1A2"
    ];
}
