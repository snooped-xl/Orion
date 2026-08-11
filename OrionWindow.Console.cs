using Avalonia.Animation.Easings;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.Media;
using Avalonia.Rendering.Composition;
using Avalonia.Threading;
using System.Numerics;

namespace OrbitAvalonia;

public sealed partial class OrionWindow
{
    private const double OrionMonacoClosedHeight = 380.7d;
    private const double OrionMonacoConsoleHeight = 188.1d;
    private const float OrionConsoleCanvasLeft = 7.333f;
    private const float OrionConsoleCanvasTop = 229.333f;

    private static readonly TimeSpan OrionConsoleAnimationDuration =
        TimeSpan.FromMilliseconds(260);

    private Border _orionConsolePanel = null!;
    private StackPanel _orionConsoleOutput = null!;
    private bool _orionConsoleOpen;
    private bool _orionConsoleTransitionActive;
    private bool _orionConsoleDisposed;

    private void InitializeOrionConsole()
    {
        _orionConsolePanel = this.FindControl<Border>("OrionConsolePanel")
            ?? throw new InvalidOperationException("OrionConsolePanel was not found.");
        _orionConsoleOutput = this.FindControl<StackPanel>("OrionConsoleOutput")
            ?? throw new InvalidOperationException("OrionConsoleOutput was not found.");

        _orionConsolePanel.IsVisible = false;
        _orionConsolePanel.IsHitTestVisible = false;
        _orionConsolePanel.Opacity = 0;
        foreach (var entry in _orionBridge.GetLogSnapshot())
        {
            AppendOrionConsoleLine(entry.Level, entry.Message);
        }
        _orionBridge.LogReceived += OrionBridge_LogReceived;
    }

    private void OrionBridge_LogReceived(string level, string message) =>
        Dispatcher.UIThread.Post(() => AppendOrionConsoleLine(level, message));

    private void AppendOrionConsoleLine(string level, string message)
    {
        if (_orionConsoleDisposed || _orionConsoleOutput is null) return;
        var normalized = string.IsNullOrWhiteSpace(level) ? "info" : level.ToLowerInvariant();
        var prefix = normalized switch
        {
            "warn" or "warning" => "[warn]   ",
            "error" => "[error]  ",
            "print" or "output" => "[print]  ",
            _ => "[info]   "
        };
        var color = normalized switch
        {
            "warn" or "warning" => "#C8A25A",
            "error" => "#D06B6B",
            _ => "#B8B8BA"
        };
        var line = new TextBlock
        {
            Text = prefix + message,
            FontFamily = new FontFamily("Consolas"),
            FontSize = 8,
            FontWeight = FontWeight.Normal,
            Foreground = new SolidColorBrush(Color.Parse(color)),
            TextWrapping = TextWrapping.Wrap
        };
        _orionConsoleOutput.Children.Add(line);
        while (_orionConsoleOutput.Children.Count > 250)
        {
            _orionConsoleOutput.Children.RemoveAt(0);
        }
        Dispatcher.UIThread.Post(line.BringIntoView, DispatcherPriority.Background);
    }

    private void OrionConsoleClear_Click(object? sender, RoutedEventArgs e) =>
        _orionConsoleOutput.Children.Clear();

    private void OrionUtilityButton_PointerEntered(object? sender, PointerEventArgs e)
    {
        SetOrionUtilityHover(sender, 1d);
    }

    private void OrionUtilityButton_PointerExited(object? sender, PointerEventArgs e)
    {
        SetOrionUtilityHover(sender, 0d);
    }

    private void SetOrionUtilityHover(object? sender, double opacity)
    {
        if (sender is not Button { Tag: string overlayName } ||
            this.FindControl<Control>(overlayName) is not { } overlay)
        {
            return;
        }

        overlay.Opacity = opacity;
    }

    private async void OrionConsoleToggle_Click(object? sender, RoutedEventArgs e)
    {
        if (_orionConsoleDisposed || _orionConsoleTransitionActive)
        {
            return;
        }

        _orionConsoleTransitionActive = true;
        try
        {
            if (_orionConsoleOpen)
            {
                await CloseOrionConsoleAsync();
            }
            else
            {
                await OpenOrionConsoleAsync();
            }
        }
        catch (OperationCanceledException)
        {
            // Window shutdown cancels any in-flight visual handoff.
        }
        finally
        {
            _orionConsoleTransitionActive = false;
        }
    }

    private async Task OpenOrionConsoleAsync()
    {
        // NativeWebView owns a child HWND and will always render over Avalonia
        // content. Resize it first so the native surface and console split
        // remain perfectly adjacent instead of visually overlapping.
        _orionMonacoWebView.Height = OrionMonacoConsoleHeight;
        _orionConsolePanel.IsVisible = true;
        _orionConsolePanel.IsHitTestVisible = true;
        _orionConsolePanel.Opacity = 1;

        StartOrionConsoleAnimation(
            fromY: 18,
            toY: 0,
            fromOpacity: 0,
            toOpacity: 1);

        await Task.Delay(
            OrionConsoleAnimationDuration,
            _orionEditorCancellation.Token);
        _orionConsoleOpen = true;
    }

    private async Task CloseOrionConsoleAsync()
    {
        StartOrionConsoleAnimation(
            fromY: 0,
            toY: 18,
            fromOpacity: 1,
            toOpacity: 0);

        await Task.Delay(
            OrionConsoleAnimationDuration,
            _orionEditorCancellation.Token);

        _orionConsolePanel.IsHitTestVisible = false;
        _orionConsolePanel.IsVisible = false;
        _orionConsolePanel.Opacity = 0;
        _orionMonacoWebView.Height = OrionMonacoClosedHeight;
        _orionConsoleOpen = false;
    }

    private void StartOrionConsoleAnimation(
        float fromY,
        float toY,
        float fromOpacity,
        float toOpacity)
    {
        var visual = ElementComposition.GetElementVisual(_orionConsolePanel);
        if (visual is null)
        {
            return;
        }

        visual.StopAnimation("Offset");
        visual.StopAnimation("Opacity");

        var easing = new SplineEasing(0.16, 1, 0.3, 1);
        var offset = visual.Compositor.CreateVector3KeyFrameAnimation();
        offset.Duration = OrionConsoleAnimationDuration;
        offset.InsertKeyFrame(
            0,
            new Vector3(
                OrionConsoleCanvasLeft,
                OrionConsoleCanvasTop + fromY,
                0));
        offset.InsertKeyFrame(
            1,
            new Vector3(
                OrionConsoleCanvasLeft,
                OrionConsoleCanvasTop + toY,
                0),
            easing);

        var opacity = visual.Compositor.CreateScalarKeyFrameAnimation();
        opacity.Duration = OrionConsoleAnimationDuration;
        opacity.InsertKeyFrame(0, fromOpacity);
        opacity.InsertKeyFrame(1, toOpacity, easing);

        visual.StartAnimation("Offset", offset);
        visual.StartAnimation("Opacity", opacity);
    }

    private void DisposeOrionConsole()
    {
        _orionConsoleDisposed = true;
        _orionBridge.LogReceived -= OrionBridge_LogReceived;
        if (_orionConsolePanel is null)
        {
            return;
        }

        if (ElementComposition.GetElementVisual(_orionConsolePanel) is { } visual)
        {
            visual.StopAnimation("Offset");
            visual.StopAnimation("Opacity");
        }
    }
}
