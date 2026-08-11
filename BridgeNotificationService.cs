using Avalonia.Controls;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Threading;

namespace OrbitAvalonia;

internal sealed class BridgeNotificationService : IDisposable
{
    private readonly IClassicDesktopStyleApplicationLifetime _desktop;
    private readonly UnifiedBridgeServer _bridge = UnifiedBridgeServer.Shared;
    private BridgeNotificationWindow? _window;
    private CancellationTokenSource? _presentationCancellation;
    private bool _disposed;

    public BridgeNotificationService(IClassicDesktopStyleApplicationLifetime desktop)
    {
        _desktop = desktop;
        _bridge.ConnectionChanged += BridgeConnectionChanged;
        if (_bridge.IsConnected) Dispatcher.UIThread.Post(ShowNotification);
    }

    private void BridgeConnectionChanged(bool connected)
    {
        if (!connected || _disposed) return;
        Dispatcher.UIThread.Post(ShowNotification);
    }

    private void ShowNotification()
    {
        if (_disposed) return;
        try
        {
            var host = _desktop.Windows.FirstOrDefault(window => window.IsActive)
                ?? _desktop.Windows.FirstOrDefault(window => window.IsVisible)
                ?? _desktop.MainWindow;
            var screen = host is null
                ? null
                : host.Screens.ScreenFromWindow(host) ?? host.Screens.Primary;
            if (screen is null) return;

            _presentationCancellation?.Cancel();
            _presentationCancellation?.Dispose();
            _presentationCancellation = new CancellationTokenSource();

            if (_window is { IsVisible: true } existing)
            {
                existing.Close();
            }

            var notification = new BridgeNotificationWindow(screen.WorkingArea, screen.Scaling);
            _window = notification;
            _ = PresentAsync(notification, _presentationCancellation.Token);
        }
        catch
        {
            _window = null;
        }
    }

    private async Task PresentAsync(
        BridgeNotificationWindow notification,
        CancellationToken cancellationToken)
    {
        try
        {
            await notification.PresentAsync(cancellationToken);
        }
        catch
        {
            if (notification.IsVisible) notification.Close();
        }
        if (ReferenceEquals(_window, notification)) _window = null;
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        _bridge.ConnectionChanged -= BridgeConnectionChanged;
        _presentationCancellation?.Cancel();
        _presentationCancellation?.Dispose();
        _presentationCancellation = null;
        if (_window is { IsVisible: true }) _window.Close();
        _window = null;
    }
}
