using Avalonia;
using Avalonia.Animation;
using Avalonia.Animation.Easings;
using Avalonia.Controls;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Controls.Primitives;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.Media;
using Avalonia.Media.Imaging;
using Avalonia.Platform;
using Avalonia.Platform.Storage;
using Avalonia.Threading;
using System.Text.Json;
using HAlign = Avalonia.Layout.HorizontalAlignment;
using StackOrientation = Avalonia.Layout.Orientation;
using VAlign = Avalonia.Layout.VerticalAlignment;
using ShapePath = Avalonia.Controls.Shapes.Path;

namespace OrbitAvalonia;

internal enum SynapseFrontendKind
{
    Blue,
    Classic2017,
    SynapseX,
    V3
}

/// <summary>
/// Native, frontend-only preservation of the four completed Synapse shells.
/// Injection, attach, account and update backends remain intentionally absent.
/// The shared native Orion Bridge queue is available to the execute controls,
/// while local editor state and script discovery stay shared with Orbit.
/// </summary>
internal sealed partial class SynapseFrontendWindow : Window
{
    private sealed record NativeGist(string Title, string RawUrl);

    private sealed record ShellSpec(
        double Width,
        double Height,
        double TitleHeight,
        string WindowBg,
        string PanelBg,
        string EditorBg,
        string TabBg,
        string ActiveTabBg,
        string Text,
        double CornerRadius);

    private readonly SynapseFrontendKind _kind;
    private readonly ShellSpec _spec;
    private readonly Uri _monacoAddress;
    private readonly string _scriptsDirectory;
    private readonly EditorWorkspaceState _workspace;
    private readonly Action<EditorWorkspaceState> _returnToOrbit;
    private readonly NativeWebView _editor;
    private readonly List<Border> _v3Underlines = [];
    private readonly List<Control> _v3NavIcons = [];
    private readonly List<Button> _blueNavButtons = [];
    private readonly List<Control> _blueNavIcons = [];
    private readonly List<Control> _bluePages = [];
    private readonly List<(Button Button, Control Icon)> _bridgeActionButtons = [];
    private int _blueActivePage;
    private StackPanel? _tabStrip;
    private Control? _editorPage;
    private Border? _shellChrome;
    private Grid? _bluePageHost;
    private readonly List<Control> _v3Pages = [];
    private int _v3ActivePage;
    private readonly List<NativeGist> _v3Gists = [];
    private readonly HashSet<string> _v3Bookmarks = new(StringComparer.OrdinalIgnoreCase);
    private StackPanel? _v3BookmarkContent;
    private StackPanel? _v3GistContent;
    private Border? _v3GistPopup;
    private TextBox? _v3GistUrlBox;
    private Button? _v3HubApiTab;
    private Button? _v3HubSynapseTab;
    private Control? _v3HubApiContent;
    private Control? _v3HubSynapseContent;
    private Border? _v3HubSearch;
    private Border? _blueTooltip;
    private TextBlock? _blueTooltipTitle;
    private TextBlock? _blueTooltipLine1;
    private TextBlock? _blueTooltipLine2;
    private SynapseXOptionsWindow? _synapseXOptionsWindow;
    private SynapseXScriptHubWindow? _synapseXScriptHubWindow;
    private SynapseOriginalSettingsWindow? _synapseOriginalSettingsWindow;
    private SynapseOriginalScriptHubWindow? _synapseOriginalScriptHubWindow;
    private bool _editorReady;
    private bool _sourceAssigned;
    private bool _returnStarted;
    private string _editorContent;

    public SynapseFrontendWindow() : this(
        SynapseFrontendKind.Blue,
        new Uri("http://127.0.0.1:1/index.html"),
        Path.Combine(AppContext.BaseDirectory, "Scripts"),
        CreateFallbackWorkspace(),
        static _ => { })
    {
    }

    internal SynapseFrontendWindow(
        SynapseFrontendKind kind,
        Uri monacoAddress,
        string scriptsDirectory,
        EditorWorkspaceState workspace,
        Action<EditorWorkspaceState> returnToOrbit)
    {
        _kind = kind;
        _spec = SpecFor(kind);
        _monacoAddress = monacoAddress;
        _scriptsDirectory = scriptsDirectory;
        if (kind == SynapseFrontendKind.V3)
        {
            LoadNativeGists();
            LoadV3Bookmarks();
        }
        _workspace = workspace.CloneDetached();
        if (_workspace.Tabs.Count == 0)
        {
            var first = new EditorTabState { Title = "Script", Extension = ".lua" };
            _workspace.Tabs.Add(first);
            _workspace.ActiveTabId = first.Id;
        }

        _returnToOrbit = returnToOrbit;
        _editorContent = ActiveTab().Content;
        _editor = new NativeWebView { Background = Brush(_spec.EditorBg) };
        _editor.WebMessageReceived += (_, args) => HandleEditorMessage(args.Body);

        var finalShell = BuildShell();
        if (kind == SynapseFrontendKind.Blue)
        {
            FontFamily = new FontFamily("avares://Avalonia.Fonts.Inter/Assets#Inter");
            _blueFinalShell = finalShell;
            Width = BlueInitializationWidth;
            Height = BlueInitializationHeight;
            MinWidth = BlueInitializationWidth;
            MinHeight = BlueInitializationHeight;
            MaxWidth = BlueInitializationWidth;
            MaxHeight = BlueInitializationHeight;
            CanResize = false;
        }
        else
        {
            Width = _spec.Width;
            Height = _spec.Height;
            MinWidth = _spec.Width;
            MinHeight = _spec.Height;
            MaxWidth = OrbitPreferences.ResizableEnabled ? double.PositiveInfinity : _spec.Width;
            MaxHeight = OrbitPreferences.ResizableEnabled ? double.PositiveInfinity : _spec.Height;
            CanResize = OrbitPreferences.ResizableEnabled;
        }
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        WindowDecorations = WindowDecorations.None;
        ExtendClientAreaToDecorationsHint = true;
        TransparencyLevelHint = [WindowTransparencyLevel.Transparent];
        Background = Brushes.Transparent;
        Topmost = OrbitPreferences.TopMostEnabled;
        Title = NameFor(kind);
        Content = kind == SynapseFrontendKind.Blue
            ? BuildBlueInitializationShell()
            : finalShell;

        UnifiedBridgeServer.Shared.ConnectionChanged += BridgeConnectionChanged;
        UnifiedBridgeServer.Shared.LogReceived += BridgeLogReceived;
        ApplyBridgeConnectionState(UnifiedBridgeServer.Shared.IsConnected);

        Opened += OnOpened;
        Closed += OnClosed;
    }

    internal void CloseForOrbit()
    {
        _returnStarted = true;
        CloseSynapseXCompanionWindows();
        Close();
    }

    private Control BuildShell()
    {
        var shellContent = _kind switch
        {
            SynapseFrontendKind.Blue => BuildBlueShell(),
            SynapseFrontendKind.Classic2017 => BuildClassicShell(),
            SynapseFrontendKind.SynapseX => BuildSynapseXShell(),
            _ => BuildV3Shell()
        };
        var chrome = new Border
        {
            Background = Brush(_spec.WindowBg),
            BorderBrush = _kind == SynapseFrontendKind.V3 ? Brush("#4B4D4C") : Brushes.Transparent,
            BorderThickness = _kind == SynapseFrontendKind.V3 ? new Thickness(1) : new Thickness(0),
            CornerRadius = new CornerRadius(_spec.CornerRadius),
            // Keep the chrome border itself un-clipped so its rounded edge
            // continues around the corners. The content gets its own mask
            // below, which prevents rectangular page backgrounds leaking out.
            ClipToBounds = false
        };
        chrome.Child = new Border
        {
            CornerRadius = new CornerRadius(Math.Max(0, _spec.CornerRadius - 1)),
            ClipToBounds = true,
            Child = shellContent
        };
        _shellChrome = chrome;
        if (_kind == SynapseFrontendKind.SynapseX)
        {
            chrome.Opacity = 0;
        }
        return chrome;
    }

    private Control BuildBlueShell()
    {
        var layout = new Grid { RowDefinitions = new RowDefinitions("55,*") };
        var titleBar = BuildTitleBar(
            CreateLogo("avares://Orion/Assets/Synapse/blue-wordmark.png", 175, 37, new Thickness(11, 0, 0, 0)),
            BlueTitleBrush(),
            55,
            compactControls: false,
            legacyTinyControls: true);
        titleBar.ZIndex = 3;
        layout.Children.Add(titleBar);

        var body = new Grid
        {
            RowDefinitions = new RowDefinitions("*"),
            ColumnDefinitions = new ColumnDefinitions("60,*")
        };
        Grid.SetRow(body, 1);

        var sidebar = new StackPanel
        {
            Background = Brush("#2F2F2F"),
            Spacing = 2,
            Effect = new DropShadowEffect
            {
                Color = Colors.Black,
                BlurRadius = 4.2,
                OffsetX = 4,
                Opacity = 0.06
            }
        };
        sidebar.ZIndex = 2;
        var navPaths = new[]
        {
            new[] { "M44.5 17L15 31.5L26 35.5M44.5 17L29.5 46.5L26 35.5M44.5 17L30.5 30.5L26 35.5" },
            new[] { "M46.5 28.5H13M13 45.5H46.5V23H27L22.5 19H13V45.5Z" },
            new[] { "M37.5 22L47 32L37 41.5M32 20L27.5 43.5", "M22.5 22L13 32L22 41.5" },
            new[] { "M45.5 31.5H15M45.5 18H15M45.5 45H15M35.5 41.5V47.5M19.5 28.5V34.5M41 15V21" },
            new[] { "M34.0014 33.4465L13.4039 50.208C13.0864 50.4664 12.7047 50.6337 12.2996 50.6923C11.8211 50.7614 11.333 50.6753 10.907 50.4467L10.6691 50.319C10.463 50.2085 10.2854 50.0517 10.1501 49.861C9.64208 49.1453 9.65462 48.1833 10.1811 47.481L10.4492 47.1233L27.6323 27.105M34.0014 33.4465L27.6323 27.105M34.0014 33.4465L40.1873 25.8398M27.6323 27.105L35.6564 21.5619M35.6564 21.5619C36.4554 24.3005 37.3311 25.3655 40.1873 25.8398M35.6564 21.5619C33.8484 15.3005 50.8418 12.062 51.8155 14.844M40.1873 25.8398C44.2367 26.2064 46.1409 24.7257 48.3212 18.7217C48.5474 18.0988 48.9123 17.5305 49.3987 17.0805L51.8155 14.844M51.8155 14.844C48.6794 16.4202 46.3462 16.6022 45.2033 19.7226" }
        };
        for (var index = 0; index < navPaths.Length; index++)
        {
            var pageIndex = index;
            var button = CreateBlueNavButton(navPaths[index], index == 0);
            button.Click += (_, _) => ShowBluePage(pageIndex);
            button.PointerEntered += (_, _) => ShowBlueTooltip(pageIndex);
            button.PointerExited += (_, _) => HideBlueTooltip(pageIndex);
            _blueNavButtons.Add(button);
            if (button.Content is Control icon)
            {
                _blueNavIcons.Add(icon);
            }
            sidebar.Children.Add(button);
        }
        body.Children.Add(sidebar);

        var pageHost = new Grid { Background = Brush("#222222") };
        _bluePageHost = pageHost;
        Grid.SetColumn(pageHost, 1);
        _editorPage = BuildBlueEditorPage();
        _bluePages.Add(_editorPage);
        _bluePages.Add(BuildBlueScriptHubPage());
        _bluePages.Add(BuildBlueConsolePage());
        _bluePages.Add(BuildBlueSettingsPage());
        _bluePages.Add(BuildBlueThemePrototypePage());
        for (var index = 0; index < _bluePages.Count; index++)
        {
            _bluePages[index].IsVisible = index == 0;
            pageHost.Children.Add(_bluePages[index]);
        }
        // The original Blue header shadow starts at the page column. Applying
        // it to the whole title bar incorrectly washes over the navigation
        // buttons and the sidebar rail.
        var pageOnlyHeaderShadow = new Border
        {
            Height = 1,
            Background = Brush("#323F89"),
            VerticalAlignment = VAlign.Top,
            IsHitTestVisible = false,
            Effect = new DropShadowEffect
            {
                Color = Colors.Black,
                BlurRadius = 15.9,
                OffsetY = 8,
                Opacity = 0.15
            }
        };
        pageOnlyHeaderShadow.ZIndex = 10;
        pageHost.Children.Add(pageOnlyHeaderShadow);
        body.Children.Add(pageHost);
        layout.Children.Add(body);

        var root = new Grid();
        root.Children.Add(layout);
        _blueTooltipPlacementRoot = root;
        var tooltipTitle = new TextBlock
        {
            Foreground = Brushes.White,
            FontSize = 13,
            FontWeight = FontWeight.Black,
            LineHeight = 16
        };
        var tooltipLine1 = new TextBlock
        {
            Foreground = Brushes.White,
            FontSize = 10,
            FontWeight = FontWeight.SemiBold,
            LineHeight = 14
        };
        var tooltipLine2 = new TextBlock
        {
            Foreground = Brushes.White,
            FontSize = 10,
            FontWeight = FontWeight.SemiBold,
            LineHeight = 14
        };
        _blueTooltipTitle = tooltipTitle;
        _blueTooltipLine1 = tooltipLine1;
        _blueTooltipLine2 = tooltipLine2;
        var tooltipCopy = new StackPanel
        {
            Spacing = 0,
            Children =
            {
                tooltipTitle,
                new StackPanel
                {
                    Margin = new Thickness(0, 2, 0, 0),
                    Spacing = 0,
                    Children = { tooltipLine1, tooltipLine2 }
                }
            }
        };
        _blueTooltipCopyHost = tooltipCopy;
        var tooltip = new Border
        {
            Width = 231,
            MinHeight = 56,
            Background = new LinearGradientBrush
            {
                StartPoint = new RelativePoint(0, 0, RelativeUnit.Relative),
                EndPoint = new RelativePoint(0, 1, RelativeUnit.Relative),
                GradientStops = new GradientStops { new(Color.Parse("#324DD8"), 0), new(Color.Parse("#3344A3"), 1) }
            },
            CornerRadius = new CornerRadius(3),
            Padding = new Thickness(6, 3, 6, 6),
            IsVisible = false,
            Opacity = 0,
            IsHitTestVisible = false,
            Child = tooltipCopy
        };
        _blueTooltip = tooltip;
        _blueTooltipDimmer = new Border
        {
            Width = Math.Max(0, _spec.Width - 60),
            Height = Math.Max(0, _spec.Height - 55),
            Background = Brushes.Black,
            Opacity = 0,
            IsHitTestVisible = false
        };
        _blueTooltipDimPopup = new Popup
        {
            PlacementTarget = root,
            Placement = PlacementMode.AnchorAndGravity,
            PlacementRect = new Rect(0, 0, 0, 0),
            PlacementAnchor = Avalonia.Controls.Primitives.PopupPositioning.PopupAnchor.TopLeft,
            PlacementGravity = Avalonia.Controls.Primitives.PopupPositioning.PopupGravity.BottomRight,
            HorizontalOffset = 60,
            VerticalOffset = 55,
            Topmost = true,
            ShouldUseOverlayLayer = false,
            TakesFocusFromNativeControl = false,
            IsOpen = false,
            Child = _blueTooltipDimmer
        };
        _blueTooltipPopup = new Popup
        {
            PlacementTarget = root,
            Placement = PlacementMode.AnchorAndGravity,
            PlacementRect = new Rect(0, 0, 0, 0),
            PlacementAnchor = Avalonia.Controls.Primitives.PopupPositioning.PopupAnchor.TopLeft,
            PlacementGravity = Avalonia.Controls.Primitives.PopupPositioning.PopupGravity.BottomRight,
            HorizontalOffset = 67,
            VerticalOffset = 55,
            Topmost = true,
            ShouldUseOverlayLayer = false,
            TakesFocusFromNativeControl = false,
            IsOpen = false,
            Child = tooltip
        };
        root.Children.Add(_blueTooltipDimPopup);
        root.Children.Add(_blueTooltipPopup);
        return root;
    }

    private Control BuildBlueEditorPage()
    {
        var page = new Grid
        {
            Margin = new Thickness(10, 7, 5, 5),
            RowDefinitions = new RowDefinitions("27,7,*,5,36")
        };
        var pageTitle = new StackPanel
        {
            Orientation = StackOrientation.Horizontal,
            Spacing = 6,
            VerticalAlignment = VAlign.Center
        };
        pageTitle.Children.Add(new TextBlock
        {
            Text = "Execution",
            Foreground = Brushes.White,
            FontSize = 21,
            FontWeight = FontWeight.Light,
            VerticalAlignment = VAlign.Center
        });
        page.Children.Add(pageTitle);

        var workspace = new Grid { ColumnDefinitions = new ColumnDefinitions("*,10,107") };
        Grid.SetRow(workspace, 2);
        var editorColumn = new Grid { RowDefinitions = new RowDefinitions("26,*") };
        editorColumn.Children.Add(BuildTabBar(SynapseFrontendKind.Blue));
        var editorHost = new Border { Background = Brush(_spec.EditorBg), ClipToBounds = true, Child = _editor };
        Grid.SetRow(editorHost, 1);
        editorColumn.Children.Add(editorHost);
        workspace.Children.Add(editorColumn);
        var list = BuildScriptList("#2A2A2A", "#2A2A2A", 9);
        Grid.SetColumn(list, 2);
        workspace.Children.Add(list);
        page.Children.Add(workspace);

        var actions = new Grid { ColumnDefinitions = new ColumnDefinitions("91,4,91,4,91,4,91,4,91,*,109") };
        Grid.SetRow(actions, 4);
        AddAction(actions, "Execute", 0, 13, false);
        AddAction(actions, "Clear", 2, 13, true);
        AddAction(actions, "Open File", 4, 13, false);
        AddAction(actions, "Execute File", 6, 12, false);
        AddAction(actions, "Save File", 8, 13, false);
        AddAction(actions, "Attach", 10, 13, false);
        page.Children.Add(actions);
        return page;
    }

