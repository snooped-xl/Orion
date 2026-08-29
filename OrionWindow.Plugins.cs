using Avalonia;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Platform.Storage;
using Avalonia.Threading;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using ShapeEllipse = Avalonia.Controls.Shapes.Ellipse;
using ShapePath = Avalonia.Controls.Shapes.Path;

namespace OrbitAvalonia;

public sealed partial class OrionWindow
{
    private const string OrionPluginGlyphData =
        "M39 21.0017C39 20.206 39.3161 19.443 39.8787 18.8804C40.4413 18.3177 41.2044 18.0017 42 18.0017H44.853C45.15 18.0017 45.333 17.6927 45.219 17.4187C45.1615 17.2839 45.116 17.1444 45.083 17.0017C44.752 15.5147 45.875 14.0017 47.5 14.0017C49.126 14.0017 50.248 15.5147 49.917 17.0017C49.884 17.1444 49.8385 17.2839 49.781 17.4187C49.666 17.6927 49.85 18.0017 50.147 18.0017H52C52.7956 18.0017 53.5587 18.3177 54.1213 18.8804C54.6839 19.443 55 20.206 55 21.0017V22.8547C55 23.1517 55.308 23.3347 55.583 23.2207C55.718 23.1647 55.856 23.1167 56 23.0847C57.487 22.7537 59 23.8757 59 25.5017C59 27.1277 57.487 28.2497 56 27.9187C55.8573 27.8856 55.7177 27.8401 55.583 27.7827C55.309 27.6677 55 27.8517 55 28.1487V31.0017C55 31.7973 54.6839 32.5604 54.1213 33.123C53.5587 33.6856 52.7956 34.0017 52 34.0017H50.107C49.819 34.0017 49.634 33.7107 49.717 33.4357C49.759 33.2957 49.7873 33.151 49.802 33.0017C49.8286 32.6832 49.7888 32.3627 49.6852 32.0605C49.5815 31.7582 49.4163 31.4807 49.2 31.2456C48.9836 31.0104 48.7208 30.8227 48.4282 30.6943C48.1356 30.5659 47.8195 30.4996 47.5 30.4996C47.1805 30.4996 46.8644 30.5659 46.5718 30.6943C46.2792 30.8227 46.0164 31.0104 45.8 31.2456C45.5837 31.4807 45.4185 31.7582 45.3148 32.0605C45.2112 32.3627 45.1714 32.6832 45.198 33.0017C45.212 33.151 45.2407 33.2957 45.284 33.4357C45.366 33.7107 45.181 34.0017 44.894 34.0017H42C41.2044 34.0017 40.4413 33.6856 39.8787 33.123C39.3161 32.5604 39 31.7973 39 31.0017V28.1087C39 27.8207 39.291 27.6357 39.566 27.7187C39.706 27.7607 39.8507 27.789 40 27.8037C40.3184 27.8302 40.6389 27.7905 40.9412 27.6868C41.2435 27.5832 41.521 27.418 41.7561 27.2016C41.9913 26.9853 42.179 26.7225 42.3074 26.4299C42.4358 26.1373 42.5021 25.8212 42.5021 25.5017C42.5021 25.1821 42.4358 24.8661 42.3074 24.5735C42.179 24.2808 41.9913 24.0181 41.7561 23.8017C41.521 23.5853 41.2435 23.4201 40.9412 23.3165C40.6389 23.2129 40.3184 23.1731 40 23.1997C39.8507 23.2137 39.706 23.2423 39.566 23.2857C39.291 23.3677 39 23.1827 39 22.8957V21.0017Z";

    private OrionPluginHost? _orionPluginHost;
    private TextBox _orionPluginSearchBox = null!;
    private TextBlock _orionPluginCountText = null!;
    private TextBlock _orionPluginMessageText = null!;
    private TextBlock _orionPluginEmptyTitle = null!;
    private TextBlock _orionPluginEmptyDescription = null!;
    private StackPanel _orionPluginListPanel = null!;
    private Border _orionPluginEmptyState = null!;
    private Border _orionPluginAdminTrack = null!;
    private ShapeEllipse _orionPluginAdminThumb = null!;
    private string? _orionPendingPluginRemoval;
    private DateTimeOffset _orionPendingPluginRemovalExpires;

