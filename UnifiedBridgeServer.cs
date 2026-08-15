using System.Net;
using System.Text;
using System.Text.Json;

namespace OrbitAvalonia;

/// <summary>
/// App-lifetime host for the Orion Bridge protocol. Every preserved UI shares
/// this queue, connection state and console stream.
/// </summary>
internal sealed class UnifiedBridgeServer : IDisposable
{
    private enum Transport
    {
        Port,
        Stream,
        Compat
    }

    private sealed record PendingExecution(string Id, string Source);

    private sealed record ClientSession(
        string SessionId,
        string Identifier,
        string Username,
        Transport Transport,
        DateTime LastSeenUtc);

    internal sealed record BridgeLogEntry(DateTime TimestampUtc, string Level, string Message);

    internal sealed record BridgeClientInfo(string Identifier, string Username);

    private readonly record struct TransportState(bool Connected, DateTime LastSeenUtc, string Client);

    private const int Port = 31337;
    private const string ProtocolToken = "orion-bridge-v2";
    private const int MaximumRememberedLogs = 500;
    private static readonly TimeSpan ClientTimeout = TimeSpan.FromSeconds(3.5);
    private static readonly TimeSpan LongPollTimeout = TimeSpan.FromSeconds(2);
    private static readonly TimeSpan CompatPollTimeout = TimeSpan.FromSeconds(2);

    private readonly HttpListener _listener = new();
    private readonly CancellationTokenSource _cancellation = new();
    private readonly object _gate = new();
    private readonly Dictionary<string, ClientSession> _clientSessions = new(StringComparer.Ordinal);
    private readonly Dictionary<string, Queue<PendingExecution>> _clientPending = new(StringComparer.Ordinal);
    private readonly Queue<BridgeLogEntry> _logs = new();
    private readonly List<TaskCompletionSource<bool>> _pollWaiters = [];
    private readonly Dictionary<Transport, TransportState> _transports = new()
    {
        [Transport.Port] = new(false, DateTime.MinValue, string.Empty),
        [Transport.Stream] = new(false, DateTime.MinValue, string.Empty),
        [Transport.Compat] = new(false, DateTime.MinValue, string.Empty)
    };
    private readonly string _scriptsDirectory;
    private bool _disposed;
    private bool _connected;

    private static readonly Lazy<UnifiedBridgeServer> SharedInstance = new(
        static () => new UnifiedBridgeServer(),
        LazyThreadSafetyMode.ExecutionAndPublication);

    public static UnifiedBridgeServer Shared => SharedInstance.Value;

    public static void ShutdownShared()
    {
        if (SharedInstance.IsValueCreated)
        {
            SharedInstance.Value.Dispose();
        }
    }

    public event Action<bool>? ConnectionChanged;
    public event Action<string, string>? LogReceived;
    public event Action? ClientsChanged;

    public bool IsConnected
    {
        get
        {
            lock (_gate) return _connected;
        }
    }

    public IReadOnlyList<BridgeLogEntry> GetLogSnapshot()
    {
        lock (_gate) return _logs.ToArray();
    }

    public IReadOnlyList<BridgeClientInfo> GetConnectedClients()
    {
        lock (_gate)
        {
            return _clientSessions.Values
                .OrderBy(session => IdentifierNumber(session.Identifier))
                .ThenBy(session => session.Identifier, StringComparer.OrdinalIgnoreCase)
                .Select(session => new BridgeClientInfo(session.Identifier, session.Username))
                .ToArray();
        }
    }

    private UnifiedBridgeServer()
    {
        _scriptsDirectory = Path.Combine(AppContext.BaseDirectory, "Scripts");
        Directory.CreateDirectory(_scriptsDirectory);
        Start();
    }

    public string EnqueueExecute(string source) => EnqueueExecute(source, null);

    public string EnqueueExecute(
        string source,
        IReadOnlyCollection<string>? targetIdentifiers)
    {
        var id = $"exec_{Guid.NewGuid():N}";
        lock (_gate)
        {
            var targetSet = targetIdentifiers is null
                ? null
                : new HashSet<string>(targetIdentifiers, StringComparer.OrdinalIgnoreCase);
            var execution = new PendingExecution(id, source ?? string.Empty);
            foreach (var session in _clientSessions.Values)
            {
                if (targetSet is not null && !targetSet.Contains(session.Identifier))
                {
                    continue;
                }

                if (!_clientPending.TryGetValue(session.SessionId, out var queue))
                {
                    queue = new Queue<PendingExecution>();
                    _clientPending[session.SessionId] = queue;
                }
                queue.Enqueue(execution);
            }
            foreach (var waiter in _pollWaiters.ToArray()) waiter.TrySetResult(true);
        }
        return id;
    }

