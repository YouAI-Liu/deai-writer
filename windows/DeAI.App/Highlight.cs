using System;
using System.Collections.Generic;
using System.Linq;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;
using DeAI.Automation;

namespace DeAI.App;

internal sealed record LocatedFinding(Finding Finding, ScreenRect Rectangle);
internal sealed class Highlight : IDisposable
{
    private readonly List<Window> windows = new();
    private readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromMilliseconds(150) };
    private LocatedFinding[] locations = Array.Empty<LocatedFinding>();
    private UnderlineAppearance? appearance;
    private Finding? hovered;
    private int hoverTicks;
    public event Action<Finding>? Hovered;
    public Highlight()
    {
        timer.Tick += (_, _) =>
        {
            if (!GetCursorPos(out var cursor)) return;
            var hit = locations.FirstOrDefault(p => cursor.X >= p.Rectangle.X && cursor.X <= p.Rectangle.X + p.Rectangle.Width &&
                cursor.Y >= p.Rectangle.Y && cursor.Y <= p.Rectangle.Y + p.Rectangle.Height + 6)?.Finding;
            if (hit != hovered) { hovered = hit; hoverTicks = 0; }
            else if (hit != null && ++hoverTicks == 2) Hovered?.Invoke(hit);
        };
    }
    public void Show(IReadOnlyList<LocatedFinding> rectangles, UnderlineAppearance appearance)
    {
        var visible = rectangles.Take(64).ToArray();
        if (this.appearance == appearance && visible.SequenceEqual(locations)) return;
        Clear(); locations = visible; this.appearance = appearance;
        foreach (var item in visible)
        {
            var rectangle = item.Rectangle;
            var window = new Window
            {
                WindowStyle = WindowStyle.None,
                AllowsTransparency = true,
                Background = Brushes.Transparent,
                ShowInTaskbar = false,
                ShowActivated = false,
                Topmost = true,
                ResizeMode = ResizeMode.NoResize,
                Width = 1,
                Height = 1,
                IsHitTestVisible = false,
                Content = new UnderlineView { Appearance = appearance, Category = item.Finding.Category, Tier = item.Finding.Tier }
            };
            window.SourceInitialized += (_, _) =>
            {
                var handle = new WindowInteropHelper(window).Handle;
                SetWindowLongPtr(handle, -20, new IntPtr(GetWindowLongPtr(handle, -20).ToInt64() | 0x08000020));
            };
            window.Show();
            SetWindowPos(new WindowInteropHelper(window).Handle, new IntPtr(-1), (int)rectangle.X, (int)rectangle.Y,
                (int)Math.Ceiling(rectangle.Width), (int)Math.Ceiling(rectangle.Height + 8), 0x10);
            windows.Add(window);
        }
        foreach (Window panel in Application.Current.Windows)
            if (panel.IsVisible && panel.Topmost && !windows.Contains(panel))
                PanelBehavior.Raise(panel);
        if (visible.Length > 0) timer.Start();
    }
    public void Clear()
    {
        timer.Stop(); foreach (var window in windows) window.Close(); windows.Clear();
        locations = Array.Empty<LocatedFinding>(); hovered = null; hoverTicks = 0;
    }
    public void Dispose() => Clear();
    [StructLayout(LayoutKind.Sequential)] private struct Point { public int X, Y; }
    [DllImport("user32.dll")] private static extern bool GetCursorPos(out Point point);
    [DllImport("user32.dll")] private static extern IntPtr GetWindowLongPtr(IntPtr hwnd, int index);
    [DllImport("user32.dll")] private static extern IntPtr SetWindowLongPtr(IntPtr hwnd, int index, IntPtr value);
    [DllImport("user32.dll")] private static extern bool SetWindowPos(IntPtr hwnd, IntPtr after, int x, int y, int width, int height, uint flags);
}
