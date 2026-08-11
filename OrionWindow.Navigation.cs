using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Media;

namespace OrbitAvalonia;

public sealed partial class OrionWindow
{
    private const double OrionNavigationPanelClosedY = -38d;
    private const double OrionNavigationPanelOpenY = 0d;
    private const double OrionNavigationArrowClosedOffsetY = 0d;
    private const double OrionNavigationArrowOpenOffsetY = 38d;
    private const double OrionNavigationArrowClosedAngle = 90d;
    private const double OrionNavigationArrowOpenAngle = -90d;

    private static readonly TimeSpan OrionNavigationOpenIntentDelay =
        TimeSpan.FromMilliseconds(220);
    private static readonly TimeSpan OrionNavigationCloseDelay =
        TimeSpan.FromMilliseconds(900);
    private static readonly TimeSpan OrionNavigationOpenDuration =
        TimeSpan.FromMilliseconds(390);
    private static readonly TimeSpan OrionNavigationCloseDuration =
        TimeSpan.FromMilliseconds(340);

    private Control _orionNavigationPanel = null!;
    private Image _orionNavigationArrow = null!;
    private Canvas _orionNavigationIndicatorHost = null!;
    private Border _orionNavigationIndicator = null!;
    private Border _orionNavigationTrigger = null!;
    private Border _orionNavigationOpenHoverArea = null!;
    private Canvas _orionNavigationButtons = null!;
    private TranslateTransform _orionNavigationPanelTranslation = null!;
    private TranslateTransform _orionNavigationIndicatorHostTranslation = null!;
    private TranslateTransform _orionNavigationArrowTranslation = null!;
    private RotateTransform _orionNavigationArrowRotation = null!;
    private CancellationTokenSource? _orionNavigationOpenDelayCancellation;
    private CancellationTokenSource? _orionNavigationCloseDelayCancellation;
    private CancellationTokenSource? _orionNavigationAnimationCancellation;
    private CancellationTokenSource? _orionNavigationIndicatorAnimationCancellation;
    private bool _orionNavigationOpen;
    private bool _orionNavigationDisposed;

    private void InitializeOrionNavigation()
    {
        _orionNavigationPanel = this.FindControl<Control>("OrionNavigationPanel")
            ?? throw new InvalidOperationException("OrionNavigationPanel was not found.");
        _orionNavigationArrow = this.FindControl<Image>("OrionNavigationArrow")
            ?? throw new InvalidOperationException("OrionNavigationArrow was not found.");
        _orionNavigationIndicatorHost = this.FindControl<Canvas>("OrionNavigationIndicatorHost")
            ?? throw new InvalidOperationException("OrionNavigationIndicatorHost was not found.");
        _orionNavigationIndicator = this.FindControl<Border>("OrionNavigationIndicator")
            ?? throw new InvalidOperationException("OrionNavigationIndicator was not found.");
        _orionNavigationTrigger = this.FindControl<Border>("OrionNavigationTrigger")
            ?? throw new InvalidOperationException("OrionNavigationTrigger was not found.");
        _orionNavigationOpenHoverArea = this.FindControl<Border>("OrionNavigationOpenHoverArea")
            ?? throw new InvalidOperationException("OrionNavigationOpenHoverArea was not found.");
        _orionNavigationButtons = this.FindControl<Canvas>("OrionNavigationButtons")
            ?? throw new InvalidOperationException("OrionNavigationButtons was not found.");

        _orionNavigationPanelTranslation =
            _orionNavigationPanel.RenderTransform as TranslateTransform
            ?? new TranslateTransform { Y = OrionNavigationPanelClosedY };
        _orionNavigationPanel.RenderTransform = _orionNavigationPanelTranslation;

        _orionNavigationIndicatorHostTranslation =
            _orionNavigationIndicatorHost.RenderTransform as TranslateTransform
            ?? new TranslateTransform { Y = OrionNavigationPanelClosedY };
        _orionNavigationIndicatorHost.RenderTransform =
            _orionNavigationIndicatorHostTranslation;

        var arrowTransforms = _orionNavigationArrow.RenderTransform as TransformGroup
            ?? throw new InvalidOperationException("The navigation arrow transform group was not found.");
        _orionNavigationArrowTranslation = arrowTransforms.Children
            .OfType<TranslateTransform>()
            .First();
        _orionNavigationArrowRotation = arrowTransforms.Children
            .OfType<RotateTransform>()
            .First();
    }

    private void OrionNavigationTrigger_PointerEntered(
        object? sender,
        PointerEventArgs e)
    {
        if (_orionNavigationDisposed)
        {
            return;
        }

        CancelOrionNavigationCloseDelay();
        QueueOrionNavigationOpen();
    }

    private void OrionNavigationTrigger_PointerExited(
        object? sender,
        PointerEventArgs e)
    {
        CancelOrionNavigationOpenDelay();
        if (_orionNavigationOpen)
        {
            QueueOrionNavigationClose();
        }
    }

