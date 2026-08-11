using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Documents;
using Avalonia.Controls.Primitives;
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

namespace OrbitAvalonia;

/// <summary>
/// Native Avalonia preservation of the AWP.GG Tauri frontend. The original
/// injection and account backend is deliberately not carried over; editor
/// execution uses Orion's app-lifetime bridge just like every other shell.
/// </summary>
public sealed partial class AWPWindow : Window
{
    private readonly string _scriptsDirectory;
    private readonly EditorWorkspaceState _workspace;
    private readonly Action<EditorWorkspaceState> _returnToOrion;
    private readonly UnifiedBridgeServer _bridge = UnifiedBridgeServer.Shared;
    private readonly List<AWPOutputLine> _outputLines = [];
    private readonly List<AWPScriptItem> _allScripts = [];
    private readonly DispatcherTimer _toastTimer;

    private readonly Border _chrome;
    private readonly Grid _scriptingPage;
    private readonly Grid _settingsPage;
    private readonly Popup _pageMenu;
    private readonly PathIcon _pageIcon;
    private readonly TextBlock _pageLabel;
    private readonly PathIcon _pageCaret;
    private readonly Button _scriptingMenuItem;
    private readonly Button _settingsMenuItem;
    private readonly StackPanel _tabBar;
    private readonly NativeWebView _editor;
    private readonly Uri _monacoAddress;
    private readonly MonacoStaticServer? _ownedMonacoServer;
    private readonly Button _executeButton;
    private readonly Button _executeFileButton;
    private readonly Button _attachButton;
    private readonly PathIcon _attachIcon;
    private readonly Button _clientManagerButton;
    private readonly Popup _clientManagerPopup;
    private readonly TextBlock _clientSummaryLabel;
    private readonly PathIcon _clientManagerCaret;
    private readonly StackPanel _clientListPanel;
    private readonly Grid _consolePanel;
    private readonly Border _consoleResizeGrip;
    private readonly ScrollViewer _outputScroll;
    private readonly SelectableTextBlock _outputText;
    private readonly PathIcon _consoleCaret;
    private readonly ListBox _workspaceList;
    private readonly TextBlock _noScriptsText;
    private readonly PathIcon _workspaceCaret;
    private readonly StackPanel _generalSettingsPanel;
    private readonly StackPanel _editorSettingsPanel;
    private readonly Button _generalSettingsTab;
    private readonly Button _editorSettingsTab;
    private readonly TextBlock _topmostStatusLabel;
    private readonly TextBlock _autoInjectStatusLabel;
    private readonly TextBlock _consoleStatusLabel;
    private readonly Button _topmostButton;
    private readonly Button _autoInjectButton;
    private readonly Button _consoleVisibilityButton;
    private readonly Border _loginOverlay;
    private readonly TextBox _loginUsername;
    private readonly TextBox _loginPassword;
    private readonly TextBlock _loginError;
    private readonly Border _credentialsOverlay;
    private readonly TextBox _credentialsUsername;
    private readonly TextBox _credentialsPassword;
    private readonly Border _toast;
    private readonly TextBlock _toastText;

    private EditorTabState _activeTab;
    private TaskCompletionSource<string>? _pendingEditorSnapshot;
    private bool _editorReady;
    private bool _editorSourceAssigned;
    private bool _editorDisposed;
    private bool _workspaceOpen = true;
    private bool _consoleOpen = true;
    private bool _consoleVisible = true;
    private bool _consoleResizing;
    private double _consoleExpandedHeight = 130;
    private double _consoleResizeStartPointerY;
    private double _consoleResizeStartHeight;
    private bool _autoInject;
    private bool _closingForOrion;
    private bool _returnRequested;
    private string _savedUsername = string.Empty;
    private readonly HashSet<string> _selectedClientIdentifiers = new(StringComparer.OrdinalIgnoreCase);
    private readonly HashSet<string> _knownClientIdentifiers = new(StringComparer.OrdinalIgnoreCase);

    public AWPWindow() : this(
        Path.Combine(AppContext.BaseDirectory, "Scripts"),
        CreateDefaultWorkspace(),
        null,
        static _ => { })
    {
    }

    internal AWPWindow(
        string scriptsDirectory,
        EditorWorkspaceState initialWorkspace,
        Uri? monacoAddress,
        Action<EditorWorkspaceState> returnToOrion)
        : this(scriptsDirectory, initialWorkspace, monacoAddress, returnToOrion, false)
    {
    }

