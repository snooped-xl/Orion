using Avalonia.Threading;

namespace OrbitAvalonia;

public sealed partial class MainWindow
{
    private SynapseFrontendWindow? _synapseWindow;
    private bool _synapseReturnInProgress;

    private Task ActivateSynapseUiAsync(SynapseFrontendKind kind)
    {
        if (_synapseWindow is { IsVisible: true })
        {
            _synapseWindow.Activate();
            return Task.CompletedTask;
        }

        var workspace = CaptureSharedEditorWorkspace();
        HideMonaco();
        _synapseWindow = new SynapseFrontendWindow(
            kind,
            _monacoServer.Address,
            _editorWorkspace.ScriptsDirectory,
            workspace,
            ReturnToOrbitFromSynapse);
        _synapseWindow.Show();
        Hide();
        return Task.CompletedTask;
    }

    private void ReturnToOrbitFromSynapse(EditorWorkspaceState workspace)
    {
        if (_synapseReturnInProgress)
        {
            return;
        }

        _synapseReturnInProgress = true;
        Dispatcher.UIThread.Post(() =>
        {
            ApplySharedEditorWorkspace(workspace);
            var window = _synapseWindow;
            _synapseWindow = null;
            if (window is not null)
            {
                window.CloseForOrbit();
            }

            Show();
            Activate();
            UpdateMonacoVisibility();
            _synapseReturnInProgress = false;
        });
    }
}
