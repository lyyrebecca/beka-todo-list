using System.IO.Pipes;
using System.Text;
using System.Windows.Threading;

namespace LiquidTodo.Windows.Services;

internal sealed class SingleInstanceService : IDisposable
{
    private readonly string _name; private readonly Dispatcher _dispatcher; private readonly Action<string> _onSignal;
    private readonly CancellationTokenSource _cancel = new(); private Task? _loop;
    public SingleInstanceService(string name, Dispatcher dispatcher, Action<string> onSignal) { _name = name; _dispatcher = dispatcher; _onSignal = onSignal; }
    public void Start() => _loop = Task.Run(ListenAsync);
    private async Task ListenAsync()
    {
        while (!_cancel.IsCancellationRequested)
        {
            try
            {
                await using var pipe = new NamedPipeServerStream(_name, PipeDirection.In, 1, PipeTransmissionMode.Byte, PipeOptions.Asynchronous);
                await pipe.WaitForConnectionAsync(_cancel.Token);
                using var reader = new StreamReader(pipe, Encoding.UTF8, leaveOpen: true);
                var command = await reader.ReadLineAsync(_cancel.Token) ?? "activate";
                _dispatcher.BeginInvoke(() => _onSignal(command));
            }
            catch (OperationCanceledException) { break; }
            catch { await Task.Delay(250, _cancel.Token); }
        }
    }
    public static void SignalExisting(string name, string command)
    {
        try { using var pipe = new NamedPipeClientStream(".", name, PipeDirection.Out); pipe.Connect(700); using var writer = new StreamWriter(pipe, Encoding.UTF8) { AutoFlush = true }; writer.WriteLine(command); } catch { }
    }
    public void Dispose() { _cancel.Cancel(); try { _loop?.Wait(500); } catch { } _cancel.Dispose(); }
}
