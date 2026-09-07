import AppKit
import SwiftUI

/// The project name field. Typing filters, ↑/↓ move the selection, Tab goes to the time
/// field, Enter commits, Esc closes (R-11, §6.4).
struct ProjectField: View {
    @Bindable var viewModel: CheckInViewModel

    var body: some View {
        EditableField(
            text: viewModel.fieldText,
            placeholder: "What are you working on?",
            isFocused: viewModel.focus == .project,
            selectAllOnFocus: true,
            onText: { viewModel.projectTextChanged($0) },
            onCommand: handle,
            onBeginEditing: { viewModel.focus = .project }
        )
        .frame(height: 22)
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
            viewModel.commit()
            return true
        case .cancelOperation:
            viewModel.close()
            return true
        case .insertTab:
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
