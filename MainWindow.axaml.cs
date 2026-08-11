using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.Markup.Xaml;
using Avalonia.Media;
using Avalonia.Media.Immutable;
using Avalonia.Threading;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text.Json;
using ShapePath = Avalonia.Controls.Shapes.Path;

namespace OrbitAvalonia;

public sealed partial class MainWindow : Window
{
    private readonly MonacoStaticServer _monacoServer;
    private readonly UnifiedBridgeServer _bridgeServer = UnifiedBridgeServer.Shared;
    private readonly ScriptHubService _scriptHubService = new();
    private readonly ObservableCollection<ScriptHubCardModel> _scriptHubCards = [];
    private readonly Grid _mainInterface;
    private readonly Grid _loadingInterface;
    private readonly Canvas _loadingElements;
    private readonly Canvas _loadingProgressArtwork;
    private readonly TranslateTransform _loadingProgressTransform;
    private readonly TextBlock _cursorPositionText;
    private readonly Grid _monacoOverlayGrid;
    private readonly Border _monacoHost;
    private readonly Canvas _scriptHubPage;
    private readonly Canvas _scriptHubContentArea;
    private readonly TranslateTransform _scriptHubContentTranslation;
    private readonly ItemsControl _scriptHubCardsControl;
    private readonly ScrollViewer _scriptHubCardsScrollViewer;
    private readonly TextBox _scriptHubSearchBox;
    private readonly TextBlock _scriptHubStateText;
    private readonly TextBlock _scriptBloxSourceText;
    private readonly TextBlock _robloxScriptsSourceText;
    private readonly TextBlock _haxHellSourceText;
    private readonly TextBlock _rscriptsSourceText;
    private readonly Viewbox _scriptHubSelectedTick;
    private readonly Grid _scriptBloxWarningOverlay;
    private readonly Border _scriptBloxWarningBackdrop;
    private readonly Button _scriptBloxBackdropButton;
    private readonly Viewbox _scriptBloxWarningPopup;
    private readonly ScaleTransform _scriptBloxWarningScale;
    private readonly TranslateTransform _scriptBloxWarningTranslation;
    private readonly Button _scriptBloxContinueButton;
    private readonly TextBlock _scriptBloxContinueText;
    private readonly TextBlock _scriptBloxWarningTitle;
    private readonly TextBlock _scriptBloxWarningLabel;
    private readonly TextBlock _scriptBloxWarningDescription;
    private readonly Button _scriptBloxDismissButton;
    private readonly Canvas _robotPage;
    private readonly Canvas _robotDrawer;
    private readonly Border _robotInputBar;
    private readonly Canvas _themesPage;
    private readonly Canvas _pluginsPage;
    private readonly Canvas _settingsPage;
    private readonly Border _settingsSurface;
    private readonly ShapePath _editorNavIcon;
    private readonly ShapePath _scriptHubNavIcon;
    private readonly ShapePath _robotNavIcon;
    private readonly ShapePath _themesNavIcon;
    private readonly ShapePath _pluginsNavIcon;
    private readonly ShapePath _settingsNavInner;
    private readonly ShapePath _settingsNavOuter;
    private readonly CancellationTokenSource _startupCancellation = new();
    private readonly HashSet<string> _scriptHubCardKeys = new(StringComparer.Ordinal);
    private CancellationTokenSource? _scriptHubLoadCancellation;
    private CancellationTokenSource? _scriptHubSearchCancellation;
    private CancellationTokenSource? _scriptBloxWarningCancellation;
    private CancellationTokenSource? _scriptBloxWarningAnimationCancellation;
    private DispatcherTimer? _bridgeConnectionRefreshTimer;
    private ScriptHubProvider _scriptHubProvider = ScriptHubProvider.RobloxScripts;
    private bool _scriptHubHasLoaded;
    private bool _scriptHubHasMore;
    private bool _scriptHubPageLoading;
    private int _scriptHubCurrentPage;
    private int _scriptHubLoadVersion;
    private bool _bridgeConnected;
    private bool _showingPrototypeDisclaimer;
    private bool _prototypeDisclaimerAcknowledged;

    private const string ScriptBloxWarningTitle = "Security Warning";
    private const string ScriptBloxWarningLabel = "SCRIPTBLOX SAFETY WARNING";
    private const string ScriptBloxWarningDescription = "ScriptBlox has a history of security incidents where scripts displayed inappropriate images in search. Scripts there are generally not vetted and may contain malware or harmful code. Proceed with caution.";
    private const string PrototypeDisclaimerTitle = "Welcome To Orion";
    private const string PrototypeDisclaimerLabel = "ORION PROTOTYPE - EXPECTED ISSUES";
    private const string PrototypeDisclaimerDescription = "Orion is in an early pre alpha state. Features and UIs are actively being integrated.";

    private const double MainWindowWidth = 996;
    private const double MainWindowHeight = 620;
    private const double ProgressTravel = 223;

    private static readonly IBrush SelectedPageBrush = new ImmutableSolidColorBrush(Color.Parse("#FFFFFF"));
    private static readonly IBrush InactivePageBrush = new ImmutableSolidColorBrush(Color.Parse("#7D7D80"));

