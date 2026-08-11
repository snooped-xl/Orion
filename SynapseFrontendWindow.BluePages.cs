using Avalonia;
using Avalonia.Animation.Easings;
using Avalonia.Controls;
using Avalonia.Controls.Primitives;
using Avalonia.Controls.Primitives.PopupPositioning;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Media.Imaging;
using Avalonia.Platform;
using Avalonia.Threading;

namespace OrbitAvalonia;

internal sealed partial class SynapseFrontendWindow
{
    private enum BlueHubPage
    {
        SynapseHub,
        RobloxScripts,
        Rscripts,
        HaxHell,
        ScriptBlox
    }

    private sealed record BlueLegacyScript(
        string Name,
        string Description,
        string Code,
        string ImageUri);

    private static readonly SplineEasing BlueHoverEase = new(0.25, 0, 0.2, 1);
    private static readonly SplineEasing BluePageEase = new(0, 0, 0.22, 1);
    private readonly ScriptHubService _blueHubService = new();
    private readonly Dictionary<BlueHubPage, Button> _blueHubButtons = [];
    private readonly List<Bitmap> _blueOwnedImages = [];
    private CancellationTokenSource? _blueTooltipCancellation;
    private CancellationTokenSource? _bluePageCancellation;
    private CancellationTokenSource? _blueHubLoadCancellation;
    private Control? _blueTooltipCopyHost;
    private Popup? _blueTooltipPopup;
    private Popup? _blueTooltipDimPopup;
    private Border? _blueTooltipDimmer;
    private Control? _blueTooltipPlacementRoot;
    private DispatcherTimer? _blueTooltipMotionTimer;
    private bool _blueTooltipShouldOpen;
    private double _blueTooltipCurrentLeft = 53;
    private double _blueTooltipCurrentTop = 55;
    private double _blueTooltipCurrentOpacity;
    private double _blueTooltipCurrentDimOpacity;
    private double _blueTooltipTargetTop = 55;
    private DateTime _blueTooltipMotionTimestamp;
    private int _blueTooltipContentIndex = -1;
    private int _blueHoveredNav = -1;
    private BlueHubPage _blueHubPage = BlueHubPage.SynapseHub;
    private Grid? _blueHubContent;
    private TextBox? _blueHubSearch;
    private TextBlock? _blueHubSource;
    private TextBlock? _blueHubStatus;
    private Control? _blueHubSpinner;
    private Border? _blueConsoleStatusDot;
    private TextBlock? _blueConsoleStatusText;
    private StackPanel? _blueConsoleOutput;

    private void ShowBlueTooltip(int index)
    {
        if (_blueTooltip is null || index < 0 || index >= BlueTooltipCopy.Length)
        {
            return;
        }

        _blueHoveredNav = index;
        RefreshBlueNavigationVisuals(index);
        _blueTooltipCancellation?.Cancel();
        _blueTooltipCancellation?.Dispose();
        _blueTooltipCancellation = null;

        var copy = BlueTooltipCopy[index];
        _blueTooltipTitle!.Text = copy.Title;
        _blueTooltipLine1!.Text = copy.Line1;
        _blueTooltipLine2!.Text = copy.Line2;
        _blueTooltipLine2.IsVisible = copy.Line2.Length > 0;
        if (_blueTooltipContentIndex != index && _blueTooltipCopyHost is not null)
        {
            _blueTooltipCopyHost.Opacity = _blueTooltipPopup?.IsOpen == true ? 0.38 : 1;
        }
        _blueTooltipContentIndex = index;
        _blueTooltipTargetTop = 55 + index * 66;
        _blueTooltipShouldOpen = true;
        EnsureBlueTooltipPopupsOpen();
        StartBlueTooltipMotion();
    }

    private void HideBlueTooltip(int index)
    {
        if (_blueHoveredNav != index)
        {
            return;
        }

        _blueTooltipCancellation?.Cancel();
        _blueTooltipCancellation?.Dispose();
        _blueTooltipCancellation = new CancellationTokenSource();
        _ = DelayBlueTooltipCloseAsync(index, _blueTooltipCancellation.Token);
    }

    private async Task DelayBlueTooltipCloseAsync(int index, CancellationToken cancellationToken)
    {
        try
        {
            // Covers the tiny gap between adjacent 64px navigation cells so
            // a quick sweep retargets one continuously moving card.
            await Task.Delay(64, cancellationToken);
        }
        catch (OperationCanceledException)
        {
            return;
        }

        if (_blueHoveredNav != index)
        {
            return;
        }

        _blueHoveredNav = -1;
        RefreshBlueNavigationVisuals(-1);
        _blueTooltipShouldOpen = false;
        StartBlueTooltipMotion();
    }

    private void EnsureBlueTooltipPopupsOpen()
    {
        if (_blueTooltip is null || _blueTooltipPopup is null)
        {
            return;
        }

        if (_blueTooltipPlacementRoot is { } placementRoot && _blueTooltipDimmer is { } dimmer)
        {
            dimmer.Width = Math.Max(0, placementRoot.Bounds.Width - 60);
            dimmer.Height = Math.Max(0, placementRoot.Bounds.Height - 55);
        }

        if (_blueTooltipDimPopup is { IsOpen: false } dimPopup)
        {
            dimPopup.IsOpen = true;
        }
        if (!_blueTooltipPopup.IsOpen)
        {
            _blueTooltipCurrentLeft = 53;
            _blueTooltipCurrentTop = _blueTooltipTargetTop;
            _blueTooltipCurrentOpacity = 0;
            _blueTooltipCurrentDimOpacity = 0;
            _blueTooltipPopup.HorizontalOffset = _blueTooltipCurrentLeft;
            _blueTooltipPopup.VerticalOffset = _blueTooltipCurrentTop;
            _blueTooltip.Opacity = 0;
            _blueTooltip.IsVisible = true;
            _blueTooltipPopup.IsOpen = true;
        }
    }

