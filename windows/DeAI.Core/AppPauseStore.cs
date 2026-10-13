using System;
using System.Collections.Generic;
using System.Linq;

namespace DeAI;

public sealed class AppPauseStore
{
    private readonly Dictionary<string, DateTimeOffset> deadlines = new(StringComparer.OrdinalIgnoreCase);
    private readonly Func<DateTimeOffset> now;
    private long version;
    public event Action<string[]>? Changed;
    public AppPauseStore(Func<DateTimeOffset>? now = null) => this.now = now ?? (() => DateTimeOffset.UtcNow);
    public long Version { get { lock (deadlines) return version; } }
    public DateTimeOffset? Deadline(string process)
    {
        lock (deadlines) return deadlines.TryGetValue(process, out var deadline) && deadline > now() ? deadline : null;
    }
    public bool PermitsAutomaticCheck(string process, bool enabled) => enabled && Deadline(process) == null;
    public bool AllowsScan(string process, bool manual, long expectedVersion)
    {
        lock (deadlines) return manual || (expectedVersion == version && Deadline(process) == null);
    }
    public void Pause(string process, TimeSpan? duration = null)
    {
        var span = duration ?? TimeSpan.FromMinutes(15);
        if (string.IsNullOrWhiteSpace(process) || span <= TimeSpan.Zero) return;
        lock (deadlines) { deadlines[process] = now().Add(span); version++; }
        Changed?.Invoke(new[] { process });
    }
    public void Resume(string process)
    {
        lock (deadlines)
        {
            if (!deadlines.Remove(process)) return;
            version++;
        }
        Changed?.Invoke(new[] { process });
    }
    public void RefreshExpirations()
    {
        string[] expired;
        lock (deadlines)
        {
            var date = now();
            expired = deadlines.Where(pair => pair.Value <= date).Select(pair => pair.Key).ToArray();
            if (expired.Length == 0) return;
            foreach (var process in expired) deadlines.Remove(process);
            version++;
        }
        Changed?.Invoke(expired);
    }
}
