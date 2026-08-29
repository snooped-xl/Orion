using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Primitives;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Threading;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Text.Json;

namespace OrbitAvalonia;

public sealed partial class OrionWindow
{
    private sealed record OrionThemeToken(string Key, string Label, string Hint);

    private static readonly IReadOnlyList<OrionThemeToken> OrionThemeTokens =
    [
        new("WindowStart", "Window light", "Top-left chrome colour"),
        new("WindowEnd", "Window shade", "Lower window colour"),
        new("PageStart", "Page surface", "Main page tint"),
        new("Panel", "Panels", "Cards and side panels"),
        new("Editor", "Editor", "Code surface"),
        new("Control", "Controls", "Buttons and inputs"),
        new("Accent", "Accent", "Selection and glass colour"),
        new("Border", "Stroke", "Page and control outlines"),
        new("TextPrimary", "Primary text", "Headings and active labels"),
        new("TextSecondary", "Secondary text", "Icons and supporting labels"),
        new("TextMuted", "Muted text", "Descriptions and metadata")
    ];

    private readonly List<OrionThemeProfile> _orionCustomThemes = [];
    private string _orionActiveThemeId = OrionThemeStore.OrionThemeId;
    private bool _orionThemeStateLoaded;
    private bool _orionThemeStudioReady;
    private bool _orionThemeStudioRefreshing;
    private bool _orionThemeDisposed;
    private bool _orionThemeUsesGlass;
    private ExperimentalAcrylicBorder _orionAcrylicLayer = null!;
    private OrionLiquidGlassVisual _orionLiquidGlassLayer = null!;
    private StackPanel _orionThemePresetPanel = null!;
    private StackPanel _orionThemeLibraryPanel = null!;
    private TextBlock _orionThemeLibraryCount = null!;
    private TextBlock _orionThemeLibraryHint = null!;
    private TextBlock _orionThemeStudioName = null!;
    private TextBlock _orionThemeStudioMeta = null!;
    private WrapPanel _orionThemeColourPanel = null!;
    private StackPanel _orionThemeEffectPanel = null!;
    private Border _orionThemeColourViewport = null!;
    private Border _orionThemeEffectViewport = null!;
    private Button _orionThemePaletteTab = null!;
    private Button _orionThemeMaterialTab = null!;
    private Button _orionThemeDeleteButton = null!;
    private bool _orionThemeMaterialInspectorVisible;
    private Flyout? _orionThemePickerFlyout;
    private OrionScreenColourPickerWindow? _orionScreenPicker;
    private readonly DispatcherTimer _orionThemeCommitTimer = new()
    {
        Interval = TimeSpan.FromMilliseconds(180)
    };
    private bool _orionThemeCommitTimerHooked;
    private bool _orionThemeCommitPending;

    private void LoadOrionThemeStateAndApply()
    {
        if (_orionThemeStateLoaded)
        {
            return;
        }

        _orionThemeStateLoaded = true;
        _orionCustomThemes.AddRange(OrionThemeStore.LoadCustomThemes());
        _orionActiveThemeId = OrionThemeStore.LoadActiveThemeId();
        if (FindOrionTheme(_orionActiveThemeId) is null)
        {
            _orionActiveThemeId = OrionThemeStore.OrionThemeId;
        }

        _orionAcrylicLayer = this.FindControl<ExperimentalAcrylicBorder>("OrionAcrylicLayer")
            ?? throw new InvalidOperationException("OrionAcrylicLayer was not found.");
        _orionLiquidGlassLayer = this.FindControl<OrionLiquidGlassVisual>("OrionLiquidGlassLayer")
            ?? throw new InvalidOperationException("OrionLiquidGlassLayer was not found.");
        if (!_orionThemeCommitTimerHooked)
        {
            _orionThemeCommitTimer.Tick += OrionThemeCommitTimer_Tick;
            _orionThemeCommitTimerHooked = true;
        }
        ApplyOrionTheme(CurrentOrionTheme(), refreshStudio: false, refreshGeneratedControls: false);
        PointerMoved += OrionThemeWindow_PointerMoved;
        PropertyChanged += OrionThemeVisibilityPropertyChanged;
    }

    private void InitializeOrionThemeStudio()
    {
        _orionThemePresetPanel = this.FindControl<StackPanel>("OrionThemePresetPanel")
            ?? throw new InvalidOperationException("OrionThemePresetPanel was not found.");
        _orionThemeLibraryPanel = this.FindControl<StackPanel>("OrionThemeLibraryPanel")
            ?? throw new InvalidOperationException("OrionThemeLibraryPanel was not found.");
        _orionThemeLibraryCount = this.FindControl<TextBlock>("OrionThemeLibraryCount")
            ?? throw new InvalidOperationException("OrionThemeLibraryCount was not found.");
        _orionThemeLibraryHint = this.FindControl<TextBlock>("OrionThemeLibraryHint")
            ?? throw new InvalidOperationException("OrionThemeLibraryHint was not found.");
        _orionThemeStudioName = this.FindControl<TextBlock>("OrionThemeStudioName")
            ?? throw new InvalidOperationException("OrionThemeStudioName was not found.");
        _orionThemeStudioMeta = this.FindControl<TextBlock>("OrionThemeStudioMeta")
            ?? throw new InvalidOperationException("OrionThemeStudioMeta was not found.");
        _orionThemeColourPanel = this.FindControl<WrapPanel>("OrionThemeColourPanel")
            ?? throw new InvalidOperationException("OrionThemeColourPanel was not found.");
        _orionThemeEffectPanel = this.FindControl<StackPanel>("OrionThemeEffectPanel")
            ?? throw new InvalidOperationException("OrionThemeEffectPanel was not found.");
        _orionThemeColourViewport = this.FindControl<Border>("OrionThemeColourViewport")
            ?? throw new InvalidOperationException("OrionThemeColourViewport was not found.");
        _orionThemeEffectViewport = this.FindControl<Border>("OrionThemeEffectViewport")
            ?? throw new InvalidOperationException("OrionThemeEffectViewport was not found.");
        _orionThemePaletteTab = this.FindControl<Button>("OrionThemePaletteTab")
            ?? throw new InvalidOperationException("OrionThemePaletteTab was not found.");
        _orionThemeMaterialTab = this.FindControl<Button>("OrionThemeMaterialTab")
            ?? throw new InvalidOperationException("OrionThemeMaterialTab was not found.");
        _orionThemeDeleteButton = this.FindControl<Button>("OrionThemeDeleteButton")
            ?? throw new InvalidOperationException("OrionThemeDeleteButton was not found.");
        _orionThemeStudioReady = true;
        RefreshOrionThemeStudio();
        ApplyOrionTheme(CurrentOrionTheme(), refreshStudio: false, refreshGeneratedControls: true);
    }

    private IReadOnlyList<OrionThemeProfile> AllOrionThemes() =>
        BuiltInOrionThemes().Concat(_orionCustomThemes).ToList();

