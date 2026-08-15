using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Markup.Xaml;
using Avalonia.Threading;
using System;
using System.Diagnostics;

namespace OrbitAvalonia;

public sealed partial class App : Application
{
    private BridgeNotificationService? _bridgeNotifications;
    private OrionPluginHost? _pluginHost;
    private bool _ownedServicesStopped;

    public override void Initialize() => AvaloniaXamlLoader.Load(this);

    public override void OnFrameworkInitializationCompleted()
    {
        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
        {
            // Orion keeps its main workspace window hidden while a preserved UI
            // is active. Notifications and companion windows must never become
            // accidental process owners after that main workspace is closed.
            desktop.ShutdownMode = ShutdownMode.OnMainWindowClose;
            var mainWindow = new OrionWindow(OrbitPreferences.LastInterface);
            desktop.MainWindow = mainWindow;
            _pluginHost = new OrionPluginHost(desktop, mainWindow);
            mainWindow.AttachOrionPluginHost(_pluginHost);
            Dispatcher.UIThread.Post(async () =>
            {
                try
                {
                    if (_pluginHost is not null)
                    {
                        await _pluginHost.InitializeAsync();
                    }
                }
                catch (Exception exception)
                {
                    Debug.WriteLine($"Orion plugin host failed to initialize: {exception}");
                }
            });
            _bridgeNotifications = new BridgeNotificationService(desktop);
            mainWindow.Closed += (_, _) => StopOwnedServices();
            desktop.ShutdownRequested += (_, _) => StopOwnedServices();
            desktop.Exit += (_, _) => StopOwnedServices();
        }

        base.OnFrameworkInitializationCompleted();
    }

    private void StopOwnedServices()
    {
        if (_ownedServicesStopped)
        {
            return;
        }

        _ownedServicesStopped = true;
        _pluginHost?.Dispose();
        _pluginHost = null;
        _bridgeNotifications?.Dispose();
        _bridgeNotifications = null;
        UnifiedBridgeServer.ShutdownShared();
    }
}
