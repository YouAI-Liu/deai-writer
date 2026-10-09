using System;
using System.Windows;
using System.Windows.Media;

namespace DeAI.App;

internal sealed class UnderlineView : FrameworkElement
{
    public UnderlineView() => SetResourceReference(TagProperty, "TextBrush");
    protected override void OnPropertyChanged(DependencyPropertyChangedEventArgs e)
    {
        base.OnPropertyChanged(e);
        if (e.Property == TagProperty) InvalidateVisual();
    }
    public UnderlineAppearance Appearance { get; set; } = new();
    public string Category { get; set; } = "grammar";
    public byte Tier { get; set; }
    protected override void OnRender(DrawingContext context)
    {
        base.OnRender(context);
        var style = Appearance.For(Ui.CategoryKey(Category));
        var color = style.Color.Length == 0 ? ((SolidColorBrush)Ui.Brush(Ui.CategoryKey(Category))).Color : (Color)ColorConverter.ConvertFromString(style.Color);
        var brush = new SolidColorBrush(color) { Opacity = Appearance.Opacity };
        var pen = new Pen(brush, Appearance.Thickness);
        var shape = Tier >= 3 && Appearance.DimLowConfidence ? "dashed" : style.Shape;
        var y = ActualHeight - 8 + Appearance.Offset;
        if (Appearance.HighlightFill) context.DrawRectangle(new SolidColorBrush(color) { Opacity = Appearance.Opacity * 0.12 }, null, new Rect(0, 0, ActualWidth, Math.Max(0, ActualHeight - 8)));
        if (shape == "dashed") pen.DashStyle = DashStyles.Dash;
        if (shape == "dotted") { pen.DashStyle = DashStyles.Dot; pen.StartLineCap = pen.EndLineCap = PenLineCap.Round; }
        if (shape != "wavy") { context.DrawLine(pen, new Point(0, y), new Point(ActualWidth, y)); return; }
        var geometry = new StreamGeometry();
        using (var path = geometry.Open())
        {
            path.BeginFigure(new Point(0, y), false, false);
            for (var x = 0.0; x < ActualWidth; x += 4)
                path.QuadraticBezierTo(new Point(Math.Min(x + 2, ActualWidth), y + ((int)(x / 4) % 2 == 0 ? -2 : 2)), new Point(Math.Min(x + 4, ActualWidth), y), true, false);
        }
        context.DrawGeometry(null, pen, geometry);
    }
}
