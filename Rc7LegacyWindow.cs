using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Threading;
using System.Reflection;
using Drawing = System.Drawing;
using Forms = System.Windows.Forms;

namespace OrbitAvalonia;

/// <summary>
/// A visual-preservation build of the original 339 x 352 RC7 WinForms client.
/// It intentionally contains no login, IPC, injection, download, game-control,
/// update, or script-execution code from the historical project.
/// </summary>
internal sealed class Rc7LegacyWindow : Forms.Form
{
    private readonly Action<EditorWorkspaceState> _returnToOrbit;
    private readonly List<Drawing.Image> _ownedImages = [];
    private readonly Forms.TabControl _tabs;
    private readonly Forms.ToolTip _toolTips = new();
    private readonly Drawing.Image? _buttonIdle;
    private readonly Drawing.Image? _buttonHover;
    private readonly Forms.Button _executeButton;
    private bool _returningToOrbit;
    private int _tabCount = 2;

    public Rc7LegacyWindow(EditorWorkspaceState initialWorkspace, Action<EditorWorkspaceState> returnToOrbit)
    {
        _returnToOrbit = returnToOrbit;

        AutoScaleDimensions = new Drawing.SizeF(6F, 13F);
        AutoScaleMode = Forms.AutoScaleMode.Font;
        BackgroundImageLayout = Forms.ImageLayout.Stretch;
        ClientSize = new Drawing.Size(339, 352);
        FormBorderStyle = Forms.FormBorderStyle.FixedSingle;
        MaximizeBox = false;
        MinimizeBox = true;
        Name = "Rc7PreservationWindow";
        StartPosition = Forms.FormStartPosition.CenterScreen;
        Text = "RC7";
        TopMost = OrbitPreferences.TopMostEnabled;
        Shown += (_, _) =>
        {
            BringToFront();
            Activate();
        };

        var icon = LoadIcon("rc7_nKh_icon.ico");
        if (icon is not null)
        {
            Icon = icon;
        }

        BackgroundImage = Own(LoadImage("MainUi.bmp"));
        _buttonIdle = Own(LoadImage("Button_Idle.bmp"));
        _buttonHover = Own(LoadImage("Button_Hover.bmp"));

        var menu = BuildMenu();
        MainMenuStrip = menu;
        Controls.Add(menu);

        var editorPanel = new Forms.Panel
        {
            BackColor = Drawing.Color.FromArgb(240, 240, 240),
            Location = new Drawing.Point(8, 24),
            Name = "editorPanel",
            Size = new Drawing.Size(283, 301),
            TabIndex = 1
        };

        _tabs = new Forms.TabControl
        {
            Dock = Forms.DockStyle.Fill,
            ItemSize = new Drawing.Size(42, 18),
            Location = Drawing.Point.Empty,
            Name = "scriptTabs",
            Padding = Drawing.Point.Empty,
            SelectedIndex = 0,
            Size = new Drawing.Size(283, 301),
            TabIndex = 0
        };
        _tabs.SelectedIndexChanged += Tabs_SelectedIndexChanged;
        _tabs.MouseDown += Tabs_MouseDown;
        LoadWorkspace(initialWorkspace);
        editorPanel.Controls.Add(_tabs);
        Controls.Add(editorPanel);

        var openButton = CreateMainButton("Open", new Drawing.Point(8, 325));
        openButton.Click += OpenButton_Click;
        Controls.Add(openButton);

        var executeButton = CreateMainButton("Execute", new Drawing.Point(102, 325));
        _executeButton = executeButton;
        executeButton.Click += (_, _) =>
        {
            if (UnifiedBridgeServer.Shared.IsConnected)
                UnifiedBridgeServer.Shared.EnqueueExecute(ActiveEditor()?.Text ?? string.Empty);
        };
        Controls.Add(executeButton);

        var clearButton = CreateMainButton("Clear", new Drawing.Point(196, 325));
        clearButton.Click += (_, _) => ActiveEditor()?.Clear();
        Controls.Add(clearButton);

        var rightPanel = new Forms.Panel
        {
            BackgroundImage = Own(LoadImage("Hide_Side.bmp")),
            BackgroundImageLayout = Forms.ImageLayout.Stretch,
            Location = new Drawing.Point(300, 24),
            Name = "rightPanel",
            Size = new Drawing.Size(39, 328),
            TabIndex = 12
        };

        var saveButton = CreateSideButton("Save_In.bmp", new Drawing.Point(5, 113), "Save script");
        saveButton.Click += SaveButton_Click;
        rightPanel.Controls.Add(saveButton);

        var wrapButton = CreateSideButton("WordWrap_In.bmp", new Drawing.Point(5, 149), "Toggle word wrap");
        wrapButton.Click += (_, _) =>
        {
            if (ActiveEditor() is { } editor)
            {
                editor.WordWrap = !editor.WordWrap;
            }
        };
        rightPanel.Controls.Add(wrapButton);

        rightPanel.Controls.Add(CreateSideButton("Auto_In.bmp", new Drawing.Point(5, 185), "Preserved UI control"));
        rightPanel.Controls.Add(CreateSideButton("Google_Drive_In.bmp", new Drawing.Point(5, 221), "Preserved UI control"));
        rightPanel.Controls.Add(CreateSideButton("Krystal_In.bmp", new Drawing.Point(5, 257), "Preserved UI control"));
        rightPanel.Controls.Add(CreateSideButton("Wofly_In.bmp", new Drawing.Point(5, 293), "Preserved UI control"));
        Controls.Add(rightPanel);

        UnifiedBridgeServer.Shared.ConnectionChanged += BridgeConnectionChanged;
        ApplyBridgeConnectionState(UnifiedBridgeServer.Shared.IsConnected);
        FormClosed += Rc7LegacyWindow_FormClosed;
    }