    private void InitializeOrionPluginsPage()
    {
        _orionPluginSearchBox = this.FindControl<TextBox>("OrionPluginSearchBox")
            ?? throw new InvalidOperationException("OrionPluginSearchBox was not found.");
        _orionPluginCountText = this.FindControl<TextBlock>("OrionPluginCountText")
            ?? throw new InvalidOperationException("OrionPluginCountText was not found.");
        _orionPluginMessageText = this.FindControl<TextBlock>("OrionPluginMessageText")
            ?? throw new InvalidOperationException("OrionPluginMessageText was not found.");
        _orionPluginEmptyTitle = this.FindControl<TextBlock>("OrionPluginEmptyTitle")
            ?? throw new InvalidOperationException("OrionPluginEmptyTitle was not found.");
        _orionPluginEmptyDescription = this.FindControl<TextBlock>("OrionPluginEmptyDescription")
            ?? throw new InvalidOperationException("OrionPluginEmptyDescription was not found.");
        _orionPluginListPanel = this.FindControl<StackPanel>("OrionPluginListPanel")
            ?? throw new InvalidOperationException("OrionPluginListPanel was not found.");
        _orionPluginEmptyState = this.FindControl<Border>("OrionPluginEmptyState")
            ?? throw new InvalidOperationException("OrionPluginEmptyState was not found.");
        _orionPluginAdminTrack = this.FindControl<Border>("OrionPluginAdminTrack")
            ?? throw new InvalidOperationException("OrionPluginAdminTrack was not found.");
        _orionPluginAdminThumb = this.FindControl<ShapeEllipse>("OrionPluginAdminThumb")
            ?? throw new InvalidOperationException("OrionPluginAdminThumb was not found.");

        UpdateOrionPluginAdminToggle();
        RenderOrionPlugins();
        Closed += OrionPluginsWindow_Closed;
    }

    internal void AttachOrionPluginHost(OrionPluginHost host)
    {
        ArgumentNullException.ThrowIfNull(host);
        if (_orionPluginHost is not null)
        {
            _orionPluginHost.PluginsChanged -= OrionPluginHost_PluginsChanged;
        }

        _orionPluginHost = host;
        _orionPluginHost.PluginsChanged += OrionPluginHost_PluginsChanged;
        RenderOrionPlugins();
    }

    private void OrionPluginsWindow_Closed(object? sender, EventArgs e)
    {
        if (_orionPluginHost is not null)
        {
            _orionPluginHost.PluginsChanged -= OrionPluginHost_PluginsChanged;
        }
    }

    private void OrionPluginHost_PluginsChanged(object? sender, EventArgs e)
    {
        if (Dispatcher.UIThread.CheckAccess())
        {
            RenderOrionPlugins();
        }
        else
        {
            Dispatcher.UIThread.Post(RenderOrionPlugins);
        }
    }

    private void OrionPluginSearch_TextChanged(object? sender, TextChangedEventArgs e) =>
        RenderOrionPlugins();

    private void OrionPluginAdminToggle_Click(object? sender, RoutedEventArgs e)
    {
        var enabled = !OrbitPreferences.PluginsRunAsAdministrator;
        OrbitPreferences.SetPluginsRunAsAdministrator(enabled);
        UpdateOrionPluginAdminToggle();

        if (enabled)
        {
            SetOrionPluginMessage(
                Program.IsRunningAsAdministrator()
                    ? "Administrator launch saved. This session is already elevated."
                    : "Administrator launch saved. Orion will request elevation next time it opens.");
        }
        else
        {
            SetOrionPluginMessage(
                Program.IsRunningAsAdministrator()
                    ? "Administrator launch disabled. This session remains elevated until Orion restarts."
                    : "Administrator launch disabled.");
        }
    }

