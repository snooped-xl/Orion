using Avalonia.Media;
using Avalonia.Media.Imaging;
using System.ComponentModel;
using System.Globalization;
using System.Net;
using System.Net.Http.Headers;
using System.Text.Json;

namespace OrbitAvalonia;

internal enum ScriptHubProvider
{
    RobloxScripts,
    ScriptBlox,
    HaxHell,
    Rscripts
}

public sealed class ScriptHubCardModel : INotifyPropertyChanged
{
    private IImage? _thumbnail;

    public ScriptHubCardModel(
        string title,
        string subtitle,
        string imageUrl,
        string scriptBody = "",
        string description = "",
        string externalUrl = "",
        DateTimeOffset? updatedAt = null,
        long views = 0,
        bool isPaid = false,
        bool hasKey = false,
        bool isVerified = false,
        string gameId = "")
    {
        Title = string.IsNullOrWhiteSpace(title) ? "Untitled" : title.Trim();
        Subtitle = string.IsNullOrWhiteSpace(subtitle) ? "Universal Script" : subtitle.Trim();
        ImageUrl = imageUrl;
        ScriptBody = scriptBody?.Trim() ?? string.Empty;
        Description = string.IsNullOrWhiteSpace(description) ? Subtitle : description.Trim();
        ExternalUrl = externalUrl?.Trim() ?? string.Empty;
        UpdatedAt = updatedAt;
        Views = Math.Max(0, views);
        IsPaid = isPaid;
        HasKey = hasKey;
        IsVerified = isVerified;
        GameId = gameId?.Trim() ?? string.Empty;
    }

    public string Title { get; }

    public string Subtitle { get; }

    public string ImageUrl { get; }

    public string ScriptBody { get; }

    public string Description { get; }

    public string ExternalUrl { get; }

    public DateTimeOffset? UpdatedAt { get; }

    public long Views { get; }

    public bool IsPaid { get; }

    public bool HasKey { get; }

    public bool IsVerified { get; }

    public string GameId { get; }

    public string Key => $"{Title}\u001F{Subtitle}\u001F{ImageUrl}";

    public IImage? Thumbnail
    {
        get => _thumbnail;
        set
        {
            if (ReferenceEquals(_thumbnail, value))
            {
                return;
            }

            _thumbnail = value;
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(Thumbnail)));
        }
    }

    public event PropertyChangedEventHandler? PropertyChanged;
}

internal sealed record ScriptHubPageResult(
    IReadOnlyList<ScriptHubCardModel> Cards,
    bool HasMore);

internal sealed class ScriptHubService : IDisposable
{
    private const int CardLimit = 12;
    private const int MaximumImageBytes = 8 * 1024 * 1024;
    private readonly HttpClient _httpClient;
    private readonly Dictionary<string, IImage> _thumbnailCache = new(StringComparer.OrdinalIgnoreCase);
    private readonly object _thumbnailCacheLock = new();

    public ScriptHubService()
    {
        var handler = new HttpClientHandler
        {
            AutomaticDecompression = DecompressionMethods.All
        };

        _httpClient = new HttpClient(handler)
        {
            Timeout = TimeSpan.FromSeconds(18)
        };
        _httpClient.DefaultRequestHeaders.UserAgent.ParseAdd("Orbit/1.0 ScriptHub");
        _httpClient.DefaultRequestHeaders.Accept.Add(
            new MediaTypeWithQualityHeaderValue("application/json"));
    }

    public async Task<ScriptHubPageResult> FetchAsync(
        ScriptHubProvider provider,
        string query,
        int page,
        CancellationToken cancellationToken)
    {
        var trimmedQuery = query.Trim();

        return provider switch
        {
            ScriptHubProvider.RobloxScripts => await FetchRobloxScriptsAsync(trimmedQuery, page, cancellationToken),
            ScriptHubProvider.ScriptBlox => await FetchScriptBloxAsync(trimmedQuery, page, cancellationToken),
            ScriptHubProvider.HaxHell => await FetchHaxHellAsync(trimmedQuery, page, cancellationToken),
            ScriptHubProvider.Rscripts => await FetchRscriptsAsync(trimmedQuery, page, cancellationToken),
            _ => new ScriptHubPageResult([], false)
        };
    }

