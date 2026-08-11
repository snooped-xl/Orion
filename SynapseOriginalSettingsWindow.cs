using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Primitives;
using Avalonia.Input;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Media.Imaging;
using Avalonia.Platform;
using Avalonia.Threading;

namespace OrbitAvalonia;

internal static class SynapseOriginalCompanionUi
{
    internal const string WindowBackground = "#232323";
    internal const string PanelBackground = "#282828";
    internal const string RowBackground = "#282827";
    internal const string RowBorder = "#313131";
    internal const string ChipBackground = "#272727";
    internal const string ChipBorder = "#323232";
    internal const string ActiveBackground = "#323232";
    internal const string ActiveBorder = "#3A3A3A";
    internal const string MutedText = "#A3A3A3";

    private static readonly Lazy<Bitmap> Logo = new(() =>
    {
        using var stream = AssetLoader.Open(
            new Uri("avares://Orion/Assets/Synapse/classic-wordmark.png"));
        return new Bitmap(stream);
    });

    internal static SolidColorBrush Brush(string value) => new(Color.Parse(value));

    internal static Grid BuildChrome(
        Window window,
        Control body,
        string? title,
        bool showClose)
    {
        var root = new Grid
        {
            Background = Brush(WindowBackground),
            RowDefinitions = new RowDefinitions("58,*")
        };
        var header = new Grid
        {
            Height = 58,
            Background = Brush(PanelBackground),
            ClipToBounds = true
        };
        header.PointerPressed += (_, args) =>
        {
            if (!args.GetCurrentPoint(window).Properties.IsLeftButtonPressed)
            {
                return;
            }
            if (args.ClickCount == 2 && window.CanResize)
            {
                window.WindowState = window.WindowState == WindowState.Maximized
                    ? WindowState.Normal
                    : WindowState.Maximized;
                return;
            }
            window.BeginMoveDrag(args);
        };

        var logo = new Image
        {
            Source = Logo.Value,
            Width = 126,
            Height = 26,
            Stretch = Stretch.Uniform,
            HorizontalAlignment = HorizontalAlignment.Left,
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new Thickness(6, 0, 0, 0)
        };
        RenderOptions.SetBitmapInterpolationMode(logo, BitmapInterpolationMode.HighQuality);
        header.Children.Add(logo);

        if (!string.IsNullOrWhiteSpace(title))
        {
            header.Children.Add(new TextBlock
            {
                Text = title,
                FontFamily = new FontFamily("avares://Avalonia.Fonts.Inter/Assets#Inter"),
                FontSize = 14,
                FontWeight = FontWeight.Normal,
                Foreground = Brushes.White,
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center,
                Margin = new Thickness(64, 0, 64, 0),
                TextTrimming = TextTrimming.CharacterEllipsis
            });
        }

        if (showClose)
        {
            var close = new Button
            {
                Content = "X",
                Width = 28,
                Height = 58,
                HorizontalAlignment = HorizontalAlignment.Right,
                Background = Brushes.Transparent,
                BorderThickness = new Thickness(0),
                Foreground = Brushes.White,
                FontSize = 13,
                Padding = new Thickness(0),
                CornerRadius = new CornerRadius(0)
            };
            close.PointerEntered += (_, _) => close.Background = Brush("#383838");
            close.PointerExited += (_, _) => close.Background = Brushes.Transparent;
            close.Click += (_, _) => window.Close();
            header.Children.Add(close);
        }

        root.Children.Add(header);
        Grid.SetRow(body, 1);
        root.Children.Add(body);
        return root;
    }

    internal static Button CreateButton(
        object content,
        double height,
        double? width = null,
        double fontSize = 13)
    {
        var button = new Button
        {
            Content = content,
            Height = height,
            Width = width ?? double.NaN,
            HorizontalAlignment = HorizontalAlignment.Stretch,
            HorizontalContentAlignment = HorizontalAlignment.Center,
            VerticalContentAlignment = VerticalAlignment.Center,
            Background = Brush(ChipBackground),
            BorderBrush = Brush(ChipBorder),
            BorderThickness = new Thickness(1),
            Foreground = Brushes.White,
            FontFamily = new FontFamily("avares://Avalonia.Fonts.Inter/Assets#Inter"),
            FontSize = fontSize,
            FontWeight = FontWeight.Normal,
            Padding = new Thickness(5, 0),
            CornerRadius = new CornerRadius(0)
        };
        button.PointerEntered += (_, _) => button.Background = Brush("#303030");
        button.PointerExited += (_, _) => button.Background = Brush(ChipBackground);
        return button;
    }
}

