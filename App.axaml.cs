using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Markup.Xaml;

namespace OrbitAvalonia;

public sealed partial class App : Application
{
    private BridgeNotificationService? _bridgeNotifications;

    public override void Initialize() => AvaloniaXamlLoader.Load(this);

    public override void OnFrameworkInitializationCompleted()
    {
        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
        {
            desktop.ShutdownMode = ShutdownMode.OnLastWindowClose;
            desktop.MainWindow = new OrionWindow(OrbitPreferences.LastInterface);
            _bridgeNotifications = new BridgeNotificationService(desktop);
            desktop.Exit += (_, _) =>
            {
                _bridgeNotifications?.Dispose();
                _bridgeNotifications = null;
            };
        }

        base.OnFrameworkInitializationCompleted();
    }
}
