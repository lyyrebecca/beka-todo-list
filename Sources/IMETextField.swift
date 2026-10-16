import AppKit
import SwiftUI

/// AppKit-backed field used for every editable Todo title.
///
/// SwiftUI's FocusState can visually focus a field while an LSUIElement app is
/// above a full-screen window, but some third-party IMEs then never receive an
/// NSTextInputClient. AppKit supplies a native field editor for NSTextField;
/// its input context must be activated only after real window attachment.
struct IMETextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let font: NSFont
    let textColor: NSColor
    let roundedBorder: Bool

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = IMECompatibleTextField()
        field.delegate = context.coordinator
        field.placeholderString = placeholder
        field.font = font
        field.textColor = textColor
        field.isEditable = true
        field.isSelectable = true
        field.isBezeled = roundedBorder
        field.isBordered = roundedBorder
        field.drawsBackground = roundedBorder
        field.backgroundColor = roundedBorder ? .textBackgroundColor : .clear
        field.focusRingType = .default
        field.lineBreakMode = .byTruncatingTail
        context.coordinator.field = field
        let coordinator = context.coordinator
        field.onWindowChanged = { [weak coordinator] in coordinator?.windowAttachmentChanged() }
        field.onLayoutReady = { [weak coordinator] in coordinator?.requestInitialFocusIfNeeded() }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        field.placeholderString = placeholder
        field.font = font
        field.textColor = textColor
        // Binding updates caused by composition preserve the same string value,
        // so AppKit keeps its marked text; only external changes replace it.
        let isComposing = (field.currentEditor() as? NSTextView)?.hasMarkedText() == true
        if field.stringValue != text && !isComposing {
            field.stringValue = text
        }
        context.coordinator.requestInitialFocusIfNeeded()
    }

    static func dismantleNSView(_ field: NSTextField, coordinator: Coordinator) {
        coordinator.cancelFocusRequest()
        (field as? IMECompatibleTextField)?.onWindowChanged = nil
        (field as? IMECompatibleTextField)?.onLayoutReady = nil
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: IMETextField
        weak var field: NSTextField?
        private var initialFocusCompleted = false
        private var focusQueued = false
        private var dismantled = false
        private weak var observedWindow: NSWindow?
        private var observations: [NSObjectProtocol] = []

        init(parent: IMETextField) { self.parent = parent }
        deinit { observations.forEach(NotificationCenter.default.removeObserver) }

        func controlTextDidChange(_ notification: Notification) {
            guard let field else { return }
            parent.text = field.stringValue
        }

        func windowAttachmentChanged() {
            removeObservations()
            guard !dismantled, let window = field?.window else { return }
            observedWindow = window
            // The first insertion may attach AFTER the expansion animation. Wait
            // for actual lifecycle events, not a one-shot 0/60/180ms deadline.
            let center = NotificationCenter.default
            observations.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification,
                object: window, queue: .main) { [weak self] _ in self?.requestInitialFocusIfNeeded() })
            observations.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification,
                object: NSApp, queue: .main) { [weak self] _ in self?.requestInitialFocusIfNeeded() })
            requestInitialFocusIfNeeded()
        }

        func requestInitialFocusIfNeeded() {
            guard !dismantled, !initialFocusCompleted, !focusQueued,
                  let field, let window = field.window else { return }
            if observedWindow !== window { windowAttachmentChanged(); return }
            focusQueued = true
            DispatchQueue.main.async { [weak self, weak field, weak window] in
                guard let self else { return }
                self.focusQueued = false
                guard !self.dismantled, !self.initialFocusCompleted,
                      let field, let window, field.window === window, window.isVisible else { return }
                Task { @MainActor in
                    guard !self.dismantled, !self.initialFocusCompleted,
                          field.window === window else { return }
                    if let delegate = NSApp.delegate as? AppDelegate {
                        delegate.activateForTextInput(responder: field)
                    } else {
                        NSApp.setActivationPolicy(.regular)
                        NSApp.activate(ignoringOtherApps: true)
                        window.makeKeyAndOrderFront(nil)
                        window.makeMain()
                        window.makeFirstResponder(field)
                    }
                    // NSTextField's real NSTextInputClient is its field editor.
                    // Do not consume the request until activation AND editor
                    // ownership succeed; didBecomeActive/Key will retry it.
                    guard NSApp.isActive, window.isKeyWindow,
                          let editor = field.currentEditor(), window.firstResponder === editor else { return }
                    editor.inputContext?.activate()
                    self.initialFocusCompleted = true
                    self.removeObservations()
                }
            }
        }

        func cancelFocusRequest() {
            dismantled = true
            removeObservations()
        }

        private func removeObservations() {
            observations.forEach(NotificationCenter.default.removeObserver)
            observations.removeAll()
            observedWindow = nil
        }
    }
}

private final class IMECompatibleTextField: NSTextField {
    var onWindowChanged: (() -> Void)?
    var onLayoutReady: (() -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChanged?()
    }
    override func layout() {
        super.layout()
        onLayoutReady?()
    }
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { currentEditor()?.inputContext?.activate() }
        return accepted
    }
}
