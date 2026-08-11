using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Primitives;
using Avalonia.Input;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Media.Imaging;
using Avalonia.Platform;
using Avalonia.Threading;

namespace OrbitAvalonia;

internal enum SynapseXHubPage
{
    RobloxScripts,
    SynapseHub,
    Rscripts,
    HaxHell,
    ScriptBlox
}

internal sealed class SynapseXScriptHubWindow : Window
{
    private readonly ScriptHubService _service = new();
    private readonly Dictionary<SynapseXHubPage, Button> _navButtons = [];
    private readonly List<(Button Button, ScriptHubCardModel Card)> _scriptRows = [];
    private readonly List<Bitmap> _ownedImages = [];
    private readonly StackPanel _listStack;
    private readonly TextBox _searchBox;
    private readonly Image _previewImage;
    private readonly TextBlock _descriptionText;
    private readonly TextBlock _sourceText;
    private readonly TextBlock _statusText;
    private readonly Button _runButton;
    private readonly Bitmap _fallbackImage;
    private CancellationTokenSource? _loadCancellation;
    private IReadOnlyList<ScriptHubCardModel> _currentCards = [];
    private ScriptHubCardModel? _selected;
    private SynapseXHubPage _currentPage = SynapseXHubPage.RobloxScripts;
    private bool _bridgeConnected;
    private bool _closed;

