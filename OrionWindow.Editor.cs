using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Media.Imaging;
using Avalonia.Platform;
using Avalonia.Platform.Storage;
using Avalonia.Threading;
using System.Text.Json;
using ShapeEllipse = Avalonia.Controls.Shapes.Ellipse;

namespace OrbitAvalonia;

public sealed partial class OrionWindow
{
    private const double OrionTabsWidth = 485d;
    private const double OrionTabHeight = 28.985d;
    private const double OrionDefaultTabWidth = 108.209d;
    private const double OrionMinimumTabWidth = 51d;
    private const double OrionTabGap = 4d;
    private const double OrionAddTabWidth = 20d;
    private const int OrionMaximumTabs = 8;

    private readonly List<EditorTabState> _orionEditorTabs = [];
    private readonly UnifiedBridgeServer _orionBridge = UnifiedBridgeServer.Shared;
    private readonly CancellationTokenSource _orionEditorCancellation = new();
    private EditorWorkspaceService _orionWorkspace = null!;
    private MonacoStaticServer _orionMonacoServer = null!;
    private NativeWebView _orionMonacoWebView = null!;
    private Canvas _orionTabsCanvas = null!;
    private TextBlock _orionCursorPositionText = null!;
    private Button _orionExecuteButton = null!;
    private Border _orionExecuteVisual = null!;
    private DispatcherTimer _orionWorkspaceSaveTimer = null!;
    private EditorTabState _orionActiveTab = null!;
    private Bitmap _orionScriptFileIcon = null!;
    private Bitmap _orionNewTabIcon = null!;
    private TaskCompletionSource<string>? _orionPendingSnapshot;
    private bool _orionMonacoReady;
    private bool _orionMonacoNavigationStarted;
    private bool _orionClearAllRequested;
    private bool _orionEditorDisposed;

    private void InitializeOrionEditor()
    {
        _orionMonacoWebView = this.FindControl<NativeWebView>("OrionMonacoWebView")
            ?? throw new InvalidOperationException("OrionMonacoWebView was not found.");
        _orionTabsCanvas = this.FindControl<Canvas>("OrionTabsCanvas")
            ?? throw new InvalidOperationException("OrionTabsCanvas was not found.");
        _orionCursorPositionText = this.FindControl<TextBlock>("OrionCursorPositionText")
            ?? throw new InvalidOperationException("OrionCursorPositionText was not found.");
        _orionExecuteButton = this.FindControl<Button>("OrionExecuteButton")
            ?? throw new InvalidOperationException("OrionExecuteButton was not found.");
        _orionExecuteVisual = this.FindControl<Border>("OrionExecuteVisual")
            ?? throw new InvalidOperationException("OrionExecuteVisual was not found.");

        _orionScriptFileIcon = LoadOrionBitmap(
            "avares://Orion/Assets/Orion/Sharp/script-file.png");
        _orionNewTabIcon = LoadOrionBitmap(
            "avares://Orion/Assets/Orion/Sharp/new-tab-plus.png");

        _orionWorkspace = new EditorWorkspaceService();
        var state = _orionWorkspace.LoadState();
        _orionEditorTabs.AddRange(state.Tabs);
        _orionActiveTab = _orionEditorTabs.FirstOrDefault(tab => tab.Id == state.ActiveTabId)
            ?? _orionEditorTabs[0];

        var monacoDirectory = Path.Combine(AppContext.BaseDirectory, "MonacoPreview");
        _orionMonacoServer = new MonacoStaticServer(monacoDirectory);
        _orionMonacoWebView.WebMessageReceived += OrionMonacoWebView_WebMessageReceived;

        _orionWorkspaceSaveTimer = new DispatcherTimer
        {
            Interval = TimeSpan.FromMilliseconds(450)
        };
        _orionWorkspaceSaveTimer.Tick += OrionWorkspaceSaveTimer_Tick;

        _orionBridge.ConnectionChanged += OrionBridge_ConnectionChanged;
        ApplyOrionBridgeState(_orionBridge.IsConnected);
        RebuildOrionTabs();
        InitializeOrionConsole();
    }

    private static Bitmap LoadOrionBitmap(string assetUri)
    {
        using var stream = AssetLoader.Open(new Uri(assetUri));
        return new Bitmap(stream);
    }

