using Microsoft.Win32;

namespace LiquidTodo.Windows.Services;

internal sealed class StartupService
{
    private const string Key = "LiquidTodo";
    public bool IsEnabled => Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run")?.GetValue(Key) is string;
    public void SetEnabled(bool enabled)
    {
        using var run = Registry.CurrentUser.CreateSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run", writable: true);
        if (enabled) run.SetValue(Key, $"\"{Environment.ProcessPath}\" --autostart"); else run.DeleteValue(Key, false);
    }
}
