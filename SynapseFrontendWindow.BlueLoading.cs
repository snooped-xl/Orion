using Avalonia;
using Avalonia.Animation.Easings;
using Avalonia.Controls;
using Avalonia.Controls.Shapes;
using Avalonia.Input;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Media.Imaging;
using Avalonia.Platform;
using Avalonia.Threading;
using System.Diagnostics;
using ShapePath = Avalonia.Controls.Shapes.Path;

namespace OrbitAvalonia;

internal sealed partial class SynapseFrontendWindow
{
    private const double BlueInitializationWidth = 290;
    private const double BlueInitializationHeight = 355;
    private const double BlueInitializationBarTop = 170;
    private const double BlueInitializationBarHeight = 160;
    private const double BlueInitializationPanelTop = 163;
    private const double BlueInitializationPanelStep = 51;
    private const double BlueInitializationProgressStartMs = 800;
    private const double BlueInitializationProgressDurationMs = 6000;
    private const double BlueInitializationExitFadeStartMs = 6820;
    private const double BlueInitializationMorphStartMs = 7340;
    private const double BlueInitializationMorphDurationMs = 580;

    private static readonly SplineEasing BlueEaseInOut = new(0.4, 0, 0.2, 1);

    private Control? _blueFinalShell;
    private Grid? _blueInitializationContent;
    private Canvas? _blueInitializationSecondary;
    private Border? _blueInitializationProgressFill;
    private readonly List<SolidColorBrush> _blueInitializationDotBrushes = [];
    private Border? _blueInitializationStepPanel;
    private Grid? _blueInitializationStepCopy;
    private TextBlock? _blueInitializationStepTitle;
    private TextBlock? _blueInitializationStepDescription;
    private CancellationTokenSource? _blueInitializationCancellation;
    private bool _blueInitializationActive;
    private bool _blueMorphConstraintsReleased;
    private int _blueInitializationDisplayedStep = -1;

