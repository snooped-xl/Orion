using Avalonia;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Media;
using Avalonia.Threading;
using ShapePath = Avalonia.Controls.Shapes.Path;

namespace OrbitAvalonia;

public sealed partial class MainWindow
{
    private const double DesignWidth = 996;
    private const double DesignHeight = 620;
    private const double PreferredTabWidth = 140;
    private const double MinimumTabWidth = 72;
    private const double AddTabButtonWidth = 42;
    private const double FixedHorizontalScale = MainWindowWidth / DesignWidth;
    private const double FixedVerticalScale = MainWindowHeight / DesignHeight;
    private const double OnePhysicalPixelX = 1 / FixedHorizontalScale;
    private const double OnePhysicalPixelY = 1 / FixedVerticalScale;
    private static readonly Thickness OnePhysicalPixelBorder = new(
        OnePhysicalPixelX,
        OnePhysicalPixelY,
        OnePhysicalPixelX,
        OnePhysicalPixelY);
    private const double MonacoLeftOffset = 304 * FixedHorizontalScale;
    // Keep the native overlay two design pixels inside the page island's
    // 10 px inset. NativeWebView owns a child HWND and can otherwise paint over
    // the Avalonia stroke even when both nominal edges are identical.
    private const double MonacoRightOffset = 12 * FixedHorizontalScale;

    private Border _mainWindowChrome = null!;
    private Canvas _mainDesignCanvas = null!;
    private Border _mainLeftRail = null!;
    private Border _editorSurface = null!;
    private Border _editorStrokeOverlay = null!;
    private ScrollViewer _explorerScrollViewer = null!;
    private Border _monacoBacking = null!;
    private ScrollViewer _editorTabsScrollViewer = null!;
    private Border _editorDivider = null!;
    private Canvas _explorerBottomBar = null!;
    private Border _editorBottomBar = null!;
    private Viewbox _executeActionIcon = null!;
    private Viewbox _openActionIcon = null!;
    private Viewbox _saveActionIcon = null!;
    private Viewbox _clearActionIcon = null!;
    private Button _executeActionButton = null!;
    private Button _openActionButton = null!;
    private Button _saveActionButton = null!;
    private Button _clearActionButton = null!;
    private TextBlock _languageText = null!;
    private Border _scriptHubSurface = null!;
    private Border _scriptHubDivider = null!;
    private Border _robotSurface = null!;
    private TextBlock _robotWelcomeText = null!;
    private Image _robotWelcomeLogo = null!;
    private TextBlock _robotWelcomeSubtitle = null!;
    private TextBlock _robotInputPlaceholder = null!;
    private Border _robotModelsChip = null!;
    private ShapePath _robotModelsChevron = null!;
    private TextBlock _robotModelsText = null!;
    private Border _robotToolsChip = null!;
    private ShapePath _robotToolsChevron = null!;
    private TextBlock _robotToolsText = null!;
    private Border _robotAddChip = null!;
    private Viewbox _robotAddIcon = null!;
    private Border _robotDrawerSurface = null!;
    private TextBlock _robotEmptyTrashText = null!;
    private Viewbox _robotEmptyTrashIcon = null!;
    private Border _robotDrawerToggleChrome = null!;
    private Button _robotDrawerToggleButton = null!;
    private Border _settingsDivider = null!;
    private Border _settingsContentPanel = null!;
    private Border _themesContentPanel = null!;
    private ScrollViewer _themesLibraryScrollViewer = null!;
    private Viewbox _settingsNavIcon = null!;
    private Button _settingsPageButton = null!;
    private Border _titleDragRegion = null!;
    private Button _minimizeWindowButton = null!;
    private Button _maximizeWindowButton = null!;
    private Button _closeWindowButton = null!;
    private Border _leftResizeHandle = null!;
    private Border _rightResizeHandle = null!;
    private Border _topResizeHandle = null!;
    private Border _bottomResizeHandle = null!;
    private Border _topLeftResizeHandle = null!;
    private Border _topRightResizeHandle = null!;
    private Border _bottomLeftResizeHandle = null!;
    private Border _bottomRightResizeHandle = null!;
    private Border _loadingWindowChrome = null!;
    private Grid _resizeTabsWarningOverlay = null!;
    private Border _resizeTabsWarningBackdrop = null!;
    private Viewbox _resizeTabsWarningPopup = null!;
    private ScaleTransform _resizeTabsWarningScale = null!;
    private TranslateTransform _resizeTabsWarningTranslation = null!;
    private TextBlock _resizeTabsWarningSummaryText = null!;
    private TextBlock _resizeTabsWarningNamesText = null!;
    private Button _resizeTabsWarningConfirmButton = null!;
    private DispatcherTimer _resizeEdgeReleaseTimer = null!;
    private CancellationTokenSource? _resizeTabsWarningAnimationCancellation;
    private CancellationTokenSource? _tabCapacityNoticeCancellation;
    private readonly List<Guid> _pendingResizeTabIds = [];
    private Size _lastAcceptedNormalSize = new(MainWindowWidth, MainWindowHeight);
    private Size _pendingRequestedSize = new(MainWindowWidth, MainWindowHeight);
    private Size _latestObservedResizeSize = new(MainWindowWidth, MainWindowHeight);
    private WindowState _lastObservedWindowState = WindowState.Normal;
    private WindowEdge? _activeResizeEdge;
    private double _resizeAnchorRight;
    private double _resizeAnchorBottom;
    private bool _startupLayoutComplete;
    private bool _applyingResponsiveSize;
    private bool _restoreFromMaximizedPending;
    private bool _resizeWarningKeepsSquareChrome;