    private void StartBlueTooltipMotion()
    {
        _blueTooltipMotionTimestamp = DateTime.UtcNow;
        if (_blueTooltipMotionTimer is null)
        {
            _blueTooltipMotionTimer = new DispatcherTimer
            {
                Interval = TimeSpan.FromMilliseconds(16)
            };
            _blueTooltipMotionTimer.Tick += (_, _) => AdvanceBlueTooltipMotion();
        }
        if (!_blueTooltipMotionTimer.IsEnabled)
        {
            _blueTooltipMotionTimer.Start();
        }
    }

    private void AdvanceBlueTooltipMotion()
    {
        if (_blueTooltip is null || _blueTooltipPopup is null)
        {
            _blueTooltipMotionTimer?.Stop();
            return;
        }

        var now = DateTime.UtcNow;
        var elapsedMs = Math.Clamp((now - _blueTooltipMotionTimestamp).TotalMilliseconds, 1, 48);
        _blueTooltipMotionTimestamp = now;
        var shellFollow = 1 - Math.Exp(-elapsedMs / 76d);
        var moveFollow = 1 - Math.Exp(-elapsedMs / 88d);
        var copyFollow = 1 - Math.Exp(-elapsedMs / 72d);
        var targetOpacity = _blueTooltipShouldOpen ? 1d : 0d;
        var targetLeft = _blueTooltipShouldOpen ? 67d : 53d;
        var targetDimOpacity = _blueTooltipShouldOpen ? 0.64d : 0d;

        _blueTooltipCurrentLeft += (targetLeft - _blueTooltipCurrentLeft) * shellFollow;
        _blueTooltipCurrentTop += (_blueTooltipTargetTop - _blueTooltipCurrentTop) * moveFollow;
        _blueTooltipCurrentOpacity += (targetOpacity - _blueTooltipCurrentOpacity) * shellFollow;
        _blueTooltipCurrentDimOpacity += (targetDimOpacity - _blueTooltipCurrentDimOpacity) * shellFollow;

        _blueTooltipPopup.HorizontalOffset = _blueTooltipCurrentLeft;
        _blueTooltipPopup.VerticalOffset = _blueTooltipCurrentTop;
        _blueTooltip.Opacity = _blueTooltipCurrentOpacity;
        if (_blueTooltipCopyHost is { } copyHost)
        {
            copyHost.Opacity += (1 - copyHost.Opacity) * copyFollow;
        }
        if (_blueTooltipDimmer is { } dimmer)
        {
            if (_blueTooltipPlacementRoot is { } placementRoot)
            {
                dimmer.Width = Math.Max(0, placementRoot.Bounds.Width - 60);
                dimmer.Height = Math.Max(0, placementRoot.Bounds.Height - 55);
            }
            dimmer.Opacity = _blueTooltipCurrentDimOpacity;
        }

        var topSettled = Math.Abs(_blueTooltipTargetTop - _blueTooltipCurrentTop) < 0.15;
        var leftSettled = Math.Abs(targetLeft - _blueTooltipCurrentLeft) < 0.1;
        var opacitySettled = Math.Abs(targetOpacity - _blueTooltipCurrentOpacity) < 0.005;
        var dimSettled = Math.Abs(targetDimOpacity - _blueTooltipCurrentDimOpacity) < 0.005;
        if (!(topSettled && leftSettled && opacitySettled && dimSettled))
        {
            return;
        }

        _blueTooltipCurrentLeft = targetLeft;
        _blueTooltipCurrentTop = _blueTooltipTargetTop;
        _blueTooltipCurrentOpacity = targetOpacity;
        _blueTooltipCurrentDimOpacity = targetDimOpacity;
        _blueTooltipPopup.HorizontalOffset = targetLeft;
        _blueTooltipPopup.VerticalOffset = _blueTooltipTargetTop;
        _blueTooltip.Opacity = targetOpacity;
        if (_blueTooltipDimmer is { } settledDimmer)
        {
            settledDimmer.Opacity = targetDimOpacity;
        }
        _blueTooltipMotionTimer?.Stop();

        if (!_blueTooltipShouldOpen)
        {
            _blueTooltip.IsVisible = false;
            _blueTooltipPopup.IsOpen = false;
            if (_blueTooltipDimPopup is not null)
            {
                _blueTooltipDimPopup.IsOpen = false;
            }
        }
    }

    private async Task AnimateBlueValueAsync(
        double from,
        double to,
        int durationMs,
        Action<double> update,
        CancellationToken cancellationToken)
    {
        var started = DateTime.UtcNow;
        while (!cancellationToken.IsCancellationRequested)
        {
            var elapsed = (DateTime.UtcNow - started).TotalMilliseconds;
            var t = Math.Clamp(elapsed / durationMs, 0, 1);
            update(from + (to - from) * t);
            if (t >= 1) return;
            await Task.Delay(16, cancellationToken);
        }
    }

