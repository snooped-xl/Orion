using Avalonia;
using Avalonia.Animation;
using Avalonia.Controls;
using Avalonia.Controls.Documents;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.Layout;
using Avalonia.Markup.Xaml;
using Avalonia.Media;
using Avalonia.Platform.Storage;
using Avalonia.Threading;
using Avalonia.VisualTree;
using System.Diagnostics;
using System.Text.Json;
using Ellipse = Avalonia.Controls.Shapes.Ellipse;
using ShapePath = Avalonia.Controls.Shapes.Path;

namespace OrbitAvalonia;

/// <summary>
/// Native Avalonia preservation of the Zenith V2 Svelte/Tauri interface.
/// Its original remote launcher/injector is intentionally not included;
/// execution is routed through Orion's app-lifetime bridge.
/// </summary>
public sealed partial class ZenithWindow : Window
{
    private const string AppBackground = "#0A0A0A";
    private const string CardBackground = "#08FFFFFF";
    private const string MutedForeground = "#E69A9A9A";

    private readonly Uri _monacoAddress;
    private readonly string _scriptsDirectory;
    private readonly EditorWorkspaceState _workspace;
    private readonly Action<EditorWorkspaceState> _returnToOrion;
    private readonly UnifiedBridgeServer _bridge = UnifiedBridgeServer.Shared;
    private readonly Dictionary<string, Control> _pages = new(StringComparer.Ordinal);
    private readonly Dictionary<string, (Button Button, Border Indicator)> _navigation = new(StringComparer.Ordinal);
    private readonly List<ZenithOutputLine> _outputLines = [];

    private readonly Border _chrome;
    private readonly Border _navigationPanel;
    private readonly NativeWebView _editor;
    private readonly StackPanel _tabBar;
    private readonly StackPanel _fileList;
    private readonly TextBlock _bridgeStatusText;
    private readonly Border _bridgeStatusGlow;
    private readonly Ellipse _bridgeStatusDotGlow;
    private readonly Ellipse _bridgeStatusDot;
    private readonly Button _executeButton;
    private readonly Button _attachButton;
    private readonly TextBlock _attachLabel;
    private readonly SelectableTextBlock _outputText;
    private readonly ScrollViewer _outputScroll;
    private readonly Border _outputResizeGrip;
    private readonly ShapePath _outputChevron;
    private readonly Grid _editorStack;
    private readonly Grid _editorSplit;
    private readonly ShapePath _fileListChevron;
    private readonly TextBlock _fileListTitle;
    private readonly Grid _settingsMainPage;
    private readonly Grid _settingsSectionPage;
    private readonly TextBlock _settingsSectionTitle;
    private readonly StackPanel _settingsRowsPanel;
    private readonly Border? _scriptHubNotice;
    private readonly Grid? _loadingOverlay;
    private readonly DispatcherTimer _navigationCloseTimer;
    private readonly ScriptHubService _zenithHubService = new();
    private readonly TextBox _zenithHubSearchBox;
    private readonly ComboBox _zenithHubProviderBox;
    private readonly TextBlock _zenithHubSourceHeader;
    private readonly StackPanel _zenithHubCardsPanel;
    private readonly ScrollViewer _zenithHubScrollViewer;
    private readonly StackPanel _zenithHubStatePanel;
    private readonly TextBlock _zenithHubStateTitle;
    private readonly TextBlock _zenithHubStateDescription;
    private readonly Button _zenithHubClearSearchButton;
    private readonly Button _zenithHubBrowsePopularButton;
    private readonly Button _zenithHubRecentButton;
    private readonly Button _zenithHubPopularButton;
    private readonly Button _zenithHubUniversalButton;
    private readonly List<ScriptHubCardModel> _zenithHubCards = [];
    private readonly HashSet<string> _zenithHubCardKeys = new(StringComparer.Ordinal);

    private EditorTabState _activeTab;
    private TaskCompletionSource<string>? _pendingSnapshot;
    private string _currentPage = "Home";
    private bool _editorReady;
    private bool _editorSourceAssigned;
    private bool _closingForOrion;
    private bool _returnRequested;
    private bool _outputExpanded = true;
    private bool _outputResizing;
    private bool _outputHasLiveContent;
    private double _outputExpandedHeight = 140;
    private double _outputResizeStartPointerY;
    private double _outputResizeStartHeight;
    private ScriptHubProvider _zenithHubProvider = ScriptHubProvider.RobloxScripts;
    private string _zenithHubFilter = "recent";
    private int _zenithHubPage = 1;
    private bool _zenithHubHasMore = true;
    private bool _zenithHubLoading;
    private bool _zenithHubLoaded;
    private bool _zenithHubInitialising = true;
    private long _zenithHubLoadVersion;
    private int _zenithHubColumnCount;
    private CancellationTokenSource? _zenithHubLoadCancellation;
    private CancellationTokenSource? _zenithHubSearchCancellation;

    public ZenithWindow() : this(
        new Uri("http://127.0.0.1:1/index.html"),
        Path.Combine(AppContext.BaseDirectory, "Scripts"),
        CreateDefaultWorkspace(),
        static _ => { })
    {
    }

    internal ZenithWindow(
        Uri monacoAddress,
        string scriptsDirectory,
        EditorWorkspaceState initialWorkspace,
        Action<EditorWorkspaceState> returnToOrion)
    {
        _monacoAddress = monacoAddress;
        _scriptsDirectory = scriptsDirectory;
        _workspace = initialWorkspace.CloneDetached();
        if (_workspace.Tabs.Count == 0)
        {
            var tab = NewTabState();
            _workspace.Tabs.Add(tab);
            _workspace.ActiveTabId = tab.Id;
        }

        _activeTab = _workspace.Tabs.FirstOrDefault(tab => tab.Id == _workspace.ActiveTabId)
            ?? _workspace.Tabs[0];
        _returnToOrion = returnToOrion;

        AvaloniaXamlLoader.Load(this);
        Topmost = OrbitPreferences.TopMostEnabled;
        CanResize = OrbitPreferences.ResizableEnabled;

        _chrome = Required<Border>("ZenithChrome");
        _navigationPanel = Required<Border>("NavigationPanel");
        _editor = Required<NativeWebView>("ZenithEditorWebView");
        _tabBar = Required<StackPanel>("ZenithTabBar");
        _fileList = Required<StackPanel>("ZenithFileList");
        _bridgeStatusText = Required<TextBlock>("BridgeStatusText");
        _bridgeStatusGlow = Required<Border>("BridgeStatusGlow");
        _bridgeStatusDotGlow = Required<Ellipse>("BridgeStatusDotGlow");
        _bridgeStatusDot = Required<Ellipse>("BridgeStatusDot");
        _executeButton = Required<Button>("ZenithExecuteButton");
        _attachButton = Required<Button>("ZenithAttachButton");
        _attachLabel = Required<TextBlock>("ZenithAttachLabel");
        _outputText = Required<SelectableTextBlock>("ZenithOutputText");
        _outputScroll = Required<ScrollViewer>("ZenithOutputScroll");
        _outputResizeGrip = Required<Border>("ZenithOutputResizeGrip");
        _outputChevron = Required<ShapePath>("ZenithOutputChevron");
        _editorStack = Required<Grid>("ZenithEditorStack");
        _editorSplit = Required<Grid>("ZenithEditorSplit");
        _fileListChevron = Required<ShapePath>("ZenithFileListChevron");
        _fileListTitle = Required<TextBlock>("ZenithFileListTitle");
        _settingsMainPage = Required<Grid>("SettingsMainPage");
        _settingsSectionPage = Required<Grid>("SettingsSectionPage");
        _settingsSectionTitle = Required<TextBlock>("SettingsSectionTitle");
        _settingsRowsPanel = Required<StackPanel>("SettingsRowsPanel");
        _scriptHubNotice = this.FindControl<Border>("ScriptHubNotice");
        _loadingOverlay = this.FindControl<Grid>("ZenithLoadingOverlay");
        _zenithHubSearchBox = Required<TextBox>("ZenithHubSearchBox");
        _zenithHubProviderBox = Required<ComboBox>("ZenithHubProviderBox");
        _zenithHubSourceHeader = Required<TextBlock>("ZenithHubSourceHeader");
        _zenithHubCardsPanel = Required<StackPanel>("ZenithHubCardsPanel");
        _zenithHubScrollViewer = Required<ScrollViewer>("ZenithHubScrollViewer");
        _zenithHubStatePanel = Required<StackPanel>("ZenithHubStatePanel");
        _zenithHubStateTitle = Required<TextBlock>("ZenithHubStateTitle");
        _zenithHubStateDescription = Required<TextBlock>("ZenithHubStateDescription");
        _zenithHubClearSearchButton = Required<Button>("ZenithHubClearSearchButton");
        _zenithHubBrowsePopularButton = Required<Button>("ZenithHubBrowsePopularButton");
        _zenithHubRecentButton = Required<Button>("ZenithHubRecentButton");
        _zenithHubPopularButton = Required<Button>("ZenithHubPopularButton");
        _zenithHubUniversalButton = Required<Button>("ZenithHubUniversalButton");
        InitializeZenithDocumentation();
        _navigationCloseTimer = new DispatcherTimer
        {
            Interval = TimeSpan.FromSeconds(2)
        };
        _navigationCloseTimer.Tick += NavigationCloseTimer_Tick;

        foreach (var name in new[] { "Home", "Execution", "ScriptHub", "Documentation", "Help", "Settings" })
        {
            _pages[name] = Required<Control>(name + "Page");
            _navigation[name] = (
                Required<Button>(name + "NavButton"),
                Required<Border>(name + "NavIndicator"));
        }

        _editor.WebMessageReceived += Editor_WebMessageReceived;
        _bridge.ConnectionChanged += Bridge_ConnectionChanged;
        _bridge.LogReceived += Bridge_LogReceived;
        Opened += ZenithWindow_Opened;
        Closed += ZenithWindow_Closed;
        SizeChanged += ZenithWindow_SizeChanged;
        PropertyChanged += ZenithWindow_PropertyChanged;
        KeyDown += ZenithWindow_KeyDown;

        RenderTabs();
        RefreshFileList();
        _zenithHubProvider = LoadZenithHubProvider();
        _zenithHubProviderBox.SelectedIndex = ZenithProviderIndex(_zenithHubProvider);
        UpdateZenithHubProviderHeader();
        UpdateZenithHubFilterVisuals();
        _zenithHubInitialising = false;
        ConfigureActionGlow("ZenithAttachButton", "ZenithAttachBlob");
        ConfigureActionGlow("ZenithExecuteButton", "ZenithExecuteBlob");
        ConfigureActionGlow("ZenithOpenButton", "ZenithOpenBlob");
        ConfigureActionGlow("ZenithSaveButton", "ZenithSaveBlob");
        ConfigureActionGlow("ZenithClearButton", "ZenithClearBlob");
        SetPage("Home");
        ApplyBridgeState(_bridge.IsConnected);
    }