    public async Task LoadThumbnailsAsync(
        IEnumerable<ScriptHubCardModel> cards,
        CancellationToken cancellationToken)
    {
        var work = cards.Select(async card =>
        {
            if (string.IsNullOrWhiteSpace(card.ImageUrl))
            {
                return;
            }

            card.Thumbnail = await LoadThumbnailAsync(card.ImageUrl, cancellationToken);
        });

        await Task.WhenAll(work);
    }

    private async Task<ScriptHubPageResult> FetchRobloxScriptsAsync(
        string query,
        int page,
        CancellationToken cancellationToken)
    {
        var url = $"https://robloxscripts.com/api/v1/scripts?page={page}&limit=12&sort=newest";
        if (query.Length > 0)
        {
            url += $"&q={Uri.EscapeDataString(query[..Math.Min(query.Length, 100)])}";
        }

        using var document = await GetJsonAsync(url, "https://robloxscripts.com/", cancellationToken);
        if (!document.RootElement.TryGetProperty("data", out var scripts) ||
            scripts.ValueKind != JsonValueKind.Array)
        {
            throw new InvalidDataException("robloxscripts.com returned an unexpected response.");
        }

        var cards = scripts.EnumerateArray()
            .Take(CardLimit)
            .Select(script =>
            {
                var game = GetObject(script, "game");
                var image = FirstString(script, "image") ?? FirstString(game, "iconUrl");
                var rawUrl = FirstString(script, "rawScriptUrl");
                var slug = FirstString(script, "slug") ?? FirstString(script, "_id");
                var externalUrl = FirstString(script, "scriptPageUrl") ??
                                  (!string.IsNullOrWhiteSpace(slug)
                                      ? $"https://robloxscripts.com/script/{Uri.EscapeDataString(slug)}"
                                      : string.Empty);
                return new ScriptHubCardModel(
                    FirstString(script, "title") ?? "Untitled",
                    FirstString(game, "name") ?? "Universal Script",
                    ResolveUrl("https://robloxscripts.com", image),
                    RunnableBody(FirstString(script, "script"), rawUrl),
                    FirstString(script, "description") ?? string.Empty,
                    externalUrl,
                    FirstDateTimeOffset(script, "updatedAt", "updated_at", "dateUpdated", "createdAt", "created_at", "date"),
                    FirstInt64(script, "views", "viewCount", "viewsCount", "totalViews"),
                    IsPaidScript(script),
                    FirstBoolean(script, "key", "hasKey", "requiresKey", "keySystem"),
                    FirstBoolean(script, "verified", "isVerified"),
                    FirstScalarString(game, "gameId", "placeId", "id", "_id"));
            })
            .ToArray();
        return new ScriptHubPageResult(cards, scripts.GetArrayLength() > 0);
    }

    private async Task<ScriptHubPageResult> FetchScriptBloxAsync(
        string query,
        int page,
        CancellationToken cancellationToken)
    {
        var url = query.Length == 0
            ? $"https://scriptblox.com/api/script/fetch?page={page}"
            : $"https://scriptblox.com/api/script/search?q={Uri.EscapeDataString(query[..Math.Min(query.Length, 100)])}&page={page}";

        using var document = await GetJsonAsync(url, "https://scriptblox.com/", cancellationToken);
        var result = GetObject(document.RootElement, "result");
        if (!result.TryGetProperty("scripts", out var scripts) ||
            scripts.ValueKind != JsonValueKind.Array)
        {
            throw new InvalidDataException("ScriptBlox returned an unexpected response.");
        }

        var cards = scripts.EnumerateArray()
            .Take(CardLimit)
            .Select(script =>
            {
                var game = GetObject(script, "game");
                var image = FirstString(script, "image") ?? FirstString(game, "imageUrl");
                var slug = FirstString(script, "slug") ?? FirstString(script, "_id");
                return new ScriptHubCardModel(
                    FirstString(script, "title") ?? "Untitled",
                    FirstString(game, "name") ?? "Universal Script",
                    ResolveUrl("https://scriptblox.com", image),
                    RunnableBody(FirstString(script, "script"), null),
                    FirstString(script, "description") ?? string.Empty,
                    !string.IsNullOrWhiteSpace(slug)
                        ? $"https://scriptblox.com/script/{Uri.EscapeDataString(slug)}"
                        : string.Empty,
                    FirstDateTimeOffset(script, "updatedAt", "updated_at", "createdAt", "created_at"),
                    FirstInt64(script, "views", "viewCount", "viewsCount", "totalViews"),
                    IsPaidScript(script),
                    FirstBoolean(script, "key", "hasKey", "requiresKey", "keySystem"),
                    FirstBoolean(script, "verified", "isVerified"),
                    FirstScalarString(game, "gameId", "placeId", "id", "_id"));
            })
            .ToArray();
        return new ScriptHubPageResult(cards, scripts.GetArrayLength() > 0);
    }