    private Forms.MenuStrip BuildMenu()
    {
        var menu = new Forms.MenuStrip
        {
            Location = Drawing.Point.Empty,
            Name = "ToolBar",
            Size = new Drawing.Size(339, 24),
            TabIndex = 0,
            Text = "Settings"
        };

        var settings = new Forms.ToolStripMenuItem("Settings");
        var view = new Forms.ToolStripMenuItem("View");
        view.DropDownItems.Add(new Forms.ToolStripMenuItem("Output") { Enabled = false });
        view.DropDownItems.Add(new Forms.ToolStripMenuItem("Code Editor") { Checked = true });
        view.DropDownItems.Add(new Forms.ToolStripMenuItem("Tabs") { Checked = true });
        settings.DropDownItems.Add(view);
        settings.DropDownItems.Add(new Forms.ToolStripMenuItem("Customization") { Enabled = false });
        settings.DropDownItems.Add(new Forms.ToolStripSeparator());
        var uiSelection = new Forms.ToolStripMenuItem("UI Selection...");
        uiSelection.Click += (_, _) => ShowUiSelectionDialog();
        settings.DropDownItems.Add(uiSelection);

        var commands = new Forms.ToolStripMenuItem("Commands");
        commands.DropDownItems.Add(new Forms.ToolStripMenuItem("Unavailable in preservation build") { Enabled = false });

        var help = new Forms.ToolStripMenuItem("Help");
        help.DropDownItems.Add(new Forms.ToolStripMenuItem("Credits") { Enabled = false });

        var editTheme = new Forms.ToolStripMenuItem("Edit Theme");
        editTheme.DropDownItems.Add(new Forms.ToolStripMenuItem("Original") { Checked = true });

        menu.Items.AddRange([settings, commands, help, editTheme]);
        return menu;
    }

    private Forms.Button CreateMainButton(string text, Drawing.Point location)
    {
        var button = new Forms.Button
        {
            BackgroundImage = _buttonIdle,
            BackgroundImageLayout = Forms.ImageLayout.Stretch,
            Cursor = Forms.Cursors.Arrow,
            FlatStyle = Forms.FlatStyle.Flat,
            Font = new Drawing.Font("Lucida Sans", 15F, Drawing.FontStyle.Bold, Drawing.GraphicsUnit.Pixel),
            ForeColor = Drawing.Color.FromArgb(100, 100, 100),
            Location = location,
            Size = new Drawing.Size(95, 25),
            TabStop = false,
            Text = text,
            UseVisualStyleBackColor = false
        };
        button.FlatAppearance.BorderSize = 0;
        button.MouseEnter += (_, _) => button.BackgroundImage = _buttonHover ?? _buttonIdle;
        button.MouseLeave += (_, _) => button.BackgroundImage = _buttonIdle;
        return button;
    }

