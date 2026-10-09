using System;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Automation;
using DeAI.Automation;

namespace DeAI.App;

internal sealed class RewriteWindow : Window
{
    private readonly CancellationTokenSource cancellation = new();
    public RewriteWindow(Controller controller, TextTarget target, TextSpan scope, Skill skill)
    {
        Title = "DeAI — " + Ui.L("AI 改写预览", "AI rewrite preview"); Width = 780; Height = 620; MinWidth = 600; MinHeight = 520; Ui.Style(this);
        var preferences = controller.Preferences; var source = target.Original[scope.Start..scope.End];
        var panel = new DockPanel { Margin = new Thickness(24) }; var header = new StackPanel();
        header.Children.Add(Ui.Label(Ui.L("改写前先确认", "Review before rewriting"), 24));
        header.Children.Add(Ui.Label(RewriteClient.Endpoint(preferences.Provider).Host + " · " + preferences.Provider.Model + " · " + skill.Name));
        header.Children.Add(Ui.Label(Ui.L("点击“发送并改写”会发送以下原文、所选 Skill 和个人词库到该服务。不会发送整个控件的其他文本；建议需再次确认才能写回。", "Send transmits the source below, selected Skill and personal lexicon to this provider. Other target text is not sent. Applying requires another confirmation.")));
        DockPanel.SetDock(header, Dock.Top); panel.Children.Add(header);
        var footer = new StackPanel(); var status = Ui.Label(""); footer.Children.Add(status); var actions = new WrapPanel();
        var output = Ui.Text("", "RewriteOutput", true); output.IsReadOnly = true;
        var apply = Ui.Button(Ui.L("接受并安全写回", "Accept and apply"), async () => { if (await controller.Apply(target, scope.Start, scope.End, output.Text)) Close(); }, "AcceptRewrite"); apply.IsEnabled = false;
        Button? send = null;
        send = Ui.Button(Ui.L("发送并改写", "Send and rewrite"), async () =>
        {
            send!.IsEnabled = false;
            try
            {
                if (preferences.Provider != controller.Preferences.Provider) throw new InvalidOperationException("服务配置已变化，请重新打开改写窗口。");
                await controller.ValidateTarget(target);
                var key = controller.Secrets.Read(); if (string.IsNullOrWhiteSpace(key)) throw new InvalidOperationException(Ui.L("请先在设置中保存 API Key。", "Save an API key in Settings first."));
                status.Text = Ui.L("正在请求；取消会中止请求，原文不变。", "Requesting; Cancel stops the request without changing the source.");
                using var client = new RewriteClient();
                var result = await client.RewriteAsync(preferences.Provider, key, source, skill, controller.Lexicon, cancellation.Token);
                if (cancellation.IsCancellationRequested) return;
                output.Text = result; apply.IsEnabled = target.CanWrite;
                status.Text = target.CanWrite ? Ui.L("请对照左右原文/结果；确认后写回会再次校验原文。", "Compare original and result. Apply rechecks the source.") : Ui.L("此目标只读；只能手动复制结果。", "Read-only target; copy the result manually.");
            }
            catch (OperationCanceledException) { status.Text = Ui.L("已取消或超时，原文不变。", "Cancelled/timed out; source unchanged."); }
            catch (Exception error) { Ui.Error(error); }
            finally { if (!cancellation.IsCancellationRequested) send.IsEnabled = true; }
        }, "SendRewrite");
        actions.Children.Add(send); actions.Children.Add(apply);
        actions.Children.Add(Ui.Button(Ui.L("复制结果", "Copy result"), () => { if (output.Text.Length > 0) Clipboard.SetText(output.Text); }, "CopyRewrite"));
        actions.Children.Add(Ui.Button(Ui.L("取消", "Cancel"), Close, "CancelRewrite")); footer.Children.Add(actions);
        DockPanel.SetDock(footer, Dock.Bottom); panel.Children.Add(footer);
        var grid = new Grid(); grid.ColumnDefinitions.Add(new ColumnDefinition()); grid.ColumnDefinitions.Add(new ColumnDefinition());
        var left = new StackPanel { Margin = new Thickness(0, 0, 12, 0) }; left.Children.Add(Ui.Label(Ui.L("原文", "Original")));
        var original = Ui.Text(source, "RewriteOriginal", true); original.IsReadOnly = true; original.Height = 260; left.Children.Add(original);
        var right = new StackPanel(); right.Children.Add(Ui.Label(Ui.L("改写结果", "Result"))); output.Height = 260; right.Children.Add(output);
        grid.Children.Add(left); Grid.SetColumn(right, 1); grid.Children.Add(right); panel.Children.Add(grid); Content = panel;
        Closed += (_, _) => cancellation.Cancel();
    }
}
