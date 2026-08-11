using Avalonia;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Platform.Storage;
using Avalonia.Threading;

namespace OrbitAvalonia;

public sealed partial class MainWindow
{
    private const string SetupPrototypeDisclaimer =
        "PROTOTYPE - SETUP UI IS VIBECODED UI UNTIL A MANUAL DESIGN IS MADE FOR PRE ALPHA";

    private static readonly string[] SetupPrototypeTitles =
    [
        "Welcome",
        "Autoexec Folder",
        "Auto Update",
        "All Set",
        "Select UI"
    ];

    private static readonly string[] SetupPrototypeSubtitles =
    [
        "A short preview of the setup experience Orbit is building.",
        "Choose where Orbit's bridge will start with your executor.",
        "Update preferences will be available after the setup prototype.",
        "Review the setup before choosing your interface.",
        "Choose the interface Orbit should open after setup."
    ];

    private Grid _setupPrototypeInterface = null!;
    private Border? _setupWindowChrome;
    private ContentControl _setupPrototypeContentHost = null!;
    private Canvas _setupProgressRail = null!;
    private Button _setupBackButton = null!;
    private Button _setupNextButton = null!;
    private TextBlock _setupStepStatusText = null!;
    private ScaleTransform _setupInterfaceScale = null!;
    private TranslateTransform _setupInterfaceTranslation = null!;
    private TranslateTransform _setupContentTranslation = null!;
    private readonly List<Border> _setupProgressCircles = [];
    private readonly List<TextBlock> _setupProgressNumbers = [];
    private readonly List<Border> _setupProgressLines = [];
    private CancellationTokenSource? _setupPrototypeAnimationCancellation;
    private int _setupPrototypeStep;
    private bool _setupPrototypeVisible;
    private bool _setupOpenedFromStartup;
    private string? _setupAutoexecPath;
    private TextBlock? _setupAutoexecPathText;
    private Border? _setupAutoexecSuccess;
    private TextBlock? _setupAutoexecStatusText;

    private void InitializeSetupPrototype()
    {
        _setupPrototypeInterface = this.FindControl<Grid>("SetupPrototypeInterface") ?? new Grid();
        _setupWindowChrome = this.FindControl<Border>("SetupWindowChrome") ?? new Border();
        _setupPrototypeContentHost = this.FindControl<ContentControl>("SetupPrototypeContentHost") ?? new ContentControl();
        _setupProgressRail = this.FindControl<Canvas>("SetupProgressRail") ?? new Canvas();
        _setupBackButton = this.FindControl<Button>("SetupBackButton") ?? new Button();
        _setupNextButton = this.FindControl<Button>("SetupNextButton") ?? new Button();
        _setupStepStatusText = this.FindControl<TextBlock>("SetupStepStatusText") ?? new TextBlock();

        var interfaceTransforms = _setupPrototypeInterface.RenderTransform as TransformGroup ?? new TransformGroup();
        _setupInterfaceScale = interfaceTransforms.Children.Count > 0 ? interfaceTransforms.Children[0] as ScaleTransform ?? new ScaleTransform() : new ScaleTransform();
        _setupInterfaceTranslation = interfaceTransforms.Children.Count > 1 ? interfaceTransforms.Children[1] as TranslateTransform ?? new TranslateTransform() : new TranslateTransform();

        _setupContentTranslation = new TranslateTransform();
        _setupPrototypeContentHost.RenderTransform = _setupContentTranslation;
        BuildSetupProgressRail();
        _setupAutoexecPath = OrbitPreferences.AutoexecPath;
        ApplySetupPrototypeStep(0);
        UpdateWindowChromeForState();
    }

    private void BuildSetupProgressRail()
    {
        _setupProgressRail.Children.Clear();
        _setupProgressCircles.Clear();
        _setupProgressNumbers.Clear();
        _setupProgressLines.Clear();

        var railWidth = _setupProgressRail.Width is > 0 and var width ? width : 380;
        var contentWidth = Math.Max(0, (SetupPrototypeTitles.Length - 1) * 50 + 30);
        var offset = Math.Max(0, (railWidth - contentWidth) / 2);

        for (var index = 0; index < SetupPrototypeTitles.Length; index++)
        {
            if (index > 0)
            {
                var line = new Border
                {
                    Width = 10,
                    Height = 1,
                    CornerRadius = new CornerRadius(0.5)
                };
                Canvas.SetLeft(line, offset + (index * 50) - 15);
                Canvas.SetTop(line, 14.5);
                _setupProgressRail.Children.Add(line);
                _setupProgressLines.Add(line);
            }

            var number = new TextBlock
            {
                Text = (index + 1).ToString(),
                FontFamily = new FontFamily("Cascadia Code"),
                FontSize = 12,
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center,
                TextAlignment = TextAlignment.Center
            };
            var circle = new Border
            {
                Width = 30,
                Height = 30,
                CornerRadius = new CornerRadius(15),
                BorderThickness = new Thickness(1),
                Child = number
            };
            Canvas.SetLeft(circle, offset + (index * 50));
            Canvas.SetTop(circle, 0);
            _setupProgressRail.Children.Add(circle);
            _setupProgressCircles.Add(circle);
            _setupProgressNumbers.Add(number);
        }
    }

