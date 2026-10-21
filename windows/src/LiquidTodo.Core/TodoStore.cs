namespace LiquidTodo.Core;

public sealed class TodoStore
{
    private readonly PersistenceService _persistence;
    private readonly BackupService _backups;
    private TodoSnapshot _lastCommitted;
    private readonly Dictionary<Guid, HashSet<Guid>> _completionGroups = [];
    public List<TodoItem> Items { get; private set; }
    public List<TodoItem> Archived { get; private set; }
    public string? RecoveryMessage => _persistence.RecoveredCorruptFile is { } p ? $"已隔离损坏数据：{Path.GetFileName(p)}" : null;
    public event EventHandler? Changed;

    public TodoStore(PersistenceService persistence, BackupService? backups = null)
    {
        _persistence = persistence;
        _backups = backups ?? new BackupService();
        var data = persistence.Load();
        Items = data.Items.Where(x => !x.Completed).ToList();
        Archived = data.Archived.Concat(data.Items.Where(x => x.Completed)).OrderByDescending(x => x.CompletedAt ?? x.CreatedAt).ToList();
        RepairHierarchy();
        _lastCommitted = Snapshot();
    }

    public TodoItem Add(string text, TodoPriority priority = TodoPriority.Normal, TodoSchedule? schedule = null, DateTimeOffset? now = null, Guid? parentId = null)
    {
        ValidateText(text);
        if (parentId is { } parent && !Items.Any(x => x.Id == parent && !x.Completed)) throw new ArgumentException("父待办不存在或已经完成。", nameof(parentId));
        var item = TodoItem.Create(text, priority, schedule, now) with { ParentId = parentId };
        InsertByPriority(item); Save(); return item;
    }

    public void Update(Guid id, string text, TodoPriority priority, TodoSchedule? schedule)
    {
        ValidateText(text);
        var index = Items.FindIndex(x => x.Id == id);
        if (index < 0) return;
        var item = Items[index] with { Text = text.Trim(), Priority = priority, Schedule = schedule?.Normalize(), DueDate = schedule?.Normalize().PrimaryDate };
        if (Items[index].Priority != priority)
        {
            var ids = TodoHierarchy.Descendants(id, Items);
            var descendants = Items.Where(x => x.Id != id && ids.Contains(x.Id)).ToList();
            Items.RemoveAll(x => ids.Contains(x.Id)); InsertByPriority(item);
            Items.AddRange(descendants); Items = TodoHierarchy.Ordered(Items);
        }
        else Items[index] = item;
        Save();
    }

    public void Move(Guid id, int targetIndex)
    {
        if (!Items.Any(x => x.Id == id)) return;
        Items = TodoHierarchy.MoveSibling(Items, id, targetIndex); Save();
    }

    public bool SetParent(Guid id, Guid? parentId)
    {
        var item = Items.FirstOrDefault(x => x.Id == id); if (item is null || item.Completed) return false;
        var ids = TodoHierarchy.Descendants(id, Items);
        if (parentId is { } parent && (ids.Contains(parent) || !Items.Any(x => x.Id == parent && !x.Completed))) return false;
        if (item.ParentId == parentId) return true;
        var descendants = Items.Where(x => x.Id != id && ids.Contains(x.Id)).ToList();
        Items.RemoveAll(x => ids.Contains(x.Id)); InsertByPriority(item with { ParentId = parentId });
        Items.AddRange(descendants); Items = TodoHierarchy.Ordered(Items); Save(); return true;
    }

    public (int Done, int Total) Progress(Guid id)
    {
        var all = Items.Concat(Archived).ToList(); var ids = TodoHierarchy.Descendants(id, all); ids.Remove(id);
        return (all.Count(x => ids.Contains(x.Id) && x.Completed), ids.Count);
    }

    public IReadOnlyList<TodoItem> VisibleItems(ISet<Guid> collapsed)
    {
        var hidden = new HashSet<Guid>();
        foreach (var id in collapsed.Where(id => Items.Any(x => x.Id == id))) { var descendants = TodoHierarchy.Descendants(id, Items); descendants.Remove(id); hidden.UnionWith(descendants); }
        return Items.Where(x => !hidden.Contains(x.Id)).ToList();
    }

    public Guid CompletionGroupKey(Guid id) => _completionGroups.FirstOrDefault(x => x.Value.Contains(id)).Key is var key && key != Guid.Empty ? key : id;

    public void Complete(Guid id, DateTimeOffset? now = null)
    {
        if (!Items.Any(x => x.Id == id && !x.Completed)) return;
        var ids = TodoHierarchy.Descendants(id, Items);
        Items = Items.Select(x => ids.Contains(x.Id) ? x with { Completed = true, CompletedAt = now ?? DateTimeOffset.UtcNow } : x).ToList();
        Save();
        foreach (var key in _completionGroups.Keys.Where(k => _completionGroups[k].Overlaps(ids)).ToArray()) _completionGroups.Remove(key);
        _completionGroups[id] = ids;
    }