    private void InitializeResponsiveWindow()
    {
        _mainWindowChrome = this.FindControl<Border>("MainWindowChrome")
            ?? throw new InvalidOperationException("The main window chrome was not created.");
        _mainDesignCanvas = RequireResponsiveControl<Canvas>("MainDesignCanvas");
        _mainLeftRail = RequireResponsiveControl<Border>("MainLeftRail");
        _editorSurface = RequireResponsiveControl<Border>("EditorSurface");
        _editorStrokeOverlay = RequireResponsiveControl<Border>("EditorStrokeOverlay");
        _explorerScrollViewer = RequireResponsiveControl<ScrollViewer>("ExplorerScrollViewer");
        _monacoBacking = RequireResponsiveControl<Border>("MonacoBacking");
        _editorTabsScrollViewer = RequireResponsiveControl<ScrollViewer>("EditorTabsScrollViewer");
        _editorDivider = RequireResponsiveControl<Border>("EditorDivider");
        _explorerBottomBar = RequireResponsiveControl<Canvas>("ExplorerBottomBar");
        _editorBottomBar = RequireResponsiveControl<Border>("EditorBottomBar");
        _executeActionIcon = RequireResponsiveControl<Viewbox>("ExecuteActionIcon");
        _openActionIcon = RequireResponsiveControl<Viewbox>("OpenActionIcon");
        _saveActionIcon = RequireResponsiveControl<Viewbox>("SaveActionIcon");
        _clearActionIcon = RequireResponsiveControl<Viewbox>("ClearActionIcon");
        _executeActionButton = RequireResponsiveControl<Button>("ExecuteActionButton");
        _openActionButton = RequireResponsiveControl<Button>("OpenActionButton");
        _saveActionButton = RequireResponsiveControl<Button>("SaveActionButton");
        _clearActionButton = RequireResponsiveControl<Button>("ClearActionButton");
        _languageText = RequireResponsiveControl<TextBlock>("LanguageText");
        _scriptHubSurface = RequireResponsiveControl<Border>("ScriptHubSurface");
        _scriptHubDivider = RequireResponsiveControl<Border>("ScriptHubDivider");
        _robotSurface = RequireResponsiveControl<Border>("RobotSurface");
        _robotWelcomeText = RequireResponsiveControl<TextBlock>("RobotWelcomeText");
        _robotWelcomeLogo = RequireResponsiveControl<Image>("RobotWelcomeLogo");
        _robotWelcomeSubtitle = RequireResponsiveControl<TextBlock>("RobotWelcomeSubtitle");
        _robotInputPlaceholder = RequireResponsiveControl<TextBlock>("RobotInputPlaceholder");
        _robotModelsChip = RequireResponsiveControl<Border>("RobotModelsChip");
        _robotModelsChevron = RequireResponsiveControl<ShapePath>("RobotModelsChevron");
        _robotModelsText = RequireResponsiveControl<TextBlock>("RobotModelsText");
        _robotToolsChip = RequireResponsiveControl<Border>("RobotToolsChip");
        _robotToolsChevron = RequireResponsiveControl<ShapePath>("RobotToolsChevron");
        _robotToolsText = RequireResponsiveControl<TextBlock>("RobotToolsText");
        _robotAddChip = RequireResponsiveControl<Border>("RobotAddChip");
        _robotAddIcon = RequireResponsiveControl<Viewbox>("RobotAddIcon");
        _robotDrawerSurface = RequireResponsiveControl<Border>("RobotDrawerSurface");
        _robotEmptyTrashText = RequireResponsiveControl<TextBlock>("RobotEmptyTrashText");
        _robotEmptyTrashIcon = RequireResponsiveControl<Viewbox>("RobotEmptyTrashIcon");
        _robotDrawerToggleChrome = RequireResponsiveControl<Border>("RobotDrawerToggleChrome");
        _robotDrawerToggleButton = RequireResponsiveControl<Button>("RobotDrawerToggleButton");
        _settingsDivider = RequireResponsiveControl<Border>("SettingsDivider");
        _settingsContentPanel = RequireResponsiveControl<Border>("SettingsContentPanel");
        _themesContentPanel = RequireResponsiveControl<Border>("ThemesContentPanel");
        _themesLibraryScrollViewer = RequireResponsiveControl<ScrollViewer>("ThemesLibraryScrollViewer");
        _settingsNavIcon = RequireResponsiveControl<Viewbox>("SettingsNavIcon");
        _settingsPageButton = RequireResponsiveControl<Button>("SettingsPageButton");
        _titleDragRegion = RequireResponsiveControl<Border>("TitleDragRegion");
        _minimizeWindowButton = RequireResponsiveControl<Button>("MinimizeWindowButton");
        _maximizeWindowButton = RequireResponsiveControl<Button>("MaximizeWindowButton");
        _closeWindowButton = RequireResponsiveControl<Button>("CloseWindowButton");
        _leftResizeHandle = RequireResponsiveControl<Border>("LeftResizeHandle");
        _rightResizeHandle = RequireResponsiveControl<Border>("RightResizeHandle");
        _topResizeHandle = RequireResponsiveControl<Border>("TopResizeHandle");
        _bottomResizeHandle = RequireResponsiveControl<Border>("BottomResizeHandle");
        _topLeftResizeHandle = RequireResponsiveControl<Border>("TopLeftResizeHandle");
        _topRightResizeHandle = RequireResponsiveControl<Border>("TopRightResizeHandle");
        _bottomLeftResizeHandle = RequireResponsiveControl<Border>("BottomLeftResizeHandle");
        _bottomRightResizeHandle = RequireResponsiveControl<Border>("BottomRightResizeHandle");
        _loadingWindowChrome = this.FindControl<Border>("LoadingWindowChrome") ?? new Border();
        _resizeTabsWarningOverlay = this.FindControl<Grid>("ResizeTabsWarningOverlay") ?? new Grid();
        _resizeTabsWarningBackdrop = this.FindControl<Border>("ResizeTabsWarningBackdrop") ?? new Border();
        _resizeTabsWarningPopup = this.FindControl<Viewbox>("ResizeTabsWarningPopup") ?? new Viewbox();
        _resizeTabsWarningSummaryText = this.FindControl<TextBlock>("ResizeTabsWarningSummaryText") ?? new TextBlock();
        _resizeTabsWarningNamesText = this.FindControl<TextBlock>("ResizeTabsWarningNamesText") ?? new TextBlock();
        _resizeTabsWarningConfirmButton = this.FindControl<Button>("ResizeTabsWarningConfirmButton") ?? new Button();

        var transformGroup = _resizeTabsWarningPopup.RenderTransform as TransformGroup ?? new TransformGroup();
        _resizeTabsWarningScale = transformGroup.Children.Count > 0 ? transformGroup.Children[0] as ScaleTransform ?? new ScaleTransform() : new ScaleTransform();
        _resizeTabsWarningTranslation = transformGroup.Children.Count > 1 ? transformGroup.Children[1] as TranslateTransform ?? new TranslateTransform() : new TranslateTransform();

        _resizeEdgeReleaseTimer = new DispatcherTimer
        {
            Interval = TimeSpan.FromMilliseconds(420)
        };
        _resizeEdgeReleaseTimer.Tick += (_, _) =>
        {
            _resizeEdgeReleaseTimer.Stop();
            if (_windowMotionTracking && _smoothMotionIsResize)
            {
                _resizeEdgeReleaseTimer.Start();
                return;
            }

            try
            {
                if (_startupLayoutComplete &&
                    !_applyingResponsiveSize &&
                    WindowState == WindowState.Normal &&
                    !_resizeTabsWarningOverlay.IsVisible)
                {
                    EvaluateResizeRequest(_latestObservedResizeSize);
                }
            }
            finally
            {
                _activeResizeEdge = null;
            }
        };

        SizeChanged += MainWindow_SizeChanged;
        PropertyChanged += MainWindow_PropertyChanged;
        _lastObservedWindowState = WindowState;
        UpdateResponsiveDesignSurface();
        UpdateWindowChromeForState();
    }

