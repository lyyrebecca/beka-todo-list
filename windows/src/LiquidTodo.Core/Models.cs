using System.Text.Json.Serialization;

namespace LiquidTodo.Core;

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum TodoPriority { Normal, Important, Urgent }

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum TodoTimeMode { None, Deadline, Period, Day }

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum TodoReminderMode { None, AtTime, DayBefore, DailyDuringPeriod }

public sealed record TodoSchedule(
    TodoTimeMode Mode = TodoTimeMode.None,
    DateTimeOffset? Date = null,
    DateOnly? StartDate = null,
    DateOnly? EndDate = null,
    TodoReminderMode ReminderMode = TodoReminderMode.None,
    int ReminderTimeMinutes = 1260)
{
    public DateTimeOffset? PrimaryDate => Mode == TodoTimeMode.Period
        ? EndDate is { } end ? new DateTimeOffset(end.ToDateTime(TimeOnly.MinValue), TimeZoneInfo.Local.GetUtcOffset(end.ToDateTime(TimeOnly.MinValue))) : null
        : Date;

    public TodoSchedule Normalize()
    {
        var minute = Math.Clamp(ReminderTimeMinutes, 0, 1439);
        if (Mode == TodoTimeMode.None) return this with { Date = null, StartDate = null, EndDate = null, ReminderMode = TodoReminderMode.None, ReminderTimeMinutes = minute };
        if (Mode == TodoTimeMode.Period && StartDate is { } start && EndDate is { } end && start > end)
            return this with { StartDate = end, EndDate = start, Date = null, ReminderMode = ReminderMode == TodoReminderMode.None ? TodoReminderMode.None : TodoReminderMode.DailyDuringPeriod, ReminderTimeMinutes = minute };
        return this with { ReminderTimeMinutes = minute };
    }
}

public sealed record TodoItem(
    Guid Id,
    string Text,
    DateTimeOffset CreatedAt,
    DateTimeOffset? DueDate = null,
    TodoSchedule? Schedule = null,
    TodoPriority Priority = TodoPriority.Normal,
    bool Completed = false,
    DateTimeOffset? CompletedAt = null)
{
    public static TodoItem Create(string text, TodoPriority priority = TodoPriority.Normal, TodoSchedule? schedule = null, DateTimeOffset? now = null) =>
        new(Guid.NewGuid(), text.Trim(), now ?? DateTimeOffset.UtcNow, schedule?.PrimaryDate, schedule?.Normalize(), priority);

    public TodoItem Normalize() => this with
    {
        Text = Text.Trim(),
        Schedule = Schedule?.Normalize(),
        DueDate = Schedule?.Normalize().PrimaryDate ?? DueDate
    };
}

public sealed record TodoSnapshot(List<TodoItem> Items, List<TodoItem> Archived);

public sealed record LiquidTodoBackup(
    int SchemaVersion,
    DateTimeOffset ExportedAt,
    List<TodoItem> Items,
    List<TodoItem> Archived)
{
    public const int CurrentSchemaVersion = 1;
}

public enum ImportMode { Merge, Replace }
public sealed record ImportResult(int ImportedItems, int ImportedArchived, int SkippedDuplicates, string SafetyBackupPath);
public sealed record ReminderRequest(string Identifier, Guid TodoId, DateTimeOffset At, string Text);
public sealed record RectD(double X, double Y, double Width, double Height)
{
    public double Right => X + Width;
    public double Bottom => Y + Height;
    public double CenterX => X + Width / 2;
}
