using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace OrbitAvalonia;

internal sealed class EditorWorkspaceService : IDisposable
{
    private const int MaximumRemoteScriptCharacters = 2_000_000;
    private readonly HttpClient _httpClient = new()
    {
        Timeout = TimeSpan.FromSeconds(20)
    };
    private readonly string _stateFilePath;

    public EditorWorkspaceService()
    {
        ScriptsDirectory = Path.Combine(AppContext.BaseDirectory, "Scripts");
        AutoExecuteDirectory = Path.Combine(AppContext.BaseDirectory, "AutoExecute");
        GithubGistsDirectory = Path.Combine(AppContext.BaseDirectory, "Github Gists");

        Directory.CreateDirectory(ScriptsDirectory);
        Directory.CreateDirectory(AutoExecuteDirectory);
        Directory.CreateDirectory(GithubGistsDirectory);

        var stateDirectory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Orbit");
        Directory.CreateDirectory(stateDirectory);
        _stateFilePath = Path.Combine(stateDirectory, "editor-workspace.json");

        _httpClient.DefaultRequestHeaders.UserAgent.ParseAdd("Orbit/1.0");
    }

    public string ScriptsDirectory { get; }

    public string AutoExecuteDirectory { get; }

    public string GithubGistsDirectory { get; }

    public EditorWorkspaceState LoadState()
    {
        try
        {
            if (File.Exists(_stateFilePath))
            {
                var state = JsonSerializer.Deserialize<EditorWorkspaceState>(
                    File.ReadAllText(_stateFilePath));
                if (state is { Tabs.Count: > 0 })
                {
                    foreach (var tab in state.Tabs)
                    {
                        tab.Title = CleanTabTitle(tab.Title);
                        tab.Content ??= string.Empty;
                        tab.Extension = NormalizeExtension(tab.Extension);
                    }

                    return state;
                }
            }
        }
        catch (IOException)
        {
            // A fresh workspace is safer than preventing the editor from opening.
        }
        catch (JsonException)
        {
            // Ignore an invalid state file and recreate it on the next save.
        }

        var firstTab = new EditorTabState
        {
            Title = "Script 1",
            Content = "-- Welcome to Orbit\nlocal message = \"Hello from Orbit\"\nprint(message)\n",
            Extension = ".lua"
        };

        return new EditorWorkspaceState
        {
            Tabs = [firstTab],
            ActiveTabId = firstTab.Id
        };
    }

    public void SaveState(IReadOnlyCollection<EditorTabState> tabs, Guid activeTabId)
    {
        try
        {
            var state = new EditorWorkspaceState
            {
                Tabs = tabs.ToList(),
                ActiveTabId = activeTabId
            };
            var json = JsonSerializer.Serialize(
                state,
                new JsonSerializerOptions { WriteIndented = true });
            var temporaryPath = _stateFilePath + ".tmp";
            File.WriteAllText(temporaryPath, json);
            File.Move(temporaryPath, _stateFilePath, true);
        }
        catch (IOException)
        {
            // Persistence should never interrupt editing.
        }
    }

    public IReadOnlyList<WorkspaceFileEntry> ListScriptFiles(string directory)
    {
        try
        {
            return Directory.EnumerateFiles(directory)
                .Where(path => !Path.GetFileName(path).StartsWith('.'))
                .OrderBy(path => Path.GetFileName(path), StringComparer.OrdinalIgnoreCase)
                .Select(path => new WorkspaceFileEntry(
                    Path.GetFileNameWithoutExtension(path),
                    path,
                    false))
                .ToList();
        }
        catch (IOException)
        {
            return [];
        }
    }

    public IReadOnlyList<WorkspaceFileEntry> ListGists()
    {
        try
        {
            return Directory.EnumerateFiles(GithubGistsDirectory, "*.txt")
                .OrderBy(path => Path.GetFileName(path), StringComparer.OrdinalIgnoreCase)
                .Select(path => new WorkspaceFileEntry(
                    Path.GetFileNameWithoutExtension(path),
                    path,
                    true))
                .ToList();
        }
        catch (IOException)
        {
            return [];
        }
    }

    public string StoreGistUrl(string rawUrl)
    {
        var normalizedUrl = NormalizeRawGithubUrl(rawUrl);
        foreach (var existingPath in Directory.EnumerateFiles(GithubGistsDirectory, "*.txt"))
        {
            try
            {
                if (string.Equals(
                        File.ReadAllText(existingPath).Trim(),
                        normalizedUrl,
                        StringComparison.OrdinalIgnoreCase))
                {
                    return Path.GetFileNameWithoutExtension(existingPath);
                }
            }
            catch (IOException)
            {
                // Continue looking for another matching entry.
            }
        }

        var title = TitleFromRawUrl(normalizedUrl);
        var path = UniqueFilePath(GithubGistsDirectory, title, ".txt");
        File.WriteAllText(path, normalizedUrl);
        return Path.GetFileNameWithoutExtension(path);
    }

