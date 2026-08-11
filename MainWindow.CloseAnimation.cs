using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Threading;

namespace OrbitAvalonia;

public sealed partial class MainWindow
{
    private static readonly TimeSpan CloseFadeDuration = TimeSpan.FromMilliseconds(300);
    private static readonly TimeSpan CloseMorphDuration = TimeSpan.FromMilliseconds(700);

    private CancellationTokenSource? _closeAnimationCancellation;
    private Border _closeAnimationBackdrop = null!;
    private bool _closeAnimationRunning;
    private bool _allowImmediateClose;
    private bool _returnToOrionOnClose;

    internal void EnableReturnToOrionOnClose() => _returnToOrionOnClose = true;

    private void InitializeCloseAnimation()
    {
        _closeAnimationBackdrop = this.FindControl<Border>("CloseAnimationBackdrop") ?? new Border();
    }

    protected override void OnClosing(WindowClosingEventArgs e)
    {
        if (_allowImmediateClose || e.CloseReason == WindowCloseReason.OSShutdown)
        {
            base.OnClosing(e);
            return;
        }

        base.OnClosing(e);
        e.Cancel = true;

        if (!_closeAnimationRunning)
        {
            _ = RunCloseAnimationAsync();
        }
    }

    private async Task RunCloseAnimationAsync()
    {
        _closeAnimationRunning = true;
        IsEnabled = false;
        HideMonaco();
        Opacity = 1;
        _closeAnimationBackdrop.IsVisible = true;
        _closeAnimationBackdrop.Opacity = 1;

        _startupCancellation.Cancel();
        _pageTransitionCancellation?.Cancel();
        _settingsTabAnimationCancellation?.Cancel();
        _setupPrototypeAnimationCancellation?.Cancel();
        _gistDialogAnimationCancellation?.Cancel();
        _scriptBloxWarningAnimationCancellation?.Cancel();
        _resizeTabsWarningAnimationCancellation?.Cancel();
        CancelEditorTabMotions();
        ReleaseSmoothWindowMotion();
        _windowMotionTimer.Stop();
        CancelWindowBoundsAnimation();

        _closeAnimationCancellation?.Cancel();
        _closeAnimationCancellation?.Dispose();
        _closeAnimationCancellation = new CancellationTokenSource();
        var cancellationToken = _closeAnimationCancellation.Token;

        try
        {
            if (!SystemAnimationsEnabled())
            {
                CompleteAnimatedClose();
                return;
            }

            var startMainOpacity = _mainInterface.Opacity;
            var startLoadingOpacity = _loadingInterface.Opacity;
            var startSetupOpacity = _setupPrototypeInterface.Opacity;
            await AnimateAsync(
                CloseFadeDuration,
                progress =>
                {
                    _mainInterface.Opacity = Lerp(startMainOpacity, 0, progress);
                    _loadingInterface.Opacity = Lerp(startLoadingOpacity, 0, progress);
                    _setupPrototypeInterface.Opacity = Lerp(startSetupOpacity, 0, progress);
                },
                CubicEaseInOut,
                cancellationToken);

            _mainInterface.Opacity = 0;
            _loadingInterface.Opacity = 0;
            _setupPrototypeInterface.Opacity = 0;

            var scaling = Screens.ScreenFromWindow(this)?.Scaling ?? 1;
            var startPosition = Position;
            var startSize = Bounds.Size;
            var centreX = startPosition.X + (startSize.Width * scaling / 2);
            var centreY = startPosition.Y + (startSize.Height * scaling / 2);
            var targetLogicalPixel = 1 / scaling;
            var targetPosition = new PixelPoint(
                (int)Math.Round(centreX - 0.5),
                (int)Math.Round(centreY - 0.5));

            if (WindowState != WindowState.Normal)
            {
                WindowState = WindowState.Normal;
                Width = startSize.Width;
                Height = startSize.Height;
                Position = startPosition;
            }

            _animatedMaximized = false;
            _applyingResponsiveSize = true;
            CanResize = false;
            MinWidth = targetLogicalPixel;
            MinHeight = targetLogicalPixel;

            await AnimateAsync(
                CloseMorphDuration,
                progress =>
                {
                    var width = Lerp(startSize.Width, targetLogicalPixel, progress);
                    var height = Lerp(startSize.Height, targetLogicalPixel, progress);
                    Width = width;
                    Height = height;
                    Position = new PixelPoint(
                        (int)Math.Round(centreX - (width * scaling / 2)),
                        (int)Math.Round(centreY - (height * scaling / 2)));
                },
                CubicEaseInOut,
                cancellationToken);

            Width = targetLogicalPixel;
            Height = targetLogicalPixel;
            Position = targetPosition;
            CompleteAnimatedClose();
        }
        catch (OperationCanceledException)
        {
            CompleteAnimatedClose();
        }
        catch
        {
            CompleteAnimatedClose();
        }
    }

    private void CompleteAnimatedClose()
    {
        if (_allowImmediateClose)
        {
            return;
        }

        _allowImmediateClose = true;
        Dispatcher.UIThread.Post(
            () =>
            {
                if (_returnToOrionOnClose)
                {
                    Close();
                }
                else if (Application.Current?.ApplicationLifetime is
                    IClassicDesktopStyleApplicationLifetime desktopLifetime)
                {
                    desktopLifetime.Shutdown();
                }
                else
                {
                    Close();
                }
            },
            DispatcherPriority.Send);
    }
}
