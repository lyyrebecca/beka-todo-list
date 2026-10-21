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
    var focusRequest: UUID? = nil

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = IMECompatibleTextField()
        field.cell = IMETextFieldCell(textCell: "")
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
        context.coordinator.updateFocusRequest(focusRequest)
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
        // A dismissed SwiftUI form must not leave a marked-text client alive.
        field.currentEditor()?.inputContext?.discardMarkedText()
        field.abortEditing()
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
        private var lastFocusRequest: UUID?

        init(parent: IMETextField) { self.parent = parent; lastFocusRequest = parent.focusRequest }
        deinit { observations.forEach(NotificationCenter.default.removeObserver) }

        func controlTextDidChange(_ notification: Notification) {
            guard let field else { return }
            parent.text = field.stringValue
        }

        func updateFocusRequest(_ request: UUID?) {
            guard request != lastFocusRequest else { return }
            lastFocusRequest = request
            initialFocusCompleted = false
            requestInitialFocusIfNeeded()
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
                      let field, let window, field.window === window, window.isVisible,
                      field.bounds.width > 1, field.bounds.height > 1,
                      !field.visibleRect.isEmpty else { return }
                Task { @MainActor in
                    guard !self.dismantled, !self.initialFocusCompleted,
                          field.window === window else { return }
                    if let delegate = NSApp.delegate as? AppDelegate {
                        delegate.activateForTextInput(responder: field)
                    } else {
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
                    editor.inputContext?.invalidateCharacterCoordinates()
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

final class IMECompatibleTextField: NSTextField {
    var onWindowChanged: (() -> Void)?
    var onLayoutReady: (() -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChanged?()
    }
    override func layout() {
        super.layout()
        currentEditor()?.inputContext?.invalidateCharacterCoordinates()
        onLayoutReady?()
    }
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted, window?.isKeyWindow == true, NSApp.isActive,
           bounds.width > 1, bounds.height > 1 {
            currentEditor()?.inputContext?.invalidateCharacterCoordinates()
        }
        return accepted
    }
}

/// A field owns its editor, rather than borrowing a shared editor left behind
/// by another SwiftUI field/popover. This also gives IMEs a stable screen anchor.
final class IMETextFieldCell: NSTextFieldCell {
    private let editor: IMEFieldEditor = {
        let editor = IMEFieldEditor()
        editor.isFieldEditor = true
        editor.isRichText = false
        editor.drawsBackground = false
        return editor
    }()

    override func fieldEditor(for controlView: NSView) -> NSTextView? {
        editor.ownerField = controlView as? NSTextField
        return editor
    }
}

final class IMEFieldEditor: NSTextView {
    weak var ownerField: NSTextField?

    override func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        let proposed = super.firstRect(forCharacterRange: range, actualRange: actualRange)
        guard let field = ownerField, let window = field.window else { return proposed }
        let anchor = window.convertToScreen(field.convert(field.bounds, to: nil))
        return Self.candidateRect(proposed: proposed, fieldRect: anchor,
                                  fontHeight: field.font?.boundingRectForFont.height ?? 18)
    }

    static func candidateRect(proposed: NSRect, fieldRect: NSRect, fontHeight: CGFloat) -> NSRect {
        // AppKit can temporarily report (0,0,0,0) during a first insertion or
        // animated resize. Passing it to WeChat IME opens its input at screen 0,0.
        let finite = [proposed.minX, proposed.minY, proposed.width, proposed.height].allSatisfy(\.isFinite)
        if finite, proposed.height > 0,
           fieldRect.insetBy(dx: -8, dy: -8).intersects(proposed.insetBy(dx: -1, dy: 0)) {
            return proposed
        }
        return NSRect(x: fieldRect.minX + 4, y: fieldRect.minY + 2,
                      width: 1, height: max(1, min(fontHeight, fieldRect.height)))
    }
}
