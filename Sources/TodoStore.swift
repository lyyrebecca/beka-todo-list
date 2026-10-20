import Foundation
import SwiftUI
import UserNotifications

protocol TodoNotificationScheduling {
    func schedule(identifier: String, text: String, date: Date)
    func cancel(identifiers: [String])
}

struct SystemTodoNotificationScheduler: TodoNotificationScheduling {
    func schedule(identifier: String, text: String, date: Date) {
        guard date > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = "贝卡の Todo list"
        content.body = text
        content.sound = .default
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { NSLog("待办通知设置失败：\(error)") }
        }
    }

    func cancel(identifiers: [String]) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}

struct TodoReminderRequest: Equatable {
    var identifier: String
    var date: Date
}

@MainActor
final class TodoStore: ObservableObject {
    @Published var items: [TodoItem] = [] { didSet { presentationCache = nil } }
    @Published var archived: [TodoItem] = [] { didSet { presentationCache = nil } }
    private var presentationCache: TodoHierarchyPresentation?
    private(set) var presentationBuildCount = 0
    private var presentation: TodoHierarchyPresentation {
        if let presentationCache { return presentationCache }
        let snapshot = TodoHierarchyPresentation(items: items, archived: archived)
        presentationCache = snapshot; presentationBuildCount += 1
        return snapshot
    }
    @Published var isAdding = false
    @Published var isExpanded = false
    @Published var isShowingArchive = false
    @Published var isMinimized = false
    @Published var isMiniDragging = false
    @Published var editingTextId: UUID? = nil
    @Published var draggingId: UUID? = nil
    @Published var addingParentId: UUID? = nil
    @Published var collapsedIds: Set<UUID> = []
    @Published private(set) var reorderPreview: TodoReorderPreview?
    private var rowFrames: [UUID: CGRect] = [:]
    @Published private(set) var now = Date()
    @Published private(set) var persistenceError: String?
    @Published private(set) var ownerName: String
    @Published var isShowingNameSetup: Bool

    var displayName: String { "\(ownerName)の Todo list 🌟" }

    let maxVisible = 10
    private let fileURL: URL
    private let notificationScheduler: TodoNotificationScheduling
    private let completionArchiveDelay: TimeInterval
    private var clockTimer: Timer?
    private var archiveWorkItems: [UUID: DispatchWorkItem] = [:]
    private var completionGroups: [UUID: Set<UUID>] = [:]

    convenience init() {
        self.init(fileURL: nil, startClock: true,
                  notificationScheduler: SystemTodoNotificationScheduler(),
                  completionArchiveDelay: 4)
    }