    private Control BuildClassicShell()
    {
        var root = new Grid { RowDefinitions = new RowDefinitions("58,*") };
        root.Children.Add(BuildTitleBar(
            CreateLogo("avares://Orion/Assets/Synapse/classic-wordmark.png", 139, 29, new Thickness(9, 0, 0, 0)),
            Brush("#282828"),
            58,
            compactControls: false,
            legacyTinyControls: true));

        var body = new Grid { Background = Brush("#232323") };
        Grid.SetRow(body, 1);

        var workspace = new Grid
        {
            Margin = new Thickness(8, 12, 12, 61),
            ColumnDefinitions = new ColumnDefinitions("*,7,139")
        };
        var editorColumn = new Grid { RowDefinitions = new RowDefinitions("17,*") };
        editorColumn.Children.Add(BuildTabBar(SynapseFrontendKind.Classic2017));
        var editorHost = new Border { Background = Brush(_spec.EditorBg), ClipToBounds = true, Child = _editor };
        Grid.SetRow(editorHost, 1);
        editorColumn.Children.Add(editorHost);
        workspace.Children.Add(editorColumn);
        var list = BuildScriptList("#282828", "#333333", 10);
        Grid.SetColumn(list, 2);
        workspace.Children.Add(list);
        body.Children.Add(workspace);

        var actions = new Grid
        {
            Height = 39,
            Margin = new Thickness(9, 0, 12, 10),
            VerticalAlignment = VAlign.Bottom,
            ColumnDefinitions = new ColumnDefinitions("116*,5,116*,5,116*,5,116*,5,144*,5,184*")
        };
        AddClassicAction(actions, "Execute", 0, false);
        AddClassicAction(actions, "Clear", 2, true);
        AddClassicAction(actions, "Open File", 4, false);
        AddClassicAction(actions, "Attach", 6, false);
        AddClassicAction(actions, "Script Hub", 8, false);
        AddClassicAction(actions, "Settings & Clients", 10, false);
        body.Children.Add(actions);
        root.Children.Add(body);
        return root;
    }

    private Control BuildSynapseXShell()
    {
        var root = new Grid { RowDefinitions = new RowDefinitions("30,*") };
        root.Children.Add(BuildTitleBar(CreateSynapseXLogo(), Brush("#3C3C3C"), 30, compactControls: true, "Synapse X"));

        var body = new Grid { Background = Brush("#333333") };
        Grid.SetRow(body, 1);
        var workspace = new Grid
        {
            Margin = new Thickness(10, 5, 6, 49),
            ColumnDefinitions = new ColumnDefinitions("*,5,122")
        };
        var editorColumn = new Grid { RowDefinitions = new RowDefinitions("17,*") };
        editorColumn.Children.Add(BuildTabBar(SynapseFrontendKind.SynapseX));
        var host = new Border { Background = Brush(_spec.EditorBg), ClipToBounds = true, Child = _editor };
        Grid.SetRow(host, 1);
        editorColumn.Children.Add(host);
        workspace.Children.Add(editorColumn);
        var list = BuildScriptList("#3C3C3C", "#333333", 10);
        Grid.SetColumn(list, 2);
        workspace.Children.Add(list);
        body.Children.Add(workspace);

        var actions = new Canvas { Height = 46, VerticalAlignment = VAlign.Bottom };
        var labels = new[] { "Execute", "Clear", "Open File", "Execute File", "Save File", "Options", "Attach", "Script Hub" };
        var lefts = new[] { 10d, 106d, 202d, 298d, 394d, 490d, 608d, 704d };
        for (var index = 0; index < labels.Length; index++)
        {
            var button = CreateActionButton(labels[index], 91, 33, 14, Brush("#3C3C3C"), "#3C3C3C");
            if (labels[index] == "Clear") button.Click += (_, _) => SetEditorContent(string.Empty);
            else if (labels[index] == "Open File") button.Click += OpenV3ScriptPicker;
            else if (labels[index] == "Save File") button.Click += SaveV3ScriptPicker;
            else if (labels[index] == "Options") button.Click += (_, _) => OpenSynapseXOptionsWindow();
            else if (labels[index] == "Script Hub") button.Click += (_, _) => OpenSynapseXScriptHubWindow();
            RegisterBridgeAction(button, labels[index]);
            Canvas.SetLeft(button, lefts[index]);
            Canvas.SetTop(button, 3);
            actions.Children.Add(button);
        }
        body.Children.Add(actions);
        root.Children.Add(body);
        return root;
    }

    private Control BuildV3Shell()
    {
        var root = new Grid { RowDefinitions = new RowDefinitions("44,*"), Background = Brushes.Black };
        root.Children.Add(BuildV3TitleBar());
        var bodyHost = new Grid { Background = Brushes.Black };
        Grid.SetRow(bodyHost, 1);
        _v3Pages.Add(BuildV3EditorPage());
        _v3Pages.Add(BuildV3SettingsPageExact());
        _v3Pages.Add(BuildV3ScriptHubPageExact());
        _v3Pages.Add(BuildV3ThemePage());
        _v3Pages.Add(BuildV3PluginsPage());
        _editorPage = _v3Pages[0];
        for (var index = 0; index < _v3Pages.Count; index++)
        {
            _v3Pages[index].IsVisible = index == 0;
            bodyHost.Children.Add(_v3Pages[index]);
        }
        root.Children.Add(bodyHost);
        return root;
    }

    private Control BuildV3TitleBar()
    {
        var bar = new Grid { Background = Brushes.Black };
        bar.PointerPressed += TitleBarPointerPressed;
        var logo = CreateLogo("avares://Orion/Assets/Synapse/v3-logo.png", 105, 26, new Thickness(9, 8, 0, 0));
        logo.HorizontalAlignment = HAlign.Left;
        logo.VerticalAlignment = VAlign.Top;
        bar.Children.Add(logo);

        var nav = new StackPanel
        {
            Orientation = StackOrientation.Horizontal,
            Width = 135,
            Height = 27,
            HorizontalAlignment = HAlign.Center,
            VerticalAlignment = VAlign.Center,
            Spacing = 0
        };
        var paths = new[]
        {
            SynapseV3IconData.WindowConsole,
            SynapseV3IconData.Settings,
            SynapseV3IconData.Globe,
            SynapseV3IconData.PaintBrush,
            SynapseV3IconData.Puzzle
        };
        for (var index = 0; index < paths.Length; index++)
        {
            var page = index;
            var cell = new Grid { Width = 27, Height = 27, RowDefinitions = new RowDefinitions("*,2") };
            var navIcon = CreateSvgIcon(paths[index], 20, "#FFFFFF");
            navIcon.RenderTransformOrigin = new RelativePoint(.5, .5, RelativeUnit.Relative);
            navIcon.RenderTransform = new ScaleTransform(index == 0 ? 1.02 : 1, index == 0 ? 1.02 : 1);
            _v3NavIcons.Add(navIcon);
            navIcon.VerticalAlignment = VAlign.Top;
            navIcon.Margin = new Thickness(0, 1, 0, 0);
            var button = new Button
            {
                Width = 27,
                Height = 25,
                Content = navIcon,
                Background = Brushes.Transparent,
                BorderThickness = new Thickness(0),
                Padding = new Thickness(0),
                VerticalContentAlignment = VAlign.Stretch
            };
            button.Click += (_, _) => ShowV3Page(page);
            cell.Children.Add(button);
            var underline = new Border
            {
                Height = 1.1,
                Width = 19.5,
                Background = index == 0 ? Brushes.White : Brushes.Transparent,
                HorizontalAlignment = HAlign.Center,
                VerticalAlignment = VAlign.Bottom,
                CornerRadius = new CornerRadius(.55)
            };
            _v3Underlines.Add(underline);
            Grid.SetRow(underline, 1);
            cell.Children.Add(underline);
            nav.Children.Add(cell);
        }
        bar.Children.Add(nav);

        var controls = new Canvas { Width = 106, Height = 44, HorizontalAlignment = HAlign.Right };
        // The source places controls left-to-right as minimize, maximize,
        // close. The coordinates below are the source's right offsets from
        // the 106px control rail.
        controls.Children.Add(CreateSvgWindowButton(SynapseV3IconData.WindowMinimize, 10, () => WindowState = WindowState.Minimized, 82, 19));
        controls.Children.Add(CreateSvgWindowButton(
            SynapseV3IconData.WindowMaximize,
            10,
            () =>
            {
                if (OrbitPreferences.ResizableEnabled)
                {
                    WindowState = WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized;
                }
            },
            47,
            19));
        controls.Children.Add(CreateSvgWindowButton(SynapseV3IconData.WindowClose, 10, CloseV3Window, 15, 19));
        bar.Children.Add(controls);
        return bar;
    }

    private Control BuildV3EditorPage()
    {
        var page = new Grid
        {
            Background = Brushes.Black,
            RowDefinitions = new RowDefinitions("6,32,5,*,46"),
            // The source leaves a three-pixel black gutter between Monaco and
            // the 197px script rail. Keeping that gutter in the grid also
            // prevents tab/status chrome from painting underneath the rail.
            ColumnDefinitions = new ColumnDefinitions("*,3,197")
        };
        var tabs = BuildTabBar(SynapseFrontendKind.V3);
        Grid.SetRow(tabs, 1);
        page.Children.Add(tabs);
        var editorHost = new Border { Background = Brushes.Black, ClipToBounds = true, Margin = new Thickness(1, 0, 0, 0), Child = _editor };
        Grid.SetRow(editorHost, 3);
        page.Children.Add(editorHost);

        var list = BuildV3ScriptList();
        Grid.SetColumn(list, 2);
        Grid.SetRowSpan(list, 5);
        list.Margin = new Thickness(0, 6, 0, 0);
        page.Children.Add(list);

        var actionBar = new Grid { Background = Brushes.Black };
        Grid.SetRow(actionBar, 4);
        var actions = new StackPanel
        {
            Orientation = StackOrientation.Horizontal,
            Spacing = 4,
            Margin = new Thickness(4, 7, 0, 6)
        };
        actions.Children.Add(CreateV3Action(SynapseV3IconData.Play, "Execute", false, false));
        actions.Children.Add(CreateV3Action(SynapseV3IconData.Eraser, "Clear", true, true));
        actions.Children.Add(CreateV3Action(SynapseV3IconData.DocumentArrowUp, "Open", true, false));
        actions.Children.Add(CreateV3Action(SynapseV3IconData.Settings, "Execute", false, false, executesFile: true));
        actions.Children.Add(CreateV3Action(SynapseV3IconData.Save, "Save", true, false));
        actionBar.Children.Add(actions);

        var status = new StackPanel
        {
            Orientation = StackOrientation.Horizontal,
            HorizontalAlignment = HAlign.Right,
            VerticalAlignment = VAlign.Center,
            Spacing = 9,
            Margin = new Thickness(0, 0, 10, 0)
        };
        status.Children.Add(CreateSvgIcon(SynapseV3IconData.PlugDisconnected, 20, "#E8C84A"));
        status.Children.Add(CreateSvgIcon(SynapseV3IconData.WindowConsole, 20, "#FFFFFF"));
        status.Children.Add(CreateSvgIcon(SynapseV3IconData.SearchSquare, 20, "#FFFFFF"));
        var aiIcon = CreateSvgIcon(SynapseV3IconData.Bot, 20, "#FFFFFF");
        aiIcon.Opacity = .4;
        status.Children.Add(aiIcon);
        actionBar.Children.Add(status);
        page.Children.Add(actionBar);

        var gistPopup = BuildV3GistPopup();
        Grid.SetRow(gistPopup, 0);
        Grid.SetRowSpan(gistPopup, 5);
        gistPopup.ZIndex = 100;
        page.Children.Add(gistPopup);
        return page;
    }

    private Control BuildV3SettingsPage()
    {
        var root = new Grid { Background = Brush("#000000"), ColumnDefinitions = new ColumnDefinitions("58,*") };
        var settingsStack = new StackPanel { Spacing = 0 };
        var application = BuildV3SectionHeader("Application", SynapseV3IconData.SettingsApplication);
        var editor = BuildV3SectionHeader("Editor", SynapseV3IconData.SettingsSectionEditor, true);
        var terminal = BuildV3SectionHeader("Terminal", SynapseV3IconData.SettingsTerminal, true);
        var layers = BuildV3SectionHeader("Layers", SynapseV3IconData.SettingsLayers, true);
        var config = BuildV3SectionHeader("Config", SynapseV3IconData.SettingsConfig);
        settingsStack.Children.Add(application);
        var moveToOrbit = (Button)BuildV3OutlineButton("Move to Orbit UI", 140);
        moveToOrbit.Click += (_, _) => ReturnWorkspaceToOrbit();
        settingsStack.Children.Add(BuildV3SettingRow("UI Shell", "Return to Orbit's native interface.", moveToOrbit));
        settingsStack.Children.Add(editor);
        settingsStack.Children.Add(new Border { Height = 22, Background = Brushes.Transparent });
        settingsStack.Children.Add(terminal);
        settingsStack.Children.Add(new Border { Height = 22, Background = Brushes.Transparent });
        settingsStack.Children.Add(layers);
        settingsStack.Children.Add(new Border { Height = 22, Background = Brushes.Transparent });
        settingsStack.Children.Add(config);
        settingsStack.Children.Add(new Border { Height = 22, Background = Brushes.Transparent });
        settingsStack.Children.Add(new Border { Height = 200, Background = Brushes.Transparent });
        var content = new ScrollViewer
        {
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
            Background = Brushes.Black,
            Padding = new Thickness(10, 8, 10, 16),
            HorizontalContentAlignment = HAlign.Stretch,
            Content = settingsStack
        };
        root.Children.Add(BuildV3SideRail(
            new[] { "Application", "Editor", "Terminal", "Layers", "Config" },
            0,
            content,
            new Control[] { application, editor, terminal, layers, config }));
        Grid.SetColumn(content, 1);
        root.Children.Add(content);
        return root;
    }

    private Control BuildV3ScriptHubPage()
    {
        var root = new Grid { Background = Brushes.Black, RowDefinitions = new RowDefinitions("32,6,38,*") };
        var sourceTabs = new StackPanel { Orientation = StackOrientation.Horizontal, HorizontalAlignment = HAlign.Center, Spacing = 5, Background = Brushes.Black };
        _v3HubApiTab = BuildV3TabChip("Scripts", true, 176);
        _v3HubSynapseTab = BuildV3TabChip("Synapse Script Hub", false, 176);
        _v3HubApiTab.Click += (_, _) => SetV3HubSource(false);
        _v3HubSynapseTab.Click += (_, _) => SetV3HubSource(true);
        sourceTabs.Children.Add(_v3HubApiTab);
        sourceTabs.Children.Add(_v3HubSynapseTab);
        root.Children.Add(new Border { Background = Brushes.Black, Child = sourceTabs });
        var toggleShadow = new Border { Background = new LinearGradientBrush { StartPoint = new RelativePoint(0, 0, RelativeUnit.Relative), EndPoint = new RelativePoint(0, 1, RelativeUnit.Relative), GradientStops = new GradientStops { new(Color.Parse("#000000"), 0), new(Color.Parse("#000000"), 1) } }, Opacity = .28 };
        Grid.SetRow(toggleShadow, 1);
        root.Children.Add(toggleShadow);
        var searchField = new TextBox
        {
            Text = "",
            PlaceholderText = "Search robloxscripts.com…",
            FontSize = 12,
            Foreground = Brushes.White,
            Background = Brushes.Transparent,
            BorderThickness = new Thickness(0),
            Padding = new Thickness(30, 0, 8, 0),
            VerticalContentAlignment = VAlign.Center
        };
        var searchContent = new Grid { Children = { searchField } };
        searchContent.Children.Add(new Border
        {
            Width = 14,
            Height = 14,
            Margin = new Thickness(10, 0, 0, 0),
            HorizontalAlignment = HAlign.Left,
            VerticalAlignment = VAlign.Center,
            Child = CreateSvgIcon("M10.5 10.5L15 15M13 7A6 6 0 1 1 1 7A6 6 0 0 1 13 7Z", 14, "#868686", 16, true)
        });
        _v3HubSearch = new Border
        {
            Margin = new Thickness(12, 2, 12, 2),
            Background = Brushes.Black,
            CornerRadius = new CornerRadius(3),
            Child = searchContent
        };
        Grid.SetRow(_v3HubSearch, 2);
        root.Children.Add(_v3HubSearch);

        // Both sources stay mounted so changing source is immediate and never
        // rebuilds the page underneath the pointer. This mirrors the original
        // V3 toggle, while keeping the two card sets completely independent.
        _v3HubApiContent = BuildV3ScriptHubCards(
            new[] { "Universal Script", "Player Utilities", "Infinite Yield", "ESP Tools", "UI Library", "Admin Commands", "Teleport Hub", "Animation Pack", "Loader", "Combat Tools", "Vehicle Hub", "Utility Pack" });
        _v3HubSynapseContent = BuildV3ScriptHubCards(
            new[] { "Dark Dex", "Unnamed ESP", "Remote Spy", "Script Dumper", "Infinite Yield", "Simple Spy", "Admin Commands", "Fly GUI", "Walkspeed", "Aimbot", "ESP Library", "UI Tools" });
        Grid.SetRow(_v3HubApiContent, 3);
        Grid.SetRow(_v3HubSynapseContent, 3);
        root.Children.Add(_v3HubApiContent);
        root.Children.Add(_v3HubSynapseContent);
        SetV3HubSource(false);
        return root;
    }