    internal SynapseXScriptHubWindow(SynapseFrontendWindow owner)
    {
        Width = 612;
        Height = 384;
        MinWidth = 612;
        MinHeight = 384;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        WindowDecorations = WindowDecorations.None;
        ExtendClientAreaToDecorationsHint = true;
        Background = SynapseXCompanionUi.Brush(SynapseXCompanionUi.WindowBackground);
        Topmost = OrbitPreferences.TopMostEnabled;
        Title = "Synapse X - Script Hub";
        FontFamily = new FontFamily("Segoe UI");
        ApplyResizablePreference(OrbitPreferences.ResizableEnabled);

        _fallbackImage = LoadBitmap("avares://Orion/Assets/SynapseX/script-preview.png");
        _ownedImages.Add(_fallbackImage);

        var nav = new StackPanel { Width = 112, Spacing = 4 };
        AddNavigationButton(nav, SynapseXHubPage.RobloxScripts, "robloxscripts.com");
        AddNavigationButton(nav, SynapseXHubPage.SynapseHub, "Synapse Hub");
        AddNavigationButton(nav, SynapseXHubPage.Rscripts, "rscripts.net");
        AddNavigationButton(nav, SynapseXHubPage.HaxHell, "HaxHell");
        AddNavigationButton(nav, SynapseXHubPage.ScriptBlox, "ScriptBlox", warning: true);

        _searchBox = new TextBox
        {
            Height = 26,
            PlaceholderText = "Search robloxscripts.com…",
            Background = SynapseXCompanionUi.Brush(SynapseXCompanionUi.ButtonBackground),
            BorderBrush = SynapseXCompanionUi.Brush(SynapseXCompanionUi.Border),
            BorderThickness = new Thickness(1),
            Foreground = SynapseXCompanionUi.Brush("#C0C0C0"),
            CaretBrush = Brushes.White,
            FontSize = 11,
            Padding = new Thickness(6, 2),
            VerticalContentAlignment = VerticalAlignment.Center,
            CornerRadius = new CornerRadius(0)
        };
        _searchBox.KeyDown += SearchBox_KeyDown;

        _listStack = new StackPanel { Spacing = 1 };
        var listScroll = new ScrollViewer
        {
            Content = _listStack,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled
        };
        var listLayout = new Grid { RowDefinitions = new RowDefinitions("26,4,*") };
        listLayout.Children.Add(_searchBox);
        Grid.SetRow(listScroll, 2);
        listLayout.Children.Add(listScroll);
        var listPanel = new Border
        {
            Width = 171,
            Background = SynapseXCompanionUi.Brush(SynapseXCompanionUi.PanelBackground),
            BorderBrush = SynapseXCompanionUi.Brush("#212120"),
            BorderThickness = new Thickness(1),
            Padding = new Thickness(6),
            Child = listLayout
        };

        _previewImage = new Image
        {
            Source = _fallbackImage,
            Stretch = Stretch.UniformToFill
        };
        var preview = new Border
        {
            Height = 162,
            Background = SynapseXCompanionUi.Brush("#252525"),
            BorderBrush = SynapseXCompanionUi.Brush("#212120"),
            BorderThickness = new Thickness(1),
            ClipToBounds = true,
            Child = _previewImage
        };

        _descriptionText = new TextBlock
        {
            Text = "Pick a script on the left to preview it.",
            FontSize = 13,
            FontWeight = FontWeight.Normal,
            Foreground = SynapseXCompanionUi.Brush("#C0C0C0"),
            TextWrapping = TextWrapping.Wrap,
            LineHeight = 17
        };
        _sourceText = new TextBlock
        {
            Text = "Source: robloxscripts.com",
            FontSize = 10,
            Foreground = SynapseXCompanionUi.Brush("#7A7A7A"),
            Margin = new Thickness(0, 2, 0, 0)
        };
        _statusText = new TextBlock
        {
            FontSize = 11,
            Foreground = SynapseXCompanionUi.Brush("#CC6E6E"),
            Margin = new Thickness(0, 3, 0, 0),
            IsVisible = false,
            TextWrapping = TextWrapping.Wrap
        };
        var descriptionLayout = new Grid { RowDefinitions = new RowDefinitions("*,Auto,Auto") };
        var descriptionScroll = new ScrollViewer
        {
            Content = _descriptionText,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled
        };
        descriptionLayout.Children.Add(descriptionScroll);
        Grid.SetRow(_sourceText, 1);
        descriptionLayout.Children.Add(_sourceText);
        Grid.SetRow(_statusText, 2);
        descriptionLayout.Children.Add(_statusText);
        var descriptionPanel = new Border
        {
            Background = SynapseXCompanionUi.Brush(SynapseXCompanionUi.PanelBackground),
            BorderBrush = SynapseXCompanionUi.Brush("#212120"),
            BorderThickness = new Thickness(1),
            Padding = new Thickness(8),
            Child = descriptionLayout
        };

        _runButton = SynapseXCompanionUi.CreateSurfaceButton("Run Script", 33, fontSize: 13);
        _runButton.Click += RunButton_Click;
        var closeButton = SynapseXCompanionUi.CreateSurfaceButton("Close", 33, fontSize: 13);
        closeButton.Click += (_, _) => Close();
        var actions = new Grid { Height = 33, ColumnDefinitions = new ColumnDefinitions("*,8,*") };
        actions.Children.Add(_runButton);
        Grid.SetColumn(closeButton, 2);
        actions.Children.Add(closeButton);

        var detail = new Grid
        {
            RowDefinitions = new RowDefinitions("162,8,*,8,33")
        };
        detail.Children.Add(preview);
        Grid.SetRow(descriptionPanel, 2);
        detail.Children.Add(descriptionPanel);
        Grid.SetRow(actions, 4);
        detail.Children.Add(actions);

        var bodyLayout = new Grid
        {
            ColumnDefinitions = new ColumnDefinitions("112,8,171,8,*")
        };
        bodyLayout.Children.Add(nav);
        Grid.SetColumn(listPanel, 2);
        bodyLayout.Children.Add(listPanel);
        Grid.SetColumn(detail, 4);
        bodyLayout.Children.Add(detail);
        var body = new Border
        {
            Padding = new Thickness(8),
            Background = SynapseXCompanionUi.Brush(SynapseXCompanionUi.WindowBackground),
            Child = bodyLayout
        };

        Content = SynapseXCompanionUi.BuildChrome(
            this,
            "Synapse X - Script Hub",
            body,
            showMinimize: true,
            showClose: false);

        UnifiedBridgeServer.Shared.ConnectionChanged += BridgeConnectionChanged;
        ApplyBridgeState(UnifiedBridgeServer.Shared.IsConnected);
        RefreshNavigation();
        Opened += (_, _) => _ = SelectPageAsync(SynapseXHubPage.RobloxScripts, forceReload: true);
        Closed += OnClosed;
    }

    internal void ApplyResizablePreference(bool enabled)
    {
        CanResize = enabled;
        MaxWidth = enabled ? double.PositiveInfinity : 612;
        MaxHeight = enabled ? double.PositiveInfinity : 384;
    }

