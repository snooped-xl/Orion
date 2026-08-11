using Avalonia.Controls;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.Markup.Xaml;
using Avalonia.Media;
using Avalonia.Threading;
using System.Diagnostics;
using System.Globalization;
using Forms = System.Windows.Forms;

namespace OrbitAvalonia;

/// <summary>
/// Native, frontend-only Calamari preservation window. The original project
/// used a React Desktop macOS title bar and a remote status iframe; Orbit keeps
/// the visible shell and controls local so it remains deterministic and safe.
/// </summary>
public sealed partial class CalamariWindow : Window
{
    private readonly Action _returnToOrbit;
    private readonly UnifiedBridgeServer _bridgeServer = UnifiedBridgeServer.Shared;
    private readonly string _presetDirectory = Path.Combine(
        AppContext.BaseDirectory,
        "Scripts",
        "Calamari Defaults");
    private bool _closingForOrbit;

    private const string BridgeInstruction =
        "please execute the Orion Bridge in your executor.";

    private const string GiveBtoolsScript = """
        local backpack = game:GetService("Players").LocalPlayer.Backpack
        for _, binType in ipairs({1, 4, 3}) do
            local tool = Instance.new("HopperBin")
            tool.BinType = binType
            tool.Parent = backpack
        end
        """;

    public CalamariWindow() : this(static () => { })
    {
    }

    internal CalamariWindow(Action returnToOrbit)
    {
        _returnToOrbit = returnToOrbit;
        AvaloniaXamlLoader.Load(this);
        Topmost = OrbitPreferences.TopMostEnabled;
        CanResize = OrbitPreferences.ResizableEnabled;
        if (CanResize)
        {
            MinWidth = 521;
            MinHeight = 365;
        }

        Closed += CalamariWindow_Closed;
        _bridgeServer.ConnectionChanged += BridgeConnectionChanged;
    }

    private void CalamariWindow_Closed(object? sender, EventArgs e)
    {
        _bridgeServer.ConnectionChanged -= BridgeConnectionChanged;
        if (!_closingForOrbit)
        {
            _returnToOrbit();
        }
    }

    internal void CloseForOrbit()
    {
        _closingForOrbit = true;
        Close();
    }

    private void CloseToOrbit_Click(object? sender, RoutedEventArgs e)
    {
        _returnToOrbit();
    }

    private void Minimize_Click(object? sender, RoutedEventArgs e)
    {
        WindowState = WindowState.Minimized;
    }

    private void Login_Click(object? sender, RoutedEventArgs e)
    {
        // This preservation port deliberately has no account service. Any
        // username/password pair, including two blank fields, is accepted.
        if (this.FindControl<Grid>("LoginPage") is { } loginPage)
        {
            loginPage.IsVisible = false;
        }

        if (this.FindControl<Grid>("MainPage") is { } mainPage)
        {
            mainPage.IsVisible = true;
        }

        SetCalamariTab(executor: true);
        ApplyBridgeStatus(_bridgeServer.IsConnected);
    }

    private void ExecutorTab_Click(object? sender, RoutedEventArgs e) =>
        SetCalamariTab(executor: true);

    private void ToolsTab_Click(object? sender, RoutedEventArgs e) =>
        SetCalamariTab(executor: false);

    private void SetCalamariTab(bool executor)
    {
        if (this.FindControl<Canvas>("ExecutorTab") is { } executorPage)
        {
            executorPage.IsVisible = executor;
        }

        if (this.FindControl<Canvas>("ToolsTab") is { } toolsPage)
        {
            toolsPage.IsVisible = !executor;
        }

        if (this.FindControl<Button>("ExecutorTabButton") is { } executorButton)
        {
            executorButton.Classes.Set("calamari-tab-selected", executor);
        }

        if (this.FindControl<Button>("ToolsTabButton") is { } toolsButton)
        {
            toolsButton.Classes.Set("calamari-tab-selected", !executor);
        }
    }

    private void BridgeConnectionChanged(bool connected) =>
        Dispatcher.UIThread.Post(() => ApplyBridgeStatus(connected));

    private void ApplyBridgeStatus(bool connected)
    {
        SetOutput(
            connected ? "Orion Bridge connected." : BridgeInstruction,
            connected ? Color.Parse("#398849") : Color.Parse("#BE4039"));
    }

    private void SetOutput(string message, Color color)
    {
        if (this.FindControl<TextBox>("CalamariOutput") is not { } output)
        {
            return;
        }

        output.Text = message;
        output.Foreground = new SolidColorBrush(color);
    }

    private bool TryExecute(string source, string label)
    {
        if (!_bridgeServer.IsConnected)
        {
            ApplyBridgeStatus(false);
            return false;
        }

        if (string.IsNullOrWhiteSpace(source))
        {
            SetOutput("Nothing to execute.", Color.Parse("#BE4039"));
            return false;
        }

        _bridgeServer.EnqueueExecute(source);
        SetOutput($"Sent {label} through the Orion Bridge.", Color.Parse("#398849"));
        return true;
    }