    private async Task ShowSetupPrototypeAsync(bool fromStartup = false)
    {
        _setupPrototypeAnimationCancellation?.Cancel();
        _setupPrototypeAnimationCancellation?.Dispose();
        _setupPrototypeAnimationCancellation = new CancellationTokenSource();
        var cancellationToken = _setupPrototypeAnimationCancellation.Token;

        HideMonaco();
        _setupOpenedFromStartup = fromStartup;
        _setupPrototypeVisible = true;
        ApplySetupPrototypeStep(0);
        _setupPrototypeInterface.IsVisible = true;
        _setupPrototypeInterface.IsHitTestVisible = true;
        _setupPrototypeInterface.Opacity = 0;
        _setupInterfaceScale.ScaleX = 0.988;
        _setupInterfaceScale.ScaleY = 0.988;
        _setupInterfaceTranslation.X = 24;

        try
        {
            if (SystemAnimationsEnabled())
            {
                await AnimateAsync(
                    TimeSpan.FromMilliseconds(280),
                    progress =>
                    {
                        _setupPrototypeInterface.Opacity = progress;
                        _setupInterfaceScale.ScaleX = Lerp(0.988, 1, progress);
                        _setupInterfaceScale.ScaleY = Lerp(0.988, 1, progress);
                        _setupInterfaceTranslation.X = Lerp(24, 0, progress);
                    },
                    CubicEaseOut,
                    cancellationToken);
            }

            _setupPrototypeInterface.Opacity = 1;
            _setupInterfaceScale.ScaleX = 1;
            _setupInterfaceScale.ScaleY = 1;
            _setupInterfaceTranslation.X = 0;
        }
        catch (OperationCanceledException)
        {
            // A setup page transition or dismissal replaced this entrance.
        }
    }

    private async Task HideSetupPrototypeAsync()
    {
        if (!_setupPrototypeVisible)
        {
            return;
        }

        _setupPrototypeAnimationCancellation?.Cancel();
        _setupPrototypeAnimationCancellation?.Dispose();
        _setupPrototypeAnimationCancellation = new CancellationTokenSource();
        var cancellationToken = _setupPrototypeAnimationCancellation.Token;
        _setupPrototypeInterface.IsHitTestVisible = false;

        try
        {
            if (SystemAnimationsEnabled())
            {
                var startOpacity = _setupPrototypeInterface.Opacity;
                await AnimateAsync(
                    TimeSpan.FromMilliseconds(230),
                    progress =>
                    {
                        _setupPrototypeInterface.Opacity = Lerp(startOpacity, 0, progress);
                        _setupInterfaceScale.ScaleX = Lerp(1, 0.992, progress);
                        _setupInterfaceScale.ScaleY = Lerp(1, 0.992, progress);
                        _setupInterfaceTranslation.X = Lerp(0, -20, progress);
                    },
                    CubicEaseInOut,
                    cancellationToken);
            }
        }
        catch (OperationCanceledException)
        {
            // The window is closing or the setup shell was reopened.
        }

        _setupPrototypeVisible = false;
        _setupPrototypeInterface.IsVisible = false;
        _setupPrototypeInterface.Opacity = 0;
        _setupInterfaceScale.ScaleX = 1;
        _setupInterfaceScale.ScaleY = 1;
        _setupInterfaceTranslation.X = 0;
        UpdateMonacoVisibility();
    }

    private async void SetupBack_Click(object? sender, RoutedEventArgs e)
    {
        if (_setupPrototypeStep > 0)
        {
            await NavigateSetupPrototypeAsync(_setupPrototypeStep - 1);
        }
    }

    private async void SetupNext_Click(object? sender, RoutedEventArgs e)
    {
        if (_setupPrototypeStep < SetupPrototypeTitles.Length - 1)
        {
            await NavigateSetupPrototypeAsync(_setupPrototypeStep + 1);
            return;
        }

        OrbitPreferences.SetSetupCompleted(true);
        await HideSetupPrototypeAsync();
        if (_setupOpenedFromStartup)
        {
            _setupOpenedFromStartup = false;
            ShowOrbitPrototypeDisclaimer();
        }
    }