    private void OrionNavigationOpenArea_PointerEntered(
        object? sender,
        PointerEventArgs e)
    {
        CancelOrionNavigationCloseDelay();
    }

    private void OrionNavigationOpenArea_PointerExited(
        object? sender,
        PointerEventArgs e)
    {
        QueueOrionNavigationClose();
    }

    private void OrionNavigationButton_PointerEntered(
        object? sender,
        PointerEventArgs e)
    {
        CancelOrionNavigationCloseDelay();
    }

    private void OrionNavigationButton_PointerExited(
        object? sender,
        PointerEventArgs e)
    {
        QueueOrionNavigationClose();
    }

    private void QueueOrionNavigationOpen()
    {
        if (_orionNavigationOpen || _orionNavigationDisposed)
        {
            return;
        }

        CancelOrionNavigationOpenDelay();
        var cancellation = new CancellationTokenSource();
        _orionNavigationOpenDelayCancellation = cancellation;
        _ = OpenOrionNavigationAfterIntentAsync(cancellation);
    }

    private async Task OpenOrionNavigationAfterIntentAsync(
        CancellationTokenSource cancellation)
    {
        try
        {
            await Task.Delay(
                OrionNavigationOpenIntentDelay,
                cancellation.Token);
            await SetOrionNavigationOpenAsync(true);
        }
        catch (OperationCanceledException)
        {
            // The pointer left the compact trigger before intent was clear.
        }
        finally
        {
            if (ReferenceEquals(_orionNavigationOpenDelayCancellation, cancellation))
            {
                _orionNavigationOpenDelayCancellation = null;
            }

            cancellation.Dispose();
        }
    }

    private void QueueOrionNavigationClose()
    {
        if (!_orionNavigationOpen || _orionNavigationDisposed)
        {
            return;
        }

        CancelOrionNavigationCloseDelay();
        var cancellation = new CancellationTokenSource();
        _orionNavigationCloseDelayCancellation = cancellation;
        _ = CloseOrionNavigationAfterDelayAsync(cancellation);
    }

    private async Task CloseOrionNavigationAfterDelayAsync(
        CancellationTokenSource cancellation)
    {
        try
        {
            await Task.Delay(OrionNavigationCloseDelay, cancellation.Token);
            await SetOrionNavigationOpenAsync(false);
        }
        catch (OperationCanceledException)
        {
            // Re-entering the buffered navigation surface keeps it open.
        }
        finally
        {
            if (ReferenceEquals(_orionNavigationCloseDelayCancellation, cancellation))
            {
                _orionNavigationCloseDelayCancellation = null;
            }

            cancellation.Dispose();
        }
    }

    private async Task SetOrionNavigationOpenAsync(bool open)
    {
        if (_orionNavigationDisposed || open == _orionNavigationOpen)
        {
            return;
        }

        CancelOrionNavigationOpenDelay();
        CancelOrionNavigationCloseDelay();
        CancelOrionNavigationAnimation();

        var cancellation = new CancellationTokenSource();
        _orionNavigationAnimationCancellation = cancellation;
        _orionNavigationOpen = open;

        if (open)
        {
            _orionNavigationPanel.IsVisible = true;
            _orionNavigationIndicatorHost.IsVisible = true;
            _orionNavigationOpenHoverArea.IsVisible = true;
            _orionNavigationOpenHoverArea.IsHitTestVisible = true;
            _orionNavigationButtons.IsHitTestVisible = true;
        }

        var startPanelY = _orionNavigationPanelTranslation.Y;
        var startPanelOpacity = _orionNavigationPanel.Opacity;
        var startIndicatorHostY = _orionNavigationIndicatorHostTranslation.Y;
        var startIndicatorHostOpacity = _orionNavigationIndicatorHost.Opacity;
        var startArrowOffsetY = _orionNavigationArrowTranslation.Y;
        var startArrowAngle = _orionNavigationArrowRotation.Angle;
        var targetPanelY = open
            ? OrionNavigationPanelOpenY
            : OrionNavigationPanelClosedY;
        var targetPanelOpacity = open ? 1d : 0d;
        var targetArrowOffsetY = open
            ? OrionNavigationArrowOpenOffsetY
            : OrionNavigationArrowClosedOffsetY;
        var targetArrowAngle = open
            ? OrionNavigationArrowOpenAngle
            : OrionNavigationArrowClosedAngle;

        try
        {
            await AnimateAsync(
                open ? OrionNavigationOpenDuration : OrionNavigationCloseDuration,
                progress =>
                {
                    _orionNavigationPanelTranslation.Y =
                        Lerp(startPanelY, targetPanelY, progress);
                    _orionNavigationPanel.Opacity =
                        Lerp(startPanelOpacity, targetPanelOpacity, progress);
                    _orionNavigationIndicatorHostTranslation.Y =
                        Lerp(startIndicatorHostY, targetPanelY, progress);
                    _orionNavigationIndicatorHost.Opacity =
                        Lerp(startIndicatorHostOpacity, targetPanelOpacity, progress);
                    _orionNavigationArrowTranslation.Y =
                        Lerp(startArrowOffsetY, targetArrowOffsetY, progress);
                    _orionNavigationArrowRotation.Angle =
                        Lerp(startArrowAngle, targetArrowAngle, progress);
                },
                OrionNavigationSmoothStep,
                cancellation.Token);

            _orionNavigationPanelTranslation.Y = targetPanelY;
            _orionNavigationPanel.Opacity = targetPanelOpacity;
            _orionNavigationIndicatorHostTranslation.Y = targetPanelY;
            _orionNavigationIndicatorHost.Opacity = targetPanelOpacity;
            _orionNavigationArrowTranslation.Y = targetArrowOffsetY;
            _orionNavigationArrowRotation.Angle = targetArrowAngle;

            if (!open)
            {
                _orionNavigationPanel.IsVisible = false;
                _orionNavigationIndicatorHost.IsVisible = false;
                _orionNavigationOpenHoverArea.IsHitTestVisible = false;
                _orionNavigationOpenHoverArea.IsVisible = false;
                _orionNavigationButtons.IsHitTestVisible = false;
                _orionNavigationTrigger.IsHitTestVisible = true;
            }
        }
        catch (OperationCanceledException)
        {
            // A reversal continues from the current interpolated values.
        }
        finally
        {
            if (ReferenceEquals(_orionNavigationAnimationCancellation, cancellation))
            {
                _orionNavigationAnimationCancellation = null;
            }

            cancellation.Dispose();
        }
    }