internal sealed class SynapseOriginalSettingsWindow : Window
{
    private readonly SynapseFrontendWindow _owner;
    private readonly Button _generalButton;
    private readonly Button _themeButton;
    private readonly ScrollViewer _scroller;
    private readonly StackPanel _generalPanel;
    private readonly StackPanel _themePanel;
    private bool _generalSelected = true;

    internal SynapseOriginalSettingsWindow(SynapseFrontendWindow owner)
    {
        _owner = owner;
        Width = 649;
        Height = 705;
        MinWidth = 649;
        MinHeight = 705;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        WindowDecorations = WindowDecorations.None;
        ExtendClientAreaToDecorationsHint = true;
        Background = SynapseOriginalCompanionUi.Brush(SynapseOriginalCompanionUi.WindowBackground);
        Topmost = OrbitPreferences.TopMostEnabled;
        Title = "Settings & Clients";
        FontFamily = new FontFamily("avares://Avalonia.Fonts.Inter/Assets#Inter");
        ApplyResizablePreference(OrbitPreferences.ResizableEnabled);

        _generalPanel = BuildGeneralPanel();
        _themePanel = BuildThemePanel();
        _scroller = new ScrollViewer
        {
            Content = _generalPanel,
            Padding = new Thickness(12),
            Background = SynapseOriginalCompanionUi.Brush(SynapseOriginalCompanionUi.WindowBackground),
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled
        };

        _generalButton = CreateNavButton("General");
        _themeButton = CreateNavButton("Theme");
        _generalButton.Click += (_, _) => ShowGeneral();
        _themeButton.Click += (_, _) => ShowTheme();
        _generalButton.PointerExited += (_, _) => RefreshNavigation();
        _themeButton.PointerExited += (_, _) => RefreshNavigation();
        var navStack = new StackPanel
        {
            Width = 94,
            Margin = new Thickness(8),
            Spacing = 4
        };
        navStack.Children.Add(_generalButton);
        navStack.Children.Add(_themeButton);
        var nav = new Border
        {
            Width = 110,
            Background = SynapseOriginalCompanionUi.Brush(SynapseOriginalCompanionUi.PanelBackground),
            BorderBrush = SynapseOriginalCompanionUi.Brush("#424242"),
            BorderThickness = new Thickness(0, 0, 1, 0),
            Child = navStack
        };

        var close = SynapseOriginalCompanionUi.CreateButton("Close", 29, 88);
        close.Click += (_, _) => Close();
        var footer = new Border
        {
            Height = 45,
            BorderBrush = SynapseOriginalCompanionUi.Brush("#424242"),
            BorderThickness = new Thickness(0, 1, 0, 0),
            Padding = new Thickness(12, 8),
            Child = new Grid
            {
                Children =
                {
                    new StackPanel
                    {
                        Orientation = Orientation.Horizontal,
                        HorizontalAlignment = HorizontalAlignment.Right,
                        Children = { close }
                    }
                }
            }
        };

        var main = new Grid { RowDefinitions = new RowDefinitions("*,45") };
        main.Children.Add(_scroller);
        Grid.SetRow(footer, 1);
        main.Children.Add(footer);
        var body = new Grid
        {
            Background = SynapseOriginalCompanionUi.Brush(SynapseOriginalCompanionUi.WindowBackground),
            ColumnDefinitions = new ColumnDefinitions("110,*")
        };
        body.Children.Add(nav);
        Grid.SetColumn(main, 1);
        body.Children.Add(main);
        Content = SynapseOriginalCompanionUi.BuildChrome(
            this,
            body,
            "Settings & Clients",
            showClose: true);
        RefreshNavigation();
        Opened += (_, _) => Dispatcher.UIThread.Post(ShowGeneral, DispatcherPriority.Loaded);
    }

    internal void ApplyResizablePreference(bool enabled)
    {
        CanResize = enabled;
        MaxWidth = enabled ? double.PositiveInfinity : 649;
        MaxHeight = enabled ? double.PositiveInfinity : 705;
    }