    private Control BuildBlueInitializationShell()
    {
        _blueInitializationActive = true;
        var root = new Border
        {
            Background = Brush("#242424"),
            ClipToBounds = true
        };
        root.PointerPressed += BlueInitializationPointerPressed;

        var content = new Grid
        {
            Width = BlueInitializationWidth,
            Height = BlueInitializationHeight,
            HorizontalAlignment = HorizontalAlignment.Left,
            VerticalAlignment = VerticalAlignment.Top,
            Opacity = 0
        };
        _blueInitializationContent = content;

        var canvas = new Canvas
        {
            Width = BlueInitializationWidth,
            Height = BlueInitializationHeight
        };
        content.Children.Add(canvas);

        var header = new ShapePath
        {
            Width = BlueInitializationWidth,
            Height = 128,
            Data = Geometry.Parse("M0 0H290V128L146.5 112L0 95V0Z"),
            Stretch = Stretch.None,
            Fill = new LinearGradientBrush
            {
                StartPoint = new RelativePoint(0, 0, RelativeUnit.Relative),
                EndPoint = new RelativePoint(0, 1, RelativeUnit.Relative),
                GradientStops =
                {
                    new GradientStop(Color.Parse("#233DA3"), 0),
                    new GradientStop(Color.Parse("#323F89"), 0.723454),
                    new GradientStop(Color.Parse("#323F89"), 1)
                }
            },
            Effect = new DropShadowEffect
            {
                Color = Colors.Black,
                BlurRadius = 16.3,
                OffsetY = 11,
                Opacity = 0.41
            }
        };
        canvas.Children.Add(header);

        using (var logoStream = AssetLoader.Open(new Uri("avares://Orion/Assets/Synapse/blue-wordmark.png")))
        {
            var logo = new Image
            {
                Source = new Bitmap(logoStream),
                Width = 208,
                Height = 43,
                Stretch = Stretch.Uniform,
                HorizontalAlignment = HorizontalAlignment.Left,
                VerticalAlignment = VerticalAlignment.Top
            };
            RenderOptions.SetBitmapInterpolationMode(logo, BitmapInterpolationMode.HighQuality);
            Canvas.SetLeft(logo, 10);
            Canvas.SetTop(logo, 10);
            canvas.Children.Add(logo);
        }

        var welcome = BlueInitializationText("Let's get scripting.", 20, FontWeight.Normal, 280);
        Canvas.SetLeft(welcome, 10);
        Canvas.SetTop(welcome, 58);
        canvas.Children.Add(welcome);

        var secondary = new Canvas
        {
            Width = BlueInitializationWidth,
            Height = BlueInitializationHeight,
            Opacity = 0
        };
        _blueInitializationSecondary = secondary;
        var initializing = BlueInitializationText("Initializing...", 18, FontWeight.Normal, 280);
        Canvas.SetLeft(initializing, 10);
        Canvas.SetTop(initializing, 119);
        secondary.Children.Add(initializing);
        var subheading = BlueInitializationText("This won't take long.", 13, FontWeight.Normal, 280);
        Canvas.SetLeft(subheading, 10);
        Canvas.SetTop(subheading, 137);
        secondary.Children.Add(subheading);
        canvas.Children.Add(secondary);

        var track = new Border
        {
            Width = 14,
            Height = BlueInitializationBarHeight,
            Background = Brush("#383838")
        };
        Canvas.SetLeft(track, 11);
        Canvas.SetTop(track, BlueInitializationBarTop);
        canvas.Children.Add(track);

        var progress = new Border
        {
            Width = 14,
            Height = 0,
            Background = Brush("#2D3EA1"),
            VerticalAlignment = VerticalAlignment.Top
        };
        _blueInitializationProgressFill = progress;
        Canvas.SetLeft(progress, 11);
        Canvas.SetTop(progress, BlueInitializationBarTop);
        canvas.Children.Add(progress);

        for (var index = 0; index < 4; index++)
        {
            var dotBrush = Brush("#414141");
            _blueInitializationDotBrushes.Add(dotBrush);
            var dot = new Ellipse
            {
                Width = 20,
                Height = 20,
                Fill = dotBrush,
                Stroke = Brush("#585858"),
                StrokeThickness = 1
            };
            Canvas.SetLeft(dot, 8);
            Canvas.SetTop(dot, BlueInitializationPanelTop + index * BlueInitializationPanelStep);
            canvas.Children.Add(dot);
        }

        _blueInitializationStepTitle = new TextBlock
        {
            Foreground = Brushes.White,
            FontFamily = new FontFamily("avares://Avalonia.Fonts.Inter/Assets#Inter"),
            FontSize = 13,
            FontWeight = FontWeight.Black,
            TextTrimming = TextTrimming.CharacterEllipsis,
            VerticalAlignment = VerticalAlignment.Top
        };
        _blueInitializationStepDescription = new TextBlock
        {
            Foreground = Brushes.White,
            FontFamily = new FontFamily("avares://Avalonia.Fonts.Inter/Assets#Inter"),
            FontSize = 9,
            FontWeight = FontWeight.SemiBold,
            TextWrapping = TextWrapping.Wrap,
            LineHeight = 11,
            MaxLines = 2,
            VerticalAlignment = VerticalAlignment.Top
        };
        var copy = new Grid
        {
            Margin = new Thickness(6, 3, 6, 4),
            RowDefinitions = new RowDefinitions("17,*"),
            Opacity = 0
        };
        _blueInitializationStepCopy = copy;
        copy.Children.Add(_blueInitializationStepTitle);
        Grid.SetRow(_blueInitializationStepDescription, 1);
        copy.Children.Add(_blueInitializationStepDescription);

        var panel = new Border
        {
            Width = 231,
            Height = 56,
            Background = new LinearGradientBrush
            {
                StartPoint = new RelativePoint(0, 0, RelativeUnit.Relative),
                EndPoint = new RelativePoint(0, 1, RelativeUnit.Relative),
                GradientStops =
                {
                    new GradientStop(Color.Parse("#324DD8"), 0),
                    new GradientStop(Color.Parse("#3344A3"), 1)
                }
            },
            CornerRadius = new CornerRadius(3),
            IsVisible = false,
            Child = copy
        };
        _blueInitializationStepPanel = panel;
        Canvas.SetLeft(panel, 36);
        Canvas.SetTop(panel, BlueInitializationPanelTop);
        canvas.Children.Add(panel);

        root.Child = content;
        return root;
    }

    private static TextBlock BlueInitializationText(
        string text,
        double size,
        FontWeight weight,
        double width) => new()
    {
        Text = text,
        Width = width,
        Foreground = Brushes.White,
        FontFamily = new FontFamily("avares://Avalonia.Fonts.Inter/Assets#Inter"),
        FontSize = size,
        FontWeight = weight,
        TextTrimming = TextTrimming.CharacterEllipsis
    };

    private void BlueInitializationPointerPressed(object? sender, PointerPressedEventArgs args)
    {
        if (args.GetCurrentPoint(this).Properties.IsLeftButtonPressed)
        {
            BeginMoveDrag(args);
        }
    }

    private void StartBlueInitializationAnimation()
    {
        _blueInitializationCancellation?.Cancel();
        _blueInitializationCancellation?.Dispose();
        _blueInitializationCancellation = new CancellationTokenSource();
        _ = PlayBlueInitializationAsync(_blueInitializationCancellation.Token);
    }

