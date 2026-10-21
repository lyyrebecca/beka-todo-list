using Xunit;
using LiquidTodo.Core;

namespace LiquidTodo.Windows.Tests;

public class WindowRegressionTests
{
    [Fact] public void Tiny_work_area_does_not_throw_or_put_orb_outside()
    {
        var area = new RectD(-20, 30, 40, 35);
        var result = WindowSnapService.SnapToNearestEdge(new(500, -999, 48, 48), area);
        Assert.InRange(result.X, area.X, area.Right);
        Assert.InRange(result.Y, area.Y, area.Bottom);
        Assert.True(result.Right <= area.Right && result.Bottom <= area.Bottom);
    }

    [Fact] public void Invalid_saved_coordinate_is_recovered()
    {
        var result = WindowSnapService.SnapToNearestEdge(new(double.NaN, double.PositiveInfinity, 48, 48), new(0, 0, 1920, 1040));
        Assert.True(double.IsFinite(result.X) && double.IsFinite(result.Y));
        Assert.InRange(result.Y, 7, 985);
    }

    [Fact] public void Period_started_more_than_60_days_ago_still_reminds_today()
    {
        var now = new DateTimeOffset(2026, 10, 13, 8, 0, 0, TimeSpan.Zero);
        var item = TodoItem.Create("长期计划", schedule: new(TodoTimeMode.Period,
            StartDate: new DateOnly(2026, 1, 1), EndDate: new DateOnly(2027, 1, 1),
            ReminderMode: TodoReminderMode.DailyDuringPeriod, ReminderTimeMinutes: 9 * 60));
        var requests = ReminderEngine.GetRequests(item, now, TimeZoneInfo.Utc);
        Assert.NotEmpty(requests);
        Assert.Equal(new DateTimeOffset(2026, 10, 13, 9, 0, 0, TimeSpan.Zero), requests[0].At);
        Assert.InRange(requests.Count, 1, 60);
    }

    [Fact] public void Structurally_corrupt_json_is_quarantined_not_a_startup_crash()
    {
        var path = Path.Combine(Path.GetTempPath(), Guid.NewGuid() + ".json");
        File.WriteAllText(path, "{\"items\":null,\"archived\":[]}");
        var persistence = new PersistenceService(path);
        try { Assert.Empty(persistence.Load().Items); Assert.NotNull(persistence.RecoveredCorruptFile); }
        finally { if (File.Exists(path)) File.Delete(path); if (persistence.RecoveredCorruptFile is {} backup) File.Delete(backup); }
    }
}
