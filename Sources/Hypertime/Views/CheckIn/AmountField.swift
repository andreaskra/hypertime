import AppKit
import SwiftUI

/// "Amount to add": 26 pt rounded tabular, centred, with an accent "+" prefix. Pre-filled from
/// the pending bucket and live until the first keystroke, which freezes it (§6.4, D-08).
struct AmountField: View {
    @Bindable var viewModel: CheckInViewModel
    @Bindable var presentation: PanelPresentation

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isFocused: Bool { viewModel.focus == .time }

    var body: some View {
        VStack(spacing: Tokens.Space.s1) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("+")
                    .font(Tokens.Typography.timeAdd.font.weight(.semibold))
                    .foregroundStyle(Tokens.Palette.accent)
                EditableField(
                    text: viewModel.timeText,
                textRevision: viewModel.timeTextRevision,
                    placeholder: "0:00:00",
                    font: Tokens.Typography.timeAdd,
                    isInvalid: viewModel.timeFieldInvalid,
                    alignment: .center,
                    isFocused: isFocused,
                    selectAllOnFocus: true,
                    onText: { viewModel.timeTextChanged($0) },
                    onCommand: handle,
                    onBeginEditing: { viewModel.beginEditingTime() }
                )
                .frame(width: 150)
            }
            .frame(maxWidth: .infinity)
            .frame(height: presentation.isDiscarding ? 0 : 38)
            .opacity(presentation.isDiscarding ? 0 : 1)
            .clipped()
            .padding(.horizontal, Tokens.Space.s2)
            .background {
                RoundedRectangle(cornerRadius: Tokens.Radius.field, style: .continuous)
                    .fill(viewModel.timeFieldInvalid
                          ? Tokens.Palette.invalidFieldBackground.color
                          : Color.clear)
            }
            .focusRing(isFocused, radius: Tokens.Radius.field)
            .shake(presentation.invalidTrigger)
            // Confirm bounce. Scale only: a rotation3DEffect on this full-width plane displaced
            // the label out of its slot in the only rendering that can be captured here, and a
            // wrong guess would be visible on every single commit.
            .scaleEffect(presentation.commitScale)
            .animation(presentation.commitAnimation(reduceMotion: reduceMotion),
                       value: presentation.commitPhase)

            Text(caption)
                .font(Tokens.Typography.caption)
                .foregroundStyle(Tokens.Palette.textTertiary.color)
                .lineLimit(1)
                .truncationMode(.middle)
                .opacity(presentation.isDiscarding ? 0 : 1)
        }
        .animation(Tokens.Motion.discardCollapse.animation(reduceMotion: reduceMotion), value: presentation.isDiscarding)
        .onChange(of: viewModel.timeFieldInvalid) {
            if viewModel.timeFieldInvalid { presentation.invalidTrigger += 1 }
        }
    }

    private var caption: String {
        if viewModel.timeFieldInvalid { return "Try 1:30 or 90m" }
        // A popup that let itself in says how long it will wait, and how to answer it without
        // reaching for the mouse (artboard A-popup passive).
        if let deadline = presentation.autoHideDeadline, !isFocused {
            let left = Int(deadline.timeIntervalSinceNow.rounded(.up))
            if left > 0 { return "⌘Tab to answer · hides in \(left) s" }
        }
        // While the field holds an entry ↩ has not taken yet, the next press sets the amount
        // rather than saving — and the line has to say the thing the key will actually do.
        if isFocused && !viewModel.isTimeAccepted {
            return "since last check-in · ↩ sets the amount"
        }
        let name = viewModel.effectiveName.isEmpty ? viewModel.currentProjectName : viewModel.effectiveName
        guard let name else { return "nothing tracked yet · counting starts on ↩" }
        let verb = viewModel.isPaused ? "adds it and resumes" : "adds it to"
        let lead = viewModel.isPaused ? "not counting" : "since last check-in"
        return "\(lead) · ↩ \(verb) \(name)"
    }

    private func handle(_ selector: Selector, _ modifiers: NSEvent.ModifierFlags) -> Bool {
        switch selector {
        case .insertNewline:
            // First ↩ takes the amount and normalises it; a second commits the popup, so what
            // gets saved is a number the user has actually seen.
            if viewModel.acceptTimeEntry() { return true }
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

    /// ±1 min, ±5 min with Shift, ±1 h with Option (§6.4).
    private func step(for modifiers: NSEvent.ModifierFlags) -> Int {
        if modifiers.contains(.option) { return 3600 }
        if modifiers.contains(.shift) { return 300 }
        return 60
    }
}
