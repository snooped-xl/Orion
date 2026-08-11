using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Primitives;
using Avalonia.Input;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Threading;

namespace OrbitAvalonia;

internal static class SynapseXCompanionUi
{
    internal const string WindowBackground = "#333333";
    internal const string PanelBackground = "#3C3C3C";
    internal const string ButtonBackground = "#2D2D2D";
    internal const string ButtonHover = "#464646";
    internal const string ActiveBackground = "#4A4A4A";
    internal const string Border = "#2A2A2A";
    internal const string ActiveBorder = "#5A5A5A";
    internal const string MutedText = "#A3A3A3";

    internal static SolidColorBrush Brush(string value) =>
        new(Color.Parse(value));

    internal static Grid BuildChrome(
        Window window,
        string title,
        Control body,
        bool showMinimize,
        bool showClose)
    {
        var root = new Grid
        {
            Background = Brush(WindowBackground),
            RowDefinitions = new RowDefinitions("30,*")
        };

        var header = new Grid
        {
            Height = 30,
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

        var logo = SynapseFrontendWindow.CreateSynapseXLogo();
        logo.HorizontalAlignment = HorizontalAlignment.Left;
        logo.VerticalAlignment = VerticalAlignment.Center;
        header.Children.Add(logo);

        header.Children.Add(new TextBlock
        {
            Text = title,
            FontFamily = new FontFamily("Segoe UI"),
            FontSize = 12,
            FontWeight = FontWeight.Normal,
            Foreground = Brushes.White,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new Thickness(50, 1, 50, 0),
            TextTrimming = TextTrimming.CharacterEllipsis
        });

        if (showMinimize || showClose)
        {
            var controls = new StackPanel
            {
                Orientation = Orientation.Horizontal,
                HorizontalAlignment = HorizontalAlignment.Right,
                VerticalAlignment = VerticalAlignment.Stretch
            };
            if (showMinimize)
            {
                controls.Children.Add(CreateWindowButton("_", () =>
                    window.WindowState = WindowState.Minimized));
            }
            if (showClose)
            {
                controls.Children.Add(CreateWindowButton("X", window.Close));
            }
            header.Children.Add(controls);
        }

        root.Children.Add(header);
        Grid.SetRow(body, 1);
        root.Children.Add(body);
        return root;
    }

    internal static Button CreateSurfaceButton(
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
            Background = Brush(PanelBackground),
            BorderBrush = Brush(Border),
            BorderThickness = new Thickness(1),
            Foreground = Brushes.White,
            FontFamily = new FontFamily("Segoe UI"),
            FontSize = fontSize,
            Padding = new Thickness(8, 0),
            HorizontalAlignment = HorizontalAlignment.Stretch,
            HorizontalContentAlignment = HorizontalAlignment.Center,
            VerticalContentAlignment = VerticalAlignment.Center,
            CornerRadius = new CornerRadius(0)
        };
        button.PointerEntered += (_, _) => button.Background = Brush(ButtonHover);
        button.PointerExited += (_, _) => button.Background = Brush(PanelBackground);
        return button;
    }

    private static Button CreateWindowButton(string text, Action action)
    {
        var button = new Button
        {
            Width = 22,
            Height = 30,
            Content = text,
            Background = Brushes.Transparent,
            BorderThickness = new Thickness(0),
            Foreground = Brushes.White,
            FontFamily = new FontFamily("Segoe UI"),
            FontSize = 13,
            Padding = new Thickness(0),
            HorizontalContentAlignment = HorizontalAlignment.Center,
            VerticalContentAlignment = VerticalAlignment.Center,
            CornerRadius = new CornerRadius(0)
        };
        button.Click += (_, _) => action();
        button.PointerEntered += (_, _) => button.Background = Brush("#505050");
        button.PointerExited += (_, _) => button.Background = Brushes.Transparent;
        return button;
    }
}

internal sealed class SynapseXOptionsWindow : Window
{
    private readonly SynapseFrontendWindow _owner;
    private readonly Button _generalButton;
    private readonly Button _themeButton;
    private readonly ScrollViewer _contentScroller;
    private readonly StackPanel _generalPanel;
    private readonly StackPanel _themePanel;
    private bool _showingGeneral = true;