    private void ShowGeneral()
    {
        _generalSelected = true;
        _scroller.Content = _generalPanel;
        _scroller.Offset = Vector.Zero;
        RefreshNavigation();
    }

    private void ShowTheme()
    {
        _generalSelected = false;
        _scroller.Content = _themePanel;
        _scroller.Offset = Vector.Zero;
        RefreshNavigation();
    }

    private void RefreshNavigation()
    {
        SetNavState(_generalButton, _generalSelected);
        SetNavState(_themeButton, !_generalSelected);
    }

    private static Button CreateNavButton(string label)
    {
        return SynapseOriginalCompanionUi.CreateButton(label, 30, 94, 13);
    }

    private static void SetNavState(Button button, bool active)
    {
        button.Background = SynapseOriginalCompanionUi.Brush(
            active ? SynapseOriginalCompanionUi.ActiveBackground : SynapseOriginalCompanionUi.PanelBackground);
        button.BorderBrush = SynapseOriginalCompanionUi.Brush(
            active ? SynapseOriginalCompanionUi.ActiveBorder : SynapseOriginalCompanionUi.ChipBorder);
    }

    private StackPanel BuildGeneralPanel()
    {
        var panel = new StackPanel { Spacing = 8 };
        panel.Children.Add(CreateToggleRow("Auto Attach", "Automatically attach to any client(s).", false));
        panel.Children.Add(CreateToggleRow("Auto Open", "Open Orion automatically after the shell finishes loading.", false));
        panel.Children.Add(CreateToggleRow("Loading Screen", "Play the Synapse 2017 loading sequence when the shell changes.", true));
        panel.Children.Add(CreateToggleRow("Auto Update", "Check for updates when Orion starts.", false));
        panel.Children.Add(CreateToggleRow(
            "Top Most",
            "All Synapse windows to stay on top.",
            OrbitPreferences.TopMostEnabled,
            enabled =>
            {
                OrbitPreferences.SetTopMost(enabled);
                _owner.ApplySynapseOriginalTopMostPreference(enabled);
                Topmost = enabled;
            }));
        panel.Children.Add(CreateToggleRow(
            "Enhanced List",
            "Search, sections, bookmarks, gists, row actions, and full script-list theming.",
            false));
        panel.Children.Add(CreateToggleRow("Minimap", "Show a miniature preview of the entire script on the right side.", false));
        panel.Children.Add(CreateToggleRow(
            "Error Logging",
            "EXPERIMENTAL - CAN SHOW FALSE ERRORS. Displays syntax errors inside the editor using a Luau diagnostics engine.",
            false));
        panel.Children.Add(CreateToggleRow(
            "Resizable",
            "Allow dragging the OG main window edges to resize. Off snaps it back to the default 838×372.",
            OrbitPreferences.ResizableEnabled,
            enabled =>
            {
                OrbitPreferences.SetResizable(enabled);
                _owner.ApplySynapseOriginalResizablePreference(enabled);
            }));
        panel.Children.Add(CreateStatusRow("Bridge Method", "One bridge script that connects Orion to your executor.", "UNIFIED", "#008B00"));
        panel.Children.Add(CreateToggleRow("Edge Curve", "Apply Windows 11 rounded corners to OG windows. Off makes the corners sharp and square.", false));
        panel.Children.Add(CreateStatusRow("Synapse X", "Switch to the Synapse X UI.", "OFF", "#860000"));
        panel.Children.Add(CreateStatusRow("Synapse Blue", "Return to the Synapse Blue desktop UI.", "OFF", "#860000"));
        panel.Children.Add(CreateStatusRow("Synapse v3", "Switch to the Synapse v3 UI.", "OFF", "#860000"));
        panel.Children.Add(CreateStatusRow("Setup", "Go back to the first-time setup wizard.", "OPEN", "#B0D8E5"));
        return panel;
    }