    private void Start()
    {
        try
        {
            _listener.Prefixes.Add($"http://127.0.0.1:{Port}/");
            _listener.Start();
            _ = AcceptLoopAsync();
            _ = WatchdogLoopAsync();
        }
        catch (HttpListenerException exception)
        {
            EmitLog("error", $"Orion Bridge could not listen on 127.0.0.1:{Port}: {exception.Message}");
        }
        catch (InvalidOperationException exception)
        {
            EmitLog("error", $"Orion Bridge could not start: {exception.Message}");
        }
    }

    private async Task AcceptLoopAsync()
    {
        while (!_cancellation.IsCancellationRequested)
        {
            HttpListenerContext context;
            try
            {
                context = await _listener.GetContextAsync().ConfigureAwait(false);
            }
            catch (HttpListenerException) when (_cancellation.IsCancellationRequested || _disposed)
            {
                return;
            }
            catch (ObjectDisposedException) when (_cancellation.IsCancellationRequested || _disposed)
            {
                return;
            }
            catch (InvalidOperationException) when (_cancellation.IsCancellationRequested || _disposed)
            {
                return;
            }

            _ = Task.Run(() => HandleRequestAsync(context), _cancellation.Token);
        }
    }

    private async Task HandleRequestAsync(HttpListenerContext context)
    {
        try
        {
            context.Response.Headers["Access-Control-Allow-Origin"] = "*";
            context.Response.Headers["Cache-Control"] = "no-store";
            var path = context.Request.Url?.AbsolutePath.TrimEnd('/') ?? string.Empty;
            var method = context.Request.HttpMethod.ToUpperInvariant();

            if (path.Equals("/bridge.lua", StringComparison.OrdinalIgnoreCase) ||
                path.Equals("/port_bridge.lua", StringComparison.OrdinalIgnoreCase) ||
                path.Equals("/stream_bridge.lua", StringComparison.OrdinalIgnoreCase) ||
                path.Equals("/compat_bridge.lua", StringComparison.OrdinalIgnoreCase))
            {
                await ServeBridgeScriptAsync(context).ConfigureAwait(false);
                return;
            }

            if (path.Equals("/status", StringComparison.OrdinalIgnoreCase))
            {
                await WriteJsonAsync(context, 200, StatusJson()).ConfigureAwait(false);
                return;
            }

            var route = ResolveRoute(path);
            if (route is null)
            {
                await WriteJsonAsync(context, 404, new { error = "not found" }).ConfigureAwait(false);
                return;
            }

            var (transport, endpoint) = route.Value;
            if (!IsVerifiedBridgeRequest(context))
            {
                await WriteJsonAsync(context, 403, new { error = "invalid bridge protocol" }).ConfigureAwait(false);
                return;
            }

            // A transport must complete the authenticated hello before any
            // polling, result or console endpoint is allowed to refresh it.
            // This prevents unrelated localhost traffic from becoming a
            // bridge connection merely by probing a known route.
            var sessionId = SessionIdForRequest(context, transport);
            if (!endpoint.Equals("hello", StringComparison.OrdinalIgnoreCase) &&
                !HasActiveHandshake(transport, sessionId))
            {
                await WriteJsonAsync(context, 409, new { error = "bridge hello required" }).ConfigureAwait(false);
                return;
            }

            switch (endpoint)
            {
                case "hello":
                    await HandleHelloAsync(context, transport, method).ConfigureAwait(false);
                    break;
                case "ping":
                    TouchClient(sessionId, transport);
                    await WriteJsonAsync(context, 200, new { ok = true }).ConfigureAwait(false);
                    break;
                case "next":
                    await HandleNextAsync(context, transport, sessionId).ConfigureAwait(false);
                    break;
                case "result":
                    await HandleResultAsync(context, transport, sessionId, method).ConfigureAwait(false);
                    break;
                case "log":
                    await HandleLogAsync(context, transport, sessionId, method).ConfigureAwait(false);
                    break;
                default:
                    await WriteJsonAsync(context, 404, new { error = "unknown bridge endpoint" }).ConfigureAwait(false);
                    break;
            }
        }
        catch (OperationCanceledException)
        {
            // Shutdown or an abandoned long poll.
        }
        catch (HttpListenerException)
        {
            // The executor may close a long-poll connection as it switches transports.
        }
        catch (Exception exception)
        {
            EmitLog("error", $"Orion Bridge request failed: {exception.Message}");
            try { await WriteJsonAsync(context, 500, new { error = "bridge request failed" }).ConfigureAwait(false); }
            catch { /* response was already closed */ }
        }
        finally
        {
            try { context.Response.Close(); } catch { }
        }
    }

