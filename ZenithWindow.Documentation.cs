using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Primitives;
using Avalonia.Input;
using Avalonia.Input.Platform;
using Avalonia.Interactivity;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Media.Imaging;
using Avalonia.Platform;
using Avalonia.Threading;
using Avalonia.VisualTree;
using System.Diagnostics;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace OrbitAvalonia;

public sealed partial class ZenithWindow
{
    private const string ZenithFunctionDocumentationUri =
        "avares://Orion/Assets/Zenith/Data/function-documentation.json";
    private const string ZenithHelpArticlesUri =
        "avares://Orion/Assets/Zenith/Data/help-articles.json";

    private static readonly IBrush ZenithDocsPrimary = ZenithDocsBrush("#F0F0F0");
    private static readonly IBrush ZenithDocsSecondary = ZenithDocsBrush("#D8D8D8");
    private static readonly IBrush ZenithDocsMuted = ZenithDocsBrush("#8D8D8D");
    private static readonly IBrush ZenithDocsInfo = ZenithDocsBrush("#39A2FF");
    private static readonly IBrush ZenithDocsWarning = ZenithDocsBrush("#E4B958");
    private static readonly IBrush ZenithDocsCard = ZenithDocsBrush("#101217");
    private static readonly IBrush ZenithDocsExpanded = ZenithDocsBrush("#0C0E12");
    private static readonly IBrush ZenithDocsSelected = ZenithDocsBrush("#1E1E1E");
    private static readonly IBrush ZenithDocsHover = ZenithDocsBrush("#252525");
    private static readonly IBrush ZenithDocsBorder = ZenithDocsBrush("#272B36");
    private static readonly IBrush ZenithDocsTransparent = Brushes.Transparent;

    private static readonly string[] ZenithHelpCategoryOrder =
    [
        "Getting Started",
        "FAQs",
        "Troubleshooting",
        "Feature Tutorials"
    ];

    // The original client intentionally keeps All first and sorts the remaining
    // categories alphabetically. Keeping the source order explicit also prevents
    // a locale-dependent sort from subtly reshuffling the native sidebar.
    private static readonly string[] ZenithFunctionCategoryOrder =
    [
        "All",
        "Actors",
        "Bit",
        "Cache",
        "Closures",
        "Crypt",
        "CSV",
        "Debug",
        "DirectoryWatcher",
        "Drawing",
        "DrawingImmediate",
        "Duration",
        "Filesystem",
        "HTTP",
        "Input",
        "Instance",
        "Math",
        "Metatable",
        "Miscellaneous",
        "Regex",
        "Scripts",
        "SecureTable",
        "Stopwatch",
        "WebSocket"
    ];

    private static readonly Dictionary<string, string> ZenithHelpCategoryDescriptions =
        new(StringComparer.Ordinal)
        {
            ["Getting Started"] = "Learn the basics and get up and running quickly with Zenith.",
            ["Feature Tutorials"] = "Step-by-step guides for using Zenith's features effectively.",
            ["Troubleshooting"] = "Find solutions to common issues and problems you might encounter.",
            ["FAQs"] = "Frequently asked questions and answers about Zenith."
        };

    private static readonly Dictionary<string, string> ZenithHelpOverviewDescriptions =
        new(StringComparer.Ordinal)
        {
            ["Getting Started"] = "Learn the basics and get up and running quickly",
            ["Feature Tutorials"] = "Step-by-step guides for using Zenith's features",
            ["Troubleshooting"] = "Solutions to common issues and problems",
            ["FAQs"] = "Frequently asked questions and answers"
        };

    private static readonly Dictionary<string, string> ZenithSettingPaths =
        new(StringComparer.Ordinal)
        {
            ["enableAutoExec"] = "Settings → Execution Settings → Enable Auto Execute",
            ["createLocalScript"] = "Settings → Execution Settings → Create LocalScript",
            ["errorSpoofing"] = "Settings → Execution Settings → Error Spoofing/Redirection",
            ["unlockFPS"] = "Settings → Execution Settings → Unlock FPS",
            ["fpsCapValue"] = "Settings → Execution Settings → FPS Cap",
            ["internalInterface"] = "Settings → Execution Settings → Internal Interface",
            ["internalKeybind"] = "Settings → Execution Settings → Internal Key-bind",
            ["multiInstance"] = "Settings → Execution Settings → Enable Multi-instance",
            ["autoAttach"] = "Settings → Other Settings → Auto-Attach",
            ["autoAttachDelay"] = "Settings → Other Settings → Auto-Attach Delay",
            ["skipVersionCheck"] = "Settings → Other Settings → Skip Version Check",
            ["skipValidation"] = "Settings → Other Settings → Skip Validation",
            ["alwaysOnTop"] = "Settings → Interface Settings → Always on Top",
            ["navigationSlideOut"] = "Settings → Interface Settings → Navigation Slide-Out",
            ["statusGlow"] = "Settings → Interface Settings → Status Indicator Glow",
            ["formatOnPaste"] = "Settings → Interface Settings → Format Code on Paste",
            ["swapAttachExecute"] = "Settings → Interface Settings → Swap Attach & Execute Buttons",
            ["hideOpenButton"] = "Settings → Interface Settings → Hide Open Button",
            ["hideSaveButton"] = "Settings → Interface Settings → Hide Save Button",
            ["hideClearButton"] = "Settings → Interface Settings → Hide Clear Button",
            ["hideOutputConsole"] = "Settings → Interface Settings → Hide Output Console",
            ["showEditorHints"] = "Settings → Interface Settings → Show Editor Hints",
            ["theme"] = "Settings → Interface Settings → Theme"
        };

    private static readonly Regex ZenithInlineTokenPattern = new(
        @"(\*\*.+?\*\*|`.+?`|\*[^*].*?\*|\[article:[^\]]+\]|\[setting:[^\]]+\]|\[button-defender:[^\]]+\]|\[[^\]]+\]\([^)]+\)|https?://[^\s]+)",
        RegexOptions.Compiled | RegexOptions.CultureInvariant);

    private static readonly Regex ZenithOrderedListPattern = new(
        @"^(\s*)(\d+)\.\s+(.+)$",
        RegexOptions.Compiled | RegexOptions.CultureInvariant);

    private static readonly Regex ZenithImagePattern = new(
        @"^!\[([^\]]*)\]\(([^)]+)\)$",
        RegexOptions.Compiled | RegexOptions.CultureInvariant);

    private readonly List<ZenithFunctionDocumentation> _zenithFunctionDocumentation = [];
    private readonly List<ZenithHelpArticle> _zenithHelpArticles = [];
    private readonly Dictionary<string, Bitmap> _zenithHelpBitmaps = new(StringComparer.OrdinalIgnoreCase);

    private StackPanel? _zenithDocumentationCategoryPanel;
    private Control? _zenithDocumentationSearchShell;
    private TextBox? _zenithDocumentationSearchBox;
    private ScrollViewer? _zenithDocumentationContentScroll;
    private StackPanel? _zenithDocumentationContentPanel;
    private TextBox? _zenithHelpSearchBox;
    private StackPanel? _zenithHelpNavigationPanel;
    private ScrollViewer? _zenithHelpContentScroll;
    private StackPanel? _zenithHelpContentPanel;

    private string _zenithDocumentationCategory = "General";
    private string? _zenithExpandedFunction;
    private string? _zenithHelpCategory;
    private ZenithHelpArticle? _zenithHelpArticle;
    private bool _zenithDocumentationInitialised;
    private readonly List<ZenithHelpHistoryEntry> _zenithHelpHistory = [new(null, null)];
    private int _zenithHelpHistoryIndex;
    private bool _zenithApplyingHelpHistory;

