using System;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Documents;

namespace DeAI.Fixture;

public static class Program
{
    public const string Sample = "😀 说白了，我们需要认真检查。\r\nIt is worth noting that we delve into details.";
    [STAThread]
    public static void Main()
    {
        var app = new Application();
        var text = new TextBox { Text = Sample, AcceptsReturn = true, TextWrapping = TextWrapping.Wrap, FontSize = 22, Height = 170 };
        AutomationProperties.SetAutomationId(text, "PlainText");
        text.Select(3, 4);
        var password = new PasswordBox { Password = "synthetic", Height = 30 };
        AutomationProperties.SetAutomationId(password, "Password");
        var rich = new RichTextBox { Document = new FlowDocument(new Paragraph(new Run(Sample))), Height = 130 };
        AutomationProperties.SetAutomationId(rich, "RichText");
        var reset = new Button { Content = "Reset synthetic text", Height = 35 };
        AutomationProperties.SetAutomationId(reset, "Reset");
        reset.Click += (_, _) => { text.Text = Sample; text.Select(3, 4); text.Focus(); };
        var mutate = new Button { Content = "Change source", Height = 35 };
        AutomationProperties.SetAutomationId(mutate, "Mutate");
        mutate.Click += (_, _) => text.Text += " changed";
        var panel = new StackPanel { Margin = new Thickness(20) };
        panel.Children.Add(new TextBlock { Text = "DeAI synthetic UI Automation fixture", FontSize = 20 });
        panel.Children.Add(text); panel.Children.Add(reset); panel.Children.Add(mutate); panel.Children.Add(password); panel.Children.Add(rich);
        var window = new Window { Title = "DeAI UIA Fixture", Width = 680, Height = 530, Content = panel };
        window.Loaded += (_, _) => text.Focus();
        app.Run(window);
    }
}
