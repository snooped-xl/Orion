using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Platform;
using Avalonia.Threading;
using System.Runtime.InteropServices;

namespace OrbitAvalonia;

public sealed partial class MainWindow
{
    private const double ResizeFollowFactor = 0.78;

    private DispatcherTimer _windowMotionTimer = null!;
    private InputElement? _windowMotionCaptureElement;
    private IPointer? _windowMotionPointer;
    private CancellationTokenSource? _windowBoundsAnimationCancellation;
    private PixelPoint _windowMotionTargetPosition;
    private Size _windowMotionTargetSize;
    private PixelPoint _animatedRestorePosition;
    private Size _animatedRestoreSize = new(MainWindowWidth, MainWindowHeight);
    private WindowEdge _smoothResizeEdge;
    private double _windowMotionScale = 1;
    private double _resizeStartLeft;
    private double _resizeStartTop;
    private double _resizeStartRight;
    private double _resizeStartBottom;
    private bool _windowMotionTracking;
    private bool _smoothMotionIsResize;
    private bool _animatedMaximized;
    private bool _windowsSnapResizeEnabled;

    private const int GwlStyle = -16;
    private const long WsThickFrame = 0x00040000L;
    private const long WsMaximizeBox = 0x00010000L;
    private const long WsMinimizeBox = 0x00020000L;
    private const uint SwpNoSize = 0x0001;
    private const uint SwpNoMove = 0x0002;
    private const uint SwpNoZOrder = 0x0004;
    private const uint SwpNoActivate = 0x0010;
    private const uint SwpFrameChanged = 0x0020;

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW", SetLastError = true)]
    private static extern IntPtr GetWindowLongPtr(IntPtr windowHandle, int index);

    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW", SetLastError = true)]
    private static extern IntPtr SetWindowLongPtr(IntPtr windowHandle, int index, IntPtr value);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool SetWindowPos(
        IntPtr windowHandle,
        IntPtr insertAfter,
        int x,
        int y,
        int width,
        int height,
        uint flags);

    private bool IsWindowVisuallyMaximized =>
        WindowState == WindowState.Maximized ||
        _animatedMaximized;

    private bool SmoothResizeAnimationActive =>
        _smoothMotionIsResize && _windowMotionTimer.IsEnabled;

    private void InitializeWindowMotion()
    {
        _windowMotionTargetPosition = Position;
        _windowMotionTargetSize = Bounds.Size;
        _animatedRestorePosition = Position;

        _windowMotionTimer = new DispatcherTimer
        {
            Interval = TimeSpan.FromMilliseconds(16)
        };
        _windowMotionTimer.Tick += (_, _) => AdvanceSmoothWindowMotion();

        PointerMoved += WindowMotion_PointerMoved;
        PointerReleased += WindowMotion_PointerReleased;
        Deactivated += (_, _) => ReleaseSmoothWindowMotion();
    }

    private void EnableWindowsSnapResize()
    {
        if (_windowsSnapResizeEnabled ||
            !OrbitPreferences.ResizableEnabled ||
            !OperatingSystem.IsWindows())
        {
            return;
        }

        var platformHandle = TryGetPlatformHandle();
        if (platformHandle is null || platformHandle.Handle == IntPtr.Zero)
        {
            return;
        }

        var windowHandle = platformHandle.Handle;
        var currentStyle = GetWindowLongPtr(windowHandle, GwlStyle).ToInt64();
        var snapStyle = currentStyle | WsThickFrame | WsMaximizeBox | WsMinimizeBox;
        if (snapStyle != currentStyle)
        {
            SetWindowLongPtr(windowHandle, GwlStyle, new IntPtr(snapStyle));
            SetWindowPos(
                windowHandle,
                IntPtr.Zero,
                0,
                0,
                0,
                0,
                SwpNoSize | SwpNoMove | SwpNoZOrder | SwpNoActivate | SwpFrameChanged);
        }

        _windowsSnapResizeEnabled = true;
    }

    private void DisableWindowsSnapResize()
    {
        if (!OperatingSystem.IsWindows())
        {
            _windowsSnapResizeEnabled = false;
            return;
        }

        var platformHandle = TryGetPlatformHandle();
        if (platformHandle is null || platformHandle.Handle == IntPtr.Zero)
        {
            _windowsSnapResizeEnabled = false;
            return;
        }

        var windowHandle = platformHandle.Handle;
        var currentStyle = GetWindowLongPtr(windowHandle, GwlStyle).ToInt64();
        var fixedStyle = currentStyle & ~WsThickFrame & ~WsMaximizeBox;
        if (fixedStyle != currentStyle)
        {
            SetWindowLongPtr(windowHandle, GwlStyle, new IntPtr(fixedStyle));
            SetWindowPos(
                windowHandle,
                IntPtr.Zero,
                0,
                0,
                0,
                0,
                SwpNoSize | SwpNoMove | SwpNoZOrder | SwpNoActivate | SwpFrameChanged);
        }

        _windowsSnapResizeEnabled = false;
    }

