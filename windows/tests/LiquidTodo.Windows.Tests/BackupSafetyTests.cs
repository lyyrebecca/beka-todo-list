using Xunit;
using LiquidTodo.Core;
namespace LiquidTodo.Windows.Tests;
public class BackupSafetyTests
{
    [Theory]
    [InlineData("{\"schemaVersion\":99,\"items\":[],\"archived\":[]}")]
    [InlineData("{\"schemaVersion\":1,\"items\":null,\"archived\":[]}")]
    [InlineData("{}")]
    [InlineData("[]")]
    public void Invalid_backup_replace_does_not_clear_local_items(string json)
    {
        var root = Path.Combine(Path.GetTempPath(), "ltd-backup-" + Guid.NewGuid()); Directory.CreateDirectory(root);
        try
        {
            var store = new TodoStore(new PersistenceService(Path.Combine(root,"data.json"))); store.Add("keep me");
            var path = Path.Combine(root,"incoming.json"); File.WriteAllText(path,json);
            Assert.Throws<InvalidDataException>(() => store.Import(path, ImportMode.Replace));
            Assert.Equal("keep me", Assert.Single(store.Items).Text);
            Assert.Equal("keep me", Assert.Single(new TodoStore(new PersistenceService(Path.Combine(root,"data.json"))).Items).Text);
        }
        finally { Directory.Delete(root,true); }
    }
    [Fact] public void Rapid_safety_backups_never_share_a_filename() =>
        Assert.NotEqual(BackupService.SuggestedExportFile("x"), BackupService.SuggestedExportFile("x"));
}
