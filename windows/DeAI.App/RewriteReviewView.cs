using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;

namespace DeAI.App;

internal sealed class RewriteReviewView(RewriteReviewState model, Action changed) : StackPanel
{
    public void Refresh()
    {
        Children.Clear();
        var review = model.Review;
        Visibility = review?.Edits.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
        if (review == null || review.Edits.Count == 0) { changed(); return; }
        var count = Ui.Label("", 11, "Muted");
        AutomationProperties.SetAutomationId(count, "ReviewCount");
        var choices = new List<CheckBox>();
        var syncing = false;
        void Update()
        {
            count.Text = Ui.L($"{review.Edits.Count} 项变更 · 已采用 {model.AcceptedCount} 项", $"{review.Edits.Count} changes · {model.AcceptedCount} accepted");
            changed();
        }
        void SelectAll(bool use)
        {
            if (model.Review?.Id != review.Id) return;
            model.SelectAll(use);
            syncing = true;
            foreach (var choice in choices) choice.IsChecked = use;
            syncing = false; Update();
        }
        Children.Add(count);
        var actions = Ui.Actions(
            Ui.Button(Ui.L("使用全部", "Use all"), () => SelectAll(true), "UseAllEdits", "FlatButton"),
            Ui.Button(Ui.L("保留全部", "Keep all"), () => SelectAll(false), "KeepAllEdits", "FlatButton"));
        actions.Margin = new Thickness(0, 4, 0, 6); Children.Add(actions);
        if (review.IsWholePassage)
            Children.Add(Ui.Label(Ui.L("变更较多，按整段审阅。", "Many changes; review as one passage."), 10, "Muted"));
        var list = new StackPanel();
        foreach (var edit in review.Edits)
        {
            var check = new CheckBox
            {
                Content = VisibleText(edit.Original) + " → " + VisibleText(edit.Revised),
                IsChecked = model.IsAccepted(edit.Id),
                FontSize = 11,
                Margin = new Thickness(0, 4, 0, 4)
            };
            AutomationProperties.SetAutomationId(check, "ReviewEdit" + edit.Id);
            AutomationProperties.SetName(check, Ui.L("采用变更：", "Use change: ") + (string)check.Content);
            check.Checked += (_, _) => Select(true);
            check.Unchecked += (_, _) => Select(false);
            void Select(bool use)
            {
                if (syncing || model.Review?.Id != review.Id) return;
                model.Select(edit.Id, use, review.Id); Update();
            }
            choices.Add(check); list.Children.Add(check);
        }
        var scroll = new ScrollViewer
        {
            Content = list,
            MaxHeight = 140,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled
        };
        AutomationProperties.SetAutomationId(scroll, "ReviewChanges");
        Children.Add(scroll); Update();
    }
    private static string VisibleText(string text) => text.Length == 0 ? Ui.L("（无）", "(None)")
        : text.Replace("\r\n", "↵").Replace("\r", "↵").Replace("\n", "↵").Replace("\t", "⇥").Replace(" ", "·");
}
