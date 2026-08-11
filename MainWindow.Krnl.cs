using Avalonia.Controls.ApplicationLifetimes;
using Forms = System.Windows.Forms;

namespace OrbitAvalonia;

public sealed partial class MainWindow
{
    private Task ActivateKrnlUiAsync()
    {
        if (Avalonia.Application.Current?.ApplicationLifetime is not IClassicDesktopStyleApplicationLifetime desktop)
            return Task.CompletedTask;
        var initialWorkspace = CaptureSharedEditorWorkspace();
        HideMonaco();

        void RestoreOrbit(EditorWorkspaceState workspace)
        {
            Avalonia.Threading.Dispatcher.UIThread.Post(() =>
            {
                ApplySharedEditorWorkspace(workspace);
                Show();
                Activate();
                UpdateMonacoVisibility();
            });
        }
        var thread = new Thread(() =>
        {
            Forms.Application.EnableVisualStyles();
            Forms.Application.SetCompatibleTextRenderingDefault(false);
            try
            {
                using var window = new KrnlLegacyWindow(initialWorkspace, RestoreOrbit);
                Forms.Application.Run(window);
            }
            catch
            {
                // Keep the Orbit shell recoverable if a platform-specific legacy
                // control fails to initialize on a particular machine.
                RestoreOrbit(initialWorkspace);
            }
        }) { IsBackground = false, Name = "Krnl UI" };
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        Hide();
        return Task.CompletedTask;
    }
}
