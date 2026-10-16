using Microsoft.Win32;
using System.Windows.Media;
using LiquidTodo.Core;

namespace LiquidTodo.Windows.Services;

internal static class WindowsThemeService
{
    private const string PersonalizeKey = @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize";
    public static bool IsDarkMode()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(PersonalizeKey);
            return Convert.ToInt32(key?.GetValue("AppsUseLightTheme", 1)) == 0;
        }
        catch { return false; }
    }
    public static void ApplyResources(bool dark)
    {
        var p = AppearancePalette.For(dark);
        var resources = System.Windows.Application.Current.Resources;
        foreach (var (key, hex) in new[] {
            ("Ink", p.Ink), ("Muted", p.Muted), ("SecondaryInk", p.SecondaryInk),
            ("Purple", p.Accent), ("AccentText", p.AccentText), ("AccentInk", p.AccentInk), ("Urgent", p.Urgent),
            ("Important", p.Important), ("RowFill", p.RowFill), ("Surface", p.Surface),
            ("InputFill", p.InputFill), ("InputBorder", p.InputBorder) })
        {
            var brush = new SolidColorBrush(ColorFrom(hex)); brush.Freeze(); resources[key] = brush;
        }
    }
    internal static Color ColorFrom(string hex) => (Color)ColorConverter.ConvertFromString("#" + hex)!;
}