    private T RequireResponsiveControl<T>(string name) where T : Control, new() =>
        this.FindControl<T>(name) ?? new T();

    private void UpdateResponsiveDesignSurface(Size? liveClientSize = null)
    {
        // SizeChanged.NewSize is the authoritative client size while Windows
        // is resizing. Bounds can trail it by one layout pass, which made the
        // chrome grow while the page islands retained their previous size.
        var requestedSize = liveClientSize ?? Bounds.Size;
        var windowWidth = requestedSize.Width > 1 ? requestedSize.Width : MainWindowWidth;
        var windowHeight = requestedSize.Height > 1 ? requestedSize.Height : MainWindowHeight;
        var designWidth = windowWidth / FixedHorizontalScale;
        var designHeight = windowHeight / FixedVerticalScale;
        var widthDelta = designWidth - DesignWidth;
        var heightDelta = designHeight - DesignHeight;
        var innerHeight = Math.Max(180, designHeight - 76);
        var editorWidth = Math.Max(180, designWidth - 314);

        _mainWindowChrome.Width = designWidth;
        _mainWindowChrome.Height = designHeight;
        _mainDesignCanvas.Width = designWidth;
        _mainDesignCanvas.Height = designHeight;
        _editorPage.Width = designWidth;
        _editorPage.Height = designHeight;

        _mainLeftRail.Height = innerHeight;
        _editorSurface.Width = Math.Max(260, designWidth - 80);
        _editorSurface.Height = innerHeight;
        _explorerScrollViewer.Height = Math.Max(68, designHeight - 206);
        Canvas.SetTop(_monacoBacking, 111);
        _monacoBacking.Width = editorWidth;
        _monacoBacking.Height = Math.Max(80, designHeight - 171);
        Canvas.SetTop(_editorTabsScrollViewer, 66);
        _editorTabsScrollViewer.Width = editorWidth;
        _editorDivider.Height = innerHeight;
        _editorDivider.Width = OnePhysicalPixelX;

        // The page surface is now 10 px clear of the chrome at the bottom.
        // Keep both bottom bars inside that boundary so their lower stroke is
        // not clipped by the page geometry.
        Canvas.SetTop(_explorerBottomBar, designHeight - 62);
        Canvas.SetTop(_editorBottomBar, designHeight - 62);
        _editorBottomBar.Width = editorWidth;
        Canvas.SetTop(_executeActionIcon, designHeight - 43);
        Canvas.SetTop(_openActionIcon, designHeight - 43);
        Canvas.SetTop(_saveActionIcon, designHeight - 43);
        Canvas.SetTop(_clearActionIcon, designHeight - 43);
        Canvas.SetTop(_executeActionButton, designHeight - 54);
        Canvas.SetTop(_openActionButton, designHeight - 54);
        Canvas.SetTop(_saveActionButton, designHeight - 54);
        Canvas.SetTop(_clearActionButton, designHeight - 54);
        Canvas.SetLeft(_cursorPositionText, designWidth - 158);
        Canvas.SetTop(_cursorPositionText, designHeight - 43);
        Canvas.SetLeft(_languageText, designWidth - 52);
        Canvas.SetTop(_languageText, designHeight - 43);

        if (_monacoOverlayGrid.ColumnDefinitions.Count >= 3)
        {
            _monacoOverlayGrid.ColumnDefinitions[0].Width =
                new GridLength(304 * FixedHorizontalScale);
            _monacoOverlayGrid.ColumnDefinitions[2].Width =
                new GridLength(10 * FixedHorizontalScale);
        }
        if (_monacoOverlayGrid.RowDefinitions.Count >= 3)
        {
            _monacoOverlayGrid.RowDefinitions[0].Height =
                new GridLength(111 * FixedVerticalScale);
            _monacoOverlayGrid.RowDefinitions[2].Height =
                new GridLength(60 * FixedVerticalScale);
        }

        _scriptHubPage.Width = designWidth;
        _scriptHubPage.Height = designHeight;
        _scriptHubSurface.Width = Math.Max(260, designWidth - 80);
        _scriptHubSurface.Height = innerHeight;
        _scriptHubDivider.Height = innerHeight;
        _scriptHubDivider.Width = OnePhysicalPixelX;
        _scriptHubContentArea.Width = designWidth;
        _scriptHubContentArea.Height = designHeight;
        _scriptHubSearchBox.Width = Math.Max(160, designWidth - 249);
        _scriptHubCardsControl.Width = Math.Max(193, designWidth - 224);
        _scriptHubCardsScrollViewer.Width = Math.Max(193, designWidth - 224);
        _scriptHubCardsScrollViewer.Height = Math.Max(163, designHeight - 131);
        _scriptHubStateText.Width = Math.Max(160, designWidth - 249);

        _robotPage.Width = designWidth;
        _robotPage.Height = designHeight;
        _robotSurface.Width = Math.Max(260, designWidth - 80);
        _robotSurface.Height = innerHeight;
        Canvas.SetLeft(_robotWelcomeText, 424 + (widthDelta / 2));
        Canvas.SetLeft(_robotWelcomeLogo, 518 + (widthDelta / 2));
        Canvas.SetLeft(_robotWelcomeSubtitle, 171 + (widthDelta / 2));
        _robotInputBar.Width = Math.Max(220, designWidth - 103);
        Canvas.SetTop(_robotInputBar, designHeight - 83);
        Canvas.SetTop(_robotInputPlaceholder, designHeight - 63);

        Canvas.SetLeft(_robotModelsChip, 802 + widthDelta);
        Canvas.SetTop(_robotModelsChip, designHeight - 68);
        Canvas.SetLeft(_robotModelsChevron, 812 + widthDelta);
        Canvas.SetTop(_robotModelsChevron, designHeight - 57);
        Canvas.SetLeft(_robotModelsText, 809 + widthDelta);
        Canvas.SetTop(_robotModelsText, designHeight - 61);
        Canvas.SetLeft(_robotToolsChip, 878 + widthDelta);
        Canvas.SetTop(_robotToolsChip, designHeight - 68);
        Canvas.SetLeft(_robotToolsChevron, 885 + widthDelta);
        Canvas.SetTop(_robotToolsChevron, designHeight - 57);
        Canvas.SetLeft(_robotToolsText, 884.5 + widthDelta);
        Canvas.SetTop(_robotToolsText, designHeight - 61);
        Canvas.SetLeft(_robotAddChip, 935 + widthDelta);
        Canvas.SetTop(_robotAddChip, designHeight - 68);
        Canvas.SetLeft(_robotAddIcon, 944 + widthDelta);
        Canvas.SetTop(_robotAddIcon, designHeight - 60);

        Canvas.SetLeft(_robotDrawer, widthDelta);
        _robotDrawerSurface.Height = innerHeight;
        Canvas.SetTop(_robotEmptyTrashText, 569 + heightDelta);
        Canvas.SetTop(_robotEmptyTrashIcon, 565 + heightDelta);
        Canvas.SetLeft(_robotDrawerToggleChrome, 947 + widthDelta);
        Canvas.SetLeft(_robotDrawerToggleButton, 940 + widthDelta);

        _settingsPage.Width = designWidth;
        _settingsPage.Height = designHeight;
        _settingsSurface.Width = Math.Max(260, designWidth - 80);
        _settingsSurface.Height = innerHeight;
        _settingsDivider.Height = innerHeight;
        _settingsDivider.Width = OnePhysicalPixelX;
        _settingsContentPanel.Width = Math.Max(220, designWidth - 329);
        _settingsContentPanel.Height = Math.Max(160, designHeight - 153);

        _themesContentPanel.Width = Math.Max(300, designWidth - 292);
        _themesContentPanel.Height = Math.Max(260, designHeight - 124);
        _themesLibraryScrollViewer.Height = Math.Max(180, designHeight - 300);

        Canvas.SetTop(_settingsNavIcon, designHeight - 71);
        Canvas.SetTop(_settingsPageButton, designHeight - 85);
        _titleDragRegion.Width = Math.Max(190, designWidth - 154);
        Canvas.SetLeft(_minimizeWindowButton, designWidth - 146);
        Canvas.SetLeft(_maximizeWindowButton, designWidth - 99);
        Canvas.SetLeft(_closeWindowButton, designWidth - 53);

        _leftResizeHandle.Height = designHeight;
        Canvas.SetLeft(_rightResizeHandle, designWidth - 8);
        _rightResizeHandle.Height = designHeight;
        _topResizeHandle.Width = Math.Max(1, designWidth - 16);
        Canvas.SetTop(_bottomResizeHandle, designHeight - 6);
        _bottomResizeHandle.Width = Math.Max(1, designWidth - 16);
        Canvas.SetLeft(_topRightResizeHandle, designWidth - 14);
        Canvas.SetTop(_bottomLeftResizeHandle, designHeight - 14);
        Canvas.SetLeft(_bottomRightResizeHandle, designWidth - 14);
        Canvas.SetTop(_bottomRightResizeHandle, designHeight - 14);
    }