    internal SynapseXOptionsWindow(SynapseFrontendWindow owner)
    {
        _owner = owner;
        Width = 528;
        Height = 460;
        MinWidth = 528;
        MinHeight = 460;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        WindowDecorations = WindowDecorations.None;
        ExtendClientAreaToDecorationsHint = true;
        Background = SynapseXCompanionUi.Brush(SynapseXCompanionUi.WindowBackground);
        Topmost = OrbitPreferences.TopMostEnabled;
        Title = "Synapse X - Options";
        FontFamily = new FontFamily("Segoe UI");
        ApplyResizablePreference(OrbitPreferences.ResizableEnabled);

        _generalPanel = BuildGeneralPanel();
        _themePanel = BuildThemePanel();
        _contentScroller = new ScrollViewer
        {
            Content = _generalPanel,
            Padding = new Thickness(12),
            Background = SynapseXCompanionUi.Brush(SynapseXCompanionUi.WindowBackground),
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled
        };

        _generalButton = CreateSidebarButton("General");
        _themeButton = CreateSidebarButton("Theme");
        _generalButton.Click += (_, _) => ShowGeneral();
        _themeButton.Click += (_, _) => ShowTheme();

        var nav = new StackPanel
        {
            Width = 94,
            Margin = new Thickness(8),
            Spacing = 4,
            Background = SynapseXCompanionUi.Brush(SynapseXCompanionUi.PanelBackground)
        };
        nav.Children.Add(_generalButton);
        nav.Children.Add(_themeButton);

        var navBorder = new Border
        {
            Width = 110,
            Background = SynapseXCompanionUi.Brush(SynapseXCompanionUi.PanelBackground),
            BorderBrush = SynapseXCompanionUi.Brush("#292929"),
            BorderThickness = new Thickness(0, 0, 1, 0),
            Child = nav
        };

        var closeButton = SynapseXCompanionUi.CreateSurfaceButton("Close", 29, 88);
        closeButton.Click += (_, _) => Close();
        var footer = new Border
        {
            Height = 45,
            BorderBrush = SynapseXCompanionUi.Brush("#292929"),
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
                        Children = { closeButton }
                    }
                }
            }
        };

        var main = new Grid { RowDefinitions = new RowDefinitions("*,45") };
        main.Children.Add(_contentScroller);
        Grid.SetRow(footer, 1);
        main.Children.Add(footer);

        var body = new Grid
        {
            Background = SynapseXCompanionUi.Brush(SynapseXCompanionUi.WindowBackground),
            ColumnDefinitions = new ColumnDefinitions("110,*")
        };
        body.Children.Add(navBorder);
        Grid.SetColumn(main, 1);
        body.Children.Add(main);

        Content = SynapseXCompanionUi.BuildChrome(
            this,
            "Synapse X - Options",
            body,
            showMinimize: false,
            showClose: true);
        RefreshSidebar();
        Opened += (_, _) => Dispatcher.UIThread.Post(ShowGeneral, DispatcherPriority.Loaded);
    }

    internal void ApplyResizablePreference(bool enabled)
    {
        CanResize = enabled;
        MaxWidth = enabled ? double.PositiveInfinity : 528;
        MaxHeight = enabled ? double.PositiveInfinity : 460;
    }

    private void ShowGeneral()
    {
        _showingGeneral = true;
        _contentScroller.Content = _generalPanel;
        _contentScroller.Offset = Vector.Zero;
        RefreshSidebar();
    }

    private void ShowTheme()
    {
        _showingGeneral = false;
        _contentScroller.Content = _themePanel;
        _contentScroller.Offset = Vector.Zero;
        RefreshSidebar();
    }

    private void RefreshSidebar()
    {
        ApplySidebarState(_generalButton, _showingGeneral);
        ApplySidebarState(_themeButton, !_showingGeneral);
    }

    private static Button CreateSidebarButton(string label)
    {
        var button = SynapseXCompanionUi.CreateSurfaceButton(label, 30, 94, 13);
        button.PointerEntered += (_, _) => button.Background = SynapseXCompanionUi.Brush("#505050");
        return button;
    }

    private static void ApplySidebarState(Button button, bool active)
    {
        button.Background = SynapseXCompanionUi.Brush(
            active ? SynapseXCompanionUi.ActiveBackground : SynapseXCompanionUi.PanelBackground);
        button.BorderBrush = SynapseXCompanionUi.Brush(
            active ? SynapseXCompanionUi.ActiveBorder : SynapseXCompanionUi.Border);
    }

    private StackPanel BuildGeneralPanel()
    {
        var panel = new StackPanel { Spacing = 2 };
        panel.Children.Add(CreateToggleRow(
            "Auto Attach",
            "Automatically attach to any client(s).",
            false));
        panel.Children.Add(CreateToggleRow(
            "Auto Open",
            "Open Orion automatically after the shell finishes loading.",
            false));
        panel.Children.Add(CreateToggleRow(
            "Loading Screen",
            "Play the Synapse X loading sequence when the shell changes.",
            true));
        panel.Children.Add(CreateToggleRow(
            "Auto Update",
            "Check for updates when Orion starts.",
            false));
        panel.Children.Add(CreateToggleRow(
            "Top Most",
            "All Synapse windows to stay on top.",
            OrbitPreferences.TopMostEnabled,
            enabled =>
            {
                OrbitPreferences.SetTopMost(enabled);
                _owner.ApplySynapseXTopMostPreference(enabled);
                Topmost = enabled;
            }));
        panel.Children.Add(CreateToggleRow(
            "Enhanced List",
            "Search, bookmarks, gists, and script-list theming.",
            false));
        panel.Children.Add(CreateToggleRow(
            "Minimap",
            "Show a miniature preview of the entire script on the right side.",
            false));
        panel.Children.Add(CreateToggleRow(
            "Error Logging",
            "EXPERIMENTAL: Luau errors in the editor (may show false positives).",
            false));
        panel.Children.Add(CreateToggleRow(
            "Resizable",
            "Drag edges to resize. Off restores the default 801×355.",
            OrbitPreferences.ResizableEnabled,
            enabled =>
            {
                OrbitPreferences.SetResizable(enabled);
                _owner.ApplySynapseXResizablePreference(enabled);
            }));
        panel.Children.Add(CreateStatusRow(
            "Bridge Method",
            "One bridge script that connects Orion to your executor.",
            "UNIFIED",
            "#5A9E5F"));
        panel.Children.Add(CreateToggleRow(
            "Edge Curve",
            "Win11 rounded corners. Off uses sharp square corners.",
            false));
        panel.Children.Add(CreateStatusRow(
            "Synapse 2017",
            "Switch to the Synapse 2017 multi-window UI.",
            "OFF",
            "#CF6363"));
        panel.Children.Add(CreateStatusRow(
            "Synapse Blue",
            "Return to the Synapse Blue desktop UI.",
            "OFF",
            "#CF6363"));
        panel.Children.Add(CreateStatusRow(
            "Synapse v3",
            "Switch to the Synapse v3 UI.",
            "OFF",
            "#CF6363"));
        panel.Children.Add(CreateStatusRow(
            "Setup",
            "Go back to the first-time setup wizard.",
            "OPEN",
            "#5A9E5F"));
        return panel;
    }

    private static StackPanel BuildThemePanel()
    {
        var panel = new StackPanel { Spacing = 2 };
        panel.Children.Add(CreateThemeIntro());
        panel.Children.Add(CreateThemeSectionTitle("Core Colors"));
        panel.Children.Add(CreateColorRow("Window background", "Outer fill behind buttons and the editor.", "#333333"));
        panel.Children.Add(CreateColorRow("Panel background", "Title bar, side panel, and button surfaces.", "#3C3C3C"));
        panel.Children.Add(CreateColorRow("Text", "Title-bar titles, banner, and headers.", "#FFFFFF"));
        panel.Children.Add(CreateThemeSectionTitle("Buttons"));
        panel.Children.Add(CreateColorRow("Button Background", "Normal state for buttons.", "#3C3C3C"));
        panel.Children.Add(CreateColorRow("Button Hover", "Hover state for buttons.", "#464646"));
        panel.Children.Add(CreateColorRow("Button Active", "Pressed state for buttons.", "#323232"));
        panel.Children.Add(CreateColorRow("Button Border", "Border around buttons.", "#2A2A2A"));
        panel.Children.Add(CreateColorRow("Button Text", "Text color for buttons.", "#FFFFFF"));
        panel.Children.Add(CreateThemeSectionTitle("Editor Tabs"));
        panel.Children.Add(CreateColorRow("Editor Background", "Main Monaco editor canvas.", "#1E1E1E"));
        panel.Children.Add(CreateColorRow("Tab Background", "Normal state for editor tabs.", "#1E1E1E"));
        panel.Children.Add(CreateColorRow("Tab Active", "Active state for the selected editor tab.", "#1E1E1E"));
        panel.Children.Add(CreateColorRow("Tab Text", "Text color for editor tabs.", "#C0C0C0"));
        panel.Children.Add(CreateThemeSectionTitle("Script List"));
        panel.Children.Add(CreateColorRow("List Hover", "Hover state for script list items.", "#333333"));
        panel.Children.Add(CreateColorRow("List Text", "Text color for script list items.", "#C0C0C0"));
        panel.Children.Add(CreateColorRow("Icon Color", "Color for close, add, and save icons.", "#C0C0C0"));
        panel.Children.Add(CreateThemeManager());
        return panel;
    }

    private static Border CreateThemeIntro()
    {
        var copy = new StackPanel { Spacing = 3 };
        copy.Children.Add(new TextBlock
        {
            Text = "Community Themes",
            Foreground = Brushes.White,
            FontSize = 14
        });
        copy.Children.Add(new TextBlock
        {
            Text = "Import shared themes from GitHub releases.",
            Foreground = SynapseXCompanionUi.Brush(SynapseXCompanionUi.MutedText),
            FontSize = 11
        });
        copy.Children.Add(CreateToggleRow("Live edit", "Apply color edits to the open shell immediately.", false));
        return new Border
        {
            Background = SynapseXCompanionUi.Brush(SynapseXCompanionUi.PanelBackground),
            BorderBrush = SynapseXCompanionUi.Brush(SynapseXCompanionUi.Border),
            BorderThickness = new Thickness(1),
            Padding = new Thickness(10),
            Child = copy
        };
    }

    private static TextBlock CreateThemeSectionTitle(string text) => new()
    {
        Text = text,
        Foreground = Brushes.White,
        FontSize = 13,
        FontWeight = FontWeight.SemiBold,
        Margin = new Thickness(2, 10, 0, 4)
    };

    private static Border CreateColorRow(string label, string description, string value)
    {
        var swatch = new Border
        {
            Width = 24,
            Height = 24,
            Background = SynapseXCompanionUi.Brush(value),
            BorderBrush = SynapseXCompanionUi.Brush("#1F1F1F"),
            BorderThickness = new Thickness(1),
            VerticalAlignment = VerticalAlignment.Center
        };
        var input = new TextBox
        {
            Width = 82,
            Height = 27,
            Text = value,
            Background = SynapseXCompanionUi.Brush(SynapseXCompanionUi.ButtonBackground),
            BorderBrush = SynapseXCompanionUi.Brush(SynapseXCompanionUi.Border),
            Foreground = Brushes.White,
            FontSize = 11,
            Padding = new Thickness(6, 3),
            VerticalContentAlignment = VerticalAlignment.Center
        };
        input.LostFocus += (_, _) =>
        {
            try
            {
                swatch.Background = SynapseXCompanionUi.Brush(input.Text ?? value);
            }
            catch (FormatException)
            {
                input.Text = value;
            }
        };

        var text = new StackPanel { Spacing = 2 };
        text.Children.Add(new TextBlock { Text = label, Foreground = Brushes.White, FontSize = 12 });
        text.Children.Add(new TextBlock
        {
            Text = description,
            Foreground = SynapseXCompanionUi.Brush(SynapseXCompanionUi.MutedText),
            FontSize = 10.5,
            TextWrapping = TextWrapping.Wrap
        });

        var grid = new Grid
        {
            MinHeight = 58,
            ColumnDefinitions = new ColumnDefinitions("*,24,8,82"),
            Margin = new Thickness(10, 0)
        };
        grid.Children.Add(text);
        Grid.SetColumn(swatch, 1);
        grid.Children.Add(swatch);
        Grid.SetColumn(input, 3);
        grid.Children.Add(input);
        return new Border
        {
            Background = SynapseXCompanionUi.Brush(SynapseXCompanionUi.PanelBackground),
            BorderBrush = SynapseXCompanionUi.Brush(SynapseXCompanionUi.Border),
            BorderThickness = new Thickness(1),
            Child = grid
        };
    }

    private static Border CreateThemeManager()
    {
        var buttons = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 6,
            Margin = new Thickness(0, 7, 0, 0)
        };
        buttons.Children.Add(SynapseXCompanionUi.CreateSurfaceButton("Import", 29, 82, 12));
        buttons.Children.Add(SynapseXCompanionUi.CreateSurfaceButton("Export", 29, 82, 12));
        buttons.Children.Add(SynapseXCompanionUi.CreateSurfaceButton("Reset", 29, 82, 12));
        var stack = new StackPanel { Spacing = 2 };
        stack.Children.Add(new TextBlock { Text = "Manage Theme", Foreground = Brushes.White, FontSize = 13 });
        stack.Children.Add(buttons);
        return new Border
        {
            Margin = new Thickness(0, 10, 0, 0),
            Padding = new Thickness(10),
            Background = SynapseXCompanionUi.Brush(SynapseXCompanionUi.PanelBackground),
            BorderBrush = SynapseXCompanionUi.Brush(SynapseXCompanionUi.Border),
            BorderThickness = new Thickness(1),
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
        var status = new TextBlock
        {
            Text = enabled ? "ON" : "OFF",
            Foreground = SynapseXCompanionUi.Brush(enabled ? "#5A9E5F" : "#CF6363"),
            FontSize = 12,
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new Thickness(8, 0, 0, 0)
        };
        var chip = CreateRowChip(label);
        chip.Click += (_, _) =>
        {
            enabled = !enabled;
            status.Text = enabled ? "ON" : "OFF";
            status.Foreground = SynapseXCompanionUi.Brush(enabled ? "#5A9E5F" : "#CF6363");
            changed?.Invoke(enabled);
        };
        return CreateRow(chip, description, status);
    }

    private static Border CreateStatusRow(
        string label,
        string description,
        string statusText,
        string statusColor)
    {
        var status = new TextBlock
        {
            Text = statusText,
            Foreground = SynapseXCompanionUi.Brush(statusColor),
            FontSize = 12,
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new Thickness(8, 0, 0, 0)
        };
        return CreateRow(CreateRowChip(label), description, status);
    }

    private static Button CreateRowChip(string label)
    {
        var button = SynapseXCompanionUi.CreateSurfaceButton(label, 33, 120, 12);
        button.Background = SynapseXCompanionUi.Brush(SynapseXCompanionUi.ButtonBackground);
        button.PointerEntered += (_, _) =>
            button.Background = SynapseXCompanionUi.Brush(SynapseXCompanionUi.ButtonHover);
        button.PointerExited += (_, _) =>
            button.Background = SynapseXCompanionUi.Brush(SynapseXCompanionUi.ButtonBackground);
        return button;
    }

    private static Border CreateRow(Button chip, string description, TextBlock status)
    {
        var grid = new Grid
        {
            MinHeight = 60,
            ColumnDefinitions = new ColumnDefinitions("120,*,Auto"),
            Margin = new Thickness(12, 0)
        };
        chip.VerticalAlignment = VerticalAlignment.Center;
        grid.Children.Add(chip);
        var copy = new TextBlock
        {
            Text = description,
            Foreground = SynapseXCompanionUi.Brush(SynapseXCompanionUi.MutedText),
            FontSize = 11,
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
            Background = SynapseXCompanionUi.Brush(SynapseXCompanionUi.PanelBackground),
            BorderBrush = SynapseXCompanionUi.Brush(SynapseXCompanionUi.Border),
            BorderThickness = new Thickness(1),
            Child = grid
        };
    }
}
