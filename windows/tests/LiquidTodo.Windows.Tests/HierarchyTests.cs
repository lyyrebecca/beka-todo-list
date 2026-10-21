using System.Text.Json;
using LiquidTodo.Core;
using Xunit;

namespace LiquidTodo.Windows.Tests;

public sealed class HierarchyTests : IDisposable
{
    private readonly string _root = Path.Combine(Path.GetTempPath(), "ltd-hierarchy-" + Guid.NewGuid());
    private string DataFile => Path.Combine(_root, "data.json");
    private TodoStore Store() => new(new PersistenceService(DataFile));
    public HierarchyTests() => Directory.CreateDirectory(_root);
    public void Dispose() { try { Directory.Delete(_root, true); } catch { } }

    [Fact] public void Nested_create_collapse_and_progress_include_archived_descendants()
    {
        var s = Store(); var p = s.Add("父"); var c = s.Add("子", parentId: p.Id); var g = s.Add("孙", parentId: c.Id);
        Assert.Equal([p.Id, c.Id, g.Id], s.Items.Select(x => x.Id));
        Assert.Equal(2, TodoHierarchy.Depth(g.Id, s.Items));
        Assert.Equal([p.Id], s.VisibleItems(new HashSet<Guid> { p.Id }).Select(x => x.Id));
        s.Complete(g.Id); s.ArchiveCompleted(g.Id);
        Assert.Equal((1, 2), s.Progress(p.Id));
        Assert.Equal(c.Id, s.Archived.Single().ParentId);
    }

    [Fact] public void Moving_parent_moves_whole_subtree_and_survives_restart()
    {
        var s = Store(); var p = s.Add("重要父", TodoPriority.Important); var c = s.Add("子", parentId: p.Id); var g = s.Add("孙", parentId: c.Id); var q = s.Add("普通");
        s.Move(p.Id, 1);
        Assert.Equal([q.Id, p.Id, c.Id, g.Id], s.Items.Select(x => x.Id));
        Assert.Equal(s.Items, Store().Items);
    }

    [Fact] public void New_priority_only_reorders_siblings_not_their_parents()
    {
        var s = Store(); var a = s.Add("A"); var b = s.Add("B"); var c = s.Add("普通子", parentId: b.Id); var important = s.Add("重要子", TodoPriority.Important, parentId: b.Id);
        Assert.Equal([a.Id, b.Id, important.Id, c.Id], s.Items.Select(x => x.Id));
        s.Update(c.Id, "编辑", TodoPriority.Urgent, null);
        Assert.Equal([a.Id, b.Id, c.Id, important.Id], s.Items.Select(x => x.Id));
    }

    [Fact] public void Reparent_and_promote_preserve_subtree_and_reject_cycles()
    {
        var s = Store(); var p = s.Add("父"); var c = s.Add("子", parentId: p.Id); var g = s.Add("孙", parentId: c.Id); var other = s.Add("另一个父");
        Assert.False(s.SetParent(p.Id, g.Id)); Assert.False(s.SetParent(c.Id, c.Id));
        Assert.True(s.SetParent(c.Id, other.Id));
        Assert.Equal(other.Id, s.Items.Single(x => x.Id == c.Id).ParentId);
        Assert.Equal(c.Id, s.Items.Single(x => x.Id == g.Id).ParentId);
        Assert.True(s.SetParent(c.Id, null)); Assert.Null(s.Items.Single(x => x.Id == c.Id).ParentId);
        Assert.Equal(1, TodoHierarchy.Depth(g.Id, s.Items));
    }

    [Fact] public void Parent_completion_undo_from_child_restores_whole_group()
    {
        var s = Store(); var p = s.Add("父"); var c = s.Add("子", parentId: p.Id); var g = s.Add("孙", parentId: c.Id);
        s.Complete(p.Id); Assert.All(s.Items, x => Assert.True(x.Completed));
        Assert.Equal(p.Id, s.CompletionGroupKey(g.Id));
        s.UndoCompletion(c.Id); Assert.All(s.Items, x => Assert.False(x.Completed));
        s.ArchiveCompleted(p.Id); Assert.Empty(s.Archived);
        s.Complete(p.Id); s.ArchiveCompleted(p.Id); Assert.Empty(s.Items); Assert.Equal(3, s.Archived.Count);
        s.RestoreArchived(p.Id); Assert.Equal([p.Id, c.Id, g.Id], s.Items.Select(x => x.Id)); Assert.Empty(s.Archived);
    }

    [Fact] public void Delete_tree_includes_already_archived_descendants()
    {
        var s = Store(); var p = s.Add("父"); var c = s.Add("子", parentId: p.Id); var q = s.Add("保留");
        s.Complete(c.Id); s.ArchiveCompleted(c.Id); s.Delete(p.Id);
        Assert.Equal(q.Id, Assert.Single(s.Items).Id); Assert.Empty(s.Archived);
    }