    private void RevealOrionEditor()
    {
        if (_orionEditorDisposed || _orionCurrentPage != OrionPage.Editor)
        {
            return;
        }

        _orionMonacoWebView.IsVisible = true;
        if (_orionMonacoNavigationStarted)
        {
            return;
        }

        _orionMonacoNavigationStarted = true;
        var address = new UriBuilder(_orionMonacoServer.Address)
        {
            Query = "surface=orion&shell=orion"
        };
        _orionMonacoWebView.Source = address.Uri;
    }

    private void OrionMonacoWebView_WebMessageReceived(
        object? sender,
        WebMessageReceivedEventArgs args)
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

            var type = typeProperty.GetString();
            switch (type)
            {
                case "ready":
                    Dispatcher.UIThread.Post(() =>
                    {
                        _orionMonacoReady = true;
                        PushOrionActiveTabToMonaco();
                    });
                    break;

                case "contentChanged" when root.TryGetProperty("content", out var contentProperty):
                {
                    var content = contentProperty.GetString() ?? string.Empty;
                    Dispatcher.UIThread.Post(() =>
                    {
                        _orionActiveTab.Content = content;
                        ScheduleOrionWorkspaceSave();
                    });
                    break;
                }

                case "contentChangedDelta" when root.TryGetProperty("changes", out var changesProperty):
                {
                    var changes = changesProperty.Clone();
                    var targetTab = _orionActiveTab;
                    Dispatcher.UIThread.Post(() =>
                    {
                        if (EditorContentDelta.TryApply(changes, targetTab.Content, out var content))
                        {
                            targetTab.Content = content;
                            ScheduleOrionWorkspaceSave();
                        }
                    });
                    break;
                }

                case "contentSnapshot" when root.TryGetProperty("content", out var snapshotProperty):
                {
                    var content = snapshotProperty.GetString() ?? string.Empty;
                    Dispatcher.UIThread.Post(() =>
                    {
                        _orionActiveTab.Content = content;
                        _orionPendingSnapshot?.TrySetResult(content);
                        ScheduleOrionWorkspaceSave();
                    });
                    break;
                }

                case "executeRequested" when root.TryGetProperty("content", out var executeProperty):
                {
                    var content = executeProperty.GetString() ?? string.Empty;
                    Dispatcher.UIThread.Post(() =>
                    {
                        _orionActiveTab.Content = content;
                        ScheduleOrionWorkspaceSave();
                        if (_orionBridge.IsConnected)
                        {
                            _orionBridge.EnqueueExecute(content);
                        }
                    });
                    break;
                }

                case "cursorPosition"
                    when root.TryGetProperty("line", out var lineProperty) &&
                         root.TryGetProperty("column", out var columnProperty) &&
                         lineProperty.TryGetInt32(out var line) &&
                         columnProperty.TryGetInt32(out var column):
                    Dispatcher.UIThread.Post(() =>
                        _orionCursorPositionText.Text = $"Ln {line}, Col {column}");
                    break;
            }
        }
        catch (JsonException)
        {
            // Ignore browser messages that are not emitted by the editor bridge.
        }
    }

    private void PushOrionActiveTabToMonaco()
    {
        if (!_orionMonacoReady || _orionActiveTab is null)
        {
            return;
        }

        var content = JsonSerializer.Serialize(_orionActiveTab.Content);
        var language = JsonSerializer.Serialize(OrionLanguageForExtension(_orionActiveTab.Extension));
        try
        {
            _orionMonacoWebView.InvokeScript(
                $"window.orbitSetContent && window.orbitSetContent({content}, {language});");
        }
        catch (InvalidOperationException)
        {
            _orionMonacoReady = false;
        }
    }

    private async Task<string> RequestOrionEditorContentAsync()
    {
        if (!_orionMonacoReady)
        {
            return _orionActiveTab.Content;
        }

        _orionPendingSnapshot?.TrySetCanceled();
        var completion = new TaskCompletionSource<string>(
            TaskCreationOptions.RunContinuationsAsynchronously);
        _orionPendingSnapshot = completion;

        try
        {
            await _orionMonacoWebView.InvokeScript(
                "window.orionRequestSnapshot && window.orionRequestSnapshot();");
        }
        catch (InvalidOperationException)
        {
            _orionMonacoReady = false;
            _orionPendingSnapshot = null;
            return _orionActiveTab.Content;
        }

        try
        {
            var completed = await Task.WhenAny(
                completion.Task,
                Task.Delay(700, _orionEditorCancellation.Token));
            return completed == completion.Task
                ? await completion.Task
                : _orionActiveTab.Content;
        }
        catch (OperationCanceledException)
        {
            return _orionActiveTab.Content;
        }
        finally
        {
            if (ReferenceEquals(_orionPendingSnapshot, completion))
            {
                _orionPendingSnapshot = null;
            }
        }
    }

    private static string OrionLanguageForExtension(string extension) =>
        extension.ToLowerInvariant() switch
        {
            ".md" or ".markdown" => "markdown",
            ".json" => "json",
            ".js" or ".ts" => "javascript",
            ".txt" => "plaintext",
            _ => "lua"
        };

    private void RebuildOrionTabs()
    {
        _orionTabsCanvas.Children.Clear();
        var count = Math.Max(1, _orionEditorTabs.Count);
        var availableForTabs = OrionTabsWidth - OrionAddTabWidth - OrionTabGap;
        var tabWidth = Math.Clamp(
            (availableForTabs - (OrionTabGap * (count - 1))) / count,
            OrionMinimumTabWidth,
            OrionDefaultTabWidth);

        for (var index = 0; index < _orionEditorTabs.Count; index++)
        {
            var tab = _orionEditorTabs[index];
            var visual = CreateOrionTabVisual(tab, tabWidth);
            Canvas.SetLeft(visual, index * (tabWidth + OrionTabGap));
            Canvas.SetTop(visual, 0);
            _orionTabsCanvas.Children.Add(visual);
        }

        var plusLeft = _orionEditorTabs.Count * (tabWidth + OrionTabGap);
        var plus = new Border
        {
            Width = OrionAddTabWidth,
            Height = OrionTabHeight,
            Background = Brushes.Transparent,
            Cursor = new Cursor(StandardCursorType.Hand),
            Child = new Image
            {
                Width = 8,
                Height = 9,
                Stretch = Stretch.Uniform,
                Source = _orionNewTabIcon
            }
        };
        plus.PointerPressed += (_, eventArgs) =>
        {
            if (!eventArgs.GetCurrentPoint(this).Properties.IsLeftButtonPressed)
            {
                return;
            }

            eventArgs.Handled = true;
            AddOrionTab();
        };
        ToolTip.SetTip(plus, _orionEditorTabs.Count >= OrionMaximumTabs
            ? "Maximum tabs reached"
            : "New tab");
        Canvas.SetLeft(plus, plusLeft);
        Canvas.SetTop(plus, 0);
        _orionTabsCanvas.Children.Add(plus);
    }

    private Border CreateOrionTabVisual(EditorTabState tab, double tabWidth)
    {
        var isActive = tab.Id == _orionActiveTab.Id;
        var tabBorder = new Border
        {
            Tag = tab.Id,
            Width = tabWidth,
            Height = OrionTabHeight,
            Background = new SolidColorBrush(Color.Parse(isActive ? "#94080A0A" : "#520E1011")),
            BorderBrush = new SolidColorBrush(Color.Parse("#171A1D")),
            BorderThickness = new Thickness(0.667, 0.667, 0.667, 0),
            CornerRadius = new CornerRadius(4.667, 4.667, 0, 0),
            Cursor = new Cursor(StandardCursorType.Hand),
            ClipToBounds = true
        };

        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition(new GridLength(22.5)));
        grid.ColumnDefinitions.Add(new ColumnDefinition(new GridLength(1, GridUnitType.Star)));
        grid.ColumnDefinitions.Add(new ColumnDefinition(new GridLength(20)));

        var icon = new Image
        {
            Width = 8,
            Height = 9,
            Source = _orionScriptFileIcon,
            Stretch = Stretch.Uniform,
            HorizontalAlignment = HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new Thickness(0, 0, 3, 0),
            Opacity = isActive ? 1 : .58
        };
        Grid.SetColumn(icon, 0);
        grid.Children.Add(icon);

        if (tab.IsRenaming)
        {
            var renameBox = new TextBox
            {
                Text = tab.Title,
                Height = 20,
                Padding = new Thickness(2, 0),
                Margin = new Thickness(0, 4, 0, 4),
                Background = new SolidColorBrush(Color.Parse("#CC07080A")),
                BorderBrush = new SolidColorBrush(Color.Parse("#525558")),
                BorderThickness = new Thickness(.667),
                CornerRadius = new CornerRadius(2.5),
                Foreground = Brushes.White,
                FontSize = 8,
                VerticalContentAlignment = VerticalAlignment.Center
            };
            Grid.SetColumn(renameBox, 1);
            renameBox.PointerPressed += (_, eventArgs) => eventArgs.Handled = true;
            renameBox.Loaded += (_, _) =>
            {
                renameBox.Focus();
                renameBox.SelectAll();
            };
            renameBox.KeyDown += (_, eventArgs) =>
            {
                if (eventArgs.Key == Key.Enter)
                {
                    CommitOrionTabRename(tab, renameBox.Text);
                    eventArgs.Handled = true;
                }
                else if (eventArgs.Key == Key.Escape)
                {
                    tab.IsRenaming = false;
                    RebuildOrionTabs();
                    eventArgs.Handled = true;
                }
            };
            renameBox.LostFocus += (_, _) =>
            {
                if (tab.IsRenaming)
                {
                    CommitOrionTabRename(tab, renameBox.Text);
                }
            };
            grid.Children.Add(renameBox);
        }
        else
        {
            var title = new TextBlock
            {
                Text = tab.Title,
                FontSize = 8,
                FontWeight = FontWeight.Bold,
                Foreground = new SolidColorBrush(Color.Parse(isActive ? "#FFFFFF" : "#7D7D80")),
                VerticalAlignment = VerticalAlignment.Center,
                TextTrimming = TextTrimming.CharacterEllipsis
            };
            Grid.SetColumn(title, 1);
            grid.Children.Add(title);
        }

        var dot = new ShapeEllipse
        {
            Width = 5,
            Height = 5,
            Fill = new SolidColorBrush(Color.Parse("#595C5F")),
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center
        };
        var closeTarget = new Border
        {
            Width = 20,
            Height = OrionTabHeight,
            Background = Brushes.Transparent,
            Child = dot,
            Cursor = new Cursor(StandardCursorType.Hand)
        };
        closeTarget.PointerEntered += (_, _) =>
            dot.Fill = new SolidColorBrush(Color.Parse("#9A5C61"));
        closeTarget.PointerExited += (_, _) =>
            dot.Fill = new SolidColorBrush(Color.Parse("#595C5F"));
        closeTarget.PointerPressed += (_, eventArgs) =>
        {
            if (!eventArgs.GetCurrentPoint(this).Properties.IsLeftButtonPressed)
            {
                return;
            }

            eventArgs.Handled = true;
            CloseOrionTab(tab);
        };
        ToolTip.SetTip(closeTarget, "Close tab");
        Grid.SetColumn(closeTarget, 2);
        grid.Children.Add(closeTarget);

        tabBorder.Child = grid;
        tabBorder.PointerPressed += (_, eventArgs) =>
        {
            if (!eventArgs.GetCurrentPoint(this).Properties.IsLeftButtonPressed)
            {
                return;
            }

            eventArgs.Handled = true;
            if (eventArgs.ClickCount >= 2)
            {
                _orionActiveTab = tab;
                tab.IsRenaming = true;
                RebuildOrionTabs();
                return;
            }

            SelectOrionTab(tab);
        };
        if (tabWidth < 88)
        {
            ToolTip.SetTip(tabBorder, tab.Title);
        }

        return tabBorder;
    }

    private void AddOrionTab()
    {
        if (_orionEditorTabs.Count >= OrionMaximumTabs)
        {
            return;
        }

        var number = 1;
        string title;
        do
        {
            title = $"Script {number++}";
        }
        while (_orionEditorTabs.Any(tab =>
                   tab.Title.Equals(title, StringComparison.OrdinalIgnoreCase)));

        var tab = new EditorTabState { Title = title, Extension = ".lua" };
        _orionEditorTabs.Add(tab);
        _orionActiveTab = tab;
        RebuildOrionTabs();
        _ = AnimateOrionTabInAsync(tab.Id);
        PushOrionActiveTabToMonaco();
        ScheduleOrionWorkspaceSave();
    }

    private void OpenOrionTab(string title, string content, string extension)
    {
        if (_orionEditorTabs.Count >= OrionMaximumTabs)
        {
            return;
        }

        var tab = new EditorTabState
        {
            Title = string.IsNullOrWhiteSpace(title) ? "Untitled" : title.Trim(),
            Content = content,
            Extension = string.IsNullOrWhiteSpace(extension) ? ".lua" : extension
        };
        _orionEditorTabs.Add(tab);
        _orionActiveTab = tab;
        RebuildOrionTabs();
        _ = AnimateOrionTabInAsync(tab.Id);
        PushOrionActiveTabToMonaco();
        ScheduleOrionWorkspaceSave();
    }

    private void SelectOrionTab(EditorTabState tab)
    {
        if (_orionActiveTab.Id == tab.Id)
        {
            return;
        }

        _orionActiveTab = tab;
        RebuildOrionTabs();
        PushOrionActiveTabToMonaco();
        ScheduleOrionWorkspaceSave();
    }

    private async void CloseOrionTab(EditorTabState tab)
    {
        if (!_orionEditorTabs.Contains(tab))
        {
            return;
        }

        var visual = FindOrionTabVisual(tab.Id);
        if (visual is not null && AreClientAnimationsEnabled())
        {
            var translation = new TranslateTransform();
            visual.RenderTransform = translation;
            try
            {
                await AnimateAsync(
                    TimeSpan.FromMilliseconds(165),
                    progress =>
                    {
                        translation.Y = Lerp(0, 30, progress);
                        visual.Opacity = 1d - progress;
                    },
                    progress => progress * progress * progress,
                    _orionEditorCancellation.Token);
            }
            catch (OperationCanceledException)
            {
                return;
            }
        }

        var index = _orionEditorTabs.IndexOf(tab);
        if (index < 0)
        {
            return;
        }

        var wasActive = tab.Id == _orionActiveTab.Id;
        _orionEditorTabs.RemoveAt(index);
        if (_orionEditorTabs.Count == 0)
        {
            var replacement = new EditorTabState { Title = "Script 1", Extension = ".lua" };
            _orionEditorTabs.Add(replacement);
            _orionActiveTab = replacement;
        }
        else if (wasActive)
        {
            _orionActiveTab = _orionEditorTabs[Math.Clamp(index, 0, _orionEditorTabs.Count - 1)];
        }

        RebuildOrionTabs();
        PushOrionActiveTabToMonaco();
        ScheduleOrionWorkspaceSave();
    }

    private async Task AnimateOrionTabInAsync(Guid tabId)
    {
        var visual = FindOrionTabVisual(tabId);
        if (visual is null || !AreClientAnimationsEnabled())
        {
            return;
        }

        var translation = new TranslateTransform { Y = 30 };
        visual.RenderTransform = translation;
        visual.Opacity = 0;
        try
        {
            await AnimateAsync(
                TimeSpan.FromMilliseconds(220),
                progress =>
                {
                    translation.Y = Lerp(30, 0, progress);
                    visual.Opacity = progress;
                },
                CubicEaseOut,
                _orionEditorCancellation.Token);
        }
        catch (OperationCanceledException)
        {
            // Closing Orion cancels any remaining entrance frame.
        }
    }

    private Border? FindOrionTabVisual(Guid tabId) =>
        _orionTabsCanvas.Children
            .OfType<Border>()
            .FirstOrDefault(control => control.Tag is Guid id && id == tabId);

    private void CommitOrionTabRename(EditorTabState tab, string? requestedTitle)
    {
        var title = (requestedTitle ?? string.Empty).Trim();
        if (title.Length > 0)
        {
            tab.Title = title[..Math.Min(title.Length, 80)];
        }

        tab.IsRenaming = false;
        RebuildOrionTabs();
        ScheduleOrionWorkspaceSave();
    }

    private void OrionBridge_ConnectionChanged(bool connected) =>
        Dispatcher.UIThread.Post(() => ApplyOrionBridgeState(connected));

    private void ApplyOrionBridgeState(bool connected)
    {
        _orionExecuteButton.IsEnabled = connected;
        _orionExecuteVisual.Opacity = connected ? 1 : .5;
        ToolTip.SetTip(
            _orionExecuteButton,
            connected
                ? "Execute current script"
                : "Execute Orion Bridge first");
    }

    private async void OrionExecute_Click(object? sender, RoutedEventArgs e)
    {
        if (!_orionBridge.IsConnected)
        {
            return;
        }

        var content = await RequestOrionEditorContentAsync();
        _orionActiveTab.Content = content;
        ScheduleOrionWorkspaceSave();
        _orionBridge.EnqueueExecute(content);
    }

    private async void OrionSave_Click(object? sender, RoutedEventArgs e)
    {
        var content = await RequestOrionEditorContentAsync();
        _orionActiveTab.Content = content;

        var scriptsFolder = await StorageProvider.TryGetFolderFromPathAsync(
            new Uri(_orionWorkspace.ScriptsDirectory));
        var extension = string.IsNullOrWhiteSpace(_orionActiveTab.Extension)
            ? ".lua"
            : _orionActiveTab.Extension;
        var file = await StorageProvider.SaveFilePickerAsync(new FilePickerSaveOptions
        {
            Title = "Save script",
            SuggestedStartLocation = scriptsFolder,
            SuggestedFileName = _orionActiveTab.Title + extension,
            DefaultExtension = extension.TrimStart('.'),
            FileTypeChoices =
            [
                new FilePickerFileType("Lua script") { Patterns = ["*.lua", "*.luau"] },
                new FilePickerFileType("Text file") { Patterns = ["*.txt", "*.md"] },
                FilePickerFileTypes.All
            ],
            ShowOverwritePrompt = true
        });

        if (file is null)
        {
            return;
        }

        await using (var stream = await file.OpenWriteAsync())
        {
            if (stream.CanSeek)
            {
                stream.SetLength(0);
            }

            await using var writer = new StreamWriter(
                stream,
                new UTF8Encoding(false),
                8192,
                leaveOpen: false);
            await writer.WriteAsync(content);
        }

        _orionActiveTab.Title = Path.GetFileNameWithoutExtension(file.Name);
        _orionActiveTab.Extension = Path.GetExtension(file.Name);
        RebuildOrionTabs();
        ScheduleOrionWorkspaceSave();
    }

    private async void OrionOpen_Click(object? sender, RoutedEventArgs e)
    {
        var selectedFiles = await StorageProvider.OpenFilePickerAsync(new FilePickerOpenOptions
        {
            Title = "Open script",
            AllowMultiple = false,
            FileTypeFilter =
            [
                new FilePickerFileType("Script and text files")
                {
                    Patterns = ["*.lua", "*.luau", "*.txt", "*.md", "*.json", "*.js", "*.ts"]
                },
                FilePickerFileTypes.All
            ]
        });

        var file = selectedFiles.FirstOrDefault();
        if (file is null)
        {
            return;
        }

        await using var stream = await file.OpenReadAsync();
        using var reader = new StreamReader(stream, Encoding.UTF8, true);
        var content = await reader.ReadToEndAsync();
        OpenOrionTab(
            Path.GetFileNameWithoutExtension(file.Name),
            content,
            Path.GetExtension(file.Name));
    }

    private void OrionClear_PointerPressed(object? sender, PointerPressedEventArgs e)
    {
        _orionClearAllRequested = e.KeyModifiers.HasFlag(KeyModifiers.Shift);
    }

    private void OrionClear_Click(object? sender, RoutedEventArgs e)
    {
        if (_orionClearAllRequested)
        {
            foreach (var tab in _orionEditorTabs)
            {
                tab.Content = string.Empty;
            }
        }
        else
        {
            _orionActiveTab.Content = string.Empty;
        }

        _orionClearAllRequested = false;
        PushOrionActiveTabToMonaco();
        ScheduleOrionWorkspaceSave();
    }

    private void OrionWorkspaceSaveTimer_Tick(object? sender, EventArgs e)
    {
        _orionWorkspaceSaveTimer.Stop();
        PersistOrionWorkspace();
    }

    private void ScheduleOrionWorkspaceSave()
    {
        _orionWorkspaceSaveTimer.Stop();
        _orionWorkspaceSaveTimer.Start();
    }

    private void PersistOrionWorkspace()
    {
        if (_orionActiveTab is not null)
        {
            _orionWorkspace.SaveState(_orionEditorTabs, _orionActiveTab.Id);
        }
    }

    private void DisposeOrionEditor()
    {
        if (_orionEditorDisposed)
        {
            return;
        }

        _orionEditorDisposed = true;
        DisposeOrionConsole();
        _orionEditorCancellation.Cancel();
        _orionPendingSnapshot?.TrySetCanceled();
        _orionBridge.ConnectionChanged -= OrionBridge_ConnectionChanged;
        _orionMonacoWebView.WebMessageReceived -= OrionMonacoWebView_WebMessageReceived;
        _orionWorkspaceSaveTimer.Stop();
        PersistOrionWorkspace();
        _orionWorkspace.Dispose();
        _orionMonacoServer.Dispose();
        _orionScriptFileIcon.Dispose();
        _orionNewTabIcon.Dispose();
        _orionEditorCancellation.Dispose();
    }
}
