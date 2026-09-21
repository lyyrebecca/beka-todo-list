namespace LiquidTodo.Core;

public sealed class TodoStore
{
    private readonly PersistenceService _persistence;
    private readonly BackupService _backups;
    public List<TodoItem> Items { get; private set; }
    public List<TodoItem> Archived { get; private set; }
    public string? RecoveryMessage => _persistence.RecoveredCorruptFile is { } p ? $"已隔离损坏数据：{Path.GetFileName(p)}" : null;
    public event EventHandler? Changed;

    public TodoStore(PersistenceService persistence, BackupService? backups = null)
    {
        _persistence = persistence;
        _backups = backups ?? new BackupService();
        var data = persistence.Load();
        Items = Sort(data.Items.Where(x => !x.Completed)).ToList();
        Archived = data.Archived.Concat(data.Items.Where(x => x.Completed)).OrderByDescending(x => x.CompletedAt ?? x.CreatedAt).ToList();
    }

    public TodoItem Add(string text, TodoPriority priority = TodoPriority.Normal, TodoSchedule? schedule = null, DateTimeOffset? now = null)
    {
        ValidateText(text);
        var item = TodoItem.Create(text, priority, schedule, now);
        Items.Add(item); Items = Sort(Items).ToList(); Save(); return item;
    }

    public void Update(Guid id, string text, TodoPriority priority, TodoSchedule? schedule)
    {
        ValidateText(text);
        var index = Items.FindIndex(x => x.Id == id);
        if (index < 0) return;
        Items[index] = Items[index] with { Text = text.Trim(), Priority = priority, Schedule = schedule?.Normalize(), DueDate = schedule?.Normalize().PrimaryDate };
        Items = Sort(Items).ToList(); Save();
    }

    public void Move(Guid id, int targetIndex)
    {
        var index = Items.FindIndex(x => x.Id == id); if (index < 0) return;
        var item = Items[index]; Items.RemoveAt(index);
        Items.Insert(Math.Clamp(targetIndex, 0, Items.Count), item); Save();
    }

    public void Complete(Guid id, DateTimeOffset? now = null)
    {
        var index = Items.FindIndex(x => x.Id == id); if (index < 0) return;
        Items[index] = Items[index] with { Completed = true, CompletedAt = now ?? DateTimeOffset.UtcNow }; Save();
    }

    public void UndoCompletion(Guid id)
    {
        var index = Items.FindIndex(x => x.Id == id); if (index < 0) return;
        Items[index] = Items[index] with { Completed = false, CompletedAt = null }; Save();
    }

    public void ArchiveCompleted(Guid id)
    {
        var index = Items.FindIndex(x => x.Id == id); if (index < 0 || !Items[index].Completed) return;
        Archived.Insert(0, Items[index]); Items.RemoveAt(index); Save();
    }

    public void RestoreArchived(Guid id)
    {
        var index = Archived.FindIndex(x => x.Id == id); if (index < 0) return;
        var item = Archived[index] with { Completed = false, CompletedAt = null }; Archived.RemoveAt(index); Items.Add(item); Items = Sort(Items).ToList(); Save();
    }

    public void Delete(Guid id) { Items.RemoveAll(x => x.Id == id); Archived.RemoveAll(x => x.Id == id); Save(); }
    public void ClearArchived() { Archived.Clear(); Save(); }
    public TodoSnapshot Snapshot() => new([.. Items], [.. Archived]);
    public void Export(string path) => _backups.Write(path, Snapshot());

    public ImportResult Import(string path, ImportMode mode)
    {
        var safety = BackupService.SuggestedExportFile(Path.GetDirectoryName(_persistence.DataFile)!);
        Export(safety);
        var incoming = _backups.Read(path);
        var known = Items.Concat(Archived).Select(x => x.Id).ToHashSet();
        var skipped = 0;
        if (mode == ImportMode.Replace) { Items = []; Archived = []; known.Clear(); }
        var importedItems = new List<TodoItem>(); var importedArchived = new List<TodoItem>();
        foreach (var item in incoming.Items)
            if (known.Add(item.Id)) importedItems.Add(item with { Completed = false, CompletedAt = null }); else skipped++;
        foreach (var item in incoming.Archived)
            if (known.Add(item.Id)) importedArchived.Add(item with { Completed = true }); else skipped++;
        Items = Sort(Items.Concat(importedItems)).ToList();
        Archived = Archived.Concat(importedArchived).OrderByDescending(x => x.CompletedAt ?? x.CreatedAt).ToList();
        Save(); return new(importedItems.Count, importedArchived.Count, skipped, safety);
    }

    public IReadOnlyList<ReminderRequest> UpcomingReminders(DateTimeOffset now) => Items.SelectMany(x => ReminderEngine.GetRequests(x, now)).OrderBy(x => x.At).ToList();
    public void Save() { _persistence.Save(Snapshot()); Changed?.Invoke(this, EventArgs.Empty); }
    public static IEnumerable<TodoItem> Sort(IEnumerable<TodoItem> items) => items.OrderByDescending(x => x.Priority);
    private static void ValidateText(string text) { if (string.IsNullOrWhiteSpace(text)) throw new ArgumentException("待办内容不能为空。", nameof(text)); }
}