    private void AddNavigationButton(
        Panel panel,
        SynapseXHubPage page,
        string label,
        bool warning = false)
    {
        Control content;
        if (warning)
        {
            var warningIcon = new Grid { Width = 12, Height = 12 };
            warningIcon.Children.Add(new Avalonia.Controls.Shapes.Path
            {
                Data = Geometry.Parse("M6 0.8 L11.5 11 H0.5 Z"),
                Fill = SynapseXCompanionUi.Brush("#EAB308")
            });
            warningIcon.Children.Add(new TextBlock
            {
                Text = "!",
                Foreground = SynapseXCompanionUi.Brush("#2A2500"),
                FontSize = 8,
                FontWeight = FontWeight.Bold,
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center,
                Margin = new Thickness(0, 2, 0, 0)
            });
            var row = new StackPanel
            {
                Orientation = Orientation.Horizontal,
                Spacing = 4,
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center
            };
            row.Children.Add(new TextBlock { Text = label, FontSize = 11 });
            row.Children.Add(warningIcon);
            content = row;
        }
        else
        {
            content = new TextBlock
            {
                Text = label,
                FontSize = label.Length > 13 ? 10.25 : 12,
                TextTrimming = TextTrimming.CharacterEllipsis,
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center
            };
        }

        var button = SynapseXCompanionUi.CreateSurfaceButton(content, 33, 112, 12);
        button.Click += (_, _) => _ = SelectPageAsync(page);
        button.PointerEntered += (_, _) => button.Background = SynapseXCompanionUi.Brush("#505050");
        button.PointerExited += (_, _) => RefreshNavigation();
        _navButtons[page] = button;
        panel.Children.Add(button);
    }

    private async Task SelectPageAsync(SynapseXHubPage page, bool forceReload = false)
    {
        if (_closed || (!forceReload && _currentPage == page && _currentCards.Count > 0))
        {
            return;
        }

        _currentPage = page;
        _searchBox.IsVisible = page != SynapseXHubPage.SynapseHub;
        _searchBox.Text = string.Empty;
        _searchBox.PlaceholderText = $"Search {DisplayName(page)}…";
        _sourceText.Text = $"Source: {DisplayName(page)}";
        ClearSelection();
        RefreshNavigation();

        if (page == SynapseXHubPage.SynapseHub)
        {
            _loadCancellation?.Cancel();
            _currentCards = BuildSynapseHubScripts();
            BuildScriptRows(_currentCards);
            SelectCard(_currentCards[0]);
            return;
        }

        await LoadProviderAsync(string.Empty);
    }

    private async Task LoadProviderAsync(string query)
    {
        if (_currentPage == SynapseXHubPage.SynapseHub || _closed)
        {
            return;
        }

        _loadCancellation?.Cancel();
        _loadCancellation?.Dispose();
        _loadCancellation = new CancellationTokenSource();
        var token = _loadCancellation.Token;
        var requestedPage = _currentPage;
        ShowListMessage("Loading…", "#A3A3A3");
        _descriptionText.Text = $"Loading {DisplayName(requestedPage)} catalogue…";
        _statusText.IsVisible = false;

        try
        {
            var result = await _service.FetchAsync(ToProvider(requestedPage), query, 1, token);
            if (token.IsCancellationRequested || requestedPage != _currentPage || _closed)
            {
                return;
            }

            _currentCards = result.Cards;
            if (_currentCards.Count == 0)
            {
                ShowListMessage(string.IsNullOrWhiteSpace(query) ? "Empty page." : "No matches.", "#6E6E6E");
                _descriptionText.Text = "Pick a script on the left to preview it.";
                return;
            }

            BuildScriptRows(_currentCards);
            _descriptionText.Text = "Pick a script on the left to preview it.";
            await _service.LoadThumbnailsAsync(_currentCards, token);
            if (!token.IsCancellationRequested && requestedPage == _currentPage && _selected is not null)
            {
                _previewImage.Source = _selected.Thumbnail ?? _fallbackImage;
            }
        }
        catch (OperationCanceledException)
        {
            // A new provider or search superseded this request.
        }
        catch (Exception exception) when (
            exception is HttpRequestException or IOException or InvalidDataException)
        {
            if (token.IsCancellationRequested || requestedPage != _currentPage || _closed)
            {
                return;
            }
            _currentCards = [];
            ShowListMessage(exception.Message, "#CC6E6E");
            _descriptionText.Text = exception.Message;
        }
    }

    private void SearchBox_KeyDown(object? sender, KeyEventArgs args)
    {
        if (args.Key != Key.Enter || _currentPage == SynapseXHubPage.SynapseHub)
        {
            return;
        }

        args.Handled = true;
        _ = LoadProviderAsync(_searchBox.Text?.Trim() ?? string.Empty);
    }