    public async Task<string> FetchGistAsync(string rawUrl, CancellationToken cancellationToken)
    {
        var normalizedUrl = NormalizeRawGithubUrl(rawUrl);
        var separator = normalizedUrl.Contains('?') ? '&' : '?';
        var requestUrl = $"{normalizedUrl}{separator}_orbit={DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()}";
        using var response = await _httpClient.GetAsync(
            requestUrl,
            HttpCompletionOption.ResponseHeadersRead,
            cancellationToken);
        response.EnsureSuccessStatusCode();

        if (response.Content.Headers.ContentLength > MaximumRemoteScriptCharacters * 2L)
        {
            throw new InvalidOperationException("The remote script is too large.");
        }

        await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
        using var reader = new StreamReader(stream, Encoding.UTF8, true, 8192, leaveOpen: false);
        var builder = new StringBuilder();
        var buffer = new char[8192];

        while (true)
        {
            var read = await reader.ReadAsync(buffer.AsMemory(), cancellationToken);
            if (read == 0)
            {
                break;
            }

            builder.Append(buffer, 0, read);
            if (builder.Length > MaximumRemoteScriptCharacters)
            {
                throw new InvalidOperationException("The remote script is too large.");
            }
        }

        if (string.IsNullOrWhiteSpace(builder.ToString()))
        {
            throw new InvalidOperationException("The remote script was empty.");
        }

        return builder.ToString();
    }

    public static string NormalizeRawGithubUrl(string input)
    {
        if (!Uri.TryCreate(input.Trim(), UriKind.Absolute, out var uri) ||
            uri.Scheme != Uri.UriSchemeHttps)
        {
            throw new InvalidOperationException("Use an HTTPS raw GitHub link.");
        }

        if (uri.Host.Equals("raw.githubusercontent.com", StringComparison.OrdinalIgnoreCase) ||
            uri.Host.Equals("gist.githubusercontent.com", StringComparison.OrdinalIgnoreCase))
        {
            return uri.GetLeftPart(UriPartial.Path);
        }

        if (uri.Host.Equals("github.com", StringComparison.OrdinalIgnoreCase))
        {
            var segments = uri.AbsolutePath.Split('/', StringSplitOptions.RemoveEmptyEntries);
            if (segments.Length >= 5 && segments[2].Equals("blob", StringComparison.OrdinalIgnoreCase))
            {
                var owner = segments[0];
                var repository = segments[1];
                var branch = segments[3];
                var filePath = string.Join('/', segments.Skip(4));
                return $"https://raw.githubusercontent.com/{owner}/{repository}/{branch}/{filePath}";
            }

            if (uri.AbsolutePath.Contains("/raw/", StringComparison.OrdinalIgnoreCase))
            {
                return uri.GetLeftPart(UriPartial.Path);
            }
        }

        throw new InvalidOperationException("That is not a raw GitHub or GitHub Gist link.");
    }

    public static string TitleFromRawUrl(string rawUrl)
    {
        var uri = new Uri(rawUrl);
        var candidate = Uri.UnescapeDataString(uri.Segments.LastOrDefault()?.Trim('/') ?? "Gist");
        if (string.IsNullOrWhiteSpace(candidate) || candidate.Equals("raw", StringComparison.OrdinalIgnoreCase))
        {
            candidate = "GitHub Gist";
        }

        var title = Path.GetFileNameWithoutExtension(candidate)
            .Replace('-', ' ')
            .Replace('_', ' ')
            .Trim();
        return CleanTabTitle(title.Length == 0 ? "GitHub Gist" : title);
    }

    public static string UniqueFilePath(string directory, string title, string extension)
    {
        var invalid = Path.GetInvalidFileNameChars();
        var safeTitle = new string(title.Where(character => !invalid.Contains(character)).ToArray()).Trim();
        if (safeTitle.Length == 0)
        {
            safeTitle = "Script";
        }

        var candidate = Path.Combine(directory, safeTitle + extension);
        for (var suffix = 2; File.Exists(candidate); suffix++)
        {
            candidate = Path.Combine(directory, $"{safeTitle} {suffix}{extension}");
        }

        return candidate;
    }

    private static string NormalizeExtension(string? extension)
    {
        if (string.IsNullOrWhiteSpace(extension))
        {
            return ".lua";
        }

        return extension.StartsWith('.') ? extension : "." + extension;
    }

    private static string CleanTabTitle(string? title)
    {
        var clean = (title ?? string.Empty).Trim();
        return clean.Length == 0 ? "Untitled" : clean[..Math.Min(clean.Length, 80)];
    }

    public void Dispose() => _httpClient.Dispose();
}

internal sealed class EditorWorkspaceState
{
    public List<EditorTabState> Tabs { get; set; } = [];

    public Guid ActiveTabId { get; set; }

    public EditorWorkspaceState CloneDetached() => new()
    {
        Tabs = Tabs.Select(tab => tab.CloneDetached()).ToList(),
        ActiveTabId = ActiveTabId
    };
}

internal sealed class EditorTabState
{
    public Guid Id { get; set; } = Guid.NewGuid();

    public string Title { get; set; } = "Untitled";

    public string Content { get; set; } = string.Empty;

    public string Extension { get; set; } = ".lua";

    [JsonIgnore]
    public bool IsRenaming { get; set; }

    public EditorTabState CloneDetached() => new()
    {
        Id = Id,
        Title = Title,
        Content = Content,
        Extension = Extension
    };
}

internal sealed record WorkspaceFileEntry(string DisplayName, string FullPath, bool IsGist);
