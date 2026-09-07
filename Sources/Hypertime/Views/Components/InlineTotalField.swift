import AppKit
import SwiftUI

/// Editable duration cell used by Reports (R-17). Enter or blur saves, Esc reverts.
struct InlineTotalField: View {
    let text: String
    var width: CGFloat = 84
    var isEnabled: Bool = true
    var onSave: (String) -> Void

    @State private var draft = ""
    @State private var isEditing = false

    var body: some View {
        if isEnabled {
            EditableField(
                text: isEditing ? draft : text,
                monospacedDigits: true,
                alignment: .right,
                isFocused: false,
                selectAllOnFocus: true,
                onText: { draft = $0; isEditing = true },
                onCommand: handle,
                onBeginEditing: { draft = text; isEditing = true },
                onEndEditing: {
                    if isEditing, draft != text { onSave(draft) }
                    isEditing = false
                }
            )
            .frame(width: width, height: 20)
        } else {
            Text(text)
                .font(.body.monospacedDigit())
                .frame(width: width, alignment: .trailing)
        }
    }

    private func handle(_ selector: Selector, _ modifiers: NSEvent.ModifierFlags) -> Bool {
        switch selector {
        case .insertNewline:
            if draft != text { onSave(draft) }
            isEditing = false
            return true
        case .cancelOperation:
            draft = text
            isEditing = false
            return true
        default:
            return false                                   // Tab keeps the normal key-view loop
        }
    }
}
