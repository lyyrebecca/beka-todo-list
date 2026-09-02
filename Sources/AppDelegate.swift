import AppKit
import SwiftUI
import ServiceManagement
import UserNotifications
import QuartzCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static let widgetWidth: CGFloat = 350
    static var frameWidth: CGFloat { widgetWidth + 12 }
    static let miniSize: CGFloat = 48

    let store = TodoStore()
    var window: WidgetWindow!
    var statusItem: NSStatusItem!
    private var hasSized = false
    private var lastSize: CGSize = .zero
    private var isWindowTransitioning = false

    /// 微动效使用接近 Apple 系统面板的快速起步、平稳收束曲线；
    /// 在“减少动态效果”开启时直接切换，避免不必要的位移。
    private var reducesMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private var windowMotionDuration: TimeInterval { reducesMotion ? 0.01 : 0.32 }
    private var componentMotion: Animation {
        reducesMotion ? .linear(duration: 0.01)
            : .spring(response: 0.36, dampingFraction: 0.88, blendDuration: 0.08)
    }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
        setupWindow()
        setupStatusItem()
        if ProcessInfo.processInfo.environment["LIQUIDTODO_START_ADDING"] == "1" {
            DispatchQueue.main.async { [weak self] in self?.startAdding() }
        }
    }

    private var desktopMode: Bool {
        get { UserDefaults.standard.bool(forKey: "desktopMode") }
        set { UserDefaults.standard.set(newValue, forKey: "desktopMode") }
    }

    // MARK: - Window

    private func setupWindow() {
        store.isMinimized = UserDefaults.standard.bool(forKey: "widgetMinimized")
        let initialSize = store.isMinimized
            ? NSSize(width: Self.miniSize, height: Self.miniSize)
            : NSSize(width: Self.frameWidth, height: 160)
        let rect = NSRect(origin: .zero, size: initialSize)
        window = WidgetWindow(contentRect: rect,
                              styleMask: [.borderless],
                              backing: .buffered,
                              defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        // SwiftUI 自己绘制圆角层次；禁用 NSWindow 的矩形阴影，避免白底上出现方形灰/黑边。
        window.hasShadow = false
        window.level = currentLevel
        window.ignoresMouseEvents = desktopMode
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // 窗口只能从标题区拖动；若设为 true，会抢走待办行手柄的拖动事件。
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.delegate = self

        let host = WidgetHostingView(rootView: WidgetView(
            store: store,
            onSizeChange: { [weak self] size in self?.setContentSize(size) },
            onMinimize: { [weak self] in self?.minimizeWidget() },
            onRequestTextInput: { [weak self] in self?.activateForTextInput() },
            onTextInputSessionChanged: { [weak self] isActive in
                self?.setTextInputSessionActive(isActive)
            }
        ))
        host.frame = rect
        window.contentView = host

        if store.isMinimized { restoreMiniFrame() } else { restoreFrame() }
        window.orderFrontRegardless()
        installDragMonitor()
    }

    private var dragMonitor: Any?
    private var miniMouseDownPoint: NSPoint?
    private var miniWindowOrigin: NSPoint?
    private var miniDidDrag = false

    private func installDragMonitor() {
        dragMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            guard let self, let window = self.window else {
                return event
            }
            if self.store.isMinimized {
                // 拖出圆圈边界后 dragged/up 事件可能不再带 window，仍要继续本次拖动。
                let continuingMiniDrag = self.miniMouseDownPoint != nil
                    && (event.type == .leftMouseDragged || event.type == .leftMouseUp)
                guard event.window === window || continuingMiniDrag else { return event }
                return self.handleMiniWindowEvent(event)
            }
            guard event.window === window else { return event }
            guard event.type == .leftMouseDown else { return event }
            let screenPoint = NSEvent.mouseLocation
            guard self.isDraggableHeaderPoint(screenPoint) else { return event }
            window.performDrag(with: event)
            return nil
        }
    }

    private func handleMiniWindowEvent(_ event: NSEvent) -> NSEvent? {
        guard let window else { return event }
        let point = NSEvent.mouseLocation
        switch event.type {
        case .leftMouseDown:
            miniMouseDownPoint = point
            miniWindowOrigin = window.frame.origin
            miniDidDrag = false
            store.isMiniDragging = true
            NSCursor.closedHand.set()
            return nil
        case .leftMouseDragged:
            guard let start = miniMouseDownPoint, let origin = miniWindowOrigin else { return nil }
            let dx = point.x - start.x
            let dy = point.y - start.y
            if hypot(dx, dy) > 2 { miniDidDrag = true }
            window.setFrameOrigin(NSPoint(x: origin.x + dx, y: origin.y + dy))
            return nil
        case .leftMouseUp:
            store.isMiniDragging = false
            NSCursor.arrow.set()
            if miniDidDrag {
                snapMiniFrameToNearestEdge(animated: true)
            } else {
                restoreWidget()
            }
            miniMouseDownPoint = nil
            miniWindowOrigin = nil
            miniDidDrag = false
            return nil
        default:
            return event
        }
    }

    private func isDraggableHeaderPoint(_ screenPoint: NSPoint) -> Bool {
        guard let window else { return false }
        let f = window.frame
        let headerHeight: CGFloat = 54
        // 标题区域可拖动；右侧整组按钮必须交给 SwiftUI 处理。
        // 旧实现只排除了最右侧 48pt，导致“已完成历史”按钮被窗口拖动监视器吞掉。
        let controlsWidth: CGFloat = 136
        let draggableRect = NSRect(x: f.minX, y: f.maxY - headerHeight,
                                   width: f.width - controlsWidth, height: headerHeight)
        return draggableRect.contains(screenPoint)
    }

    private var desktopLevel: NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)))
    }

    private var currentLevel: NSWindow.Level {
        desktopMode ? desktopLevel : .floating
    }

    func toggleDesktopMode() {
        desktopMode.toggle()
        window.level = currentLevel
        window.ignoresMouseEvents = desktopMode
        window.orderFrontRegardless()
    }

    private func setContentSize(_ size: CGSize) {
        guard !isWindowTransitioning, let window, size.width > 10, size.height > 10,
              abs(size.width - lastSize.width) > 0.5 || abs(size.height - lastSize.height) > 0.5
        else { return }
        lastSize = size
        let f = window.frame
        let target = NSRect(x: f.origin.x, y: f.maxY - size.height,
                            width: size.width, height: size.height)
        if !hasSized {
            hasSized = true
            window.setFrame(target, display: true, animate: false)
        } else {
            window.setFrame(target, display: true, animate: true)
        }
    }

    private var saveWorkItem: DispatchWorkItem?

    private var currentFrameKey: String {
        store.isMinimized ? "miniWindowFrame" : "windowFrame"
    }

    private func saveFrame() {
        guard hasSized else { return }
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let w = self.window else { return }
            UserDefaults.standard.set(NSStringFromRect(w.frame), forKey: self.currentFrameKey)
        }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func saveFrameImmediately() {
        guard let window else { return }
        saveWorkItem?.cancel()
        UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: currentFrameKey)
    }

    private func restoreFrame() {
        window.setFrame(normalTargetFrame(), display: false)
    }

    private func normalTargetFrame() -> NSRect {
        let fallbackHeight: CGFloat = 160
        let stored = UserDefaults.standard.string(forKey: "windowFrame").map(NSRectFromString)
        var frame = (stored?.width ?? 0) > 10
            ? stored!
            : NSRect(x: 0, y: 0, width: Self.frameWidth, height: fallbackHeight)
        frame.size.width = Self.frameWidth
        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(frame) }) ?? NSScreen.main {
            let v = screen.visibleFrame
            if stored == nil {
                frame.origin = NSPoint(x: v.maxX - Self.frameWidth - 60,
                                       y: v.maxY - fallbackHeight - 80)
            }
            frame.origin.x = min(max(frame.origin.x, v.minX + 20), v.maxX - frame.width - 20)
            frame.origin.y = min(max(frame.origin.y, v.minY + 20),
                                 v.maxY - frame.height - 20)
        }
        return frame
    }

    private func placeDefaultFrame() {
        window.setFrame(normalTargetFrame(), display: false)
    }

    private func restoreMiniFrame() {
        if let str = UserDefaults.standard.string(forKey: "miniWindowFrame") {
            var frame = NSRectFromString(str)
            frame.size = NSSize(width: Self.miniSize, height: Self.miniSize)
            window.setFrame(frame, display: false)
            snapMiniFrameToNearestEdge(animated: false)
        } else {
            placeMiniOnRight()
        }
    }

    private func placeMiniOnRight() {
        window.setFrame(miniTargetFrame(), display: true)
    }

    private func miniTargetFrame() -> NSRect {
        guard let screen = window.screen ?? NSScreen.main else { return window.frame }
        let v = screen.visibleFrame
        let size = Self.miniSize
        let y = min(max(window.frame.midY - size / 2, v.minY + 16), v.maxY - size - 16)
        return NSRect(x: v.maxX - size - 7, y: y, width: size, height: size)
    }

    private func snapMiniFrameToNearestEdge(animated: Bool) {
        guard let window,
              let screen = NSScreen.screens.first(where: { $0.frame.intersects(window.frame) })
                ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let margin: CGFloat = 7
        var target = window.frame
        let leftX = visible.minX + margin
        let rightX = visible.maxX - target.width - margin
        target.origin.x = target.midX < visible.midX ? leftX : rightX
        target.origin.y = min(max(target.origin.y, visible.minY + margin),
                              visible.maxY - target.height - margin)

        guard animated else {
            window.setFrame(target, display: true)
            saveFrameImmediately()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reducesMotion ? 0.01 : 0.26
            // 快速响应、无明显回弹：贴边时像 macOS 原生浮层一样干净收束。
            context.timingFunction = CAMediaTimingFunction(
                controlPoints: 0.16, 1.00, 0.30, 1.00)
            context.allowsImplicitAnimation = !reducesMotion
            window.animator().setFrame(target, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in self?.saveFrameImmediately() }
        }
    }

    func minimizeWidget() {
        guard !store.isMinimized else { return }
        saveFrameImmediately()
        store.isAdding = false
        store.editingTextId = nil
        withAnimation(componentMotion) { store.isMinimized = true }
        UserDefaults.standard.set(true, forKey: "widgetMinimized")
        lastSize = .zero
        animateWindow(to: miniTargetFrame())
    }

    func restoreWidget() {
        guard store.isMinimized else { return }
        saveFrameImmediately()
        withAnimation(componentMotion) { store.isMinimized = false }
        UserDefaults.standard.set(false, forKey: "widgetMinimized")
        lastSize = .zero
        window.orderFrontRegardless()
        animateWindow(to: normalTargetFrame())
    }

    private func animateWindow(to target: NSRect) {
        guard let window else { return }
        isWindowTransitioning = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = windowMotionDuration
            // 与 SwiftUI 内容的临界阻尼 spring 对齐：缩放和窗口尺寸在同一节奏内完成。
            context.timingFunction = CAMediaTimingFunction(
                controlPoints: 0.20, 0.80, 0.20, 1.00)
            context.allowsImplicitAnimation = !reducesMotion
            window.animator().setFrame(target, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isWindowTransitioning = false
                self.lastSize = target.size
                self.saveFrameImmediately()
            }
        }
    }

    func windowDidMove(_ notification: Notification) { saveFrame() }
    func windowDidResize(_ notification: Notification) { saveFrame() }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            if let img = NSImage(systemSymbolName: "checklist",
                                 accessibilityDescription: "液态待办") {
                img.isTemplate = false
                button.image = img
                button.contentTintColor = NSColor(red: 0.66, green: 0.52, blue: 0.98, alpha: 1)
            }
            button.toolTip = "贝卡の Todo list 🌟"
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        let visible = window?.isVisible ?? false
        let showTitle = store.isMinimized ? "展开桌面组件" : (visible ? "隐藏桌面组件" : "显示桌面组件")
        let showItem = NSMenuItem(title: showTitle,
                                  action: #selector(toggleWidget),
                                  keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)

        let addItem = NSMenuItem(title: "添加待办…",
                                 action: #selector(startAdding),
                                 keyEquivalent: "n")
        addItem.keyEquivalentModifierMask = [.command]
        addItem.target = self
        menu.addItem(addItem)

        let pinItem = NSMenuItem(title: "沉入桌面（纯展示，不可点击）",
                                 action: #selector(toggleDesktopModeAction),
                                 keyEquivalent: "")
        pinItem.target = self
        pinItem.state = desktopMode ? .on : .off
        menu.addItem(pinItem)

        let launchItem = NSMenuItem(title: "开机自动启动",
                                    action: #selector(toggleLaunch),
                                    keyEquivalent: "")
        launchItem.target = self
        launchItem.state = autoLaunchEnabled ? .on : .off
        menu.addItem(launchItem)

        menu.addItem(.separator())

        let clearItem = NSMenuItem(title: "清空已完成（\(store.archived.count)）",
                                   action: #selector(clearArchived),
                                   keyEquivalent: "")
        clearItem.target = self
        clearItem.isEnabled = !store.archived.isEmpty
        menu.addItem(clearItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出 贝卡の Todo list",
                                  action: #selector(quit),
                                  keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc private func toggleWidget() {
        guard let window else { return }
        if store.isMinimized {
            restoreWidget()
            return
        }
        if window.isVisible {
            window.orderOut(nil)
        } else {
            window.orderFrontRegardless()
        }
    }

    @objc private func startAdding() {
        if store.isMinimized { restoreWidget() }
        activateForTextInput()
        store.isShowingArchive = false
        store.isAdding = true
        store.isExpanded = false
        DispatchQueue.main.async { [weak self] in self?.activateForTextInput() }
    }

    /// Brings the accessory app into the real AppKit text-input path.  The
    /// optional responder is an NSTextField (including the popover editor),
    /// which must become first responder after activation for WeChat IME.
    func activateForTextInput(responder: NSResponder? = nil) {
        guard let window else { return }
        // An accessory app does not become the active text-input client over a
        // full-screen Space on macOS 14+. Promote it only while text is being
        // edited, then return to its dockless widget mode when editing ends.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeMain()

        if let inputView = responder as? NSView, let inputWindow = inputView.window {
            inputWindow.makeKeyAndOrderFront(nil)
            inputWindow.makeFirstResponder(responder)
        } else if let responder {
            window.makeFirstResponder(responder)
        }
    }

    private func setTextInputSessionActive(_ isActive: Bool) {
        guard !isActive else { return }
        // Let SwiftUI finish dismissing its field/popover before hiding the
        // temporary Dock presence used to obtain a third-party IME context.
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.store.isAdding, self.store.editingTextId == nil else { return }
            NSApp.setActivationPolicy(.accessory)
        }
    }

    @objc private func toggleDesktopModeAction() { toggleDesktopMode() }

    @objc private func toggleLaunch() {
        let service = SMAppService.mainApp
        do {
            if autoLaunchEnabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            NSLog("登录项设置失败：\(error)")
        }
    }

    private var autoLaunchEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @objc private func clearArchived() { store.clearArchived() }

    @objc private func quit() { NSApp.terminate(nil) }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) { rebuildMenu(menu) }
}