    private Forms.Button CreateSideButton(string imageName, Drawing.Point location, string tooltip)
    {
        var button = new Forms.Button
        {
            BackgroundImage = Own(LoadImage(imageName)),
            BackgroundImageLayout = Forms.ImageLayout.Stretch,
            Cursor = Forms.Cursors.Arrow,
            FlatStyle = Forms.FlatStyle.Flat,
            Location = location,
            Size = new Drawing.Size(30, 30),
            TabStop = false,
            UseVisualStyleBackColor = false
        };
        button.FlatAppearance.BorderSize = 0;
        _toolTips.SetToolTip(button, tooltip);
        return button;
    }

    private Forms.TabPage CreateEditorTab(string title, EditorTabState? workspaceTab = null)
    {
        workspaceTab ??= new EditorTabState
        {
            Title = Path.GetFileNameWithoutExtension(title),
            Extension = Path.GetExtension(title) is { Length: > 0 } extension ? extension : ".lua"
        };
        var tab = new Forms.TabPage
        {
            Name = title,
            Padding = new Forms.Padding(3),
            Tag = workspaceTab.CloneDetached(),
            Text = title,
            UseVisualStyleBackColor = true
        };
        var editor = new Forms.RichTextBox
        {
            AcceptsTab = true,
            BackColor = Drawing.Color.FromArgb(16, 18, 22),
            BorderStyle = Forms.BorderStyle.None,
            DetectUrls = false,
            Dock = Forms.DockStyle.Fill,
            Font = new Drawing.Font("Consolas", 10F, Drawing.FontStyle.Regular, Drawing.GraphicsUnit.Point),
            ForeColor = Drawing.Color.FromArgb(224, 225, 227),
            WordWrap = false
        };
        tab.Controls.Add(editor);
        editor.Text = workspaceTab.Content;
        return tab;
    }

    private void LoadWorkspace(EditorWorkspaceState workspace)
    {
        _tabs.TabPages.Clear();
        var detached = workspace.CloneDetached();
        if (detached.Tabs.Count == 0)
        {
            detached.Tabs.Add(new EditorTabState { Title = "Script 1", Extension = ".lua" });
            detached.ActiveTabId = detached.Tabs[0].Id;
        }

        foreach (var workspaceTab in detached.Tabs)
        {
            _tabs.TabPages.Add(CreateEditorTab(DisplayTitle(workspaceTab), workspaceTab));
        }
        _tabs.TabPages.Add("+");
        _tabCount = detached.Tabs.Count + 1;

        var activeIndex = detached.Tabs.FindIndex(tab => tab.Id == detached.ActiveTabId);
        _tabs.SelectedIndex = activeIndex >= 0 ? activeIndex : 0;
    }

    private EditorWorkspaceState CaptureWorkspace()
    {
        var tabs = new List<EditorTabState>();
        foreach (Forms.TabPage page in _tabs.TabPages)
        {
            if (page.Text == "+")
            {
                continue;
            }

            var metadata = page.Tag as EditorTabState;
            var extension = Path.GetExtension(page.Text);
            tabs.Add(new EditorTabState
            {
                Id = metadata?.Id ?? Guid.NewGuid(),
                Title = Path.GetFileNameWithoutExtension(page.Text),
                Extension = string.IsNullOrWhiteSpace(extension) ? metadata?.Extension ?? ".lua" : extension,
                Content = page.Controls.OfType<Forms.RichTextBox>().FirstOrDefault()?.Text ?? string.Empty
            });
        }

        if (tabs.Count == 0)
        {
            tabs.Add(new EditorTabState { Title = "Script 1", Extension = ".lua" });
        }

        var selectedId = (_tabs.SelectedTab?.Tag as EditorTabState)?.Id;
        return new EditorWorkspaceState
        {
            Tabs = tabs,
            ActiveTabId = selectedId is { } id && tabs.Any(tab => tab.Id == id) ? id : tabs[0].Id
        };
    }

