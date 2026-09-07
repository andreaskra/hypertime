import SwiftUI
import Observation

enum PanelMode {
    case passive, focused
}

/// View-layer presentation state for the check-in panel: appearance animation, the auto-hide
/// drain, the discard collapse and the height the window should take. Holds no domain state.
@MainActor
@Observable
final class PanelPresentation {
    var mode: PanelMode = .passive
    var isAppeared = false
    /// 1 = full width, 0 = drained. Drives the 20 s top-edge drain (D-14).
    var drainProgress: Double = 1
    var isDraining = false
    /// Set while the discard animation collapses the amount field.
    var isDiscarding = false
    /// Bumped to trigger the invalid shake.
    var invalidTrigger = 0
    /// Brief accent flash on commit.
    var isConfirming = false

    var contentHeight: CGFloat = Tokens.Size.popupMinHeight
    /// Y of the dropdown's top edge in panel coordinates — just under the project field it
    /// filters, so the two read as one combobox. It overlaps the amount and the today list
    /// rather than displacing them.
    var listTop: CGFloat = 120
    var dropdownHeight: CGFloat = 0
    /// Y of the button row, measured only while the dropdown is closed — so the space reserved
    /// for an open dropdown can never feed back into its own measurement.
    var buttonsTop: CGFloat = 0

    var onHeightRequest: ((CGFloat) -> Void)?

    /// The window only grows when an open dropdown would not otherwise fit: with a today list
    /// of any length the list already ends above the buttons, so opening it resizes nothing.
    var requiredHeight: CGFloat {
        let dropdownBottom = dropdownHeight > 0 ? listTop + dropdownHeight + Tokens.Space.s4 : 0
        return max(contentHeight, dropdownBottom)
    }

    func reportContentHeight(_ height: CGFloat) {
        guard abs(height - contentHeight) > 0.5 else { return }
        contentHeight = height
        onHeightRequest?(requiredHeight)
    }

    func reportListTop(_ value: CGFloat) {
        guard abs(value - listTop) > 0.5 else { return }
        listTop = value
        onHeightRequest?(requiredHeight)
    }

    func reportButtonsTop(_ value: CGFloat) {
        guard abs(value - buttonsTop) > 0.5 else { return }
        buttonsTop = value
    }

    func reportDropdownHeight(_ value: CGFloat) {
        guard abs(value - dropdownHeight) > 0.5 else { return }
        dropdownHeight = value
        onHeightRequest?(requiredHeight)
    }
}
