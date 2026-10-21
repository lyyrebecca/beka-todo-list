namespace LiquidTodo.Core;

// Resident reminders use short polling, not one Timer with a potentially invalid
// multi-month dueTime. All app access and delivery take place on the UI thread.
public sealed class ReminderPoller(DateTimeOffset startedAt)
{
    private DateTimeOffset _previous = startedAt;
    private readonly Dictionary<string, DateTimeOffset> _delivered = [];
    public IReadOnlyList<ReminderRequest> Poll(DateTimeOffset now, Func<DateTimeOffset, IReadOnlyList<ReminderRequest>> source)
    {
        if (now < _previous) { _previous = now; return []; }
        var since = now - _previous > TimeSpan.FromDays(1) ? now.AddDays(-1) : _previous;
        var due = source(since).Where(x => x.At > since && x.At <= now && !_delivered.ContainsKey($"{x.Identifier}|{x.At.UtcTicks}"))
            .GroupBy(x => x.TodoId).Select(g => g.MaxBy(x => x.At)!).ToArray();
        foreach (var request in due) _delivered[$"{request.Identifier}|{request.At.UtcTicks}"] = now;
        foreach (var key in _delivered.Where(x => now - x.Value > TimeSpan.FromDays(7)).Select(x => x.Key).ToArray()) _delivered.Remove(key);
        _previous = now;
        return due;
    }
}
