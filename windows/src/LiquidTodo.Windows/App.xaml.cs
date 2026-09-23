using System.IO.Pipes;
using System.Windows;
using LiquidTodo.Core;
using LiquidTodo.Windows.Services;

namespace LiquidTodo.Windows;

public partial class App : System.Windows.Application
{
    private const string InstanceName = "com.beka.liquidtodo.windows.v2";
    private Mutex? _mutex;
    private bool _ownsMutex;
    private bool _fatalErrorShown;
    private MainWindow? _mainWindow;
    private SingleInstanceService? _singleInstance;
    private StartupDiagnostics? _diagnostics;

    protected override void OnStartup(StartupEventArgs e)
    {
        LiquidTodoPaths? paths = null;
        try
        {
            paths = LiquidTodoPaths.Resolve(e.Args);
            _diagnostics = StartupDiagnostics.Create(paths);
            ConfigureUnhandledExceptionLogging();
            var safeMode = e.Args.Any(x => x.Equals("--safe-mode", StringComparison.OrdinalIgnoreCase));
            _diagnostics.WriteStartup(paths, e.Args, safeMode);
            Directory.CreateDirectory(paths.Root);

            base.OnStartup(e);
            _mutex = new Mutex(true, InstanceName, out var isFirst);
            _ownsMutex = isFirst;
            if (!isFirst)
            {
                SingleInstanceService.SignalExisting(InstanceName, e.Args.Any(x => x.Equals("--import", StringComparison.OrdinalIgnoreCase)) ? "import" : "activate");
                Shutdown(); return;
            }

            NativeWindow.SetCurrentProcessAppUserModelId("com.beka.liquidtodo");
            var store = new TodoStore(new PersistenceService(paths.DataFile));
            _singleInstance = new SingleInstanceService(InstanceName, Dispatcher, HandleSecondLaunch);
            _singleInstance.Start();
            _mainWindow = new MainWindow(paths, store, e.Args, safeMode);
            _mainWindow.Closed += (_, _) => Shutdown();
            _mainWindow.Show();
            _diagnostics.Write("startup", "main window shown");
        }
        catch (Exception exception) { ReportFatalStartupError(exception, paths); }
    }

    private void HandleSecondLaunch(string command) => _mainWindow?.ActivateFromSecondLaunch(command);

    protected override void OnExit(ExitEventArgs e)
    {
        _singleInstance?.Dispose();
        if (_ownsMutex)
        {
            try { _mutex?.ReleaseMutex(); }
            catch (ApplicationException) { }
        }
        _mutex?.Dispose();
        base.OnExit(e);
    }

    private void ConfigureUnhandledExceptionLogging()
    {
        DispatcherUnhandledException += (_, eventArgs) =>
        {
            _diagnostics?.WriteException("dispatcher-unhandled", eventArgs.Exception);
            eventArgs.Handled = true;
            ReportFatalStartupError(eventArgs.Exception, null);
        };
        AppDomain.CurrentDomain.UnhandledException += (_, eventArgs) =>
        {
            if (eventArgs.ExceptionObject is Exception exception) _diagnostics?.WriteException("appdomain-unhandled", exception);
            else _diagnostics?.Write("appdomain-unhandled", "Non-Exception error");
        };
        TaskScheduler.UnobservedTaskException += (_, eventArgs) =>
        {
            _diagnostics?.WriteException("task-unobserved", eventArgs.Exception);
            eventArgs.SetObserved();
        };
    }

    private void ReportFatalStartupError(Exception exception, LiquidTodoPaths? paths)
    {
        _diagnostics ??= StartupDiagnostics.Create(paths);
        _diagnostics.WriteException("fatal-startup", exception);
        if (_fatalErrorShown) return;
        _fatalErrorShown = true;
        try
        {
            MessageBox.Show(
                "贝卡の Todo list 未能启动。已保存诊断日志：\n" + _diagnostics.LogFile +
                "\n\n请保留该日志并重新尝试使用 --safe-mode 启动。",
                "贝卡の Todo list",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
        }
        finally { Shutdown(-1); }
    }
}
