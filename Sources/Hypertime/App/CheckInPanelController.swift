import AppKit
import SwiftUI
import HypertimeCore

/// Non-activating floating panel: it can appear without taking keyboard focus (R-08, §6.3).
final class CheckInPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    var onEscape: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {                    // Esc, when no text field is first responder
            onEscape?()
            return
        }
        super.keyDown(with: event)
    }
}

/// `NSVisualEffectView` that reports the mouse entering, so a passive popup can cancel its
/// auto-hide when the user reaches for it (D-14).
final class HoverEffectView: NSVisualEffectView {
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
    enum Mode { case passive, focused }

    private let model: AppModel
    private let activation: ActivationController
    let viewModel: CheckInViewModel

    private let panel: CheckInPanel
    private let effectView: HoverEffectView
    private let hostingView: NSHostingView<CheckInView>

    private var autoHideTimer: Timer?
    /// True once the user has clicked or Cmd+Tabbed into the panel; only then do we hand focus back.
    private var didEngage = false

    /// Supplies the status item button for positioning.
    var anchorProvider: (() -> NSStatusBarButton?)?
    var onPauseRequested: ((NSView) -> Void)?

    var isVisible: Bool { panel.isVisible }
    var isKey: Bool { panel.isKeyWindow }

    init(model: AppModel, activation: ActivationController) {
        self.model = model
        self.activation = activation
        self.viewModel = CheckInViewModel(model: model)

        panel = CheckInPanel(contentRect: NSRect(x: 0, y: 0, width: CheckInView.width, height: 200),
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

        effectView = HoverEffectView()
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 16
        effectView.layer?.masksToBounds = true

        hostingView = NSHostingView(rootView: CheckInView(viewModel: viewModel))
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        super.init()

        effectView.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: effectView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor),
        ])
        panel.contentView = effectView
        panel.delegate = self
        panel.onEscape = { [weak self] in self?.close() }
        effectView.onMouseEntered = { [weak self] in self?.cancelAutoHide() }

        viewModel.onCommitted = { [weak self] in self?.finish(returnFocus: true) }
        viewModel.onDiscarded = { [weak self] in self?.finish(returnFocus: true) }
        viewModel.onClose = { [weak self] in self?.close() }
        viewModel.onContentSizeChanged = { [weak self] in self?.layoutPanel() }
        viewModel.onPauseRequested = { [weak self] in
            guard let self else { return }
            self.onPauseRequested?(self.effectView)
        }
    }

    // MARK: - Show / hide

    func show(mode: Mode) {
        viewModel.prepareForShow()
        layoutPanel()
        position()

        switch mode {
        case .passive:
            didEngage = false
            panel.orderFrontRegardless()                 // never activates us (R-08)
            startAutoHide()
        case .focused:
            didEngage = true
            cancelAutoHide()
            activation.activate {
                panel.makeKeyAndOrderFront(nil)
            }
            viewModel.focus = .project
        }
        Log.panel.debug("show(\(String(describing: mode), privacy: .public))")
    }

    func hide() {
        cancelAutoHide()
        panel.orderOut(nil)                              // never changes focus by itself
    }

    /// Status item click (§6.3).
    func toggle() {
        if isVisible && isKey {
            hide()
            activation.returnFocus()
        } else if isVisible {
            show(mode: .focused)
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

    // MARK: - Auto-hide (D-14)

    private func startAutoHide() {
        cancelAutoHide()
        let seconds = model.settings.passivePopupAutoHideSeconds
        guard seconds > 0 else { return }
        autoHideTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(seconds), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.panel.isKeyWindow else { return }
                self.hide()                              // no focus change
            }
        }
    }

    private func cancelAutoHide() {
        autoHideTimer?.invalidate()
        autoHideTimer = nil
    }

    // MARK: - Geometry

    private func layoutPanel() {
        hostingView.layoutSubtreeIfNeeded()
        let fitting = hostingView.fittingSize
        let size = NSSize(width: CheckInView.width, height: max(fitting.height, 120))
        guard size != panel.frame.size else { return }
        let top = panel.frame.maxY
        var frame = panel.frame
        frame.size = size
        frame.origin.y = top - size.height                 // keep the top edge anchored
        panel.setFrame(frame, display: true)
    }

    private func position() {
        let size = panel.frame.size
        let screen = anchorScreen()
        var origin: NSPoint

        if let button = anchorProvider?(), let window = button.window, window.screen != nil {
            let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
            origin = NSPoint(x: anchor.midX - size.width / 2, y: anchor.minY - 6 - size.height)
        } else {
            // Status item hidden in the menu bar overflow: fall back to the top right.
            let visible = screen.visibleFrame
            origin = NSPoint(x: visible.maxX - size.width - 12, y: visible.maxY - size.height - 6)
        }

        let visible = screen.visibleFrame
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height)
        panel.setFrameOrigin(origin)
    }

    private func anchorScreen() -> NSScreen {
        if let button = anchorProvider?(), let screen = button.window?.screen { return screen }
        return NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
    }

    // MARK: - NSWindowDelegate

    func windowDidBecomeKey(_ notification: Notification) {
        didEngage = true
        cancelAutoHide()
        if viewModel.focus == .none { viewModel.focus = .project }
    }
}
