using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Shapes;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Media.Imaging;
using Avalonia.Platform;
using Avalonia.Threading;

namespace OrbitAvalonia;

public sealed partial class MainWindow
{
    private ContentControl _settingsContentHost = null!;
    private ScrollViewer _settingsContentScrollViewer = null!;
    private TranslateTransform _settingsContentTranslation = null!;
    private readonly Dictionary<SettingsTab, SettingsTabVisuals> _settingsTabVisuals = [];
    private readonly Dictionary<SynapseFrontendKind, List<DateTime>> _synapseDeveloperClicks = [];
    private CancellationTokenSource? _settingsTabAnimationCancellation;
    private SettingsTab _selectedSettingsTab = SettingsTab.General;

    private void InitializeSettingsPage()
    {
        _settingsContentHost = this.FindControl<ContentControl>("SettingsContentHost") ?? new ContentControl();
        _settingsContentScrollViewer = this.FindControl<ScrollViewer>("SettingsContentScrollViewer") ?? new ScrollViewer();
        _settingsContentTranslation = new TranslateTransform();
        _settingsContentHost.RenderTransform = _settingsContentTranslation;

        RegisterSettingsTab(SettingsTab.General, "General", "SettingsTabGeneralBackground", "SettingsTabGeneralText", "SettingsSectionGeneralText");
        RegisterSettingsTab(SettingsTab.Global, "Global Settings (All UIs)", "SettingsTabGlobalBackground", "SettingsTabGlobalText", "SettingsSectionGlobalText");
        RegisterSettingsTab(SettingsTab.Bridge, "Bridge Explainer", "SettingsTabBridgeBackground", "SettingsTabBridgeText", "SettingsSectionBridgeText");
        RegisterSettingsTab(SettingsTab.Setup, "Back to Setup", "SettingsTabSetupBackground", "SettingsTabSetupText", "SettingsSectionSetupText");
        RegisterSettingsTab(SettingsTab.AutoOpen, "Auto Open", "SettingsTabAutoOpenBackground", "SettingsTabAutoOpenText", "SettingsSectionAutoOpenText");
        RegisterSettingsTab(SettingsTab.UiSelect, "UI Select", "SettingsTabUiSelectBackground", "SettingsTabUiSelectText", "SettingsSectionUiSelectText");
        RegisterSettingsTab(SettingsTab.Account, "Account", "SettingsTabAccountBackground", "SettingsTabAccountText", null);
        RegisterSettingsTab(SettingsTab.About, "About", "SettingsTabAboutBackground", "SettingsTabAboutText", "SettingsSectionAboutText");

        UpdateSettingsTabVisuals();
        ApplySettingsContentInsets(_selectedSettingsTab);
        _settingsContentHost.Content = BuildSettingsContent(_selectedSettingsTab);
    }

    private void RegisterSettingsTab(
        SettingsTab tab,
        string displayName,
        string backgroundName,
        string tabTextName,
        string? sectionTextName)
    {
        _settingsTabVisuals[tab] = new SettingsTabVisuals(
            displayName,
            this.FindControl<Border>(backgroundName) ?? new Border(),
            this.FindControl<TextBlock>(tabTextName) ?? new TextBlock(),
            sectionTextName is null
                ? null
                : this.FindControl<TextBlock>(sectionTextName) ?? new TextBlock());
    }

