import AppKit
import SwiftUI
import HypertimeCore

/// The timer picker (T-10): one sweep from a minute to eight hours over `TimerLadder`'s slots,
/// so the first hour — where nearly every timer lands — gets two thirds of the travel.
///
/// The knob moves when you ask it to and never otherwise: press the track and it goes there,
/// drag it, or roll the wheel over it a slot at a time. Hovering changes nothing. Letting go
/// sets the timer, so what the readout says when you release is what you get.
struct TimerSlider: View {
    /// The timer already on the task, marked on the track so it can be found again.
    var current: Seconds?
    var onPick: (Seconds) -> Void

    @State private var index: Int
    @State private var grabOffset: CGFloat = 0
    @State private var isHovering = false
    @State private var isDragging = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// With nothing set yet the slider opens on the length people actually reach for.
    private static let opening: Seconds = 1500

    init(current: Seconds?, onPick: @escaping (Seconds) -> Void) {
        self.current = current
        self.onPick = onPick
        _index = State(initialValue: TimerLadder.index(nearest: current ?? Self.opening))
    }

    private var shownSeconds: Seconds { TimerLadder.seconds(at: index) }

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
            Text("scroll or drag to adjust · click to set")
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

    // MARK: - Geometry

    /// Knob centres are inset by its radius, so neither end of the sweep is clipped.
    private func knobX(width: CGFloat) -> CGFloat {
        x(forFraction: TimerLadder.fraction(ofIndex: index), width: width)
    }

    private func x(forFraction fraction: Double, width: CGFloat) -> CGFloat {
        Self.radius + CGFloat(fraction) * Self.span(width)
    }

    /// The inverse: a position on the track, in the same inset space the knob is drawn in, so
    /// pressing the track puts the knob exactly where the cursor is at every point of the sweep.
    static func fraction(forX x: CGFloat, width: CGFloat) -> Double {
        min(max(Double((x - radius) / span(width)), 0), 1)
    }

    /// Whether a press landed on the knob rather than on bare track. A press on the knob
    /// keeps its value: a knob is wider than a slot, so re-reading the value from the cursor
    /// would quietly shift it by a slot or two on the way out.
    static func isOnKnob(pressX: CGFloat, knobX: CGFloat) -> Bool {
        abs(pressX - knobX) <= Tokens.Slider.knob / 2
    }

    private static let radius = Tokens.Slider.knob / 2
    private static func span(_ width: CGFloat) -> CGFloat { max(width - 2 * radius, 1) }

    private func move(to x: CGFloat, width: CGFloat) {
        index = TimerLadder.index(atFraction: Self.fraction(forX: x + grabOffset, width: width))
    }

    // MARK: - Track

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
                .scaleEffect(isHovering || isDragging ? Tokens.Slider.knobHoverScale : 1)
                .offset(x: knob - Tokens.Slider.knob / 2)
        }
        .frame(height: Tokens.Slider.bandHeight)
        // A dragged knob tracks the cursor with no easing; everything else glides.
        .animation(isDragging ? nil : motion, value: index)
        .animation(motion, value: isHovering)
        .overlay {
            SliderInteraction(
                onHover: { isHovering = $0 },
                onPress: { x, keepsValue in
                    isDragging = true
                    let knob = knobX(width: width)
                    if keepsValue || Self.isOnKnob(pressX: x, knobX: knob) {
                        // Hold the length that is already chosen and let a drag move it from
                        // there, rather than throwing it away for whatever is under the cursor.
                        grabOffset = knob - x
                    } else {
                        grabOffset = 0
                        move(to: x, width: width)
                    }
                },
                onDrag: { x in move(to: x, width: width) },
                onRelease: {
                    isDragging = false
                    onPick(shownSeconds)
                },
                onScroll: { steps in
                    index = min(max(index + steps, 0), TimerLadder.slots.count - 1)
                }
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

/// Press, drag, release, wheel and hover for the slider, in one AppKit view.
///
/// SwiftUI on macOS 15 has no scroll-wheel event, and a `DragGesture` cannot report a press
/// before the finger has travelled — both of which this control is built on. Positions arrive
/// as points inside the view so the SwiftUI side owns every pixel of the drawing.
struct SliderInteraction: NSViewRepresentable {
    var onHover: (Bool) -> Void
    /// The press position, and whether it should keep the length already chosen — true for a
    /// click that follows a scroll with no mouse movement in between.
    var onPress: (CGFloat, Bool) -> Void
    var onDrag: (CGFloat) -> Void
    var onRelease: () -> Void
    var onScroll: (Int) -> Void

    func makeNSView(context: Context) -> TrackingView { TrackingView() }

    func updateNSView(_ view: TrackingView, context: Context) {
        view.onHover = onHover
        view.onPress = onPress
        view.onDrag = onDrag
        view.onRelease = onRelease
        view.onScroll = onScroll
    }

    final class TrackingView: NSView {
        var onHover: ((Bool) -> Void)?
        var onPress: ((CGFloat, Bool) -> Void)?
        var onDrag: ((CGFloat) -> Void)?
        var onRelease: (() -> Void)?
        var onScroll: ((Int) -> Void)?

        private var isDragging = false
        /// Set by the wheel and cleared by the first real mouse movement: a click straight
        /// after a scroll means "that one", while moving the cursor first means "that spot".
        private var keepsValue = false
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

        /// Hovering is a cursor state, nothing more: the knob stays where it was put. The
        /// only thing movement does is retire a scroll's claim on the next click.
        override func mouseEntered(with event: NSEvent) { onHover?(true) }

        override func mouseMoved(with event: NSEvent) { keepsValue = false }

        override func mouseExited(with event: NSEvent) {
            // A drag that wanders off the track is still a drag.
            guard !isDragging else { return }
            onHover?(false)
        }

        override func mouseDown(with event: NSEvent) {
            isDragging = true
            onPress?(pointerX(event), keepsValue)
            keepsValue = false
        }

        override func mouseDragged(with event: NSEvent) {
            guard isDragging else { return }
            onDrag?(pointerX(event))
        }

        override func mouseUp(with event: NSEvent) {
            isDragging = false
            onRelease?()
        }

        override func scrollWheel(with event: NSEvent) {
            // Vertical wins when both axes move. Up is longer; so is a swipe to the right,
            // which arrives as a negative horizontal delta.
            let vertical = event.scrollingDeltaY
            let horizontal = -event.scrollingDeltaX
            let delta = abs(vertical) >= abs(horizontal) ? vertical : horizontal
            guard delta != 0 else { return }

            keepsValue = true
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