    private static IReadOnlyList<OrionThemeProfile> BuiltInOrionThemes() =>
    [
        new OrionThemeProfile
        {
            Id = OrionThemeStore.OrionThemeId,
            Name = "Orion",
            BaseThemeId = OrionThemeStore.OrionThemeId,
            Material = OrionThemeMaterial.Solid,
            SurfaceOpacity = 0,
            GlassIntensity = 0,
            Refraction = 0,
            Specular = 0.18,
            Saturation = 1,
            Noise = 0,
            Colours = new(StringComparer.Ordinal)
            {
                ["WindowStart"] = "#181A1B",
                ["WindowEnd"] = "#08090A",
                ["PageStart"] = "#070809",
                ["PageEnd"] = "#111314",
                ["Panel"] = "#07080A",
                ["Editor"] = "#101112",
                ["Control"] = "#111315",
                ["ControlHover"] = "#191B1D",
                ["Accent"] = "#8DB7FF",
                ["Border"] = "#303235",
                ["ControlBorder"] = "#525558",
                ["BorderStrong"] = "#66696C",
                ["TextPrimary"] = "#FFFFFF",
                ["TextSecondary"] = "#7D7D80",
                ["TextMuted"] = "#55585C"
            }
        },
        new OrionThemeProfile
        {
            Id = OrionThemeStore.LiquidGlassThemeId,
            Name = "Liquid Glass",
            BaseThemeId = OrionThemeStore.LiquidGlassThemeId,
            Material = OrionThemeMaterial.LiquidGlass,
            SurfaceOpacity = 0.16,
            GlassIntensity = 0.38,
            Refraction = 0.08,
            Specular = 0.18,
            Saturation = 1,
            Noise = 0.002,
            Colours = new(StringComparer.Ordinal)
            {
                ["WindowStart"] = "#181A1B",
                ["WindowEnd"] = "#08090A",
                ["PageStart"] = "#070809",
                ["PageEnd"] = "#111314",
                ["Panel"] = "#07080A",
                ["Editor"] = "#101112",
                ["Control"] = "#111315",
                ["ControlHover"] = "#191B1D",
                ["Accent"] = "#8DB7FF",
                ["Border"] = "#303235",
                ["ControlBorder"] = "#525558",
                ["BorderStrong"] = "#66696C",
                ["TextPrimary"] = "#FFFFFF",
                ["TextSecondary"] = "#7D7D80",
                ["TextMuted"] = "#55585C"
            }
        },
        new OrionThemeProfile
        {
            Id = OrionThemeStore.TransparentThemeId,
            Name = "Transparent",
            BaseThemeId = OrionThemeStore.TransparentThemeId,
            Material = OrionThemeMaterial.Transparent,
            SurfaceOpacity = 0.16,
            GlassIntensity = 0,
            Refraction = 0,
            Specular = 0.08,
            Saturation = 1,
            Noise = 0,
            Colours = new(StringComparer.Ordinal)
            {
                ["WindowStart"] = "#181A1B",
                ["WindowEnd"] = "#08090A",
                ["PageStart"] = "#070809",
                ["PageEnd"] = "#111314",
                ["Panel"] = "#07080A",
                ["Editor"] = "#101112",
                ["Control"] = "#111315",
                ["ControlHover"] = "#191B1D",
                ["Accent"] = "#8DB7FF",
                ["Border"] = "#303235",
                ["ControlBorder"] = "#525558",
                ["BorderStrong"] = "#66696C",
                ["TextPrimary"] = "#FFFFFF",
                ["TextSecondary"] = "#7D7D80",
                ["TextMuted"] = "#55585C"
            }
        }
    ];

    private OrionThemeProfile CurrentOrionTheme() =>
        FindOrionTheme(_orionActiveThemeId) ?? BuiltInOrionThemes()[0];

    private OrionThemeProfile? FindOrionTheme(string id) =>
        BuiltInOrionThemes().FirstOrDefault(theme => theme.Id == id)
        ?? _orionCustomThemes.FirstOrDefault(theme => theme.Id == id);

    private static bool IsBuiltInOrionTheme(OrionThemeProfile profile) =>
        !profile.Id.StartsWith("custom-", StringComparison.Ordinal);

    private void SelectOrionTheme(string id)
    {
        var profile = FindOrionTheme(id);
        if (profile is null)
        {
            return;
        }

        _orionActiveThemeId = id;
        OrionThemeStore.SaveActiveThemeId(id);
        ApplyOrionTheme(profile, refreshStudio: true, refreshGeneratedControls: true);
    }

    private void ApplyOrionTheme(
        OrionThemeProfile profile,
        bool refreshStudio,
        bool refreshGeneratedControls)
    {
        CompleteOrionThemeColours(profile);
        var isSolid = profile.Material == OrionThemeMaterial.Solid;
        var isGlass = profile.Material == OrionThemeMaterial.LiquidGlass;
        var isTransparent = profile.Material == OrionThemeMaterial.Transparent;

        var windowOpacity = isSolid
            ? 1
            : isGlass
                ? Math.Clamp(profile.SurfaceOpacity, 0.06, 0.5)
                : Math.Clamp(profile.SurfaceOpacity, 0.04, 0.78);
        var pageOpacity = isSolid ? profile.SurfaceOpacity : isGlass
            ? Math.Clamp(profile.SurfaceOpacity * 0.75, 0.06, 0.3)
            : Math.Clamp(profile.SurfaceOpacity * 0.72, 0.06, 0.42);
        var panelOpacity = isSolid ? 1 : isGlass
            ? Math.Clamp(0.22 + (profile.SurfaceOpacity * 0.4), 0.24, 0.38)
            : Math.Clamp(0.22 + (profile.SurfaceOpacity * 0.35), 0.22, 0.44);
        var controlOpacity = isSolid ? 1 : Math.Clamp(panelOpacity + 0.12, 0.34, 0.58);
        var strokeOpacity = isSolid ? 1 : isGlass ? 0.64 : 0.58;

        Resources["OrionWindowFill"] = Gradient(
            ThemeColour(profile, "WindowStart"),
            ThemeColour(profile, "WindowEnd"),
            windowOpacity,
            secondOffset: 0.37019,
            new RelativePoint(0.189114, -0.0048156, RelativeUnit.Relative),
            new RelativePoint(0.99810886, 1.0048156, RelativeUnit.Relative));
        Resources["OrionLoadingFill"] = Gradient(
            ThemeColour(profile, "WindowStart"),
            ThemeColour(profile, "WindowEnd"),
            isSolid ? 1 : Math.Clamp(windowOpacity + 0.24, 0.34, 0.96),
            secondOffset: 0.37019,
            new RelativePoint(-0.103312, 0.263073, RelativeUnit.Relative),
            new RelativePoint(1.103312, 0.736927, RelativeUnit.Relative));
        Resources["OrionPageSurface"] = Gradient(
            ThemeColour(profile, "PageStart"),
            ThemeColour(profile, "PageEnd"),
            pageOpacity,
            secondOffset: 1,
            new RelativePoint(0.971834, 1.078071, RelativeUnit.Relative),
            new RelativePoint(0.028166, -0.078071, RelativeUnit.Relative));

        SetOrionThemeBrush("OrionMonacoSurface", ThemeColour(profile, "Editor"), 0);
        SetOrionThemeBrush("OrionTabSurface", ThemeColour(profile, "Control"), isSolid ? 0.58 : controlOpacity);
        SetOrionThemeBrush("OrionUtilityGlass", ThemeColour(profile, "Panel"), isSolid ? 0.7 : Math.Min(0.48, panelOpacity + 0.08));
        SetOrionThemeBrush("OrionPanelBrush", ThemeColour(profile, "Panel"), panelOpacity);
        SetOrionThemeBrush("OrionPanelOverlayBrush", ThemeColour(profile, "Panel"), panelOpacity * 0.2);
        SetOrionThemeBrush("OrionGlassPanelBrush", ThemeColour(profile, "Panel"), panelOpacity * 0.6);
        SetOrionThemeBrush("OrionPanelSoftBrush", ThemeColour(profile, "Panel"), panelOpacity * 0.47);
        SetOrionThemeBrush("OrionPanelElevatedBrush", ThemeColour(profile, "Panel"), panelOpacity * 0.78);
        SetOrionThemeBrush("OrionPanelStrongBrush", ThemeColour(profile, "Panel"), panelOpacity * 0.85);
        SetOrionThemeBrush("OrionControlBrush", ThemeColour(profile, "Control"), controlOpacity);
        SetOrionThemeBrush("OrionControlHoverBrush", ThemeColour(profile, "ControlHover"), Math.Min(1, controlOpacity + 0.1));
        SetOrionThemeBrush("OrionInputBrush", ThemeColour(profile, "Editor"), Math.Min(1, controlOpacity + 0.08));
        SetOrionThemeBrush("OrionBorderBrush", ThemeColour(profile, "Border"), strokeOpacity);
        SetOrionThemeBrush("OrionControlBorderBrush", ThemeColour(profile, "ControlBorder"), strokeOpacity);
        SetOrionThemeBrush("OrionBorderStrongBrush", ThemeColour(profile, "BorderStrong"), strokeOpacity);
        SetOrionThemeBrush("OrionHairlineBrush", ThemeColour(profile, "TextSecondary"), isSolid ? 1 : 0.78);
        SetOrionThemeBrush("OrionTextPrimaryBrush", ThemeColour(profile, "TextPrimary"), 1);
        SetOrionThemeBrush(
            "OrionTextSecondaryBrush",
            isSolid
                ? ThemeColour(profile, "TextSecondary")
                : MixColour(ThemeColour(profile, "TextSecondary"), Colors.White, isGlass ? 0.34 : 0.24),
            1);
        SetOrionThemeBrush(
            "OrionTextMutedBrush",
            isSolid
                ? ThemeColour(profile, "TextMuted")
                : MixColour(ThemeColour(profile, "TextMuted"), Colors.White, isGlass ? 0.38 : 0.28),
            1);
        SetOrionThemeBrush("OrionAccentBrush", ThemeColour(profile, "Accent"), 1);
        SetOrionThemeBrush("OrionAccentSoftBrush", ThemeColour(profile, "Accent"), 0.2);
        SetOrionThemeBrush("OrionSelectionBrush", ThemeColour(profile, "Accent"), isSolid ? 0.28 : 0.22);

        Resources["OrionChromeShadeBrush"] = isSolid
            ? Brushes.Transparent
            : new LinearGradientBrush
            {
                StartPoint = new RelativePoint(0.5, 0, RelativeUnit.Relative),
                EndPoint = new RelativePoint(0.5, 1, RelativeUnit.Relative),
                GradientStops =
                {
                    new GradientStop(WithOpacity(ThemeColour(profile, "WindowEnd"), isGlass ? 0.24 : 0.18), 0),
                    new GradientStop(WithOpacity(ThemeColour(profile, "WindowEnd"), isGlass ? 0.12 : 0.08), 0.62),
                    new GradientStop(Colors.Transparent, 1)
                }
            };

        Resources["OrionEdgeStroke"] = CreateOrionEdgeStroke(profile, isSolid, strokeOpacity);

        if (isGlass)
        {
            TransparencyLevelHint =
            [
                WindowTransparencyLevel.AcrylicBlur,
                WindowTransparencyLevel.Blur,
                WindowTransparencyLevel.Transparent
            ];
            TransparencyBackgroundFallback = SolidBrush(
                ThemeColour(profile, "WindowEnd"),
                Math.Clamp(windowOpacity + 0.2, 0.32, 0.72));
            _orionAcrylicLayer.Material = new ExperimentalAcrylicMaterial
            {
                BackgroundSource = AcrylicBackgroundSource.Digger,
                TintColor = ThemeColour(profile, "WindowStart"),
                TintOpacity = Math.Clamp(0.08 + (profile.GlassIntensity * 0.18), 0.08, 0.24),
                MaterialOpacity = Math.Clamp(0.18 + (profile.GlassIntensity * 0.36), 0.2, 0.46),
                PlatformTransparencyCompensationLevel = 0.05,
                FallbackColor = WithOpacity(ThemeColour(profile, "WindowEnd"), 0.42)
            };
            _orionAcrylicLayer.IsVisible = true;
        }
        else
        {
            TransparencyLevelHint = [WindowTransparencyLevel.Transparent];
            TransparencyBackgroundFallback = SolidBrush(
                ThemeColour(profile, "WindowEnd"),
                isTransparent ? windowOpacity : 1);
            _orionAcrylicLayer.IsVisible = false;
        }

        _orionLiquidGlassLayer.Configure(
            isGlass,
            profile.Refraction,
            profile.Specular,
            profile.Noise,
            ThemeColour(profile, "Accent"));
        _orionThemeUsesGlass = isGlass;
        UpdateOrionGlassAnimationState();

        if (refreshGeneratedControls)
        {
            RebuildOrionTabs();
            RenderOrionPlugins();
        }

        PushOrionThemeToMonaco(profile, windowOpacity, pageOpacity);
        InvalidateVisual();

        if (refreshStudio)
        {
            RefreshOrionThemeStudio();
        }
    }

