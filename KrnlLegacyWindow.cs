using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Threading;
using Bunifu.Framework.UI;
using System.Runtime.InteropServices;
using Drawing = System.Drawing;
using Forms = System.Windows.Forms;

namespace OrbitAvalonia;

/// <summary>
/// Source-measured 1-to-1 recreation of the original 679 x 345 Krnl WinForms shell.
/// Matches KrnlLeak source code layout, control bounds, colors, animations, and Z-ordering.
/// </summary>
internal sealed class KrnlLegacyWindow : Forms.Form
{
    private static readonly Drawing.Size SourceClientSize = new(679, 345);
    private const int WsClipChildren = 0x02000000;
    private const int WmNcHitTest = 0x0084;
    private const int HtClient = 1;
    private const int HtLeft = 10;
    private const int HtRight = 11;
    private const int HtTop = 12;
    private const int HtTopLeft = 13;
    private const int HtTopRight = 14;
    private const int HtBottom = 15;
    private const int HtBottomLeft = 16;
    private const int HtBottomRight = 17;
    private const int ResizeGrip = 5;
    private readonly Action<EditorWorkspaceState> _returnToOrbit;
    private readonly KrnlTabControl _tabs;
    private readonly BunifuFlatButton _executeButton;
    private readonly Forms.Panel _blueAccent;
    private readonly Forms.TreeView _scriptView;
    private bool _returningToOrbit;
    private bool _animBreak;
    private bool _opacityFadeEnabled;
    private bool _closing;
    private int _opacityAnimationVersion;

    protected override Forms.CreateParams CreateParams
    {
        get
        {
            var parameters = base.CreateParams;
            parameters.Style |= WsClipChildren;
            return parameters;
        }
    }