    private void CompleteStartupResponsiveLayout()
    {
        MinWidth = MainWindowWidth;
        MinHeight = MainWindowHeight;
        _startupLayoutComplete = true;
        ApplyResizablePreference(OrbitPreferences.ResizableEnabled);
        _lastAcceptedNormalSize = Bounds.Size;
        _latestObservedResizeSize = Bounds.Size;
        UpdateResponsiveDesignSurface();
        UpdateWindowChromeForState();

        var capacity = GetTabCapacity(Bounds.Width);
        if (_editorTabs.Count > capacity)
        {
            var requiredWidth = RequiredWindowWidthForTabs(_editorTabs.Count);
            var workingSize = GetWorkingAreaLogicalSize();
            if (requiredWidth <= workingSize.Width)
            {
                var expandedSize = new Size(requiredWidth, Bounds.Height);
                ApplyResponsiveWindowSize(expandedSize);
                _lastAcceptedNormalSize = expandedSize;
            }
        }

        RebuildEditorTabs();
    }

    private void MainWindow_PropertyChanged(object? sender, AvaloniaPropertyChangedEventArgs e)
    {
        if (e.Property != WindowStateProperty)
        {
            return;
        }

        if (_closeAnimationRunning)
        {
            return;
        }

        var previousState = _lastObservedWindowState;
        _lastObservedWindowState = WindowState;
        _restoreFromMaximizedPending =
            previousState == WindowState.Maximized && WindowState == WindowState.Normal;
        UpdateWindowChromeForState();

        if (_startupLayoutComplete && WindowState != WindowState.Minimized)
        {
            Dispatcher.UIThread.Post(() =>
            {
                UpdateResponsiveDesignSurface();
                UpdateWindowChromeForState();
                if (WindowState == WindowState.Normal && !_resizeTabsWarningOverlay.IsVisible)
                {
                    EvaluateResizeRequest(Bounds.Size);
                }

                RebuildEditorTabs();
            }, DispatcherPriority.Background);
        }
    }

