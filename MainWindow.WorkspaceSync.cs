namespace OrbitAvalonia;

public sealed partial class MainWindow
{
    private EditorWorkspaceState CaptureSharedEditorWorkspace()
    {
        PersistEditorWorkspace();
        return new EditorWorkspaceState
        {
            Tabs = _editorTabs.Select(tab => tab.CloneDetached()).ToList(),
            ActiveTabId = _activeEditorTab.Id
        };
    }

    private void ApplySharedEditorWorkspace(EditorWorkspaceState state)
    {
        if (state.Tabs.Count == 0)
        {
            return;
        }

        var detached = state.CloneDetached();
        _editorTabs.Clear();
        _editorTabs.AddRange(detached.Tabs);
        _activeEditorTab = _editorTabs.FirstOrDefault(tab => tab.Id == detached.ActiveTabId)
            ?? _editorTabs[0];

        RebuildEditorTabs();
        RebuildExplorerTree();
        PushActiveTabToMonaco();
        PersistEditorWorkspace();
    }
}

