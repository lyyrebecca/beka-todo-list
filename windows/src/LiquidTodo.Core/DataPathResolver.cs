namespace LiquidTodo.Core;

public sealed record LiquidTodoPaths(string Root, string DataFile, string SettingsFile, bool IsPortable)
{
    public static LiquidTodoPaths Resolve(string[]? args = null, string? executableDirectory = null, string? localAppData = null)
    {
        args ??= Environment.GetCommandLineArgs();
        executableDirectory ??= AppContext.BaseDirectory;
        localAppData ??= Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        var portable = args.Any(a => string.Equals(a, "--portable", StringComparison.OrdinalIgnoreCase))
                       || File.Exists(Path.Combine(executableDirectory, "portable.flag"));
        var root = portable ? Path.Combine(executableDirectory, "Data") : Path.Combine(localAppData, "LiquidTodo");
        return new(root, Path.Combine(root, "data.json"), Path.Combine(root, "settings.json"), portable);
    }
}
