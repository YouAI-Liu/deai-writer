using System;
using System.Collections.Generic;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Threading;
using DeAI.Automation;
using Forms = System.Windows.Forms;

namespace DeAI.App;

internal sealed record CheckResult(TextTarget Target, Finding[] Findings);

internal sealed class Controller : IDisposable
{
    public DataStore Store { get; } = new();
    public SecretStore Secrets => new(Store, Preferences.ActiveProviderId);
    public SkillStore Skills { get; }
    public Preferences Preferences { get; private set; }
    public PersonalEntry[] Lexicon { get; private set; }
    private readonly AutomationWorker worker = new();
    private readonly NativeChecker checker = new();
    private readonly Hotkeys hotkeys = new();
    private readonly Highlight highlight = new();
    private readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromMilliseconds(1200) };
    private readonly Forms.NotifyIcon tray;
    private readonly System.Drawing.Icon trayIcon;
    private readonly SuggestionWindow suggestions;
    private SettingsWindow? settings;
    private RewriteWindow? rewrite;
    private TrayWindow? trayMenu;
    private CheckResult? current;
    private readonly HashSet<Finding> ignored = new();
    private bool busy, disposed;
    public Controller()
    {
        Preferences = Store.Load("settings.json", new Preferences()); Preferences.Validate();
        Lexicon = Store.Load("lexicon.json", Array.Empty<PersonalEntry>()); DataStore.ValidateLexicon(Lexicon);
        Skills = new SkillStore(Store); Ui.Language = Preferences.Language;
        suggestions = new SuggestionWindow(this);
        trayIcon = new System.Drawing.Icon(typeof(Controller).Assembly.GetManifestResourceStream("DeAI.ico")!);
        tray = new Forms.NotifyIcon { Icon = trayIcon, Text = "DeAI", Visible = true };
        tray.MouseClick += (_, e) =>
        {
            if (e.Button is not (Forms.MouseButtons.Left or Forms.MouseButtons.Right)) return;
            trayMenu?.Close(); trayMenu = new TrayWindow(this, current?.Target.ProcessName);
            trayMenu.Closed += (_, _) => trayMenu = null; trayMenu.Show();
            var cursor = Forms.Cursor.Position; PanelBehavior.Place(trayMenu, new ScreenRect(cursor.X, cursor.Y, 1, 1));
        };
        tray.DoubleClick += (_, _) => ShowSuggestions();
        highlight.Hovered += finding => { if (rewrite == null) { Render(); suggestions.Select(finding); suggestions.Show(); } };
        hotkeys.Pressed += async isRewrite => await Scan(true, isRewrite);
        timer.Tick += async (_, _) => { if (Preferences.AutoCheck && rewrite == null) await Scan(false, false); };
    }
    public void Start()
    {
        try { hotkeys.Register(Preferences); } catch (Exception error) { Ui.Error(error); }
        timer.Start();
    }
    public void ShowSuggestions() { suggestions.Show(); }
    public void ShowSettings() => ShowSettings(0);
    public void ShowSettings(int tab)
    {
        if (settings != null) { settings.SelectTab(tab); settings.Activate(); return; }
        settings = new SettingsWindow(this, tab); settings.Closed += (_, _) => settings = null; settings.Show();
    }
    public IDisposable PauseHotkeys()
    {
        hotkeys.Suspend();
        return new ResumeAction(() => { try { hotkeys.Register(Preferences); } catch (Exception error) { Ui.Error(error); } });
    }
    private sealed class ResumeAction(Action resume) : IDisposable
    {
        private Action? action = resume;
        public void Dispose() { var current = action; action = null; current?.Invoke(); }
    }
    public void SavePreferences(Preferences preferences)
    {
        preferences.Validate(); hotkeys.Register(preferences);
        try { Store.Save("settings.json", preferences); } catch { hotkeys.Register(Preferences); throw; }
        Preferences = preferences; Ui.Language = preferences.Language; current = null; ignored.Clear(); highlight.Clear();
        suggestions.Render(null, Array.Empty<Finding>(), Ui.L("设置已保存。聚焦目标并按检查快捷键。", "Saved. Focus a target and press the check hotkey."));
    }
    public void SaveLexicon(PersonalEntry[] entries) { DataStore.ValidateLexicon(entries); Store.Save("lexicon.json", entries); Lexicon = entries; current = null; }
    public async Task Scan(bool show, bool isRewrite)
    {
        if (busy || disposed) return;
        busy = true;
        try
        {
            var preferences = Preferences; var entries = Lexicon; var previous = current;
            var result = await worker.Run(automation =>
            {
                var target = TextTarget.Focused(automation, preferences.BrowsersEnabled, preferences.ExcludedApps, preferences.AllowsProcess);
                if (target == null || target.WindowHandle != GetForegroundWindow()) return null;
                if (!show && previous != null && previous.Target.SameTarget(target) && previous.Target.Original == target.Original) return previous;
                var findings = checker.Check(target.Original, preferences.OptionsForProcess(target.ProcessName), entries).Where(f => !preferences.DisabledRules.Contains(f.RuleId)).ToArray();
                return new CheckResult(target, findings);
            });
            if (preferences != Preferences || entries != Lexicon) return;
            if (result == null)
            {
                highlight.Clear();
                if (show) { suggestions.Render(null, Array.Empty<Finding>(), Ui.L("未找到可读目标：请聚焦普通编辑框；密码、终端、排除应用和默认浏览器不会读取。", "No readable target. Focus a plain editor. Passwords, terminals, excluded apps and browsers (by default) are not read.")); suggestions.Show(); }
                return;
            }
            if (!ReferenceEquals(result, previous)) { ignored.Clear(); current = result; Render(); }
            tray.Text = "DeAI — " + result.Findings.Length + Ui.L(" 条建议", " suggestions");
            if (isRewrite) { BeginRewrite(result.Target, null); return; }
            if (show) suggestions.Show();
            var visible = result.Findings.Where(f => !ignored.Contains(f) && !Preferences.DisabledRules.Contains(f.RuleId)).Take(32).ToArray();
            var locations = await worker.Run(_ =>
            {
                if (preferences != Preferences || result.Target.WindowHandle != GetForegroundWindow()) return Array.Empty<LocatedFinding>();
                result.Target.Validate();
                return visible.SelectMany(f => result.Target.Locate(f.Start, f.End).Select(rect => new LocatedFinding(f, rect))).Take(64).ToArray();
            });
            if (preferences == Preferences) highlight.Show(locations, preferences.Underline);
        }
        catch (Exception error) { highlight.Clear(); if (show) Ui.Error(error); else tray.Text = "DeAI — " + Ui.L("目标不可用", "target unavailable"); }
        finally { busy = false; }
    }
    private void Render() => suggestions.Render(current?.Target, current?.Findings.Where(f => !ignored.Contains(f) && !Preferences.DisabledRules.Contains(f.RuleId)).ToArray() ?? Array.Empty<Finding>());
    public void Ignore(Finding finding) { ignored.Add(finding); Render(); }
    public void Disable(Finding finding)
    {
        try { var updated = Preferences with { DisabledRules = Preferences.DisabledRules.Append(finding.RuleId).Distinct().ToArray() }; Store.Save("settings.json", updated); Preferences = updated; Render(); }
        catch (Exception error) { Ui.Error(error); }
    }
    public async Task Locate(TextTarget target, Finding finding)
    {
        try
        {
            var preferences = Preferences;
            await ValidateTarget(target);
            var rectangles = await worker.Run(_ =>
            {
                if (preferences != Preferences) throw new InvalidOperationException("设置已变化，请重新检查。");
                target.Validate(); SetForegroundWindow(target.WindowHandle); target.Select(finding.Start, finding.End); return target.Locate(finding.Start, finding.End);
            });
            if (rectangles.Count == 0) throw new InvalidOperationException(Ui.L("目标未提供可见范围坐标。", "Target did not provide visible geometry."));
            highlight.Show(rectangles.Select(rect => new LocatedFinding(finding, rect)).ToArray(), preferences.Underline);
        }
        catch (Exception error) { highlight.Clear(); Ui.Error(error); }
    }
    public async Task<ScreenRect?> Geometry(TextTarget target, Finding finding)
    {
        try
        {
            var preferences = Preferences;
            return await worker.Run(_ =>
            {
                if (!target.IsAllowed(preferences.BrowsersEnabled, preferences.ExcludedApps) || !preferences.AllowsProcess(target.ProcessName)) return null;
                target.Validate(); return target.Locate(finding.Start, finding.End).FirstOrDefault();
            });
        }
        catch { return null; }
    }
    public async Task ValidateTarget(TextTarget target)
    {
        var preferences = Preferences;
        await worker.Run(_ => { if (!target.IsAllowed(preferences.BrowsersEnabled, preferences.ExcludedApps) || !preferences.AllowsProcess(target.ProcessName)) throw new InvalidOperationException("目标已被应用策略排除。"); target.Validate(); return true; });
        if (preferences != Preferences) throw new InvalidOperationException("设置已变化，请重新检查。");
    }
    public async Task<bool> Apply(TextTarget target, int start, int end, string replacement)
    {
        try
        {
            var preferences = Preferences;
            await ValidateTarget(target);
            await worker.Run(_ => { if (preferences != Preferences) throw new InvalidOperationException("设置已变化，请重新检查。"); target.Replace(start, end, replacement); return true; });
            current = null; ignored.Clear(); highlight.Clear();
            suggestions.Render(null, Array.Empty<Finding>(), Ui.L("已写回并验证。请重新聚焦目标进行检查。", "Applied and verified. Refocus target to check again."));
            return true;
        }
        catch (Exception error) { Ui.Error(error); return false; }
    }
    public void BeginRewrite(TextTarget target, Finding? finding)
    {
        if (rewrite != null) { rewrite.Activate(); return; }
        try
        {
            var scope = finding == null ? RewriteScope.Compute(target.Original, target.Selection) : RewriteScope.Compute(target.Original, new TextSpan(finding.Start, finding.End));
            var source = target.Original[scope.Start..scope.End];
            var language = SkillStore.LanguageOf(source);
            var skill = SkillStore.Resolve(Skills.Load(), language == "zh" ? Preferences.ChineseSkill : Preferences.EnglishSkill, language);
            rewrite = new RewriteWindow(this, target, scope, skill); rewrite.Closed += (_, _) => rewrite = null; rewrite.Show();
        }
        catch (Exception error) { Ui.Error(error); }
    }
    public void Dispose()
    {
        disposed = true; timer.Stop(); trayMenu?.Close(); rewrite?.Close(); settings?.Close(); suggestions.Exit(); highlight.Dispose(); hotkeys.Dispose(); tray.Dispose(); trayIcon.Dispose(); worker.Dispose();
    }
    public IReadOnlyList<Finding> TestRules(string text) => checker.Check(text, Preferences.Options, Lexicon);
    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr hwnd);
}
