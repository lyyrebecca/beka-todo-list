using LiquidTodo.Core;

if (args.Length != 2) throw new ArgumentException("Expected: write|verify temporary-directory");
var root = Path.GetFullPath(args[1]); Directory.CreateDirectory(root);
var backup = new BackupService();
if (args[0] == "write")
{
    var date = DateTimeOffset.Parse("2026-10-22T12:30:00Z");
    var parent = TodoItem.Create("跨平台父任务", TodoPriority.Important, new(TodoTimeMode.Deadline, date, ReminderMode: TodoReminderMode.DayBefore), date.AddDays(-1));
    var child = TodoItem.Create("期间子任务", TodoPriority.Normal, new(TodoTimeMode.Period, StartDate: new(2026, 10, 22), EndDate: new(2026, 10, 25), ReminderMode: TodoReminderMode.DailyDuringPeriod, ReminderTimeMinutes: 540), date) with { ParentId = parent.Id };
    var leaf = TodoItem.Create("已完成孙任务", TodoPriority.Urgent, now: date) with { ParentId = child.Id, Completed = true, CompletedAt = date.AddHours(1) };
    backup.Write(Path.Combine(root, "windows.json"), new([parent, child], [leaf]));
    Console.WriteLine("Windows serializer exported hierarchy v2 with UTC/date-only schedules.");
}
else if (args[0] == "verify")
{
    var original = backup.Read(Path.Combine(root, "windows.json"));
    var result = backup.Read(Path.Combine(root, "macos.json"));
    var expected = original.Items.Concat(original.Archived).ToDictionary(x => x.Id);
    if (result.SchemaVersion != 2 || result.Items.Count != 2 || result.Archived.Count != 1) throw new Exception("Cross-platform collections/version changed.");
    foreach (var item in result.Items.Concat(result.Archived))
    {
        var source = expected[item.Id];
        if (item.Text != source.Text || item.ParentId != source.ParentId || item.Priority != source.Priority || item.Completed != source.Completed || item.CreatedAt != source.CreatedAt || item.CompletedAt != source.CompletedAt || item.Schedule != source.Schedule)
            throw new Exception("Cross-platform UUID/relationship/text/priority/completion/schedule changed.");
    }
    var data = Path.Combine(root, "round-trip-data.json");
    var store = new TodoStore(new PersistenceService(data));
    store.Import(Path.Combine(root, "macos.json"), ImportMode.Replace);
    if (store.Progress(store.Items[0].Id) != (1, 2)) throw new Exception("Archived descendant progress changed.");
    if (store.Import(Path.Combine(root, "macos.json"), ImportMode.Merge).SkippedDuplicates != 3) throw new Exception("Merge failed UUID deduplication.");
    Console.WriteLine("PASS Windows -> Swift import/export -> Windows: UUIDs, recursive parents, archive, priorities, UTC and date-only schedules, merge/replace.");
}
else throw new ArgumentException("Unknown mode.");