    init(fileURL: URL?, startClock: Bool,
         notificationScheduler: TodoNotificationScheduling,
         completionArchiveDelay: TimeInterval) {
        let sandbox = ProcessInfo.processInfo.environment["LIQUIDTODO_SANDBOX"] == "1"
        let fm = FileManager.default
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(sandbox ? "LiquidTodo-sandbox" : "LiquidTodo", isDirectory: true)
            do { try fm.createDirectory(at: base, withIntermediateDirectories: true) }
            catch { NSLog("无法创建数据目录：\(error)") }
            self.fileURL = base.appendingPathComponent("data.json")
        }
        self.notificationScheduler = notificationScheduler
        self.completionArchiveDelay = completionArchiveDelay
        let savedOwner = UserDefaults.standard.string(forKey: "todoOwnerName")
        self.ownerName = savedOwner?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? savedOwner! : "贝卡"
        self.isShowingNameSetup = savedOwner == nil
        load()
        if startClock { startClockTimer() }
        rescheduleFutureNotifications()
        if sandbox && items.isEmpty && archived.isEmpty { seedDemo() }
    }

    deinit {
        clockTimer?.invalidate()
        archiveWorkItems.values.forEach { $0.cancel() }
    }

    var visibleItems: [TodoItem] {
        let map = presentation.activeByID
        return items.filter { item in
            var cursor = item.parentId
            var visited = Set<UUID>()
            while let id = cursor, visited.insert(id).inserted, let parent = map[id] {
                if collapsedIds.contains(id) { return false }
                cursor = parent.parentId
            }
            return true
        }
    }

    var overflowCount: Int { max(0, visibleItems.count - maxVisible) }
    func depth(of id: UUID) -> Int { presentation.depths[id] ?? 0 }
    func hasChildren(_ id: UUID) -> Bool { (presentation.progress[id]?.total ?? 0) > 0 }
    func hasActiveChildren(_ id: UUID) -> Bool { presentation.activeParentIDs.contains(id) }
    func childProgress(_ id: UUID) -> (done: Int, total: Int) {
        let progress = presentation.progress[id]
        return (progress?.done ?? 0, progress?.total ?? 0)
    }

    func toggleChildren(_ id: UUID) {
        if !collapsedIds.insert(id).inserted { collapsedIds.remove(id) }
    }

    func setOwnerName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        ownerName = trimmed.isEmpty ? "贝卡" : String(trimmed.prefix(20))
        UserDefaults.standard.set(ownerName, forKey: "todoOwnerName")
        isShowingNameSetup = false
    }

    func isOverdue(_ item: TodoItem) -> Bool {
        if item.schedule?.mode == .period, let end = item.schedule?.endDate,
           let endOfDay = Calendar.current.date(byAdding: DateComponents(day: 1, second: -1),
                                                to: Calendar.current.startOfDay(for: end)) {
            return !item.completed && endOfDay <= now
        }
        guard let due = item.dueDate, !item.completed else { return false }
        return due <= now
    }

    func add(text: String, due: Date?) {
        add(text: text, priority: .normal,
            schedule: due.map(TodoSchedule.legacy))
    }

    @discardableResult
    func add(text: String, priority: TodoPriority, schedule: TodoSchedule?, parentId: UUID? = nil) -> UUID? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let parentId, !items.contains(where: { $0.id == parentId && !$0.completed }) { return nil }
        let item = TodoItem(text: trimmed, schedule: schedule, priority: priority, parentId: parentId)
        insertByPriority(item)
        if let parentId { collapsedIds.remove(parentId) }
        scheduleNotification(for: item)
        save()
        return item.id
    }

    func moveItem(id: UUID, to target: Int) {
        guard let source = items.firstIndex(where: { $0.id == id }), !items.isEmpty else { return }
        let clamped = max(0, min(target, items.count - 1))
        guard source != clamped else { return }
        let item = items[source], targetItem = items[clamped]
        guard item.parentId == targetItem.parentId else { return }
        let siblings = items.filter { $0.parentId == item.parentId }
        guard let targetIndex = siblings.firstIndex(where: { $0.id == targetItem.id }) else { return }
        moveSibling(id: id, to: targetIndex)
    }

    func moveSibling(id: UUID, to target: Int) {
        let moved = TodoHierarchy.movingSibling(id, to: target, in: items)
        guard moved != items else { return }
        items = moved
        save()
    }

    func updateRowFrames(_ frames: [UUID: CGRect]) { rowFrames = frames }

    func beginRowDrag(_ id: UUID) {
        guard reorderPreview == nil, let item = items.first(where: { $0.id == id }),
              rowFrames[id] != nil else { return }
        let siblings = items.filter { $0.parentId == item.parentId }
        guard let index = siblings.firstIndex(where: { $0.id == id }) else { return }
        draggingId = id
        reorderPreview = TodoReorderPreview(id: id, frames: rowFrames,
            originalItems: items, draggedIDs: TodoHierarchy.descendantIDs(of: id, in: items),
            targetSiblingIndex: index, translation: 0, offsets: [:])
    }

    func updateRowDrag(translation: CGFloat) {
        guard var preview = reorderPreview, let dragged = preview.originalItems.first(where: { $0.id == preview.id }),
              let origin = preview.frames[preview.id] else { return }
        let siblings = preview.originalItems.filter { $0.parentId == dragged.parentId }
        let measuredSiblings = siblings.filter { preview.frames[$0.id] != nil }
        let center = origin.midY + translation
        let preceding = measuredSiblings.filter { $0.id != preview.id && preview.frames[$0.id]!.midY < center }
        if let last = preceding.last {
            let otherSiblings = siblings.filter { $0.id != preview.id }
            preview.targetSiblingIndex = (otherSiblings.firstIndex { $0.id == last.id } ?? 0) + 1
        } else if let first = measuredSiblings.first {
            preview.targetSiblingIndex = siblings.firstIndex { $0.id == first.id } ?? 0
        }
        let moved = TodoHierarchy.movingSibling(preview.id, to: preview.targetSiblingIndex, in: preview.originalItems)
        preview.translation = translation
        preview.offsets = TodoReorderPreview.offsets(original: preview.originalItems, reordered: moved,
            frames: preview.frames, draggedIDs: preview.draggedIDs, translation: translation)
        reorderPreview = preview
    }

    func finishRowDrag(cancelled: Bool = false) {
        guard let preview = reorderPreview else { return }
        reorderPreview = nil; draggingId = nil
        if !cancelled, items.map(\.id) == preview.originalItems.map(\.id) {
            moveSibling(id: preview.id, to: preview.targetSiblingIndex)
        }
    }

    func isInDraggingSubtree(_ id: UUID) -> Bool {
        guard let preview = reorderPreview else { return false }
        return preview.draggedIDs.contains(id)
    }

    @discardableResult
    func setParent(_ id: UUID, to parentId: UUID?) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id && !$0.completed }) else { return false }
        let ids = TodoHierarchy.descendantIDs(of: id, in: items)
        if let parentId {
            guard !ids.contains(parentId), items.contains(where: { $0.id == parentId && !$0.completed }) else { return false }
        }
        var item = items[index]
        guard item.parentId != parentId else { return true }
        let children = items.filter { ids.contains($0.id) && $0.id != id }
        items.removeAll { ids.contains($0.id) }
        item.parentId = parentId
        insertByPriority(item)
        items.append(contentsOf: children)
        items = TodoHierarchy.ordered(items)
        if let parentId { collapsedIds.remove(parentId) }
        save()
        return true
    }

    func updateText(_ id: UUID, _ text: String) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        update(id, text: text, priority: item.priority, schedule: item.schedule)
    }

    func update(_ id: UUID, text: String, due: Date?) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        update(id, text: text, priority: item.priority,
               schedule: due.map(TodoSchedule.legacy))
    }

    func update(_ id: UUID, text: String, priority: TodoPriority,
                schedule: TodoSchedule?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let idx = items.firstIndex(where: { $0.id == id }) else { return }
        cancelNotification(for: items[idx])
        var item = items.remove(at: idx)
        let priorityChanged = item.priority != priority
        item.text = trimmed
        item.priority = priority
        item.schedule = schedule
        item.dueDate = schedule?.primaryDate
        if priorityChanged {
            insertByPriority(item)
        } else {
            items.insert(item, at: min(idx, items.count))
        }
        scheduleNotification(for: item)
        save()
    }

    func setDue(_ id: UUID, _ due: Date?) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        cancelNotification(for: items[idx])
        items[idx].dueDate = due
        items[idx].schedule = due.map(TodoSchedule.legacy)
        scheduleNotification(for: items[idx])
        save()
    }

    func complete(_ id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }), !items[idx].completed else { return }
        let ids = TodoHierarchy.descendantIDs(of: id, in: items)
        for key in Array(completionGroups.keys) where !(completionGroups[key] ?? []).isDisjoint(with: ids) {
            archiveWorkItems.removeValue(forKey: key)?.cancel()
            completionGroups.removeValue(forKey: key)
        }
        let completedAt = Date()
        for index in items.indices where ids.contains(items[index].id) {
            items[index].completed = true
            items[index].completedAt = completedAt
            cancelNotification(for: items[index])
        }
        completionGroups[id] = ids
        save()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in self?.archiveIfCompleted(id) }
        }
        archiveWorkItems[id]?.cancel()
        archiveWorkItems[id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + completionArchiveDelay, execute: work)
    }

    func undoCompletion(_ id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }), items[idx].completed else { return }
        let group = completionGroups.first { $0.value.contains(id) }
        let ids = group?.value ?? [id]
        let key = group?.key ?? id
        archiveWorkItems.removeValue(forKey: key)?.cancel()
        completionGroups.removeValue(forKey: key)
        for index in items.indices where ids.contains(items[index].id) {
            items[index].completed = false
            items[index].completedAt = nil
            scheduleNotification(for: items[index])
        }
        save()
    }

    func delete(_ id: UUID) {
        guard items.contains(where: { $0.id == id }) else { return }
        let ids = TodoHierarchy.descendantIDs(of: id, in: items + archived)
        for item in items where ids.contains(item.id) { cancelNotification(for: item) }
        for key in Array(archiveWorkItems.keys) where ids.contains(key) {
            archiveWorkItems.removeValue(forKey: key)?.cancel(); completionGroups.removeValue(forKey: key)
        }
        items.removeAll { ids.contains($0.id) }
        archived.removeAll { ids.contains($0.id) }
        collapsedIds.subtract(ids)
        save()
    }

    func restoreArchived(_ id: UUID) {
        guard archived.contains(where: { $0.id == id }) else { return }
        let ids = TodoHierarchy.descendantIDs(of: id, in: archived)
        let restoring = TodoHierarchy.ordered(archived.filter { ids.contains($0.id) })
        archived.removeAll { ids.contains($0.id) }
        for var item in restoring {
            item.completed = false; item.completedAt = nil
            insertByPriority(item)
            scheduleNotification(for: item)
        }
        save()
    }

    func deleteArchived(_ id: UUID) {
        let ids = TodoHierarchy.descendantIDs(of: id, in: archived)
        archived.removeAll { ids.contains($0.id) }
        repairHierarchy()
        save()
    }

    func clearArchived() {
        archived.removeAll()
        repairHierarchy()
        save()
    }

    func exportBackup(to url: URL) throws {
        let version = (items + archived).contains(where: { $0.parentId != nil }) ? 2 : 1
        let backup = TodoBackupDocument(schemaVersion: version, exportedAt: TodoBackupItem.iso(Date()),
                                  items: items.map(TodoBackupItem.init), archived: archived.map(TodoBackupItem.init))
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(backup).write(to: url, options: .atomic)
    }

    /// 导入前先在同目录自动保留本机快照；默认合并，UUID 相同则保留本机记录。
    func importBackup(from url: URL, replacing: Bool) throws {
        let decoder = JSONDecoder()
        let backup = try decoder.decode(TodoBackupDocument.self, from: Data(contentsOf: url))
        guard TodoBackupDocument.supportedVersions.contains(backup.schemaVersion) else { throw CocoaError(.fileReadCorruptFile) }
        let safety = fileURL.deletingLastPathComponent().appendingPathComponent("LiquidTodo-auto-backup-\(Int(Date().timeIntervalSince1970)).json")
        try exportBackup(to: safety)
        var known = Set((replacing ? [] : items + archived).map(\.id))
        let incomingItems = backup.items.compactMap { $0.todoItem() }.filter { known.insert($0.id).inserted }
        let incomingArchived = backup.archived.compactMap { $0.todoItem() }.filter { known.insert($0.id).inserted }
        if replacing { items = []; archived = [] }
        for var item in incomingItems { item.completed = false; item.completedAt = nil; insertByPriority(item) }
        archived.append(contentsOf: incomingArchived)
        archived.sort { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) }
        repairHierarchy(); rescheduleFutureNotifications(); save()
    }

    private func insertByPriority(_ item: TodoItem) {
        if let index = items.firstIndex(where: { $0.parentId == item.parentId && $0.priority.rawValue < item.priority.rawValue }) {
            items.insert(item, at: index)
        } else if let last = items.last(where: { $0.parentId == item.parentId }) {
            let ids = TodoHierarchy.descendantIDs(of: last.id, in: items)
            items.insert(item, at: items.lastIndex(where: { ids.contains($0.id) })! + 1)
        } else {
            items.append(item)
        }
        items = TodoHierarchy.ordered(items)
    }

    private func repairHierarchy() {
        let active = Set(items.map(\.id))
        let repaired = TodoHierarchy.sanitized(items + archived)
        items = TodoHierarchy.ordered(repaired.filter { active.contains($0.id) })
        archived = TodoHierarchy.ordered(repaired.filter { !active.contains($0.id) })
    }

    private struct Snapshot: Codable { var items: [TodoItem]; var archived: [TodoItem] }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let snap = try JSONDecoder().decode(Snapshot.self, from: data)
            let pendingArchived = snap.items.filter(\.completed)
            items = snap.items.filter { !$0.completed }
            archived = (pendingArchived + snap.archived)
                .sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) }
            repairHierarchy()
            if !pendingArchived.isEmpty { save() }
        } catch {
            persistenceError = "数据读取失败：\(error.localizedDescription)"
            NSLog("\(persistenceError!)")
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let snap = Snapshot(items: items, archived: archived)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(snap).write(to: fileURL, options: .atomic)
            persistenceError = nil
        } catch {
            persistenceError = "数据保存失败：\(error.localizedDescription)"
            NSLog("\(persistenceError!)")
        }
    }

    private func archiveIfCompleted(_ id: UUID) {
        archiveWorkItems.removeValue(forKey: id)
        guard items.contains(where: { $0.id == id && $0.completed }) else { return }
        let ids = completionGroups.removeValue(forKey: id) ?? [id]
        let completed = items.filter { ids.contains($0.id) && $0.completed }
        items.removeAll { ids.contains($0.id) && $0.completed }
        archived.insert(contentsOf: completed, at: 0)
        archived = TodoHierarchy.ordered(archived)
        save()
    }

    private func startClockTimer() {
        clockTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.now = Date() }
        }
        now = Date()
    }

    private func rescheduleFutureNotifications() { items.forEach { scheduleNotification(for: $0) } }

    private func scheduleNotification(for item: TodoItem) {
        guard !item.completed else { return }
        for request in Self.reminderRequests(for: item) {
            notificationScheduler.schedule(identifier: request.identifier,
                                           text: item.text, date: request.date)
        }
    }

    private func cancelNotification(for item: TodoItem) {
        let identifiers = Self.allReminderIdentifiers(for: item)
        notificationScheduler.cancel(identifiers: identifiers)
    }

    static func reminderRequests(for item: TodoItem, now: Date = Date(),
                                 calendar: Calendar = .current) -> [TodoReminderRequest] {
        guard let schedule = item.schedule else { return [] }
        let prefix = item.id.uuidString
        var requests: [TodoReminderRequest] = []

        switch schedule.reminderMode {
        case .none:
            break
        case .atTime:
            if let date = schedule.date, date > now {
                requests.append(TodoReminderRequest(identifier: prefix, date: date))
            }
        case .dayBefore:
            if let eventDate = schedule.date {
                let day = calendar.date(byAdding: .day, value: -1,
                                        to: calendar.startOfDay(for: eventDate))!
                let date = calendar.date(byAdding: .minute,
                                         value: schedule.reminderTimeMinutes, to: day)!
                if date > now {
                    requests.append(TodoReminderRequest(identifier: prefix + "-day-before", date: date))
                }
            }
        case .dailyDuringPeriod:
            guard let start = schedule.startDate, let end = schedule.endDate else { break }
            var day = calendar.startOfDay(for: min(start, end))
            let last = calendar.startOfDay(for: max(start, end))
            var count = 0
            while day <= last && count < 60 {
                let date = calendar.date(byAdding: .minute,
                                         value: schedule.reminderTimeMinutes, to: day)!
                if date > now {
                    let comps = calendar.dateComponents([.year, .month, .day], from: day)
                    let suffix = String(format: "%04d%02d%02d",
                                        comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
                    requests.append(TodoReminderRequest(identifier: prefix + "-daily-" + suffix,
                                                        date: date))
                }
                day = calendar.date(byAdding: .day, value: 1, to: day)!
                count += 1
            }
        }
        return requests
    }

    private static func allReminderIdentifiers(for item: TodoItem,
                                               calendar: Calendar = .current) -> [String] {
        let prefix = item.id.uuidString
        guard let schedule = item.schedule else { return [prefix] }
        switch schedule.reminderMode {
        case .none: return [prefix]
        case .atTime: return [prefix]
        case .dayBefore: return [prefix + "-day-before"]
        case .dailyDuringPeriod:
            guard let start = schedule.startDate, let end = schedule.endDate else { return [] }
            var ids: [String] = []
            var day = calendar.startOfDay(for: min(start, end))
            let last = calendar.startOfDay(for: max(start, end))
            var count = 0
            while day <= last && count < 60 {
                let comps = calendar.dateComponents([.year, .month, .day], from: day)
                ids.append(prefix + String(format: "-daily-%04d%02d%02d",
                                           comps.year ?? 0, comps.month ?? 0, comps.day ?? 0))
                day = calendar.date(byAdding: .day, value: 1, to: day)!
                count += 1
            }
            return ids
        }
    }

    private func seedDemo() {
        let cal = Calendar.current
        let today = cal.date(byAdding: .hour, value: 2, to: Date())
        let tomorrow = cal.date(bySettingHour: 9, minute: 0, second: 0,
                                of: cal.date(byAdding: .day, value: 1, to: Date())!)
        items = [
            TodoItem(text: "给研一新生发课程大纲", dueDate: today),
            TodoItem(text: "审阅三篇开题报告并写批注"),
            TodoItem(text: "回复教务处关于排课的邮件", dueDate: tomorrow),
            TodoItem(text: "整理民事诉讼法讲义第三章"),
        ]
        save()
    }
}
