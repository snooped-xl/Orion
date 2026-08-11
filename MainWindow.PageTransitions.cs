using Avalonia.Controls;
using Avalonia.Media;
using ShapePath = Avalonia.Controls.Shapes.Path;

namespace OrbitAvalonia;

public sealed partial class MainWindow
{
    private const double PageSlideDistance = 42;
    private static readonly TimeSpan PageExitDuration = TimeSpan.FromMilliseconds(150);
    private static readonly TimeSpan PageEnterDuration = TimeSpan.FromMilliseconds(220);

    private Canvas _editorPage = null!;
    private readonly Dictionary<AppPage, TranslateTransform> _pageTranslations = [];
    private readonly Dictionary<AppPage, TranslateTransform> _navigationPageTranslations = [];
    private CancellationTokenSource? _pageTransitionCancellation;
    private AppPage? _pageTransitionTarget;
    private AppPage _requestedPage = AppPage.Editor;
    private bool _startupCompleted;
    private bool _monacoSourceAssigned;

    private void InitializePageTransitions()
    {
        _editorPage = this.FindControl<Canvas>("EditorPage") ?? new Canvas();

        foreach (var page in Enum.GetValues<AppPage>())
        {
            var navigationTranslation = new TranslateTransform();
            var transitionTranslation = new TranslateTransform();
            var transformGroup = new TransformGroup();
            transformGroup.Children.Add(navigationTranslation);
            transformGroup.Children.Add(transitionTranslation);
            PageControl(page).RenderTransform = transformGroup;
            _navigationPageTranslations[page] = navigationTranslation;
            _pageTranslations[page] = transitionTranslation;
        }
    }

    private void SetPage(AppPage page)
    {
        _requestedPage = page;
        UpdatePageNavigationVisuals(page);

        if (!_startupCompleted)
        {
            return;
        }

        _ = NavigateToPageAsync(page);
    }

    private AppPage RequestedStartupPage() => _requestedPage;

    private async Task NavigateToPageAsync(AppPage targetPage)
    {
        if (_pageTransitionTarget == targetPage ||
            (_pageTransitionTarget is null && targetPage == _currentPage))
        {
            return;
        }

        if (_pageTransitionTarget is not null && targetPage == _currentPage)
        {
            _pageTransitionCancellation?.Cancel();
            _pageTransitionCancellation?.Dispose();
            _pageTransitionCancellation = null;
            _pageTransitionTarget = null;
            NormalizeVisiblePage(_currentPage);
            UpdatePageNavigationVisuals(_currentPage);
            return;
        }

        _pageTransitionCancellation?.Cancel();
        _pageTransitionCancellation?.Dispose();
        _pageTransitionCancellation = new CancellationTokenSource();
        var cancellation = _pageTransitionCancellation;
        var cancellationToken = cancellation.Token;
        _pageTransitionTarget = targetPage;

        try
        {
            var outgoingPage = _currentPage;
            NormalizeVisiblePage(outgoingPage);
            UpdatePageNavigationVisuals(targetPage);

            if (SystemAnimationsEnabled())
            {
                await AnimatePageOutAsync(outgoingPage, cancellationToken);
            }

            SetPageVisible(outgoingPage, false);

            _currentPage = targetPage;
            PreparePageEntrance(targetPage);

            if (SystemAnimationsEnabled())
            {
                await AnimatePageInAsync(targetPage, cancellationToken);
            }

            CompletePageEntrance(targetPage);
        }
        catch (OperationCanceledException)
        {
            if (ReferenceEquals(_pageTransitionCancellation, cancellation))
            {
                NormalizeVisiblePage(_currentPage);
                UpdatePageNavigationVisuals(_currentPage);
            }
        }
        finally
        {
            if (ReferenceEquals(_pageTransitionCancellation, cancellation))
            {
                _pageTransitionTarget = null;
                _pageTransitionCancellation = null;
                cancellation.Dispose();
            }
        }
    }

    private async Task AnimatePageOutAsync(
        AppPage page,
        CancellationToken cancellationToken)
    {
        var translation = _pageTranslations[page];
        var startX = translation.X;
        var startOpacity = PageControl(page).Opacity;

        SetPageHitTesting(page, false);
        await AnimateAsync(
            PageExitDuration,
            progress =>
            {
                translation.X = Lerp(startX, PageSlideDistance, progress);
                PageControl(page).Opacity = Lerp(startOpacity, 0, progress);
            },
            CubicEaseIn,
            cancellationToken);
    }

    private async Task AnimatePageInAsync(
        AppPage page,
        CancellationToken cancellationToken)
    {
        var translation = _pageTranslations[page];
        await AnimateAsync(
            PageEnterDuration,
            progress =>
            {
                translation.X = Lerp(PageSlideDistance, 0, progress);
                PageControl(page).Opacity = progress;
            },
            CubicEaseOut,
            cancellationToken);
    }

    private async Task AnimateInitialPageInAsync(
        AppPage page,
        CancellationToken cancellationToken)
    {
        await Task.Delay(TimeSpan.FromMilliseconds(390), cancellationToken);
        await AnimatePageInAsync(page, cancellationToken);
    }

    private void PreparePageEntrance(AppPage page)
    {
        foreach (var candidate in Enum.GetValues<AppPage>())
        {
            if (candidate == page)
            {
                continue;
            }

            SetPageVisible(candidate, false);
        }

        var translation = _pageTranslations[page];
        translation.X = SystemAnimationsEnabled() ? PageSlideDistance : 0;
        PageControl(page).Opacity = SystemAnimationsEnabled() ? 0 : 1;
        SetPageVisible(page, true);
        SetPageHitTesting(page, true);
    }

    private void CompletePageEntrance(AppPage page)
    {
        var translation = _pageTranslations[page];
        translation.X = 0;
        PageControl(page).Opacity = 1;
        SetPageVisible(page, true);
        SetPageHitTesting(page, true);
    }

    private void NormalizeVisiblePage(AppPage page)
    {
        foreach (var candidate in Enum.GetValues<AppPage>())
        {
            var isTarget = candidate == page;
            SetPageVisible(candidate, isTarget);
            SetPageHitTesting(candidate, isTarget);
            var translation = _pageTranslations[candidate];
            translation.X = 0;
            PageControl(candidate).Opacity = isTarget ? 1 : 0;
        }
    }

    private void UpdatePageNavigationVisuals(AppPage page)
    {
        if (this.FindControl<Avalonia.Controls.Shapes.Path>("TopNavIndicator") is { } indicator)
        {
            double left = page switch
            {
                AppPage.Plugins => 255,
                AppPage.Settings => 287,
                AppPage.Editor => 319,
                AppPage.Themes => 351,
                AppPage.ScriptHub => 383,
                _ => 319
            };
            Canvas.SetLeft(indicator, left);
        }
    }

    private Control PageControl(AppPage page) => page switch
    {
        AppPage.Editor => _editorPage,
        AppPage.ScriptHub => _scriptHubPage,
        AppPage.Robot => _robotPage,
        AppPage.Themes => _themesPage,
        AppPage.Plugins => _pluginsPage,
        AppPage.Settings => _settingsPage,
        _ => throw new ArgumentOutOfRangeException(nameof(page), page, null)
    };

    private void SetPageVisible(AppPage page, bool isVisible)
    {
        PageControl(page).IsVisible = isVisible;
    }

    private void UpdateMonacoVisibility() { }

    private void HideMonaco() { }

    private void SetPageHitTesting(AppPage page, bool isEnabled) =>
        PageControl(page).IsHitTestVisible = isEnabled;
}