    private void ConfigureActionGlow(string buttonName, string blobName)
    {
        var button = Required<Button>(buttonName);
        var blob = Required<Border>(blobName);
        var resting = new ScaleTransform(.9, .9);
        var hovered = new ScaleTransform(1, 1);
        var pressed = new ScaleTransform(1.05, 1.05);

        blob.Opacity = 0;
        blob.RenderTransform = resting;
        button.PointerEntered += (_, _) =>
        {
            blob.Opacity = 1;
            blob.RenderTransform = hovered;
        };
        button.PointerExited += (_, _) =>
        {
            blob.Opacity = 0;
            blob.RenderTransform = resting;
        };
        button.PointerPressed += (_, _) =>
        {
            blob.Opacity = 1;
            blob.RenderTransform = pressed;
        };
        button.PointerReleased += (_, _) =>
        {
            blob.Opacity = button.IsPointerOver ? 1 : 0;
            blob.RenderTransform = button.IsPointerOver ? hovered : resting;
        };
    }

    internal void CloseForOrion()
    {
        _closingForOrion = true;
        Close();
    }

    private T Required<T>(string name) where T : Control
        => this.FindControl<T>(name)
           ?? throw new InvalidOperationException($"Zenith control '{name}' was not created.");

    private static EditorWorkspaceState CreateDefaultWorkspace()
    {
        var tab = NewTabState();
        return new EditorWorkspaceState { Tabs = [tab], ActiveTabId = tab.Id };
    }

    private static EditorTabState NewTabState() => new()
    {
        Title = "Tab 1",
        Extension = ".lua",
        Content = string.Empty
    };

    private async void ZenithWindow_Opened(object? sender, EventArgs e)
    {
        Opened -= ZenithWindow_Opened;
        if (_loadingOverlay is not null)
        {
            await Task.Delay(520);
            _loadingOverlay.Opacity = 0;
            await Task.Delay(180);
            _loadingOverlay.IsVisible = false;
        }
    }

    private void ZenithWindow_Closed(object? sender, EventArgs e)
    {
        _editor.WebMessageReceived -= Editor_WebMessageReceived;
        _bridge.ConnectionChanged -= Bridge_ConnectionChanged;
        _bridge.LogReceived -= Bridge_LogReceived;
        _navigationCloseTimer.Stop();
        _navigationCloseTimer.Tick -= NavigationCloseTimer_Tick;
        SizeChanged -= ZenithWindow_SizeChanged;
        _pendingSnapshot?.TrySetCanceled();
        _zenithHubLoadCancellation?.Cancel();
        _zenithHubSearchCancellation?.Cancel();
        _zenithHubLoadCancellation?.Dispose();
        _zenithHubSearchCancellation?.Dispose();
        _zenithHubService.Dispose();
        if (!_closingForOrion && !_returnRequested)
        {
            _returnRequested = true;
            _returnToOrion(CaptureWorkspace());
        }
    }

    private void ZenithWindow_PropertyChanged(object? sender, AvaloniaPropertyChangedEventArgs e)
    {
        if (e.Property != WindowStateProperty)
        {
            return;
        }

        var maximized = WindowState == WindowState.Maximized;
        _chrome.CornerRadius = maximized ? new CornerRadius(0) : new CornerRadius(7);
        _chrome.BorderThickness = maximized ? new Thickness(0) : new Thickness(1);
    }

    private void ZenithWindow_SizeChanged(object? sender, SizeChangedEventArgs e)
    {
        if (_currentPage == "ScriptHub" && _zenithHubCards.Count > 0 &&
            GetZenithHubColumnCount(e.NewSize.Width) != _zenithHubColumnCount)
        {
            RenderZenithHubCards(animate: false);
        }
    }

    private void ZenithWindow_KeyDown(object? sender, KeyEventArgs e)
    {
        if (_currentPage == "ScriptHub" &&
            (e.KeyModifiers & KeyModifiers.Control) != 0 && e.Key == Key.K)
        {
            _zenithHubSearchBox.Focus();
            _zenithHubSearchBox.SelectAll();
            e.Handled = true;
        }
        else if ((e.KeyModifiers & KeyModifiers.Control) != 0 && e.Key == Key.S)
        {
            _ = SaveCurrentFileAsync();
            e.Handled = true;
        }
        else if ((e.KeyModifiers & KeyModifiers.Control) != 0 && e.Key == Key.Enter)
        {
            _ = ExecuteCurrentScriptAsync();
            e.Handled = true;
        }
        else if ((e.KeyModifiers & KeyModifiers.Control) != 0 && e.Key == Key.W)
        {
            CloseTab(_activeTab);
            e.Handled = true;
        }
    }

    private void TitleBar_PointerPressed(object? sender, PointerPressedEventArgs e)
    {
        var point = e.GetCurrentPoint(this);
        if (!point.Properties.IsLeftButtonPressed)
        {
            return;
        }

        if (e.Source is Visual visual &&
            (visual is Button || visual.GetVisualAncestors().OfType<Button>().Any()))
        {
            return;
        }

        if (e.ClickCount == 2 && CanResize)
        {
            WindowState = WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized;
            return;
        }

        if (WindowState != WindowState.Maximized)
        {
            BeginMoveDrag(e);
        }
    }

    private void Minimize_Click(object? sender, RoutedEventArgs e) => WindowState = WindowState.Minimized;

    private void Maximize_Click(object? sender, RoutedEventArgs e)
    {
        if (CanResize)
        {
            WindowState = WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized;
        }
    }

    private void Close_Click(object? sender, RoutedEventArgs e)
    {
        _returnRequested = true;
        Environment.Exit(0);
    }

    private void NavigationPanel_PointerEntered(object? sender, PointerEventArgs e)
    {
        _navigationCloseTimer.Stop();
        _navigationPanel.Width = 200;
    }

    private void NavigationPanel_PointerExited(object? sender, PointerEventArgs e)
    {
        _navigationCloseTimer.Stop();
        _navigationCloseTimer.Start();
    }

    private void NavigationCloseTimer_Tick(object? sender, EventArgs e)
    {
        _navigationCloseTimer.Stop();
        _navigationPanel.Width = 56;
    }

