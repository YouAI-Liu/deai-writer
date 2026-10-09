using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Automation;
using DeAI.Automation;

namespace DeAI.App;

internal sealed class RewriteWindow : Window
{
    private readonly CancellationTokenSource cancellation = new();
    private readonly Controller controller;
    private readonly TextTarget target;
    private readonly TextSpan scope;
    private readonly Skill skill;
    private readonly Preferences preferences;
    private readonly string source;
    private readonly StackPanel body, state = new(), remember = new();
    private readonly TextBox output;
    private readonly Button send, apply, copy, retry;
    private readonly TextBlock status;
    private bool requesting, saved, applying, requested;
    private readonly ProgressBar progress = new() { IsIndeterminate = true, Height = 3, Margin = new Thickness(0, 8, 0, 12), Visibility = Visibility.Collapsed };
    public RewriteWindow(Controller controller, TextTarget target, TextSpan scope, Skill skill)
    {
        this.controller = controller; this.target = target; this.scope = scope; this.skill = skill;
        preferences = controller.Preferences; source = target.Original[scope.Start..scope.End];
        Title = "DeAI — " + Ui.L("AI 改写", "AI rewrite");
        body = Ui.Panel(this, Ui.RewriteWidth);
        ShowActivated = true;
        var close = Ui.Icon("×", Ui.L("关闭", "Close"), Close, "CloseRewrite");
        var header = Ui.Row(Ui.Title(Ui.L("AI 改写", "AI rewrite"), 18), close);
        header.MouseLeftButtonDown += (_, e) => { if (e.ClickCount == 1 && e.OriginalSource is TextBlock) DragMove(); };
        var sourceLabel = Ui.Label(Ui.L("原文", "Original"), 11, "Muted"); sourceLabel.Margin = new Thickness(0, 18, 0, 8); body.Children.Add(sourceLabel);
        var original = Ui.Text(source, "RewriteOriginal", true);
        original.IsReadOnly = true; original.MinHeight = 20; original.MaxHeight = 160; original.FontSize = 13; original.Padding = new Thickness(0); original.BorderThickness = new Thickness(0);
        Ui.Color(original, Control.BackgroundProperty, "Background"); Ui.Color(original, Control.ForegroundProperty, "SecondaryText"); body.Children.Add(original);
        var divider = Ui.Separator(); divider.Margin = new Thickness(0, 16, 0, 16); body.Children.Add(divider);
        output = Ui.Text("", "RewriteOutput", true); output.IsReadOnly = true; output.MinHeight = 20; output.MaxHeight = 160; output.Margin = new Thickness(0, 6, 0, 0);
        Ui.Color(output, Control.BackgroundProperty, "Background"); output.BorderThickness = new Thickness(0); output.Padding = new Thickness(0);
        state.Children.Add(Ui.Label(Ui.L("改写", "Rewrite"), 11, "Muted")); state.Children.Add(progress); state.Children.Add(output); body.Children.Add(state);
        status = Ui.Label("", 11, "Muted"); status.Margin = new Thickness(0, 8, 0, 12);
        AutomationProperties.SetAutomationId(status, "RewriteStatus"); body.Children.Add(status);
        body.Children.Add(remember);
        var footer = new StackPanel { Margin = new Thickness(0, 12, 0, 0) };
        var separator = Ui.Separator(); separator.Margin = new Thickness(0, 0, 0, 16); footer.Children.Add(separator);
        send = Ui.Button(Ui.L("发送并改写", "Send and rewrite"), async () => await Request(), "SendRewrite", "PrimaryButton");
        apply = Ui.Button(Ui.L("替换", "Replace"), async () =>
        {
            if (requesting || applying) return;
            applying = true; RefreshActions(true);
            if (await controller.Apply(target, scope.Start, scope.End, output.Text)) Close();
            else { applying = false; RefreshActions(); }
        }, "AcceptRewrite", "PrimaryButton");
        copy = Ui.Button(Ui.L("复制", "Copy"), () => { if (output.Text.Length > 0) Clipboard.SetText(output.Text); }, "CopyRewrite");
        retry = Ui.Button(Ui.L("重试", "Retry"), async () => await Request(), "RetryRewrite");
        footer.Children.Add(Ui.Actions(send, apply, copy, retry, Ui.Button(Ui.L("取消", "Cancel"), Close, "CancelRewrite", "FlatButton")));
        Ui.PinPanel(this, body, header, footer);
        output.Visibility = Visibility.Collapsed; state.Visibility = Visibility.Collapsed;
        status.Text = RewriteClient.Endpoint(preferences.Provider).Host + " · " + preferences.Provider.Model + "\n" +
            Ui.L("仅发送上面的原文、所选 Skill 和个人词库。结果需确认后才写回。", "Only the source above, selected Skill and lexicon are sent. Confirm the result before applying.");
        RefreshActions();
        new PanelBehavior(this, () => { if (!requesting && !applying) Close(); }, () => requesting || applying);
        Closed += (_, _) => cancellation.Cancel();
    }
    private async Task Request()
    {
        if (requesting || applying) return;
        requesting = true; requested = true; saved = false; output.Text = ""; remember.Children.Clear(); RefreshActions();
        progress.Visibility = Visibility.Visible; Ui.Color(status, TextBlock.ForegroundProperty, "Muted");
        state.Visibility = Visibility.Visible; output.Visibility = Visibility.Collapsed;
        status.Text = Ui.L("正在改写… 取消会中止请求，原文不变。", "Rewriting… Cancel stops the request; source unchanged.");
        try
        {
            await controller.ValidateTarget(target);
            if (preferences.Provider != controller.Preferences.Provider || preferences.ActiveProviderId != controller.Preferences.ActiveProviderId) throw new InvalidOperationException(Ui.L("服务配置已变化，请重新打开改写窗口。", "Provider changed. Reopen the rewrite panel."));
            var key = controller.Secrets.Read();
            if (string.IsNullOrWhiteSpace(key)) throw new InvalidOperationException(Ui.L("请先在设置中保存 API Key。", "Save an API key in Settings first."));
            using var client = new RewriteClient();
            var result = await client.RewriteAsync(preferences.Provider, key, source, skill, controller.Lexicon, cancellation.Token);
            if (cancellation.IsCancellationRequested) return;
            output.Text = result; output.Visibility = Visibility.Visible;
            status.Text = result == source ? Ui.L("原文已很自然，无需改写。", "Already natural. No changes needed.")
                : target.CanWrite ? Ui.L("确认后将再次校验原文并替换。", "Replace rechecks the original before writing.")
                : Ui.L("此目标只读；可复制结果，不能自动替换。", "Read-only target. Copy the result; automatic replacement is unavailable.");
            BuildRemember(result);
        }
        catch (OperationCanceledException) { status.Text = Ui.L("已取消或超时，原文不变。", "Cancelled or timed out; source unchanged."); }
        catch (Exception error)
        {
            status.Text = error is InvalidOperationException ? error.Message : Ui.L("改写失败，请检查服务配置后重试。原文未修改。", "Rewrite failed. Check your provider and retry. Source unchanged.");
            Ui.Color(status, TextBlock.ForegroundProperty, "Danger");
        }
        finally { requesting = false; progress.Visibility = Visibility.Collapsed; if (!cancellation.IsCancellationRequested) RefreshActions(); }
    }
    private void RefreshActions(bool allDisabled = false)
    {
        var hasResult = output.Text.Length > 0;
        send.Visibility = requested ? Visibility.Collapsed : Visibility.Visible;
        send.IsEnabled = !allDisabled && !requesting;
        apply.Visibility = hasResult && output.Text != source ? Visibility.Visible : Visibility.Collapsed;
        apply.IsEnabled = !allDisabled && !requesting && target.CanWrite;
        copy.Visibility = hasResult ? Visibility.Visible : Visibility.Collapsed; copy.IsEnabled = !allDisabled && !requesting;
        retry.Visibility = requested ? Visibility.Visible : Visibility.Collapsed; retry.IsEnabled = !allDisabled && !requesting;
    }
    private void BuildRemember(string result)
    {
        remember.Children.Clear(); if (result == source) return;
        var pairs = RewriteDiff.Pairs(source, result).Where(p => p.Candidate() != null).ToArray();
        if (pairs.Length == 0)
        {
            remember.Children.Add(Ui.Label(Ui.L("本次改写无法拆成简短词条，请在个人词库中手动添加。", "No short word pairs to learn. Add a lexicon entry manually."), 10, "Muted")); return;
        }
        var list = new StackPanel();
        var options = new List<(CheckBox Check, RewritePair Pair)>();
        foreach (var pair in pairs)
        {
            var check = new CheckBox { Content = pair.From + " → " + (pair.To.Length == 0 ? Ui.L("（删除）", "(Delete)") : pair.To), IsChecked = false, Margin = new Thickness(0, 4, 0, 4), FontSize = 11 };
            options.Add((check, pair)); list.Children.Add(check);
        }
        Button? add = null;
        add = Ui.Button(Ui.L("加入词库", "Add to lexicon"), () =>
        {
            if (saved || applying) return;
            try
            {
                var entries = options.Where(p => p.Check.IsChecked == true).Select(p => p.Pair.Candidate()!).ToArray();
                if (entries.Length == 0) return;
                controller.SaveLexicon(controller.Lexicon.Concat(entries).Distinct().ToArray());
                saved = true; add!.Content = Ui.L("已加入词库", "Added to lexicon"); add.IsEnabled = false;
            }
            catch (Exception error) { Ui.Error(error); }
        }, "RememberRewrite");
        add.HorizontalAlignment = HorizontalAlignment.Right; add.Margin = new Thickness(0, 8, 0, 0);
        Ui.EnableForSelection(add, options.Select(option => option.Check).ToArray(), () => !saved);
        list.Children.Add(add);
        var container = new Border { CornerRadius = new CornerRadius(8), Padding = new Thickness(10), Child = list };
        Ui.Color(container, Border.BackgroundProperty, "Sidebar");
        var expander = new Expander { Header = Ui.L($"记住改法（{pairs.Length}）", $"Remember changes ({pairs.Length})"), Content = container };
        AutomationProperties.SetAutomationId(expander, "RememberChanges"); remember.Children.Add(expander);
    }
}
