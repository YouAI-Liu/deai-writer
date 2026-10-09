using System;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Automation;
using System.Windows.Documents;
using System.Windows.Media;
using DeAI.Automation;

namespace DeAI.App;

internal sealed record SuggestionItem(string Text) { public override string ToString() => Text.Length == 0 ? Ui.L("（删除）", "(Delete)") : Text; }

internal sealed class SuggestionWindow : Window
{
    private readonly Controller controller;
    private readonly StackPanel body;
    private readonly PanelBehavior behavior;
    private TextTarget? target;
    private Finding[] findings = Array.Empty<Finding>();
    private int index;
    private bool exiting, busy, popupOpen;
    private string? message;
    public SuggestionWindow(Controller controller)
    {
        this.controller = controller;
        Title = "DeAI — " + Ui.L("写作建议", "Writing suggestions");
        body = Ui.Panel(this, Ui.CardWidth, 14);
        behavior = new PanelBehavior(this, Hide, () => popupOpen || busy);
        Closing += (_, e) => { if (!exiting) { e.Cancel = true; Hide(); } };
        IsVisibleChanged += async (_, _) => { if (IsVisible) await Position(); };
        Render(null, Array.Empty<Finding>(), Ui.L("聚焦编辑框后按检查快捷键。检查在本地运行。", "Focus an editor and press the check shortcut. Checks run locally."));
    }
    private Finding? Selected => findings.Length > 0 ? findings[Math.Clamp(index, 0, findings.Length - 1)] : null;
    public void Render(TextTarget? target, Finding[] findings, string? message = null)
    {
        var selected = Selected;
        this.target = target;
        this.findings = target == null ? Array.Empty<Finding>() : findings.Where(f => f.Start >= 0 && f.End >= f.Start && f.End <= target.Original.Length).ToArray();
        index = selected == null ? 0 : Math.Max(0, Array.IndexOf(this.findings, selected));
        this.message = message; Rebuild();
        if (IsVisible) _ = Position();
    }
    private void Rebuild()
    {
        body.Children.Clear();
        var selected = Selected;
        var heading = new StackPanel { Orientation = Orientation.Horizontal };
        if (selected != null)
        {
            var dot = new System.Windows.Shapes.Ellipse { Width = 5, Height = 5, Margin = new Thickness(0, 0, 6, 0), VerticalAlignment = VerticalAlignment.Center };
            Ui.Color(dot, System.Windows.Shapes.Shape.FillProperty, Ui.CategoryKey(selected.Category)); heading.Children.Add(dot);
            var tag = Ui.Label(Ui.Category(selected.Category), 10, "Muted");
            tag.Padding = new Thickness(7, 3, 7, 3);
            var capsule = new Border { CornerRadius = new CornerRadius(20), Child = tag };
            Ui.Color(capsule, Border.BackgroundProperty, "Track"); heading.Children.Add(capsule);
        }
        else heading.Children.Add(Ui.Label("DeAI", 12, "Muted"));
        var controls = new StackPanel { Orientation = Orientation.Horizontal };
        if (findings.Length > 1)
        {
            controls.Children.Add(Ui.Icon("‹", Ui.L("上一条", "Previous"), () => Step(-1), "PreviousFinding"));
            var count = Ui.Label($"{index + 1}/{findings.Length}", 10, "Muted"); count.VerticalAlignment = VerticalAlignment.Center; controls.Children.Add(count);
            controls.Children.Add(Ui.Icon("›", Ui.L("下一条", "Next"), () => Step(1), "NextFinding"));
        }
        controls.Children.Add(Ui.Icon("×", Ui.L("关闭", "Close"), Hide, "DismissSuggestions"));
        body.Children.Add(Ui.Row(heading, controls, 0));
        if (selected == null || target == null)
        {
            var text = Ui.Label(message ?? Ui.L("没有发现问题", "No issues found"), 13, "Muted"); text.Margin = new Thickness(0, 14, 0, 12);
            AutomationProperties.SetAutomationId(text, "CheckStatus"); body.Children.Add(text);
            body.Children.Add(Ui.Button(Ui.L("打开设置", "Settings"), controller.ShowSettings, "OpenSettings", "FlatButton")); return;
        }
        var matched = target.Original[selected.Start..selected.End];
        var description = Ui.Label(selected.Message, 12); description.Margin = new Thickness(0, 12, 0, 8); body.Children.Add(description);
        var original = Ui.Label(matched, 13, "Muted"); original.TextDecorations = TextDecorations.Strikethrough;
        AutomationProperties.SetAutomationId(original, "FindingOriginal"); body.Children.Add(original);
        var choices = selected.Suggestions.Select(s => new SuggestionItem(s)).ToArray();
        var replacements = new ComboBox { ItemsSource = choices, SelectedIndex = choices.Length > 0 ? 0 : -1, Margin = new Thickness(0, 8, 0, 12) };
        AutomationProperties.SetAutomationId(replacements, "Suggestions");
        replacements.DropDownOpened += (_, _) => popupOpen = true; replacements.DropDownClosed += (_, _) => popupOpen = false;
        if (choices.Length > 1) body.Children.Add(replacements);
        else if (choices.Length == 1)
        {
            var replacement = Ui.Label(choices[0].ToString(), 14); replacement.FontWeight = FontWeights.Medium;
            replacement.Margin = new Thickness(0, 6, 0, 12); AutomationProperties.SetAutomationId(replacement, "Suggestions"); body.Children.Add(replacement);
        }
        var actions = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 4, 0, 0) };
        var apply = Ui.Icon("✓", Ui.L("接受建议", "Accept suggestion"), async () =>
        {
            if (busy || replacements.SelectedItem is not SuggestionItem replacement) return;
            busy = true; Rebuild();
            await controller.Apply(target, selected.Start, selected.End, replacement.Text);
            busy = false; Rebuild();
        }, "ApplySuggestion");
        Ui.Color(apply, Control.BackgroundProperty, "AcceptGreen"); apply.Foreground = Brushes.White;
        apply.IsEnabled = !busy && target.CanWrite && choices.Length > 0; actions.Children.Add(apply);
        var rewrite = Ui.Icon("✧", Ui.L("AI 改写", "AI rewrite"), () => { Hide(); controller.BeginRewrite(target, selected); }, "RewriteFinding");
        rewrite.IsEnabled = !busy; actions.Children.Add(rewrite);
        var ignore = Ui.Icon("⊘", Ui.L("忽略", "Ignore"), () => controller.Ignore(selected), "IgnoreFinding"); ignore.IsEnabled = !busy; actions.Children.Add(ignore);
        var menu = new ContextMenu();
        menu.Opened += (_, _) => popupOpen = true; menu.Closed += (_, _) => popupOpen = false;
        AddMenu(menu, Ui.L("定位原文", "Locate original"), async () => await controller.Locate(target, selected), "LocateFinding");
        AddMenu(menu, Ui.L("复制建议", "Copy suggestion"), () => { if (replacements.SelectedItem is SuggestionItem item && item.Text.Length > 0) Clipboard.SetText(item.Text); }, "CopySuggestion");
        AddMenu(menu, Ui.L("保留此词", "Keep this word"), () => Remember(new PersonalEntry("keep", matched, null)), "KeepTerm");
        AddMenu(menu, Ui.L("记住改法", "Remember this fix"), () =>
        {
            if (replacements.SelectedItem is SuggestionItem item)
                Remember(new PersonalEntry(item.Text.Length == 0 ? "avoid" : "replace", matched, item.Text.Length == 0 ? null : item.Text));
        }, "RememberFix");
        AddMenu(menu, Ui.L("禁用规则", "Disable rule"), () => controller.Disable(selected), "DisableRule");
        AddMenu(menu, Ui.L("设置", "Settings"), controller.ShowSettings, "OpenSettings");
        var more = Ui.Icon("⋯", Ui.L("更多", "More"), () => menu.IsOpen = true, "MoreSuggestions"); more.ContextMenu = menu; more.IsEnabled = !busy; actions.Children.Add(more);
        foreach (FrameworkElement child in actions.Children) child.Margin = new Thickness(0, 0, 8, 0);
        body.Children.Add(actions);
        if (!target.CanWrite)
        {
            var status = Ui.Label(Ui.L("此目标只读，可定位或复制。", "Read-only target. Locate or copy instead."), 10, "Muted");
            status.Margin = new Thickness(0, 8, 0, 0); body.Children.Add(status);
        }
    }
    private void Remember(PersonalEntry entry)
    {
        try { controller.SaveLexicon(controller.Lexicon.Append(entry).Distinct().ToArray()); controller.Ignore(Selected!); }
        catch (Exception error) { Ui.Error(error); }
    }
    private static void AddMenu(ContextMenu menu, string label, Action action, string id)
    {
        var item = new MenuItem { Header = label }; AutomationProperties.SetAutomationId(item, id);
        item.Click += (_, _) => action(); menu.Items.Add(item);
    }
    private void Step(int delta)
    {
        if (busy || findings.Length == 0) return;
        index = (index + delta + findings.Length) % findings.Length; Rebuild(); _ = Position();
    }
    public void Select(Finding finding)
    {
        var selected = Array.IndexOf(findings, finding);
        if (selected >= 0) { index = selected; Rebuild(); _ = Position(); }
    }
    private async System.Threading.Tasks.Task Position()
    {
        if (target == null || Selected == null || busy) return;
        var captured = target; var finding = Selected;
        var anchor = await controller.Geometry(captured, finding);
        if (IsVisible && target == captured && Selected == finding && anchor != null) PanelBehavior.Place(this, anchor);
    }
    public void Exit() { exiting = true; behavior.Dispose(); Close(); }
}
