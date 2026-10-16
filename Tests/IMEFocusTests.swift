import AppKit
import SwiftUI
import Darwin

// Runs in its own test app. It never creates TodoStore or opens the user's data.
@MainActor
final class FocusTestDelegate: NSObject, NSApplicationDelegate {
    var host: NSHostingView<IMETextField>!
    var window: NSWindow!
    var results: [[String: Any]] = []
    var text = ""
    let otherControl = NSButton(title: "Other control", target: nil, action: nil)
    var removedHost: NSHostingView<IMETextField>?

    func makeInput() -> IMETextField {
        IMETextField(text: Binding(get: { self.text }, set: { self.text = $0 }),
                     placeholder: "IME focus regression test", font: .systemFont(ofSize: 14),
                     textColor: .labelColor, roundedBorder: true)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        host = NSHostingView(rootView: makeInput())
        host.frame = NSRect(x: 0, y: 0, width: 350, height: 70)
        host.layoutSubtreeIfNeeded()
        // A cold SwiftUI insertion/transition can outlive the old 180ms retry window.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.attach() }
    }

    func findField(_ view: NSView) -> NSTextField? {
        if let field = view as? NSTextField { return field }
        return view.subviews.lazy.compactMap { self.findField($0) }.first
    }

    func attach() {
        let createdWhileDetached = findField(host)?.window == nil && findField(host) != nil
        results.append(["check": "field-created-before-window-attachment", "passed": createdWhileDetached])
        window = NSWindow(contentRect: NSRect(x: 180, y: 180, width: 350, height: 70),
                          styleMask: [.titled], backing: .buffered, defer: false)
        // No window-level default key-view focus may mask the field's own request.
        window.initialFirstResponder = nil
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 350, height: 110))
        host.frame.origin.y = 40
        otherControl.frame = NSRect(x: 12, y: 4, width: 140, height: 30)
        content.addSubview(host)
        content.addSubview(otherControl)
        window.contentView = content
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.check() }
    }

    func check() {
        let field = findField(host)
        let editor = field?.currentEditor()
        let focused = editor != nil && window.firstResponder === editor && window.isKeyWindow && NSApp.isActive
        results.append(["check": "initial-focus-after-delayed-attachment", "passed": focused,
                        "appActive": NSApp.isActive, "windowKey": window.isKeyWindow,
                        "fieldEditorAttached": editor != nil])
        // Once initial focus succeeds, redraws must not steal it from a picker/button.
        window.makeFirstResponder(otherControl)
        host.needsLayout = true
        host.layoutSubtreeIfNeeded()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.checkNoFocusTheft() }
    }

    func checkNoFocusTheft() {
        results.append(["check": "redraw-does-not-steal-completed-focus", "passed": window.firstResponder === otherControl])
        guard let field = findField(host) else { finish(); return }
        window.makeFirstResponder(field)
        guard let editor = field.currentEditor() as? NSTextView else {
            results.append(["check": "native-marked-text-preserved", "passed": false])
            finish(); return
        }
        // Native composition lifecycle test only, NOT a real WeChat candidate test.
        editor.setMarkedText("zhong", selectedRange: NSRange(location: 5, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        let hadMarkedText = editor.hasMarkedText()
        text = "external SwiftUI update"
        host.rootView = makeInput()
        host.layoutSubtreeIfNeeded()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.results.append(["check": "native-marked-text-preserved",
                                 "passed": hadMarkedText && editor.hasMarkedText() && editor.string.contains("zhong")])
            editor.unmarkText()
            self.checkCancelledInsertion()
        }
    }

    func checkCancelledInsertion() {
        // Insert then remove before the deferred focus request runs. No stale
        // activation may steal focus after the user closes the add form.
        removedHost = NSHostingView(rootView: makeInput())
        removedHost!.frame = NSRect(x: 0, y: 0, width: 350, height: 70)
        removedHost!.layoutSubtreeIfNeeded()
        window.contentView!.addSubview(removedHost!)
        removedHost!.layoutSubtreeIfNeeded()
        removedHost!.removeFromSuperview()
        window.makeFirstResponder(otherControl)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            self.results.append(["check": "removed-field-does-not-steal-focus", "passed": self.window.firstResponder === self.otherControl])
            self.finish()
        }
    }

    func finish() {
        let path = ProcessInfo.processInfo.environment["LIQUIDTODO_FOCUS_REPORT"] ?? "/tmp/liquidtodo-ime-focus.json"
        let data = try! JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
        try! data.write(to: URL(fileURLWithPath: path))
        print(String(data: data, encoding: .utf8)!)
        window.title = results.allSatisfy { $0["passed"] as? Bool == true } ? "IME Focus Tests: PASS" : "IME Focus Tests: FAIL"
        if CommandLine.arguments.contains("--exit-after-test") {
            fflush(stdout)
            Darwin.exit(results.allSatisfy { $0["passed"] as? Bool == true } ? 0 : 1)
        }
        // Remain available for CUA inspection; the test app never touches live todos.
    }
}

@main
struct IMEFocusTests {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = FocusTestDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}
