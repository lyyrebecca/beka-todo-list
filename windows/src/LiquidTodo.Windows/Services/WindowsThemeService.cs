using Microsoft.Win32;
using System.Windows.Media;

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
        var resources = System.Windows.Application.Current.Resources;
        resources["Ink"] = new SolidColorBrush(ColorFrom(dark ? "FFF4F0FF" : "FF29213B"));
        resources["Muted"] = new SolidColorBrush(ColorFrom(dark ? "FFC4B8E8" : "FF786F8A"));
        resources["SecondaryInk"] = new SolidColorBrush(ColorFrom(dark ? "FFD8D0EC" : "FF625B73"));
        resources["Purple"] = new SolidColorBrush(ColorFrom(dark ? "FFB3A7FF" : "FF7B68EE"));
        resources["Urgent"] = new SolidColorBrush(ColorFrom(dark ? "FFFF8296" : "FFCD5A70"));
        resources["Important"] = new SolidColorBrush(ColorFrom(dark ? "FFFFD982" : "FFB88618"));
        resources["GlassTint"] = new SolidColorBrush(ColorFrom(dark ? "C91E1831" : "AFFFFFFF"));
        resources["RowFill"] = new SolidColorBrush(ColorFrom(dark ? "664A3D6B" : "88FFFFFF"));
        resources["GlassBorder"] = new SolidColorBrush(ColorFrom(dark ? "55FFFFFF" : "AFFFFFFF"));
        resources["Surface"] = new SolidColorBrush(ColorFrom(dark ? "FF211B32" : "FFFAF8FF"));
    }

    private static Color ColorFrom(string value) => (Color)ColorConverter.ConvertFromString("#" + value)!;
}