    private async Task ServeBridgeScriptAsync(HttpListenerContext context)
    {
        var path = Path.Combine(_scriptsDirectory, "Orion Bridge.lua");
        if (!File.Exists(path))
        {
            await WriteTextAsync(context, 404, "-- Orion Bridge.lua is not installed in the Scripts folder\n", "text/plain; charset=utf-8").ConfigureAwait(false);
            return;
        }

        var bytes = await File.ReadAllBytesAsync(path, _cancellation.Token).ConfigureAwait(false);
        context.Response.StatusCode = 200;
        context.Response.ContentType = "text/plain; charset=utf-8";
        context.Response.ContentLength64 = bytes.Length;
        await context.Response.OutputStream.WriteAsync(bytes, _cancellation.Token).ConfigureAwait(false);
    }

    private static (Transport Transport, string Endpoint)? ResolveRoute(string path)
    {
        var segments = path.Split('/', StringSplitOptions.RemoveEmptyEntries);
        if (segments.Length != 2) return null;
        var transport = segments[0].ToLowerInvariant() switch
        {
            "port_bridge" => Transport.Port,
            "stream_bridge" => Transport.Stream,
            "compat_bridge" => Transport.Compat,
            _ => (Transport?)null
        };
        return transport is null ? null : (transport.Value, segments[1].ToLowerInvariant());
    }

    private static bool IsVerifiedBridgeRequest(HttpListenerContext context)
    {
        var supplied = context.Request.QueryString["protocol"]
            ?? context.Request.Headers["X-Orion-Bridge-Protocol"];
        return string.Equals(supplied, ProtocolToken, StringComparison.Ordinal);
    }

    private static string SessionIdForRequest(HttpListenerContext context, Transport transport)
    {
        var supplied = context.Request.QueryString["session_id"];
        return string.IsNullOrWhiteSpace(supplied)
            ? $"legacy-{transport.ToString().ToLowerInvariant()}"
            : supplied.Trim();
    }

    private bool HasActiveHandshake(Transport transport, string sessionId)
    {
        lock (_gate)
        {
            return _clientSessions.TryGetValue(sessionId, out var session) &&
                   session.Transport == transport &&
                   DateTime.UtcNow - session.LastSeenUtc <= ClientTimeout;
        }
    }

    private async Task HandleHelloAsync(HttpListenerContext context, Transport transport, string method)
    {
        var values = await ReadValuesAsync(context, method).ConfigureAwait(false);
        var client = GetValue(values, "client") ?? $"{transport.ToString().ToLowerInvariant()}-bridge";
        var sessionId = GetValue(values, "session_id");
        if (string.IsNullOrWhiteSpace(sessionId))
        {
            sessionId = SessionIdForRequest(context, transport);
        }
        var username = NormalizeUsername(GetValue(values, "username"), client);
        var requestedIdentifier = GetValue(values, "requested_identifier") ?? "User1";
        var registration = RegisterClient(sessionId, requestedIdentifier, username, transport, client);
        await WriteJsonAsync(context, 200, new
        {
            ok = true,
            transport = transport.ToString().ToLowerInvariant(),
            identifier = registration.Identifier,
            username = registration.Username,
            reassigned = !registration.Identifier.Equals(requestedIdentifier, StringComparison.OrdinalIgnoreCase)
        }).ConfigureAwait(false);
    }

