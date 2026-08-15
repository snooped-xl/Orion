using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.Markup.Xaml;
using Avalonia.Media;
using Avalonia.Threading;
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;

namespace OrbitAvalonia;

public sealed partial class OrionWindow : Window
{
    private const double EditorWidth = 896.4d;
    private const double EditorHeight = 558d;
    private const double SpinnerDegreesPerSecond = 10d;
    private const uint SpiGetClientAreaAnimation = 0x1042;

    private static readonly TimeSpan LoadingFadeInDuration = TimeSpan.FromMilliseconds(600);
    private static readonly TimeSpan LoadingHoldDuration = TimeSpan.FromMilliseconds(900);
    private static readonly TimeSpan LoadingFadeDuration = TimeSpan.FromMilliseconds(350);
    private static readonly TimeSpan WindowMorphDuration = TimeSpan.FromMilliseconds(750);
    private static readonly TimeSpan EditorRevealDuration = TimeSpan.FromMilliseconds(500);

    private readonly Border _rootShell;
    private readonly Border _edgeStroke;
    private readonly Grid _loadingLayer;
    private readonly Viewbox _editorLayer;
    private readonly Image _spinnerMark;
    private readonly RotateTransform _spinnerRotation;
    private readonly DispatcherTimer _spinnerTimer;
    private readonly Stopwatch _spinnerClock = new();
    private readonly CancellationTokenSource _startupCancellation = new();
    private readonly string _startupInterface;
    private bool _morphCompleted;

    public OrionWindow() : this(OrbitPreferences.LastInterface)
    {
    }

    internal OrionWindow(string? startupInterface)
    {
        _startupInterface = string.IsNullOrWhiteSpace(startupInterface)
            ? OrbitPreferences.OrionInterface
            : startupInterface;
        AvaloniaXamlLoader.Load(this);

        _rootShell = this.FindControl<Border>("RootShell")
            ?? throw new InvalidOperationException("RootShell was not found.");
        _edgeStroke = this.FindControl<Border>("EdgeStroke")
            ?? throw new InvalidOperationException("EdgeStroke was not found.");
        _loadingLayer = this.FindControl<Grid>("LoadingLayer")
            ?? throw new InvalidOperationException("LoadingLayer was not found.");
        _editorLayer = this.FindControl<Viewbox>("EditorLayer")
            ?? throw new InvalidOperationException("EditorLayer was not found.");

        _spinnerMark = this.FindControl<Image>("SpinnerMark")
            ?? throw new InvalidOperationException("SpinnerMark was not found.");
        _spinnerRotation = _spinnerMark.RenderTransform as RotateTransform
            ?? new RotateTransform();
        _spinnerMark.RenderTransform = _spinnerRotation;

        _spinnerTimer = new DispatcherTimer
        {
            Interval = TimeSpan.FromMilliseconds(16)
        };
        _spinnerTimer.Tick += SpinnerTimer_Tick;

        InitializeOrionNavigation();
        InitializeOrionEditor();
        InitializeOrionPages();
        InitializeOrionPluginsPage();

        Opened += OrionWindow_Opened;
    }

    private void SpinnerTimer_Tick(object? sender, EventArgs e)
    {
        _spinnerRotation.Angle =
            (_spinnerClock.Elapsed.TotalSeconds * SpinnerDegreesPerSecond) % 360d;
    }

    private async void OrionWindow_Opened(object? sender, EventArgs e)
    {
        Opened -= OrionWindow_Opened;

        if (!string.Equals(_startupInterface, OrbitPreferences.OrionInterface, StringComparison.Ordinal))
        {
            // Orion remains alive as the shared workspace and Monaco host, but
            // it never becomes visible when the user previously chose another
            // interface. That UI can therefore open directly on the next run.
            PrepareOrionForPreservedUiStartup();
            await LaunchSelectedOrionInterfaceAsync(_startupInterface);
            return;
        }

        _spinnerClock.Start();
        _spinnerTimer.Start();

        try
        {
            await RunStartupSequenceAsync(_startupCancellation.Token);
        }
        catch (OperationCanceledException)
        {
            // Closing during startup cancels the remaining animation frames.
        }
        catch
        {
            // Never leave a live but transparent window behind if a frame fails.
            ShowEditorImmediately();
        }
    }