    private AWPWindow(
        string scriptsDirectory,
        EditorWorkspaceState initialWorkspace,
        Uri? monacoAddress,
        Action<EditorWorkspaceState> returnToOrion,
        bool _ = false)
    {
        _scriptsDirectory = scriptsDirectory;
        _workspace = initialWorkspace.CloneDetached();
        if (_workspace.Tabs.Count == 0)
        {
            var firstTab = NewTabState();
            _workspace.Tabs.Add(firstTab);
            _workspace.ActiveTabId = firstTab.Id;
        }

        _activeTab = _workspace.Tabs.FirstOrDefault(tab => tab.Id == _workspace.ActiveTabId)
            ?? _workspace.Tabs[0];
        _returnToOrion = returnToOrion;

        AvaloniaXamlLoader.Load(this);

        _chrome = Required<Border>("AwpChrome");
        _scriptingPage = Required<Grid>("ScriptingPage");
        _settingsPage = Required<Grid>("SettingsPage");
        _pageMenu = Required<Popup>("PageMenu");
        _pageIcon = Required<PathIcon>("PageIcon");
        _pageLabel = Required<TextBlock>("PageLabel");
        _pageCaret = Required<PathIcon>("PageCaretPath");
        _pageMenu.PlacementTarget = Required<Button>("PageMenuButton");
        _pageMenu.Closed += (_, _) =>
            _pageCaret.Data = (Geometry)Resources["AwpChevronDownIcon"]!;
        _scriptingMenuItem = Required<Button>("ScriptingMenuItem");
        _settingsMenuItem = Required<Button>("SettingsMenuItem");
        _tabBar = Required<StackPanel>("TabBar");
        _editor = Required<NativeWebView>("AwpMonacoWebView");
        _executeButton = Required<Button>("ExecuteButton");
        _executeFileButton = Required<Button>("ExecuteFileButton");
        _attachButton = Required<Button>("AttachButton");
        _attachIcon = Required<PathIcon>("AttachIcon");
        _clientManagerButton = Required<Button>("ClientManagerButton");
        _clientManagerPopup = Required<Popup>("ClientManagerPopup");
        _clientSummaryLabel = Required<TextBlock>("ClientSummaryLabel");
        _clientManagerCaret = Required<PathIcon>("ClientManagerCaretPath");
        _clientListPanel = Required<StackPanel>("ClientListPanel");
        _clientManagerPopup.PlacementTarget = _clientManagerButton;
        _clientManagerPopup.Closed += (_, _) =>
            _clientManagerCaret.Data = (Geometry)Resources["AwpChevronUpIcon"]!;
        var closeButton = Required<Button>("CloseButton");
        closeButton.AddHandler(
            InputElement.PointerPressedEvent,
            CloseButton_PointerPressed,
            RoutingStrategies.Tunnel,
            handledEventsToo: true);
        _consolePanel = Required<Grid>("ConsolePanel");
        _consoleResizeGrip = Required<Border>("ConsoleResizeGrip");
        _outputScroll = Required<ScrollViewer>("OutputScroll");
        _outputText = Required<SelectableTextBlock>("OutputText");
        _consoleCaret = Required<PathIcon>("ConsoleCaretPath");
        _workspaceList = Required<ListBox>("WorkspaceList");
        _noScriptsText = Required<TextBlock>("NoScriptsText");
        _workspaceCaret = Required<PathIcon>("WorkspaceCaretPath");
        _generalSettingsPanel = Required<StackPanel>("GeneralSettingsPanel");
        _editorSettingsPanel = Required<StackPanel>("EditorSettingsPanel");
        _generalSettingsTab = Required<Button>("GeneralSettingsTab");
        _editorSettingsTab = Required<Button>("EditorSettingsTab");
        _topmostStatusLabel = Required<TextBlock>("TopmostStatusLabel");
        _autoInjectStatusLabel = Required<TextBlock>("AutoInjectStatusLabel");
        _consoleStatusLabel = Required<TextBlock>("ConsoleStatusLabel");
        _topmostButton = Required<Button>("TopmostButton");
        _autoInjectButton = Required<Button>("AutoInjectButton");
        _consoleVisibilityButton = Required<Button>("ConsoleVisibilityButton");
        _loginOverlay = Required<Border>("LoginOverlay");
        _loginUsername = Required<TextBox>("LoginUsername");
        _loginPassword = Required<TextBox>("LoginPassword");
        _loginError = Required<TextBlock>("LoginError");
        _credentialsOverlay = Required<Border>("CredentialsOverlay");
        _credentialsUsername = Required<TextBox>("CredentialsUsername");
        _credentialsPassword = Required<TextBox>("CredentialsPassword");
        _toast = Required<Border>("Toast");
        _toastText = Required<TextBlock>("ToastText");

        if (monacoAddress is null)
        {
            _ownedMonacoServer = new MonacoStaticServer(
                Path.Combine(AppContext.BaseDirectory, "MonacoPreview"));
            _monacoAddress = _ownedMonacoServer.Address;
        }
        else
        {
            _monacoAddress = monacoAddress;
        }

        _editor.WebMessageReceived += Editor_WebMessageReceived;

        Topmost = OrbitPreferences.TopMostEnabled;
        CanResize = OrbitPreferences.ResizableEnabled;
        _toastTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(2500) };
        _toastTimer.Tick += (_, _) =>
        {
            _toastTimer.Stop();
            _toast.IsVisible = false;
        };

        RenderTabs();
        SelectTab(_activeTab);
        RefreshWorkspaceFiles();
        ApplyBridgeState(_bridge.IsConnected);
        RefreshClientManager();
        UpdateSettingsVisuals();

