import AppKit
import SwiftUI
import HypertimeCore

/// The last 24 hours as 144 ten-minute marks, each coloured by what the app was doing in it
/// (TL-01 … TL-06). Hovering magnifies the mark under the cursor the way the Dock magnifies
/// its icons, and the caption reads what it is.
///
/// One rule separates this from the Dock: **marks never move.** Every centre stays pinned to
/// its time and magnified neighbours overlap instead of pushing each other along. The Dock
/// displaces its icons, which is fine for icons and wrong for a time axis — a strip that
/// slides under the cursor is lying about when things happened, and this exists to be trusted
/// about exactly that.
struct TimelineStrip: View {
    @Bindable var viewModel: CheckInViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var hoveredIndex: Int? {
        guard let start = viewModel.hoveredBucket else { return nil }
        return viewModel.timeline.firstIndex { $0.start == start }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Strip.captionGap) {
            GeometryReader { geo in
                marks(width: geo.size.width)
                    .overlay {
                        StripPointer(
                            onHover: { x in
                                guard let x else { viewModel.hoveredBucket = nil; return }
                                viewModel.hoveredBucket = bucket(atX: x, width: geo.size.width)?.start
                            })
                    }
            }
            .frame(height: Tokens.Strip.height)

            Text(viewModel.timelineCaption)
                .font(Tokens.Typography.keyboardHint)
                .foregroundStyle(viewModel.hoveredBucket == nil
                                 ? Tokens.Palette.textTertiary.color
                                 : Tokens.Palette.textSecondary.color)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(nil, value: viewModel.timelineCaption)
        }
    }

    // MARK: - Geometry

    private var count: Int { max(viewModel.timeline.count, 1) }

    /// Half the widest a mark ever gets, so a bulge at either end has somewhere to go instead
    /// of being clipped by the strip's own edge. The inset is uniform, so the axis stays
    /// linear — it is a day across slightly less than the full width, not a distorted day.
    private static var inset: CGFloat { Tokens.Strip.markWidth * Tokens.Strip.widthGain / 2 }

    private func pitch(_ width: CGFloat) -> CGFloat {
        max(width - 2 * Self.inset, 1) / CGFloat(count)
    }

    private func centre(of index: Int, width: CGFloat) -> CGFloat {
        Self.inset + pitch(width) * (CGFloat(index) + 0.5)
    }

    /// Nearest mark, not the one strictly under the pointer: at a 2.4 pt pitch nobody can aim
    /// at a bracket on purpose, which is exactly what the magnification is there to excuse.
    private func bucket(atX x: CGFloat, width: CGFloat) -> TimelineBucket? {
        let index = Int(((x - Self.inset) / pitch(width)).rounded(.down))
        guard viewModel.timeline.indices.contains(index) else { return nil }
        return viewModel.timeline[index]
    }

    /// Dock falloff: full size under the cursor, tapering to nothing a bucket-radius away.
    private func magnification(_ index: Int, hovered: Int?) -> CGFloat {
        guard !reduceMotion, let hovered else { return 0 }
        let distance = abs(index - hovered)
        guard distance <= Tokens.Strip.magnifyRadius else { return 0 }
        let t = 1 - CGFloat(distance) / CGFloat(Tokens.Strip.magnifyRadius + 1)
        return t * t * (3 - 2 * t)                      // smoothstep, so the bulge has no corner
    }

    // MARK: - Marks

    /// One `Canvas` rather than 144 views. A `ForEach` over the brackets cost most of a second
    /// of launch on its own — the popup's view tree is built eagerly, and a day of marks is a
    /// lot of views for something that is, in the end, a row of coloured rectangles.
    private func marks(width: CGFloat) -> some View {
        let buckets = viewModel.timeline
        let hovered = hoveredIndex
        let track = Tokens.Palette.buttonSecondary.color
        let idleInk = Tokens.Palette.textSecondary.color
        let pausedInk = Tokens.Palette.textTertiary.color
        let tickInk = Tokens.Palette.separator.color
        let fills = buckets.map { fill($0.dominant) }
        let kinds = buckets.map { $0.dominant?.kind }
        let idling = buckets.map(\.hasIdle)
        let ticks = hourMarks()

        return Canvas { context, size in
            let height = size.height
            let trackRect = CGRect(x: 0, y: (height - Tokens.Strip.trackHeight) / 2,
                                   width: size.width, height: Tokens.Strip.trackHeight)
            context.fill(Path(roundedRect: trackRect, cornerRadius: Tokens.Strip.trackHeight / 2),
                         with: .color(track))

            for tick in ticks {
                let tall = tick.isDayBoundary ? Tokens.Strip.tickTall : Tokens.Strip.tick
                let x = centre(of: tick.index, width: size.width)
                context.fill(Path(CGRect(x: x - Tokens.Focus.hairlineWidth(false) / 2,
                                         y: height - tall, width: Tokens.Focus.hairlineWidth(false),
                                         height: tall)),
                             with: .color(tickInk))
            }

            for index in buckets.indices where kinds[index] != nil {
                let lift = magnification(index, hovered: hovered)
                let markHeight = Tokens.Strip.markHeight
                    + (Tokens.Strip.height - Tokens.Strip.markHeight) * lift
                let markWidth = Tokens.Strip.markWidth * (1 + (Tokens.Strip.widthGain - 1) * lift)
                let x = centre(of: index, width: size.width)
                let rect = CGRect(x: x - markWidth / 2, y: (height - markHeight) / 2,
                                  width: markWidth, height: markHeight)
                let path = Path(roundedRect: rect, cornerRadius: markWidth / 2)
                switch kinds[index] {
                case .idle:
                    // Present but empty: the app noticed, and booked nothing.
                    context.stroke(path, with: .color(idleInk), lineWidth: Tokens.Focus.borderWidth)
                case .paused:
                    context.fill(path, with: .color(pausedInk))
                default:
                    context.fill(path, with: .color(fills[index]))
                    // Half an hour is wide enough to hide a ten-minute idle stretch behind the
                    // work either side of it. Outlined means "there is idle in here".
                    if idling[index] {
                        context.stroke(path, with: .color(idleInk), lineWidth: Tokens.Focus.borderWidth)
                    }
                }
            }

            // Only where there is no mark to magnify: over a bracket that holds something the
            // bulge is the feedback, and a ring on top of it is another thing to look at.
            if let hovered, buckets.indices.contains(hovered), buckets[hovered].isEmpty {
                let w = Tokens.Strip.markWidth * Tokens.Strip.widthGain
                let rect = CGRect(x: centre(of: hovered, width: size.width) - w / 2,
                                  y: (height - Tokens.Strip.markHeight) / 2,
                                  width: w, height: Tokens.Strip.markHeight)
                context.stroke(Path(roundedRect: rect, cornerRadius: w / 2),
                               with: .color(pausedInk), lineWidth: Tokens.Focus.borderWidth)
            }
        }
        .frame(height: Tokens.Strip.height)
    }

    private func fill(_ part: Slice?) -> Color {
        guard let part, part.kind == .tracked else { return .clear }
        guard let id = part.projectID else { return Tokens.Series.other.color }
        return Tokens.Series.color(slot: viewModel.colorSlot(for: id))
    }

    private struct HourTick { let index: Int; let isDayBoundary: Bool }

    private func hourMarks() -> [HourTick] {
        var calendar = Calendar.autoupdatingCurrent
        calendar.timeZone = .autoupdatingCurrent
        return viewModel.timeline.enumerated().compactMap { index, bucket in
            let parts = calendar.dateComponents([.hour, .minute], from: bucket.start)
            guard parts.minute == 0 else { return nil }
            guard (parts.hour ?? 0) % Tokens.Strip.tickEveryHours == 0 else { return nil }
            return HourTick(index: index, isDayBoundary: parts.hour == 0)
        }
    }
}

// MARK: - Pointer

/// Pointer tracking for the strip. SwiftUI's `onContinuousHover` reports coordinates but stops
/// at the view's own bounds, and the strip's marks are narrower than the gaps between them —
/// it is the whole band that has to be live, not the marks.
private struct StripPointer: NSViewRepresentable {
    var onHover: (CGFloat?) -> Void

    func makeNSView(context: Context) -> TrackingView { TrackingView() }

    func updateNSView(_ view: TrackingView, context: Context) { view.onHover = onHover }

    final class TrackingView: NSView {
        var onHover: ((CGFloat?) -> Void)?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                owner: self))
        }

        private func report(_ event: NSEvent) {
            onHover?(convert(event.locationInWindow, from: nil).x)
        }

        override func mouseEntered(with event: NSEvent) { report(event) }
        override func mouseMoved(with event: NSEvent) { report(event) }
        override func mouseExited(with event: NSEvent) { onHover?(nil) }
    }
}
