import AppKit
import SwiftUI

final class WidgetWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    // 第三方中文输入法（包括微信输入法）需要 Main/Key Window 才会建立文本输入上下文。
    override var canBecomeMain: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown || event.type == .rightMouseDown {
            NSApp.activate(ignoringOtherApps: true)
            makeKeyAndOrderFront(nil)
            makeMain()
        }
        super.sendEvent(event)
    }
}

struct ContentSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

final class WidgetHostingView: NSHostingView<WidgetView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
