using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Primitives;
using Avalonia.Input;
using Avalonia.Layout;
using Avalonia.Media;

namespace OrbitAvalonia;

internal abstract class XenoPanelWindow : Window
{
    protected readonly StackPanel Body;

    protected XenoPanelWindow(string title, double width, double height)
    {
        Width = width;
        Height = height;
        MinWidth = width;
        MinHeight = height;
        MaxWidth = width;
        MaxHeight = height;
        Title = title;
        Background = Brushes.Transparent;
        TransparencyLevelHint = [WindowTransparencyLevel.Transparent];
        WindowDecorations = WindowDecorations.None;
        CanResize = false;
        ShowInTaskbar = false;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;

        var titleBar = new Grid
        {
            Height = 30,
            Background = Brush("#090909"),
            ColumnDefinitions = new ColumnDefinitions("*,Auto")
        };
        titleBar.PointerPressed += (_, e) =>
        {
            if (e.GetCurrentPoint(this).Properties.IsLeftButtonPressed)
            {
                BeginMoveDrag(e);
            }
        };

        titleBar.Children.Add(new TextBlock
        {
            Text = title,
            FontFamily = new FontFamily("Consolas"),
            FontSize = 18,
            Foreground = Brushes.White,
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new Thickness(10, 0)
        });

        var close = CreateButton("×", 29, 29);
        close.FontSize = 22;
        close.Click += (_, _) => Close();
        Grid.SetColumn(close, 1);
        titleBar.Children.Add(close);

        Body = new StackPanel
        {
            Spacing = 6,
            Margin = new Thickness(6, 5, 6, 6)
        };

        var content = new Grid
        {
            RowDefinitions = new RowDefinitions("30,*")
        };
        content.Children.Add(titleBar);
        var bodyBorder = new Border
        {
            Background = Brushes.Black,
            BorderBrush = Brush("#303030"),
            BorderThickness = new Thickness(0, 1, 0, 0),
            Child = new ScrollViewer
            {
                VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
                Content = Body
            }
        };
        Grid.SetRow(bodyBorder, 1);
        content.Children.Add(bodyBorder);

        Content = new Border
        {
            Background = Brush("#090909"),
            BorderBrush = Brushes.Black,
            BorderThickness = new Thickness(2),
            CornerRadius = new CornerRadius(10),
            Child = content
        };
    }

    protected static Button CreateButton(string label, double width, double height)
    {
        return new Button
        {
            Content = label,
            Width = width,
            Height = height,
            Background = Brush("#1A1A1A"),
            BorderBrush = Brush("#333333"),
            BorderThickness = new Thickness(1),
            Foreground = Brushes.White,
            FontFamily = new FontFamily("Consolas"),
            FontSize = 13,
            Padding = new Thickness(5, 2),
            HorizontalContentAlignment = HorizontalAlignment.Center,
            VerticalContentAlignment = VerticalAlignment.Center
        };
    }

    protected static IBrush Brush(string color) => new SolidColorBrush(Color.Parse(color));
}

internal sealed class XenoScriptsWindow : XenoPanelWindow
{
    private readonly List<Button> _executeButtons = [];

