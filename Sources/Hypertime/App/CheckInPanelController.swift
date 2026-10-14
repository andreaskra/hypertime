import AppKit
import SwiftUI
import HypertimeCore

/// Non-activating floating panel: it can appear without taking keyboard focus (R-08, §6.3).
final class CheckInPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    var onEscape: (() -> Void)?
    /// Handles keys when no text field is first responder (e.g. the Confirm button has focus).
    var keyHandler: ((NSEvent) -> Bool)?

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {                    // Esc, when no text field is first responder
            onEscape?()
            return
        }
        if keyHandler?(event) == true { return }
        super.keyDown(with: event)
    }
}

/// Transparent content view that reports the mouse entering, so a passive popup can cancel its
/// auto-hide when the user reaches for it (D-14).
final class HoverView: NSView {
    var onMouseEntered: (() -> Void)?
    private var hoverArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onMouseEntered?()
    }
}

@MainActor
final class CheckInPanelController: NSObject, NSWindowDelegate {
    typealias Mode = PanelMode

    private let model: AppModel
    private let activation: ActivationController
    let viewModel: CheckInViewModel
    let presentation = PanelPresentation()

    private let panel: CheckInPanel
    private let hoverView: HoverView
    private let hostingView: NSHostingView<CheckInView>

    private var autoHideTimer: Timer?
    private var dismissWorkItem: DispatchWorkItem?
    /// True once the user has clicked or Cmd+Tabbed into the panel; only then do we hand focus back.
    private var didEngage = false

    /// Where to hang the panel: the status item's screen frame, or nil while it has no place in
    /// the menu bar (not yet laid out at launch, or pushed into the overflow).
    var anchorProvider: (() -> NSRect?)?
    var onPauseRequested: ((NSView) -> Void)?

