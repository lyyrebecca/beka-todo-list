using System.Windows;

namespace LiquidTodo.Windows.Services;

internal static class DesktopModeService
{
    public static void Apply(Window window, bool enabled)
    {
        window.Topmost = !enabled;
        NativeWindow.SetMousePassthrough(window, enabled);
    }
}
