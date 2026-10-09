using System;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using DeAI.Automation;

namespace DeAI.App;

internal sealed class PanelBehavior : IDisposable
{
    private delegate IntPtr Hook(int code, IntPtr message, IntPtr data);
    private readonly Window window;
    private readonly Action dismiss;
    private readonly Func<bool> popupOpen;
    private readonly Hook mouse, keyboard;
    private IntPtr mouseHandle, keyboardHandle;
    public PanelBehavior(Window window, Action dismiss, Func<bool>? popupOpen = null)
    {
        this.window = window; this.dismiss = dismiss; this.popupOpen = popupOpen ?? (() => false);
        mouse = Mouse; keyboard = Keyboard;
        window.IsVisibleChanged += VisibilityChanged;
        window.SizeChanged += Resized;
        window.Closed += (_, _) => Dispose();
    }
    private void VisibilityChanged(object sender, DependencyPropertyChangedEventArgs args)
    {
        if (window.IsVisible)
        {
            Fit();
            mouseHandle = SetWindowsHookEx(14, mouse, GetModuleHandle(null), 0);
            keyboardHandle = SetWindowsHookEx(13, keyboard, GetModuleHandle(null), 0);
        }
        else Unhook();
    }
    private void Resized(object sender, SizeChangedEventArgs args) { if (window.IsVisible) Fit(); }
    private void Fit()
    {
        var handle = new WindowInteropHelper(window).Handle;
        if (handle == IntPtr.Zero || !GetWindowRect(handle, out var rect)) return;
        var area = System.Windows.Forms.Screen.FromHandle(handle).WorkingArea;
        var scale = GetDpiForWindow(handle) / 96.0;
        window.MaxHeight = area.Height / scale;
        if (window.Content is System.Windows.Controls.Border border) border.MaxHeight = Math.Max(0, window.MaxHeight - 40);
        var x = Math.Clamp(rect.Left, area.Left, Math.Max(area.Left, area.Right - (rect.Right - rect.Left)));
        var y = Math.Clamp(rect.Top, area.Top, Math.Max(area.Top, area.Bottom - (rect.Bottom - rect.Top)));
        if (x != rect.Left || y != rect.Top) SetWindowPos(handle, IntPtr.Zero, x, y, 0, 0, 0x15);
    }
    private IntPtr Mouse(int code, IntPtr message, IntPtr data)
    {
        if (code >= 0 && (message.ToInt32() is 0x201 or 0x204) && !popupOpen())
        {
            var point = Marshal.PtrToStructure<Point>(data);
            var padding = (int)(GetDpiForWindow(new WindowInteropHelper(window).Handle) / 96.0 * 20);
            if (GetWindowRect(new WindowInteropHelper(window).Handle, out var rect) &&
                (point.X < rect.Left + padding || point.X > rect.Right - padding || point.Y < rect.Top + padding || point.Y > rect.Bottom - padding))
                window.Dispatcher.BeginInvoke(dismiss);
        }
        return CallNextHookEx(mouseHandle, code, message, data);
    }
    private IntPtr Keyboard(int code, IntPtr message, IntPtr data)
    {
        if (code >= 0 && (message.ToInt32() is 0x100 or 0x104) && Marshal.ReadInt32(data) == 0x1B && !popupOpen())
            window.Dispatcher.BeginInvoke(dismiss);
        return CallNextHookEx(keyboardHandle, code, message, data);
    }
    public static void Raise(Window window)
    {
        var handle = new WindowInteropHelper(window).Handle;
        if (window.IsVisible && handle != IntPtr.Zero)
        {
            SetWindowPos(handle, new IntPtr(-1), 0, 0, 0, 0, 0x13);
            RaisePopups();
        }
    }
    public static void RaisePopup(Visual popup)
    {
        if (PresentationSource.FromVisual(popup) is HwndSource source && source.Handle != IntPtr.Zero)
            SetWindowPos(source.Handle, new IntPtr(-1), 0, 0, 0, 0, 0x13);
    }
    private static void RaisePopups()
    {
        // WPF popup HWNDs are separate from Application.Windows.
        foreach (PresentationSource source in PresentationSource.CurrentSources)
            if (source is HwndSource hwnd && hwnd.RootVisual != null && hwnd.RootVisual is not Window)
                RaisePopup(hwnd.RootVisual);
    }
    public static void Place(Window window, ScreenRect anchor)
    {
        var handle = new WindowInteropHelper(window).Handle;
        if (handle == IntPtr.Zero) return;
        // Move first so WPF receives WM_DPICHANGED before the final physical-pixel clamp.
        SetWindowPos(handle, new IntPtr(-1), (int)anchor.X - 20, (int)(anchor.Y + anchor.Height) - 14, 0, 0, 0x11);
        if (!GetWindowRect(handle, out var size)) return;
        var area = System.Windows.Forms.Screen.FromPoint(new System.Drawing.Point((int)anchor.X, (int)anchor.Y)).WorkingArea;
        var width = size.Right - size.Left; var height = size.Bottom - size.Top;
        var x = Math.Clamp((int)anchor.X - 20, area.Left, Math.Max(area.Left, area.Right - width));
        var y = (int)(anchor.Y + anchor.Height) - 14;
        if (y + height > area.Bottom) y = (int)anchor.Y - height + 14;
        y = Math.Clamp(y, area.Top, Math.Max(area.Top, area.Bottom - height));
        SetWindowPos(handle, new IntPtr(-1), x, y, 0, 0, 0x11);
        RaisePopups();
    }
    private void Unhook()
    {
        if (mouseHandle != IntPtr.Zero) UnhookWindowsHookEx(mouseHandle);
        if (keyboardHandle != IntPtr.Zero) UnhookWindowsHookEx(keyboardHandle);
        mouseHandle = keyboardHandle = IntPtr.Zero;
    }
    public void Dispose() { Unhook(); window.IsVisibleChanged -= VisibilityChanged; window.SizeChanged -= Resized; }
    [StructLayout(LayoutKind.Sequential)] private struct Point { public int X, Y; }
    [StructLayout(LayoutKind.Sequential)] private struct Rect { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] private static extern IntPtr SetWindowsHookEx(int kind, Hook callback, IntPtr module, uint thread);
    [DllImport("user32.dll")] private static extern bool UnhookWindowsHookEx(IntPtr hook);
    [DllImport("user32.dll")] private static extern IntPtr CallNextHookEx(IntPtr hook, int code, IntPtr message, IntPtr data);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] private static extern IntPtr GetModuleHandle(string? module);
    [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr window, out Rect rect);
    [DllImport("user32.dll")] private static extern uint GetDpiForWindow(IntPtr window);
    [DllImport("user32.dll")] private static extern bool SetWindowPos(IntPtr window, IntPtr after, int x, int y, int width, int height, uint flags);
}
