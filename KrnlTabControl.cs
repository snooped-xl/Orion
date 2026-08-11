using Drawing = System.Drawing;
using Drawing2D = System.Drawing.Drawing2D;
using DrawingText = System.Drawing.Text;
using Forms = System.Windows.Forms;

namespace OrbitAvalonia;

internal sealed class KrnlTabControl : Forms.TabControl
{
    private readonly Drawing.StringFormat _textFormat = new()
    {
        Alignment = Drawing.StringAlignment.Near,
        LineAlignment = Drawing.StringAlignment.Center
    };
    private int _scriptCount = 1;
    private Forms.TabPage? _draggedTab;

    public KrnlTabControl()
    {
        SetStyle(Forms.ControlStyles.UserPaint | Forms.ControlStyles.ResizeRedraw |
                 Forms.ControlStyles.AllPaintingInWmPaint | Forms.ControlStyles.OptimizedDoubleBuffer, true);
        DoubleBuffered = true;
        SizeMode = Forms.TabSizeMode.Normal;
        ItemSize = new Drawing.Size(240, 16);
        AllowDrop = true;
        Font = new Drawing.Font("Segoe UI", 8.25F);
    }

    public void InitializeTabs(EditorWorkspaceState workspace)
    {
        TabPages.Clear();
        var detached = workspace.CloneDetached();
        if (detached.Tabs.Count == 0)
        {
            detached.Tabs.Add(new EditorTabState { Title = "Script 1", Extension = ".lua" });
            detached.ActiveTabId = detached.Tabs[0].Id;
        }

        foreach (var tab in detached.Tabs)
        {
            TabPages.Add(CreateEditorPage(DisplayTitle(tab), tab.Content, tab));
        }
        TabPages.Add(new Forms.TabPage("+"));
        _scriptCount = detached.Tabs.Count;
        var activeIndex = detached.Tabs.FindIndex(tab => tab.Id == detached.ActiveTabId);
        SelectedIndex = activeIndex >= 0 ? activeIndex : 0;
    }

    public KrnlCodeEditor? ActiveEditor => SelectedTab?.Controls.OfType<KrnlCodeEditor>().FirstOrDefault();

    public void AddScript(string? title = null, string content = "")
    {
        var index = Math.Max(0, TabPages.Count - 1);
        title ??= $"Script {++_scriptCount}.lua";
        var extension = Path.GetExtension(title);
        var state = new EditorTabState
        {
            Title = Path.GetFileNameWithoutExtension(title),
            Extension = string.IsNullOrWhiteSpace(extension) ? ".lua" : extension,
            Content = content
        };
        var page = CreateEditorPage(title, content, state);
        TabPages.Insert(index, page);
        SelectedIndex = index;
        Invalidate();
    }

    protected override void OnMouseDown(Forms.MouseEventArgs e)
    {
        for (var i = 0; i < TabPages.Count; i++)
        {
            if (!GetTabRect(i).Contains(e.Location)) continue;
            if (i == TabPages.Count - 1 && e.Button == Forms.MouseButtons.Left)
            {
                AddScript();
                return;
            }
            if (e.Button == Forms.MouseButtons.Right && i < TabPages.Count - 1)
            {
                SelectedIndex = i;
                ShowTabMenu(TabPages[i], e.Location);
                return;
            }

            if (e.Button == Forms.MouseButtons.Left && i < TabPages.Count - 1)
                _draggedTab = TabPages[i];
            break;
        }
        base.OnMouseDown(e);
    }

    protected override void OnMouseMove(Forms.MouseEventArgs e)
    {
        if (e.Button == Forms.MouseButtons.Left && _draggedTab is not null)
        {
            var dragged = _draggedTab;
            _draggedTab = null;
            DoDragDrop(dragged, Forms.DragDropEffects.Move);
        }
        base.OnMouseMove(e);
    }

    protected override void OnMouseUp(Forms.MouseEventArgs e)
    {
        _draggedTab = null;
        base.OnMouseUp(e);
    }

