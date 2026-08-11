using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.Media;
using Avalonia.Platform.Storage;
using Avalonia.Threading;
using System.Text;
using ShapePath = Avalonia.Controls.Shapes.Path;

namespace OrbitAvalonia;

public sealed partial class MainWindow
{
    private Canvas? _navigationRailLayer;
    private ShapePath? _topNavIndicator;

    private void InitializeNavigationRail()
    {
        _navigationRailLayer = this.FindControl<Canvas>("NavigationRailLayer");
        _topNavIndicator = this.FindControl<ShapePath>("TopNavIndicator");
    }

    private void NavUiSelection_Click(object? sender, RoutedEventArgs e) => SetPage(AppPage.Plugins);
    private void NavScriptHub_Click(object? sender, RoutedEventArgs e) => SetPage(AppPage.ScriptHub);
    private void NavEditor_Click(object? sender, RoutedEventArgs e) => SetPage(AppPage.Editor);
    private void NavAgent_Click(object? sender, RoutedEventArgs e) => SetPage(AppPage.Robot);
    private void NavThemes_Click(object? sender, RoutedEventArgs e) => SetPage(AppPage.Themes);
    private void NavSettings_Click(object? sender, RoutedEventArgs e) => SetPage(AppPage.Settings);

    private void OpenSynapseV3_Click(object? sender, RoutedEventArgs e) => _ = ActivateSynapseUiAsync(SynapseFrontendKind.V3);
    private void OpenSynapse2016_Click(object? sender, RoutedEventArgs e) => _ = ActivateSynapseUiAsync(SynapseFrontendKind.Classic2017);
    private void OpenSynapseBlue_Click(object? sender, RoutedEventArgs e) => _ = ActivateSynapseUiAsync(SynapseFrontendKind.Blue);
    private void OpenSynapseX_Click(object? sender, RoutedEventArgs e) => _ = ActivateSynapseUiAsync(SynapseFrontendKind.SynapseX);
    private void OpenRc7_Click(object? sender, RoutedEventArgs e) => _ = ActivateRc7UiAsync();
    private void OpenKrnl_Click(object? sender, RoutedEventArgs e) => _ = ActivateKrnlUiAsync();
    private void OpenCalamari_Click(object? sender, RoutedEventArgs e) => _ = ActivateCalamariUiAsync();

    private void Execute_Click(object? sender, RoutedEventArgs e)
    {
        var textBox = this.FindControl<TextBox>("NativeEditorTextBox");
        var text = textBox?.Text ?? _activeEditorTab?.Content ?? string.Empty;
        if (_bridgeServer.IsConnected && !string.IsNullOrWhiteSpace(text))
        {
            _bridgeServer.EnqueueExecute(text);
        }
    }

    private async void SaveFile_Click(object? sender, RoutedEventArgs e)
    {
        var topLevel = TopLevel.GetTopLevel(this);
        if (topLevel == null) return;
        var file = await topLevel.StorageProvider.SaveFilePickerAsync(new FilePickerSaveOptions
        {
            Title = "Save Script",
            DefaultExtension = "lua",
            FileTypeChoices = new[] { new FilePickerFileType("Lua Script") { Patterns = new[] { "*.lua", "*.txt" } } }
        });
        if (file != null)
        {
            var textBox = this.FindControl<TextBox>("NativeEditorTextBox");
            await using var stream = await file.OpenWriteAsync();
            await using var writer = new StreamWriter(stream, Encoding.UTF8);
            await writer.WriteAsync(textBox?.Text ?? string.Empty);
        }
    }

    private async void OpenFile_Click(object? sender, RoutedEventArgs e)
    {
        var topLevel = TopLevel.GetTopLevel(this);
        if (topLevel == null) return;
        var files = await topLevel.StorageProvider.OpenFilePickerAsync(new FilePickerOpenOptions
        {
            Title = "Open Script",
            AllowMultiple = false,
            FileTypeFilter = new[] { new FilePickerFileType("Scripts") { Patterns = new[] { "*.lua", "*.txt", "*.json" } } }
        });
        if (files.Count > 0)
        {
            await using var stream = await files[0].OpenReadAsync();
            using var reader = new StreamReader(stream, Encoding.UTF8);
            var content = await reader.ReadToEndAsync();
            var textBox = this.FindControl<TextBox>("NativeEditorTextBox");
            if (textBox != null)
            {
                textBox.Text = content;
            }
            if (_activeEditorTab != null)
            {
                _activeEditorTab.Content = content;
                ScheduleWorkspaceSave();
            }
        }
    }

    private void Clear_Click(object? sender, RoutedEventArgs e)
    {
        var textBox = this.FindControl<TextBox>("NativeEditorTextBox");
        if (textBox != null)
        {
            textBox.Text = string.Empty;
        }
        if (_activeEditorTab != null)
        {
            _activeEditorTab.Content = string.Empty;
            ScheduleWorkspaceSave();
        }
    }

    private void NewTab_Click(object? sender, RoutedEventArgs e)
    {
        AddEditorTab();
    }

    private void CloseTab_Click(object? sender, RoutedEventArgs e)
    {
        if (_activeEditorTab != null && _editorTabs.Count > 1)
        {
            CloseEditorTab(_activeEditorTab);
        }
    }

    private void TopMost_Click(object? sender, RoutedEventArgs e)
    {
        Topmost = !Topmost;
        OrbitPreferences.SetTopMost(Topmost);
        var topMostText = this.FindControl<TextBlock>("TopMostText");
        if (topMostText != null)
        {
            topMostText.Foreground = Topmost ? Brushes.Lime : BrushFrom("#FF4C4C");
        }
    }

    private void BridgeSettings_Click(object? sender, RoutedEventArgs e)
    {
        var screen = Screens.ScreenFromWindow(this) ?? Screens.Primary;
        var workingArea = screen?.WorkingArea ?? new PixelRect(0, 0, 1920, 1080);
        var scaling = screen?.Scaling ?? 1.0;
        var window = new BridgeNotificationWindow(workingArea, scaling);
        _ = window.PresentAsync(CancellationToken.None);
    }

    private void EditorTextBox_TextChanged(object? sender, TextChangedEventArgs e)
    {
        var textBox = this.FindControl<TextBox>("NativeEditorTextBox");
        if (_activeEditorTab != null && textBox != null)
        {
            _activeEditorTab.Content = textBox.Text;
            ScheduleWorkspaceSave();
        }
    }

    private void EditorTextBox_SelectionChanged(object? sender, RoutedEventArgs e)
    {
        var textBox = this.FindControl<TextBox>("NativeEditorTextBox");
        var cursorText = this.FindControl<TextBlock>("CursorPositionText");
        if (textBox != null && cursorText != null)
        {
            var text = textBox.Text ?? string.Empty;
            var caretIndex = textBox.CaretIndex;
            var line = 1;
            var col = 1;
            for (int i = 0; i < Math.Min(caretIndex, text.Length); i++)
            {
                if (text[i] == '\n')
                {
                    line++;
                    col = 1;
                }
                else
                {
                    col++;
                }
            }
            cursorText.Text = $"Ln {line}, Col {col}";
        }
    }

    private void QuickSettingsPlus_Click(object? sender, RoutedEventArgs e)
    {
        var popup = this.FindControl<Border>("QuickSettingsPopup");
        if (popup != null)
        {
            popup.IsVisible = !popup.IsVisible;
        }
    }
}