    /// <summary>
    /// Connects the native Zenith documentation and Help surfaces to the data preserved
    /// from the original Zenith V2 interface. The containing window calls this once after
    /// Avalonia has created the named controls.
    /// </summary>
    internal void InitializeZenithDocumentation()
    {
        if (_zenithDocumentationInitialised)
        {
            return;
        }

        _zenithDocumentationCategoryPanel = Required<StackPanel>("DocumentationCategoryPanel");
        _zenithDocumentationSearchShell = Required<Control>("DocumentationSearchShell");
        _zenithDocumentationSearchBox = Required<TextBox>("DocumentationSearchBox");
        _zenithDocumentationContentScroll = Required<ScrollViewer>("DocumentationContentScroll");
        _zenithDocumentationContentPanel = Required<StackPanel>("DocumentationContentPanel");
        _zenithHelpSearchBox = Required<TextBox>("HelpSearchBox");
        _zenithHelpNavigationPanel = Required<StackPanel>("HelpNavigationPanel");
        _zenithHelpContentScroll = Required<ScrollViewer>("HelpContentScroll");
        _zenithHelpContentPanel = Required<StackPanel>("HelpContentPanel");

        _zenithFunctionDocumentation.AddRange(LoadZenithAsset<List<ZenithFunctionDocumentation>>(
            ZenithFunctionDocumentationUri) ?? []);
        _zenithHelpArticles.AddRange(LoadZenithAsset<List<ZenithHelpArticle>>(
            ZenithHelpArticlesUri) ?? []);

        _zenithDocumentationSearchBox.PlaceholderText = "Search functions...";
        _zenithHelpSearchBox.PlaceholderText = "Search articles...";
        _zenithDocumentationSearchBox.TextChanged += ZenithDocumentationSearchBox_TextChanged;
        _zenithHelpSearchBox.TextChanged += ZenithHelpSearchBox_TextChanged;
        KeyDown += ZenithDocumentation_KeyDown;
        PointerPressed += ZenithDocumentation_PointerPressed;
        Closed += ZenithDocumentationWindow_Closed;

        Debug.Assert(
            _zenithFunctionDocumentation.Count == 302,
            $"The preserved Zenith function reference should contain 302 entries, but {_zenithFunctionDocumentation.Count} were loaded.");
        Debug.Assert(
            _zenithHelpArticles.Count == 31,
            $"The preserved Zenith Help Center should contain 31 articles, but {_zenithHelpArticles.Count} were loaded.");

        _zenithDocumentationInitialised = true;
        RenderZenithDocumentationNavigation();
        RenderZenithDocumentation(resetScroll: true);
        RenderZenithHelpNavigation();
        RenderZenithHelpContent(resetScroll: true);
    }

    private static T? LoadZenithAsset<T>(string assetUri)
    {
        try
        {
            using var stream = AssetLoader.Open(new Uri(assetUri));
            return JsonSerializer.Deserialize<T>(stream, new JsonSerializerOptions
            {
                PropertyNameCaseInsensitive = true
            });
        }
        catch (Exception exception)
        {
            Debug.WriteLine($"Unable to load Zenith documentation asset '{assetUri}': {exception}");
            return default;
        }
    }

    private void ZenithDocumentationWindow_Closed(object? sender, EventArgs e)
    {
        Closed -= ZenithDocumentationWindow_Closed;
        if (_zenithDocumentationSearchBox is not null)
        {
            _zenithDocumentationSearchBox.TextChanged -= ZenithDocumentationSearchBox_TextChanged;
        }

        if (_zenithHelpSearchBox is not null)
        {
            _zenithHelpSearchBox.TextChanged -= ZenithHelpSearchBox_TextChanged;
        }

        KeyDown -= ZenithDocumentation_KeyDown;
        PointerPressed -= ZenithDocumentation_PointerPressed;

        foreach (var bitmap in _zenithHelpBitmaps.Values)
        {
            bitmap.Dispose();
        }

        _zenithHelpBitmaps.Clear();
    }

    private void ZenithDocumentationSearchBox_TextChanged(object? sender, TextChangedEventArgs e)
    {
        _zenithExpandedFunction = null;
        RenderZenithDocumentation(resetScroll: true);
    }

    private void ZenithHelpSearchBox_TextChanged(object? sender, TextChangedEventArgs e)
        => RenderZenithHelpNavigation();

    private void ZenithDocumentation_KeyDown(object? sender, KeyEventArgs e)
    {
        var control = (e.KeyModifiers & KeyModifiers.Control) != 0;
        var alt = (e.KeyModifiers & KeyModifiers.Alt) != 0;

        if (_currentPage == "Documentation" && control && e.Key == Key.K)
        {
            if (_zenithDocumentationCategory != "General")
            {
                _zenithDocumentationSearchBox?.Focus();
                _zenithDocumentationSearchBox?.SelectAll();
            }

            e.Handled = true;
            return;
        }

        if (_currentPage != "Help")
        {
            return;
        }

        if (control && e.Key == Key.K
            || e.Key is Key.Oem2 or Key.OemQuestion && e.KeyModifiers == KeyModifiers.None)
        {
            _zenithHelpSearchBox?.Focus();
            _zenithHelpSearchBox?.SelectAll();
            e.Handled = true;
            return;
        }

        if ((alt && e.Key == Key.Left) || e.Key == Key.BrowserBack)
        {
            NavigateZenithHelpHistory(-1);
            e.Handled = true;
            return;
        }

        if ((alt && e.Key == Key.Right) || e.Key == Key.BrowserForward)
        {
            NavigateZenithHelpHistory(1);
            e.Handled = true;
            return;
        }

        if (e.Key != Key.Escape)
        {
            return;
        }

        if (_zenithHelpSearchBox?.IsFocused == true)
        {
            _zenithHelpSearchBox.Text = string.Empty;
            Focus();
        }
        else if (_zenithHelpArticle is not null)
        {
            ShowZenithHelpCategory(_zenithHelpArticle.Category);
        }
        else if (_zenithHelpCategory is not null)
        {
            ShowZenithHelpOverview();
        }

        e.Handled = true;
    }

    private void ZenithDocumentation_PointerPressed(object? sender, PointerPressedEventArgs e)
    {
        if (_currentPage != "Help")
        {
            return;
        }

        var properties = e.GetCurrentPoint(this).Properties;
        if (properties.IsXButton1Pressed)
        {
            NavigateZenithHelpHistory(-1);
            e.Handled = true;
        }
        else if (properties.IsXButton2Pressed)
        {
            NavigateZenithHelpHistory(1);
            e.Handled = true;
        }
    }

    private void RenderZenithDocumentationNavigation()
    {
        var panel = _zenithDocumentationCategoryPanel!;
        panel.Children.Clear();
        panel.Spacing = 2;

        panel.Children.Add(CreateZenithSectionLabel("DOCUMENTATION"));
        panel.Children.Add(CreateZenithSidebarButton(
            "General",
            _zenithDocumentationCategory == "General",
            () => SelectZenithDocumentationCategory("General")));
        panel.Children.Add(CreateZenithDivider(new Thickness(0, 8)));
        panel.Children.Add(CreateZenithSectionLabel("CATEGORIES"));

        var availableCategories = _zenithFunctionDocumentation
            .Select(function => function.Category)
            .Where(category => !string.IsNullOrWhiteSpace(category))
            .ToHashSet(StringComparer.Ordinal);
        foreach (var category in ZenithFunctionCategoryOrder.Where(category =>
                     category == "All" || availableCategories.Contains(category)))
        {
            var captured = category;
            panel.Children.Add(CreateZenithSidebarButton(
                captured,
                _zenithDocumentationCategory == captured,
                () => SelectZenithDocumentationCategory(captured)));
        }
    }

    private void SelectZenithDocumentationCategory(string category)
    {
        _zenithDocumentationCategory = category;
        _zenithExpandedFunction = null;
        if (category == "General")
        {
            _zenithDocumentationSearchBox!.Text = string.Empty;
        }

        RenderZenithDocumentationNavigation();
        RenderZenithDocumentation(resetScroll: true);
    }

