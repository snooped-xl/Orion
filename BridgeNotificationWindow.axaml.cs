using Avalonia;
using Avalonia.Controls;
using Avalonia.Markup.Xaml;
using System.Diagnostics;
using Drawing = System.Drawing;
using Forms = System.Windows.Forms;

namespace OrbitAvalonia;

internal sealed partial class BridgeNotificationWindow : Window
{
    private static readonly TimeSpan EntranceDuration = TimeSpan.FromMilliseconds(520);
    private static readonly TimeSpan VisibleDuration = TimeSpan.FromSeconds(3);
    private static readonly TimeSpan ExitDuration = TimeSpan.FromMilliseconds(440);

    private readonly PixelRect _workingArea;
    private readonly double _screenScaling;
    private readonly int _restingX;
    private readonly int _restingY;
    private readonly int _hiddenY;

    public BridgeNotificationWindow(PixelRect workingArea, double screenScaling)
    {
        AvaloniaXamlLoader.Load(this);

        var point = new Drawing.Point(
            workingArea.X + (workingArea.Width / 2),
            workingArea.Y + (workingArea.Height / 2));
        var nativeScreen = Forms.Screen.FromPoint(point);
        var nativeWorkingArea = nativeScreen.WorkingArea;
        _workingArea = new PixelRect(
            nativeWorkingArea.X,
            nativeWorkingArea.Y,
            nativeWorkingArea.Width,
            nativeWorkingArea.Height);
        _screenScaling = Math.Max(0.5, screenScaling);

        var widthInPixels = (int)Math.Ceiling(Width * _screenScaling);
        var heightInPixels = (int)Math.Ceiling(Height * _screenScaling);
        var rightInset = (int)Math.Round(16 * _screenScaling);
        var autoHiddenTaskbarReserve = nativeWorkingArea.Bottom >= nativeScreen.Bounds.Bottom - 2
            ? 48
            : 0;
        var bottomInset = (int)Math.Round(14 * _screenScaling) + autoHiddenTaskbarReserve;

        _restingX = _workingArea.Right - widthInPixels - rightInset;
        _restingY = _workingArea.Bottom - heightInPixels - bottomInset;
        _hiddenY = _workingArea.Bottom + (int)Math.Round(10 * _screenScaling);
        Position = new PixelPoint(_restingX, _hiddenY);
    }

    public async Task PresentAsync(CancellationToken cancellationToken)
    {
        try
        {
            Position = new PixelPoint(_restingX, _hiddenY);
            Show();
            Topmost = true;

            // Wait one compositor frame so the first visible frame begins just
            // outside the monitor instead of flashing at the resting position.
            await Task.Delay(16, cancellationToken);
            await AnimatePositionAsync(
                _hiddenY,
                _restingY,
                EntranceDuration,
                QuinticEaseOut,
                cancellationToken);

            await Task.Delay(VisibleDuration, cancellationToken);

            await AnimatePositionAsync(
                _restingY,
                _hiddenY,
                ExitDuration,
                QuinticEaseIn,
                cancellationToken);
        }
        catch (OperationCanceledException)
        {
            // A reconnect or application shutdown replaced this notification.
        }
        finally
        {
            if (IsVisible)
            {
                Close();
            }
        }
    }

    private async Task AnimatePositionAsync(
        int startY,
        int targetY,
        TimeSpan duration,
        Func<double, double> easing,
        CancellationToken cancellationToken)
    {
        var stopwatch = Stopwatch.StartNew();
        while (stopwatch.Elapsed < duration)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var progress = Math.Clamp(
                stopwatch.Elapsed.TotalMilliseconds / duration.TotalMilliseconds,
                0,
                1);
            var eased = easing(progress);
            Position = new PixelPoint(
                _restingX,
                (int)Math.Round(startY + ((targetY - startY) * eased)));
            await Task.Delay(16, cancellationToken);
        }

        Position = new PixelPoint(_restingX, targetY);
    }

    private static double QuinticEaseOut(double progress) =>
        1 - Math.Pow(1 - progress, 5);

    private static double QuinticEaseIn(double progress) =>
        Math.Pow(progress, 5);
}