    private async Task HandleNextAsync(HttpListenerContext context, Transport transport, string sessionId)
    {
        TouchClient(sessionId, transport);
        var timeout = transport == Transport.Compat ? CompatPollTimeout : LongPollTimeout;
        var batch = await WaitForExecutionsAsync(sessionId, timeout, _cancellation.Token).ConfigureAwait(false);
        if (batch.Count == 0)
        {
            await WriteJsonAsync(context, 200, new { exec = (object?)null }).ConfigureAwait(false);
            return;
        }

        if (batch.Count == 1)
        {
            var item = batch[0];
            await WriteJsonAsync(context, 200, new
            {
                exec = new
                {
                    id = item.Id,
                    source_b64 = Convert.ToBase64String(Encoding.UTF8.GetBytes(item.Source)),
                    encoding = "base64",
                    origin = "editor"
                }
            }).ConfigureAwait(false);
            return;
        }

        await WriteJsonAsync(context, 200, new
        {
            execs = batch.Select(item => new
            {
                id = item.Id,
                source_b64 = Convert.ToBase64String(Encoding.UTF8.GetBytes(item.Source)),
                encoding = "base64",
                origin = "editor"
            }).ToArray()
        }).ConfigureAwait(false);
    }

    private async Task HandleResultAsync(
        HttpListenerContext context,
        Transport transport,
        string sessionId,
        string method)
    {
        var values = await ReadValuesAsync(context, method).ConfigureAwait(false);
        var id = GetValue(values, "id") ?? "unknown";
        var ok = bool.TryParse(GetValue(values, "ok"), out var parsed) && parsed;
        var error = GetValue(values, "error");
        var errorB64 = GetValue(values, "error_b64");
        if (string.IsNullOrWhiteSpace(error) && !string.IsNullOrWhiteSpace(errorB64))
        {
            try { error = Encoding.UTF8.GetString(Convert.FromBase64String(errorB64)); }
            catch (FormatException) { error = "invalid encoded error"; }
        }
        TouchClient(sessionId, transport);
        EmitLog(ok ? "info" : "error", ok ? $"Execution {id} completed." : $"Execution {id} failed: {error ?? "unknown error"}");
        await WriteJsonAsync(context, 200, new { ok = true }).ConfigureAwait(false);
    }

    private async Task HandleLogAsync(
        HttpListenerContext context,
        Transport transport,
        string sessionId,
        string method)
    {
        var values = await ReadValuesAsync(context, method).ConfigureAwait(false);
        var level = GetValue(values, "level") ?? "info";
        var message = GetValue(values, "message");
        var messageB64 = GetValue(values, "message_b64");
        if (string.IsNullOrWhiteSpace(message) && !string.IsNullOrWhiteSpace(messageB64))
        {
            try { message = Encoding.UTF8.GetString(Convert.FromBase64String(messageB64)); }
            catch (FormatException) { message = "invalid encoded log"; }
        }
        TouchClient(sessionId, transport);
        EmitLog(level, message ?? string.Empty);
        await WriteJsonAsync(context, 200, new { ok = true }).ConfigureAwait(false);
    }

    private async Task<Dictionary<string, string>> ReadValuesAsync(HttpListenerContext context, string method)
    {
        var values = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        if (context.Request.Url is not null)
        {
            foreach (var pair in context.Request.Url.Query.TrimStart('?').Split('&', StringSplitOptions.RemoveEmptyEntries))
            {
                var split = pair.Split('=', 2);
                if (split.Length == 2) values[WebUtility.UrlDecode(split[0])] = WebUtility.UrlDecode(split[1]);
            }
        }

        if (method == "POST")
        {
            using var reader = new StreamReader(context.Request.InputStream, context.Request.ContentEncoding ?? Encoding.UTF8);
            var body = await reader.ReadToEndAsync(_cancellation.Token).ConfigureAwait(false);
            if (!string.IsNullOrWhiteSpace(body))
            {
                try
                {
                    using var document = JsonDocument.Parse(body);
                    if (document.RootElement.ValueKind == JsonValueKind.Object)
                    {
                        foreach (var property in document.RootElement.EnumerateObject())
                            values[property.Name] = property.Value.ValueKind == JsonValueKind.String
                                ? property.Value.GetString() ?? string.Empty
                                : property.Value.ToString();
                    }
                }
                catch (JsonException)
                {
                    // GET-style form data is accepted as a compatibility fallback.
                    foreach (var pair in body.Split('&', StringSplitOptions.RemoveEmptyEntries))
                    {
                        var split = pair.Split('=', 2);
                        if (split.Length == 2) values[WebUtility.UrlDecode(split[0])] = WebUtility.UrlDecode(split[1]);
                    }
                }
            }
        }
        return values;
    }

