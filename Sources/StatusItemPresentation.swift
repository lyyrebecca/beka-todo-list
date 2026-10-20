import AppKit

/// Own a stable menu-bar slot instead of receiving a new far-left slot at each launch.
@MainActor
enum StatusItemPresentation {
    static let autosaveName = "LiquidTodoMainStatus"

    static func prepare(defaults: UserDefaults = .standard) {
        let positionKey = "NSStatusItem Preferred Position \(autosaveName)"
        // Seed only the first position. Preserve subsequent Command-drag placement.
        if defaults.object(forKey: positionKey) == nil {
            defaults.set(0, forKey: positionKey)
        }
        // Recover a previously removed item before AppKit restores its visibility.
        defaults.set(true, forKey: "NSStatusItem Visible \(autosaveName)")
    }

    static func configure(_ item: NSStatusItem,
                          symbol: NSImage? = NSImage(systemSymbolName: "checklist",
                                                    accessibilityDescription: "待办菜单")) {
        item.autosaveName = autosaveName
        item.behavior = []
        item.isVisible = true
        guard let button = item.button else { return }
        if let source = symbol {
            let icon = source.withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
            ) ?? source
            icon.isTemplate = true
            icon.size = NSSize(width: 18, height: 18)
            button.image = icon
            button.title = ""
        } else {
            // A missing system symbol must never create an invisible menu button.
            button.image = nil
            button.title = "干"
        }
        button.contentTintColor = nil
        button.toolTip = "贝卡の Todo list — 点击打开菜单"
        button.setAccessibilityLabel("贝卡待办菜单")
    }
}