    private void RefreshBlueNavigationVisuals(int hoveredIndex)
    {
        for (var index = 0; index < _blueNavButtons.Count; index++)
        {
            var highlighted = index == _blueActivePage || index == hoveredIndex;
            _blueNavButtons[index].Background = Brush(highlighted ? "#404040" : "#383838");
            if (index >= _blueNavIcons.Count || _blueNavIcons[index] is not Canvas canvas)
            {
                continue;
            }

            foreach (var path in canvas.Children.OfType<Avalonia.Controls.Shapes.Path>())
            {
                path.Stroke = Brush(highlighted ? "#FFFFFF" : "#ECECEC");
            }
        }
    }

    private async void ShowBluePage(int index)
    {
        if (_bluePages.Count == 0)
        {
            return;
        }

        index = Math.Clamp(index, 0, _bluePages.Count - 1);
        if (_blueActivePage == index && _bluePages[index].IsVisible)
        {
            RefreshBlueNavigationVisuals(_blueHoveredNav);
            return;
        }

        _bluePageCancellation?.Cancel();
        _bluePageCancellation?.Dispose();
        _bluePageCancellation = new CancellationTokenSource();
        var token = _bluePageCancellation.Token;
        _blueActivePage = index;
        // NativeWebView owns a child HWND. Hiding only its Avalonia parent can
        // let that HWND repaint above another route after focus/hover changes,
        // so the editor surface itself must follow the active Blue page.
        _editor.IsVisible = index == 0;
        RefreshBlueNavigationVisuals(_blueHoveredNav);

        for (var pageIndex = 0; pageIndex < _bluePages.Count; pageIndex++)
        {
            if (pageIndex == index) continue;
            _bluePages[pageIndex].IsVisible = false;
            _bluePages[pageIndex].Opacity = 0;
        }

        var incoming = _bluePages[index];
        incoming.Opacity = 0;
        incoming.IsVisible = true;
        try
        {
            await AnimateBlueValueAsync(
                0,
                1,
                340,
                t => incoming.Opacity = BluePageEase.Ease(t),
                token);
        }
        catch (OperationCanceledException)
        {
            return;
        }

        if (!token.IsCancellationRequested)
        {
            incoming.Opacity = 1;
        }
    }

    private Control BuildBlueScriptHubPage()
    {
        var root = new Grid
        {
            Margin = new Thickness(8, 4, 8, 8),
            RowDefinitions = new RowDefinitions("27,5,30,7,*")
        };

        root.Children.Add(new TextBlock
        {
            Text = "Script hub",
            Foreground = Brushes.White,
            FontSize = 22,
            FontWeight = FontWeight.Normal,
            VerticalAlignment = VerticalAlignment.Center
        });

        var providerStrip = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 4,
            VerticalAlignment = VerticalAlignment.Center
        };
        AddBlueHubButton(providerStrip, BlueHubPage.SynapseHub, "Synapse Hub", 101);
        AddBlueHubButton(providerStrip, BlueHubPage.RobloxScripts, "robloxscripts.com", 123);
        AddBlueHubButton(providerStrip, BlueHubPage.Rscripts, "rscripts.net", 96);
        AddBlueHubButton(providerStrip, BlueHubPage.HaxHell, "HaxHell", 76);
        AddBlueHubButton(providerStrip, BlueHubPage.ScriptBlox, "ScriptBlox", 101, warning: true);
        Grid.SetRow(providerStrip, 2);
        root.Children.Add(providerStrip);

