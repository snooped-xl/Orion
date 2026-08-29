using Avalonia;
using Avalonia.Controls;
using Avalonia.Media;
using Avalonia.Rendering.SceneGraph;
using Avalonia.Skia;
using Avalonia.Threading;
using SkiaSharp;
using System.Diagnostics;

namespace OrbitAvalonia;

/// <summary>
/// Draws Orion's restrained liquid-glass caustics behind the interface. The
/// operating system acrylic layer supplies real backdrop blur; this visual is
/// deliberately limited to refraction light, spectral edging and fine grain so
/// text and Monaco stay perfectly sharp.
/// </summary>
internal sealed class OrionLiquidGlassVisual : Control, IDisposable
{
    private readonly DispatcherTimer _timer;
    private readonly Stopwatch _clock = Stopwatch.StartNew();
    private Point _pointer = new(0.64, 0.22);
    private Point _targetPointer = new(0.64, 0.22);
    private bool _isEnabled;
    private bool _animationActive = true;
    private double _refraction = 0.14;
    private double _specular = 0.36;
    private double _noise = 0.012;
    private Color _accent = Color.Parse("#91B9FF");

    public OrionLiquidGlassVisual()
    {
        IsHitTestVisible = false;
        ClipToBounds = true;
        _timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(16) };
        _timer.Tick += OnFrame;
    }

    public void Configure(
        bool enabled,
        double refraction,
        double specular,
        double noise,
        Color accent)
    {
        _isEnabled = enabled;
        _refraction = Math.Clamp(refraction, 0, 1);
        _specular = Math.Clamp(specular, 0, 1);
        _noise = Math.Clamp(noise, 0, 0.12);
        _accent = accent;
        IsVisible = enabled;

        UpdateTimerState();
        InvalidateVisual();
    }

    public void SetAnimationActive(bool active)
    {
        _animationActive = active;
        UpdateTimerState();
    }

    private void UpdateTimerState()
    {
        if (_isEnabled && _animationActive)
        {
            if (!_timer.IsEnabled)
            {
                _clock.Restart();
                _timer.Start();
            }
        }
        else
        {
            _timer.Stop();
        }
    }

    public void SetPointer(Point point)
    {
        if (Bounds.Width <= 1 || Bounds.Height <= 1)
        {
            return;
        }

        _targetPointer = new Point(
            Math.Clamp(point.X / Bounds.Width, 0, 1),
            Math.Clamp(point.Y / Bounds.Height, 0, 1));
    }

    private void OnFrame(object? sender, EventArgs e)
    {
        if (!_isEnabled)
        {
            return;
        }

        // The slow interpolation is the lens inertia used by Apple's glass:
        // it follows the pointer without turning into a distracting spotlight.
        _pointer = new Point(
            _pointer.X + ((_targetPointer.X - _pointer.X) * 0.075),
            _pointer.Y + ((_targetPointer.Y - _pointer.Y) * 0.075));
        InvalidateVisual();
    }

    public override void Render(DrawingContext context)
    {
        base.Render(context);
        if (!_isEnabled || Bounds.Width <= 1 || Bounds.Height <= 1)
        {
            return;
        }

        context.Custom(new GlassDrawOperation(
            new Rect(Bounds.Size),
            _pointer,
            _clock.Elapsed.TotalSeconds,
            _refraction,
            _specular,
            _noise,
            _accent));
    }

    public void Dispose()
    {
        _timer.Stop();
        _timer.Tick -= OnFrame;
    }

    private sealed class GlassDrawOperation : ICustomDrawOperation
    {
        private readonly Point _pointer;
        private readonly double _time;
        private readonly double _refraction;
        private readonly double _specular;
        private readonly double _noise;
        private readonly Color _accent;

        public GlassDrawOperation(
            Rect bounds,
            Point pointer,
            double time,
            double refraction,
            double specular,
            double noise,
            Color accent)
        {
            Bounds = bounds;
            _pointer = pointer;
            _time = time;
            _refraction = refraction;
            _specular = specular;
            _noise = noise;
            _accent = accent;
        }

        public Rect Bounds { get; }

        public bool HitTest(Point point) => false;

        public bool Equals(ICustomDrawOperation? other) => false;

        public void Render(ImmediateDrawingContext context)
        {
            var leaseFeature = context.TryGetFeature<ISkiaSharpApiLeaseFeature>();
            if (leaseFeature is null)
            {
                return;
            }

            using var lease = leaseFeature.Lease();
            var canvas = lease.SkCanvas;
            var width = (float)Bounds.Width;
            var height = (float)Bounds.Height;
            if (width <= 1 || height <= 1)
            {
                return;
            }

            canvas.Save();

            var pointerX = (float)(_pointer.X * width);
            var pointerY = (float)(_pointer.Y * height);
            var driftX = (float)(Math.Sin(_time * 0.31) * width * 0.025);
            var driftY = (float)(Math.Cos(_time * 0.27) * height * 0.02);
            var accent = new SKColor(_accent.R, _accent.G, _accent.B);

            // A broad optical lens follows the pointer. Its centre is fully
            // transparent; only the refractive shoulder catches light.
            using (var lensPaint = new SKPaint { IsAntialias = true })
            using (var lensShader = SKShader.CreateRadialGradient(
                       new SKPoint(pointerX + driftX, pointerY + driftY),
                       Math.Max(width, height) * 0.72f,
                       [
                           new SKColor(accent.Red, accent.Green, accent.Blue, 0),
                           new SKColor(accent.Red, accent.Green, accent.Blue, (byte)(12 + (30 * _refraction))),
                           new SKColor(255, 255, 255, (byte)(9 + (28 * _specular))),
                           new SKColor(accent.Red, accent.Green, accent.Blue, 0)
                       ],
                       [0f, 0.42f, 0.73f, 1f],
                       SKShaderTileMode.Clamp))
            {
                lensPaint.Shader = lensShader;
                canvas.DrawRect(0, 0, width, height, lensPaint);
            }

            // Two gently curved caustics provide the visible "warp" cue. They
            // are rendered behind the interface and never distort text.
            DrawCaustic(canvas, width, height, pointerX, pointerY, accent, phase: 0);
            DrawCaustic(canvas, width, height, pointerX, pointerY, accent, phase: 2.17);

            if (_noise > 0.001)
            {
                DrawGrain(canvas, width, height);
            }

            canvas.Restore();
        }

        private void DrawCaustic(
            SKCanvas canvas,
            float width,
            float height,
            float pointerX,
            float pointerY,
            SKColor accent,
            double phase)
        {
            var wave = (float)Math.Sin((_time * 0.38) + phase);
            var y = pointerY + (wave * height * 0.13f) + ((float)phase * 9f);
            using var path = new SKPath();
            path.MoveTo(-width * 0.08f, y - (height * 0.08f));
            path.CubicTo(
                width * 0.24f,
                y + (height * (0.11f + (0.03f * wave))),
                pointerX - (width * 0.12f),
                y - (height * 0.14f),
                pointerX + (width * 0.1f),
                y);
            path.CubicTo(
                pointerX + (width * 0.26f),
                y + (height * 0.12f),
                width * 0.83f,
                y - (height * 0.09f),
                width * 1.08f,
                y + (height * 0.04f));

            var alpha = (byte)(8 + (54 * _refraction));
            using var blur = SKMaskFilter.CreateBlur(SKBlurStyle.Normal, 12 + (float)(_refraction * 14));
            using var paint = new SKPaint
            {
                IsAntialias = true,
                Style = SKPaintStyle.Stroke,
                StrokeWidth = 1.2f + (float)(_refraction * 3.4),
                Color = new SKColor(accent.Red, accent.Green, accent.Blue, alpha),
                MaskFilter = blur
            };
            canvas.DrawPath(path, paint);
        }

        private void DrawGrain(SKCanvas canvas, float width, float height)
        {
            var alpha = (byte)Math.Clamp(_noise * 255, 1, 24);
            using var paint = new SKPaint
            {
                IsAntialias = true,
                Color = new SKColor(255, 255, 255, alpha)
            };

            // Stable blue-noise-like points: no per-frame allocations or
            // flicker, just enough texture to stop flat acrylic banding.
            for (var index = 0; index < 72; index++)
            {
                var x = ((index * 73) % 101) / 101f * width;
                var y = ((index * 47 + 19) % 103) / 103f * height;
                canvas.DrawCircle(x, y, 0.45f, paint);
            }
        }

        public void Dispose()
        {
        }
    }
}
