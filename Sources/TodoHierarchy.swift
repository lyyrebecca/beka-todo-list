import Foundation

/// Flat storage, recursive presentation. Optional parent IDs keep old backups readable.
enum TodoHierarchy {
    static func movingSibling(_ id: UUID, to target: Int, in items: [TodoItem]) -> [TodoItem] {
        guard let item = items.first(where: { $0.id == id }) else { return items }
        let siblings = items.filter { $0.parentId == item.parentId }
        guard let source = siblings.firstIndex(where: { $0.id == id }) else { return items }
        let target = max(0, min(target, siblings.count - 1))
        guard source != target else { return items }
        let ids = descendantIDs(of: id, in: items)
        let block = items.filter { ids.contains($0.id) }
        var remainingItems = items.filter { !ids.contains($0.id) }
        let remaining = remainingItems.filter { $0.parentId == item.parentId }
        let index: Int
        if target < remaining.count {
            index = remainingItems.firstIndex { $0.id == remaining[target].id }!
        } else if let last = remaining.last {
            let tail = descendantIDs(of: last.id, in: remainingItems)
            index = remainingItems.lastIndex { tail.contains($0.id) }! + 1
        } else { index = remainingItems.count }
        remainingItems.insert(contentsOf: block, at: index)
        return remainingItems
    }

    static func descendantIDs(of id: UUID, in items: [TodoItem]) -> Set<UUID> {
        let children = Dictionary(grouping: items, by: { $0.parentId })
        var found: Set<UUID> = [id]
        var queue = [id]
        while let parent = queue.popLast() {
            for child in children[parent] ?? [] where found.insert(child.id).inserted {
                queue.append(child.id)
            }
        }
        return found
    }

    static func depth(of id: UUID, in items: [TodoItem]) -> Int {
        let map = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var cursor = map[id]?.parentId
        var visited: Set<UUID> = [id]
        var depth = 0
        while let parent = cursor, visited.insert(parent).inserted, let item = map[parent] {
            depth += 1
            cursor = item.parentId
        }
        return depth
    }

    /// Preserve sibling order, including manual ordering; roots may refer to an
    /// archived parent, which must not make active children disappear.
    static func ordered(_ items: [TodoItem]) -> [TodoItem] {
        let ids = Set(items.map(\.id))
        let children = Dictionary(grouping: items, by: { $0.parentId })
        var output: [TodoItem] = []
        var visited = Set<UUID>()
        func append(_ item: TodoItem) {
            guard visited.insert(item.id).inserted else { return }
            output.append(item)
            for child in children[item.id] ?? [] { append(child) }
        }
        for item in items where item.parentId == nil || !ids.contains(item.parentId!) { append(item) }
        for item in items { append(item) } // Malformed legacy cycles are still visible.
        return output
    }

    /// Repair only broken relationships, not valid ordering. Call on the union
    /// of active and archived items so references across the two lists survive.
    static func sanitized(_ items: [TodoItem]) -> [TodoItem] {
        var seen = Set<UUID>()
        var output = items.filter { seen.insert($0.id).inserted }
        let ids = Set(output.map(\.id))
        var parents = Dictionary(uniqueKeysWithValues: output.map { ($0.id, $0.parentId) })
        for index in output.indices {
            let id = output[index].id
            var cursor = output[index].parentId
            var path: Set<UUID> = [id]
            var invalid = false
            while let parent = cursor {
                guard ids.contains(parent), path.insert(parent).inserted else { invalid = true; break }
                cursor = parents[parent] ?? nil
            }
            if invalid { output[index].parentId = nil; parents[id] = .some(nil) }
        }
        return output
    }
}

struct TodoReorderPreview {
    var id: UUID
    var frames: [UUID: CGRect]
    var originalItems: [TodoItem]
    var targetSiblingIndex: Int
    var translation: CGFloat
    var offsets: [UUID: CGFloat]

    /// Measure real variable-height rows and their actual spacing. Previewing
    /// moves drawing only: no disk writes or list reparenting on pointer events.
    static func offsets(original: [TodoItem], reordered: [TodoItem], frames: [UUID: CGRect],
                        draggedIDs: Set<UUID>, translation: CGFloat) -> [UUID: CGFloat] {
        let measured = original.filter { frames[$0.id] != nil }
        guard let first = measured.first, var y = frames[first.id]?.minY else { return [:] }
        let gaps = zip(measured, measured.dropFirst()).map {
            max(0, frames[$0.1.id]!.minY - frames[$0.0.id]!.maxY)
        }.sorted()
        let gap = gaps.isEmpty ? 0 : gaps[gaps.count / 2]
        var offsets: [UUID: CGFloat] = [:]
        for item in reordered {
            guard let frame = frames[item.id] else { continue }
            offsets[item.id] = draggedIDs.contains(item.id) ? translation : y - frame.minY
            y += frame.height + gap
        }
        return offsets
    }
}