    private void UpdateOrionPluginAdminToggle()
    {
        var enabled = OrbitPreferences.PluginsRunAsAdministrator;
        _orionPluginAdminTrack.Background = enabled
            ? ThemeResourceBrush("OrionBorderStrongBrush", "#55595D")
            : ThemeResourceBrush("OrionControlBrush", "#111315");
        _orionPluginAdminTrack.BorderBrush = enabled
            ? ThemeResourceBrush("OrionTextSecondaryBrush", "#777B7F")
            : ThemeResourceBrush("OrionBorderBrush", "#373A3D");
        _orionPluginAdminThumb.Fill = enabled
            ? ThemeResourceBrush("OrionTextPrimaryBrush", "#F1F2F3")
            : ThemeResourceBrush("OrionTextSecondaryBrush", "#74777A");
        Canvas.SetLeft(_orionPluginAdminThumb, enabled ? 14 : 2);
    }

    private void RenderOrionPlugins()
    {
        if (_orionPluginListPanel is null)
        {
            return;
        }

        var allPlugins = _orionPluginHost?.Plugins ?? Array.Empty<OrionPluginInfo>();
        var query = _orionPluginSearchBox?.Text?.Trim() ?? string.Empty;
        var visiblePlugins = allPlugins
            .Where(plugin => MatchesOrionPluginSearch(plugin, query))
            .ToArray();

        _orionPluginCountText.Text = allPlugins.Count == 1
            ? "1 installed"
            : $"{allPlugins.Count} installed";
        _orionPluginListPanel.Children.Clear();

        foreach (var plugin in visiblePlugins)
        {
            _orionPluginListPanel.Children.Add(BuildOrionPluginRow(plugin));
        }

        _orionPluginEmptyState.IsVisible = visiblePlugins.Length == 0;
        if (allPlugins.Count == 0)
        {
            _orionPluginEmptyTitle.Text = "No plugins installed";
            _orionPluginEmptyDescription.Text =
                "Import a .orionplugin package, a .zip package, or a .NET assembly.";
        }
        else
        {
            _orionPluginEmptyTitle.Text = "No matching plugins";
            _orionPluginEmptyDescription.Text =
                "Try a different name, author, status, or plugin id.";
        }
    }

    private static bool MatchesOrionPluginSearch(OrionPluginInfo plugin, string query)
    {
        if (string.IsNullOrWhiteSpace(query))
        {
            return true;
        }

        return plugin.Name.Contains(query, StringComparison.OrdinalIgnoreCase) ||
               plugin.Id.Contains(query, StringComparison.OrdinalIgnoreCase) ||
               plugin.Author.Contains(query, StringComparison.OrdinalIgnoreCase) ||
               plugin.Description.Contains(query, StringComparison.OrdinalIgnoreCase) ||
               PluginStatus(plugin).Contains(query, StringComparison.OrdinalIgnoreCase);
    }

    private Control BuildOrionPluginRow(OrionPluginInfo plugin)
    {
        var row = new Border
        {
            Height = 53.333,
            Background = Brushes.Transparent,
            BorderBrush = ThemeResourceBrush("OrionBorderBrush", "#25272A"),
            BorderThickness = new Thickness(0, 0, 0, 0.5)
        };

        var grid = new Grid
        {
            Margin = new Thickness(11.333, 0),
            ColumnDefinitions = new ColumnDefinitions("30,*,70,53,49")
        };

        grid.Children.Add(new ShapePath
        {
            Width = 13.333,
            Height = 13.333,
            HorizontalAlignment = HorizontalAlignment.Left,
            VerticalAlignment = VerticalAlignment.Center,
            Opacity = plugin.IsRunning ? 0.95 : 0.52,
            Stretch = Stretch.Uniform,
            Fill = ThemeResourceBrush("OrionTextSecondaryBrush", "#BCBCBC"),
            Data = Geometry.Parse(OrionPluginGlyphData)
        });

        var identity = new StackPanel
        {
            VerticalAlignment = VerticalAlignment.Center,
            Spacing = 2
        };
        Grid.SetColumn(identity, 1);
        var titleLine = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 5
        };
        titleLine.Children.Add(new TextBlock
        {
            Text = plugin.Name,
            FontSize = 8.333,
            Foreground = ThemeResourceBrush("OrionTextPrimaryBrush", "#E3E4E5"),
            TextTrimming = TextTrimming.CharacterEllipsis,
            MaxWidth = 240
        });
        titleLine.Children.Add(new TextBlock
        {
            Text = plugin.Version,
            FontSize = 6.333,
            Foreground = ThemeResourceBrush("OrionTextMutedBrush", "#515458"),
            VerticalAlignment = VerticalAlignment.Center
        });
        identity.Children.Add(titleLine);

