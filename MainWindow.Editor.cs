using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.Media;
using Avalonia.Platform.Storage;
using Avalonia.Threading;
using System.Text;
using System.Text.Json;
using ShapeEllipse = Avalonia.Controls.Shapes.Ellipse;
using ShapePath = Avalonia.Controls.Shapes.Path;

namespace OrbitAvalonia;

public sealed partial class MainWindow
{
    private readonly List<EditorTabState> _editorTabs = [];
    private EditorWorkspaceService _editorWorkspace = null!;
    private NativeWebView _monacoWebView = null!;
    private StackPanel _explorerTree = null!;
    private StackPanel _editorTabsPanel = null!;
    private Grid _gistDialogOverlay = null!;
    private Border _gistDialogBackdrop = null!;
    private Viewbox _gistDialogPopup = null!;
    private ScaleTransform _gistDialogScale = null!;
    private TranslateTransform _gistDialogTranslation = null!;
    private TextBox _gistUrlTextBox = null!;
    private TextBlock _gistDialogStatusText = null!;
    private Button _gistDialogAddButton = null!;
    private DispatcherTimer _workspaceSaveTimer = null!;
    private EditorTabState _activeEditorTab = null!;
    private CancellationTokenSource? _gistDialogCancellation;
    private CancellationTokenSource? _gistDialogAnimationCancellation;
    private readonly Dictionary<Guid, CancellationTokenSource> _editorTabMotionCancellations = [];
    private readonly HashSet<Guid> _closingEditorTabIds = [];
    private AppPage _currentPage = AppPage.Editor;
    private bool _scriptsExpanded = true;
    private bool _autoExecuteExpanded;
    private bool _githubGistsExpanded;
    private bool _monacoReady;
    private bool _isRebuildingEditorTabs;

    private IBrush ExplorerTextBrush => FindThemeBrush("OrbitSubtextBrush", "#A1A4A6");
    private IBrush ExplorerHoverBrush => FindThemeBrush("OrbitControlHoverBrush", "#1B1E21");
    private IBrush ActiveTabBrush => FindThemeBrush("OrbitChoiceBrush", "#181B1D");
    private IBrush InactiveTabBrush => FindThemeBrush("OrbitDeepBrush", "#101216");
    private IBrush TabCloseBrush => FindThemeBrush("OrbitMutedTextBrush", "#595C5F");
    private IBrush TabCloseHoverBrush => BrushFrom("#9A5C61");

    private void InitializeEditorWorkspace()
    {
        _editorWorkspace = new EditorWorkspaceService();
        _explorerTree = this.FindControl<StackPanel>("ExplorerTree") ?? new StackPanel();
        _editorTabsPanel = this.FindControl<StackPanel>("EditorTabsPanel") ?? new StackPanel();
        _gistDialogOverlay = this.FindControl<Grid>("GistDialogOverlay") ?? new Grid();
        _gistDialogBackdrop = this.FindControl<Border>("GistDialogBackdrop") ?? new Border();
        _gistDialogPopup = this.FindControl<Viewbox>("GistDialogPopup") ?? new Viewbox();
        _gistUrlTextBox = this.FindControl<TextBox>("GistUrlTextBox") ?? new TextBox();
        _gistDialogStatusText = this.FindControl<TextBlock>("GistDialogStatusText") ?? new TextBlock();
        _gistDialogAddButton = this.FindControl<Button>("GistDialogAddButton") ?? new Button();

        var transformGroup = _gistDialogPopup.RenderTransform as TransformGroup ?? new TransformGroup();
        _gistDialogScale = transformGroup.Children.Count > 0 ? transformGroup.Children[0] as ScaleTransform ?? new ScaleTransform() : new ScaleTransform();
        _gistDialogTranslation = transformGroup.Children.Count > 1 ? transformGroup.Children[1] as TranslateTransform ?? new TranslateTransform() : new TranslateTransform();

        var state = _editorWorkspace.LoadState();
        _editorTabs.AddRange(state.Tabs);
        _activeEditorTab = _editorTabs.FirstOrDefault(tab => tab.Id == state.ActiveTabId)
            ?? _editorTabs[0];

        _workspaceSaveTimer = new DispatcherTimer
        {
            Interval = TimeSpan.FromMilliseconds(450)
        };
        _workspaceSaveTimer.Tick += (_, _) =>
        {
            _workspaceSaveTimer.Stop();
            PersistEditorWorkspace();
        };

        RebuildExplorerTree();
        RebuildEditorTabs();
    }