    private static string? GetValue(IReadOnlyDictionary<string, string> values, string key) =>
        values.TryGetValue(key, out var value) ? value : null;

    private async Task<List<PendingExecution>> WaitForExecutionsAsync(
        string sessionId,
        TimeSpan timeout,
        CancellationToken cancellationToken)
    {
        var waiter = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        lock (_gate)
        {
            // Register the waiter before checking the queue. This closes the
            // enqueue-between-check-and-wait race that could delay a click for
            // the entire long-poll timeout.
            _pollWaiters.Add(waiter);
            if (_clientPending.TryGetValue(sessionId, out var pending) && pending.Count > 0)
            {
                _pollWaiters.Remove(waiter);
                return TakePendingLocked(sessionId);
            }
        }
        try
        {
            await Task.WhenAny(waiter.Task, Task.Delay(timeout, cancellationToken)).ConfigureAwait(false);
        }
        finally
        {
            lock (_gate) _pollWaiters.Remove(waiter);
        }

        lock (_gate) return TakePendingLocked(sessionId);
    }

    private List<PendingExecution> TakePendingLocked(string sessionId)
    {
        if (!_clientPending.TryGetValue(sessionId, out var pending))
        {
            return [];
        }

        var batch = new List<PendingExecution>(Math.Min(8, pending.Count));
        while (pending.Count > 0 && batch.Count < 8) batch.Add(pending.Dequeue());
        return batch;
    }

    private BridgeClientInfo RegisterClient(
        string sessionId,
        string requestedIdentifier,
        string username,
        Transport transport,
        string clientLabel)
    {
        var connectionChanged = false;
        var clientsChanged = false;
        BridgeClientInfo result;
        lock (_gate)
        {
            var wasConnected = _connected;
            var now = DateTime.UtcNow;
            if (_clientSessions.TryGetValue(sessionId, out var existing))
            {
                clientsChanged = !existing.Username.Equals(username, StringComparison.Ordinal);
                existing = existing with
                {
                    Username = username,
                    Transport = transport,
                    LastSeenUtc = now
                };
                _clientSessions[sessionId] = existing;
                result = new BridgeClientInfo(existing.Identifier, existing.Username);
            }
            else
            {
                var preferred = NormalizeIdentifier(requestedIdentifier);
                var used = new HashSet<string>(
                    _clientSessions.Values.Select(session => session.Identifier),
                    StringComparer.OrdinalIgnoreCase);
                var assigned = used.Contains(preferred)
                    ? FirstAvailableIdentifier(used)
                    : preferred;
                var session = new ClientSession(sessionId, assigned, username, transport, now);
                _clientSessions[sessionId] = session;
                _clientPending[sessionId] = new Queue<PendingExecution>();
                result = new BridgeClientInfo(assigned, username);
                clientsChanged = true;
            }

            _transports[transport] = new(true, now, clientLabel);
            _connected = _clientSessions.Count > 0;
            connectionChanged = _connected != wasConnected;
        }

        if (connectionChanged) ConnectionChanged?.Invoke(_connected);
        if (clientsChanged) ClientsChanged?.Invoke();
        return result;
    }

    private void TouchClient(string sessionId, Transport transport)
    {
        lock (_gate)
        {
            if (!_clientSessions.TryGetValue(sessionId, out var session))
            {
                return;
            }

            var now = DateTime.UtcNow;
            _clientSessions[sessionId] = session with
            {
                Transport = transport,
                LastSeenUtc = now
            };
            _transports[transport] = new(true, now, session.Identifier);
        }
    }

