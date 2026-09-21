using System.Text.Json;

namespace LiquidTodo.Core;

public sealed class PersistenceService
{
    public PersistenceService(string dataFile) => DataFile = dataFile;
    public string DataFile { get; }
    public string? RecoveredCorruptFile { get; private set; }

    public TodoSnapshot Load()
    {
        if (!File.Exists(DataFile)) return new([], []);
        try
        {
            using var stream = File.OpenRead(DataFile);
            var snapshot = JsonSerializer.Deserialize<TodoSnapshot>(stream, LiquidTodoJson.Options)
                ?? new TodoSnapshot([], []);
            return Normalize(snapshot);
        }
        catch (Exception) when (ex) when (ex is JsonException or IOException or UnauthorizedAccessException)
        {
            var corrupt = $"{DataFile}.corrupt-{DateTimeOffset.UtcNow:yyyyMMddHHmmss}";
            try { File.Move(DataFile, corrupt); RecoveredCorruptFile = corrupt; } catch { /* retain original if isolation fails */ }
            return new([], []);
        }
    }

    public void Save(TodoSnapshot snapshot)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(DataFile)!);
        var tmp = DataFile + ".tmp";
        File.WriteAllText(tmp, JsonSerializer.Serialize(Normalize(snapshot), LiquidTodoJson.Options));
        File.Move(tmp, DataFile, true);
    }

    private static TodoSnapshot Normalize(TodoSnapshot snapshot) => new(
        snapshot.Items.Where(x => !x.Completed).Select(x => x.Normalize()).ToList(),
        snapshot.Archived.Concat(snapshot.Items.Where(x => x.Completed)).Select(x => x.Normalize()).ToList());
}
