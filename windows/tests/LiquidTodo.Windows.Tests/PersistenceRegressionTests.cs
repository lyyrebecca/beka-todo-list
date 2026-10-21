using LiquidTodo.Core;
using Xunit;

namespace LiquidTodo.Windows.Tests;

public sealed class WindowsFileSharingFactAttribute : FactAttribute
{
    public WindowsFileSharingFactAttribute()
    {
        if (!OperatingSystem.IsWindows()) Skip = "Requires actual Windows kernel file-sharing/delete semantics.";
    }
}

public sealed class PersistenceRegressionTests : IDisposable
{
    private readonly string _root = Path.Combine(Path.GetTempPath(), "LiquidTodo-Persistence-QA", Guid.NewGuid().ToString("N"));
    public PersistenceRegressionTests() => Directory.CreateDirectory(_root);
    public void Dispose() { try { Directory.Delete(_root, true); } catch { } }

    [Theory]
    [InlineData("add")]
    [InlineData("update")]
    [InlineData("move")]
    [InlineData("complete")]
    [InlineData("undo")]
    [InlineData("archive")]
    [InlineData("restore")]
    [InlineData("delete")]
    [InlineData("clear")]
    public void Failed_commit_rolls_back_visible_state_and_preserves_saved_file(string operation)
    {
        var parent = Path.Combine(_root, "state");
        var path = Path.Combine(parent, "data.json");
        var store = new TodoStore(new PersistenceService(path));
        var a = store.Add("first"); store.Add("second");
        var archived = store.Add("archived"); store.Complete(archived.Id); store.ArchiveCompleted(archived.Id);
        if (operation is "undo" or "archive") store.Complete(a.Id);
        var before = store.Snapshot();
        var saved = File.ReadAllBytes(path);
        var changed = 0; store.Changed += (_, _) => changed++;
        var retained = parent + "-retained";
        // A deterministic real IO failure on both macOS and Windows; no real data.
        Directory.Move(parent, retained);
        File.WriteAllText(parent, "A file now occupies the data-directory path.");
        try
        {
            Action action = operation switch
            {
                "add" => () => store.Add("must not survive a failed commit"),
                "update" => () => store.Update(a.Id, "changed", TodoPriority.Urgent, null),
                "move" => () => store.Move(a.Id, 1),
                "complete" => () => store.Complete(a.Id),
                "undo" => () => store.UndoCompletion(a.Id),
                "archive" => () => store.ArchiveCompleted(a.Id),
                "restore" => () => store.RestoreArchived(archived.Id),
                "delete" => () => store.Delete(a.Id),
                _ => () => store.ClearArchived()
            };
            var error = Record.Exception(action);
            Assert.True(error is IOException or UnauthorizedAccessException, "The attempted commit must actually fail.");
            Assert.Equal(before.Items, store.Items);
            Assert.Equal(before.Archived, store.Archived);
            Assert.Equal(0, changed);
            Assert.Equal(saved, File.ReadAllBytes(Path.Combine(retained, "data.json")));
        }
        finally { File.Delete(parent); Directory.Move(retained, parent); }
    }

    [WindowsFileSharingFact]
    [Trait("Environment", "WindowsKernelFileSharing")]
    public async Task Transient_reader_without_delete_share_does_not_make_atomic_save_fail()
    {
        var path = Path.Combine(_root, "transient.json");
        var persistence = new PersistenceService(path);
        var before = new TodoSnapshot([TodoItem.Create("before")], []);
        var after = new TodoSnapshot([TodoItem.Create("after")], []);
        persistence.Save(before);
        using var reader = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
        var release = Task.Run(async () => { await Task.Delay(250); reader.Dispose(); });
        try { persistence.Save(after); }
        finally { await release; }
        Assert.Equal("after", Assert.Single(persistence.Load().Items).Text);
        Assert.Empty(Directory.GetFiles(_root, "*.tmp"));
    }

    [WindowsFileSharingFact]
    [Trait("Environment", "WindowsKernelFileSharing")]
    public void Readonly_destination_failure_keeps_last_good_file_and_cleans_temp()
    {
        var path = Path.Combine(_root, "readonly.json");
        var persistence = new PersistenceService(path);
        persistence.Save(new([TodoItem.Create("keep")], []));
        var bytes = File.ReadAllBytes(path);
        File.SetAttributes(path, FileAttributes.ReadOnly);
        try
        {
            Assert.ThrowsAny<UnauthorizedAccessException>(() => persistence.Save(new([TodoItem.Create("not committed")], [])));
            Assert.Equal(bytes, File.ReadAllBytes(path));
            Assert.Empty(Directory.GetFiles(_root, "*.tmp"));
        }
        finally { File.SetAttributes(path, FileAttributes.Normal); }
    }

    [WindowsFileSharingFact]
    [Trait("Environment", "WindowsKernelFileSharing")]
    public void Locked_valid_data_is_not_misclassified_as_corrupt_or_replaced_with_empty_data()
    {
        var path = Path.Combine(_root, "locked.json");
        var persistence = new PersistenceService(path);
        persistence.Save(new([TodoItem.Create("must survive")], []));
        var bytes = File.ReadAllBytes(path);
        using (var lease = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.None))
        {
            Assert.ThrowsAny<IOException>(() => persistence.Load());
            Assert.Null(persistence.RecoveredCorruptFile);
            Assert.Empty(Directory.GetFiles(_root, "*.corrupt-*"));
        }
        Assert.Equal(bytes, File.ReadAllBytes(path));
        Assert.Equal("must survive", Assert.Single(persistence.Load().Items).Text);
    }
}