    private void BuildScriptRows(IReadOnlyList<ScriptHubCardModel> cards)
    {
        _listStack.Children.Clear();
        _scriptRows.Clear();
        foreach (var card in cards)
        {
            var text = new TextBlock
            {
                Text = card.Title,
                FontSize = 11,
                Foreground = SynapseXCompanionUi.Brush("#C0C0C0"),
                TextWrapping = TextWrapping.Wrap,
                TextAlignment = TextAlignment.Left,
                LineHeight = 14,
                MaxLines = 2
            };
            var button = new Button
            {
                Content = text,
                MinHeight = 28,
                HorizontalAlignment = HorizontalAlignment.Stretch,
                HorizontalContentAlignment = HorizontalAlignment.Left,
                Background = Brushes.Transparent,
                BorderThickness = new Thickness(0),
                Padding = new Thickness(4, 4),
                CornerRadius = new CornerRadius(0)
            };
            ToolTip.SetTip(button, card.Title);
            button.Click += (_, _) => SelectCard(card);
            button.PointerEntered += (_, _) =>
            {
                if (!ReferenceEquals(_selected, card))
                {
                    button.Background = SynapseXCompanionUi.Brush(SynapseXCompanionUi.WindowBackground);
                }
            };
            button.PointerExited += (_, _) => RefreshSelectedRowVisuals();
            _scriptRows.Add((button, card));
            _listStack.Children.Add(button);
        }
    }

    private void SelectCard(ScriptHubCardModel card)
    {
        _selected = card;
        _previewImage.Source = card.Thumbnail ?? _fallbackImage;
        _descriptionText.Text = string.IsNullOrWhiteSpace(card.Description)
            ? card.Title
            : card.Description;
        _sourceText.Text = $"Source: {DisplayName(_currentPage)}";
        _statusText.IsVisible = false;
        RefreshSelectedRowVisuals();
        UpdateRunButton();
    }

    private void ClearSelection()
    {
        _selected = null;
        _currentCards = [];
        _previewImage.Source = _fallbackImage;
        _descriptionText.Text = "Pick a script on the left to preview it.";
        _statusText.IsVisible = false;
        _scriptRows.Clear();
        UpdateRunButton();
    }

    private void RefreshSelectedRowVisuals()
    {
        foreach (var (button, card) in _scriptRows)
        {
            var selected = ReferenceEquals(card, _selected);
            button.Background = selected
                ? SynapseXCompanionUi.Brush(SynapseXCompanionUi.ActiveBackground)
                : Brushes.Transparent;
            if (button.Content is TextBlock text)
            {
                text.Foreground = SynapseXCompanionUi.Brush(selected ? "#E8E8E8" : "#C0C0C0");
            }
        }
    }

    private void RefreshNavigation()
    {
        foreach (var (page, button) in _navButtons)
        {
            var active = page == _currentPage;
            button.Background = SynapseXCompanionUi.Brush(
                active ? SynapseXCompanionUi.ActiveBackground : SynapseXCompanionUi.PanelBackground);
            button.BorderBrush = SynapseXCompanionUi.Brush(
                active ? SynapseXCompanionUi.ActiveBorder : SynapseXCompanionUi.Border);
        }
    }

    private void ShowListMessage(string message, string color)
    {
        _listStack.Children.Clear();
        _scriptRows.Clear();
        _listStack.Children.Add(new TextBlock
        {
            Text = message,
            Foreground = SynapseXCompanionUi.Brush(color),
            FontSize = 10,
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(2, 8),
            HorizontalAlignment = HorizontalAlignment.Center
        });
    }

    private void RunButton_Click(object? sender, Avalonia.Interactivity.RoutedEventArgs args)
    {
        if (!_bridgeConnected || _selected is null)
        {
            return;
        }

        if (string.IsNullOrWhiteSpace(_selected.ScriptBody))
        {
            SetStatus("Script source is unavailable.", error: true);
            return;
        }

        UnifiedBridgeServer.Shared.EnqueueExecute(_selected.ScriptBody);
        SetStatus($"Sent: {_selected.Title}", error: false);
    }

    private void BridgeConnectionChanged(bool connected) =>
        Dispatcher.UIThread.Post(() => ApplyBridgeState(connected));

    private void ApplyBridgeState(bool connected)
    {
        _bridgeConnected = connected;
        UpdateRunButton();
    }

