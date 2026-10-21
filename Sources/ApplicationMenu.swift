import AppKit

/// Status-item shortcuts alone are not a substitute for NSApplication's menu.
/// Keep standard editing and quit commands available even if macOS hides the icon.
@MainActor
enum ApplicationMenu {
    static func make(target: AnyObject, newAction: Selector, quitAction: Selector) -> NSMenu {
        let bar = NSMenu()
        let application = NSMenu(title: "Todo list")
        let quit = NSMenuItem(title: "退出 Todo list", action: quitAction, keyEquivalent: "q")
        quit.target = target; application.addItem(quit)
        let appItem = NSMenuItem(); appItem.submenu = application; bar.addItem(appItem)
        let file = NSMenu(title: "文件")
        let new = NSMenuItem(title: "新建待办…", action: newAction, keyEquivalent: "n")
        new.target = target; file.addItem(new)
        let fileItem = NSMenuItem(); fileItem.submenu = file; bar.addItem(fileItem)
        let edit = NSMenu(title: "编辑")
        edit.addItem(NSMenuItem(title: "撤销", action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]; edit.addItem(redo)
        edit.addItem(.separator())
        edit.addItem(NSMenuItem(title: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        edit.addItem(NSMenuItem(title: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        edit.addItem(NSMenuItem(title: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        edit.addItem(NSMenuItem(title: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        let editItem = NSMenuItem(); editItem.submenu = edit; bar.addItem(editItem)
        return bar
    }
}