    private void MainWindow_SizeChanged(object? sender, SizeChangedEventArgs e)
    {
        if (_closeAnimationRunning)
        {
            return;
        }

        UpdateResponsiveDesignSurface(e.NewSize);

        if (!_startupLayoutComplete || _applyingResponsiveSize || WindowState != WindowState.Normal)
        {
            if (_startupLayoutComplete && WindowState == WindowState.Maximized)
            {
                RebuildEditorTabs();
            }
            return;
        }

        _resizeEdgeReleaseTimer.Stop();
        _latestObservedResizeSize = e.NewSize;

        if (_editorTabs.Count <= GetTabCapacity(e.NewSize.Width))
        {
            _lastAcceptedNormalSize = e.NewSize;
        }

        if (!SmoothResizeAnimationActive)
        {
            RebuildEditorTabs();
        }
        _resizeEdgeReleaseTimer.Start();
    }

    private void EvaluateResizeRequest(Size requestedSize)
    {
        if (_applyingResponsiveSize || _resizeTabsWarningOverlay.IsVisible)
        {
            return;
        }

        var responsiveSize = new Size(
            Math.Max(MinWidth, requestedSize.Width),
            Math.Max(MinHeight, requestedSize.Height));
        var capacity = GetTabCapacity(responsiveSize.Width);
        if (_editorTabs.Count > capacity)
        {
            var retainedCapacity = Math.Max(1, capacity);
            _pendingRequestedSize = responsiveSize;
            _pendingResizeTabIds.Clear();
            _pendingResizeTabIds.AddRange(
                _editorTabs.Skip(retainedCapacity).Select(tab => tab.Id));

            _resizeWarningKeepsSquareChrome = _restoreFromMaximizedPending;
            if (_restoreFromMaximizedPending)
            {
                _restoreFromMaximizedPending = false;
                _applyingResponsiveSize = true;
                WindowState = WindowState.Maximized;
                _applyingResponsiveSize = false;
            }
            else
            {
                ApplyResponsiveWindowSize(_lastAcceptedNormalSize);
            }

            ShowResizeTabsWarning(retainedCapacity);
            return;
        }

        _restoreFromMaximizedPending = false;
        _lastAcceptedNormalSize = responsiveSize;
        RebuildEditorTabs();
    }

