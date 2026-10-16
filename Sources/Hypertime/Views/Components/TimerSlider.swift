import AppKit
import SwiftUI
import HypertimeCore

/// The timer picker (T-10): one sweep from a minute to eight hours over `TimerLadder`'s slots,
/// so the first hour — where nearly every timer lands — gets two thirds of the travel.
///
/// The knob follows the pointer, the wheel nudges it a slot at a time, and a click takes
/// whatever the readout says. There is no separate confirm step, so the one rule that has to
/// hold is that the readout is always the truth: it names the pointer's slot while hovering,
/// the scrolled slot after a scroll, and that is what a click sets.
struct TimerSlider: View {
    /// The timer already on the task, marked on the track so it can be found again.
    var current: Seconds?
    var onPick: (Seconds) -> Void

    @State private var index: Int
    @State private var pointer: Double?
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// With nothing set yet the slider opens on the length people actually reach for.
    private static let opening: Seconds = 1500

    init(current: Seconds?, onPick: @escaping (Seconds) -> Void) {
        self.current = current
        self.onPick = onPick
        _index = State(initialValue: TimerLadder.index(nearest: current ?? Self.opening))
    }

    /// The pointer wins while it is over the track; a scroll takes it back until the mouse
    /// moves again. Everything on screen reads from here.
    private var shownIndex: Int {
        if let pointer { return TimerLadder.index(atFraction: pointer) }
        return index
    }

    private var shownSeconds: Seconds { TimerLadder.seconds(at: shownIndex) }

    private var motion: Animation? {
        Tokens.Motion.highlightMove.animation(reduceMotion: reduceMotion)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s1) {
            readout
            GeometryReader { geo in
                VStack(alignment: .leading, spacing: Tokens.Space.s1) {
                    track(width: geo.size.width)
                    scale(width: geo.size.width)
                }
            }
            .frame(height: Tokens.Slider.bandHeight + Tokens.Slider.scaleHeight + Tokens.Space.s1)
            Text("scroll to adjust · click to set")
                .font(Tokens.Typography.keyboardHint)
                .foregroundStyle(Tokens.Palette.textTertiary.color)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var readout: some View {
        Text(TimerLadder.label(shownSeconds))
            .font(Tokens.Typography.timeAdd)
            .foregroundStyle(Tokens.Palette.accent)
            .contentTransition(.numericText())
            .animation(Tokens.Motion.digitTick.animation(reduceMotion: reduceMotion), value: shownSeconds)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Track

    /// Knob centres are inset by its radius, so neither end of the sweep is clipped.
    private func knobX(width: CGFloat) -> CGFloat {
        x(forFraction: TimerLadder.fraction(ofIndex: shownIndex), width: width)
    }

    private func x(forFraction fraction: Double, width: CGFloat) -> CGFloat {
        Self.radius + CGFloat(fraction) * Self.span(width)
    }

    /// The inverse: where the pointer is, in the same space. Without this the knob would lag
    /// the cursor by up to a knob radius at the ends of the sweep, and the control's one rule
    /// is that what is under the cursor is what you get.
    static func fraction(forX x: CGFloat, width: CGFloat) -> Double {
        min(max(Double((x - radius) / span(width)), 0), 1)
    }

    private static let radius = Tokens.Slider.knob / 2
    private static func span(_ width: CGFloat) -> CGFloat { max(width - 2 * radius, 1) }

    private func track(width: CGFloat) -> some View {
        let knob = knobX(width: width)
        return ZStack(alignment: .leading) {
            Capsule()
                .fill(Tokens.Palette.buttonSecondary.color)
                .frame(height: Tokens.Slider.trackHeight)
            Capsule()
                .fill(Tokens.Palette.accent)
                .frame(width: knob, height: Tokens.Slider.trackHeight)
            // Where the hour sits, so the non-linear scale is visible rather than implied.
            marker(at: TimerLadder.fraction(ofIndex: TimerLadder.index(nearest: 3600)),
                   width: width, color: Tokens.Palette.textTertiary.color)
            // …and where the task's own timer sits, so it can be found again.
            if let current {
                marker(at: TimerLadder.fraction(ofIndex: TimerLadder.index(nearest: current)),
                       width: width, color: Tokens.Palette.textSecondary.color)
            }
            Circle()
                .fill(Tokens.Palette.accent)
                .overlay { Circle().strokeBorder(Tokens.Palette.onAccent.color, lineWidth: Tokens.Slider.knobRing) }
                .frame(width: Tokens.Slider.knob, height: Tokens.Slider.knob)
                .scaleEffect(isHovering ? Tokens.Slider.knobHoverScale : 1)
                .offset(x: knob - Tokens.Slider.knob / 2)
        }
        .frame(height: Tokens.Slider.bandHeight)
        .animation(motion, value: shownIndex)
        .animation(motion, value: isHovering)
        .overlay {
            SliderInteraction(
                onPointer: { x in
                    pointer = x.map { Self.fraction(forX: $0, width: width) }
                    isHovering = x != nil
                },
                onScroll: { steps in
                    // A scroll takes the knob off the pointer: it is now the one being aimed.
                    index = min(max(shownIndex + steps, 0), TimerLadder.slots.count - 1)
                    pointer = nil
                },
                onCommit: { onPick(shownSeconds) }
            )
        }
    }

    private func marker(at fraction: Double, width: CGFloat, color: Color) -> some View {
        Capsule()
            .fill(color)
            .frame(width: Tokens.Slider.markerWidth, height: Tokens.Slider.markerHeight)
            .offset(x: x(forFraction: fraction, width: width) - Tokens.Slider.markerWidth / 2)
    }

    private func scale(width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                Text(TimerLadder.label(TimerLadder.shortest))
                Spacer(minLength: 0)
                Text(TimerLadder.label(TimerLadder.longest))
            }
            Text(TimerLadder.label(3600))
                .position(x: x(forFraction: TimerLadder.fraction(ofIndex: TimerLadder.index(nearest: 3600)),
                               width: width),
                          y: Tokens.Slider.scaleHeight / 2)
        }
        .font(Tokens.Typography.keyboardHint)
        .foregroundStyle(Tokens.Palette.textTertiary.color)
        .frame(height: Tokens.Slider.scaleHeight)
    }
}