    private void RenderZenithDocumentation(bool resetScroll)
    {
        if (!_zenithDocumentationInitialised)
        {
            return;
        }

        var content = _zenithDocumentationContentPanel!;
        content.Children.Clear();
        content.Spacing = 12;
        _zenithDocumentationSearchShell!.IsVisible = _zenithDocumentationCategory != "General";

        if (_zenithFunctionDocumentation.Count == 0)
        {
            content.Children.Add(CreateZenithEmptyState(
                "Documentation unavailable",
                "The preserved Zenith function reference could not be loaded."));
            return;
        }

        if (_zenithDocumentationCategory == "General")
        {
            RenderZenithDocumentationWelcome(content);
        }
        else
        {
            var query = (_zenithDocumentationSearchBox!.Text ?? string.Empty).Trim();
            IEnumerable<ZenithFunctionDocumentation> functions = _zenithFunctionDocumentation;
            if (_zenithDocumentationCategory != "All")
            {
                functions = functions.Where(function =>
                    string.Equals(function.Category, _zenithDocumentationCategory, StringComparison.Ordinal));
            }

            if (query.Length > 0)
            {
                functions = functions.Where(function => ZenithFunctionMatches(function, query));
            }

            var results = functions
                .OrderBy(function => function.Name, StringComparer.OrdinalIgnoreCase)
                .ToList();

            if (results.Count == 0)
            {
                var empty = CreateZenithEmptyState(
                    "No functions found",
                    query.Length == 0
                        ? "There are no functions in this category."
                        : $"Couldn't find any functions matching \"{query}\".");
                if (query.Length > 0)
                {
                    empty.Children.Add(CreateZenithActionButton("Clear search", () =>
                    {
                        _zenithDocumentationSearchBox.Text = string.Empty;
                        _zenithDocumentationSearchBox.Focus();
                    }));
                }

                content.Children.Add(empty);
            }
            else
            {
                var categoryTotal = _zenithDocumentationCategory == "All"
                    ? _zenithFunctionDocumentation.Count
                    : _zenithFunctionDocumentation.Count(function =>
                        string.Equals(function.Category, _zenithDocumentationCategory, StringComparison.Ordinal));
                var heading = query.Length > 0
                    ? $"{results.Count} result{(results.Count == 1 ? string.Empty : "s")} out of {categoryTotal} "
                      + (_zenithDocumentationCategory == "All" ? "total" : $"in {_zenithDocumentationCategory}")
                    : _zenithDocumentationCategory;
                content.Children.Add(CreateZenithText(heading, 12, ZenithDocsMuted, FontWeight.Medium));
                foreach (var function in results)
                {
                    content.Children.Add(CreateZenithFunctionCard(function));
                }
            }
        }

        if (resetScroll)
        {
            ResetZenithScroll(_zenithDocumentationContentScroll!);
        }
    }

    private static bool ZenithFunctionMatches(ZenithFunctionDocumentation function, string query)
        => function.Name.Contains(query, StringComparison.OrdinalIgnoreCase)
           || function.Description.Contains(query, StringComparison.OrdinalIgnoreCase)
           || function.Aliases.Any(alias => alias.Contains(query, StringComparison.OrdinalIgnoreCase));

    private void RenderZenithDocumentationWelcome(StackPanel content)
    {
        var wrap = new StackPanel
        {
            MaxWidth = 768,
            HorizontalAlignment = HorizontalAlignment.Left,
            Spacing = 24,
            Margin = new Thickness(20)
        };

        wrap.Children.Add(CreateZenithText(
            "Welcome to Zenith's In-App Function Documentation",
            30,
            ZenithDocsSecondary,
            FontWeight.Bold));

        wrap.Children.Add(CreateZenithInformationSection(
            "Zenith has it all (and more)!",
            "We have the most expanded custom Lua environment on the market (typically 100% UNC + more), which comes with many novelty and QoL features for you to adopt. As a scripter, you can navigate our documentation here and get familiar with our environment.",
            "Browse the categories in the sidebar or use the search functionality to find specific functions. Each function entry includes syntax, parameters, return values, and example usage."));

        var faq = new StackPanel { Spacing = 16 };
        faq.Children.Add(CreateZenithText("FAQ", 16, ZenithDocsSecondary, FontWeight.SemiBold));
        faq.Children.Add(CreateZenithInformationSection(
            "I'm still confused with X!",
            "You're welcome to try either our official documentation or ask our community. You can find our Discord server by heading over to the Settings page and going to the bottom of the main page."));

        var suggestions = new StackPanel { Spacing = 8 };
        suggestions.Children.Add(CreateZenithText(
            "Can I suggest a function to you?",
            16,
            ZenithDocsSecondary,
            FontWeight.SemiBold));
        var suggestionLine = new WrapPanel { Orientation = Orientation.Horizontal };
        AddZenithInlineWords(
            suggestionLine,
            "Yes, we welcome suggestions openly. Learn more in our ",
            ZenithDocsMuted,
            FontWeight.Normal,
            FontStyle.Normal,
            size: 16);
        suggestionLine.Children.Add(CreateZenithInlineButton(
            "Help Center guide",
            () =>
            {
                SetPage("Help");
                ShowZenithHelpArticle("Can I contribute or suggest features?");
            }));
        AddZenithInlineWords(
            suggestionLine,
            ".",
            ZenithDocsMuted,
            FontWeight.Normal,
            FontStyle.Normal,
            size: 16);
        suggestions.Children.Add(suggestionLine);
        faq.Children.Add(suggestions);

        var help = CreateZenithInformationSection(
            "I'm confused on how to actually even use Zenith...?",
            "This documentation covers our environment. If you're confused on other aspects, visit our Help Center for comprehensive guides.");
        help.Children.Add(CreateZenithActionButton("Visit Help Center", () => SetPage("Help")));
        faq.Children.Add(help);
        wrap.Children.Add(faq);
        content.Children.Add(wrap);
    }

    private Border CreateZenithFunctionCard(ZenithFunctionDocumentation function)
    {
        var expanded = string.Equals(_zenithExpandedFunction, function.Name, StringComparison.Ordinal);
        var body = new StackPanel { Spacing = 0 };
        var headerButton = CreateZenithBareButton(() =>
        {
            var offset = _zenithDocumentationContentScroll!.Offset;
            _zenithExpandedFunction = expanded ? null : function.Name;
            RenderZenithDocumentation(resetScroll: false);
            Dispatcher.UIThread.Post(() => _zenithDocumentationContentScroll.Offset = offset);
        });
        headerButton.Padding = new Thickness(12);

        var headerGrid = new Grid();
        headerGrid.ColumnDefinitions.Add(new ColumnDefinition(GridLength.Star));
        headerGrid.ColumnDefinitions.Add(new ColumnDefinition(GridLength.Auto));

        var identity = new StackPanel { Spacing = 4 };
        var nameLine = new WrapPanel
        {
            Orientation = Orientation.Horizontal,
            VerticalAlignment = VerticalAlignment.Center
        };
        nameLine.Children.Add(CreateZenithText(function.Name, 14, ZenithDocsPrimary, FontWeight.Medium, monospaced: true));
        if (function.Aliases.Count > 0)
        {
            nameLine.Children.Add(CreateZenithText(
                $"  (or {string.Join(", ", function.Aliases)})",
                12,
                ZenithDocsMuted,
                FontWeight.Normal,
                monospaced: true));
        }

        identity.Children.Add(nameLine);
        identity.Children.Add(CreateZenithText(function.Description, 12, ZenithDocsMuted));

        var trailing = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 10,
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new Thickness(12, 0, 0, 0)
        };
        trailing.Children.Add(new Border
        {
            Background = ZenithDocsExpanded,
            BorderBrush = ZenithDocsBorder,
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(6),
            Padding = new Thickness(8, 4),
            Child = CreateZenithText(function.Category, 11, ZenithDocsMuted)
        });
        trailing.Children.Add(CreateZenithText(expanded ? "⌃" : "⌄", 16, ZenithDocsSecondary));
        Grid.SetColumn(trailing, 1);
        headerGrid.Children.Add(identity);
        headerGrid.Children.Add(trailing);
        headerButton.Content = headerGrid;
        body.Children.Add(headerButton);

        if (expanded)
        {
            body.Children.Add(CreateZenithFunctionDetails(function));
        }

