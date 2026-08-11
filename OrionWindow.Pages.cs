using Avalonia.Controls;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Interactivity;
using Avalonia.Media;
using Avalonia.Rendering.Composition;
using Avalonia.Threading;
using System.Numerics;
using Forms = System.Windows.Forms;

namespace OrbitAvalonia;

public sealed partial class OrionWindow
{
    private enum OrionPage
    {
        Editor,
        Settings,
        UiSelection,
        Plugins,
        Themes,
        ScriptHub
    }

    private static readonly TimeSpan OrionPageExitDuration =
        TimeSpan.FromMilliseconds(440);
    private static readonly TimeSpan OrionPageEnterDuration =
        TimeSpan.FromMilliseconds(480);

    private Canvas _orionEditorPage = null!;
    private Canvas _orionSettingsPage = null!;
    private Canvas _orionUiSelectionPage = null!;
    private Canvas _orionPluginsPage = null!;
    private Canvas _orionThemesPage = null!;
    private Canvas _orionScriptHubPage = null!;
    private TextBlock _orionTopMostText = null!;
    private OrionPage _orionCurrentPage = OrionPage.Editor;
    private bool _orionPageTransitionActive;
    private bool _orionPagesDisposed;
    private Window? _orionPreservedWindow;
    private bool _orionInterfaceHandoffActive;
    private bool _orionInterfaceReturnActive;

    private void InitializeOrionPages()
    {
        _orionEditorPage = this.FindControl<Canvas>("OrionEditorPage")
            ?? throw new InvalidOperationException("OrionEditorPage was not found.");
        _orionSettingsPage = this.FindControl<Canvas>("OrionSettingsPage")
            ?? throw new InvalidOperationException("OrionSettingsPage was not found.");
        _orionUiSelectionPage = this.FindControl<Canvas>("OrionUiSelectionPage")
            ?? throw new InvalidOperationException("OrionUiSelectionPage was not found.");
        _orionPluginsPage = this.FindControl<Canvas>("OrionPluginsPage")
            ?? throw new InvalidOperationException("OrionPluginsPage was not found.");
        _orionThemesPage = this.FindControl<Canvas>("OrionThemesPage")
            ?? throw new InvalidOperationException("OrionThemesPage was not found.");
        _orionScriptHubPage = this.FindControl<Canvas>("OrionScriptHubPage")
            ?? throw new InvalidOperationException("OrionScriptHubPage was not found.");
        _orionTopMostText = this.FindControl<TextBlock>("OrionTopMostText")
            ?? throw new InvalidOperationException("OrionTopMostText was not found.");

        // Make startup deterministic even when Avalonia restores a compositor
        // snapshot while the window is completing its loading morph.
        ShowOrionPageImmediately(OrionPage.Editor);
        UpdateOrionTopMostVisual();
    }

    private async void OrionEditorNavigation_Click(object? sender, RoutedEventArgs e)
    {
        await SwitchOrionPageAsync(OrionPage.Editor);
    }

    private async void OrionPluginsNavigation_Click(object? sender, RoutedEventArgs e)
    {
        await SwitchOrionPageAsync(OrionPage.Plugins);
    }

    private async void OrionSettingsNavigation_Click(object? sender, RoutedEventArgs e)
    {
        // Selecting Settings while already inside a settings sub-page returns
        // to the settings home, making the top navigation the consistent back.
        await SwitchOrionPageAsync(OrionPage.Settings);
    }

    private async void OrionThemesNavigation_Click(object? sender, RoutedEventArgs e)
    {
        await SwitchOrionPageAsync(OrionPage.Themes);
    }

    private async void OrionScriptHubNavigation_Click(object? sender, RoutedEventArgs e)
    {
        await SwitchOrionPageAsync(OrionPage.ScriptHub);
    }

    private async void OrionUiSelectionCard_Click(object? sender, RoutedEventArgs e)
    {
        await SwitchOrionPageAsync(OrionPage.UiSelection);
    }

