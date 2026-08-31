import Foundation

final class FakeNotificationScheduler: TodoNotificationScheduling {
    var scheduled: [(String, String, Date)] = []
    var cancelled: [[String]] = []

    func schedule(identifier: String, text: String, date: Date) {
        scheduled.append((identifier, text, date))
    }
    func cancel(identifiers: [String]) { cancelled.append(identifiers) }
}

@main
struct TodoStoreTests {
    private static var passed = 0

    @MainActor
    static func main() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LiquidTodoTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try testAddEditReorderAndPersistence(root)
        try testDueNotificationLifecycle(root)
        try testScheduleModesAndPriority(root)
        try testCompleteUndoArchiveAndRestore(root)
        try testCompletedItemMigration(root)
        print("✅ TodoStore tests: \(passed) assertions passed")
    }

    @MainActor
    private static func makeStore(_ url: URL, scheduler: FakeNotificationScheduler,
                                  delay: TimeInterval = 4) -> TodoStore {
        TodoStore(fileURL: url, startClock: false,
                  notificationScheduler: scheduler, completionArchiveDelay: delay)
    }

    @MainActor
    private static func testAddEditReorderAndPersistence(_ root: URL) throws {
        let url = root.appendingPathComponent("basic.json")
        let fake = FakeNotificationScheduler()
        let store = makeStore(url, scheduler: fake)
        store.add(text: "   第一项  ", due: nil)
        store.add(text: "\n", due: nil)
        store.add(text: "第二项", due: nil)
        check(store.items.map(\.text) == ["第一项", "第二项"], "添加会去空白并拒绝空内容")

        let first = store.items[0].id
        store.updateText(first, "  修改后  ")
        store.updateText(first, "   ")
        check(store.items[0].text == "修改后", "编辑会去空白且不会把待办改为空")
        store.moveItem(id: first, to: 1)
        check(store.items.map(\.text) == ["第二项", "修改后"], "拖动排序写入正确顺序")

        let reloaded = makeStore(url, scheduler: FakeNotificationScheduler())
        check(reloaded.items.map(\.text) == ["第二项", "修改后"], "重启后数据和顺序保持")
        check(reloaded.persistenceError == nil, "正常保存没有持久化错误")
    }

    @MainActor
    private static func testDueNotificationLifecycle(_ root: URL) throws {
        let url = root.appendingPathComponent("due.json")
        let fake = FakeNotificationScheduler()
        let store = makeStore(url, scheduler: fake)
        let future = Date().addingTimeInterval(3600)
        store.add(text: "带提醒", due: future)
        let id = store.items[0].id
        check(fake.scheduled.last?.0 == id.uuidString, "添加未来截止时间会安排通知")
        store.updateText(id, "新提醒文字")
        check(fake.cancelled.flatMap { $0 }.contains(id.uuidString)
              && fake.scheduled.last?.1 == "新提醒文字",
              "编辑文字会同步刷新通知内容")
        store.setDue(id, nil)
        check(fake.cancelled.last?.contains(id.uuidString) == true, "清除截止时间会取消通知")
        let changedDue = Date().addingTimeInterval(7200)
        store.update(id, text: "统一编辑", due: changedDue)
        check(store.items[0].text == "统一编辑" && store.items[0].dueDate == changedDue,
              "统一编辑器可同时修改文字和截止时间")
        check(fake.scheduled.last?.0 == id.uuidString && fake.scheduled.last?.2 == changedDue,
              "统一修改截止时间后会同步刷新通知")
    }

    @MainActor
    private static func testScheduleModesAndPriority(_ root: URL) throws {
        let url = root.appendingPathComponent("schedule.json")
        let fake = FakeNotificationScheduler()
        let store = makeStore(url, scheduler: fake)
        store.add(text: "普通", priority: .normal, schedule: nil)
        store.add(text: "重要", priority: .important, schedule: nil)
        store.add(text: "紧急", priority: .urgent, schedule: nil)
        check(store.items.map(\.text) == ["紧急", "重要", "普通"],
              "重要和紧急待办创建后按级别自动置顶")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(from: DateComponents(year: 2030, month: 5, day: 2))!
        let end = calendar.date(from: DateComponents(year: 2030, month: 5, day: 4))!
        let period = TodoSchedule(mode: .period, startDate: start, endDate: end,
                                  reminderMode: .dailyDuringPeriod,
                                  reminderTimeMinutes: 9 * 60)
        let periodItem = TodoItem(text: "出差期间", schedule: period)
        let daily = TodoStore.reminderRequests(
            for: periodItem,
            now: calendar.date(from: DateComponents(year: 2030, month: 5, day: 1))!,
            calendar: calendar)
        check(daily.count == 3, "期间模式会在起止日期内每天提醒")
        check(calendar.component(.hour, from: daily[0].date) == 9,
              "期间每日提醒使用所选时间")

        let event = calendar.date(from: DateComponents(year: 2030, month: 5, day: 8, hour: 16))!
        let before = TodoSchedule(mode: .deadline, date: event,
                                  reminderMode: .dayBefore,
                                  reminderTimeMinutes: 21 * 60)
        let beforeRequest = TodoStore.reminderRequests(
            for: TodoItem(text: "提交材料", schedule: before),
            now: start, calendar: calendar).first!
        check(calendar.component(.day, from: beforeRequest.date) == 7
              && calendar.component(.hour, from: beforeRequest.date) == 21,
              "提前一天提醒默认在前一晚 9 点")

        let encoded = try JSONEncoder().encode(store.items)
        let decoded = try JSONDecoder().decode([TodoItem].self, from: encoded)
        check(decoded.map(\.priority) == [.urgent, .important, .normal],
              "重要级别可持久化并恢复")

        struct LegacyItem: Codable {
            var id: UUID; var text: String; var createdAt: Date
            var dueDate: Date?; var completed: Bool; var completedAt: Date?
        }
        let legacyDue = Date().addingTimeInterval(10_000)
        let legacyData = try JSONEncoder().encode(LegacyItem(
            id: UUID(), text: "旧版待办", createdAt: Date(), dueDate: legacyDue,
            completed: false, completedAt: nil))
        let migrated = try JSONDecoder().decode(TodoItem.self, from: legacyData)
        check(migrated.priority == .normal && migrated.schedule?.mode == .deadline
              && migrated.schedule?.date == legacyDue,
              "旧版数据自动迁移为普通级别和截止日期模式")
    }

    @MainActor
    private static func testCompleteUndoArchiveAndRestore(_ root: URL) throws {
        let url = root.appendingPathComponent("archive.json")
        let fake = FakeNotificationScheduler()
        let store = makeStore(url, scheduler: fake, delay: 0.05)
        store.add(text: "可撤销", due: nil)
        let undoId = store.items[0].id
        store.complete(undoId)
        check(store.items[0].completed, "完成后先保留短暂撤销状态")
        store.undoCompletion(undoId)
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        check(!store.items[0].completed && store.archived.isEmpty, "撤销完成会取消归档")

        store.complete(undoId)
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        check(store.items.isEmpty && store.archived.first?.id == undoId, "完成等待后进入已完成记录")
        store.restoreArchived(undoId)
        check(store.archived.isEmpty && store.items.first?.id == undoId && !store.items[0].completed,
              "已完成记录可以恢复为待办")
        store.complete(undoId)
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        store.deleteArchived(undoId)
        check(store.archived.isEmpty, "已完成记录可以永久删除")
    }

    @MainActor
    private static func testCompletedItemMigration(_ root: URL) throws {
        struct Snapshot: Codable { var items: [TodoItem]; var archived: [TodoItem] }
        let url = root.appendingPathComponent("migration.json")
        var completed = TodoItem(text: "退出前刚完成")
        completed.completed = true
        completed.completedAt = Date()
        try JSONEncoder().encode(Snapshot(items: [completed], archived: []))
            .write(to: url, options: .atomic)
        let store = makeStore(url, scheduler: FakeNotificationScheduler())
        check(store.items.isEmpty && store.archived.first?.id == completed.id,
              "退出发生在延迟归档期间时，重启会迁移到已完成记录")
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fputs("❌ \(message)\n", stderr)
            exit(1)
        }
        passed += 1
        print("✓ \(message)")
    }
}