    private void ApplyResizablePreference(bool enabled)
    {
        if (!enabled)
        {
            CancelWindowBoundsAnimation();
            ReleaseSmoothWindowMotion();
            _windowMotionTimer.Stop();
            _smoothMotionIsResize = false;

            if (_animatedMaximized)
            {
                Position = _animatedRestorePosition;
                Width = _animatedRestoreSize.Width;
                Height = _animatedRestoreSize.Height;
                _animatedMaximized = false;
            }
            else if (WindowState == WindowState.Maximized)
            {
                WindowState = WindowState.Normal;
            }
        }

        CanResize = enabled;
        if (enabled)
        {
            EnableWindowsSnapResize();
        }
        else
        {
            DisableWindowsSnapResize();
        }

        UpdateWindowChromeForState();
    }

    private void BeginSmoothWindowResize(
        WindowEdge edge,
        InputElement resizeHandle,
        PointerPressedEventArgs e)
    {
        if (!OrbitPreferences.ResizableEnabled ||
            IsWindowVisuallyMaximized)
        {
            return;
        }

        CancelWindowBoundsAnimation();
        BeginResponsiveResize(edge);
        _resizeEdgeReleaseTimer.Stop();
        _smoothResizeEdge = edge;
        _smoothMotionIsResize = true;
        _windowMotionTracking = true;
        _windowMotionPointer = e.Pointer;
        _windowMotionCaptureElement = resizeHandle;
        _windowMotionScale = Screens.ScreenFromWindow(this)?.Scaling ?? 1;
        _windowMotionTargetPosition = Position;
        _windowMotionTargetSize = Bounds.Size;

        _resizeStartLeft = Position.X;
        _resizeStartTop = Position.Y;
        _resizeStartRight = _resizeStartLeft + (Bounds.Width * _windowMotionScale);
        _resizeStartBottom = _resizeStartTop + (Bounds.Height * _windowMotionScale);

        e.Pointer.Capture(resizeHandle);
        UpdateSmoothWindowMotionTarget(e);
        _windowMotionTimer.Start();
        e.Handled = true;
    }

    private void WindowMotion_PointerMoved(object? sender, PointerEventArgs e)
    {
        if (!_windowMotionTracking || e.Pointer != _windowMotionPointer)
        {
            return;
        }

        UpdateSmoothWindowMotionTarget(e);
        e.Handled = true;
    }

    private void WindowMotion_PointerReleased(object? sender, PointerReleasedEventArgs e)
    {
        if (!_windowMotionTracking || e.Pointer != _windowMotionPointer)
        {
            return;
        }

        UpdateSmoothWindowMotionTarget(e);
        ReleaseSmoothWindowMotion();
        e.Handled = true;
    }

    private void UpdateSmoothWindowMotionTarget(PointerEventArgs e)
    {
        var pointerScreen = GetPointerScreenPosition(e);
        var left = _resizeStartLeft;
        var top = _resizeStartTop;
        var right = _resizeStartRight;
        var bottom = _resizeStartBottom;
        var minimumWidth = Math.Max(MainWindowWidth, MinWidth) * _windowMotionScale;
        var minimumHeight = Math.Max(MainWindowHeight, MinHeight) * _windowMotionScale;

        if (_smoothResizeEdge is WindowEdge.West or WindowEdge.NorthWest or WindowEdge.SouthWest)
        {
            left = Math.Min(pointerScreen.X, _resizeStartRight - minimumWidth);
        }
        else if (_smoothResizeEdge is WindowEdge.East or WindowEdge.NorthEast or WindowEdge.SouthEast)
        {
            right = Math.Max(pointerScreen.X, _resizeStartLeft + minimumWidth);
        }

        if (_smoothResizeEdge is WindowEdge.North or WindowEdge.NorthWest or WindowEdge.NorthEast)
        {
            top = Math.Min(pointerScreen.Y, _resizeStartBottom - minimumHeight);
        }
        else if (_smoothResizeEdge is WindowEdge.South or WindowEdge.SouthWest or WindowEdge.SouthEast)
        {
            bottom = Math.Max(pointerScreen.Y, _resizeStartTop + minimumHeight);
        }

        _windowMotionTargetPosition = new PixelPoint(
            (int)Math.Round(left),
            (int)Math.Round(top));
        _windowMotionTargetSize = new Size(
            Math.Max(MainWindowWidth, (right - left) / _windowMotionScale),
            Math.Max(MainWindowHeight, (bottom - top) / _windowMotionScale));
    }