    private async void OrionUiChoice_Click(object? sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: string selection })
        {
            return;
        }

        await LaunchSelectedOrionInterfaceAsync(selection);
    }

    private void OrionTopMost_Click(object? sender, RoutedEventArgs e)
    {
        Topmost = !Topmost;
        UpdateOrionTopMostVisual();
    }

    private void UpdateOrionTopMostVisual()
    {
        _orionTopMostText.Foreground = new SolidColorBrush(
            Color.Parse(Topmost ? "#FFFFFF" : "#FF4C4C"));
    }

    private async Task SwitchOrionPageAsync(OrionPage target)
    {
        if (_orionPagesDisposed || _orionPageTransitionActive)
        {
            return;
        }

        if (target == _orionCurrentPage)
        {
            await AnimateOrionNavigationIndicatorAsync(
                NavigationIndexForOrionPage(target));
            QueueOrionNavigationClose();
            return;
        }

        _orionPageTransitionActive = true;
        CancelOrionNavigationCloseDelay();

        var outgoing = ControlForOrionPage(_orionCurrentPage);
        var incoming = ControlForOrionPage(target);
        var indicatorAnimation = AnimateOrionNavigationIndicatorAsync(
            NavigationIndexForOrionPage(target));

        if (_orionCurrentPage == OrionPage.Editor)
        {
            // NativeWebView is a child HWND, so it must be hidden before the
            // compositor animates the native Avalonia page above it.
            _orionMonacoWebView.IsVisible = false;
        }

        ResetOrionPageComposition(outgoing, true);
        ResetOrionPageComposition(incoming, false);
        incoming.IsVisible = false;
        incoming.IsHitTestVisible = false;

        try
        {
            // Complete the outgoing movement before exposing the new page.
            // This keeps both pages fully opaque without letting the previous
            // page show through the transparent glass surfaces of the next.
            await AnimateOrionPageTranslationAsync(
                outgoing,
                fromY: 0,
                toY: 413.333,
                OrionPageExitDuration);

            ResetOrionPageComposition(outgoing, false);
            outgoing.IsVisible = false;
            outgoing.IsHitTestVisible = false;

            ResetOrionPageComposition(incoming, true);
            incoming.IsVisible = true;
            incoming.IsHitTestVisible = false;
            await AnimateOrionPageTranslationAsync(
                incoming,
                fromY: 413.333,
                toY: 0,
                OrionPageEnterDuration);

            ResetOrionPageComposition(outgoing, false);
            ResetOrionPageComposition(incoming, true);
            outgoing.IsVisible = false;
            outgoing.IsHitTestVisible = false;
            incoming.IsVisible = true;
            incoming.IsHitTestVisible = true;
            _orionCurrentPage = target;

            if (target == OrionPage.Editor)
            {
                await RevealOrionEditorAfterPageTransitionAsync();
            }

            await indicatorAnimation;
            QueueOrionNavigationClose();
        }
        finally
        {
            _orionPageTransitionActive = false;
        }
    }

    private Canvas ControlForOrionPage(OrionPage page) => page switch
    {
        OrionPage.Editor => _orionEditorPage,
        OrionPage.Settings => _orionSettingsPage,
        OrionPage.UiSelection => _orionUiSelectionPage,
        OrionPage.Plugins => _orionPluginsPage,
        OrionPage.Themes => _orionThemesPage,
        OrionPage.ScriptHub => _orionScriptHubPage,
        _ => _orionEditorPage
    };

    private static int NavigationIndexForOrionPage(OrionPage page) => page switch
    {
        OrionPage.Plugins => 0,
        OrionPage.Settings or OrionPage.UiSelection => 1,
        OrionPage.Editor => 2,
        OrionPage.Themes => 3,
        OrionPage.ScriptHub => 4,
        _ => 2
    };

    private static void ResetOrionPageComposition(Control control, bool selected)
    {
        StopOrionPageComposition(control);
        if (ElementComposition.GetElementVisual(control) is { } visual)
        {
            visual.Offset = Vector3.Zero;
            visual.Opacity = selected ? 1 : 0;
        }

        control.Opacity = selected ? 1 : 0;
        control.RenderTransform = null;
    }

    private async Task RevealOrionEditorAfterPageTransitionAsync()
    {
        RevealOrionEditor();
        await Task.Delay(24);

        if (!_orionMonacoReady || _orionCurrentPage != OrionPage.Editor)
        {
            return;
        }

        try
        {
            await _orionMonacoWebView.InvokeScript(
                "window.orionLayout && window.orionLayout();");
            PushOrionActiveTabToMonaco();
        }
        catch (InvalidOperationException)
        {
            _orionMonacoReady = false;
        }
    }

    private async Task AnimateOrionPageTranslationAsync(
        Control control,
        double fromY,
        double toY,
        TimeSpan duration)
    {
        // A regular render transform survives native-window hide/show cycles
        // deterministically. Composition animations can retain a detached
        // terminal offset after another UI hides Orion, which is what left
        // Monaco visible over an apparently empty window on return.
        StopOrionPageComposition(control);
        var translation = new TranslateTransform { Y = fromY };
        control.RenderTransform = translation;
        control.Opacity = 1;

        await AnimateAsync(
            duration,
            progress => translation.Y = Lerp(fromY, toY, progress),
            CubicEaseInOut,
            _orionEditorCancellation.Token);

        translation.Y = toY;
    }

    private static void StopOrionPageComposition(Control control)
    {
        var visual = ElementComposition.GetElementVisual(control);
        if (visual is null)
        {
            return;
        }

        visual.StopAnimation("Offset");
        visual.StopAnimation("Opacity");
    }

    private async Task LaunchSelectedOrionInterfaceAsync(string selection)
    {
        if (_orionInterfaceHandoffActive)
        {
            return;
        }

        _orionInterfaceHandoffActive = true;
        var workspace = await CaptureOrionWorkspaceAsync();
        _orionMonacoWebView.IsVisible = false;
        OrbitPreferences.SetLastInterface(selection);

        try
        {
            switch (selection)
            {
                case "SynapseV3":
                    ShowPreservedAvaloniaWindow(new SynapseFrontendWindow(
                        SynapseFrontendKind.V3,
                        _orionMonacoServer.Address,
                        _orionWorkspace.ScriptsDirectory,
                        workspace,
                        RestoreOrionWorkspace));
                    break;
                case "Synapse2017":
                    ShowPreservedAvaloniaWindow(new SynapseFrontendWindow(
                        SynapseFrontendKind.Classic2017,
                        _orionMonacoServer.Address,
                        _orionWorkspace.ScriptsDirectory,
                        workspace,
                        RestoreOrionWorkspace));
                    break;
                case "SynapseBlue":
                    ShowPreservedAvaloniaWindow(new SynapseFrontendWindow(
                        SynapseFrontendKind.Blue,
                        _orionMonacoServer.Address,
                        _orionWorkspace.ScriptsDirectory,
                        workspace,
                        RestoreOrionWorkspace));
                    break;
                case "SynapseX":
                    ShowPreservedAvaloniaWindow(new SynapseFrontendWindow(
                        SynapseFrontendKind.SynapseX,
                        _orionMonacoServer.Address,
                        _orionWorkspace.ScriptsDirectory,
                        workspace,
                        RestoreOrionWorkspace));
                    break;
                case "Xeno":
                    ShowPreservedAvaloniaWindow(new XenoWindow(
                        _orionMonacoServer.Address,
                        _orionWorkspace.ScriptsDirectory,
                        workspace,
                        RestoreOrionWorkspace));
                    break;
                case "Calamari":
                    ShowPreservedAvaloniaWindow(new CalamariWindow(
                        () => RestoreOrionWorkspace(workspace)));
                    break;
                case "AWP":
                    ShowPreservedAvaloniaWindow(new AWPWindow(
                        _orionWorkspace.ScriptsDirectory,
                        workspace,
                        _orionMonacoServer.Address,
                        RestoreOrionWorkspace));
                    break;
                case "RC7":
                    ShowPreservedWinFormsWindow(
                        "RC7 UI",
                        () => new Rc7LegacyWindow(workspace, RestoreOrionWorkspace));
                    break;
                case "Krnl":
                    ShowPreservedWinFormsWindow(
                        "Krnl UI",
                        () => new KrnlLegacyWindow(workspace, RestoreOrionWorkspace));
                    break;
                default:
                    _orionInterfaceHandoffActive = false;
                    RevealOrionEditor();
                    break;
            }
        }
        catch
        {
            _orionInterfaceHandoffActive = false;
            OrbitPreferences.SetLastInterface(OrbitPreferences.OrionInterface);
            Show();
            Activate();
            RevealOrionEditor();
        }
    }

    private Task ReturnToOrionEditorAsync() => SwitchOrionPageAsync(OrionPage.Editor);

    private async Task<EditorWorkspaceState> CaptureOrionWorkspaceAsync()
    {
        _orionActiveTab.Content = await RequestOrionEditorContentAsync();
        PersistOrionWorkspace();
        return new EditorWorkspaceState
        {
            Tabs = _orionEditorTabs.Select(tab => tab.CloneDetached()).ToList(),
            ActiveTabId = _orionActiveTab.Id
        };
    }

    private void ShowPreservedAvaloniaWindow(Window window)
    {
        _orionPreservedWindow = window;
        window.Show();
        window.Activate();
        Hide();
    }

    private void ShowPreservedWinFormsWindow(
        string threadName,
        Func<Forms.Form> createWindow)
    {
        var thread = new Thread(() =>
        {
            Forms.Application.EnableVisualStyles();
            Forms.Application.SetCompatibleTextRenderingDefault(false);
            try
            {
                using var window = createWindow();
                Forms.Application.Run(window);
            }
            catch
            {
                Dispatcher.UIThread.Post(() => RestoreOrionWorkspaceFromDisk());
            }
        })
        {
            IsBackground = false,
            Name = threadName
        };
        thread.SetApartmentState(ApartmentState.STA);
        Hide();
        thread.Start();
    }

    private void RestoreOrionWorkspaceFromDisk()
    {
        RestoreOrionWorkspace(_orionWorkspace.LoadState());
    }

    private void RestoreOrionWorkspace(EditorWorkspaceState workspace)
    {
        // A deliberate return from a preserved UI makes Orion the most
        // recently used interface, so the next launch opens here.
        OrbitPreferences.SetLastInterface(OrbitPreferences.OrionInterface);
        Dispatcher.UIThread.Post(async () =>
        {
            if (_orionInterfaceReturnActive || _orionPagesDisposed)
            {
                return;
            }

            _orionInterfaceReturnActive = true;
            try
            {
                var returningWindow = _orionPreservedWindow;
                _orionPreservedWindow = null;

                if (returningWindow is XenoWindow xeno)
                {
                    xeno.CloseForOrbit();
                }
                else if (returningWindow is SynapseFrontendWindow synapse)
                {
                    synapse.CloseForOrbit();
                }
                else if (returningWindow is CalamariWindow calamari)
                {
                    calamari.CloseForOrbit();
                }
                else if (returningWindow is AWPWindow awp)
                {
                    awp.CloseForOrion();
                }

                ApplyOrionWorkspace(workspace);
                _orionMonacoWebView.IsVisible = false;
                _orionPageTransitionActive = false;

                // Reattach the top-level window before touching page
                // composition. Resetting compositor visuals while Orion is
                // hidden leaves the native WebView visible over a detached
                // zero-opacity editor page on the next Show().
                Opacity = 0;
                Show();
                Activate();
                await Task.Delay(32);

                if (_orionPagesDisposed)
                {
                    return;
                }

                ShowOrionPageImmediately(OrionPage.Editor);
                _orionEditorPage.RenderTransform = null;
                _editorLayer.Opacity = 1;
                _editorLayer.IsVisible = true;
                _editorLayer.IsHitTestVisible = true;
                _orionEditorPage.InvalidateMeasure();
                _orionEditorPage.InvalidateArrange();
                _orionEditorPage.InvalidateVisual();
                _editorLayer.InvalidateMeasure();
                _editorLayer.InvalidateArrange();
                _editorLayer.InvalidateVisual();
                _rootShell.InvalidateVisual();

                // Give Avalonia one complete frame to rebuild the native page
                // before the child HWND is allowed back above it.
                await Task.Delay(48);
                Opacity = 1;
                RevealOrionEditor();
                await Task.Delay(24);

                if (_orionMonacoReady)
                {
                    try
                    {
                        await _orionMonacoWebView.InvokeScript(
                            "window.orionLayout && window.orionLayout();");
                    }
                    catch (InvalidOperationException)
                    {
                        _orionMonacoReady = false;
                    }
                }

                PushOrionActiveTabToMonaco();
            }
            catch
            {
                Opacity = 1;
                Show();
                Activate();
                ShowOrionPageImmediately(OrionPage.Editor);
                RevealOrionEditor();
                PushOrionActiveTabToMonaco();
            }
            finally
            {
                _orionInterfaceHandoffActive = false;
                _orionInterfaceReturnActive = false;
            }
        });
    }

    private void ApplyOrionWorkspace(EditorWorkspaceState state)
    {
        if (state.Tabs.Count == 0)
        {
            return;
        }

        var detached = state.CloneDetached();
        _orionEditorTabs.Clear();
        _orionEditorTabs.AddRange(detached.Tabs);
        _orionActiveTab = _orionEditorTabs.FirstOrDefault(
                tab => tab.Id == detached.ActiveTabId)
            ?? _orionEditorTabs[0];
        RebuildOrionTabs();
        PersistOrionWorkspace();
    }

    private void ShowOrionPageImmediately(OrionPage target)
    {
        foreach (var page in Enum.GetValues<OrionPage>())
        {
            var control = ControlForOrionPage(page);
            var selected = page == target;
            ResetOrionPageComposition(control, selected);
            control.IsVisible = selected;
            control.IsHitTestVisible = selected;
        }

        _orionCurrentPage = target;
        SetOrionNavigationIndicatorImmediately(
            NavigationIndexForOrionPage(target));
    }

    private void DisposeOrionPages()
    {
        _orionPagesDisposed = true;
        StopOrionPageComposition(_orionEditorPage);
        StopOrionPageComposition(_orionSettingsPage);
        StopOrionPageComposition(_orionUiSelectionPage);
        StopOrionPageComposition(_orionPluginsPage);
        StopOrionPageComposition(_orionThemesPage);
        StopOrionPageComposition(_orionScriptHubPage);
    }
}