    private void PrepareOrionForPreservedUiStartup()
    {
        _spinnerTimer.Stop();
        _spinnerMark.Opacity = 0;
        _loadingLayer.Opacity = 0;
        _loadingLayer.IsVisible = false;
        _editorLayer.Opacity = 1;
        _editorLayer.IsHitTestVisible = false;
        ResizeWindowImmediately();
        ShowOrionPageImmediately(OrionPage.Editor);
        _morphCompleted = true;
    }

    private async Task RunStartupSequenceAsync(CancellationToken cancellationToken)
    {
        await AnimateAsync(
            LoadingFadeInDuration,
            progress => _spinnerMark.Opacity = progress,
            CubicEaseOut,
            cancellationToken);

        _spinnerMark.Opacity = 1;
        await Task.Delay(LoadingHoldDuration, cancellationToken);

        if (!AreClientAnimationsEnabled())
        {
            ResizeWindowImmediately();
            ShowEditorImmediately();
            return;
        }

        // Match Orbit's proven handoff: fade only the loading artwork first.
        await AnimateAsync(
            LoadingFadeDuration,
            progress => _spinnerMark.Opacity = 1d - progress,
            CubicEaseInOut,
            cancellationToken);

        _spinnerMark.Opacity = 0;
        _spinnerTimer.Stop();

        // Keep the opaque shell alive while the top-level window changes size.
        await AnimateWindowSizeAsync(
            EditorWidth,
            EditorHeight,
            WindowMorphDuration,
            cancellationToken);

        // The editor has remained laid out underneath the opaque loading layer,
        // so revealing it cannot depend on attaching a new visual after resize.
        _editorLayer.IsHitTestVisible = false;
        _editorLayer.InvalidateMeasure();
        _editorLayer.InvalidateArrange();
        _editorLayer.InvalidateVisual();
        _rootShell.InvalidateVisual();

        // Yield a normal frame so Avalonia can measure, arrange and render the
        // final-size editor before its opacity begins changing. Awaiting a
        // render-priority dispatcher operation here can stall a transparent
        // top-level window on Windows.
        await Task.Delay(32, cancellationToken);

        await AnimateAsync(
            EditorRevealDuration,
            progress => _loadingLayer.Opacity = 1d - progress,
            CubicEaseOut,
            cancellationToken);

        _loadingLayer.Opacity = 0;
        _loadingLayer.IsVisible = false;
        _editorLayer.IsHitTestVisible = true;
        _morphCompleted = true;
        RevealOrionEditor();
    }

    private async Task AnimateWindowSizeAsync(
        double targetWidth,
        double targetHeight,
        TimeSpan duration,
        CancellationToken cancellationToken)
    {
        var startWidth = Bounds.Width;
        var startHeight = Bounds.Height;
        var startPosition = Position;
        var scaling = Screens.ScreenFromWindow(this)?.Scaling ?? RenderScaling;
        var centreX = startPosition.X + (startWidth * scaling / 2d);
        var centreY = startPosition.Y + (startHeight * scaling / 2d);
        var targetX = centreX - (targetWidth * scaling / 2d);
        var targetY = centreY - (targetHeight * scaling / 2d);

        await AnimateAsync(
            duration,
            progress =>
            {
                Width = Lerp(startWidth, targetWidth, progress);
                Height = Lerp(startHeight, targetHeight, progress);
                Position = new PixelPoint(
                    (int)Math.Round(Lerp(startPosition.X, targetX, progress)),
                    (int)Math.Round(Lerp(startPosition.Y, targetY, progress)));
                var cornerRadius = new CornerRadius(Lerp(15d, 13.5d, progress));
                _rootShell.CornerRadius = cornerRadius;
                _edgeStroke.CornerRadius = cornerRadius;
            },
            CubicEaseInOut,
            cancellationToken);

        Width = targetWidth;
        Height = targetHeight;
        Position = new PixelPoint((int)Math.Round(targetX), (int)Math.Round(targetY));
        _rootShell.CornerRadius = new CornerRadius(13.5);
        _edgeStroke.CornerRadius = new CornerRadius(13.5);
        MinWidth = targetWidth;
        MinHeight = targetHeight;
    }