    public void UndoCompletion(Guid id)
    {
        if (!Items.Any(x => x.Id == id && x.Completed)) return;
        var key = CompletionGroupKey(id); var ids = _completionGroups.GetValueOrDefault(key) ?? [id];
        Items = Items.Select(x => ids.Contains(x.Id) ? x with { Completed = false, CompletedAt = null } : x).ToList();
        Save(); _completionGroups.Remove(key);
    }

    public void ArchiveCompleted(Guid id)
    {
        if (!Items.Any(x => x.Id == id && x.Completed)) return;
        var key = CompletionGroupKey(id); var ids = _completionGroups.GetValueOrDefault(key) ?? TodoHierarchy.Descendants(id, Items);
        var completed = Items.Where(x => ids.Contains(x.Id) && x.Completed).ToList();
        Archived.InsertRange(0, completed); Items.RemoveAll(x => ids.Contains(x.Id) && x.Completed);
        Archived = TodoHierarchy.Ordered(Archived); Save(); _completionGroups.Remove(key);
    }

    public void RestoreArchived(Guid id)
    {
        if (!Archived.Any(x => x.Id == id)) return;
        var ids = TodoHierarchy.Descendants(id, Archived);
        var restoring = TodoHierarchy.Ordered(Archived.Where(x => ids.Contains(x.Id)));
        Archived.RemoveAll(x => ids.Contains(x.Id));
        foreach (var item in restoring) InsertByPriority(item with { Completed = false, CompletedAt = null });
        RepairHierarchy(); Save();
    }

    public void Delete(Guid id)
    {
        var ids = TodoHierarchy.Descendants(id, Items.Concat(Archived));
        Items.RemoveAll(x => ids.Contains(x.Id)); Archived.RemoveAll(x => ids.Contains(x.Id)); Save();
        foreach (var key in _completionGroups.Keys.Where(k => _completionGroups[k].Overlaps(ids)).ToArray()) _completionGroups.Remove(key);
    }
    public void DeleteArchived(Guid id)
    {
        var ids = TodoHierarchy.Descendants(id, Archived);
        Archived.RemoveAll(x => ids.Contains(x.Id)); RepairHierarchy(); Save();
    }
    public void ClearArchived() { Archived.Clear(); RepairHierarchy(); Save(); }
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
        foreach (var item in importedItems) InsertByPriority(item);
        Archived = Archived.Concat(importedArchived).OrderByDescending(x => x.CompletedAt ?? x.CreatedAt).ToList();
        RepairHierarchy(); Save(); _completionGroups.Clear(); return new(importedItems.Count, importedArchived.Count, skipped, safety);
    }

    public IReadOnlyList<ReminderRequest> UpcomingReminders(DateTimeOffset now) => Items.SelectMany(x => ReminderEngine.GetRequests(x, now)).OrderBy(x => x.At).ToList();
    public void Save()
    {
        try { _persistence.Save(Snapshot()); }
        catch
        {
            // A failed commit must not leave hidden in-memory edits that a later
            // successful operation would unexpectedly flush to disk.
            Items = [.. _lastCommitted.Items];
            Archived = [.. _lastCommitted.Archived];
            throw;
        }
        _lastCommitted = Snapshot();
        Changed?.Invoke(this, EventArgs.Empty);
    }
    private void InsertByPriority(TodoItem item)
    {
        var index = Items.FindIndex(x => x.ParentId == item.ParentId && x.Priority < item.Priority);
        if (index < 0 && Items.LastOrDefault(x => x.ParentId == item.ParentId) is { } last)
        { var tail = TodoHierarchy.Descendants(last.Id, Items); index = Items.FindLastIndex(x => tail.Contains(x.Id)) + 1; }
        Items.Insert(index < 0 ? Items.Count : index, item); Items = TodoHierarchy.Ordered(Items);
    }

    private void RepairHierarchy()
    {
        var active = Items.Select(x => x.Id).ToHashSet();
        var repaired = TodoHierarchy.Sanitized(Items.Concat(Archived));
        Items = TodoHierarchy.Ordered(repaired.Where(x => active.Contains(x.Id)));
        Archived = TodoHierarchy.Ordered(repaired.Where(x => !active.Contains(x.Id)));
    }
    public static IEnumerable<TodoItem> Sort(IEnumerable<TodoItem> items) => items.OrderByDescending(x => x.Priority);
    private static void ValidateText(string text) { if (string.IsNullOrWhiteSpace(text)) throw new ArgumentException("待办内容不能为空。", nameof(text)); }
}