    private async Task NavigateSetupPrototypeAsync(int targetStep)
    {
        targetStep = Math.Clamp(targetStep, 0, SetupPrototypeTitles.Length - 1);
        if (targetStep == _setupPrototypeStep)
        {
            return;
        }

        _setupPrototypeAnimationCancellation?.Cancel();
        _setupPrototypeAnimationCancellation?.Dispose();
        _setupPrototypeAnimationCancellation = new CancellationTokenSource();
        var cancellationToken = _setupPrototypeAnimationCancellation.Token;
        var direction = targetStep > _setupPrototypeStep ? 1d : -1d;
        _setupBackButton.IsEnabled = false;
        _setupNextButton.IsEnabled = false;

        try
        {
            if (SystemAnimationsEnabled())
            {
                var startOpacity = _setupPrototypeContentHost.Opacity;
                await AnimateAsync(
                    TimeSpan.FromMilliseconds(135),
                    progress =>
                    {
                        _setupPrototypeContentHost.Opacity = Lerp(startOpacity, 0, progress);
                        _setupContentTranslation.X = Lerp(0, -24 * direction, progress);
                    },
                    CubicEaseIn,
                    cancellationToken);
            }

            ApplySetupPrototypeStep(targetStep);
            _setupPrototypeContentHost.Opacity = 0;
            _setupContentTranslation.X = 30 * direction;

            if (SystemAnimationsEnabled())
            {
                await AnimateAsync(
                    TimeSpan.FromMilliseconds(220),
                    progress =>
                    {
                        _setupPrototypeContentHost.Opacity = progress;
                        _setupContentTranslation.X = Lerp(30 * direction, 0, progress);
                    },
                    CubicEaseOut,
                    cancellationToken);
            }

            _setupPrototypeContentHost.Opacity = 1;
            _setupContentTranslation.X = 0;
        }
        catch (OperationCanceledException)
        {
            // A newer navigation request replaced this page transition.
        }
        finally
        {
            if (_setupPrototypeVisible)
            {
                _setupBackButton.IsEnabled = true;
                _setupNextButton.IsEnabled = true;
            }
        }
    }

    private void ApplySetupPrototypeStep(int step)
    {
        _setupPrototypeStep = Math.Clamp(step, 0, SetupPrototypeTitles.Length - 1);
        _setupPrototypeContentHost.Content = BuildSetupPrototypePage(_setupPrototypeStep);
        _setupPrototypeContentHost.Opacity = 1;
        _setupContentTranslation.X = 0;
        _setupBackButton.IsVisible = _setupPrototypeStep > 0;
        _setupNextButton.Content = _setupPrototypeStep == SetupPrototypeTitles.Length - 1
            ? "Exit Setup"
            : _setupPrototypeStep == SetupPrototypeTitles.Length - 2
                ? "Select UI"
                : "Next";
        _setupStepStatusText.Text = $"STEP {_setupPrototypeStep + 1} OF {SetupPrototypeTitles.Length}";
        UpdateSetupProgressVisuals();
    }

    private void UpdateSetupProgressVisuals()
    {
        for (var index = 0; index < _setupProgressCircles.Count; index++)
        {
            var active = index == _setupPrototypeStep;
            var completed = index < _setupPrototypeStep;
            _setupProgressCircles[index].BorderBrush = new SolidColorBrush(Color.Parse(
                active ? "#FFFFFF" : completed ? "#667B9E" : "#2E3A51"));
            _setupProgressCircles[index].Background = new SolidColorBrush(Color.Parse(
                active ? "#132037" : completed ? "#0F1B2E" : "#0A101D"));
            _setupProgressNumbers[index].Foreground = new SolidColorBrush(Color.Parse(
                active ? "#FFFFFF" : completed ? "#B4C1D3" : "#66738B"));
        }

        for (var index = 0; index < _setupProgressLines.Count; index++)
        {
            _setupProgressLines[index].Background = new SolidColorBrush(Color.Parse(
                index < _setupPrototypeStep ? "#566F94" : "#273244"));
        }
    }

    private Control BuildSetupPrototypePage(int step) => step switch
    {
        0 => BuildSetupWelcomePage(),
        1 => BuildSetupAutoexecPage(),
        2 => BuildSetupUpdatePage(),
        3 => BuildSetupFinishPage(),
        4 => BuildSetupUiSelectPage(),
        _ => BuildSetupWelcomePage()
    };

