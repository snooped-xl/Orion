using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Media;

namespace OrbitAvalonia;

public sealed partial class MainWindow
{
    private enum PluginsSection
    {
        Installed,
        Import,
        Create
    }

    private Canvas _pluginsInstalledContent = null!;
    private Canvas _pluginsImportContent = null!;
    private Canvas _pluginsCreateContent = null!;
    private Border _pluginsInstalledRule = null!;
    private Border _pluginsInstalledCard = null!;
    private Border _pluginsImportRule = null!;
    private Border _pluginsImportCard = null!;
    private Border _pluginsCreateRule = null!;
    private Border _pluginsCreateCard = null!;
    private Border _pluginsSectionIndicator = null!;
    private TextBlock _pluginsInstalledMenuText = null!;
    private TextBlock _pluginsImportMenuText = null!;
    private TextBlock _pluginsCreateMenuText = null!;

    private void InitializePluginsPage()
    {
        _pluginsInstalledContent = this.FindControl<Canvas>("PluginsInstalledContent") ?? new Canvas();
        _pluginsImportContent = this.FindControl<Canvas>("PluginsImportContent") ?? new Canvas();
        _pluginsCreateContent = this.FindControl<Canvas>("PluginsCreateContent") ?? new Canvas();
        _pluginsInstalledRule = this.FindControl<Border>("PluginsInstalledRule") ?? new Border();
        _pluginsInstalledCard = this.FindControl<Border>("PluginsInstalledCard") ?? new Border();
        _pluginsImportRule = this.FindControl<Border>("PluginsImportRule") ?? new Border();
        _pluginsImportCard = this.FindControl<Border>("PluginsImportCard") ?? new Border();
        _pluginsCreateRule = this.FindControl<Border>("PluginsCreateRule") ?? new Border();
        _pluginsCreateCard = this.FindControl<Border>("PluginsCreateCard") ?? new Border();
        _pluginsSectionIndicator = this.FindControl<Border>("PluginsSectionIndicator") ?? new Border();
        _pluginsInstalledMenuText = this.FindControl<TextBlock>("PluginsInstalledMenuText") ?? new TextBlock();
        _pluginsImportMenuText = this.FindControl<TextBlock>("PluginsImportMenuText") ?? new TextBlock();
        _pluginsCreateMenuText = this.FindControl<TextBlock>("PluginsCreateMenuText") ?? new TextBlock();

        SetPluginsSection(PluginsSection.Installed);
    }

    private void PluginsSection_Click(object? sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: string tag } ||
            !Enum.TryParse<PluginsSection>(tag, ignoreCase: true, out var section))
        {
            return;
        }

        SetPluginsSection(section);
    }

    private void PluginsOpenImport_Click(object? sender, RoutedEventArgs e) =>
        SetPluginsSection(PluginsSection.Import);

    private void SetPluginsSection(PluginsSection section)
    {
        _pluginsInstalledContent.IsVisible = section == PluginsSection.Installed;
        _pluginsImportContent.IsVisible = section == PluginsSection.Import;
        _pluginsCreateContent.IsVisible = section == PluginsSection.Create;

        _pluginsInstalledMenuText.Foreground = MenuBrush(section == PluginsSection.Installed);
        _pluginsImportMenuText.Foreground = MenuBrush(section == PluginsSection.Import);
        _pluginsCreateMenuText.Foreground = MenuBrush(section == PluginsSection.Create);

        _pluginsInstalledMenuText.FontWeight = section == PluginsSection.Installed
            ? FontWeight.SemiBold
            : FontWeight.Normal;
        _pluginsImportMenuText.FontWeight = section == PluginsSection.Import
            ? FontWeight.SemiBold
            : FontWeight.Normal;
        _pluginsCreateMenuText.FontWeight = section == PluginsSection.Create
            ? FontWeight.SemiBold
            : FontWeight.Normal;

        Canvas.SetTop(_pluginsSectionIndicator, section switch
        {
            PluginsSection.Installed => 140,
            PluginsSection.Import => 174,
            PluginsSection.Create => 208,
            _ => 140
        });
    }

    private static SolidColorBrush MenuBrush(bool selected) =>
        new(Color.Parse(selected ? "#FFFFFF" : "#A1A4A6"));
}
