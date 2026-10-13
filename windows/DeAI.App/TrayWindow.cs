using System;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Automation;

namespace DeAI.App;

internal sealed class TrayWindow : Window
{
    public TrayWindow(Controller controller, string? process)
    {
        Title = "DeAI"; var panel = Ui.Panel(this, 300, 16); ShowActivated = true;
        var automatic = new CheckBox { IsChecked = controller.Preferences.AutoCheck, ToolTip = Ui.L("自动检查", "Automatic checks") };
        AutomationProperties.SetAutomationId(automatic, "AutoCheck");
        automatic.Checked += (_, _) => SaveAuto(true); automatic.Unchecked += (_, _) => SaveAuto(false);
        panel.Children.Add(Ui.Row(Ui.Title("DeAI", 18), automatic));
        if (process != null)
        {
            var active = new CheckBox { Content = Ui.L("当前应用：", "Current app: ") + process, IsChecked = !controller.Preferences.ExcludedApps.Contains(process, StringComparer.OrdinalIgnoreCase), Margin = new Thickness(0, 16, 0, 10) };
            panel.Children.Add(active);
            var pauseState = Ui.Label("", 10, "Muted");
            AutomationProperties.SetAutomationId(pauseState, "AppPauseStatus");
            var pause = Ui.Button("", () =>
            {
                try
                {
                    if (controller.AppPauses.Deadline(process) != null) controller.ResumeApp(process);
                    else controller.PauseApp(process);
                }
                catch (Exception error) { Ui.Error(error); }
            }, "ToggleAppPause", "FlatButton");
            pause.HorizontalAlignment = HorizontalAlignment.Left;
            panel.Children.Add(pauseState); panel.Children.Add(pause);
            var caption = Ui.Label(Ui.L("仅暂停自动检查，手动检查仍可用。", "Pauses automatic checks only; manual checks still work."), 10, "Muted");
            caption.Margin = new Thickness(0, 4, 0, 8); panel.Children.Add(caption);
            void RefreshPause()
            {
                var deadline = controller.AppPauses.Deadline(process);
                pauseState.Text = deadline is { } until ? Ui.L("已暂停至 ", "Paused until ") + until.ToLocalTime().ToString("t") : "";
                pauseState.Visibility = deadline == null ? Visibility.Collapsed : Visibility.Visible;
                pause.Content = deadline != null ? Ui.L("恢复此应用自动检查", "Resume this app") : Ui.L("暂停此应用 15 分钟", "Pause this app for 15 minutes");
                AutomationProperties.SetName(pause, (string)pause.Content);
                pause.IsEnabled = controller.Preferences.AllowsProcess(process) && !controller.Preferences.ExcludedApps.Contains(process, StringComparer.OrdinalIgnoreCase);
            }
            void PausesChanged(string[] _) => RefreshPause();
            controller.AppPauses.Changed += PausesChanged;
            Closed += (_, _) => controller.AppPauses.Changed -= PausesChanged;
            RefreshPause();
            active.Checked += (_, _) => SetApp(true); active.Unchecked += (_, _) => SetApp(false);
            void SetApp(bool enabled)
            {
                try
                {
                    var apps = controller.Preferences.ExcludedApps.Where(p => !p.Equals(process, StringComparison.OrdinalIgnoreCase));
                    controller.SavePreferences(controller.Preferences with { ExcludedApps = enabled ? apps.ToArray() : apps.Append(process).ToArray() });
                    RefreshPause();
                }
                catch (Exception error) { Ui.Error(error); }
            }
        }
        else
        {
            var label = Ui.Label(Ui.L("先聚焦可读编辑框进行检查", "Focus a readable editor to check"), 11, "Muted"); label.Margin = new Thickness(0, 14, 0, 10); panel.Children.Add(label);
        }
        var divider = Ui.Separator(); divider.Margin = new Thickness(0, 4, 0, 10); panel.Children.Add(divider);
        Add(Ui.L("查看建议", "Suggestions"), "☷", controller.ShowSuggestions, "ShowSuggestions");
        Add(Ui.L("应用组", "App groups"), "▦", controller.ShowSettings, "OpenAppGroups");
        Add(Ui.L("设置…", "Settings…"), "⚙", controller.ShowSettings, "OpenSettings");
        Add(Ui.L("规则测试器…", "Rule tester…"), "⌕", () => new RuleTester(controller).Show(), "OpenRuleTester");
        var footer = Ui.Separator(); footer.Margin = new Thickness(0, 8, 0, 8); panel.Children.Add(footer);
        Add(Ui.L("退出 DeAI", "Quit DeAI"), "", () => Application.Current.Shutdown(), "QuitDeAI");
        new PanelBehavior(this, Close);
        void SaveAuto(bool enabled)
        {
            try { controller.SavePreferences(controller.Preferences with { AutoCheck = enabled }); }
            catch (Exception error) { Ui.Error(error); }
        }
        void Add(string title, string icon, Action action, string id)
        {
            var button = Ui.Button(title, () => { Close(); action(); }, id, "FlatButton"); button.Padding = new Thickness(5, 7, 5, 7);
            button.HorizontalContentAlignment = HorizontalAlignment.Stretch;
            button.Content = Ui.Row(Ui.Label(title, 13), Ui.Label(icon, 15, "Muted")); panel.Children.Add(button);
        }
    }
}

internal sealed class RuleTester : Window
{
    public RuleTester(Controller controller)
    {
        Title = Ui.L("DeAI 规则测试器", "DeAI rule tester"); Ui.Style(this); Width = 560; Height = 540;
        var panel = new StackPanel { Margin = new Thickness(30) }; panel.Children.Add(Ui.Title(Ui.L("规则测试器", "Rule tester"), 20));
        var input = Ui.Text("", "RuleTestInput", true); input.Height = 150; input.Margin = new Thickness(0, 20, 0, 16); panel.Children.Add(input);
        var results = Ui.Text("", "RuleTestResults", true); results.IsReadOnly = true; results.Height = 190;
        panel.Children.Add(Ui.Button(Ui.L("检查", "Check"), () =>
        {
            try
            {
                var findings = controller.TestRules(input.Text);
                results.Text = findings.Count == 0 ? Ui.L("没有发现问题", "No issues found") : string.Join("\n\n", findings.Select(f => Ui.Category(f.Category) + " · " + f.RuleId + $" · [{f.Start}, {f.End})\n" + f.Message + "\n" + string.Join(" / ", f.Suggestions)));
            }
            catch (Exception error) { Ui.Error(error); }
        }, "RunRuleTest", "PrimaryButton")); panel.Children.Add(results); Content = panel;
    }
}
