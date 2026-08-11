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

internal sealed class SynapseOriginalScriptHubWindow : Window
{
    private readonly ScriptHubService _service = new();
    private readonly Dictionary<SynapseXHubPage, Button> _navigationButtons = [];
    private readonly List<(Button Button, ScriptHubCardModel Card)> _scriptRows = [];
    private readonly List<Bitmap> _ownedImages = [];
    private readonly StackPanel _navigation;
    private readonly StackPanel _scriptList;
    private readonly TextBox _searchBox;
    private readonly Image _previewImage;
    private readonly TextBlock _descriptionText;
    private readonly TextBlock _sourceText;
    private readonly TextBlock _statusText;
    private readonly Button _runButton;
    private readonly Bitmap _fallbackImage;
    private CancellationTokenSource? _loadCancellation;
    private IReadOnlyList<ScriptHubCardModel> _currentCards = [];
    private ScriptHubCardModel? _selectedCard;
    private SynapseXHubPage _currentPage = SynapseXHubPage.RobloxScripts;
    private bool _bridgeConnected;
    private bool _closed;

    internal SynapseOriginalScriptHubWindow(SynapseFrontendWindow owner)
    {
        Width = 612;
        Height = 384;
        MinWidth = 612;
        MinHeight = 384;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        WindowDecorations = WindowDecorations.None;
        ExtendClientAreaToDecorationsHint = true;
        Background = SynapseOriginalCompanionUi.Brush(SynapseOriginalCompanionUi.WindowBackground);
        Topmost = OrbitPreferences.TopMostEnabled;
        Title = "Script Hub";
        FontFamily = new FontFamily("avares://Avalonia.Fonts.Inter/Assets#Inter");
        ApplyResizablePreference(OrbitPreferences.ResizableEnabled);

        _fallbackImage = LoadBitmap("avares://Orion/Assets/SynapseX/script-preview.png");
        _ownedImages.Add(_fallbackImage);

        _navigation = new StackPanel
        {
            Width = 94,
            Spacing = 10,
            HorizontalAlignment = HorizontalAlignment.Left,
            VerticalAlignment = VerticalAlignment.Top
        };
        AddNavigationButton(SynapseXHubPage.RobloxScripts, "robloxscripts.com");
        AddNavigationButton(SynapseXHubPage.SynapseHub, "Synapse Hub");
        AddNavigationButton(SynapseXHubPage.Rscripts, "rscripts.net");
        AddNavigationButton(SynapseXHubPage.HaxHell, "HaxHell");
        AddNavigationButton(SynapseXHubPage.ScriptBlox, "ScriptBlox", warning: true);

        _searchBox = new TextBox
        {
            Height = 26,
            PlaceholderText = "Search robloxscripts.com...",
            Background = SynapseOriginalCompanionUi.Brush(SynapseOriginalCompanionUi.ChipBackground),
            BorderBrush = SynapseOriginalCompanionUi.Brush(SynapseOriginalCompanionUi.ChipBorder),
            BorderThickness = new Thickness(1),
            Foreground = SynapseOriginalCompanionUi.Brush("#C0C0C0"),
            CaretBrush = Brushes.White,
            FontSize = 11,
            Padding = new Thickness(6, 2),
            VerticalContentAlignment = VerticalAlignment.Center,
            CornerRadius = new CornerRadius(0)
        };
        _searchBox.KeyDown += SearchBox_KeyDown;

        _scriptList = new StackPanel { Spacing = 1 };
        var listScroll = new ScrollViewer
        {
            Content = _scriptList,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled
        };
        var listLayout = new Grid { RowDefinitions = new RowDefinitions("26,4,*") };
        listLayout.Children.Add(_searchBox);
        Grid.SetRow(listScroll, 2);
        listLayout.Children.Add(listScroll);
        var listPanel = new Border
        {
            Background = SynapseOriginalCompanionUi.Brush(SynapseOriginalCompanionUi.RowBackground),
            BorderBrush = SynapseOriginalCompanionUi.Brush("#212120"),
            BorderThickness = new Thickness(1),
            Padding = new Thickness(6),
            Child = listLayout
        };

        _previewImage = new Image
        {
            Source = _fallbackImage,
            Stretch = Stretch.UniformToFill
        };
        RenderOptions.SetBitmapInterpolationMode(_previewImage, BitmapInterpolationMode.HighQuality);
        var preview = new Border
        {
            Background = SynapseOriginalCompanionUi.Brush("#1D1D1D"),
            ClipToBounds = true,
            Child = _previewImage
        };

        _descriptionText = new TextBlock
        {
            Text = "Pick a script on the left to preview it.",
            FontSize = 14,
            Foreground = SynapseOriginalCompanionUi.Brush("#C0C0C0"),
            TextWrapping = TextWrapping.Wrap,
            LineHeight = 18
        };
        _sourceText = new TextBlock
        {
            Text = "Source: robloxscripts.com",
            FontSize = 10,
            Foreground = SynapseOriginalCompanionUi.Brush("#7A7A7A"),
            Margin = new Thickness(0, 2, 0, 0)
        };
        _statusText = new TextBlock
        {
            FontSize = 10,
            Foreground = SynapseOriginalCompanionUi.Brush("#CC6E6E"),
            Margin = new Thickness(0, 2, 0, 0),
            TextWrapping = TextWrapping.Wrap,
            IsVisible = false
        };
        var descriptionGrid = new Grid { RowDefinitions = new RowDefinitions("*,Auto,Auto") };
        descriptionGrid.Children.Add(new ScrollViewer
        {
            Content = _descriptionText,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled
        });
        Grid.SetRow(_sourceText, 1);
        descriptionGrid.Children.Add(_sourceText);
        Grid.SetRow(_statusText, 2);
        descriptionGrid.Children.Add(_statusText);
        var descriptionPanel = new Border
        {
            Background = SynapseOriginalCompanionUi.Brush(SynapseOriginalCompanionUi.RowBackground),
            Padding = new Thickness(8),
            Child = descriptionGrid
        };

        _runButton = CreateHubButton("Run Script");
        _runButton.Click += RunButton_Click;
        var closeButton = CreateHubButton("Close");
        closeButton.Click += (_, _) => Close();
        var actions = new Grid { ColumnDefinitions = new ColumnDefinitions("*,3,*") };
        actions.Children.Add(_runButton);
        Grid.SetColumn(closeButton, 2);
        actions.Children.Add(closeButton);

        var detail = new Grid { RowDefinitions = new RowDefinitions("162,113,3,37") };
        detail.Children.Add(preview);
        Grid.SetRow(descriptionPanel, 1);
        detail.Children.Add(descriptionPanel);
        Grid.SetRow(actions, 3);
        detail.Children.Add(actions);

        var body = new Grid
        {
            Margin = new Thickness(6, 5, 14, 6),
            ColumnDefinitions = new ColumnDefinitions("94,9,171,9,*")
        };
        body.Children.Add(_navigation);
        Grid.SetColumn(listPanel, 2);
        body.Children.Add(listPanel);
        Grid.SetColumn(detail, 4);
        body.Children.Add(detail);

        Content = SynapseOriginalCompanionUi.BuildChrome(this, body, title: null, showClose: false);
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

    private Button CreateHubButton(string label)
    {
        var button = SynapseOriginalCompanionUi.CreateButton(label, 37, fontSize: 14);
        button.PointerExited += (_, _) =>
            button.Background = SynapseOriginalCompanionUi.Brush(SynapseOriginalCompanionUi.ChipBackground);
        return button;
    }

    private void AddNavigationButton(SynapseXHubPage page, string label, bool warning = false)
    {
        Control content;
        if (warning)
        {
            var warningIcon = new Grid { Width = 11, Height = 11 };
            warningIcon.Children.Add(new Avalonia.Controls.Shapes.Path
            {
                Data = Geometry.Parse("M5.5 0.5 L10.7 10.5 H0.3 Z"),
                Fill = SynapseOriginalCompanionUi.Brush("#EAB308")
            });
            warningIcon.Children.Add(new TextBlock
            {
                Text = "!",
                Foreground = SynapseOriginalCompanionUi.Brush("#2A2500"),
                FontSize = 7,
                FontWeight = FontWeight.Bold,
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center,
                Margin = new Thickness(0, 1.5, 0, 0)
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
                FontSize = label.Length > 13 ? 10 : 13,
                TextTrimming = TextTrimming.CharacterEllipsis,
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center
            };
        }

        var button = SynapseOriginalCompanionUi.CreateButton(content, 37, 94, 13);
        button.Click += (_, _) => _ = SelectPageAsync(page);
        button.PointerExited += (_, _) => RefreshNavigation();
        _navigationButtons[page] = button;
        _navigation.Children.Add(button);
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
        _searchBox.PlaceholderText = $"Search {DisplayName(page)}...";
        _sourceText.Text = $"Source: {DisplayName(page)}";
        ClearSelection();
        RefreshNavigation();

        if (page == SynapseXHubPage.SynapseHub)
        {
            _loadCancellation?.Cancel();
            _currentCards = BuildSynapseHubScripts();
            BuildScriptRows(_currentCards);
            if (_currentCards.Count > 0)
            {
                SelectCard(_currentCards[0]);
            }
            return;
        }

        await LoadProviderAsync(string.Empty);
    }

    private async Task LoadProviderAsync(string query)
    {
        if (_closed || _currentPage == SynapseXHubPage.SynapseHub)
        {
            return;
        }

        _loadCancellation?.Cancel();
        _loadCancellation?.Dispose();
        _loadCancellation = new CancellationTokenSource();
        var token = _loadCancellation.Token;
        var requestedPage = _currentPage;
        ShowListMessage("Loading...", "#A3A3A3");
        _descriptionText.Text = $"Loading {DisplayName(requestedPage)} catalogue...";
        _statusText.IsVisible = false;

        try
        {
            var result = await _service.FetchAsync(ToProvider(requestedPage), query, 1, token);
            if (_closed || token.IsCancellationRequested || requestedPage != _currentPage)
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
            if (!_closed && !token.IsCancellationRequested && requestedPage == _currentPage && _selectedCard is not null)
            {
                _previewImage.Source = _selectedCard.Thumbnail ?? _fallbackImage;
            }
        }
        catch (OperationCanceledException)
        {
            // A newer page selection or search superseded this request.
        }
        catch (Exception exception) when (exception is HttpRequestException or IOException or InvalidDataException)
        {
            if (_closed || token.IsCancellationRequested || requestedPage != _currentPage)
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
        _scriptList.Children.Clear();
        _scriptRows.Clear();
        foreach (var card in cards)
        {
            var text = new TextBlock
            {
                Text = card.Title,
                FontSize = 11,
                Foreground = SynapseOriginalCompanionUi.Brush("#C0C0C0"),
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
                Padding = new Thickness(4),
                CornerRadius = new CornerRadius(0)
            };
            ToolTip.SetTip(button, card.Title);
            button.Click += (_, _) => SelectCard(card);
            button.PointerEntered += (_, _) =>
            {
                if (!ReferenceEquals(_selectedCard, card))
                {
                    button.Background = SynapseOriginalCompanionUi.Brush("#333333");
                }
            };
            button.PointerExited += (_, _) => RefreshSelectedRowVisuals();
            _scriptRows.Add((button, card));
            _scriptList.Children.Add(button);
        }
    }

    private void SelectCard(ScriptHubCardModel card)
    {
        _selectedCard = card;
        _previewImage.Source = card.Thumbnail ?? _fallbackImage;
        _descriptionText.Text = string.IsNullOrWhiteSpace(card.Description) ? card.Title : card.Description;
        _sourceText.Text = $"Source: {DisplayName(_currentPage)}";
        _statusText.IsVisible = false;
        RefreshSelectedRowVisuals();
        UpdateRunButton();
    }

    private void ClearSelection()
    {
        _selectedCard = null;
        _currentCards = [];
        _previewImage.Source = _fallbackImage;
        _descriptionText.Text = "Pick a script on the left to preview it.";
        _statusText.IsVisible = false;
        _scriptRows.Clear();
        _scriptList.Children.Clear();
        UpdateRunButton();
    }

    private void RefreshSelectedRowVisuals()
    {
        foreach (var (button, card) in _scriptRows)
        {
            var selected = ReferenceEquals(card, _selectedCard);
            button.Background = selected
                ? SynapseOriginalCompanionUi.Brush("#3C3C3C")
                : Brushes.Transparent;
            if (button.Content is TextBlock text)
            {
                text.Foreground = SynapseOriginalCompanionUi.Brush(selected ? "#E8E8E8" : "#C0C0C0");
            }
        }
    }

    private void RefreshNavigation()
    {
        foreach (var (page, button) in _navigationButtons)
        {
            var active = page == _currentPage;
            button.Background = SynapseOriginalCompanionUi.Brush(
                active ? SynapseOriginalCompanionUi.ActiveBackground : SynapseOriginalCompanionUi.ChipBackground);
            button.BorderBrush = SynapseOriginalCompanionUi.Brush(
                active ? SynapseOriginalCompanionUi.ActiveBorder : SynapseOriginalCompanionUi.ChipBorder);
        }
    }

    private void ShowListMessage(string message, string color)
    {
        _scriptList.Children.Clear();
        _scriptRows.Clear();
        _scriptList.Children.Add(new TextBlock
        {
            Text = message,
            Foreground = SynapseOriginalCompanionUi.Brush(color),
            FontSize = 10,
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(2, 8),
            HorizontalAlignment = HorizontalAlignment.Center
        });
    }

    private void RunButton_Click(object? sender, Avalonia.Interactivity.RoutedEventArgs args)
    {
        if (!_bridgeConnected || _selectedCard is null)
        {
            return;
        }
        if (string.IsNullOrWhiteSpace(_selectedCard.ScriptBody))
        {
            SetStatus("Script source is unavailable.", error: true);
            return;
        }
        UnifiedBridgeServer.Shared.EnqueueExecute(_selectedCard.ScriptBody);
        SetStatus($"Sent: {_selectedCard.Title}", error: false);
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
                               _selectedCard is not null &&
                               !string.IsNullOrWhiteSpace(_selectedCard.ScriptBody);
        _runButton.Opacity = _runButton.IsEnabled ? 1 : 0.5;
    }

    private void SetStatus(string message, bool error)
    {
        _statusText.Text = message;
        _statusText.Foreground = SynapseOriginalCompanionUi.Brush(error ? "#CC6E6E" : "#77A97A");
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
        Bitmap image) =>
        new(title, description, string.Empty, script, description) { Thumbnail = image };

    private Bitmap AddOwnedBitmap(string uri)
    {
        var image = LoadBitmap(uri);
        _ownedImages.Add(image);
        return image;
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
