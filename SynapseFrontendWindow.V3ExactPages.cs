using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Documents;
using Avalonia.Controls.Primitives;
using Avalonia.Input;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Threading;
using System.Diagnostics;

namespace OrbitAvalonia;

internal sealed partial class SynapseFrontendWindow
{
    private CancellationTokenSource? _v3ExactHubCancellation;
    private ScriptHubProvider _v3ExactHubProvider = ScriptHubProvider.RobloxScripts;
    private int _v3ExactHubPage = 1;
    private bool _v3ExactHubHasMore;
    private Grid? _v3ExactApiHost;
    private TextBox? _v3ExactHubSearchBox;
    private ComboBox? _v3ExactProviderSelect;
    private TextBlock? _v3ExactPageLabel;
    private Button? _v3ExactPreviousButton;
    private Button? _v3ExactNextButton;
    private Border? _v3ExactSearchChrome;
    private Border? _v3ExactPagerChrome;

    private Control BuildV3SettingsPageExact()
    {
        var root = new Grid
        {
            Background = Brushes.Black,
            ColumnDefinitions = new ColumnDefinitions("58,*")
        };

        var contentStack = new StackPanel { Spacing = 0 };
        var application = BuildV3ExactSectionHeader(
            "Application", SynapseV3IconData.SettingsApplication, 14, false);
        var editor = BuildV3ExactSectionHeader(
            "Editor", SynapseV3IconData.SettingsSectionEditor, 14, true);
        var terminal = BuildV3ExactSectionHeader(
            "Terminal", SynapseV3IconData.SettingsTerminal, 18, true);
        var layers = BuildV3ExactSectionHeader(
            "Layers", SynapseV3IconData.SettingsLayers, 18, true);
        var config = BuildV3ExactSectionHeader(
            "Config", SynapseV3IconData.SettingsConfig, 18, false);

        contentStack.Children.Add(application);
        contentStack.Children.Add(BuildV3ExactSettingRow(
            "Auto Open",
            "Open Orion automatically after the shell finishes loading.",
            BuildV3ExactStaticCheckbox(true)));
        contentStack.Children.Add(BuildV3ExactSettingRow(
            "Play loading screen on shell change",
            "Show the V3 loading sequence whenever the active shell changes.",
            BuildV3ExactStaticCheckbox(true)));
        contentStack.Children.Add(BuildV3ExactSettingRow(
            "Auto Update",
            "Check for updates when Orion starts.",
            BuildV3ExactStaticCheckbox(false)));
        contentStack.Children.Add(BuildV3ExactSettingRow(
            "Setup wizard",
            "Go back to the first-time setup to reconfigure the autoexec folder, bridge, and plugins.",
            BuildV3ExactStaticButton("Go to Setup", 110)));
        contentStack.Children.Add(BuildV3ExactSettingRow(
            "Reset all settings",
            "Pressing this button will reset settings and close the application.",
            BuildV3ExactStaticButton("Reset", 70)));
        contentStack.Children.Add(BuildV3ExactSettingRow(
            "Top Most",
            "All Synapse windows stay on top.",
            BuildV3ExactStaticCheckbox(Topmost)));
        contentStack.Children.Add(BuildV3ExactSettingRow(
            "Resizable",
            "Allow dragging the window edges to resize.",
            BuildV3ExactStaticCheckbox(CanResize)));
        contentStack.Children.Add(BuildV3ExactSettingRow(
            "Orion Bridge",
            "One script for every executor; the bridge tries Port, Stream, and Compat in order.",
            BuildV3ExactValueChip("bridge.lua  ✓", 110)));
        contentStack.Children.Add(BuildV3ExactProviderSettingsBlock());

        var moveToOrion = BuildV3ExactStaticButton("Move to Orion UI", 132, false);
        moveToOrion.Click += (_, _) => ReturnWorkspaceToOrbit();
        contentStack.Children.Add(BuildV3ExactSettingRow(
            "UI Mode",
            "Return to Orion's native interface.",
            moveToOrion));

        contentStack.Children.Add(editor);
        contentStack.Children.Add(BuildV3ExactSettingRow(
            "Toggle script list",
            "Optional — hide the editor script list panel. Bookmarks, gists, and quick script access live there.",
            BuildV3ExactStaticCheckbox(true)));
        contentStack.Children.Add(BuildV3ExactSettingRow(
            "Minimap",
            "Show a miniature preview of the entire script on the right side.",
            BuildV3ExactStaticCheckbox(true)));
        contentStack.Children.Add(BuildV3ExactSettingRow(
            "Minimap size",
            "Scale the editor minimap without changing the editor text.",
            BuildV3ExactSlider()));
        contentStack.Children.Add(BuildV3ExactSettingRow(
            "Error Logging",
            "EXPERIMENTAL — displays Luau syntax diagnostics inside the editor.",
            BuildV3ExactStaticCheckbox(false)));
        contentStack.Children.Add(BuildV3ExactSettingRow(
            "AI features",
            "SynapseAI assistant and related editor tooling.",
            BuildV3ExactStaticCheckbox(false)));
        contentStack.Children.Add(BuildV3ExactSettingRow(
            "Compact editor buttons",
            "Reduces the size of editor buttons.",
            BuildV3ExactStaticCheckbox(false)));
        contentStack.Children.Add(BuildV3ExactSettingRow(
            "Compact tabs",
            "Use compact square tabs instead of round padded ones.",
            BuildV3ExactStaticCheckbox(false)));

        contentStack.Children.Add(terminal);
        contentStack.Children.Add(BuildV3ExactNote(
            "Terminal settings are coming soon for Synapse v3."));

        contentStack.Children.Add(layers);
        contentStack.Children.Add(BuildV3ExactNote(
            "Layer settings are coming soon for Synapse v3."));

        contentStack.Children.Add(config);
        contentStack.Children.Add(BuildV3ExactNote(
            "Config settings are coming soon for Synapse v3.", 16));
        contentStack.Children.Add(BuildV3ExactSettingRow(
            "Default Tab Content",
            "What will be written to the contents of a new tab.",
            BuildV3ExactTextField("Content…", 250)));
        contentStack.Children.Add(BuildV3ExactSettingRow(
            "Directories in sidebar",
            "You can set extra directories to show up in the sidebar.",
            BuildV3ExactValueChip(@"H:\project\editor-sidebar-scripts", 250)));
        contentStack.Children.Add(new Border { Height = 200, Background = Brushes.Transparent });

        var content = new ScrollViewer
        {
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
            Background = Brushes.Black,
            Padding = new Thickness(10, 8, 10, 16),
            HorizontalContentAlignment = HorizontalAlignment.Stretch,
            Content = contentStack
        };
        Grid.SetColumn(content, 1);
        root.Children.Add(content);

        root.Children.Add(BuildV3ExactSettingsRail(
            content,
            new (string Label, string Path, double ViewBox, bool Stroke, Control Target)[]
            {
                ("Application", SynapseV3IconData.SettingsSidebarApplication, 18, false, application),
                ("Editor", SynapseV3IconData.SettingsEditor, 18, true, editor),
                ("Terminal", SynapseV3IconData.SettingsTerminal, 18, true, terminal),
                ("Layers", SynapseV3IconData.SettingsLayers, 18, true, layers),
                ("Config", SynapseV3IconData.SettingsConfig, 18, false, config)
            }));
        return root;
    }