    private void AdvanceSmoothWindowMotion()
    {
        var factor = ResizeFollowFactor;
        var nextX = Lerp(Position.X, _windowMotionTargetPosition.X, factor);
        var nextY = Lerp(Position.Y, _windowMotionTargetPosition.Y, factor);
        var nextWidth = Lerp(Bounds.Width, _windowMotionTargetSize.Width, factor);
        var nextHeight = Lerp(Bounds.Height, _windowMotionTargetSize.Height, factor);

        Position = new PixelPoint(
            (int)Math.Round(nextX),
            (int)Math.Round(nextY));

        Width = nextWidth;
        Height = nextHeight;
        UpdateResponsiveDesignSurface(new Size(nextWidth, nextHeight));

        if (_windowMotionTracking || !WindowMotionIsSettled())
        {
            return;
        }

        Position = _windowMotionTargetPosition;
        Width = _windowMotionTargetSize.Width;
        Height = _windowMotionTargetSize.Height;
        UpdateResponsiveDesignSurface(_windowMotionTargetSize);
        RebuildEditorTabs();

        _windowMotionTimer.Stop();
        _smoothMotionIsResize = false;
    }

    private bool WindowMotionIsSettled() =>
        Math.Abs(Position.X - _windowMotionTargetPosition.X) <= 1 &&
        Math.Abs(Position.Y - _windowMotionTargetPosition.Y) <= 1 &&
        Math.Abs(Bounds.Width - _windowMotionTargetSize.Width) <= 0.5 &&
        Math.Abs(Bounds.Height - _windowMotionTargetSize.Height) <= 0.5;

    private void ReleaseSmoothWindowMotion()
    {
        if (!_windowMotionTracking)
        {
            return;
        }

        _windowMotionTracking = false;
        _windowMotionPointer?.Capture(null);
        _windowMotionPointer = null;
        _windowMotionCaptureElement = null;
    }

    private Task ToggleMaximizeAnimatedAsync()
    {
        if (!OrbitPreferences.ResizableEnabled ||
            !_startupLayoutComplete)
        {
            return Task.CompletedTask;
        }

        ReleaseSmoothWindowMotion();
        _windowMotionTimer.Stop();
        _smoothMotionIsResize = false;

        if (WindowState == WindowState.Maximized)
        {
            WindowState = WindowState.Normal;
            _animatedMaximized = false;
            return Task.CompletedTask;
        }

        // Do not interpolate Position/Width/Height here.  The Windows snap
        // frame is deliberately enabled for real edge/corner resizing and
        // Windows 11 snap layouts.  Manually animating the same bounds races
        // that native frame; on maximize Windows reaches the full monitor
        // rectangle while Avalonia can still be measuring the old 996px
        // design canvas.  WindowState is the single authoritative transition,
        // and MainWindow_PropertyChanged refreshes the responsive layout from
        // the resulting bounds.
        _animatedRestorePosition = Position;
        _animatedRestoreSize = Bounds.Size;
        _animatedMaximized = false;
        WindowState = WindowState.Maximized;
        return Task.CompletedTask;
    }

    private void CancelWindowBoundsAnimation()
    {
        _windowBoundsAnimationCancellation?.Cancel();
        _windowBoundsAnimationCancellation?.Dispose();
        _windowBoundsAnimationCancellation = null;
    }

    private PixelPoint GetPointerScreenPosition(PointerEventArgs e)
    {
        if (OperatingSystem.IsWindows() && GetCursorPos(out var cursor))
        {
            return new PixelPoint(cursor.X, cursor.Y);
        }

        var relative = e.GetPosition(this);
        var scaling = Screens.ScreenFromWindow(this)?.Scaling ?? 1;
        return new PixelPoint(
            Position.X + (int)Math.Round(relative.X * scaling),
            Position.Y + (int)Math.Round(relative.Y * scaling));
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NativePoint
    {
        public int X;
        public int Y;
    }

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetCursorPos(out NativePoint point);
}
