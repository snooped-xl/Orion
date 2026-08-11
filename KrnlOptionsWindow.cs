using Drawing = System.Drawing;
using Forms = System.Windows.Forms;
using System.Runtime.InteropServices;

namespace OrbitAvalonia;

internal sealed class KrnlOptionsWindow : Forms.Form
{
    private readonly Action _returnToOrbit;

    public KrnlOptionsWindow(
        Action returnToOrbit,
        bool topMost,
        bool opacityFade,
        Action<bool> setTopMost,
        Action<bool> setOpacityFade)
    {
        _returnToOrbit = returnToOrbit;
        AutoScaleDimensions = new Drawing.SizeF(6F, 13F);
        AutoScaleMode = Forms.AutoScaleMode.Font;
        BackColor = Drawing.Color.FromArgb(25, 25, 25);
        ClientSize = new Drawing.Size(248, 153);
        FormBorderStyle = Forms.FormBorderStyle.None;
        MaximizeBox = false;
        MinimizeBox = false;
        Name = "settings";
        ShowInTaskbar = false;
        StartPosition = Forms.FormStartPosition.CenterParent;
        Text = "Settings";
        TopMost = topMost;

        var header = new Forms.Panel
        {
            BackColor = Drawing.Color.FromArgb(29, 29, 29),
            Location = new Drawing.Point(-9, -3),
            Size = new Drawing.Size(281, 37)
        };
        header.MouseDown += BeginDrag;
        var logo = new Forms.PictureBox
        {
            Image = KrnlSourceAssets.LoadPng("pictureBox1.Image"),
            Location = new Drawing.Point(7, 1),
            Size = new Drawing.Size(35, 36),
            SizeMode = Forms.PictureBoxSizeMode.Zoom
        };
        logo.MouseDown += BeginDrag;
        header.Controls.Add(logo);
        var title = new Forms.Label
        {
            AutoSize = true,
            Font = new Drawing.Font("Segoe UI", 9F),
            ForeColor = Drawing.Color.White,
            Location = new Drawing.Point(110, 11),
            Text = "Settings"
        };
        title.MouseDown += BeginDrag;
        header.Controls.Add(title);
        var minimize = CreateHeaderButton("—", new Drawing.Point(200, -1));
        minimize.Click += (_, _) => WindowState = Forms.FormWindowState.Minimized;
        header.Controls.Add(minimize);
        var close = CreateHeaderButton("✕", new Drawing.Point(228, -1));
        close.Click += (_, _) => Close();
        header.Controls.Add(close);
        Controls.Add(header);

        AddLabel("Top Most", 10, 55);
        AddToggle(187, 52, topMost, enabled =>
        {
            TopMost = enabled;
            setTopMost(enabled);
        });
        AddLabel("Opacity Fade-in/out", 10, 84);
        AddToggle(187, 81, opacityFade, setOpacityFade);
        var orbit = CreateButton("Use Orbit UI", 10, 118);
        orbit.Click += (_, _) =>
        {
            _returnToOrbit();
            Close();
        };
        Controls.Add(orbit);
    }

    private static Forms.Button CreateHeaderButton(string text, Drawing.Point location)
    {
        var button = new Forms.Button
        {
            BackColor = Drawing.Color.FromArgb(29, 29, 29),
            FlatStyle = Forms.FlatStyle.Flat,
            ForeColor = Drawing.Color.White,
            Location = location,
            Size = new Drawing.Size(25, 37),
            Text = text,
            UseVisualStyleBackColor = false
        };
        button.FlatAppearance.BorderSize = 0;
        button.FlatAppearance.MouseDownBackColor = Drawing.Color.FromArgb(40, 40, 40);
        button.FlatAppearance.MouseOverBackColor = Drawing.Color.FromArgb(35, 35, 35);
        return button;
    }

    private void AddLabel(string text, int x, int y) => Controls.Add(new Forms.Label
    {
        AutoSize = true,
        Font = new Drawing.Font("Segoe UI", 9F),
        ForeColor = Drawing.Color.White,
        Location = new Drawing.Point(x, y),
        Text = text
    });

