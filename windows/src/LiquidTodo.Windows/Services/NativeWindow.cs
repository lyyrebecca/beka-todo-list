using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;

namespace LiquidTodo.Windows.Services;

internal static class NativeWindow
{
    [StructLayout(LayoutKind.Sequential)] internal struct Point { public int X; public int Y; }
    [StructLayout(LayoutKind.Sequential)] private struct Rect { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] private static extern bool GetCursorPos(out Point point);
    [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr hwnd, out Rect rect);
    [DllImport("user32.dll")] private static extern uint GetDpiForWindow(IntPtr hwnd);
    [DllImport("user32.dll", SetLastError = true)] private static extern bool SetWindowPos(IntPtr hwnd, IntPtr after, int x, int y, int width, int height, uint flags);
    public static Point CursorPosition() { GetCursorPos(out var point); return point; }
    public static double Dpi(Window window) { var dpi = GetDpiForWindow(new WindowInteropHelper(window).Handle); return dpi > 0 ? dpi : 96; }
    public static LiquidTodo.Core.RectD Bounds(Window window)
    {
        GetWindowRect(new WindowInteropHelper(window).Handle, out var rect);
        return new(rect.Left, rect.Top, rect.Right - rect.Left, rect.Bottom - rect.Top);
    }
    public static void Move(Window window, double x, double y)
    {
        if (!double.IsFinite(x) || !double.IsFinite(y)) return;
        if (!SetWindowPos(new WindowInteropHelper(window).Handle, IntPtr.Zero, (int)Math.Round(x), (int)Math.Round(y), 0, 0, 0x0015))
            throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
    }

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
