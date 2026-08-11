using Avalonia;
using Avalonia.Controls;
using Avalonia.Media;
using Avalonia.Media.Imaging;
using Avalonia.Platform;
using Avalonia.Threading;

namespace OrbitAvalonia;

public sealed partial class MainWindow
{
    private sealed record OrbitThemeValue(string Midnight, string Legacy);

    private static readonly IReadOnlyDictionary<string, OrbitThemeValue> OrbitBrushTheme =
        new Dictionary<string, OrbitThemeValue>(StringComparer.Ordinal)
        {
            ["OrbitPanelBrush"] = new("#0D121F", "#15181C"),
            ["OrbitEditorBrush"] = new("#080D17", "#101216"),
            ["OrbitChromeBorderBrush"] = new("#435675", "#6B6E70"),
            ["OrbitBorderBrush"] = new("#232F45", "#303235"),
            ["OrbitDividerBrush"] = new("#1D283B", "#353535"),
            ["OrbitSearchBrush"] = new("#131C2E", "#2A2E31"),
            ["OrbitCardBrush"] = new("#101828", "#25282A"),
            ["OrbitCardHoverBrush"] = new("#17233A", "#34383B"),
            ["OrbitControlBrush"] = new("#0F1726", "#202428"),
            ["OrbitControlHoverBrush"] = new("#152034", "#1D2328"),
            ["OrbitControlPressedBrush"] = new("#090F1D", "#12161A"),
            ["OrbitControlBorderBrush"] = new("#28364F", "#34393E"),
            ["OrbitChoiceBrush"] = new("#0E1523", "#15191D"),
            ["OrbitChoiceDisabledBrush"] = new("#0B121F", "#13171A"),
            ["OrbitChoiceDisabledBorderBrush"] = new("#1B273B", "#22272B"),
            ["OrbitChoiceDisabledHoverBrush"] = new("#0E1727", "#15191C"),
            ["OrbitChoiceDisabledHoverBorderBrush"] = new("#223148", "#292F34"),
            ["OrbitDeepBrush"] = new("#060A13", "#0C0E12"),
            ["OrbitRaisedBrush"] = new("#0C1320", "#191C20"),
            ["OrbitChipBrush"] = new("#070C16", "#0B0D0F"),
            ["OrbitDialogHeaderBrush"] = new("#0E1625", "#1B1F23"),
            ["OrbitInputBrush"] = new("#070D17", "#0D1014"),
            ["OrbitMutedSurfaceBrush"] = new("#090F1B", "#0E1115"),
            ["OrbitCloseBackdropBrush"] = new("#080D17", "#16191C"),
            ["OrbitTextBrush"] = new("#FFFFFF", "#FFFFFF"),
            ["OrbitSubtextBrush"] = new("#8CA0BA", "#A1A4A6"),
            ["OrbitMutedTextBrush"] = new("#55698A", "#737E91"),
            ["OrbitIconBrush"] = new("#C8C7CC", "#C8C7CC")
        };

    private static readonly IReadOnlyDictionary<string, OrbitThemeValue> OrbitColorTheme =
        new Dictionary<string, OrbitThemeValue>(StringComparer.Ordinal)
        {
            ["OrbitChromeStartColor"] = new("#0F1728", "#222526"),
            ["OrbitChromeEndColor"] = new("#080D17", "#16191C"),
            ["OrbitMainChromeEndColor"] = new("#070C15", "#141719"),
            ["OrbitRailStartColor"] = new("#131D32", "#2A2E31"),
            ["OrbitRailEndColor"] = new("#080E1A", "#14171B"),
            ["OrbitSurfaceStartColor"] = new("#090E1B", "#0D0F12"),
            ["OrbitSurfaceEndColor"] = new("#060A13", "#0D0F11"),
            ["OrbitDialogStartColor"] = new("#10192B", "#202428"),
            ["OrbitDialogMidColor"] = new("#0C1321", "#171A1E"),
            ["OrbitDialogEndColor"] = new("#070C16", "#121519")
        };

