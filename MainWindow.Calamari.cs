using Avalonia.Threading;

namespace OrbitAvalonia;

public sealed partial class MainWindow
{
    private CalamariWindow? _calamariWindow;
    private bool _calamariReturnInProgress;

    private Task ActivateCalamariUiAsync()
    {
        if (_calamariWindow is { IsVisible: true })
        {
            _calamariWindow.Activate();
            return Task.CompletedTask;
        }

        HideMonaco();
        var window = new CalamariWindow(ReturnToOrbitFromCalamari);
        _calamariWindow = window;
        window.Show();
        Hide();
        return Task.CompletedTask;
    }

    private void ReturnToOrbitFromCalamari()
    {
        if (_calamariReturnInProgress)
        {
            return;
        }

        _calamariReturnInProgress = true;
        Dispatcher.UIThread.Post(() =>
        {
            var window = _calamariWindow;
            _calamariWindow = null;
            if (window is not null)
            {
                window.CloseForOrbit();
            }

            Show();
            Activate();
            UpdateMonacoVisibility();
            _calamariReturnInProgress = false;
        });
    }
}
