using CommunityToolkit.WinUI.Notifications;
using LiquidTodo.Core;

namespace LiquidTodo.Windows.Services;

/// <summary>Uses the stable AUMID for native toasts; resident timers remain a deterministic fallback for unpackaged installs.</summary>
internal sealed class ToastNotificationService : IDisposable
{
    private readonly Dictionary<string, System.Threading.Timer> _timers = [];
    private readonly Action<string, string> _fallback;
    public bool NativeRegistrationAvailable { get; private set; } = true;
    public ToastNotificationService(Action<string, string> fallback) => _fallback = fallback;

    public void Rebuild(IEnumerable<ReminderRequest> requests)
    {
        CancelAll();
        foreach (var request in requests)
        {
            var due = request.At - DateTimeOffset.Now;
            if (due <= TimeSpan.Zero) continue;
            _timers[request.Identifier] = new System.Threading.Timer(_ => Deliver(request), null, due, Timeout.InfiniteTimeSpan);
        }
    }

    public void Cancel(IEnumerable<string> identifiers)
    {
        foreach (var id in identifiers) if (_timers.Remove(id, out var timer)) timer.Dispose();
    }

    private void Deliver(ReminderRequest request)
    {
        try
        {
            new ToastContentBuilder().AddText("贝卡の Todo list").AddText(request.Text).Show();
        }
        catch
        {
            NativeRegistrationAvailable = false;
            _fallback("贝卡の Todo list", request.Text);
        }
        finally { if (_timers.Remove(request.Identifier, out var timer)) timer.Dispose(); }
    }

    private void CancelAll() { foreach (var item in _timers.Values) item.Dispose(); _timers.Clear(); }
    public void Dispose() => CancelAll();
}
