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
    var fieldBottom: CGFloat = 78
    var dropdownHeight: CGFloat = 0

    var onHeightRequest: ((CGFloat) -> Void)?

    var requiredHeight: CGFloat {
        let dropdownBottom = dropdownHeight > 0
            ? fieldBottom + Tokens.Space.s1 + dropdownHeight + Tokens.Space.s4
            : 0
        return max(contentHeight, dropdownBottom)
    }

    func reportContentHeight(_ height: CGFloat) {
        guard abs(height - contentHeight) > 0.5 else { return }
        contentHeight = height
        onHeightRequest?(requiredHeight)
    }

    func reportFieldBottom(_ value: CGFloat) {
        guard abs(value - fieldBottom) > 0.5 else { return }
        fieldBottom = value
        onHeightRequest?(requiredHeight)
    }

    func reportDropdownHeight(_ value: CGFloat) {
        guard abs(value - dropdownHeight) > 0.5 else { return }
        dropdownHeight = value
        onHeightRequest?(requiredHeight)
    }
}
