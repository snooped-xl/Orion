using Avalonia.Threading;

namespace OrbitAvalonia;

public sealed partial class MainWindow
{
    private XenoWindow? _xenoWindow;
    private bool _xenoReturnInProgress;

    private Task ActivateXenoUiAsync()
    {
        if (_xenoWindow is { IsVisible: true })
        {
            _xenoWindow.Activate();
            return Task.CompletedTask;
        }

        var initialWorkspace = CaptureSharedEditorWorkspace();
        HideMonaco();

        var xenoWindow = new XenoWindow(
            _monacoServer.Address,
            _editorWorkspace.ScriptsDirectory,
            initialWorkspace,
            ReturnToOrbitFromXeno);
        _xenoWindow = xenoWindow;
        xenoWindow.Show();

        // Keep Orbit alive but hidden, matching the handoff used by the other
        // preserved UI shells. Returning therefore never creates a second
        // Orbit window or races the desktop lifetime.
        Hide();
        return Task.CompletedTask;
    }

    private void ReturnToOrbitFromXeno(EditorWorkspaceState workspace)
    {
        if (_xenoReturnInProgress)
        {
            return;
        }

        _xenoReturnInProgress = true;
        Dispatcher.UIThread.Post(() =>
        {
            ApplySharedEditorWorkspace(workspace);
            var xenoWindow = _xenoWindow;
            _xenoWindow = null;
            if (xenoWindow is not null)
            {
                xenoWindow.CloseForOrbit();
            }

            Show();
            Activate();
            UpdateMonacoVisibility();
            _xenoReturnInProgress = false;
        });
    }
}
