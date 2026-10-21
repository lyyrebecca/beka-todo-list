import Foundation

/// v1 flat backups remain readable; hierarchy uses v2 so old clients reject it
/// explicitly instead of silently flattening and losing parent relationships.
struct TodoBackupDocument: Codable {
    static let supportedVersions: Set<Int> = [1, 2]
    var schemaVersion: Int
    var exportedAt: String
    var items: [TodoBackupItem]
    var archived: [TodoBackupItem]
}

struct TodoBackupItem: Codable {
    var id: UUID
    var text: String
    var createdAt: String
    var dueDate: String?
    var schedule: TodoBackupSchedule?
    var priority: String
    var completed: Bool
    var completedAt: String?
    var parentId: UUID?

    init(_ item: TodoItem) {
        id = item.id; text = item.text; createdAt = Self.iso(item.createdAt)
        dueDate = item.dueDate.map(Self.iso); schedule = item.schedule.map(TodoBackupSchedule.init)
        priority = ["normal", "important", "urgent"][item.priority.rawValue]
        completed = item.completed; completedAt = item.completedAt.map(Self.iso)
        parentId = item.parentId
    }
    func todoItem() -> TodoItem? {
        guard let created = Self.date(createdAt) else { return nil }
        let p: TodoPriority = priority == "urgent" ? .urgent : priority == "important" ? .important : .normal
        return TodoItem(id: id, text: text, createdAt: created, dueDate: dueDate.flatMap(Self.date),
                        schedule: schedule?.todoSchedule(), priority: p, completed: completed,
                        completedAt: completedAt.flatMap(Self.date), parentId: parentId)
    }
    static let formatter: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()
    static func iso(_ date: Date) -> String { formatter.string(from: date) }
    static func date(_ string: String) -> Date? { formatter.date(from: string) ?? ISO8601DateFormatter().date(from: string) }
}

struct TodoBackupSchedule: Codable {
    var mode: String; var date: String?; var startDate: String?; var endDate: String?
    var reminderMode: String; var reminderTimeMinutes: Int
    init(_ schedule: TodoSchedule) {
        mode = schedule.mode.rawValue; date = schedule.date.map(TodoBackupItem.iso)
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        startDate = schedule.startDate.map(f.string); endDate = schedule.endDate.map(f.string)
        reminderMode = schedule.reminderMode.rawValue; reminderTimeMinutes = schedule.reminderTimeMinutes
    }
    func todoSchedule() -> TodoSchedule? {
        guard let m = TodoTimeMode(rawValue: mode), let r = TodoReminderMode(rawValue: reminderMode) else { return nil }
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return TodoSchedule(mode: m, date: date.flatMap(TodoBackupItem.date), startDate: startDate.flatMap(f.date), endDate: endDate.flatMap(f.date), reminderMode: r, reminderTimeMinutes: reminderTimeMinutes)
    }
}
