using System.Text.Json;
using LiquidTodo.Core;
namespace LiquidTodo.Windows.Services;
internal sealed record AppSettings(string? OwnerName = null, bool IsMinimized = false, bool DesktopMode = false, double? Left = null, double? Top = null,
    int PlacementVersion = 2, WindowPlacement? PanelPlacement = null, WindowPlacement? OrbPlacement = null);
internal sealed class SettingsService
{
    private readonly string _path;
    public SettingsService(string path) => _path = path;
    public AppSettings Load() { try { return JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(_path), LiquidTodoJson.Options) ?? new(); } catch { return new(); } }
    public bool TrySave(AppSettings setting, out string? error)
    {
        error = null;
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
            var tmp = _path + ".tmp";
            File.WriteAllText(tmp, JsonSerializer.Serialize(setting with { Left = null, Top = null }, LiquidTodoJson.Options));
            File.Move(tmp, _path, true); return true;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or ArgumentException)
        { error = ex.Message; return false; }
    }
}
