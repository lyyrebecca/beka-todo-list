namespace LiquidTodo.Core;

public static class ReminderEngine
{
    public static IReadOnlyList<ReminderRequest> GetRequests(TodoItem item, DateTimeOffset now, TimeZoneInfo? timeZone = null)
    {
        if (item.Completed || item.Schedule is null) return [];
        timeZone ??= TimeZoneInfo.Local;
        var schedule = item.Schedule.Normalize();
        var output = new List<ReminderRequest>();
        DateTimeOffset At(DateOnly day, int minutes)
        {
            var local = day.ToDateTime(TimeOnly.MinValue).AddMinutes(minutes);
            return new DateTimeOffset(local, timeZone.GetUtcOffset(local));
        }
        void Add(string suffix, DateTimeOffset at)
        {
            if (at > now) output.Add(new ReminderRequest($"{item.Id:D}{suffix}", item.Id, at, item.Text));
        }
        switch (schedule.ReminderMode)
        {
            case TodoReminderMode.AtTime when schedule.Date is { } date:
                Add("", date); break;
            case TodoReminderMode.DayBefore when schedule.Date is { } eventDate:
                Add("-day-before", At(DateOnly.FromDateTime(TimeZoneInfo.ConvertTime(eventDate, timeZone).Date.AddDays(-1)), schedule.ReminderTimeMinutes)); break;
            case TodoReminderMode.DailyDuringPeriod when schedule.StartDate is { } start && schedule.EndDate is { } end:
                var today = DateOnly.FromDateTime(TimeZoneInfo.ConvertTime(now, timeZone).Date);
                var first = start > today ? start : today;
                for (var offset = 0; offset < 60 && first.DayNumber + offset <= end.DayNumber; offset++)
                {
                    var day = first.AddDays(offset);
                    Add($"-daily-{day:yyyyMMdd}", At(day, schedule.ReminderTimeMinutes));
                }
                break;
        }
        return output;
    }

    public static IReadOnlyList<string> AllIdentifiers(TodoItem item)
    {
        if (item.Schedule?.ReminderMode != TodoReminderMode.DailyDuringPeriod || item.Schedule.StartDate is not { } start || item.Schedule.EndDate is not { } end)
            return [$"{item.Id:D}", $"{item.Id:D}-day-before"];
        return Enumerable.Range(0, Math.Max(0, Math.Min(60, end.DayNumber - start.DayNumber + 1)))
            .Select(i => $"{item.Id:D}-daily-{start.AddDays(i):yyyyMMdd}").ToArray();
    }
}
