import SwiftUI
import HypertimeCore

/// How close the machine is to its limits, across the top of the popup: processor, memory and
/// disk on one 0–100 scale, where 100 is the point it stops coping.
///
/// Each figure is also a switch. Clicking one puts it in the menu bar, where it stays visible
/// with the popup closed; clicking it again takes it back out. The pill fills in when it is up
/// there, so the popup always says which of the three you are already watching.
struct SystemLoadBar: View {
    @Bindable var viewModel: CheckInViewModel

    var body: some View {
        HStack(spacing: Tokens.Space.s1) {
            ForEach(SystemMetric.allCases, id: \.self) { metric in
                MetricPill(metric: metric,
                           percent: viewModel.systemLoad.percent(metric),
                           fraction: viewModel.systemLoad[metric],
                           isInMenuBar: viewModel.isInMenuBar(metric)) {
                    viewModel.toggleMenuBarMetric(metric)
                }
            }
        }
    }
}

private struct MetricPill: View {
    let metric: SystemMetric
    let percent: Int
    let fraction: Double
    let isInMenuBar: Bool
    var action: () -> Void

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The one thing worth colouring: a figure close enough to the top to be the reason the
    /// machine is struggling.
    private var isStrained: Bool { fraction >= Tokens.Load.strainedAt }

    private var ink: Color {
        if isStrained { return Tokens.Palette.invalid.color }
        return isInMenuBar ? Tokens.Palette.accent : Tokens.Palette.textSecondary.color
    }

    private var help: String {
        (isInMenuBar ? "Hide " : "Show ") + metric.label.lowercased() + " in the menu bar"
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Tokens.Load.gauge.gap) {
                HStack(spacing: Tokens.Load.labelGap) {
                    Text(metric.label)
                        .font(Tokens.Typography.caption)
                        .tracking(0.5)
                        .foregroundStyle(isInMenuBar
                                         ? Tokens.Palette.accent
                                         : Tokens.Palette.textTertiary.color)
                    Spacer(minLength: 0)
                    Text("\(percent)%")
                        .font(Tokens.Typography.loadValue)
                        .foregroundStyle(ink)
                        .contentTransition(.numericText())
                }
                gauge
            }
            .padding(.horizontal, Tokens.Load.inset)
            .padding(.vertical, Tokens.Load.gauge.gap)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: Tokens.Radius.cell, style: .continuous)
                    .fill(isInMenuBar
                          ? Tokens.Palette.accent.opacity(Tokens.Load.pinnedTint)
                          : (isHovering ? Tokens.Palette.rowHover.color : .clear))
            }
            .contentShape(RoundedRectangle(cornerRadius: Tokens.Radius.cell, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { isHovering = $0 }
        .animation(Tokens.Motion.digitTick.animation(reduceMotion: reduceMotion), value: percent)
    }

    private var gauge: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Tokens.Palette.buttonSecondary.color)
                Capsule()
                    .fill(isStrained ? Tokens.Palette.invalid.color : ink)
                    .frame(width: max(geo.size.width * min(max(fraction, 0), 1),
                                      Tokens.Load.gauge.height))
            }
        }
        .frame(height: Tokens.Load.gauge.height)
    }
}
