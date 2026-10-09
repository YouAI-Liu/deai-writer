using System;
using System.Linq;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;
using System.Windows.Threading;
using DeAI.App;
using static DeAI.Tests.Program;

namespace DeAI.Tests;

internal static class LayoutTests
{
    public static void Run()
    {
        var thread = new Thread(() =>
        {
            var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
            try
            {
                app.Resources.MergedDictionaries.Add(new ResourceDictionary { Source = new Uri("/DeAI.Tests;component/Design.xaml", UriKind.Relative) });
                foreach (var dark in new[] { false, true })
                {
                    Ui.RefreshTheme(dark);
                    var theme = dark ? "dark" : "light";
                    Check(theme + " learn action requires a selection and stays disabled after saving", () =>
                    {
                        var choices = new[] { new CheckBox(), new CheckBox() };
                        var action = Ui.Button("Add to lexicon", () => { });
                        var saved = false;
                        Ui.EnableForSelection(action, choices, () => !saved);
                        Equal(false, action.IsEnabled);
                        choices[0].IsChecked = true; Equal(true, action.IsEnabled);
                        choices[1].IsChecked = true; choices[0].IsChecked = false; Equal(true, action.IsEnabled);
                        choices[1].IsChecked = false; Equal(false, action.IsEnabled);
                        choices[0].IsChecked = true; saved = true; action.IsEnabled = false;
                        choices[0].IsChecked = false; choices[0].IsChecked = true; Equal(false, action.IsEnabled);
                    });
                    Check(theme + " long selected names have a complete tooltip", () =>
                    {
                        var name = new string('x', 100);
                        var combo = new ComboBox { ItemsSource = new[] { new { Name = name } }, DisplayMemberPath = "Name", SelectedIndex = 0 };
                        Ui.SelectedTooltip(combo, "Name");
                        Layout(combo, 166);
                        Equal(name, combo.ToolTip as string);
                    });
                    Check(theme + " pills have circular caps and natural button width", () =>
                    {
                        var button = Ui.Button("Add entry", () => { });
                        var count = Ui.Label("0/200");
                        var row = Ui.Row(button, count);
                        Layout(row, 443);
                        Require(button.ActualWidth < 150, "Button stretched to fill the row");
                        var border = (Border)button.Template.FindName("Body", button);
                        Require(Math.Abs(border.CornerRadius.TopLeft - border.ActualHeight / 2) < 0.01, "Pill caps are elliptical");
                        Require(count.TransformToAncestor(row).Transform(new Point()).X > button.ActualWidth + 12, "Counter overlaps button");
                        var primary = Ui.Button("Send", () => { }, style: "PrimaryButton");
                        Layout(primary, 200);
                        var text = Find<TextBlock>(primary);
                        Equal(Colors.White, ((SolidColorBrush)text.Foreground).Color);
                        Equal(12.0, text.FontSize);
                    });
                    Check(theme + " icon buttons remain square and respect content alignment", () =>
                    {
                        var button = Ui.Icon("×", "Close", () => { });
                        Layout(button, 100);
                        Require(Math.Abs(button.ActualWidth - button.ActualHeight) < 0.01, "Icon button is distorted");
                        var flat = Ui.Button("Menu", () => { }, style: "FlatButton");
                        flat.HorizontalContentAlignment = HorizontalAlignment.Stretch;
                        Layout(flat, 260);
                        Equal(HorizontalAlignment.Stretch, Find<ContentPresenter>(flat).HorizontalAlignment);
                    });
                    Check(theme + " long remember labels wrap before the switch", () =>
                    {
                        var check = new CheckBox { Content = new string('甲', 20) + " → " + new string('春', 20), FontSize = 11 };
                        Layout(check, 354);
                        var text = Find<TextBlock>(check);
                        var track = (Border)check.Template.FindName("Track", check);
                        var label = text.TransformToAncestor(check).TransformBounds(new Rect(text.RenderSize));
                        var toggle = track.TransformToAncestor(check).TransformBounds(new Rect(track.RenderSize));
                        Equal(TextWrapping.Wrap, text.TextWrapping);
                        Require(text.ActualHeight > 23, "Long label did not wrap");
                        Require(label.Right + 10 <= toggle.Left, "Label overlaps switch");
                    });
                    Check(theme + " settings tab headers fit both languages", () =>
                    {
                        foreach (var names in new[] { new[] { "检查", "下划线外观", "AI 改写", "个人" }, new[] { "Check", "Underlines", "AI rewrite", "Personal" } })
                        {
                            var tabs = new TabControl();
                            foreach (var name in names)
                            {
                                var header = new StackPanel();
                                header.Children.Add(Ui.Label("U", 16));
                                var label = Ui.Label(name, 11); label.Margin = new Thickness(0, 3, 0, 0); header.Children.Add(label);
                                tabs.Items.Add(new TabItem { Header = header, Content = new Border() });
                            }
                            Layout(tabs, 560, 400);
                            var top = Find<TabPanel>(tabs);
                            foreach (TabItem tab in tabs.Items)
                            {
                                var bounds = tab.TransformToAncestor(top).TransformBounds(new Rect(tab.RenderSize));
                                Require(bounds.Top >= 0 && bounds.Bottom <= top.ActualHeight + 0.01, "Tab header was clipped");
                            }
                            Require(top.ActualHeight >= 60, "Tab strip is undersized");
                        }
                    });
                    Check(theme + " short rewrite text grows only to its scroll limit", () =>
                    {
                        var text = Ui.Text("A short result.", multiline: true);
                        text.MinHeight = 20; text.MaxHeight = 160; text.Padding = new Thickness(0);
                        Layout(text, 376);
                        Require(text.ActualHeight < 40, "Short result has excessive empty space");
                        text.Text = string.Join("\n", Enumerable.Repeat("A synthetic line.", 40));
                        Layout(text, 376);
                        Require(text.ActualHeight <= 160, "Text exceeded the scroll limit");
                    });
                    Check(theme + " wrapped action rows have horizontal and vertical gaps", () =>
                    {
                        var first = Ui.Button("Import file", () => { });
                        var second = Ui.Button("Import folder", () => { });
                        var actions = Ui.Actions(first, second);
                        Layout(actions, 120);
                        var a = first.TransformToAncestor(actions).TransformBounds(new Rect(first.RenderSize));
                        var b = second.TransformToAncestor(actions).TransformBounds(new Rect(second.RenderSize));
                        Require(b.Top >= a.Bottom + 8, "Wrapped controls touch vertically");
                    });
                    Check(theme + " long panels pin header and actions within the viewport", () =>
                    {
                        var window = new Window();
                        var body = Ui.Panel(window, 420);
                        for (var i = 0; i < 10; i++) body.Children.Add(new CheckBox { Content = new string('甲', 20) + " → " + new string('春', 20), Margin = new Thickness(0, 4, 0, 4), FontSize = 11 });
                        var header = Ui.Title("AI rewrite");
                        var footer = Ui.Actions(Ui.Button("Replace", () => { }), Ui.Button("Copy", () => { }), Ui.Button("Retry", () => { }), Ui.Button("Cancel", () => { }));
                        Ui.PinPanel(window, body, header, footer);
                        var border = (Border)window.Content;
                        border.MaxHeight = 320;
                        Layout(border, 460);
                        var bounds = footer.TransformToAncestor(border).TransformBounds(new Rect(footer.RenderSize));
                        Require(bounds.Bottom <= border.ActualHeight + 0.01, "Actions extend beyond the panel");
                        var scroll = Find<ScrollViewer>(border);
                        Require(scroll.ActualHeight < body.DesiredSize.Height, "Long content has no constrained viewport");
                        window.Close();
                    });
                }
            }
            catch (Exception error) { Check("WPF layout test harness", () => throw new InvalidOperationException("Layout harness failed", error)); }
            finally { app.Shutdown(); }
        });
        thread.SetApartmentState(ApartmentState.STA); thread.Start(); thread.Join();
    }
    private static void Layout(FrameworkElement element, double width, double height = double.PositiveInfinity)
    {
        element.Measure(new Size(width, height));
        element.Arrange(new Rect(0, 0, width, double.IsPositiveInfinity(height) ? element.DesiredSize.Height : height));
        element.UpdateLayout();
        Dispatcher.CurrentDispatcher.Invoke(() => { }, DispatcherPriority.Loaded);
    }
    private static T Find<T>(DependencyObject root) where T : DependencyObject
    {
        for (var i = 0; i < VisualTreeHelper.GetChildrenCount(root); i++)
        {
            var child = VisualTreeHelper.GetChild(root, i);
            if (child is T match) return match;
            try { return Find<T>(child); } catch (InvalidOperationException) { }
        }
        throw new InvalidOperationException("Missing visual " + typeof(T).Name);
    }
    private static void Require(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
}
