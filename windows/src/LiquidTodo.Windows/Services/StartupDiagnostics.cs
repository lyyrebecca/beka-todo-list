using System.Reflection;
using System.Text;
using LiquidTodo.Core;

namespace LiquidTodo.Windows.Services;

/// <summary>
/// Writes a small, local-only startup record.  A WPF WinExe has no console, so
/// without this a constructor failure looks exactly like a process that flashes
/// in Task Manager and disappears.
/// </summary>
internal sealed class StartupDiagnostics
{
    private readonly string _logDirectory;
    private readonly string _logFile;
    private readonly object _gate = new();

    private StartupDiagnostics(string logDirectory)
    {
        _logDirectory = logDirectory;
        _logFile = Path.Combine(logDirectory, $"startup-{DateTimeOffset.UtcNow:yyyyMMdd-HHmmssfff}.log");
    }

    public string LogFile => _logFile;

    public static StartupDiagnostics Create(LiquidTodoPaths? paths)
    {
        var root = paths?.Root;
        if (string.IsNullOrWhiteSpace(root))
        {
            var baseDirectory = AppContext.BaseDirectory;
            var portable = File.Exists(Path.Combine(baseDirectory, "portable.flag"));
            root = portable
                ? Path.Combine(baseDirectory, "Data")
                : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "LiquidTodo");
        }
        return new StartupDiagnostics(Path.Combine(root, "Logs"));
    }

    public void WriteStartup(LiquidTodoPaths paths, IEnumerable<string> arguments, bool safeMode)
    {
        var version = Assembly.GetExecutingAssembly().GetName().Version?.ToString() ?? "unknown";
        Write("startup", $"version={version}; portable={paths.IsPortable}; safeMode={safeMode}; " +
            $"dataRoot={paths.Root}; arguments={string.Join(' ', arguments.Select(RedactArgument))}");
    }

    public void Write(string stage, string detail)
    {
        try
        {
            lock (_gate)
            {
                Directory.CreateDirectory(_logDirectory);
                File.AppendAllText(_logFile, $"{DateTimeOffset.UtcNow:O} [{stage}] {detail}{Environment.NewLine}", new UTF8Encoding(false));
            }
        }
        catch
        {
            // Diagnostics must not become a second startup failure.
        }
    }

    public void WriteException(string stage, Exception exception) => Write(stage, exception.ToString());

    private static string RedactArgument(string argument) =>
        argument.Equals("--import", StringComparison.OrdinalIgnoreCase) || argument.EndsWith(".json", StringComparison.OrdinalIgnoreCase)
            ? "<import-file>"
            : argument;
}