    private Control CreateSetupPageShell(int step, Control body)
    {
        var root = new Grid
        {
            Width = 866,
            Height = 394,
            RowDefinitions = new RowDefinitions("Auto,*")
        };
        var heading = new StackPanel { Spacing = 4 };
        heading.Children.Add(new TextBlock
        {
            Text = SetupPrototypeDisclaimer,
            FontFamily = new FontFamily("Cascadia Code"),
            FontSize = 8.5,
            Foreground = BrushFrom("#C4A76A"),
            TextWrapping = TextWrapping.NoWrap,
            Margin = new Thickness(0, 0, 0, 2)
        });
        heading.Children.Add(new TextBlock
        {
            Text = $"ORBIT SETUP  /  {step + 1:00}",
            FontFamily = new FontFamily("Cascadia Code"),
            FontSize = 9.5,
            Foreground = BrushFrom("#62676B")
        });
        heading.Children.Add(new TextBlock
        {
            Text = SetupPrototypeTitles[step],
            FontSize = 24,
            FontWeight = FontWeight.SemiBold,
            Foreground = Brushes.White
        });
        heading.Children.Add(new TextBlock
        {
            Text = SetupPrototypeSubtitles[step],
            FontSize = 11,
            Foreground = BrushFrom("#73787D")
        });
        root.Children.Add(heading);

        body.Margin = new Thickness(0, 22, 0, 0);
        Grid.SetRow(body, 1);
        root.Children.Add(body);
        return root;
    }

    private Control BuildSetupWelcomePage()
    {
        var body = new Grid { RowDefinitions = new RowDefinitions("105,14,*") };
        var heroContent = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };
        var heroCopy = new StackPanel { Spacing = 7, VerticalAlignment = VerticalAlignment.Center };
        heroCopy.Children.Add(SetupText("Build your Orbit workspace", 16, Brushes.White, FontWeight.SemiBold));
        heroCopy.Children.Add(SetupText(
            "This preview walks through the future first-run flow without changing files or preferences.",
            10.5,
            BrushFrom("#858A8F")));
        heroContent.Children.Add(heroCopy);
        var badge = SetupPill("5 STEPS", accent: true);
        badge.VerticalAlignment = VerticalAlignment.Center;
        Grid.SetColumn(badge, 1);
        heroContent.Children.Add(badge);
        body.Children.Add(SetupCard(heroContent, new Thickness(22, 17)));

