using LiquidTodo.Core;
using Xunit;

namespace LiquidTodo.Windows.Tests;
public class AppearanceTests
{
    [Theory]
    [InlineData(false)] [InlineData(true)]
    public void Small_text_remains_readable_on_both_day_and_night_surfaces(bool dark)
    {
        var p = AppearancePalette.For(dark);
        foreach (var background in new[] { p.FillTop, p.FillBottom, p.RowFill })
        foreach (var foreground in new[] { p.Ink, p.Muted, p.SecondaryInk })
            Assert.True(Contrast(foreground, background) >= 4.5, $"{p.Name}: {foreground}/{background}");
        foreach (var foreground in new[] { p.AccentText, p.Important, p.Urgent })
            Assert.True(Contrast(foreground, p.RowFill) >= 4.5, $"{p.Name} row: {foreground}/{p.RowFill}");
        Assert.True(Contrast(p.AccentInk, p.Accent) >= 4.5);
    }
    [Fact]
    public void Orb_has_the_correct_native_Chinese_character()
    {
        Assert.Equal("\u5E72", AppearancePalette.OrbGlyph);
        Assert.Single(AppearancePalette.OrbGlyph);
        Assert.NotEqual("于", AppearancePalette.OrbGlyph);
        Assert.NotEqual("千", AppearancePalette.OrbGlyph);
    }
    [Fact]
    public void Both_materials_are_purple_and_not_white_reading_planes()
    {
        foreach (var p in new[] { AppearancePalette.Day, AppearancePalette.Night })
        foreach (var hex in new[] { p.FillTop, p.FillBottom, p.RowFill })
        {
            var (r,g,b) = Rgb(hex);
            Assert.True(b > g && r > g); Assert.True(g < .85);
        }
    }
    private static (double R,double G,double B) Rgb(string hex) =>
        (Convert.ToInt32(hex[..2],16)/255d, Convert.ToInt32(hex[2..4],16)/255d, Convert.ToInt32(hex[4..6],16)/255d);
    private static double Luminance(string hex)
    {
        static double Channel(double c) => c <= .04045 ? c/12.92 : Math.Pow((c+.055)/1.055,2.4);
        var (r,g,b)=Rgb(hex); return .2126*Channel(r)+.7152*Channel(g)+.0722*Channel(b);
    }
    private static double Contrast(string a,string b)
    {
        var x=Luminance(a); var y=Luminance(b); return (Math.Max(x,y)+.05)/(Math.Min(x,y)+.05);
    }
}