    private static double OrionNavigationSmoothStep(double progress) =>
        progress * progress * progress *
        (progress * ((progress * 6d) - 15d) + 10d);

    private static double OrionNavigationIndicatorLeft(int index) =>
        236d + (44d * Math.Clamp(index, 0, 4));

    private void SetOrionNavigationIndicatorImmediately(int index)
    {
        CancelOrionNavigationIndicatorAnimation();
        Canvas.SetLeft(_orionNavigationIndicator, OrionNavigationIndicatorLeft(index));
        _orionNavigationIndicator.Width = 16.667d;
    }

    private async Task AnimateOrionNavigationIndicatorAsync(int index)
    {
        if (_orionNavigationDisposed)
        {
            return;
        }

        CancelOrionNavigationIndicatorAnimation();
        var cancellation = new CancellationTokenSource();
        _orionNavigationIndicatorAnimationCancellation = cancellation;

        var startLeft = Canvas.GetLeft(_orionNavigationIndicator);
        if (double.IsNaN(startLeft))
        {
            startLeft = OrionNavigationIndicatorLeft(2);
        }

        var startWidth = _orionNavigationIndicator.Width;
        var targetLeft = OrionNavigationIndicatorLeft(index);
        var startCenter = startLeft + (startWidth / 2d);
        var targetCenter = targetLeft + (16.667d / 2d);

        try
        {
            await AnimateAsync(
                TimeSpan.FromMilliseconds(380),
                progress =>
                {
                    var width = 16.667d + (Math.Sin(progress * Math.PI) * 7d);
                    var center = Lerp(startCenter, targetCenter, progress);
                    _orionNavigationIndicator.Width = width;
                    Canvas.SetLeft(_orionNavigationIndicator, center - (width / 2d));
                },
                progress => 1d - Math.Pow(1d - progress, 4d),
                cancellation.Token);

            _orionNavigationIndicator.Width = 16.667d;
            Canvas.SetLeft(_orionNavigationIndicator, targetLeft);
        }
        catch (OperationCanceledException)
        {
            // A second route selection continues from the visible position.
        }
        finally
        {
            if (ReferenceEquals(_orionNavigationIndicatorAnimationCancellation, cancellation))
            {
                _orionNavigationIndicatorAnimationCancellation = null;
            }

            cancellation.Dispose();
        }
    }

    private void CancelOrionNavigationOpenDelay()
    {
        _orionNavigationOpenDelayCancellation?.Cancel();
        _orionNavigationOpenDelayCancellation = null;
    }

    private void CancelOrionNavigationCloseDelay()
    {
        _orionNavigationCloseDelayCancellation?.Cancel();
        _orionNavigationCloseDelayCancellation = null;
    }

    private void CancelOrionNavigationAnimation()
    {
        _orionNavigationAnimationCancellation?.Cancel();
        _orionNavigationAnimationCancellation = null;
    }

    private void CancelOrionNavigationIndicatorAnimation()
    {
        _orionNavigationIndicatorAnimationCancellation?.Cancel();
        _orionNavigationIndicatorAnimationCancellation = null;
    }

    private void DisposeOrionNavigation()
    {
        if (_orionNavigationDisposed)
        {
            return;
        }

        _orionNavigationDisposed = true;
        CancelOrionNavigationOpenDelay();
        CancelOrionNavigationCloseDelay();
        CancelOrionNavigationAnimation();
        CancelOrionNavigationIndicatorAnimation();
    }
}