        var overview = new Grid
        {
            ColumnDefinitions = new ColumnDefinitions("*,10,*,10,*,10,*,10,*"),
            RowDefinitions = new RowDefinitions("*")
        };
        var hints = new[] { "Start", "Folder", "Prototype", "Review", "Interface" };
        for (var index = 0; index < SetupPrototypeTitles.Length; index++)
        {
            var tileCopy = new StackPanel { Spacing = 4 };
            tileCopy.Children.Add(SetupText($"{index + 1:00}", 9.5, BrushFrom("#62676B"), FontWeight.SemiBold));
            tileCopy.Children.Add(SetupText(SetupPrototypeTitles[index], 11, Brushes.White, FontWeight.Medium));
            tileCopy.Children.Add(SetupText(hints[index], 9, BrushFrom("#73787D")));
            var tile = SetupCard(tileCopy, new Thickness(13, 10), 18);
            Grid.SetColumn(tile, index * 2);
            overview.Children.Add(tile);
        }
        Grid.SetRow(overview, 2);
        body.Children.Add(overview);
        return CreateSetupPageShell(0, body);
    }

    private Control BuildSetupAutoexecPage()
    {
        var body = new Grid { ColumnDefinitions = new ColumnDefinitions("*,18,278") };
        var selector = new StackPanel { Spacing = 14 };
        selector.Children.Add(SetupText("Executor autoexec folder", 13, Brushes.White, FontWeight.Medium));
        selector.Children.Add(SetupText(
            "Choose the folder your executor uses for autoexec scripts. Orbit will send its bridge there immediately.",
            10.5,
            BrushFrom("#858A8F")));
        selector.Children.Add(SetupField(
            _setupAutoexecPath ?? "No folder selected",
            "PATH PREVIEW",
            out _setupAutoexecPathText));

        var chooseButton = new Button
        {
            Classes = { "setup-action", "setup-secondary" },
            Content = "Choose folder",
            HorizontalAlignment = HorizontalAlignment.Stretch
        };
        chooseButton.Click += SetupChooseAutoexecFolder_Click;
        selector.Children.Add(chooseButton);

        _setupAutoexecStatusText = SetupText(
            _setupAutoexecPath is null ? string.Empty : "Successfully Sent Bridge Script",
            10.5,
            BrushFrom("#8FE2B0"),
            FontWeight.Medium,
            TextAlignment.Center);
        _setupAutoexecSuccess = new Border
        {
            Height = 34,
            CornerRadius = new CornerRadius(17),
            Background = BrushFrom("#132B25"),
            BorderBrush = BrushFrom("#356B57"),
            BorderThickness = new Thickness(1),
            IsVisible = _setupAutoexecPath is not null,
            Child = _setupAutoexecStatusText
        };
        selector.Children.Add(_setupAutoexecSuccess);
        body.Children.Add(SetupCard(selector, new Thickness(20, 18)));

        var note = new StackPanel { Spacing = 12 };
        note.Children.Add(SetupPill("AUTOMATIC", accent: true));
        note.Children.Add(SetupText("Bridge delivery", 14, Brushes.White, FontWeight.SemiBold));
        note.Children.Add(SetupText(
            "The bridge runs inside your chosen executor and announces the connection to Orbit.",
            10.5,
            BrushFrom("#858A8F")));
        note.Children.Add(SetupDivider());
        note.Children.Add(SetupText("Only the bundled bridge file is copied.", 9.5, BrushFrom("#62676B")));
        var noteCard = SetupCard(note, new Thickness(19, 18));
        Grid.SetColumn(noteCard, 2);
        body.Children.Add(noteCard);
        return CreateSetupPageShell(1, body);
    }

    private async void SetupChooseAutoexecFolder_Click(object? sender, RoutedEventArgs e)
    {
        var folders = await StorageProvider.OpenFolderPickerAsync(new FolderPickerOpenOptions
        {
            Title = "Choose executor autoexec folder",
            AllowMultiple = false
        });
        var folder = folders.FirstOrDefault();
        if (folder is null)
        {
            return;
        }

        var path = folder.Path.LocalPath;
        if (string.IsNullOrWhiteSpace(path))
        {
            return;
        }

        try
        {
            var source = Path.Combine(_editorWorkspace.ScriptsDirectory, "Orion Bridge.lua");
            var destination = Path.Combine(path, "Orion Bridge.lua");
            if (!string.Equals(Path.GetFullPath(source), Path.GetFullPath(destination), StringComparison.OrdinalIgnoreCase))
            {
                File.Copy(source, destination, overwrite: true);
            }

            _setupAutoexecPath = path;
            OrbitPreferences.SetAutoexecPath(path);
            if (_setupAutoexecPathText is not null)
            {
                _setupAutoexecPathText.Text = path;
            }
            if (_setupAutoexecStatusText is not null)
            {
                _setupAutoexecStatusText.Text = "Successfully Sent Bridge Script";
                _setupAutoexecStatusText.Foreground = BrushFrom("#8FE2B0");
            }
            if (_setupAutoexecSuccess is not null)
            {
                _setupAutoexecSuccess.IsVisible = true;
            }
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            if (_setupAutoexecStatusText is not null)
            {
                _setupAutoexecStatusText.Text = "Could not send bridge script";
                _setupAutoexecStatusText.Foreground = BrushFrom("#E8A2A2");
            }
            if (_setupAutoexecSuccess is not null)
            {
                _setupAutoexecSuccess.IsVisible = true;
            }
        }
    }

    private Control BuildSetupBridgePage()
    {
        var body = new Grid { RowDefinitions = new RowDefinitions("150,16,*") };
        var fileGrid = new Grid { ColumnDefinitions = new ColumnDefinitions("Auto,18,*,Auto") };
        var fileIcon = new Border
        {
            Width = 46,
            Height = 46,
            CornerRadius = new CornerRadius(14),
            Background = BrushFrom("#202428"),
            BorderBrush = BrushFrom("#3A4148"),
            BorderThickness = new Thickness(1),
            Child = SetupText("{ }", 14, Brushes.White, FontWeight.SemiBold, TextAlignment.Center)
        };
        fileIcon.Child.VerticalAlignment = VerticalAlignment.Center;
        fileGrid.Children.Add(fileIcon);
        var fileCopy = new StackPanel { Spacing = 5, VerticalAlignment = VerticalAlignment.Center };
        fileCopy.Children.Add(SetupText("Orion Bridge.lua", 14, Brushes.White, FontWeight.SemiBold));
        fileCopy.Children.Add(SetupText("Bundled with every Orbit build", 10, BrushFrom("#858A8F")));
        Grid.SetColumn(fileCopy, 2);
        fileGrid.Children.Add(fileCopy);
        var copyVisual = SetupVisualAction("Copy bridge", "PROTOTYPE");
        copyVisual.VerticalAlignment = VerticalAlignment.Center;
        Grid.SetColumn(copyVisual, 3);
        fileGrid.Children.Add(copyVisual);
        body.Children.Add(SetupCard(fileGrid, new Thickness(20, 18)));

        var flow = new Grid { ColumnDefinitions = new ColumnDefinitions("*,28,*,28,*") };
        var labels = new[] { ("01", "Orion"), ("02", "Orion Bridge"), ("03", "Executor") };
        for (var index = 0; index < labels.Length; index++)
        {
            var item = new StackPanel { Spacing = 7, HorizontalAlignment = HorizontalAlignment.Center };
            item.Children.Add(SetupPill(labels[index].Item1, accent: index == 1));
            item.Children.Add(SetupText(labels[index].Item2, 11, Brushes.White, FontWeight.Medium, TextAlignment.Center));
            var card = SetupCard(item, new Thickness(14, 14), 18);
            Grid.SetColumn(card, index * 2);
            flow.Children.Add(card);
            if (index < 2)
            {
                var arrow = SetupText("→", 15, BrushFrom("#62676B"), FontWeight.Normal, TextAlignment.Center);
                arrow.VerticalAlignment = VerticalAlignment.Center;
                Grid.SetColumn(arrow, (index * 2) + 1);
                flow.Children.Add(arrow);
            }
        }
        Grid.SetRow(flow, 2);
        body.Children.Add(flow);
        return CreateSetupPageShell(2, body);
    }

    private Control BuildSetupAutoOpenPage()
    {
        var body = new Grid { ColumnDefinitions = new ColumnDefinitions("*,18,278") };
        var controlStack = new StackPanel { Spacing = 15 };
        controlStack.Children.Add(SetupSettingRow(
            "Launch executor with Orbit",
            "Start the selected executable when Orbit opens.",
            SetupToggleVisual(false)));
        controlStack.Children.Add(SetupField("No executor selected", "EXECUTABLE"));
        controlStack.Children.Add(SetupVisualAction("Select executor exe", "PROTOTYPE"));
        body.Children.Add(SetupCard(controlStack, new Thickness(20, 17)));

        var note = new StackPanel { Spacing = 12 };
        note.Children.Add(SetupPill("OPTIONAL"));
        note.Children.Add(SetupText("Keep your current routine", 14, Brushes.White, FontWeight.SemiBold));
        note.Children.Add(SetupText(
            "Skip this if you prefer to open and attach your executor manually.",
            10.5,
            BrushFrom("#858A8F")));
        note.Children.Add(SetupDivider());
        note.Children.Add(SetupText("Nothing launches during this preview.", 9.5, BrushFrom("#62676B")));
        var noteCard = SetupCard(note, new Thickness(19, 18));
        Grid.SetColumn(noteCard, 2);
        body.Children.Add(noteCard);
        return CreateSetupPageShell(3, body);
    }

    private Control BuildSetupPluginPage()
    {
        var body = new Grid { ColumnDefinitions = new ColumnDefinitions("*,18,278") };
        var plugin = new StackPanel { Spacing = 14 };
        plugin.Children.Add(SetupText("Plugin pack", 13, Brushes.White, FontWeight.Medium));
        plugin.Children.Add(SetupText(
            "Import an Orbit-compatible plugin pack to extend the shell after setup.",
            10.5,
            BrushFrom("#858A8F")));
        plugin.Children.Add(SetupField("No plugin selected", "PLUGIN"));
        plugin.Children.Add(SetupVisualAction("Choose plugin", "PROTOTYPE"));
        body.Children.Add(SetupCard(plugin, new Thickness(20, 18)));

        var note = new StackPanel { Spacing = 12 };
        note.Children.Add(SetupPill("OPTIONAL"));
        note.Children.Add(SetupText("Extend later", 14, Brushes.White, FontWeight.SemiBold));
        note.Children.Add(SetupText(
            "The Plugins page will become the permanent home for importing and managing extensions.",
            10.5,
            BrushFrom("#858A8F")));
        note.Children.Add(SetupDivider());
        note.Children.Add(SetupText("Plugin loading remains disabled here.", 9.5, BrushFrom("#62676B")));
        var noteCard = SetupCard(note, new Thickness(19, 18));
        Grid.SetColumn(noteCard, 2);
        body.Children.Add(noteCard);
        return CreateSetupPageShell(4, body);
    }

    private Control BuildSetupUpdatePage()
    {
        var body = new Grid();
        body.Children.Add(new TextBlock
        {
            Text = "Prototype - Not Available",
            FontSize = 15,
            FontWeight = FontWeight.Medium,
            Foreground = BrushFrom("#858A8F"),
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
            TextAlignment = TextAlignment.Center
        });
        return CreateSetupPageShell(2, body);
    }

    private Control BuildSetupFinishPage()
    {
        var body = new Grid { ColumnDefinitions = new ColumnDefinitions("270,18,*") };
        var complete = new StackPanel
        {
            Spacing = 12,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center
        };
        complete.Children.Add(new Border
        {
            Width = 54,
            Height = 54,
            CornerRadius = new CornerRadius(27),
            BorderBrush = new SolidColorBrush(Color.Parse("#597095")),
            BorderThickness = new Thickness(1),
            Background = new SolidColorBrush(Color.Parse("#111E34")),
            Child = SetupText("✓", 22, Brushes.White, FontWeight.SemiBold, TextAlignment.Center)
        });
        complete.Children.Add(SetupText("Ready for UI selection", 14, Brushes.White, FontWeight.SemiBold, TextAlignment.Center));
        complete.Children.Add(SetupText("Prototype review complete", 9.5, BrushFrom("#73787D"), FontWeight.Normal, TextAlignment.Center));
        body.Children.Add(SetupCard(complete, new Thickness(18)));

        var summary = new StackPanel { Spacing = 0 };
        summary.Children.Add(SetupSummaryRow("Autoexec folder", _setupAutoexecPath is null ? "Not selected" : "Bridge sent"));
        summary.Children.Add(SetupDivider());
        summary.Children.Add(SetupSummaryRow("Auto update", "Prototype"));
        var summaryCard = SetupCard(summary, new Thickness(20, 12));
        Grid.SetColumn(summaryCard, 2);
        body.Children.Add(summaryCard);
        return CreateSetupPageShell(3, body);
    }

    private Control BuildSetupUiSelectPage()
    {
        var body = new Grid { ColumnDefinitions = new ColumnDefinitions("*,18,260") };
        var orbitChoice = new Grid { ColumnDefinitions = new ColumnDefinitions("Auto,18,*,Auto") };
        orbitChoice.Children.Add(new Border
        {
            Width = 54,
            Height = 54,
            CornerRadius = new CornerRadius(16),
            BorderBrush = new SolidColorBrush(Color.Parse("#576F95")),
            BorderThickness = new Thickness(1),
            Background = new SolidColorBrush(Color.Parse("#111E34")),
            Child = SetupText("O", 20, Brushes.White, FontWeight.SemiBold, TextAlignment.Center)
        });
        var orbitCopy = new StackPanel { Spacing = 5, VerticalAlignment = VerticalAlignment.Center };
        orbitCopy.Children.Add(SetupText("Orbit", 16, Brushes.White, FontWeight.SemiBold));
        orbitCopy.Children.Add(SetupText("Native Avalonia interface", 10, BrushFrom("#858A8F")));
        orbitCopy.Children.Add(SetupText("Midnight Navy", 9.5, BrushFrom("#62676B")));
        Grid.SetColumn(orbitCopy, 2);
        orbitChoice.Children.Add(orbitCopy);
        var selected = SetupPill("SELECTED", accent: true);
        selected.VerticalAlignment = VerticalAlignment.Center;
        Grid.SetColumn(selected, 3);
        orbitChoice.Children.Add(selected);
        body.Children.Add(SetupCard(orbitChoice, new Thickness(20, 20)));

        var note = new StackPanel { Spacing = 12 };
        note.Children.Add(SetupPill("PROTOTYPE"));
        note.Children.Add(SetupText("One available interface", 14, Brushes.White, FontWeight.SemiBold));
        note.Children.Add(SetupText(
            "Setup can only return to Orbit for now. More interface choices will be added after the flow is functional.",
            10.5,
            BrushFrom("#858A8F")));
        note.Children.Add(SetupDivider());
        note.Children.Add(SetupText("Exit Setup returns to the existing Orbit settings page.", 9.5, BrushFrom("#62676B")));
        var noteCard = SetupCard(note, new Thickness(19, 18));
        Grid.SetColumn(noteCard, 2);
        body.Children.Add(noteCard);
        return CreateSetupPageShell(4, body);
    }

    private static Border SetupCard(Control child, Thickness padding, double radius = 18) => new()
    {
        Background = BrushFrom("#25282A"),
        BorderBrush = BrushFrom("#34393E"),
        BorderThickness = new Thickness(1),
        CornerRadius = new CornerRadius(radius),
        Padding = padding,
        ClipToBounds = true,
        Child = child
    };

    private static TextBlock SetupText(
        string text,
        double size,
        IBrush foreground,
        FontWeight? weight = null,
        TextAlignment alignment = TextAlignment.Left) => new()
    {
        Text = text,
        FontSize = size,
        FontWeight = weight ?? FontWeight.Normal,
        Foreground = foreground,
        TextAlignment = alignment,
        TextWrapping = TextWrapping.Wrap,
        VerticalAlignment = VerticalAlignment.Center
    };

    private static Border SetupPill(string text, bool accent = false) => new()
    {
        HorizontalAlignment = HorizontalAlignment.Left,
        CornerRadius = new CornerRadius(10),
        BorderThickness = new Thickness(1),
        BorderBrush = new SolidColorBrush(Color.Parse(accent ? "#4B6288" : "#303C51")),
        Background = new SolidColorBrush(Color.Parse(accent ? "#112037" : "#0B121F")),
        Padding = new Thickness(9, 4),
        Child = SetupText(
            text,
            8.5,
            new SolidColorBrush(Color.Parse(accent ? "#B2C0D4" : "#727F93")),
            FontWeight.SemiBold,
            TextAlignment.Center)
    };

    private static Border SetupField(string value, string label) => SetupField(value, label, out _);

    private static Border SetupField(string value, string label, out TextBlock valueText)
    {
        var copy = new StackPanel { Spacing = 5 };
        copy.Children.Add(SetupText(label, 8.5, BrushFrom("#62676B"), FontWeight.SemiBold));
        valueText = SetupText(value, 10.5, BrushFrom("#AEB4B9"));
        copy.Children.Add(valueText);
        return new Border
        {
            Background = BrushFrom("#0D1014"),
            BorderBrush = BrushFrom("#34393E"),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(18),
            Padding = new Thickness(13, 10),
            Child = copy
        };
    }

    private static Border SetupVisualAction(string label, string status)
    {
        var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };
        grid.Children.Add(SetupText(label, 10.5, BrushFrom("#AEB4B9"), FontWeight.Medium));
        var statusPill = SetupPill(status);
        Grid.SetColumn(statusPill, 1);
        grid.Children.Add(statusPill);
        return new Border
        {
            Height = 42,
            Background = BrushFrom("#202428"),
            BorderBrush = BrushFrom("#34393E"),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(18),
            Padding = new Thickness(14, 0),
            Opacity = 0.72,
            Child = grid
        };
    }

    private static Border SetupDivider() => new()
    {
        Height = 1,
        Background = BrushFrom("#303235"),
        HorizontalAlignment = HorizontalAlignment.Stretch
    };

    private static Grid SetupSettingRow(string title, string detail, Control trailing)
    {
        var row = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };
        var copy = new StackPanel { Spacing = 4 };
        copy.Children.Add(SetupText(title, 12, Brushes.White, FontWeight.Medium));
        copy.Children.Add(SetupText(detail, 9.5, BrushFrom("#73787D")));
        row.Children.Add(copy);
        trailing.VerticalAlignment = VerticalAlignment.Center;
        Grid.SetColumn(trailing, 1);
        row.Children.Add(trailing);
        return row;
    }

    private static Border SetupToggleVisual(bool enabled)
    {
        var knob = new Border
        {
            Width = 20,
            Height = 20,
            CornerRadius = new CornerRadius(10),
            Background = new SolidColorBrush(Color.Parse(enabled ? "#D1D6DE" : "#3D4B5F")),
            HorizontalAlignment = enabled ? HorizontalAlignment.Right : HorizontalAlignment.Left,
            Margin = new Thickness(3)
        };
        return new Border
        {
            Width = 48,
            Height = 26,
            CornerRadius = new CornerRadius(13),
            BorderBrush = new SolidColorBrush(Color.Parse("#344359")),
            BorderThickness = new Thickness(1),
            Background = new SolidColorBrush(Color.Parse(enabled ? "#162B4C" : "#0B121F")),
            Child = knob
        };
    }

    private static Grid SetupSummaryRow(string title, string value)
    {
        var row = new Grid
        {
            Height = 42,
            ColumnDefinitions = new ColumnDefinitions("*,Auto")
        };
        row.Children.Add(SetupText(title, 10.5, BrushFrom("#73787D")));
        var valueText = SetupText(value, 10.5, BrushFrom("#AEB4B9"), FontWeight.Medium);
        Grid.SetColumn(valueText, 1);
        row.Children.Add(valueText);
        return row;
    }
}
