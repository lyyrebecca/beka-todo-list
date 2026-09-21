using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;

namespace LiquidTodo.Windows.Services;

internal static class NativeWindow
{
    private const int GwlExStyle = -20;
    private const int WsExTransparent = 0x20;
    private const int WsExToolWindow = 0x80;
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)] private static extern int SetCurrentProcessExplicitAppUserModelID(string appID);
    [DllImport("user32.dll")] private static extern int GetWindowLong(IntPtr hWnd, int nIndex);
    [DllImport("user32.dll")] private static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);

    public static void SetCurrentProcessAppUserModelId(string id) => SetCurrentProcessExplicitAppUserModelID(id);
    public static void SetMousePassthrough(Window window, bool enabled)
    {
        var hwnd = new WindowInteropHelper(window).Handle; if (hwnd == IntPtr.Zero) return;
        var style = GetWindowLong(hwnd, GwlExStyle);
        style = enabled ? style | WsExTransparent : style & ~WsExTransparent;
        SetWindowLong(hwnd, GwlExStyle, style | WsExToolWindow);
    }
}