    protected override void OnDragOver(Forms.DragEventArgs drgevent)
    {
        if (drgevent.Data?.GetData(typeof(Forms.TabPage)) is not Forms.TabPage source ||
            source.Text == "+")
        {
            base.OnDragOver(drgevent);
            return;
        }

        var point = PointToClient(new Drawing.Point(drgevent.X, drgevent.Y));
        Forms.TabPage? destination = null;
        for (var index = 0; index < TabPages.Count - 1; index++)
        {
            if (GetTabRect(index).Contains(point))
            {
                destination = TabPages[index];
                break;
            }
        }

        if (destination is not null && destination != source)
        {
            SwapPages(source, destination);
            SelectedTab = source;
            drgevent.Effect = Forms.DragDropEffects.Move;
        }
        base.OnDragOver(drgevent);
    }

    protected override void OnSelecting(Forms.TabControlCancelEventArgs e)
    {
        if (e.TabPageIndex == TabCount - 1)
            e.Cancel = true;
        base.OnSelecting(e);
    }

    protected override void OnPaint(Forms.PaintEventArgs e)
    {
        var g = e.Graphics;
        g.SmoothingMode = Drawing2D.SmoothingMode.HighQuality;
        g.PixelOffsetMode = Drawing2D.PixelOffsetMode.HighQuality;
        g.TextRenderingHint = DrawingText.TextRenderingHint.ClearTypeGridFit;
        g.Clear(Drawing.Color.FromArgb(45, 45, 48));
        for (var i = 0; i < TabCount; i++)
        {
            var source = GetTabRect(i);
            var rect = new Drawing.Rectangle(source.X + 2, source.Y, source.Width, source.Height);
            if (i == SelectedIndex)
            {
                using var active = new Drawing.SolidBrush(Drawing.Color.FromArgb(36, 36, 36));
                g.FillRectangle(active, new Drawing.Rectangle(rect.X - 5, rect.Y - 3, rect.Width, rect.Height + 5));
            }
            if (i == TabCount - 1)
            {
                using var plusFont = new Drawing.Font(System.Drawing.SystemFonts.DefaultFont.FontFamily, 14F, Drawing.FontStyle.Bold);
                using var plusBrush = new Drawing.SolidBrush(Drawing.Color.WhiteSmoke);
                g.DrawString("+", plusFont, plusBrush, rect.Right - 22, rect.Top / 2F - 4);
            }
            else
            {
                using var brush = new Drawing.SolidBrush(Drawing.Color.White);
                g.DrawString(TabPages[i].Text, Font, brush, rect, _textFormat);
            }
        }
        using var line = new Drawing.Pen(Drawing.Color.FromArgb(36, 36, 36), 5F);
        g.DrawLine(line, new Drawing.Point(0, 19), new Drawing.Point(Width, 19));
        using var body = new Drawing.SolidBrush(Drawing.Color.FromArgb(36, 36, 36));
        g.FillRectangle(body, new Drawing.Rectangle(0, 20, Width, Height - 20));
        using var border = new Drawing.Pen(Drawing.Color.FromArgb(30, 30, 30), 2F);
        g.DrawRectangle(border, new Drawing.Rectangle(0, 0, Width, Height));
    }