    public MainWindow()
    {
        AvaloniaXamlLoader.Load(this);
        _prototypeDisclaimerAcknowledged = true;
        Topmost = OrbitPreferences.TopMostEnabled;

        _mainInterface = this.FindControl<Grid>("MainInterface") ?? new Grid();
        _loadingInterface = this.FindControl<Grid>("LoadingInterface") ?? new Grid();
        _loadingElements = this.FindControl<Canvas>("LoadingElements") ?? new Canvas();
        _loadingProgressArtwork = this.FindControl<Canvas>("LoadingProgressArtwork") ?? new Canvas();
        var loadingProgressSegment = this.FindControl<Border>("LoadingProgressSegment") ?? new Border();
        _loadingProgressTransform = loadingProgressSegment.RenderTransform as TranslateTransform
            ?? new TranslateTransform();
        loadingProgressSegment.RenderTransform = _loadingProgressTransform;

        var monacoDirectory = Path.Combine(
            AppContext.BaseDirectory,
            "MonacoPreview");
        _monacoServer = new MonacoStaticServer(monacoDirectory);

        _monacoWebView = this.FindControl<NativeWebView>("MonacoWebView") ?? new NativeWebView();
        _cursorPositionText = this.FindControl<TextBlock>("CursorPositionText") ?? new TextBlock();
        _monacoOverlayGrid = this.FindControl<Grid>("MonacoOverlayGrid") ?? new Grid();
        _monacoHost = this.FindControl<Border>("MonacoHost") ?? new Border();
        _scriptHubPage = this.FindControl<Canvas>("ScriptHubPage") ?? new Canvas();
        _scriptHubContentArea = this.FindControl<Canvas>("ScriptHubContentArea") ?? new Canvas();
        _scriptHubContentTranslation = _scriptHubContentArea.RenderTransform as TranslateTransform
            ?? new TranslateTransform();
        _scriptHubCardsControl = this.FindControl<ItemsControl>("ScriptHubCards") ?? new ItemsControl();
        _scriptHubCardsScrollViewer = this.FindControl<ScrollViewer>("ScriptHubCardsScrollViewer") ?? new ScrollViewer();
        _scriptHubSearchBox = this.FindControl<TextBox>("ScriptHubSearchBox") ?? new TextBox();
        _scriptHubStateText = this.FindControl<TextBlock>("ScriptHubStateText") ?? new TextBlock();
        _scriptBloxSourceText = this.FindControl<TextBlock>("ScriptBloxSourceText") ?? new TextBlock();
        _robloxScriptsSourceText = this.FindControl<TextBlock>("RobloxScriptsSourceText") ?? new TextBlock();
        _haxHellSourceText = this.FindControl<TextBlock>("HaxHellSourceText") ?? new TextBlock();
        _rscriptsSourceText = this.FindControl<TextBlock>("RscriptsSourceText") ?? new TextBlock();
        _scriptHubSelectedTick = this.FindControl<Viewbox>("ScriptHubSelectedTick") ?? new Viewbox();
        _scriptBloxWarningOverlay = this.FindControl<Grid>("ScriptBloxWarningOverlay") ?? new Grid();
        _scriptBloxWarningBackdrop = this.FindControl<Border>("ScriptBloxWarningBackdrop") ?? new Border();
        _scriptBloxBackdropButton = this.FindControl<Button>("ScriptBloxBackdropButton") ?? new Button();
        _scriptBloxWarningPopup = this.FindControl<Viewbox>("ScriptBloxWarningPopup") ?? new Viewbox();
        var warningTransformGroup = _scriptBloxWarningPopup.RenderTransform as TransformGroup
            ?? new TransformGroup();
        _scriptBloxWarningScale = warningTransformGroup.Children.Count > 0 ? warningTransformGroup.Children[0] as ScaleTransform ?? new ScaleTransform() : new ScaleTransform();
        _scriptBloxWarningTranslation = warningTransformGroup.Children.Count > 1 ? warningTransformGroup.Children[1] as TranslateTransform ?? new TranslateTransform() : new TranslateTransform();
        _scriptBloxContinueButton = this.FindControl<Button>("ScriptBloxContinueButton") ?? new Button();
        _scriptBloxContinueText = this.FindControl<TextBlock>("ScriptBloxContinueText") ?? new TextBlock();
        _scriptBloxWarningTitle = this.FindControl<TextBlock>("ScriptBloxWarningTitle") ?? new TextBlock();
        _scriptBloxWarningLabel = this.FindControl<TextBlock>("ScriptBloxWarningLabel") ?? new TextBlock();
        _scriptBloxWarningDescription = this.FindControl<TextBlock>("ScriptBloxWarningDescription") ?? new TextBlock();
        _scriptBloxDismissButton = this.FindControl<Button>("ScriptBloxDismissButton") ?? new Button();
        _robotPage = this.FindControl<Canvas>("RobotPage") ?? new Canvas();
        _robotDrawer = this.FindControl<Canvas>("RobotDrawer") ?? new Canvas();
        _robotInputBar = this.FindControl<Border>("RobotInputBar") ?? new Border();
        _themesPage = this.FindControl<Canvas>("ThemesPage") ?? new Canvas();
        _pluginsPage = this.FindControl<Canvas>("PluginsPage") ?? new Canvas();
        _settingsPage = this.FindControl<Canvas>("SettingsPage") ?? new Canvas();
        _settingsSurface = this.FindControl<Border>("SettingsSurface") ?? new Border();
        _editorNavIcon = this.FindControl<ShapePath>("EditorNavIcon") ?? new ShapePath();
        _scriptHubNavIcon = this.FindControl<ShapePath>("ScriptHubNavIcon") ?? new ShapePath();
        _robotNavIcon = this.FindControl<ShapePath>("RobotNavIcon") ?? new ShapePath();
        _themesNavIcon = this.FindControl<ShapePath>("ThemesNavIcon") ?? new ShapePath();
        _pluginsNavIcon = this.FindControl<ShapePath>("PluginsNavIcon") ?? new ShapePath();
        _settingsNavInner = this.FindControl<ShapePath>("SettingsNavInner") ?? new ShapePath();
        _settingsNavOuter = this.FindControl<ShapePath>("SettingsNavOuter") ?? new ShapePath();

        InitializeEditorWorkspace();
        InitializePageTransitions();
        InitializeCloseAnimation();
        InitializeResponsiveWindow();
        InitializeWindowMotion();
        InitializeNavigationRail();
        InitializeSettingsPage();
        InitializePluginsPage();
        InitializeThemeStudio();
        InitializeSetupPrototype();
        ApplyOrbitColourScheme(OrbitPreferences.LegacyColoursEnabled, refreshGeneratedControls: false);
        NormalizeVisiblePage(AppPage.Editor);
        UpdatePageNavigationVisuals(AppPage.Editor);

        _monacoWebView.WebMessageReceived += (_, args) =>
        {
            if (!string.IsNullOrEmpty(args.Body))
            {
                HandleMonacoMessage(args.Body);
            }
        };
        _scriptHubCardsControl.ItemsSource = _scriptHubCards;
        UpdateScriptHubProviderVisuals();
        _bridgeServer.ConnectionChanged += MainWindowBridgeConnectionChanged;
        ApplyMainWindowBridgeState(_bridgeServer.IsConnected);
        _bridgeConnectionRefreshTimer = new DispatcherTimer
        {
            Interval = TimeSpan.FromSeconds(3.5)
        };
        _bridgeConnectionRefreshTimer.Tick += BridgeConnectionRefreshTimer_Tick;
        _bridgeConnectionRefreshTimer.Start();
        HideMonaco();
        Opened += MainWindow_Opened;
    }

