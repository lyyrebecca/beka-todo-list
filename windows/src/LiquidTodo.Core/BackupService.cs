using System.Globalization;
using System.Text.Json;

namespace LiquidTodo.Core;

public sealed class BackupService
{
    public LiquidTodoBackup Read(string path)
    {
        using var document = JsonDocument.Parse(File.ReadAllText(path));
        var root = document.RootElement;
        if (root.TryGetProperty("schemaVersion", out _))
        {
            return JsonSerializer.Deserialize<LiquidTodoBackup>(root.GetRawText(), LiquidTodoJson.Options)
                ?? throw new InvalidDataException("无效的 LiquidTodo Backup v1 文件。");
        }
        return ReadLegacyMac(root);
    }

    public void Write(string path, TodoSnapshot snapshot)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var backup = new LiquidTodoBackup(LiquidTodoBackup.CurrentSchemaVersion, DateTimeOffset.UtcNow, snapshot.Items, snapshot.Archived);
        File.WriteAllText(path, JsonSerializer.Serialize(backup, LiquidTodoJson.Options));
    }

    public static string SuggestedExportFile(string directory) => Path.Combine(directory, $"LiquidTodo-Backup-{DateTimeOffset.UtcNow:yyyyMMdd-HHmmss}.json");

    private static LiquidTodoBackup ReadLegacyMac(JsonElement root)
    {
        var items = ReadLegacyArray(root, "items");
        var archived = ReadLegacyArray(root, "archived");
        return new LiquidTodoBackup(LiquidTodoBackup.CurrentSchemaVersion, DateTimeOffset.UtcNow, items, archived);
    }

    private static List<TodoItem> ReadLegacyArray(JsonElement root, string property) =>
        root.TryGetProperty(property, out var values) && values.ValueKind == JsonValueKind.Array
            ? values.EnumerateArray().Select(ReadLegacyItem).ToList() : [];

    private static TodoItem ReadLegacyItem(JsonElement value)
    {
        var id = value.TryGetProperty("id", out var rawId) && Guid.TryParse(rawId.GetString(), out var parsed) ? parsed : Guid.NewGuid();
        var text = value.TryGetProperty("text", out var rawText) ? rawText.GetString() ?? "" : "";
        var created = LegacyDate(value, "createdAt") ?? DateTimeOffset.UtcNow;
        var due = LegacyDate(value, "dueDate");
        var priority = value.TryGetProperty("priority", out var rawPriority) ? rawPriority.ValueKind switch
        {
            JsonValueKind.Number when rawPriority.TryGetInt32(out var n) => n switch { 2 => TodoPriority.Urgent, 1 => TodoPriority.Important, _ => TodoPriority.Normal },
            JsonValueKind.String when Enum.TryParse<TodoPriority>(rawPriority.GetString(), true, out var p) => p,
            _ => TodoPriority.Normal
        } : TodoPriority.Normal;
        var complete = value.TryGetProperty("completed", out var rawCompleted) && rawCompleted.GetBoolean();
        var completedAt = LegacyDate(value, "completedAt");
        var schedule = ReadLegacySchedule(value, due);
        return new TodoItem(id, text, created, schedule?.PrimaryDate ?? due, schedule, priority, complete, completedAt).Normalize();
    }

    private static TodoSchedule? ReadLegacySchedule(JsonElement item, DateTimeOffset? due)
    {
        if (!item.TryGetProperty("schedule", out var source) || source.ValueKind == JsonValueKind.Null)
            return due is { } oldDue ? new TodoSchedule(TodoTimeMode.Deadline, oldDue, ReminderMode: TodoReminderMode.AtTime) : null;
        var mode = ParseEnum(source, "mode", TodoTimeMode.None);
        var reminder = ParseEnum(source, "reminderMode", TodoReminderMode.None);
        var minute = source.TryGetProperty("reminderTimeMinutes", out var rawMinute) && rawMinute.TryGetInt32(out var m) ? m : 1260;
        var date = LegacyDate(source, "date");
        var start = LegacyDate(source, "startDate").HasValue ? DateOnly.FromDateTime(LegacyDate(source, "startDate")!.Value.LocalDateTime) : null;
        var end = LegacyDate(source, "endDate").HasValue ? DateOnly.FromDateTime(LegacyDate(source, "endDate")!.Value.LocalDateTime) : null;
        return new TodoSchedule(mode, date, start, end, reminder, minute).Normalize();
    }

    private static T ParseEnum<T>(JsonElement source, string name, T fallback) where T : struct, Enum =>
        source.TryGetProperty(name, out var value) && Enum.TryParse<T>(value.GetString(), true, out var parsed) ? parsed : fallback;

    private static DateTimeOffset? LegacyDate(JsonElement source, string name)
    {
        if (!source.TryGetProperty(name, out var value) || value.ValueKind == JsonValueKind.Null) return null;
        if (value.ValueKind == JsonValueKind.Number && value.TryGetDouble(out var seconds))
            return new DateTimeOffset(2001, 1, 1, 0, 0, 0, TimeSpan.Zero).AddSeconds(seconds);
        if (value.ValueKind == JsonValueKind.String && DateTimeOffset.TryParse(value.GetString(), CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out var parsed)) return parsed;
        return null;
    }
}