    private void ApplyResponsiveWindowSize(Size size)
    {
        _applyingResponsiveSize = true;
        try
        {
            Width = size.Width;
            Height = size.Height;
            UpdateResponsiveDesignSurface(size);

            var scaling = Screens.ScreenFromWindow(this)?.Scaling ?? 1;
            if (_activeResizeEdge is WindowEdge.West or WindowEdge.NorthWest or WindowEdge.SouthWest)
            {
                Position = new PixelPoint(
                    (int)Math.Round(_resizeAnchorRight - (size.Width * scaling)),
                    Position.Y);
            }
            if (_activeResizeEdge is WindowEdge.North or WindowEdge.NorthWest or WindowEdge.NorthEast)
            {
                Position = new PixelPoint(
                    Position.X,
                    (int)Math.Round(_resizeAnchorBottom - (size.Height * scaling)));
            }
        }
        finally
        {
            _applyingResponsiveSize = false;
        }
    }

    private void BeginResponsiveResize(WindowEdge edge)
    {
        _activeResizeEdge = edge;
        var scaling = Screens.ScreenFromWindow(this)?.Scaling ?? 1;
        _resizeAnchorRight = Position.X + (Bounds.Width * scaling);
        _resizeAnchorBottom = Position.Y + (Bounds.Height * scaling);
    }

    private void UpdateWindowChromeForState()
    {
        if (_mainWindowChrome is null)
        {
            return;
        }

        var maximized = IsWindowVisuallyMaximized;
        maximized = maximized ||
            (_resizeTabsWarningOverlay.IsVisible && _resizeWarningKeepsSquareChrome);
        _mainWindowChrome.CornerRadius = maximized ? new CornerRadius(0) : new CornerRadius(24);
        _mainWindowChrome.BorderThickness = maximized ? new Thickness(0) : OnePhysicalPixelBorder;
        _closeAnimationBackdrop.CornerRadius = maximized ? new CornerRadius(0) : new CornerRadius(20);
        _loadingWindowChrome.CornerRadius = maximized ? new CornerRadius(0) : new CornerRadius(18);
        _gistDialogBackdrop.CornerRadius = maximized ? new CornerRadius(0) : new CornerRadius(20);
        _resizeTabsWarningBackdrop.CornerRadius = maximized ? new CornerRadius(0) : new CornerRadius(20);
        _scriptBloxWarningBackdrop.CornerRadius = maximized ? new CornerRadius(0) : new CornerRadius(20);
        if (_setupWindowChrome is not null)
        {
            _setupWindowChrome.CornerRadius = maximized ? new CornerRadius(0) : new CornerRadius(24);
            _setupWindowChrome.BorderThickness = maximized ? new Thickness(0) : new Thickness(1);
        }

        var resizeHandlesVisible = OrbitPreferences.ResizableEnabled && !maximized;
        _leftResizeHandle.IsVisible = resizeHandlesVisible;
        _rightResizeHandle.IsVisible = resizeHandlesVisible;
        _topResizeHandle.IsVisible = resizeHandlesVisible;
        _bottomResizeHandle.IsVisible = resizeHandlesVisible;
        _topLeftResizeHandle.IsVisible = resizeHandlesVisible;
        _topRightResizeHandle.IsVisible = resizeHandlesVisible;
        _bottomLeftResizeHandle.IsVisible = resizeHandlesVisible;
        _bottomRightResizeHandle.IsVisible = resizeHandlesVisible;
    }

