using Avalonia;
using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Security.Principal;
using System.Threading;

namespace OrbitAvalonia;

internal static class Program
{
    private const string ElevatedLaunchArgument = "--orion-elevated";
    private const string SingleInstanceMutexName =
        @"Local\Orion.Desktop.SingleInstance.6A80D42B-1A0A-48B3-8A8A-310796D50E68";

    [STAThread]
    public static int Main(string[] args)
    {
        if (OrbitPreferences.PluginsRunAsAdministrator &&
            !IsRunningAsAdministrator() &&
            !Array.Exists(args, argument =>
                argument.Equals(ElevatedLaunchArgument, StringComparison.OrdinalIgnoreCase)) &&
            TryRestartAsAdministrator(args))
        {
            return 0;
        }

        if (!TryAcquireSingleInstance(out var instanceMutex))
        {
            return 0;
        }

        AppDomain.CurrentDomain.ProcessExit += (_, _) =>
            UnifiedBridgeServer.ShutdownShared();

        var exitCode = 0;
        try
        {
            exitCode = BuildAvaloniaApp().StartWithClassicDesktopLifetime(args);
        }
        finally
        {
            // This is intentionally duplicated with App's lifetime cleanup.
            // It is the final process boundary if startup fails or an unusual
            // window path returns from Avalonia without raising Exit.
            UnifiedBridgeServer.ShutdownShared();
            try
            {
                instanceMutex?.ReleaseMutex();
            }
            catch (ApplicationException)
            {
                // The process no longer owns the mutex; disposal is sufficient.
            }
            instanceMutex?.Dispose();
        }

        // WinForms preservation shells use their own foreground UI threads.
        // A graceful Avalonia shutdown closes them, but forcing process exit
        // here guarantees no orphan bridge/API host can survive an edge case.
        Environment.Exit(exitCode);
        return exitCode;
    }

    private static bool TryAcquireSingleInstance(out Mutex? mutex)
    {
        mutex = null;
        try
        {
            mutex = new Mutex(
                initiallyOwned: true,
                SingleInstanceMutexName,
                out var createdNew);
            if (createdNew)
            {
                return true;
            }

            mutex.Dispose();
            mutex = null;
            return false;
        }
        catch (UnauthorizedAccessException)
        {
            // An existing elevated Orion owns the named mutex.
            mutex?.Dispose();
            mutex = null;
            return false;
        }
    }

    internal static bool IsRunningAsAdministrator()
    {
        try
        {
            using var identity = WindowsIdentity.GetCurrent();
            return new WindowsPrincipal(identity)
                .IsInRole(WindowsBuiltInRole.Administrator);
        }
        catch
        {
            return false;
        }
    }

    private static bool TryRestartAsAdministrator(string[] args)
    {
        var executable = Environment.ProcessPath;
        if (string.IsNullOrWhiteSpace(executable))
        {
            return false;
        }

        var startInfo = new ProcessStartInfo
        {
            FileName = executable,
            WorkingDirectory = AppContext.BaseDirectory,
            UseShellExecute = true,
            Verb = "runas"
        };
        foreach (var argument in args)
        {
            if (!argument.Equals(ElevatedLaunchArgument, StringComparison.OrdinalIgnoreCase))
            {
                startInfo.ArgumentList.Add(argument);
            }
        }
        startInfo.ArgumentList.Add(ElevatedLaunchArgument);

        try
        {
            Process.Start(startInfo);
            return true;
        }
        catch (Win32Exception)
        {
            // If the user cancels UAC, Orion still opens normally. The saved
            // setting remains enabled and will request elevation next launch.
            return false;
        }
        catch (InvalidOperationException)
        {
            return false;
        }
    }

    public static AppBuilder BuildAvaloniaApp() =>
        AppBuilder.Configure<App>()
            .UsePlatformDetect()
            .LogToTrace();
}