        return new Border
        {
            Background = ZenithDocsCard,
            BorderBrush = ZenithDocsBorder,
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(12),
            ClipToBounds = true,
            Child = body
        };
    }

    private Border CreateZenithFunctionDetails(ZenithFunctionDocumentation function)
    {
        var panel = new StackPanel { Spacing = 12 };
        panel.Children.Add(CreateZenithCodeSection("Syntax", function.Syntax, copyable: true));

        if (function.Params.Count > 0)
        {
            var parameters = new StackPanel { Spacing = 8 };
            foreach (var parameter in function.Params)
            {
                var line = new WrapPanel { Orientation = Orientation.Horizontal };
                line.Children.Add(CreateZenithText(parameter.Name, 12, ZenithDocsWarning, FontWeight.Normal, monospaced: true));
                line.Children.Add(CreateZenithText($"  ({parameter.Type})", 12, ZenithDocsMuted));
                if (parameter.Optional)
                {
                    line.Children.Add(CreateZenithText("  (optional)", 11, ZenithDocsMuted));
                }

                var item = new StackPanel { Spacing = 4 };
                item.Children.Add(line);
                item.Children.Add(CreateZenithText(parameter.Description, 12, ZenithDocsMuted));
                parameters.Children.Add(item);
            }

            panel.Children.Add(CreateZenithInsetSection("Parameters", parameters));
        }

        if (function.Returns.Count > 0)
        {
            var returns = new StackPanel { Spacing = 8 };
            foreach (var result in function.Returns)
            {
                var item = new StackPanel { Spacing = 4 };
                item.Children.Add(CreateZenithText(result.Type, 12, ZenithDocsMuted, FontWeight.Normal, monospaced: true));
                item.Children.Add(CreateZenithText(result.Description, 12, ZenithDocsMuted));
                returns.Children.Add(item);
            }

            panel.Children.Add(CreateZenithInsetSection("Returns", returns));
        }

        if (function.Examples.Count > 0)
        {
            var examples = new StackPanel { Spacing = 10 };
            foreach (var example in function.Examples)
            {
                if (!string.IsNullOrWhiteSpace(example.Description))
                {
                    examples.Children.Add(CreateZenithText(example.Description, 12, ZenithDocsMuted));
                }

                examples.Children.Add(CreateZenithCodeBlock(example.Code, copyable: true));
            }

            panel.Children.Add(CreateZenithTitledSection("Examples", examples));
        }

        if (!string.IsNullOrWhiteSpace(function.Notes))
        {
            panel.Children.Add(CreateZenithInsetSection(
                "Notes",
                CreateZenithText(function.Notes, 12, ZenithDocsMuted)));
        }

        return new Border
        {
            Background = ZenithDocsExpanded,
            BorderBrush = ZenithDocsBorder,
            BorderThickness = new Thickness(0, 1, 0, 0),
            Padding = new Thickness(12),
            Child = panel
        };
    }

    private Control CreateZenithCodeSection(string title, string code, bool copyable)
    {
        var panel = new StackPanel { Spacing = 5 };
        panel.Children.Add(CreateZenithText(title, 11, ZenithDocsMuted));
        panel.Children.Add(CreateZenithCodeBlock(code, copyable));
        return panel;
    }

    private Control CreateZenithCodeBlock(string code, bool copyable, bool helpStyle = false)
    {
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition(GridLength.Star));
        grid.ColumnDefinitions.Add(new ColumnDefinition(GridLength.Auto));
        grid.Children.Add(new SelectableTextBlock
        {
            Text = code,
            FontSize = helpStyle ? 14 : 12,
            FontFamily = new FontFamily("Consolas"),
            Foreground = helpStyle ? ZenithDocsWarning : ZenithDocsSecondary,
            TextWrapping = TextWrapping.Wrap,
            VerticalAlignment = VerticalAlignment.Center
        });

        if (copyable)
        {
            var copy = CreateZenithBareButton(() => { });
            copy.Content = "Copy";
            copy.FontSize = 10;
            copy.Foreground = ZenithDocsMuted;
            copy.Padding = new Thickness(7, 4);
            copy.Margin = new Thickness(10, 0, 0, 0);
            copy.VerticalAlignment = VerticalAlignment.Top;
            copy.Click += async (_, _) => await CopyZenithDocumentationTextAsync(copy, code);
            Grid.SetColumn(copy, 1);
            grid.Children.Add(copy);
        }

        return new Border
        {
            Background = ZenithDocsCard,
            BorderBrush = ZenithDocsBorder,
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(8),
            Padding = new Thickness(helpStyle ? 16 : 9),
            Child = grid
        };
    }

    private async Task CopyZenithDocumentationTextAsync(Button button, string text)
    {
        var clipboard = TopLevel.GetTopLevel(this)?.Clipboard;
        if (clipboard is null)
        {
            return;
        }

        var original = button.Content;
        try
        {
            await clipboard.SetTextAsync(text);
            button.Content = "Copied";
            await Task.Delay(1200);
        }
        catch (Exception exception)
        {
            Debug.WriteLine($"Unable to copy Zenith documentation text: {exception}");
            button.Content = "Failed";
            await Task.Delay(1200);
        }
        finally
        {
            if (button.IsAttachedToVisualTree())
            {
                button.Content = original;
            }
        }
    }

    private void RenderZenithHelpNavigation()
    {
        if (!_zenithDocumentationInitialised)
        {
            return;
        }

        var panel = _zenithHelpNavigationPanel!;
        panel.Children.Clear();
        panel.Spacing = 2;
        panel.Children.Add(CreateZenithSectionLabel("HELP & GUIDES"));
        panel.Children.Add(CreateZenithSidebarButton(
            "Overview",
            _zenithHelpArticle is null && _zenithHelpCategory is null,
            ShowZenithHelpOverview));
        panel.Children.Add(CreateZenithDivider(new Thickness(0, 8)));

        var query = (_zenithHelpSearchBox!.Text ?? string.Empty).Trim();
        if (query.Length > 0)
        {
            var results = _zenithHelpArticles
                .Where(article => ZenithHelpMatches(article, query))
                .OrderBy(article => article.Title, StringComparer.OrdinalIgnoreCase)
                .ToList();

            panel.Children.Add(CreateZenithText(
                $"{results.Count} result{(results.Count == 1 ? string.Empty : "s")}",
                11,
                ZenithDocsMuted,
                FontWeight.Medium));

            if (results.Count == 0)
            {
                var empty = CreateZenithEmptyState(
                    "No articles found",
                    $"No articles found for \"{TruncateZenith(query, 30)}\".");
                empty.Children.Add(CreateZenithActionButton("Clear search", () =>
                {
                    _zenithHelpSearchBox.Text = string.Empty;
                    _zenithHelpSearchBox.Focus();
                }));
                panel.Children.Add(empty);
            }
            else
            {
                foreach (var article in results)
                {
                    var captured = article;
                    panel.Children.Add(CreateZenithSidebarArticleButton(
                        captured,
                        includeCategory: true,
                        () => ShowZenithHelpArticle(captured)));
                }
            }

            return;
        }

        foreach (var category in ZenithHelpCategoryOrder)
        {
            var articles = _zenithHelpArticles
                .Where(article => article.Category == category)
                .ToList();
            if (articles.Count == 0)
            {
                continue;
            }

            var categoryButton = CreateZenithBareButton(() => ShowZenithHelpCategory(category));
            categoryButton.Content = CreateZenithText(category.ToUpperInvariant(), 11, ZenithDocsMuted, FontWeight.Medium);
            categoryButton.Padding = new Thickness(4, 8, 4, 6);
            panel.Children.Add(categoryButton);

            foreach (var article in articles)
            {
                var captured = article;
                panel.Children.Add(CreateZenithSidebarArticleButton(
                    captured,
                    includeCategory: false,
                    () => ShowZenithHelpArticle(captured)));
            }

            panel.Children.Add(new Border { Height = 10 });
        }
    }

    private static bool ZenithHelpMatches(ZenithHelpArticle article, string query)
        => article.Title.Contains(query, StringComparison.OrdinalIgnoreCase)
           || ZenithHelpSearchText(article.Content).Contains(query, StringComparison.OrdinalIgnoreCase)
           || article.Tags.Any(tag => tag.Contains(query, StringComparison.OrdinalIgnoreCase));

    private void ShowZenithHelpOverview()
    {
        _zenithHelpArticle = null;
        _zenithHelpCategory = null;
        _zenithHelpSearchBox!.Text = string.Empty;
        PushZenithHelpHistory(null, null);
        RenderZenithHelpNavigation();
        RenderZenithHelpContent(resetScroll: true);
    }

    private void ShowZenithHelpCategory(string category)
    {
        _zenithHelpArticle = null;
        _zenithHelpCategory = category;
        _zenithHelpSearchBox!.Text = string.Empty;
        PushZenithHelpHistory(null, category);
        RenderZenithHelpNavigation();
        RenderZenithHelpContent(resetScroll: true);
    }

    private void ShowZenithHelpArticle(ZenithHelpArticle article)
    {
        _zenithHelpArticle = article;
        _zenithHelpCategory = null;
        _zenithHelpSearchBox!.Text = string.Empty;
        PushZenithHelpHistory(article.Title, null);
        RenderZenithHelpNavigation();
        RenderZenithHelpContent(resetScroll: true);
    }

    private void ShowZenithHelpArticle(string title)
    {
        var article = _zenithHelpArticles.FirstOrDefault(candidate =>
            string.Equals(candidate.Title, title, StringComparison.OrdinalIgnoreCase));
        if (article is not null)
        {
            ShowZenithHelpArticle(article);
        }
    }

    private void PushZenithHelpHistory(string? articleTitle, string? category)
    {
        if (_zenithApplyingHelpHistory)
        {
            return;
        }

        var current = _zenithHelpHistory[_zenithHelpHistoryIndex];
        if (string.Equals(current.ArticleTitle, articleTitle, StringComparison.Ordinal)
            && string.Equals(current.Category, category, StringComparison.Ordinal))
        {
            return;
        }

        if (_zenithHelpHistoryIndex < _zenithHelpHistory.Count - 1)
        {
            _zenithHelpHistory.RemoveRange(
                _zenithHelpHistoryIndex + 1,
                _zenithHelpHistory.Count - _zenithHelpHistoryIndex - 1);
        }

        _zenithHelpHistory.Add(new ZenithHelpHistoryEntry(articleTitle, category));
        _zenithHelpHistoryIndex = _zenithHelpHistory.Count - 1;
    }

    private void NavigateZenithHelpHistory(int direction)
    {
        var requestedIndex = Math.Clamp(
            _zenithHelpHistoryIndex + direction,
            0,
            _zenithHelpHistory.Count - 1);
        if (requestedIndex == _zenithHelpHistoryIndex)
        {
            return;
        }

        _zenithHelpHistoryIndex = requestedIndex;
        var destination = _zenithHelpHistory[requestedIndex];
        _zenithApplyingHelpHistory = true;
        try
        {
            _zenithHelpSearchBox!.Text = string.Empty;
            _zenithHelpArticle = destination.ArticleTitle is null
                ? null
                : _zenithHelpArticles.FirstOrDefault(article =>
                    string.Equals(article.Title, destination.ArticleTitle, StringComparison.Ordinal));
            _zenithHelpCategory = _zenithHelpArticle is null ? destination.Category : null;
            RenderZenithHelpNavigation();
            RenderZenithHelpContent(resetScroll: true);
        }
        finally
        {
            _zenithApplyingHelpHistory = false;
        }
    }

    private void RenderZenithHelpContent(bool resetScroll)
    {
        if (!_zenithDocumentationInitialised)
        {
            return;
        }

        var content = _zenithHelpContentPanel!;
        content.Children.Clear();
        content.Spacing = 0;

        if (_zenithHelpArticles.Count == 0)
        {
            content.Children.Add(CreateZenithEmptyState(
                "Help unavailable",
                "The preserved Zenith Help Center articles could not be loaded."));
        }
        else if (_zenithHelpArticle is not null)
        {
            RenderZenithHelpArticle(content, _zenithHelpArticle);
        }
        else if (_zenithHelpCategory is not null)
        {
            RenderZenithHelpCategory(content, _zenithHelpCategory);
        }
        else
        {
            RenderZenithHelpOverview(content);
        }

        if (resetScroll)
        {
            ResetZenithScroll(_zenithHelpContentScroll!);
        }
    }

    private void RenderZenithHelpOverview(StackPanel content)
    {
        var panel = new StackPanel
        {
            MaxWidth = 768,
            HorizontalAlignment = HorizontalAlignment.Left,
            Spacing = 20,
            Margin = new Thickness(32)
        };
        panel.Children.Add(CreateZenithText("Welcome to Zenith Help Center", 30, ZenithDocsSecondary, FontWeight.Bold));
        panel.Children.Add(CreateZenithText(
            "Find guides, help, tutorials, and answers to common questions about using Zenith. Browse articles by category or use the search to find specific topics.",
            16,
            ZenithDocsMuted));

        var categoryGrid = new Grid();
        categoryGrid.ColumnDefinitions.Add(new ColumnDefinition(GridLength.Star));
        categoryGrid.ColumnDefinitions.Add(new ColumnDefinition(GridLength.Star));
        for (var index = 0; index < ZenithHelpCategoryOrder.Length; index++)
        {
            var category = ZenithHelpCategoryOrder[index];
            var count = _zenithHelpArticles.Count(article => article.Category == category);
            var card = CreateZenithClickableCard(() => ShowZenithHelpCategory(category));
            card.Margin = new Thickness(4);
            card.Padding = new Thickness(20);
            var cardContent = new StackPanel { Spacing = 7 };
            cardContent.Children.Add(CreateZenithText(category, 18, ZenithDocsSecondary, FontWeight.SemiBold));
            cardContent.Children.Add(CreateZenithText(
                ZenithHelpOverviewDescriptions.GetValueOrDefault(category, string.Empty),
                14,
                ZenithDocsMuted));
            cardContent.Children.Add(CreateZenithText($"{count} articles", 12, ZenithDocsInfo));
            card.Content = cardContent;
            Grid.SetColumn(card, index % 2);
            Grid.SetRow(card, index / 2);
            if (categoryGrid.RowDefinitions.Count <= index / 2)
            {
                categoryGrid.RowDefinitions.Add(new RowDefinition(GridLength.Auto));
            }

            categoryGrid.Children.Add(card);
        }

        panel.Children.Add(categoryGrid);

        var support = new StackPanel { Spacing = 10 };
        support.Children.Add(CreateZenithText("Still Need Help?", 18, ZenithDocsSecondary, FontWeight.SemiBold));
        var supportLine = new WrapPanel { Orientation = Orientation.Horizontal };
        supportLine.Children.Add(CreateZenithText("Have a question that isn't covered here? ", 14, ZenithDocsMuted));
        var discord = CreateZenithInlineButton("Join our Discord community", () => SetPage("Settings"));
        supportLine.Children.Add(discord);
        supportLine.Children.Add(CreateZenithText(" to get help from our team and other users.", 14, ZenithDocsMuted));
        support.Children.Add(supportLine);
        panel.Children.Add(new Border
        {
            Background = ZenithDocsCard,
            BorderBrush = ZenithDocsBorder,
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(12),
            Padding = new Thickness(24),
            Child = support
        });
        content.Children.Add(panel);
    }

    private void RenderZenithHelpCategory(StackPanel content, string category)
    {
        var panel = new StackPanel
        {
            MaxWidth = 896,
            HorizontalAlignment = HorizontalAlignment.Left,
            Spacing = 18,
            Margin = new Thickness(32)
        };
        panel.Children.Add(CreateZenithBreadcrumb(
            ("Help Center", ShowZenithHelpOverview),
            (category, null)));
        panel.Children.Add(CreateZenithText(category, 30, ZenithDocsSecondary, FontWeight.Bold));
        panel.Children.Add(CreateZenithText(
            ZenithHelpCategoryDescriptions.GetValueOrDefault(category, string.Empty),
            16,
            ZenithDocsMuted));

        var cards = new StackPanel { Spacing = 14 };
        foreach (var article in _zenithHelpArticles.Where(article => article.Category == category))
        {
            var captured = article;
            var card = CreateZenithClickableCard(() => ShowZenithHelpArticle(captured));
            card.Padding = new Thickness(20);
            var cardContent = new StackPanel { Spacing = 9 };
            cardContent.Children.Add(CreateZenithText(article.Title, 18, ZenithDocsSecondary, FontWeight.SemiBold));
            cardContent.Children.Add(CreateZenithText(ZenithHelpExcerpt(article.Content, 180) + "...", 14, ZenithDocsMuted));
            if (article.Tags.Count > 0)
            {
                cardContent.Children.Add(CreateZenithTags(article.Tags.Take(3)));
            }

            card.Content = cardContent;
            cards.Children.Add(card);
        }

        panel.Children.Add(cards);
        content.Children.Add(panel);
    }

    private void RenderZenithHelpArticle(StackPanel content, ZenithHelpArticle article)
    {
        var panel = new StackPanel
        {
            MaxWidth = 896,
            HorizontalAlignment = HorizontalAlignment.Left,
            Spacing = 18,
            Margin = new Thickness(32)
        };
        panel.Children.Add(CreateZenithBreadcrumb(
            ("Help Center", ShowZenithHelpOverview),
            (article.Category, () => ShowZenithHelpCategory(article.Category)),
            (article.Title, null)));
        panel.Children.Add(CreateZenithText(article.Title, 30, ZenithDocsSecondary, FontWeight.Bold));

        var metadata = new WrapPanel { Orientation = Orientation.Horizontal };
        metadata.Children.Add(CreateZenithTag(article.Category, emphasised: true));
        foreach (var tag in article.Tags.Take(3))
        {
            metadata.Children.Add(CreateZenithTag(tag, emphasised: false));
        }

        panel.Children.Add(metadata);
        panel.Children.Add(RenderZenithHelpMarkdown(ExpandZenithHelpPaths(article.Content)));

        var related = _zenithHelpArticles
            .Where(candidate => candidate.Category == article.Category && candidate.Title != article.Title)
            .Take(3)
            .ToList();
        if (related.Count > 0)
        {
            panel.Children.Add(CreateZenithDivider(new Thickness(0, 12)));
            panel.Children.Add(CreateZenithText("Related Articles", 16, ZenithDocsSecondary, FontWeight.SemiBold));
            var relatedPanel = new StackPanel { Spacing = 10 };
            foreach (var candidate in related)
            {
                var captured = candidate;
                var relatedButton = CreateZenithClickableCard(() => ShowZenithHelpArticle(captured));
                relatedButton.Padding = new Thickness(16);
                var relatedContent = new StackPanel { Spacing = 4 };
                relatedContent.Children.Add(CreateZenithText(candidate.Title, 14, ZenithDocsSecondary, FontWeight.Medium));
                relatedContent.Children.Add(CreateZenithText(ZenithHelpExcerpt(candidate.Content, 120), 13, ZenithDocsMuted));
                relatedButton.Content = relatedContent;
                relatedPanel.Children.Add(relatedButton);
            }

            panel.Children.Add(relatedPanel);
        }

        content.Children.Add(panel);
    }

    private StackPanel RenderZenithHelpMarkdown(string markdown)
    {
        var output = new StackPanel { Spacing = 12 };
        var paragraph = new List<string>();
        var code = new List<string>();
        var inCode = false;

        void FlushParagraph()
        {
            if (paragraph.Count == 0)
            {
                return;
            }

            output.Children.Add(CreateZenithInlineContent(string.Join(" ", paragraph)));
            paragraph.Clear();
        }

        void FlushCode()
        {
            if (code.Count == 0)
            {
                return;
            }

            output.Children.Add(CreateZenithCodeBlock(
                string.Join(Environment.NewLine, code),
                copyable: true,
                helpStyle: true));
            code.Clear();
        }

        foreach (var sourceLine in markdown.Replace("\r\n", "\n", StringComparison.Ordinal).Split('\n'))
        {
            var line = sourceLine.TrimEnd();
            if (line.TrimStart().StartsWith("```", StringComparison.Ordinal))
            {
                FlushParagraph();
                if (inCode)
                {
                    FlushCode();
                }

                inCode = !inCode;
                continue;
            }

            if (inCode)
            {
                code.Add(sourceLine);
                continue;
            }

            if (string.IsNullOrWhiteSpace(line))
            {
                FlushParagraph();
                continue;
            }

            var trimmed = line.Trim();
            if (trimmed.StartsWith("### ", StringComparison.Ordinal))
            {
                FlushParagraph();
                output.Children.Add(CreateZenithText(trimmed[4..], 18, ZenithDocsSecondary, FontWeight.Medium));
                continue;
            }

            if (trimmed.StartsWith("## ", StringComparison.Ordinal))
            {
                FlushParagraph();
                output.Children.Add(CreateZenithText(trimmed[3..], 20, ZenithDocsSecondary, FontWeight.SemiBold));
                continue;
            }

            if (trimmed.StartsWith("# ", StringComparison.Ordinal))
            {
                FlushParagraph();
                output.Children.Add(CreateZenithText(trimmed[2..], 24, ZenithDocsSecondary, FontWeight.Bold));
                continue;
            }

            var imageMatch = ZenithImagePattern.Match(trimmed);
            if (imageMatch.Success)
            {
                FlushParagraph();
                output.Children.Add(CreateZenithHelpImage(imageMatch.Groups[2].Value, imageMatch.Groups[1].Value));
                continue;
            }

            if (trimmed.StartsWith("[youtube:", StringComparison.OrdinalIgnoreCase) && trimmed.EndsWith(']'))
            {
                FlushParagraph();
                output.Children.Add(CreateZenithYouTubeCard(trimmed[9..^1]));
                continue;
            }

            var orderedMatch = ZenithOrderedListPattern.Match(line);
            if (orderedMatch.Success)
            {
                FlushParagraph();
                output.Children.Add(CreateZenithListRow(
                    orderedMatch.Groups[2].Value + ".",
                    orderedMatch.Groups[3].Value,
                    orderedMatch.Groups[1].Value.Length >= 3));
                continue;
            }

            if (trimmed.StartsWith("- ", StringComparison.Ordinal) || trimmed.StartsWith("* ", StringComparison.Ordinal))
            {
                FlushParagraph();
                output.Children.Add(CreateZenithListRow("•", trimmed[2..], line.Length - line.TrimStart().Length >= 3));
                continue;
            }

            paragraph.Add(trimmed);
        }

        FlushParagraph();
        FlushCode();
        return output;
    }

    private Control CreateZenithHelpImage(string source, string alt)
    {
        var fileName = source.Replace('\\', '/').Split('/').LastOrDefault() ?? string.Empty;
        try
        {
            if (!_zenithHelpBitmaps.TryGetValue(fileName, out var bitmap))
            {
                using var stream = AssetLoader.Open(new Uri($"avares://Orion/Assets/Zenith/Help/{fileName}"));
                bitmap = new Bitmap(stream);
                _zenithHelpBitmaps[fileName] = bitmap;
            }

            return new Border
            {
                BorderBrush = ZenithDocsBorder,
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(8),
                ClipToBounds = true,
                Margin = new Thickness(0, 12),
                Child = new Image
                {
                    Source = bitmap,
                    Stretch = Stretch.Uniform,
                    MaxHeight = 520,
                    HorizontalAlignment = HorizontalAlignment.Left
                }
            };
        }
        catch (Exception exception)
        {
            Debug.WriteLine($"Unable to load Zenith help image '{source}': {exception}");
            return CreateZenithEmptyState("Image unavailable", alt);
        }
    }

    private Control CreateZenithYouTubeCard(string videoId)
    {
        var button = CreateZenithClickableCard(() => OpenZenithExternalUri($"https://www.youtube.com/watch?v={videoId}"));
        button.MinHeight = 400;
        button.Padding = new Thickness(24);
        button.HorizontalContentAlignment = HorizontalAlignment.Center;
        button.VerticalContentAlignment = VerticalAlignment.Center;
        var content = new StackPanel
        {
            Spacing = 10,
            HorizontalAlignment = HorizontalAlignment.Center
        };
        content.Children.Add(CreateZenithText("▶", 30, ZenithDocsInfo, FontWeight.Normal));
        content.Children.Add(CreateZenithText("Open video tutorial", 14, ZenithDocsSecondary, FontWeight.Medium));
        button.Content = content;
        return button;
    }

    private Control CreateZenithListRow(string marker, string text, bool nested)
    {
        var grid = new Grid { Margin = new Thickness(nested ? 24 : 8, 0, 0, 0) };
        grid.ColumnDefinitions.Add(new ColumnDefinition(GridLength.Auto));
        grid.ColumnDefinitions.Add(new ColumnDefinition(GridLength.Star));
        var markerText = CreateZenithText(marker, 16, ZenithDocsMuted);
        markerText.Width = 24;
        grid.Children.Add(markerText);
        var line = CreateZenithInlineContent(text);
        Grid.SetColumn(line, 1);
        grid.Children.Add(line);
        return grid;
    }

    private WrapPanel CreateZenithInlineContent(string text)
    {
        var panel = new WrapPanel
        {
            Orientation = Orientation.Horizontal,
            VerticalAlignment = VerticalAlignment.Top
        };

        var cursor = 0;
        foreach (Match match in ZenithInlineTokenPattern.Matches(text))
        {
            if (match.Index > cursor)
            {
                AddZenithInlineWords(panel, text[cursor..match.Index], ZenithDocsMuted, FontWeight.Normal, FontStyle.Normal);
            }

            AddZenithInlineToken(panel, match.Value);
            cursor = match.Index + match.Length;
        }

        if (cursor < text.Length)
        {
            AddZenithInlineWords(panel, text[cursor..], ZenithDocsMuted, FontWeight.Normal, FontStyle.Normal);
        }

        return panel;
    }

    private void AddZenithInlineToken(WrapPanel panel, string token)
    {
        if (token.StartsWith("**", StringComparison.Ordinal) && token.EndsWith("**", StringComparison.Ordinal))
        {
            AddZenithInlineWords(panel, token[2..^2], ZenithDocsSecondary, FontWeight.SemiBold, FontStyle.Normal);
            return;
        }

        if (token.StartsWith('`') && token.EndsWith('`'))
        {
            panel.Children.Add(new Border
            {
                Background = ZenithDocsCard,
                BorderBrush = ZenithDocsBorder,
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(4),
                Padding = new Thickness(5, 1),
                Margin = new Thickness(1, 0),
                Child = CreateZenithText(token[1..^1], 13, ZenithDocsWarning, FontWeight.Normal, monospaced: true)
            });
            return;
        }

        if (token.StartsWith('*') && token.EndsWith('*'))
        {
            AddZenithInlineWords(panel, token[1..^1], ZenithDocsMuted, FontWeight.Normal, FontStyle.Italic);
            return;
        }

        if (token.StartsWith("[article:", StringComparison.OrdinalIgnoreCase))
        {
            var title = token[9..^1];
            panel.Children.Add(CreateZenithInlineButton(title, () => ShowZenithHelpArticle(title)));
            return;
        }

        if (token.StartsWith("[setting:", StringComparison.OrdinalIgnoreCase))
        {
            var key = token[9..^1];
            var label = ZenithSettingPaths.GetValueOrDefault(key, key);
            panel.Children.Add(CreateZenithInlineButton(label, () => SetPage("Settings")));
            return;
        }

        if (token.StartsWith("[button-defender:", StringComparison.OrdinalIgnoreCase))
        {
            var label = token[17..^1];
            panel.Children.Add(CreateZenithActionButton(label, () => OpenZenithExternalUri("windowsdefender:")));
            return;
        }

        var link = Regex.Match(token, @"^\[([^\]]+)\]\(([^)]+)\)$");
        if (link.Success)
        {
            var destination = link.Groups[2].Value;
            panel.Children.Add(CreateZenithInlineButton(
                link.Groups[1].Value,
                () => OpenZenithExternalUri(destination.Contains("://", StringComparison.Ordinal)
                    ? destination
                    : "https://" + destination)));
            return;
        }

        if (token.StartsWith("http://", StringComparison.OrdinalIgnoreCase)
            || token.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
        {
            panel.Children.Add(CreateZenithInlineButton(token, () => OpenZenithExternalUri(token.TrimEnd('.', ',', ')'))));
            return;
        }

        AddZenithInlineWords(panel, token, ZenithDocsMuted, FontWeight.Normal, FontStyle.Normal);
    }

    private static void AddZenithInlineWords(
        WrapPanel panel,
        string text,
        IBrush foreground,
        FontWeight weight,
        FontStyle style,
        double size = 16)
    {
        foreach (var word in Regex.Split(text, @"(?<=\s)|(?=\s)"))
        {
            if (word.Length == 0)
            {
                continue;
            }

            panel.Children.Add(new TextBlock
            {
                Text = word,
                FontSize = size,
                FontWeight = weight,
                FontStyle = style,
                Foreground = foreground,
                TextWrapping = TextWrapping.NoWrap,
                VerticalAlignment = VerticalAlignment.Center
            });
        }
    }

    private static string ZenithHelpExcerpt(string content, int maximumLength)
    {
        var paragraphs = content.Replace("\r\n", "\n", StringComparison.Ordinal).Split("\n\n");
        var candidate = paragraphs
            .Select(paragraph => paragraph.Trim())
            .FirstOrDefault(paragraph => paragraph.Length > 0 && !paragraph.StartsWith('#'))
            ?? string.Empty;
        candidate = Regex.Replace(candidate, @"\[setting:[^\]]+\]", string.Empty);
        candidate = Regex.Replace(candidate, @"\[article:[^\]]+\]", string.Empty);
        candidate = Regex.Replace(candidate, @"!\[[^\]]*\]\([^)]+\)", string.Empty);
        candidate = candidate.Replace("**", string.Empty, StringComparison.Ordinal)
            .Replace("`", string.Empty, StringComparison.Ordinal)
            .Replace("*", string.Empty, StringComparison.Ordinal)
            .Trim();
        return TruncateZenith(candidate, maximumLength);
    }

    private static string ZenithHelpSearchText(string content)
    {
        var text = Regex.Replace(content, @"```.*?```", string.Empty, RegexOptions.Singleline);
        text = Regex.Replace(text, @"^#+\s+", string.Empty, RegexOptions.Multiline);
        text = Regex.Replace(text, @"\*\*(.+?)\*\*", "$1");
        text = Regex.Replace(text, @"\*(.+?)\*", "$1");
        text = Regex.Replace(text, @"`(.+?)`", "$1");
        text = Regex.Replace(text, @"!\[[^\]]*\]\([^)]+\)", string.Empty);
        text = Regex.Replace(text, @"\[([^\]]+)\]\([^)]+\)", "$1");
        text = Regex.Replace(text, @"\[article:([^\]]+)\]", "$1", RegexOptions.IgnoreCase);
        text = Regex.Replace(text, @"\[setting:[^\]]+\]", string.Empty, RegexOptions.IgnoreCase);
        text = Regex.Replace(text, @"\[button-defender:([^\]]+)\]", "$1", RegexOptions.IgnoreCase);
        text = Regex.Replace(text, @"\[youtube:[^\]]+\]", string.Empty, RegexOptions.IgnoreCase);
        text = Regex.Replace(text, @"^[\s]*[-*+]\s+", string.Empty, RegexOptions.Multiline);
        text = Regex.Replace(text, @"^[\s]*\d+\.\s+", string.Empty, RegexOptions.Multiline);
        return Regex.Replace(text, @"\s+", " ").Trim();
    }

    private static string ExpandZenithHelpPaths(string content)
    {
        var appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        var root = Path.Combine(appData, "Zenith");
        var installation = AppContext.BaseDirectory.TrimEnd(
            Path.DirectorySeparatorChar,
            Path.AltDirectorySeparatorChar);
        return content
            .Replace(@"%APPDATA%\Zenith\Scripts", Path.Combine(root, "Scripts"), StringComparison.Ordinal)
            .Replace(@"%APPDATA%\Zenith\AutoExec", Path.Combine(root, "AutoExec"), StringComparison.Ordinal)
            .Replace(@"%APPDATA%\Zenith\Workspace", Path.Combine(root, "Workspace"), StringComparison.Ordinal)
            .Replace(@"%APPDATA%\Zenith", root, StringComparison.Ordinal)
            .Replace("ZENITH_INSTALL", installation, StringComparison.Ordinal);
    }

    private static string TruncateZenith(string text, int maximumLength)
        => text.Length <= maximumLength ? text : text[..maximumLength].TrimEnd();

    private static void OpenZenithExternalUri(string uri)
    {
        try
        {
            Process.Start(new ProcessStartInfo(uri) { UseShellExecute = true });
        }
        catch (Exception exception)
        {
            Debug.WriteLine($"Unable to open Zenith help link '{uri}': {exception}");
        }
    }

    private Button CreateZenithSidebarArticleButton(
        ZenithHelpArticle article,
        bool includeCategory,
        Action action)
    {
        var selected = ReferenceEquals(_zenithHelpArticle, article)
                       || string.Equals(_zenithHelpArticle?.Title, article.Title, StringComparison.Ordinal);
        var button = CreateZenithBareButton(action);
        button.Background = selected ? ZenithDocsSelected : ZenithDocsTransparent;
        button.Padding = new Thickness(12, 8);
        button.HorizontalContentAlignment = HorizontalAlignment.Stretch;
        var content = new StackPanel { Spacing = 3 };
        content.Children.Add(CreateZenithText(
            article.Title,
            13,
            selected ? ZenithDocsPrimary : ZenithDocsMuted,
            FontWeight.Medium));
        if (includeCategory)
        {
            content.Children.Add(CreateZenithText(article.Category, 11, ZenithDocsMuted));
        }

        button.Content = content;
        AddZenithHover(button, selected ? ZenithDocsSelected : ZenithDocsTransparent, ZenithDocsHover);
        return button;
    }

    private Button CreateZenithSidebarButton(string label, bool selected, Action action)
    {
        var button = CreateZenithBareButton(action);
        button.Content = label;
        button.FontSize = 13;
        button.FontWeight = FontWeight.Medium;
        button.Foreground = selected ? ZenithDocsPrimary : ZenithDocsMuted;
        button.Background = selected ? ZenithDocsSelected : ZenithDocsTransparent;
        button.Padding = new Thickness(12, 8);
        button.HorizontalContentAlignment = HorizontalAlignment.Left;
        AddZenithHover(button, selected ? ZenithDocsSelected : ZenithDocsTransparent, ZenithDocsHover);
        return button;
    }

    private static Button CreateZenithBareButton(Action action)
    {
        var button = new Button
        {
            Background = ZenithDocsTransparent,
            BorderThickness = new Thickness(0),
            CornerRadius = new CornerRadius(8),
            Padding = new Thickness(0),
            HorizontalContentAlignment = HorizontalAlignment.Left,
            VerticalContentAlignment = VerticalAlignment.Center,
            HorizontalAlignment = HorizontalAlignment.Stretch,
            MinHeight = 0
        };
        button.Click += (_, _) => action();
        return button;
    }

    private static Button CreateZenithClickableCard(Action action)
    {
        var button = CreateZenithBareButton(action);
        button.Background = ZenithDocsCard;
        button.BorderBrush = ZenithDocsBorder;
        button.BorderThickness = new Thickness(1);
        button.CornerRadius = new CornerRadius(12);
        button.HorizontalContentAlignment = HorizontalAlignment.Stretch;
        AddZenithHover(button, ZenithDocsCard, ZenithDocsHover);
        return button;
    }

    private static Button CreateZenithActionButton(string label, Action action)
    {
        var button = CreateZenithBareButton(action);
        button.Content = label;
        button.FontSize = 13;
        button.FontWeight = FontWeight.Medium;
        button.Foreground = ZenithDocsInfo;
        button.Background = ZenithDocsBrush("#1839A2FF");
        button.BorderBrush = ZenithDocsBrush("#4D39A2FF");
        button.BorderThickness = new Thickness(1);
        button.Padding = new Thickness(14, 8);
        button.HorizontalAlignment = HorizontalAlignment.Left;
        button.HorizontalContentAlignment = HorizontalAlignment.Center;
        AddZenithHover(button, ZenithDocsBrush("#1839A2FF"), ZenithDocsBrush("#3039A2FF"));
        return button;
    }

    private static Button CreateZenithInlineButton(string label, Action action)
    {
        var button = CreateZenithBareButton(action);
        button.Content = label;
        button.FontSize = 16;
        button.FontWeight = FontWeight.Medium;
        button.Foreground = ZenithDocsInfo;
        button.Padding = new Thickness(0);
        button.Margin = new Thickness(0, 0, 2, 0);
        button.HorizontalAlignment = HorizontalAlignment.Left;
        return button;
    }

    private static void AddZenithHover(Button control, IBrush normal, IBrush hover)
    {
        control.PointerEntered += (_, _) => control.Background = hover;
        control.PointerExited += (_, _) => control.Background = normal;
    }

    private static StackPanel CreateZenithEmptyState(string title, string description)
    {
        var panel = new StackPanel
        {
            Spacing = 10,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new Thickness(20, 48)
        };
        panel.Children.Add(CreateZenithText(title, 18, ZenithDocsSecondary, FontWeight.Medium));
        var body = CreateZenithText(description, 13, ZenithDocsMuted);
        body.TextAlignment = TextAlignment.Center;
        panel.Children.Add(body);
        return panel;
    }

    private static StackPanel CreateZenithInformationSection(string title, params string[] paragraphs)
    {
        var panel = new StackPanel { Spacing = 8 };
        panel.Children.Add(CreateZenithText(title, 16, ZenithDocsSecondary, FontWeight.SemiBold));
        foreach (var paragraph in paragraphs)
        {
            panel.Children.Add(CreateZenithText(paragraph, 16, ZenithDocsMuted));
        }

        return panel;
    }

    private static Control CreateZenithInsetSection(string title, Control content)
    {
        var panel = new StackPanel { Spacing = 5 };
        panel.Children.Add(CreateZenithText(title, 11, ZenithDocsMuted));
        panel.Children.Add(new Border
        {
            Background = ZenithDocsCard,
            BorderBrush = ZenithDocsBorder,
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(8),
            Padding = new Thickness(9),
            Child = content
        });
        return panel;
    }

    private static Control CreateZenithTitledSection(string title, Control content)
    {
        var panel = new StackPanel { Spacing = 5 };
        panel.Children.Add(CreateZenithText(title, 11, ZenithDocsMuted));
        panel.Children.Add(content);
        return panel;
    }

    private static TextBlock CreateZenithSectionLabel(string text)
    {
        var label = CreateZenithText(text, 11, ZenithDocsMuted, FontWeight.Medium);
        label.Margin = new Thickness(4, 0, 0, 6);
        return label;
    }

    private static Border CreateZenithDivider(Thickness margin)
        => new()
        {
            Height = 1,
            Background = ZenithDocsBorder,
            Margin = margin
        };

    private static TextBlock CreateZenithText(
        string text,
        double size,
        IBrush foreground,
        FontWeight? weight = null,
        bool monospaced = false)
    {
        var block = new TextBlock
        {
            Text = text,
            FontSize = size,
            FontWeight = weight ?? FontWeight.Normal,
            Foreground = foreground,
            TextWrapping = TextWrapping.Wrap,
            LineHeight = size * 1.48
        };
        if (monospaced)
        {
            block.FontFamily = new FontFamily("Consolas");
        }

        return block;
    }

    private static WrapPanel CreateZenithTags(IEnumerable<string> tags)
    {
        var panel = new WrapPanel { Orientation = Orientation.Horizontal };
        foreach (var tag in tags)
        {
            panel.Children.Add(CreateZenithTag(tag, emphasised: false));
        }

        return panel;
    }

    private static Border CreateZenithTag(string text, bool emphasised)
        => new()
        {
            Background = emphasised ? ZenithDocsBrush("#1839A2FF") : ZenithDocsBrush("#08FFFFFF"),
            BorderBrush = ZenithDocsBorder,
            BorderThickness = emphasised ? new Thickness(0) : new Thickness(1),
            CornerRadius = new CornerRadius(4),
            Padding = new Thickness(8, 4),
            Margin = new Thickness(0, 0, 6, 4),
            Child = CreateZenithText(text, 11, emphasised ? ZenithDocsSecondary : ZenithDocsMuted)
        };

    private static WrapPanel CreateZenithBreadcrumb(params (string Label, Action? Action)[] entries)
    {
        var panel = new WrapPanel { Orientation = Orientation.Horizontal };
        for (var index = 0; index < entries.Length; index++)
        {
            if (index > 0)
            {
                panel.Children.Add(CreateZenithText("  /  ", 13, ZenithDocsMuted));
            }

            var entry = entries[index];
            panel.Children.Add(entry.Action is null
                ? CreateZenithText(entry.Label, 13, ZenithDocsSecondary)
                : CreateZenithInlineButton(entry.Label, entry.Action));
        }

        return panel;
    }

    private static void ResetZenithScroll(ScrollViewer scrollViewer)
        => Dispatcher.UIThread.Post(() => scrollViewer.Offset = new Vector(0, 0));

    private static SolidColorBrush ZenithDocsBrush(string color)
        => new(Color.Parse(color));

    private sealed class ZenithFunctionDocumentation
    {
        public string Name { get; set; } = string.Empty;
        public string Category { get; set; } = string.Empty;
        public string Description { get; set; } = string.Empty;
        public string Syntax { get; set; } = string.Empty;
        public List<ZenithFunctionParameter> Params { get; set; } = [];
        public List<ZenithFunctionReturn> Returns { get; set; } = [];
        public List<ZenithFunctionExample> Examples { get; set; } = [];
        public List<string> Aliases { get; set; } = [];
        public string Notes { get; set; } = string.Empty;
    }

    private sealed class ZenithFunctionParameter
    {
        public string Name { get; set; } = string.Empty;
        public string Type { get; set; } = string.Empty;
        public string Description { get; set; } = string.Empty;
        public bool Optional { get; set; }
    }

    private sealed class ZenithFunctionReturn
    {
        public string Type { get; set; } = string.Empty;
        public string Description { get; set; } = string.Empty;
    }

    private sealed class ZenithFunctionExample
    {
        public string Description { get; set; } = string.Empty;
        public string Code { get; set; } = string.Empty;
    }

    private sealed class ZenithHelpArticle
    {
        public string Title { get; set; } = string.Empty;
        public string Category { get; set; } = string.Empty;
        public string Content { get; set; } = string.Empty;
        public List<string> Tags { get; set; } = [];
    }

    private sealed record ZenithHelpHistoryEntry(string? ArticleTitle, string? Category);
}
