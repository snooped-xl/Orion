namespace OrbitAvalonia;

internal static class OrbitPreferences
{
    private static readonly object Gate = new();
    private static readonly string PreferencesDirectory = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "Orbit");
    private static readonly string TopMostPath = Path.Combine(PreferencesDirectory, "topmost");
    private static readonly string LegacyColoursPath = Path.Combine(PreferencesDirectory, "legacy-colours");
    private static readonly string ResizablePath = Path.Combine(PreferencesDirectory, "resizable");
    private static readonly string PluginsRunAsAdministratorPath = Path.Combine(
        PreferencesDirectory,
        "plugins-run-as-administrator");
    private static readonly string SetupCompletedPath = Path.Combine(PreferencesDirectory, "setup-completed");
    private static readonly string AutoexecPathFile = Path.Combine(PreferencesDirectory, "autoexec-path");
    private static readonly string LastInterfacePath = Path.Combine(PreferencesDirectory, "last-ui");
    internal const string OrionInterface = "Orion";
    private static bool _topMostEnabled = LoadTopMost();
    private static bool _legacyColoursEnabled = LoadFlag(LegacyColoursPath);
    private static bool _resizableEnabled = LoadFlag(ResizablePath);
    private static bool _pluginsRunAsAdministrator = LoadFlag(PluginsRunAsAdministratorPath);
    private static bool _setupCompleted = LoadFlag(SetupCompletedPath);
    private static string? _autoexecPath = LoadText(AutoexecPathFile);
    private static string _lastInterface = LoadLastInterface();

    public static string LastInterface
    {
        get
        {
            lock (Gate) return _lastInterface;
        }
    }

    public static void SetLastInterface(string? selection)
    {
        var normalized = NormalizeInterface(selection);
        lock (Gate)
        {
            _lastInterface = normalized;
            try
            {
                Directory.CreateDirectory(PreferencesDirectory);
                File.WriteAllText(LastInterfacePath, normalized);
            }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
        }
    }

    public static bool TopMostEnabled
    {
        get
        {
            lock (Gate) return _topMostEnabled;
        }
    }

    public static void SetTopMost(bool enabled)
    {
        lock (Gate)
        {
            _topMostEnabled = enabled;
            try
            {
                Directory.CreateDirectory(PreferencesDirectory);
                File.WriteAllText(TopMostPath, enabled ? "1" : "0");
            }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
        }
    }

    public static bool LegacyColoursEnabled
    {
        get
        {
            lock (Gate) return _legacyColoursEnabled;
        }
    }

    public static void SetLegacyColours(bool enabled)
    {
        lock (Gate)
        {
            _legacyColoursEnabled = enabled;
            SaveFlag(LegacyColoursPath, enabled);
        }
    }

    public static bool ResizableEnabled
    {
        get
        {
            lock (Gate) return _resizableEnabled;
        }
    }

    public static bool PluginsRunAsAdministrator
    {
        get
        {
            lock (Gate) return _pluginsRunAsAdministrator;
        }
    }

    public static void SetPluginsRunAsAdministrator(bool enabled)
    {
        lock (Gate)
        {
            _pluginsRunAsAdministrator = enabled;
            SaveFlag(PluginsRunAsAdministratorPath, enabled);
        }
    }

    public static void SetResizable(bool enabled)
    {
        lock (Gate)
        {
            _resizableEnabled = enabled;
            SaveFlag(ResizablePath, enabled);
        }
    }

    public static bool SetupCompleted
    {
        get
        {
            lock (Gate) return _setupCompleted;
        }
    }

    public static void SetSetupCompleted(bool completed)
    {
        lock (Gate)
        {
            _setupCompleted = completed;
            SaveFlag(SetupCompletedPath, completed);
        }
    }

    public static string? AutoexecPath
    {
        get
        {
            lock (Gate) return _autoexecPath;
        }
    }

    public static void SetAutoexecPath(string? path)
    {
        lock (Gate)
        {
            _autoexecPath = string.IsNullOrWhiteSpace(path) ? null : path;
            try
            {
                Directory.CreateDirectory(PreferencesDirectory);
                if (_autoexecPath is null)
                {
                    if (File.Exists(AutoexecPathFile)) File.Delete(AutoexecPathFile);
                }
                else
                {
                    File.WriteAllText(AutoexecPathFile, _autoexecPath);
                }
            }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
        }
    }

    private static bool LoadTopMost()
    {
        return LoadFlag(TopMostPath);
    }

    private static bool LoadFlag(string path)
    {
        try { return File.Exists(path) && File.ReadAllText(path).Trim() == "1"; }
        catch (IOException) { return false; }
        catch (UnauthorizedAccessException) { return false; }
    }

    private static string? LoadText(string path)
    {
        try
        {
            var text = File.Exists(path) ? File.ReadAllText(path).Trim() : string.Empty;
            return string.IsNullOrWhiteSpace(text) ? null : text;
        }
        catch (IOException) { return null; }
        catch (UnauthorizedAccessException) { return null; }
    }

    private static string LoadLastInterface() => NormalizeInterface(LoadText(LastInterfacePath));

    private static string NormalizeInterface(string? selection) => selection switch
    {
        "SynapseV3" => "SynapseV3",
        "Synapse2017" => "Synapse2017",
        "SynapseBlue" => "SynapseBlue",
        "SynapseX" => "SynapseX",
        "RC7" => "RC7",
        "Krnl" => "Krnl",
        "Xeno" => "Xeno",
        "Calamari" => "Calamari",
        "AWP" => "AWP",
        "ZenithV2" => "ZenithV2",
        _ => OrionInterface
    };

    private static void SaveFlag(string path, bool enabled)
    {
        try
        {
            Directory.CreateDirectory(PreferencesDirectory);
            File.WriteAllText(path, enabled ? "1" : "0");
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }
}