    private void HandleMonacoMessage(string message)
    {
        try
        {
            using var payload = JsonDocument.Parse(message);
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
                        _monacoReady = true;
                        // Adapter creation is asynchronous. Reassert the page
                        // gate after it completes so the native HWND cannot be
                        // revealed by a late ready callback on another page.
                        UpdateMonacoVisibility();
                        PushActiveTabToMonaco();
                    });
                    break;

                case "contentChanged" when root.TryGetProperty("content", out var contentProperty):
                {
                    var content = contentProperty.GetString() ?? string.Empty;
                    Dispatcher.UIThread.Post(() =>
                    {
                        _activeEditorTab.Content = content;
                        ScheduleWorkspaceSave();
                    });
                    break;
                }

                case "contentChangedDelta" when root.TryGetProperty("changes", out var changesProperty):
                {
                    var changes = changesProperty.Clone();
                    var targetTab = _activeEditorTab;
                    Dispatcher.UIThread.Post(() =>
                    {
                        if (EditorContentDelta.TryApply(changes, targetTab.Content, out var content))
                        {
                            targetTab.Content = content;
                            ScheduleWorkspaceSave();
                        }
                    });
                    break;
                }

                case "executeRequested" when root.TryGetProperty("content", out var executeContentProperty):
                {
                    var content = executeContentProperty.GetString() ?? string.Empty;
                    Dispatcher.UIThread.Post(() =>
                    {
                        _activeEditorTab.Content = content;
                        ScheduleWorkspaceSave();
                        if (_bridgeServer.IsConnected)
                        {
                            _bridgeServer.EnqueueExecute(content);
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
                        _cursorPositionText.Text = $"Ln {line}, Col {column}");
                    break;
            }
        }
        catch (JsonException)
        {
            // Ignore unrelated messages produced by the embedded browser.
        }
    }

