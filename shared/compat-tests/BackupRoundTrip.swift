import Foundation

final class SilentCompatibilityScheduler: TodoNotificationScheduling {
    func schedule(identifier: String, text: String, date: Date) {}
    func cancel(identifiers: [String]) {}
}

@main struct BackupRoundTrip {
    @MainActor static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let store = TodoStore(fileURL: root.appendingPathComponent("macos-data.json"), startClock: false,
                              notificationScheduler: SilentCompatibilityScheduler(), completionArchiveDelay: 4)
        try store.importBackup(from: root.appendingPathComponent("windows.json"), replacing: true)
        guard store.items.count == 2, store.archived.count == 1,
              store.items[1].parentId == store.items[0].id,
              store.archived[0].parentId == store.items[1].id,
              store.items[0].priority == .important,
              store.archived[0].priority == .urgent,
              store.items[1].schedule?.mode == .period,
              store.items[1].schedule?.reminderTimeMinutes == 540,
              store.childProgress(store.items[0].id).done == 1 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try store.exportBackup(to: root.appendingPathComponent("macos.json"))
        print("Swift imported Windows hierarchy and exported it without dropping archived relationships.")
    }
}
