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
        try testHierarchyAndBackups(root)
        try testHierarchyCompletion(root)
        try testMeasuredReorderPreview(root)
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
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        check(!store.items[0].completed && store.archived.isEmpty, "撤销完成会取消归档")

        store.complete(undoId)
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        check(store.items.isEmpty && store.archived.first?.id == undoId, "完成等待后进入已完成记录")
        store.restoreArchived(undoId)
        check(store.archived.isEmpty && store.items.first?.id == undoId && !store.items[0].completed,
              "已完成记录可以恢复为待办")
        store.complete(undoId)
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
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

    @MainActor
    private static func testHierarchyAndBackups(_ root: URL) throws {
        let store = makeStore(root.appendingPathComponent("tree.json"), scheduler: FakeNotificationScheduler())
        let a = store.add(text: "项目 A", priority: .normal, schedule: nil)!
        let b = store.add(text: "项目 B", priority: .normal, schedule: nil)!
        let a1 = store.add(text: "步骤 A1", priority: .normal, schedule: nil, parentId: a)!
        let a2 = store.add(text: "步骤 A2", priority: .important, schedule: nil, parentId: a)!
        let leaf = store.add(text: "继续拆分", priority: .normal, schedule: nil, parentId: a1)!
        check(store.items.map(\.id) == [a, a2, a1, leaf, b], "子项优先级只影响同级，树保持连续")
        check(store.depth(of: leaf) == 2, "支持递归拆分，不限于两层清单")
        check(store.add(text: "无效父项", priority: .normal, schedule: nil, parentId: UUID()) == nil, "拒绝把新子项加入不存在的父项")
        check(!store.setParent(a, to: leaf), "不能把父项移入自己的后代，防止循环")
        check(!store.setParent(a1, to: a1), "不能把自己设为父项")
        store.moveSibling(id: a1, to: 0)
        check(store.items.map(\.id) == [a, a1, leaf, a2, b], "同级拖动带着完整子树移动")
        store.moveSibling(id: a, to: 1)
        check(store.items.map(\.id) == [b, a, a1, leaf, a2], "父待办排序不会遗留子项")
        check(store.setParent(a1, to: b), "可以把子树改挂到另一个父待办")
        check(store.items.first(where: { $0.id == leaf })?.parentId == a1, "改挂时保留孙级关系")
        check(store.setParent(a1, to: nil) && store.depth(of: leaf) == 1, "提升为顶级时保留整棵子树")
        store.toggleChildren(a1)
        check(!store.visibleItems.contains(where: { $0.id == leaf }), "折叠隐藏后代但不删除数据")
        store.toggleChildren(a1)
        check(store.visibleItems.contains(where: { $0.id == leaf }), "展开恢复所有可见后代")
        let backup = root.appendingPathComponent("tree-backup.json")
        try store.exportBackup(to: backup)
        let exportedDocument = try JSONDecoder().decode(TodoBackupDocument.self, from: Data(contentsOf: backup))
        check(exportedDocument.schemaVersion == 2, "层级备份使用 v2，避免旧版静默丢失父子关系")
        let restored = makeStore(root.appendingPathComponent("tree-import.json"), scheduler: FakeNotificationScheduler())
        try restored.importBackup(from: backup, replacing: false)
        check(restored.items.first(where: { $0.id == leaf })?.parentId == a1, "跨平台备份往返保留 parentId")
        let loaded = makeStore(root.appendingPathComponent("tree.json"), scheduler: FakeNotificationScheduler())
        check(loaded.items == store.items, "重启后层级、同级顺序和文本不变")
        let flat = makeStore(root.appendingPathComponent("flat-compatible.json"), scheduler: FakeNotificationScheduler())
        flat.add(text: "旧版仍能读取的平面清单", due: nil)
        let flatURL = root.appendingPathComponent("flat-v1.json")
        try flat.exportBackup(to: flatURL)
        let flatDocument = try JSONDecoder().decode(TodoBackupDocument.self, from: Data(contentsOf: flatURL))
        check(flatDocument.schemaVersion == 1,
              "无层级备份继续输出 v1，保持旧版双端兼容")
        try restored.importBackup(from: flatURL, replacing: false)
        check(restored.items.contains(where: { $0.text == "旧版仍能读取的平面清单" }), "新版可合并导入旧 v1 备份")
        var x = TodoItem(text: "循环 X"), y = TodoItem(text: "循环 Y")
        x.parentId = y.id; y.parentId = x.id
        let repaired = TodoHierarchy.sanitized([x, y, TodoItem(text: "孤儿", parentId: UUID())])
        check(repaired.last?.parentId == nil, "损坏备份中的孤儿恢复为顶级，不丢内容")
        check(TodoHierarchy.ordered(repaired).count == 3 && repaired.filter { $0.parentId == nil }.count >= 2,
              "坏数据循环可确定性修复且所有待办仍可见")
    }

    @MainActor
    private static func testMeasuredReorderPreview(_ root: URL) throws {
        let url = root.appendingPathComponent("drag-preview.json")
        let store = makeStore(url, scheduler: FakeNotificationScheduler())
        let a = store.add(text: "短行", priority: .normal, schedule: nil)!
        let b = store.add(text: "两行长标题", priority: .normal, schedule: nil)!
        let c = store.add(text: "第三行", priority: .normal, schedule: nil)!
        let frames: [UUID: CGRect] = [a: CGRect(x: 0, y: 0, width: 350, height: 32),
            b: CGRect(x: 0, y: 38, width: 350, height: 62), c: CGRect(x: 0, y: 106, width: 350, height: 44)]
        store.updateRowFrames(frames)
        let before = try Data(contentsOf: url)
        _ = store.childProgress(a)
        let cacheBuilds = store.presentationBuildCount
        store.beginRowDrag(a)
        for y in 0...140 {
            store.updateRowDrag(translation: CGFloat(y))
            _ = store.childProgress(a); _ = store.depth(of: b); _ = store.hasActiveChildren(a)
        }
        check(store.presentationBuildCount == cacheBuilds, "鼠标移动复用层级与进度缓存，不逐帧重算整棵树")
        check(store.items.map(\.id) == [a, b, c], "拖动预览不会反复改写列表和重建输入控件")
        let duringDrag = try Data(contentsOf: url)
        check(duringDrag == before, "每次鼠标移动不做磁盘写入")
        check(store.reorderPreview?.targetSiblingIndex == 2, "按真实不等高行计算目标，而非写死 45px")
        check(store.reorderPreview?.offsets[b] == -38 && store.reorderPreview?.offsets[c] == -38,
              "相邻行实时让位，长标题不影响间隙")
        store.finishRowDrag()
        check(store.items.map(\.id) == [b, c, a] && store.reorderPreview == nil, "松手一次提交实际排序并清理手势状态")
        let saved = try Data(contentsOf: url)
        store.updateRowFrames(frames)
        store.beginRowDrag(b); store.updateRowDrag(translation: 200); store.finishRowDrag(cancelled: true)
        let afterCancel = try Data(contentsOf: url)
        check(afterCancel == saved && store.items.map(\.id) == [b, c, a], "取消拖动不落盘、不改变原有顺序")
    }

    @MainActor
    private static func testHierarchyCompletion(_ root: URL) throws {
        let store = makeStore(root.appendingPathComponent("tree-completion.json"), scheduler: FakeNotificationScheduler(), delay: 0.05)
        let parent = store.add(text: "父项", priority: .normal, schedule: nil)!
        let child = store.add(text: "子项", priority: .normal, schedule: nil, parentId: parent)!
        let grandchild = store.add(text: "孙项", priority: .normal, schedule: nil, parentId: child)!
        store.complete(parent)
        check(store.items.allSatisfy(\.completed), "完成父项会完成所有后代")
        store.undoCompletion(child)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        check(store.items.count == 3 && store.items.allSatisfy { !$0.completed } && store.archived.isEmpty,
              "四秒撤销对整个完成分组生效，不留下半归档树")
        store.complete(parent)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        check(store.items.isEmpty && store.archived.map(\.id) == [parent, child, grandchild], "整棵子树按层级归档")
        store.restoreArchived(parent)
        check(store.archived.isEmpty && store.items.map(\.id) == [parent, child, grandchild], "恢复父项会恢复子树和顺序")
        store.complete(grandchild)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        check(store.childProgress(parent).done == 1 && store.childProgress(parent).total == 2, "父项进度包括已归档的完成子项")
        store.delete(parent)
        check(store.items.isEmpty && store.archived.isEmpty, "删除父项连同活动和已完成后代一起清理")
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
