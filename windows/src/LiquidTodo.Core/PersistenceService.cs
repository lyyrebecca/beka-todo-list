using System.Text.Json;

namespace LiquidTodo.Core;

public sealed class PersistenceService
{
    public PersistenceService(string dataFile) => DataFile = Path.GetFullPath(dataFile);
    public string DataFile { get; }
    public string? RecoveredCorruptFile { get; private set; }
    private static readonly int[] RetryDelaysMilliseconds = [20, 40, 80, 160, 320, 640];

    public TodoSnapshot Load()
    {
        try
        {
            return WithTransientRetry(() =>
            {
                // Readers must allow an atomic writer to replace the directory
                // entry. An open handle still sees one complete old/new file.
                using var stream = new FileStream(DataFile, FileMode.Open, FileAccess.Read,
                    FileShare.ReadWrite | FileShare.Delete);
                var snapshot = JsonSerializer.Deserialize<TodoSnapshot>(stream, LiquidTodoJson.Options)
                    ?? new TodoSnapshot([], []);
                if (snapshot.Items is null || snapshot.Archived is null || snapshot.Items.Concat(snapshot.Archived).Any(x => x is null || x.Text is null))
                    throw new InvalidDataException("Todo JSON has missing or invalid collections.");
                return Normalize(snapshot);
            });
        }
        catch (FileNotFoundException) { return new([], []); }
        catch (DirectoryNotFoundException) { return new([], []); }
        catch (Exception ex) when (ex is JsonException or InvalidDataException)
        {
            // Permission/sharing failures are NOT corrupt JSON. Let startup
            // report them without ever replacing valid data with an empty list.
            var corrupt = $"{DataFile}.corrupt-{DateTimeOffset.UtcNow:yyyyMMddHHmmss}-{Guid.NewGuid():N}";
            WithTransientRetry(() => File.Move(DataFile, corrupt));
            RecoveredCorruptFile = corrupt;
            return new([], []);
        }
    }

    public void Save(TodoSnapshot snapshot)
    {
        WithTransientRetry(() => Directory.CreateDirectory(Path.GetDirectoryName(DataFile)!));
        var tmp = $"{DataFile}.{Guid.NewGuid():N}.tmp";
        try
        {
            using (var stream = new FileStream(tmp, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            {
                JsonSerializer.Serialize(stream, Normalize(snapshot), LiquidTodoJson.Options);
                stream.Flush(flushToDisk: true);
            }
            // Antivirus/readers can briefly refuse delete sharing on Windows.
            // Retry the rename, never truncate/delete the last committed file.
            WithTransientRetry(() => File.Move(tmp, DataFile, true));
        }
        finally
        {
            try { WithTransientRetry(() => File.Delete(tmp)); }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { /* keep the original commit error */ }
        }
    }

    private static bool IsTransient(Exception exception) =>
        exception is IOException or UnauthorizedAccessException &&
        (exception.HResult & 0xffff) is 5 or 32 or 33;

    private static T WithTransientRetry<T>(Func<T> operation)
    {
        for (var attempt = 0; ; attempt++)
        {
            try { return operation(); }
            catch (Exception ex) when (IsTransient(ex) && attempt < RetryDelaysMilliseconds.Length)
            {
                Thread.Sleep(RetryDelaysMilliseconds[attempt]);
            }
        }
    }

    private static void WithTransientRetry(Action operation) => WithTransientRetry(() => { operation(); return true; });

    private static TodoSnapshot Normalize(TodoSnapshot snapshot) => new(
        snapshot.Items.Where(x => !x.Completed).Select(x => x.Normalize()).ToList(),
        snapshot.Archived.Concat(snapshot.Items.Where(x => x.Completed)).Select(x => x.Normalize()).ToList());
}
