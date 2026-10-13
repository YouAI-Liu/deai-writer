using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace DeAI.Automation;

internal sealed class FocusHistory
{
    internal IntPtr Owner { get; private set; }
    internal long Version { get; private set; }
    internal long FocusVersion { get; private set; }
    private int focusPid;
    private int[] focusId = Array.Empty<int>();
    internal void ObserveFocus(int pid, int[] id, bool ownProcess)
    {
        if (ownProcess) return;
        if (pid > 0 && id.Length > 0 && pid == focusPid && id.AsSpan().SequenceEqual(focusId)) return;
        focusPid = pid; focusId = (int[])id.Clone(); FocusVersion++;
    }
    internal void Observe(IntPtr window, bool ownProcess)
    {
        // Windows can report no foreground window while activation is in progress.
        if (window == IntPtr.Zero || ownProcess || window == Owner) return;
        Owner = window; Version++;
    }
    internal bool Matches(IntPtr owner, long version, IntPtr foreground, bool ownProcess) =>
        owner != IntPtr.Zero && Owner == owner && Version == version && (foreground == owner || ownProcess);
}

public sealed class ForegroundLease
{
    private readonly ForegroundTracker tracker;
    internal IntPtr Owner { get; }
    internal long Version { get; }
    internal long? FocusVersion { get; set; }
    internal ForegroundLease(ForegroundTracker tracker, IntPtr owner, long version) { this.tracker = tracker; Owner = owner; Version = version; }
    public void Validate() => tracker.Validate(this);
    internal void Bind(int pid, int[] id) => tracker.Bind(this, pid, id);
}

public sealed class ForegroundTracker : IDisposable
{
    private delegate void WinEvent(IntPtr hook, uint eventId, IntPtr window, int objectId, int childId, uint thread, uint time);
    private readonly FocusHistory history = new();
    private readonly WinEvent callback;
    private readonly IntPtr hook;
    private bool disposed;
    public ForegroundTracker()
    {
        callback = (_, _, window, _, _, _, _) => { lock (history) history.Observe(window, OwnProcess(window)); };
        hook = SetWinEventHook(3, 3, IntPtr.Zero, callback, 0, 0, 2);
        if (hook == IntPtr.Zero) throw new InvalidOperationException("无法监听前台目标变化，拒绝启用写回。");
        history.Observe(GetForegroundWindow(), OwnProcess(GetForegroundWindow()));
    }
    public ForegroundLease Capture(IntPtr owner)
    {
        lock (history)
        {
            var foreground = GetForegroundWindow();
            history.Observe(foreground, OwnProcess(foreground));
            var lease = new ForegroundLease(this, owner, history.Version);
            Validate(lease);
            return lease;
        }
    }
    internal void Validate(ForegroundLease lease)
    {
        lock (history)
        {
            var foreground = GetForegroundWindow();
            var ownProcess = OwnProcess(foreground);
            history.Observe(foreground, ownProcess);
            if (disposed || !history.Matches(lease.Owner, lease.Version, foreground, ownProcess)
                || (lease.FocusVersion != null && lease.FocusVersion != history.FocusVersion))
                throw new InvalidOperationException("焦点已切换，请重新聚焦目标并检查。");
        }
    }
    public void ObserveFocus(int pid, int[] id)
    {
        lock (history) history.ObserveFocus(pid, id, pid == Environment.ProcessId);
    }
    public string? CurrentProcessName()
    {
        lock (history)
        {
            var window = GetForegroundWindow();
            if (window == IntPtr.Zero) return null;
            history.Observe(window, OwnProcess(window));
            var owner = OwnProcess(window) ? history.Owner : window;
            if (owner == IntPtr.Zero || OwnProcess(owner)) return null;
            GetWindowThreadProcessId(owner, out var pid);
            try
            {
                var name = AppPolicy.ProcessName(pid);
                return name.Length == 0 ? null : name;
            }
            catch (Exception error) when (error is ArgumentException or InvalidOperationException or Win32Exception) { return null; }
        }
    }
    internal void Bind(ForegroundLease lease, int pid, int[] id)
    {
        lock (history)
        {
            ObserveFocus(pid, id); lease.FocusVersion = history.FocusVersion; Validate(lease);
        }
    }
    private static bool OwnProcess(IntPtr window)
    {
        GetWindowThreadProcessId(window, out var pid);
        return pid == Environment.ProcessId;
    }
    public void Dispose() { lock (history) { if (disposed) return; disposed = true; UnhookWinEvent(hook); } }
    [DllImport("user32.dll")] private static extern IntPtr SetWinEventHook(uint first, uint last, IntPtr module, WinEvent callback, uint process, uint thread, uint flags);
    [DllImport("user32.dll")] private static extern bool UnhookWinEvent(IntPtr hook);
    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr window, out int pid);
}
