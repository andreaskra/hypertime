import AppKit
import SwiftUI

/// The project combobox (30 pt, r10). Typing filters, ↑/↓ move the dropdown highlight,
/// Tab goes to the amount field, Enter commits, Esc closes (R-11, §6.4).
struct ProjectField: View {
    @Bindable var viewModel: CheckInViewModel
    @Environment(\.colorSchemeContrast) private var contrast

    private var isFocused: Bool { viewModel.focus == .project }

    var body: some View {
        HStack(spacing: Tokens.Space.s2) {
            EditableField(
                text: viewModel.fieldText,
                placeholder: "Project name",
                font: Tokens.Typography.body,
                isFocused: isFocused,
                selectAllOnFocus: true,
                onText: { viewModel.projectTextChanged($0) },
                onCommand: handle,
                onBeginEditing: { viewModel.focus = .project }
            )
            Button {
                viewModel.focus = .project
                viewModel.toggleProjectList()
            } label: {
                Image(systemName: Tokens.Icons.dropdownChevron)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Tokens.Palette.textTertiary.color)
                    .rotationEffect(.degrees(viewModel.isProjectListOpen ? 180 : 0))
                    .frame(width: 14, height: Tokens.Size.fieldHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(viewModel.isProjectListOpen ? "Hide the project list" : "Show the project list")
        }
        .padding(.horizontal, Tokens.Space.fieldInset)
        .frame(height: Tokens.Size.fieldHeight)
        .background {
            RoundedRectangle(cornerRadius: Tokens.Radius.field, style: .continuous)
                .fill(Tokens.Palette.fieldBackground.color)
                .overlay {
                    RoundedRectangle(cornerRadius: Tokens.Radius.field, style: .continuous)
                        .strokeBorder(Tokens.Palette.separator.color,
                                      lineWidth: Tokens.Focus.hairlineWidth(contrast == .increased))
                }
        }
        .focusRing(isFocused, radius: Tokens.Radius.field)
        .contentShape(Rectangle())
        .onTapGesture { viewModel.focus = .project }
    }

    private func handle(_ selector: Selector, _ modifiers: NSEvent.ModifierFlags) -> Bool {
        switch selector {
        case .moveUp:
            viewModel.moveSelection(by: -1)
            return true
        case .moveDown:
            viewModel.moveSelection(by: 1)
            return true
        case .insertNewline:
            // With the list open, ↩ is the list's: it takes the highlighted row and closes it.
            // Only once there is no list in the way does ↩ mean "commit the popup".
            if viewModel.acceptHighlightedRow() { return true }
            viewModel.commit()
            return true
        case .cancelOperation:
            // First Esc dismisses the dropdown; a second one closes the popup.
            if viewModel.isProjectListOpen {
                viewModel.closeProjectList()
            } else {
                viewModel.close()
            }
            return true
        case .insertTab:
            viewModel.closeProjectList()
            viewModel.focus = .time
            return true
        case .insertBacktab:
            return true                                   // nothing before the project field
        case .deleteToBeginningOfLine where modifiers.contains(.command):
            viewModel.discard()
            return true
        default:
            return false
        }
    }
}
