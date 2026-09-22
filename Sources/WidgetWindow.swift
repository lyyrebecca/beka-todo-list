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

/// SwiftUI 坐标中的标题栏按钮实际点击区域。AppDelegate 只需要 X 轴：
/// 事件已先限定在标题栏高度内，而 SwiftUI/AppKit 的 X 原点一致。
struct HeaderControlFramesKey: PreferenceKey {
    static var defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value.append(contentsOf: nextValue())
    }
}

struct HeaderControlFrameReporter: View {
    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(key: HeaderControlFramesKey.self,
                                   value: [proxy.frame(in: .global)])
        }
        .allowsHitTesting(false)
    }
}

final class WidgetHostingView: NSHostingView<WidgetView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