    private void ResizeWindowImmediately()
    {
        var scaling = Screens.ScreenFromWindow(this)?.Scaling ?? RenderScaling;
        var centreX = Position.X + (Bounds.Width * scaling / 2d);
        var centreY = Position.Y + (Bounds.Height * scaling / 2d);

        Width = EditorWidth;
        Height = EditorHeight;
        Position = new PixelPoint(
            (int)Math.Round(centreX - (EditorWidth * scaling / 2d)),
            (int)Math.Round(centreY - (EditorHeight * scaling / 2d)));
        _rootShell.CornerRadius = new CornerRadius(13.5);
        _edgeStroke.CornerRadius = new CornerRadius(13.5);
        MinWidth = EditorWidth;
        MinHeight = EditorHeight;
    }

    private void ShowEditorImmediately()
    {
        _spinnerTimer.Stop();
        _spinnerMark.Opacity = 0;
        _loadingLayer.Opacity = 0;
        _loadingLayer.IsVisible = false;
        _editorLayer.Opacity = 1;
        _editorLayer.IsHitTestVisible = true;
        _morphCompleted = true;
        RevealOrionEditor();
    }

    private static async Task AnimateAsync(
        TimeSpan duration,
        Action<double> update,
        Func<double, double> easing,
        CancellationToken cancellationToken)
    {
        var stopwatch = Stopwatch.StartNew();

        while (stopwatch.Elapsed < duration)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var progress = Math.Clamp(
                stopwatch.Elapsed.TotalMilliseconds / duration.TotalMilliseconds,
                0d,
                1d);
            update(easing(progress));
            // Target high-refresh displays without forcing a layout pass; the
            // animated properties are opacity and render transforms only.
            await Task.Delay(8, cancellationToken);
        }

        update(1d);
    }

    private static double CubicEaseInOut(double progress)
    {
        return progress < 0.5d
            ? 4d * progress * progress * progress
            : 1d - Math.Pow(-2d * progress + 2d, 3d) / 2d;
    }

    private static double CubicEaseOut(double progress)
    {
        return 1d - Math.Pow(1d - progress, 3d);
    }

    private static double Lerp(double start, double end, double progress)
    {
        return start + ((end - start) * progress);
    }

    private static bool AreClientAnimationsEnabled()
    {
        if (!RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
        {
            return true;
        }

        return !SystemParametersInfo(
                   SpiGetClientAreaAnimation,
                   0,
                   out var animationsEnabled,
                   0)
               || animationsEnabled;
    }

    [DllImport("user32.dll", SetLastError = false)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SystemParametersInfo(
        uint uiAction,
        uint uiParam,
        [MarshalAs(UnmanagedType.Bool)] out bool pvParam,
        uint fWinIni);

    private void TitleBar_PointerPressed(object? sender, PointerPressedEventArgs e)
    {
        if (_morphCompleted && e.GetCurrentPoint(this).Properties.IsLeftButtonPressed)
        {
            BeginMoveDrag(e);
        }
    }

    private void Minimize_Click(object? sender, RoutedEventArgs e)
    {
        WindowState = WindowState.Minimized;
    }

    private void Maximize_Click(object? sender, RoutedEventArgs e)
    {
        WindowState = WindowState == WindowState.Maximized
            ? WindowState.Normal
            : WindowState.Maximized;
    }

    private void Close_Click(object? sender, RoutedEventArgs e)
    {
        Close();
    }

    protected override void OnClosed(EventArgs e)
    {
        DisposeOrionNavigation();
        DisposeOrionPages();
        DisposeOrionEditor();
        _startupCancellation.Cancel();
        _startupCancellation.Dispose();
        _spinnerTimer.Stop();
        base.OnClosed(e);
    }
}