    private void AddToggle(int x, int y, bool initialValue, Action<bool> changed)
    {
        var toggle = new KrnlToggle
        {
            Checked = initialValue,
            Location = new Drawing.Point(x, y),
            Size = new Drawing.Size(54, 21)
        };
        toggle.CheckedChanged += (_, _) => changed(toggle.Checked);
        Controls.Add(toggle);
    }

    private static Forms.Button CreateButton(string text, int x, int y)
    {
        var button = new Forms.Button
        {
            BackColor = Drawing.Color.FromArgb(36, 36, 36),
            FlatStyle = Forms.FlatStyle.Flat,
            ForeColor = Drawing.Color.White,
            Location = new Drawing.Point(x, y),
            Size = new Drawing.Size(text.Contains("Orbit", StringComparison.OrdinalIgnoreCase) ? 130 : 62, 23),
            Text = text,
            UseVisualStyleBackColor = false
        };
        button.FlatAppearance.BorderSize = 0;
        button.FlatAppearance.MouseDownBackColor = Drawing.Color.FromArgb(40, 40, 40);
        button.FlatAppearance.MouseOverBackColor = Drawing.Color.FromArgb(39, 39, 39);
        return button;
    }

    private void BeginDrag(object? sender, Forms.MouseEventArgs e)
    {
        if (e.Button != Forms.MouseButtons.Left) return;
        ReleaseCapture();
        SendMessage(Handle, 0xA1, 2, 0);
    }

    [DllImport("user32.dll")] private static extern bool ReleaseCapture();
    [DllImport("user32.dll")] private static extern IntPtr SendMessage(IntPtr handle, int message, int wParam, int lParam);

    private sealed class KrnlToggle : Forms.Control
    {
        private bool _checked;
        private int _thumbX = 1;
        private readonly Forms.Timer _animation = new() { Interval = 10 };

        public event EventHandler? CheckedChanged;

        public bool Checked
        {
            get => _checked;
            set
            {
                _checked = value;
                _thumbX = value ? 20 : 1;
                Invalidate();
            }
        }

        public KrnlToggle()
        {
            SetStyle(Forms.ControlStyles.UserPaint | Forms.ControlStyles.OptimizedDoubleBuffer, true);
            Cursor = Forms.Cursors.Hand;
            Click += (_, _) =>
            {
                _checked = !_checked;
                _animation.Start();
                CheckedChanged?.Invoke(this, EventArgs.Empty);
            };
            _animation.Tick += (_, _) =>
            {
                var destination = _checked ? 20 : 1;
                if (_thumbX == destination)
                {
                    _animation.Stop();
                    return;
                }

                _thumbX += Math.Sign(destination - _thumbX) * Math.Min(3, Math.Abs(destination - _thumbX));
                Invalidate();
            };
        }

        protected override void OnPaint(Forms.PaintEventArgs e)
        {
            e.Graphics.SmoothingMode = Drawing.Drawing2D.SmoothingMode.HighQuality;
            using var bar = new Drawing.SolidBrush(Drawing.Color.FromArgb(35, 35, 35));
            e.Graphics.FillRoundedRectangle(bar, new Drawing.Rectangle(5, 7, 27, 7), 4);
            using var circle = new Drawing.SolidBrush(Drawing.Color.FromArgb(91, 91, 91));
            e.Graphics.FillEllipse(circle, _thumbX, 2, 18, 18);
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing) _animation.Dispose();
            base.Dispose(disposing);
        }
    }
}

internal static class KrnlDrawingExtensions
{
    public static void FillRoundedRectangle(this Drawing.Graphics graphics, Drawing.Brush brush, Drawing.Rectangle bounds, int radius)
    {
        using var path = new Drawing.Drawing2D.GraphicsPath();
        var diameter = radius * 2;
        path.AddArc(bounds.X, bounds.Y, diameter, diameter, 180, 90);
        path.AddArc(bounds.Right - diameter, bounds.Y, diameter, diameter, 270, 90);
        path.AddArc(bounds.Right - diameter, bounds.Bottom - diameter, diameter, diameter, 0, 90);
        path.AddArc(bounds.X, bounds.Bottom - diameter, diameter, diameter, 90, 90);
        path.CloseFigure();
        graphics.FillPath(brush, path);
    }
}