    private void BridgeConnectionRefreshTimer_Tick(object? sender, EventArgs e)
    {
        // Keep this check in the UI layer. The bridge server remains the source
        // of truth, while the timer makes sure the visual state catches up even
        // when a connection event is missed during a reconnect.
        ApplyMainWindowBridgeConnection(_bridgeServer.IsConnected);
    }

    private async void MainWindow_Opened(object? sender, EventArgs e)
    {
        Opened -= MainWindow_Opened;

        try
        {
            await RunStartupSequenceAsync(_startupCancellation.Token);
        }
        catch (OperationCanceledException)
        {
            // Closing the window cancels any remaining startup frames.
        }
    }

    private async Task RunStartupSequenceAsync(CancellationToken cancellationToken)
    {
        ResizeWindowImmediately();
        if (_loadingInterface != null)
            _loadingInterface.IsVisible = false;

        _mainInterface.IsVisible = true;
        _mainInterface.Opacity = 1;
        var startupPage = RequestedStartupPage();
        _currentPage = startupPage;
        _startupCompleted = true;
        NormalizeVisiblePage(startupPage);
        UpdatePageNavigationVisuals(startupPage);

        CompleteStartupResponsiveLayout();
        if (OrbitPreferences.SetupCompleted)
        {
            ShowOrbitPrototypeDisclaimer();
        }
        else
        {
            await ShowSetupPrototypeAsync(fromStartup: true);
        }
    }

    private async Task AnimateWindowSizeAsync(
        double targetWidth,
        double targetHeight,
        TimeSpan duration,
        CancellationToken cancellationToken)
    {
        var startWidth = Bounds.Width;
        var startHeight = Bounds.Height;
        var startPosition = Position;
        var scaling = Screens.ScreenFromWindow(this)?.Scaling ?? 1;
        var centreX = startPosition.X + (startWidth * scaling / 2);
        var centreY = startPosition.Y + (startHeight * scaling / 2);
        var targetX = centreX - (targetWidth * scaling / 2);
        var targetY = centreY - (targetHeight * scaling / 2);

        await AnimateAsync(
            duration,
            progress =>
            {
                Width = Lerp(startWidth, targetWidth, progress);
                Height = Lerp(startHeight, targetHeight, progress);
                Position = new PixelPoint(
                    (int)Math.Round(Lerp(startPosition.X, targetX, progress)),
                    (int)Math.Round(Lerp(startPosition.Y, targetY, progress)));
            },
            CubicEaseInOut,
            cancellationToken);

        Width = targetWidth;
        Height = targetHeight;
        Position = new PixelPoint((int)Math.Round(targetX), (int)Math.Round(targetY));
        MinWidth = 560;
        MinHeight = 349;
        ApplyResizablePreference(OrbitPreferences.ResizableEnabled);
    }