    private static string DisplayTitle(EditorTabState tab)
    {
        var extension = string.IsNullOrWhiteSpace(tab.Extension) ? ".lua" : tab.Extension;
        return tab.Title.EndsWith(extension, StringComparison.OrdinalIgnoreCase)
            ? tab.Title
            : tab.Title + extension;
    }

    private void Tabs_SelectedIndexChanged(object? sender, EventArgs e)
    {
        if (_tabs.SelectedTab?.Text != "+")
        {
            return;
        }

        var insertAt = Math.Max(0, _tabs.TabPages.Count - 1);
        _tabs.TabPages.Insert(insertAt, CreateEditorTab($"({_tabCount++}).lua"));
        _tabs.SelectedIndex = insertAt;
    }

    private void Tabs_MouseDown(object? sender, Forms.MouseEventArgs e)
    {
        if (e.Button != Forms.MouseButtons.Right || _tabs.SelectedTab?.Text == "+")
        {
            return;
        }

        var menu = new Forms.ContextMenuStrip();
        var close = new Forms.ToolStripMenuItem("Close");
        close.Click += (_, _) =>
        {
            if (_tabs.SelectedTab is { Text: not "+" } selected && _tabs.TabPages.Count > 2)
            {
                _tabs.TabPages.Remove(selected);
                selected.Dispose();
            }
        };
        menu.Items.Add(close);
        menu.Show(_tabs, e.Location);
    }

    private Forms.RichTextBox? ActiveEditor() =>
        _tabs.SelectedTab?.Controls.OfType<Forms.RichTextBox>().FirstOrDefault();

    private void OpenButton_Click(object? sender, EventArgs e)
    {
        using var dialog = new Forms.OpenFileDialog
        {
            Filter = "Script and text files|*.lua;*.luau;*.txt;*.md|All files|*.*",
            Title = "Open Script"
        };
        if (dialog.ShowDialog(this) != Forms.DialogResult.OK)
        {
            return;
        }

        var title = Path.GetFileName(dialog.FileName);
        var tab = CreateEditorTab(title);
        tab.Controls.OfType<Forms.RichTextBox>().First().Text = File.ReadAllText(dialog.FileName);
        var insertAt = Math.Max(0, _tabs.TabPages.Count - 1);
        _tabs.TabPages.Insert(insertAt, tab);
        _tabs.SelectedIndex = insertAt;
    }

    private void SaveButton_Click(object? sender, EventArgs e)
    {
        var editor = ActiveEditor();
        if (editor is null)
        {
            return;
        }

        using var dialog = new Forms.SaveFileDialog
        {
            AddExtension = true,
            DefaultExt = "lua",
            FileName = _tabs.SelectedTab?.Text ?? "script.lua",
            Filter = "Lua script|*.lua|Text file|*.txt|All files|*.*",
            Title = "Save Script"
        };
        if (dialog.ShowDialog(this) == Forms.DialogResult.OK)
        {
            File.WriteAllText(dialog.FileName, editor.Text);
        }
    }

    private void ShowUiSelectionDialog()
    {
        // Reassert the RC7 owner before opening the modal form. Orbit is hidden
        // during this handoff, but explicitly activating the WinForms owner
        // avoids the dialog being placed behind the old Avalonia HWND.
        BringToFront();
        Activate();

        using var dialog = new Forms.Form
        {
            AutoScaleMode = Forms.AutoScaleMode.Font,
            BackColor = Drawing.Color.FromArgb(24, 24, 26),
            ClientSize = new Drawing.Size(270, 122),
            FormBorderStyle = Forms.FormBorderStyle.FixedToolWindow,
            MaximizeBox = false,
            MinimizeBox = false,
            ShowInTaskbar = false,
            TopMost = TopMost,
            StartPosition = Forms.FormStartPosition.CenterParent,
            Text = "RC7 Settings"
        };
        dialog.Shown += (_, _) =>
        {
            dialog.BringToFront();
            dialog.Activate();
        };
        dialog.Controls.Add(new Forms.Label
        {
            AutoSize = false,
            ForeColor = Drawing.Color.Gainsboro,
            Font = new Drawing.Font("Segoe UI", 9F),
            Location = new Drawing.Point(16, 14),
            Size = new Drawing.Size(238, 34),
            Text = "UI Selection\r\nReturn to the default Orbit interface."
        });
        var orbitButton = new Forms.Button
        {
            BackColor = Drawing.Color.FromArgb(36, 36, 39),
            FlatStyle = Forms.FlatStyle.Flat,
            ForeColor = Drawing.Color.WhiteSmoke,
            Location = new Drawing.Point(16, 67),
            Size = new Drawing.Size(238, 34),
            Text = "Use Orbit UI"
        };
        orbitButton.FlatAppearance.BorderColor = Drawing.Color.FromArgb(83, 83, 88);
        orbitButton.Click += (_, _) => dialog.DialogResult = Forms.DialogResult.OK;
        dialog.Controls.Add(orbitButton);

        if (dialog.ShowDialog(this) == Forms.DialogResult.OK)
        {
            _returningToOrbit = true;
            _returnToOrbit(CaptureWorkspace());
            // Let the Avalonia dispatcher process the fresh Orbit window first;
            // closing synchronously here can tear down the shell handoff race.
            BeginInvoke(new Action(Close));
        }
    }

