using System.Text.Json;
using System.Text.Json.Serialization;

namespace LiquidTodo.Core;

public static class LiquidTodoJson
{
    public static readonly JsonSerializerOptions Options = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) }
    };
}