    private void PushActiveTabToMonaco()
    {
        if (!_monacoReady || _activeEditorTab is null)
        {
            return;
        }

        var content = JsonSerializer.Serialize(_activeEditorTab.Content);
        var language = JsonSerializer.Serialize(LanguageForExtension(_activeEditorTab.Extension));
        try
        {
            _monacoWebView.InvokeScript(
                $"window.orbitSetContent && window.orbitSetContent({content}, {language});");
        }
        catch (InvalidOperationException)
        {
            // Monaco will send another ready event if its native browser is recreated.
            _monacoReady = false;
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

    private void RebuildEditorTabs()
    {
        if (_isRebuildingEditorTabs)
        {
            return;
        }

        _isRebuildingEditorTabs = true;
        try
        {
            _editorTabsPanel.Children.Clear();
            var tabLayout = GetResponsiveTabLayout();

        foreach (var tab in _editorTabs)
        {
            var isActive = tab.Id == _activeEditorTab.Id;
            var tabBorder = new Border
            {
                Tag = tab.Id,
                Width = tabLayout.TabWidth,
                Height = 45,
                Background = isActive ? ActiveTabBrush : InactiveTabBrush,
                BorderBrush = FindThemeBrush("OrbitBorderBrush", "#171A1D"),
                BorderThickness = new Thickness(1, 1, 1, 0),
                CornerRadius = new CornerRadius(10, 10, 0, 0),
                Cursor = new Cursor(StandardCursorType.Hand)
            };

            var grid = new Grid
            {
                Margin = new Thickness(tabLayout.HorizontalMargin, 0)
            };
            grid.ColumnDefinitions.Add(new ColumnDefinition(new GridLength(tabLayout.IconColumnWidth)));
            grid.ColumnDefinitions.Add(new ColumnDefinition(new GridLength(1, GridUnitType.Star)));
            grid.ColumnDefinitions.Add(new ColumnDefinition(new GridLength(tabLayout.CloseColumnWidth)));

            var fileIcon = new ShapePath
            {
                Width = tabLayout.IconWidth,
                Height = tabLayout.IconHeight,
                Stretch = Stretch.Fill,
                Fill = isActive ? FindThemeBrush("OrbitTextBrush", "#FFFFFF") : ExplorerTextBrush,
                Data = Geometry.Parse("M9.48 11.7C9.24 12.48 8.58 13 7.8 13H1.8C0.78 13 0 12.155 0 11.05V10.4H7.32C7.56 11.18 8.22 11.7 9 11.7H9.48ZM10.2 0H3.6C2.58 0 1.8 0.845 1.8 1.95V9.1H8.4V9.75C8.4 10.14 8.64 10.4 9 10.4H9.6V1.95C9.6 1.56 9.84 1.3 10.2 1.3C10.56 1.3 10.8 1.56 10.8 1.95V2.6H12V1.95C12 0.845 11.22 0 10.2 0Z")
            };
            Grid.SetColumn(fileIcon, 0);
            grid.Children.Add(fileIcon);

            if (tab.IsRenaming)
            {
                var renameBox = new TextBox
                {
                    Text = tab.Title,
                    Height = tabLayout.RenameHeight,
                    Padding = new Thickness(4, 0),
                    Margin = new Thickness(0, 3, 0, 3),
                    Background = BrushFrom("#0F1216"),
                    BorderBrush = BrushFrom("#55595C"),
                    BorderThickness = new Thickness(1),
                    Foreground = Brushes.White,
                    FontSize = tabLayout.FontSize,
                    VerticalContentAlignment = Avalonia.Layout.VerticalAlignment.Center
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
                        CommitTabRename(tab, renameBox.Text);
                        eventArgs.Handled = true;
                    }
                    else if (eventArgs.Key == Key.Escape)
                    {
                        tab.IsRenaming = false;
                        RebuildEditorTabs();
                        eventArgs.Handled = true;
                    }
                };
                renameBox.LostFocus += (_, _) =>
                {
                    if (tab.IsRenaming)
                    {
                        CommitTabRename(tab, renameBox.Text);
                    }
                };
                grid.Children.Add(renameBox);
            }
            else
            {
                var title = new TextBlock
                {
                    Text = tabLayout.ShowTitle ? tab.Title : string.Empty,
                    FontSize = tabLayout.FontSize,
                    Foreground = isActive ? FindThemeBrush("OrbitTextBrush", "#FFFFFF") : ExplorerTextBrush,
                    VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center,
                    TextTrimming = TextTrimming.CharacterEllipsis
                };
                Grid.SetColumn(title, 1);
                grid.Children.Add(title);
            }

            var closeDot = new ShapeEllipse
            {
                Width = tabLayout.DotWidth,
                Height = tabLayout.DotHeight,
                Fill = TabCloseBrush,
                HorizontalAlignment = Avalonia.Layout.HorizontalAlignment.Center,
                VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center
            };
            var closeHitTarget = new Border
            {
                Width = tabLayout.CloseColumnWidth,
                Height = 45,
                Background = Brushes.Transparent,
                Child = closeDot,
                Cursor = new Cursor(StandardCursorType.Hand)
            };
            ToolTip.SetTip(closeHitTarget, "Close tab");
            closeHitTarget.PointerEntered += (_, _) => closeDot.Fill = TabCloseHoverBrush;
            closeHitTarget.PointerExited += (_, _) => closeDot.Fill = TabCloseBrush;
            closeHitTarget.PointerPressed += (_, eventArgs) =>
            {
                if (eventArgs.GetCurrentPoint(this).Properties.IsLeftButtonPressed)
                {
                    eventArgs.Handled = true;
                    CloseEditorTab(tab);
                }
            };
            Grid.SetColumn(closeHitTarget, 2);
            grid.Children.Add(closeHitTarget);

            tabBorder.Child = grid;
            if (tabLayout.ShowTooltip)
            {
                ToolTip.SetTip(tabBorder, tab.Title);
            }
            tabBorder.PointerPressed += (_, eventArgs) =>
            {
                if (!eventArgs.GetCurrentPoint(this).Properties.IsLeftButtonPressed)
                {
                    return;
                }

                eventArgs.Handled = true;
                SelectEditorTab(tab);
                if (eventArgs.ClickCount == 2)
                {
                    tab.IsRenaming = true;
                    RebuildEditorTabs();
                }
            };
            _editorTabsPanel.Children.Add(tabBorder);
        }

        var addTabSlot = new Grid
        {
            Width = tabLayout.AddButtonWidth,
            Height = 45
        };
        var addTab = new Border
        {
            Width = Math.Min(tabLayout.AddButtonWidth, 30 / FixedHorizontalScale),
            Height = 34,
            HorizontalAlignment = Avalonia.Layout.HorizontalAlignment.Center,
            VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center,
            Background = Brushes.Transparent,
            Cursor = new Cursor(tabLayout.CanAdd
                ? StandardCursorType.Hand
                : StandardCursorType.Arrow),
            Opacity = tabLayout.CanAdd ? 1 : 0.35,
            Child = new TextBlock
            {
                Text = "+",
                FontSize = tabLayout.PlusFontSize,
                FontWeight = FontWeight.Light,
                Foreground = ExplorerTextBrush,
                HorizontalAlignment = Avalonia.Layout.HorizontalAlignment.Center,
                VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center
            }
        };
        ToolTip.SetTip(
            addTab,
            tabLayout.CanAdd
                ? "New tab"
                : $"Maximum of {tabLayout.Capacity} tabs at this window size");
        addTab.Tapped += (_, eventArgs) =>
        {
            eventArgs.Handled = true;
            if (tabLayout.CanAdd)
            {
                AddEditorTab();
            }
        };
            addTabSlot.Children.Add(addTab);
            _editorTabsPanel.Children.Add(addTabSlot);
        }
        finally
        {
            _isRebuildingEditorTabs = false;
        }
    }

    private void AddEditorTab()
    {
        if (_editorTabs.Count >= GetTabCapacity(Bounds.Width))
        {
            NotifyTabCapacityReached();
            return;
        }

        var number = 1;
        string title;
        do
        {
            title = $"Script {number++}";
        }
        while (_editorTabs.Any(tab => tab.Title.Equals(title, StringComparison.OrdinalIgnoreCase)));

        var tab = new EditorTabState { Title = title, Extension = ".lua" };
        _editorTabs.Add(tab);
        _activeEditorTab = tab;
        RebuildEditorTabs();
        _ = AnimateEditorTabInAsync(tab.Id);
        PushActiveTabToMonaco();
        ScheduleWorkspaceSave();
    }

    private void OpenEditorTab(string title, string content, string extension)
    {
        if (_editorTabs.Count >= GetTabCapacity(Bounds.Width))
        {
            NotifyTabCapacityReached();
            return;
        }

        var tab = new EditorTabState
        {
            Title = string.IsNullOrWhiteSpace(title) ? "Untitled" : title.Trim(),
            Content = content,
            Extension = string.IsNullOrWhiteSpace(extension) ? ".lua" : extension
        };
        _editorTabs.Add(tab);
        _activeEditorTab = tab;
        RebuildEditorTabs();
        _ = AnimateEditorTabInAsync(tab.Id);
        PushActiveTabToMonaco();
        ScheduleWorkspaceSave();
    }

    private void SelectEditorTab(EditorTabState tab)
    {
        if (_activeEditorTab.Id == tab.Id)
        {
            return;
        }

        _activeEditorTab = tab;
        RebuildEditorTabs();
        PushActiveTabToMonaco();
        ScheduleWorkspaceSave();
    }

    private async void CloseEditorTab(EditorTabState tab)
    {
        if (!_editorTabs.Contains(tab) || !_closingEditorTabIds.Add(tab.Id))
        {
            return;
        }

        var cancellation = BeginEditorTabMotion(tab.Id);
        try
        {
            var visual = FindEditorTabVisual(tab.Id);
            if (visual is not null && SystemAnimationsEnabled())
            {
                var translation = visual.RenderTransform as TranslateTransform
                    ?? new TranslateTransform();
                visual.RenderTransform = translation;
                var startY = translation.Y;
                var startOpacity = visual.Opacity;

                await AnimateAsync(
                    TimeSpan.FromMilliseconds(165),
                    progress =>
                    {
                        translation.Y = Lerp(startY, 46, progress);
                        visual.Opacity = Lerp(startOpacity, 0, progress);
                    },
                    CubicEaseIn,
                    cancellation.Token);
            }

            cancellation.Token.ThrowIfCancellationRequested();
            var index = _editorTabs.IndexOf(tab);
            if (index < 0)
            {
                return;
            }

            var wasActive = tab.Id == _activeEditorTab.Id;
            _editorTabs.RemoveAt(index);
            EditorTabState? replacement = null;

            if (_editorTabs.Count == 0)
            {
                replacement = new EditorTabState { Title = "Script 1", Extension = ".lua" };
                _editorTabs.Add(replacement);
                _activeEditorTab = replacement;
            }
            else if (wasActive)
            {
                _activeEditorTab = _editorTabs[Math.Clamp(index, 0, _editorTabs.Count - 1)];
            }

            RebuildEditorTabs();
            if (replacement is not null)
            {
                _ = AnimateEditorTabInAsync(replacement.Id);
            }

            PushActiveTabToMonaco();
            ScheduleWorkspaceSave();
        }
        catch (OperationCanceledException)
        {
            // Window shutdown or a replacement motion cancelled this tab animation.
        }
        finally
        {
            EndEditorTabMotion(tab.Id, cancellation);
            _closingEditorTabIds.Remove(tab.Id);
        }
    }

    private async Task AnimateEditorTabInAsync(Guid tabId)
    {
        var visual = FindEditorTabVisual(tabId);
        if (visual is null)
        {
            return;
        }

        var translation = visual.RenderTransform as TranslateTransform
            ?? new TranslateTransform();
        visual.RenderTransform = translation;

        if (!SystemAnimationsEnabled())
        {
            translation.Y = 0;
            visual.Opacity = 1;
            return;
        }

        var cancellation = BeginEditorTabMotion(tabId);
        translation.Y = 44;
        visual.Opacity = 0;

        try
        {
            await AnimateAsync(
                TimeSpan.FromMilliseconds(220),
                progress =>
                {
                    translation.Y = Lerp(44, 0, progress);
                    visual.Opacity = progress;
                },
                CubicEaseOut,
                cancellation.Token);

            translation.Y = 0;
            visual.Opacity = 1;
        }
        catch (OperationCanceledException)
        {
            // Closing or rebuilding the same tab replaced its entrance motion.
        }
        finally
        {
            EndEditorTabMotion(tabId, cancellation);
        }
    }

    private Border? FindEditorTabVisual(Guid tabId) =>
        _editorTabsPanel.Children
            .OfType<Border>()
            .FirstOrDefault(control => control.Tag is Guid id && id == tabId);

    private CancellationTokenSource BeginEditorTabMotion(Guid tabId)
    {
        if (_editorTabMotionCancellations.Remove(tabId, out var existing))
        {
            existing.Cancel();
            existing.Dispose();
        }

        var cancellation = new CancellationTokenSource();
        _editorTabMotionCancellations[tabId] = cancellation;
        return cancellation;
    }

    private void EndEditorTabMotion(Guid tabId, CancellationTokenSource cancellation)
    {
        if (_editorTabMotionCancellations.TryGetValue(tabId, out var current) &&
            ReferenceEquals(current, cancellation))
        {
            _editorTabMotionCancellations.Remove(tabId);
            cancellation.Dispose();
        }
    }

    private void CancelEditorTabMotions()
    {
        foreach (var cancellation in _editorTabMotionCancellations.Values)
        {
            cancellation.Cancel();
            cancellation.Dispose();
        }

        _editorTabMotionCancellations.Clear();
        _closingEditorTabIds.Clear();
    }

    private void CommitTabRename(EditorTabState tab, string? requestedTitle)
    {
        var title = (requestedTitle ?? string.Empty).Trim();
        if (title.Length > 0)
        {
            tab.Title = title[..Math.Min(80, title.Length)];
        }

        tab.IsRenaming = false;
        RebuildEditorTabs();
        ScheduleWorkspaceSave();
    }

    private void RebuildExplorerTree()
    {
        _explorerTree.Children.Clear();
        AddExplorerSection(
            "Scripts",
            _scriptsExpanded,
            () => _scriptsExpanded = !_scriptsExpanded,
            _editorWorkspace.ListScriptFiles(_editorWorkspace.ScriptsDirectory));
        AddExplorerSection(
            "AutoExecute",
            _autoExecuteExpanded,
            () => _autoExecuteExpanded = !_autoExecuteExpanded,
            _editorWorkspace.ListScriptFiles(_editorWorkspace.AutoExecuteDirectory));
        AddExplorerSection(
            "Github Gists",
            _githubGistsExpanded,
            () => _githubGistsExpanded = !_githubGistsExpanded,
            _editorWorkspace.ListGists(),
            showAddButton: true);
    }

    private void AddExplorerSection(
        string title,
        bool expanded,
        Action toggle,
        IReadOnlyList<WorkspaceFileEntry> files,
        bool showAddButton = false)
    {
        var header = new Border
        {
            Height = 33,
            Background = Brushes.Transparent,
            Cursor = new Cursor(StandardCursorType.Hand)
        };
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition(new GridLength(22)));
        grid.ColumnDefinitions.Add(new ColumnDefinition(new GridLength(1, GridUnitType.Star)));
        grid.ColumnDefinitions.Add(new ColumnDefinition(new GridLength(30)));

        var chevron = new ShapePath
        {
            Width = 5,
            Height = 8,
            Data = Geometry.Parse("M1 1 L4 4 L1 7"),
            Stretch = Stretch.Fill,
            Stroke = ExplorerTextBrush,
            StrokeThickness = 1.2,
            StrokeLineCap = PenLineCap.Round,
            StrokeJoin = PenLineJoin.Round,
            HorizontalAlignment = Avalonia.Layout.HorizontalAlignment.Center,
            VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center,
            RenderTransformOrigin = RelativePoint.Center,
            RenderTransform = expanded ? new RotateTransform(90) : null
        };
        Grid.SetColumn(chevron, 0);
        grid.Children.Add(chevron);

        var label = new TextBlock
        {
            Text = title,
            FontSize = 12,
            Foreground = ExplorerTextBrush,
            VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center
        };
        Grid.SetColumn(label, 1);
        grid.Children.Add(label);

        if (showAddButton)
        {
            var add = new Border
            {
                Width = 27,
                Height = 27,
                Background = Brushes.Transparent,
                CornerRadius = new CornerRadius(6),
                Cursor = new Cursor(StandardCursorType.Hand),
                Child = new TextBlock
                {
                    Text = "+",
                    FontSize = 14,
                    Foreground = FindThemeBrush("OrbitTextBrush", "#FFFFFF"),
                    HorizontalAlignment = Avalonia.Layout.HorizontalAlignment.Center,
                    VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center
                }
            };
            ToolTip.SetTip(add, "Add raw GitHub link");
            add.PointerEntered += (_, _) => add.Background = ExplorerHoverBrush;
            add.PointerExited += (_, _) => add.Background = Brushes.Transparent;
            add.PointerPressed += (_, eventArgs) =>
            {
                if (eventArgs.GetCurrentPoint(this).Properties.IsLeftButtonPressed)
                {
                    eventArgs.Handled = true;
                    ShowGistDialog();
                }
            };
            Grid.SetColumn(add, 2);
            grid.Children.Add(add);
        }

        header.Child = grid;
        header.PointerEntered += (_, _) => header.Background = ExplorerHoverBrush;
        header.PointerExited += (_, _) => header.Background = Brushes.Transparent;
        header.PointerPressed += (_, eventArgs) =>
        {
            if (eventArgs.GetCurrentPoint(this).Properties.IsLeftButtonPressed)
            {
                toggle();
                RebuildExplorerTree();
            }
        };
        _explorerTree.Children.Add(header);

        if (!expanded)
        {
            return;
        }

        foreach (var file in files)
        {
            var row = new Border
            {
                Height = 31,
                Margin = new Thickness(22, 0, 0, 0),
                Background = Brushes.Transparent,
                CornerRadius = new CornerRadius(5),
                Cursor = new Cursor(StandardCursorType.Hand)
            };
            var rowGrid = new Grid { Margin = new Thickness(7, 0, 5, 0) };
            rowGrid.ColumnDefinitions.Add(new ColumnDefinition(new GridLength(20)));
            rowGrid.ColumnDefinitions.Add(new ColumnDefinition(new GridLength(1, GridUnitType.Star)));

            var fileGlyph = new ShapePath
            {
                Width = 11,
                Height = 13,
                Stretch = Stretch.Fill,
                Fill = ExplorerTextBrush,
                Data = Geometry.Parse("M1 0H7L11 4V13H1Z M7 0V4H11"),
                VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center
            };
            Grid.SetColumn(fileGlyph, 0);
            rowGrid.Children.Add(fileGlyph);

            var fileLabel = new TextBlock
            {
                Text = file.DisplayName,
                FontSize = 12,
                Foreground = ExplorerTextBrush,
                VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center,
                TextTrimming = TextTrimming.CharacterEllipsis
            };
            Grid.SetColumn(fileLabel, 1);
            rowGrid.Children.Add(fileLabel);

            row.Child = rowGrid;
            ToolTip.SetTip(row, file.DisplayName);
            row.PointerEntered += (_, _) => row.Background = ExplorerHoverBrush;
            row.PointerExited += (_, _) => row.Background = Brushes.Transparent;
            row.PointerPressed += async (_, eventArgs) =>
            {
                if (eventArgs.GetCurrentPoint(this).Properties.IsLeftButtonPressed)
                {
                    eventArgs.Handled = true;
                    await OpenWorkspaceEntryAsync(file);
                }
            };
            _explorerTree.Children.Add(row);
        }
    }

