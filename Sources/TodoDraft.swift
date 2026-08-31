import Foundation

struct TodoDraft {
    var text: String
    var priority: TodoPriority
    var timeMode: TodoTimeMode
    var date: Date
    var periodStart: Date
    var periodEnd: Date
    var reminderMode: TodoReminderMode
    var reminderClock: Date

    init(item: TodoItem? = nil) {
        let calendar = Calendar.current
        let now = Date()
        let defaultDate = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        let defaultClock = calendar.date(bySettingHour: 21, minute: 0, second: 0, of: now) ?? now
        let schedule = item?.schedule

        text = item?.text ?? ""
        priority = item?.priority ?? .normal
        timeMode = schedule?.mode ?? .none
        date = schedule?.date ?? defaultDate
        periodStart = schedule?.startDate ?? now
        periodEnd = schedule?.endDate ?? defaultDate
        reminderMode = schedule?.reminderMode ?? .none
        let minutes = schedule?.reminderTimeMinutes ?? 21 * 60
        reminderClock = calendar.date(bySettingHour: minutes / 60, minute: minutes % 60,
                                      second: 0, of: defaultClock) ?? defaultClock
    }

    var schedule: TodoSchedule? {
        guard timeMode != .none else { return nil }
        let minutes = Calendar.current.component(.hour, from: reminderClock) * 60
            + Calendar.current.component(.minute, from: reminderClock)
        switch timeMode {
        case .none:
            return nil
        case .deadline, .day:
            let rule: TodoReminderMode = [.atTime, .dayBefore, .none].contains(reminderMode)
                ? reminderMode : .atTime
            return TodoSchedule(mode: timeMode, date: date,
                                reminderMode: rule, reminderTimeMinutes: minutes)
        case .period:
            let start = min(periodStart, periodEnd)
            let end = max(periodStart, periodEnd)
            let rule: TodoReminderMode = reminderMode == .none ? .none : .dailyDuringPeriod
            return TodoSchedule(mode: .period, startDate: start, endDate: end,
                                reminderMode: rule, reminderTimeMinutes: minutes)
        }
    }

    mutating func selectTimeMode(_ mode: TodoTimeMode) {
        timeMode = mode
        switch mode {
        case .none: reminderMode = .none
        case .deadline, .day: reminderMode = .atTime
        case .period:
            reminderMode = .dailyDuringPeriod
            setReminderClock(hour: 9, minute: 0)
        }
    }

    mutating func selectReminderMode(_ mode: TodoReminderMode) {
        reminderMode = mode
        if mode == .dayBefore { setReminderClock(hour: 21, minute: 0) }
        if mode == .dailyDuringPeriod { setReminderClock(hour: 9, minute: 0) }
    }

    private mutating func setReminderClock(hour: Int, minute: Int) {
        reminderClock = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0,
                                              of: reminderClock) ?? reminderClock
    }
}