    private void Rc7LegacyWindow_FormClosed(object? sender, Forms.FormClosedEventArgs e)
    {
        UnifiedBridgeServer.Shared.ConnectionChanged -= BridgeConnectionChanged;
        var finalWorkspace = CaptureWorkspace();
        using (var workspace = new EditorWorkspaceService())
        {
            workspace.SaveState(finalWorkspace.Tabs, finalWorkspace.ActiveTabId);
        }

        try
        {
            // FormClosed can be raised while WinForms is still unwinding a paint
            // message. Disposing the shared background bitmaps here makes
            // ControlPaint inspect an invalid Image and throws ArgumentException
            // when returning to Orbit. The RC7 STA thread exits immediately after
            // this form closes, so leave these tiny embedded images to the process
            // teardown/GC instead of invalidating them during the final paint.
            _toolTips.Dispose();
        }
        catch
        {
            // A native resource may already have been released during shutdown.
        }

        if (_returningToOrbit)
        {
            return;
        }

        Dispatcher.UIThread.Post(() =>
        {
            if (Avalonia.Application.Current?.ApplicationLifetime is
                IClassicDesktopStyleApplicationLifetime desktop)
            {
                desktop.Shutdown();
            }
        });
    }

    private void BridgeConnectionChanged(bool connected)
    {
        if (IsDisposed) return;
        if (InvokeRequired)
        {
            try { BeginInvoke(new Action(() => ApplyBridgeConnectionState(connected))); } catch (InvalidOperationException) { }
            return;
        }
        ApplyBridgeConnectionState(connected);
    }

    private void ApplyBridgeConnectionState(bool connected)
    {
        _executeButton.Enabled = connected;
        _toolTips.SetToolTip(_executeButton, connected ? "Execute" : "Execute (run Scripts\\Orion Bridge.lua first)");
    }

    private Drawing.Image? Own(Drawing.Image? image)
    {
        if (image is not null)
        {
            _ownedImages.Add(image);
        }
        return image;
    }

    private static Drawing.Image? LoadImage(string fileName)
    {
        var assembly = Assembly.GetExecutingAssembly();
        var resourceName = assembly.GetManifestResourceNames().FirstOrDefault(name =>
            name.EndsWith(fileName, StringComparison.OrdinalIgnoreCase));
        if (resourceName is null)
        {
            return null;
        }

        using var stream = assembly.GetManifestResourceStream(resourceName);
        using var source = stream is null ? null : Drawing.Image.FromStream(stream);
        return source is null ? null : new Drawing.Bitmap(source);
    }

    private static Drawing.Icon? LoadIcon(string fileName)
    {
        var assembly = Assembly.GetExecutingAssembly();
        var resourceName = assembly.GetManifestResourceNames().FirstOrDefault(name =>
            name.EndsWith(fileName, StringComparison.OrdinalIgnoreCase));
        if (resourceName is null)
        {
            return null;
        }

        using var stream = assembly.GetManifestResourceStream(resourceName);
        using var source = stream is null ? null : new Drawing.Icon(stream);
        return source is null ? null : (Drawing.Icon)source.Clone();
    }
}