    private static Control BuildV3ScriptHubCards(string[] titles)
    {
        var grid = new Grid
        {
            Margin = new Thickness(12, 0, 12, 8),
            ColumnDefinitions = new ColumnDefinitions("*,*,*,*"),
            RowDefinitions = new RowDefinitions("Auto,Auto,Auto,Auto")
        };
        for (var i = 0; i < titles.Length; i++)
        {
            var card = BuildV3ScriptHubCard(titles[i], i);
            Grid.SetColumn(card, i % 4);
            Grid.SetRow(card, i / 4);
            grid.Children.Add(card);
        }
        return new ScrollViewer
        {
            Content = grid,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
            IsVisible = false
        };
    }

    private void SetV3HubSource(bool synapse)
    {
        if (_v3HubApiTab is null || _v3HubSynapseTab is null) return;
        _v3HubApiTab.Background = Brush(synapse ? "#000000" : "#121212");
        _v3HubApiTab.Foreground = synapse ? Brush("#8D8D8D") : Brushes.White;
        _v3HubSynapseTab.Background = Brush(synapse ? "#121212" : "#000000");
        _v3HubSynapseTab.Foreground = synapse ? Brushes.White : Brush("#8D8D8D");
        if (_v3HubApiContent is not null) _v3HubApiContent.IsVisible = !synapse;
        if (_v3HubSynapseContent is not null) _v3HubSynapseContent.IsVisible = synapse;
        if (_v3HubSearch is not null) _v3HubSearch.IsVisible = !synapse;
    }

    private Control BuildV3ThemePage()
    {
        if (_kind == SynapseFrontendKind.V3)
        {
            return BuildV3PrototypePage();
        }
        var root = new Grid { Background = Brushes.Black, ColumnDefinitions = new ColumnDefinitions("58,*") };
        var labels = new[] { "Quick", "Brand", "Shell", "Accent", "Editor", "Scripts", "AI chat", "AI overlays", "Top bar", "Icons", "Actions", "Panels", "Script Hub", "Background", "Effects", "Tuning", "Typography", "Manage" };
        root.Children.Add(BuildV3SideRail(labels, 0));
        var scroll = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Padding = new Thickness(10, 8, 10, 16), Background = Brushes.Black };
        var stack = new StackPanel { Spacing = 0 };
        stack.Children.Add(BuildV3SettingRow("Community Themes", "Import shared themes from GitHub releases.", BuildV3ChipRow("Export theme", "Browse themes")));
        stack.Children.Add(BuildV3SectionHeader("Visual Effects", SynapseV3IconData.PaintBrush));
        stack.Children.Add(BuildV3SettingRow("Background image", "Choose a background layer for the V3 shell.", BuildV3OutlineButton("Browse", 90)));
        stack.Children.Add(BuildV3SettingRow("Page scrim opacity", "Darkens the page above the background media.", BuildV3ValueChip("55%")));
        stack.Children.Add(BuildV3SectionHeader("Quick", SynapseV3IconData.Settings));
        stack.Children.Add(BuildV3SettingRow("Theme preset", "Apply a complete V3 theme preset.", BuildV3ChipRow("V3 Default", "Midnight", "Reset")));
        stack.Children.Add(BuildV3SectionHeader("Branding", SynapseV3IconData.TextAsterisk));
        stack.Children.Add(BuildV3SettingRow("Top bar logo", "Pick a preset or upload your own.", BuildV3OutlineButton("Browse custom logo...", 150)));
        stack.Children.Add(BuildV3SectionHeader("Shell", SynapseV3IconData.WindowConsole));
        stack.Children.Add(BuildV3SettingRow("Corner radius", "Radius of the native V3 shell surface.", BuildV3ValueChip("7 px")));
        stack.Children.Add(BuildV3SectionHeader("Editor", SynapseV3IconData.WindowConsole));
        stack.Children.Add(BuildV3SettingRow("Editor background", "The work area behind Monaco.", BuildV3ValueChip("#000000")));
        stack.Children.Add(BuildV3SectionHeader("Script Hub", SynapseV3IconData.Globe));
        stack.Children.Add(BuildV3SettingRow("Card glass", "Surface and border treatment for script cards.", BuildV3ValueChip("Enabled")));
        stack.Children.Add(BuildV3SectionHeader("Effects", SynapseV3IconData.PaintBrush));
        stack.Children.Add(BuildV3Note("Adjust shell effects and visual polish from this panel."));
        stack.Children.Add(new Border { Height = 120, Background = Brushes.Transparent });
        scroll.Content = stack;

