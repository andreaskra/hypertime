import AppKit
import SwiftUI

/// "Time to add", pre-filled with the pending bucket and live until the first keystroke (§6.4).
struct TimeField: View {
    @Bindable var viewModel: CheckInViewModel

    var body: some View {
        EditableField(
            text: viewModel.timeText,
            placeholder: "0:00:00",
            isInvalid: viewModel.timeFieldInvalid,
            monospacedDigits: true,
            alignment: .right,
            isFocused: viewModel.focus == .time,
            selectAllOnFocus: true,
            onText: { viewModel.timeTextChanged($0) },
            onCommand: handle,
            onBeginEditing: { viewModel.focus = .time }
        )
        .frame(width: 96, height: 22)
    }

    private func handle(_ selector: Selector, _ modifiers: NSEvent.ModifierFlags) -> Bool {
        switch selector {
        case .insertNewline:
            viewModel.commit()
            return true
        case .cancelOperation:
            viewModel.close()
            return true
        case .insertTab:
            viewModel.focusNext(from: .time)
            return true
        case .insertBacktab:
            viewModel.focus = .project
            return true
        case .moveUp:
            viewModel.adjustTime(by: 1, step: step(for: modifiers))
            return true
        case .moveDown:
            viewModel.adjustTime(by: -1, step: step(for: modifiers))
            return true
        case .deleteToBeginningOfLine where modifiers.contains(.command):
            viewModel.discard()
            return true
        default:
            return false
        }
    }

    private func step(for modifiers: NSEvent.ModifierFlags) -> Int {
        if modifiers.contains(.option) { return 3600 }
        if modifiers.contains(.shift) { return 300 }
        return 60
    }
}