    private void UpdateRunButton()
    {
        _runButton.IsEnabled = _bridgeConnected &&
                               _selected is not null &&
                               !string.IsNullOrWhiteSpace(_selected.ScriptBody);
        _runButton.Opacity = _runButton.IsEnabled ? 1 : 0.5;
    }

    private void SetStatus(string message, bool error)
    {
        _statusText.Text = message;
        _statusText.Foreground = SynapseXCompanionUi.Brush(error ? "#CC6E6E" : "#77A97A");
        _statusText.IsVisible = true;
    }

    private IReadOnlyList<ScriptHubCardModel> BuildSynapseHubScripts()
    {
        var dex = AddOwnedBitmap("avares://Orion/Assets/SynapseX/dex.png");
        var unnamedEsp = AddOwnedBitmap("avares://Orion/Assets/SynapseX/unnamed-esp.png");
        var remoteSpy = AddOwnedBitmap("avares://Orion/Assets/SynapseX/remote-spy.png");
        var scriptDumper = AddOwnedBitmap("avares://Orion/Assets/SynapseX/script-dumper.png");

        return
        [
            CreateSynapseCard(
                "Dark Dex",
                "Universal Explorer",
                "loadstring(game:HttpGet(\"https://raw.githubusercontent.com/Babyhamsta/RBLX_Scripts/main/Universal/BypassedDarkDexV3.lua\", true))()",
                dex),
            CreateSynapseCard(
                "Unnamed ESP",
                "Global ESP Framework",
                "loadstring(game:HttpGet(\"https://raw.githubusercontent.com/ic3w0lf22/Unnamed-ESP/master/UnnamedESP.lua\"))()",
                unnamedEsp),
            CreateSynapseCard(
                "Remote Spy",
                "SimpleSpy V3",
                "loadstring(game:HttpGet(\"https://raw.githubusercontent.com/exxtremestuffs/SimpleSpySource/master/SimpleSpy.lua\"))()",
                remoteSpy),
            CreateSynapseCard(
                "Script Dumper",
                "Decompile & dump all scripts",
                LoadTextAsset("avares://Orion/Assets/SynapseX/script-dumper.lua"),
                scriptDumper)
        ];
    }

    private static ScriptHubCardModel CreateSynapseCard(
        string title,
        string description,
        string script,
        Bitmap image)
    {
        return new ScriptHubCardModel(title, description, string.Empty, script, description)
        {
            Thumbnail = image
        };
    }

    private Bitmap AddOwnedBitmap(string uri)
    {
        var bitmap = LoadBitmap(uri);
        _ownedImages.Add(bitmap);
        return bitmap;
    }

    private static Bitmap LoadBitmap(string uri)
    {
        using var stream = AssetLoader.Open(new Uri(uri));
        return new Bitmap(stream);
    }

    private static string LoadTextAsset(string uri)
    {
        using var stream = AssetLoader.Open(new Uri(uri));
        using var reader = new StreamReader(stream);
        return reader.ReadToEnd();
    }

    private static ScriptHubProvider ToProvider(SynapseXHubPage page) => page switch
    {
        SynapseXHubPage.RobloxScripts => ScriptHubProvider.RobloxScripts,
        SynapseXHubPage.Rscripts => ScriptHubProvider.Rscripts,
        SynapseXHubPage.HaxHell => ScriptHubProvider.HaxHell,
        SynapseXHubPage.ScriptBlox => ScriptHubProvider.ScriptBlox,
        _ => ScriptHubProvider.RobloxScripts
    };

    private static string DisplayName(SynapseXHubPage page) => page switch
    {
        SynapseXHubPage.RobloxScripts => "robloxscripts.com",
        SynapseXHubPage.SynapseHub => "Synapse Hub",
        SynapseXHubPage.Rscripts => "rscripts.net",
        SynapseXHubPage.HaxHell => "haxhell.com",
        SynapseXHubPage.ScriptBlox => "scriptblox.com",
        _ => "scripts"
    };

    private void OnClosed(object? sender, EventArgs args)
    {
        _closed = true;
        _loadCancellation?.Cancel();
        _loadCancellation?.Dispose();
        UnifiedBridgeServer.Shared.ConnectionChanged -= BridgeConnectionChanged;
        _service.Dispose();
        foreach (var image in _ownedImages)
        {
            image.Dispose();
        }
        _ownedImages.Clear();
    }
}
