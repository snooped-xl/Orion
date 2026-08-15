using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.ApplicationLifetimes;
using System;
using System.Threading;
using System.Threading.Tasks;

namespace Orion.Extensibility;

/// <summary>
/// The native Orion extension entry point. Plugins run in-process and may use
/// the supplied Avalonia objects to extend any part of the application.
/// </summary>
public interface IOrionPlugin
{
    ValueTask InitializeAsync(
        IOrionPluginContext context,
        CancellationToken cancellationToken);

    ValueTask ShutdownAsync(CancellationToken cancellationToken) =>
        ValueTask.CompletedTask;
}

/// <summary>
/// Full-trust access to Orion's application, desktop lifetime, window, shared
/// services, and plugin-owned storage.
/// </summary>
public interface IOrionPluginContext : IServiceProvider
{
    string PluginId { get; }

    Application Application { get; }

    IClassicDesktopStyleApplicationLifetime DesktopLifetime { get; }

    Window MainWindow { get; }

    string PluginDirectory { get; }

    string DataDirectory { get; }

    CancellationToken ApplicationStopping { get; }

    void RegisterService(Type serviceType, object service);

    bool RemoveService(Type serviceType);

    T? GetService<T>() where T : class => GetService(typeof(T)) as T;

    void RegisterService<T>(T service) where T : class =>
        RegisterService(typeof(T), service);

    bool RemoveService<T>() where T : class => RemoveService(typeof(T));

    Task RunOnUiThreadAsync(Action action);
}

[AttributeUsage(AttributeTargets.Class, AllowMultiple = false, Inherited = false)]
public sealed class OrionPluginAttribute : Attribute
{
    public OrionPluginAttribute(string id, string name, string version)
    {
        Id = id;
        Name = name;
        Version = version;
    }

    public string Id { get; }

    public string Name { get; }

    public string Version { get; }

    public string Description { get; init; } = string.Empty;

    public string Author { get; init; } = string.Empty;
}
