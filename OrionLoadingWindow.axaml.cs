using Avalonia.Controls;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Markup.Xaml;
using Avalonia.Media;
using Avalonia.Threading;
using System;
using System.Diagnostics;
using System.Threading.Tasks;

namespace OrbitAvalonia;

public sealed partial class OrionLoadingWindow : Window
{
    private readonly RotateTransform _spinnerRotation;
    private readonly DispatcherTimer _spinnerTimer;
    private readonly Stopwatch _spinnerClock = new();
    private bool _transitioned;

    public OrionLoadingWindow()
    {
        AvaloniaXamlLoader.Load(this);

        var spinnerMark = this.FindControl<Image>("SpinnerMark");
        _spinnerRotation = spinnerMark?.RenderTransform as RotateTransform
            ?? new RotateTransform();
        if (spinnerMark is not null)
        {
            spinnerMark.RenderTransform = _spinnerRotation;
        }
        _spinnerTimer = new DispatcherTimer
        {
            Interval = TimeSpan.FromMilliseconds(16)
        };
        _spinnerTimer.Tick += SpinnerTimer_Tick;
        Opened += LoadingWindow_Opened;
        Closed += (_, _) => _spinnerTimer.Stop();
    }

    private void SpinnerTimer_Tick(object? sender, EventArgs e)
    {
        _spinnerRotation.Angle = (_spinnerClock.Elapsed.TotalSeconds * 300d) % 360d;
    }

    private async void LoadingWindow_Opened(object? sender, EventArgs e)
    {
        Opened -= LoadingWindow_Opened;
        _spinnerClock.Start();
        _spinnerTimer.Start();

        await Task.Delay(TimeSpan.FromMilliseconds(1650));
        if (_transitioned || !IsVisible)
        {
            return;
        }

        _transitioned = true;
        _spinnerTimer.Stop();

        var editorWindow = new OrionWindow();
        if (Avalonia.Application.Current?.ApplicationLifetime
            is IClassicDesktopStyleApplicationLifetime desktop)
        {
            desktop.MainWindow = editorWindow;
        }

        editorWindow.Show();
        Close();
    }
}
