using Avalonia.Controls;
using Avalonia.Media;
using Avalonia.Threading;
using ShapePath = Avalonia.Controls.Shapes.Path;

namespace OrbitAvalonia;

public sealed partial class MainWindow
{
    private BridgeNotificationWindow? _bridgeNotificationWindow;
    private CancellationTokenSource? _bridgeNotificationCancellation;

    private void MainWindowBridgeConnectionChanged(bool connected) =>
        Dispatcher.UIThread.Post(() => ApplyMainWindowBridgeConnection(connected));

    private void ApplyMainWindowBridgeConnection(bool connected)
    {
        ApplyMainWindowBridgeState(connected);
    }

    private void ApplyMainWindowBridgeState(bool connected)
    {
        _bridgeConnected = connected;
        _executeActionButton.IsEnabled = connected;
        _executeActionButton.Opacity = connected ? 1 : .62;
        ToolTip.SetTip(_executeActionButton, connected
            ? "Execute"
            : "Execute (run Scripts/Orion Bridge.lua first)");
        if (_executeActionIcon.Child is ShapePath icon)
        {
            icon.Fill = connected ? BrushFrom("#7D7D80") : BrushFrom("#393C40");
        }
    }

    private void ExecuteAction_Click(object? sender, Avalonia.Interactivity.RoutedEventArgs e)
    {
        if (!_bridgeConnected || _activeEditorTab is null)
        {
            return;
        }

        if (_monacoReady)
        {
            try
            {
                // Monaco sends the model value back in an executeRequested
                // message. This bypasses the normal 90 ms edit debounce.
                _monacoWebView.InvokeScript("window.orbitRequestExecute && window.orbitRequestExecute();");
                return;
            }
            catch (InvalidOperationException)
            {
                _monacoReady = false;
            }
        }

        _bridgeServer.EnqueueExecute(_activeEditorTab.Content);
    }

    private void ShowBridgeConnectedNotification()
    {
        _bridgeNotificationCancellation?.Cancel();
        _bridgeNotificationCancellation?.Dispose();
        _bridgeNotificationCancellation = new CancellationTokenSource();

        if (_bridgeNotificationWindow is { IsVisible: true } previousWindow)
        {
            previousWindow.Close();
        }

        var screen = Screens.ScreenFromWindow(this) ?? Screens.Primary;
        if (screen is null)
        {
            return;
        }

        var notification = new BridgeNotificationWindow(screen.WorkingArea, screen.Scaling);
        _bridgeNotificationWindow = notification;
        _ = PresentBridgeConnectedNotificationAsync(
            notification,
            _bridgeNotificationCancellation.Token);
    }

    private async Task PresentBridgeConnectedNotificationAsync(
        BridgeNotificationWindow notification,
        CancellationToken cancellationToken)
    {
        await notification.PresentAsync(cancellationToken);
        if (ReferenceEquals(_bridgeNotificationWindow, notification))
        {
            _bridgeNotificationWindow = null;
        }
    }

    private void DisposeBridgeConnectedNotification()
    {
        _bridgeNotificationCancellation?.Cancel();
        _bridgeNotificationCancellation?.Dispose();
        _bridgeNotificationCancellation = null;

        if (_bridgeNotificationWindow is { IsVisible: true } notification)
        {
            notification.Close();
        }
        _bridgeNotificationWindow = null;
    }
}
