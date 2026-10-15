import AppKit
import SwiftUI

/// An `NSTextField` wrapped for SwiftUI so Tab/Enter/Esc/arrow keys can be intercepted
/// deterministically (§6.4). Phase 2 draws the chrome in SwiftUI, so the field itself is
/// borderless and transparent.
/// Reports focus the moment it arrives. `controlTextDidBeginEditing` is no use for this: AppKit
/// withholds it until the first keystroke, so a field could hold the caret for seconds while the
/// app still believed nothing was focused — and kept writing into it.
/// Only *gaining* focus is reported here. A text field hands off to its field editor the instant
/// it becomes first responder, which calls `resignFirstResponder` on the field itself — reading
/// that as "focus lost" fires an end-of-editing the moment the user clicks in. Losing focus comes
/// from `controlTextDidEndEditing`, which is reliable in that direction.
final class FocusReportingTextField: NSTextField {
    var onFocusGained: (() -> Void)?

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocusGained?() }
        return accepted
    }
}

struct EditableField: NSViewRepresentable {
    var text: String
    /// Bumped by the view model when it means to replace the text. Anything else leaves a field
    /// that holds the keyboard untouched — a caret is a promise that the text will stay put.
    var textRevision: Int = 0
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
        let field = FocusReportingTextField(string: text)
        field.delegate = context.coordinator
        field.onFocusGained = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onBeginEditing()
        }
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

        let isEditing = field.currentEditor() != nil
        let wasPushed = textRevision != context.coordinator.lastRevision
        context.coordinator.lastRevision = textRevision
        // A field with the caret in it is only ever rewritten on purpose.
        if field.stringValue != text, !context.coordinator.isTyping, !isEditing || wasPushed {
            field.stringValue = text
            if wasPushed, isEditing, selectAllOnFocus, field.window?.isKeyWindow == true {
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
        var lastRevision = 0

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