    private void PushOrionThemeToMonaco(
        OrionThemeProfile profile,
        double windowOpacity,
        double pageOpacity)
    {
        if (!_orionMonacoReady || _orionEditorDisposed)
        {
            return;
        }

        var payload = JsonSerializer.Serialize(new
        {
            windowStart = CssRgba(ThemeColour(profile, "WindowStart"), windowOpacity),
            windowEnd = CssRgba(ThemeColour(profile, "WindowEnd"), windowOpacity),
            editor = "transparent",
            lineHighlight = CssRgba(ThemeColour(profile, "Accent"), profile.Material == OrionThemeMaterial.Solid ? 0.04 : 0.06),
            widget = CssRgba(ThemeColour(profile, "Panel"), profile.Material == OrionThemeMaterial.Solid ? 0.98 : Math.Max(0.82, pageOpacity)),
            widgetSelection = CssRgba(ThemeColour(profile, "Accent"), 0.2),
            border = CssRgba(ThemeColour(profile, "Border"), 0.92),
            text = ToHex(ThemeColour(profile, "TextPrimary"))
        });
        _ = InvokeOrionThemeScriptAsync($"window.orionApplyTheme && window.orionApplyTheme({payload});");
    }

    private async Task InvokeOrionThemeScriptAsync(string script)
    {
        try
        {
            await _orionMonacoWebView.InvokeScript(script);
        }
        catch (Exception)
        {
            // WebView navigation/COM state is transient while Orion changes
            // pages or shells. The latest theme is pushed again when Monaco
            // reports ready, so a stale native host never tears down the UI.
        }
    }

    private void RefreshOrionThemeStudio()
    {
        if (!_orionThemeStudioReady || _orionThemeStudioRefreshing)
        {
            return;
        }

        _orionThemeStudioRefreshing = true;
        try
        {
            BuildOrionThemeLibrary();
            BuildOrionThemeInspector(CurrentOrionTheme());
        }
        finally
        {
            _orionThemeStudioRefreshing = false;
        }
    }

    private void BuildOrionThemeLibrary()
    {
        _orionThemePresetPanel.Children.Clear();
        _orionThemeLibraryPanel.Children.Clear();
        foreach (var profile in BuiltInOrionThemes())
        {
            _orionThemePresetPanel.Children.Add(BuildOrionPresetCard(profile));
        }

        _orionThemeLibraryCount.Text = _orionCustomThemes.Count.ToString();
        _orionThemeLibraryHint.Text = _orionCustomThemes.Count == 0
            ? "Duplicate a preset to begin"
            : "Custom themes save automatically";
        if (_orionCustomThemes.Count == 0)
        {
            _orionThemeLibraryPanel.Children.Add(new TextBlock
            {
                Margin = new Thickness(6, 10),
                Text = "No custom themes yet.",
                FontSize = 6.333,
                Foreground = ThemeResourceBrush("OrionTextMutedBrush", "#55585C"),
                HorizontalAlignment = HorizontalAlignment.Center
            });
            return;
        }

        foreach (var profile in _orionCustomThemes)
        {
            _orionThemeLibraryPanel.Children.Add(BuildOrionCustomThemeRow(profile));
        }
    }

