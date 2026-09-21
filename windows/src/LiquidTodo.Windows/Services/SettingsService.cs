using System.Text.Json;
using LiquidTodo.Core;

namespace LiquidTodo.Windows.Services;

internal sealed record AppSettings(string? OwnerName = null, bool IsMinimized = false, bool DesktopMode = false, double Left = double.NaN, double Top = double.NaN);
internal sealed class SettingsService
{
    private readonly string _path;
    public SettingsService(string path) => _path = path;
    public AppSettings Load() { try { return JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(_path), LiquidTodoJson.Options) ?? new(); } catch { return new(); } }
    public void Save(AppSettings setting) { Directory.CreateDirectory(Path.GetDirectoryName(_path)!); var tmp = _path + ".tmp"; File.WriteAllText(tmp, JsonSerializer.Serialize(setting, LiquidTodoJson.Options)); File.Move(tmp, _path, true); }
}
