using System;
using System.Collections.Generic;
using System.Diagnostics;

namespace DeAI.Automation;

public static class AppPolicy
{
    private static readonly HashSet<string> Sensitive = new(StringComparer.OrdinalIgnoreCase)
    {
        "DeAI", "DeAI.App", "WindowsTerminal", "cmd", "powershell", "pwsh", "conhost",
        "mintty", "putty", "KeePass", "KeePassXC", "1Password", "Bitwarden", "LastPass"
    };
    private static readonly HashSet<string> Browsers = new(StringComparer.OrdinalIgnoreCase)
    { "chrome", "msedge", "firefox", "brave", "opera", "vivaldi" };

    public static string ProcessName(int pid)
    {
        using var process = Process.GetProcessById(pid);
        return process.ProcessName;
    }

    public static bool IsAllowed(int pid, bool browsersEnabled = false, IEnumerable<string>? excluded = null)
    {
        if (pid == Environment.ProcessId) return false;
        var name = ProcessName(pid);
        if (Sensitive.Contains(name) || (!browsersEnabled && Browsers.Contains(name))) return false;
        if (excluded != null)
            foreach (var item in excluded)
                if (string.Equals(name, item.Trim(), StringComparison.OrdinalIgnoreCase)) return false;
        return true;
    }
}