    private async Task<ScriptHubPageResult> FetchHaxHellAsync(
        string query,
        int page,
        CancellationToken cancellationToken)
    {
        var url = query.Length == 0
            ? $"https://haxhell.com/api/v1/scripts?page={page}&limit=12"
            : $"https://haxhell.com/api/v1/search/scripts?page={page}&limit=12&q={Uri.EscapeDataString(query[..Math.Min(query.Length, 100)])}";

        using var document = await GetJsonAsync(url, "https://haxhell.com/", cancellationToken);
        if (!document.RootElement.TryGetProperty("data", out var scripts) ||
            scripts.ValueKind != JsonValueKind.Array)
        {
            throw new InvalidDataException("HaxHell returned an unexpected response.");
        }

        var cards = scripts.EnumerateArray()
            .Take(CardLimit)
            .Select(script =>
            {
                var game = GetObject(script, "game");
                var media = GetObject(script, "media");
                var links = GetObject(script, "links");
                var image = FirstString(media, "thumbnailUrl") ?? FirstString(game, "thumbnailUrl");
                return new ScriptHubCardModel(
                    FirstString(script, "title") ?? "Untitled",
                    FirstString(game, "name") ?? "Universal Script",
                    ResolveUrl("https://haxhell.com", image),
                    RunnableBody(null, ResolveUrl("https://haxhell.com", FirstString(links, "raw"))),
                    FirstString(script, "description") ?? string.Empty,
                    ResolveUrl("https://haxhell.com", FirstString(links, "webpage")),
                    FirstDateTimeOffset(script, "updatedAt", "updated_at", "publishedAt", "createdAt", "created_at", "date"),
                    FirstInt64(script, "views", "viewCount", "viewsCount", "totalViews"),
                    IsPaidScript(script),
                    FirstBoolean(script, "key", "hasKey", "requiresKey", "keySystem"),
                    FirstBoolean(script, "verified", "isVerified"),
                    FirstScalarString(game, "gameId", "placeId", "id", "_id"));
            })
            .ToArray();
        return new ScriptHubPageResult(cards, scripts.GetArrayLength() > 0);
    }

    private async Task<ScriptHubPageResult> FetchRscriptsAsync(
        string query,
        int page,
        CancellationToken cancellationToken)
    {
        var url = $"https://rscripts.net/api/v2/scripts?page={page}&orderBy=date&sort=desc";
        if (query.Length > 0)
        {
            url += $"&q={Uri.EscapeDataString(query[..Math.Min(query.Length, 100)])}";
        }

        using var document = await GetJsonAsync(url, "https://rscripts.net/", cancellationToken);
        if (!document.RootElement.TryGetProperty("scripts", out var scripts) ||
            scripts.ValueKind != JsonValueKind.Array)
        {
            throw new InvalidDataException("rscripts.net returned an unexpected response.");
        }

        var cards = scripts.EnumerateArray()
            .Take(CardLimit)
            .Select(script =>
            {
                var game = GetObject(script, "game");
                var image = FirstString(script, "image") ??
                            FirstString(script, "imageUrl") ??
                            FirstString(game, "imgurl") ??
                            FirstString(game, "thumbnailUrl") ??
                            FirstString(game, "logoUrl");
                var rawUrl = FirstString(script, "rawScript");
                var slug = FirstString(script, "slug") ?? FirstString(script, "_id");
                return new ScriptHubCardModel(
                    FirstString(script, "title") ?? "Untitled",
                    FirstString(game, "title") ?? "Universal / Unknown Game",
                    ResolveUrl("https://rscripts.net", image),
                    RunnableBody(FirstString(script, "script"), ResolveUrl("https://rscripts.net", rawUrl)),
                    FirstString(script, "description") ?? string.Empty,
                    !string.IsNullOrWhiteSpace(slug)
                        ? $"https://rscripts.net/script/{Uri.EscapeDataString(slug)}"
                        : string.Empty,
                    FirstDateTimeOffset(script, "updatedAt", "updated_at", "publishedAt", "createdAt", "created_at", "date"),
                    FirstInt64(script, "views", "viewCount", "viewsCount", "totalViews"),
                    IsPaidScript(script),
                    FirstBoolean(script, "key", "hasKey", "requiresKey", "keySystem"),
                    FirstBoolean(script, "verified", "isVerified"),
                    FirstScalarString(game, "gameId", "placeId", "id", "_id"));
            })
            .ToArray();
        return new ScriptHubPageResult(cards, scripts.GetArrayLength() > 0);
    }

