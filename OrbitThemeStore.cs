using System.Text.Json;

namespace OrbitAvalonia;

internal sealed class OrbitThemeProfile
{
    public string Id { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string BaseThemeId { get; set; } = "midnight";
    public Dictionary<string, string> Colours { get; set; } = new(StringComparer.Ordinal);
}

internal static class OrbitThemeStore
{
    private static readonly object Gate = new();
    private static readonly string DirectoryPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Orbit");
    private static readonly string ThemesPath = Path.Combine(DirectoryPath, "themes.json");
    private static readonly string ActiveThemePath = Path.Combine(DirectoryPath, "active-theme");
    private static readonly string LiveEditPath = Path.Combine(DirectoryPath, "theme-live-edit");

    public static IReadOnlyList<OrbitThemeProfile> LoadCustomThemes()
    {
        lock (Gate)
        {
            try
            {
                if (!File.Exists(ThemesPath)) return [];
                var raw = File.ReadAllText(ThemesPath);
                var themes = JsonSerializer.Deserialize<List<OrbitThemeProfile>>(raw) ?? [];
                foreach (var theme in themes)
                {
                    theme.Id = string.IsNullOrWhiteSpace(theme.Id) ? NewId() : theme.Id;
                    theme.Name = string.IsNullOrWhiteSpace(theme.Name) ? "Untitled Theme" : theme.Name;
                    theme.BaseThemeId = string.IsNullOrWhiteSpace(theme.BaseThemeId) ? "midnight" : theme.BaseThemeId;
                    theme.Colours = new Dictionary<string, string>(theme.Colours ?? [], StringComparer.Ordinal);
                }
                return themes;
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or JsonException)
            {
                return [];
            }
        }
    }

    public static void SaveCustomThemes(IEnumerable<OrbitThemeProfile> themes)
    {
        lock (Gate)
        {
            try
            {
                Directory.CreateDirectory(DirectoryPath);
                var options = new JsonSerializerOptions { WriteIndented = true };
                File.WriteAllText(ThemesPath, JsonSerializer.Serialize(themes, options));
            }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
        }
    }

    public static string? LoadActiveThemeId()
    {
        lock (Gate)
        {
            try
            {
                var value = File.Exists(ActiveThemePath) ? File.ReadAllText(ActiveThemePath).Trim() : string.Empty;
                return string.IsNullOrWhiteSpace(value) ? null : value;
            }
            catch (IOException) { return null; }
            catch (UnauthorizedAccessException) { return null; }
        }
    }

    public static void SaveActiveThemeId(string id)
    {
        lock (Gate)
        {
            try
            {
                Directory.CreateDirectory(DirectoryPath);
                File.WriteAllText(ActiveThemePath, id);
            }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
        }
    }

    public static bool LoadLiveEdit()
    {
        lock (Gate)
        {
            try { return File.Exists(LiveEditPath) && File.ReadAllText(LiveEditPath).Trim() == "1"; }
            catch (IOException) { return false; }
            catch (UnauthorizedAccessException) { return false; }
        }
    }

    public static void SaveLiveEdit(bool enabled)
    {
        lock (Gate)
        {
            try
            {
                Directory.CreateDirectory(DirectoryPath);
                File.WriteAllText(LiveEditPath, enabled ? "1" : "0");
            }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
        }
    }

    public static string NewId() => $"custom-{Guid.NewGuid():N}";
}
