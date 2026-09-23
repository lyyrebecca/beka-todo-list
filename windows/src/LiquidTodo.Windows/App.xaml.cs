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
            var previewMode = e.Args.Any(x => x.Equals("--demo-screenshot", StringComparison.OrdinalIgnoreCase));
            var dataFile = previewMode
                ? Path.Combine(Path.GetTempPath(), $"LiquidTodo-VisualSmoke-{Guid.NewGuid():N}", "data.json")
                : paths.DataFile;
            var store = new TodoStore(new PersistenceService(dataFile));
            if (previewMode) SeedVisualPreview(store);
            _singleInstance = new SingleInstanceService(InstanceName, Dispatcher, HandleSecondLaunch);
            _singleInstance.Start();
            _mainWindow = new MainWindow(paths, store, e.Args, safeMode);
            _mainWindow.Closed += (_, _) => Shutdown();
            _mainWindow.Show();
            _diagnostics.Write("startup", "main window shown");
            if (TryReadCapturePath(e.Args, out var capturePath)) _mainWindow.CaptureScreenshotAndExit(capturePath);
        }
        catch (Exception exception) { ReportFatalStartupError(exception, paths); }
    }

    private void HandleSecondLaunch(string command) => _mainWindow?.ActivateFromSecondLaunch(command);

    private static bool TryReadCapturePath(IEnumerable<string> arguments, out string path)
    {
        var values = arguments.ToArray();
        var index = Array.FindIndex(values, value => value.Equals("--capture-screenshot", StringComparison.OrdinalIgnoreCase));
        path = index >= 0 && index + 1 < values.Length ? values[index + 1] : "";
        return !string.IsNullOrWhiteSpace(path);
    }

    private static void SeedVisualPreview(TodoStore store)
    {
        store.Add("准备 Windows 版验收", TodoPriority.Urgent);
        store.Add("整理发布说明与下载指引", TodoPriority.Important,
            new TodoSchedule(TodoTimeMode.Deadline, DateTimeOffset.Now.AddHours(4), ReminderMode: TodoReminderMode.AtTime));
        var start = DateOnly.FromDateTime(DateTime.Today.AddDays(1));
        store.Add("完成玻璃质感界面复核", TodoPriority.Normal,
            new TodoSchedule(TodoTimeMode.Period, StartDate: start, EndDate: start.AddDays(2), ReminderMode: TodoReminderMode.DailyDuringPeriod, ReminderTimeMinutes: 9 * 60));
    }

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