    private TabLayout GetResponsiveTabLayout()
    {
        var windowWidth = Math.Max(Bounds.Width, 1);
        var capacity = GetTabCapacity(windowWidth);
        var count = Math.Max(1, _editorTabs.Count);
        var availableWidth = Math.Max(
            MinimumTabWidth + AddTabButtonWidth,
            windowWidth - MonacoLeftOffset - MonacoRightOffset);
        var tabWidth = Math.Clamp(
            (availableWidth - AddTabButtonWidth) / count,
            MinimumTabWidth,
            PreferredTabWidth);
        var titleWidth = tabWidth - 16 - 18 - 25;

        return new TabLayout(
            TabWidth: tabWidth / FixedHorizontalScale,
            AddButtonWidth: AddTabButtonWidth / FixedHorizontalScale,
            HorizontalMargin: 8 / FixedHorizontalScale,
            IconColumnWidth: 18 / FixedHorizontalScale,
            CloseColumnWidth: 25 / FixedHorizontalScale,
            IconWidth: 12 / FixedHorizontalScale,
            IconHeight: 13 / FixedVerticalScale,
            DotWidth: 8 / FixedHorizontalScale,
            DotHeight: 8 / FixedVerticalScale,
            FontSize: 11 / FixedVerticalScale,
            PlusFontSize: 22 / FixedVerticalScale,
            RenameHeight: 29 / FixedVerticalScale,
            ShowTitle: titleWidth >= 14,
            ShowTooltip: tabWidth < 116,
            CanAdd: _editorTabs.Count < capacity,
            Capacity: capacity);
    }

    private static int GetTabCapacity(double windowWidth)
    {
        var availableWidth = Math.Max(
            MinimumTabWidth + AddTabButtonWidth,
            windowWidth - MonacoLeftOffset - MonacoRightOffset);
        return Math.Max(1, (int)Math.Floor(
            (availableWidth - AddTabButtonWidth) / MinimumTabWidth));
    }

    private static double RequiredWindowWidthForTabs(int tabCount) =>
        MonacoLeftOffset + MonacoRightOffset + AddTabButtonWidth +
        (tabCount * MinimumTabWidth);

    private async void NotifyTabCapacityReached()
    {
        _tabCapacityNoticeCancellation?.Cancel();
        _tabCapacityNoticeCancellation?.Dispose();
        _tabCapacityNoticeCancellation = new CancellationTokenSource();
        var cancellationToken = _tabCapacityNoticeCancellation.Token;
        var previousText = _cursorPositionText.Text;
        var notice = $"Max {GetTabCapacity(Bounds.Width)} tabs";
        _cursorPositionText.Text = notice;

        try
        {
            await Task.Delay(TimeSpan.FromSeconds(1.6), cancellationToken);
            if (_cursorPositionText.Text == notice)
            {
                _cursorPositionText.Text = previousText;
            }
        }
        catch (OperationCanceledException)
        {
            // A newer capacity notice replaced this one.
        }
    }

    private Size GetWorkingAreaLogicalSize()
    {
        var screen = Screens.ScreenFromWindow(this);
        if (screen is null)
        {
            return new Size(1920, 1080);
        }

        return new Size(
            screen.WorkingArea.Width / screen.Scaling,
            screen.WorkingArea.Height / screen.Scaling);
    }

    private void ShowResizeTabsWarning(int retainedCapacity)
    {
        var closingTabs = _editorTabs
            .Where(tab => _pendingResizeTabIds.Contains(tab.Id))
            .ToList();
        if (closingTabs.Count == 0)
        {
            return;
        }

        _resizeTabsWarningSummaryText.Text =
            $"At {Math.Round(_pendingRequestedSize.Width)} × {Math.Round(_pendingRequestedSize.Height)}, " +
            $"Orbit can reliably show {retainedCapacity} tabs. Continue to close " +
            $"{closingTabs.Count} overflow {(closingTabs.Count == 1 ? "tab" : "tabs")}.";
        _resizeTabsWarningNamesText.Text = string.Join(
            Environment.NewLine,
            closingTabs.Select(tab => $"•  {tab.Title}"));
        _resizeTabsWarningConfirmButton.Content = closingTabs.Count == 1
            ? "Close 1 Tab"
            : $"Close {closingTabs.Count} Tabs";

        _resizeTabsWarningOverlay.IsVisible = true;
        UpdateMonacoVisibility();
        _ = AnimateResizeTabsWarningInAsync();
    }

