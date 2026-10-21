using LiquidTodo.Core;
using Xunit;

namespace LiquidTodo.Windows.Tests;

// Exercise the actual persisted store and reminder source together; a source
// returning [] cannot prove that editing or completing a task cancels reminders.
public sealed class ReminderLifecycleTests : IDisposable
{
    private readonly string _root = Path.Combine(Path.GetTempPath(), "ltd-reminder-" + Guid.NewGuid());
    private readonly DateTimeOffset _start = new(2026, 10, 15, 8, 0, 0, TimeSpan.Zero);
    private TodoStore Store(string name = "data.json") => new(new PersistenceService(Path.Combine(_root, name)));
    private TodoSchedule At(int minutes) => new(TodoTimeMode.Deadline, _start.AddMinutes(minutes), ReminderMode: TodoReminderMode.AtTime);
    public void Dispose() { if (Directory.Exists(_root)) Directory.Delete(_root, true); }

    [Fact]
    public void Edit_cancels_old_time_and_delivers_updated_text_only_once()
    {
        var store = Store(); var item = store.Add("old", schedule: At(1)); var poller = new ReminderPoller(_start);
        Assert.Empty(poller.Poll(_start.AddSeconds(30), store.UpcomingReminders));
        store.Update(item.Id, "new", TodoPriority.Important, At(3));
        Assert.Empty(poller.Poll(_start.AddMinutes(2), store.UpcomingReminders));
        var due = Assert.Single(poller.Poll(_start.AddMinutes(3), store.UpcomingReminders));
        Assert.Equal("new", due.Text); Assert.Equal(item.Id, due.TodoId);
        Assert.Empty(poller.Poll(_start.AddMinutes(4), store.UpcomingReminders));
    }

    [Theory]
    [InlineData("complete")]
    [InlineData("delete")]
    [InlineData("clear-schedule")]
    [InlineData("disable-reminder")]
    public void Mutation_cancels_reminder_in_real_store_and_after_restart(string mutation)
    {
        var store = Store(); var item = store.Add("cancel", schedule: At(1));
        Assert.Single(store.UpcomingReminders(_start));
        switch (mutation)
        {
            case "complete": store.Complete(item.Id, _start); break;
            case "delete": store.Delete(item.Id); break;
            case "clear-schedule": store.Update(item.Id, item.Text, item.Priority, null); break;
            case "disable-reminder": store.Update(item.Id, item.Text, item.Priority, At(1) with { ReminderMode = TodoReminderMode.None }); break;
        }
        Assert.Empty(new ReminderPoller(_start).Poll(_start.AddMinutes(2), store.UpcomingReminders));
        Assert.Empty(new ReminderPoller(_start).Poll(_start.AddMinutes(2), Store().UpcomingReminders));
    }

    [Fact]
    public void Undo_completion_before_due_restores_future_reminder()
    {
        var store = Store(); var item = store.Add("undo", schedule: At(2)); var poller = new ReminderPoller(_start);
        store.Complete(item.Id, _start);
        Assert.Empty(poller.Poll(_start.AddSeconds(30), store.UpcomingReminders));
        store.UndoCompletion(item.Id);
        Assert.Equal(item.Id, Assert.Single(poller.Poll(_start.AddMinutes(2), store.UpcomingReminders)).TodoId);
    }

    [Fact]
    public void Replace_import_cancels_removed_task_without_cancelling_new_task()
    {
        var store = Store(); var old = store.Add("old", schedule: At(1));
        var incoming = Store("incoming.json"); var replacement = incoming.Add("replacement", schedule: At(2));
        var backup = Path.Combine(_root, "backup.json"); incoming.Export(backup);
        store.Import(backup, ImportMode.Replace);
        var due = new ReminderPoller(_start).Poll(_start.AddMinutes(3), store.UpcomingReminders);
        Assert.Equal(replacement.Id, Assert.Single(due).TodoId);
        Assert.DoesNotContain(due, x => x.TodoId == old.Id);
    }

    [Fact]
    public void Simultaneous_tasks_each_deliver_even_when_dates_are_equal()
    {
        var store = Store(); store.Add("a", schedule: At(1)); store.Add("b", schedule: At(1));
        var poller = new ReminderPoller(_start);
        var due = poller.Poll(_start.AddMinutes(1), store.UpcomingReminders);
        Assert.Equal(2, due.Count); Assert.Equal(2, due.Select(x => x.TodoId).Distinct().Count());
        Assert.Empty(poller.Poll(_start.AddMinutes(2), store.UpcomingReminders));
    }
}
