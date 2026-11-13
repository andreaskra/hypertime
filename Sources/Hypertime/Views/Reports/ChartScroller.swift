import AppKit
import SwiftUI

/// Two-finger scrolling and pinch zoom for the activity chart.
///
/// SwiftUI on macOS 15 reports neither: there is no scroll-wheel event, and `MagnifyGesture`
/// does not fire for a trackpad pinch inside a plain view. Both arrive as `NSResponder`
/// methods, so the chart's gesture layer is one AppKit view sitting over the plot.
///
/// Deltas come out in points. The chart turns them into days, because only it knows how wide
/// a day currently is — which is the whole point of a zoomable axis.
struct ChartScroller: NSViewRepresentable {
    /// Horizontal movement in points. Positive means the content should move into the past.
    var onScroll: (CGFloat) -> Void
    /// Multiplier (1.2 = zoom in a fifth) and where the cursor sits across the plot, 0…1.
    var onZoom: (Double, Double) -> Void
    /// Pointer position across the plot, 0…1, or nil when it leaves.
    var onHover: (Double?) -> Void

    func makeNSView(context: Context) -> ScrollView { ScrollView() }

    func updateNSView(_ view: ScrollView, context: Context) {
        view.onScroll = onScroll
        view.onZoom = onZoom
        view.onHover = onHover
    }

    final class ScrollView: NSView {
        var onScroll: ((CGFloat) -> Void)?
        var onZoom: ((Double, Double) -> Void)?
        var onHover: ((Double?) -> Void)?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
                owner: self))
        }

        private func fraction(_ event: NSEvent) -> Double {
            guard bounds.width > 0 else { return 0.5 }
            let x = convert(event.locationInWindow, from: nil).x
            return min(max(Double(x / bounds.width), 0), 1)
        }

        override func mouseEntered(with event: NSEvent) { onHover?(fraction(event)) }
        override func mouseMoved(with event: NSEvent) { onHover?(fraction(event)) }
        override func mouseExited(with event: NSEvent) { onHover?(nil) }

        override func scrollWheel(with event: NSEvent) {
            // A horizontal swipe pans. A vertical one does too, because a chart with no
            // vertical scrolling of its own should not simply swallow the gesture.
            let horizontal = event.scrollingDeltaX
            let vertical = event.scrollingDeltaY
            let delta = abs(horizontal) >= abs(vertical) ? horizontal : vertical
            guard delta != 0 else { return }
            onScroll?(delta)
        }

        /// Trackpad pinch. `magnification` is a fraction per event, accumulated by the system.
        override func magnify(with event: NSEvent) {
            guard event.magnification != 0 else { return }
            onZoom?(1 + Double(event.magnification), fraction(event))
        }

        /// Double-tap with two fingers, the system's "smart zoom".
        override func smartMagnify(with event: NSEvent) {
            onZoom?(2, fraction(event))
        }
    }
}