    private static StackPanel BuildThemePanel()
    {
        var panel = new StackPanel { Spacing = 8 };
        panel.Children.Add(CreateThemeIntro());
        panel.Children.Add(CreateSectionTitle("Core Colors"));
        panel.Children.Add(CreateColorRow("Window background", "Outer fill behind buttons and the editor.", "#232323"));
        panel.Children.Add(CreateColorRow("Panel background", "Top bar, side panels, and script-list surfaces.", "#282828"));
        panel.Children.Add(CreateColorRow("Text", "Title-bar titles, labels, and headers.", "#FFFFFF"));
        panel.Children.Add(CreateSectionTitle("Buttons"));
        panel.Children.Add(CreateColorRow("Button Background", "Normal state for buttons.", "#272727"));
        panel.Children.Add(CreateColorRow("Button Hover", "Hover state for buttons.", "#303030"));
        panel.Children.Add(CreateColorRow("Button Border", "Border around buttons.", "#2D2D2D"));
        panel.Children.Add(CreateColorRow("Button Text", "Text color for buttons.", "#FFFFFF"));
        panel.Children.Add(CreateSectionTitle("Editor & Tabs"));
        panel.Children.Add(CreateColorRow("Editor Background", "Main Monaco editor canvas.", "#232323"));
        panel.Children.Add(CreateColorRow("Tab Background", "Normal state for editor tabs.", "#232323"));
        panel.Children.Add(CreateColorRow("Tab Text", "Text color for editor tabs.", "#C0C0C0"));
        panel.Children.Add(CreateSectionTitle("Script List"));
        panel.Children.Add(CreateColorRow("List Hover", "Hover state for script list items.", "#333333"));
        panel.Children.Add(CreateColorRow("List Text", "Text color for script list items.", "#C0C0C0"));
        panel.Children.Add(CreateThemeManager());
        return panel;
    }

    private static Border CreateThemeIntro()
    {
        var stack = new StackPanel { Spacing = 5 };
        stack.Children.Add(new TextBlock { Text = "Community Themes", Foreground = Brushes.White, FontSize = 14 });
        stack.Children.Add(new TextBlock
        {
            Text = "Import shared themes from GitHub releases.",
            Foreground = SynapseOriginalCompanionUi.Brush(SynapseOriginalCompanionUi.MutedText),
            FontSize = 11
        });
        stack.Children.Add(CreateToggleRow("Live edit", "Apply color edits to the open shell immediately.", false));
        return new Border
        {
            Background = SynapseOriginalCompanionUi.Brush(SynapseOriginalCompanionUi.RowBackground),
            BorderBrush = SynapseOriginalCompanionUi.Brush(SynapseOriginalCompanionUi.RowBorder),
            BorderThickness = new Thickness(1),
            Padding = new Thickness(10),
            Child = stack
        };
    }

    private static TextBlock CreateSectionTitle(string text) => new()
    {
        Text = text,
        Foreground = Brushes.White,
        FontSize = 13,
        FontWeight = FontWeight.SemiBold,
        Margin = new Thickness(2, 6, 0, 0)
    };

    private static Border CreateColorRow(string label, string description, string value)
    {
        var swatch = new Border
        {
            Width = 25,
            Height = 25,
            Background = SynapseOriginalCompanionUi.Brush(value),
            BorderBrush = SynapseOriginalCompanionUi.Brush("#181818"),
            BorderThickness = new Thickness(1),
            VerticalAlignment = VerticalAlignment.Center
        };
        var input = new TextBox
        {
            Width = 86,
            Height = 27,
            Text = value,
            Background = SynapseOriginalCompanionUi.Brush(SynapseOriginalCompanionUi.ChipBackground),
            BorderBrush = SynapseOriginalCompanionUi.Brush(SynapseOriginalCompanionUi.ChipBorder),
            Foreground = Brushes.White,
            FontSize = 11,
            Padding = new Thickness(6, 3)
        };
        input.LostFocus += (_, _) =>
        {
            try
            {
                swatch.Background = SynapseOriginalCompanionUi.Brush(input.Text ?? value);
            }
            catch (FormatException)
            {
                input.Text = value;
            }
        };
        var copy = new StackPanel { Spacing = 2 };
        copy.Children.Add(new TextBlock { Text = label, Foreground = Brushes.White, FontSize = 12 });
        copy.Children.Add(new TextBlock
        {
            Text = description,
            Foreground = SynapseOriginalCompanionUi.Brush(SynapseOriginalCompanionUi.MutedText),
            FontSize = 11,
            TextWrapping = TextWrapping.Wrap
        });
        var grid = new Grid
        {
            Height = 60,
            ColumnDefinitions = new ColumnDefinitions("*,25,8,86"),
            Margin = new Thickness(12, 0)
        };
        grid.Children.Add(copy);
        Grid.SetColumn(swatch, 1);
        grid.Children.Add(swatch);
        Grid.SetColumn(input, 3);
        grid.Children.Add(input);
        return new Border
        {
            Background = SynapseOriginalCompanionUi.Brush(SynapseOriginalCompanionUi.RowBackground),
            BorderBrush = SynapseOriginalCompanionUi.Brush(SynapseOriginalCompanionUi.RowBorder),
            BorderThickness = new Thickness(1),
            Child = grid
        };
    }