    public EditorWorkspaceState CaptureWorkspace()
    {
        var tabs = new List<EditorTabState>();
        foreach (Forms.TabPage page in TabPages)
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
                Content = page.Controls.OfType<KrnlCodeEditor>().FirstOrDefault()?.Text ?? string.Empty
            });
        }

        if (tabs.Count == 0)
        {
            tabs.Add(new EditorTabState { Title = "Script 1", Extension = ".lua" });
        }

        var selectedId = (SelectedTab?.Tag as EditorTabState)?.Id;
        return new EditorWorkspaceState
        {
            Tabs = tabs,
            ActiveTabId = selectedId is { } id && tabs.Any(tab => tab.Id == id) ? id : tabs[0].Id
        };
    }

    private Forms.TabPage CreateEditorPage(string title, string content, EditorTabState workspaceTab)
    {
        var page = new Forms.TabPage(title)
        {
            BackColor = Drawing.Color.FromArgb(36, 36, 36),
            BorderStyle = Forms.BorderStyle.None,
            Padding = new Forms.Padding(0),
            Tag = workspaceTab.CloneDetached()
        };
        page.Controls.Add(CreateEditor(content));
        return page;
    }

    private static KrnlCodeEditor CreateEditor(string script)
    {
        return new KrnlCodeEditor { Text = script };
    }

    private static string DisplayTitle(EditorTabState tab)
    {
        var extension = string.IsNullOrWhiteSpace(tab.Extension) ? ".lua" : tab.Extension;
        return tab.Title.EndsWith(extension, StringComparison.OrdinalIgnoreCase)
            ? tab.Title
            : tab.Title + extension;
    }

    private void ShowTabMenu(Forms.TabPage page, Drawing.Point location)
    {
        var menu = new Forms.ContextMenuStrip { RenderMode = Forms.ToolStripRenderMode.System };
        var clear = new Forms.ToolStripMenuItem("Clear"); clear.Click += (_, _) => page.Controls.OfType<KrnlCodeEditor>().FirstOrDefault()?.ClearAll();
        var open = new Forms.ToolStripMenuItem("Open Into"); open.Click += (_, _) => OpenInto(page);
        var save = new Forms.ToolStripMenuItem("Save"); save.Click += (_, _) => Save(page);
        var close = new Forms.ToolStripMenuItem("Close Tab");
        close.Click += (_, _) => ClosePage(page);
        menu.Items.AddRange([clear, open, save, new Forms.ToolStripSeparator(), close]);
        menu.Show(this, location);
    }

    private void ClosePage(Forms.TabPage page)
    {
        var scriptPages = TabPages.Cast<Forms.TabPage>().Where(tab => tab.Text != "+").ToArray();
        if (!scriptPages.Contains(page)) return;
        if (scriptPages.Length == 1)
        {
            page.Text = "Script 1.lua";
            page.Tag = new EditorTabState { Title = "Script 1", Extension = ".lua" };
            page.Controls.OfType<KrnlCodeEditor>().FirstOrDefault()?.ClearAll();
            Invalidate();
            return;
        }

        var index = TabPages.IndexOf(page);
        TabPages.Remove(page);
        page.Dispose();
        SelectedIndex = Math.Clamp(index - 1, 0, TabPages.Count - 2);
        Invalidate();
    }

    private void SwapPages(Forms.TabPage source, Forms.TabPage destination)
    {
        var pages = TabPages.Cast<Forms.TabPage>().ToList();
        var sourceIndex = pages.IndexOf(source);
        var destinationIndex = pages.IndexOf(destination);
        if (sourceIndex < 0 || destinationIndex < 0) return;
        (pages[sourceIndex], pages[destinationIndex]) = (pages[destinationIndex], pages[sourceIndex]);
        TabPages.Clear();
        TabPages.AddRange(pages.ToArray());
        Invalidate();
    }

    private void OpenInto(Forms.TabPage page)
    {
        using var dialog = new Forms.OpenFileDialog { CheckFileExists = true, RestoreDirectory = true, Filter = "Script Files (*.txt, *.lua)|*.txt;*.lua|All Files (*.*)|*.*" };
        if (dialog.ShowDialog(FindForm()) != Forms.DialogResult.OK) return;
        page.Text = Path.GetFileName(dialog.FileName);
        page.Controls.OfType<KrnlCodeEditor>().First().Text = File.ReadAllText(dialog.FileName);
    }

    private void Save(Forms.TabPage page)
    {
        using var dialog = new Forms.SaveFileDialog { AddExtension = true, DefaultExt = "lua", FileName = page.Text, Filter = "Lua Script (*.lua)|*.lua|Text File (*.txt)|*.txt|All Files (*.*)|*.*" };
        if (dialog.ShowDialog(FindForm()) == Forms.DialogResult.OK) File.WriteAllText(dialog.FileName, page.Controls.OfType<KrnlCodeEditor>().First().Text);
    }
}
