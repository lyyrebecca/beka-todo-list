namespace LiquidTodo.Core;

/// Flat, interoperable storage; iterative traversal also tolerates malformed imports.
public static class TodoHierarchy
{
    public static HashSet<Guid> Descendants(Guid id, IEnumerable<TodoItem> source)
    {
        var children = source.Where(x => x.ParentId.HasValue).ToLookup(x => x.ParentId!.Value);
        var found = new HashSet<Guid> { id };
        var stack = new Stack<Guid>(); stack.Push(id);
        while (stack.TryPop(out var parent))
            foreach (var child in children[parent])
                if (found.Add(child.Id)) stack.Push(child.Id);
        return found;
    }

    public static int Depth(Guid id, IEnumerable<TodoItem> source)
    {
        var map = source.DistinctBy(x => x.Id).ToDictionary(x => x.Id);
        var visited = new HashSet<Guid> { id }; var depth = 0;
        while (map.TryGetValue(id, out var item) && item.ParentId is { } parent && map.ContainsKey(parent) && visited.Add(parent))
        { depth++; id = parent; }
        return depth;
    }

    public static List<TodoItem> Ordered(IEnumerable<TodoItem> source)
    {
        var items = source.DistinctBy(x => x.Id).ToList();
        var ids = items.Select(x => x.Id).ToHashSet();
        var children = items.Where(x => x.ParentId.HasValue).ToLookup(x => x.ParentId!.Value);
        var output = new List<TodoItem>(); var seen = new HashSet<Guid>();
        void Append(TodoItem root)
        {
            var stack = new Stack<TodoItem>(); stack.Push(root);
            while (stack.TryPop(out var item))
            {
                if (!seen.Add(item.Id)) continue;
                output.Add(item);
                foreach (var child in children[item.Id].Reverse()) stack.Push(child);
            }
        }
        foreach (var item in items.Where(x => x.ParentId is null || !ids.Contains(x.ParentId.Value))) Append(item);
        foreach (var item in items) Append(item);
        return output;
    }

    public static List<TodoItem> Sanitized(IEnumerable<TodoItem> source)
    {
        var output = source.DistinctBy(x => x.Id).ToList();
        var map = output.ToDictionary(x => x.Id, x => x.ParentId);
        for (var i = 0; i < output.Count; i++)
        {
            var item = output[i]; var cursor = item.ParentId; var seen = new HashSet<Guid> { item.Id };
            while (cursor is { } parent)
            {
                if (!map.ContainsKey(parent) || !seen.Add(parent))
                { output[i] = item with { ParentId = null }; map[item.Id] = null; break; }
                cursor = map[parent];
            }
        }
        return output;
    }

    public static List<TodoItem> MoveSibling(IReadOnlyList<TodoItem> source, Guid id, int target)
    {
        var item = source.FirstOrDefault(x => x.Id == id); if (item is null) return [.. source];
        var siblings = source.Where(x => x.ParentId == item.ParentId).ToList();
        target = Math.Clamp(target, 0, siblings.Count - 1);
        if (siblings.FindIndex(x => x.Id == id) == target) return [.. source];
        var ids = Descendants(id, source); var block = source.Where(x => ids.Contains(x.Id)).ToList();
        var rest = source.Where(x => !ids.Contains(x.Id)).ToList();
        var remaining = rest.Where(x => x.ParentId == item.ParentId).ToList();
        var index = target < remaining.Count ? rest.FindIndex(x => x.Id == remaining[target].Id) : rest.Count;
        if (target >= remaining.Count && remaining.LastOrDefault() is { } last)
        { var tail = Descendants(last.Id, rest); index = rest.FindLastIndex(x => tail.Contains(x.Id)) + 1; }
        rest.InsertRange(index, block); return rest;
    }
}