    private async Task<JsonDocument> GetJsonAsync(
        string url,
        string referrer,
        CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, url);
        request.Headers.Referrer = new Uri(referrer);
        using var response = await _httpClient.SendAsync(request, cancellationToken);
        var body = await response.Content.ReadAsStringAsync(cancellationToken);

        if (!response.IsSuccessStatusCode)
        {
            throw new HttpRequestException(
                $"The provider returned HTTP {(int)response.StatusCode}.",
                null,
                response.StatusCode);
        }

        try
        {
            return JsonDocument.Parse(body);
        }
        catch (JsonException exception)
        {
            throw new InvalidDataException("The provider returned invalid data.", exception);
        }
    }

    private async Task<IImage?> LoadThumbnailAsync(
        string url,
        CancellationToken cancellationToken)
    {
        lock (_thumbnailCacheLock)
        {
            if (_thumbnailCache.TryGetValue(url, out var cached))
            {
                return cached;
            }
        }

        try
        {
            using var response = await _httpClient.GetAsync(
                url,
                HttpCompletionOption.ResponseHeadersRead,
                cancellationToken);
            response.EnsureSuccessStatusCode();

            if (response.Content.Headers.ContentLength > MaximumImageBytes)
            {
                return null;
            }

            await using var source = await response.Content.ReadAsStreamAsync(cancellationToken);
            using var imageBytes = new MemoryStream();
            var buffer = new byte[16 * 1024];
            var total = 0;

            while (true)
            {
                var read = await source.ReadAsync(buffer, cancellationToken);
                if (read == 0)
                {
                    break;
                }

                total += read;
                if (total > MaximumImageBytes)
                {
                    return null;
                }

                await imageBytes.WriteAsync(buffer.AsMemory(0, read), cancellationToken);
            }

            imageBytes.Position = 0;
            var bitmap = new Bitmap(imageBytes);
            lock (_thumbnailCacheLock)
            {
                _thumbnailCache[url] = bitmap;
            }

            return bitmap;
        }
        catch (Exception exception) when (
            exception is HttpRequestException or IOException or ArgumentException)
        {
            return null;
        }
    }

    private static JsonElement GetObject(JsonElement parent, string name) =>
        parent.ValueKind == JsonValueKind.Object &&
        parent.TryGetProperty(name, out var value) &&
        value.ValueKind == JsonValueKind.Object
            ? value
            : default;

    private static string? FirstString(JsonElement element, string name)
    {
        if (element.ValueKind != JsonValueKind.Object ||
            !element.TryGetProperty(name, out var value) ||
            value.ValueKind != JsonValueKind.String)
        {
            return null;
        }

        return value.GetString();
    }

    private static string FirstScalarString(JsonElement element, params string[] names)
    {
        if (element.ValueKind != JsonValueKind.Object)
        {
            return string.Empty;
        }

        foreach (var name in names)
        {
            if (!element.TryGetProperty(name, out var value))
            {
                continue;
            }

            if (value.ValueKind == JsonValueKind.String)
            {
                return value.GetString()?.Trim() ?? string.Empty;
            }

            if (value.ValueKind == JsonValueKind.Number)
            {
                return value.GetRawText();
            }
        }

        return string.Empty;
    }

    private static long FirstInt64(JsonElement element, params string[] names)
    {
        if (element.ValueKind != JsonValueKind.Object)
        {
            return 0;
        }

        foreach (var name in names)
        {
            if (!element.TryGetProperty(name, out var value))
            {
                continue;
            }

            if (value.ValueKind == JsonValueKind.Number)
            {
                if (value.TryGetInt64(out var integer))
                {
                    return Math.Max(0, integer);
                }

                if (value.TryGetDouble(out var number) && double.IsFinite(number))
                {
                    return Math.Max(0, (long)Math.Min(number, long.MaxValue));
                }
            }
            else if (value.ValueKind == JsonValueKind.String &&
                     long.TryParse(value.GetString(), NumberStyles.Integer, CultureInfo.InvariantCulture, out var parsed))
            {
                return Math.Max(0, parsed);
            }
        }

        return 0;
    }

    private static bool FirstBoolean(JsonElement element, params string[] names)
    {
        if (element.ValueKind != JsonValueKind.Object)
        {
            return false;
        }

        foreach (var name in names)
        {
            if (!element.TryGetProperty(name, out var value))
            {
                continue;
            }

            switch (value.ValueKind)
            {
                case JsonValueKind.True:
                    return true;
                case JsonValueKind.False:
                    return false;
                case JsonValueKind.Number:
                    return value.TryGetDouble(out var number) && number != 0;
                case JsonValueKind.String:
                {
                    var text = value.GetString()?.Trim();
                    if (bool.TryParse(text, out var boolean))
                    {
                        return boolean;
                    }

                    if (double.TryParse(text, NumberStyles.Number, CultureInfo.InvariantCulture, out var numeric))
                    {
                        return numeric != 0;
                    }

                    return text?.Equals("yes", StringComparison.OrdinalIgnoreCase) == true ||
                           text?.Equals("required", StringComparison.OrdinalIgnoreCase) == true ||
                           text?.Equals("paid", StringComparison.OrdinalIgnoreCase) == true;
                }
            }
        }

        return false;
    }

    private static DateTimeOffset? FirstDateTimeOffset(JsonElement element, params string[] names)
    {
        if (element.ValueKind != JsonValueKind.Object)
        {
            return null;
        }

        foreach (var name in names)
        {
            if (!element.TryGetProperty(name, out var value))
            {
                continue;
            }

            if (value.ValueKind == JsonValueKind.String &&
                DateTimeOffset.TryParse(
                    value.GetString(),
                    CultureInfo.InvariantCulture,
                    DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal,
                    out var timestamp))
            {
                return timestamp;
            }

            if (value.ValueKind == JsonValueKind.Number && value.TryGetInt64(out var unixTimestamp))
            {
                try
                {
                    return unixTimestamp > 10_000_000_000
                        ? DateTimeOffset.FromUnixTimeMilliseconds(unixTimestamp)
                        : DateTimeOffset.FromUnixTimeSeconds(unixTimestamp);
                }
                catch (ArgumentOutOfRangeException)
                {
                    // Ignore malformed provider timestamps and try the next alias.
                }
            }
        }

        return null;
    }

    private static bool IsPaidScript(JsonElement script)
    {
        if (FirstBoolean(script, "paid", "isPaid"))
        {
            return true;
        }

        var scriptType = FirstString(script, "scriptType") ?? FirstString(script, "type");
        if (scriptType?.Equals("paid", StringComparison.OrdinalIgnoreCase) == true)
        {
            return true;
        }

        return FirstInt64(script, "price", "cost") > 0;
    }

    private static string ResolveUrl(string origin, string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return string.Empty;
        }

        if (Uri.TryCreate(value, UriKind.Absolute, out var absolute))
        {
            return absolute.ToString();
        }

        return new Uri(new Uri(origin), value).ToString();
    }

    private static string RunnableBody(string? inlineScript, string? rawUrl)
    {
        if (!string.IsNullOrWhiteSpace(inlineScript))
        {
            return inlineScript.Trim();
        }

        if (string.IsNullOrWhiteSpace(rawUrl))
        {
            return string.Empty;
        }

        var escapedUrl = rawUrl.Trim().Replace("\"", "\\\"");
        return $"loadstring(game:HttpGet(\"{escapedUrl}\"))()";
    }

    public void Dispose()
    {
        _httpClient.Dispose();
        lock (_thumbnailCacheLock)
        {
            foreach (var image in _thumbnailCache.Values.OfType<IDisposable>())
            {
                image.Dispose();
            }

            _thumbnailCache.Clear();
        }
    }
}
