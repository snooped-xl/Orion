using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.Markup.Xaml;
using Avalonia.Media.Imaging;
using Avalonia.Platform;
using Avalonia.Platform.Storage;
using System.Text.Json;

namespace OrbitAvalonia;

/// <summary>
/// Native Avalonia preservation of Xeno's WPF shell. It intentionally contains
/// no injection or native Xeno backend integration. Execute and client
/// selection route through the shared native Orion Bridge.
/// </summary>
public sealed partial class XenoWindow : Window
{
    private readonly Uri _monacoAddress;
    private readonly string _scriptsDirectory;
    private readonly EditorWorkspaceState _workspaceState;
    private readonly Action<EditorWorkspaceState> _returnToOrbit;
    private readonly UnifiedBridgeServer _bridgeServer = UnifiedBridgeServer.Shared;
    private readonly NativeWebView _editorWebView;
    private readonly Button _executeActionButton;
    private readonly HashSet<string> _selectedClientIdentifiers = new(StringComparer.OrdinalIgnoreCase);
    private readonly HashSet<string> _knownClientIdentifiers = new(StringComparer.OrdinalIgnoreCase);
    private XenoScriptsWindow? _scriptsWindow;
    private XenoClientsWindow? _clientsWindow;
    private XenoSettingsWindow? _settingsWindow;
    private bool _closingForOrbit;
    private bool _editorLoaded;
    private bool _editorReady;
    private string _editorContent;

    // Avalonia's compiled XAML loader requires a public parameterless
    // constructor even though Orbit uses the address-aware overload below.
    public XenoWindow() : this(
        new Uri("http://127.0.0.1:1/index.html"),
        Path.Combine(AppContext.BaseDirectory, "Scripts"),
        CreateDefaultWorkspace(),
        static _ => { })
    {
    }

    internal XenoWindow(
        Uri monacoAddress,
        string scriptsDirectory,
        EditorWorkspaceState initialWorkspace,
        Action<EditorWorkspaceState> returnToOrbit)
    {
        _monacoAddress = monacoAddress;
        _scriptsDirectory = scriptsDirectory;
        _workspaceState = initialWorkspace.CloneDetached();
        if (_workspaceState.Tabs.Count == 0)
        {
            var firstTab = new EditorTabState { Title = "Script 1", Extension = ".lua" };
            _workspaceState.Tabs.Add(firstTab);
            _workspaceState.ActiveTabId = firstTab.Id;
        }
        _editorContent = ActiveWorkspaceTab().Content;
        _returnToOrbit = returnToOrbit;

        AvaloniaXamlLoader.Load(this);
        Topmost = OrbitPreferences.TopMostEnabled;
        CanResize = OrbitPreferences.ResizableEnabled;
        _editorWebView = this.FindControl<NativeWebView>("EditorWebView")
            ?? throw new InvalidOperationException("The Xeno editor was not created.");
        _executeActionButton = this.FindControl<Button>("ExecuteActionButton")
            ?? throw new InvalidOperationException("The Xeno execute button was not created.");
        _editorWebView.WebMessageReceived += (_, args) => HandleEditorMessage(args.Body);
        _bridgeServer.ConnectionChanged += BridgeConnectionChanged;
        _bridgeServer.ClientsChanged += BridgeClientsChanged;
        RefreshBridgeClients();

        Opened += XenoWindow_Opened;
        Closed += XenoWindow_Closed;
        PropertyChanged += XenoWindow_PropertyChanged;
    }

    private void XenoWindow_Opened(object? sender, EventArgs e)
    {
        if (_editorLoaded)
        {
            return;
        }

        _editorLoaded = true;
        var editorUri = new UriBuilder(_monacoAddress)
        {
            Query = "theme=xeno"
        };
        _editorWebView.Source = editorUri.Uri;
    }

    private void XenoWindow_Closed(object? sender, EventArgs e)
    {
        _bridgeServer.ConnectionChanged -= BridgeConnectionChanged;
        _bridgeServer.ClientsChanged -= BridgeClientsChanged;
        _scriptsWindow?.Close();
        _clientsWindow?.Close();
        _settingsWindow?.Close();
        _scriptsWindow = null;
        _clientsWindow = null;
        _settingsWindow = null;

        if (!_closingForOrbit)
        {
            ReturnWorkspaceToOrbit();
        }
    }

    private void XenoWindow_PropertyChanged(object? sender, AvaloniaPropertyChangedEventArgs e)
    {
        if (e.Property == WindowStateProperty)
        {
            var maximized = WindowState == WindowState.Maximized;
            if (this.FindControl<Border>("XenoChrome") is { } chrome)
            {
                chrome.CornerRadius = maximized ? new CornerRadius(0) : new CornerRadius(12);
                chrome.BorderThickness = maximized ? new Thickness(0) : new Thickness(1);
            }

            if (this.FindControl<Image>("MaximizeIcon") is { } icon)
            {
                icon.Source = LoadBitmap(maximized
                    ? "avares://Orion/Assets/Xeno/normalize.png"
                    : "avares://Orion/Assets/Xeno/maximize.png");
            }
        }
    }

