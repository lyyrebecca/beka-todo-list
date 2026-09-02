import AppKit
import SwiftUI

/// AppKit-backed field used for every editable Todo title.
///
/// SwiftUI's FocusState can visually focus a field while an LSUIElement app is
/// above a full-screen window, but some third-party IMEs then never receive an
/// NSTextInputClient. NSTextField is that client directly, so marked Chinese
/// text and the WeChat IME candidate window keep working in this configuration.
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
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        field.placeholderString = placeholder
        field.font = font
        field.textColor = textColor
        // Binding updates caused by composition preserve the same string value,
        // so AppKit keeps its marked text; only external changes replace it.
        if field.stringValue != text {
            field.stringValue = text
        }
        context.coordinator.requestInitialFocusIfNeeded()
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: IMETextField
        weak var field: NSTextField?
        private var requestedInitialFocus = false

        init(parent: IMETextField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field else { return }
            parent.text = field.stringValue
        }

        /// Activation is intentionally repeated after the floating window has
        /// joined the active space. This is the point at which WeChat IME
        /// creates its input context when another app is in full screen.
        func requestInitialFocusIfNeeded() {
            guard !requestedInitialFocus, let field else { return }
            requestedInitialFocus = true
            [0.0, 0.06, 0.18].forEach { delay in
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak field] in
                    guard let self, let field, field.window != nil else { return }
                    self.focus(field)
                }
            }
        }

        private func focus(_ field: NSTextField) {
            Task { @MainActor in
                if let delegate = NSApp.delegate as? AppDelegate {
                    delegate.activateForTextInput(responder: field)
                } else if let inputWindow = field.window {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    inputWindow.makeKeyAndOrderFront(nil)
                    inputWindow.makeFirstResponder(field)
                }
            }
        }
    }
}

private final class IMECompatibleTextField: NSTextField {
    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { inputContext?.activate() }
        return accepted
    }
}
