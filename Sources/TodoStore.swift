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
    @Published var items: [TodoItem] = []
    @Published var archived: [TodoItem] = []
    @Published var isAdding = false
    @Published var isExpanded = false
    @Published var isShowingArchive = false
    @Published var isMinimized = false
    @Published var isMiniDragging = false
    @Published var editingTextId: UUID? = nil
    @Published var draggingId: UUID? = nil
    @Published private(set) var now = Date()
    @Published private(set) var persistenceError: String?

    let maxVisible = 10
    private let fileURL: URL
    private let notificationScheduler: TodoNotificationScheduling
    private let completionArchiveDelay: TimeInterval
    private var clockTimer: Timer?
    private var archiveWorkItems: [UUID: DispatchWorkItem] = [:]

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
        load()
        if startClock { startClockTimer() }
        rescheduleFutureNotifications()
        if sandbox && items.isEmpty && archived.isEmpty { seedDemo() }
    }

    deinit {
        clockTimer?.invalidate()
        archiveWorkItems.values.forEach { $0.cancel() }
    }

    var overflowCount: Int { max(0, items.count - maxVisible) }

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

    func add(text: String, priority: TodoPriority, schedule: TodoSchedule?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let item = TodoItem(text: trimmed, schedule: schedule, priority: priority)
        insertByPriority(item)
        scheduleNotification(for: item)
        save()
    }

    func moveItem(id: UUID, to target: Int) {
        guard let source = items.firstIndex(where: { $0.id == id }), !items.isEmpty else { return }
        let clamped = max(0, min(target, items.count - 1))
        guard source != clamped else { return }
        let item = items.remove(at: source)
        items.insert(item, at: clamped)
        save()
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
        items[idx].completed = true
        items[idx].completedAt = Date()
        cancelNotification(for: items[idx])
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
        archiveWorkItems.removeValue(forKey: id)?.cancel()
        items[idx].completed = false
        items[idx].completedAt = nil
        scheduleNotification(for: items[idx])
        save()
    }

    func delete(_ id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        archiveWorkItems.removeValue(forKey: id)?.cancel()
        cancelNotification(for: items[idx])
        items.remove(at: idx)
        save()
    }

    func restoreArchived(_ id: UUID) {
        guard let idx = archived.firstIndex(where: { $0.id == id }) else { return }
        var item = archived.remove(at: idx)
        item.completed = false
        item.completedAt = nil
        insertByPriority(item)
        scheduleNotification(for: item)
        save()
    }

    func deleteArchived(_ id: UUID) {
        archived.removeAll { $0.id == id }
        save()
    }

    func clearArchived() {
        archived.removeAll()
        save()
    }

    private func insertByPriority(_ item: TodoItem) {
        if let index = items.firstIndex(where: { $0.priority.rawValue < item.priority.rawValue }) {
            items.insert(item, at: index)
        } else {
            items.append(item)
        }
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
        guard let idx = items.firstIndex(where: { $0.id == id }), items[idx].completed else { return }
        let item = items.remove(at: idx)
        archived.insert(item, at: 0)
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
