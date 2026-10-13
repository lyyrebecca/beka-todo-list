using System.Text.Json;
namespace LiquidTodo.Core;

public sealed record InstanceCommand(string Action, string? ImportPath = null)
{
    public string Serialize() => JsonSerializer.Serialize(this, LiquidTodoJson.Options);
    public static InstanceCommand Parse(string message)
    {
        // Older clients sent a single literal line; allow them to wake the window.
        if (message is "activate" or "import") return new("activate");
        try { return JsonSerializer.Deserialize<InstanceCommand>(message, LiquidTodoJson.Options) ?? new("activate"); }
        catch (JsonException) { return new("activate"); }
    }
}