    private async Task WatchdogLoopAsync()
    {
        while (!_cancellation.IsCancellationRequested)
        {
            try { await Task.Delay(TimeSpan.FromMilliseconds(500), _cancellation.Token).ConfigureAwait(false); }
            catch (OperationCanceledException) { return; }

            var connectionChanged = false;
            var clientsChanged = false;
            var now = DateTime.UtcNow;
            lock (_gate)
            {
                var wasConnected = _connected;
                foreach (var sessionId in _clientSessions
                             .Where(pair => now - pair.Value.LastSeenUtc > ClientTimeout)
                             .Select(pair => pair.Key)
                             .ToArray())
                {
                    _clientSessions.Remove(sessionId);
                    _clientPending.Remove(sessionId);
                    clientsChanged = true;
                }
                foreach (var transport in _transports.Keys.ToArray())
                {
                    var state = _transports[transport];
                    if (state.Connected && now - state.LastSeenUtc > ClientTimeout)
                        _transports[transport] = state with { Connected = false, Client = string.Empty };
                }
                _connected = _clientSessions.Count > 0;
                connectionChanged = _connected != wasConnected;
            }
            if (connectionChanged) ConnectionChanged?.Invoke(_connected);
            if (clientsChanged) ClientsChanged?.Invoke();
        }
    }

    private static string NormalizeUsername(string? username, string fallback)
    {
        var value = string.IsNullOrWhiteSpace(username) ? fallback : username.Trim();
        return value.Length <= 64 ? value : value[..64];
    }

    private static string NormalizeIdentifier(string? identifier)
    {
        if (!string.IsNullOrWhiteSpace(identifier) &&
            identifier.StartsWith("User", StringComparison.OrdinalIgnoreCase) &&
            int.TryParse(identifier[4..], out var number) && number > 0)
        {
            return $"User{number}";
        }
        return "User1";
    }

    private static int IdentifierNumber(string identifier) =>
        identifier.StartsWith("User", StringComparison.OrdinalIgnoreCase) &&
        int.TryParse(identifier[4..], out var number)
            ? number
            : int.MaxValue;

    private static string FirstAvailableIdentifier(IReadOnlySet<string> used)
    {
        for (var number = 1; number < int.MaxValue; number++)
        {
            var candidate = $"User{number}";
            if (!used.Contains(candidate)) return candidate;
        }
        return $"User{Guid.NewGuid():N}";
    }

    private void EmitLog(string level, string message)
    {
        var entry = new BridgeLogEntry(
            DateTime.UtcNow,
            string.IsNullOrWhiteSpace(level) ? "info" : level.Trim().ToLowerInvariant(),
            message ?? string.Empty);
        lock (_gate)
        {
            _logs.Enqueue(entry);
            while (_logs.Count > MaximumRememberedLogs) _logs.Dequeue();
        }
        LogReceived?.Invoke(entry.Level, entry.Message);
    }

    private string StatusJson()
    {
        lock (_gate)
        {
            return JsonSerializer.Serialize(new
            {
                connected = _connected,
                port_connected = _transports[Transport.Port].Connected,
                stream_connected = _transports[Transport.Stream].Connected,
                compat_connected = _transports[Transport.Compat].Connected,
                queued = _clientPending.Values.Sum(queue => queue.Count),
                clients = _clientSessions.Values
                    .OrderBy(session => IdentifierNumber(session.Identifier))
                    .Select(session => new
                    {
                        identifier = session.Identifier,
                        username = session.Username,
                        transport = session.Transport.ToString().ToLowerInvariant()
                    })
                    .ToArray()
            });
        }
    }

    private static async Task WriteJsonAsync(HttpListenerContext context, int status, object payload)
    {
        await WriteTextAsync(context, status, payload is string text ? text : JsonSerializer.Serialize(payload), "application/json; charset=utf-8").ConfigureAwait(false);
    }

    private static async Task WriteTextAsync(HttpListenerContext context, int status, string text, string contentType)
    {
        var bytes = Encoding.UTF8.GetBytes(text);
        context.Response.StatusCode = status;
        context.Response.ContentType = contentType;
        context.Response.ContentLength64 = bytes.Length;
        await context.Response.OutputStream.WriteAsync(bytes).ConfigureAwait(false);
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        _cancellation.Cancel();
        try { _listener.Stop(); } catch { }
        try { _listener.Close(); } catch { }
        lock (_gate)
        {
            foreach (var waiter in _pollWaiters) waiter.TrySetCanceled();
            _pollWaiters.Clear();
            _clientSessions.Clear();
            _clientPending.Clear();
            _connected = false;
        }
        ConnectionChanged = null;
        LogReceived = null;
        ClientsChanged = null;
        _cancellation.Dispose();
    }
}
