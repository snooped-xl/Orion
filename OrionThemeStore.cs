using System.Text.Json;

namespace OrbitAvalonia;

internal enum OrionThemeMaterial
{
    Solid,
    LiquidGlass,
    Transparent
}

internal sealed class OrionThemeProfile
{
    public int SchemaVersion { get; set; } = 1;
    public string Id { get; set; } = string.Empty;
    public string Name { get; set; } = "Untitled Theme";
    public string BaseThemeId { get; set; } = OrionThemeStore.OrionThemeId;
    public OrionThemeMaterial Material { get; set; } = OrionThemeMaterial.Solid;
    public Dictionary<string, string> Colours { get; set; } = new(StringComparer.Ordinal);
    public double SurfaceOpacity { get; set; } = 1;
    public double GlassIntensity { get; set; }
    public double Refraction { get; set; }
    public double Specular { get; set; } = 0.2;
    public double Saturation { get; set; } = 1;
    public double Noise { get; set; }

    public OrionThemeProfile Clone(string id, string name)
    {
        return new OrionThemeProfile
        {
            SchemaVersion = SchemaVersion,
            Id = id,
            Name = name,
            BaseThemeId = BaseThemeId,
            Material = Material,
            Colours = new Dictionary<string, string>(Colours, StringComparer.Ordinal),
            SurfaceOpacity = SurfaceOpacity,
            GlassIntensity = GlassIntensity,
            Refraction = Refraction,
            Specular = Specular,
            Saturation = Saturation,
            Noise = Noise
        };
    }
}

internal static class OrionThemeStore
{
    public const string OrionThemeId = "orion";
    public const string LiquidGlassThemeId = "liquid-glass";
    public const string TransparentThemeId = "transparent";

    private static readonly object Gate = new();
    private static readonly string DirectoryPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "Orion");
    private static readonly string ThemesPath = Path.Combine(DirectoryPath, "theme-studio.json");
    private static readonly string ActiveThemePath = Path.Combine(DirectoryPath, "active-theme");

    public static IReadOnlyList<OrionThemeProfile> LoadCustomThemes()
    {
        lock (Gate)
        {
            try
            {
                if (!File.Exists(ThemesPath))
                {
                    return [];
                }

                var profiles = JsonSerializer.Deserialize<List<OrionThemeProfile>>(
                    File.ReadAllText(ThemesPath)) ?? [];
                foreach (var profile in profiles)
                {
                    profile.Id = string.IsNullOrWhiteSpace(profile.Id) ? NewId() : profile.Id;
                    profile.Name = string.IsNullOrWhiteSpace(profile.Name) ? "Untitled Theme" : profile.Name.Trim();
                    profile.BaseThemeId = string.IsNullOrWhiteSpace(profile.BaseThemeId)
                        ? OrionThemeId
                        : profile.BaseThemeId;
                    profile.Colours = new Dictionary<string, string>(
                        profile.Colours ?? [],
                        StringComparer.Ordinal);
                    profile.SurfaceOpacity = Clamp(profile.SurfaceOpacity, 0, 1);
                    profile.GlassIntensity = Clamp(profile.GlassIntensity, 0, 1);
                    profile.Refraction = Clamp(profile.Refraction, 0, 1);
                    profile.Specular = Clamp(profile.Specular, 0, 1);
                    profile.Saturation = Clamp(profile.Saturation, 0.65, 1.5);
                    profile.Noise = Clamp(profile.Noise, 0, 0.12);
                }

                return profiles;
            }
            catch (Exception exception) when (
                exception is IOException or UnauthorizedAccessException or JsonException)
            {
                return [];
            }
        }
    }

    public static bool SaveCustomThemes(IEnumerable<OrionThemeProfile> themes)
    {
        lock (Gate)
        {
            var temporaryPath = ThemesPath + ".tmp";
            try
            {
                Directory.CreateDirectory(DirectoryPath);
                var options = new JsonSerializerOptions { WriteIndented = true };
                File.WriteAllText(temporaryPath, JsonSerializer.Serialize(themes, options));
                File.Move(temporaryPath, ThemesPath, overwrite: true);
                return true;
            }
            catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
            {
                try
                {
                    File.Delete(temporaryPath);
                }
                catch (Exception cleanupException) when (
                    cleanupException is IOException or UnauthorizedAccessException)
                {
                }

                return false;
            }
        }
    }

    public static string LoadActiveThemeId()
    {
        lock (Gate)
        {
            try
            {
                if (!File.Exists(ActiveThemePath))
                {
                    return OrionThemeId;
                }

                var id = File.ReadAllText(ActiveThemePath).Trim();
                return string.IsNullOrWhiteSpace(id) ? OrionThemeId : id;
            }
            catch (IOException)
            {
                return OrionThemeId;
            }
            catch (UnauthorizedAccessException)
            {
                return OrionThemeId;
            }
        }
    }

    public static bool SaveActiveThemeId(string id)
    {
        lock (Gate)
        {
            var temporaryPath = ActiveThemePath + ".tmp";
            try
            {
                Directory.CreateDirectory(DirectoryPath);
                File.WriteAllText(temporaryPath, id);
                File.Move(temporaryPath, ActiveThemePath, overwrite: true);
                return true;
            }
            catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
            {
                try
                {
                    File.Delete(temporaryPath);
                }
                catch (Exception cleanupException) when (
                    cleanupException is IOException or UnauthorizedAccessException)
                {
                }

                return false;
            }
        }
    }

    public static string NewId() => $"custom-{Guid.NewGuid():N}";

    private static double Clamp(double value, double minimum, double maximum) =>
        double.IsFinite(value) ? Math.Clamp(value, minimum, maximum) : minimum;
}
