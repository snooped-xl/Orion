using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Threading;
using Orion.Extensibility;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Reflection;
using System.Runtime.Loader;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;

namespace OrbitAvalonia;

internal sealed class OrionPluginHost : IDisposable
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = true
    };

    private static readonly Regex ValidPluginId = new(
        "^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$",
        RegexOptions.CultureInvariant | RegexOptions.Compiled);

    private readonly IClassicDesktopStyleApplicationLifetime _desktop;
    private readonly Window _mainWindow;
    private readonly SemaphoreSlim _operationGate = new(1, 1);
    private readonly object _recordGate = new();
    private readonly object _serviceGate = new();
    private readonly Dictionary<Type, object> _services = new();
    private readonly Dictionary<string, bool> _enabledState =
        new(StringComparer.OrdinalIgnoreCase);
    private readonly List<PluginRecord> _records = new();
    private readonly CancellationTokenSource _applicationStopping = new();
    private bool _initialized;
    private bool _disposed;

    internal OrionPluginHost(
        IClassicDesktopStyleApplicationLifetime desktop,
        Window mainWindow)
    {
        _desktop = desktop;
        _mainWindow = mainWindow;
        PluginRoot = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Orion",
            "Plugins");
        PluginDataRoot = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Orion",
            "PluginData");
        StatePath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Orion",
            "plugin-state.json");

        _services[typeof(Application)] = Application.Current
            ?? throw new InvalidOperationException("Avalonia is not initialized.");
        _services[typeof(Window)] = mainWindow;
        _services[typeof(IClassicDesktopStyleApplicationLifetime)] = desktop;
    }

    internal event EventHandler? PluginsChanged;

    internal string PluginRoot { get; }

    internal string PluginDataRoot { get; }

    private string StatePath { get; }

    internal IReadOnlyList<OrionPluginInfo> Plugins
    {
        get
        {
            lock (_recordGate)
            {
                return _records
                    .Select(ToInfo)
                    .OrderBy(plugin => plugin.Name, StringComparer.OrdinalIgnoreCase)
                    .ToArray();
            }
        }
    }

    internal async Task InitializeAsync()
    {
        await _operationGate.WaitAsync();
        try
        {
            if (_disposed || _initialized)
            {
                return;
            }

            Directory.CreateDirectory(PluginRoot);
            Directory.CreateDirectory(PluginDataRoot);
            EnsurePluginReadme();
            LoadEnabledState();
            DiscoverInstalledPlugins();
            _initialized = true;

            foreach (var record in SnapshotRecords().Where(record => record.Enabled))
            {
                await StartRecordAsync(record);
            }
        }
        finally
        {
            _operationGate.Release();
            RaisePluginsChanged();
        }
    }

    internal async Task ImportAsync(string sourcePath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(sourcePath);
        await EnsureInitializedAsync();
        await _operationGate.WaitAsync();

        var stagingDirectory = Path.Combine(
            PluginRoot,
            ".staging-" + Guid.NewGuid().ToString("N"));

        try
        {
            Directory.CreateDirectory(stagingDirectory);
            var extension = Path.GetExtension(sourcePath);

            if (extension.Equals(".zip", StringComparison.OrdinalIgnoreCase) ||
                extension.Equals(".orionplugin", StringComparison.OrdinalIgnoreCase))
            {
                ExtractPackageSafely(sourcePath, stagingDirectory);
            }
            else if (Path.GetFileName(sourcePath)
                     .Equals("plugin.json", StringComparison.OrdinalIgnoreCase))
            {
                CopyDirectory(
                    Path.GetDirectoryName(sourcePath)
                        ?? throw new InvalidDataException("The selected manifest has no folder."),
                    stagingDirectory);
            }
            else if (extension.Equals(".dll", StringComparison.OrdinalIgnoreCase))
            {
                File.Copy(
                    sourcePath,
                    Path.Combine(stagingDirectory, Path.GetFileName(sourcePath)),
                    overwrite: true);
                await CreateManifestForLooseAssemblyAsync(
                    stagingDirectory,
                    Path.GetFileName(sourcePath));
            }
            else
            {
                throw new InvalidDataException(
                    "Choose a .orionplugin, .zip, plugin.json, or .NET .dll file.");
            }

            var manifestPath = Directory
                .EnumerateFiles(stagingDirectory, "plugin.json", SearchOption.AllDirectories)
                .OrderBy(path => path.Count(character => character == Path.DirectorySeparatorChar))
                .FirstOrDefault()
                ?? throw new InvalidDataException("The package does not contain plugin.json.");
            var packageRoot = Path.GetDirectoryName(manifestPath)
                ?? throw new InvalidDataException("The plugin manifest is invalid.");
            var manifest = ReadManifest(manifestPath);
            ValidateManifest(manifest, packageRoot);

            var existing = FindRecord(manifest.Id);
            var shouldRestart = existing?.Enabled == true;
            if (existing is not null)
            {
                await StopRecordAsync(existing);
            }

            var destination = Path.Combine(PluginRoot, manifest.Id);
            if (Directory.Exists(destination))
            {
                Directory.Delete(destination, recursive: true);
            }

            CopyDirectory(packageRoot, destination);
            _enabledState[manifest.Id] = shouldRestart;
            SaveEnabledState();
            DiscoverInstalledPlugins();

            if (shouldRestart && FindRecord(manifest.Id) is { } imported)
            {
                await StartRecordAsync(imported);
            }
        }
        finally
        {
            TryDeleteDirectory(stagingDirectory);
            _operationGate.Release();
            RaisePluginsChanged();
        }
    }

    internal async Task SetEnabledAsync(string pluginId, bool enabled)
    {
        await EnsureInitializedAsync();
        await _operationGate.WaitAsync();
        try
        {
            var record = FindRecord(pluginId)
                ?? throw new InvalidOperationException("The plugin is no longer installed.");

            record.Enabled = enabled;
            _enabledState[record.Manifest.Id] = enabled;
            SaveEnabledState();

            if (enabled)
            {
                await StartRecordAsync(record);
            }
            else
            {
                await StopRecordAsync(record);
                record.Error = null;
            }
        }
        finally
        {
            _operationGate.Release();
            RaisePluginsChanged();
        }
    }

    internal async Task ReloadAsync(string pluginId)
    {
        await EnsureInitializedAsync();
        await _operationGate.WaitAsync();
        try
        {
            var record = FindRecord(pluginId)
                ?? throw new InvalidOperationException("The plugin is no longer installed.");
            await StopRecordAsync(record);
            if (record.Enabled)
            {
                await StartRecordAsync(record);
            }
        }
        finally
        {
            _operationGate.Release();
            RaisePluginsChanged();
        }
    }

    internal async Task RemoveAsync(string pluginId)
    {
        await EnsureInitializedAsync();
        await _operationGate.WaitAsync();
        try
        {
            var record = FindRecord(pluginId)
                ?? throw new InvalidOperationException("The plugin is no longer installed.");
            await StopRecordAsync(record);
            lock (_recordGate)
            {
                _records.Remove(record);
            }

            _enabledState.Remove(record.Manifest.Id);
            SaveEnabledState();
            TryDeleteDirectory(record.Directory);
            TryDeleteDirectory(Path.Combine(PluginDataRoot, record.Manifest.Id));
        }
        finally
        {
            _operationGate.Release();
            RaisePluginsChanged();
        }
    }

    internal async Task RefreshAsync()
    {
        await EnsureInitializedAsync();
        await _operationGate.WaitAsync();
        try
        {
            foreach (var record in SnapshotRecords())
            {
                await StopRecordAsync(record);
            }

            DiscoverInstalledPlugins();
            foreach (var record in SnapshotRecords().Where(record => record.Enabled))
            {
                await StartRecordAsync(record);
            }
        }
        finally
        {
            _operationGate.Release();
            RaisePluginsChanged();
        }
    }

    private async Task EnsureInitializedAsync()
    {
        if (!_initialized)
        {
            await InitializeAsync();
        }
    }

    private void DiscoverInstalledPlugins()
    {
        var discovered = new List<PluginRecord>();
        Directory.CreateDirectory(PluginRoot);

        foreach (var directory in Directory.EnumerateDirectories(PluginRoot))
        {
            if (Path.GetFileName(directory).StartsWith(".staging-", StringComparison.Ordinal))
            {
                continue;
            }

            var manifestPath = Path.Combine(directory, "plugin.json");
            if (!File.Exists(manifestPath))
            {
                continue;
            }

            try
            {
                var manifest = ReadManifest(manifestPath);
                ValidateManifest(manifest, directory);
                discovered.Add(new PluginRecord(
                    manifest,
                    directory,
                    _enabledState.TryGetValue(manifest.Id, out var enabled) && enabled));
            }
            catch (Exception exception)
            {
                discovered.Add(new PluginRecord(
                    new PluginManifest
                    {
                        Id = Path.GetFileName(directory),
                        Name = Path.GetFileName(directory),
                        Version = "Invalid",
                        EntryAssembly = string.Empty
                    },
                    directory,
                    enabled: false)
                {
                    Error = CleanExceptionMessage(exception)
                });
            }
        }

        lock (_recordGate)
        {
            _records.Clear();
            _records.AddRange(discovered);
        }
    }

    private async Task StartRecordAsync(PluginRecord record)
    {
        if (record.IsRunning)
        {
            return;
        }

        record.Error = null;
        try
        {
            var entryPath = SafePathWithin(record.Directory, record.Manifest.EntryAssembly);
            var loadContext = new PluginLoadContext(record.Directory);
            var assembly = loadContext.LoadMainAssembly(entryPath);
            var entryType = ResolveEntryType(assembly, record.Manifest.EntryType);
            var instance = Activator.CreateInstance(entryType) as IOrionPlugin
                ?? throw new InvalidDataException(
                    $"{entryType.FullName} does not implement IOrionPlugin.");
            var context = new PluginContext(this, record);

            record.LoadContext = loadContext;
            record.Instance = instance;
            record.Context = context;
            await instance.InitializeAsync(context, _applicationStopping.Token);
            record.IsRunning = true;
        }
        catch (Exception exception)
        {
            record.Error = CleanExceptionMessage(exception);
            await ReleaseRecordRuntimeAsync(record, callShutdown: false);
        }
    }

    private async Task StopRecordAsync(PluginRecord record)
    {
        await ReleaseRecordRuntimeAsync(record, callShutdown: true);
        record.IsRunning = false;
    }

    private async Task ReleaseRecordRuntimeAsync(PluginRecord record, bool callShutdown)
    {
        if (callShutdown && record.Instance is not null)
        {
            try
            {
                using var timeout = CancellationTokenSource.CreateLinkedTokenSource(
                    _applicationStopping.Token);
                timeout.CancelAfter(TimeSpan.FromSeconds(5));
                await record.Instance.ShutdownAsync(timeout.Token);
            }
            catch (Exception exception)
            {
                Debug.WriteLine($"Orion plugin shutdown failed: {exception}");
            }
        }

        record.Context?.Dispose();
        record.Context = null;
        record.Instance = null;
        record.IsRunning = false;

        if (record.LoadContext is not null)
        {
            record.LoadContext.Unload();
            record.LoadContext = null;
        }
    }

    private static Type ResolveEntryType(Assembly assembly, string? configuredType)
    {
        if (!string.IsNullOrWhiteSpace(configuredType))
        {
            return assembly.GetType(configuredType, throwOnError: true, ignoreCase: false)
                ?? throw new InvalidDataException($"Plugin entry type {configuredType} was not found.");
        }

        try
        {
            return assembly.GetTypes().FirstOrDefault(type =>
                       !type.IsAbstract &&
                       !type.IsInterface &&
                       typeof(IOrionPlugin).IsAssignableFrom(type))
                   ?? throw new InvalidDataException(
                       "No concrete IOrionPlugin implementation was found.");
        }
        catch (ReflectionTypeLoadException exception)
        {
            var details = exception.LoaderExceptions
                .Where(error => error is not null)
                .Select(error => error!.Message)
                .FirstOrDefault();
            throw new InvalidDataException(
                details ?? "The plugin's types could not be loaded.",
                exception);
        }
    }

    private async Task CreateManifestForLooseAssemblyAsync(
        string stagingDirectory,
        string assemblyFileName)
    {
        await Task.Yield();
        var loadContext = new PluginLoadContext(stagingDirectory);
        try
        {
            var assembly = loadContext.LoadMainAssembly(
                Path.Combine(stagingDirectory, assemblyFileName));
            var entryType = ResolveEntryType(assembly, configuredType: null);
            var metadata = entryType.GetCustomAttribute<OrionPluginAttribute>();
            var baseId = Path.GetFileNameWithoutExtension(assemblyFileName);
            var manifest = new PluginManifest
            {
                Id = metadata?.Id ?? NormalizePluginId(baseId),
                Name = metadata?.Name ?? SplitPascalCase(entryType.Name.Replace("Plugin", string.Empty)),
                Version = metadata?.Version ?? assembly.GetName().Version?.ToString(3) ?? "1.0.0",
                Description = metadata?.Description ?? string.Empty,
                Author = metadata?.Author ?? string.Empty,
                EntryAssembly = assemblyFileName,
                EntryType = entryType.FullName
            };

            File.WriteAllText(
                Path.Combine(stagingDirectory, "plugin.json"),
                JsonSerializer.Serialize(manifest, JsonOptions));
        }
        finally
        {
            loadContext.Unload();
        }
    }

    private static PluginManifest ReadManifest(string path)
    {
        var manifest = JsonSerializer.Deserialize<PluginManifest>(
            File.ReadAllText(path),
            JsonOptions);
        return manifest ?? throw new InvalidDataException("plugin.json is empty.");
    }

    private static void ValidateManifest(PluginManifest manifest, string pluginDirectory)
    {
        if (!ValidPluginId.IsMatch(manifest.Id ?? string.Empty))
        {
            throw new InvalidDataException(
                "Plugin id must use only letters, numbers, dots, underscores, or hyphens.");
        }

        if (string.IsNullOrWhiteSpace(manifest.Name) ||
            string.IsNullOrWhiteSpace(manifest.Version) ||
            string.IsNullOrWhiteSpace(manifest.EntryAssembly))
        {
            throw new InvalidDataException(
                "plugin.json requires id, name, version, and entryAssembly.");
        }

        var entryPath = SafePathWithin(pluginDirectory, manifest.EntryAssembly);
        if (!File.Exists(entryPath))
        {
            throw new FileNotFoundException(
                $"Entry assembly {manifest.EntryAssembly} was not found.",
                entryPath);
        }
    }

    private static string SafePathWithin(string root, string relativePath)
    {
        if (Path.IsPathRooted(relativePath))
        {
            throw new InvalidDataException("Plugin paths must be relative.");
        }

        var normalizedRoot = Path.GetFullPath(root)
            .TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)
            + Path.DirectorySeparatorChar;
        var candidate = Path.GetFullPath(Path.Combine(normalizedRoot, relativePath));
        if (!candidate.StartsWith(normalizedRoot, StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidDataException("A plugin path escaped its package directory.");
        }

        return candidate;
    }

    private static void ExtractPackageSafely(string archivePath, string destinationRoot)
    {
        using var archive = ZipFile.OpenRead(archivePath);
        foreach (var entry in archive.Entries)
        {
            var destination = SafePathWithin(destinationRoot, entry.FullName);
            if (string.IsNullOrEmpty(entry.Name))
            {
                Directory.CreateDirectory(destination);
                continue;
            }

            Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
            using var source = entry.Open();
            using var target = new FileStream(
                destination,
                FileMode.Create,
                FileAccess.Write,
                FileShare.None);
            source.CopyTo(target);
        }
    }

    private static void CopyDirectory(string source, string destination)
    {
        Directory.CreateDirectory(destination);
        foreach (var directory in Directory.EnumerateDirectories(
                     source,
                     "*",
                     SearchOption.AllDirectories))
        {
            Directory.CreateDirectory(Path.Combine(
                destination,
                Path.GetRelativePath(source, directory)));
        }

        foreach (var file in Directory.EnumerateFiles(
                     source,
                     "*",
                     SearchOption.AllDirectories))
        {
            var target = Path.Combine(destination, Path.GetRelativePath(source, file));
            Directory.CreateDirectory(Path.GetDirectoryName(target)!);
            File.Copy(file, target, overwrite: true);
        }
    }

    private void LoadEnabledState()
    {
        _enabledState.Clear();
        try
        {
            if (!File.Exists(StatePath))
            {
                return;
            }

            var state = JsonSerializer.Deserialize<Dictionary<string, bool>>(
                File.ReadAllText(StatePath),
                JsonOptions);
            if (state is null)
            {
                return;
            }

            foreach (var entry in state)
            {
                _enabledState[entry.Key] = entry.Value;
            }
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
        catch (JsonException) { }
    }

    private void EnsurePluginReadme()
    {
        var readmePath = Path.Combine(PluginRoot, "README.txt");
        if (File.Exists(readmePath))
        {
            return;
        }

        const string readme = """
            ORION NATIVE PLUGINS

            Orion plugins are full-trust .NET 8 assemblies. They run inside Orion and can
            access the live Avalonia Application, desktop lifetime, main Window, shared
            services, their package folder, and a private writable data folder.

            Package a plugin as .orionplugin or .zip with this plugin.json at its root:

            {
              "id": "author.plugin-name",
              "name": "Plugin Name",
              "version": "1.0.0",
              "description": "What the plugin does.",
              "author": "Author",
              "entryAssembly": "PluginName.dll",
              "entryType": "PluginName.EntryPoint"
            }

            The entry type must implement Orion.Extensibility.IOrionPlugin. A loose DLL
            may also be imported directly; Orion will discover its entry type and create
            the manifest automatically. Package dependencies beside the entry assembly.
            """;

        try
        {
            File.WriteAllText(readmePath, readme);
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }

    private void SaveEnabledState()
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(StatePath)!);
            File.WriteAllText(
                StatePath,
                JsonSerializer.Serialize(_enabledState, JsonOptions));
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }

    private PluginRecord? FindRecord(string pluginId)
    {
        lock (_recordGate)
        {
            return _records.FirstOrDefault(record =>
                record.Manifest.Id.Equals(pluginId, StringComparison.OrdinalIgnoreCase));
        }
    }

    private PluginRecord[] SnapshotRecords()
    {
        lock (_recordGate)
        {
            return _records.ToArray();
        }
    }

    private static OrionPluginInfo ToInfo(PluginRecord record) => new(
        record.Manifest.Id,
        record.Manifest.Name,
        record.Manifest.Version,
        record.Manifest.Description ?? string.Empty,
        record.Manifest.Author ?? string.Empty,
        record.Enabled,
        record.IsRunning,
        record.Error);

    private static string NormalizePluginId(string value)
    {
        var normalized = Regex.Replace(value, "[^A-Za-z0-9._-]", "-").Trim('-');
        return string.IsNullOrWhiteSpace(normalized)
            ? "plugin-" + Guid.NewGuid().ToString("N")[..8]
            : normalized[..Math.Min(normalized.Length, 64)];
    }

    private static string SplitPascalCase(string value) =>
        Regex.Replace(value, "(?<!^)([A-Z])", " $1").Trim();

    private static string CleanExceptionMessage(Exception exception)
    {
        while (exception is TargetInvocationException { InnerException: not null })
        {
            exception = exception.InnerException;
        }

        return exception.Message.Replace(Environment.NewLine, " ").Trim();
    }

    private static void TryDeleteDirectory(string path)
    {
        try
        {
            if (Directory.Exists(path))
            {
                Directory.Delete(path, recursive: true);
            }
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }

    private object? GetService(Type serviceType)
    {
        lock (_serviceGate)
        {
            return _services.TryGetValue(serviceType, out var service) ? service : null;
        }
    }

    private void RegisterService(Type serviceType, object service)
    {
        lock (_serviceGate)
        {
            _services[serviceType] = service;
        }
    }

    private bool RemoveService(Type serviceType, object expectedService)
    {
        lock (_serviceGate)
        {
            return _services.TryGetValue(serviceType, out var current) &&
                   ReferenceEquals(current, expectedService) &&
                   _services.Remove(serviceType);
        }
    }

    private void RaisePluginsChanged()
    {
        if (Dispatcher.UIThread.CheckAccess())
        {
            PluginsChanged?.Invoke(this, EventArgs.Empty);
            return;
        }

        Dispatcher.UIThread.Post(() => PluginsChanged?.Invoke(this, EventArgs.Empty));
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        _applicationStopping.Cancel();
        foreach (var record in SnapshotRecords())
        {
            try
            {
                ReleaseRecordRuntimeAsync(record, callShutdown: true)
                    .Wait(TimeSpan.FromSeconds(1));
            }
            catch { }
        }

        _applicationStopping.Dispose();
        _operationGate.Dispose();
    }

    private sealed class PluginContext : IOrionPluginContext, IDisposable
    {
        private readonly OrionPluginHost _host;
        private readonly Dictionary<Type, object> _registrations = new();

        internal PluginContext(OrionPluginHost host, PluginRecord record)
        {
            _host = host;
            PluginId = record.Manifest.Id;
            PluginDirectory = record.Directory;
            DataDirectory = Path.Combine(host.PluginDataRoot, record.Manifest.Id);
            Directory.CreateDirectory(DataDirectory);
        }

        public string PluginId { get; }

        public Application Application => Application.Current!;

        public IClassicDesktopStyleApplicationLifetime DesktopLifetime => _host._desktop;

        public Window MainWindow => _host._mainWindow;

        public string PluginDirectory { get; }

        public string DataDirectory { get; }

        public CancellationToken ApplicationStopping => _host._applicationStopping.Token;

        public object? GetService(Type serviceType) => _host.GetService(serviceType);

        public void RegisterService(Type serviceType, object service)
        {
            ArgumentNullException.ThrowIfNull(serviceType);
            ArgumentNullException.ThrowIfNull(service);
            _host.RegisterService(serviceType, service);
            _registrations[serviceType] = service;
        }

        public bool RemoveService(Type serviceType)
        {
            if (!_registrations.Remove(serviceType, out var service))
            {
                return false;
            }

            return _host.RemoveService(serviceType, service);
        }

        public Task RunOnUiThreadAsync(Action action)
        {
            ArgumentNullException.ThrowIfNull(action);
            if (Dispatcher.UIThread.CheckAccess())
            {
                action();
                return Task.CompletedTask;
            }

            var completion = new TaskCompletionSource(
                TaskCreationOptions.RunContinuationsAsynchronously);
            Dispatcher.UIThread.Post(() =>
            {
                try
                {
                    action();
                    completion.SetResult();
                }
                catch (Exception exception)
                {
                    completion.SetException(exception);
                }
            });
            return completion.Task;
        }

        public void Dispose()
        {
            foreach (var registration in _registrations.ToArray())
            {
                _host.RemoveService(registration.Key, registration.Value);
            }

            _registrations.Clear();
        }
    }

    private sealed class PluginLoadContext : AssemblyLoadContext
    {
        private readonly string _pluginDirectory;

        internal PluginLoadContext(string pluginDirectory)
            : base($"OrionPlugin:{Path.GetFileName(pluginDirectory)}", isCollectible: true)
        {
            _pluginDirectory = pluginDirectory;
        }

        internal Assembly LoadMainAssembly(string path) => LoadAssemblyFromBytes(path);

        protected override Assembly? Load(AssemblyName assemblyName)
        {
            var shared = Default.Assemblies.FirstOrDefault(assembly =>
                AssemblyName.ReferenceMatchesDefinition(assembly.GetName(), assemblyName));
            if (shared is not null)
            {
                return shared;
            }

            var candidate = Path.Combine(_pluginDirectory, assemblyName.Name + ".dll");
            return File.Exists(candidate) ? LoadAssemblyFromBytes(candidate) : null;
        }

        private Assembly LoadAssemblyFromBytes(string path)
        {
            using var assemblyStream = new MemoryStream(File.ReadAllBytes(path));
            var symbolsPath = Path.ChangeExtension(path, ".pdb");
            if (!File.Exists(symbolsPath))
            {
                return LoadFromStream(assemblyStream);
            }

            using var symbolsStream = new MemoryStream(File.ReadAllBytes(symbolsPath));
            return LoadFromStream(assemblyStream, symbolsStream);
        }
    }

    private sealed class PluginRecord
    {
        internal PluginRecord(PluginManifest manifest, string directory, bool enabled)
        {
            Manifest = manifest;
            Directory = directory;
            Enabled = enabled;
        }

        internal PluginManifest Manifest { get; }
        internal string Directory { get; }
        internal bool Enabled { get; set; }
        internal bool IsRunning { get; set; }
        internal string? Error { get; set; }
        internal PluginLoadContext? LoadContext { get; set; }
        internal IOrionPlugin? Instance { get; set; }
        internal PluginContext? Context { get; set; }
    }

    private sealed class PluginManifest
    {
        public string Id { get; set; } = string.Empty;
        public string Name { get; set; } = string.Empty;
        public string Version { get; set; } = string.Empty;
        public string Description { get; set; } = string.Empty;
        public string Author { get; set; } = string.Empty;
        public string EntryAssembly { get; set; } = string.Empty;
        public string? EntryType { get; set; }
    }
}

internal sealed record OrionPluginInfo(
    string Id,
    string Name,
    string Version,
    string Description,
    string Author,
    bool Enabled,
    bool IsRunning,
    string? Error);
