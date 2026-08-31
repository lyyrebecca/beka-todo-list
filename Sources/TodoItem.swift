import Foundation

enum TodoPriority: Int, Codable, CaseIterable, Identifiable {
    case normal = 0
    case important = 1
    case urgent = 2

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .normal: return "普通"
        case .important: return "重要 🌟"
        case .urgent: return "紧急 ‼️"
        }
    }
}

enum TodoTimeMode: String, Codable, CaseIterable, Identifiable {
    case none, deadline, period, day
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: return "无时间"
        case .deadline: return "截止日期"
        case .period: return "期间"
        case .day: return "某一天"
        }
    }
}

enum TodoReminderMode: String, Codable, CaseIterable, Identifiable {
    case none, atTime, dayBefore, dailyDuringPeriod
    var id: String { rawValue }
}

struct TodoSchedule: Codable, Equatable {
    var mode: TodoTimeMode
    var date: Date?
    var startDate: Date?
    var endDate: Date?
    var reminderMode: TodoReminderMode
    /// 当天分钟数；提前一天默认为 21:00（1260）。
    var reminderTimeMinutes: Int

    init(mode: TodoTimeMode = .none, date: Date? = nil,
         startDate: Date? = nil, endDate: Date? = nil,
         reminderMode: TodoReminderMode = .none,
         reminderTimeMinutes: Int = 21 * 60) {
        self.mode = mode
        self.date = date
        self.startDate = startDate
        self.endDate = endDate
        self.reminderMode = reminderMode
        self.reminderTimeMinutes = reminderTimeMinutes
    }

    var primaryDate: Date? {
        switch mode {
        case .none: return nil
        case .deadline, .day: return date
        case .period: return endDate
        }
    }

    static func legacy(dueDate: Date) -> TodoSchedule {
        TodoSchedule(mode: .deadline, date: dueDate, reminderMode: .atTime)
    }
}

struct TodoItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var text: String
    var createdAt: Date = Date()
    var dueDate: Date? = nil
    var schedule: TodoSchedule? = nil
    var priority: TodoPriority = .normal
    var completed: Bool = false
    var completedAt: Date? = nil

    init(id: UUID = UUID(), text: String, createdAt: Date = Date(),
         dueDate: Date? = nil, schedule: TodoSchedule? = nil,
         priority: TodoPriority = .normal, completed: Bool = false,
         completedAt: Date? = nil) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.schedule = schedule ?? dueDate.map(TodoSchedule.legacy)
        self.dueDate = self.schedule?.primaryDate ?? dueDate
        self.priority = priority
        self.completed = completed
        self.completedAt = completedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, createdAt, dueDate, schedule, priority, completed, completedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = try c.decode(String.self, forKey: .text)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        let legacyDue = try c.decodeIfPresent(Date.self, forKey: .dueDate)
        schedule = try c.decodeIfPresent(TodoSchedule.self, forKey: .schedule)
            ?? legacyDue.map(TodoSchedule.legacy)
        dueDate = schedule?.primaryDate ?? legacyDue
        priority = try c.decodeIfPresent(TodoPriority.self, forKey: .priority) ?? .normal
        completed = try c.decodeIfPresent(Bool.self, forKey: .completed) ?? false
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
    }
}
