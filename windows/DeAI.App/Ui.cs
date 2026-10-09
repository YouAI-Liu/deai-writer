using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Automation;
using System.Collections.Generic;
using System.Windows.Input;
using System.Windows.Media.Effects;
using Microsoft.Win32;

namespace DeAI.App;

internal static class Ui
{
    public const double SettingsWidth = 560, SettingsHeight = 660, CardWidth = 260, RewriteWidth = 420;
    public static Brush Ink => Brush("Text");
    public static Brush Accent => Brush("Accent");
    public static bool Dark { get; private set; }
    public static string Language = "zh";
    public static string L(string zh, string en) => Language == "en" ? en : zh;
    public static void Initialize()
    {
        Application.Current.Resources.MergedDictionaries.Add(new ResourceDictionary { Source = new Uri("/DeAI;component/Design.xaml", UriKind.Relative) });
        RefreshTheme();
        SystemEvents.UserPreferenceChanged += ThemeChanged;
        Application.Current.Exit += (_, _) => SystemEvents.UserPreferenceChanged -= ThemeChanged;
    }
    private static void ThemeChanged(object sender, UserPreferenceChangedEventArgs args) => Application.Current.Dispatcher.BeginInvoke(new Action(() => RefreshTheme()));
    internal static void RefreshTheme(bool? dark = null)
    {
        using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
        Dark = dark ?? (key?.GetValue("AppsUseLightTheme") is int value && value == 0);
        var colors = new Dictionary<string, (string Light, string Dark)>
        {
            ["Background"] = ("#FAF9F5", "#262624"),
            ["Sidebar"] = ("#F5F4ED", "#1F1E1D"),
            ["Track"] = ("#F0EEE6", "#141413"),
            ["Surface"] = ("#FFFFFF", "#30302E"),
            ["Border"] = ("#261F1E1D", "#26DEDCD1"),
            ["Text"] = ("#141413", "#FAF9F5"),
            ["SecondaryText"] = ("#3D3D3A", "#C2C0B6"),
            ["Muted"] = ("#73726C", "#9C9A92"),
            ["Accent"] = ("#C6613F", "#D97757"),
            ["Danger"] = ("#B53333", "#DD5353"),
            ["InactiveTrack"] = ("#26141413", "#26FAF9F5"),
            ["AcceptGreen"] = ("#33C759", "#33C759"),
            ["grammar"] = ("#AA6970", "#C98D93"),
            ["ai_tone_zh"] = ("#8D769F", "#B69FC8"),
            ["ai_tone_en"] = ("#5E859F", "#8FB3CB"),
            ["markdown"] = ("#82847F", "#AFB1AB"),
            ["personal"] = ("#3E8A80", "#7FBFB5")
        };
        foreach (var (name, pair) in colors)
        {
            var color = (Color)ColorConverter.ConvertFromString(Dark ? pair.Dark : pair.Light);
            if (SystemParameters.HighContrast)
                color = name is "Background" or "Sidebar" or "Track" or "Surface" ? SystemColors.WindowColor
                    : name is "Accent" or "AcceptGreen" ? SystemColors.HighlightColor : SystemColors.WindowTextColor;
            var brush = new SolidColorBrush(color); brush.Freeze();
            Application.Current.Resources[name + "Brush"] = brush;
        }
    }
    public static Brush Brush(string name) => (Brush)Application.Current.FindResource(name + "Brush");
    public static void Color(FrameworkElement element, DependencyProperty property, string name) => element.SetResourceReference(property, name + "Brush");
    public static void Style(Window window)
    {
        window.FontFamily = new FontFamily("Segoe UI, Microsoft YaHei UI"); window.FontSize = 13;
        Color(window, Control.ForegroundProperty, "Text"); Color(window, Control.BackgroundProperty, "Background");
        window.UseLayoutRounding = true; window.SnapsToDevicePixels = true;
        window.WindowStartupLocation = WindowStartupLocation.CenterScreen;
    }
    public static TextBlock Label(string text, double size = 13, string color = "Text")
    {
        var label = new TextBlock { Text = text, TextWrapping = TextWrapping.Wrap, FontSize = size };
        Color(label, TextBlock.ForegroundProperty, color); return label;
    }
    public static TextBlock Title(string text, double size = 14)
    {
        var title = Label(text, size); title.FontFamily = new FontFamily("Georgia, Microsoft YaHei UI"); title.FontWeight = FontWeights.Medium; return title;
    }
    public static Button Button(string label, Action action, string? id = null, string? style = null)
    {
        var button = new Button { Content = label };
        if (style != null) button.Style = (Style)Application.Current.FindResource(style);
        button.Click += (_, _) => action(); AutomationProperties.SetName(button, label);
        if (id != null) AutomationProperties.SetAutomationId(button, id); return button;
    }
    public static Button Icon(string glyph, string label, Action action, string? id = null)
    {
        var button = Button(glyph, action, id, "IconButton"); button.ToolTip = label;
        AutomationProperties.SetName(button, label); return button;
    }
    public static StackPanel Panel(Window window, double width, double padding = 22)
    {
        Style(window); window.WindowStyle = WindowStyle.None; window.AllowsTransparency = true;
        window.Background = Brushes.Transparent; window.ResizeMode = ResizeMode.NoResize;
        window.SizeToContent = SizeToContent.Height; window.Width = width + 40;
        window.ShowInTaskbar = false; window.Topmost = true; window.ShowActivated = false;
        var content = new StackPanel { Margin = new Thickness(padding) };
        var border = new Border
        {
            Width = width,
            Margin = new Thickness(20),
            CornerRadius = new CornerRadius(12),
            BorderThickness = new Thickness(0.5),
            Child = content,
            Effect = new DropShadowEffect { BlurRadius = 18, ShadowDepth = 4, Opacity = 0.16 }
        };
        Color(border, Border.BackgroundProperty, "Background"); Color(border, Border.BorderBrushProperty, "Border");
        window.Content = border;
        window.PreviewKeyDown += (_, e) => { if (e.Key == Key.Escape) { window.Close(); e.Handled = true; } };
        return content;
    }
    public static Border Separator()
    {
        var line = new Border { Height = 0.5 }; Color(line, Border.BackgroundProperty, "Border"); return line;
    }
    public static StackPanel Section(StackPanel parent, string title)
    {
        var section = new StackPanel { Margin = new Thickness(0, 0, 0, 24) };
        var heading = Title(title); heading.Margin = new Thickness(0, 0, 0, 14); section.Children.Add(heading);
        var content = new StackPanel();
        var border = new Border { CornerRadius = new CornerRadius(12), BorderThickness = new Thickness(0.5), Padding = new Thickness(20), Child = content };
        Color(border, Border.BackgroundProperty, "Surface"); Color(border, Border.BorderBrushProperty, "Border");
        section.Children.Add(border); parent.Children.Add(section); return content;
    }
    public static Grid Row(FrameworkElement left, FrameworkElement right, double gap = 12)
    {
        var row = new Grid(); row.ColumnDefinitions.Add(new ColumnDefinition()); row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        left.VerticalAlignment = right.VerticalAlignment = VerticalAlignment.Center; right.Margin = new Thickness(gap, 0, 0, 0);
        row.Children.Add(left); Grid.SetColumn(right, 1); row.Children.Add(right); return row;
    }
    public static string Category(string category) => CategoryKey(category) switch
    {
        "grammar" => Ui.L("语法", "Grammar"),
        "ai_tone_zh" => Ui.L("中文 AI 腔", "Chinese AI tone"),
        "ai_tone_en" => Ui.L("英文 AI 腔", "English AI tone"),
        "markdown" => Ui.L("Markdown 残留", "Markdown"),
        "personal" => Ui.L("个人词库", "Personal lexicon"),
        _ => category
    };
    public static string CategoryKey(string category) => category switch
    {
        "AiToneZh" or "aiToneZh" or "ai_tone_zh" => "ai_tone_zh",
        "AiToneEn" or "aiToneEn" or "ai_tone_en" => "ai_tone_en",
        "Grammar" or "grammar" => "grammar",
        "Markdown" or "markdown" => "markdown",
        "Personal" or "personal" => "personal",
        _ => "Muted"
    };
    public static TextBox Text(string value, string? id = null, bool multiline = false)
    {
        var text = new TextBox
        {
            Text = value,
            Padding = new Thickness(12),
            AcceptsReturn = multiline,
            TextWrapping = multiline ? TextWrapping.Wrap : TextWrapping.NoWrap,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            MinHeight = multiline ? 80 : 34
        };
        if (id != null) AutomationProperties.SetAutomationId(text, id); return text;
    }
    public static void Error(Exception error) => MessageBox.Show(error is InvalidOperationException ? error.Message : L("操作失败；原文未主动覆盖。请重试或检查配置/目标权限。", "Operation failed. Check configuration/target permissions and retry."), "DeAI", MessageBoxButton.OK, MessageBoxImage.Warning);
}