    [DllImport("dwmapi.dll", CharSet = CharSet.Unicode)]
    private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);

    protected override void OnHandleCreated(EventArgs e)
    {
        base.OnHandleCreated(e);

        // The leaked client was authored against .NET Framework's 6 x 13
        // autoscale baseline.  Modern WinForms uses a larger default font and
        // otherwise expands this 679 x 345 form to 792 x 398 at 96 DPI. Keep
        // the original client area literally while borderless edge hit-testing
        // supplies the optional resize behavior without adding any frame.
        ClientSize = SourceClientSize;

        try
        {
            int preference = 1; // DWMWCP_DONOTROUND - forces sharp square corners
            DwmSetWindowAttribute(Handle, 33, ref preference, sizeof(int));

            // Set border color to match title bar background (0x001D1D1D)
            int borderColor = 0x001D1D1D;
            DwmSetWindowAttribute(Handle, 34, ref borderColor, sizeof(int));

            int captionColor = 0x001D1D1D;
            DwmSetWindowAttribute(Handle, 35, ref captionColor, sizeof(int));
        }
        catch { }
    }

    protected override void OnShown(EventArgs e)
    {
        // WinForms can perform one final non-client recalculation after handle
        // creation. Reassert the leaked client rectangle before the first
        // visible frame, then use the resulting complete window as the minimum.
        ClientSize = SourceClientSize;
        MinimumSize = Size;
        base.OnShown(e);
    }

    protected override void WndProc(ref Forms.Message message)
    {
        base.WndProc(ref message);

        if (!OrbitPreferences.ResizableEnabled ||
            message.Msg != WmNcHitTest ||
            message.Result.ToInt32() != HtClient)
        {
            return;
        }

        var screenPoint = new Drawing.Point(
            unchecked((short)(long)message.LParam),
            unchecked((short)((long)message.LParam >> 16)));
        var clientPoint = PointToClient(screenPoint);
        var left = clientPoint.X < ResizeGrip;
        var right = clientPoint.X >= ClientSize.Width - ResizeGrip;
        var top = clientPoint.Y < ResizeGrip;
        var bottom = clientPoint.Y >= ClientSize.Height - ResizeGrip;

        message.Result = (left, right, top, bottom) switch
        {
            (true, _, true, _) => (IntPtr)HtTopLeft,
            (_, true, true, _) => (IntPtr)HtTopRight,
            (true, _, _, true) => (IntPtr)HtBottomLeft,
            (_, true, _, true) => (IntPtr)HtBottomRight,
            (true, _, _, _) => (IntPtr)HtLeft,
            (_, true, _, _) => (IntPtr)HtRight,
            (_, _, true, _) => (IntPtr)HtTop,
            (_, _, _, true) => (IntPtr)HtBottom,
            _ => (IntPtr)HtClient
        };
    }

    public KrnlLegacyWindow(
        EditorWorkspaceState initialWorkspace,
        Action<EditorWorkspaceState> returnToOrbit)
    {
        _returnToOrbit = returnToOrbit;
        SuspendLayout();
        AutoScaleMode = Forms.AutoScaleMode.None;
        BackColor = Drawing.Color.FromArgb(18, 18, 18);
        ClientSize = SourceClientSize;
        FormBorderStyle = Forms.FormBorderStyle.None;
        MaximizeBox = OrbitPreferences.ResizableEnabled;
        MinimizeBox = false;
        Name = "krnl";
        StartPosition = Forms.FormStartPosition.CenterScreen;
        Text = "krnl";
        TopMost = OrbitPreferences.TopMostEnabled;

        // -- panel1 (title bar: 679 x 33 @ 0,0) --------------------------------
        var panel1 = new Forms.Panel
        {
            Anchor = Forms.AnchorStyles.Top | Forms.AnchorStyles.Left | Forms.AnchorStyles.Right,
            BackColor = Drawing.Color.FromArgb(29, 29, 29),
            Location = new Drawing.Point(0, 0),
            Name = "panel1",
            Size = new Drawing.Size(679, 33)
        };
        panel1.MouseDown += BeginDrag;

        // -- panel3 (blue accent line: 682 x 3 @ -1,-1 inside panel1) -----------
        _blueAccent = new Forms.Panel
        {
            Anchor = Forms.AnchorStyles.Top | Forms.AnchorStyles.Left | Forms.AnchorStyles.Right,
            BackColor = Drawing.Color.DodgerBlue,
            Location = new Drawing.Point(-1, -1),
            Name = "panel3",
            Size = new Drawing.Size(682, 3)
        };
        panel1.Controls.Add(_blueAccent);

        // -- button2 (minimize: 35 x 33 @ 609,0 inside panel1) ------------------
        var button2 = CreateTitleButton(new Drawing.Point(609, 0), KrnlSourceAssets.LoadPng("button2.Image"));
        button2.Click += (_, _) => WindowState = Forms.FormWindowState.Minimized;
        panel1.Controls.Add(button2);

        // -- button1 (close: 35 x 33 @ 644,0 inside panel1) ---------------------
        var button1 = CreateTitleButton(new Drawing.Point(644, 0), KrnlSourceAssets.LoadPng("button1.Image"));
        button1.Click += async (_, _) =>
        {
            _closing = true;
            ++_opacityAnimationVersion;
            for (var opacity = Opacity; opacity > 0.0; opacity -= 0.1)
            {
                Opacity = opacity;
                await Task.Delay(10);
            }
            Close();
        };
        panel1.Controls.Add(button1);

        // Bring blue accent to front of panel1 so line runs continuously across top edge
        _blueAccent.BringToFront();

        // -- pictureBox1 (logo: 25 x 25 @ 4,4 inside panel1) --------------------
        var logo = new Forms.PictureBox
        {
            Image = KrnlSourceAssets.LoadPng("pictureBox1.Image"),
            Location = new Drawing.Point(4, 4),
            Name = "pictureBox1",
            Size = new Drawing.Size(25, 25),
            SizeMode = Forms.PictureBoxSizeMode.Zoom,
            TabStop = false
        };
        logo.MouseDown += BeginDrag;
        panel1.Controls.Add(logo);

        // -- label1 (KRNL title text: @ 322,7 inside panel1) -------------------
        var label1 = new Forms.Label
        {
            Anchor = Forms.AnchorStyles.None,
            AutoSize = true,
            Font = new Drawing.Font("Segoe UI", 11.25F),
            ForeColor = Drawing.Color.White,
            Location = new Drawing.Point(322, 7),
            Name = "label1",
            Size = new Drawing.Size(45, 20),
            Text = "KRNL"
        };
        label1.MouseDown += BeginDrag;
        panel1.Controls.Add(label1);

        // -- menuStrip1 (289 x 24 @ 0,33) ---------------------------------------
        var menu = new Forms.MenuStrip
        {
            // Keep the original item-packed menu width. Right-anchoring this
            // AutoSize ToolStrip under per-monitor DPI creates a blank seam.
            Anchor = Forms.AnchorStyles.Top | Forms.AnchorStyles.Left,
            AutoSize = true,
            BackColor = Drawing.Color.FromArgb(33, 33, 33),
            Dock = Forms.DockStyle.None,
            ImageScalingSize = new Drawing.Size(20, 20),
            Location = new Drawing.Point(0, 33),
            Name = "menuStrip1",
            Renderer = new Forms.ToolStripProfessionalRenderer(new KrnlMenuColors()),
            Size = new Drawing.Size(289, 24)
        };
        var file = TopMenu("File"); file.DropDownItems.AddRange([DropItem("Inject"), DropItem("Kill Roblox")]);
        var credits = TopMenu("Credits");
        var games = TopMenu("Games");
        var hot = TopMenu("Hot-Scripts");
        hot.DropDownItems.AddRange([DropItem("DarkDex"), DropItem("OpenGui"), DropItem("Owl Hub"), DropItem("Krnl Hub"), DropItem("Remote Spy"), DropItem("Game Sense"), DropItem("Unnamed ESP")]);
        var others = TopMenu("Others");
        others.DropDownItems.AddRange([DropItem("Get Key"), DropItem("Join Discord Server")]);
        menu.Items.AddRange([file, credits, games, hot, others]);
        MainMenuStrip = menu;

        // -- ScriptView (TreeView: 121 x 254 @ 554,59) --------------------------
        _scriptView = new KrnlScriptTreeView
        {
            Anchor = Forms.AnchorStyles.Top | Forms.AnchorStyles.Bottom | Forms.AnchorStyles.Right,
            BackColor = Drawing.Color.FromArgb(29, 29, 29),
            BorderStyle = Forms.BorderStyle.None,
            Font = new Drawing.Font("Segoe UI", 8.25F),
            ForeColor = Drawing.Color.White,
            HideSelection = false,
            LineColor = Drawing.Color.White,
            Location = new Drawing.Point(554, 59),
            Name = "ScriptView",
            Size = new Drawing.Size(121, 254)
        };
        _scriptView.ContextMenuStrip = CreateScriptMenu();
        _scriptView.NodeMouseDoubleClick += (_, e) => LoadScriptNode(e.Node);
        PopulateScripts();

        // -- customTabControl1 (545 x 254 @ 4,59) ------------------------------
        _tabs = new KrnlTabControl
        {
            Anchor = Forms.AnchorStyles.Top | Forms.AnchorStyles.Bottom | Forms.AnchorStyles.Left | Forms.AnchorStyles.Right,
            Location = new Drawing.Point(4, 59),
            Name = "customTabControl1",
            Size = new Drawing.Size(545, 254)
        };
        _tabs.InitializeTabs(initialWorkspace);

        // -- panel2 (menu fill: 391 x 25 @ 288,32) -- matches original 1-to-1 ---
        var panel2 = new Forms.Panel
        {
            Anchor = Forms.AnchorStyles.Top | Forms.AnchorStyles.Left | Forms.AnchorStyles.Right,
            BackColor = Drawing.Color.FromArgb(33, 33, 33),
            Location = new Drawing.Point(288, 32),
            Name = "panel2",
            Size = new Drawing.Size(391, 25)
        };

        // -- Bottom buttons (100 x 25 @ Y=316) ----------------------------------
        var execute = CreateBottomButton("EXECUTE", 4);
        _executeButton = execute;
        execute.Click += (_, _) =>
        {
            if (UnifiedBridgeServer.Shared.IsConnected)
                UnifiedBridgeServer.Shared.EnqueueExecute(_tabs.ActiveEditor?.Text ?? string.Empty);
        };
        var clear = CreateBottomButton("CLEAR", 107); clear.Click += (_, _) => _tabs.ActiveEditor?.ClearAll();
        var open = CreateBottomButton("OPEN FILE", 210); open.Click += (_, _) => OpenFile();
        var save = CreateBottomButton("SAVE FILE", 313); save.Click += (_, _) => SaveFile();
        var inject = CreateBottomButton("INJECT", 416);
        var options = CreateBottomButton("OPTIONS", 575, Forms.AnchorStyles.Bottom | Forms.AnchorStyles.Right); options.Click += (_, _) => ShowOptions();

        // -- Exact original Z-order addition -----------------------------------
        Controls.Add(menu);
        Controls.Add(_scriptView);
        Controls.Add(_tabs);
        Controls.Add(panel1);
        Controls.Add(panel2);
        Controls.Add(inject);
        Controls.Add(save);
        Controls.Add(open);
        Controls.Add(clear);
        Controls.Add(execute);
        Controls.Add(options);

        // Ensure menu is brought in front of panel2 fill
        menu.BringToFront();

        ResumeLayout(false);
        PerformLayout();

        // MenuStrip keeps its preferred width during WinForms DPI autoscaling,
        // while the adjacent source panel is scaled normally. Join the two
        // surfaces after layout so the original continuous menu bar has no seam.
        void AlignMenuFill()
        {
            var left = Math.Max(0, menu.Right - 1);
            var width = Math.Max(0, ClientSize.Width - left);
            if (panel2.Left != left || panel2.Width != width)
                panel2.SetBounds(left, panel2.Top, width, panel2.Height);
        }
        AlignMenuFill();
        SizeChanged += (_, _) => AlignMenuFill();

        // -- Opacity animations (matches original) ------------------------------
        Activated += (_, _) => AnimateOpacityTo(1.0);
        Deactivate += (_, _) =>
        {
            if (_opacityFadeEnabled && !_closing)
                AnimateOpacityTo(0.5);
        };

        // -- Blue accent pulse animation (anim_AwaitingTaskFinish) -------------
        _animBreak = true;
        AnimateBlueAccent();

        UnifiedBridgeServer.Shared.ConnectionChanged += BridgeConnectionChanged;
        ApplyBridgeConnectionState(UnifiedBridgeServer.Shared.IsConnected);
        FormClosed += OnFormClosed;
    }

    private async void AnimateBlueAccent()
    {
        while (_animBreak && !IsDisposed)
        {
            for (var i = 0; i < 70; i++)
            {
                if (!_animBreak || IsDisposed) { ResetBlueAccent(); return; }
                await Task.Delay(3);
                try { _blueAccent.BackColor = Drawing.Color.FromArgb(30, 144 - i, 255 - i); } catch { return; }
            }
            for (var i = 0; i < 69; i++)
            {
                if (!_animBreak || IsDisposed) { ResetBlueAccent(); return; }
                await Task.Delay(3);
                try { _blueAccent.BackColor = Drawing.Color.FromArgb(30, 74 + i, 185 + i); } catch { return; }
            }
        }
    }

    private void ResetBlueAccent()
    {
        try { if (!IsDisposed) _blueAccent.BackColor = Drawing.Color.FromArgb(30, 144, 255); } catch { }
    }

    private static Forms.Button CreateTitleButton(Drawing.Point location, Drawing.Image? image)
    {
        var button = new Forms.Button
        {
            Anchor = Forms.AnchorStyles.Right,
            BackColor = Drawing.Color.FromArgb(29, 29, 29),
            BackgroundImageLayout = Forms.ImageLayout.Center,
            FlatStyle = Forms.FlatStyle.Flat,
            Font = new Drawing.Font("Corbel", 12F),
            ForeColor = Drawing.Color.White,
            Image = image,
            Location = location,
            Size = new Drawing.Size(35, 33),
            UseVisualStyleBackColor = false
        };
        button.FlatAppearance.BorderSize = 0;
        button.FlatAppearance.BorderColor = Drawing.Color.FromArgb(29, 29, 29);
        button.FlatAppearance.MouseDownBackColor = Drawing.Color.FromArgb(40, 40, 40);
        button.FlatAppearance.MouseOverBackColor = Drawing.Color.FromArgb(35, 35, 35);
        return button;
    }

    private static Forms.ToolStripMenuItem TopMenu(string text) => new(text)
    {
        Font = new Drawing.Font("Segoe UI", 9F),
        ForeColor = Drawing.Color.White
    };

    private static Forms.ToolStripMenuItem DropItem(string text) => new(text)
    {
        BackColor = Drawing.Color.FromArgb(33, 33, 33),
        ForeColor = Drawing.Color.White
    };

    private static BunifuFlatButton CreateBottomButton(string text, int x, Forms.AnchorStyles anchor = Forms.AnchorStyles.Bottom | Forms.AnchorStyles.Left)
    {
        return new BunifuFlatButton
        {
            Activecolor = Drawing.Color.FromArgb(36, 36, 36),
            Anchor = anchor,
            BackColor = Drawing.Color.FromArgb(36, 36, 36),
            BackgroundImageLayout = Forms.ImageLayout.Stretch,
            BorderRadius = 0,
            ButtonText = text,
            Cursor = Forms.Cursors.Hand,
            // Bunifu's default disabled gray is considerably lighter than the
            // source button.  Keep the disconnected state dark, as KRNL did.
            DisabledColor = Drawing.Color.FromArgb(27, 27, 27),
            Font = new Drawing.Font("Segoe UI", 8.25F),
            Iconcolor = Drawing.Color.Transparent,
            Iconimage = null,
            Iconimage_right = null,
            IconMarginLeft = 0,
            IconMarginRight = 0,
            IconRightVisible = true,
            IconRightZoom = 0,
            IconVisible = true,
            IconZoom = 20,
            IsTab = false,
            Location = new Drawing.Point(x, 316),
            Margin = new Forms.Padding(0, 3, 3, 3),
            MinimumSize = new Drawing.Size(84, 25),
            Normalcolor = Drawing.Color.FromArgb(36, 36, 36),
            OnHovercolor = Drawing.Color.FromArgb(39, 39, 39),
            OnHoverTextColor = Drawing.Color.White,
            Padding = new Forms.Padding(0, 4, 0, 0),
            selected = false,
            Size = new Drawing.Size(100, 25),
            Text = text,
            TextAlign = Drawing.ContentAlignment.MiddleCenter,
            Textcolor = Drawing.Color.White,
            TextFont = new Drawing.Font("Microsoft Sans Serif", 9.75F)
        };
    }

    private void PopulateScripts()
    {
        _scriptView.BeginUpdate();
        _scriptView.Nodes.Clear();
        var scripts = Path.Combine(AppContext.BaseDirectory, "Scripts");
        try
        {
            Directory.CreateDirectory(scripts);
            AddDirectoryNodes(_scriptView.Nodes, scripts);
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
        finally
        {
            _scriptView.EndUpdate();
        }
    }

    private static void AddDirectoryNodes(Forms.TreeNodeCollection nodes, string directory)
    {
        try
        {
            foreach (var childDirectory in Directory.EnumerateDirectories(directory).OrderBy(Path.GetFileName, StringComparer.OrdinalIgnoreCase))
            {
                var directoryNode = nodes.Add(Path.GetFileName(childDirectory));
                directoryNode.Tag = childDirectory;
                AddDirectoryNodes(directoryNode.Nodes, childDirectory);
            }

            foreach (var file in Directory.EnumerateFiles(directory).OrderBy(Path.GetFileName, StringComparer.OrdinalIgnoreCase))
            {
                // The leaked source used FileInfo.Name, including the extension.
                var fileNode = nodes.Add(Path.GetFileName(file));
                fileNode.Tag = file;
            }
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }

    private Forms.ContextMenuStrip CreateScriptMenu()
    {
        var menu = new Forms.ContextMenuStrip
        {
            ImageScalingSize = new Drawing.Size(20, 20),
            RenderMode = Forms.ToolStripRenderMode.System,
            Size = new Drawing.Size(159, 114)
        };
        var execute = new Forms.ToolStripMenuItem("Execute");
        execute.Click += (_, _) =>
        {
            if (!UnifiedBridgeServer.Shared.IsConnected || !TryGetSelectedScript(out var path)) return;
            try { UnifiedBridgeServer.Shared.EnqueueExecute(File.ReadAllText(path)); }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
        };
        var load = new Forms.ToolStripMenuItem("Load Into Editor");
        load.Click += (_, _) => LoadScriptNode(_scriptView.SelectedNode);
        var delete = new Forms.ToolStripMenuItem("Delete File");
        var changePath = new Forms.ToolStripMenuItem("Change Path");
        var reload = new Forms.ToolStripMenuItem("Reload");
        reload.Click += (_, _) => PopulateScripts();
        menu.Items.AddRange([execute, load, delete, changePath, reload]);
        menu.Opening += (_, _) =>
        {
            var hasScript = TryGetSelectedScript(out _);
            execute.Enabled = hasScript;
            load.Enabled = hasScript;
            // Preserve the source menu visually; destructive/path-changing
            // handlers intentionally remain stripped from this frontend port.
            delete.Enabled = hasScript;
            changePath.Enabled = true;
        };
        return menu;
    }

    private bool TryGetSelectedScript(out string path)
    {
        path = _scriptView.SelectedNode?.Tag as string ?? string.Empty;
        return File.Exists(path);
    }

    private void LoadScriptNode(Forms.TreeNode? node)
    {
        if (node?.Tag is not string path || !File.Exists(path)) return;
        try { _tabs.AddScript(Path.GetFileName(path), File.ReadAllText(path)); }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }

    private void OpenFile()
    {
        using var dialog = new Forms.OpenFileDialog { CheckFileExists = true, RestoreDirectory = true, Filter = "Script Files (*.txt, *.lua)|*.txt;*.lua|All Files (*.*)|*.*" };
        if (dialog.ShowDialog(this) == Forms.DialogResult.OK) _tabs.AddScript(Path.GetFileName(dialog.FileName), File.ReadAllText(dialog.FileName));
    }

    private void SaveFile()
    {
        if (_tabs.ActiveEditor is not { } editor) return;
        using var dialog = new Forms.SaveFileDialog { AddExtension = true, DefaultExt = "lua", FileName = _tabs.SelectedTab?.Text ?? "Script.lua", Filter = "Script Files (*.txt, *.lua)|*.txt;*.lua|All Files (*.*)|*.*" };
        if (dialog.ShowDialog(this) == Forms.DialogResult.OK) File.WriteAllText(dialog.FileName, editor.Text);
    }

    private void ShowOptions()
    {
        using var options = new KrnlOptionsWindow(
            ReturnToOrbit,
            TopMost,
            _opacityFadeEnabled,
            enabled =>
            {
                TopMost = enabled;
                OrbitPreferences.SetTopMost(enabled);
            },
            enabled =>
            {
                _opacityFadeEnabled = enabled;
                if (!enabled) AnimateOpacityTo(1.0);
            });
        options.ShowDialog(this);
    }

    private void ReturnToOrbit()
    {
        _returningToOrbit = true;
        _returnToOrbit(_tabs.CaptureWorkspace());
        Close();
    }

    private void BeginDrag(object? sender, Forms.MouseEventArgs e)
    {
        if (e.Button != Forms.MouseButtons.Left) return;
        ReleaseCapture();
        SendMessage(Handle, 0xA1, 2, 0);
    }

    private void OnFormClosed(object? sender, Forms.FormClosedEventArgs e)
    {
        _animBreak = false;
        UnifiedBridgeServer.Shared.ConnectionChanged -= BridgeConnectionChanged;
        var finalWorkspace = _tabs.CaptureWorkspace();
        using (var workspace = new EditorWorkspaceService())
        {
            workspace.SaveState(finalWorkspace.Tabs, finalWorkspace.ActiveTabId);
        }

        if (_returningToOrbit) return;
        Dispatcher.UIThread.Post(() => (Avalonia.Application.Current?.ApplicationLifetime as IClassicDesktopStyleApplicationLifetime)?.Shutdown());
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
        _executeButton.Text = connected ? "EXECUTE" : "EXECUTE";
        _executeButton.Cursor = connected ? Forms.Cursors.Hand : Forms.Cursors.Default;
    }

    private async void AnimateOpacityTo(double target)
    {
        if (_closing || IsDisposed) return;
        var version = ++_opacityAnimationVersion;
        var step = target > Opacity ? 0.05 : -0.05;
        while (!IsDisposed && version == _opacityAnimationVersion &&
               (step > 0 ? Opacity < target : Opacity > target))
        {
            Opacity = Math.Clamp(Opacity + step, 0.05, 1.0);
            await Task.Delay(10);
        }

        if (!IsDisposed && version == _opacityAnimationVersion)
            Opacity = target;
    }

    [DllImport("user32.dll")] private static extern bool ReleaseCapture();
    [DllImport("user32.dll")] private static extern IntPtr SendMessage(IntPtr handle, int message, int wParam, int lParam);

    private sealed class KrnlMenuColors : Forms.ProfessionalColorTable
    {
        private static Drawing.Color Drop => Drawing.Color.FromArgb(40, 40, 40);
        public override Drawing.Color ToolStripDropDownBackground => Drop;
        public override Drawing.Color ImageMarginGradientBegin => Drop;
        public override Drawing.Color ImageMarginGradientMiddle => Drop;
        public override Drawing.Color ImageMarginGradientEnd => Drop;
        public override Drawing.Color MenuBorder => Drawing.Color.FromArgb(45, 45, 45);
        public override Drawing.Color MenuItemBorder => Drawing.Color.FromArgb(45, 45, 45);
        public override Drawing.Color MenuItemSelected => Drawing.Color.FromArgb(45, 45, 45);
        public override Drawing.Color MenuStripGradientBegin => Drop;
        public override Drawing.Color MenuStripGradientEnd => Drawing.Color.FromArgb(45, 45, 45);
        public override Drawing.Color MenuItemSelectedGradientBegin => Drop;
        public override Drawing.Color MenuItemSelectedGradientEnd => Drop;
        public override Drawing.Color MenuItemPressedGradientBegin => Drop;
        public override Drawing.Color MenuItemPressedGradientEnd => Drop;
    }

    private sealed class KrnlScriptTreeView : Forms.TreeView
    {
        private const int TvsNoHorizontalScroll = 0x8000;

        protected override Forms.CreateParams CreateParams
        {
            get
            {
                var parameters = base.CreateParams;
                parameters.Style |= TvsNoHorizontalScroll;
                return parameters;
            }
        }
    }
}
