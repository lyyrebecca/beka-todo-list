import AppKit
import Foundation
import Darwin

private struct SilentLayoutNotifications: TodoNotificationScheduling {
    func schedule(identifier: String, text: String, date: Date) {}
    func cancel(identifiers: [String]) {}
}

@main
struct ArchiveLayoutTests {
    @MainActor static func main() {
        setenv("LIQUIDTODO_SANDBOX", "1", 1)
        UserDefaults.standard.set("布局检查", forKey: "todoOwnerName")
        UserDefaults.standard.set(false, forKey: "widgetMinimized")
        UserDefaults.standard.set(false, forKey: "desktopMode")
        let store = TodoStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("layout-\(UUID()).json"), startClock: false, notificationScheduler: SilentLayoutNotifications(), completionArchiveDelay: 4)
        store.items = [TodoItem(text: "一个活动任务")]
        store.archived = (1...4).map { TodoItem(text: "已完成任务 \($0)", completed: true, completedAt: Date()) }
        let app = NSApplication.shared
        let delegate = AppDelegate(store: store)
        app.delegate = delegate; app.setActivationPolicy(.accessory)
        var results: [[String: Any]] = []
        func record(_ name: String, _ minimum: CGFloat, _ maximum: CGFloat) {
            let height = delegate.window.frame.height
            results.append(["check": name, "height": height, "passed": height >= minimum && height <= maximum])
        }
        let coordinateWindow = NSWindow(contentRect: NSRect(x: 100, y: 200, width: 300, height: 100), styleMask: [.borderless], backing: .buffered, defer: false)
        let attachedEvent = NSEvent.mouseEvent(with: .rightMouseDown, location: NSPoint(x: 80, y: 70), modifierFlags: [], timestamp: 0, windowNumber: coordinateWindow.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        results.append(["check": "event-uses-own-window-coordinates", "passed": WidgetWindow.screenPoint(for: attachedEvent) == NSPoint(x: 180, y: 270)])
        let detachedEvent = NSEvent.mouseEvent(with: .leftMouseDragged, location: NSPoint(x: 420, y: 380), modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        results.append(["check": "detached-drag-keeps-screen-coordinates", "passed": WidgetWindow.screenPoint(for: detachedEvent) == NSPoint(x: 420, y: 380)])
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            record("single-active-row-start", 90, 220)
            store.isShowingArchive = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                record("archive-expands-from-short-window", 240, 440)
                store.archived += (5...30).map { TodoItem(text: "长历史任务 \($0)", completed: true, completedAt: Date()) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    record("long-archive-bounded-viewport", 380, 460)
                    store.isShowingArchive = false
                    store.items = (1...26).map { TodoItem(text: "长清单 \($0)") }
                    store.isExpanded = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        record("expanded-list-bounded-viewport", 410, 500)
                        store.isAdding = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            record("add-form-list-does-not-collapse", 360, 600)
                            let data = try! JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
                            if let path = ProcessInfo.processInfo.environment["LIQUIDTODO_LAYOUT_REPORT"] { try! data.write(to: URL(fileURLWithPath: path)) }
                            print(String(data: data, encoding: .utf8)!); fflush(stdout)
                            Darwin.exit(results.allSatisfy { $0["passed"] as? Bool == true } ? 0 : 1)
                        }
                    }
                }
            }
        }
        app.run(); withExtendedLifetime(delegate) {}
    }
}
