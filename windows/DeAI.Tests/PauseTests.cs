using System;
using System.Linq;
using DeAI;
using static DeAI.Tests.Program;

namespace DeAI.Tests;

internal static class PauseTests
{
    public static void Run()
    {
        Check("App pause is case-insensitive, per-app and defaults to 15 minutes", () =>
        {
            var now = DateTimeOffset.UtcNow; var store = new AppPauseStore(() => now);
            store.Pause("Notepad");
            Equal<DateTimeOffset?>(now.AddMinutes(15), store.Deadline("notepad"));
            Equal(false, store.PermitsAutomaticCheck("notepad", true));
            Equal(true, store.PermitsAutomaticCheck("word", true));
        });
        Check("App pause permits manual checks but rejects in-flight automatic generations", () =>
        {
            var store = new AppPauseStore(); var version = store.Version;
            store.Pause("notepad");
            Equal(false, store.AllowsScan("notepad", false, version));
            Equal(true, store.AllowsScan("notepad", true, version));
            store.Resume("notepad");
            Equal(false, store.AllowsScan("notepad", false, version));
            Equal(true, store.AllowsScan("notepad", false, store.Version));
        });
        Check("App pause expiry notifies once and leaves other apps paused", () =>
        {
            var now = DateTimeOffset.UtcNow; var store = new AppPauseStore(() => now);
            store.Pause("notepad", TimeSpan.FromSeconds(5)); store.Pause("word", TimeSpan.FromMinutes(1));
            var count = 0;
            store.Changed += changed => { count++; Equal("notepad", changed.Single()); };
            now = now.AddSeconds(5); Equal(null, store.Deadline("notepad"));
            store.RefreshExpirations(); store.RefreshExpirations();
            Equal(1, count); Equal(true, store.Deadline("word") != null);
        });
        Check("App pause resume and expiry never reenable permanent exclusions", () =>
        {
            var now = DateTimeOffset.UtcNow; var store = new AppPauseStore(() => now);
            var preferences = new Preferences { ExcludedApps = new[] { "notepad" } };
            bool Enabled() => preferences.AllowsProcess("notepad") && !preferences.ExcludedApps.Contains("notepad");
            store.Pause("notepad"); store.Resume("notepad");
            Equal(false, store.PermitsAutomaticCheck("notepad", Enabled()));
            store.Pause("notepad"); now = now.AddMinutes(16); store.RefreshExpirations();
            Equal(false, store.PermitsAutomaticCheck("notepad", Enabled()));
            Equal("notepad", preferences.ExcludedApps.Single());
        });
        Check("App pause restarts clear pauses and repeat pause extends deadline", () =>
        {
            var now = DateTimeOffset.UtcNow; var store = new AppPauseStore(() => now);
            store.Pause("notepad"); now = now.AddMinutes(1); store.Pause("notepad");
            Equal<DateTimeOffset?>(now.AddMinutes(15), store.Deadline("notepad"));
            Equal(null, new AppPauseStore(() => now).Deadline("notepad"));
            store.Pause("word", TimeSpan.Zero); Equal(null, store.Deadline("word"));
        });
        Check("App pause manual resume notifies once", () =>
        {
            var store = new AppPauseStore(); store.Pause("notepad");
            var count = 0; store.Changed += _ => count++;
            store.Resume("NOTEPAD"); store.Resume("notepad"); Equal(1, count);
        });
    }
}
