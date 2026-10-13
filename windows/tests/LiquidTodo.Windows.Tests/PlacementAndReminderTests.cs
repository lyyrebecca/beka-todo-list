using Xunit;
using LiquidTodo.Core;
using LiquidTodo.Windows.Services;

namespace LiquidTodo.Windows.Tests;
public class PlacementAndReminderTests
{
    public static IEnumerable<object[]> Displays()
    {
        foreach (var dpi in new[] { 96d, 120d, 144d, 192d })
        foreach (var origin in new[] { (-1920d, -1080d), (0d, 0d), (2560d, -600d) })
        foreach (var shape in new[] { (1920d, 1040d), (1040d, 1920d), (800d, 560d) })
            yield return [dpi, origin.Item1, origin.Item2, shape.Item1, shape.Item2];
    }

    [Theory, MemberData(nameof(Displays))]
    public void Orb_and_restored_panel_stay_inside_physical_work_area(double dpi, double x, double y, double width, double height)
    {
        var area = new RectD(x, y, width, height);
        var size = WindowSnapService.DipsToPixels(48, dpi);
        var margin = WindowSnapService.DipsToPixels(7, dpi);
        foreach (var position in new[] { new RectD(x - 999, y - 999, size, size), new RectD(x + width + 999, y + height + 999, size, size) })
        {
            var snap = WindowSnapService.SnapToNearestEdge(position, area, margin);
            Assert.True(snap.X >= x && snap.Y >= y && snap.Right <= area.Right && snap.Bottom <= area.Bottom);
            var saved = WindowSnapService.Capture(snap, area, "screen");
            var restored = WindowSnapService.Restore(saved, area, size, size);
            Assert.Equal(snap.X, restored.X, 6); Assert.Equal(snap.Y, restored.Y, 6);
            var panel = WindowSnapService.Restore(saved, area, WindowSnapService.DipsToPixels(362, dpi), WindowSnapService.DipsToPixels(400, dpi));
            Assert.True(panel.X >= x && panel.Y >= y && panel.Right <= area.Right && panel.Bottom <= area.Bottom);
        }
    }

    [Fact] public void Invalid_placement_ratios_and_removed_monitor_use_safe_default()
    {
        var area = new RectD(0, 0, 800, 600);
        var result = WindowSnapService.Restore(new("removed", double.NaN, double.NegativeInfinity), area, 48, 48);
        Assert.Equal(745, result.X); Assert.Equal(276, result.Y);
    }

    [Fact] public void Physical_150_percent_coordinates_are_not_multiplied_twice()
    {
        var area = new RectD(0, 0, 1920, 1080);
        var orb = WindowSnapService.SnapToNearestEdge(new(1850, 200, 72, 72), area, 10.5);
        Assert.Equal(1837.5, orb.X); Assert.Equal(72, orb.Width);
    }

    [Fact] public void First_name_and_legacy_NaN_coordinates_save_without_crash()
    {
        var root = Path.Combine(Path.GetTempPath(), "ltd-settings-" + Guid.NewGuid());
        var path = Path.Combine(root, "settings.json"); var service = new SettingsService(path);
        try
        {
            Assert.True(service.TrySave(new("测试", Left: double.NaN, Top: double.PositiveInfinity), out _));
            Assert.Equal("测试", service.Load().OwnerName);
            Assert.DoesNotContain("NaN", File.ReadAllText(path));
        }
        finally { Directory.Delete(root, true); }
    }

    [Fact] public void Settings_write_failure_is_reported_not_thrown()
    {
        var path = Path.Combine(Path.GetTempPath(), "ltd-settings-" + Guid.NewGuid()); File.WriteAllText(path, "unchanged");
        try
        {
            Assert.False(new SettingsService(Path.Combine(path, "settings.json")).TrySave(new(), out var error));
            Assert.NotNull(error); Assert.Equal("unchanged", File.ReadAllText(path));
        }
        finally { File.Delete(path); }
    }

    [Fact] public void Second_launch_preserves_Unicode_import_file_and_spaces()
    {
        var command = new InstanceCommand("import", @"C:\备份 文件\todo.json");
        Assert.Equal(command, InstanceCommand.Parse(command.Serialize()));
        Assert.Equal("activate", InstanceCommand.Parse("activate").Action);
        Assert.Equal("activate", InstanceCommand.Parse("malformed").Action);
    }

    [Fact] public void Polling_handles_far_future_and_delivers_once()
    {
        var start = DateTimeOffset.UtcNow; var id = Guid.NewGuid(); var at = start.AddDays(120);
        var poller = new ReminderPoller(start);
        IReadOnlyList<ReminderRequest> Source(DateTimeOffset _) => [new("one", id, at, "future")];
        Assert.Empty(poller.Poll(start.AddDays(119), Source)); Assert.Single(poller.Poll(at, Source));
        Assert.Empty(poller.Poll(at.AddSeconds(15), Source));
        Assert.Empty(poller.Poll(at.AddMinutes(-1), Source)); Assert.Empty(poller.Poll(at, Source));
    }

    [Fact] public void Polling_uses_current_store_for_edit_completion_and_deletion()
    {
        var start = DateTimeOffset.UtcNow; var poller = new ReminderPoller(start);
        IReadOnlyList<ReminderRequest> Source(DateTimeOffset _) => [];
        Assert.Empty(poller.Poll(start.AddMinutes(2), Source));
    }

    [Fact] public void Resume_after_months_delivers_latest_daily_reminder_not_a_backlog()
    {
        var start = new DateTimeOffset(2026, 1, 1, 8, 0, 0, TimeSpan.Zero);
        var now = new DateTimeOffset(2026, 10, 13, 10, 0, 0, TimeSpan.Zero);
        var item = TodoItem.Create("长计划", schedule: new(TodoTimeMode.Period, StartDate: new(2026,1,1), EndDate: new(2027,1,1), ReminderMode: TodoReminderMode.DailyDuringPeriod, ReminderTimeMinutes: 540));
        var due = new ReminderPoller(start).Poll(now, since => ReminderEngine.GetRequests(item, since, TimeZoneInfo.Utc));
        Assert.Equal(new DateTimeOffset(2026,10,13,9,0,0,TimeSpan.Zero), Assert.Single(due).At);
    }
}