    private void CancelBlueInitializationAnimation()
    {
        _blueInitializationCancellation?.Cancel();
        _blueInitializationCancellation?.Dispose();
        _blueInitializationCancellation = null;
    }

    private async Task PlayBlueInitializationAsync(CancellationToken cancellationToken)
    {
        if (_blueInitializationContent is null ||
            _blueInitializationSecondary is null ||
            _blueInitializationProgressFill is null ||
            _blueInitializationStepPanel is null ||
            _blueInitializationStepCopy is null)
        {
            CompleteBlueInitialization();
            return;
        }

        var scale = RenderScaling;
        var centerX = Position.X + (int)Math.Round(BlueInitializationWidth * scale / 2);
        var centerY = Position.Y + (int)Math.Round(BlueInitializationHeight * scale / 2);
        var watch = Stopwatch.StartNew();

        try
        {
            while (!cancellationToken.IsCancellationRequested)
            {
                var elapsed = watch.Elapsed.TotalMilliseconds;
                UpdateBlueInitializationContent(elapsed);

                if (elapsed >= BlueInitializationMorphStartMs)
                {
                    if (!_blueMorphConstraintsReleased)
                    {
                        _blueMorphConstraintsReleased = true;
                        MinWidth = 0;
                        MinHeight = 0;
                        MaxWidth = double.PositiveInfinity;
                        MaxHeight = double.PositiveInfinity;
                        CanResize = true;
                    }

                    var t = Math.Clamp(
                        (elapsed - BlueInitializationMorphStartMs) / BlueInitializationMorphDurationMs,
                        0,
                        1);
                    var eased = BlueEaseInOut.Ease(t);
                    var width = Lerp(BlueInitializationWidth, _spec.Width, eased);
                    var height = Lerp(BlueInitializationHeight, _spec.Height, eased);
                    ApplyBlueInitializationWindowFrame(width, height, scale, centerX, centerY);

                    if (t >= 1)
                    {
                        break;
                    }
                }

                await Task.Delay(16, cancellationToken);
            }
        }
        catch (OperationCanceledException)
        {
            return;
        }

        if (!cancellationToken.IsCancellationRequested)
        {
            CompleteBlueInitialization();
        }
    }

    private void UpdateBlueInitializationContent(double elapsed)
    {
        if (_blueInitializationContent is null ||
            _blueInitializationSecondary is null ||
            _blueInitializationProgressFill is null ||
            _blueInitializationStepPanel is null ||
            _blueInitializationStepCopy is null)
        {
            return;
        }

        _blueInitializationContent.Opacity = elapsed < BlueInitializationExitFadeStartMs
            ? BlueEaseInOut.Ease(Math.Clamp((elapsed - 680) / 440, 0, 1))
            : 1 - BlueEaseInOut.Ease(Math.Clamp((elapsed - BlueInitializationExitFadeStartMs) / 480, 0, 1));
        _blueInitializationSecondary.Opacity =
            BlueEaseInOut.Ease(Math.Clamp((elapsed - 820) / 420, 0, 1));

        if (elapsed < BlueInitializationProgressStartMs)
        {
            return;
        }

        var linearProgress = Math.Clamp(
            (elapsed - BlueInitializationProgressStartMs) / BlueInitializationProgressDurationMs,
            0,
            1);
        var easedProgress = BlueInitializationBarProgress(linearProgress);
        _blueInitializationProgressFill.Height = BlueInitializationBarHeight * Math.Max(easedProgress, 0.001);
        for (var index = 0; index < _blueInitializationDotBrushes.Count; index++)
        {
            _blueInitializationDotBrushes[index].Color =
                BlueInitializationDotColor(index, linearProgress, easedProgress);
        }

        _blueInitializationStepPanel.IsVisible = true;
        var firstMove = BlueEaseInOut.Ease(Math.Clamp((elapsed - 2800) / 550, 0, 1));
        var secondMove = BlueEaseInOut.Ease(Math.Clamp((elapsed - 4800) / 550, 0, 1));
        Canvas.SetTop(
            _blueInitializationStepPanel,
            BlueInitializationPanelTop + BlueInitializationPanelStep * (firstMove + secondMove));

        if (elapsed < 2800)
        {
            SetBlueInitializationStep(0);
            _blueInitializationStepCopy.Opacity =
                BlueEaseInOut.Ease(Math.Clamp((elapsed - 800) / 280, 0, 1));
        }
        else if (elapsed < 3080)
        {
            SetBlueInitializationStep(0);
            _blueInitializationStepCopy.Opacity =
                1 - BlueEaseInOut.Ease(Math.Clamp((elapsed - 2800) / 280, 0, 1));
        }
        else if (elapsed < 4800)
        {
            SetBlueInitializationStep(1);
            _blueInitializationStepCopy.Opacity =
                BlueEaseInOut.Ease(Math.Clamp((elapsed - 3080) / 280, 0, 1));
        }
        else if (elapsed < 5080)
        {
            SetBlueInitializationStep(1);
            _blueInitializationStepCopy.Opacity =
                1 - BlueEaseInOut.Ease(Math.Clamp((elapsed - 4800) / 280, 0, 1));
        }
        else
        {
            SetBlueInitializationStep(2);
            _blueInitializationStepCopy.Opacity =
                BlueEaseInOut.Ease(Math.Clamp((elapsed - 5080) / 280, 0, 1));
        }
    }

