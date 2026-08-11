using System.Net;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Hosting.Server;
using Microsoft.AspNetCore.Hosting.Server.Features;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.FileProviders;

namespace OrbitAvalonia;

internal sealed class MonacoStaticServer : IDisposable
{
    private readonly WebApplication _application;

    public MonacoStaticServer(string rootDirectory)
    {
        var contentRoot = Path.GetFullPath(rootDirectory);
        var fileProvider = new PhysicalFileProvider(contentRoot);
        var builder = WebApplication.CreateSlimBuilder();

        builder.WebHost.ConfigureKestrel(options =>
            options.Listen(IPAddress.Loopback, 0));

        _application = builder.Build();
        _application.UseStaticFiles(new StaticFileOptions
        {
            FileProvider = fileProvider,
            ServeUnknownFileTypes = false
        });
        _application.StartAsync().GetAwaiter().GetResult();

        var addresses = _application.Services
            .GetRequiredService<IServer>()
            .Features
            .Get<IServerAddressesFeature>()?
            .Addresses;
        var serverAddress = addresses?.SingleOrDefault()
            ?? throw new InvalidOperationException("The Monaco server did not start.");

        Address = new Uri(new Uri(serverAddress), "index.html");
    }

    public Uri Address { get; }

    public void Dispose()
    {
        _application.StopAsync().GetAwaiter().GetResult();
        _application.DisposeAsync().AsTask().GetAwaiter().GetResult();
    }
}
