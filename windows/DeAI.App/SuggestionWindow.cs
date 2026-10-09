using System;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Automation;
using DeAI.Automation;

namespace DeAI.App;

internal sealed record FindingItem(Finding Finding, string Matched)
{
    public override string ToString() => Finding.Category + " · " + Matched.Replace("\r", " ").Replace("\n", " ") + "\n" + Finding.Message;
}
internal sealed record SuggestionItem(string Text) { public override string ToString() => Text.Length == 0 ? Ui.L("（删除）", "(Delete)") : Text; }

internal sealed class SuggestionWindow : Window
{
    private readonly Controller controller;
    private readonly TextBlock status = Ui.Label("", 14);
    private readonly TextBlock detail = Ui.Label("");
    private readonly ListBox list = new() { MinHeight = 180, Margin = new Thickness(0, 8, 0, 12) };
    private readonly ComboBox replacements = new() { MinHeight = 34, Margin = new Thickness(0, 8, 0, 8) };
    private readonly Button apply, locate, ignore, disable, rewrite;
    private TextTarget? target;
    private bool exiting;
    public SuggestionWindow(Controller controller)
    {
        this.controller = controller; Title = "DeAI — " + Ui.L("写作建议", "Writing suggestions"); Width = 520; Height = 610; MinHeight = 540; MinWidth = 440;
        Ui.Style(this); ShowActivated = false;
        var panel = new DockPanel { Margin = new Thickness(24) };
        var heading = new StackPanel(); heading.Children.Add(Ui.Label("DeAI", 27));
        heading.Children.Add(status); DockPanel.SetDock(heading, Dock.Top); panel.Children.Add(heading);
        var footer = new StackPanel();
        footer.Children.Add(detail); footer.Children.Add(replacements);
        var actions = new WrapPanel();
        apply = Ui.Button(Ui.L("应用建议", "Apply"), async () => { if (target != null && Selected != null && replacements.SelectedItem is SuggestionItem item) await controller.Apply(target, Selected.Start, Selected.End, item.Text); }, "ApplySuggestion");
        locate = Ui.Button(Ui.L("定位原文", "Locate"), async () => { if (target != null && Selected != null) await controller.Locate(target, Selected); }, "LocateFinding");
        ignore = Ui.Button(Ui.L("忽略本次", "Ignore once"), () => { if (Selected != null) controller.Ignore(Selected); }, "IgnoreFinding");
        disable = Ui.Button(Ui.L("禁用规则", "Disable rule"), () => { if (Selected != null) controller.Disable(Selected); }, "DisableRule");
        rewrite = Ui.Button(Ui.L("AI 改写", "AI rewrite"), () => { if (target != null && Selected != null) controller.BeginRewrite(target, Selected); }, "RewriteFinding");
        actions.Children.Add(apply); actions.Children.Add(locate); actions.Children.Add(ignore); actions.Children.Add(disable); actions.Children.Add(rewrite);
        actions.Children.Add(Ui.Button(Ui.L("复制建议", "Copy suggestion"), () => { if (replacements.SelectedItem is SuggestionItem item && item.Text.Length != 0) Clipboard.SetText(item.Text); }, "CopySuggestion"));
        actions.Children.Add(Ui.Button(Ui.L("设置", "Settings"), controller.ShowSettings, "OpenSettings"));
        footer.Children.Add(actions); footer.Children.Add(Ui.Label(Ui.L("默认：Ctrl+Alt+F9 检查；Ctrl+Alt+F10 改写选区/光标所在段落。仅验证纯文本控件写回。", "Defaults: Ctrl+Alt+F9 checks; Ctrl+Alt+F10 rewrites selection/caret paragraph. Write-back is limited to verified plain-text controls."), 12));
        DockPanel.SetDock(footer, Dock.Bottom); panel.Children.Add(footer); panel.Children.Add(list); Content = panel;
        AutomationProperties.SetAutomationId(list, "Findings"); AutomationProperties.SetAutomationId(status, "CheckStatus");
        AutomationProperties.SetAutomationId(replacements, "Suggestions");
        list.SelectionChanged += (_, _) => UpdateSelection();
        Closing += (_, e) => { if (!exiting) { e.Cancel = true; Hide(); } };
        Render(null, Array.Empty<Finding>(), Ui.L("聚焦编辑框后按检查快捷键。检查在本地运行；AI 仅在你确认发送后调用。关闭此窗口仍在托盘运行。", "Focus an editor and press the check hotkey. Checks run locally; AI runs only after sending confirmation. Closing this window keeps DeAI in the tray."));
    }
    private Finding? Selected => (list.SelectedItem as FindingItem)?.Finding;
    public void Render(TextTarget? target, Finding[] findings, string? message = null)
    {
        this.target = target;
        status.Text = message ?? target?.ProcessName + " · " + findings.Length + Ui.L(" 条建议", " suggestions")
            + (target?.CanWrite == true ? "" : Ui.L(" · 只读：可定位/复制，不自动写回", " · Read-only: locate/copy only"));
        list.ItemsSource = findings.Where(f => f.Start >= 0 && f.End >= f.Start && f.End <= target!.Original.Length)
            .Select(f => new FindingItem(f, target!.Original[f.Start..f.End])).ToArray();
        if (list.Items.Count > 0) list.SelectedIndex = 0; else UpdateSelection();
    }
    private void UpdateSelection()
    {
        var selected = Selected;
        detail.Text = selected == null ? "" : selected.RuleId + " · UTF-16 [" + selected.Start + ", " + selected.End + ")";
        replacements.ItemsSource = selected?.Suggestions.Select(s => new SuggestionItem(s)).ToArray();
        if (replacements.Items.Count > 0) replacements.SelectedIndex = 0;
        apply.IsEnabled = target?.CanWrite == true && selected != null && replacements.Items.Count > 0;
        locate.IsEnabled = ignore.IsEnabled = disable.IsEnabled = rewrite.IsEnabled = selected != null;
    }
    public void Exit() { exiting = true; Close(); }
}