    internal void CloseForOrbit()
    {
        _closingForOrbit = true;
        Close();
    }

    private void TitleBar_PointerPressed(object? sender, PointerPressedEventArgs e)
    {
        if (e.GetCurrentPoint(this).Properties.IsLeftButtonPressed && WindowState != WindowState.Maximized)
        {
            BeginMoveDrag(e);
        }
    }

    private void Minimize_Click(object? sender, RoutedEventArgs e) => WindowState = WindowState.Minimized;

    private void Maximize_Click(object? sender, RoutedEventArgs e)
    {
        if (OrbitPreferences.ResizableEnabled)
        {
            WindowState = WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized;
        }
    }

    private void Close_Click(object? sender, RoutedEventArgs e) => ReturnWorkspaceToOrbit();

    private async void Open_Click(object? sender, RoutedEventArgs e)
    {
        var files = await StorageProvider.OpenFilePickerAsync(new FilePickerOpenOptions
        {
            AllowMultiple = false,
            Title = "Open script",
            FileTypeFilter =
            [
                new FilePickerFileType("Script files")
                {
                    Patterns = ["*.lua", "*.luau", "*.txt", "*.md"]
                }
            ]
        });

        if (files.Count == 0)
        {
            return;
        }

        try
        {
            var filePath = files[0].Path.LocalPath;
            var content = await File.ReadAllTextAsync(filePath);
            var activeTab = ActiveWorkspaceTab();
            activeTab.Title = Path.GetFileNameWithoutExtension(filePath);
            activeTab.Extension = Path.GetExtension(filePath) is { Length: > 0 } extension
                ? extension
                : ".lua";
            SetEditorContent(content);
        }
        catch (IOException)
        {
            // This shell is a UI preservation and keeps file errors non-modal.
        }
    }

    private async void Save_Click(object? sender, RoutedEventArgs e)
    {
        var file = await StorageProvider.SaveFilePickerAsync(new FilePickerSaveOptions
        {
            Title = "Save script",
            SuggestedFileName = ActiveWorkspaceTab().Title + ActiveWorkspaceTab().Extension,
            FileTypeChoices =
            [
                new FilePickerFileType("Lua script") { Patterns = ["*.lua"] },
                new FilePickerFileType("Text file") { Patterns = ["*.txt"] }
            ]
        });

        if (file is null)
        {
            return;
        }

        try
        {
            await File.WriteAllTextAsync(file.Path.LocalPath, _editorContent);
        }
        catch (IOException)
        {
            // This UI-only shell keeps file errors non-modal.
        }
    }

    private void Clear_Click(object? sender, RoutedEventArgs e) => SetEditorContent(string.Empty);

    private void Execute_Click(object? sender, RoutedEventArgs e)
    {
        if (!HasLiveBridgeConnection)
        {
            return;
        }

        if (_editorReady)
        {
            try
            {
                _editorWebView.InvokeScript("window.orbitRequestExecute && window.orbitRequestExecute();");
                return;
            }
            catch (InvalidOperationException)
            {
                _editorReady = false;
            }
        }

        _bridgeServer.EnqueueExecute(_editorContent, SelectedClientIdentifiers());
    }

    private void BridgeConnectionChanged(bool connected) =>
        Avalonia.Threading.Dispatcher.UIThread.Post(() => ApplyBridgeConnectionState(connected));

    private void BridgeClientsChanged() =>
        Avalonia.Threading.Dispatcher.UIThread.Post(RefreshBridgeClients);

    private void RefreshBridgeClients()
    {
        var clients = _bridgeServer.GetConnectedClients();
        var liveIdentifiers = new HashSet<string>(
            clients.Select(client => client.Identifier),
            StringComparer.OrdinalIgnoreCase);

        _selectedClientIdentifiers.RemoveWhere(identifier => !liveIdentifiers.Contains(identifier));
        _knownClientIdentifiers.RemoveWhere(identifier => !liveIdentifiers.Contains(identifier));
        foreach (var client in clients)
        {
            if (_knownClientIdentifiers.Add(client.Identifier))
            {
                _selectedClientIdentifiers.Add(client.Identifier);
            }
        }

        _clientsWindow?.RefreshClients();
        ApplyBridgeConnectionState(_bridgeServer.IsConnected);
    }

    private void ApplyBridgeConnectionState(bool connected)
    {
        var bridgeConnected = connected && HasLiveBridgeConnection;
        var hasTarget = _selectedClientIdentifiers.Count > 0;
        _executeActionButton.IsEnabled = bridgeConnected && hasTarget;
        _executeActionButton.Opacity = bridgeConnected && hasTarget ? 1 : .52;
        ToolTip.SetTip(_executeActionButton,
            !bridgeConnected
                ? "Execute (run Scripts/Orion Bridge.lua first)"
                : hasTarget ? "Execute" : "Select at least one client");
    }

    private bool HasLiveBridgeConnection =>
        _bridgeServer.IsConnected && _bridgeServer.GetConnectedClients().Count > 0;

