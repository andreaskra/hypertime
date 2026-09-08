import AppKit
import SwiftUI

/// An `NSTextField` wrapped for SwiftUI so Tab/Enter/Esc/arrow keys can be intercepted
/// deterministically (§6.4). Phase 2 draws the chrome in SwiftUI, so the field itself is
/// borderless and transparent.
struct EditableField: NSViewRepresentable {
    var text: String
    var placeholder: String = ""
    var font: Tokens.FontToken = Tokens.Typography.body
    var textColor: NSColor = Tokens.Palette.textPrimary.nsColor
    var isInvalid: Bool = false
    var alignment: NSTextAlignment = .natural
    var isFocused: Bool
    var selectAllOnFocus: Bool = false
    var onText: (String) -> Void = { _ in }
    /// Return true when the command was handled.
    var onCommand: (Selector, NSEvent.ModifierFlags) -> Bool = { _, _ in false }
    var onBeginEditing: () -> Void = {}
    var onEndEditing: () -> Void = {}

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.backgroundColor = .clear
        field.focusRingType = .none                     // the design draws its own ring
        field.lineBreakMode = .byTruncatingTail
        field.usesSingleLineMode = true
        field.cell?.sendsActionOnEndEditing = false
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self

        if field.stringValue != text, !context.coordinator.isTyping {
            let wasEditing = field.currentEditor() != nil
            field.stringValue = text
            // The live counter rewrites the field every second; keep the pre-selected text
            // selected so the first keystroke still replaces it. Only while the window has the
            // keyboard — otherwise the selection keeps redrawing itself bright in a panel the
            // user has already left.
            if wasEditing, selectAllOnFocus, field.window?.isKeyWindow == true {
                field.currentEditor()?.selectAll(nil)
            }
        }
        field.font = font.nsFont
        field.alignment = alignment
        field.textColor = isInvalid ? Tokens.Palette.invalid.nsColor : textColor
        if field.placeholderString != placeholder {
            field.placeholderAttributedString = NSAttributedString(
                string: placeholder,
                attributes: [.font: font.nsFont, .foregroundColor: Tokens.Palette.textTertiary.nsColor]
            )
        }

        guard let window = field.window, window.isKeyWindow else { return }
        let isFirstResponder = window.firstResponder === field.currentEditor() && field.currentEditor() != nil
        if isFocused, !isFirstResponder {
            // Defer: SwiftUI may still be in the middle of a layout pass.
            DispatchQueue.main.async {
                guard let window = field.window, window.isKeyWindow,
                      window.firstResponder !== field.currentEditor() else { return }
                window.makeFirstResponder(field)
                if selectAllOnFocus { field.currentEditor()?.selectAll(nil) }
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: EditableField
        var isTyping = false

        init(parent: EditableField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            isTyping = true
            parent.onText(field.stringValue)
            isTyping = false
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            parent.onBeginEditing()
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            parent.onEndEditing()
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            let modifiers = NSApp.currentEvent?.modifierFlags ?? []
            return parent.onCommand(commandSelector, modifiers)
        }
    }
}

extension Selector {
    static let insertNewline = #selector(NSStandardKeyBindingResponding.insertNewline(_:))
    static let cancelOperation = #selector(NSStandardKeyBindingResponding.cancelOperation(_:))
    static let insertTab = #selector(NSStandardKeyBindingResponding.insertTab(_:))
    static let insertBacktab = #selector(NSStandardKeyBindingResponding.insertBacktab(_:))
    static let moveUp = #selector(NSStandardKeyBindingResponding.moveUp(_:))
    static let moveDown = #selector(NSStandardKeyBindingResponding.moveDown(_:))
    static let deleteToBeginningOfLine = #selector(NSStandardKeyBindingResponding.deleteToBeginningOfLine(_:))
}
