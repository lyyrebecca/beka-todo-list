using System.Windows;
using System.Windows.Media;
using LiquidTodo.Core;
using LiquidTodo.Windows.Services;

namespace LiquidTodo.Windows;

// Resolution-independent material, not a screenshot with baked-in text. Its
// opaque quiet reading plane prevents the old console/desktop ghosting, while
// narrow refracted edges and broad low-intensity sheen provide visual glass depth.
public sealed class LiquidGlassSurface : FrameworkElement
{
    private bool _dark;
    public void SetTheme(bool dark) { _dark = dark; InvalidateVisual(); }
    protected override void OnRender(DrawingContext dc)
    {
        base.OnRender(dc);
        var w = ActualWidth; var h = ActualHeight;
        if (w <= 0 || h <= 0) return;
        var p = AppearancePalette.For(_dark);
        var bounds = new Rect(0, 0, w, h);
        dc.PushClip(new RectangleGeometry(bounds, 22, 22));
        dc.DrawRoundedRectangle(Gradient(p.FillTop, p.FillBottom), null, bounds, 22, 22);
        // A thin warm-lilac glint, never a bright white or black rectangular rim.
        if (_dark)
        {
            var rim = new LinearGradientBrush();
            rim.StartPoint = new Point(0, 0); rim.EndPoint = new Point(1, 1);
            rim.GradientStops = new GradientStopCollection {
                new(WindowsThemeService.ColorFrom("B8A2CF"), 0),
                new(WindowsThemeService.ColorFrom("766087"), .2),
                new(WindowsThemeService.ColorFrom("A38ABD"), .55),
                new(WindowsThemeService.ColorFrom("675079"), .75),
                new(WindowsThemeService.ColorFrom("A991BC"), 1) };
            dc.DrawRoundedRectangle(null, new Pen(rim, 2.2), new Rect(1.1, 1.1, Math.Max(0, w-2.2), Math.Max(0, h-2.2)), 21, 21);
            dc.DrawRoundedRectangle(null, new Pen(new SolidColorBrush(Color.FromArgb(65, 225, 205, 248)), .7), new Rect(3, 3, Math.Max(0,w-6), Math.Max(0,h-6)), 19, 19);
        }
        else
            dc.DrawRoundedRectangle(null, new Pen(new SolidColorBrush(WindowsThemeService.ColorFrom("D7C7ED")), .8), new Rect(.4, .4, Math.Max(0,w-.8), Math.Max(0,h-.8)), 21.6, 21.6);
        // Highlights stay outside the text plane: no white overlay beneath labels.
        dc.DrawRoundedRectangle(null, new Pen(new SolidColorBrush(Color.FromArgb(_dark ? (byte)50 : (byte)22, 218, 195, 242)), .8), new Rect(5, 5, Math.Max(0,w-10), Math.Max(0,h-10)), 17, 17);
        dc.Pop();
    }
    private static LinearGradientBrush Gradient(string a, string b) => new(
        WindowsThemeService.ColorFrom(a), WindowsThemeService.ColorFrom(b), new Point(0,0), new Point(1,1));
}