    private void Scripts_Click(object? sender, RoutedEventArgs e)
    {
        if (_scriptsWindow is { IsVisible: true })
        {
            _scriptsWindow.Close();
            return;
        }

        _scriptsWindow ??= new XenoScriptsWindow(
            _scriptsDirectory,
            SelectedClientIdentifiers);
        _scriptsWindow.Closed -= ScriptsWindow_Closed;
        _scriptsWindow.Closed += ScriptsWindow_Closed;
        _scriptsWindow.Show();
        _scriptsWindow.Activate();
    }

    private void Clients_Click(object? sender, RoutedEventArgs e)
    {
        if (_clientsWindow is { IsVisible: true })
        {
            _clientsWindow.Hide();
            return;
        }

        _clientsWindow ??= new XenoClientsWindow(
            _bridgeServer,
            _selectedClientIdentifiers,
            () => ApplyBridgeConnectionState(_bridgeServer.IsConnected));
        _clientsWindow.Closed -= ClientsWindow_Closed;
        _clientsWindow.Closed += ClientsWindow_Closed;
        _clientsWindow.RefreshClients();
        _clientsWindow.Show(this);
        _clientsWindow.Activate();
    }

    private void Settings_Click(object? sender, RoutedEventArgs e)
    {
        if (_settingsWindow is { IsVisible: true })
        {
            _settingsWindow.Activate();
            return;
        }

        // NativeWebView is a real child HWND. Hide the Xeno shell while the
        // secondary settings surface is open so that HWND z-order cannot put
        // Monaco above the settings window.
        Hide();
        _settingsWindow = new XenoSettingsWindow(ReturnWorkspaceToOrbit);
        _settingsWindow.Closed += SettingsWindow_Closed;
        _settingsWindow.Show();
        _settingsWindow.Activate();
    }

    private void ScriptsWindow_Closed(object? sender, EventArgs e) => _scriptsWindow = null;

    private void ClientsWindow_Closed(object? sender, EventArgs e) => _clientsWindow = null;

    private IReadOnlyCollection<string> SelectedClientIdentifiers() =>
        _selectedClientIdentifiers.ToArray();

    private void SettingsWindow_Closed(object? sender, EventArgs e)
    {
        _settingsWindow = null;
        if (!_closingForOrbit)
        {
            Show();
            Activate();
        }
    }

    private void SetEditorContent(string content)
    {
        _editorContent = content;
        ActiveWorkspaceTab().Content = content;
        var serialized = JsonSerializer.Serialize(content);
        try
        {
            _editorWebView.InvokeScript($"window.orbitSetContent && window.orbitSetContent({serialized}, 'lua');");
        }
        catch (InvalidOperationException)
        {
            // Monaco may still be loading; the action can safely be retried.
        }
    }

    private void HandleEditorMessage(string? message)
    {
        if (string.IsNullOrWhiteSpace(message))
        {
            return;
        }

        try
        {
            using var payload = JsonDocument.Parse(message);
            var root = payload.RootElement;
            if (!root.TryGetProperty("type", out var type))
            {
                return;
            }

            if (type.GetString() == "ready")
            {
                _editorReady = true;
                SetEditorContent(_editorContent);
            }
            else if (type.GetString() == "contentChanged" &&
                root.TryGetProperty("content", out var content))
            {
                _editorContent = content.GetString() ?? string.Empty;
                ActiveWorkspaceTab().Content = _editorContent;
            }
            else if (type.GetString() == "contentChangedDelta" &&
                root.TryGetProperty("changes", out var changes) &&
                EditorContentDelta.TryApply(changes, _editorContent, out var updatedContent))
            {
                _editorContent = updatedContent;
                ActiveWorkspaceTab().Content = _editorContent;
            }
            else if (type.GetString() == "executeRequested" &&
                root.TryGetProperty("content", out var executeContent))
            {
                _editorContent = executeContent.GetString() ?? string.Empty;
                ActiveWorkspaceTab().Content = _editorContent;
                if (HasLiveBridgeConnection)
                {
                    _bridgeServer.EnqueueExecute(
                        _editorContent,
                        SelectedClientIdentifiers());
                }
            }
        }
        catch (JsonException)
        {
            // Ignore unrelated browser messages.
        }
    }

    private EditorTabState ActiveWorkspaceTab()
    {
        var activeTab = _workspaceState.Tabs.FirstOrDefault(tab => tab.Id == _workspaceState.ActiveTabId)
            ?? _workspaceState.Tabs[0];
        _workspaceState.ActiveTabId = activeTab.Id;
        return activeTab;
    }

    private void ReturnWorkspaceToOrbit()
    {
        ActiveWorkspaceTab().Content = _editorContent;
        _returnToOrbit(_workspaceState.CloneDetached());
    }

    private static EditorWorkspaceState CreateDefaultWorkspace()
    {
        var firstTab = new EditorTabState
        {
            Title = "Script 1",
            Extension = ".lua",
            Content = "-- Xeno UI preview\n"
        };
        return new EditorWorkspaceState
        {
            Tabs = [firstTab],
            ActiveTabId = firstTab.Id
        };
    }

    private static Bitmap LoadBitmap(string uri) => new(AssetLoader.Open(new Uri(uri)));
}