    [Fact] public void Missing_completed_and_archived_parents_reject_new_children()
    {
        var s = Store(); var p = s.Add("父"); s.Complete(p.Id);
        Assert.Throws<ArgumentException>(() => s.Add("子", parentId: p.Id));
        s.ArchiveCompleted(p.Id); Assert.Throws<ArgumentException>(() => s.Add("子", parentId: p.Id));
        Assert.Throws<ArgumentException>(() => s.Add("子", parentId: Guid.NewGuid()));
    }

    [Fact] public void Sanitize_cycles_orphans_duplicates_without_losing_content()
    {
        var a = TodoItem.Create("A"); var b = TodoItem.Create("B") with { ParentId = a.Id }; a = a with { ParentId = b.Id };
        var orphan = TodoItem.Create("孤儿") with { ParentId = Guid.NewGuid() };
        var repaired = TodoHierarchy.Ordered(TodoHierarchy.Sanitized([a, b, orphan, a]));
        Assert.Equal(3, repaired.Count); Assert.Null(repaired.Single(x => x.Id == orphan.Id).ParentId);
        Assert.All(repaired, x => Assert.InRange(TodoHierarchy.Depth(x.Id, repaired), 0, 2));
    }

    [Fact] public void Hierarchical_backup_uses_v2_and_flat_backup_still_uses_v1()
    {
        var s = Store(); var p = s.Add("父"); var path = Path.Combine(_root, "backup.json"); s.Export(path);
        using (var doc = JsonDocument.Parse(File.ReadAllText(path))) Assert.Equal(1, doc.RootElement.GetProperty("schemaVersion").GetInt32());
        var c = s.Add("子", parentId: p.Id); s.Export(path);
        var backup = new BackupService().Read(path); Assert.Equal(2, backup.SchemaVersion); Assert.Equal(p.Id, backup.Items.Single(x => x.Id == c.Id).ParentId);
        s.Import(path, ImportMode.Replace); Assert.Equal(p.Id, s.Items.Single(x => x.Id == c.Id).ParentId);
        Assert.Equal(2, s.Import(path, ImportMode.Merge).SkippedDuplicates);
    }

    [Fact] public void Legacy_mac_parent_UUID_is_preserved()
    {
        var p = Guid.NewGuid(); var c = Guid.NewGuid(); var path = Path.Combine(_root, "mac.json");
        File.WriteAllText(path, $$"""{"items":[{"id":"{{p}}","text":"父","createdAt":86400},{"id":"{{c}}","text":"子","parentId":"{{p}}","createdAt":86400}],"archived":[]}""");
        var b = new BackupService().Read(path); Assert.Equal(p, b.Items[1].ParentId);
    }

    [Fact] public void Restored_child_of_collapsed_archived_parent_remains_visible()
    {
        var s = Store(); var p = s.Add("父"); var c = s.Add("子", parentId: p.Id);
        s.Complete(p.Id); s.ArchiveCompleted(p.Id); s.RestoreArchived(c.Id);
        Assert.Equal(c.Id, Assert.Single(s.VisibleItems(new HashSet<Guid> { p.Id })).Id);
        s.DeleteArchived(p.Id); Assert.Equal(c.Id, Assert.Single(s.Items).Id); Assert.Null(s.Items[0].ParentId);
    }

    [Fact] public void Failed_group_undo_rolls_back_model_and_retains_undo_group()
    {
        var s = Store(); var p = s.Add("父"); var c = s.Add("子", parentId: p.Id); s.Complete(p.Id);
        var saved = _root + "-retained"; Directory.Move(_root, saved);
        File.WriteAllText(_root, "blocked directory");
        try
        {
            Assert.ThrowsAny<IOException>(() => s.UndoCompletion(c.Id));
            Assert.All(s.Items, x => Assert.True(x.Completed)); Assert.Equal(p.Id, s.CompletionGroupKey(c.Id));
        }
        finally { File.Delete(_root); Directory.Move(saved, _root); }
        s.UndoCompletion(c.Id); Assert.All(s.Items, x => Assert.False(x.Completed));
    }

    [Fact] public void Canonical_enum_values_match_Mac_schema()
    {
        var p = Path.Combine(_root, "export.json");
        var s = Store(); s.Add("兼容", TodoPriority.Important, new(TodoTimeMode.Period, StartDate: new(2026, 10, 22), EndDate: new(2026, 10, 24), ReminderMode: TodoReminderMode.DailyDuringPeriod)); s.Export(p);
        using var doc = JsonDocument.Parse(File.ReadAllText(p)); var item = doc.RootElement.GetProperty("items")[0];
        Assert.Equal("important", item.GetProperty("priority").GetString());
        Assert.Equal("period", item.GetProperty("schedule").GetProperty("mode").GetString());
        Assert.Equal("dailyDuringPeriod", item.GetProperty("schedule").GetProperty("reminderMode").GetString());
    }
}
