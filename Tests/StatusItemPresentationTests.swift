import AppKit

@main
struct StatusItemPresentationTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        let suite = "com.beka.liquidtodo.status-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var passed = 0
        func check(_ condition: Bool, _ label: String) {
            precondition(condition, label)
            passed += 1
            print("PASS: \(label)")
        }
        let position = "NSStatusItem Preferred Position \(StatusItemPresentation.autosaveName)"
        let visible = "NSStatusItem Visible \(StatusItemPresentation.autosaveName)"
        StatusItemPresentation.prepare(defaults: defaults)
        check(defaults.integer(forKey: position) == 0, "first launch seeds right-side slot")
        check(defaults.bool(forKey: visible), "first launch visible")
        defaults.set(160, forKey: position)
        defaults.set(false, forKey: visible)
        StatusItemPresentation.prepare(defaults: defaults)
        check(defaults.integer(forKey: position) == 160, "user placement preserved")
        check(defaults.bool(forKey: visible), "hidden state recovered")
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        defer { NSStatusBar.system.removeStatusItem(item) }
        StatusItemPresentation.configure(item)
        check(item.isVisible, "status item enabled")
        check(item.autosaveName == StatusItemPresentation.autosaveName, "stable autosave name")
        check(item.button?.image?.isTemplate == true, "adaptive template symbol")
        check(item.button?.image?.size == NSSize(width: 18, height: 18), "bounded nonzero symbol size")
        StatusItemPresentation.configure(item, symbol: nil)
        check(item.button?.title == "干" && item.button?.image == nil, "missing symbol has visible text fallback")
        let target = NSObject()
        let appMenu = ApplicationMenu.make(target: target, newAction: Selector(("newTodo:")), quitAction: Selector(("quit:")))
        let quit = appMenu.items[0].submenu!.items[0]
        let new = appMenu.items[1].submenu!.items[0]
        check(quit.keyEquivalent == "q" && quit.target === target, "Command-Q works without opening status menu")
        check(new.keyEquivalent == "n" && new.target === target, "native Command-N command target")
        let edit = appMenu.items[2].submenu!
        check(edit.items.first(where: { $0.title == "复制" })?.keyEquivalent == "c", "native copy command")
        check(edit.items.first(where: { $0.title == "粘贴" })?.keyEquivalent == "v", "native paste command")
        check(edit.items.first(where: { $0.title == "全选" })?.keyEquivalent == "a", "native select-all command")
        check(edit.items.first(where: { $0.title == "重做" })?.keyEquivalentModifierMask == [.command, .shift], "native redo modifiers")
        print("Status item native checks: \(passed) passed. Not a screenshot/visibility-on-screen test.")
    }
}