    private Button BuildOrionPresetCard(OrionThemeProfile profile)
    {
        var selected = profile.Id == _orionActiveThemeId;
        var button = new Button
        {
            Width = 194,
            Height = 54,
            Classes = { "orion-theme-card" },
            BorderBrush = ThemeResourceBrush("OrionBorderBrush", "#303235")
        };
        var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("2,*,54") };
        grid.Children.Add(new Border
        {
            Width = 2,
            HorizontalAlignment = HorizontalAlignment.Left,
            Background = selected
                ? ThemeResourceBrush("OrionAccentBrush", "#8DB7FF")
                : Brushes.Transparent,
            CornerRadius = new CornerRadius(2, 0, 0, 2)
        });
        var labels = new StackPanel
        {
            Margin = new Thickness(11, 0, 0, 0),
            VerticalAlignment = VerticalAlignment.Center,
            Spacing = 2,
            Children =
            {
                new TextBlock
                {
                    Text = profile.Name,
                    FontSize = 8.667,
                    Foreground = ThemeResourceBrush("OrionTextPrimaryBrush", "#FFFFFF")
                },
                new TextBlock
                {
                    Text = profile.Material switch
                    {
                        OrionThemeMaterial.Solid => "ORIGINAL MATERIAL",
                        OrionThemeMaterial.LiquidGlass => "REFRACTIVE MATERIAL",
                        _ => "CLEAR MATERIAL"
                    },
                    FontSize = 6,
                    Foreground = ThemeResourceBrush("OrionTextSecondaryBrush", "#7D7D80")
                }
            }
        };
        Grid.SetColumn(labels, 1);
        grid.Children.Add(labels);
        var materialGlyph = BuildOrionMaterialGlyph(profile.Material, 38, 30);
        materialGlyph.Margin = new Thickness(0, 0, 9, 0);
        materialGlyph.HorizontalAlignment = HorizontalAlignment.Right;
        materialGlyph.VerticalAlignment = VerticalAlignment.Center;
        Grid.SetColumn(materialGlyph, 2);
        grid.Children.Add(materialGlyph);
        button.Content = grid;
        button.Click += (_, _) => SelectOrionTheme(profile.Id);
        return button;
    }

    private Button BuildOrionCustomThemeRow(OrionThemeProfile profile)
    {
        var selected = profile.Id == _orionActiveThemeId;
        var button = new Button
        {
            Height = 35.333,
            Classes = { "orion-theme-card" },
            BorderBrush = ThemeResourceBrush("OrionBorderBrush", "#303235")
        };
        var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("2,27,*") };
        grid.Children.Add(new Border
        {
            Width = 2,
            HorizontalAlignment = HorizontalAlignment.Left,
            Background = selected
                ? ThemeResourceBrush("OrionAccentBrush", "#8DB7FF")
                : Brushes.Transparent,
            CornerRadius = new CornerRadius(2, 0, 0, 2)
        });
        var glyph = BuildOrionMaterialGlyph(profile.Material, 18, 18);
        glyph.Margin = new Thickness(5, 0, 0, 0);
        glyph.VerticalAlignment = VerticalAlignment.Center;
        Grid.SetColumn(glyph, 1);
        grid.Children.Add(glyph);
        var labels = new StackPanel
        {
            Margin = new Thickness(3, 0, 5, 0),
            VerticalAlignment = VerticalAlignment.Center,
            Spacing = 0.667,
            Children =
            {
                new TextBlock
                {
                    Text = profile.Name,
                    FontSize = 6.667,
                    Foreground = ThemeResourceBrush("OrionTextPrimaryBrush", "#FFFFFF"),
                    TextTrimming = TextTrimming.CharacterEllipsis
                },
                new TextBlock
                {
                    Text = MaterialLabel(profile.Material),
                    FontSize = 5.333,
                    Foreground = ThemeResourceBrush("OrionTextSecondaryBrush", "#7D7D80")
                }
            }
        };
        Grid.SetColumn(labels, 2);
        grid.Children.Add(labels);
        button.Content = grid;
        button.Click += (_, _) => SelectOrionTheme(profile.Id);
        return button;
    }

    private Control BuildOrionMaterialGlyph(OrionThemeMaterial material, double width, double height)
    {
        var grid = new Grid { Width = width, Height = height };
        var surface = new Border
        {
            CornerRadius = new CornerRadius(Math.Min(width, height) * 0.22),
            BorderBrush = ThemeResourceBrush("OrionBorderStrongBrush", "#66696C"),
            BorderThickness = new Thickness(0.667),
            Background = material == OrionThemeMaterial.Solid
                ? ThemeResourceBrush("OrionControlBrush", "#111315")
                : material == OrionThemeMaterial.LiquidGlass
                    ? SolidBrush(ThemeColour(CurrentOrionTheme(), "WindowStart"), 0.28)
                    : Brushes.Transparent
        };
        grid.Children.Add(surface);
        if (material == OrionThemeMaterial.LiquidGlass)
        {
            grid.Children.Add(new Border
            {
                Margin = new Thickness(width * 0.12, height * 0.16),
                Background = SolidBrush(Colors.White, 0.045),
                BorderBrush = SolidBrush(Colors.White, 0.13),
                BorderThickness = new Thickness(0.5),
                CornerRadius = new CornerRadius(Math.Min(width, height) * 0.14)
            });
            grid.Children.Add(new Border
            {
                Width = width * 0.52,
                Height = 1,
                Margin = new Thickness(0, height * 0.28, width * 0.12, 0),
                HorizontalAlignment = HorizontalAlignment.Right,
                VerticalAlignment = VerticalAlignment.Top,
                Background = SolidBrush(Colors.White, 0.26),
                CornerRadius = new CornerRadius(1)
            });
        }
        else if (material == OrionThemeMaterial.Transparent)
        {
            grid.Children.Add(new Border
            {
                Margin = new Thickness(width * 0.18, height * 0.2),
                CornerRadius = new CornerRadius(Math.Min(width, height) * 0.12),
                BorderBrush = ThemeResourceBrush("OrionBorderBrush", "#303235"),
                BorderThickness = new Thickness(0.667)
            });
        }
        return grid;
    }

    private void BuildOrionThemeInspector(OrionThemeProfile profile)
    {
        var builtIn = IsBuiltInOrionTheme(profile);
        _orionThemeStudioName.Text = profile.Name;
        _orionThemeStudioMeta.Text = builtIn
            ? $"Built-in · {MaterialLabel(profile.Material)} · duplicate to customise"
            : $"Custom · {MaterialLabel(profile.Material)} · changes save automatically";
        _orionThemeDeleteButton.IsVisible = !builtIn;

        _orionThemeColourPanel.Children.Clear();
        foreach (var token in OrionThemeTokens)
        {
            _orionThemeColourPanel.Children.Add(BuildOrionColourRow(profile, token, builtIn));
        }

        _orionThemeEffectPanel.Children.Clear();
        if (!builtIn)
        {
            _orionThemeEffectPanel.Children.Add(SectionLabel("THEME NAME"));
            var name = new TextBox
            {
                Text = profile.Name,
                Height = 22,
                PlaceholderText = "Theme name",
                Classes = { "orion-theme-input" }
            };
            name.LostFocus += (_, _) => RenameOrionTheme(profile, name.Text);
            name.KeyDown += (_, eventArgs) =>
            {
                if (eventArgs.Key == Key.Enter)
                {
                    RenameOrionTheme(profile, name.Text);
                    Focus();
                    eventArgs.Handled = true;
                }
            };
            _orionThemeEffectPanel.Children.Add(name);
        }

        _orionThemeEffectPanel.Children.Add(SectionLabel("MATERIAL"));

        var materialGrid = new Grid
        {
            Width = 390,
            ColumnDefinitions = new ColumnDefinitions("*,*,*"),
            ColumnSpacing = 4
        };
        var materials = new[]
        {
            (OrionThemeMaterial.Solid, "Solid"),
            (OrionThemeMaterial.LiquidGlass, "Glass"),
            (OrionThemeMaterial.Transparent, "Clear")
        };
        for (var index = 0; index < materials.Length; index++)
        {
            var (material, label) = materials[index];
            var button = new Button
            {
                Width = 124,
                Height = 22,
                HorizontalAlignment = HorizontalAlignment.Center,
                Content = label,
                IsHitTestVisible = !builtIn,
                Classes = { "orion-theme-button" },
                Background = profile.Material == material
                    ? ThemeResourceBrush("OrionAccentSoftBrush", "#338DB7FF")
                    : ThemeResourceBrush("OrionControlBrush", "#111315"),
                BorderBrush = profile.Material == material
                    ? ThemeResourceBrush("OrionAccentBrush", "#8DB7FF")
                    : ThemeResourceBrush("OrionBorderBrush", "#303235"),
                BorderThickness = new Thickness(0.5),
                CornerRadius = new CornerRadius(5),
                Foreground = ThemeResourceBrush("OrionTextPrimaryBrush", "#FFFFFF"),
                FontSize = 6.333,
                Padding = new Thickness(0),
                Cursor = new Cursor(StandardCursorType.Hand)
            };
            Grid.SetColumn(button, index);
            button.Click += (_, _) =>
            {
                profile.Material = material;
                SaveAndApplyOrionCustomTheme(profile);
            };
            materialGrid.Children.Add(button);
        }
        _orionThemeEffectPanel.Children.Add(materialGrid);

        var effectGrid = new WrapPanel
        {
            Width = 390,
            Orientation = Orientation.Horizontal,
            ItemWidth = 190,
            ItemHeight = 23.333
        };
        effectGrid.Children.Add(BuildOrionThemeSlider(
            "Surface opacity",
            profile.SurfaceOpacity,
            0,
            1,
            builtIn,
            value => profile.SurfaceOpacity = value,
            profile));
        effectGrid.Children.Add(BuildOrionThemeSlider(
            "Glass intensity",
            profile.GlassIntensity,
            0,
            1,
            builtIn,
            value => profile.GlassIntensity = value,
            profile));
        effectGrid.Children.Add(BuildOrionThemeSlider(
            "Refraction",
            profile.Refraction,
            0,
            0.4,
            builtIn,
            value => profile.Refraction = value,
            profile));
        effectGrid.Children.Add(BuildOrionThemeSlider(
            "Highlight",
            profile.Specular,
            0,
            1,
            builtIn,
            value => profile.Specular = value,
            profile));
        effectGrid.Children.Add(BuildOrionThemeSlider(
            "Saturation",
            profile.Saturation,
            0.65,
            1.5,
            builtIn,
            value => profile.Saturation = value,
            profile));
        effectGrid.Children.Add(BuildOrionThemeSlider(
            "Fine grain",
            profile.Noise,
            0,
            0.06,
            builtIn,
            value => profile.Noise = value,
            profile));
        _orionThemeEffectPanel.Children.Add(effectGrid);

        if (builtIn)
        {
            _orionThemeEffectPanel.Children.Add(new TextBlock
            {
                Margin = new Thickness(0, 2, 0, 0),
                Text = "Duplicate this preset to unlock editing.",
                FontSize = 6,
                Foreground = ThemeResourceBrush("OrionTextSecondaryBrush", "#7D7D80"),
                TextWrapping = TextWrapping.Wrap
            });
        }
        UpdateOrionThemeInspectorModeVisual();
    }

    private void OrionThemePaletteTab_Click(object? sender, RoutedEventArgs e)
    {
        _orionThemeMaterialInspectorVisible = false;
        UpdateOrionThemeInspectorModeVisual();
    }

    private void OrionThemeMaterialTab_Click(object? sender, RoutedEventArgs e)
    {
        _orionThemeMaterialInspectorVisible = true;
        UpdateOrionThemeInspectorModeVisual();
    }

    private void UpdateOrionThemeInspectorModeVisual()
    {
        if (!_orionThemeStudioReady)
        {
            return;
        }

        _orionThemeColourViewport.IsVisible = !_orionThemeMaterialInspectorVisible;
        _orionThemeEffectViewport.IsVisible = _orionThemeMaterialInspectorVisible;
        StyleOrionThemeInspectorTab(_orionThemePaletteTab, !_orionThemeMaterialInspectorVisible);
        StyleOrionThemeInspectorTab(_orionThemeMaterialTab, _orionThemeMaterialInspectorVisible);
    }

    private void StyleOrionThemeInspectorTab(Button button, bool selected)
    {
        button.Background = selected
            ? ThemeResourceBrush("OrionAccentSoftBrush", "#338DB7FF")
            : Brushes.Transparent;
        button.BorderBrush = selected
            ? ThemeResourceBrush("OrionAccentBrush", "#8DB7FF")
            : ThemeResourceBrush("OrionBorderBrush", "#303235");
        button.Foreground = selected
            ? ThemeResourceBrush("OrionTextPrimaryBrush", "#FFFFFF")
            : ThemeResourceBrush("OrionTextMutedBrush", "#55585C");
    }

    private Control BuildOrionColourRow(
        OrionThemeProfile profile,
        OrionThemeToken token,
        bool builtIn)
    {
        var colour = RawThemeColour(profile, token.Key);
        var button = new Button
        {
            Height = 24,
            Margin = new Thickness(0, 0, 3, 3),
            Padding = new Thickness(5, 0),
            HorizontalContentAlignment = HorizontalAlignment.Stretch,
            Background = ThemeResourceBrush("OrionControlBrush", "#111315"),
            BorderBrush = ThemeResourceBrush("OrionBorderBrush", "#303235"),
            BorderThickness = new Thickness(0.5),
            CornerRadius = new CornerRadius(5.333),
            IsEnabled = !builtIn,
            Cursor = new Cursor(StandardCursorType.Hand)
        };
        var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("18,*,Auto") };
        grid.Children.Add(new Border
        {
            Width = 12,
            Height = 12,
            CornerRadius = new CornerRadius(3.667),
            Background = new SolidColorBrush(colour),
            BorderBrush = SolidBrush(Colors.White, 0.28),
            BorderThickness = new Thickness(0.5)
        });
        var text = new TextBlock
        {
            Text = token.Label,
            FontSize = 6.333,
            VerticalAlignment = VerticalAlignment.Center,
            Foreground = ThemeResourceBrush("OrionTextPrimaryBrush", "#FFFFFF")
        };
        Grid.SetColumn(text, 1);
        grid.Children.Add(text);
        var hexLabel = new TextBlock
        {
            Text = ToHex(colour),
            FontSize = 6,
            VerticalAlignment = VerticalAlignment.Center,
            Foreground = ThemeResourceBrush("OrionTextSecondaryBrush", "#7D7D80")
        };
        Grid.SetColumn(hexLabel, 2);
        grid.Children.Add(hexLabel);
        button.Content = grid;
        ToolTip.SetTip(button, token.Hint);
        button.Click += (_, _) => OpenOrionColourPicker(profile, token, button);
        return button;
    }

    private Control BuildOrionThemeSlider(
        string label,
        double value,
        double minimum,
        double maximum,
        bool readOnly,
        Action<double> update,
        OrionThemeProfile profile)
    {
        var valueText = new TextBlock
        {
            Text = SliderValue(value, maximum),
            FontSize = 6,
            Foreground = ThemeResourceBrush("OrionTextSecondaryBrush", "#7D7D80"),
            HorizontalAlignment = HorizontalAlignment.Right
        };
        var header = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };
        header.Children.Add(new TextBlock
        {
            Text = label,
            FontSize = 6.333,
            Foreground = ThemeResourceBrush("OrionTextSecondaryBrush", "#7D7D80")
        });
        Grid.SetColumn(valueText, 1);
        header.Children.Add(valueText);
        var slider = new OrionThemeRangeControl
        {
            Minimum = minimum,
            Maximum = maximum,
            Value = value,
            Height = 10.667,
            IsEnabled = !readOnly,
            TrackBrush = ThemeResourceBrush("OrionBorderBrush", "#303235"),
            FillBrush = ThemeResourceBrush("OrionAccentBrush", "#8DB7FF"),
            ThumbBrush = ThemeResourceBrush("OrionTextPrimaryBrush", "#FFFFFF"),
            ThumbBorderBrush = ThemeResourceBrush("OrionBorderStrongBrush", "#66696C")
        };
        slider.ValueChanged += newValue =>
        {
            if (_orionThemeStudioRefreshing)
            {
                return;
            }

            update(newValue);
            valueText.Text = SliderValue(newValue, maximum);
            PreviewAndQueueOrionCustomTheme(profile);
        };
        return new StackPanel
        {
            Width = 186,
            Spacing = 0,
            Children = { header, slider }
        };
    }

    private static string SliderValue(double value, double maximum) =>
        maximum <= 0.06 ? value.ToString("0.000") : $"{value * 100:0}%";

    private TextBlock SectionLabel(string text) => new()
    {
        Text = text,
        FontSize = 6.333,
        Foreground = ThemeResourceBrush("OrionTextSecondaryBrush", "#7D7D80")
    };

    private void OrionThemeNew_Click(object? sender, RoutedEventArgs e) =>
        CreateOrionCustomTheme(CurrentOrionTheme(), "New Theme");

    private void OrionThemeDuplicate_Click(object? sender, RoutedEventArgs e) =>
        CreateOrionCustomTheme(CurrentOrionTheme(), $"{CurrentOrionTheme().Name} Copy");

    private void OrionThemeReset_Click(object? sender, RoutedEventArgs e)
    {
        var current = CurrentOrionTheme();
        if (IsBuiltInOrionTheme(current))
        {
            ApplyOrionTheme(current, refreshStudio: true, refreshGeneratedControls: true);
            return;
        }

        var baseline = FindOrionTheme(current.BaseThemeId) ?? BuiltInOrionThemes()[0];
        var replacement = baseline.Clone(current.Id, current.Name);
        var index = _orionCustomThemes.IndexOf(current);
        if (index >= 0)
        {
            _orionCustomThemes[index] = replacement;
            SaveAndApplyOrionCustomTheme(replacement);
        }
    }

    private void OrionThemeDelete_Click(object? sender, RoutedEventArgs e)
    {
        var current = CurrentOrionTheme();
        if (IsBuiltInOrionTheme(current))
        {
            return;
        }

        _orionCustomThemes.Remove(current);
        OrionThemeStore.SaveCustomThemes(_orionCustomThemes);
        SelectOrionTheme(OrionThemeStore.OrionThemeId);
    }

    private void CreateOrionCustomTheme(OrionThemeProfile source, string requestedName)
    {
        var name = UniqueOrionThemeName(requestedName);
        var profile = source.Clone(OrionThemeStore.NewId(), name);
        profile.BaseThemeId = IsBuiltInOrionTheme(source) ? source.Id : source.BaseThemeId;
        _orionCustomThemes.Add(profile);
        OrionThemeStore.SaveCustomThemes(_orionCustomThemes);
        SelectOrionTheme(profile.Id);
    }

    private string UniqueOrionThemeName(string candidate)
    {
        candidate = string.IsNullOrWhiteSpace(candidate) ? "New Theme" : candidate.Trim();
        var names = AllOrionThemes().Select(theme => theme.Name).ToHashSet(StringComparer.OrdinalIgnoreCase);
        if (!names.Contains(candidate))
        {
            return candidate;
        }

        for (var index = 2; ; index++)
        {
            var name = $"{candidate} {index}";
            if (!names.Contains(name))
            {
                return name;
            }
        }
    }

    private void RenameOrionTheme(OrionThemeProfile profile, string? name)
    {
        if (IsBuiltInOrionTheme(profile) || string.IsNullOrWhiteSpace(name))
        {
            return;
        }

        profile.Name = name.Trim();
        OrionThemeStore.SaveCustomThemes(_orionCustomThemes);
        RefreshOrionThemeStudio();
    }

    private void SaveAndApplyOrionCustomTheme(
        OrionThemeProfile profile,
        bool refreshStudio = true)
    {
        if (IsBuiltInOrionTheme(profile))
        {
            return;
        }

        OrionThemeStore.SaveCustomThemes(_orionCustomThemes);
        ApplyOrionTheme(profile, refreshStudio, refreshGeneratedControls: true);
    }

    private void PreviewAndQueueOrionCustomTheme(OrionThemeProfile profile)
    {
        if (IsBuiltInOrionTheme(profile))
        {
            return;
        }

        ApplyOrionTheme(profile, refreshStudio: false, refreshGeneratedControls: false);
        _orionThemeCommitPending = true;
        _orionThemeCommitTimer.Stop();
        _orionThemeCommitTimer.Start();
    }

    private void OrionThemeCommitTimer_Tick(object? sender, EventArgs e)
    {
        _orionThemeCommitTimer.Stop();
        CommitPendingOrionThemeChanges(refreshGeneratedControls: true);
    }

    private void CommitPendingOrionThemeChanges(bool refreshGeneratedControls)
    {
        if (!_orionThemeCommitPending)
        {
            return;
        }

        _orionThemeCommitPending = false;
        OrionThemeStore.SaveCustomThemes(_orionCustomThemes);
        if (refreshGeneratedControls && !_orionThemeDisposed)
        {
            ApplyOrionTheme(CurrentOrionTheme(), refreshStudio: false, refreshGeneratedControls: true);
        }
    }

    private void OpenOrionColourPicker(
        OrionThemeProfile profile,
        OrionThemeToken token,
        Control anchor)
    {
        if (IsBuiltInOrionTheme(profile))
        {
            return;
        }

        _orionThemePickerFlyout?.Hide();
        var startingColour = RawThemeColour(profile, token.Key);
        var preview = new Border
        {
            Width = 34,
            Height = 34,
            CornerRadius = new CornerRadius(9),
            Background = new SolidColorBrush(startingColour),
            BorderBrush = SolidBrush(Colors.White, 0.22),
            BorderThickness = new Thickness(1)
        };
        var status = new TextBlock
        {
            Text = token.Hint,
            FontSize = 10,
            Foreground = ThemeResourceBrush("OrionTextMutedBrush", "#55585C")
        };
        var spectrum = new OrionThemeSpectrum { Height = 142 };
        spectrum.SetColour(startingColour);
        var hue = new OrionThemeHueStrip { Width = 20 };
        hue.SetHue(spectrum.Hue);
        var hex = new TextBox
        {
            Text = ToHex(startingColour),
            Height = 30,
            Classes = { "orion-theme-input" },
            FontSize = 11
        };
        var changing = false;

        void ApplyColour(Color colour, string message)
        {
            if (changing)
            {
                return;
            }

            changing = true;
            try
            {
                profile.Colours[token.Key] = ToHex(colour);
                preview.Background = new SolidColorBrush(colour);
                hex.Text = ToHex(colour);
                status.Text = message;
                PreviewAndQueueOrionCustomTheme(profile);
            }
            finally
            {
                changing = false;
            }
        }

        spectrum.ColourChanged += (_, colour) =>
        {
            hue.SetHue(spectrum.Hue);
            ApplyColour(colour, "Live preview · autosaves");
        };
        hue.HueChanged += (_, value) =>
        {
            spectrum.SetHue(value, raiseChanged: false);
            ApplyColour(spectrum.CurrentColour, "Live preview · autosaves");
        };
        hex.TextChanged += (_, _) =>
        {
            if (changing || !TryParseThemeHex(hex.Text, out var colour))
            {
                return;
            }

            spectrum.SetColour(colour);
            hue.SetHue(spectrum.Hue);
            ApplyColour(colour, "Live preview · autosaves");
        };

        var spectrumGrid = new Grid
        {
            Height = 142,
            ColumnDefinitions = new ColumnDefinitions("*,20"),
            ColumnSpacing = 8
        };
        spectrumGrid.Children.Add(new Border
        {
            CornerRadius = new CornerRadius(9),
            ClipToBounds = true,
            BorderBrush = ThemeResourceBrush("OrionBorderBrush", "#303235"),
            BorderThickness = new Thickness(1),
            Child = spectrum
        });
        var hueBorder = new Border
        {
            CornerRadius = new CornerRadius(9),
            ClipToBounds = true,
            BorderBrush = ThemeResourceBrush("OrionBorderBrush", "#303235"),
            BorderThickness = new Thickness(1),
            Child = hue
        };
        Grid.SetColumn(hueBorder, 1);
        spectrumGrid.Children.Add(hueBorder);

        var eyedropper = new Button
        {
            Height = 30,
            Classes = { "orion-theme-button" },
            Content = "Pick from screen"
        };
        eyedropper.Click += (_, _) =>
        {
            status.Text = "Click any colour on your monitor · Esc cancels";
            _orionScreenPicker?.Close();
            _orionScreenPicker = new OrionScreenColourPickerWindow(this);
            _orionScreenPicker.Picked += (_, colour) =>
            {
                spectrum.SetColour(colour);
                hue.SetHue(spectrum.Hue);
                ApplyColour(colour, "Picked from screen · autosaves");
            };
            _orionScreenPicker.Show(this);
        };

        var top = new Grid { ColumnDefinitions = new ColumnDefinitions("34,10,*") };
        top.Children.Add(preview);
        var labels = new StackPanel
        {
            VerticalAlignment = VerticalAlignment.Center,
            Spacing = 2,
            Children =
            {
                new TextBlock
                {
                    Text = token.Label,
                    FontSize = 13,
                    Foreground = ThemeResourceBrush("OrionTextPrimaryBrush", "#FFFFFF")
                },
                status
            }
        };
        Grid.SetColumn(labels, 2);
        top.Children.Add(labels);
        var content = new StackPanel
        {
            Width = 276,
            Spacing = 9,
            Children = { top, spectrumGrid, hex, eyedropper }
        };
        var flyout = new Flyout
        {
            Placement = PlacementMode.BottomEdgeAlignedLeft,
            Content = new Border
            {
                Padding = new Thickness(13),
                Background = ThemeResourceBrush("OrionPanelBrush", "#07080A"),
                BorderBrush = ThemeResourceBrush("OrionBorderStrongBrush", "#66696C"),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(13),
                Child = content
            }
        };
        _orionThemePickerFlyout = flyout;
        flyout.Closed += (_, _) =>
        {
            if (ReferenceEquals(_orionThemePickerFlyout, flyout))
            {
                _orionThemePickerFlyout = null;
                RefreshOrionThemeStudio();
            }
        };
        flyout.ShowAt(anchor);
    }

    private void OrionThemeWindow_PointerMoved(object? sender, PointerEventArgs e)
    {
        if (_orionThemeDisposed || !_orionLiquidGlassLayer.IsVisible)
        {
            return;
        }

        _orionLiquidGlassLayer.SetPointer(e.GetPosition(_orionLiquidGlassLayer));
    }

    private void OrionThemeVisibilityPropertyChanged(object? sender, AvaloniaPropertyChangedEventArgs e)
    {
        if (e.Property == Visual.IsVisibleProperty)
        {
            UpdateOrionGlassAnimationState();
        }
    }

    private void UpdateOrionGlassAnimationState()
    {
        if (!_orionThemeStateLoaded || _orionThemeDisposed)
        {
            return;
        }

        var windowActive = _orionThemeUsesGlass && IsVisible;
        _orionLiquidGlassLayer.SetAnimationActive(windowActive);
    }

    private static void CompleteOrionThemeColours(OrionThemeProfile profile)
    {
        var baseline = BuiltInOrionThemes().FirstOrDefault(theme => theme.Id == profile.BaseThemeId)
            ?? BuiltInOrionThemes()[0];
        foreach (var (key, value) in baseline.Colours)
        {
            if (!profile.Colours.ContainsKey(key) || !TryParseThemeHex(profile.Colours[key], out _))
            {
                profile.Colours[key] = value;
            }
        }
    }

    private static Color ThemeColour(OrionThemeProfile profile, string key)
    {
        var colour = RawThemeColour(profile, key);
        if (key.StartsWith("Text", StringComparison.Ordinal) || Math.Abs(profile.Saturation - 1) < 0.001)
        {
            return colour;
        }

        var hsv = colour.ToHsv();
        return HsvColor.ToRgb(
            hsv.H,
            Math.Clamp(hsv.S * profile.Saturation, 0, 1),
            hsv.V,
            colour.A / 255d);
    }

    private static Color RawThemeColour(OrionThemeProfile profile, string key)
    {
        if (profile.Colours.TryGetValue(key, out var raw) && TryParseThemeHex(raw, out var colour))
        {
            return colour;
        }

        return key.StartsWith("Text", StringComparison.Ordinal)
            ? Colors.White
            : Color.Parse("#08090A");
    }

    private void SetOrionThemeBrush(string key, Color colour, double opacity) =>
        Resources[key] = SolidBrush(colour, opacity);

    private static SolidColorBrush SolidBrush(Color colour, double opacity) =>
        new(WithOpacity(colour, opacity));

    private static Color WithOpacity(Color colour, double opacity) =>
        Color.FromArgb(
            (byte)Math.Round(Math.Clamp(opacity, 0, 1) * 255),
            colour.R,
            colour.G,
            colour.B);

    private static Color MixColour(Color first, Color second, double amount)
    {
        amount = Math.Clamp(amount, 0, 1);
        return Color.FromArgb(
            (byte)Math.Round(first.A + ((second.A - first.A) * amount)),
            (byte)Math.Round(first.R + ((second.R - first.R) * amount)),
            (byte)Math.Round(first.G + ((second.G - first.G) * amount)),
            (byte)Math.Round(first.B + ((second.B - first.B) * amount)));
    }

    private static LinearGradientBrush Gradient(
        Color start,
        Color end,
        double opacity,
        double secondOffset,
        RelativePoint startPoint,
        RelativePoint endPoint) => new()
    {
        StartPoint = startPoint,
        EndPoint = endPoint,
        GradientStops =
        [
            new GradientStop(WithOpacity(start, opacity), 0),
            new GradientStop(WithOpacity(end, opacity), secondOffset)
        ]
    };

    private static LinearGradientBrush CreateOrionEdgeStroke(
        OrionThemeProfile profile,
        bool isSolid,
        double opacity)
    {
        if (IsBuiltInOrionTheme(profile))
        {
            return new LinearGradientBrush
            {
                StartPoint = new RelativePoint(0, 0, RelativeUnit.Relative),
                EndPoint = new RelativePoint(1, 1, RelativeUnit.Relative),
                GradientStops =
                [
                    new GradientStop(Color.Parse("#7A7E81"), 0),
                    new GradientStop(Color.Parse("#5D6063"), 0.38),
                    new GradientStop(Color.Parse("#303235"), 1)
                ]
            };
        }

        var accent = ThemeColour(profile, "Accent");
        var strong = ThemeColour(profile, "BorderStrong");
        var border = ThemeColour(profile, "Border");
        return new LinearGradientBrush
        {
            StartPoint = new RelativePoint(0, 0, RelativeUnit.Relative),
            EndPoint = new RelativePoint(1, 1, RelativeUnit.Relative),
            GradientStops =
            [
                new GradientStop(WithOpacity(strong, isSolid ? 0.9 : Math.Min(1, opacity + 0.16)), 0),
                new GradientStop(WithOpacity(accent, isSolid ? 0.36 : 0.48), 0.31),
                new GradientStop(WithOpacity(border, opacity), 1)
            ]
        };
    }

    private IBrush ThemeResourceBrush(string key, string fallback)
    {
        if (Resources.TryGetValue(key, out var resource) && resource is IBrush brush)
        {
            return brush;
        }

        return new SolidColorBrush(Color.Parse(fallback));
    }

    private static string MaterialLabel(OrionThemeMaterial material) => material switch
    {
        OrionThemeMaterial.LiquidGlass => "Liquid Glass",
        OrionThemeMaterial.Transparent => "Transparent",
        _ => "Solid"
    };

    private static bool TryParseThemeHex(string? raw, out Color colour)
    {
        colour = Colors.Transparent;
        if (string.IsNullOrWhiteSpace(raw))
        {
            return false;
        }

        raw = raw.Trim();
        if (!raw.StartsWith('#'))
        {
            raw = "#" + raw;
        }

        try
        {
            colour = Color.Parse(raw);
            return true;
        }
        catch (FormatException)
        {
            return false;
        }
    }

    private static string ToHex(Color colour) => $"#{colour.R:X2}{colour.G:X2}{colour.B:X2}";

    private static string CssRgba(Color colour, double opacity) =>
        string.Create(
            CultureInfo.InvariantCulture,
            $"rgba({colour.R},{colour.G},{colour.B},{Math.Clamp(opacity, 0, 1):0.###})");

    private void DisposeOrionThemeStudio()
    {
        if (_orionThemeDisposed)
        {
            return;
        }

        _orionThemeDisposed = true;
        _orionThemeCommitTimer.Stop();
        CommitPendingOrionThemeChanges(refreshGeneratedControls: false);
        if (_orionThemeCommitTimerHooked)
        {
            _orionThemeCommitTimer.Tick -= OrionThemeCommitTimer_Tick;
            _orionThemeCommitTimerHooked = false;
        }
        PointerMoved -= OrionThemeWindow_PointerMoved;
        PropertyChanged -= OrionThemeVisibilityPropertyChanged;
        _orionThemePickerFlyout?.Hide();
        _orionScreenPicker?.Close();
        _orionLiquidGlassLayer.Dispose();
    }

    private sealed class OrionThemeRangeControl : Control
    {
        private double _value;
        private bool _dragging;

        public OrionThemeRangeControl()
        {
            Focusable = true;
            Cursor = new Cursor(StandardCursorType.Hand);
        }

        public double Minimum { get; init; }
        public double Maximum { get; init; } = 1;
        public IBrush TrackBrush { get; init; } = Brushes.DimGray;
        public IBrush FillBrush { get; init; } = Brushes.White;
        public IBrush ThumbBrush { get; init; } = Brushes.White;
        public IBrush ThumbBorderBrush { get; init; } = Brushes.Gray;

        public double Value
        {
            get => _value;
            set => SetValue(value, raiseChanged: false);
        }

        public event Action<double>? ValueChanged;

        public override void Render(DrawingContext context)
        {
            base.Render(context);
            var left = 4d;
            var right = Math.Max(left, Bounds.Width - 4d);
            var centreY = Bounds.Height / 2d;
            var range = Math.Max(0.000001, Maximum - Minimum);
            var progress = Math.Clamp((_value - Minimum) / range, 0, 1);
            var thumbX = left + ((right - left) * progress);

            context.DrawLine(
                new Pen(TrackBrush, 1.333),
                new Point(left, centreY),
                new Point(right, centreY));
            context.DrawLine(
                new Pen(FillBrush, 1.667),
                new Point(left, centreY),
                new Point(thumbX, centreY));
            context.DrawEllipse(
                ThumbBrush,
                new Pen(ThumbBorderBrush, 0.667),
                new Rect(thumbX - 3.667, centreY - 3.667, 7.333, 7.333));
        }

        protected override void OnPointerPressed(PointerPressedEventArgs e)
        {
            base.OnPointerPressed(e);
            if (!IsEnabled || !e.GetCurrentPoint(this).Properties.IsLeftButtonPressed)
            {
                return;
            }

            Focus();
            _dragging = true;
            e.Pointer.Capture(this);
            SetValueFromPointer(e.GetPosition(this));
            e.Handled = true;
        }

        protected override void OnPointerMoved(PointerEventArgs e)
        {
            base.OnPointerMoved(e);
            if (!_dragging)
            {
                return;
            }

            SetValueFromPointer(e.GetPosition(this));
            e.Handled = true;
        }

        protected override void OnPointerReleased(PointerReleasedEventArgs e)
        {
            base.OnPointerReleased(e);
            if (!_dragging)
            {
                return;
            }

            _dragging = false;
            e.Pointer.Capture(null);
            SetValueFromPointer(e.GetPosition(this));
            e.Handled = true;
        }

        protected override void OnKeyDown(KeyEventArgs e)
        {
            base.OnKeyDown(e);
            if (!IsEnabled || (e.Key != Key.Left && e.Key != Key.Right))
            {
                return;
            }

            var direction = e.Key == Key.Right ? 1d : -1d;
            SetValue(_value + (((Maximum - Minimum) / 100d) * direction), raiseChanged: true);
            e.Handled = true;
        }

        private void SetValueFromPointer(Point point)
        {
            var usableWidth = Math.Max(1, Bounds.Width - 8d);
            var progress = Math.Clamp((point.X - 4d) / usableWidth, 0, 1);
            SetValue(Minimum + ((Maximum - Minimum) * progress), raiseChanged: true);
        }

        private void SetValue(double value, bool raiseChanged)
        {
            var clamped = Math.Clamp(value, Minimum, Maximum);
            if (Math.Abs(clamped - _value) < 0.000001)
            {
                return;
            }

            _value = clamped;
            InvalidateVisual();
            if (raiseChanged)
            {
                ValueChanged?.Invoke(_value);
            }
        }
    }

    private sealed class OrionThemeSpectrum : Control
    {
        private double _hue;
        private double _saturation;
        private double _value;

        public event EventHandler<Color>? ColourChanged;
        public double Hue => _hue;
        public Color CurrentColour => HsvColor.ToRgb(_hue, _saturation, _value, 1);

        public void SetColour(Color colour)
        {
            var hsv = colour.ToHsv();
            _hue = hsv.H;
            _saturation = hsv.S;
            _value = hsv.V;
            InvalidateVisual();
        }

        public void SetHue(double hue, bool raiseChanged = true)
        {
            _hue = NormalizeHue(hue);
            InvalidateVisual();
            if (raiseChanged)
            {
                ColourChanged?.Invoke(this, CurrentColour);
            }
        }

        protected override void OnPointerPressed(PointerPressedEventArgs e)
        {
            base.OnPointerPressed(e);
            if (!e.GetCurrentPoint(this).Properties.IsLeftButtonPressed)
            {
                return;
            }

            e.Pointer.Capture(this);
            SetFromPointer(e.GetPosition(this));
            e.Handled = true;
        }

        protected override void OnPointerMoved(PointerEventArgs e)
        {
            base.OnPointerMoved(e);
            if (e.GetCurrentPoint(this).Properties.IsLeftButtonPressed)
            {
                SetFromPointer(e.GetPosition(this));
                e.Handled = true;
            }
        }

        protected override void OnPointerReleased(PointerReleasedEventArgs e)
        {
            base.OnPointerReleased(e);
            e.Pointer.Capture(null);
        }

        private void SetFromPointer(Point point)
        {
            if (Bounds.Width <= 0 || Bounds.Height <= 0)
            {
                return;
            }

            _saturation = Math.Clamp(point.X / Bounds.Width, 0, 1);
            _value = 1 - Math.Clamp(point.Y / Bounds.Height, 0, 1);
            InvalidateVisual();
            ColourChanged?.Invoke(this, CurrentColour);
        }

        public override void Render(DrawingContext context)
        {
            base.Render(context);
            var rect = new Rect(Bounds.Size);
            if (rect.Width <= 0 || rect.Height <= 0)
            {
                return;
            }

            context.FillRectangle(new LinearGradientBrush
            {
                StartPoint = new RelativePoint(0, 0, RelativeUnit.Relative),
                EndPoint = new RelativePoint(1, 0, RelativeUnit.Relative),
                GradientStops =
                [
                    new GradientStop(Colors.White, 0),
                    new GradientStop(HsvColor.ToRgb(_hue, 1, 1, 1), 1)
                ]
            }, rect);
            context.FillRectangle(new LinearGradientBrush
            {
                StartPoint = new RelativePoint(0, 0, RelativeUnit.Relative),
                EndPoint = new RelativePoint(0, 1, RelativeUnit.Relative),
                GradientStops =
                [
                    new GradientStop(Colors.Transparent, 0),
                    new GradientStop(Colors.Black, 1)
                ]
            }, rect);

            var point = new Point(
                _saturation * rect.Width,
                (1 - _value) * rect.Height);
            context.DrawEllipse(null, new Pen(Brushes.Black, 3), point, 6, 6);
            context.DrawEllipse(null, new Pen(Brushes.White, 1.5), point, 6, 6);
        }
    }

    private sealed class OrionThemeHueStrip : Control
    {
        private double _hue;
        public event EventHandler<double>? HueChanged;

        public void SetHue(double hue)
        {
            _hue = NormalizeHue(hue);
            InvalidateVisual();
        }

        protected override void OnPointerPressed(PointerPressedEventArgs e)
        {
            base.OnPointerPressed(e);
            if (!e.GetCurrentPoint(this).Properties.IsLeftButtonPressed)
            {
                return;
            }

            e.Pointer.Capture(this);
            SetFromPointer(e.GetPosition(this));
            e.Handled = true;
        }

        protected override void OnPointerMoved(PointerEventArgs e)
        {
            base.OnPointerMoved(e);
            if (e.GetCurrentPoint(this).Properties.IsLeftButtonPressed)
            {
                SetFromPointer(e.GetPosition(this));
                e.Handled = true;
            }
        }

        protected override void OnPointerReleased(PointerReleasedEventArgs e)
        {
            base.OnPointerReleased(e);
            e.Pointer.Capture(null);
        }

        private void SetFromPointer(Point point)
        {
            if (Bounds.Height <= 0)
            {
                return;
            }

            _hue = NormalizeHue(Math.Clamp(point.Y / Bounds.Height, 0, 1) * 360);
            InvalidateVisual();
            HueChanged?.Invoke(this, _hue);
        }

        public override void Render(DrawingContext context)
        {
            base.Render(context);
            var rect = new Rect(Bounds.Size);
            if (rect.Width <= 0 || rect.Height <= 0)
            {
                return;
            }

            var stops = new GradientStops();
            for (var index = 0; index <= 6; index++)
            {
                stops.Add(new GradientStop(HsvColor.ToRgb(index * 60, 1, 1, 1), index / 6d));
            }
            context.FillRectangle(new LinearGradientBrush
            {
                StartPoint = new RelativePoint(0, 0, RelativeUnit.Relative),
                EndPoint = new RelativePoint(0, 1, RelativeUnit.Relative),
                GradientStops = stops
            }, rect);

            var y = Math.Clamp(_hue / 360, 0, 1) * rect.Height;
            context.DrawLine(new Pen(Brushes.White, 2), new Point(0, y), new Point(rect.Width, y));
        }
    }

    private static double NormalizeHue(double hue)
    {
        hue %= 360;
        return hue < 0 ? hue + 360 : hue;
    }

    private sealed class OrionScreenColourPickerWindow : Window
    {
        private readonly OrionWindow _owner;
        public event EventHandler<Color>? Picked;

        public OrionScreenColourPickerWindow(OrionWindow owner)
        {
            _owner = owner;
            Background = Brushes.Transparent;
            TransparencyLevelHint = [WindowTransparencyLevel.Transparent];
            WindowDecorations = WindowDecorations.None;
            ShowInTaskbar = false;
            CanResize = false;
            Topmost = true;
            WindowStartupLocation = WindowStartupLocation.Manual;
            Cursor = new Cursor(StandardCursorType.Cross);
            Content = new Border { Background = Brushes.Transparent };
            ConfigureBounds();
            Opened += (_, _) => Focus();
            PointerPressed += OnPointerPressed;
            KeyDown += OnKeyDown;
        }

        private void ConfigureBounds()
        {
            var screens = _owner.Screens.All;
            if (screens.Count == 0)
            {
                return;
            }

            var left = screens.Min(screen => screen.Bounds.X);
            var top = screens.Min(screen => screen.Bounds.Y);
            var right = screens.Max(screen => screen.Bounds.Right);
            var bottom = screens.Max(screen => screen.Bounds.Bottom);
            var scaling = Math.Max(1, (_owner.Screens.ScreenFromWindow(_owner)
                ?? _owner.Screens.Primary
                ?? screens[0]).Scaling);
            Position = new PixelPoint(left, top);
            Width = Math.Max(1, (right - left) / scaling);
            Height = Math.Max(1, (bottom - top) / scaling);
        }

        private void OnPointerPressed(object? sender, PointerPressedEventArgs e)
        {
            if (!e.GetCurrentPoint(this).Properties.IsLeftButtonPressed)
            {
                return;
            }

            if (TrySampleScreen(out var colour))
            {
                Picked?.Invoke(this, colour);
            }
            e.Handled = true;
            Close();
        }

        private void OnKeyDown(object? sender, KeyEventArgs e)
        {
            if (e.Key == Key.Escape)
            {
                e.Handled = true;
                Close();
            }
        }

        private static bool TrySampleScreen(out Color colour)
        {
            colour = Colors.Transparent;
            if (!GetCursorPos(out var point))
            {
                return false;
            }

            var hdc = GetDC(IntPtr.Zero);
            if (hdc == IntPtr.Zero)
            {
                return false;
            }

            try
            {
                var pixel = GetPixel(hdc, point.X, point.Y);
                if (pixel == 0xFFFFFFFF)
                {
                    return false;
                }
                colour = Color.FromRgb(
                    (byte)(pixel & 0xFF),
                    (byte)((pixel >> 8) & 0xFF),
                    (byte)((pixel >> 16) & 0xFF));
                return true;
            }
            finally
            {
                ReleaseDC(IntPtr.Zero, hdc);
            }
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct NativePoint
        {
            public int X;
            public int Y;
        }

        [DllImport("user32.dll")]
        private static extern bool GetCursorPos(out NativePoint point);

        [DllImport("user32.dll")]
        private static extern IntPtr GetDC(IntPtr hWnd);

        [DllImport("user32.dll")]
        private static extern int ReleaseDC(IntPtr hWnd, IntPtr hDc);

        [DllImport("gdi32.dll")]
        private static extern uint GetPixel(IntPtr hDc, int x, int y);
    }
}