    private static Border BuildV3ExactSectionHeader(
        string title,
        string iconPath,
        double viewBox,
        bool stroke)
    {
        var row = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 8,
            VerticalAlignment = VerticalAlignment.Center
        };
        row.Children.Add(CreateSvgIcon(iconPath, 14, "#FFFFFF", viewBox, stroke));
        row.Children.Add(new TextBlock
        {
            Text = title,
            Foreground = Brushes.White,
            FontSize = 16,
            FontWeight = FontWeight.Normal,
            VerticalAlignment = VerticalAlignment.Center
        });
        return new Border
        {
            Height = 33,
            Margin = new Thickness(0, 0, 0, 16),
            Padding = new Thickness(12, 0),
            Background = Brush("#303030"),
            CornerRadius = new CornerRadius(4),
            Child = row
        };
    }

    private static Control BuildV3ExactSettingRow(string label, string description, Control control)
    {
        var copy = new StackPanel { Spacing = 4 };
        copy.Children.Add(new TextBlock
        {
            Text = label,
            Foreground = Brushes.White,
            FontSize = 14,
            FontWeight = FontWeight.Normal
        });
        copy.Children.Add(new TextBlock
        {
            Text = description,
            Foreground = Brush("#6B6B6B"),
            FontSize = 13,
            FontWeight = FontWeight.Normal,
            TextWrapping = TextWrapping.Wrap
        });

        var grid = new Grid
        {
            Margin = new Thickness(0, 0, 0, 22),
            ColumnDefinitions = new ColumnDefinitions("*,auto")
        };
        grid.Children.Add(copy);
        var controlHost = new Border
        {
            Margin = new Thickness(16, 0, 0, 0),
            VerticalAlignment = VerticalAlignment.Top,
            Child = control
        };
        Grid.SetColumn(controlHost, 1);
        grid.Children.Add(controlHost);
        return grid;
    }

    private static Button BuildV3ExactStaticButton(string text, double width, bool staticVisual = true)
    {
        return new Button
        {
            Width = width,
            Height = 33,
            Content = text,
            Background = Brush("#373737"),
            BorderBrush = Brush("#3D3D3C"),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(4),
            Foreground = Brushes.White,
            FontSize = 13,
            FontWeight = FontWeight.Normal,
            Padding = new Thickness(8, 0),
            IsHitTestVisible = !staticVisual
        };
    }

    private static Control BuildV3ExactStaticCheckbox(bool value)
    {
        var checkbox = BuildV3Checkbox(value);
        checkbox.IsHitTestVisible = false;
        return checkbox;
    }

    private static Control BuildV3ExactSlider()
    {
        var grid = new Grid
        {
            Width = 140,
            Height = 32,
            RowDefinitions = new RowDefinitions("12,*")
        };
        grid.Children.Add(new TextBlock
        {
            Text = "100%",
            Foreground = Brush("#B0D8E5"),
            FontSize = 12,
            HorizontalAlignment = HorizontalAlignment.Right
        });
        var track = new Grid { Height = 14, VerticalAlignment = VerticalAlignment.Center };
        track.Children.Add(new Border
        {
            Height = 3,
            Background = Brush("#313131"),
            CornerRadius = new CornerRadius(2),
            VerticalAlignment = VerticalAlignment.Center
        });
        track.Children.Add(new Border
        {
            Width = 8,
            Height = 8,
            Background = Brush("#B0D8E5"),
            CornerRadius = new CornerRadius(4),
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center
        });
        Grid.SetRow(track, 1);
        grid.Children.Add(track);
        return grid;
    }

    private static Control BuildV3ExactValueChip(string text, double width)
    {
        return new Border
        {
            Width = width,
            Height = 30,
            Background = Brush("#2D2D2D"),
            BorderBrush = Brush("#3D3D3C"),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(4),
            Padding = new Thickness(10, 0),
            Child = new TextBlock
            {
                Text = text,
                Foreground = Brush("#B0D8E5"),
                FontSize = 12,
                TextTrimming = TextTrimming.CharacterEllipsis,
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center
            }
        };
    }

    private static Control BuildV3ExactTextField(string watermark, double width)
    {
        return new TextBox
        {
            Width = width,
            Height = 38,
            PlaceholderText = watermark,
            Background = Brush("#2D2D2D"),
            BorderBrush = Brush("#3D3D3C"),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(6),
            Foreground = Brushes.White,
            FontSize = 14,
            Padding = new Thickness(10, 0),
            VerticalContentAlignment = VerticalAlignment.Center,
            IsHitTestVisible = false
        };
    }

    private static Control BuildV3ExactNote(string text, double bottom = 22)
    {
        return new TextBlock
        {
            Text = text,
            Foreground = Brush("#6B6B6B"),
            FontSize = 13,
            FontStyle = FontStyle.Italic,
            Margin = new Thickness(0, 0, 0, bottom)
        };
    }

    private static Control BuildV3ExactProviderSettingsBlock()
    {
        var options = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 4,
            Margin = new Thickness(0, 10, 0, 0)
        };
        foreach (var label in new[] { "robloxscripts.com", "⚠ ScriptBlox", "HaxHell", "rscripts.net" })
        {
            options.Children.Add(BuildV3ExactStaticButton(label, Math.Max(84, label.Length * 7 + 22)));
        }

        var block = new StackPanel { Margin = new Thickness(0, 0, 0, 22) };
        block.Children.Add(new TextBlock
        {
            Text = "Script Hub Source",
            Foreground = Brushes.White,
            FontSize = 14
        });
        block.Children.Add(new TextBlock
        {
            Text = "Choose which website to search for scripts. This affects all script hub UIs.",
            Foreground = Brush("#6B6B6B"),
            FontSize = 13,
            Margin = new Thickness(0, 4, 0, 0)
        });
        block.Children.Add(options);
        return block;
    }

    private static Control BuildV3ExactSettingsRail(
        ScrollViewer targetScroll,
        IReadOnlyList<(string Label, string Path, double ViewBox, bool Stroke, Control Target)> items)
    {
        var stack = new StackPanel
        {
            Background = Brushes.Black,
            Spacing = 9,
            Margin = new Thickness(3, 4, 3, 8)
        };
        var buttons = new List<Button>();
        var accents = new List<Border>();
        var icons = new List<Control>();

        void Select(int selected, bool scroll)
        {
            for (var index = 0; index < buttons.Count; index++)
            {
                buttons[index].Background = index == selected ? Brush("#121212") : Brushes.Transparent;
                accents[index].IsVisible = index == selected;
                icons[index].Opacity = index == selected ? 1 : .55;
            }
            if (scroll && selected >= 0 && selected < items.Count)
            {
                targetScroll.Offset = new Vector(
                    targetScroll.Offset.X,
                    Math.Max(0, items[selected].Target.Bounds.Y));
            }
        }

        for (var index = 0; index < items.Count; index++)
        {
            var itemIndex = index;
            var item = items[index];
            var icon = CreateSvgIcon(item.Path, 18, "#FFFFFF", item.ViewBox, item.Stroke);
            icon.Opacity = index == 0 ? 1 : .55;
            icons.Add(icon);
            var button = new Button
            {
                Width = 51,
                Height = 36,
                Background = index == 0 ? Brush("#121212") : Brushes.Transparent,
                BorderThickness = new Thickness(0),
                CornerRadius = new CornerRadius(4),
                Padding = new Thickness(0),
                Content = icon
            };
            ToolTip.SetTip(button, item.Label);
            button.Click += (_, _) => Select(itemIndex, true);
            buttons.Add(button);

            var cell = new Grid { Width = 51, Height = 36 };
            cell.Children.Add(button);
            var accent = new Border
            {
                Width = 3,
                Margin = new Thickness(0, 4, 0, 4),
                HorizontalAlignment = HorizontalAlignment.Left,
                Background = Brush("#BDD3DE"),
                CornerRadius = new CornerRadius(0, 2, 2, 0),
                IsVisible = index == 0,
                IsHitTestVisible = false
            };
            accents.Add(accent);
            cell.Children.Add(accent);
            stack.Children.Add(cell);
        }

        targetScroll.ScrollChanged += (_, _) =>
        {
            var selected = 0;
            var probe = targetScroll.Offset.Y + 20;
            for (var index = 1; index < items.Count; index++)
            {
                if (items[index].Target.Bounds.Y > probe) break;
                selected = index;
            }
            Select(selected, false);
        };

        var rail = new ScrollViewer
        {
            VerticalScrollBarVisibility = ScrollBarVisibility.Hidden,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
            Background = Brushes.Black,
            Content = stack
        };
        Grid.SetColumn(rail, 0);
        return rail;
    }

    private Control BuildV3ScriptHubPageExact()
    {
        var root = new Grid
        {
            Background = Brushes.Black,
            RowDefinitions = new RowDefinitions("32,6,42,*,34")
        };

        var sourceTabs = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            HorizontalAlignment = HorizontalAlignment.Center,
            Spacing = 5,
            Background = Brushes.Black
        };
        _v3HubApiTab = BuildV3TabChip("Scripts", true, 176);
        _v3HubSynapseTab = BuildV3TabChip("Synapse Script Hub", false, 176);
        _v3HubApiTab.Click += (_, _) => SetV3ExactHubSource(false);
        _v3HubSynapseTab.Click += (_, _) => SetV3ExactHubSource(true);
        sourceTabs.Children.Add(_v3HubApiTab);
        sourceTabs.Children.Add(_v3HubSynapseTab);
        root.Children.Add(new Border { Background = Brushes.Black, Child = sourceTabs });

        var toggleShadow = new Border
        {
            Background = new LinearGradientBrush
            {
                StartPoint = new RelativePoint(0, 0, RelativeUnit.Relative),
                EndPoint = new RelativePoint(0, 1, RelativeUnit.Relative),
                GradientStops = new GradientStops
                {
                    new(Color.Parse("#48000000"), 0),
                    new(Color.Parse("#00000000"), 1)
                }
            }
        };
        Grid.SetRow(toggleShadow, 1);
        root.Children.Add(toggleShadow);

        _v3ExactHubSearchBox = new TextBox
        {
            PlaceholderText = "Search robloxscripts.com…",
            FontSize = 12,
            Foreground = Brush("#F6F6F5"),
            CaretBrush = Brushes.White,
            Background = Brushes.Transparent,
            BorderThickness = new Thickness(0),
            Padding = new Thickness(30, 0, 8, 0),
            VerticalContentAlignment = VerticalAlignment.Center
        };
        _v3ExactHubSearchBox.KeyDown += (_, args) =>
        {
            if (args.Key != Key.Enter) return;
            args.Handled = true;
            StartV3ExactProviderLoad(1);
        };
        var searchContents = new Grid();
        searchContents.Children.Add(_v3ExactHubSearchBox);
        searchContents.Children.Add(new Border
        {
            Width = 14,
            Height = 14,
            Margin = new Thickness(10, 0, 0, 0),
            HorizontalAlignment = HorizontalAlignment.Left,
            VerticalAlignment = VerticalAlignment.Center,
            IsHitTestVisible = false,
            Child = CreateSvgIcon(
                "M10.5 10.5L15 15M13 7A6 6 0 1 1 1 7A6 6 0 0 1 13 7Z",
                14,
                "#868686",
                16,
                true)
        });
        var search = new Border
        {
            Background = Brush("#2A2A2A"),
            CornerRadius = new CornerRadius(3),
            Child = searchContents
        };

        _v3ExactProviderSelect = new ComboBox
        {
            Height = 34,
            SelectedIndex = 0,
            Background = Brush("#2A2A2A"),
            BorderBrush = Brush("#3A3A3A"),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(3),
            Foreground = Brush("#F6F6F5"),
            FontSize = 12,
            Padding = new Thickness(9, 0),
            HorizontalContentAlignment = HorizontalAlignment.Stretch,
            ItemsSource = new Control[]
            {
                BuildV3ExactProviderItem("robloxscripts.com"),
                BuildV3ExactProviderItem("rscripts.net"),
                BuildV3ExactProviderItem("haxhell.com"),
                BuildV3ExactProviderItem("ScriptBlox", true)
            }
        };
        _v3ExactProviderSelect.SelectionChanged += (_, _) =>
        {
            _v3ExactHubProvider = _v3ExactProviderSelect.SelectedIndex switch
            {
                1 => ScriptHubProvider.Rscripts,
                2 => ScriptHubProvider.HaxHell,
                3 => ScriptHubProvider.ScriptBlox,
                _ => ScriptHubProvider.RobloxScripts
            };
            if (_v3ExactHubSearchBox is not null)
            {
                _v3ExactHubSearchBox.PlaceholderText = $"Search {V3ExactProviderName(_v3ExactHubProvider)}…";
            }
            StartV3ExactProviderLoad(1);
        };

        var searchRow = new Grid
        {
            Margin = new Thickness(12, 2, 12, 6),
            ColumnDefinitions = new ColumnDefinitions("*,8,174")
        };
        searchRow.Children.Add(search);
        Grid.SetColumn(_v3ExactProviderSelect, 2);
        searchRow.Children.Add(_v3ExactProviderSelect);
        _v3ExactSearchChrome = new Border { Background = Brushes.Black, Child = searchRow };
        Grid.SetRow(_v3ExactSearchChrome, 2);
        root.Children.Add(_v3ExactSearchChrome);

        _v3ExactApiHost = new Grid { Margin = new Thickness(12, 0, 12, 0) };
        _v3HubApiContent = _v3ExactApiHost;
        _v3HubSynapseContent = new ScrollViewer
        {
            Margin = new Thickness(12, 0, 12, 8),
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
            Content = BuildV3ExactCardsGrid(BuildBlueLegacyCards(), true)
        };
        Grid.SetRow(_v3HubApiContent, 3);
        Grid.SetRow(_v3HubSynapseContent, 3);
        root.Children.Add(_v3HubApiContent);
        root.Children.Add(_v3HubSynapseContent);

        _v3ExactPreviousButton = BuildV3ExactPagerButton("Previous");
        _v3ExactNextButton = BuildV3ExactPagerButton("Next");
        _v3ExactPageLabel = new TextBlock
        {
            Text = "Page 1",
            Foreground = Brush("#868686"),
            FontSize = 11,
            VerticalAlignment = VerticalAlignment.Center
        };
        _v3ExactPreviousButton.Click += (_, _) =>
        {
            if (_v3ExactHubPage > 1) StartV3ExactProviderLoad(_v3ExactHubPage - 1);
        };
        _v3ExactNextButton.Click += (_, _) =>
        {
            if (_v3ExactHubHasMore) StartV3ExactProviderLoad(_v3ExactHubPage + 1);
        };
        var pager = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
            Spacing = 20,
            Children = { _v3ExactPreviousButton, _v3ExactPageLabel, _v3ExactNextButton }
        };
        _v3ExactPagerChrome = new Border
        {
            BorderBrush = Brush("#3A3A3A"),
            BorderThickness = new Thickness(0, 1, 0, 0),
            Background = Brushes.Black,
            Child = pager
        };
        Grid.SetRow(_v3ExactPagerChrome, 4);
        root.Children.Add(_v3ExactPagerChrome);

        SetV3ExactHubSource(false);
        Dispatcher.UIThread.Post(() => StartV3ExactProviderLoad(1));
        return root;
    }

    private static Control BuildV3ExactProviderItem(string label, bool warning = false)
    {
        var row = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 6,
            VerticalAlignment = VerticalAlignment.Center
        };
        if (warning)
        {
            row.Children.Add(CreateSvgIcon(
                "M8 1.5L15 14.5H1L8 1.5ZM8 5V9.5M8 12V12.1",
                13,
                "#EAB308",
                16,
                true,
                1.25));
        }
        row.Children.Add(new TextBlock
        {
            Text = label,
            Foreground = Brush("#F6F6F5"),
            FontSize = 12,
            VerticalAlignment = VerticalAlignment.Center
        });
        return row;
    }

    private static Button BuildV3ExactPagerButton(string text) => new()
    {
        Content = text,
        Background = Brushes.Transparent,
        BorderThickness = new Thickness(0),
        Foreground = Brush("#868686"),
        FontSize = 11,
        Padding = new Thickness(8, 2)
    };

    private void SetV3ExactHubSource(bool synapse)
    {
        if (_v3HubApiTab is null || _v3HubSynapseTab is null) return;
        _v3HubApiTab.Background = Brush(synapse ? "#000000" : "#121212");
        _v3HubApiTab.Foreground = synapse ? Brush("#8D8D8D") : Brushes.White;
        _v3HubSynapseTab.Background = Brush(synapse ? "#121212" : "#000000");
        _v3HubSynapseTab.Foreground = synapse ? Brushes.White : Brush("#8D8D8D");
        if (_v3HubApiContent is not null) _v3HubApiContent.IsVisible = !synapse;
        if (_v3HubSynapseContent is not null) _v3HubSynapseContent.IsVisible = synapse;
        if (_v3ExactSearchChrome is not null) _v3ExactSearchChrome.IsVisible = !synapse;
        if (_v3ExactPagerChrome is not null) _v3ExactPagerChrome.IsVisible = !synapse;
    }

    private void StartV3ExactProviderLoad(int page)
    {
        _v3ExactHubCancellation?.Cancel();
        _v3ExactHubCancellation?.Dispose();
        _v3ExactHubCancellation = new CancellationTokenSource();
        _ = LoadV3ExactProviderAsync(
            _v3ExactHubProvider,
            _v3ExactHubSearchBox?.Text?.Trim() ?? string.Empty,
            page,
            _v3ExactHubCancellation.Token);
    }

    private async Task LoadV3ExactProviderAsync(
        ScriptHubProvider provider,
        string query,
        int page,
        CancellationToken cancellationToken)
    {
        if (_v3ExactApiHost is null) return;
        _v3ExactApiHost.Children.Clear();
        _v3ExactApiHost.Children.Add(BuildV3ExactHubMessage("Loading…", "#868686"));
        UpdateV3ExactPager(page, false, true);

        try
        {
            var result = await _blueHubService.FetchAsync(provider, query, page, cancellationToken);
            await _blueHubService.LoadThumbnailsAsync(result.Cards, cancellationToken);
            if (cancellationToken.IsCancellationRequested || provider != _v3ExactHubProvider || _v3ExactApiHost is null)
            {
                return;
            }

            _v3ExactApiHost.Children.Clear();
            if (result.Cards.Count == 0)
            {
                _v3ExactApiHost.Children.Add(BuildV3ExactHubMessage(
                    string.IsNullOrWhiteSpace(query) ? "No scripts on this page." : "No scripts match your search.",
                    "#868686"));
            }
            else
            {
                _v3ExactApiHost.Children.Add(new ScrollViewer
                {
                    VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
                    HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
                    Content = BuildV3ExactCardsGrid(result.Cards, false)
                });
            }
            UpdateV3ExactPager(page, result.HasMore, false);
        }
        catch (OperationCanceledException)
        {
            // A provider change or newer search replaced this request.
        }
        catch (Exception exception) when (
            exception is HttpRequestException or IOException or InvalidDataException or ObjectDisposedException)
        {
            if (cancellationToken.IsCancellationRequested || _v3ExactApiHost is null) return;
            _v3ExactApiHost.Children.Clear();
            _v3ExactApiHost.Children.Add(BuildV3ExactHubMessage(exception.Message, "#CC6E6E"));
            UpdateV3ExactPager(page, false, false);
        }
    }

    private void UpdateV3ExactPager(int page, bool hasMore, bool loading)
    {
        _v3ExactHubPage = page;
        _v3ExactHubHasMore = hasMore;
        if (_v3ExactPageLabel is not null) _v3ExactPageLabel.Text = $"Page {page}";
        if (_v3ExactPreviousButton is not null)
        {
            _v3ExactPreviousButton.IsEnabled = !loading && page > 1;
            _v3ExactPreviousButton.Opacity = !loading && page > 1 ? 1 : .35;
        }
        if (_v3ExactNextButton is not null)
        {
            _v3ExactNextButton.IsEnabled = !loading && hasMore;
            _v3ExactNextButton.Opacity = !loading && hasMore ? 1 : .35;
        }
    }

    private static Control BuildV3ExactHubMessage(string text, string color)
    {
        return new TextBlock
        {
            Text = text,
            Foreground = Brush(color),
            FontSize = 12,
            TextAlignment = TextAlignment.Center,
            TextWrapping = TextWrapping.Wrap,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new Thickness(20)
        };
    }

    private Grid BuildV3ExactCardsGrid(IReadOnlyList<ScriptHubCardModel> cards, bool synapseLegacy)
    {
        var rows = Math.Max(1, (cards.Count + 3) / 4);
        var grid = new Grid
        {
            ColumnDefinitions = new ColumnDefinitions("*,8,*,8,*,8,*"),
            RowDefinitions = new RowDefinitions(string.Join(',', Enumerable.Repeat("165", rows * 2 - 1)))
        };
        for (var separator = 1; separator < rows * 2 - 1; separator += 2)
        {
            grid.RowDefinitions[separator].Height = new GridLength(8);
        }

        for (var index = 0; index < cards.Count; index++)
        {
            var card = BuildV3ExactHubCard(cards[index], synapseLegacy);
            Grid.SetColumn(card, (index % 4) * 2);
            Grid.SetRow(card, (index / 4) * 2);
            grid.Children.Add(card);
        }
        return grid;
    }

    private Border BuildV3ExactHubCard(ScriptHubCardModel card, bool synapseLegacy)
    {
        var image = new Image
        {
            Source = card.Thumbnail ?? BlueFallbackImage(),
            Stretch = Stretch.UniformToFill
        };
        var surface = new Grid();
        surface.Children.Add(image);
        surface.Children.Add(new Border
        {
            Height = 88,
            VerticalAlignment = VerticalAlignment.Bottom,
            Background = new LinearGradientBrush
            {
                StartPoint = new RelativePoint(0, 0, RelativeUnit.Relative),
                EndPoint = new RelativePoint(0, 1, RelativeUnit.Relative),
                GradientStops = new GradientStops
                {
                    new(Color.Parse("#00161616"), 0),
                    new(Color.Parse("#DC161616"), 1)
                }
            },
            IsHitTestVisible = false
        });

        var details = new StackPanel { Spacing = 5 };
        var title = new TextBlock
        {
            Foreground = Brush("#F6F6F5"),
            FontSize = 12,
            TextTrimming = TextTrimming.CharacterEllipsis
        };
        title.Inlines?.Add(new Run(card.Title) { FontWeight = FontWeight.SemiBold });
        title.Inlines?.Add(new Run($" · {card.Subtitle}") { Foreground = Brush("#B0B0B0") });
        details.Children.Add(title);

        var actionColumns = synapseLegacy ? "*,4,24" : "*,4,24,4,24";
        var actions = new Grid { Height = 24, ColumnDefinitions = new ColumnDefinitions(actionColumns) };
        var execute = new Button
        {
            Content = "Execute",
            Background = Brush("#303030"),
            BorderBrush = Brush("#555555"),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(3),
            Foreground = Brush("#C8C8C8"),
            FontSize = 10,
            Padding = new Thickness(4, 0)
        };
        var executeVisual = execute;
        RegisterBridgeSourceAction(execute, executeVisual, () => Task.FromResult(card.ScriptBody));
        actions.Children.Add(execute);

        var open = new Button
        {
            Width = 24,
            Height = 24,
            Background = Brush("#303030"),
            BorderThickness = new Thickness(0),
            CornerRadius = new CornerRadius(3),
            Padding = new Thickness(0),
            Content = CreateSvgIcon("M2 10L10 2M10 2H4.5M10 2V7.5", 11, "#FFFFFF", 12, true)
        };
        open.Click += (_, _) => OpenV3ExactHubScript(card, synapseLegacy ? "Synapse Script Hub" : V3ExactProviderName(_v3ExactHubProvider));
        Grid.SetColumn(open, 2);
        actions.Children.Add(open);

        if (!synapseLegacy)
        {
            var view = new Button
            {
                Width = 24,
                Height = 24,
                Background = Brush("#303030"),
                BorderThickness = new Thickness(0),
                CornerRadius = new CornerRadius(3),
                Padding = new Thickness(0),
                Content = CreateSvgIcon("M4.5 2H2V10H10V7.5M7 2H10V5M10 2L5.5 6.5", 11, "#C8C8C8", 12, true)
            };
            ToolTip.SetTip(view, "View on website");
            view.Click += (_, _) =>
            {
                if (!Uri.TryCreate(card.ExternalUrl, UriKind.Absolute, out var uri)) return;
                try
                {
                    Process.Start(new ProcessStartInfo(uri.ToString()) { UseShellExecute = true });
                }
                catch (System.ComponentModel.Win32Exception) { }
            };
            Grid.SetColumn(view, 4);
            actions.Children.Add(view);
        }
        details.Children.Add(actions);

        surface.Children.Add(new Border
        {
            VerticalAlignment = VerticalAlignment.Bottom,
            Padding = new Thickness(8, 6),
            Background = Brush("#D1161616"),
            BorderBrush = Brush("#14FFFFFF"),
            BorderThickness = new Thickness(0, 1, 0, 0),
            CornerRadius = new CornerRadius(0, 0, 7, 7),
            Child = details
        });

        return new Border
        {
            Height = 165,
            Background = Brush("#303030"),
            CornerRadius = new CornerRadius(7),
            ClipToBounds = true,
            Child = surface
        };
    }

    private void OpenV3ExactHubScript(ScriptHubCardModel card, string source)
    {
        ActiveTab().Content = _editorContent;
        var tab = new EditorTabState
        {
            Title = card.Title,
            Extension = ".lua",
            Content = string.IsNullOrWhiteSpace(card.ScriptBody)
                ? $"-- {source}: {card.Title}\n-- No source returned.\n"
                : card.ScriptBody
        };
        _workspace.Tabs.Add(tab);
        _workspace.ActiveTabId = tab.Id;
        _editorContent = tab.Content;
        RebuildTabs(SynapseFrontendKind.V3);
        SetEditorContent(tab.Content);
        ShowV3Page(0);
    }

    private static string V3ExactProviderName(ScriptHubProvider provider) => provider switch
    {
        ScriptHubProvider.RobloxScripts => "robloxscripts.com",
        ScriptHubProvider.ScriptBlox => "scriptblox.com",
        ScriptHubProvider.HaxHell => "haxhell.com",
        ScriptHubProvider.Rscripts => "rscripts.net",
        _ => "scripts"
    };

    private void DisposeV3ExactPages()
    {
        _v3ExactHubCancellation?.Cancel();
        _v3ExactHubCancellation?.Dispose();
        _v3ExactHubCancellation = null;
    }
}