    private void NavButton_Click(object? sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: string page })
        {
            SetPage(page);
        }
    }

    private void SetPage(string page)
    {
        if (!_pages.ContainsKey(page))
        {
            return;
        }

        _currentPage = page;
        foreach (var pair in _pages)
        {
            pair.Value.IsVisible = pair.Key == page;
        }

        foreach (var pair in _navigation)
        {
            var active = pair.Key == page;
            pair.Value.Indicator.Opacity = active ? 1 : 0;
            pair.Value.Button.Background = Brushes.Transparent;
            ToolTip.SetIsOpen(pair.Value.Button, false);
        }

        if (page == "Execution")
        {
            RevealEditor();
        }
        else
        {
            _editor.IsVisible = false;
        }

        if (page == "Settings")
        {
            ShowSettingsMain();
        }

        if (page == "ScriptHub" && !_zenithHubLoaded)
        {
            _ = ReloadZenithHubAsync();
        }
    }

    private void RevealEditor()
    {
        _editor.IsVisible = true;
        if (_editorSourceAssigned)
        {
            return;
        }

        _editorSourceAssigned = true;
        _editor.Source = new UriBuilder(_monacoAddress)
        {
            Query = "transparent=1&shell=zenith&radius=8"
        }.Uri;
    }

    private void RenderTabs()
    {
        _tabBar.Children.Clear();
        foreach (var tab in _workspace.Tabs)
        {
            _tabBar.Children.Add(CreateTabVisual(tab));
        }
    }

    private Control CreateTabVisual(EditorTabState tab)
    {
        var active = tab.Id == _activeTab.Id;
        var border = new Border
        {
            Height = 32,
            MinWidth = 84,
            MaxWidth = 190,
            Margin = new Thickness(0, 4),
            Padding = new Thickness(8, 4, 4, 4),
            CornerRadius = new CornerRadius(6),
            ClipToBounds = true,
            Background = active ? Brush.Parse("#14FFFFFF") : Brushes.Transparent,
            VerticalAlignment = VerticalAlignment.Center,
            Cursor = new Cursor(StandardCursorType.Hand)
        };
        var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("*,20") };
        var indicator = new Border
        {
            Width = 4,
            HorizontalAlignment = HorizontalAlignment.Left,
            VerticalAlignment = VerticalAlignment.Stretch,
            Background = new LinearGradientBrush
            {
                StartPoint = new RelativePoint(0.5, 0, RelativeUnit.Relative),
                EndPoint = new RelativePoint(0.5, 1, RelativeUnit.Relative),
                GradientStops =
                {
                    new GradientStop(Color.Parse("#3B82F6"), 0),
                    new GradientStop(Color.Parse("#2563EB"), 1)
                }
            },
            CornerRadius = new CornerRadius(0, 4, 4, 0),
            Margin = new Thickness(-8, -4, 0, -4),
            Opacity = active ? 1 : 0
        };
        var title = new TextBlock
        {
            Text = tab.Title,
            FontSize = 16,
            FontWeight = FontWeight.Regular,
            Foreground = Brush.Parse(active ? "#FFFFFF" : "#80FFFFFF"),
            VerticalAlignment = VerticalAlignment.Center,
            TextTrimming = TextTrimming.CharacterEllipsis
        };
        Grid.SetColumn(title, 0);
        var close = new Button
        {
            Content = "×"
        };
        close.Classes.Add("zenith-tab-close");
        close.Click += (_, e) =>
        {
            e.Handled = true;
            CloseTab(tab);
        };
        Grid.SetColumn(close, 1);
        grid.Children.Add(indicator);
        grid.Children.Add(title);
        grid.Children.Add(close);
        border.Child = grid;
        border.PointerEntered += (_, _) => border.Background = Brush.Parse("#1FFFFFFF");
        border.PointerExited += (_, _) => border.Background = active ? Brush.Parse("#14FFFFFF") : Brushes.Transparent;
        border.PointerPressed += (_, e) =>
        {
            if (e.GetCurrentPoint(border).Properties.IsLeftButtonPressed)
            {
                SelectTab(tab);
                e.Handled = true;
            }
        };
        return border;
    }

    private void NewTab_Click(object? sender, RoutedEventArgs e)
    {
        var tab = new EditorTabState
        {
            Title = $"Tab {_workspace.Tabs.Count + 1}",
            Extension = ".lua",
            Content = string.Empty
        };
        _workspace.Tabs.Add(tab);
        SelectTab(tab);
    }

    private void SelectTab(EditorTabState tab)
    {
        _activeTab = tab;
        _workspace.ActiveTabId = tab.Id;
        PushActiveTabToEditor();
        RenderTabs();
    }

    private void CloseTab(EditorTabState tab)
    {
        if (_workspace.Tabs.Count <= 1)
        {
            return;
        }

        var index = _workspace.Tabs.IndexOf(tab);
        _workspace.Tabs.Remove(tab);
        if (_activeTab.Id == tab.Id)
        {
            SelectTab(_workspace.Tabs[Math.Clamp(index - 1, 0, _workspace.Tabs.Count - 1)]);
        }
        else
        {
            RenderTabs();
        }
    }

    private void Editor_WebMessageReceived(object? sender, WebMessageReceivedEventArgs args)
    {
        if (string.IsNullOrWhiteSpace(args.Body))
        {
            return;
        }

        try
        {
            using var document = JsonDocument.Parse(args.Body);
            var root = document.RootElement;
            if (!root.TryGetProperty("type", out var typeProperty))
            {
                return;
            }

            switch (typeProperty.GetString())
            {
                case "ready":
                    Dispatcher.UIThread.Post(() =>
                    {
                        _editorReady = true;
                        PushActiveTabToEditor();
                    });
                    break;
                case "contentChanged" when root.TryGetProperty("content", out var contentProperty):
                {
                    var content = contentProperty.GetString() ?? string.Empty;
                    var tab = _activeTab;
                    Dispatcher.UIThread.Post(() => tab.Content = content);
                    break;
                }
                case "contentChangedDelta" when root.TryGetProperty("changes", out var changesProperty):
                {
                    var changes = changesProperty.Clone();
                    var tab = _activeTab;
                    Dispatcher.UIThread.Post(() =>
                    {
                        if (EditorContentDelta.TryApply(changes, tab.Content, out var content))
                        {
                            tab.Content = content;
                        }
                    });
                    break;
                }
                case "contentSnapshot" when root.TryGetProperty("content", out var snapshotProperty):
                {
                    var content = snapshotProperty.GetString() ?? string.Empty;
                    var tab = _activeTab;
                    Dispatcher.UIThread.Post(() =>
                    {
                        tab.Content = content;
                        _pendingSnapshot?.TrySetResult(content);
                    });
                    break;
                }
                case "executeRequested" when root.TryGetProperty("content", out var executeProperty):
                {
                    var content = executeProperty.GetString() ?? string.Empty;
                    Dispatcher.UIThread.Post(() =>
                    {
                        _activeTab.Content = content;
                        if (_bridge.IsConnected)
                        {
                            _bridge.EnqueueExecute(content);
                        }
                    });
                    break;
                }
                case "zenithHelpRequested":
                    Dispatcher.UIThread.Post(() =>
                    {
                        SetPage("Help");
                        ShowZenithHelpArticle("Keyboard Shortcuts Reference");
                    });
                    break;
            }
        }
        catch (JsonException)
        {
            // Ignore messages which were not emitted by Orion's Monaco host.
        }
    }

    private void PushActiveTabToEditor()
    {
        if (!_editorReady)
        {
            return;
        }

        var content = JsonSerializer.Serialize(_activeTab.Content);
        var language = JsonSerializer.Serialize(LanguageForExtension(_activeTab.Extension));
        try
        {
            _editor.InvokeScript($"window.orbitSetContent && window.orbitSetContent({content}, {language});");
        }
        catch (InvalidOperationException)
        {
            _editorReady = false;
        }
    }

    private async Task<string> RequestEditorContentAsync()
    {
        if (!_editorReady)
        {
            return _activeTab.Content;
        }

        var completion = new TaskCompletionSource<string>(TaskCreationOptions.RunContinuationsAsynchronously);
        _pendingSnapshot?.TrySetCanceled();
        _pendingSnapshot = completion;
        try
        {
            await _editor.InvokeScript("window.orionRequestSnapshot && window.orionRequestSnapshot();");
            var completed = await Task.WhenAny(completion.Task, Task.Delay(700));
            return completed == completion.Task ? await completion.Task : _activeTab.Content;
        }
        catch (InvalidOperationException)
        {
            _editorReady = false;
            return _activeTab.Content;
        }
        finally
        {
            if (ReferenceEquals(_pendingSnapshot, completion))
            {
                _pendingSnapshot = null;
            }
        }
    }

    private static string LanguageForExtension(string extension) => extension.ToLowerInvariant() switch
    {
        ".md" or ".markdown" => "markdown",
        ".json" => "json",
        ".js" or ".ts" => "javascript",
        ".txt" => "plaintext",
        _ => "lua"
    };

    private async void Execute_Click(object? sender, RoutedEventArgs e) => await ExecuteCurrentScriptAsync();

    private async Task ExecuteCurrentScriptAsync()
    {
        var content = await RequestEditorContentAsync();
        _activeTab.Content = content;
        if (_bridge.IsConnected && !string.IsNullOrWhiteSpace(content))
        {
            _bridge.EnqueueExecute(content);
        }
    }

    private void Attach_Click(object? sender, RoutedEventArgs e)
    {
        // Zenith's original attach action is replaced by the universal bridge.
        ApplyBridgeState(_bridge.IsConnected);
    }

    private async void OpenFile_Click(object? sender, RoutedEventArgs e)
    {
        var files = await StorageProvider.OpenFilePickerAsync(new FilePickerOpenOptions
        {
            Title = "Open script",
            AllowMultiple = false,
            FileTypeFilter =
            [
                new FilePickerFileType("Script files")
                {
                    Patterns = ["*.lua", "*.luau", "*.txt", "*.md", "*.json"]
                }
            ]
        });
        var file = files.FirstOrDefault();
        if (file is null)
        {
            return;
        }

        await using var stream = await file.OpenReadAsync();
        using var reader = new StreamReader(stream);
        var tab = new EditorTabState
        {
            Title = Path.GetFileNameWithoutExtension(file.Name),
            Extension = Path.GetExtension(file.Name) is { Length: > 0 } extension ? extension : ".lua",
            Content = await reader.ReadToEndAsync()
        };
        _workspace.Tabs.Add(tab);
        SelectTab(tab);
    }

    private async void SaveFile_Click(object? sender, RoutedEventArgs e) => await SaveCurrentFileAsync();

    private async Task SaveCurrentFileAsync()
    {
        _activeTab.Content = await RequestEditorContentAsync();
        var file = await StorageProvider.SaveFilePickerAsync(new FilePickerSaveOptions
        {
            Title = "Save script",
            SuggestedFileName = _activeTab.Title + _activeTab.Extension,
            DefaultExtension = "lua",
            FileTypeChoices =
            [
                new FilePickerFileType("Lua script") { Patterns = ["*.lua"] },
                new FilePickerFileType("Luau script") { Patterns = ["*.luau"] },
                new FilePickerFileType("Text file") { Patterns = ["*.txt"] }
            ]
        });
        if (file is null)
        {
            return;
        }

        await using var stream = await file.OpenWriteAsync();
        stream.SetLength(0);
        await using var writer = new StreamWriter(stream);
        await writer.WriteAsync(_activeTab.Content);
    }

    private async void ZenithHubSearchBox_TextChanged(object? sender, TextChangedEventArgs e)
    {
        if (_zenithHubInitialising)
        {
            return;
        }

        _zenithHubSearchCancellation?.Cancel();
        _zenithHubSearchCancellation?.Dispose();
        var cancellation = new CancellationTokenSource();
        _zenithHubSearchCancellation = cancellation;
        try
        {
            await Task.Delay(500, cancellation.Token);
            await ReloadZenithHubAsync();
        }
        catch (OperationCanceledException)
        {
            // A newer search term superseded this debounce.
        }
    }

    private void ZenithHubProviderBox_SelectionChanged(object? sender, SelectionChangedEventArgs e)
    {
        if (_zenithHubInitialising ||
            _zenithHubProviderBox.SelectedItem is not ComboBoxItem { Tag: string providerName } ||
            !Enum.TryParse(providerName, out ScriptHubProvider provider) ||
            provider == _zenithHubProvider)
        {
            return;
        }

        _zenithHubProvider = provider;
        SaveZenithHubProvider(provider);
        UpdateZenithHubProviderHeader();
        if (provider == ScriptHubProvider.ScriptBlox &&
            _scriptHubNotice is not null &&
            !File.Exists(ZenithScriptBloxAcknowledgementPath()))
        {
            _scriptHubNotice.IsVisible = true;
        }

        _ = ReloadZenithHubAsync();
    }

    private void ZenithHubFilter_Click(object? sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: string filter } || filter == _zenithHubFilter)
        {
            return;
        }

        _zenithHubFilter = filter;
        UpdateZenithHubFilterVisuals();
        _ = ReloadZenithHubAsync();
    }

    private void ZenithHubBrowsePopular_Click(object? sender, RoutedEventArgs e)
    {
        _zenithHubInitialising = true;
        _zenithHubSearchBox.Text = string.Empty;
        _zenithHubInitialising = false;
        _zenithHubFilter = "popular";
        UpdateZenithHubFilterVisuals();
        _ = ReloadZenithHubAsync();
    }

    private void ZenithHubClearSearch_Click(object? sender, RoutedEventArgs e)
    {
        _zenithHubInitialising = true;
        _zenithHubSearchBox.Text = string.Empty;
        _zenithHubInitialising = false;
        _ = ReloadZenithHubAsync();
    }

    private void ZenithHubScrollViewer_ScrollChanged(object? sender, ScrollChangedEventArgs e)
    {
        if (!_pages["ScriptHub"].IsVisible || !_zenithHubHasMore || _zenithHubLoading ||
            _zenithHubCards.Count == 0)
        {
            return;
        }

        var viewportBottom = _zenithHubScrollViewer.Offset.Y + _zenithHubScrollViewer.Viewport.Height;
        if (_zenithHubScrollViewer.Extent.Height > 0 &&
            viewportBottom >= _zenithHubScrollViewer.Extent.Height - 180)
        {
            _ = LoadZenithHubPageAsync(append: true);
        }
    }

    private async Task ReloadZenithHubAsync()
    {
        _zenithHubPage = 1;
        _zenithHubHasMore = true;
        _zenithHubCards.Clear();
        _zenithHubCardKeys.Clear();
        _zenithHubCardsPanel.Children.Clear();
        await LoadZenithHubPageAsync(append: false);
    }

    private async Task LoadZenithHubPageAsync(bool append)
    {
        if (_zenithHubLoading && append)
        {
            return;
        }

        var version = ++_zenithHubLoadVersion;
        if (!append)
        {
            _zenithHubLoadCancellation?.Cancel();
            _zenithHubLoadCancellation?.Dispose();
            _zenithHubLoadCancellation = new CancellationTokenSource();
        }
        var cancellation = _zenithHubLoadCancellation ??= new CancellationTokenSource();
        var requestedPage = append ? _zenithHubPage + 1 : 1;
        _zenithHubLoading = true;
        if (!append)
        {
            ShowZenithHubState("Searching scripts...", "This might take a moment", false);
        }

        try
        {
            var query = (_zenithHubSearchBox.Text ?? string.Empty).Trim();
            if (_zenithHubFilter == "universal")
            {
                query = query.Length == 0 ? "universal" : query + " universal";
            }

            var result = await _zenithHubService.FetchAsync(
                _zenithHubProvider,
                query,
                requestedPage,
                cancellation.Token);
            await _zenithHubService.LoadThumbnailsAsync(result.Cards, cancellation.Token);
            if (version != _zenithHubLoadVersion || cancellation.IsCancellationRequested)
            {
                return;
            }

            var added = result.Cards.Where(card => _zenithHubCardKeys.Add(card.Key)).ToArray();
            _zenithHubCards.AddRange(added);
            _zenithHubPage = requestedPage;
            _zenithHubHasMore = result.HasMore && added.Length > 0;
            _zenithHubLoaded = true;
            RenderZenithHubCards(animate: !append);

            if (_zenithHubCards.Count == 0)
            {
                var searched = (_zenithHubSearchBox.Text ?? string.Empty).Trim();
                var displayedSearch = searched.Length > 30 ? searched[..30] + "..." : searched;
                ShowZenithHubState(
                    "No scripts found",
                    searched.Length > 0
                        ? $"Couldn't find any scripts matching \"{displayedSearch}\""
                        : "No scripts are available right now",
                    true);
            }
            else
            {
                _zenithHubStatePanel.IsVisible = false;
            }
        }
        catch (OperationCanceledException)
        {
            // Provider, filter, or search changed while the request was active.
        }
        catch (Exception exception) when (exception is HttpRequestException or JsonException or InvalidDataException or TaskCanceledException)
        {
            if (version == _zenithHubLoadVersion)
            {
                ShowZenithHubState(
                    "Couldn't load scripts",
                    $"{ZenithProviderDisplayName(_zenithHubProvider)} is unavailable right now. {exception.Message}",
                    true);
                _zenithHubHasMore = false;
            }
        }
        finally
        {
            if (version == _zenithHubLoadVersion)
            {
                _zenithHubLoading = false;
            }
        }
    }

    private void RenderZenithHubCards(bool animate)
    {
        _zenithHubCardsPanel.Children.Clear();
        var windowWidth = Bounds.Width > 0 ? Bounds.Width : Width;
        var columnCount = GetZenithHubColumnCount(windowWidth);
        _zenithHubColumnCount = columnCount;
        var visualIndex = 0;
        for (var rowStart = 0; rowStart < _zenithHubCards.Count; rowStart += columnCount)
        {
            var row = new Grid
            {
                ColumnDefinitions = new ColumnDefinitions(BuildZenithHubColumns(columnCount)),
                HorizontalAlignment = HorizontalAlignment.Stretch
            };
            if (windowWidth >= 980 && windowWidth < 1280)
            {
                row.MaxWidth = 1000;
            }
            for (var column = 0; column < columnCount; column++)
            {
                var modelIndex = rowStart + column;
                if (modelIndex >= _zenithHubCards.Count)
                {
                    break;
                }

                var card = CreateZenithHubCard(_zenithHubCards[modelIndex]);
                Grid.SetColumn(card, column * 2);
                row.Children.Add(card);
                if (animate)
                {
                    AnimateZenithHubCard(card, visualIndex);
                }
                visualIndex++;
            }
            _zenithHubCardsPanel.Children.Add(row);
        }
    }

    private static int GetZenithHubColumnCount(double windowWidth)
    {
        // Match the reference Svelte grid's media queries, then fall back to its
        // auto-fill/minmax(280px, 1fr) behavior outside those breakpoints.
        if (windowWidth >= 980 && windowWidth < 1280)
        {
            return 3;
        }

        if (windowWidth >= 640 && windowWidth < 980)
        {
            return 2;
        }

        var availableWidth = Math.Max(280, windowWidth - 80);
        return Math.Max(1, (int)Math.Floor((availableWidth + 16) / 296));
    }

    private static string BuildZenithHubColumns(int columnCount)
        => string.Join(",", Enumerable.Range(0, columnCount)
            .SelectMany(index => index == columnCount - 1 ? new[] { "*" } : new[] { "*", "16" }));

    private Border CreateZenithHubCard(ScriptHubCardModel card)
    {
        var universal = card.Subtitle.Contains("Universal", StringComparison.OrdinalIgnoreCase);
        var shell = new Border
        {
            Height = 320,
            MinWidth = 280,
            Padding = new Thickness(16),
            Background = Brush.Parse("#03FFFFFF"),
            BorderBrush = Brush.Parse("#3A3B3C"),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(12),
            ClipToBounds = true
        };

        var root = new Grid();
        root.Children.Add(new Border
        {
            Opacity = .075,
            IsHitTestVisible = false,
            Background = new LinearGradientBrush
            {
                StartPoint = new RelativePoint(0, 0, RelativeUnit.Relative),
                EndPoint = new RelativePoint(1, 1, RelativeUnit.Relative),
                GradientStops =
                {
                    new GradientStop(Color.Parse("#0DFFFFFF"), 0),
                    new GradientStop(Color.Parse("#05FFFFFF"), 1)
                }
            }
        });

        var content = new Grid { RowDefinitions = new RowDefinitions("144,16,*,12,36") };
        var thumbnail = new Border
        {
            Background = Brush.Parse("#80000000"),
            BorderBrush = Brush.Parse("#1AFFFFFF"),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(8),
            ClipToBounds = true
        };
        var thumbnailContent = new Grid();
        if (card.Thumbnail is not null)
        {
            thumbnailContent.Children.Add(new Image
            {
                Source = card.Thumbnail,
                Stretch = Stretch.UniformToFill
            });
        }
        else
        {
            thumbnailContent.Children.Add(new PathIcon
            {
                Width = 38,
                Height = 38,
                Foreground = Brush.Parse("#667C8293"),
                Data = (Geometry?)Resources["ZenithScriptHubGlyph"],
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center
            });
        }

        thumbnailContent.Children.Add(new Border
        {
            Height = 48,
            VerticalAlignment = VerticalAlignment.Bottom,
            IsHitTestVisible = false,
            Background = new LinearGradientBrush
            {
                StartPoint = new RelativePoint(.5, 0, RelativeUnit.Relative),
                EndPoint = new RelativePoint(.5, 1, RelativeUnit.Relative),
                GradientStops =
                {
                    new GradientStop(Colors.Transparent, 0),
                    new GradientStop(Color.Parse("#80000000"), 1)
                }
            }
        });

        if (card.IsVerified)
        {
            var verified = CreateZenithHubBadge(
                "Verified",
                "M20 6L9 17L4 12",
                "#22C55E",
                "#3322C55E",
                "#4D22C55E");
            verified.HorizontalAlignment = HorizontalAlignment.Left;
            verified.VerticalAlignment = VerticalAlignment.Top;
            verified.Margin = new Thickness(8);
            verified.ZIndex = 2;
            thumbnailContent.Children.Add(verified);
        }

        var thumbnailBadges = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 8,
            HorizontalAlignment = HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Top,
            Margin = new Thickness(8)
        };
        if (card.HasKey)
        {
            thumbnailBadges.Children.Add(CreateZenithHubBadge(
                "Key",
                "M21 2L19 4M11.39 11.61A5.5 5.5 0 1 1 3.612 19.388A5.5 5.5 0 0 1 11.39 11.61ZM11.39 11.61L15.5 7.5M15.5 7.5L18.5 10.5L22 7L19 4M15.5 7.5L19 4",
                "#FF7940",
                "#33FF7940",
                "#4DFF7940"));
        }
        if (universal)
        {
            thumbnailBadges.Children.Add(CreateZenithHubBadge(
                "Universal",
                null,
                "#E69A9A9A",
                "#08FFFFFF",
                "#123A3B3C"));
        }
        if (thumbnailBadges.Children.Count > 0)
        {
            thumbnailBadges.ZIndex = 2;
            thumbnailContent.Children.Add(thumbnailBadges);
        }

        thumbnail.Child = thumbnailContent;
        content.Children.Add(thumbnail);

        var metadata = new Grid { RowDefinitions = new RowDefinitions("Auto,Auto,Auto,*,Auto") };
        Grid.SetRow(metadata, 2);
        metadata.Children.Add(new TextBlock
        {
            Text = card.Title,
            FontSize = 16,
            FontWeight = FontWeight.Medium,
            Foreground = Brushes.White,
            TextTrimming = TextTrimming.CharacterEllipsis,
            MaxLines = 1
        });
        if (card.UpdatedAt is { } updatedAt)
        {
            var freshness = new TextBlock
            {
                Text = $"Updated {FormatZenithHubRelativeTime(updatedAt)}",
                FontSize = 12,
                Foreground = Brush.Parse("#E69A9A9A"),
                Margin = new Thickness(0, 4, 0, 0)
            };
            Grid.SetRow(freshness, 1);
            metadata.Children.Add(freshness);
        }

        var detail = new Grid
        {
            ColumnDefinitions = new ColumnDefinitions("*,Auto"),
            Margin = new Thickness(0, 4, 0, 0)
        };
        detail.Children.Add(card.IsPaid
            ? CreateZenithHubPaidLabel()
            : new TextBlock
            {
                Text = "Free",
                FontSize = 12,
                Foreground = Brush.Parse("#809A9A9A"),
                VerticalAlignment = VerticalAlignment.Center
            });
        var views = CreateZenithHubViewsLabel(card.Views);
        Grid.SetColumn(views, 1);
        detail.Children.Add(views);
        Grid.SetRow(detail, 2);
        metadata.Children.Add(detail);
        var game = new TextBlock
        {
            Text = universal
                ? "Works in any game"
                : $"Game: {card.Subtitle}",
            FontSize = 12,
            Foreground = Brush.Parse("#E69A9A9A"),
            TextTrimming = TextTrimming.CharacterEllipsis,
            MaxLines = 1,
            VerticalAlignment = VerticalAlignment.Bottom
        };
        Grid.SetRow(game, 4);
        metadata.Children.Add(game);
        content.Children.Add(metadata);

        var showGameButton = !universal && !string.IsNullOrWhiteSpace(card.GameId);
        var actions = new Grid
        {
            ColumnDefinitions = new ColumnDefinitions(showGameButton ? "*,8,36,8,36" : "*,8,36")
        };
        Grid.SetRow(actions, 4);
        var execute = CreateZenithHubActionButton("ZenithHubPlayGlyph", "Execute", true);
        execute.HorizontalAlignment = HorizontalAlignment.Stretch;
        execute.Click += (_, _) =>
        {
            if (_bridge.IsConnected && !string.IsNullOrWhiteSpace(card.ScriptBody))
            {
                _bridge.EnqueueExecute(card.ScriptBody);
            }
        };
        actions.Children.Add(execute);
        var editorButton = CreateZenithHubActionButton("ZenithHubEditGlyph", string.Empty, false);
        Grid.SetColumn(editorButton, 2);
        editorButton.Click += (_, _) => OpenZenithHubCardInEditor(card);
        actions.Children.Add(editorButton);
        if (showGameButton)
        {
            var external = CreateZenithHubActionButton("ZenithHubExternalGlyph", string.Empty, false);
            Grid.SetColumn(external, 4);
            external.Click += (_, _) => OpenZenithHubExternal(
                $"https://roblox.com/games/{Uri.EscapeDataString(card.GameId)}");
            actions.Children.Add(external);
        }
        content.Children.Add(actions);
        root.Children.Add(content);
        shell.Child = root;
        return shell;
    }

    private static Border CreateZenithHubBadge(
        string text,
        string? geometry,
        string foreground,
        string background,
        string border)
    {
        var content = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 4,
            VerticalAlignment = VerticalAlignment.Center
        };
        if (!string.IsNullOrWhiteSpace(geometry))
        {
            var canvas = new Canvas { Width = 24, Height = 24 };
            canvas.Children.Add(new ShapePath
            {
                Data = Geometry.Parse(geometry),
                Stroke = Brush.Parse(foreground),
                StrokeThickness = 2.25,
                StrokeLineCap = PenLineCap.Round,
                StrokeJoin = PenLineJoin.Round
            });
            content.Children.Add(new Viewbox
            {
                Width = 10,
                Height = 10,
                Child = canvas,
                VerticalAlignment = VerticalAlignment.Center
            });
        }
        content.Children.Add(new TextBlock
        {
            Text = text,
            FontSize = 12,
            Foreground = Brush.Parse(foreground),
            VerticalAlignment = VerticalAlignment.Center
        });
        return new Border
        {
            Padding = new Thickness(8, 4),
            Background = Brush.Parse(background),
            BorderBrush = Brush.Parse(border),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(6),
            Child = content
        };
    }

    private static StackPanel CreateZenithHubViewsLabel(long viewCount)
    {
        var canvas = new Canvas { Width = 24, Height = 24 };
        canvas.Children.Add(new ShapePath
        {
            Data = Geometry.Parse("M2 12S5 5 12 5S22 12 22 12S19 19 12 19S2 12 2 12ZM12 9A3 3 0 1 0 12 15A3 3 0 1 0 12 9Z"),
            Stroke = Brush.Parse("#9A9A9A"),
            StrokeThickness = 1.35,
            StrokeLineCap = PenLineCap.Round,
            StrokeJoin = PenLineJoin.Round
        });
        return new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 4,
            VerticalAlignment = VerticalAlignment.Center,
            Children =
            {
                new Viewbox { Width = 12, Height = 12, Child = canvas, VerticalAlignment = VerticalAlignment.Center },
                new TextBlock
                {
                    Text = viewCount.ToString("N0"),
                    FontSize = 12,
                    Foreground = Brush.Parse("#9A9A9A"),
                    VerticalAlignment = VerticalAlignment.Center
                }
            }
        };
    }

    private static StackPanel CreateZenithHubPaidLabel()
    {
        var canvas = new Canvas { Width = 24, Height = 24 };
        canvas.Children.Add(new ShapePath
        {
            Data = Geometry.Parse("M12 1V23M17 5H9.5A3.5 3.5 0 0 0 9.5 12H14.5A3.5 3.5 0 0 1 14.5 19H6"),
            Stroke = Brush.Parse("#FF7940"),
            StrokeThickness = 2,
            StrokeLineCap = PenLineCap.Round,
            StrokeJoin = PenLineJoin.Round
        });
        return new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 4,
            VerticalAlignment = VerticalAlignment.Center,
            Children =
            {
                new Viewbox { Width = 10, Height = 10, Child = canvas, VerticalAlignment = VerticalAlignment.Center },
                new TextBlock
                {
                    Text = "Paid",
                    FontSize = 12,
                    Foreground = Brush.Parse("#FF7940"),
                    VerticalAlignment = VerticalAlignment.Center
                }
            }
        };
    }

    private static string FormatZenithHubRelativeTime(DateTimeOffset value)
    {
        var seconds = Math.Max(0, (long)Math.Floor((DateTimeOffset.Now - value).TotalSeconds));
        var units = new (string Label, long Seconds)[]
        {
            ("year", 31_536_000),
            ("month", 2_592_000),
            ("week", 604_800),
            ("day", 86_400),
            ("hour", 3_600),
            ("minute", 60)
        };
        foreach (var unit in units)
        {
            var count = seconds / unit.Seconds;
            if (count >= 1)
            {
                return $"{count} {unit.Label}{(count == 1 ? string.Empty : "s")} ago";
            }
        }
        return "just now";
    }

    private Button CreateZenithHubActionButton(string geometryKey, string text, bool primary)
    {
        var canvas = new Canvas { Width = 24, Height = 24 };
        canvas.Children.Add(new ShapePath
        {
            Data = (Geometry?)Resources[geometryKey],
            Stroke = Brushes.White,
            StrokeThickness = 2,
            StrokeLineCap = PenLineCap.Round,
            StrokeJoin = PenLineJoin.Round
        });
        var content = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 7,
            VerticalAlignment = VerticalAlignment.Center,
            Children =
            {
                new Viewbox { Width = 14, Height = 14, Child = canvas, VerticalAlignment = VerticalAlignment.Center }
            }
        };
        if (text.Length > 0)
        {
            content.Children.Add(new TextBlock
            {
                Text = text,
                FontSize = 14,
                FontWeight = FontWeight.Medium,
                Foreground = Brushes.White,
                VerticalAlignment = VerticalAlignment.Center
            });
        }
        return new Button
        {
            Content = content,
            Height = 36,
            MinHeight = 36,
            Padding = new Thickness(primary ? 12 : 0, 0),
            Background = Brush.Parse(primary ? "#39A2FF" : "#207C8293"),
            BorderThickness = new Thickness(0),
            CornerRadius = new CornerRadius(6),
            Foreground = Brushes.White,
            HorizontalAlignment = HorizontalAlignment.Stretch,
            HorizontalContentAlignment = HorizontalAlignment.Center,
            VerticalContentAlignment = VerticalAlignment.Center
        };
    }

    private async void OpenZenithHubCardInEditor(ScriptHubCardModel card)
    {
        var content = card.ScriptBody;
        if (string.IsNullOrWhiteSpace(content))
        {
            return;
        }
        var tab = new EditorTabState
        {
            Title = card.Title,
            Extension = ".lua",
            Content = content
        };
        _workspace.Tabs.Add(tab);
        SetPage("Execution");
        SelectTab(tab);
        await Task.CompletedTask;
    }

    private static void OpenZenithHubExternal(string url)
    {
        if (!Uri.TryCreate(url, UriKind.Absolute, out var uri) ||
            (uri.Scheme != Uri.UriSchemeHttps && uri.Scheme != Uri.UriSchemeHttp))
        {
            return;
        }
        try
        {
            Process.Start(new ProcessStartInfo(uri.AbsoluteUri) { UseShellExecute = true });
        }
        catch (Exception exception) when (exception is InvalidOperationException or System.ComponentModel.Win32Exception)
        {
            // The browser may be unavailable on restricted systems.
        }
    }

    private async void AnimateZenithHubCard(Border card, int index)
    {
        card.Opacity = 0;
        var scale = new ScaleTransform(.98, .98);
        var translate = new TranslateTransform(0, 4);
        var transforms = new TransformGroup();
        transforms.Children.Add(scale);
        transforms.Children.Add(translate);
        card.RenderTransformOrigin = RelativePoint.Center;
        card.RenderTransform = transforms;
        try
        {
            await Task.Delay(Math.Min(index, 12) * 20);
            for (var step = 1; step <= 12; step++)
            {
                var eased = EaseOutCubic(step / 12d);
                card.Opacity = eased;
                scale.ScaleX = .98 + .02 * eased;
                scale.ScaleY = .98 + .02 * eased;
                translate.Y = 4 * (1 - eased);
                await Task.Delay(25);
            }
            card.Opacity = 1;
            scale.ScaleX = 1;
            scale.ScaleY = 1;
            translate.Y = 0;
        }
        catch (OperationCanceledException)
        {
            card.Opacity = 1;
            scale.ScaleX = 1;
            scale.ScaleY = 1;
            translate.Y = 0;
        }
    }

    private static double EaseOutCubic(double value) => 1 - Math.Pow(1 - value, 3);

    private void ShowZenithHubState(string title, string description, bool showBrowse)
    {
        _zenithHubStateTitle.Text = title;
        _zenithHubStateDescription.Text = description;
        _zenithHubBrowsePopularButton.IsVisible = showBrowse;
        _zenithHubClearSearchButton.IsVisible = showBrowse &&
            !string.IsNullOrWhiteSpace(_zenithHubSearchBox.Text);
        _zenithHubStatePanel.IsVisible = true;
    }

    private void UpdateZenithHubFilterVisuals()
    {
        foreach (var button in new[] { _zenithHubRecentButton, _zenithHubPopularButton, _zenithHubUniversalButton })
        {
            var active = string.Equals(button.Tag as string, _zenithHubFilter, StringComparison.Ordinal);
            if (active)
            {
                if (!button.Classes.Contains("active"))
                {
                    button.Classes.Add("active");
                }
            }
            else
            {
                button.Classes.Remove("active");
            }
        }
    }

    private void UpdateZenithHubProviderHeader()
        => _zenithHubSourceHeader.Text = ZenithProviderDisplayName(_zenithHubProvider);

    private static string ZenithProviderDisplayName(ScriptHubProvider provider) => provider switch
    {
        ScriptHubProvider.RobloxScripts => "robloxscripts.com",
        ScriptHubProvider.ScriptBlox => "ScriptBlox",
        ScriptHubProvider.HaxHell => "haxhell",
        ScriptHubProvider.Rscripts => "rscripts",
        _ => "robloxscripts.com"
    };

    private static int ZenithProviderIndex(ScriptHubProvider provider) => provider switch
    {
        ScriptHubProvider.RobloxScripts => 0,
        ScriptHubProvider.Rscripts => 1,
        ScriptHubProvider.HaxHell => 2,
        ScriptHubProvider.ScriptBlox => 3,
        _ => 0
    };

    private static string ZenithProviderPreferencePath() => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "Orbit",
        "zenith-script-hub-provider");

    private static string ZenithScriptBloxAcknowledgementPath() => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "Orbit",
        "zenith-script-hub-warning");

    private static ScriptHubProvider LoadZenithHubProvider()
    {
        try
        {
            var path = ZenithProviderPreferencePath();
            if (File.Exists(path) &&
                Enum.TryParse(File.ReadAllText(path).Trim(), out ScriptHubProvider provider))
            {
                return provider;
            }
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
        return ScriptHubProvider.RobloxScripts;
    }

    private static void SaveZenithHubProvider(ScriptHubProvider provider)
    {
        try
        {
            var path = ZenithProviderPreferencePath();
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            File.WriteAllText(path, provider.ToString());
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }

    private void ClearEditor_Click(object? sender, RoutedEventArgs e)
    {
        _activeTab.Content = string.Empty;
        PushActiveTabToEditor();
    }

    private void ToggleFileList_Click(object? sender, RoutedEventArgs e)
    {
        var expanded = _editorSplit.ColumnDefinitions[2].Width.Value > 30;
        _editorSplit.ColumnDefinitions[2].Width = new GridLength(expanded ? 30 : 200);
        _fileList.IsVisible = !expanded;
        _fileListTitle.IsVisible = !expanded;
        _fileListChevron.RenderTransform = new RotateTransform(expanded ? 180 : 0);
    }

    private void RefreshFileList()
    {
        _fileList.Children.Clear();
        _fileList.Children.Add(CreateSourceFolder("Scripts", _scriptsDirectory));
        var parent = Directory.GetParent(_scriptsDirectory)?.FullName ?? AppContext.BaseDirectory;
        _fileList.Children.Add(CreateSourceFolder("AutoExec", Path.Combine(parent, "AutoExec")));
    }

    private Control CreateSourceFolder(string title, string directory)
    {
        var contents = new StackPanel
        {
            Spacing = 0,
            Margin = new Thickness(16, 0, 0, 0),
            IsVisible = false
        };
        var expanded = false;
        var chevron = CreateSourceChevron(0);
        var header = new Button
        {
            Content = new StackPanel
            {
                Orientation = Orientation.Horizontal,
                Spacing = 7,
                Children =
                {
                    chevron,
                    CreateSourceFolderIcon(),
                    new TextBlock
                    {
                        Text = title,
                        FontSize = 13,
                        FontWeight = FontWeight.Medium,
                        Foreground = Brush.Parse("#E6FFFFFF"),
                        VerticalAlignment = VerticalAlignment.Center
                    }
                }
            }
        };
        header.Classes.Add("zenith-file-row");
        header.Click += (_, _) =>
        {
            expanded = !expanded;
            contents.IsVisible = expanded;
            chevron.RenderTransform = new RotateTransform(expanded ? 90 : 0);
        };

        if (Directory.Exists(directory))
        {
            foreach (var path in Directory.EnumerateFiles(directory)
                         .Where(path => new[] { ".lua", ".luau", ".txt", ".md" }
                             .Contains(Path.GetExtension(path), StringComparer.OrdinalIgnoreCase))
                         .Take(18))
            {
            var button = new Button
            {
                Tag = path
            };
            button.Classes.Add("zenith-file-row");
            button.Content = new StackPanel
            {
                Orientation = Orientation.Horizontal,
                Spacing = 0,
                Children =
                {
                    CreateSourceFileIcon(),
                    new TextBlock { Text = Path.GetFileNameWithoutExtension(path), FontSize = 13, Foreground = Brush.Parse("#E6FFFFFF"), VerticalAlignment = VerticalAlignment.Center }
                }
            };
            button.Click += async (_, _) =>
            {
                var content = await File.ReadAllTextAsync(path);
                var tab = new EditorTabState
                {
                    Title = Path.GetFileNameWithoutExtension(path),
                    Extension = Path.GetExtension(path),
                    Content = content
                };
                _workspace.Tabs.Add(tab);
                SelectTab(tab);
            };
                contents.Children.Add(button);
            }
        }

        if (contents.Children.Count == 0)
        {
            contents.Children.Add(new TextBlock
            {
                Text = "Empty. What is this? →",
                Margin = new Thickness(4, 2),
                FontSize = 12,
                FontStyle = FontStyle.Italic,
                Foreground = Brush.Parse("#999A9A9A"),
                TextDecorations = TextDecorations.Underline,
                Cursor = new Cursor(StandardCursorType.Hand)
            });
        }

        return new StackPanel { Spacing = 0, Children = { header, contents } };
    }

    private Control CreateSourceFileIcon()
    {
        var canvas = new Canvas { Width = 24, Height = 24 };
        canvas.Children.Add(new Avalonia.Controls.Shapes.Path
        {
            Data = (Geometry?)Resources["ZenithFileGlyph"],
            Stroke = Brush.Parse("#99FFFFFF"),
            StrokeThickness = 2,
            StrokeLineCap = PenLineCap.Round,
            StrokeJoin = PenLineJoin.Round
        });
        return new Viewbox { Width = 16, Height = 16, Child = canvas, VerticalAlignment = VerticalAlignment.Center };
    }

    private Control CreateSourceFolderIcon()
    {
        var canvas = new Canvas { Width = 24, Height = 24 };
        canvas.Children.Add(new Avalonia.Controls.Shapes.Path
        {
            Data = (Geometry?)Resources["ZenithFolderGlyph"],
            Stroke = Brush.Parse("#B3FFFFFF"),
            StrokeThickness = 2,
            StrokeLineCap = PenLineCap.Round,
            StrokeJoin = PenLineJoin.Round
        });
        return new Viewbox { Width = 16, Height = 16, Child = canvas, VerticalAlignment = VerticalAlignment.Center };
    }

    private ShapePath CreateSourceChevron(double angle) => new()
    {
        Width = 14,
        Height = 14,
        Data = (Geometry?)Resources["ZenithChevronGlyph"],
        Stroke = Brush.Parse("#80FFFFFF"),
        StrokeThickness = 2,
        StrokeLineCap = PenLineCap.Round,
        StrokeJoin = PenLineJoin.Round,
        Stretch = Stretch.Uniform,
        RenderTransformOrigin = RelativePoint.Center,
        RenderTransform = new RotateTransform(angle),
        HorizontalAlignment = HorizontalAlignment.Center,
        VerticalAlignment = VerticalAlignment.Center
    };

    private void ToggleOutput_Click(object? sender, RoutedEventArgs e)
    {
        _outputExpanded = !_outputExpanded;
        _outputScroll.IsVisible = _outputExpanded;
        _outputResizeGrip.IsVisible = _outputExpanded;
        _editorStack.RowDefinitions[2].Height = new GridLength(_outputExpanded ? _outputExpandedHeight : 32);
        _outputChevron.Data = (Geometry?)Resources[_outputExpanded ? "ZenithChevronDownGlyph" : "ZenithChevronUpGlyph"];
    }

    private void ClearOutput_Click(object? sender, RoutedEventArgs e)
    {
        _outputLines.Clear();
        _outputText.Inlines?.Clear();
        _outputText.ClearSelection();
        _outputHasLiveContent = true;
    }

    private void OutputResizeGrip_PointerPressed(object? sender, PointerPressedEventArgs e)
    {
        if (!_outputExpanded || sender is not Control grip ||
            !e.GetCurrentPoint(this).Properties.IsLeftButtonPressed)
        {
            return;
        }

        _outputResizing = true;
        _outputResizeStartPointerY = e.GetPosition(this).Y;
        _outputResizeStartHeight = _editorStack.RowDefinitions[2].ActualHeight > 0
            ? _editorStack.RowDefinitions[2].ActualHeight
            : _outputExpandedHeight;
        e.Pointer.Capture(grip);
        e.Handled = true;
    }

    private void OutputResizeGrip_PointerMoved(object? sender, PointerEventArgs e)
    {
        if (!_outputResizing || !e.GetCurrentPoint(this).Properties.IsLeftButtonPressed)
        {
            return;
        }

        var requestedHeight = _outputResizeStartHeight + (_outputResizeStartPointerY - e.GetPosition(this).Y);
        var maximumHeight = Math.Max(80, _editorStack.Bounds.Height * .65);
        _outputExpandedHeight = Math.Clamp(requestedHeight, 72, maximumHeight);
        _editorStack.RowDefinitions[2].Height = new GridLength(_outputExpandedHeight);
        e.Handled = true;
    }

    private void OutputResizeGrip_PointerReleased(object? sender, PointerReleasedEventArgs e)
    {
        if (!_outputResizing)
        {
            return;
        }

        _outputResizing = false;
        e.Pointer.Capture(null);
        e.Handled = true;
    }

    private void Bridge_ConnectionChanged(bool connected)
        => Dispatcher.UIThread.Post(() => ApplyBridgeState(connected));

    private void ApplyBridgeState(bool connected)
    {
        var live = connected && _bridge.GetConnectedClients().Count > 0;
        var statusColor = Color.Parse(live ? "#2CFF35" : "#4E4D72");
        _bridgeStatusText.Text = live ? "Attached" : "Inactive";
        _bridgeStatusText.Foreground = Brush.Parse("#9A9A9A");
        _bridgeStatusGlow.Background = CreateStatusGlowBrush(statusColor);
        _bridgeStatusDot.Fill = new SolidColorBrush(statusColor);
        _bridgeStatusDotGlow.Fill = new SolidColorBrush(statusColor);
        _executeButton.IsEnabled = true;
        _executeButton.IsHitTestVisible = live;
        _executeButton.Focusable = live;
        _executeButton.Opacity = 1;
        _attachLabel.Text = live ? "Attached" : "Attach";
    }

    private static RadialGradientBrush CreateStatusGlowBrush(Color color)
    {
        var brush = new RadialGradientBrush();
        brush.GradientStops.Add(new GradientStop(WithOpacity(color, .40), 0));
        brush.GradientStops.Add(new GradientStop(WithOpacity(color, .35), .04));
        brush.GradientStops.Add(new GradientStop(WithOpacity(color, .25), .10));
        brush.GradientStops.Add(new GradientStop(WithOpacity(color, .15), .20));
        brush.GradientStops.Add(new GradientStop(WithOpacity(color, .08), .33));
        brush.GradientStops.Add(new GradientStop(WithOpacity(color, .04), .50));
        brush.GradientStops.Add(new GradientStop(WithOpacity(color, 0), 1));
        return brush;
    }

    private static Color WithOpacity(Color color, double opacity)
        => Color.FromArgb((byte)Math.Round(255 * opacity), color.R, color.G, color.B);

    private void Bridge_LogReceived(string level, string message)
        => Dispatcher.UIThread.Post(() => AddOutput(message, level));

    private void AddOutput(string message, string level)
    {
        var selectionStart = _outputText.SelectionStart;
        var selectionEnd = _outputText.SelectionEnd;
        var hadSelection = selectionStart != selectionEnd;
        var foreground = level.ToLowerInvariant() switch
        {
            "warn" or "warning" => Brush.Parse("#E5C07B"),
            "error" => Brush.Parse("#E06C75"),
            "info" => Brush.Parse("#61AFEF"),
            _ => Brush.Parse("#C5C5C5")
        };

        if (!_outputHasLiveContent)
        {
            _outputText.Inlines?.Clear();
            _outputHasLiveContent = true;
        }

        var line = new ZenithOutputLine(DateTime.Now.ToString("HH:mm:ss"), message, foreground);
        _outputLines.Add(line);
        var rebuild = false;
        while (_outputLines.Count > 500)
        {
            _outputLines.RemoveAt(0);
            rebuild = true;
        }

        if (rebuild)
        {
            RebuildOutputText();
        }
        else
        {
            AppendOutputLine(line, _outputLines.Count > 1);
        }

        if (hadSelection && !rebuild)
        {
            _outputText.SelectionStart = selectionStart;
            _outputText.SelectionEnd = selectionEnd;
        }
        else
        {
            _outputText.ClearSelection();
        }

        Dispatcher.UIThread.Post(
            () => _outputScroll.Offset = new Vector(0, _outputScroll.Extent.Height),
            DispatcherPriority.Background);

        if (!_outputExpanded)
        {
            _outputExpanded = true;
            _outputScroll.IsVisible = true;
            _outputResizeGrip.IsVisible = true;
            _editorStack.RowDefinitions[2].Height = new GridLength(_outputExpandedHeight);
            _outputChevron.Data = (Geometry?)Resources["ZenithChevronDownGlyph"];
        }
    }

    private void RebuildOutputText()
    {
        _outputText.Inlines?.Clear();
        for (var index = 0; index < _outputLines.Count; index++)
        {
            AppendOutputLine(_outputLines[index], index > 0);
        }
    }

    private void AppendOutputLine(ZenithOutputLine line, bool prependLineBreak)
    {
        var inlines = _outputText.Inlines;
        if (inlines is null)
        {
            return;
        }

        if (prependLineBreak)
        {
            inlines.Add(new LineBreak());
        }
        inlines.Add(new Run { Text = line.Timestamp + " ", Foreground = Brush.Parse("#555555") });
        inlines.Add(new Run { Text = line.Message, Foreground = line.Foreground });
    }

    private void SettingsSection_Click(object? sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: string section })
        {
            return;
        }

        _settingsSectionTitle.Text = section;
        _settingsRowsPanel.Children.Clear();
        foreach (var definition in SettingsForSection(section))
        {
            _settingsRowsPanel.Children.Add(CreateSettingRow(definition));
        }
        _settingsMainPage.IsVisible = false;
        _settingsSectionPage.IsVisible = true;
    }

    private void SettingsBack_Click(object? sender, RoutedEventArgs e) => ShowSettingsMain();

    private void ShowSettingsMain()
    {
        _settingsSectionPage.IsVisible = false;
        _settingsMainPage.IsVisible = true;
    }

    private Control CreateSettingRow(ZenithSettingDefinition definition)
    {
        var border = new Border
        {
            Background = Brush.Parse("#18FFFFFF"),
            CornerRadius = new CornerRadius(12),
            Padding = new Thickness(16, 11),
            MinHeight = 80
        };
        var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };
        var copy = new StackPanel { Spacing = 6, VerticalAlignment = VerticalAlignment.Center };
        copy.Children.Add(new TextBlock
        {
            Text = definition.Title,
            FontSize = 16,
            Foreground = Brushes.White
        });
        copy.Children.Add(new TextBlock
        {
            Text = definition.Description,
            FontSize = 14,
            Foreground = Brush.Parse(MutedForeground),
            TextWrapping = TextWrapping.Wrap
        });
        grid.Children.Add(copy);

        Control editor;
        if (definition.Value is int numeric)
        {
            editor = new NumericUpDown
            {
                Value = numeric,
                Minimum = 0,
                Maximum = 1000,
                Width = 130,
                Height = 34,
                Background = Brush.Parse(CardBackground),
                Foreground = Brushes.White,
                BorderBrush = Brush.Parse("#333333"),
                VerticalAlignment = VerticalAlignment.Center
            };
        }
        else if (definition.Value is string text)
        {
            editor = new Button
            {
                Content = text,
                MinWidth = 110,
                VerticalAlignment = VerticalAlignment.Center
            };
        }
        else
        {
            var toggle = new ToggleSwitch
            {
                IsChecked = definition.Value as bool? ?? false,
                OnContent = string.Empty,
                OffContent = string.Empty,
                MinWidth = 48,
                VerticalAlignment = VerticalAlignment.Center,
                HorizontalAlignment = HorizontalAlignment.Right
            };
            toggle.Classes.Add("zenith-toggle");
            if (definition.Title == "Always on Top")
            {
                toggle.IsChecked = Topmost;
                toggle.IsCheckedChanged += (_, _) =>
                {
                    Topmost = toggle.IsChecked == true;
                    OrbitPreferences.SetTopMost(Topmost);
                };
            }
            editor = toggle;
        }
        Grid.SetColumn(editor, 1);
        grid.Children.Add(editor);
        border.Child = grid;
        return border;
    }

    private static IReadOnlyList<ZenithSettingDefinition> SettingsForSection(string section) => section switch
    {
        "Execution Settings" =>
        [
            new("Enable Auto Execute", "Automatically execute scripts from the AutoExec folder when you attach into a game", true),
            new("Create LocalScript", "When you execute a script, it will run under a LocalScript in-game", false),
            new("Error Spoofing/Redirection", "Errors are redirected to the UI console rather than in-game", false),
            new("Unlock FPS", "Unlock FPS in-game up to the FPS cap limit", false),
            new("FPS Cap", "The limit to which your FPS is in-game", 60),
            new("Internal Interface", "Enables the in-game internal interface, enabled via the key-bind", false),
            new("Internal Key-bind", "The key-bind which will toggle the internal interface", "Insert"),
            new("Enable Multi-instance", "Allows you to have multiple games running and attach to them simultaneously", false)
        ],
        "Interface Settings" =>
        [
            new("Theme", "Customise the appearance of Zenith with themes", "Dark"),
            new("Always on Top", "Keep the window above all other windows", false),
            new("Navigation Slide-Out", "Enables the sliding animation/feature for the left-side navigation panel", true),
            new("Status Indicator Glow", "Shows a glow effect behind the status indicator in the top-left corner", true),
            new("Format Code on Paste", "Automatically format code when pasting into the editor", true),
            new("Swap Attach & Execute Buttons", "Swaps the positions of the Attach and Execute buttons", false),
            new("Hide Open Button", "Hides the Open button from the UI", false),
            new("Hide Save Button", "Hides the Save button from the UI", false),
            new("Hide Clear Button", "Hides the Clear button from the UI", false),
            new("Hide Output Console", "Completely hides the output console from the UI", false),
            new("Show Editor Hints", "Display helpful keyboard shortcut hints at the bottom of empty editor tabs", true)
        ],
        _ =>
        [
            new("Auto-Attach", "Automatically attach to the game rather than having to press 'Attach'", false),
            new("Auto-Attach Delay", "Delay for auto-attaching, will attempt to attach after the specified time in seconds", 5),
            new("Skip Version Check", "Disable the version mismatch warning when attaching to Roblox", false),
            new("Skip Validation", "Skip file validation checks when attaching (faster attach but may cause issues if files are outdated)", false)
        ]
    };

    private void ScriptHubNoticeDismiss_Click(object? sender, RoutedEventArgs e)
    {
        if (_scriptHubNotice is null)
        {
            return;
        }
        _scriptHubNotice.IsVisible = false;
        try
        {
            var directory = Path.GetDirectoryName(ZenithScriptBloxAcknowledgementPath())!;
            Directory.CreateDirectory(directory);
            File.WriteAllText(ZenithScriptBloxAcknowledgementPath(), "1");
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }

    private async void BackToOrion_Click(object? sender, RoutedEventArgs e)
    {
        if (_returnRequested)
        {
            return;
        }

        _returnRequested = true;
        _activeTab.Content = await RequestEditorContentAsync();
        _returnToOrion(CaptureWorkspace());
    }

    private EditorWorkspaceState CaptureWorkspace() => new()
    {
        Tabs = _workspace.Tabs.Select(tab => tab.CloneDetached()).ToList(),
        ActiveTabId = _activeTab.Id
    };

    private sealed record ZenithOutputLine(string Timestamp, string Message, IBrush Foreground);
    private sealed record ZenithSettingDefinition(string Title, string Description, object Value);
}