    private async void SettingsTab_Click(object? sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: string tag } ||
            !Enum.TryParse<SettingsTab>(tag, out var tab) ||
            tab == _selectedSettingsTab)
        {
            return;
        }

        await SelectSettingsTabAsync(tab);
    }

    private async Task SelectSettingsTabAsync(SettingsTab tab)
    {
        _settingsTabAnimationCancellation?.Cancel();
        _settingsTabAnimationCancellation?.Dispose();
        _settingsTabAnimationCancellation = new CancellationTokenSource();
        var cancellationToken = _settingsTabAnimationCancellation.Token;

        try
        {
            if (SystemAnimationsEnabled())
            {
                var startOpacity = _settingsContentHost.Opacity;
                await AnimateAsync(
                    TimeSpan.FromMilliseconds(90),
                    progress =>
                    {
                        _settingsContentHost.Opacity = Lerp(startOpacity, 0, progress);
                        _settingsContentTranslation.Y = Lerp(0, -4, progress);
                    },
                    CubicEaseIn,
                    cancellationToken);
            }

            _selectedSettingsTab = tab;
            UpdateSettingsTabVisuals();
            ApplySettingsContentInsets(tab);
            _settingsContentHost.Content = BuildSettingsContent(tab);
            _settingsContentScrollViewer.Offset = new Vector(0, 0);
            _settingsContentHost.Opacity = 0;
            _settingsContentTranslation.Y = 7;

            if (SystemAnimationsEnabled())
            {
                await AnimateAsync(
                    TimeSpan.FromMilliseconds(150),
                    progress =>
                    {
                        _settingsContentHost.Opacity = progress;
                        _settingsContentTranslation.Y = Lerp(7, 0, progress);
                    },
                    CubicEaseOut,
                    cancellationToken);
            }

            _settingsContentHost.Opacity = 1;
            _settingsContentTranslation.Y = 0;
        }
        catch (OperationCanceledException)
        {
            // A newer settings tab selection replaced this transition.
        }
    }

    private void UpdateSettingsTabVisuals()
    {
        foreach (var (tab, visuals) in _settingsTabVisuals)
        {
            var selected = tab == _selectedSettingsTab;
            visuals.Background.Opacity = selected ? 1 : 0.53;
            visuals.TabText.Opacity = selected ? 1 : 0.53;
            visuals.TabText.Foreground = selected ? Brushes.White : BrushFrom("#A5A1A2");
            if (visuals.SectionText is not null)
            {
                visuals.SectionText.Foreground = selected ? Brushes.White : BrushFrom("#A5A1A2");
                visuals.SectionText.FontWeight = selected ? FontWeight.SemiBold : FontWeight.Normal;
            }
        }
    }

    private Control BuildSettingsContent(SettingsTab tab) => tab switch
    {
        SettingsTab.General => BuildGeneralSettingsPreview(),
        SettingsTab.Global => BuildGlobalSettingsPreview(),
        SettingsTab.Bridge => BuildBridgeSettingsPreview(),
        SettingsTab.Setup => BuildSetupSettingsPreview(),
        SettingsTab.AutoOpen => BuildAutoOpenSettingsPreview(),
        SettingsTab.UiSelect => BuildUiSelectSettingsPreview(),
        SettingsTab.Account => BuildAccountSettingsPreview(),
        SettingsTab.About => BuildAboutSettingsPreview(),
        _ => BuildGeneralSettingsPreview()
    };

    private Control BuildGeneralSettingsPreview()
    {
        var root = CreateFigmaLibraryPage("General");
        AddFigmaLibrarySetting(
            root,
            "Legacy Colours",
            64,
            CreateFigmaLibraryToggle(
                OrbitPreferences.LegacyColoursEnabled,
                SetLegacyColours));
        return root;
    }

    private Control BuildGlobalSettingsPreview()
    {
        var root = CreateFigmaLibraryPage("Global Settings");
        AddFigmaLibrarySetting(root, "Top Most", 64, CreateTopMostToggle());
        AddFigmaLibrarySetting(root, "Resizable", 122, CreateResizableToggle());
        return root;
    }

    private Button CreateTopMostToggle()
    {
        var button = CreateFigmaLibraryToggle(
            OrbitPreferences.TopMostEnabled,
            enabled =>
            {
                OrbitPreferences.SetTopMost(enabled);
                Topmost = enabled;
            });
        ToolTip.SetTip(button, "Always on top");
        return button;
    }

    private Button CreateResizableToggle()
    {
        var button = CreateFigmaLibraryToggle(
            OrbitPreferences.ResizableEnabled,
            enabled =>
            {
                OrbitPreferences.SetResizable(enabled);
                ApplyResizablePreference(enabled);
            });
        ToolTip.SetTip(button, "Allow Orbit interfaces to resize");
        return button;
    }

    private Control BuildBridgeSettingsPreview()
    {
        var root = CreateFigmaSettingsPage(
            "Bridge Explainer",
            "Use Orion Bridge to connect an executor to the native UI.");
        root.Children.Add(CreateFigmaSettingsRow(
            "1. Place the bridge",
            "Copy Orion Bridge.lua from Scripts into your executor's autoexec folder.",
            CreateSettingsValuePill("Autoexec")));
        root.Children.Add(CreateFigmaSettingsRow(
            "2. Connect",
            "Open your desired executor. Attach and open a game.",
            CreateSettingsValuePill("Attach")));
        root.Children.Add(CreateFigmaSettingsRow(
            "3. Execute",
            "Once connected, Execute and Execute File become available.",
            CreateSettingsValuePill("Ready")));
        root.Children.Add(CreateFigmaSettingsRow(
            "Transport order",
            "Orbit tries Port, then Stream, then Compat automatically.",
            CreateSettingsValuePill("Automatic")));
        return root;
    }

    private Control BuildSetupSettingsPreview()
    {
        var stack = new StackPanel
        {
            Spacing = 16,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center
        };
        stack.Children.Add(new TextBlock
        {
            Text = "Prototype: Not Available yet",
            FontSize = 12,
            Foreground = BrushFrom("#73787D"),
            HorizontalAlignment = HorizontalAlignment.Center
        });

        var previewButton = new Button
        {
            Classes = { "setup-action", "setup-primary" },
            Width = 184,
            Height = 38,
            Content = "View Setup Prototype",
            HorizontalAlignment = HorizontalAlignment.Center
        };
        previewButton.Click += (_, _) => _ = ShowSetupPrototypeAsync();
        stack.Children.Add(previewButton);

        return new Grid
        {
            Width = 590,
            Height = 420,
            Children = { stack }
        };
    }

    private Control BuildAutoOpenSettingsPreview()
    {
        return CreatePrototypeSettingsView("Prototype: Not Available yet");
    }

    private Control BuildUiSelectSettingsPreview()
    {
        var root = new Canvas
        {
            Width = 647,
            Height = 433,
            HorizontalAlignment = HorizontalAlignment.Left,
            VerticalAlignment = VerticalAlignment.Top
        };

        var heading = new TextBlock
        {
            Text = "UI Selection",
            FontSize = 19,
            FontWeight = FontWeight.SemiBold,
            Foreground = Brushes.White
        };
        Canvas.SetLeft(heading, 8);
        Canvas.SetTop(heading, 4);
        root.Children.Add(heading);

        var wordmark = new Image
        {
            Width = 226,
            Height = 74,
            Stretch = Stretch.Uniform,
            Source = new Bitmap(AssetLoader.Open(
                new Uri("avares://Orion/Assets/Synapse/framework-wordmark.png")))
        };
        RenderOptions.SetBitmapInterpolationMode(wordmark, BitmapInterpolationMode.HighQuality);
        Canvas.SetLeft(wordmark, 2);
        Canvas.SetTop(wordmark, 28);
        root.Children.Add(wordmark);

        var description = new TextBlock
        {
            Width = 590,
            Text = "Synapse: Frameworks UIs ported to work natively rather than on a web based framework. until the prototyping phase is over,\n" +
                   "they are not a focus. but an early preview of the v3 port is available",
            FontSize = 9.5,
            LineHeight = 14,
            Foreground = BrushFrom("#777A7D"),
            TextWrapping = TextWrapping.NoWrap
        };
        Canvas.SetLeft(description, 2);
        Canvas.SetTop(description, 103);
        root.Children.Add(description);

        var synapseChoices = new Grid
        {
            ColumnDefinitions = new ColumnDefinitions("122,9,122,9,147,9,147"),
            HorizontalAlignment = HorizontalAlignment.Stretch,
            VerticalAlignment = VerticalAlignment.Center
        };
        AddUiSelectChoice(synapseChoices,
            CreateDeveloperSynapseChoiceButton("Synapse X", "Disabled", SynapseFrontendKind.SynapseX), 0);
        AddUiSelectChoice(synapseChoices,
            CreateDeveloperSynapseChoiceButton("Synapse Blue", "Disabled", SynapseFrontendKind.Blue), 2);
        AddUiSelectChoice(synapseChoices,
            CreateDeveloperSynapseChoiceButton("Synapse 2016–2019", "Disabled", SynapseFrontendKind.Classic2017), 4);
        var synapseV3Button = CreateUiSelectChoiceButton("Synapse V3", "Preview build");
        synapseV3Button.Click += (_, _) => _ = ActivateSynapseUiAsync(SynapseFrontendKind.V3);
        AddUiSelectChoice(synapseChoices, synapseV3Button, 6);

        var synapseCard = CreateUiSelectCard(synapseChoices, 82);
        Canvas.SetLeft(synapseCard, 0);
        Canvas.SetTop(synapseCard, 139);
        root.Children.Add(synapseCard);

        var otherHeading = new TextBlock
        {
            Text = "Other UIs",
            FontSize = 17,
            FontWeight = FontWeight.SemiBold,
            Foreground = BrushFrom("#B5B7B9")
        };
        Canvas.SetLeft(otherHeading, 8);
        Canvas.SetTop(otherHeading, 235);
        root.Children.Add(otherHeading);

        var otherChoices = new Grid
        {
            ColumnDefinitions = new ColumnDefinitions("*,14,*"),
            RowDefinitions = new RowDefinitions("*,12,*"),
            HorizontalAlignment = HorizontalAlignment.Stretch,
            VerticalAlignment = VerticalAlignment.Top
        };
        var rc7Button = CreateUiSelectChoiceButton("RC7", "Open interface");
        rc7Button.Click += (_, _) => _ = ActivateRc7UiAsync();
        AddUiSelectChoice(otherChoices, rc7Button, 0);
        var krnlButton = CreateUiSelectChoiceButton("Krnl", "Open interface");
        krnlButton.Click += (_, _) => _ = ActivateKrnlUiAsync();
        AddUiSelectChoice(otherChoices, krnlButton, 2);
        var xenoButton = CreateUiSelectChoiceButton("Xeno", "Open interface");
        xenoButton.Click += (_, _) => _ = ActivateXenoUiAsync();
        AddUiSelectChoice(otherChoices, xenoButton, 0, 2);
        var calamariButton = CreateUiSelectChoiceButton("Calimari", "Open interface");
        calamariButton.Click += (_, _) => _ = ActivateCalamariUiAsync();
        AddUiSelectChoice(otherChoices, calamariButton, 2, 2);

        var otherCard = CreateUiSelectCard(otherChoices, 154);
        Canvas.SetLeft(otherCard, 0);
        Canvas.SetTop(otherCard, 263);
        root.Children.Add(otherCard);

        return root;
    }

    private Button CreateDeveloperSynapseChoiceButton(
        string label,
        string status,
        SynapseFrontendKind kind)
    {
        var button = CreateUiSelectChoiceButton(label, status, navigable: false);
        button.Classes.Add("ui-choice-dev-disabled");
        ToolTip.SetTip(button, "Developer build: click three times within five seconds to open this UI.");
        button.Click += (_, _) =>
        {
            var now = DateTime.UtcNow;
            if (!_synapseDeveloperClicks.TryGetValue(kind, out var clicks))
            {
                clicks = [];
                _synapseDeveloperClicks[kind] = clicks;
            }

            clicks.RemoveAll(timestamp => now - timestamp > TimeSpan.FromSeconds(5));
            clicks.Add(now);
            if (clicks.Count < 3)
            {
                return;
            }

            clicks.Clear();
            _ = ActivateSynapseUiAsync(kind);
        };
        return button;
    }

    private static void ApplySettingsContentInsets(SettingsTab tab, ContentControl host)
    {
        host.Margin = tab == SettingsTab.UiSelect
            ? new Thickness(10, 22, 10, 12)
            : tab is SettingsTab.General or SettingsTab.Global
                ? new Thickness(30, 16, 24, 24)
                : new Thickness(24, 22, 24, 24);
    }

    private void ApplySettingsContentInsets(SettingsTab tab)
    {
        ApplySettingsContentInsets(tab, _settingsContentHost);
    }

    private static Border CreateUiSelectCard(Control content, double height)
    {
        var background = new LinearGradientBrush
        {
            StartPoint = new RelativePoint(0, 0, RelativeUnit.Relative),
            EndPoint = new RelativePoint(1, 1, RelativeUnit.Relative),
            GradientStops =
            {
                new GradientStop(ThemeColor("#13171B"), 0),
                new GradientStop(ThemeColor("#101317"), 1)
            }
        };

        return new Border
        {
            Width = 590,
            Height = height,
            Background = background,
            BorderBrush = BrushFrom("#282D32"),
            BorderThickness = new Thickness(0.75),
            CornerRadius = new CornerRadius(12),
            Padding = new Thickness(12.25),
            Child = content
        };
    }

    private static void AddUiSelectChoice(Grid grid, Button button, int column, int row = 0)
    {
        Grid.SetColumn(button, column);
        Grid.SetRow(button, row);
        grid.Children.Add(button);
    }

    private static Button CreateUiSelectChoiceButton(
        string label,
        string status,
        bool navigable = true)
    {
        var content = new Grid
        {
            ColumnDefinitions = new ColumnDefinitions("5,9,*,11"),
            HorizontalAlignment = HorizontalAlignment.Stretch,
            VerticalAlignment = VerticalAlignment.Center
        };

        var stateDot = new Ellipse
        {
            Width = 5,
            Height = 5,
            Fill = BrushFrom(navigable ? "#BFC3C7" : "#4F5459"),
            VerticalAlignment = VerticalAlignment.Center
        };
        content.Children.Add(stateDot);

        var copy = new StackPanel
        {
            Spacing = 1,
            HorizontalAlignment = HorizontalAlignment.Stretch,
            VerticalAlignment = VerticalAlignment.Center
        };
        copy.Children.Add(new TextBlock
        {
            Text = label,
            FontSize = 9.5,
            FontWeight = FontWeight.SemiBold,
            Foreground = BrushFrom(navigable ? "#F1F2F3" : "#A0A4A8"),
            HorizontalAlignment = HorizontalAlignment.Stretch,
            TextAlignment = TextAlignment.Left,
            TextTrimming = TextTrimming.CharacterEllipsis
        });
        copy.Children.Add(new TextBlock
        {
            Text = status,
            FontSize = 7.75,
            Foreground = BrushFrom(navigable ? "#858B90" : "#64696E"),
            HorizontalAlignment = HorizontalAlignment.Stretch,
            TextAlignment = TextAlignment.Left,
            TextTrimming = TextTrimming.CharacterEllipsis
        });
        Grid.SetColumn(copy, 2);
        content.Children.Add(copy);

        var chevron = new TextBlock
        {
            Text = "›",
            FontSize = 15,
            FontWeight = FontWeight.Light,
            Foreground = BrushFrom("#8D9398"),
            Opacity = navigable ? 1 : 0,
            HorizontalAlignment = HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Center,
            IsHitTestVisible = false
        };
        Grid.SetColumn(chevron, 3);
        content.Children.Add(chevron);

        var button = new Button
        {
            Height = 54,
            Padding = new Thickness(10, 4),
            HorizontalAlignment = HorizontalAlignment.Stretch,
            VerticalAlignment = VerticalAlignment.Center,
            Content = content
        };
        button.Classes.Add("ui-choice");
        return button;
    }

    private static Canvas CreateFigmaLibraryPage(string title)
    {
        var root = new Canvas
        {
            Width = 590,
            Height = 400
        };
        var heading = new TextBlock
        {
            Text = title,
            FontSize = 20,
            FontWeight = FontWeight.SemiBold,
            Foreground = Brushes.White
        };
        Canvas.SetLeft(heading, 0);
        Canvas.SetTop(heading, 0);
        root.Children.Add(heading);
        return root;
    }

    private static void AddFigmaLibrarySetting(
        Canvas root,
        string title,
        double top,
        Control trailing)
    {
        var label = new TextBlock
        {
            Text = title,
            FontSize = 15,
            FontWeight = FontWeight.Light,
            Foreground = Brushes.White
        };
        Canvas.SetLeft(label, 0);
        Canvas.SetTop(label, top);
        root.Children.Add(label);

        Canvas.SetLeft(trailing, 512);
        Canvas.SetTop(trailing, top + 2);
        root.Children.Add(trailing);
    }

    private static Button CreateFigmaLibraryToggle(
        bool initialEnabled,
        Action<bool>? changed = null)
    {
        var track = new Border
        {
            Width = 70,
            Height = 33,
            CornerRadius = new CornerRadius(16.5),
            BorderBrush = BrushFrom("#505255"),
            BorderThickness = new Thickness(1),
            Background = new LinearGradientBrush
            {
                StartPoint = new RelativePoint(0, 0, RelativeUnit.Relative),
                EndPoint = new RelativePoint(1, 1, RelativeUnit.Relative),
                GradientStops =
                {
                    new GradientStop(ThemeColor("#222426"), 0),
                    new GradientStop(ThemeColor("#15181C"), 1)
                }
            }
        };
        var knob = new Border
        {
            Width = 29,
            Height = 29,
            CornerRadius = new CornerRadius(14.5),
            BorderBrush = BrushFrom("#505255"),
            BorderThickness = new Thickness(1)
        };
        var artwork = new Canvas { Width = 70, Height = 33 };
        artwork.Children.Add(track);
        artwork.Children.Add(knob);

        var enabled = initialEnabled;
        void UpdateVisual()
        {
            knob.Background = enabled
                ? new LinearGradientBrush
                {
                    StartPoint = new RelativePoint(0, 0, RelativeUnit.Relative),
                    EndPoint = new RelativePoint(1, 1, RelativeUnit.Relative),
                    GradientStops =
                    {
                        new GradientStop(Color.Parse("#FFFFFF"), 0),
                        new GradientStop(Color.Parse("#003479"), 1)
                    }
                }
                : new LinearGradientBrush
                {
                    StartPoint = new RelativePoint(0, 0, RelativeUnit.Relative),
                    EndPoint = new RelativePoint(1, 1, RelativeUnit.Relative),
                    GradientStops =
                    {
                        new GradientStop(ThemeColor("#62676B"), 0),
                        new GradientStop(ThemeColor("#24282C"), 1)
                    }
                };
            Canvas.SetLeft(knob, enabled ? 38 : 3);
            Canvas.SetTop(knob, 2);
        }

        var button = new Button
        {
            Width = 70,
            Height = 33,
            Padding = new Thickness(0),
            Background = Brushes.Transparent,
            BorderThickness = new Thickness(0),
            Cursor = new Cursor(StandardCursorType.Hand),
            HorizontalContentAlignment = HorizontalAlignment.Left,
            VerticalContentAlignment = VerticalAlignment.Top,
            Content = artwork
        };
        button.Click += (_, _) =>
        {
            enabled = !enabled;
            UpdateVisual();
            changed?.Invoke(enabled);
        };
        UpdateVisual();
        return button;
    }

    private static StackPanel CreateFigmaSettingsPage(string title, string description)
    {
        var root = new StackPanel
        {
            Width = 590,
            Spacing = 0
        };
        root.Children.Add(new TextBlock
        {
            Text = title,
            FontSize = 20,
            FontWeight = FontWeight.SemiBold,
            Foreground = Brushes.White
        });
        root.Children.Add(new TextBlock
        {
            Text = description,
            FontSize = 10,
            LineHeight = 14,
            Foreground = BrushFrom("#73787D"),
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(0, 5, 0, 17)
        });
        return root;
    }

    private static Border CreateFigmaSettingsRow(string title, string detail, Control trailing)
    {
        var row = new Grid
        {
            ColumnDefinitions = new ColumnDefinitions("*,Auto"),
            MinHeight = 58
        };
        var copy = new StackPanel
        {
            Spacing = 3,
            VerticalAlignment = VerticalAlignment.Center
        };
        copy.Children.Add(new TextBlock
        {
            Text = title,
            FontSize = 13,
            FontWeight = FontWeight.Light,
            Foreground = Brushes.White
        });
        copy.Children.Add(new TextBlock
        {
            Text = detail,
            FontSize = 9.5,
            Foreground = BrushFrom("#73787D"),
            TextWrapping = TextWrapping.Wrap,
            MaxWidth = 465
        });
        row.Children.Add(copy);
        trailing.VerticalAlignment = VerticalAlignment.Center;
        Grid.SetColumn(trailing, 1);
        row.Children.Add(trailing);
        return new Border
        {
            BorderBrush = BrushFrom("#22272C"),
            BorderThickness = new Thickness(0, 0, 0, 1),
            Child = row
        };
    }

    private static Border CreateSettingsValuePill(string text)
    {
        return new Border
        {
            Background = BrushFrom("#15191D"),
            BorderBrush = BrushFrom("#3A4148"),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(16),
            Padding = new Thickness(11, 5),
            Child = new TextBlock
            {
                Text = text,
                FontSize = 8.5,
                Foreground = BrushFrom("#AEB4B9")
            }
        };
    }

    private static Control CreatePrototypeSettingsView(string message)
    {
        var grid = new Grid
        {
            Width = 590,
            Height = 420
        };
        grid.Children.Add(new TextBlock
        {
            Text = message,
            FontSize = 12,
            Foreground = BrushFrom("#73787D"),
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center
        });
        return grid;
    }

    private static Control CreateSettingsMessageView(string title, string body)
    {
        var root = new StackPanel
        {
            Width = 590,
            Spacing = 12
        };
        root.Children.Add(new TextBlock
        {
            Text = title,
            FontSize = 20,
            FontWeight = FontWeight.SemiBold,
            Foreground = Brushes.White
        });
        root.Children.Add(new TextBlock
        {
            Text = body,
            FontSize = 11,
            LineHeight = 17,
            Foreground = BrushFrom("#858A8F"),
            TextWrapping = TextWrapping.Wrap,
            MaxWidth = 570
        });
        return root;
    }

    private static Border CreateAboutSection(string title, string body)
    {
        return new Border
        {
            BorderBrush = BrushFrom("#22272C"),
            BorderThickness = new Thickness(0, 0, 0, 1),
            Padding = new Thickness(0, 0, 0, 14),
            Margin = new Thickness(0, 0, 0, 14),
            Child = new StackPanel
            {
                Spacing = 5,
                Children =
                {
                    new TextBlock
                    {
                        Text = title,
                        FontSize = 14,
                        FontWeight = FontWeight.Light,
                        Foreground = Brushes.White
                    },
                    new TextBlock
                    {
                        Text = body,
                        FontSize = 10.5,
                        LineHeight = 16,
                        Foreground = BrushFrom("#858A8F"),
                        TextWrapping = TextWrapping.Wrap
                    }
                }
            }
        };
    }

    private Control BuildAccountSettingsPreview()
    {
        return CreateSettingsMessageView(
            "Does this mean its becoming an executor?",
            "No, accounts is simply a choice in the future. you will have the ability to setup a local account to keep your orbit workspace safe from the prying eyes of others around you, dont worry. when it exists you will be able to skip it.");
    }

    private Control BuildAboutSettingsPreview()
    {
        var root = CreateFigmaSettingsPage(
            "About",
            "Orbit is the native successor to Synapse: Framework.");
        root.Children.Add(CreateAboutSection(
            "Orbit",
            "Orbit is the successor to Synapse: Framework. While Synapse Framework was based on Tauri, fully web based. Orbit is built on AvaloniaUI. so its fully 100% Native. allowing much more accuracy in UI remakes. along with better performance and more."));
        root.Children.Add(CreateAboutSection(
            "Why?",
            "Orbit was built because the developer (me) \"_snooped\" on Discord. was building out synapse framework. and ran into huge issues constantly due to the limitations of Tauri, when trying electron as a last resort. it just made things worse. so i did some research, found AvaloniaUI. found out it was relatively easy to work with as my UI work is usually heavy in figma. and here we are. to help with the problem of burning out. i wanted more freedom. so i made a completely original UI utilizing every skill i could. without copying other UI projects. and making something i can find myself using on a daily basis while my users have fun with the remakes"));
        root.Children.Add(CreateAboutSection(
            "What about the other UIs?",
            "Synapse: Framework is being ported over currently. its web based UI is extremely difficult to work with when it comes to converting it to native UI. but in the end. it will be worth it.\n\nas for the other UIs. in the \"Other UIs\" section. many of those are either remakes i made myself again. or direct ports of leaked UI sources. thats why they feel so accurate. they literally are those original UIs ported over 1 to 1."));
        return root;
    }

    private static Control CreateBareSettingsView(
        string eyebrow,
        string title,
        string description,
        string sectionTitle,
        params (string Label, string Value)[] rows)
    {
        var root = CreateSettingsPage(eyebrow, title, description);
        root.Children.Add(CreateBareSettingsSection(sectionTitle, rows));
        return root;
    }

    private static Border CreateBareSettingsSection(
        string title,
        params (string Label, string Value)[] rows)
    {
        var stack = new StackPanel { Spacing = 0 };
        stack.Children.Add(new TextBlock
        {
            Text = title,
            FontSize = 10.5,
            FontWeight = FontWeight.SemiBold,
            Foreground = BrushFrom("#D5D7D9"),
            Margin = new Thickness(0, 0, 0, 10)
        });

        for (var index = 0; index < rows.Length; index++)
        {
            var row = new Grid
            {
                ColumnDefinitions = new ColumnDefinitions("*,Auto"),
                Height = 46
            };
            row.Children.Add(new TextBlock
            {
                Text = rows[index].Label,
                FontSize = 10.5,
                Foreground = BrushFrom("#B8BBBE"),
                VerticalAlignment = VerticalAlignment.Center
            });
            var value = new TextBlock
            {
                Text = rows[index].Value,
                FontSize = 10,
                Foreground = BrushFrom("#73787C"),
                VerticalAlignment = VerticalAlignment.Center
            };
            Grid.SetColumn(value, 1);
            row.Children.Add(value);

            stack.Children.Add(new Border
            {
                BorderBrush = BrushFrom("#24282C"),
                BorderThickness = new Thickness(0, index == 0 ? 1 : 0, 0, 1),
                Child = row
            });
        }

        return new Border
        {
            Background = BrushFrom("#111418"),
            BorderBrush = BrushFrom("#292D31"),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(10),
            Padding = new Thickness(16, 14, 16, 8),
            MaxWidth = 590,
            HorizontalAlignment = HorizontalAlignment.Stretch,
            Child = stack
        };
    }

    private static StackPanel CreateSettingsPage(string eyebrow, string title, string description)
    {
        var root = new StackPanel { Spacing = 12 };
        root.Children.Add(new TextBlock
        {
            Text = eyebrow,
            FontSize = 9,
            FontWeight = FontWeight.SemiBold,
            Foreground = BrushFrom("#666B70")
        });
        root.Children.Add(new TextBlock
        {
            Text = title,
            FontSize = 18,
            FontWeight = FontWeight.SemiBold,
            Foreground = Brushes.White
        });
        root.Children.Add(new TextBlock
        {
            Text = description,
            FontSize = 10.5,
            LineHeight = 15,
            TextWrapping = TextWrapping.Wrap,
            Foreground = BrushFrom("#7E8387"),
            Margin = new Thickness(0, -7, 0, 4)
        });
        return root;
    }

    private static Border CreateHeroCard(string title, string description, string badge, string accent)
    {
        var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };
        var copy = new StackPanel { Spacing = 5 };
        copy.Children.Add(new TextBlock
        {
            Text = title,
            FontSize = 14,
            FontWeight = FontWeight.SemiBold,
            Foreground = Brushes.White
        });
        copy.Children.Add(new TextBlock
        {
            Text = description,
            FontSize = 10.5,
            LineHeight = 15,
            TextWrapping = TextWrapping.Wrap,
            Foreground = BrushFrom("#92969A"),
            MaxWidth = 430
        });
        grid.Children.Add(copy);
        var pill = CreatePill(badge, accent);
        pill.VerticalAlignment = VerticalAlignment.Top;
        Grid.SetColumn(pill, 1);
        grid.Children.Add(pill);
        return CreateCard(grid, accent, new Thickness(17, 15));
    }

    private static Border CreateRowsCard(
        string title,
        string subtitle,
        params (string Title, string Detail, string Value, string Tone)[] rows)
    {
        var stack = new StackPanel { Spacing = 0 };
        stack.Children.Add(CreateCardHeading(title, subtitle));
        foreach (var row in rows)
        {
            stack.Children.Add(CreateInfoRow(row.Title, row.Detail, row.Value, row.Tone));
        }

        return CreateCard(stack, "#292D31", new Thickness(15, 13));
    }

    private static Control CreateCardHeading(string title, string subtitle)
    {
        var heading = new StackPanel { Spacing = 2, Margin = new Thickness(0, 0, 0, 7) };
        heading.Children.Add(new TextBlock
        {
            Text = title,
            FontSize = 12,
            FontWeight = FontWeight.SemiBold,
            Foreground = BrushFrom("#F1F1F2")
        });
        heading.Children.Add(new TextBlock
        {
            Text = subtitle,
            FontSize = 9.5,
            Foreground = BrushFrom("#74797D")
        });
        return heading;
    }

    private static Control CreateInfoRow(string title, string detail, string value, string tone)
    {
        var grid = new Grid
        {
            ColumnDefinitions = new ColumnDefinitions("*,Auto"),
            MinHeight = 43
        };
        var copy = new StackPanel { Spacing = 1, VerticalAlignment = VerticalAlignment.Center };
        copy.Children.Add(new TextBlock { Text = title, FontSize = 10.5, Foreground = BrushFrom("#E1E2E3") });
        copy.Children.Add(new TextBlock { Text = detail, FontSize = 8.5, Foreground = BrushFrom("#73787C"), TextTrimming = TextTrimming.CharacterEllipsis });
        grid.Children.Add(copy);
        var pill = CreatePill(value, tone);
        pill.VerticalAlignment = VerticalAlignment.Center;
        Grid.SetColumn(pill, 1);
        grid.Children.Add(pill);
        return new Border
        {
            BorderThickness = new Thickness(0, 1, 0, 0),
            BorderBrush = BrushFrom("#202428"),
            Child = grid
        };
    }

    private static Border CreatePill(string text, string tone)
    {
        return new Border
        {
            Background = BrushFrom(WithAlpha(tone, "22")),
            BorderBrush = BrushFrom(WithAlpha(tone, "70")),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(9),
            Padding = new Thickness(7, 3),
            Child = new TextBlock
            {
                Text = text,
                FontSize = 8.5,
                FontWeight = FontWeight.SemiBold,
                Foreground = BrushFrom(tone)
            }
        };
    }

    private static Border CreateCard(Control child, string accent, Thickness padding)
    {
        return new Border
        {
            Background = BrushFrom("#111418"),
            BorderBrush = BrushFrom(WithAlpha(accent, "66")),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(12),
            Padding = padding,
            Child = child
        };
    }

    private static Grid CreateTwoColumn(Control left, Control right)
    {
        var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("*,12,*") };
        Grid.SetColumn(left, 0);
        Grid.SetColumn(right, 2);
        grid.Children.Add(left);
        grid.Children.Add(right);
        return grid;
    }

    private static Control CreateStatusStrip(params (string Label, string Value, string Tone)[] items)
    {
        var grid = new Grid();
        for (var index = 0; index < items.Length; index++)
        {
            grid.ColumnDefinitions.Add(new ColumnDefinition(new GridLength(1, GridUnitType.Star)));
            if (index < items.Length - 1)
            {
                grid.ColumnDefinitions.Add(new ColumnDefinition(new GridLength(8)));
            }

            var item = new Border
            {
                Background = BrushFrom("#101317"),
                BorderBrush = BrushFrom("#282C30"),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(10),
                Padding = new Thickness(12, 9),
                Child = new StackPanel
                {
                    Spacing = 2,
                    Children =
                    {
                        new TextBlock { Text = items[index].Label, FontSize = 8.5, Foreground = BrushFrom("#70757A") },
                        new TextBlock { Text = items[index].Value, FontSize = 11, FontWeight = FontWeight.SemiBold, Foreground = BrushFrom(items[index].Tone) }
                    }
                }
            };
            Grid.SetColumn(item, index * 2);
            grid.Children.Add(item);
        }

        return grid;
    }

    private static Control CreateLayerCard()
    {
        var stack = new StackPanel { Spacing = 8 };
        stack.Children.Add(CreateCardHeading("Config layers", "A proposed precedence model"));
        stack.Children.Add(CreateLayer("01", "Profile", "Shared baseline", "#9B87B5"));
        stack.Children.Add(CreateLayer("02", "Workspace", "Project override", "#7699B8"));
        stack.Children.Add(CreateLayer("03", "Session", "Temporary choice", "#79A889"));
        return CreateCard(stack, "#292D31", new Thickness(15, 13));
    }

    private static Control CreateLayer(string number, string title, string detail, string tone)
    {
        var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("34,*,Auto") };
        var index = CreatePill(number, tone);
        index.HorizontalAlignment = HorizontalAlignment.Left;
        grid.Children.Add(index);
        var copy = new StackPanel { Spacing = 1, VerticalAlignment = VerticalAlignment.Center };
        copy.Children.Add(new TextBlock { Text = title, FontSize = 10, Foreground = Brushes.White });
        copy.Children.Add(new TextBlock { Text = detail, FontSize = 8.5, Foreground = BrushFrom("#74797D") });
        Grid.SetColumn(copy, 1);
        grid.Children.Add(copy);
        var line = new TextBlock { Text = number == "03" ? "FINAL" : "MERGE", FontSize = 7.5, Foreground = BrushFrom(tone), VerticalAlignment = VerticalAlignment.Center };
        Grid.SetColumn(line, 2);
        grid.Children.Add(line);
        return grid;
    }

    private static Control CreateFlowCard()
    {
        var outer = new StackPanel { Spacing = 9 };
        outer.Children.Add(CreateCardHeading("Local flow", "A visual explanation, not a live connection"));
        var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("*,30,*,30,*") };
        var editor = CreateFlowNode("01", "Editor", "Active buffer", "#7699B8");
        var bridge = CreateFlowNode("02", "Bridge", "Local boundary", "#9B87B5");
        var runtime = CreateFlowNode("03", "Runtime", "Target session", "#79A889");
        Grid.SetColumn(bridge, 2);
        Grid.SetColumn(runtime, 4);
        grid.Children.Add(editor);
        grid.Children.Add(CreateFlowArrow(1));
        grid.Children.Add(bridge);
        grid.Children.Add(CreateFlowArrow(3));
        grid.Children.Add(runtime);
        outer.Children.Add(grid);
        return CreateCard(outer, "#79A889", new Thickness(15, 13));
    }

    private static Border CreateFlowNode(string index, string title, string detail, string tone)
    {
        var stack = new StackPanel { Spacing = 4 };
        stack.Children.Add(new TextBlock { Text = index, FontSize = 8, Foreground = BrushFrom(tone) });
        stack.Children.Add(new TextBlock { Text = title, FontSize = 11, FontWeight = FontWeight.SemiBold, Foreground = Brushes.White });
        stack.Children.Add(new TextBlock { Text = detail, FontSize = 8.5, Foreground = BrushFrom("#74797D") });
        return new Border
        {
            Background = BrushFrom(WithAlpha(tone, "12")),
            BorderBrush = BrushFrom(WithAlpha(tone, "66")),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(9),
            Padding = new Thickness(11, 9),
            Child = stack
        };
    }

    private static Control CreateFlowArrow(int column)
    {
        var arrow = new TextBlock
        {
            Text = "→",
            FontSize = 15,
            Foreground = BrushFrom("#555B60"),
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center
        };
        Grid.SetColumn(arrow, column);
        return arrow;
    }

    private static Control CreateChecklistCard()
    {
        var stack = new StackPanel { Spacing = 0 };
        stack.Children.Add(CreateCardHeading("Setup review", "Four clear checkpoints"));
        stack.Children.Add(CreateChecklistRow("1", "Workspace location", "Scripts and local data folders", true));
        stack.Children.Add(CreateChecklistRow("2", "Editor defaults", "Language and startup behavior", true));
        stack.Children.Add(CreateChecklistRow("3", "Bridge overview", "Connection model and safety", false));
        stack.Children.Add(CreateChecklistRow("4", "Finish", "Review the proposed choices", false));
        return CreateCard(stack, "#B49B69", new Thickness(15, 13));
    }

    private static Control CreateChecklistRow(string index, string title, string detail, bool complete)
    {
        var grid = new Grid
        {
            ColumnDefinitions = new ColumnDefinitions("30,*,Auto"),
            MinHeight = 45
        };
        var circle = new Border
        {
            Width = 21,
            Height = 21,
            CornerRadius = new CornerRadius(11),
            Background = BrushFrom(complete ? "#253229" : "#202428"),
            BorderBrush = BrushFrom(complete ? "#5E866B" : "#3A3F43"),
            BorderThickness = new Thickness(1),
            VerticalAlignment = VerticalAlignment.Center,
            Child = new TextBlock
            {
                Text = complete ? "✓" : index,
                FontSize = 8.5,
                Foreground = BrushFrom(complete ? "#79A889" : "#858A8E"),
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center
            }
        };
        grid.Children.Add(circle);
        var copy = new StackPanel { Spacing = 1, VerticalAlignment = VerticalAlignment.Center };
        copy.Children.Add(new TextBlock { Text = title, FontSize = 10.5, Foreground = Brushes.White });
        copy.Children.Add(new TextBlock { Text = detail, FontSize = 8.5, Foreground = BrushFrom("#74797D") });
        Grid.SetColumn(copy, 1);
        grid.Children.Add(copy);
        var status = CreatePill(complete ? "Reviewed" : "Preview", complete ? "#79A889" : "#B49B69");
        status.VerticalAlignment = VerticalAlignment.Center;
        Grid.SetColumn(status, 2);
        grid.Children.Add(status);
        return new Border
        {
            BorderThickness = new Thickness(0, 1, 0, 0),
            BorderBrush = BrushFrom("#202428"),
            Child = grid
        };
    }

    private static Control CreateFauxAction(string title, string detail, string tone)
    {
        var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };
        var copy = new StackPanel { Spacing = 2 };
        copy.Children.Add(new TextBlock { Text = title, FontSize = 11, FontWeight = FontWeight.SemiBold, Foreground = BrushFrom(tone) });
        copy.Children.Add(new TextBlock { Text = detail, FontSize = 8.5, Foreground = BrushFrom("#74797D") });
        grid.Children.Add(copy);
        var arrow = new TextBlock { Text = "→", FontSize = 16, Foreground = BrushFrom(tone), VerticalAlignment = VerticalAlignment.Center };
        Grid.SetColumn(arrow, 1);
        grid.Children.Add(arrow);
        return CreateCard(grid, tone, new Thickness(14, 10));
    }

    private static Control CreateFeatureToggleCard(string title, string detail, bool enabled)
    {
        var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };
        var copy = new StackPanel { Spacing = 3 };
        copy.Children.Add(new TextBlock { Text = title, FontSize = 13, FontWeight = FontWeight.SemiBold, Foreground = Brushes.White });
        copy.Children.Add(new TextBlock { Text = detail, FontSize = 9.5, Foreground = BrushFrom("#7A7F83"), TextWrapping = TextWrapping.Wrap });
        grid.Children.Add(copy);

        var toggleCanvas = new Canvas { Width = 38, Height = 20 };
        toggleCanvas.Children.Add(new Border
        {
            Width = 38,
            Height = 20,
            Background = BrushFrom(enabled ? "#355244" : "#292D31"),
            BorderBrush = BrushFrom(enabled ? "#638D72" : "#44494D"),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(10)
        });
        var knob = new Ellipse { Width = 14, Height = 14, Fill = BrushFrom(enabled ? "#DDE9E1" : "#858A8E") };
        Canvas.SetLeft(knob, enabled ? 21 : 3);
        Canvas.SetTop(knob, 3);
        toggleCanvas.Children.Add(knob);
        toggleCanvas.VerticalAlignment = VerticalAlignment.Center;
        Grid.SetColumn(toggleCanvas, 1);
        grid.Children.Add(toggleCanvas);
        return CreateCard(grid, enabled ? "#79A889" : "#44494D", new Thickness(16, 13));
    }

    private static Control CreateThemeGallery()
    {
        var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("*,10,*,10,*") };
        var midnight = CreateThemeCard("Orbit Midnight", "#0F1216", "#252A2E", "#FFFFFF", true);
        var graphite = CreateThemeCard("Graphite", "#17191C", "#30343A", "#C7D0D7", false);
        var nocturne = CreateThemeCard("Nocturne", "#11121A", "#25253B", "#C2B8EA", false);
        Grid.SetColumn(graphite, 2);
        Grid.SetColumn(nocturne, 4);
        grid.Children.Add(midnight);
        grid.Children.Add(graphite);
        grid.Children.Add(nocturne);
        return grid;
    }

    private static Border CreateThemeCard(string name, string surface, string panel, string accent, bool selected)
    {
        var preview = new Grid
        {
            Height = 76,
            Background = BrushFrom(surface),
            ColumnDefinitions = new ColumnDefinitions("22,*")
        };
        preview.Children.Add(new Border { Background = BrushFrom(panel) });
        var main = new StackPanel { Spacing = 5, Margin = new Thickness(8) };
        main.Children.Add(new Border { Height = 7, Width = 56, HorizontalAlignment = HorizontalAlignment.Left, CornerRadius = new CornerRadius(4), Background = BrushFrom(accent), Opacity = 0.75 });
        main.Children.Add(new Border { Height = 28, CornerRadius = new CornerRadius(5), Background = BrushFrom(panel) });
        main.Children.Add(new Border { Height = 6, Width = 72, HorizontalAlignment = HorizontalAlignment.Left, CornerRadius = new CornerRadius(3), Background = BrushFrom("#555B60") });
        Grid.SetColumn(main, 1);
        preview.Children.Add(main);

        var stack = new StackPanel { Spacing = 8 };
        stack.Children.Add(preview);
        var label = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };
        label.Children.Add(new TextBlock { Text = name, FontSize = 9.5, FontWeight = FontWeight.SemiBold, Foreground = Brushes.White });
        if (selected)
        {
            var check = CreatePill("SELECTED", "#79A889");
            Grid.SetColumn(check, 1);
            label.Children.Add(check);
        }
        stack.Children.Add(label);

        return new Border
        {
            Background = BrushFrom("#101317"),
            BorderBrush = BrushFrom(selected ? "#638D72" : "#292D31"),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(11),
            Padding = new Thickness(8),
            ClipToBounds = true,
            Child = stack
        };
    }

    private static Control CreateProfileCard()
    {
        var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("58,*,Auto") };
        var avatar = new Border
        {
            Width = 46,
            Height = 46,
            CornerRadius = new CornerRadius(14),
            Background = BrushFrom("#242A31"),
            BorderBrush = BrushFrom("#4D5862"),
            BorderThickness = new Thickness(1),
            Child = new TextBlock
            {
                Text = "OR",
                FontSize = 13,
                FontWeight = FontWeight.SemiBold,
                Foreground = Brushes.White,
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center
            }
        };
        grid.Children.Add(avatar);
        var copy = new StackPanel { Spacing = 3, VerticalAlignment = VerticalAlignment.Center };
        copy.Children.Add(new TextBlock { Text = "Orbit Preview", FontSize = 14, FontWeight = FontWeight.SemiBold, Foreground = Brushes.White });
        copy.Children.Add(new TextBlock { Text = "Local profile · no account connected", FontSize = 9.5, Foreground = BrushFrom("#7A7F83") });
        Grid.SetColumn(copy, 1);
        grid.Children.Add(copy);
        var pill = CreatePill("LOCAL FIRST", "#7699B8");
        pill.VerticalAlignment = VerticalAlignment.Center;
        Grid.SetColumn(pill, 2);
        grid.Children.Add(pill);
        return CreateCard(grid, "#7699B8", new Thickness(15));
    }

    private static Control CreateAboutHero()
    {
        var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };
        var copy = new StackPanel { Spacing = 5 };
        copy.Children.Add(new TextBlock { Text = "O  R  B  I  T", FontSize = 18, FontWeight = FontWeight.Light, Foreground = Brushes.White });
        copy.Children.Add(new TextBlock { Text = "Desktop interface preview", FontSize = 9.5, Foreground = BrushFrom("#7A7F83") });
        grid.Children.Add(copy);
        var version = CreatePill("VERSION 0.9.0", "#9B87B5");
        version.VerticalAlignment = VerticalAlignment.Center;
        Grid.SetColumn(version, 1);
        grid.Children.Add(version);
        return CreateCard(grid, "#9B87B5", new Thickness(17, 15));
    }

    private static string WithAlpha(string color, string alpha) =>
        color.Length == 7 ? $"#{alpha}{color[1..]}" : color;

    private enum SettingsTab
    {
        General,
        Global,
        Bridge,
        Setup,
        AutoOpen,
        UiSelect,
        Account,
        About
    }

    private sealed record SettingsTabVisuals(
        string DisplayName,
        Border Background,
        TextBlock TabText,
        TextBlock? SectionText);
}
