using System.IO.Pipes;
using System.Windows;
using LiquidTodo.Core;
using LiquidTodo.Windows.Services;

namespace LiquidTodo.Windows;

public partial class App : Application
{
    private const string InstanceName = "com.beka.liquidtodo.windows.v2";
    private Mutex? _mutex;
    private CancellationTokenSource? _pipeCancellation;
    private MainWindow? _mainWindow;
    private SingleInstanceService? _singleInstance;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        _mutex = new Mutex(true, InstanceName, out var isFirst);
        if (!isFirst)
        {
            SingleInstanceService.SignalExisting(InstanceName, e.Args.Any(x => x.Equals("--import", StringComparison.OrdinalIgnoreCase)) ? "import" : "activate");
            Shutdown(); return;
        }

        NativeWindow.SetCurrentProcessAppUserModelId("com.beka.liquidtodo");
        var paths = LiquidTodoPaths.Resolve(e.Args);
        var store = new TodoStore(new PersistenceService(paths.DataFile));
        _singleInstance = new SingleInstanceService(InstanceName, Dispatcher, HandleSecondLaunch);
        _singleInstance.Start();
        _mainWindow = new MainWindow(paths, store, e.Args);
        _mainWindow.Closed += (_, _) => Shutdown();
        _mainWindow.Show();
    }

    private void HandleSecondLaunch(string command) => _mainWindow?.ActivateFromSecondLaunch(command);

    protected override void OnExit(ExitEventArgs e)
    {
        _singleInstance?.Dispose(); _pipeCancellation?.Cancel(); _mutex?.ReleaseMutex(); _mutex?.Dispose();
        base.OnExit(e);
    }
}
