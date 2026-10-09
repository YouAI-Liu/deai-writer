using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Automation;

namespace DeAI.App;

internal static class Ui
{
    public static readonly Brush Ink = new SolidColorBrush(Color.FromRgb(32, 43, 55));
    public static readonly Brush Accent = new SolidColorBrush(Color.FromRgb(19, 109, 97));
    public static string Language = "zh";
    public static string L(string zh, string en) => Language == "en" ? en : zh;
    public static void Style(Window window)
    {
        window.FontFamily = new FontFamily("Segoe UI"); window.FontSize = 14;
        window.Foreground = Ink; window.Background = new SolidColorBrush(Color.FromRgb(247, 249, 250));
        window.WindowStartupLocation = WindowStartupLocation.CenterScreen;
    }
    public static TextBlock Label(string text, double size = 14) => new() { Text = text, TextWrapping = TextWrapping.Wrap, FontSize = size, Margin = new Thickness(0, 5, 0, 8) };
    public static Button Button(string label, Action action, string? id = null)
    {
        var button = new Button { Content = label, Padding = new Thickness(12, 7, 12, 7), Margin = new Thickness(0, 4, 8, 4), MinHeight = 34 };
        button.Click += (_, _) => action(); if (id != null) AutomationProperties.SetAutomationId(button, id); return button;
    }
    public static TextBox Text(string value, string? id = null, bool multiline = false)
    {
        var text = new TextBox
        {
            Text = value,
            Margin = new Thickness(0, 2, 0, 10),
            Padding = new Thickness(8),
            AcceptsReturn = multiline,
            TextWrapping = multiline ? TextWrapping.Wrap : TextWrapping.NoWrap,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            MinHeight = multiline ? 130 : 34
        };
        if (id != null) AutomationProperties.SetAutomationId(text, id); return text;
    }
    public static void Error(Exception error) => MessageBox.Show(error is InvalidOperationException ? error.Message : L("操作失败；原文未主动覆盖。请重试或检查配置/目标权限。", "Operation failed. Check configuration/target permissions and retry."), "DeAI", MessageBoxButton.OK, MessageBoxImage.Warning);
}
