using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;
using DeAI.Automation;

namespace DeAI.App;

internal sealed class Highlight : IDisposable
{
    private readonly List<Window> windows = new();
    private readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromSeconds(2) };
    public Highlight() { timer.Tick += (_, _) => Clear(); }
    public void Show(IReadOnlyList<ScreenRect> rectangles)
    {
        Clear();
        foreach (var rectangle in rectangles)
        {
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
                Content = new Border { BorderBrush = Ui.Accent, BorderThickness = new Thickness(0, 0, 0, 3), Background = new SolidColorBrush(Color.FromArgb(35, 19, 109, 97)) }
            };
            window.SourceInitialized += (_, _) => { var handle = new WindowInteropHelper(window).Handle; SetWindowLongPtr(handle, -20, new IntPtr(GetWindowLongPtr(handle, -20).ToInt64() | 0x08000020)); };
            window.Show();
            // UIA geometry is physical screen pixels; native placement avoids mixing DPI/DIP units.
            SetWindowPos(new WindowInteropHelper(window).Handle, new IntPtr(-1), (int)rectangle.X, (int)rectangle.Y, (int)Math.Ceiling(rectangle.Width), (int)Math.Ceiling(rectangle.Height), 0x10);
            windows.Add(window);
        }
        timer.Start();
    }
    public void Clear() { timer.Stop(); foreach (var window in windows) window.Close(); windows.Clear(); }
    public void Dispose() => Clear();
    [DllImport("user32.dll")] private static extern IntPtr GetWindowLongPtr(IntPtr hwnd, int index);
    [DllImport("user32.dll")] private static extern IntPtr SetWindowLongPtr(IntPtr hwnd, int index, IntPtr value);
    [DllImport("user32.dll")] private static extern bool SetWindowPos(IntPtr hwnd, IntPtr after, int x, int y, int width, int height, uint flags);
}