    public XenoScriptsWindow(string scriptsDirectory) : base("Scripts", 300, 200)
    {
        IReadOnlyList<string> scriptPaths;
        try
        {
            scriptPaths = Directory.Exists(scriptsDirectory)
                ? Directory.EnumerateFiles(scriptsDirectory)
                    .Where(path => !Path.GetFileName(path).StartsWith('.'))
                    .OrderBy(Path.GetFileName, StringComparer.OrdinalIgnoreCase)
                    .ToList()
                : [];
        }
        catch (IOException)
        {
            scriptPaths = [];
        }

        if (scriptPaths.Count == 0)
        {
            Body.Children.Add(new TextBlock
            {
                Text = "No scripts found",
                FontFamily = new FontFamily("Cascadia Code"),
                FontSize = 13,
                Foreground = Brush("#777777"),
                Margin = new Thickness(4, 6)
            });
            return;
        }

        foreach (var scriptPath in scriptPaths)
        {
            var row = new Grid
            {
                ColumnDefinitions = new ColumnDefinitions("*,Auto"),
                Margin = new Thickness(0, 0, 0, 3)
            };
            row.Children.Add(new TextBlock
            {
                Text = Path.GetFileNameWithoutExtension(scriptPath),
                FontFamily = new FontFamily("Cascadia Code"),
                FontSize = 14,
                Foreground = Brushes.White,
                VerticalAlignment = VerticalAlignment.Center
            });

            var execute = CreateButton("Execute", 69, 28);
            execute.IsEnabled = UnifiedBridgeServer.Shared.IsConnected;
            _executeButtons.Add(execute);
            execute.Click += async (_, _) =>
            {
                if (!UnifiedBridgeServer.Shared.IsConnected)
                {
                    return;
                }

                try
                {
                    UnifiedBridgeServer.Shared.EnqueueExecute(
                        await File.ReadAllTextAsync(scriptPath));
                }
                catch (IOException)
                {
                    // Preserve the source UI's quiet script-list behavior.
                }
                catch (UnauthorizedAccessException)
                {
                    // Preserve the source UI's quiet script-list behavior.
                }
            };
            Grid.SetColumn(execute, 1);
            row.Children.Add(execute);
            Body.Children.Add(row);
            Body.Children.Add(new Border
            {
                Height = 1,
                Background = Brush("#555555"),
                Margin = new Thickness(0, 0, 0, 2)
            });
        }

        UnifiedBridgeServer.Shared.ConnectionChanged += BridgeConnectionChanged;
        Closed += (_, _) =>
            UnifiedBridgeServer.Shared.ConnectionChanged -= BridgeConnectionChanged;
    }

    private void BridgeConnectionChanged(bool connected) =>
        Avalonia.Threading.Dispatcher.UIThread.Post(() =>
        {
            var available = connected && UnifiedBridgeServer.Shared.IsConnected;
            foreach (var button in _executeButtons)
            {
                button.IsEnabled = available;
            }
        });
}

internal sealed class XenoClientsWindow : XenoPanelWindow
{
    public XenoClientsWindow() : base("Clients", 300, 200)
    {
        AddClient("Client 1, PID: —");
        AddClient("Client 2, PID: —");
    }

    private void AddClient(string label)
    {
        Body.Children.Add(new CheckBox
        {
            Content = label,
            IsChecked = true,
            Foreground = Brushes.White,
            Background = Brushes.Black,
            FontFamily = new FontFamily("Franklin Gothic Medium"),
            FontSize = 13,
            Margin = new Thickness(3, 2)
        });
    }
}

internal sealed class XenoSettingsWindow : XenoPanelWindow
{
    public XenoSettingsWindow(Action returnToOrbit) : base("Settings", 330, 270)
    {
        Body.Children.Add(new TextBlock
        {
            Text = "XENO UI",
            FontSize = 10,
            Foreground = Brush("#777777"),
            Margin = new Thickness(3, 5, 3, 0)
        });
        Body.Children.Add(new TextBlock
        {
            Text = "Interface settings",
            FontSize = 17,
            Foreground = Brushes.White,
            FontWeight = FontWeight.SemiBold,
            Margin = new Thickness(3, 0, 3, 5)
        });
        Body.Children.Add(CreateInfoRow("Editor", "Monaco preview"));
        Body.Children.Add(CreateInfoRow("Runtime", "Orion Bridge"));
        Body.Children.Add(CreateInfoRow("Theme", "Xeno Dark"));

        var orbit = CreateButton("Use Orion UI", 150, 32);
        orbit.HorizontalAlignment = HorizontalAlignment.Left;
        orbit.Margin = new Thickness(3, 10, 0, 0);
        orbit.Click += (_, _) => returnToOrbit();
        Body.Children.Add(orbit);
    }

    private static Border CreateInfoRow(string label, string value)
    {
        var grid = new Grid
        {
            ColumnDefinitions = new ColumnDefinitions("*,Auto"),
            Height = 30
        };
        grid.Children.Add(new TextBlock
        {
            Text = label,
            Foreground = Brush("#B0B0B0"),
            VerticalAlignment = VerticalAlignment.Center
        });
        var valueText = new TextBlock
        {
            Text = value,
            Foreground = Brush("#737373"),
            VerticalAlignment = VerticalAlignment.Center
        };
        Grid.SetColumn(valueText, 1);
        grid.Children.Add(valueText);
        return new Border
        {
            BorderBrush = Brush("#303030"),
            BorderThickness = new Thickness(0, 0, 0, 1),
            Child = grid
        };
    }
}