    private void SetBlueInitializationStep(int step)
    {
        if (_blueInitializationDisplayedStep == step ||
            _blueInitializationStepTitle is null ||
            _blueInitializationStepDescription is null)
        {
            return;
        }

        _blueInitializationDisplayedStep = step;
        (_blueInitializationStepTitle.Text, _blueInitializationStepDescription.Text) = step switch
        {
            0 => ("Checking Status", "We are checking for an active\nPort Bridge connection to your executor."),
            1 => ("Checking For Updates", "Run Port Bridge.lua in your executor to connect\nthe Port bridge."),
            _ => ("Initialization Complete", "Thank you for your patience, enjoy using\nSynapse Framework")
        };
    }

    private void ApplyBlueInitializationWindowFrame(
        double width,
        double height,
        double scale,
        int centerX,
        int centerY)
    {
        Width = width;
        Height = height;
        Position = new PixelPoint(
            centerX - (int)Math.Round(width * scale / 2),
            centerY - (int)Math.Round(height * scale / 2));
    }

    private void CompleteBlueInitialization()
    {
        if (!_blueInitializationActive || _blueFinalShell is null)
        {
            return;
        }

        _blueInitializationActive = false;
        Width = _spec.Width;
        Height = _spec.Height;
        MinWidth = _spec.Width;
        MinHeight = _spec.Height;
        MaxWidth = OrbitPreferences.ResizableEnabled ? double.PositiveInfinity : _spec.Width;
        MaxHeight = OrbitPreferences.ResizableEnabled ? double.PositiveInfinity : _spec.Height;
        CanResize = OrbitPreferences.ResizableEnabled;
        if (_shellChrome is not null)
        {
            _shellChrome.Opacity = 1;
        }
        Content = _blueFinalShell;
        Dispatcher.UIThread.Post(AssignEditorSource, DispatcherPriority.Loaded);
    }

    private static double BlueInitializationBarProgress(double linearProgress)
    {
        if (linearProgress <= 0) return 0;
        if (linearProgress >= 1) return 1;
        var warped = linearProgress < 2d / 3d
            ? linearProgress
            : 2d / 3d + (linearProgress - 2d / 3d) * 1.85;
        warped = Math.Min(1, warped);
        var index = Math.Min((int)Math.Floor(warped * 3), 2);
        var local = warped * 3 - index;
        return (index + local * local * local) / 3;
    }

    private static Color BlueInitializationDotColor(int index, double linearProgress, double easedProgress)
    {
        const double fade = 0.09;
        double factor;
        if (index == 0)
        {
            factor = easedProgress <= 0 ? 0 : easedProgress >= fade ? 1 : easedProgress / fade;
        }
        else if (index == 3)
        {
            var start = 1 - fade;
            factor = easedProgress < start ? 0 : easedProgress >= 1 ? 1 : (easedProgress - start) / fade;
        }
        else
        {
            var hit = index / 3d;
            factor = easedProgress <= hit ? 0 : easedProgress >= hit + fade ? 1 : (easedProgress - hit) / fade;
        }

        factor = 1 - Math.Pow(1 - Math.Clamp(factor, 0, 1), 3);
        return LerpColor(Color.Parse("#414141"), Color.Parse("#3149E8"), factor);
    }

    private static Color LerpColor(Color from, Color to, double progress)
    {
        var t = Math.Clamp(progress, 0, 1);
        return Color.FromRgb(
            (byte)Math.Round(from.R + (to.R - from.R) * t),
            (byte)Math.Round(from.G + (to.G - from.G) * t),
            (byte)Math.Round(from.B + (to.B - from.B) * t));
    }

    private static double Lerp(double from, double to, double progress) =>
        from + (to - from) * Math.Clamp(progress, 0, 1);
}
