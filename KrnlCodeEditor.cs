using System.Runtime.InteropServices;
using System.Text.RegularExpressions;
using Drawing = System.Drawing;
using Forms = System.Windows.Forms;

namespace OrbitAvalonia;

/// <summary>
/// .NET 8 editor surface recreating the leaked Scintilla palette, number margin,
/// typography, selection behavior and scrolling without carrying over its backend.
/// </summary>
internal sealed class KrnlCodeEditor : Forms.UserControl
{
    private const int WmSetRedraw = 0x000B;
    private const int EmGetLineCount = 0x00BA;
    private const int EmLineIndex = 0x00BB;
    private const int EmGetFirstVisibleLine = 0x00CE;
    private const int EmGetScrollPosition = 0x04DD;
    private const int EmSetScrollPosition = 0x04DE;
    private const int VisibleLinePadding = 1;
    private static readonly Drawing.Color Canvas = Drawing.Color.FromArgb(40, 40, 40);
    private static readonly Regex CommentPattern = new(@"--\[\[[\s\S]*?\]\]|--[^\r\n]*", RegexOptions.Compiled);
    private static readonly Regex StringPattern = new("(?s)(?<!\\\\)(?:\\\\\\\\)*(['\\\"])(?:\\\\.|(?!\\1).)*?\\1", RegexOptions.Compiled);
    private static readonly Regex NumberPattern = new(@"\b(?:0x[0-9a-fA-F]+|\d+(?:\.\d+)?)\b", RegexOptions.Compiled);
    private static readonly Regex KeywordPattern = new(@"\b(?:and|break|do|else|elseif|end|false|for|function|if|in|local|nil|not|or|repeat|return|then|true|until|while)\b", RegexOptions.Compiled);
    private static readonly Regex BuiltInPattern = new(@"\b(?:warn|print|loadstring|game|workspace|wait|spawn|pairs|ipairs|require|typeof|tostring|tonumber|pcall|xpcall|getgenv|getgc|identifyexecutor)\b", RegexOptions.Compiled);

    private readonly Forms.RichTextBox _textBox;
    private readonly Forms.Panel _lineNumbers;
    private readonly Forms.Timer _highlightTimer;
    private readonly Drawing.Font _regularFont = new("Consolas", 10F, Drawing.FontStyle.Regular);
    private readonly Drawing.Font _boldFont = new("Consolas", 10F, Drawing.FontStyle.Bold);
    private readonly Drawing.Font _lineNumberFont = new("Consolas", 8F, Drawing.FontStyle.Regular);
    private bool _highlighting;

    public KrnlCodeEditor()
    {
        BackColor = Canvas;
        BorderStyle = Forms.BorderStyle.None;
        Dock = Forms.DockStyle.Fill;
        Margin = Forms.Padding.Empty;
        Padding = Forms.Padding.Empty;

        _lineNumbers = new BufferedPanel
        {
            BackColor = Canvas,
            Dock = Forms.DockStyle.Left,
            Margin = Forms.Padding.Empty,
            Width = 15
        };
        _lineNumbers.Paint += (_, e) => PaintLineNumbers(e.Graphics);

        _highlightTimer = new Forms.Timer { Interval = 150 };
        _highlightTimer.Tick += (_, _) =>
        {
            _highlightTimer.Stop();
            ApplySyntaxPalette();
        };

        _textBox = new Forms.RichTextBox
        {
            AcceptsTab = true,
            BackColor = Canvas,
            BorderStyle = Forms.BorderStyle.None,
            DetectUrls = false,
            Dock = Forms.DockStyle.Fill,
            Font = _regularFont,
            ForeColor = Drawing.Color.White,
            HideSelection = false,
            Margin = Forms.Padding.Empty,
            Multiline = true,
            ScrollBars = Forms.RichTextBoxScrollBars.Both,
            ShortcutsEnabled = true,
            WordWrap = false
        };
        _textBox.TextChanged += (_, _) =>
        {
            if (_highlighting) return;
            UpdateMarginWidth();
            _lineNumbers.Invalidate();
            ScheduleVisibleHighlight();
        };
        _textBox.VScroll += (_, _) =>
        {
            _lineNumbers.Invalidate();
            ScheduleVisibleHighlight();
        };
        _textBox.SelectionChanged += (_, _) =>
        {
            if (!_highlighting) _lineNumbers.Invalidate();
        };
        _textBox.Resize += (_, _) =>
        {
            _lineNumbers.Invalidate();
            ScheduleVisibleHighlight();
        };
        _textBox.HandleCreated += (_, _) =>
        {
            UpdateMarginWidth();
            BeginInvoke(new Action(ApplySyntaxPalette));
        };

        Controls.Add(_textBox);
        Controls.Add(_lineNumbers);
    }

    public new string Text
    {
        get => _textBox.Text;
        set
        {
            _textBox.Text = value;
            ApplySyntaxPalette();
        }
    }

    public void ClearAll() => _textBox.Clear();

    private void UpdateMarginWidth()
    {
        var digits = Math.Max(1, GetLineCount().ToString().Length);
        var width = Math.Max(15, TextRendererWidth(new string('9', digits + 1)) + 5);
        if (_lineNumbers.Width != width)
            _lineNumbers.Width = width;
    }

    private int TextRendererWidth(string text) => Forms.TextRenderer.MeasureText(
        text,
        _lineNumberFont,
        Drawing.Size.Empty,
        Forms.TextFormatFlags.NoPadding).Width;