        _bridge.ConnectionChanged += BridgeConnectionChanged;
        _bridge.LogReceived += BridgeLogReceived;
        _bridge.ClientsChanged += BridgeClientsChanged;
        Opened += AWPWindow_Opened;
        Closed += AWPWindow_Closed;
        PropertyChanged += AWPWindow_PropertyChanged;
        KeyDown += AWPWindow_KeyDown;
    }

    internal void CloseForOrion()
    {
        _closingForOrion = true;
        Close();
    }

    private void AWPWindow_Opened(object? sender, EventArgs e)
    {
        Opened -= AWPWindow_Opened;
        _loginOverlay.IsVisible = true;
        _loginOverlay.ZIndex = 100;
        Dispatcher.UIThread.Post(() => _loginUsername.Focus(), DispatcherPriority.Input);
    }

    private T Required<T>(string name) where T : Control
        => this.FindControl<T>(name)
           ?? throw new InvalidOperationException($"AWP control '{name}' was not created.");

    private static EditorWorkspaceState CreateDefaultWorkspace()
    {
        var tab = NewTabState();
        return new EditorWorkspaceState { Tabs = [tab], ActiveTabId = tab.Id };
    }

    private static EditorTabState NewTabState() => new()
    {
        Title = "Untitled Tab",
        Content = string.Empty,
        Extension = ".lua"
    };

    private void AWPWindow_Closed(object? sender, EventArgs e)
    {
        _editorDisposed = true;
        _editor.IsVisible = false;
        _pendingEditorSnapshot?.TrySetCanceled();
        _editor.WebMessageReceived -= Editor_WebMessageReceived;
        _ownedMonacoServer?.Dispose();
        _bridge.ConnectionChanged -= BridgeConnectionChanged;
        _bridge.LogReceived -= BridgeLogReceived;
        _bridge.ClientsChanged -= BridgeClientsChanged;
        if (!_closingForOrion && !_returnRequested)
        {
            _returnRequested = true;
            _returnToOrion(CaptureWorkspace());
        }
    }

    private void AWPWindow_PropertyChanged(object? sender, AvaloniaPropertyChangedEventArgs e)
    {
        if (e.Property != WindowStateProperty)
        {
            return;
        }

        var maximized = WindowState == WindowState.Maximized;
        _chrome.CornerRadius = maximized ? new CornerRadius(0) : new CornerRadius(4);
        _chrome.BorderThickness = maximized ? new Thickness(0) : new Thickness(1);
    }

    private void AWPWindow_KeyDown(object? sender, KeyEventArgs e)
    {
        if (e.Key == Key.Escape)
        {
            _pageMenu.IsOpen = false;
            _pageCaret.Data = (Geometry)Resources["AwpChevronDownIcon"]!;
            _credentialsOverlay.IsVisible = false;
            return;
        }

        if (e.Key == Key.F5 || ((e.KeyModifiers & KeyModifiers.Control) != 0 && e.Key == Key.Enter))
        {
            _ = ExecuteCurrentScriptAsync();
            e.Handled = true;
        }
        else if ((e.KeyModifiers & KeyModifiers.Control) != 0 && e.Key == Key.S)
        {
            _ = SaveCurrentFileAsync();
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

    private void CloseButton_PointerPressed(object? sender, PointerPressedEventArgs e)
    {
        if (!e.GetCurrentPoint(this).Properties.IsLeftButtonPressed)
        {
            return;
        }

        e.Handled = true;
        _returnRequested = true;
        // AWP is shown while Orion's owner window is hidden. A normal
        // lifetime shutdown blocks on that hidden window's close transition,
        // so the title-bar X intentionally uses a process-level exit.
        Environment.Exit(0);
    }

    private async void BackToOrion_Click(object? sender, RoutedEventArgs e)
        => await ReturnToOrionAsync();

    private async Task ReturnToOrionAsync()
    {
        if (_returnRequested)
        {
            return;
        }

        _returnRequested = true;
        _activeTab.Content = await RequestEditorContentAsync();
        _returnToOrion(CaptureWorkspace());
    }

    private EditorWorkspaceState CaptureWorkspace()
    {
        return new EditorWorkspaceState
        {
            Tabs = _workspace.Tabs.Select(tab => tab.CloneDetached()).ToList(),
            ActiveTabId = _activeTab.Id
        };
    }

    private void PageMenu_Click(object? sender, RoutedEventArgs e)
    {
        _pageMenu.IsOpen = !_pageMenu.IsOpen;
        _pageCaret.Data = (Geometry)Resources[_pageMenu.IsOpen ? "AwpChevronUpIcon" : "AwpChevronDownIcon"]!;
    }

    private void ScriptingMenuItem_Click(object? sender, RoutedEventArgs e) => ShowPage(settings: false);

    private void SettingsMenuItem_Click(object? sender, RoutedEventArgs e) => ShowPage(settings: true);

    private void ShowPage(bool settings)
    {
        _pageMenu.IsOpen = false;
        _pageCaret.Data = (Geometry)Resources["AwpChevronDownIcon"]!;
        _scriptingPage.IsVisible = !settings;
        _settingsPage.IsVisible = settings;
        _pageLabel.Text = settings ? "Settings" : "Scripting";
        _pageIcon.Data = (Geometry)Resources[settings ? "AwpToolIcon" : "AwpFileIcon"]!;
        _scriptingMenuItem.Background = settings ? Brushes.Transparent : Brush.Parse("#282828");
        _settingsMenuItem.Background = settings ? Brush.Parse("#282828") : Brushes.Transparent;
        if (settings)
        {
            _editor.IsVisible = false;
        }
        else if (!_loginOverlay.IsVisible)
        {
            RevealEditor();
        }
    }

    private void Logout_Click(object? sender, RoutedEventArgs e)
    {
        _savedUsername = string.Empty;
        _loginUsername.Text = string.Empty;
        _loginPassword.Text = string.Empty;
        _loginError.Text = string.Empty;
        _editor.IsVisible = false;
        _loginOverlay.IsVisible = true;
        _loginUsername.Focus();
    }

    private void Login_Click(object? sender, RoutedEventArgs e)
    {
        var username = (_loginUsername.Text ?? string.Empty).Trim();
        _savedUsername = username;
        _loginError.Text = string.Empty;
        _loginOverlay.IsVisible = false;
        RevealEditor();
    }

    private void RenderTabs()
    {
        _tabBar.Children.Clear();
        foreach (var tab in _workspace.Tabs)
        {
            _tabBar.Children.Add(CreateTabVisual(tab));
        }

        var add = new Button
        {
            Width = 25,
            Height = 25,
            Background = Brushes.Transparent,
            BorderThickness = new Thickness(0),
            Padding = new Thickness(4),
            CornerRadius = new CornerRadius(4),
            Content = new TextBlock
            {
                Text = "+",
                FontSize = 18,
                Foreground = Brush.Parse("#6A6A6A"),
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center
            }
        };
        add.Classes.Add("awp-flat");
        add.Click += (_, _) =>
        {
            var next = NewTabState();
            _workspace.Tabs.Add(next);
            SelectTab(next);
        };
        _tabBar.Children.Add(add);
    }

    private Border CreateTabVisual(EditorTabState tab)
    {
        var active = tab.Id == _activeTab.Id;
        var border = new Border
        {
            Width = 150,
            Height = 28,
            Padding = new Thickness(5),
            CornerRadius = new CornerRadius(4),
            Background = active ? Brush.Parse("#282828") : Brushes.Transparent,
            BorderBrush = active ? Brush.Parse("#2C2C2C") : Brushes.Transparent,
            BorderThickness = new Thickness(1),
            Cursor = new Cursor(StandardCursorType.Hand)
        };

        var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("16,*,16") };
        var icon = new PathIcon
        {
            Data = (Geometry)Resources["AwpFileIcon"]!,
            Width = 14,
            Height = 14,
            Foreground = Brush.Parse("#808080"),
            VerticalAlignment = VerticalAlignment.Center
        };
        Grid.SetColumn(icon, 0);

        var title = new TextBlock
        {
            Text = tab.Title,
            FontSize = 13,
            Foreground = active ? Brush.Parse("#C5C5C5") : Brush.Parse("#808080"),
            TextTrimming = TextTrimming.CharacterEllipsis,
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new Thickness(6, 0, 0, 1)
        };
        title.DoubleTapped += (_, e) =>
        {
            e.Handled = true;
            BeginTabRename(tab, grid, title);
        };
        Grid.SetColumn(title, 1);

        var close = new Button
        {
            Width = 16,
            Height = 16,
            Padding = new Thickness(2),
            Background = Brushes.Transparent,
            BorderThickness = new Thickness(0),
            CornerRadius = new CornerRadius(4),
            Content = new TextBlock
            {
                Text = "×",
                FontSize = 13,
                Foreground = Brush.Parse("#808080"),
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center
            }
        };
        close.Classes.Add("awp-flat");
        close.Click += (_, e) =>
        {
            e.Handled = true;
            CloseTab(tab);
        };
        Grid.SetColumn(close, 2);

        grid.Children.Add(icon);
        grid.Children.Add(title);
        grid.Children.Add(close);
        border.Child = grid;
        border.PointerPressed += (_, e) =>
        {
            if (e.GetCurrentPoint(border).Properties.IsLeftButtonPressed)
            {
                SelectTab(tab);
                e.Handled = true;
            }
        };
        border.PointerEntered += (_, _) =>
        {
            if (tab.Id != _activeTab.Id)
            {
                border.Background = Brush.Parse("#282828");
            }
        };
        border.PointerExited += (_, _) =>
        {
            if (tab.Id != _activeTab.Id)
            {
                border.Background = Brushes.Transparent;
            }
        };
        return border;
    }

    private void BeginTabRename(EditorTabState tab, Grid grid, TextBlock title)
    {
        var input = new TextBox
        {
            Text = tab.Title,
            Background = Brushes.Transparent,
            BorderThickness = new Thickness(0),
            Foreground = Brush.Parse("#C5C5C5"),
            CaretBrush = Brush.Parse("#C5C5C5"),
            Padding = new Thickness(6, 0, 0, 0),
            FontSize = 13,
            VerticalContentAlignment = VerticalAlignment.Center
        };
        Grid.SetColumn(input, 1);
        grid.Children.Remove(title);
        grid.Children.Add(input);

        var committed = false;
        void Commit()
        {
            if (committed)
            {
                return;
            }

            committed = true;
            var name = (input.Text ?? string.Empty).Trim();
            tab.Title = name.Length == 0 ? "Untitled Tab" : name;
            RenderTabs();
        }

        input.LostFocus += (_, _) => Commit();
        input.KeyDown += (_, e) =>
        {
            if (e.Key == Key.Enter)
            {
                Commit();
                e.Handled = true;
            }
            else if (e.Key == Key.Escape)
            {
                committed = true;
                RenderTabs();
                e.Handled = true;
            }
        };
        input.Focus();
        input.SelectAll();
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
        if (_workspace.Tabs.Count == 1)
        {
            ShowToast("Cannot close last tab");
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

    private void RevealEditor()
    {
        if (_editorDisposed || !_scriptingPage.IsVisible || _loginOverlay.IsVisible)
        {
            return;
        }

        _editor.IsVisible = true;
        if (_editorSourceAssigned)
        {
            return;
        }

        _editorSourceAssigned = true;
        var address = new UriBuilder(_monacoAddress)
        {
            Query = "transparent=1&shell=awp"
        };
        _editor.Source = address.Uri;
    }

    private void Editor_WebMessageReceived(object? sender, WebMessageReceivedEventArgs args)
    {
        if (string.IsNullOrWhiteSpace(args.Body))
        {
            return;
        }

        try
        {
            using var payload = JsonDocument.Parse(args.Body);
            var root = payload.RootElement;
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
                    var targetTab = _activeTab;
                    Dispatcher.UIThread.Post(() => targetTab.Content = content);
                    break;
                }

                case "contentChangedDelta" when root.TryGetProperty("changes", out var changesProperty):
                {
                    var changes = changesProperty.Clone();
                    var targetTab = _activeTab;
                    Dispatcher.UIThread.Post(() =>
                    {
                        if (EditorContentDelta.TryApply(changes, targetTab.Content, out var content))
                        {
                            targetTab.Content = content;
                        }
                    });
                    break;
                }

                case "contentSnapshot" when root.TryGetProperty("content", out var snapshotProperty):
                {
                    var content = snapshotProperty.GetString() ?? string.Empty;
                    var targetTab = _activeTab;
                    Dispatcher.UIThread.Post(() =>
                    {
                        targetTab.Content = content;
                        _pendingEditorSnapshot?.TrySetResult(content);
                    });
                    break;
                }

                case "executeRequested" when root.TryGetProperty("content", out var executeProperty):
                {
                    var content = executeProperty.GetString() ?? string.Empty;
                    var targetTab = _activeTab;
                    Dispatcher.UIThread.Post(() =>
                    {
                        targetTab.Content = content;
                        if (_bridge.IsConnected)
                        {
                            _bridge.EnqueueExecute(content);
                        }
                    });
                    break;
                }
            }
        }
        catch (JsonException)
        {
            // Ignore messages not emitted by the shared Monaco bridge.
        }
    }

    private void PushActiveTabToEditor()
    {
        if (!_editorReady || _activeTab is null)
        {
            return;
        }

        var content = JsonSerializer.Serialize(_activeTab.Content);
        var language = JsonSerializer.Serialize(LanguageForExtension(_activeTab.Extension));
        try
        {
            _editor.InvokeScript(
                $"window.orbitSetContent && window.orbitSetContent({content}, {language});");
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

        _pendingEditorSnapshot?.TrySetCanceled();
        var completion = new TaskCompletionSource<string>(
            TaskCreationOptions.RunContinuationsAsynchronously);
        _pendingEditorSnapshot = completion;
        try
        {
            await _editor.InvokeScript(
                "window.orionRequestSnapshot && window.orionRequestSnapshot();");
            var completed = await Task.WhenAny(completion.Task, Task.Delay(700));
            return completed == completion.Task
                ? await completion.Task
                : _activeTab.Content;
        }
        catch (InvalidOperationException)
        {
            _editorReady = false;
            return _activeTab.Content;
        }
        finally
        {
            if (ReferenceEquals(_pendingEditorSnapshot, completion))
            {
                _pendingEditorSnapshot = null;
            }
        }
    }

    private static string LanguageForExtension(string extension) =>
        extension.ToLowerInvariant() switch
        {
            ".md" or ".markdown" => "markdown",
            ".json" => "json",
            ".js" or ".ts" => "javascript",
            ".txt" => "plaintext",
            _ => "lua"
        };

    private void Clear_Click(object? sender, RoutedEventArgs e)
    {
        _activeTab.Content = string.Empty;
        PushActiveTabToEditor();
    }

    private async void Execute_Click(object? sender, RoutedEventArgs e)
        => await ExecuteCurrentScriptAsync();

    private async Task ExecuteCurrentScriptAsync()
    {
        var source = await RequestEditorContentAsync();
        _activeTab.Content = source;
        if (string.IsNullOrWhiteSpace(source))
        {
            ShowToast("Nothing to execute");
            return;
        }

        if (!_bridge.IsConnected)
        {
            ShowToast("No bridge connection");
            return;
        }

        var targets = _selectedClientIdentifiers.ToArray();
        if (targets.Length == 0)
        {
            ShowToast("No clients selected");
            return;
        }

        _bridge.EnqueueExecute(source, targets);
    }

    private async void Open_Click(object? sender, RoutedEventArgs e)
    {
        var picked = await PickScriptAsync();
        if (picked is null)
        {
            return;
        }

        var (file, content) = picked.Value;
        OpenFileInTab(file.Name, content);
    }

    private async void ExecuteFile_Click(object? sender, RoutedEventArgs e)
    {
        var picked = await PickScriptAsync();
        if (picked is null)
        {
            return;
        }

        var (file, content) = picked.Value;
        OpenFileInTab(file.Name, content);
        if (_bridge.IsConnected && !string.IsNullOrWhiteSpace(content))
        {
            var targets = _selectedClientIdentifiers.ToArray();
            if (targets.Length == 0)
            {
                ShowToast("No clients selected");
                return;
            }
            _bridge.EnqueueExecute(content, targets);
        }
    }

    private async Task<(IStorageFile File, string Content)?> PickScriptAsync()
    {
        var files = await StorageProvider.OpenFilePickerAsync(new FilePickerOpenOptions
        {
            Title = "Open script",
            AllowMultiple = false,
            FileTypeFilter =
            [
                new FilePickerFileType("Script files")
                {
                    Patterns = ["*.lua", "*.luau", "*.txt"]
                }
            ]
        });
        var file = files.FirstOrDefault();
        if (file is null)
        {
            return null;
        }

        await using var stream = await file.OpenReadAsync();
        using var reader = new StreamReader(stream);
        return (file, await reader.ReadToEndAsync());
    }

    private void OpenFileInTab(string fileName, string content)
    {
        var tab = new EditorTabState
        {
            Title = Path.GetFileNameWithoutExtension(fileName),
            Extension = Path.GetExtension(fileName) is { Length: > 0 } extension ? extension : ".lua",
            Content = content
        };
        _workspace.Tabs.Add(tab);
        SelectTab(tab);
    }

    private async void Save_Click(object? sender, RoutedEventArgs e) => await SaveCurrentFileAsync();

    private async Task SaveCurrentFileAsync()
    {
        _activeTab.Content = await RequestEditorContentAsync();
        var file = await StorageProvider.SaveFilePickerAsync(new FilePickerSaveOptions
        {
            Title = "Save script",
            SuggestedFileName = SanitizeFileName(_activeTab.Title) + _activeTab.Extension,
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
        _activeTab.Title = Path.GetFileNameWithoutExtension(file.Name);
        _activeTab.Extension = Path.GetExtension(file.Name) is { Length: > 0 } extension ? extension : ".lua";
        RenderTabs();
        ShowToast($"Saved {file.Name}");
    }

    private static string SanitizeFileName(string value)
    {
        var invalid = Path.GetInvalidFileNameChars();
        var result = new string(value.Where(character => !invalid.Contains(character)).ToArray()).Trim();
        return result.Length == 0 ? "script" : result;
    }

    private void ConsoleHeader_PointerPressed(object? sender, PointerPressedEventArgs e)
    {
        if (e.Source is Control source &&
            (source is Button || source.FindAncestorOfType<Button>() is not null))
        {
            return;
        }

        if (e.GetCurrentPoint(this).Properties.IsLeftButtonPressed)
        {
            _consoleOpen = !_consoleOpen;
            ApplyConsoleState();
        }
    }

    private void ConsoleCaret_Click(object? sender, RoutedEventArgs e)
    {
        if (!_consoleVisible)
        {
            return;
        }

        _consoleOpen = !_consoleOpen;
        ApplyConsoleState();
        e.Handled = true;
    }

    private void ConsoleClear_Click(object? sender, RoutedEventArgs e)
    {
        _outputLines.Clear();
        _outputText.Inlines?.Clear();
        e.Handled = true;
    }

    private void ConsoleResizeGrip_PointerPressed(object? sender, PointerPressedEventArgs e)
    {
        if (!_consoleVisible || !_consoleOpen || sender is not Control grip ||
            !e.GetCurrentPoint(this).Properties.IsLeftButtonPressed)
        {
            return;
        }

        _consoleResizing = true;
        _consoleResizeStartPointerY = e.GetPosition(this).Y;
        _consoleResizeStartHeight = _consolePanel.Bounds.Height > 0
            ? _consolePanel.Bounds.Height
            : _consoleExpandedHeight;
        e.Pointer.Capture(grip);
        e.Handled = true;
    }

    private void ConsoleResizeGrip_PointerMoved(object? sender, PointerEventArgs e)
    {
        if (!_consoleResizing || !e.GetCurrentPoint(this).Properties.IsLeftButtonPressed)
        {
            return;
        }

        var pointerY = e.GetPosition(this).Y;
        var requestedHeight = _consoleResizeStartHeight + (_consoleResizeStartPointerY - pointerY);
        var maximumHeight = Math.Max(72, _scriptingPage.Bounds.Height - 130);
        _consoleExpandedHeight = Math.Clamp(requestedHeight, 72, maximumHeight);
        _consolePanel.Height = _consoleExpandedHeight;
        e.Handled = true;
    }

    private void ConsoleResizeGrip_PointerReleased(object? sender, PointerReleasedEventArgs e)
    {
        if (!_consoleResizing)
        {
            return;
        }

        _consoleResizing = false;
        e.Pointer.Capture(null);
        e.Handled = true;
    }

    private void ApplyConsoleState()
    {
        _consolePanel.IsVisible = _consoleVisible;
        _consolePanel.Height = _consoleOpen ? _consoleExpandedHeight : 33;
        _outputScroll.IsVisible = _consoleOpen;
        _consoleResizeGrip.IsVisible = _consoleOpen;
        _consoleCaret.Data = (Geometry)Resources[_consoleOpen ? "AwpChevronUpIcon" : "AwpChevronDownIcon"]!;
        _consoleStatusLabel.Text = $"Console: {(_consoleVisible ? "Visible" : "Hidden")}";
        _consoleVisibilityButton.Content = _consoleVisible ? "Hide" : "Show";
    }

    private void WorkspaceHeader_Click(object? sender, RoutedEventArgs e)
    {
        _workspaceOpen = !_workspaceOpen;
        _workspaceList.IsVisible = _workspaceOpen;
        _workspaceCaret.Data = (Geometry)Resources[_workspaceOpen ? "AwpChevronUpIcon" : "AwpChevronDownIcon"]!;
        _noScriptsText.IsVisible = _workspaceOpen && _workspaceList.ItemCount == 0;
    }

    private void ScriptSearchBox_TextChanged(object? sender, TextChangedEventArgs e)
        => ApplyWorkspaceFilter((sender as TextBox)?.Text ?? string.Empty);

    private void RefreshWorkspaceFiles()
    {
        _allScripts.Clear();
        try
        {
            Directory.CreateDirectory(_scriptsDirectory);
            _allScripts.AddRange(
                Directory.EnumerateFiles(_scriptsDirectory)
                    .Where(path => new[] { ".lua", ".luau", ".txt" }
                        .Contains(Path.GetExtension(path), StringComparer.OrdinalIgnoreCase))
                    .OrderBy(Path.GetFileName, StringComparer.OrdinalIgnoreCase)
                    .Select(path => new AWPScriptItem(Path.GetFileName(path), path)));
        }
        catch (IOException)
        {
            // Match the source UI's empty workspace fallback.
        }
        catch (UnauthorizedAccessException)
        {
            // Match the source UI's empty workspace fallback.
        }

        ApplyWorkspaceFilter(string.Empty);
    }

    private void ApplyWorkspaceFilter(string query)
    {
        var filtered = _allScripts
            .Where(item => query.Length == 0 || item.Name.Contains(query, StringComparison.OrdinalIgnoreCase))
            .ToList();
        _workspaceList.ItemsSource = filtered;
        _noScriptsText.IsVisible = _workspaceOpen && filtered.Count == 0;
    }

    private async void WorkspaceList_SelectionChanged(object? sender, SelectionChangedEventArgs e)
    {
        if (_workspaceList.SelectedItem is not AWPScriptItem item)
        {
            return;
        }

        _workspaceList.SelectedItem = null;
        try
        {
            OpenFileInTab(item.Name, await File.ReadAllTextAsync(item.Path));
        }
        catch (IOException exception)
        {
            ShowToast($"Read error: {exception.Message}");
        }
        catch (UnauthorizedAccessException exception)
        {
            ShowToast($"Read error: {exception.Message}");
        }
    }

    private void Attach_Click(object? sender, RoutedEventArgs e)
    {
        var connected = _bridge.IsConnected;
        ApplyBridgeState(connected);
        ShowToast(connected ? "Bridge connected" : "No bridge connection");
    }

    private void Launch_Click(object? sender, RoutedEventArgs e)
    {
        try
        {
            Process.Start(new ProcessStartInfo("roblox-player://") { UseShellExecute = true });
            AddOutput("Launching Roblox…", "info");
        }
        catch
        {
            ShowToast("Unable to launch Roblox");
        }
    }

    private void BridgeConnectionChanged(bool connected)
        => Dispatcher.UIThread.Post(() => ApplyBridgeState(connected));

    private void BridgeClientsChanged()
        => Dispatcher.UIThread.Post(RefreshClientManager);

    private void ClientManager_Click(object? sender, RoutedEventArgs e)
    {
        RefreshClientManager();
        _clientManagerPopup.IsOpen = !_clientManagerPopup.IsOpen;
        _clientManagerCaret.Data = (Geometry)Resources[
            _clientManagerPopup.IsOpen ? "AwpChevronDownIcon" : "AwpChevronUpIcon"]!;
    }

    private void RefreshClientManager()
    {
        var clients = _bridge.GetConnectedClients();
        var liveIdentifiers = new HashSet<string>(
            clients.Select(client => client.Identifier),
            StringComparer.OrdinalIgnoreCase);

        _selectedClientIdentifiers.RemoveWhere(identifier => !liveIdentifiers.Contains(identifier));
        _knownClientIdentifiers.RemoveWhere(identifier => !liveIdentifiers.Contains(identifier));
        foreach (var client in clients)
        {
            // A newly detected client is enabled by default, preserving the
            // single-client behaviour while still allowing any combination
            // to be disabled from AWP.
            if (_knownClientIdentifiers.Add(client.Identifier))
            {
                _selectedClientIdentifiers.Add(client.Identifier);
            }
        }

        _clientListPanel.Children.Clear();
        if (clients.Count == 0)
        {
            _clientListPanel.Children.Add(new TextBlock
            {
                Text = "No clients connected",
                Foreground = Brush.Parse("#606060"),
                FontSize = 11,
                FontStyle = FontStyle.Italic,
                Margin = new Thickness(8, 9, 8, 10),
                HorizontalAlignment = HorizontalAlignment.Center
            });
        }
        else
        {
            foreach (var client in clients)
            {
                _clientListPanel.Children.Add(BuildClientRow(client));
            }
        }

        var selected = clients
            .Where(client => _selectedClientIdentifiers.Contains(client.Identifier))
            .ToArray();
        _clientSummaryLabel.Text = selected.Length switch
        {
            0 => "None",
            1 => selected[0].Username,
            _ => $"{selected.Length} Clients"
        };
        ToolTip.SetTip(
            _clientManagerButton,
            selected.Length == 0
                ? "No execution clients selected"
                : "Executing on " + string.Join(", ", selected.Select(client => $"{client.Username} ({client.Identifier})")));
    }

    private Control BuildClientRow(UnifiedBridgeServer.BridgeClientInfo client)
    {
        var selected = _selectedClientIdentifiers.Contains(client.Identifier);
        var row = new Grid
        {
            ColumnDefinitions = new ColumnDefinitions("24,*,22"),
            Margin = new Thickness(7, 0)
        };
        row.Children.Add(new Avalonia.Controls.Shapes.Path
        {
            Width = 15,
            Height = 15,
            Stretch = Stretch.Uniform,
            Stroke = Brush.Parse(selected ? "#C5C5C5" : "#808080"),
            StrokeThickness = 1.7,
            StrokeLineCap = PenLineCap.Round,
            StrokeJoin = PenLineJoin.Round,
            Data = Geometry.Parse("M8,7 A4,4 0 1 0 16,7 A4,4 0 0 0 8,7 M6,21 V19 A4,4 0 0 1 10,15 H14 A4,4 0 0 1 18,19 V21"),
            VerticalAlignment = VerticalAlignment.Center
        });

        var identity = new StackPanel
        {
            Spacing = 0,
            VerticalAlignment = VerticalAlignment.Center
        };
        identity.Children.Add(new TextBlock
        {
            Text = client.Username,
            Foreground = Brush.Parse(selected ? "#C5C5C5" : "#8A8A8A"),
            FontSize = 12,
            FontWeight = FontWeight.SemiBold,
            TextTrimming = TextTrimming.CharacterEllipsis
        });
        identity.Children.Add(new TextBlock
        {
            Text = client.Identifier,
            Foreground = Brush.Parse("#606060"),
            FontSize = 9.5,
            TextTrimming = TextTrimming.CharacterEllipsis
        });
        Grid.SetColumn(identity, 1);
        row.Children.Add(identity);

        var check = new Border
        {
            Width = 15,
            Height = 15,
            CornerRadius = new CornerRadius(3),
            BorderBrush = Brush.Parse(selected ? "#686868" : "#444444"),
            BorderThickness = new Thickness(1),
            Background = Brush.Parse(selected ? "#3A3A3A" : "#202020"),
            VerticalAlignment = VerticalAlignment.Center
        };
        if (selected)
        {
            check.Child = new Avalonia.Controls.Shapes.Path
            {
                Width = 9,
                Height = 7,
                Stretch = Stretch.Uniform,
                Stroke = Brush.Parse("#C5C5C5"),
                StrokeThickness = 1.7,
                StrokeLineCap = PenLineCap.Round,
                StrokeJoin = PenLineJoin.Round,
                Data = Geometry.Parse("M1,4 L3.5,6.5 L8,1")
            };
        }
        Grid.SetColumn(check, 2);
        row.Children.Add(check);

        var button = new Button
        {
            Height = 45,
            MinHeight = 0,
            MinWidth = 0,
            Padding = new Thickness(0),
            Background = Brush.Parse(selected ? "#282828" : "#1F1F1F"),
            BorderBrush = Brush.Parse(selected ? "#343434" : "#252525"),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(3),
            HorizontalContentAlignment = HorizontalAlignment.Stretch,
            Content = row
        };
        button.Click += (_, _) =>
        {
            if (!_selectedClientIdentifiers.Remove(client.Identifier))
            {
                _selectedClientIdentifiers.Add(client.Identifier);
            }
            RefreshClientManager();
        };
        return button;
    }

    private void ApplyBridgeState(bool connected)
    {
        // Never infer the connected visual from a click or a remembered UI state.
        // The app-lifetime bridge watchdog is the sole source of truth.
        var bridgeConnected = connected && _bridge.IsConnected;
        _executeButton.IsEnabled = bridgeConnected;
        _executeFileButton.IsEnabled = bridgeConnected;
        _attachIcon.Data = (Geometry)Resources[bridgeConnected ? "AwpConnectedPlugIcon" : "AwpPlugIcon"]!;
        ToolTip.SetTip(_attachButton, bridgeConnected ? "Bridge Connected" : "Attach to Roblox");
    }

    private void BridgeLogReceived(string level, string message)
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
        var line = new AWPOutputLine(DateTime.Now.ToString("HH:mm:ss"), message, foreground);
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

        if (_consoleVisible && !_consoleOpen)
        {
            _consoleOpen = true;
            ApplyConsoleState();
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

    private void AppendOutputLine(AWPOutputLine line, bool prependLineBreak)
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
        inlines.Add(new Run
        {
            Text = line.Timestamp + " ",
            Foreground = Brush.Parse("#555555")
        });
        inlines.Add(new Run
        {
            Text = line.Message,
            Foreground = line.Foreground
        });
    }

    private void GeneralSettingsTab_Click(object? sender, RoutedEventArgs e)
    {
        _generalSettingsPanel.IsVisible = true;
        _editorSettingsPanel.IsVisible = false;
        _generalSettingsTab.Background = Brush.Parse("#2D2D2D");
        _generalSettingsTab.BorderBrush = Brush.Parse("#3A3A3A");
        _generalSettingsTab.BorderThickness = new Thickness(1);
        _generalSettingsTab.Foreground = Brush.Parse("#C5C5C5");
        _editorSettingsTab.Background = Brushes.Transparent;
        _editorSettingsTab.BorderBrush = Brushes.Transparent;
        _editorSettingsTab.BorderThickness = new Thickness(1);
        _editorSettingsTab.Foreground = Brush.Parse("#808080");
    }

    private void EditorSettingsTab_Click(object? sender, RoutedEventArgs e)
    {
        _generalSettingsPanel.IsVisible = false;
        _editorSettingsPanel.IsVisible = true;
        _editorSettingsTab.Background = Brush.Parse("#2D2D2D");
        _editorSettingsTab.BorderBrush = Brush.Parse("#3A3A3A");
        _editorSettingsTab.BorderThickness = new Thickness(1);
        _editorSettingsTab.Foreground = Brush.Parse("#C5C5C5");
        _generalSettingsTab.Background = Brushes.Transparent;
        _generalSettingsTab.BorderBrush = Brushes.Transparent;
        _generalSettingsTab.BorderThickness = new Thickness(1);
        _generalSettingsTab.Foreground = Brush.Parse("#808080");
    }

    private void Topmost_Click(object? sender, RoutedEventArgs e)
    {
        Topmost = !Topmost;
        UpdateSettingsVisuals();
    }

    private void AutoInject_Click(object? sender, RoutedEventArgs e)
    {
        _autoInject = !_autoInject;
        UpdateSettingsVisuals();
    }

    private void ConsoleVisibility_Click(object? sender, RoutedEventArgs e)
    {
        _consoleVisible = !_consoleVisible;
        ApplyConsoleState();
    }

    private void UpdateSettingsVisuals()
    {
        _topmostStatusLabel.Text = $"Always on Top: {(Topmost ? "On" : "Off")}";
        _topmostButton.Content = Topmost ? "Disable" : "Enable";
        _autoInjectStatusLabel.Text = $"Auto Inject: {(_autoInject ? "On" : "Off")}";
        _autoInjectButton.Content = _autoInject ? "Disable" : "Enable";
        ApplyConsoleState();
    }

    private void OpenScriptsFolder_Click(object? sender, RoutedEventArgs e)
    {
        try
        {
            Directory.CreateDirectory(_scriptsDirectory);
            Process.Start(new ProcessStartInfo("explorer.exe", _scriptsDirectory) { UseShellExecute = true });
        }
        catch
        {
            ShowToast("Unable to open workspace");
        }
    }

    private void ResetState_Click(object? sender, RoutedEventArgs e)
    {
        _workspace.Tabs.Clear();
        var first = NewTabState();
        _workspace.Tabs.Add(first);
        _outputLines.Clear();
        SelectTab(first);
        ShowToast("State reset");
    }

    private void OpenCredentials_Click(object? sender, RoutedEventArgs e)
    {
        _credentialsUsername.Text = _savedUsername;
        _credentialsPassword.Text = string.Empty;
        _credentialsOverlay.IsVisible = true;
        (_savedUsername.Length == 0 ? _credentialsUsername : _credentialsPassword).Focus();
    }

    private void CancelCredentials_Click(object? sender, RoutedEventArgs e)
        => _credentialsOverlay.IsVisible = false;

    private void SaveCredentials_Click(object? sender, RoutedEventArgs e)
    {
        var username = (_credentialsUsername.Text ?? string.Empty).Trim();
        if (username.Length == 0)
        {
            ShowToast("Username required");
            return;
        }

        _savedUsername = username;
        _credentialsOverlay.IsVisible = false;
        ShowToast("Credentials saved");
    }

    private void ShowToast(string message)
    {
        _toastText.Text = message;
        _toast.IsVisible = true;
        _toastTimer.Stop();
        _toastTimer.Start();
    }

    private sealed record AWPScriptItem(string Name, string Path);

    private sealed record AWPOutputLine(string Timestamp, string Message, IBrush Foreground);
}