    private async Task AnimateResizeTabsWarningInAsync()
    {
        _resizeTabsWarningAnimationCancellation?.Cancel();
        _resizeTabsWarningAnimationCancellation?.Dispose();
        _resizeTabsWarningAnimationCancellation = new CancellationTokenSource();
        var cancellationToken = _resizeTabsWarningAnimationCancellation.Token;

        if (!SystemAnimationsEnabled())
        {
            _resizeTabsWarningBackdrop.Opacity = 1;
            _resizeTabsWarningPopup.Opacity = 1;
            _resizeTabsWarningScale.ScaleX = 1;
            _resizeTabsWarningScale.ScaleY = 1;
            _resizeTabsWarningTranslation.Y = 0;
            return;
        }

        _resizeTabsWarningBackdrop.Opacity = 0;
        _resizeTabsWarningPopup.Opacity = 0;
        _resizeTabsWarningScale.ScaleX = 0.94;
        _resizeTabsWarningScale.ScaleY = 0.94;
        _resizeTabsWarningTranslation.Y = 9;

        try
        {
            await AnimateAsync(
                TimeSpan.FromMilliseconds(270),
                progress =>
                {
                    _resizeTabsWarningBackdrop.Opacity = progress;
                    _resizeTabsWarningPopup.Opacity = progress;
                    _resizeTabsWarningScale.ScaleX = Lerp(0.94, 1, progress);
                    _resizeTabsWarningScale.ScaleY = Lerp(0.94, 1, progress);
                    _resizeTabsWarningTranslation.Y = Lerp(9, 0, progress);
                },
                CubicEaseOut,
                cancellationToken);
        }
        catch (OperationCanceledException)
        {
            // A dismissal transition took over.
        }
    }

    private async void ResizeTabsWarningCancel_Click(object? sender, RoutedEventArgs e)
    {
        var returnToMaximized = _resizeWarningKeepsSquareChrome;
        _pendingResizeTabIds.Clear();
        await HideResizeTabsWarningAsync();
        if (returnToMaximized && WindowState != WindowState.Maximized)
        {
            WindowState = WindowState.Maximized;
        }
        _resizeWarningKeepsSquareChrome = false;
        UpdateWindowChromeForState();
    }

    private async void ResizeTabsWarningConfirm_Click(object? sender, RoutedEventArgs e)
    {
        if (_pendingResizeTabIds.Count == 0)
        {
            await HideResizeTabsWarningAsync();
            return;
        }

        var activeTabWillClose = _pendingResizeTabIds.Contains(_activeEditorTab.Id);
        _editorTabs.RemoveAll(tab => _pendingResizeTabIds.Contains(tab.Id));
        _pendingResizeTabIds.Clear();
        if (_editorTabs.Count == 0)
        {
            var replacement = new EditorTabState { Title = "Script 1", Extension = ".lua" };
            _editorTabs.Add(replacement);
            _activeEditorTab = replacement;
        }
        else if (activeTabWillClose)
        {
            _activeEditorTab = _editorTabs[^1];
        }

        RebuildEditorTabs();
        PushActiveTabToMonaco();
        ScheduleWorkspaceSave();
        await HideResizeTabsWarningAsync();
        _resizeWarningKeepsSquareChrome = false;

        var requestedSize = _pendingRequestedSize;
        if (WindowState == WindowState.Maximized)
        {
            WindowState = WindowState.Normal;
        }

        Dispatcher.UIThread.Post(() =>
        {
            ApplyResponsiveWindowSize(requestedSize);
            _lastAcceptedNormalSize = requestedSize;
            RebuildEditorTabs();
        }, DispatcherPriority.Background);
    }

    private async Task HideResizeTabsWarningAsync()
    {
        if (!_resizeTabsWarningOverlay.IsVisible)
        {
            return;
        }

        _resizeTabsWarningAnimationCancellation?.Cancel();
        _resizeTabsWarningAnimationCancellation?.Dispose();
        _resizeTabsWarningAnimationCancellation = new CancellationTokenSource();
        var cancellationToken = _resizeTabsWarningAnimationCancellation.Token;

        try
        {
            if (SystemAnimationsEnabled())
            {
                var backdropOpacity = _resizeTabsWarningBackdrop.Opacity;
                var popupOpacity = _resizeTabsWarningPopup.Opacity;
                var scale = _resizeTabsWarningScale.ScaleX;
                var translation = _resizeTabsWarningTranslation.Y;
                await AnimateAsync(
                    TimeSpan.FromMilliseconds(210),
                    progress =>
                    {
                        _resizeTabsWarningBackdrop.Opacity = Lerp(backdropOpacity, 0, progress);
                        _resizeTabsWarningPopup.Opacity = Lerp(popupOpacity, 0, progress);
                        _resizeTabsWarningScale.ScaleX = Lerp(scale, 0.96, progress);
                        _resizeTabsWarningScale.ScaleY = Lerp(scale, 0.96, progress);
                        _resizeTabsWarningTranslation.Y = Lerp(translation, 6, progress);
                    },
                    CubicEaseIn,
                    cancellationToken);
            }

            _resizeTabsWarningOverlay.IsVisible = false;
            UpdateWindowChromeForState();
            UpdateMonacoVisibility();
        }
        catch (OperationCanceledException)
        {
            // A newer warning transition replaced this fade.
        }
    }

    private readonly record struct TabLayout(
        double TabWidth,
        double AddButtonWidth,
        double HorizontalMargin,
        double IconColumnWidth,
        double CloseColumnWidth,
        double IconWidth,
        double IconHeight,
        double DotWidth,
        double DotHeight,
        double FontSize,
        double PlusFontSize,
        double RenameHeight,
        bool ShowTitle,
        bool ShowTooltip,
        bool CanAdd,
        int Capacity);
}