    private void ResizeWindowImmediately()
    {
        var scaling = Screens.ScreenFromWindow(this)?.Scaling ?? 1;
        var centreX = Position.X + (Bounds.Width * scaling / 2);
        var centreY = Position.Y + (Bounds.Height * scaling / 2);

        Width = MainWindowWidth;
        Height = MainWindowHeight;
        Position = new PixelPoint(
            (int)Math.Round(centreX - (MainWindowWidth * scaling / 2)),
            (int)Math.Round(centreY - (MainWindowHeight * scaling / 2)));
        MinWidth = 560;
        MinHeight = 349;
        ApplyResizablePreference(OrbitPreferences.ResizableEnabled);
    }

    private static async Task AnimateAsync(
        TimeSpan duration,
        Action<double> update,
        Func<double, double> easing,
        CancellationToken cancellationToken)
    {
        var stopwatch = Stopwatch.StartNew();

        while (stopwatch.Elapsed < duration)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var progress = Math.Clamp(
                stopwatch.Elapsed.TotalMilliseconds / duration.TotalMilliseconds,
                0,
                1);
            update(easing(progress));
            await Task.Delay(16, cancellationToken);
        }

        update(1);
    }

    private static double Linear(double progress) => progress;

    private static double CubicEaseIn(double progress) =>
        progress * progress * progress;

    private static double CubicEaseOut(double progress) =>
        1 - Math.Pow(1 - progress, 3);

    private static double CubicEaseInOut(double progress) =>
        progress < 0.5
            ? 4 * progress * progress * progress
            : 1 - Math.Pow(-2 * progress + 2, 3) / 2;

    private static double Lerp(double start, double end, double progress) =>
        start + ((end - start) * progress);

    private static bool SystemAnimationsEnabled()
    {
        if (!OperatingSystem.IsWindows())
        {
            return true;
        }

        var animationsEnabled = true;
        return SystemParametersInfo(
            SpiGetClientAreaAnimation,
            0,
            ref animationsEnabled,
            0)
            ? animationsEnabled
            : true;
    }

    private const uint SpiGetClientAreaAnimation = 0x1042;

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SystemParametersInfo(
        uint uiAction,
        uint uiParam,
        [MarshalAs(UnmanagedType.Bool)] ref bool pvParam,
        uint fWinIni);

    private void EditorPage_Click(object? sender, RoutedEventArgs e) =>
        SetPage(AppPage.Editor);

    private void ScriptHubPage_Click(object? sender, RoutedEventArgs e)
    {
        SetPage(AppPage.ScriptHub);

        if (!_scriptHubHasLoaded)
        {
            _ = LoadScriptHubCardsAsync(animateProviderChange: false, append: false);
        }
    }

    private void RobotPage_Click(object? sender, RoutedEventArgs e) =>
        SetPage(AppPage.Robot);

    private void ThemesPage_Click(object? sender, RoutedEventArgs e) =>
        SetPage(AppPage.Themes);

    private void PluginsPage_Click(object? sender, RoutedEventArgs e) =>
        SetPage(AppPage.Plugins);

    private void SettingsPage_Click(object? sender, RoutedEventArgs e) =>
        SetPage(AppPage.Settings);

    private void RobotDrawerToggle_Click(object? sender, RoutedEventArgs e) =>
        SetRobotDrawerVisible(!_robotDrawer.IsVisible);

    private void ScriptBloxSource_Click(object? sender, RoutedEventArgs e)
    {
        if (_scriptHubProvider == ScriptHubProvider.ScriptBlox)
        {
            return;
        }

        ShowScriptBloxWarning();
    }

    private void RobloxScriptsSource_Click(object? sender, RoutedEventArgs e) =>
        SelectScriptHubProvider(ScriptHubProvider.RobloxScripts);

    private void HaxHellSource_Click(object? sender, RoutedEventArgs e) =>
        SelectScriptHubProvider(ScriptHubProvider.HaxHell);

    private void RscriptsSource_Click(object? sender, RoutedEventArgs e) =>
        SelectScriptHubProvider(ScriptHubProvider.Rscripts);

    private async void ScriptHubSearchBox_TextChanged(object? sender, TextChangedEventArgs e)
    {
        if (!_scriptHubPage.IsVisible)
        {
            return;
        }

        _scriptHubSearchCancellation?.Cancel();
        _scriptHubSearchCancellation?.Dispose();
        _scriptHubSearchCancellation = new CancellationTokenSource();
        var cancellationToken = _scriptHubSearchCancellation.Token;

        try
        {
            await Task.Delay(350, cancellationToken);
            await LoadScriptHubCardsAsync(animateProviderChange: false, append: false);
        }
        catch (OperationCanceledException)
        {
            // A newer keystroke replaced this search.
        }
    }

    private void SelectScriptHubProvider(ScriptHubProvider provider)
    {
        if (_scriptHubProvider == provider && _scriptHubHasLoaded)
        {
            return;
        }

        _scriptHubProvider = provider;
        _scriptHubHasLoaded = false;
        UpdateScriptHubProviderVisuals();
        _ = LoadScriptHubCardsAsync(animateProviderChange: true, append: false);
    }

    private void UpdateScriptHubProviderVisuals()
    {
        _scriptBloxSourceText.Foreground =
            _scriptHubProvider == ScriptHubProvider.ScriptBlox ? SelectedPageBrush : InactivePageBrush;
        _robloxScriptsSourceText.Foreground =
            _scriptHubProvider == ScriptHubProvider.RobloxScripts ? SelectedPageBrush : InactivePageBrush;
        _haxHellSourceText.Foreground =
            _scriptHubProvider == ScriptHubProvider.HaxHell ? SelectedPageBrush : InactivePageBrush;
        _rscriptsSourceText.Foreground =
            _scriptHubProvider == ScriptHubProvider.Rscripts ? SelectedPageBrush : InactivePageBrush;

        var (left, top, watermark) = _scriptHubProvider switch
        {
            ScriptHubProvider.ScriptBlox => (159d, 130d, "Search scriptblox..."),
            ScriptHubProvider.RobloxScripts => (196d, 153d, "Search robloxscripts.com..."),
            ScriptHubProvider.HaxHell => (132d, 176d, "Search haxhell..."),
            ScriptHubProvider.Rscripts => (128d, 199d, "Search rscripts..."),
            _ => (196d, 153d, "Search scripts...")
        };

        Canvas.SetLeft(_scriptHubSelectedTick, left);
        Canvas.SetTop(_scriptHubSelectedTick, top);
        _scriptHubSearchBox.PlaceholderText = watermark;
    }

    private async Task LoadScriptHubCardsAsync(bool animateProviderChange, bool append)
    {
        if (append && (!_scriptHubHasMore || _scriptHubPageLoading))
        {
            return;
        }

        if (!append)
        {
            _scriptHubLoadCancellation?.Cancel();
        }

        _scriptHubLoadCancellation?.Dispose();
        _scriptHubLoadCancellation = new CancellationTokenSource();
        var cancellationToken = _scriptHubLoadCancellation.Token;
        var provider = _scriptHubProvider;
        var query = (_scriptHubSearchBox.Text ?? string.Empty).Trim();
        var page = append ? _scriptHubCurrentPage + 1 : 1;
        var loadVersion = ++_scriptHubLoadVersion;
        var contentUpdated = false;
        _scriptHubPageLoading = true;

        _scriptHubContentArea.Opacity = 1;
        _scriptHubContentTranslation.X = 0;

        if (!append && _scriptHubCards.Count == 0)
        {
            _scriptHubCardsControl.IsVisible = false;
            _scriptHubStateText.Text = $"Loading {ProviderDisplayName(provider)}...";
            _scriptHubStateText.IsVisible = true;
        }

        try
        {
            var result = await _scriptHubService.FetchAsync(
                provider,
                query,
                page,
                cancellationToken);
            cancellationToken.ThrowIfCancellationRequested();

            if (provider != _scriptHubProvider ||
                !query.Equals(
                    (_scriptHubSearchBox.Text ?? string.Empty).Trim(),
                    StringComparison.Ordinal))
            {
                return;
            }

            if (result.Cards.Count > 0)
            {
                await _scriptHubService.LoadThumbnailsAsync(result.Cards, cancellationToken);
            }

            cancellationToken.ThrowIfCancellationRequested();

            void ApplyPage()
            {
                if (!append)
                {
                    _scriptHubCards.Clear();
                    _scriptHubCardKeys.Clear();
                    _scriptHubCardsScrollViewer.Offset = new Vector(0, 0);
                }

                var added = 0;
                foreach (var card in result.Cards)
                {
                    if (_scriptHubCardKeys.Add(card.Key))
                    {
                        _scriptHubCards.Add(card);
                        added++;
                    }
                }

                _scriptHubCurrentPage = page;
                _scriptHubHasMore = result.HasMore && (!append || added > 0);
                _scriptHubHasLoaded = true;
                _scriptHubCardsControl.IsVisible = _scriptHubCards.Count > 0;
                _scriptHubStateText.Text = _scriptHubCards.Count == 0
                    ? "No scripts found."
                    : string.Empty;
                _scriptHubStateText.IsVisible = _scriptHubCards.Count == 0;
                contentUpdated = true;
            }

            if (animateProviderChange && !append)
            {
                await TransitionScriptHubContentAsync(ApplyPage, cancellationToken);
            }
            else
            {
                ApplyPage();
                _scriptHubContentArea.Opacity = 1;
                _scriptHubContentTranslation.X = 0;
            }
        }
        catch (OperationCanceledException)
        {
            // Provider or search text changed while this request was running.
        }
        catch (Exception exception)
        {
            if (append)
            {
                _scriptHubHasMore = false;
                return;
            }

            void ShowError()
            {
                _scriptHubCards.Clear();
                _scriptHubCardKeys.Clear();
                _scriptHubCardsControl.IsVisible = false;
                _scriptHubStateText.Text =
                    $"Couldn’t load {ProviderDisplayName(provider)}. {exception.Message}";
                _scriptHubStateText.IsVisible = true;
                _scriptHubHasMore = false;
            }

            if (animateProviderChange)
            {
                await TransitionScriptHubContentAsync(ShowError, cancellationToken);
            }
            else
            {
                ShowError();
            }
        }
        finally
        {
            if (loadVersion == _scriptHubLoadVersion)
            {
                _scriptHubPageLoading = false;
            }

            if (contentUpdated)
            {
                Dispatcher.UIThread.Post(
                    TryLoadNextScriptHubPage,
                    DispatcherPriority.Background);
            }
        }
    }

    private void ScriptHubCardsScrollViewer_ScrollChanged(
        object? sender,
        ScrollChangedEventArgs e) =>
        TryLoadNextScriptHubPage();

    private void TryLoadNextScriptHubPage()
    {
        if (!_scriptHubPage.IsVisible ||
            !_scriptHubHasMore ||
            _scriptHubPageLoading ||
            _scriptHubCards.Count == 0)
        {
            return;
        }

        var viewportBottom =
            _scriptHubCardsScrollViewer.Offset.Y +
            _scriptHubCardsScrollViewer.Viewport.Height;
        if (_scriptHubCardsScrollViewer.Extent.Height <= 0 ||
            viewportBottom < _scriptHubCardsScrollViewer.Extent.Height - 180)
        {
            return;
        }

        _ = LoadScriptHubCardsAsync(animateProviderChange: false, append: true);
    }

    private async Task TransitionScriptHubContentAsync(
        Action swapContent,
        CancellationToken cancellationToken)
    {
        if (!SystemAnimationsEnabled())
        {
            swapContent();
            _scriptHubContentArea.Opacity = 1;
            _scriptHubContentTranslation.X = 0;
            return;
        }

        await AnimateAsync(
            TimeSpan.FromMilliseconds(150),
            progress =>
            {
                _scriptHubContentArea.Opacity = 1 - progress;
                _scriptHubContentTranslation.X = Lerp(0, -10, progress);
            },
            CubicEaseIn,
            cancellationToken);

        swapContent();
        _scriptHubContentArea.Opacity = 0;
        _scriptHubContentTranslation.X = 12;

        await AnimateAsync(
            TimeSpan.FromMilliseconds(220),
            progress =>
            {
                _scriptHubContentArea.Opacity = progress;
                _scriptHubContentTranslation.X = Lerp(12, 0, progress);
            },
            CubicEaseOut,
            cancellationToken);

        _scriptHubContentArea.Opacity = 1;
        _scriptHubContentTranslation.X = 0;
    }

    private static string ProviderDisplayName(ScriptHubProvider provider) => provider switch
    {
        ScriptHubProvider.RobloxScripts => "robloxscripts.com",
        ScriptHubProvider.ScriptBlox => "ScriptBlox",
        ScriptHubProvider.HaxHell => "HaxHell",
        ScriptHubProvider.Rscripts => "rscripts",
        _ => "scripts"
    };

    private void ShowScriptBloxWarning()
    {
        _showingPrototypeDisclaimer = false;
        _scriptBloxWarningTitle.Text = ScriptBloxWarningTitle;
        _scriptBloxWarningLabel.Text = ScriptBloxWarningLabel;
        _scriptBloxWarningDescription.Text = ScriptBloxWarningDescription;
        _scriptBloxDismissButton.Content = "Don't Use";
        _scriptBloxDismissButton.IsVisible = true;
        Canvas.SetLeft(_scriptBloxContinueButton, 197);
        ShowScriptBloxWarningCore();
    }

    private void ShowOrbitPrototypeDisclaimer()
    {
        _prototypeDisclaimerAcknowledged = false;
        _showingPrototypeDisclaimer = true;
        _scriptBloxWarningTitle.Text = PrototypeDisclaimerTitle;
        _scriptBloxWarningLabel.Text = PrototypeDisclaimerLabel;
        _scriptBloxWarningDescription.Text = PrototypeDisclaimerDescription;
        _scriptBloxDismissButton.IsVisible = false;
        Canvas.SetLeft(_scriptBloxContinueButton, 110.5);
        UpdateMonacoVisibility();
        ShowScriptBloxWarningCore();
    }

    private void ShowScriptBloxWarningCore()
    {
        _scriptBloxWarningCancellation?.Cancel();
        _scriptBloxWarningCancellation?.Dispose();
        _scriptBloxWarningCancellation = new CancellationTokenSource();

        _scriptBloxWarningAnimationCancellation?.Cancel();
        _scriptBloxWarningAnimationCancellation?.Dispose();
        _scriptBloxWarningAnimationCancellation = new CancellationTokenSource();

        _scriptBloxWarningOverlay.IsVisible = true;
        _scriptBloxContinueButton.IsEnabled = false;
        _scriptBloxContinueText.Text = "Continue (5)";
        _ = RunScriptBloxCountdownAsync(_scriptBloxWarningCancellation.Token);
        _ = AnimateScriptBloxWarningInAsync(_scriptBloxWarningAnimationCancellation.Token);
    }

    private async Task AnimateScriptBloxWarningInAsync(CancellationToken cancellationToken)
    {
        if (!SystemAnimationsEnabled())
        {
            _scriptBloxWarningBackdrop.Opacity = 1;
            _scriptBloxWarningPopup.Opacity = 1;
            _scriptBloxWarningScale.ScaleX = 1;
            _scriptBloxWarningScale.ScaleY = 1;
            _scriptBloxWarningTranslation.Y = 0;
            return;
        }

        _scriptBloxWarningBackdrop.Opacity = 0;
        _scriptBloxWarningPopup.Opacity = 0;
        _scriptBloxWarningScale.ScaleX = 0.94;
        _scriptBloxWarningScale.ScaleY = 0.94;
        _scriptBloxWarningTranslation.Y = 8;

        try
        {
            await AnimateAsync(
                TimeSpan.FromMilliseconds(280),
                progress =>
                {
                    _scriptBloxWarningBackdrop.Opacity = progress;
                    _scriptBloxWarningPopup.Opacity = progress;
                    _scriptBloxWarningScale.ScaleX = Lerp(0.94, 1, progress);
                    _scriptBloxWarningScale.ScaleY = Lerp(0.94, 1, progress);
                    _scriptBloxWarningTranslation.Y = Lerp(8, 0, progress);
                },
                CubicEaseOut,
                cancellationToken);
        }
        catch (OperationCanceledException)
        {
            // A dismissal animation took over before the entrance finished.
        }
    }

    private async Task RunScriptBloxCountdownAsync(CancellationToken cancellationToken)
    {
        try
        {
            for (var remaining = 5; remaining > 0; remaining--)
            {
                _scriptBloxContinueText.Text = $"Continue ({remaining})";
                await Task.Delay(TimeSpan.FromSeconds(1), cancellationToken);
            }

            _scriptBloxContinueText.Text = "Continue";
            _scriptBloxContinueButton.IsEnabled = true;
        }
        catch (OperationCanceledException)
        {
            // The warning was dismissed before the countdown completed.
        }
    }

    private async void ScriptBloxDontUse_Click(object? sender, RoutedEventArgs e)
    {
        if (_showingPrototypeDisclaimer && ReferenceEquals(sender, _scriptBloxBackdropButton))
        {
            return;
        }
        await HideScriptBloxWarningAsync();
    }

    private async void ScriptBloxContinue_Click(object? sender, RoutedEventArgs e)
    {
        if (!_scriptBloxContinueButton.IsEnabled)
        {
            return;
        }

        if (_showingPrototypeDisclaimer)
        {
            _prototypeDisclaimerAcknowledged = true;
            _showingPrototypeDisclaimer = false;
        }
        else
        {
            SelectScriptHubProvider(ScriptHubProvider.ScriptBlox);
        }
        await HideScriptBloxWarningAsync();
    }

    private async Task HideScriptBloxWarningAsync()
    {
        _scriptBloxWarningCancellation?.Cancel();
        _scriptBloxWarningCancellation?.Dispose();
        _scriptBloxWarningCancellation = null;

        _scriptBloxWarningAnimationCancellation?.Cancel();
        _scriptBloxWarningAnimationCancellation?.Dispose();
        _scriptBloxWarningAnimationCancellation = new CancellationTokenSource();
        var cancellationToken = _scriptBloxWarningAnimationCancellation.Token;

        if (!SystemAnimationsEnabled())
        {
            _scriptBloxWarningOverlay.IsVisible = false;
            UpdateMonacoVisibility();
            return;
        }

        var startBackdropOpacity = _scriptBloxWarningBackdrop.Opacity;
        var startPopupOpacity = _scriptBloxWarningPopup.Opacity;
        var startScale = _scriptBloxWarningScale.ScaleX;
        var startTranslation = _scriptBloxWarningTranslation.Y;

        try
        {
            await AnimateAsync(
                TimeSpan.FromMilliseconds(220),
                progress =>
                {
                    _scriptBloxWarningBackdrop.Opacity = Lerp(startBackdropOpacity, 0, progress);
                    _scriptBloxWarningPopup.Opacity = Lerp(startPopupOpacity, 0, progress);
                    _scriptBloxWarningScale.ScaleX = Lerp(startScale, 0.96, progress);
                    _scriptBloxWarningScale.ScaleY = Lerp(startScale, 0.96, progress);
                    _scriptBloxWarningTranslation.Y = Lerp(startTranslation, 6, progress);
                },
                CubicEaseIn,
                cancellationToken);

            _scriptBloxWarningOverlay.IsVisible = false;
            UpdateMonacoVisibility();
        }
        catch (OperationCanceledException)
        {
            // A newer warning transition replaced this fade.
        }
    }

    private void SetRobotDrawerVisible(bool isVisible)
    {
        _robotDrawer.IsVisible = isVisible;
        _robotInputBar.BorderThickness = isVisible ? new Thickness(1) : new Thickness(0);
    }

    private enum AppPage
    {
        Editor,
        ScriptHub,
        Robot,
        Themes,
        Plugins,
        Settings
    }

    private void UpdateCursorPosition(string message)
    {
        try
        {
            using var payload = JsonDocument.Parse(message);
            var root = payload.RootElement;

            if (!root.TryGetProperty("type", out var type) ||
                type.GetString() != "cursorPosition" ||
                !root.TryGetProperty("line", out var lineProperty) ||
                !root.TryGetProperty("column", out var columnProperty) ||
                !lineProperty.TryGetInt32(out var line) ||
                !columnProperty.TryGetInt32(out var column))
            {
                return;
            }

            Dispatcher.UIThread.Post(() =>
                _cursorPositionText.Text = $"Ln {line}, Col {column}");
        }
        catch (JsonException)
        {
            // Ignore messages that are not editor status updates.
        }
    }

    protected override void OnClosed(EventArgs e)
    {
        _workspaceSaveTimer.Stop();
        PersistEditorWorkspace();
        _gistDialogCancellation?.Cancel();
        _gistDialogCancellation?.Dispose();
        _gistDialogAnimationCancellation?.Cancel();
        _gistDialogAnimationCancellation?.Dispose();
        _resizeEdgeReleaseTimer.Stop();
        _resizeTabsWarningAnimationCancellation?.Cancel();
        _resizeTabsWarningAnimationCancellation?.Dispose();
        _tabCapacityNoticeCancellation?.Cancel();
        _tabCapacityNoticeCancellation?.Dispose();
        _settingsTabAnimationCancellation?.Cancel();
        _settingsTabAnimationCancellation?.Dispose();
        _setupPrototypeAnimationCancellation?.Cancel();
        _setupPrototypeAnimationCancellation?.Dispose();
        _pageTransitionCancellation?.Cancel();
        _pageTransitionCancellation?.Dispose();
        CancelEditorTabMotions();
        _closeAnimationCancellation?.Cancel();
        _closeAnimationCancellation?.Dispose();
        _windowMotionTimer.Stop();
        CancelWindowBoundsAnimation();
        _startupCancellation.Cancel();
        _startupCancellation.Dispose();
        _scriptHubLoadCancellation?.Cancel();
        _scriptHubLoadCancellation?.Dispose();
        _scriptHubSearchCancellation?.Cancel();
        _scriptHubSearchCancellation?.Dispose();
        _scriptBloxWarningCancellation?.Cancel();
        _scriptBloxWarningCancellation?.Dispose();
        _scriptBloxWarningAnimationCancellation?.Cancel();
        _scriptBloxWarningAnimationCancellation?.Dispose();
        _bridgeConnectionRefreshTimer?.Stop();
        _bridgeConnectionRefreshTimer = null;
        _bridgeServer.ConnectionChanged -= MainWindowBridgeConnectionChanged;
        DisposeBridgeConnectedNotification();
        _editorWorkspace.Dispose();
        _scriptHubService.Dispose();
        if (!_allowImmediateClose)
        {
            _monacoServer.Dispose();
        }
        base.OnClosed(e);

        if (_allowImmediateClose)
        {
            Environment.Exit(0);
        }
    }

    private void TitleBar_PointerPressed(object? sender, PointerPressedEventArgs e)
    {
        if (!e.GetCurrentPoint(this).Properties.IsLeftButtonPressed)
        {
            return;
        }

        if (e.ClickCount == 2)
        {
            ReleaseSmoothWindowMotion();
            _ = ToggleMaximizeAnimatedAsync();
            return;
        }

        if (IsWindowVisuallyMaximized)
        {
            return;
        }

        // Use Avalonia's native move operation so Windows can apply its own
        // snap/maximize zones. Corner/edge resize remains on the eased path.
        BeginMoveDrag(e);
    }

    private void Minimize_Click(object? sender, RoutedEventArgs e) =>
        WindowState = WindowState.Minimized;

    private void Maximize_Click(object? sender, RoutedEventArgs e) =>
        _ = ToggleMaximizeAnimatedAsync();

    private void Close_Click(object? sender, RoutedEventArgs e) => Close();

    private void ResizeEdge_PointerPressed(object? sender, PointerPressedEventArgs e)
    {
        if (!OrbitPreferences.ResizableEnabled ||
            IsWindowVisuallyMaximized ||
            sender is not Border { Tag: string edge } resizeHandle ||
            !e.GetCurrentPoint(this).Properties.IsLeftButtonPressed)
        {
            return;
        }

        var windowEdge = edge switch
        {
            "Left" => WindowEdge.West,
            "Right" => WindowEdge.East,
            "Top" => WindowEdge.North,
            "Bottom" => WindowEdge.South,
            "TopLeft" => WindowEdge.NorthWest,
            "TopRight" => WindowEdge.NorthEast,
            "BottomLeft" => WindowEdge.SouthWest,
            "BottomRight" => WindowEdge.SouthEast,
            _ => WindowEdge.NorthWest
        };

        // Client-edge resizing follows the pointer through the UI animation.
        // The native thick frame remains enabled outside these handles so
        // Windows 11 snap and maximize affordances continue to work normally.
        BeginSmoothWindowResize(windowEdge, resizeHandle, e);
    }
}
