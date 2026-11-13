import SwiftUI
import HypertimeCore

/// Stacked bars of tracked time, with the legend doubling as the project filter.
///
/// Colours are the validated categorical palette in `Tokens.Series`, assigned in fixed order
/// from the unfiltered ranking — unticking a project never repaints the ones that remain, and a
/// ninth project folds into "Other" rather than repeating a hue. Three light-mode slots sit
/// under 3:1 on the surface, so the relief rule applies: the legend labels every series and the
/// table view carries the same numbers.
struct ActivityChartView: View {
    @Bindable var viewModel: ReportsViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let barMaxHeight: CGFloat = 220
    private let legendColumns = [GridItem(.adaptive(minimum: 150), spacing: Tokens.Space.s2)]

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s4) {
            if viewModel.chartBuckets.isEmpty {
                empty
            } else {
                plot
            }
            Hairline()
            legend
        }
        .padding(Tokens.Space.s4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(Tokens.Motion.listOpen.animation(reduceMotion: reduceMotion),
                   value: viewModel.hiddenProjects)
    }

    private var empty: some View {
        Text("Nothing tracked in this period.")
            .font(Tokens.Typography.body)
            .foregroundStyle(Tokens.Palette.textTertiary.color)
            .frame(maxWidth: .infinity, minHeight: barMaxHeight)
    }

    // MARK: - Plot

    /// The plot is a window onto a continuous axis rather than a fixed period: two fingers
    /// pan it and a pinch zooms it. One extra bar is drawn past each edge and the whole row is
    /// translated by the sub-day remainder, so scrolling slides rather than snapping a day at
    /// a time — at a week's width, a day is a seventh of the screen.
    private var plot: some View {
        let maximum = viewModel.chartMaximum
        return HStack(alignment: .bottom, spacing: Tokens.Space.s1) {
            axis(maximum: maximum)
            GeometryReader { geo in
                let width = max(geo.size.width, 1)
                let dayWidth = width / CGFloat(max(viewModel.visibleDays, 1))
                HStack(alignment: .bottom, spacing: barSpacing(dayWidth)) {
                    ForEach(viewModel.chartBuckets) { bucket in
                        bar(bucket, maximum: maximum, width: barWidth(dayWidth))
                    }
                }
                .frame(width: width, alignment: .trailing)
                .offset(x: CGFloat(viewModel.subDayOffset) * dayWidth)
                .clipped()
                .overlay {
                    ChartScroller(
                        onScroll: { points in
                            viewModel.pan(byDays: Double(points / dayWidth))
                        },
                        onZoom: { factor, focus in
                            viewModel.zoom(by: factor, focus: focus)
                        },
                        onHover: { _ in })
                }
            }
            .frame(height: barMaxHeight + 22)
        }
        .frame(height: barMaxHeight + 22)
    }

    /// Two recessive gridline labels — the peak and the midpoint — rather than a full axis.
    private func axis(maximum: Seconds) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(viewModel.text(maximum))
            Spacer()
            Text(viewModel.text(maximum / 2))
            Spacer()
            Text("")
        }
        .font(Tokens.Typography.keyboardHint)
        .foregroundStyle(Tokens.Palette.textTertiary.color)
        .frame(height: barMaxHeight)
        .padding(.bottom, 22)
    }

    /// Bars keep the 2 pt surface gap the palette's separation depends on, and never less.
    private func barSpacing(_ dayWidth: CGFloat) -> CGFloat {
        min(max(dayWidth * 0.18, Tokens.Series.gap), Tokens.Space.s2)
    }

    private func barWidth(_ dayWidth: CGFloat) -> CGFloat {
        let perBucket: CGFloat
        switch viewModel.grain {
        case .project: perBucket = 54
        case .day: perBucket = dayWidth
        case .week: perBucket = dayWidth * 7
        case .month: perBucket = dayWidth * 30
        }
        return max(perBucket - barSpacing(dayWidth), 2)
    }

    private func bar(_ bucket: ChartBucket, maximum: Seconds, width barWidth: CGFloat) -> some View {
        VStack(spacing: Tokens.Space.s1) {
            Spacer(minLength: 0)
            VStack(spacing: Tokens.Series.gap) {
                ForEach(bucket.segments) { segment in
                    Rectangle()
                        .fill(Tokens.Series.color(slot: segment.slot))
                        .frame(width: barWidth,
                               height: height(segment.seconds, maximum: maximum))
                        .onTapGesture { viewModel.isolate(segment.id) }
                        .help("\(segment.name) · \(viewModel.text(segment.seconds))")
                }
            }
            // Rounded data-end on the stack, square at the baseline.
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: Tokens.Series.barCorner,
                                              topTrailingRadius: Tokens.Series.barCorner,
                                              style: .continuous))
            .frame(minHeight: 1)

            Text(bucket.label)
                .font(Tokens.Typography.keyboardHint)
                .foregroundStyle(isToday(bucket)
                                 ? Tokens.Palette.accent
                                 : Tokens.Palette.textTertiary.color)
                .lineLimit(1)
                .frame(width: barWidth + 6)
        }
        .frame(height: barMaxHeight + 22, alignment: .bottom)
    }

    private func isToday(_ bucket: ChartBucket) -> Bool {
        bucket.day.map { viewModel.isToday($0) } ?? false
    }

    private func height(_ seconds: Seconds, maximum: Seconds) -> CGFloat {
        max(CGFloat(seconds) / CGFloat(maximum) * barMaxHeight, 2)
    }

    // MARK: - Legend and filter

    private var legend: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            HStack {
                Text("PROJECTS")
                    .font(Tokens.Typography.caption)
                    .tracking(0.5)
                    .foregroundStyle(Tokens.Palette.textTertiary.color)
                Spacer()
                Button("Select all") { viewModel.selectAll() }
                    .buttonStyle(.plain)
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(viewModel.hasHiddenProjects
                                     ? Tokens.Palette.accent
                                     : Tokens.Palette.textTertiary.color)
                    .disabled(!viewModel.hasHiddenProjects)
            }

            LazyVGrid(columns: legendColumns, alignment: .leading, spacing: Tokens.Space.s1) {
                ForEach(viewModel.legendRows) { row in
                    LegendRow(viewModel: viewModel, row: row)
                }
            }
        }
    }
}

private struct LegendRow: View {
    @Bindable var viewModel: ReportsViewModel
    let row: ReportRow

    private var isOn: Bool { viewModel.isVisible(row.project.id) }

    var body: some View {
        HStack(spacing: Tokens.Space.s2) {
            Button { viewModel.toggle(row.project.id) } label: {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size: 12))
                    .foregroundStyle(isOn
                                     ? Tokens.Series.color(slot: viewModel.slot(for: row.project.id))
                                     : Tokens.Palette.textTertiary.color)
            }
            .buttonStyle(.plain)
            .help(isOn ? "Hide \(row.project.name)" : "Show \(row.project.name)")

            Button { viewModel.isolate(row.project.id) } label: {
                HStack(spacing: Tokens.Space.s2) {
                    Text(row.project.name)
                        .font(Tokens.Typography.listRow)
                        .foregroundStyle(Tokens.Palette.textPrimary.color)
                        .lineLimit(1)
                    Spacer(minLength: Tokens.Space.s1)
                    Text(viewModel.text(row.seconds))
                        .font(Tokens.Typography.timeCell)
                        .foregroundStyle(Tokens.Palette.textSecondary.color)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Show only \(row.project.name)")
        }
        .opacity(isOn ? 1 : 0.45)
    }
}