// MARK: - Pointer and wheel

/// Pointer tracking, scroll wheel and click for the slider, in one AppKit view.
///
/// SwiftUI on macOS 15 has no scroll-wheel event, and its gestures cannot tell a hover from a
/// drag — both of which this control is built on. Positions are reported as a fraction of the
/// view's width so the SwiftUI side owns every pixel of the drawing.
struct SliderInteraction: NSViewRepresentable {
    /// The pointer's x inside the track, or nil when it leaves.
    var onPointer: (CGFloat?) -> Void
    var onScroll: (Int) -> Void
    var onCommit: () -> Void

    func makeNSView(context: Context) -> TrackingView { TrackingView() }

    func updateNSView(_ view: TrackingView, context: Context) {
        view.onPointer = onPointer
        view.onScroll = onScroll
        view.onCommit = onCommit
    }

    final class TrackingView: NSView {
        var onPointer: ((CGFloat?) -> Void)?
        var onScroll: ((Int) -> Void)?
        var onCommit: (() -> Void)?

        private var isDragging = false
        private var wheelTravel: CGFloat = 0
        /// Trackpad deltas arrive in points; this many of them is one slot.
        private let travelPerStep: CGFloat = 6

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                owner: self))
        }

        private func pointerX(_ event: NSEvent) -> CGFloat {
            convert(event.locationInWindow, from: nil).x
        }

        override func mouseEntered(with event: NSEvent) { onPointer?(pointerX(event)) }
        override func mouseMoved(with event: NSEvent) { onPointer?(pointerX(event)) }
        override func mouseDragged(with event: NSEvent) { onPointer?(pointerX(event)) }

        override func mouseExited(with event: NSEvent) {
            // A drag that wanders off the track is still a drag.
            guard !isDragging else { return }
            onPointer?(nil)
        }

        override func mouseDown(with event: NSEvent) {
            isDragging = true
            onPointer?(pointerX(event))
        }

        override func mouseUp(with event: NSEvent) {
            isDragging = false
            onCommit?()
        }

        override func scrollWheel(with event: NSEvent) {
            // Vertical wins when both axes move. Up is longer; so is a swipe to the right,
            // which arrives as a negative horizontal delta.
            let vertical = event.scrollingDeltaY
            let horizontal = -event.scrollingDeltaX
            let delta = abs(vertical) >= abs(horizontal) ? vertical : horizontal
            guard delta != 0 else { return }

            guard event.hasPreciseScrollingDeltas else {
                onScroll?(delta > 0 ? 1 : -1)
                return
            }
            wheelTravel += delta
            while abs(wheelTravel) >= travelPerStep {
                let step: CGFloat = wheelTravel > 0 ? 1 : -1
                onScroll?(Int(step))
                wheelTravel -= step * travelPerStep
            }
        }
    }
}