        var detail = !string.IsNullOrWhiteSpace(plugin.Error)
            ? plugin.Error
            : !string.IsNullOrWhiteSpace(plugin.Description)
                ? plugin.Description
                : !string.IsNullOrWhiteSpace(plugin.Author)
                    ? $"by {plugin.Author}"
                    : plugin.Id;
        identity.Children.Add(new TextBlock
        {
            Text = detail,
            FontSize = 6.667,
            Foreground = plugin.Error is null
                ? ThemeResourceBrush("OrionTextMutedBrush", "#606367")
                : Brush("#A6676B"),
            TextTrimming = TextTrimming.CharacterEllipsis,
            MaxWidth = 292
        });
        grid.Children.Add(identity);

        var status = new TextBlock
        {
            Text = PluginStatus(plugin),
            FontSize = 6.667,
            Foreground = plugin.Error is not null
                ? Brush("#A6676B")
                : plugin.IsRunning
                    ? ThemeResourceBrush("OrionTextPrimaryBrush", "#AEB8B0")
                    : ThemeResourceBrush("OrionTextMutedBrush", "#5C5F63"),
            HorizontalAlignment = HorizontalAlignment.Left,
            VerticalAlignment = VerticalAlignment.Center
        };
        Grid.SetColumn(status, 2);
        grid.Children.Add(status);

        var toggle = PluginButton(
            plugin.Enabled && plugin.IsRunning ? "Disable" : plugin.Enabled ? "Retry" : "Enable",
            47.333,
            OrionPluginToggle_Click,
            plugin.Id);
        Grid.SetColumn(toggle, 3);
        grid.Children.Add(toggle);

        var awaitingConfirmation =
            string.Equals(_orionPendingPluginRemoval, plugin.Id, StringComparison.OrdinalIgnoreCase) &&
            DateTimeOffset.UtcNow <= _orionPendingPluginRemovalExpires;
        var remove = PluginButton(
            awaitingConfirmation ? "Sure?" : "Remove",
            44,
            OrionPluginRemove_Click,
            plugin.Id);
        remove.Classes.Add("danger");
        Grid.SetColumn(remove, 4);
        grid.Children.Add(remove);

        row.Child = grid;
        if (!string.IsNullOrWhiteSpace(plugin.Error))
        {
            ToolTip.SetTip(row, plugin.Error);
        }

