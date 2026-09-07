import AppKit
import SwiftUI

/// Editable duration cell used by Reports (R-17). Enter or blur saves, Esc reverts.
struct InlineTotalField: View {
    let text: String
    var width: CGFloat = 78
    var isEnabled: Bool = true
    var alignment: NSTextAlignment = .right
    var onSave: (String) -> Void

    @State private var draft = ""
    @State private var isEditing = false
    @State private var isHovering = false

    var body: some View {
        if isEnabled {
            EditableField(
                text: isEditing ? draft : text,
                font: Tokens.Typography.timeCell,
                textColor: Tokens.Palette.textPrimary.nsColor,
                alignment: alignment,
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
            .padding(.horizontal, Tokens.Space.s1)
            .background {
                RoundedRectangle(cornerRadius: Tokens.Radius.cell, style: .continuous)
                    .fill(isEditing ? Tokens.Palette.fieldBackground.color
                          : (isHovering ? Tokens.Palette.rowHover.color : .clear))
            }
            .onHover { isHovering = $0 }
        } else {
            Text(text)
                .font(Tokens.Typography.timeCell)
                .foregroundStyle(Tokens.Palette.textSecondary.color)
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
