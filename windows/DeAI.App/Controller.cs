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
    public SecretStore Secrets { get; }
    public SkillStore Skills { get; }
    public Preferences Preferences { get; private set; }
    public PersonalEntry[] Lexicon { get; private set; }
    private readonly AutomationWorker worker = new();
    private readonly NativeChecker checker = new();
    private readonly Hotkeys hotkeys = new();
    private readonly Highlight highlight = new();
    private readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromMilliseconds(1200) };
    private readonly Forms.NotifyIcon tray;
    private readonly SuggestionWindow suggestions;
    private SettingsWindow? settings;
    private RewriteWindow? rewrite;
    private CheckResult? current;
    private readonly HashSet<Finding> ignored = new();
    private bool busy, disposed;
    public Controller()
    {
        Preferences = Store.Load("settings.json", new Preferences()); Preferences.Validate();
        Lexicon = Store.Load("lexicon.json", Array.Empty<PersonalEntry>()); DataStore.ValidateLexicon(Lexicon);
        Secrets = new SecretStore(Store); Skills = new SkillStore(Store); Ui.Language = Preferences.Language;
        suggestions = new SuggestionWindow(this);
        tray = new Forms.NotifyIcon { Icon = System.Drawing.SystemIcons.Information, Text = "DeAI", Visible = true };
        var menu = new Forms.ContextMenuStrip();
        menu.Items.Add(Ui.L("查看建议", "Suggestions"), null, (_, _) => ShowSuggestions());
        menu.Items.Add(Ui.L("设置", "Settings"), null, (_, _) => ShowSettings());
        menu.Items.Add(Ui.L("暂停 / 继续检查", "Pause / resume checks"), null, (_, _) => { timer.IsEnabled = !timer.IsEnabled; tray.Text = timer.IsEnabled ? "DeAI" : "DeAI — paused"; });
        menu.Items.Add(Ui.L("退出", "Quit"), null, (_, _) => Application.Current.Shutdown());
        tray.ContextMenuStrip = menu; tray.DoubleClick += (_, _) => ShowSuggestions();
        hotkeys.Pressed += async isRewrite => await Scan(true, isRewrite);
        timer.Tick += async (_, _) => { if (Preferences.AutoCheck && rewrite == null) await Scan(false, false); };
    }
    public void Start()
    {
        try { hotkeys.Register(Preferences); } catch (Exception error) { Ui.Error(error); }
        timer.Start(); ShowSuggestions();
    }
    public void ShowSuggestions() { suggestions.Show(); suggestions.Activate(); }
    public void ShowSettings()
    {
        if (settings != null) { settings.Activate(); return; }
        settings = new SettingsWindow(this); settings.Closed += (_, _) => settings = null; settings.Show();
    }
    public void SavePreferences(Preferences preferences)
    {
        preferences.Validate(); hotkeys.Register(preferences);
        try { Store.Save("settings.json", preferences); } catch { hotkeys.Register(Preferences); throw; }
        Preferences = preferences; Ui.Language = preferences.Language; current = null; ignored.Clear(); highlight.Clear();
        suggestions.Render(null, Array.Empty<Finding>(), Ui.L("设置已保存。聚焦目标并按检查快捷键。语言切换在重启后完整生效。", "Saved. Focus a target and press the check hotkey. Restart to fully change UI language."));
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
                var target = TextTarget.Focused(automation, preferences.BrowsersEnabled, preferences.ExcludedApps);
                if (target == null || target.WindowHandle != GetForegroundWindow()) return null;
                if (!show && previous != null && previous.Target.SameTarget(target) && previous.Target.Original == target.Original) return previous;
                var findings = checker.Check(target.Original, preferences.Options, entries).Where(f => !preferences.DisabledRules.Contains(f.RuleId)).ToArray();
                return new CheckResult(target, findings);
            });
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
        }
        catch (Exception error) { if (show) Ui.Error(error); else tray.Text = "DeAI — " + Ui.L("目标不可用", "target unavailable"); }
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
            var rectangles = await worker.Run(_ => { target.Validate(); SetForegroundWindow(target.WindowHandle); target.Select(finding.Start, finding.End); return target.Locate(finding.Start, finding.End); });
            if (rectangles.Count == 0) throw new InvalidOperationException(Ui.L("目标未提供可见范围坐标。", "Target did not provide visible geometry."));
            highlight.Show(rectangles);
        }
        catch (Exception error) { highlight.Clear(); Ui.Error(error); }
    }
    public async Task ValidateTarget(TextTarget target)
    {
        var preferences = Preferences;
        await worker.Run(_ => { if (!target.IsAllowed(preferences.BrowsersEnabled, preferences.ExcludedApps)) throw new InvalidOperationException("目标已被应用策略排除。"); target.Validate(); return true; });
        if (preferences != Preferences) throw new InvalidOperationException("设置已变化，请重新检查。");
    }
    public async Task<bool> Apply(TextTarget target, int start, int end, string replacement)
    {
        try
        {
            await ValidateTarget(target);
            await worker.Run(_ => { target.Replace(start, end, replacement); return true; });
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
        disposed = true; timer.Stop(); rewrite?.Close(); settings?.Close(); suggestions.Exit(); highlight.Dispose(); hotkeys.Dispose(); tray.Dispose(); worker.Dispose();
    }
    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr hwnd);
}