        return row;
    }

    private static Button PluginButton(
        string text,
        double width,
        EventHandler<RoutedEventArgs> click,
        string pluginId)
    {
        var button = new Button
        {
            Content = text,
            Tag = pluginId,
            Width = width,
            Height = 21.333,
            HorizontalAlignment = HorizontalAlignment.Left,
            VerticalAlignment = VerticalAlignment.Center
        };
        button.Classes.Add("orion-plugin-button");
        button.Click += click;
        return button;
    }

    private static string PluginStatus(OrionPluginInfo plugin) =>
        plugin.Error is not null
            ? "Needs attention"
            : plugin.IsRunning ? "Active" : plugin.Enabled ? "Stopped" : "Disabled";

    private async void OrionImportPlugin_Click(object? sender, RoutedEventArgs e)
    {
        if (_orionPluginHost is null)
        {
            SetOrionPluginMessage("The plugin host is not ready.", isError: true);
            return;
        }

        var selected = await StorageProvider.OpenFilePickerAsync(new FilePickerOpenOptions
        {
            Title = "Import Orion plugin",
            AllowMultiple = false,
            FileTypeFilter =
            [
                new FilePickerFileType("Orion plugins")
                {
                    Patterns = ["*.orionplugin", "*.zip", "plugin.json", "*.dll"]
                },
                FilePickerFileTypes.All
            ]
        });
        var file = selected.FirstOrDefault();
        if (file is null)
        {
            return;
        }

        try
        {
            SetOrionPluginMessage("Importing plugin…");
            await _orionPluginHost.ImportAsync(file.Path.LocalPath);
            SetOrionPluginMessage("Plugin imported. Enable it when you are ready.");
        }
        catch (Exception exception)
        {
            SetOrionPluginMessage(exception.Message, isError: true);
        }
    }

    private void OrionOpenPluginFolder_Click(object? sender, RoutedEventArgs e)
    {
        if (_orionPluginHost is null)
        {
            SetOrionPluginMessage("The plugin host is not ready.", isError: true);
            return;
        }

        try
        {
            Directory.CreateDirectory(_orionPluginHost.PluginRoot);
            Process.Start(new ProcessStartInfo("explorer.exe", _orionPluginHost.PluginRoot)
            {
                UseShellExecute = true
            });
        }
        catch (Exception exception)
        {
            SetOrionPluginMessage(exception.Message, isError: true);
        }
    }

    private async void OrionPluginToggle_Click(object? sender, RoutedEventArgs e)
    {
        if (_orionPluginHost is null || sender is not Button { Tag: string pluginId })
        {
            return;
        }

        var plugin = _orionPluginHost.Plugins.FirstOrDefault(item =>
            item.Id.Equals(pluginId, StringComparison.OrdinalIgnoreCase));
        if (plugin is null)
        {
            return;
        }

        try
        {
            if (plugin.Enabled && plugin.IsRunning)
            {
                await _orionPluginHost.SetEnabledAsync(pluginId, enabled: false);
                SetOrionPluginMessage($"{plugin.Name} disabled.");
            }
            else if (plugin.Enabled)
            {
                await _orionPluginHost.ReloadAsync(pluginId);
                var updated = _orionPluginHost.Plugins.First(item =>
                    item.Id.Equals(pluginId, StringComparison.OrdinalIgnoreCase));
                SetOrionPluginMessage(
                    updated.Error is null
                        ? $"{plugin.Name} started."
                        : updated.Error,
                    updated.Error is not null);
            }
            else
            {
                await _orionPluginHost.SetEnabledAsync(pluginId, enabled: true);
                var updated = _orionPluginHost.Plugins.First(item =>
                    item.Id.Equals(pluginId, StringComparison.OrdinalIgnoreCase));
                SetOrionPluginMessage(
                    updated.Error is null
                        ? $"{plugin.Name} enabled."
                        : updated.Error,
                    updated.Error is not null);
            }
        }
        catch (Exception exception)
        {
            SetOrionPluginMessage(exception.Message, isError: true);
        }
    }

    private async void OrionPluginRemove_Click(object? sender, RoutedEventArgs e)
    {
        if (_orionPluginHost is null || sender is not Button { Tag: string pluginId })
        {
            return;
        }

        var plugin = _orionPluginHost.Plugins.FirstOrDefault(item =>
            item.Id.Equals(pluginId, StringComparison.OrdinalIgnoreCase));
        if (plugin is null)
        {
            return;
        }

        var now = DateTimeOffset.UtcNow;
        if (!string.Equals(_orionPendingPluginRemoval, pluginId, StringComparison.OrdinalIgnoreCase) ||
            now > _orionPendingPluginRemovalExpires)
        {
            _orionPendingPluginRemoval = pluginId;
            _orionPendingPluginRemovalExpires = now.AddSeconds(4);
            SetOrionPluginMessage($"Click Remove again to delete {plugin.Name}.");
            RenderOrionPlugins();
            return;
        }

        try
        {
            _orionPendingPluginRemoval = null;
            await _orionPluginHost.RemoveAsync(pluginId);
            SetOrionPluginMessage($"{plugin.Name} removed.");
        }
        catch (Exception exception)
        {
            SetOrionPluginMessage(exception.Message, isError: true);
        }
    }

    private void SetOrionPluginMessage(string message, bool isError = false)
    {
        _orionPluginMessageText.Text = message;
        _orionPluginMessageText.Foreground = isError
            ? Brush("#A6676B")
            : ThemeResourceBrush("OrionTextMutedBrush", "#55585C");
        ToolTip.SetTip(_orionPluginMessageText, message);
    }

    private static SolidColorBrush Brush(string color) => new(Color.Parse(color));
}