    var isVisible: Bool { panel.isVisible }
    var isKey: Bool { panel.isKeyWindow }

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    init(model: AppModel, activation: ActivationController) {
        self.model = model
        self.activation = activation
        self.viewModel = CheckInViewModel(model: model)

        panel = CheckInPanel(contentRect: NSRect(x: 0, y: 0,
                                                 width: Tokens.Size.popupWidth,
                                                 height: Tokens.Size.popupMinHeight),
                             styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                             backing: .buffered,
                             defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.isReleasedWhenClosed = false

        hoverView = HoverView()
        hostingView = NSHostingView(rootView: CheckInView(viewModel: viewModel, presentation: presentation))
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        super.init()

        hoverView.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: hoverView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: hoverView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: hoverView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: hoverView.bottomAnchor),
        ])
        panel.contentView = hoverView
        panel.delegate = self
        panel.onEscape = { [weak self] in self?.close() }
        panel.keyHandler = { [weak self] event in self?.handleKey(event) ?? false }
        hoverView.onMouseEntered = { [weak self] in self?.cancelAutoHide() }

        viewModel.onCommitted = { [weak self] in self?.animateCommit() }
        viewModel.onDiscarded = { [weak self] in self?.animateDiscard() }
        viewModel.onClose = { [weak self] in self?.close() }
        viewModel.onContentSizeChanged = { [weak self] in self?.layoutPanel() }
        viewModel.onPauseRequested = { [weak self] in
            guard let self else { return }
            self.onPauseRequested?(self.hoverView)
        }
        presentation.onHeightRequest = { [weak self] height in self?.layoutPanel(height: height) }
    }

    // MARK: - Show / hide

    func show(mode: Mode) {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil

        viewModel.prepareForShow()
        presentation.commitPhase = .idle
        presentation.mode = mode
        if !panel.isVisible { presentation.isAppeared = false }
        layoutPanel()
        position()

        switch mode {
        case .passive:
            didEngage = false
            panel.orderFrontRegardless()                 // never activates us (R-08)
            appear(Tokens.Motion.popupAppearPassive)
            startAutoHide()
        case .focused:
            didEngage = true
            cancelAutoHide()
            activation.activate {
                panel.makeKeyAndOrderFront(nil)
            }
            appear(Tokens.Motion.popupAppearFocused)
            viewModel.focus = .project
        }
        Log.panel.debug("show(\(String(describing: mode), privacy: .public))")
    }

    private func appear(_ motion: Tokens.MotionToken) {
        withAnimation(motion.animation(reduceMotion: reduceMotion)) {
            presentation.isAppeared = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + motion.duration) { [weak self] in
            self?.panel.invalidateShadow()
        }
    }

    /// Animated dismiss; `orderOut` happens when the animation is done. Never changes focus.
    func hide() {
        cancelAutoHide()
        guard panel.isVisible else { return }
        withAnimation(Tokens.Motion.popupDismiss.animation(reduceMotion: reduceMotion)) {
            presentation.isAppeared = false
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.panel.orderOut(nil)
            self.presentation.isDiscarding = false
        }
        dismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Tokens.Motion.popupDismiss.duration, execute: work)
    }

    /// Status item click (§6.3).
    func toggle() {
        if isVisible && isKey {
            hide()
            activation.returnFocus()
        } else {
            show(mode: .focused)
        }
    }

    private func close() {
        let shouldRestore = didEngage
        hide()
        if shouldRestore { activation.returnFocus() }
    }

    private func finish(returnFocus: Bool) {
        hide()
        if returnFocus { activation.returnFocus() }
    }

    /// Confirm reads as the amount being handed to the project: the label shrinks, the numbers
    /// change at the bottom of that shrink, then it overshoots and settles before the panel goes.
    private func animateCommit() {
        cancelAutoHide()
        guard !reduceMotion else {
            viewModel.revealCommittedTotals()
            finish(returnFocus: true)
            return
        }

        presentation.commitPhase = .shrunk
        after(Tokens.Motion.commitShrink) { [weak self] in
            guard let self else { return }
            // The amount flips to zero and the project's total jumps, in one frame.
            self.viewModel.revealCommittedTotals()
            self.presentation.commitPhase = .magnified
            self.after(Tokens.Motion.commitMagnify) {
                self.presentation.commitPhase = .settled
                self.after(Tokens.Motion.commitSettle) {
                    self.finish(returnFocus: true)
                }
            }
        }
    }

    private func after(_ motion: Tokens.MotionToken, _ body: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + motion.duration) {
            MainActor.assumeIsolated(body)
        }
    }

    /// Discard reads as "thrown away": the amount collapses and clears, then the panel dismisses.
    private func animateDiscard() {
        guard !reduceMotion else {
            finish(returnFocus: true)
            return
        }
        withAnimation(Tokens.Motion.discardCollapse.curve) { presentation.isDiscarding = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + Tokens.Motion.discardCollapse.duration) { [weak self] in
            self?.finish(returnFocus: true)
        }
    }

    /// Called by the 1 s timer while visible.
    func tick() {
        guard isVisible else { return }
        viewModel.tick()
    }

    func refresh() {
        guard isVisible else { return }
        viewModel.refreshRows()
        viewModel.refreshStatus()
    }

    // MARK: - Keyboard when no field is first responder

    private func handleKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 48:                                            // Tab
            if event.modifierFlags.contains(.shift) {
                viewModel.focusPrevious(from: viewModel.focus)
            } else {
                viewModel.focusNext(from: viewModel.focus)
            }
            return true
        case 36, 76, 49:                                    // Return, Enter, Space
            guard viewModel.focus == .confirm || viewModel.focus == .none else { return false }
            viewModel.commit()
            return true
        default:
            return false
        }
    }

    // MARK: - Auto-hide (D-14)

    private func startAutoHide() {
        cancelAutoHide()
        let seconds = model.settings.passivePopupAutoHideSeconds
        guard seconds > 0 else { return }

        presentation.drainProgress = 1
        presentation.isDraining = true
        presentation.autoHideDeadline = Date().addingTimeInterval(TimeInterval(seconds))
        if !reduceMotion {
            withAnimation(.linear(duration: TimeInterval(seconds))) {
                presentation.drainProgress = 0
            }
        }
        autoHideTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(seconds), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.panel.isKeyWindow else { return }
                self.presentation.isDraining = false
                self.hide()                              // no focus change
            }
        }
    }

    private func cancelAutoHide() {
        autoHideTimer?.invalidate()
        autoHideTimer = nil
        if presentation.isDraining {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                presentation.isDraining = false
                presentation.drainProgress = 1
            }
            presentation.autoHideDeadline = nil
        }
    }

    // MARK: - Geometry

    /// Grows downward only: the top edge stays anchored under the menu bar icon.
    private func layoutPanel(height: CGFloat? = nil) {
        let requested = height ?? max(hostingView.fittingSize.height, Tokens.Size.popupMinHeight)
        let clamped = min(max(requested, Tokens.Size.popupMinHeight), Tokens.Size.popupMaxHeight * 1.5)
        let size = NSSize(width: Tokens.Size.popupWidth, height: clamped)
        guard abs(size.height - panel.frame.height) > 0.5 || size.width != panel.frame.width else { return }
        let top = panel.frame.maxY
        var frame = panel.frame
        frame.size = size
        frame.origin.y = top - size.height
        panel.setFrame(frame, display: true)
        panel.invalidateShadow()
    }

    private func position() {
        let size = panel.frame.size
        let screen = anchorScreen()
        var origin: NSPoint

        if let anchor = anchorProvider?() {
            // Centred on the item, 6 pt below the menu bar (§6.3) — the item sits centred inside
            // the menu bar, so its own bottom edge is a few points higher than the bar's.
            origin = NSPoint(x: anchor.midX - size.width / 2,
                             y: screen.visibleFrame.maxY - 6 - size.height)
        } else {
            // No place in the menu bar to hang off: fall back to the top right.
            let visible = screen.visibleFrame
            origin = NSPoint(x: visible.maxX - size.width - 12, y: visible.maxY - size.height - 6)
        }

        let visible = screen.visibleFrame
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height)
        panel.setFrameOrigin(origin)
    }

    private func anchorScreen() -> NSScreen {
        if let anchor = anchorProvider?(),
           let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
    }

    // MARK: - NSWindowDelegate

    func windowDidBecomeKey(_ notification: Notification) {
        didEngage = true
        cancelAutoHide()
        presentation.mode = .focused
        if viewModel.focus == .none { viewModel.focus = .project }
    }
}