    private void PaintLineNumbers(Drawing.Graphics graphics)
    {
        graphics.Clear(Canvas);
        if (!_textBox.IsHandleCreated) return;

        var firstLine = Math.Max(0, SendMessage(_textBox.Handle, EmGetFirstVisibleLine, IntPtr.Zero, IntPtr.Zero).ToInt32());
        var lineCount = GetLineCount();
        for (var line = firstLine; line < lineCount; line++)
        {
            var charIndex = _textBox.GetFirstCharIndexFromLine(line);
            if (charIndex < 0 && line > 0) break;
            var y = _textBox.GetPositionFromCharIndex(Math.Max(0, charIndex)).Y;
            if (y > _textBox.ClientSize.Height) break;
            Forms.TextRenderer.DrawText(
                graphics,
                (line + 1).ToString(),
                _lineNumberFont,
                new Drawing.Rectangle(0, y, _lineNumbers.Width - 3, _lineNumberFont.Height + 2),
                Drawing.Color.FromArgb(190, 190, 190),
                Forms.TextFormatFlags.Right | Forms.TextFormatFlags.Top | Forms.TextFormatFlags.NoPadding);
        }
    }

    private void ApplySyntaxPalette()
    {
        if (_highlighting || _textBox.IsDisposed || !_textBox.IsHandleCreated) return;
        _highlighting = true;
        var selectionStart = _textBox.SelectionStart;
        var selectionLength = _textBox.SelectionLength;
        var firstVisibleLine = GetFirstVisibleLine();
        var scrollPosition = GetScrollPosition();
        SendMessage(_textBox.Handle, WmSetRedraw, IntPtr.Zero, IntPtr.Zero);
        try
        {
            var lineCount = GetLineCount();
            var visibleLineCount = Math.Max(
                1,
                (int)Math.Ceiling(_textBox.ClientSize.Height / (double)Math.Max(1, _regularFont.Height)) + 1);
            var startLine = Math.Max(0, firstVisibleLine - VisibleLinePadding);
            var endLine = Math.Min(
                lineCount - 1,
                firstVisibleLine + visibleLineCount + VisibleLinePadding);
            var startIndex = LineIndex(startLine);
            var endIndex = endLine + 1 < lineCount
                ? LineIndex(endLine + 1)
                : _textBox.TextLength;
            if (startIndex < 0 || endIndex < startIndex) return;

            var rangeLength = endIndex - startIndex;
            _textBox.Select(startIndex, rangeLength);
            var visibleText = _textBox.SelectedText;
            _textBox.SelectionColor = Drawing.Color.White;
            _textBox.SelectionFont = _regularFont;

            ApplyMatches(KeywordPattern, visibleText, startIndex, Drawing.Color.FromArgb(255, 60, 122), bold: false);
            ApplyMatches(BuiltInPattern, visibleText, startIndex, Drawing.Color.FromArgb(89, 255, 172), bold: true);
            ApplyMatches(NumberPattern, visibleText, startIndex, Drawing.Color.FromArgb(165, 112, 255), bold: false);
            ApplyMatches(StringPattern, visibleText, startIndex, Drawing.Color.FromArgb(255, 192, 115), bold: false);
            ApplyMatches(CommentPattern, visibleText, startIndex, Drawing.Color.FromArgb(79, 81, 98), bold: false);
        }
        finally
        {
            _textBox.Select(Math.Min(selectionStart, _textBox.TextLength), Math.Min(selectionLength, Math.Max(0, _textBox.TextLength - selectionStart)));
            SetScrollPosition(scrollPosition);
            SendMessage(_textBox.Handle, WmSetRedraw, new IntPtr(1), IntPtr.Zero);
            _textBox.Invalidate();
            _lineNumbers.Invalidate();
            _highlighting = false;
        }
    }

    private void ApplyMatches(
        Regex pattern,
        string visibleText,
        int rangeStart,
        Drawing.Color color,
        bool bold)
    {
        foreach (Match match in pattern.Matches(visibleText))
        {
            _textBox.Select(rangeStart + match.Index, match.Length);
            _textBox.SelectionColor = color;
            _textBox.SelectionFont = bold ? _boldFont : _regularFont;
        }
    }

    private void ScheduleVisibleHighlight()
    {
        _highlightTimer.Stop();
        _highlightTimer.Start();
    }

    private int GetLineCount() => Math.Max(
        1,
        SendMessage(_textBox.Handle, EmGetLineCount, IntPtr.Zero, IntPtr.Zero).ToInt32());

    private int GetFirstVisibleLine() => Math.Max(
        0,
        SendMessage(_textBox.Handle, EmGetFirstVisibleLine, IntPtr.Zero, IntPtr.Zero).ToInt32());

    private int LineIndex(int line) => SendMessage(
        _textBox.Handle,
        EmLineIndex,
        new IntPtr(line),
        IntPtr.Zero).ToInt32();

    private NativePoint GetScrollPosition()
    {
        var point = default(NativePoint);
        SendMessagePoint(_textBox.Handle, EmGetScrollPosition, IntPtr.Zero, ref point);
        return point;
    }

    private void SetScrollPosition(NativePoint point) =>
        SendMessagePoint(_textBox.Handle, EmSetScrollPosition, IntPtr.Zero, ref point);

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _highlightTimer.Dispose();
            _regularFont.Dispose();
            _boldFont.Dispose();
            _lineNumberFont.Dispose();
        }
        base.Dispose(disposing);
    }

    [DllImport("user32.dll")]
    private static extern IntPtr SendMessage(IntPtr handle, int message, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", EntryPoint = "SendMessageW")]
    private static extern IntPtr SendMessagePoint(
        IntPtr handle,
        int message,
        IntPtr wParam,
        ref NativePoint lParam);

    [StructLayout(LayoutKind.Sequential)]
    private struct NativePoint
    {
        public int X;
        public int Y;
    }

    private sealed class BufferedPanel : Forms.Panel
    {
        public BufferedPanel()
        {
            DoubleBuffered = true;
            ResizeRedraw = true;
        }
    }
}