    private void ExecuteEditor_Click(object? sender, RoutedEventArgs e)
    {
        var source = this.FindControl<TextBox>("CalamariEditor")?.Text ?? string.Empty;
        TryExecute(source, "editor script");
    }

    private void ExecuteRaw_Click(object? sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: string source })
        {
            TryExecute(source, "action");
        }
    }

    private async void ExecutePreset_Click(object? sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: string preset } ||
            !_bridgeServer.IsConnected)
        {
            ApplyBridgeStatus(false);
            return;
        }

        var presetRoot = Path.GetFullPath(_presetDirectory)
            .TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        var path = Path.GetFullPath(Path.Combine(_presetDirectory, preset + ".lua"));
        if (!path.StartsWith(presetRoot, StringComparison.OrdinalIgnoreCase) ||
            !File.Exists(path))
        {
            SetOutput($"Missing Calimari preset: {preset}.", Color.Parse("#BE4039"));
            return;
        }

        try
        {
            var source = await File.ReadAllTextAsync(path);
            TryExecute(source, preset);
        }
        catch (IOException exception)
        {
            SetOutput($"Could not read {preset}: {exception.Message}", Color.Parse("#BE4039"));
        }
        catch (UnauthorizedAccessException exception)
        {
            SetOutput($"Could not read {preset}: {exception.Message}", Color.Parse("#BE4039"));
        }
    }

    private void ExecuteNumericAction_Click(object? sender, RoutedEventArgs e)
    {
        var text = this.FindControl<TextBox>("CalamariNumberValue")?.Text ?? string.Empty;
        if (!double.TryParse(text, NumberStyles.Float, CultureInfo.InvariantCulture, out var value) &&
            !double.TryParse(text, NumberStyles.Float, CultureInfo.CurrentCulture, out value))
        {
            SetOutput("Enter a valid number first.", Color.Parse("#BE4039"));
            return;
        }

        var formatted = value.ToString("R", CultureInfo.InvariantCulture);
        var action = (sender as Button)?.Tag as string;
        var source = action switch
        {
            "walkspeed" =>
                $"game:GetService('Players').LocalPlayer.Character.Humanoid.WalkSpeed={formatted}",
            "jumppower" =>
                $"game:GetService('Players').LocalPlayer.Character.Humanoid.JumpHeight={formatted}; " +
                $"game:GetService('Players').LocalPlayer.Character.Humanoid.JumpPower={formatted}",
            "hipheight" =>
                $"game:GetService('Players').LocalPlayer.Character.Humanoid.HipHeight={formatted}",
            "gravity" => $"workspace.Gravity={formatted}",
            _ => string.Empty
        };

        TryExecute(source, "LocalPlayer action");
    }

    private void GiveBtools_Click(object? sender, RoutedEventArgs e) =>
        TryExecute(GiveBtoolsScript, "Give Btools");

    private void RefreshBridgeStatus_Click(object? sender, RoutedEventArgs e) =>
        ApplyBridgeStatus(_bridgeServer.IsConnected);

    private void OpenCalamariSaves_Click(object? sender, RoutedEventArgs e)
    {
        Directory.CreateDirectory(_presetDirectory);
        Process.Start(new ProcessStartInfo("explorer.exe", $"\"{_presetDirectory}\"")
        {
            UseShellExecute = true
        });
    }

    private void PasteClipboard_Click(object? sender, RoutedEventArgs e)
    {
        try
        {
            var text = Forms.Clipboard.ContainsText()
                ? Forms.Clipboard.GetText()
                : string.Empty;
            if (this.FindControl<TextBox>("CalamariEditor") is { } editor)
            {
                editor.Text = text;
                editor.CaretIndex = text.Length;
                editor.Focus();
            }
        }
        catch (Exception exception) when (
            exception is System.Runtime.InteropServices.ExternalException or ThreadStateException)
        {
            SetOutput("Clipboard access is currently unavailable.", Color.Parse("#BE4039"));
        }

    }

    private void BackToOrbit_Click(object? sender, RoutedEventArgs e) =>
        _returnToOrbit();

    private static void NoOp_Click(object? sender, RoutedEventArgs e)
    {
        // Calamari is a frontend-only preservation port for now.
    }

    private void TitleBar_PointerPressed(object? sender, PointerPressedEventArgs e)
    {
        if (e.Source is Button || !e.GetCurrentPoint(this).Properties.IsLeftButtonPressed)
        {
            return;
        }

        if (e.ClickCount == 2 && CanResize)
        {
            WindowState = WindowState == WindowState.Maximized
                ? WindowState.Normal
                : WindowState.Maximized;
            return;
        }

        BeginMoveDrag(e);
    }
}