    private static readonly IReadOnlyDictionary<string, string> MidnightColourMap =
        new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["#222526"] = "#111A2C",
            ["#16191C"] = "#090E1A",
            ["#2A2E31"] = "#152037",
            ["#14171B"] = "#090F1D",
            ["#0D0F12"] = "#0A101E",
            ["#0D0F11"] = "#070B15",
            ["#15181C"] = "#0E1422",
            ["#101216"] = "#090E1A",
            ["#303235"] = "#27344D",
            ["#353535"] = "#202C42",
            ["#202428"] = "#111A2A",
            ["#222426"] = "#121C2E",
            ["#25282A"] = "#121B2D",
            ["#34383B"] = "#1A2740",
            ["#292D31"] = "#18243A",
            ["#0D1014"] = "#080E1A",
            ["#15191D"] = "#0F1727",
            ["#1D2328"] = "#17243A",
            ["#12161A"] = "#0A1120",
            ["#13171A"] = "#0C1422",
            ["#22272B"] = "#1E2B42",
            ["#15191C"] = "#101A2B",
            ["#292F34"] = "#263650",
            ["#0C0E12"] = "#070B15",
            ["#191C20"] = "#0D1524",
            ["#0B0D0F"] = "#080D18",
            ["#0D1012"] = "#080D18",
            ["#0E1114"] = "#090F1C",
            ["#0E1115"] = "#0A111E",
            ["#0F1216"] = "#090F1C",
            ["#101317"] = "#080E1A",
            ["#111418"] = "#090F1C",
            ["#11121A"] = "#090F1D",
            ["#121519"] = "#080D18",
            ["#13171B"] = "#0B1220",
            ["#171A1D"] = "#0C1423",
            ["#171A1E"] = "#0D1525",
            ["#181B1D"] = "#0D1524",
            ["#181B1F"] = "#0D1524",
            ["#1B1E21"] = "#111A2B",
            ["#1B1F23"] = "#101929",
            ["#202324"] = "#111A2A",
            ["#22262A"] = "#121C2E",
            ["#22272C"] = "#142038",
            ["#24282C"] = "#152139",
            ["#242A31"] = "#16233B",
            ["#252A2F"] = "#17243C",
            ["#282C30"] = "#18253E",
            ["#292E33"] = "#19263F",
            ["#30353A"] = "#293750",
            ["#332D22"] = "#282319",
            ["#34393E"] = "#2D3C58",
            ["#3A4148"] = "#30415F",
            ["#3C4247"] = "#31425F",
            ["#44494D"] = "#354764",
            ["#454B50"] = "#354966",
            ["#4D5862"] = "#3A4F70",
            ["#505255"] = "#3B4C6A",
            ["#55595C"] = "#3D4E6C",
            ["#565B60"] = "#3E506F",
            ["#5B6065"] = "#425574",
            ["#62676B"] = "#485C7B"
        };

    private static Color ThemeColor(string legacyColour)
    {
        if (OrbitPreferences.LegacyColoursEnabled ||
            !MidnightColourMap.TryGetValue(legacyColour, out var midnightColour))
        {
            return Color.Parse(legacyColour);
        }

        return DarkenMidnight(Color.Parse(midnightColour));
    }

    private static Color DarkenMidnight(Color colour) =>
        Color.FromArgb(
            colour.A,
            (byte)Math.Round(colour.R * 0.9),
            (byte)Math.Round(colour.G * 0.9),
            (byte)Math.Round(colour.B * 0.9));

    private Image? _orbitHeaderLogo;
    private static Bitmap? _defaultLogoBitmap;
    private static Bitmap? _invertedLogoBitmap;

    private void EnsureDynamicThemeBrushes()
    {
        var surfaceColor = Resources.TryGetValue("OrbitSurfaceStartColor", out var s) && s is Color sc ? sc : Color.Parse("#090E1B");
        var lightness = (0.299 * surfaceColor.R + 0.587 * surfaceColor.G + 0.114 * surfaceColor.B) / 255.0;
        var isLight = lightness > 0.6;

        if (isLight)
        {
            if (!Resources.ContainsKey("OrbitTextBrush") || (Resources["OrbitTextBrush"] as SolidColorBrush)?.Color == Colors.White)
                Resources["OrbitTextBrush"] = new SolidColorBrush(Color.Parse("#111827"));
            if (!Resources.ContainsKey("OrbitSubtextBrush") || (Resources["OrbitSubtextBrush"] as SolidColorBrush)?.Color == Color.Parse("#8CA0BA"))
                Resources["OrbitSubtextBrush"] = new SolidColorBrush(Color.Parse("#4B5563"));
            if (!Resources.ContainsKey("OrbitMutedTextBrush") || (Resources["OrbitMutedTextBrush"] as SolidColorBrush)?.Color == Color.Parse("#55698A"))
                Resources["OrbitMutedTextBrush"] = new SolidColorBrush(Color.Parse("#6B7280"));
            Resources["OrbitIconBrush"] = new SolidColorBrush(Color.Parse("#111827"));
        }

        UpdateHeaderLogoVisual(isLight);
    }

    private void UpdateHeaderLogoVisual(bool isLight)
    {
        if (_orbitHeaderLogo is null)
        {
            _orbitHeaderLogo = this.FindControl<Image>("OrbitHeaderLogo");
            if (_orbitHeaderLogo is null) return;
        }

        try
        {
            if (isLight)
            {
                if (_invertedLogoBitmap is null)
                {
                    var uri = new Uri("avares://Orion/Assets/orbit-logo-hq.png");
                    using var stream = AssetLoader.Open(uri);
                    using var original = new Bitmap(stream);
                    _invertedLogoBitmap = CreateInvertedBitmap(original);
                }
                _orbitHeaderLogo.Source = _invertedLogoBitmap;
            }
            else
            {
                if (_defaultLogoBitmap is null)
                {
                    var uri = new Uri("avares://Orion/Assets/orbit-logo-hq.png");
                    using var stream = AssetLoader.Open(uri);
                    _defaultLogoBitmap = new Bitmap(stream);
                }
                _orbitHeaderLogo.Source = _defaultLogoBitmap;
            }
        }
        catch
        {
            // Fallback gracefully if logo asset loading is unavailable
        }
    }

    private static Bitmap CreateInvertedBitmap(Bitmap source)
    {
        var rtb = new RenderTargetBitmap(source.PixelSize, source.Dpi);
        using (var ctx = rtb.CreateDrawingContext())
        {
            ctx.DrawImage(source, new Rect(0, 0, source.Size.Width, source.Size.Height));
        }

        var wb = new WriteableBitmap(source.PixelSize, source.Dpi, Avalonia.Platform.PixelFormat.Bgra8888, Avalonia.Platform.AlphaFormat.Premul);
        using (var fb = wb.Lock())
        {
            int totalBytes = fb.RowBytes * source.PixelSize.Height;
            byte[] pixelData = new byte[totalBytes];
            rtb.CopyPixels(new PixelRect(source.PixelSize), fb.Address, totalBytes, fb.RowBytes);
            System.Runtime.InteropServices.Marshal.Copy(fb.Address, pixelData, 0, totalBytes);

            for (int i = 0; i < totalBytes; i += 4)
            {
                byte a = pixelData[i + 3];
                if (a > 10)
                {
                    pixelData[i] = (byte)(255 - pixelData[i]);         // Blue
                    pixelData[i + 1] = (byte)(255 - pixelData[i + 1]); // Green
                    pixelData[i + 2] = (byte)(255 - pixelData[i + 2]); // Red
                }
            }

            System.Runtime.InteropServices.Marshal.Copy(pixelData, 0, fb.Address, totalBytes);
        }
        return wb;
    }

    private void ApplyOrbitColourScheme(bool legacyColours, bool refreshGeneratedControls)
    {
        foreach (var (key, value) in OrbitBrushTheme)
        {
            Resources[key] = new SolidColorBrush(Color.Parse(legacyColours ? value.Legacy : value.Midnight));
        }

        foreach (var (key, value) in OrbitColorTheme)
        {
            Resources[key] = Color.Parse(legacyColours ? value.Legacy : value.Midnight);
        }

        ApplyActiveThemeOverrides();
        EnsureDynamicThemeBrushes();

        if (!refreshGeneratedControls)
        {
            return;
        }

        RebuildExplorerTree();
        RebuildEditorTabs();
        ApplySettingsContentInsets(_selectedSettingsTab);
        _settingsContentHost.Content = BuildSettingsContent(_selectedSettingsTab);
        UpdateSettingsTabVisuals();
        UpdatePageNavigationVisuals(_requestedPage);

        if (_monacoSourceAssigned)
        {
            _monacoReady = false;
            HideMonaco();
            _monacoWebView.Source = OrbitMonacoAddress();
        }
    }

    private void SetLegacyColours(bool enabled)
    {
        OrbitPreferences.SetLegacyColours(enabled);
        if (_themeStudioInitialized && !_activeThemeId.StartsWith("custom-", StringComparison.Ordinal))
        {
            _activeThemeId = enabled ? MidnightLegacyId : MidnightId;
            OrbitThemeStore.SaveActiveThemeId(_activeThemeId);
        }
        Dispatcher.UIThread.Post(() =>
        {
            ApplyOrbitColourScheme(enabled, refreshGeneratedControls: true);
            RefreshThemeStudio();
        });
    }

    private Uri OrbitMonacoAddress()
    {
        var background = "#080D17";
        if (Resources.TryGetValue("OrbitEditorBrush", out var b) && b is SolidColorBrush solid)
        {
            background = $"#{solid.Color.R:X2}{solid.Color.G:X2}{solid.Color.B:X2}";
        }
        else if (OrbitPreferences.LegacyColoursEnabled)
        {
            background = "#101216";
        }
        var builder = new UriBuilder(_monacoServer.Address)
        {
            Query = $"bg={Uri.EscapeDataString(background)}"
        };
        return builder.Uri;
    }
}