        _blueHubContent = new Grid { Background = Brushes.Transparent };
        Grid.SetRow(_blueHubContent, 4);
        root.Children.Add(_blueHubContent);
        Dispatcher.UIThread.Post(() => _ = SelectBlueHubPageAsync(BlueHubPage.SynapseHub, true), DispatcherPriority.Loaded);
        return root;
    }

    private void AddBlueHubButton(
        Panel parent,
        BlueHubPage page,
        string label,
        double width,
        bool warning = false)
    {
        Control content;
        if (warning)
        {
            var row = new StackPanel
            {
                Orientation = Orientation.Horizontal,
                Spacing = 4,
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center
            };
            row.Children.Add(new TextBlock
            {
                Text = label,
                Foreground = Brush("#C3C3C3"),
                FontSize = 11,
                VerticalAlignment = VerticalAlignment.Center
            });
            var warningGrid = new Grid { Width = 12, Height = 12 };
            warningGrid.Children.Add(new Avalonia.Controls.Shapes.Path
            {
                Data = Geometry.Parse("M6 0.8 L11.5 11 H0.5 Z"),
                Fill = Brush("#EAB308")
            });
            warningGrid.Children.Add(new TextBlock
            {
                Text = "!",
                Foreground = Brush("#2A2500"),
                FontSize = 8,
                FontWeight = FontWeight.Bold,
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center,
                Margin = new Thickness(0, 2, 0, 0)
            });
            row.Children.Add(warningGrid);
            content = row;
        }
        else
        {
            content = new TextBlock
            {
                Text = label,
                Foreground = Brush("#C3C3C3"),
                FontSize = label.Length > 13 ? 10 : 11,
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center
            };
        }

        var button = CreateBlueSurfaceButton(content, width, 30, 11);
        button.Click += (_, _) => _ = SelectBlueHubPageAsync(page);
        button.PointerEntered += (_, _) => button.Background = BlueActionHoverBrush();
        button.PointerExited += (_, _) => RefreshBlueHubButtons();
        _blueHubButtons[page] = button;
        parent.Children.Add(button);
    }

    private async Task SelectBlueHubPageAsync(BlueHubPage page, bool force = false)
    {
        if (_blueHubContent is null || (!force && _blueHubPage == page && _blueHubContent.Children.Count > 0))
        {
            return;
        }

        _blueHubPage = page;
        RefreshBlueHubButtons();
        _blueHubLoadCancellation?.Cancel();
        _blueHubLoadCancellation?.Dispose();
        _blueHubLoadCancellation = new CancellationTokenSource();
        var token = _blueHubLoadCancellation.Token;

        _blueHubContent.Children.Clear();
        if (page == BlueHubPage.SynapseHub)
        {
            _blueHubContent.Children.Add(BuildBlueSynapseHubContent());
            return;
        }

        _blueHubContent.Children.Add(BuildBlueProviderHubChrome(page));
        await LoadBlueProviderAsync(page, string.Empty, token);
    }

    private void RefreshBlueHubButtons()
    {
        foreach (var (page, button) in _blueHubButtons)
        {
            button.Background = page == _blueHubPage ? BlueActionHoverBrush() : BlueActionBrush();
            button.BorderBrush = Brush(page == _blueHubPage ? "#7183E8" : "#606060");
        }
    }

    private Control BuildBlueSynapseHubContent()
    {
        var stack = new StackPanel { Spacing = 9 };
        stack.Children.Add(new TextBlock
        {
            Text = "Synapse legacy scripts — open in the editor to run or edit.",
            Foreground = Brush("#8A8A8E"),
            FontSize = 12
        });
        stack.Children.Add(BuildBlueCardsGrid(BuildBlueLegacyCards(), "Synapse Hub"));
        return new ScrollViewer
        {
            Content = stack,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled
        };
    }

    private Control BuildBlueProviderHubChrome(BlueHubPage page)
    {
        var root = new Grid { RowDefinitions = new RowDefinitions("34,5,16,5,*") };
        _blueHubSearch = new TextBox
        {
            Height = 34,
            PlaceholderText = $"Search {BlueHubDisplayName(page)}…",
            Background = Brush("#191919"),
            BorderBrush = Brush("#606060"),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(4),
            Foreground = Brushes.White,
            CaretBrush = Brushes.White,
            FontSize = 12,
            Padding = new Thickness(10, 3),
            VerticalContentAlignment = VerticalAlignment.Center
        };
        _blueHubSearch.GotFocus += (_, _) => _blueHubSearch.BorderBrush = Brush("#3149E8");
        _blueHubSearch.LostFocus += (_, _) => _blueHubSearch.BorderBrush = Brush("#606060");
        _blueHubSearch.KeyDown += (_, args) =>
        {
            if (args.Key != Key.Enter) return;
            args.Handled = true;
            _blueHubLoadCancellation?.Cancel();
            _blueHubLoadCancellation?.Dispose();
            _blueHubLoadCancellation = new CancellationTokenSource();
            _ = LoadBlueProviderAsync(_blueHubPage, _blueHubSearch.Text?.Trim() ?? string.Empty, _blueHubLoadCancellation.Token);
        };
        root.Children.Add(_blueHubSearch);

        _blueHubSource = new TextBlock
        {
            Text = $"Source: {BlueHubDisplayName(page)}",
            Foreground = Brush("#8A8A8E"),
            FontSize = 11,
            VerticalAlignment = VerticalAlignment.Center
        };
        Grid.SetRow(_blueHubSource, 2);
        root.Children.Add(_blueHubSource);

        var resultsHost = new Grid();
        _blueHubStatus = new TextBlock
        {
            Text = "Loading…",
            Foreground = Brush("#8A8A8E"),
            FontSize = 12,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
            TextAlignment = TextAlignment.Center,
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(20)
        };
        resultsHost.Children.Add(_blueHubStatus);
        _blueHubSpinner = _blueHubStatus;
        Grid.SetRow(resultsHost, 4);
        root.Children.Add(resultsHost);
        return root;
    }

    private async Task LoadBlueProviderAsync(
        BlueHubPage page,
        string query,
        CancellationToken cancellationToken)
    {
        if (_blueHubContent is null || page == BlueHubPage.SynapseHub)
        {
            return;
        }

        if (_blueHubStatus is not null)
        {
            _blueHubStatus.Text = "Loading…";
            _blueHubStatus.Foreground = Brush("#8A8A8E");
            _blueHubStatus.IsVisible = true;
        }

        try
        {
            var result = await _blueHubService.FetchAsync(ToBlueProvider(page), query, 1, cancellationToken);
            if (cancellationToken.IsCancellationRequested || _blueHubPage != page || _blueHubContent is null)
            {
                return;
            }

            await _blueHubService.LoadThumbnailsAsync(result.Cards, cancellationToken);
            if (cancellationToken.IsCancellationRequested || _blueHubPage != page)
            {
                return;
            }

            var root = _blueHubContent.Children.OfType<Grid>().FirstOrDefault();
            var resultHost = root?.Children.OfType<Grid>().FirstOrDefault(control => Grid.GetRow(control) == 4);
            if (resultHost is null) return;
            resultHost.Children.Clear();
            if (result.Cards.Count == 0)
            {
                resultHost.Children.Add(new TextBlock
                {
                    Text = string.IsNullOrWhiteSpace(query) ? "No scripts on this page." : "No scripts match your search.",
                    Foreground = Brush("#8A8A8E"),
                    FontSize = 12,
                    HorizontalAlignment = HorizontalAlignment.Center,
                    VerticalAlignment = VerticalAlignment.Center
                });
                return;
            }

            resultHost.Children.Add(new ScrollViewer
            {
                Content = BuildBlueCardsGrid(result.Cards, BlueHubDisplayName(page)),
                VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
                HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled
            });
        }
        catch (OperationCanceledException)
        {
            // A provider switch or a newer search superseded this request.
        }
        catch (Exception exception) when (exception is HttpRequestException or IOException or InvalidDataException)
        {
            if (cancellationToken.IsCancellationRequested || _blueHubStatus is null) return;
            _blueHubStatus.Text = exception.Message;
            _blueHubStatus.Foreground = Brush("#CC6E6E");
        }
    }

    private Grid BuildBlueCardsGrid(IReadOnlyList<ScriptHubCardModel> cards, string source)
    {
        var grid = new Grid
        {
            ColumnDefinitions = new ColumnDefinitions("*,12,*"),
            RowDefinitions = new RowDefinitions(string.Join(',', Enumerable.Repeat("112", Math.Max(1, (cards.Count + 1) / 2))))
        };

        for (var index = 0; index < cards.Count; index++)
        {
            var card = BuildBlueHubCard(cards[index], source);
            var row = index / 2;
            var column = index % 2 == 0 ? 0 : 2;
            if (row > 0) card.Margin = new Thickness(0, 12, 0, 0);
            Grid.SetRow(card, row);
            Grid.SetColumn(card, column);
            grid.Children.Add(card);
        }
        return grid;
    }

    private Border BuildBlueHubCard(ScriptHubCardModel card, string source)
    {
        var image = new Image
        {
            Source = card.Thumbnail ?? BlueFallbackImage(),
            Stretch = Stretch.UniformToFill
        };
        var thumbnail = new Border
        {
            Background = Brush("#454545"),
            ClipToBounds = true,
            Child = image
        };

        var title = new TextBlock
        {
            Text = card.Title,
            Foreground = Brushes.White,
            FontSize = 14,
            FontWeight = FontWeight.SemiBold,
            TextWrapping = TextWrapping.Wrap,
            MaxLines = 2,
            TextTrimming = TextTrimming.CharacterEllipsis,
            LineHeight = 17
        };
        var subtitle = new TextBlock
        {
            Text = card.Subtitle,
            Foreground = Brush("#8A8A8E"),
            FontSize = 10,
            TextWrapping = TextWrapping.Wrap,
            MaxLines = 2,
            TextTrimming = TextTrimming.CharacterEllipsis,
            Margin = new Thickness(0, 2, 0, 0)
        };
        var open = new Button
        {
            Height = 27,
            Content = "OPEN IN EDITOR",
            Background = Brush("#3149E8"),
            BorderBrush = Brush("#4A5ED8"),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(4),
            Foreground = Brushes.White,
            FontSize = 10,
            FontWeight = FontWeight.SemiBold,
            HorizontalContentAlignment = HorizontalAlignment.Center,
            VerticalContentAlignment = VerticalAlignment.Center,
            Padding = new Thickness(2, 0)
        };
        open.PointerEntered += (_, _) => open.Background = Brush("#2A40D4");
        open.PointerExited += (_, _) => open.Background = Brush("#3149E8");
        open.Click += (_, _) => OpenBlueHubScript(card, source);

        var detail = new Grid
        {
            Margin = new Thickness(8),
            RowDefinitions = new RowDefinitions("*,Auto")
        };
        var copy = new StackPanel { Spacing = 0 };
        copy.Children.Add(title);
        copy.Children.Add(subtitle);
        detail.Children.Add(copy);
        Grid.SetRow(open, 1);
        detail.Children.Add(open);

        var layout = new Grid { ColumnDefinitions = new ColumnDefinitions("34*,66*") };
        layout.Children.Add(thumbnail);
        Grid.SetColumn(detail, 1);
        layout.Children.Add(detail);

        return new Border
        {
            Height = 112,
            Background = Brush("#191919"),
            BorderBrush = Brush("#3A3A3A"),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(8),
            ClipToBounds = true,
            Effect = new DropShadowEffect
            {
                Color = Colors.Black,
                BlurRadius = 8,
                OffsetY = 2,
                Opacity = .2
            },
            Child = layout
        };
    }

    private IReadOnlyList<ScriptHubCardModel> BuildBlueLegacyCards()
    {
        var scripts = new[]
        {
            new BlueLegacyScript("Dark Dex", "Universal Explorer",
                "loadstring(game:HttpGet(\"https://raw.githubusercontent.com/Babyhamsta/RBLX_Scripts/main/Universal/BypassedDarkDexV3.lua\", true))()",
                "avares://Orion/Assets/SynapseX/dex.png"),
            new BlueLegacyScript("Unnamed ESP", "Global ESP Framework",
                "loadstring(game:HttpGet(\"https://raw.githubusercontent.com/ic3w0lf22/Unnamed-ESP/master/UnnamedESP.lua\"))()",
                "avares://Orion/Assets/SynapseX/unnamed-esp.png"),
            new BlueLegacyScript("Remote Spy", "SimpleSpy V3",
                "loadstring(game:HttpGet(\"https://raw.githubusercontent.com/exxtremestuffs/SimpleSpySource/master/SimpleSpy.lua\"))()",
                "avares://Orion/Assets/SynapseX/remote-spy.png"),
            new BlueLegacyScript("Script Dumper", "Decompile & dump all scripts",
                LoadBlueTextAsset("avares://Orion/Assets/SynapseX/script-dumper.lua"),
                "avares://Orion/Assets/SynapseX/script-dumper.png")
        };

        return scripts.Select(script =>
        {
            var card = new ScriptHubCardModel(script.Name, script.Description, string.Empty, script.Code, script.Description)
            {
                Thumbnail = LoadBlueBitmap(script.ImageUri)
            };
            return card;
        }).ToArray();
    }

    private Bitmap BlueFallbackImage()
    {
        var existing = _blueOwnedImages.FirstOrDefault(image => image.PixelSize.Width == 1 && image.PixelSize.Height == 1);
        if (existing is not null) return existing;
        return LoadBlueBitmap("avares://Orion/Assets/SynapseX/script-preview.png");
    }

    private Bitmap LoadBlueBitmap(string uri)
    {
        using var stream = AssetLoader.Open(new Uri(uri));
        var bitmap = new Bitmap(stream);
        _blueOwnedImages.Add(bitmap);
        return bitmap;
    }

    private static string LoadBlueTextAsset(string uri)
    {
        using var stream = AssetLoader.Open(new Uri(uri));
        using var reader = new StreamReader(stream);
        return reader.ReadToEnd();
    }

    private void OpenBlueHubScript(ScriptHubCardModel card, string source)
    {
        ActiveTab().Content = _editorContent;
        var tab = new EditorTabState
        {
            Title = card.Title,
            Extension = ".lua",
            Content = string.IsNullOrWhiteSpace(card.ScriptBody)
                ? $"-- {source}: {card.Title}\n-- No source returned.\n"
                : card.ScriptBody
        };
        _workspace.Tabs.Add(tab);
        _workspace.ActiveTabId = tab.Id;
        _editorContent = tab.Content;
        RebuildTabs(SynapseFrontendKind.Blue);
        SetEditorContent(tab.Content);
        ShowBluePage(0);
    }

    private Control BuildBlueConsolePage()
    {
        var page = new Grid
        {
            Margin = new Thickness(7),
            RowDefinitions = new RowDefinitions("36,6,*")
        };
        var heading = new Grid { ColumnDefinitions = new ColumnDefinitions("*,4,91,4,91") };
        var titleStack = new StackPanel { Spacing = 0 };
        titleStack.Children.Add(new TextBlock
        {
            Text = "Console",
            Foreground = Brushes.White,
            FontSize = 22,
            FontWeight = FontWeight.Normal,
            LineHeight = 24
        });
        var status = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 6,
            VerticalAlignment = VerticalAlignment.Center
        };
        _blueConsoleStatusDot = new Border
        {
            Width = 8,
            Height = 8,
            CornerRadius = new CornerRadius(4),
            Background = Brush(UnifiedBridgeServer.Shared.IsConnected ? "#6FCF97" : "#C45C5C")
        };
        _blueConsoleStatusText = new TextBlock
        {
            Text = UnifiedBridgeServer.Shared.IsConnected ? "Orion Bridge · Connected" : "Orion Bridge · Listening · Attach required",
            Foreground = Brush("#B8B8B8"),
            FontSize = 10,
            Opacity = .8
        };
        status.Children.Add(_blueConsoleStatusDot);
        status.Children.Add(_blueConsoleStatusText);
        titleStack.Children.Add(status);
        heading.Children.Add(titleStack);

        var copy = CreateBlueSurfaceButton("Copy", 91, 36, 13);
        copy.Click += (_, _) =>
        {
            if (_blueConsoleOutput is not null)
            {
                var text = string.Join(Environment.NewLine,
                    _blueConsoleOutput.Children.OfType<TextBlock>().Select(item => item.Text));
                if (!string.IsNullOrWhiteSpace(text)) System.Windows.Forms.Clipboard.SetText(text);
            }
        };
        Grid.SetColumn(copy, 2);
        heading.Children.Add(copy);

        var clear = CreateBlueSurfaceButton("Clear", 91, 36, 13, attachHover: true);
        clear.Click += (_, _) => _blueConsoleOutput?.Children.Clear();
        Grid.SetColumn(clear, 4);
        heading.Children.Add(clear);
        page.Children.Add(heading);

        _blueConsoleOutput = new StackPanel { Spacing = 5, Margin = new Thickness(8) };
        foreach (var entry in UnifiedBridgeServer.Shared.GetLogSnapshot())
        {
            AddBlueBridgeConsoleLine(entry.Level, entry.Message);
        }
        var output = new Border
        {
            Background = Brush("#2A2A2A"),
            BorderBrush = Brush("#1E1E1E"),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(2),
            ClipToBounds = true,
            Effect = new DropShadowEffect
            {
                Color = Colors.White,
                BlurRadius = 0,
                OffsetY = 1,
                Opacity = .05
            },
            Child = new ScrollViewer
            {
                Content = _blueConsoleOutput,
                VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
                HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled
            }
        };
        Grid.SetRow(output, 2);
        page.Children.Add(output);
        return page;
    }

    private void AddBlueConsoleLine(string text, string color)
    {
        _blueConsoleOutput?.Children.Add(new TextBlock
        {
            Text = text,
            Foreground = Brush(color),
            FontFamily = new FontFamily("Consolas"),
            FontSize = 11,
            LineHeight = 14,
            TextWrapping = TextWrapping.Wrap
        });
    }

    private void BridgeLogReceived(string level, string message) =>
        Dispatcher.UIThread.Post(() => AddBlueBridgeConsoleLine(level, message));

    private void AddBlueBridgeConsoleLine(string level, string message)
    {
        if (_blueConsoleOutput is null) return;
        var normalized = string.IsNullOrWhiteSpace(level) ? "info" : level.ToLowerInvariant();
        var prefix = normalized switch
        {
            "warn" or "warning" => "[warn]   ",
            "error" => "[error]  ",
            "print" or "output" => "[print]  ",
            _ => "[info]   "
        };
        var color = normalized switch
        {
            "warn" or "warning" => "#C8A25A",
            "error" => "#D06B6B",
            _ => "#D0D0D0"
        };
        AddBlueConsoleLine(prefix + message, color);
        while (_blueConsoleOutput.Children.Count > 250)
        {
            _blueConsoleOutput.Children.RemoveAt(0);
        }
        if (_blueConsoleOutput.Children.LastOrDefault() is Control last)
        {
            Dispatcher.UIThread.Post(last.BringIntoView, DispatcherPriority.Background);
        }
    }

    private void UpdateBlueConsoleConnection(bool connected)
    {
        if (_blueConsoleStatusDot is not null)
        {
            _blueConsoleStatusDot.Background = Brush(connected ? "#6FCF97" : "#C45C5C");
        }
        if (_blueConsoleStatusText is not null)
        {
            _blueConsoleStatusText.Text = connected
                ? "Orion Bridge · Connected"
                : "Orion Bridge · Listening · Attach required";
        }
    }

    private Control BuildBlueSettingsPage()
    {
        var root = new Grid { RowDefinitions = new RowDefinitions("35,*") };
        root.Children.Add(new TextBlock
        {
            Text = "Options",
            Foreground = Brushes.White,
            FontSize = 22,
            FontWeight = FontWeight.Normal,
            Margin = new Thickness(4, 4, 4, 6),
            VerticalAlignment = VerticalAlignment.Center
        });

        var options = new StackPanel
        {
            MaxWidth = 540,
            HorizontalAlignment = HorizontalAlignment.Center,
            Spacing = 2
        };
        options.Children.Add(CreateBlueOptionRow(
            "Auto-attach",
            "Start the attach flow once after the loading screen when the main UI appears.",
            false));
        options.Children.Add(CreateBlueOptionRow(
            "Play loading screen on shell change",
            "Show the Synapse Blue initialization sequence whenever this shell opens.",
            true));
        options.Children.Add(CreateBlueOptionRow(
            "Auto update",
            "Check for framework updates when Orion starts.",
            false));
        options.Children.Add(CreateBlueOptionRow(
            "Auto open",
            "Open Orion automatically after the desktop session starts.",
            false));
        options.Children.Add(CreateBlueOptionRow(
            "Clear confirmation",
            "Ask before clearing the active script or resetting every tab.",
            true));
        options.Children.Add(CreateBlueOptionRow(
            "Close tab confirmation",
            "Ask before closing a script tab when more than one tab is open.",
            true));
        options.Children.Add(CreateBlueOptionRow(
            "Resizable window",
            "Allow dragging the Synapse desktop window edges to resize it.",
            OrbitPreferences.ResizableEnabled,
            enabled =>
            {
                OrbitPreferences.SetResizable(enabled);
                CanResize = enabled;
                MaxWidth = enabled ? double.PositiveInfinity : _spec.Width;
                MaxHeight = enabled ? double.PositiveInfinity : _spec.Height;
            }));
        options.Children.Add(CreateBlueOptionRow(
            "Always on top",
            "Keep the Synapse Blue window above other windows.",
            OrbitPreferences.TopMostEnabled,
            enabled =>
            {
                OrbitPreferences.SetTopMost(enabled);
                Topmost = enabled;
            }));
        options.Children.Add(CreateBlueOptionRow(
            "Edge curve",
            "Apply the operating system edge curve to the desktop window.",
            false));
        options.Children.Add(CreateBlueOptionRow(
            "Enhanced script list",
            "Enable search, bookmarks, gists, and script row actions in the editor.",
            false));
        options.Children.Add(CreateBlueOptionRow(
            "Minimap",
            "Show a miniature preview of the entire script on the editor edge.",
            false));
        options.Children.Add(CreateBlueOptionRow(
            "Editor error logging",
            "Experimental Luau diagnostics can display false errors.",
            false));

        var returnRow = new Grid
        {
            Margin = new Thickness(4, 6),
            ColumnDefinitions = new ColumnDefinitions("*,Auto")
        };
        var returnCopy = new StackPanel { Spacing = 3 };
        returnCopy.Children.Add(new TextBlock
        {
            Text = "Orion UI",
            Foreground = Brush("#E8E8E8"),
            FontSize = 16,
            FontWeight = FontWeight.Medium
        });
        returnCopy.Children.Add(new TextBlock
        {
            Text = "Close Synapse Blue and return to Orion.",
            Foreground = Brush("#A0A0A0"),
            FontSize = 10
        });
        returnRow.Children.Add(returnCopy);
        var returnButton = CreateBlueSurfaceButton("Move to Orion UI", 126, 31, 10);
        returnButton.Click += (_, _) => ReturnWorkspaceToOrbit();
        Grid.SetColumn(returnButton, 1);
        returnRow.Children.Add(returnButton);
        options.Children.Add(returnRow);

        var scroll = new ScrollViewer
        {
            Content = options,
            Margin = new Thickness(10, 0, 10, 10),
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled
        };
        Grid.SetRow(scroll, 1);
        root.Children.Add(scroll);
        return root;
    }

    private Control CreateBlueOptionRow(
        string title,
        string description,
        bool initial,
        Action<bool>? changed = null)
    {
        var pressed = initial;
        var indicator = new Border
        {
            Width = 14,
            Height = 13,
            Background = Brush(pressed ? "#5A9E5F" : "#C0C0C0"),
            BorderBrush = Brush("#5A5A5A"),
            BorderThickness = new Thickness(1)
        };
        var toggle = new Button
        {
            Width = 14,
            Height = 13,
            Margin = new Thickness(0, 2, 0, 0),
            Padding = new Thickness(0),
            Background = Brushes.Transparent,
            BorderThickness = new Thickness(0),
            Content = indicator,
            VerticalAlignment = VerticalAlignment.Top
        };
        toggle.Click += (_, _) =>
        {
            pressed = !pressed;
            indicator.Background = Brush(pressed ? "#5A9E5F" : "#C0C0C0");
            changed?.Invoke(pressed);
        };

        var copy = new StackPanel { Spacing = 4 };
        copy.Children.Add(new TextBlock
        {
            Text = title,
            Foreground = Brush("#E8E8E8"),
            FontSize = 16,
            FontWeight = FontWeight.Medium,
            LineHeight = 18
        });
        copy.Children.Add(new TextBlock
        {
            Text = description,
            Foreground = Brush("#A0A0A0"),
            FontSize = 10,
            LineHeight = 14,
            TextWrapping = TextWrapping.Wrap
        });

        var row = new Grid
        {
            Margin = new Thickness(4, 6),
            ColumnDefinitions = new ColumnDefinitions("14,12,*")
        };
        row.Children.Add(toggle);
        Grid.SetColumn(copy, 2);
        row.Children.Add(copy);
        return row;
    }

    private Control BuildBlueThemePrototypePage()
    {
        return new Border
        {
            Background = Brush("#222222"),
            Child = new StackPanel
            {
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center,
                Spacing = 5,
                Children =
                {
                    new TextBlock
                    {
                        Text = "Theme Control Panel",
                        Foreground = Brushes.White,
                        FontSize = 22,
                        FontWeight = FontWeight.Normal,
                        HorizontalAlignment = HorizontalAlignment.Center
                    },
                    new TextBlock
                    {
                        Text = "Prototype - Not Available Yet.",
                        Foreground = Brush("#8A8A8E"),
                        FontSize = 11,
                        HorizontalAlignment = HorizontalAlignment.Center
                    }
                }
            }
        };
    }

    private static Button CreateBlueSurfaceButton(
        object content,
        double width,
        double height,
        double fontSize,
        bool attachHover = false)
    {
        var button = new Button
        {
            Width = width,
            Height = height,
            Content = content,
            Background = BlueActionBrush(),
            BorderBrush = Brush("#606060"),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(0),
            Foreground = Brush("#C3C3C3"),
            FontFamily = new FontFamily("avares://Avalonia.Fonts.Inter/Assets#Inter"),
            FontSize = fontSize,
            FontWeight = FontWeight.Normal,
            Padding = new Thickness(2, 0),
            HorizontalContentAlignment = HorizontalAlignment.Center,
            VerticalContentAlignment = VerticalAlignment.Center,
            Effect = new DropShadowEffect
            {
                Color = Colors.Black,
                BlurRadius = 4,
                OffsetY = 4,
                Opacity = .09
            }
        };
        button.PointerEntered += (_, _) => button.Background = attachHover ? BlueAttachHoverBrush() : BlueActionHoverBrush();
        button.PointerExited += (_, _) => button.Background = BlueActionBrush();
        return button;
    }

    private static string BlueHubDisplayName(BlueHubPage page) => page switch
    {
        BlueHubPage.RobloxScripts => "robloxscripts.com",
        BlueHubPage.Rscripts => "rscripts.net",
        BlueHubPage.HaxHell => "HaxHell",
        BlueHubPage.ScriptBlox => "ScriptBlox",
        _ => "Synapse Hub"
    };

    private static ScriptHubProvider ToBlueProvider(BlueHubPage page) => page switch
    {
        BlueHubPage.RobloxScripts => ScriptHubProvider.RobloxScripts,
        BlueHubPage.Rscripts => ScriptHubProvider.Rscripts,
        BlueHubPage.HaxHell => ScriptHubProvider.HaxHell,
        BlueHubPage.ScriptBlox => ScriptHubProvider.ScriptBlox,
        _ => ScriptHubProvider.RobloxScripts
    };

    private void DisposeBluePages()
    {
        _blueTooltipCancellation?.Cancel();
        _blueTooltipCancellation?.Dispose();
        _blueTooltipCancellation = null;
        _blueTooltipMotionTimer?.Stop();
        _blueTooltipMotionTimer = null;
        _bluePageCancellation?.Cancel();
        _bluePageCancellation?.Dispose();
        _bluePageCancellation = null;
        _blueHubLoadCancellation?.Cancel();
        _blueHubLoadCancellation?.Dispose();
        _blueHubLoadCancellation = null;
        if (_blueTooltipPopup is not null)
        {
            _blueTooltipPopup.IsOpen = false;
        }
        if (_blueTooltipDimPopup is not null)
        {
            _blueTooltipDimPopup.IsOpen = false;
        }
        _blueHubService.Dispose();
        foreach (var image in _blueOwnedImages)
        {
            image.Dispose();
        }
        _blueOwnedImages.Clear();
    }
}
