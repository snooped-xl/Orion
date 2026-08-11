using Avalonia.Controls.ApplicationLifetimes;
using Forms = System.Windows.Forms;

namespace OrbitAvalonia;

public sealed partial class MainWindow
{
    private Task ActivateRc7UiAsync()
    {
        if (Avalonia.Application.Current?.ApplicationLifetime is not
            IClassicDesktopStyleApplicationLifetime desktop)
        {
            return Task.CompletedTask;
        }

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

        var legacyThread = new Thread(() =>
        {
            Forms.Application.EnableVisualStyles();
            Forms.Application.SetCompatibleTextRenderingDefault(false);
            try
            {
                using var legacyWindow = new Rc7LegacyWindow(initialWorkspace, RestoreOrbit);
                Forms.Application.Run(legacyWindow);
            }
            catch
            {
                // If WinForms cannot create the preservation window, return the
                // Avalonia shell instead of leaving the desktop hidden.
                RestoreOrbit(initialWorkspace);
            }
        })
        {
            IsBackground = false,
            Name = "RC7 UI"
        };
        legacyThread.SetApartmentState(ApartmentState.STA);
        // Keep the original Orbit shell alive but hidden. Returning to it is
        // then a deterministic show/activate operation with no desktop-lifetime
        // race or duplicate MainWindow to be torn down.
        Hide();
        legacyThread.Start();
        return Task.CompletedTask;
    }
}
