using CommunityToolkit.WinUI.Notifications;
using System.Windows.Threading;
using LiquidTodo.Core;
namespace LiquidTodo.Windows.Services;
internal sealed class ToastNotificationService : IDisposable
{
    private readonly DispatcherTimer _heartbeat;
    private readonly ReminderPoller _poller = new(DateTimeOffset.Now);
    private readonly Func<DateTimeOffset, IReadOnlyList<ReminderRequest>> _source;
    private readonly Action<string, string> _fallback;
    private readonly Func<string> _title;
    public bool NativeRegistrationAvailable { get; private set; } = true;
    public ToastNotificationService(Action<string, string> fallback, Func<DateTimeOffset, IReadOnlyList<ReminderRequest>> source, Func<string> title)
    {
        _fallback = fallback; _source = source; _title = title;
        _heartbeat = new DispatcherTimer { Interval = TimeSpan.FromSeconds(15) };
        _heartbeat.Tick += (_, _) => Rebuild(); _heartbeat.Start();
    }
    public void Rebuild()
    {
        // Current store invalidates edited/deleted/completed reminders. Short
        // UI-thread polling avoids Timer dueTime limits and callback races.
        foreach (var request in _poller.Poll(DateTimeOffset.Now, _source))
        {
            try { new ToastContentBuilder().AddText(_title()).AddText(request.Text).Show(); }
            catch { NativeRegistrationAvailable = false; _fallback(_title(), request.Text); }
        }
    }
    public void Dispose() => _heartbeat.Stop();
}
