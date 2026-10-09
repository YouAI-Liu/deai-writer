using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Windows.Interop;

namespace DeAI.App;

public sealed class Hotkeys : IDisposable
{
    private readonly HwndSource source;
    private int checkId, rewriteId, nextId = 1;
    private Hotkey? checkKey, rewriteKey;
    public event Action<bool>? Pressed;
    public Hotkeys()
    {
        source = new HwndSource(new HwndSourceParameters("DeAI Hotkeys") { ParentWindow = new IntPtr(-3) });
        source.AddHook(Hook);
    }
    public void Register(Preferences preferences)
    {
        if (preferences.CheckHotkey == preferences.RewriteHotkey) throw new InvalidOperationException("检查与改写快捷键不能相同。");
        var added = new List<int>();
        int Register(Hotkey key)
        {
            if (key == checkKey) return checkId;
            if (key == rewriteKey) return rewriteId;
            var id = nextId++;
            if (id > 0xbfff || !RegisterHotKey(source.Handle, id, key.Modifiers | 0x4000, key.Key))
                throw new InvalidOperationException("快捷键已被占用；原快捷键保持不变。");
            added.Add(id);
            return id;
        }
        int first, second;
        try { first = Register(preferences.CheckHotkey); second = Register(preferences.RewriteHotkey); }
        catch { foreach (var id in added) UnregisterHotKey(source.Handle, id); throw; }
        foreach (var id in new[] { checkId, rewriteId })
            if (id != 0 && id != first && id != second) UnregisterHotKey(source.Handle, id);
        checkId = first; rewriteId = second;
        checkKey = preferences.CheckHotkey; rewriteKey = preferences.RewriteHotkey;
    }
    private IntPtr Hook(IntPtr hwnd, int message, IntPtr wparam, IntPtr lparam, ref bool handled)
    {
        if (message == 0x0312 && (wparam.ToInt32() == checkId || wparam.ToInt32() == rewriteId))
        { handled = true; Pressed?.Invoke(wparam.ToInt32() == rewriteId); }
        return IntPtr.Zero;
    }
    public void Dispose()
    {
        if (checkId != 0) { UnregisterHotKey(source.Handle, checkId); UnregisterHotKey(source.Handle, rewriteId); }
        source.Dispose();
    }
    [DllImport("user32.dll", SetLastError = true)] private static extern bool RegisterHotKey(IntPtr hwnd, int id, uint modifiers, uint key);
    [DllImport("user32.dll")] private static extern bool UnregisterHotKey(IntPtr hwnd, int id);
}