    private static Border CreateThemeManager()
    {
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6 };
        buttons.Children.Add(SynapseOriginalCompanionUi.CreateButton("Import", 29, 88, 12));
        buttons.Children.Add(SynapseOriginalCompanionUi.CreateButton("Export", 29, 88, 12));
        buttons.Children.Add(SynapseOriginalCompanionUi.CreateButton("Reset", 29, 88, 12));
        var stack = new StackPanel { Spacing = 7 };
        stack.Children.Add(new TextBlock { Text = "Manage Theme", Foreground = Brushes.White, FontSize = 13 });
        stack.Children.Add(buttons);
        return new Border
        {
            Background = SynapseOriginalCompanionUi.Brush(SynapseOriginalCompanionUi.RowBackground),
            BorderBrush = SynapseOriginalCompanionUi.Brush(SynapseOriginalCompanionUi.RowBorder),
            BorderThickness = new Thickness(1),
            Padding = new Thickness(10),
            Child = stack
        };
    }

    private static Border CreateToggleRow(
        string label,
        string description,
        bool initialValue,
        Action<bool>? changed = null)
    {
        var enabled = initialValue;
        var status = CreateStatus(enabled ? "ON" : "OFF", enabled ? "#008B00" : "#860000");
        var chip = CreateChip(label);
        chip.Click += (_, _) =>
        {
            enabled = !enabled;
            status.Text = enabled ? "ON" : "OFF";
            status.Foreground = SynapseOriginalCompanionUi.Brush(enabled ? "#008B00" : "#860000");
            changed?.Invoke(enabled);
        };
        return CreateRow(chip, description, status);
    }

    private static Border CreateStatusRow(string label, string description, string status, string color) =>
        CreateRow(CreateChip(label), description, CreateStatus(status, color));

    private static TextBlock CreateStatus(string text, string color) => new()
    {
        Text = text,
        Foreground = SynapseOriginalCompanionUi.Brush(color),
        FontSize = 12,
        VerticalAlignment = VerticalAlignment.Center,
        Margin = new Thickness(5, 0, 0, 0)
    };

    private static Button CreateChip(string label)
    {
        var button = SynapseOriginalCompanionUi.CreateButton(label, 33, 120, 13);
        button.PointerExited += (_, _) =>
            button.Background = SynapseOriginalCompanionUi.Brush(SynapseOriginalCompanionUi.ChipBackground);
        return button;
    }

    private static Border CreateRow(Button chip, string description, TextBlock status)
    {
        var grid = new Grid
        {
            Height = 60,
            ColumnDefinitions = new ColumnDefinitions("120,*,Auto"),
            Margin = new Thickness(12, 0)
        };
        chip.VerticalAlignment = VerticalAlignment.Center;
        grid.Children.Add(chip);
        var copy = new TextBlock
        {
            Text = description,
            Foreground = SynapseOriginalCompanionUi.Brush(SynapseOriginalCompanionUi.MutedText),
            FontSize = 12,
            TextWrapping = TextWrapping.Wrap,
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new Thickness(12, 0, 8, 0)
        };
        Grid.SetColumn(copy, 1);
        grid.Children.Add(copy);
        Grid.SetColumn(status, 2);
        grid.Children.Add(status);
        return new Border
        {
            Height = 60,
            Background = SynapseOriginalCompanionUi.Brush(SynapseOriginalCompanionUi.RowBackground),
            BorderBrush = SynapseOriginalCompanionUi.Brush(SynapseOriginalCompanionUi.RowBorder),
            BorderThickness = new Thickness(1),
            Child = grid
        };
    }
}
