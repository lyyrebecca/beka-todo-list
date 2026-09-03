import AppKit
import Darwin

@main
struct LiquidTodoMain {
    // Keep the descriptor alive for the complete app lifetime. flock is released
    // automatically if the primary instance exits or crashes.
    private static var instanceLockFileDescriptor: Int32 = -1

    private static func acquireSingleInstanceLock() -> Bool {
        let fileManager = FileManager.default
        let supportDirectory = fileManager.urls(for: .applicationSupportDirectory,
                                                 in: .userDomainMask)[0]
            .appendingPathComponent("LiquidTodo", isDirectory: true)
        try? fileManager.createDirectory(at: supportDirectory,
                                         withIntermediateDirectories: true)
        let lockURL = supportDirectory.appendingPathComponent(".instance.lock")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)

        // If macOS cannot create the lock file, retain normal launch behavior
        // rather than blocking access to the user's Todo list.
        guard descriptor >= 0 else { return true }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            return false
        }
        instanceLockFileDescriptor = descriptor
        return true
    }

    @MainActor
    static func main() {
        // The login LaunchAgent and a Dock/Finder launch can otherwise each
        // create their own floating widget. Only the first process owns it.
        guard acquireSingleInstanceLock() else { return }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