    private async Task OpenWorkspaceEntryAsync(WorkspaceFileEntry entry)
    {
        try
        {
            if (entry.IsGist)
            {
                var url = (await File.ReadAllTextAsync(entry.FullPath)).Trim();
                _cursorPositionText.Text = "Fetching...";
                var content = await _editorWorkspace.FetchGistAsync(url, CancellationToken.None);
                OpenEditorTab(entry.DisplayName, content, ".lua");
            }
            else
            {
                var content = await File.ReadAllTextAsync(entry.FullPath);
                OpenEditorTab(entry.DisplayName, content, Path.GetExtension(entry.FullPath));
            }
        }
        catch (Exception exception) when (exception is IOException or HttpRequestException or InvalidOperationException)
        {
            ShowGistDialog(
                entry.IsGist ? (await SafeReadAllTextAsync(entry.FullPath)).Trim() : string.Empty,
                entry.IsGist ? $"Couldn’t fetch this script. {exception.Message}" : exception.Message);
        }
    }

    private static async Task<string> SafeReadAllTextAsync(string path)
    {
        try
        {
            return await File.ReadAllTextAsync(path);
        }
        catch (IOException)
        {
            return string.Empty;
        }
    }

    private async void OpenScript_Click(object? sender, RoutedEventArgs e)
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
        OpenEditorTab(
            Path.GetFileNameWithoutExtension(file.Name),
            content,
            Path.GetExtension(file.Name));
    }

    private async void SaveScript_Click(object? sender, RoutedEventArgs e)
    {
        var scriptsFolder = await StorageProvider.TryGetFolderFromPathAsync(
            new Uri(_editorWorkspace.ScriptsDirectory));
        var extension = string.IsNullOrWhiteSpace(_activeEditorTab.Extension)
            ? ".lua"
            : _activeEditorTab.Extension;
        var file = await StorageProvider.SaveFilePickerAsync(new FilePickerSaveOptions
        {
            Title = "Save script",
            SuggestedStartLocation = scriptsFolder,
            SuggestedFileName = _activeEditorTab.Title + extension,
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

            await using var writer = new StreamWriter(stream, new UTF8Encoding(false), 8192, leaveOpen: false);
            await writer.WriteAsync(_activeEditorTab.Content);
        }

        _activeEditorTab.Title = Path.GetFileNameWithoutExtension(file.Name);
        _activeEditorTab.Extension = Path.GetExtension(file.Name);
        RebuildEditorTabs();
        RebuildExplorerTree();
        ScheduleWorkspaceSave();
    }

    private bool _clearAllTabsRequested;

    private void ClearEditor_PointerPressed(object? sender, PointerPressedEventArgs e)
    {
        _clearAllTabsRequested = e.KeyModifiers.HasFlag(KeyModifiers.Shift);
    }

    private void ClearEditor_Click(object? sender, RoutedEventArgs e)
    {
        if (_clearAllTabsRequested)
        {
            foreach (var tab in _editorTabs)
            {
                tab.Content = string.Empty;
            }
        }
        else
        {
            _activeEditorTab.Content = string.Empty;
        }

        PushActiveTabToMonaco();
        ScheduleWorkspaceSave();
        _clearAllTabsRequested = false;
    }

    private void ShowGistDialog(string initialUrl = "", string status = "")
    {
        if (_resizeTabsWarningOverlay.IsVisible)
        {
            return;
        }

        _gistDialogCancellation?.Cancel();
        _gistDialogCancellation?.Dispose();
        _gistDialogCancellation = new CancellationTokenSource();
        _gistUrlTextBox.Text = initialUrl;
        _gistDialogStatusText.Text = status;
        _gistDialogAddButton.IsEnabled = true;
        _gistDialogAddButton.Content = "Import";
        _gistDialogOverlay.IsVisible = true;
        UpdateMonacoVisibility();
        _ = AnimateGistDialogInAsync();
        Dispatcher.UIThread.Post(() =>
        {
            _gistUrlTextBox.Focus();
            _gistUrlTextBox.CaretIndex = _gistUrlTextBox.Text?.Length ?? 0;
        });
    }

    private async Task AnimateGistDialogInAsync()
    {
        _gistDialogAnimationCancellation?.Cancel();
        _gistDialogAnimationCancellation?.Dispose();
        _gistDialogAnimationCancellation = new CancellationTokenSource();
        var cancellationToken = _gistDialogAnimationCancellation.Token;

        if (!SystemAnimationsEnabled())
        {
            _gistDialogBackdrop.Opacity = 1;
            _gistDialogPopup.Opacity = 1;
            _gistDialogScale.ScaleX = 1;
            _gistDialogScale.ScaleY = 1;
            _gistDialogTranslation.Y = 0;
            return;
        }

        _gistDialogBackdrop.Opacity = 0;
        _gistDialogPopup.Opacity = 0;
        _gistDialogScale.ScaleX = 0.94;
        _gistDialogScale.ScaleY = 0.94;
        _gistDialogTranslation.Y = 9;

        try
        {
            await AnimateAsync(
                TimeSpan.FromMilliseconds(270),
                progress =>
                {
                    _gistDialogBackdrop.Opacity = progress;
                    _gistDialogPopup.Opacity = progress;
                    _gistDialogScale.ScaleX = Lerp(0.94, 1, progress);
                    _gistDialogScale.ScaleY = Lerp(0.94, 1, progress);
                    _gistDialogTranslation.Y = Lerp(9, 0, progress);
                },
                CubicEaseOut,
                cancellationToken);
        }
        catch (OperationCanceledException)
        {
            // A close transition took over.
        }
    }

    private async void GistDialogAdd_Click(object? sender, RoutedEventArgs e)
    {
        if (_editorTabs.Count >= GetTabCapacity(Bounds.Width))
        {
            _gistDialogStatusText.Foreground = BrushFrom("#C9A968");
            _gistDialogStatusText.Text = "No tab space at this size. Enlarge the window first.";
            return;
        }

        var rawUrl = _gistUrlTextBox.Text ?? string.Empty;
        try
        {
            var normalizedUrl = EditorWorkspaceService.NormalizeRawGithubUrl(rawUrl);
            _gistDialogStatusText.Foreground = ExplorerTextBrush;
            _gistDialogStatusText.Text = "Fetching the latest script…";
            _gistDialogAddButton.IsEnabled = false;
            _gistDialogAddButton.Content = "Importing";

            var cancellationToken = _gistDialogCancellation?.Token ?? CancellationToken.None;
            var content = await _editorWorkspace.FetchGistAsync(normalizedUrl, cancellationToken);
            var title = _editorWorkspace.StoreGistUrl(normalizedUrl);
            _githubGistsExpanded = true;
            RebuildExplorerTree();
            OpenEditorTab(title, content, ".lua");
            await HideGistDialogAsync();
        }
        catch (OperationCanceledException)
        {
            // Closing the dialog cancels the network request.
        }
        catch (Exception exception) when (exception is HttpRequestException or InvalidOperationException or IOException)
        {
            _gistDialogStatusText.Foreground = BrushFrom("#C77A7A");
            _gistDialogStatusText.Text = exception.Message;
            _gistDialogAddButton.IsEnabled = true;
            _gistDialogAddButton.Content = "Import";
        }
    }

    private async void GistDialogCancel_Click(object? sender, RoutedEventArgs e) =>
        await HideGistDialogAsync();

    private async void GistUrlTextBox_KeyDown(object? sender, KeyEventArgs e)
    {
        if (e.Key == Key.Enter && _gistDialogAddButton.IsEnabled)
        {
            GistDialogAdd_Click(sender, new RoutedEventArgs());
            e.Handled = true;
        }
        else if (e.Key == Key.Escape)
        {
            await HideGistDialogAsync();
            e.Handled = true;
        }
    }

    private async Task HideGistDialogAsync()
    {
        if (!_gistDialogOverlay.IsVisible)
        {
            return;
        }

        _gistDialogCancellation?.Cancel();
        _gistDialogCancellation?.Dispose();
        _gistDialogCancellation = null;
        _gistDialogAnimationCancellation?.Cancel();
        _gistDialogAnimationCancellation?.Dispose();
        _gistDialogAnimationCancellation = new CancellationTokenSource();
        var cancellationToken = _gistDialogAnimationCancellation.Token;

        try
        {
            if (SystemAnimationsEnabled())
            {
                var backdropOpacity = _gistDialogBackdrop.Opacity;
                var popupOpacity = _gistDialogPopup.Opacity;
                var scale = _gistDialogScale.ScaleX;
                var translation = _gistDialogTranslation.Y;
                await AnimateAsync(
                    TimeSpan.FromMilliseconds(210),
                    progress =>
                    {
                        _gistDialogBackdrop.Opacity = Lerp(backdropOpacity, 0, progress);
                        _gistDialogPopup.Opacity = Lerp(popupOpacity, 0, progress);
                        _gistDialogScale.ScaleX = Lerp(scale, 0.96, progress);
                        _gistDialogScale.ScaleY = Lerp(scale, 0.96, progress);
                        _gistDialogTranslation.Y = Lerp(translation, 6, progress);
                    },
                    CubicEaseIn,
                    cancellationToken);
            }

            _gistDialogOverlay.IsVisible = false;
            UpdateMonacoVisibility();
        }
        catch (OperationCanceledException)
        {
            // A newer dialog transition replaced this one.
        }
    }

    private void ScheduleWorkspaceSave()
    {
        _workspaceSaveTimer.Stop();
        _workspaceSaveTimer.Start();
    }

    private void PersistEditorWorkspace()
    {
        if (_activeEditorTab is not null)
        {
            _editorWorkspace.SaveState(_editorTabs, _activeEditorTab.Id);
        }
    }

    private static IBrush BrushFrom(string color) => new SolidColorBrush(ThemeColor(color));
}
