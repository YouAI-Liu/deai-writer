using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using Interop.UIAutomationClient;

namespace DeAI.Automation;

internal sealed class ClassicNotepadEdit
{
    private const uint GetText = 0x000D, GetLength = 0x000E, GetSelection = 0x00B0, SetSelection = 0x00B1, ReplaceSelection = 0x00C2;
    private readonly IntPtr handle, owner;
    private readonly int pid;
    private readonly long started;

    private ClassicNotepadEdit(IntPtr handle, IntPtr owner, int pid)
    {
        this.handle = handle; this.owner = owner; this.pid = pid;
        using var process = Process.GetProcessById(pid);
        started = process.StartTime.ToUniversalTime().Ticks;
    }

    internal static bool Eligible(string framework, string controlClass, string ownerClass, string imagePath, uint style) =>
        framework == "Win32" && controlClass == "Edit" && ownerClass == "Notepad"
        && string.Equals(imagePath, Path.Combine(Environment.SystemDirectory, "notepad.exe"), StringComparison.OrdinalIgnoreCase)
        && (style & 0x40000004u) == 0x40000004u && (style & (0x0020u | 0x0800u)) == 0;

    internal static ClassicNotepadEdit? TryCreate(IUIAutomationElement element, IntPtr owner, string original)
    {
        if (element.CurrentFrameworkId != "Win32" || element.CurrentClassName != "Edit" || original.Contains('\0')) return null;
        try
        {
            var edit = new ClassicNotepadEdit(element.CurrentNativeWindowHandle, owner, element.CurrentProcessId);
            edit.Validate(original);
            return edit;
        }
        catch { return null; }
    }

    private void ValidateIdentity()
    {
        using var process = Process.GetProcessById(pid);
        GetWindowThreadProcessId(handle, out var controlPid);
        GetWindowThreadProcessId(owner, out var ownerPid);
        if (handle == IntPtr.Zero || owner == IntPtr.Zero || controlPid != pid || ownerPid != pid
            || GetAncestor(handle, 2) != owner || !IsWindowUnicode(handle) || !IsWindowEnabled(handle) || !IsWindowVisible(handle)
            || process.StartTime.ToUniversalTime().Ticks != started
            || !Eligible("Win32", ClassName(handle), ClassName(owner), process.MainModule?.FileName ?? "", unchecked((uint)GetWindowLongPtr(handle, -16).ToInt64())))
            throw new InvalidOperationException("经典记事本编辑控件已失效或不再满足安全写回条件。");
    }

    internal void Validate(string original)
    {
        ValidateIdentity();
        if (!string.Equals(Read(), original, StringComparison.Ordinal))
            throw new InvalidOperationException("记事本原文或换行映射已变化，请重新检查。");
    }

    private string Read()
    {
        var length = Send(GetLength, UIntPtr.Zero, IntPtr.Zero).ToUInt64();
        if (length > TextSafety.MaxTextLength) throw new InvalidOperationException("文本超过安全长度限制。");
        var buffer = new StringBuilder((int)length + 1);
        if (SendMessageText(handle, GetText, new UIntPtr(length + 1), buffer, 0x0023, 1000, out var copied) == IntPtr.Zero
            || copied.ToUInt64() != length || buffer.Length != (int)length
            || Send(GetLength, UIntPtr.Zero, IntPtr.Zero).ToUInt64() != length)
            throw new InvalidOperationException("记事本读取失败或原文正在变化。");
        return buffer.ToString();
    }

    internal static string Expected(string original, int start, int end, string replacement)
    {
        if (original.Contains('\0') || replacement.Contains('\0')) throw new InvalidOperationException("拒绝含 NUL 的原生替换文本。");
        return TextSafety.Replace(original, original, start, end, replacement);
    }

    internal void Replace(string original, int start, int end, string replacement, Action confirmFocus)
    {
        var expected = Expected(original, start, end, replacement);
        Validate(original);
        confirmFocus();
        Send(SetSelection, new UIntPtr((uint)start), new IntPtr(end));
        var from = Marshal.AllocHGlobal(sizeof(int));
        var to = Marshal.AllocHGlobal(sizeof(int));
        try
        {
            Marshal.WriteInt32(from, -1); Marshal.WriteInt32(to, -1);
            Send(GetSelection, new UIntPtr(unchecked((ulong)from.ToInt64())), to);
            if (Marshal.ReadInt32(from) != start || Marshal.ReadInt32(to) != end)
                throw new InvalidOperationException("记事本 UTF-16 选区不一致，未写回。");
        }
        finally { Marshal.FreeHGlobal(from); Marshal.FreeHGlobal(to); }
        Validate(original);
        confirmFocus();
        // EM_REPLACESEL preserves undo and edit notifications; never flatten with WM_SETTEXT.
        if (SendMessageString(handle, ReplaceSelection, new UIntPtr(1), replacement, 0x0023, 1000, out _) == IntPtr.Zero)
            throw new InvalidOperationException("记事本写回未确认；请检查文档，未尝试重试或回滚。");
        ValidateIdentity();
        if (!string.Equals(Read(), expected, StringComparison.Ordinal))
            throw new InvalidOperationException("记事本写回结果与预期不符；请检查文档，未尝试重试或回滚。");
    }

    private UIntPtr Send(uint message, UIntPtr wParam, IntPtr lParam)
    {
        if (SendMessageTimeout(handle, message, wParam, lParam, 0x0023, 1000, out var result) == IntPtr.Zero)
            throw new InvalidOperationException("记事本编辑控件未响应或拒绝访问。");
        return result;
    }

    private static string ClassName(IntPtr window)
    {
        var name = new StringBuilder(256);
        return GetClassName(window, name, name.Capacity) == 0 ? "" : name.ToString();
    }

    [DllImport("user32.dll", EntryPoint = "SendMessageTimeoutW")] private static extern IntPtr SendMessageTimeout(IntPtr window, uint message, UIntPtr wParam, IntPtr lParam, uint flags, uint timeout, out UIntPtr result);
    [DllImport("user32.dll", EntryPoint = "SendMessageTimeoutW", CharSet = CharSet.Unicode)] private static extern IntPtr SendMessageText(IntPtr window, uint message, UIntPtr wParam, StringBuilder text, uint flags, uint timeout, out UIntPtr result);
    [DllImport("user32.dll", EntryPoint = "SendMessageTimeoutW", CharSet = CharSet.Unicode)] private static extern IntPtr SendMessageString(IntPtr window, uint message, UIntPtr wParam, string text, uint flags, uint timeout, out UIntPtr result);
    [DllImport("user32.dll", EntryPoint = "GetClassNameW", CharSet = CharSet.Unicode)] private static extern int GetClassName(IntPtr window, StringBuilder name, int maximum);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] private static extern IntPtr GetWindowLongPtr(IntPtr window, int index);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr window, out int processId);
    [DllImport("user32.dll")] private static extern IntPtr GetAncestor(IntPtr window, uint flags);
    [DllImport("user32.dll")] private static extern bool IsWindowUnicode(IntPtr window);
    [DllImport("user32.dll")] private static extern bool IsWindowEnabled(IntPtr window);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr window);
}