        var panel = new Grid { RowDefinitions = new RowDefinitions("*,72"), Background = Brushes.Black };
        panel.Children.Add(scroll);
        var footerCopy = new StackPanel
        {
            Spacing = 2,
            VerticalAlignment = VAlign.Center,
            Children =
            {
                new TextBlock { Text = "CSS Editor", Foreground = Brushes.White, FontSize = 14 },
                new TextBlock { Text = "Edit raw CSS variables for advanced customization.", Foreground = Brush("#6B6B6B"), FontSize = 12 }
            }
        };
        var footerControls = new StackPanel
        {
            Orientation = StackOrientation.Horizontal,
            Spacing = 12,
            HorizontalAlignment = HAlign.Right,
            VerticalAlignment = VAlign.Center,
            Children =
            {
                BuildV3Checkbox(false),
                new Button
                {
                    Width = 80,
                    Height = 30,
                    Content = "LIVE EDIT",
                    Background = Brush("#212120"),
                    BorderBrush = Brush("#3A3A3A"),
                    BorderThickness = new Thickness(1),
                    CornerRadius = new CornerRadius(4),
                    Foreground = Brush("#B0D8E5"),
                    FontSize = 10,
                    FontWeight = FontWeight.SemiBold
                }
            }
        };
        var footerGrid = new Grid
        {
            ColumnDefinitions = new ColumnDefinitions("*,auto"),
            Children = { footerCopy, footerControls }
        };
        Grid.SetColumn(footerControls, 1);
        var footer = new Border
        {
            Padding = new Thickness(12, 10),
            Background = Brushes.Black,
            BorderBrush = Brush("#3A3A3A"),
            BorderThickness = new Thickness(0, 1, 0, 0),
            Child = footerGrid
        };
        Grid.SetRow(footer, 1);
        panel.Children.Add(footer);
        Grid.SetColumn(panel, 1);
        root.Children.Add(panel);
        return root;
    }

    private static Border BuildV3ScriptHubCard(string title, int index)
    {
        var palette = new[]
        {
            ("#253342", "#121820"), ("#3B2D24", "#171310"), ("#25362C", "#111A15"),
            ("#3C2529", "#191012"), ("#303044", "#13131B"), ("#21363B", "#0F181B")
        };
        var colors = palette[index % palette.Length];
        var backdrop = new Border
        {
            Background = new LinearGradientBrush
            {
                StartPoint = new RelativePoint(0, 0, RelativeUnit.Relative),
                EndPoint = new RelativePoint(1, 1, RelativeUnit.Relative),
                GradientStops = new GradientStops
                {
                    new(Color.Parse(colors.Item1), 0),
                    new(Color.Parse(colors.Item2), 1)
                }
            }
        };

        var details = new StackPanel { Spacing = 5 };
        details.Children.Add(new TextBlock
        {
            Text = $"{title} · Universal Script",
            Foreground = Brush("#F6F6F5"),
            FontSize = 12,
            FontWeight = FontWeight.SemiBold,
            TextTrimming = TextTrimming.CharacterEllipsis
        });
        var actions = new Grid { Height = 24, ColumnDefinitions = new ColumnDefinitions("*,4,24,4,24") };
        actions.Children.Add(new Button
        {
            Content = "Execute",
            Background = Brush("#343434"),
            BorderBrush = Brush("#555555"),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(3),
            Foreground = Brush("#C8C8C8"),
            FontSize = 10,
            Padding = new Thickness(4, 0)
        });
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
        Grid.SetColumn(open, 2);
        actions.Children.Add(open);
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
        Grid.SetColumn(view, 4);
        actions.Children.Add(view);
        details.Children.Add(actions);

        var glass = new Border
        {
            VerticalAlignment = VAlign.Bottom,
            Padding = new Thickness(8, 6),
            Background = Brush("#261E1E1E"),
            BorderBrush = Brush("#1AFFFFFF"),
            BorderThickness = new Thickness(0, 1, 0, 0),
            CornerRadius = new CornerRadius(0, 0, 7, 7),
            Child = details
        };
        return new Border
        {
            Height = 165,
            Margin = new Thickness(0, 0, 8, 8),
            Background = Brush("#202020"),
            CornerRadius = new CornerRadius(7),
            ClipToBounds = true,
            Child = new Grid { Children = { backdrop, glass } }
        };
    }

    private Control BuildV3PluginsPage()
    {
        if (_kind == SynapseFrontendKind.V3)
        {
            return BuildV3PrototypePage();
        }
        var root = new Grid
        {
            Background = Brushes.Black,
            RowDefinitions = new RowDefinitions("49,*")
        };

        var toolbarContent = new StackPanel
        {
            Orientation = StackOrientation.Horizontal,
            Spacing = 4,
            VerticalAlignment = VAlign.Center
        };
        toolbarContent.Children.Add(CreateSvgIcon(SynapseV3IconData.Puzzle, 16, "#FFFFFF"));
        toolbarContent.Children.Add(new TextBlock
        {
            Text = "Plugins",
            Width = 66,
            Margin = new Thickness(4, 0, 8, 0),
            Foreground = Brushes.White,
            FontSize = 16,
            VerticalAlignment = VAlign.Center
        });
        toolbarContent.Children.Add(BuildV3ToolbarIconButton(SynapseV3IconData.Settings, "Plugins AI"));
        toolbarContent.Children.Add(BuildV3ToolbarButton("Log", 52));
        toolbarContent.Children.Add(BuildV3ToolbarDivider());
        toolbarContent.Children.Add(BuildV3ToolbarButton("New", 49));
        toolbarContent.Children.Add(BuildV3ToolbarButton("Community", 82));
        toolbarContent.Children.Add(BuildV3ToolbarDivider());
        toolbarContent.Children.Add(BuildV3ToolbarButton("Import", 58));
        toolbarContent.Children.Add(BuildV3ToolbarButton("Export", 59));
        toolbarContent.Children.Add(BuildV3ToolbarButton("Community export", 116));

        var toolbar = new Border
        {
            MinHeight = 33,
            Margin = new Thickness(8, 8, 8, 8),
            Padding = new Thickness(12, 2),
            Background = Brush("#303030"),
            CornerRadius = new CornerRadius(4),
            Child = toolbarContent
        };
        root.Children.Add(toolbar);

        var split = new Grid
        {
            Margin = new Thickness(8, 0, 8, 8),
            ColumnDefinitions = new ColumnDefinitions("200,8,*")
        };
        Grid.SetRow(split, 1);

        var railStack = new StackPanel { Spacing = 0 };
        railStack.Children.Add(new TextBox
        {
            PlaceholderText = "Search plugins…",
            Height = 28,
            Margin = new Thickness(0, 0, 0, 8),
            Padding = new Thickness(8, 0),
            Background = Brush("#373737"),
            BorderBrush = Brush("#3D3D3C"),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(4),
            Foreground = Brushes.White,
            FontSize = 11,
            VerticalContentAlignment = VAlign.Center
        });
        railStack.Children.Add(BuildV3RestartButton("Restart Framework", "#182216", "#43632D", "#8BC34A"));
        railStack.Children.Add(new TextBlock
        {
            Text = "Saves enabled plugins and restarts the entire app.",
            Foreground = Brush("#777777"),
            FontSize = 10,
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(0, 3, 0, 8)
        });
        railStack.Children.Add(BuildV3RestartButton("Restart as Admin", "#211D16", "#6A5A3D", "#D4A84B"));
        railStack.Children.Add(new TextBlock
        {
            Text = "Recommended with some APIs",
            Foreground = Brush("#777777"),
            FontSize = 10,
            Margin = new Thickness(0, 3, 0, 8)
        });
        railStack.Children.Add(new TextBlock
        {
            Text = "No plugins yet. Create or import one.",
            Foreground = Brush("#666666"),
            FontSize = 11,
            Margin = new Thickness(0, 8, 0, 0)
        });
        var rail = new Border
        {
            Background = Brushes.Black,
            BorderBrush = Brush("#3A3A3A"),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(4),
            Padding = new Thickness(8),
            Child = railStack
        };
        split.Children.Add(rail);

        var empty = new StackPanel
        {
            HorizontalAlignment = HAlign.Center,
            VerticalAlignment = VAlign.Center,
            Spacing = 14,
            MaxWidth = 470
        };
        empty.Children.Add(CreateSvgIcon(SynapseV3IconData.Puzzle, 40, "#555555"));
        empty.Children.Add(new TextBlock
        {
            Text = "Create or import a plugin",
            Foreground = Brush("#CCCCCC"),
            FontSize = 14,
            HorizontalAlignment = HAlign.Center
        });
        empty.Children.Add(new TextBlock
        {
            Text = "Each plugin is a single plugin.js file. Enable it, edit the file, save, then click Restart Framework to apply changes across Synapse Blue, OG, X, and V3.",
            Foreground = Brush("#777777"),
            FontSize = 12,
            TextAlignment = TextAlignment.Center,
            TextWrapping = TextWrapping.Wrap,
            HorizontalAlignment = HAlign.Center
        });
        empty.Children.Add(BuildV3OutlineButton("New plugin", 102));
        var editor = new Border { Background = Brushes.Black, Child = empty };
        Grid.SetColumn(editor, 2);
        split.Children.Add(editor);
        root.Children.Add(split);
        return root;
    }

    private static Control BuildV3PrototypePage() => new Border
    {
        Background = Brushes.Black,
        Child = new TextBlock
        {
            Text = "prototype - not available",
            Foreground = Brush("#6B6B6B"),
            FontSize = 14,
            HorizontalAlignment = HAlign.Center,
            VerticalAlignment = VAlign.Center
        }
    };

    private static Control BuildV3SideRail(string[] labels, int active, ScrollViewer? targetScroll = null, IReadOnlyList<Control>? targets = null)
    {
        var rail = new StackPanel { Background = Brushes.Black, Spacing = 9, Margin = new Thickness(3, 4, 3, 8) };
        for (var i = 0; i < labels.Length; i++)
        {
            var path = labels[i] switch
            {
                "Application" => SynapseV3IconData.SettingsSidebarApplication,
                "Editor" => SynapseV3IconData.SettingsEditor,
                "Terminal" => SynapseV3IconData.SettingsTerminal,
                "Layers" => SynapseV3IconData.SettingsLayers,
                "Config" => SynapseV3IconData.SettingsConfig,
                "Quick" => SynapseV3IconData.SettingsApplication,
                "Brand" => SynapseV3IconData.SettingsApplication,
                "Shell" => SynapseV3IconData.SettingsEditor,
                "Accent" => SynapseV3IconData.PaintBrush,
                "Scripts" => SynapseV3IconData.SettingsLayers,
                "Icons" => SynapseV3IconData.SettingsTerminal,
                "Panels" => SynapseV3IconData.SettingsConfig,
                "Script Hub" => SynapseV3IconData.Globe,
                "Background" => SynapseV3IconData.SettingsEditor,
                "Effects" => SynapseV3IconData.PaintBrush,
                _ => SynapseV3IconData.Settings
            };
            var strokeIcon = labels[i] is "Editor" or "Terminal" or "Layers";
            var cell = new Grid { Width = 51, Height = 36 };
            var button = new Button
            {
                Width = 51,
                Height = 36,
                Background = i == active ? Brush("#121212") : Brushes.Transparent,
                BorderThickness = new Thickness(0),
                CornerRadius = new CornerRadius(4),
                Padding = new Thickness(0),
                Content = CreateSvgIcon(path, 18, i == active ? "#FFFFFF" : "#8D8D8D", 18, strokeIcon)
            };
            ToolTip.SetTip(button, labels[i]);
            if (targetScroll is not null && targets is not null && i < targets.Count)
            {
                var target = targets[i];
                button.Click += (_, _) => target.BringIntoView();
            }
            cell.Children.Add(button);
            if (i == active)
            {
                cell.Children.Add(new Border
                {
                    Width = 3,
                    Margin = new Thickness(0, 4, 0, 4),
                    HorizontalAlignment = HAlign.Left,
                    Background = Brush("#BDD3DE"),
                    CornerRadius = new CornerRadius(0, 2, 2, 0)
                });
            }
            rail.Children.Add(cell);
        }
        var scroll = new ScrollViewer
        {
            VerticalScrollBarVisibility = ScrollBarVisibility.Hidden,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
            Background = Brushes.Black,
            Content = rail
        };
        Grid.SetColumn(scroll, 0);
        return scroll;
    }

    private static Border BuildV3SectionHeader(string title, string iconPath, bool strokeIcon = false)
    {
        var viewBox = iconPath is SynapseV3IconData.SettingsApplication or SynapseV3IconData.SettingsSectionEditor or SynapseV3IconData.SettingsTerminal or SynapseV3IconData.SettingsLayers or SynapseV3IconData.SettingsConfig ? 14 : 18;
        return new Border { Height = 33, Margin = new Thickness(0, 0, 0, 16), Padding = new Thickness(12, 0), Background = Brush("#303030"), CornerRadius = new CornerRadius(4), Child = new StackPanel { Orientation = StackOrientation.Horizontal, Spacing = 8, VerticalAlignment = VAlign.Center, Children = { CreateSvgIcon(iconPath, 14, "#FFFFFF", viewBox, strokeIcon), new TextBlock { Text = title, Foreground = Brushes.White, FontSize = 16 } } } };
    }

    private static Control BuildV3SettingRow(string label, string description, Control control)
    {
        return new Grid { Margin = new Thickness(0, 0, 0, 22), ColumnDefinitions = new ColumnDefinitions("*,auto"), Children = { new StackPanel { Spacing = 4, Children = { new TextBlock { Text = label, Foreground = Brushes.White, FontSize = 14 }, new TextBlock { Text = description, Foreground = Brush("#6B6B6B"), FontSize = 13, TextWrapping = TextWrapping.Wrap } } }, new Border { Child = control, Margin = new Thickness(16, 0, 0, 0) } } };
    }

    private static Control BuildV3OutlineButton(string text, double width)
    {
        return new Button { Width = width, Height = 33, Content = text, Background = Brush("#373737"), BorderBrush = Brush("#3D3D3C"), BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(4), Foreground = Brushes.White, FontSize = 13, Padding = new Thickness(8, 0) };
    }

    private static Control BuildV3ToolbarButton(string text, double width) => new Button
    {
        Width = width,
        Height = 28,
        Content = text,
        Background = Brush("#373737"),
        BorderBrush = Brush("#3D3D3C"),
        BorderThickness = new Thickness(1),
        CornerRadius = new CornerRadius(4),
        Foreground = Brushes.White,
        FontSize = 12,
        Padding = new Thickness(8, 0)
    };

    private static Control BuildV3ToolbarIconButton(string path, string tooltip)
    {
        var button = new Button
        {
            Width = 28,
            Height = 28,
            Content = CreateSvgIcon(path, 16, "#FFFFFF"),
            Background = Brush("#373737"),
            BorderBrush = Brush("#3D3D3C"),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(4),
            Padding = new Thickness(0)
        };
        ToolTip.SetTip(button, tooltip);
        return button;
    }

    private static Control BuildV3ToolbarDivider() => new Border
    {
        Width = 1,
        Height = 20,
        Margin = new Thickness(4, 0),
        VerticalAlignment = VAlign.Center,
        Background = Brush("#3A3A3A")
    };

    private static Control BuildV3RestartButton(string text, string background, string border, string foreground) => new Button
    {
        Height = 30,
        HorizontalAlignment = HAlign.Stretch,
        HorizontalContentAlignment = HAlign.Center,
        Content = text,
        Background = Brush(background),
        BorderBrush = Brush(border),
        BorderThickness = new Thickness(1),
        CornerRadius = new CornerRadius(4),
        Foreground = Brush(foreground),
        FontSize = 12,
        FontWeight = FontWeight.Medium,
        Padding = new Thickness(4, 0)
    };

    private static Control BuildV3Checkbox(bool value)
    {
        return new Border { Width = 30, Height = 30, Background = value ? Brush("#B0D8E5") : Brushes.Black, BorderBrush = Brush("#7E7E7E"), BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(3), Child = value ? CreateSvgIcon("M1 4.5L4.5 8L12.5 1", 14, "#0F2433", 14, true) : null };
    }

    private static Control BuildV3ChipRow(params string[] labels)
    {
        var stack = new StackPanel { Orientation = StackOrientation.Horizontal, Spacing = 4 };
        foreach (var label in labels.Length == 0 ? new[] { "robloxscripts.com", "ScriptBlox", "HaxHell" } : labels) stack.Children.Add(BuildV3OutlineButton(label, Math.Max(60, label.Length * 7 + 22)));
        return stack;
    }

    private static Control BuildV3ValueChip(string text) => new Border { Height = 30, MinWidth = 72, Background = Brush("#2D2D2D"), BorderBrush = Brush("#3D3D3C"), BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(4), Padding = new Thickness(10, 0), Child = new TextBlock { Text = text, Foreground = Brush("#B0D8E5"), FontSize = 12, VerticalAlignment = VAlign.Center, HorizontalAlignment = HAlign.Center } };

    private static Control BuildV3Field(string watermark, double width) => new TextBox { Width = width, Height = 38, PlaceholderText = watermark, Background = Brush("#373737"), BorderBrush = Brush("#3D3D3C"), Foreground = Brushes.White, FontSize = 14, Padding = new Thickness(10, 0), VerticalContentAlignment = VAlign.Center };

    private static Control BuildV3ReadonlyField(string text, double width) => new Border
    {
        Width = width,
        Height = 28,
        Background = Brushes.Black,
        BorderBrush = Brush("#262626"),
        BorderThickness = new Thickness(1),
        CornerRadius = new CornerRadius(7),
        Padding = new Thickness(12, 0),
        Child = new TextBlock { Text = text, Foreground = Brush("#6B6B6B"), FontSize = 12, VerticalAlignment = VAlign.Center }
    };

    private static Control BuildV3Note(string text) => new TextBlock { Text = text, Foreground = Brush("#6B6B6B"), FontSize = 13, FontStyle = FontStyle.Italic, Margin = new Thickness(0, 0, 0, 22) };

    private static Button BuildV3TabChip(string text, bool active, double width) => new() { Width = width, Height = 32, Content = text, Background = Brush(active ? "#121212" : "#000000"), BorderThickness = new Thickness(0), CornerRadius = new CornerRadius(5), Foreground = active ? Brushes.White : Brush("#8D8D8D"), FontSize = 12, Padding = new Thickness(12, 0) };

    private Control BuildTitleBar(
        Control logo,
        IBrush background,
        double height,
        bool compactControls,
        string? centeredTitle = null,
        bool legacyTinyControls = false)
    {
        var bar = new Grid { Height = height, Background = background };
        bar.PointerPressed += TitleBarPointerPressed;
        logo.HorizontalAlignment = HAlign.Left;
        logo.VerticalAlignment = VAlign.Center;
        bar.Children.Add(logo);
        if (centeredTitle is not null)
        {
            bar.Children.Add(new TextBlock
            {
                Text = centeredTitle,
                Foreground = Brushes.White,
                FontSize = 12,
                HorizontalAlignment = HAlign.Center,
                VerticalAlignment = VAlign.Center
            });
        }

        var width = compactControls ? 22 : legacyTinyControls ? 15 : 34;
        var controls = new StackPanel
        {
            Orientation = StackOrientation.Horizontal,
            HorizontalAlignment = HAlign.Right,
            Height = legacyTinyControls ? 19 : height,
            VerticalAlignment = legacyTinyControls ? VAlign.Top : VAlign.Stretch,
            Margin = legacyTinyControls ? new Thickness(0, 2, 5, 0) : new Thickness(0)
        };
        var buttonHeight = legacyTinyControls ? 19 : height;
        var minPath = legacyTinyControls ? "M6 10.0001L1 10.0001" : "M0.5 5.75H10.5";
        var closePath = legacyTinyControls ? "M9.5 1L2.5 8.5M9.5 8.5L2.5 1" : "M10.5 10.5L0.5 0.5M0.999999 10.5L10.5 0.500001";
        controls.Children.Add(CreateWindowIconButton(minPath, width, buttonHeight, () => WindowState = WindowState.Minimized, compactControls ? 10 : legacyTinyControls ? 9 : 11));
        if (!compactControls && !legacyTinyControls)
        {
            controls.Children.Add(CreateWindowButton("?", width, buttonHeight, static () => { }, 15));
        }
        controls.Children.Add(CreateWindowIconButton(closePath, width, buttonHeight, ReturnWorkspaceToOrbit, compactControls ? 10 : legacyTinyControls ? 9 : 11));
        bar.Children.Add(controls);
        return bar;
    }

    private Control BuildTabBar(SynapseFrontendKind kind)
    {
        var host = new Grid
        {
            Background = kind switch
            {
                SynapseFrontendKind.Blue => Brush("#222222"),
                SynapseFrontendKind.Classic2017 or SynapseFrontendKind.SynapseX => Brush(_spec.EditorBg),
                _ => Brush(_spec.TabBg)
            },
            ClipToBounds = true,
            ColumnDefinitions = kind is SynapseFrontendKind.Classic2017 or SynapseFrontendKind.SynapseX ? new ColumnDefinitions("*,78") : new ColumnDefinitions("*")
        };
        var scroll = new ScrollViewer
        {
            HorizontalScrollBarVisibility = ScrollBarVisibility.Hidden,
            VerticalScrollBarVisibility = ScrollBarVisibility.Disabled
        };
        _tabStrip = new StackPanel
        {
            Orientation = StackOrientation.Horizontal,
            Spacing = kind == SynapseFrontendKind.Blue ? 2 : kind == SynapseFrontendKind.V3 ? 5 : 0,
            Margin = kind == SynapseFrontendKind.V3 ? new Thickness(4, 0, 0, 0) : new Thickness(0),
            VerticalAlignment = kind == SynapseFrontendKind.Blue ? VAlign.Center : VAlign.Stretch
        };
        scroll.Content = _tabStrip;
        host.Children.Add(scroll);
        if (kind is SynapseFrontendKind.Classic2017 or SynapseFrontendKind.SynapseX)
        {
            Grid.SetColumn(scroll, 0);
            var toolbar = new StackPanel
            {
                Orientation = StackOrientation.Horizontal,
                HorizontalAlignment = HAlign.Right,
                VerticalAlignment = VAlign.Center,
                Spacing = 3,
                Margin = new Thickness(0, 0, 3, 0)
            };
            if (kind == SynapseFrontendKind.Classic2017)
            {
                toolbar.Children.Add(new Button
                {
                    Width = 18, Height = 16, Padding = new Thickness(0), BorderThickness = new Thickness(0),
                    Background = Brushes.Transparent, Content = CreateSvgIcon(SynapseV3IconData.Save, 14, "#C0C0C0")
                });
            }
            toolbar.Children.Add(new TextBlock { Text = "AI", Foreground = Brush("#777777"), FontSize = 10, Opacity = .4, VerticalAlignment = VAlign.Center });
            var plus = new Button
            {
                Width = 16, Height = 16, Padding = new Thickness(0), BorderThickness = new Thickness(0),
                    Background = Brushes.Transparent, Content = CreateSvgIcon("M7.5 3L7.5 12M12 7.5L3 7.5", 12, "#C0C0C0", 20, true)
            };
            plus.Click += (_, _) => AddTab(kind);
            toolbar.Children.Add(plus);
            Grid.SetColumn(toolbar, 1);
            host.Children.Add(toolbar);
        }
        RebuildTabs(kind);
        return host;
    }

    private void RebuildTabs(SynapseFrontendKind kind)
    {
        if (_tabStrip is null) return;
        _tabStrip.Children.Clear();
        foreach (var tab in _workspace.Tabs)
        {
            var active = tab.Id == _workspace.ActiveTabId;
            var height = kind switch { SynapseFrontendKind.Blue => 24, SynapseFrontendKind.V3 => 32, _ => 16 };
            var width = kind switch { SynapseFrontendKind.Blue => Math.Clamp(16 + tab.Title.Length * 6, 46, 280), SynapseFrontendKind.V3 => 159, _ => Math.Clamp(44 + tab.Title.Length * 5, 72, 160) };
            var item = new Grid
            {
                Width = width,
                Height = height,
                Background = kind is SynapseFrontendKind.Classic2017 or SynapseFrontendKind.SynapseX ? Brushes.Transparent : Brush(active ? _spec.ActiveTabBg : _spec.TabBg),
                ColumnDefinitions = kind switch
                {
                    SynapseFrontendKind.Blue => new ColumnDefinitions("*"),
                    SynapseFrontendKind.V3 => new ColumnDefinitions("24,*,25"),
                    _ => new ColumnDefinitions("*,18")
                }
            };
            var tabButton = new Button
            {
                Tag = tab.Id,
                Background = Brushes.Transparent,
                BorderThickness = new Thickness(0),
                CornerRadius = new CornerRadius(0),
                MinWidth = 0,
                MinHeight = 0,
                Padding = new Thickness(kind == SynapseFrontendKind.V3 ? 8 : kind == SynapseFrontendKind.Blue ? 10 : 5, 0),
                HorizontalContentAlignment = HAlign.Left,
                VerticalContentAlignment = VAlign.Center,
                Foreground = kind is SynapseFrontendKind.Blue or SynapseFrontendKind.V3 || active ? Brushes.White : Brush("#C0C0C0"),
                FontSize = kind == SynapseFrontendKind.V3 ? 12 : kind == SynapseFrontendKind.Blue ? 13 : 10,
                Content = kind == SynapseFrontendKind.V3
                    ? new StackPanel { Orientation = StackOrientation.Horizontal, Spacing = 10, Children = { CreateSvgIcon(SynapseV3IconData.TextAsterisk, 13, "#FFFFFF"), new TextBlock { Text = tab.Title, VerticalAlignment = VAlign.Center } } }
                    : new TextBlock { Text = tab.Title, VerticalAlignment = VAlign.Center }
            };
            Grid.SetColumnSpan(tabButton, kind == SynapseFrontendKind.V3 ? 2 : 1);
            tabButton.Click += TabClicked;
            if (kind == SynapseFrontendKind.Blue && tab.IsRenaming)
            {
                var rename = new TextBox
                {
                    Text = tab.Title,
                    Background = Brushes.Transparent,
                    BorderThickness = new Thickness(0),
                    Foreground = Brushes.White,
                    FontSize = 13,
                    Padding = new Thickness(10, 0),
                    VerticalContentAlignment = VAlign.Center
                };
                rename.KeyDown += (_, eventArgs) =>
                {
                    if (eventArgs.Key == Key.Enter)
                    {
                        FinishSynapseTabRename(tab, rename.Text, kind, true);
                        eventArgs.Handled = true;
                    }
                    else if (eventArgs.Key == Key.Escape)
                    {
                        FinishSynapseTabRename(tab, rename.Text, kind, false);
                        eventArgs.Handled = true;
                    }
                };
                rename.LostFocus += (_, _) => FinishSynapseTabRename(tab, rename.Text, kind, true);
                item.Children.Add(rename);
                Dispatcher.UIThread.Post(() =>
                {
                    rename.Focus();
                    rename.SelectAll();
                }, DispatcherPriority.Input);
            }
            else
            {
                item.Children.Add(tabButton);
            }
            if (kind is SynapseFrontendKind.Blue or SynapseFrontendKind.V3)
            {
                item.ContextMenu = BuildSynapseTabContextMenu(tab, kind);
            }
            if (kind is SynapseFrontendKind.Classic2017 or SynapseFrontendKind.SynapseX or SynapseFrontendKind.V3)
            {
                var close = new Button
                {
                    Width = kind == SynapseFrontendKind.V3 ? 11 : 16,
                    Height = height,
                    HorizontalAlignment = kind == SynapseFrontendKind.V3 ? HAlign.Right : HAlign.Stretch,
                    Margin = kind == SynapseFrontendKind.V3 ? new Thickness(0, 0, 8, 0) : new Thickness(0),
                    Padding = kind == SynapseFrontendKind.V3 ? new Thickness(0, 9, 0, 0) : new Thickness(0),
                    Background = Brushes.Transparent,
                    BorderThickness = new Thickness(0),
                    VerticalContentAlignment = kind == SynapseFrontendKind.V3 ? VAlign.Top : VAlign.Center,
                    Content = CreateSvgIcon(kind == SynapseFrontendKind.V3 ? SynapseV3IconData.WindowClose : "M8 1L1 8M8 8L1 1", kind == SynapseFrontendKind.V3 ? 11 : 9, kind == SynapseFrontendKind.V3 ? "#FFFFFF" : "#C0C0C0", kind == SynapseFrontendKind.V3 ? 11 : 20, true)
                };
                Grid.SetColumn(close, kind == SynapseFrontendKind.V3 ? 2 : 1);
                close.Click += (_, e) => { e.Handled = true; CloseTab(tab.Id, kind); };
                item.Children.Add(close);
            }
            if (kind == SynapseFrontendKind.V3)
            {
                item.Background = Brushes.Transparent;
                _tabStrip.Children.Add(new Border
                {
                    Width = width,
                    Height = height,
                    Background = Brush(active ? _spec.ActiveTabBg : _spec.TabBg),
                    CornerRadius = new CornerRadius(5),
                    Child = item
                });
            }
            else
            {
                _tabStrip.Children.Add(item);
            }
        }

        if (kind is SynapseFrontendKind.Blue or SynapseFrontendKind.V3)
        {
            var plusSize = kind == SynapseFrontendKind.Blue ? 17 : 12;
            var plus = new Button
            {
                Width = plusSize,
                Height = kind == SynapseFrontendKind.V3 ? 32 : 16,
                MinWidth = 0,
                MinHeight = 0,
                Padding = new Thickness(0),
                Background = kind == SynapseFrontendKind.Blue ? Brush("#69686B") : Brushes.Transparent,
                BorderThickness = new Thickness(0),
                CornerRadius = new CornerRadius(0),
                VerticalAlignment = kind == SynapseFrontendKind.Blue ? VAlign.Center : VAlign.Stretch,
                Content = CreateSvgIcon("M4.76515 8V1M1 4.58979H8.5", kind == SynapseFrontendKind.V3 ? 11 : 8, kind == SynapseFrontendKind.V3 ? "#898989" : "#FFFFFF", 9.5, true, 2)
            };
            plus.Click += (_, _) => AddTab(kind);
            _tabStrip.Children.Add(plus);
        }
    }

    private void CloseTab(Guid id, SynapseFrontendKind kind)
    {
        if (_workspace.Tabs.Count <= 1) return;
        ActiveTab().Content = _editorContent;
        var index = _workspace.Tabs.FindIndex(x => x.Id == id);
        if (index < 0) return;
        _workspace.Tabs.RemoveAt(index);
        if (_workspace.ActiveTabId == id)
        {
            var next = _workspace.Tabs[Math.Clamp(index - 1, 0, _workspace.Tabs.Count - 1)];
            _workspace.ActiveTabId = next.Id;
            _editorContent = next.Content;
            SetEditorContent(_editorContent);
        }
        RebuildTabs(kind);
    }

    private ContextMenu BuildSynapseTabContextMenu(
        EditorTabState tab,
        SynapseFrontendKind kind)
    {
        var menu = new ContextMenu
        {
            Background = Brush(kind == SynapseFrontendKind.Blue ? "#3D3D3D" : "#2D2D2D"),
            BorderBrush = Brush(kind == SynapseFrontendKind.Blue ? "#5A5A5A" : "#808080"),
            BorderThickness = new Thickness(1),
            Padding = new Thickness(2),
            MinWidth = kind == SynapseFrontendKind.Blue ? 150 : 199
        };
        if (kind == SynapseFrontendKind.Blue)
        {
            menu.Items.Add(CreateSynapseTabMenuItem("Rename", () =>
            {
                tab.IsRenaming = true;
                RebuildTabs(kind);
            }, 13));
            menu.Items.Add(CreateSynapseTabMenuItem(
                "Close Tab",
                () => CloseTab(tab.Id, kind),
                13,
                _workspace.Tabs.Count <= 1));
            return menu;
        }

        menu.Items.Add(CreateSynapseTabMenuItem("Undock", static () => { }, 16, true));
        menu.Items.Add(CreateSynapseTabMenuItem("Duplicate", () => DuplicateSynapseTab(tab, kind), 16));
        menu.Items.Add(CreateSynapseTabMenuItem("Execute", () => ExecuteSynapseTab(tab), 16));
        menu.Items.Add(CreateSynapseTabMenuItem("Customize", static () => { }, 16, true));
        menu.Items.Add(CreateSynapseTabMenuItem("Toggle auto-execute", static () => { }, 16, true));
        menu.Items.Add(CreateSynapseTabMenuItem(
            "Close all but this",
            () => CloseOtherSynapseTabs(tab, kind),
            16,
            _workspace.Tabs.Count <= 1));
        menu.Items.Add(new Separator());
        menu.Items.Add(CreateSynapseTabMenuItem(
            "Close Tab",
            () => CloseTab(tab.Id, kind),
            16,
            _workspace.Tabs.Count <= 1));
        return menu;
    }

    private MenuItem CreateSynapseTabMenuItem(
        string label,
        Action action,
        double fontSize,
        bool disabled = false)
    {
        var item = new MenuItem
        {
            Header = label,
            FontSize = fontSize,
            Foreground = Brush(disabled ? "#666666" : "#D4D4D4"),
            Background = Brushes.Transparent,
            IsEnabled = !disabled,
            Padding = new Thickness(10, 6)
        };
        item.Click += (_, _) => action();
        return item;
    }

    private void FinishSynapseTabRename(
        EditorTabState tab,
        string? title,
        SynapseFrontendKind kind,
        bool commit)
    {
        if (!tab.IsRenaming) return;
        tab.IsRenaming = false;
        var normalized = (title ?? string.Empty).Trim();
        if (commit && normalized.Length > 0)
        {
            tab.Title = normalized[..Math.Min(80, normalized.Length)];
        }
        RebuildTabs(kind);
    }

    private void DuplicateSynapseTab(EditorTabState tab, SynapseFrontendKind kind)
    {
        ActiveTab().Content = _editorContent;
        var duplicate = new EditorTabState
        {
            Title = tab.Title + " (Copy)",
            Extension = tab.Extension,
            Content = tab.Content
        };
        var index = _workspace.Tabs.IndexOf(tab);
        _workspace.Tabs.Insert(Math.Max(0, index + 1), duplicate);
        _workspace.ActiveTabId = duplicate.Id;
        _editorContent = duplicate.Content;
        RebuildTabs(kind);
        SetEditorContent(_editorContent);
    }

    private void ExecuteSynapseTab(EditorTabState tab)
    {
        if (!UnifiedBridgeServer.Shared.IsConnected) return;
        if (_workspace.ActiveTabId == tab.Id)
        {
            RequestEditorExecute();
            return;
        }
        UnifiedBridgeServer.Shared.EnqueueExecute(tab.Content);
    }

    private void CloseOtherSynapseTabs(EditorTabState tab, SynapseFrontendKind kind)
    {
        ActiveTab().Content = _editorContent;
        _workspace.Tabs.RemoveAll(candidate => candidate.Id != tab.Id);
        _workspace.ActiveTabId = tab.Id;
        _editorContent = tab.Content;
        RebuildTabs(kind);
        SetEditorContent(_editorContent);
    }

    private Border BuildScriptList(string background, string border, double fontSize)
    {
        var panel = new Border
        {
            Background = Brush(background),
            BorderBrush = Brush(border),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(0),
            Padding = new Thickness(3, 2),
            ClipToBounds = true
        };
        var list = new StackPanel { Spacing = 1 };
        var files = ListScripts();
        if (files.Count == 0)
        {
            list.Children.Add(new TextBlock
            {
                Text = "Add .lua files to scripts.",
                TextWrapping = TextWrapping.Wrap,
                Foreground = Brush("#B0B0B0"),
                FontSize = fontSize,
                Margin = new Thickness(2, 5)
            });
        }
        else
        {
            foreach (var path in files)
            {
                var item = CreateListButton(Path.GetFileNameWithoutExtension(path), fontSize);
                item.Click += (_, _) => OpenScript(path);
                list.Children.Add(item);
            }
        }
        panel.Child = new ScrollViewer { Content = list, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        return panel;
    }

    private Control BuildV3ScriptList()
    {
        var panel = new Border
        {
            Background = Brushes.Black,
            // The source V3 rail has no visible seam at its left edge. The
            // section dividers below provide the only intentional rules.
            BorderThickness = new Thickness(0)
        };
        var layout = new Grid { RowDefinitions = new RowDefinitions("31,5,*") };
        var searchText = new TextBox
        {
            PlaceholderText = "Search...",
            Background = Brushes.Transparent,
            BorderThickness = new Thickness(0),
            Foreground = Brush("#6F6F6E"),
            FontSize = 11,
            Padding = new Thickness(25, 0, 5, 0),
            VerticalContentAlignment = VAlign.Center
        };
        var search = new Border
        {
            Height = 31,
            Background = Brushes.Black,
            CornerRadius = new CornerRadius(3),
            Child = new Grid { Children = { searchText } }
        };
        ((Grid)search.Child).Children.Add(new Border
        {
            Width = 16,
            Height = 16,
            Margin = new Thickness(4, 0, 0, 0),
            HorizontalAlignment = HAlign.Left,
            VerticalAlignment = VAlign.Center,
            Child = CreateSvgIcon("M10.5 18A7.5 7.5 0 1 0 10.5 3A7.5 7.5 0 0 0 10.5 18ZM16 16L20.5 20.5", 16, "#868686", 24, true, 1.5)
        });
        layout.Children.Add(search);

        var sections = new StackPanel { Spacing = 0, HorizontalAlignment = HAlign.Stretch };

        // These are real disclosure sections; the old port drew chevrons but
        // left every body permanently mounted and non-interactive.
        var localContent = new StackPanel { Spacing = 0 };
        var bookmarkContent = new StackPanel { Spacing = 0 };
        var gistContent = new StackPanel { Spacing = 0 };
        _v3BookmarkContent = bookmarkContent;
        _v3GistContent = gistContent;

        void RebuildBookmarks()
        {
            bookmarkContent.Children.Clear();
            var paths = ListScripts().Where(path => _v3Bookmarks.Contains(path)).ToArray();
            var gists = _v3Gists.Where(gist => _v3Bookmarks.Contains(gist.RawUrl)).ToArray();
            if (paths.Length == 0 && gists.Length == 0)
            {
                bookmarkContent.Children.Add(BuildV3ScriptEmpty("No bookmarks yet. Hover a script or gist and click the bookmark icon."));
                return;
            }
            foreach (var path in paths) bookmarkContent.Children.Add(BuildV3ScriptRow(path, true, ToggleBookmark));
            foreach (var gist in gists) bookmarkContent.Children.Add(BuildV3GistRow(gist, ToggleBookmark));
        }

        void RebuildGists()
        {
            gistContent.Children.Clear();
            var query = searchText.Text?.Trim() ?? string.Empty;
            var entries = _v3Gists
                .Where(gist => string.IsNullOrEmpty(query) || gist.Title.Contains(query, StringComparison.OrdinalIgnoreCase) || gist.RawUrl.Contains(query, StringComparison.OrdinalIgnoreCase))
                .ToArray();
            if (entries.Length == 0)
            {
                gistContent.Children.Add(BuildV3ScriptEmpty(_v3Gists.Count == 0 ? "No gists yet. Click + and paste a raw .lua URL." : "No gists match your search."));
                return;
            }
            foreach (var gist in entries) gistContent.Children.Add(BuildV3GistRow(gist, ToggleBookmark));
        }

        void RebuildLocalScripts()
        {
            localContent.Children.Clear();
            var query = searchText.Text?.Trim() ?? string.Empty;
            var files = ListScripts()
                .Where(path => string.IsNullOrEmpty(query) || Path.GetFileNameWithoutExtension(path).Contains(query, StringComparison.OrdinalIgnoreCase))
                .ToArray();
            if (files.Length == 0)
            {
                localContent.Children.Add(BuildV3ScriptEmpty(string.IsNullOrEmpty(query) ? "No scripts found." : "No scripts match your search."));
                return;
            }
            foreach (var path in files) localContent.Children.Add(BuildV3ScriptRow(path, true, ToggleBookmark));
        }
        void ToggleBookmark(string key)
        {
            if (!_v3Bookmarks.Add(key)) _v3Bookmarks.Remove(key);
            SaveV3Bookmarks();
            RebuildLocalScripts();
            RebuildBookmarks();
            RebuildGists();
        }
        RebuildLocalScripts();
        RebuildBookmarks();
        RebuildGists();
        searchText.TextChanged += (_, _) => RebuildLocalScripts();
        searchText.TextChanged += (_, _) => RebuildBookmarks();
        searchText.TextChanged += (_, _) => RebuildGists();
        var localHeader = BuildV3ScriptSectionHeader("Local Filesystem", "#60A5FA", SynapseV3IconData.HardDrive, true, true);
        localHeader.Click += (_, _) => localContent.IsVisible = !localContent.IsVisible;
        sections.Children.Add(localHeader);
        sections.Children.Add(localContent);

        var autoContent = new StackPanel { Spacing = 0 };
        autoContent.Children.Add(BuildV3ScriptEmpty("No autoexecute scripts yet. Toggle auto-execute on a tab to add one."));
        var autoHeader = BuildV3ScriptSectionHeader("Autoexecute", "#FB923C", SynapseV3IconData.ArrowSync, true, true);
        autoHeader.Click += (_, _) => autoContent.IsVisible = !autoContent.IsVisible;
        sections.Children.Add(autoHeader);
        sections.Children.Add(autoContent);

        var bookmarkHeader = BuildV3ScriptSectionHeader("Bookmarks", "#FACC15", SynapseV3IconData.Bookmark, true, true);
        bookmarkHeader.Click += (_, _) => bookmarkContent.IsVisible = !bookmarkContent.IsVisible;
        sections.Children.Add(bookmarkHeader);
        sections.Children.Add(bookmarkContent);

        var gistHeader = BuildV3ScriptSectionHeader("Github Gists", "#4ADE80", SynapseV3IconData.GitHub, true, true, true, ShowV3GistPopup);
        gistHeader.Click += (_, _) => gistContent.IsVisible = !gistContent.IsVisible;
        sections.Children.Add(gistHeader);
        sections.Children.Add(gistContent);
        var scroll = new ScrollViewer
        {
            Content = sections,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
            HorizontalContentAlignment = HAlign.Stretch
        };
        Grid.SetRow(scroll, 2);
        layout.Children.Add(scroll);
        panel.Child = layout;
        return panel;
    }

    private Control BuildV3ScriptRow(string path, bool showBookmark, Action<string>? bookmarkAction)
    {
        var row = new Grid
        {
            Height = 26,
            Margin = new Thickness(8, 0),
            ColumnDefinitions = new ColumnDefinitions("16,5,*,80"),
            Background = Brushes.Transparent
        };
        row.Children.Add(CreateSvgIcon(SynapseV3IconData.Document, 16, "#868686"));
        var title = new TextBlock
        {
            Text = Path.GetFileNameWithoutExtension(path),
            Foreground = Brush("#F6F6F5"),
            FontSize = 12,
            TextTrimming = TextTrimming.CharacterEllipsis,
            VerticalAlignment = VAlign.Center
        };
        Grid.SetColumn(title, 2);
        row.Children.Add(title);
        var actions = new StackPanel
        {
            Orientation = StackOrientation.Horizontal,
            HorizontalAlignment = HAlign.Right,
            VerticalAlignment = VAlign.Center,
            Spacing = 1,
            IsVisible = false,
            Background = Brush("#0F0F0F")
        };
        var playIcon = CreateSvgIcon(SynapseV3IconData.Play, 14, "#F6F6F5");
        var play = new Button
        {
            Width = 18,
            Height = 18,
            Padding = new Thickness(0),
            Background = Brushes.Transparent,
            BorderThickness = new Thickness(0),
            Content = playIcon
        };
        RegisterBridgeSourceAction(play, playIcon, () => File.ReadAllTextAsync(path));
        actions.Children.Add(play);
        var open = new Button
        {
            Width = 18,
            Height = 18,
            Padding = new Thickness(0),
            Background = Brushes.Transparent,
            BorderThickness = new Thickness(0),
            Content = CreateSvgIcon(SynapseV3IconData.DocumentArrowUp, 14, "#8E8E8E")
        };
        open.Click += (_, e) => { e.Handled = true; OpenScript(path); };
        actions.Children.Add(open);
        if (showBookmark && bookmarkAction is not null)
        {
            var bookmark = new Button
            {
                Width = 18,
                Height = 18,
                Padding = new Thickness(0),
                Background = Brushes.Transparent,
                BorderThickness = new Thickness(0),
                Content = CreateSvgIcon(SynapseV3IconData.Bookmark, 14, _v3Bookmarks.Contains(path) ? "#FACC15" : "#8E8E8E")
            };
            bookmark.Click += (_, e) => { e.Handled = true; bookmarkAction(path); };
            actions.Children.Add(bookmark);
        }
        var reveal = new Button
        {
            Width = 18,
            Height = 18,
            Padding = new Thickness(0),
            Background = Brushes.Transparent,
            BorderThickness = new Thickness(0),
            Content = CreateSvgIcon(SynapseV3IconData.FolderLink, 14, "#8E8E8E")
        };
        reveal.Click += (_, e) =>
        {
            e.Handled = true;
            try
            {
                System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo("explorer.exe", $"/select,\"{path}\"") { UseShellExecute = true });
            }
            catch (System.ComponentModel.Win32Exception) { }
        };
        actions.Children.Add(reveal);
        Grid.SetColumn(actions, 3);
        row.Children.Add(actions);
        var button = new Button
        {
            Height = 26,
            HorizontalAlignment = HAlign.Stretch,
            HorizontalContentAlignment = HAlign.Stretch,
            Content = row,
            Background = Brushes.Transparent,
            BorderThickness = new Thickness(0),
            Padding = new Thickness(0)
        };
        button.Click += (_, _) => OpenScript(path);
        button.PointerEntered += (_, _) =>
        {
            row.Background = Brush("#0F0F0F");
            actions.IsVisible = true;
        };
        button.PointerExited += (_, _) =>
        {
            row.Background = Brushes.Transparent;
            actions.IsVisible = false;
        };
        return button;
    }

    private Control BuildV3GistRow(NativeGist gist, Action<string> bookmarkAction)
    {
        var row = new Grid
        {
            Height = 26,
            Margin = new Thickness(8, 0),
            ColumnDefinitions = new ColumnDefinitions("16,5,*,98"),
            Background = Brushes.Transparent
        };
        row.Children.Add(CreateSvgIcon(SynapseV3IconData.Document, 16, "#868686"));
        var title = new TextBlock
        {
            Text = gist.Title,
            Foreground = Brush("#F6F6F5"),
            FontSize = 12,
            TextTrimming = TextTrimming.CharacterEllipsis,
            VerticalAlignment = VAlign.Center
        };
        Grid.SetColumn(title, 2);
        row.Children.Add(title);
        var actions = new StackPanel
        {
            Orientation = StackOrientation.Horizontal,
            HorizontalAlignment = HAlign.Right,
            VerticalAlignment = VAlign.Center,
            Spacing = 1,
            IsVisible = false,
            Background = Brush("#0F0F0F")
        };
        var playIcon = CreateSvgIcon(SynapseV3IconData.Play, 14, "#F6F6F5");
        var play = new Button
        {
            Width = 18, Height = 18, Padding = new Thickness(0), Background = Brushes.Transparent,
            BorderThickness = new Thickness(0), Content = playIcon
        };
        RegisterBridgeSourceAction(play, playIcon, async () =>
        {
            using var client = new HttpClient();
            return await client.GetStringAsync(gist.RawUrl);
        });
        actions.Children.Add(play);
        var open = new Button
        {
            Width = 18, Height = 18, Padding = new Thickness(0), Background = Brushes.Transparent,
            BorderThickness = new Thickness(0), Content = CreateSvgIcon(SynapseV3IconData.DocumentArrowUp, 14, "#8E8E8E")
        };
        open.Click += (_, e) => { e.Handled = true; OpenGist(gist); };
        actions.Children.Add(open);
        var bookmark = new Button
        {
            Width = 18, Height = 18, Padding = new Thickness(0), Background = Brushes.Transparent,
            BorderThickness = new Thickness(0), Content = CreateSvgIcon(SynapseV3IconData.Bookmark, 14, _v3Bookmarks.Contains(gist.RawUrl) ? "#FACC15" : "#8E8E8E")
        };
        bookmark.Click += (_, e) => { e.Handled = true; bookmarkAction(gist.RawUrl); };
        actions.Children.Add(bookmark);
        var link = new Button
        {
            Width = 18, Height = 18, Padding = new Thickness(0), Background = Brushes.Transparent,
            BorderThickness = new Thickness(0), Content = CreateSvgIcon(SynapseV3IconData.FolderLink, 14, "#8E8E8E")
        };
        link.Click += (_, e) =>
        {
            e.Handled = true;
            try { System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(gist.RawUrl) { UseShellExecute = true }); }
            catch (System.ComponentModel.Win32Exception) { }
        };
        actions.Children.Add(link);
        var remove = new Button
        {
            Width = 18, Height = 18, Padding = new Thickness(0), Background = Brushes.Transparent,
            BorderThickness = new Thickness(0), Content = CreateSvgIcon("M1 1L9 9M9 1L1 9", 12, "#8E8E8E", 10, true, 1.1)
        };
        remove.Click += (_, e) => { e.Handled = true; RemoveV3Gist(gist); };
        actions.Children.Add(remove);
        Grid.SetColumn(actions, 3);
        row.Children.Add(actions);

        var button = new Button
        {
            Height = 26,
            HorizontalAlignment = HAlign.Stretch,
            HorizontalContentAlignment = HAlign.Stretch,
            Content = row,
            Background = Brushes.Transparent,
            BorderThickness = new Thickness(0),
            Padding = new Thickness(0)
        };
        button.Click += (_, _) => OpenGist(gist);
        button.PointerEntered += (_, _) => { row.Background = Brush("#0F0F0F"); actions.IsVisible = true; };
        button.PointerExited += (_, _) => { row.Background = Brushes.Transparent; actions.IsVisible = false; };
        return button;
    }

    private Border BuildV3GistPopup()
    {
        var surface = new Canvas { Width = 384, Height = 203 };
        var outer = new Border
        {
            Width = 384,
            Height = 203,
            Background = Brush("#131312"),
            BorderBrush = Brush("#808080"),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(8),
            HorizontalAlignment = HAlign.Center,
            VerticalAlignment = VAlign.Center,
            IsVisible = false,
            Child = surface
        };
        _v3GistPopup = outer;

        surface.Children.Add(new Border
        {
            Width = 382,
            Height = 137,
            Background = Brush("#212120"),
            BorderBrush = Brush("#808080"),
            BorderThickness = new Thickness(1, 1, 1, 0),
            CornerRadius = new CornerRadius(7, 7, 0, 0)
        });
        surface.Children.Add(CreateSvgIcon(SynapseV3IconData.GitHub, 20, "#FFFFFF", 24));
        Canvas.SetLeft(surface.Children[^1], 10);
        Canvas.SetTop(surface.Children[^1], 14);
        surface.Children.Add(new TextBlock
        {
            Text = "Add GitHub Gist",
            FontSize = 20,
            Foreground = Brushes.White,
            FontWeight = FontWeight.Normal
        });
        Canvas.SetLeft(surface.Children[^1], 50);
        Canvas.SetTop(surface.Children[^1], 14);
        surface.Children.Add(new TextBlock
        {
            Text = "Paste a raw link — updates when you reopen or refresh.",
            FontSize = 11,
            Foreground = Brush("#B3B3B3")
        });
        Canvas.SetLeft(surface.Children[^1], 50);
        Canvas.SetTop(surface.Children[^1], 49);

        var inputBackground = new Border
        {
            Width = 365,
            Height = 37,
            Background = Brush("#2D2D2D"),
            CornerRadius = new CornerRadius(6)
        };
        Canvas.SetLeft(inputBackground, 10);
        Canvas.SetTop(inputBackground, 92);
        surface.Children.Add(inputBackground);
        _v3GistUrlBox = new TextBox
        {
            Width = 350,
            Height = 37,
            FontSize = 14,
            Foreground = Brushes.White,
            Background = Brushes.Transparent,
            BorderThickness = new Thickness(0),
            Padding = new Thickness(0),
            PlaceholderText = "Place a URL to a raw .lua script here",
            VerticalContentAlignment = VAlign.Center
        };
        _v3GistUrlBox.TextChanged += (_, _) => UpdateV3GistPopupButtons(surface);
        _v3GistUrlBox.KeyDown += (_, e) =>
        {
            if (e.Key == Key.Enter && IsValidRawGistUrl(_v3GistUrlBox.Text))
            {
                e.Handled = true;
                AddV3GistFromPopup();
            }
            else if (e.Key == Key.Escape)
            {
                e.Handled = true;
                CloseV3GistPopup();
            }
        };
        Canvas.SetLeft(_v3GistUrlBox, 16);
        Canvas.SetTop(_v3GistUrlBox, 92);
        surface.Children.Add(_v3GistUrlBox);

        var add = new Button
        {
            Width = 50,
            Height = 32,
            Padding = new Thickness(0),
            Background = Brush("#373737"),
            BorderBrush = Brush("#3F3F3F"),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(4),
            Content = new TextBlock { Text = "Ok", FontSize = 14, Foreground = Brush("#B3B3B3"), HorizontalAlignment = HAlign.Center, VerticalAlignment = VAlign.Center }
        };
        add.Tag = "gist-add";
        add.Click += (_, _) => AddV3GistFromPopup();
        Canvas.SetLeft(add, 240);
        Canvas.SetTop(add, 154);
        surface.Children.Add(add);

        var cancel = new Button
        {
            Width = 77,
            Height = 32,
            Padding = new Thickness(0),
            Background = Brush("#373737"),
            BorderBrush = Brush("#3F3F3F"),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(4),
            Content = new TextBlock { Text = "Cancel", FontSize = 14, Foreground = Brush("#B3B3B3"), HorizontalAlignment = HAlign.Center, VerticalAlignment = VAlign.Center }
        };
        cancel.Click += (_, _) => CloseV3GistPopup();
        Canvas.SetLeft(cancel, 298);
        Canvas.SetTop(cancel, 154);
        surface.Children.Add(cancel);
        UpdateV3GistPopupButtons(surface);
        return outer;
    }

    private void UpdateV3GistPopupButtons(Canvas surface)
    {
        var add = surface.Children.OfType<Button>().FirstOrDefault(button => Equals(button.Tag, "gist-add"));
        if (add is null) return;
        var valid = IsValidRawGistUrl(_v3GistUrlBox?.Text);
        add.IsEnabled = valid;
        add.Opacity = valid ? 1 : .5;
    }

    private void ShowV3GistPopup()
    {
        if (_v3GistPopup is null) return;
        _v3GistUrlBox!.Text = string.Empty;
        _v3GistPopup.Opacity = 0;
        _v3GistPopup.RenderTransformOrigin = new RelativePoint(.5, .5, RelativeUnit.Relative);
        _v3GistPopup.RenderTransform = new ScaleTransform(.95, .95);
        // NativeWebView is a child HWND and must be taken out of the airspace
        // while this in-window Avalonia dialog is active.
        _editor.IsVisible = false;
        _v3GistPopup.IsVisible = true;
        _v3GistUrlBox.Focus();
        AnimateV3GistPopupIn(_v3GistPopup);
    }

    private static async void AnimateV3GistPopupIn(Border popup)
    {
        var started = DateTime.UtcNow;
        while (popup.IsVisible)
        {
            var t = Math.Clamp((DateTime.UtcNow - started).TotalMilliseconds / 150d, 0, 1);
            var eased = 1 - Math.Pow(1 - t, 3);
            popup.Opacity = eased;
            popup.RenderTransform = new ScaleTransform(.95 + .05 * eased, .95 + .05 * eased);
            if (t >= 1) break;
            await Task.Delay(16);
        }
    }

    private void CloseV3GistPopup()
    {
        if (_v3GistPopup is not null) _v3GistPopup.IsVisible = false;
        if (_kind == SynapseFrontendKind.V3 && _v3ActivePage == 0)
        {
            _editor.IsVisible = true;
        }
    }

    private void AddV3GistFromPopup()
    {
        var rawUrl = _v3GistUrlBox?.Text?.Trim() ?? string.Empty;
        if (!IsValidRawGistUrl(rawUrl)) return;
        if (!_v3Gists.Any(gist => string.Equals(gist.RawUrl, rawUrl, StringComparison.OrdinalIgnoreCase)))
        {
            var title = TitleFromRawGistUrl(rawUrl);
            _v3Gists.Add(new NativeGist(title, rawUrl));
            SaveNativeGists();
            RebuildV3GistContent();
        }
        CloseV3GistPopup();
    }

    private void RemoveV3Gist(NativeGist gist)
    {
        _v3Gists.Remove(gist);
        _v3Bookmarks.Remove(gist.RawUrl);
        SaveV3Bookmarks();
        try
        {
            var directory = GistsDirectory();
            if (Directory.Exists(directory))
            {
                foreach (var file in Directory.EnumerateFiles(directory, "*.txt"))
                {
                    if (string.Equals(File.ReadAllText(file).Trim(), gist.RawUrl, StringComparison.OrdinalIgnoreCase))
                        File.Delete(file);
                }
            }
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
        RebuildV3GistContent();
        RebuildV3BookmarkContent();
    }

    private void RebuildV3GistContent()
    {
        if (_v3GistContent is null) return;
        _v3GistContent.Children.Clear();
        if (_v3Gists.Count == 0)
        {
            _v3GistContent.Children.Add(BuildV3ScriptEmpty("No gists yet. Click + and paste a raw .lua URL."));
            return;
        }
        foreach (var gist in _v3Gists)
            _v3GistContent.Children.Add(BuildV3GistRow(gist, ToggleV3Bookmark));
    }

    private void ToggleV3Bookmark(string key)
    {
        if (!_v3Bookmarks.Add(key)) _v3Bookmarks.Remove(key);
        SaveV3Bookmarks();
        // Existing script-list closures rebuild their own panels. Refreshing
        // the visible bookmark/gist rails here keeps a gist added from the
        // popup immediately interactive without rebuilding the whole window.
        RebuildV3GistContent();
        RebuildV3BookmarkContent();
    }

    private void RebuildV3BookmarkContent()
    {
        if (_v3BookmarkContent is null) return;
        _v3BookmarkContent.Children.Clear();
        var paths = ListScripts().Where(path => _v3Bookmarks.Contains(path)).ToArray();
        var gists = _v3Gists.Where(gist => _v3Bookmarks.Contains(gist.RawUrl)).ToArray();
        if (paths.Length == 0 && gists.Length == 0)
        {
            _v3BookmarkContent.Children.Add(BuildV3ScriptEmpty("No bookmarks yet. Hover a script or gist and click the bookmark icon."));
            return;
        }
        foreach (var path in paths) _v3BookmarkContent.Children.Add(BuildV3ScriptRow(path, true, ToggleV3Bookmark));
        foreach (var gist in gists) _v3BookmarkContent.Children.Add(BuildV3GistRow(gist, ToggleV3Bookmark));
    }

    private async void OpenGist(NativeGist gist)
    {
        try
        {
            using var client = new HttpClient();
            var content = await client.GetStringAsync(gist.RawUrl);
            ActiveTab().Content = _editorContent;
            var tab = new EditorTabState { Title = gist.Title, Extension = ".lua", Content = content };
            _workspace.Tabs.Add(tab);
            _workspace.ActiveTabId = tab.Id;
            _editorContent = content;
            RebuildTabs(_kind);
            SetEditorContent(content);
        }
        catch (HttpRequestException)
        {
            // A failed remote fetch is intentionally silent in this frontend-only port.
        }
    }

    private void LoadNativeGists()
    {
        try
        {
            var directory = GistsDirectory();
            if (!Directory.Exists(directory)) return;
            foreach (var file in Directory.EnumerateFiles(directory, "*.txt"))
            {
                var rawUrl = File.ReadAllText(file).Trim();
                if (!IsValidRawGistUrl(rawUrl) || _v3Gists.Any(gist => string.Equals(gist.RawUrl, rawUrl, StringComparison.OrdinalIgnoreCase))) continue;
                _v3Gists.Add(new NativeGist(TitleFromRawGistUrl(rawUrl), rawUrl));
            }
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }

    private void SaveNativeGists()
    {
        try
        {
            var directory = GistsDirectory();
            Directory.CreateDirectory(directory);
            foreach (var gist in _v3Gists)
            {
                var name = string.Concat(gist.Title.Select(character => char.IsLetterOrDigit(character) ? character : '_'));
                if (string.IsNullOrWhiteSpace(name)) name = "gist";
                var file = Path.Combine(directory, name + ".txt");
                var suffix = 1;
                while (File.Exists(file) && !string.Equals(File.ReadAllText(file).Trim(), gist.RawUrl, StringComparison.OrdinalIgnoreCase))
                    file = Path.Combine(directory, $"{name}_{suffix++}.txt");
                File.WriteAllText(file, gist.RawUrl);
            }
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }

    private string GistsDirectory() => Path.Combine(Path.GetDirectoryName(_scriptsDirectory) ?? AppContext.BaseDirectory, "Github Gists");

    private string V3BookmarksFile() => Path.Combine(Path.GetDirectoryName(_scriptsDirectory) ?? AppContext.BaseDirectory, "v3-bookmarks.json");

    private void LoadV3Bookmarks()
    {
        try
        {
            var file = V3BookmarksFile();
            if (!File.Exists(file)) return;
            foreach (var key in JsonSerializer.Deserialize<string[]>(File.ReadAllText(file)) ?? [])
                if (!string.IsNullOrWhiteSpace(key)) _v3Bookmarks.Add(key);
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
        catch (JsonException) { }
    }

    private void SaveV3Bookmarks()
    {
        try { File.WriteAllText(V3BookmarksFile(), JsonSerializer.Serialize(_v3Bookmarks.OrderBy(key => key, StringComparer.OrdinalIgnoreCase))); }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }

    private static bool IsValidRawGistUrl(string? value)
        => Uri.TryCreate(value?.Trim(), UriKind.Absolute, out var uri) && (uri.Scheme == Uri.UriSchemeHttp || uri.Scheme == Uri.UriSchemeHttps);

    private static string TitleFromRawGistUrl(string rawUrl)
    {
        try
        {
            var baseName = Path.GetFileNameWithoutExtension(new Uri(rawUrl).AbsolutePath);
            if (string.IsNullOrWhiteSpace(baseName)) return "Gist";
            return string.Join(' ', baseName.Replace('-', ' ').Replace('_', ' ').Split(' ', StringSplitOptions.RemoveEmptyEntries).Select(word => char.ToUpperInvariant(word[0]) + word[1..].ToLowerInvariant()));
        }
        catch { return "Gist"; }
    }

    private static TextBlock BuildV3ScriptEmpty(string text) => new()
    {
        Text = text,
        Foreground = Brush("#8D8D8D"),
        FontSize = 11,
        TextWrapping = TextWrapping.Wrap,
        Margin = new Thickness(6, 4, 6, 4)
    };

    private Button BuildV3ScriptSectionHeader(string label, string color, string iconPath, bool open, bool topDivider, bool gistActions = false, Action? onAddGist = null)
    {
        var grid = new Grid
        {
            Height = 29,
            Margin = new Thickness(4, 0, 2, 0),
            ColumnDefinitions = gistActions ? new ColumnDefinitions("12,2,16,2,*,34") : new ColumnDefinitions("12,2,16,2,*")
        };
        var chevronOpen = CreateSvgIcon("M0.5 0.5L5 5.5L9.5 0.5", 10, color, 10, true);
        var chevronClosed = CreateSvgIcon("M0.5 0.5L5.5 5L0.5 9.5", 10, color, 10, true);
        chevronOpen.VerticalAlignment = VAlign.Center;
        chevronClosed.VerticalAlignment = VAlign.Center;
        chevronOpen.IsVisible = open;
        chevronClosed.IsVisible = !open;
        grid.Children.Add(chevronOpen);
        grid.Children.Add(chevronClosed);
        var icon = CreateSvgIcon(iconPath, 16, color);
        Grid.SetColumn(icon, 2);
        grid.Children.Add(icon);
        var text = new TextBlock
        {
            Text = label,
            Foreground = Brush(color),
            FontSize = 16,
            FontWeight = FontWeight.Normal,
            TextTrimming = TextTrimming.CharacterEllipsis,
            VerticalAlignment = VAlign.Center
        };
        Grid.SetColumn(text, 4);
        grid.Children.Add(text);
        if (gistActions)
        {
            var actions = new StackPanel
            {
                Orientation = StackOrientation.Horizontal,
                HorizontalAlignment = HAlign.Right,
                VerticalAlignment = VAlign.Center,
                Spacing = 2,
            };
            var add = new Button
            {
                Width = 14,
                Height = 18,
                Padding = new Thickness(0),
                Background = Brushes.Transparent,
                BorderThickness = new Thickness(0),
                Content = CreateSvgIcon("M5.5 11.5V0.5M0.5 6L10.5 6", 12, "#868686", 12, true)
            };
            add.Click += (_, e) => { e.Handled = true; onAddGist?.Invoke(); };
            actions.Children.Add(add);
            Grid.SetColumn(actions, 5);
            grid.Children.Add(actions);
        }
        var header = new Button
        {
            Height = 29,
            Background = Brushes.Black,
            BorderBrush = Brush("#282827"),
            BorderThickness = new Thickness(0, topDivider ? 1 : 0, 0, 1),
            Padding = new Thickness(0),
            HorizontalContentAlignment = HAlign.Stretch,
            VerticalContentAlignment = VAlign.Stretch,
            Content = grid
        };
        header.HorizontalAlignment = HAlign.Stretch;
        header.Click += (_, _) =>
        {
            var nextOpen = !chevronOpen.IsVisible;
            chevronOpen.IsVisible = nextOpen;
            chevronClosed.IsVisible = !nextOpen;
        };
        return header;
    }

    private Button CreateListButton(string label, double fontSize) => new()
    {
        Content = label,
        HorizontalContentAlignment = HAlign.Left,
        Background = Brushes.Transparent,
        BorderThickness = new Thickness(0),
        Foreground = Brush("#C0C0C0"),
        Padding = new Thickness(3, 3),
        FontSize = fontSize
    };

    private void AddAction(Grid grid, string label, int column, double fontSize, bool clears, string background = "#444444")
    {
        var button = CreateActionButton(label, double.NaN, 36, fontSize, background == "#444444" ? BlueActionBrush() : Brush(background), "#606060");
        button.HorizontalAlignment = HAlign.Stretch;
        button.VerticalAlignment = VAlign.Stretch;
        button.MinWidth = 0;
        button.MinHeight = 0;
        button.Foreground = Brush("#C3C3C3");
        button.FontFamily = new FontFamily("avares://Avalonia.Fonts.Inter/Assets#Inter");
        button.Effect = new DropShadowEffect
        {
            Color = Colors.Black,
            BlurRadius = 4,
            OffsetY = 4,
            Opacity = 0.09
        };
        button.PointerEntered += (_, _) => button.Background = label == "Attach"
            ? BlueAttachHoverBrush()
            : BlueActionHoverBrush();
        button.PointerExited += (_, _) => button.Background = BlueActionBrush();
        if (clears) button.Click += (_, _) => SetEditorContent(string.Empty);
        else if (label == "Open File") button.Click += OpenV3ScriptPicker;
        else if (label == "Save File") button.Click += SaveV3ScriptPicker;
        RegisterBridgeAction(button, label);
        Grid.SetColumn(button, column);
        grid.Children.Add(button);
    }

    private void AddClassicAction(Grid grid, string label, int column, bool clears)
    {
        var button = CreateActionButton(label, double.NaN, 39, 20, Brush("#272727"), "#2D2D2D");
        button.HorizontalAlignment = HAlign.Stretch;
        button.VerticalAlignment = VAlign.Stretch;
        button.FontFamily = new FontFamily("avares://Avalonia.Fonts.Inter/Assets#Inter");
        if (clears) button.Click += (_, _) => SetEditorContent(string.Empty);
        else if (label == "Open File") button.Click += OpenV3ScriptPicker;
        else if (label == "Script Hub") button.Click += (_, _) => OpenSynapseOriginalScriptHubWindow();
        else if (label == "Settings & Clients") button.Click += (_, _) => OpenSynapseOriginalSettingsWindow();
        RegisterBridgeAction(button, label);
        Grid.SetColumn(button, column);
        grid.Children.Add(button);
    }

    private Button CreateV3Action(
        string path,
        string label,
        bool enabled,
        bool clears,
        bool executesFile = false)
    {
        var content = new StackPanel
        {
            Orientation = StackOrientation.Horizontal,
            Spacing = 4,
            HorizontalAlignment = HAlign.Center,
            VerticalAlignment = VAlign.Center
        };
        var icon = CreateSvgIcon(path, 14, "#F6F6F5");
        content.Children.Add(icon);
        content.Children.Add(new TextBlock
        {
            Text = label,
            FontSize = 14,
            Foreground = Brush("#F6F6F5"),
            VerticalAlignment = VAlign.Center
        });
        var button = new Button
        {
            Width = 91,
            Height = 33,
            Background = Brush(enabled ? "#0D0D0D" : "#000000"),
            BorderBrush = Brush("#282827"),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(4),
            Padding = new Thickness(0),
            HorizontalContentAlignment = HAlign.Center,
            VerticalContentAlignment = VAlign.Center,
            Content = content,
            IsHitTestVisible = true
        };
        if (clears) button.Click += (_, _) => SetEditorContent(string.Empty);
        else if (enabled && label == "Open") button.Click += OpenV3ScriptPicker;
        else if (enabled && label == "Save") button.Click += SaveV3ScriptPicker;
        RegisterBridgeAction(button, executesFile ? "Execute File" : label, icon);
        return button;
    }

    private void RegisterBridgeAction(Button button, string label, Control? icon = null)
    {
        if (!label.Equals("Execute", StringComparison.OrdinalIgnoreCase) &&
            !label.Equals("Execute File", StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        var visual = icon ?? button;
        _bridgeActionButtons.Add((button, visual));
        if (label.Equals("Execute File", StringComparison.OrdinalIgnoreCase))
        {
            button.Click += async (_, _) => await ExecuteFilePickerAsync();
        }
        else
        {
            button.Click += (_, _) =>
            {
                if (UnifiedBridgeServer.Shared.IsConnected)
                {
                    RequestEditorExecute();
                }
            };
        }
        ApplyBridgeActionState(button, visual, UnifiedBridgeServer.Shared.IsConnected);
    }

    private void RegisterBridgeSourceAction(Button button, Control icon, Func<Task<string>> source)
    {
        _bridgeActionButtons.Add((button, icon));
        button.Click += async (_, eventArgs) =>
        {
            eventArgs.Handled = true;
            if (!UnifiedBridgeServer.Shared.IsConnected) return;
            try
            {
                var content = await source();
                UnifiedBridgeServer.Shared.EnqueueExecute(content);
            }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
            catch (HttpRequestException) { }
        };
        ApplyBridgeActionState(button, icon, UnifiedBridgeServer.Shared.IsConnected);
    }

    private void BridgeConnectionChanged(bool connected) =>
        Dispatcher.UIThread.Post(() => ApplyBridgeConnectionState(connected));

    private void ApplyBridgeConnectionState(bool connected)
    {
        foreach (var (button, icon) in _bridgeActionButtons)
        {
            ApplyBridgeActionState(button, icon, connected);
        }
        UpdateBlueConsoleConnection(connected);
    }

    private static void ApplyBridgeActionState(Button button, Control icon, bool connected)
    {
        button.IsEnabled = connected;
        button.Opacity = connected ? 1 : .46;
        icon.Opacity = connected ? 1 : .64;
        ToolTip.SetTip(button, connected ? "Execute" : "Execute (run Scripts/Orion Bridge.lua first)");
    }

    private void RequestEditorExecute()
    {
        if (_editorReady)
        {
            try
            {
                _editor.InvokeScript("window.orbitRequestExecute && window.orbitRequestExecute();");
                return;
            }
            catch (InvalidOperationException)
            {
                _editorReady = false;
            }
        }

        UnifiedBridgeServer.Shared.EnqueueExecute(_editorContent);
    }

    private async Task ExecuteFilePickerAsync()
    {
        if (!UnifiedBridgeServer.Shared.IsConnected) return;
        var files = await StorageProvider.OpenFilePickerAsync(new FilePickerOpenOptions
        {
            Title = "Execute script file",
            AllowMultiple = false,
            FileTypeFilter =
            [
                new FilePickerFileType("Script and text files")
                {
                    Patterns = ["*.lua", "*.luau", "*.txt", "*.md"]
                },
                FilePickerFileTypes.All
            ]
        });
        var file = files.FirstOrDefault();
        if (file is null) return;
        try
        {
            await using var stream = await file.OpenReadAsync();
            using var reader = new StreamReader(stream);
            UnifiedBridgeServer.Shared.EnqueueExecute(await reader.ReadToEndAsync());
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }

    private static Control CreateSvgIcon(string path, double size, string color, double viewSize = 20, bool stroke = false, double strokeThickness = 1.1)
    {
        // Avalonia's Viewbox normally scales a Path from its geometry bounds.
        // The source V3 icons are SVGs with fixed view boxes, so scaling from
        // bounds makes glyphs with inset artwork appear too large.  Preserve
        // the source view box explicitly, then scale that box to the target.
        var canvas = new Canvas { Width = viewSize, Height = viewSize };
        canvas.Children.Add(new ShapePath
        {
            Data = Geometry.Parse(path),
            Fill = stroke ? Brushes.Transparent : Brush(color),
            Stroke = stroke ? Brush(color) : Brushes.Transparent,
            StrokeThickness = stroke ? strokeThickness : 0,
            Stretch = Stretch.None
        });
        return new Viewbox
        {
            Width = size,
            Height = size,
            Stretch = Stretch.Uniform,
            Child = canvas
        };
    }

    private static Button CreateSvgWindowButton(string path, double size, Action action, double right, double top)
    {
        var button = new Button
        {
            Width = 24,
            Height = 24,
            Content = CreateSvgIcon(path, size, "#FFFFFF", 11, true, path == SynapseV3IconData.WindowMinimize ? 1.3 : 1.1),
            Background = Brushes.Transparent,
            BorderThickness = new Thickness(0),
            Padding = new Thickness(0)
        };
        Canvas.SetLeft(button, 106 - right - 10 - 7);
        Canvas.SetTop(button, top - 7);
        button.Click += (_, _) => action();
        return button;
    }

    private static Button CreateActionButton(string label, double width, double height, double fontSize, IBrush background, string border)
    {
        return new Button
        {
            Width = width,
            Height = height,
            Content = label,
            Background = background,
            BorderBrush = Brush(border),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(0),
            Foreground = Brushes.White,
            Padding = new Thickness(2, 0),
            HorizontalContentAlignment = HAlign.Center,
            VerticalContentAlignment = VAlign.Center,
            FontSize = fontSize,
            FontWeight = FontWeight.Normal
        };
    }

    private static IBrush BlueActionBrush() => new LinearGradientBrush
    {
        StartPoint = new RelativePoint(0, 0, RelativeUnit.Relative),
        EndPoint = new RelativePoint(0, 1, RelativeUnit.Relative),
        GradientStops = new GradientStops
        {
            new(Color.Parse("#494949"), 0),
            new(Color.Parse("#404040"), 1)
        }
    };

    private static IBrush BlueActionHoverBrush() => new LinearGradientBrush
    {
        StartPoint = new RelativePoint(0, 0, RelativeUnit.Relative),
        EndPoint = new RelativePoint(0, 1, RelativeUnit.Relative),
        GradientStops = new GradientStops
        {
            new(Color.Parse("#515151"), 0),
            new(Color.Parse("#484848"), 1)
        }
    };

    private static IBrush BlueAttachHoverBrush() => new LinearGradientBrush
    {
        StartPoint = new RelativePoint(0, 0, RelativeUnit.Relative),
        EndPoint = new RelativePoint(0, 1, RelativeUnit.Relative),
        GradientStops = new GradientStops
        {
            new(Color.Parse("#2D4191"), 0),
            new(Color.Parse("#233EA6"), 1)
        }
    };

    private static Button CreateGlyphButton(string glyph, double width, double height, string background, double fontSize)
    {
        return new Button
        {
            Width = width,
            Height = height,
            Content = new TextBlock
            {
                Text = glyph,
                FontFamily = new FontFamily("Segoe MDL2 Assets"),
                FontSize = fontSize,
                Foreground = Brushes.White,
                HorizontalAlignment = HAlign.Center,
                VerticalAlignment = VAlign.Center
            },
            Background = Brush(background),
            BorderThickness = new Thickness(0),
            Padding = new Thickness(0)
        };
    }

    private static Button CreateBlueNavButton(IEnumerable<string> pathData, bool active)
    {
        var canvas = new Canvas { Width = 60, Height = 64 };
        foreach (var data in pathData)
        {
            canvas.Children.Add(new ShapePath
            {
                Data = Geometry.Parse(data),
                Stroke = Brushes.White,
                StrokeThickness = 2,
                StrokeLineCap = PenLineCap.Round,
                Fill = Brushes.Transparent
            });
        }

        return new Button
        {
            Width = 60,
            Height = 64,
            Content = canvas,
            Background = Brush(active ? "#404040" : "#383838"),
            BorderThickness = new Thickness(0),
            Padding = new Thickness(0)
        };
    }

    private static Button CreateWindowButton(string label, double width, double height, Action action, double fontSize)
    {
        var button = new Button
        {
            Width = width,
            Height = height,
            Content = label,
            Background = Brushes.Transparent,
            BorderThickness = new Thickness(0),
            Foreground = Brushes.White,
            FontSize = fontSize,
            Padding = new Thickness(0),
            HorizontalContentAlignment = HAlign.Center,
            VerticalContentAlignment = VAlign.Center
        };
        button.Click += (_, _) => action();
        return button;
    }

    private static Button CreateWindowIconButton(string path, double width, double height, Action action, double iconSize)
    {
        var button = new Button
        {
            Width = width,
            Height = height,
            Content = CreateSvgIcon(path, iconSize, "#FFFFFF", 11, true),
            Background = Brushes.Transparent,
            BorderThickness = new Thickness(0),
            Padding = new Thickness(0),
            HorizontalContentAlignment = HAlign.Center,
            VerticalContentAlignment = VAlign.Center
        };
        button.Click += (_, _) => action();
        return button;
    }

    private static Image CreateLogo(string uri, double width, double height, Thickness margin)
    {
        var image = new Image
        {
            Source = new Bitmap(AssetLoader.Open(new Uri(uri))),
            Width = width,
            Height = height,
            Margin = margin,
            Stretch = Stretch.Uniform
        };
        RenderOptions.SetBitmapInterpolationMode(image, BitmapInterpolationMode.HighQuality);
        return image;
    }

    internal static Control CreateSynapseXLogo()
    {
        var source = new Canvas { Width = 741.0603, Height = 611.33087 };
        var translation = new TranslateTransform(-120.73973, -183.44912);
        source.Children.Add(new ShapePath
        {
            Data = Geometry.Parse("M301.98 183.54C376.3 183.49 450.62 183.49 524.94 183.47C542.69 183.57 560.46 183.28 578.21 183.62C578.11 224.32 578.16 265.03 578.18 305.73C487.8 305.85 397.42 305.71 307.04 305.75C301.28 305.61 295.5 306.07 289.88 307.32C272.51 311.2 257.23 323.2 249.16 339.04C243.05 350.88 241.06 364.76 243.46 377.85C246.38 394.58 256.78 409.72 271.14 418.71C280.59 424.7 291.78 427.96 302.97 427.88C341.31 427.95 379.66 427.8 418 427.96C429.01 427.81 440.03 427.76 451.02 428.46C493.09 431.22 533.81 449.38 564.22 478.53C594.92 507.75 615.01 547.87 619.71 590.01C624.69 631.63 614.89 674.84 592.19 710.11C570.28 744.51 536.66 771.4 498.03 784.65C478.47 791.48 457.73 794.86 437.02 794.7C345.9 794.73 254.78 794.75 163.67 794.78C163.65 753.98 163.69 713.18 163.65 672.38C250.78 672.4 337.91 672.44 425.04 672.43C434.34 672.32 443.81 673.06 452.91 670.63C470.45 666.42 485.64 653.82 493.28 637.53C500.41 622.69 501.13 604.95 495.19 589.58C486.85 567.03 464.14 550.61 440.02 550.29C394.01 550.19 348.01 550.31 302 550.23C262.92 549.99 224.05 536.77 193.04 512.95C173.59 498.1 157.06 479.38 144.95 458.1C120.73 416.19 114.3 364.47 127.39 317.88C136.03 286.17 153.56 256.98 177.33 234.3C210.37 202.3 255.95 183.64 301.98 183.54Z"),
            Fill = Brushes.White,
            RenderTransform = translation
        });
        source.Children.Add(new ShapePath
        {
            Data = Geometry.Parse("M621.09 184.56C641.33 184.43 661.57 184.57 681.8 184.61C701.63 211.77 721.51 238.89 741.47 265.94C761.4 238.85 781.33 211.76 801.18 184.6C821.38 184.54 841.59 184.45 861.8 184.55C831.87 225.35 801.86 266.11 772.1 307.04C772.2 307.38 772.4 308.07 772.49 308.41C802.22 349 831.96 389.58 861.74 430.13C841.54 430.2 821.35 430.14 801.15 430.16C781.16 403.11 761.53 375.77 741.33 348.89C728 367.07 714.65 385.23 701.33 403.42C694.62 412.26 688.43 421.57 681.44 430.14C661.35 430.18 641.26 430.17 621.17 430.14C650.93 389.58 680.73 349.03 710.44 308.42C711.6 307.41 710.25 306.23 709.72 305.35C680.13 265.12 650.67 224.8 621.09 184.56Z"),
            Fill = Brush("#FF6A00"),
            RenderTransform = translation
        });
        return new Viewbox
        {
            Width = 23,
            Height = 18,
            Margin = new Thickness(8, 0, 0, 0),
            Stretch = Stretch.Uniform,
            Child = source
        };
    }

    private static IBrush BlueTitleBrush()
    {
        return new LinearGradientBrush
        {
            StartPoint = new RelativePoint(0, 0, RelativeUnit.Relative),
            EndPoint = new RelativePoint(0, 1, RelativeUnit.Relative),
            GradientStops = new GradientStops
            {
                new(Color.Parse("#233DA4"), 0),
                new(Color.Parse("#323F89"), 1)
            }
        };
    }

    private void TitleBarPointerPressed(object? sender, PointerPressedEventArgs e)
    {
        if (e.GetCurrentPoint(this).Properties.IsLeftButtonPressed)
        {
            BeginMoveDrag(e);
        }
    }

    private static readonly (string Title, string Line1, string Line2)[] BlueTooltipCopy =
    [
        ("Execution", "Create and run scripts in the current", "instance."),
        ("Script Hub", "Execute pre-made scripts by the community", "and ScriptBlox"),
        ("Console", "Integrated Synapse console.", ""),
        ("Options", "Tweak various preferences that modify", "Synapse."),
        ("Theme Control Panel", "Customise your theming with precise and", "clear control")
    ];

    private void ShowV3Page(int index)
    {
        if (_v3Pages.Count == 0) return;
        index = Math.Clamp(index, 0, _v3Pages.Count - 1);
        _v3ActivePage = index;
        _editor.IsVisible = index == 0 && _v3GistPopup?.IsVisible != true;
        for (var i = 0; i < _v3Pages.Count; i++)
        {
            _v3Pages[i].IsVisible = i == index;
            if (i == index)
            {
                _v3Pages[i].Opacity = 0;
                AnimateOpacity(_v3Pages[i], 1, 220);
            }
        }
        foreach (var underline in _v3Underlines)
        {
            underline.Background = Brushes.Transparent;
        }
        for (var i = 0; i < _v3NavIcons.Count; i++)
        {
            var scale = i == index ? 1.02 : 1;
            _v3NavIcons[i].RenderTransform = new ScaleTransform(scale, scale);
        }
        if (index >= 0 && index < _v3Underlines.Count)
        {
            _v3Underlines[index].Background = Brushes.White;
        }
    }

    private void OnOpened(object? sender, EventArgs e)
    {
        if (_sourceAssigned) return;
        _sourceAssigned = true;
        if (_kind == SynapseFrontendKind.Blue && _blueInitializationActive)
        {
            StartBlueInitializationAnimation();
            return;
        }
        if (_shellChrome is not null)
        {
            var duration = _kind == SynapseFrontendKind.SynapseX ? 700 : 0;
            if (duration > 0)
            {
                AnimateOpacity(_shellChrome, 1, duration);
                _ = AssignEditorSourceAfterAsync(duration);
            }
            else
            {
                _shellChrome.Opacity = 1;
                AssignEditorSource();
            }
        }
        else AssignEditorSource();
    }

    private async Task AssignEditorSourceAfterAsync(int delayMs)
    {
        await Task.Delay(delayMs);
        if (!Dispatcher.UIThread.CheckAccess())
        {
            Dispatcher.UIThread.Post(AssignEditorSource, DispatcherPriority.Render);
            return;
        }
        AssignEditorSource();
    }

    private void AssignEditorSource()
    {
        var builder = new UriBuilder(_monacoAddress)
        {
            Query = "bg=" + Uri.EscapeDataString(_spec.EditorBg) +
                (_kind == SynapseFrontendKind.Blue ? "&theme=blue" : string.Empty)
        };
        _editor.Source = builder.Uri;
    }

    private static async void AnimateOpacity(Control target, double destination, int durationMs)
    {
        var initial = target.Opacity;
        var started = DateTime.UtcNow;
        while (true)
        {
            var elapsed = (DateTime.UtcNow - started).TotalMilliseconds;
            var t = Math.Clamp(elapsed / durationMs, 0, 1);
            // Smooth source-like ease-in/out without introducing a compositor dependency.
            var eased = t * t * (3 - 2 * t);
            target.Opacity = initial + (destination - initial) * eased;
            if (t >= 1) break;
            await Task.Delay(16);
        }
    }

    private void OnClosed(object? sender, EventArgs e)
    {
        CancelBlueInitializationAnimation();
        DisposeV3ExactPages();
        DisposeBluePages();
        CloseSynapseXCompanionWindows();
        UnifiedBridgeServer.Shared.ConnectionChanged -= BridgeConnectionChanged;
        UnifiedBridgeServer.Shared.LogReceived -= BridgeLogReceived;
        if (!_returnStarted)
        {
            ReturnWorkspaceToOrbit();
        }
    }

    private void OpenSynapseXOptionsWindow()
    {
        if (_kind != SynapseFrontendKind.SynapseX)
        {
            return;
        }

        if (_synapseXOptionsWindow is { } existing)
        {
            existing.Activate();
            return;
        }

        var window = new SynapseXOptionsWindow(this);
        _synapseXOptionsWindow = window;
        window.Closed += (_, _) => _synapseXOptionsWindow = null;
        window.Show(this);
        window.Activate();
    }

    private void OpenSynapseXScriptHubWindow()
    {
        if (_kind != SynapseFrontendKind.SynapseX)
        {
            return;
        }

        if (_synapseXScriptHubWindow is { } existing)
        {
            existing.Activate();
            return;
        }

        var window = new SynapseXScriptHubWindow(this);
        _synapseXScriptHubWindow = window;
        window.Closed += (_, _) => _synapseXScriptHubWindow = null;
        window.Show(this);
        window.Activate();
    }

    private void CloseSynapseXCompanionWindows()
    {
        _synapseXOptionsWindow?.Close();
        _synapseXOptionsWindow = null;
        _synapseXScriptHubWindow?.Close();
        _synapseXScriptHubWindow = null;
        _synapseOriginalSettingsWindow?.Close();
        _synapseOriginalSettingsWindow = null;
        _synapseOriginalScriptHubWindow?.Close();
        _synapseOriginalScriptHubWindow = null;
    }

    private void OpenSynapseOriginalSettingsWindow()
    {
        if (_kind != SynapseFrontendKind.Classic2017)
        {
            return;
        }

        if (_synapseOriginalSettingsWindow is { } existing)
        {
            existing.Activate();
            return;
        }

        var window = new SynapseOriginalSettingsWindow(this);
        _synapseOriginalSettingsWindow = window;
        window.Closed += (_, _) => _synapseOriginalSettingsWindow = null;
        window.Show(this);
        window.Activate();
    }

    private void OpenSynapseOriginalScriptHubWindow()
    {
        if (_kind != SynapseFrontendKind.Classic2017)
        {
            return;
        }

        if (_synapseOriginalScriptHubWindow is { } existing)
        {
            existing.Activate();
            return;
        }

        var window = new SynapseOriginalScriptHubWindow(this);
        _synapseOriginalScriptHubWindow = window;
        window.Closed += (_, _) => _synapseOriginalScriptHubWindow = null;
        window.Show(this);
        window.Activate();
    }

    internal void ApplySynapseXTopMostPreference(bool enabled)
    {
        Topmost = enabled;
        if (_synapseXOptionsWindow is not null)
        {
            _synapseXOptionsWindow.Topmost = enabled;
        }
        if (_synapseXScriptHubWindow is not null)
        {
            _synapseXScriptHubWindow.Topmost = enabled;
        }
    }

    internal void ApplySynapseXResizablePreference(bool enabled)
    {
        CanResize = enabled;
        MaxWidth = enabled ? double.PositiveInfinity : _spec.Width;
        MaxHeight = enabled ? double.PositiveInfinity : _spec.Height;
        _synapseXOptionsWindow?.ApplyResizablePreference(enabled);
        _synapseXScriptHubWindow?.ApplyResizablePreference(enabled);
    }

    internal void ApplySynapseOriginalTopMostPreference(bool enabled)
    {
        Topmost = enabled;
        if (_synapseOriginalSettingsWindow is not null)
        {
            _synapseOriginalSettingsWindow.Topmost = enabled;
        }
        if (_synapseOriginalScriptHubWindow is not null)
        {
            _synapseOriginalScriptHubWindow.Topmost = enabled;
        }
    }

    internal void ApplySynapseOriginalResizablePreference(bool enabled)
    {
        CanResize = enabled;
        MaxWidth = enabled ? double.PositiveInfinity : _spec.Width;
        MaxHeight = enabled ? double.PositiveInfinity : _spec.Height;
        _synapseOriginalSettingsWindow?.ApplyResizablePreference(enabled);
        _synapseOriginalScriptHubWindow?.ApplyResizablePreference(enabled);
    }

    private void TabClicked(object? sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: Guid id }) return;
        ActiveTab().Content = _editorContent;
        _workspace.ActiveTabId = id;
        _editorContent = ActiveTab().Content;
        RebuildTabs(_kind);
        SetEditorContent(_editorContent);
    }

    private void AddTab(SynapseFrontendKind kind)
    {
        ActiveTab().Content = _editorContent;
        var tab = new EditorTabState { Title = $"Script {_workspace.Tabs.Count + 1}", Extension = ".lua" };
        _workspace.Tabs.Add(tab);
        _workspace.ActiveTabId = tab.Id;
        _editorContent = string.Empty;
        RebuildTabs(kind);
        SetEditorContent(string.Empty);
    }

    private void OpenScript(string path)
    {
        try
        {
            ActiveTab().Content = _editorContent;
            var tab = new EditorTabState
            {
                Title = Path.GetFileNameWithoutExtension(path),
                Extension = Path.GetExtension(path),
                Content = File.ReadAllText(path)
            };
            _workspace.Tabs.Add(tab);
            _workspace.ActiveTabId = tab.Id;
            _editorContent = tab.Content;
            RebuildTabs(_kind);
            SetEditorContent(tab.Content);
        }
        catch (IOException)
        {
            // UI preservation keeps local file failures non-modal.
        }
    }

    private async void OpenV3ScriptPicker(object? sender, RoutedEventArgs e)
    {
        var files = await StorageProvider.OpenFilePickerAsync(new FilePickerOpenOptions
        {
            Title = "Open script",
            AllowMultiple = false,
            FileTypeFilter =
            [
                new FilePickerFileType("Script and text files") { Patterns = ["*.lua", "*.luau", "*.txt", "*.md", "*.json", "*.js", "*.ts"] },
                FilePickerFileTypes.All
            ]
        });
        var file = files.FirstOrDefault();
        if (file is null) return;
        try
        {
            await using var stream = await file.OpenReadAsync();
            using var reader = new StreamReader(stream);
            ActiveTab().Content = _editorContent;
            var tab = new EditorTabState
            {
                Title = Path.GetFileNameWithoutExtension(file.Name),
                Extension = Path.GetExtension(file.Name),
                Content = await reader.ReadToEndAsync()
            };
            _workspace.Tabs.Add(tab);
            _workspace.ActiveTabId = tab.Id;
            _editorContent = tab.Content;
            RebuildTabs(_kind);
            SetEditorContent(tab.Content);
        }
        catch (IOException) { }
    }

    private async void SaveV3ScriptPicker(object? sender, RoutedEventArgs e)
    {
        var active = ActiveTab();
        var extension = string.IsNullOrWhiteSpace(active.Extension) ? ".lua" : active.Extension;
        IStorageFolder? startFolder = null;
        try
        {
            Directory.CreateDirectory(_scriptsDirectory);
            startFolder = await StorageProvider.TryGetFolderFromPathAsync(new Uri(_scriptsDirectory));
        }
        catch (IOException) { }
        var file = await StorageProvider.SaveFilePickerAsync(new FilePickerSaveOptions
        {
            Title = "Save script",
            SuggestedStartLocation = startFolder,
            SuggestedFileName = active.Title + extension,
            DefaultExtension = extension.TrimStart('.'),
            FileTypeChoices =
            [
                new FilePickerFileType("Lua script") { Patterns = ["*.lua", "*.luau"] },
                new FilePickerFileType("Text file") { Patterns = ["*.txt", "*.md"] },
                FilePickerFileTypes.All
            ],
            ShowOverwritePrompt = true
        });
        if (file is null) return;
        try
        {
            await using var stream = await file.OpenWriteAsync();
            if (stream.CanSeek) stream.SetLength(0);
            await using var writer = new StreamWriter(stream);
            await writer.WriteAsync(_editorContent);
            active.Title = Path.GetFileNameWithoutExtension(file.Name);
            active.Extension = Path.GetExtension(file.Name);
            RebuildTabs(_kind);
        }
        catch (IOException) { }
    }

    private List<string> ListScripts()
    {
        try
        {
            return Directory.EnumerateFiles(_scriptsDirectory)
                .Where(path => !Path.GetFileName(path).StartsWith('.'))
                .OrderBy(Path.GetFileName, StringComparer.OrdinalIgnoreCase)
                .ToList();
        }
        catch (IOException)
        {
            return [];
        }
    }

    private void SetEditorContent(string content)
    {
        _editorContent = content;
        ActiveTab().Content = content;
        if (!_editorReady) return;
        try
        {
            _editor.InvokeScript($"window.orbitSetContent && window.orbitSetContent({JsonSerializer.Serialize(content)}, 'lua');");
        }
        catch (InvalidOperationException)
        {
            // Monaco is still completing its native-webview handoff.
        }
    }

    private void HandleEditorMessage(string? message)
    {
        if (string.IsNullOrWhiteSpace(message)) return;
        try
        {
            using var payload = JsonDocument.Parse(message);
            var root = payload.RootElement;
            if (!root.TryGetProperty("type", out var type)) return;
            if (type.GetString() == "ready")
            {
                _editorReady = true;
                SetEditorContent(_editorContent);
            }
            else if (type.GetString() == "contentChanged" && root.TryGetProperty("content", out var content))
            {
                _editorContent = content.GetString() ?? string.Empty;
                ActiveTab().Content = _editorContent;
            }
            else if (type.GetString() == "contentChangedDelta" &&
                root.TryGetProperty("changes", out var changes) &&
                EditorContentDelta.TryApply(changes, _editorContent, out var updatedContent))
            {
                _editorContent = updatedContent;
                ActiveTab().Content = _editorContent;
            }
            else if (type.GetString() == "executeRequested" && root.TryGetProperty("content", out var executeContent))
            {
                _editorContent = executeContent.GetString() ?? string.Empty;
                ActiveTab().Content = _editorContent;
                if (UnifiedBridgeServer.Shared.IsConnected)
                {
                    UnifiedBridgeServer.Shared.EnqueueExecute(_editorContent);
                }
            }
        }
        catch (JsonException)
        {
            // Ignore unrelated browser messages.
        }
    }

    private EditorTabState ActiveTab()
    {
        var active = _workspace.Tabs.FirstOrDefault(tab => tab.Id == _workspace.ActiveTabId) ?? _workspace.Tabs[0];
        _workspace.ActiveTabId = active.Id;
        return active;
    }

    private void ReturnWorkspaceToOrbit()
    {
        if (_returnStarted) return;
        _returnStarted = true;
        ActiveTab().Content = _editorContent;
        _returnToOrbit(_workspace.CloneDetached());
    }

    private void CloseV3Window()
    {
        _returnStarted = true;
        if (Application.Current?.ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
        {
            desktop.Shutdown();
            return;
        }
        Close();
    }

    private static ShellSpec SpecFor(SynapseFrontendKind kind) => kind switch
    {
        SynapseFrontendKind.Blue => new(714, 393, 55, "#222222", "#2F2F2F", "#2D2D2D", "#474747", "#535353", "#FFFFFF", 0),
        SynapseFrontendKind.Classic2017 => new(838, 372, 58, "#232323", "#282828", "#232323", "#323232", "#3C3C3C", "#FFFFFF", 0),
        SynapseFrontendKind.SynapseX => new(801, 355, 30, "#333333", "#3C3C3C", "#1E1E1E", "#1E1E1E", "#1E1E1E", "#FFFFFF", 0),
        _ => new(961, 461, 44, "#000000", "#000000", "#000000", "#000000", "#121212", "#FFFFFF", 7)
    };

    private static string NameFor(SynapseFrontendKind kind) => kind switch
    {
        SynapseFrontendKind.Blue => "Synapse Blue",
        SynapseFrontendKind.Classic2017 => "Synapse 2017",
        SynapseFrontendKind.SynapseX => "Synapse X",
        _ => "Synapse V3"
    };

    private static SolidColorBrush Brush(string value) => new(Color.Parse(value));

    private static EditorWorkspaceState CreateFallbackWorkspace()
    {
        var tab = new EditorTabState { Title = "Script", Extension = ".lua" };
        return new EditorWorkspaceState { Tabs = [tab], ActiveTabId = tab.Id };
    }
}

