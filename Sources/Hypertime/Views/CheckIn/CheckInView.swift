import AppKit
import SwiftUI
import HypertimeCore

/// The check-in popup (R-02), built from the Phase 2 handoff: 380 pt wide, r18 glass, growing
/// downward from the menu bar anchor. Anatomy: header · project combobox · amount · today list ·
/// buttons.
struct CheckInView: View {
    @Bindable var viewModel: CheckInViewModel
    @Bindable var presentation: PanelPresentation

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    static let width: CGFloat = Tokens.Size.popupWidth

    private var material: Tokens.MaterialStyle {
        presentation.mode == .passive ? Tokens.Materials.panelPassive : Tokens.Materials.panel
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                header

                ProjectField(viewModel: viewModel)
                    // The dropdown hangs off the field it filters, one gap below it, so the two
                    // read as a single combobox. It covers whatever is beneath — the amount is
                    // back the moment the list closes.
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("panel")).maxY } action: {
                        presentation.reportListTop($0 + Tokens.Space.s1)
                    }

                AmountField(viewModel: viewModel, presentation: presentation)

                if hasTodayList {
                    VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                        Hairline()
                        TodayListView(viewModel: viewModel)
                            // The dropdown owns the keyboard while it is open; the list steps back.
                            .opacity(viewModel.showsProjectList ? 0.45 : 1)
                            .allowsHitTesting(!viewModel.showsProjectList)
                    }
                }

                buttons
                    // Short panel, long list: push the actions clear instead of letting the
                    // dropdown bury them. The panel grows with them (it only ever grows down).
                    .padding(.top, dropdownClearance)
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("panel")).minY } action: { top in
                        if !viewModel.showsProjectList { presentation.reportButtonsTop(top) }
                    }
            }
            .padding(Tokens.Space.s4)

            if viewModel.showsProjectList {
                ProjectList(viewModel: viewModel)
                    .frame(width: Self.width - 2 * Tokens.Space.s4)
                    .offset(x: Tokens.Space.s4, y: presentation.listTop)
                    .transition(.opacity)
                    .onAppear { presentation.reportDropdownHeight(dropdownHeight) }
                    .onDisappear { presentation.reportDropdownHeight(0) }
                    .onChange(of: viewModel.matches.count) { presentation.reportDropdownHeight(dropdownHeight) }
                    .zIndex(2)
            }
        }
        .animation(Tokens.Motion.listOpen.animation(reduceMotion: reduceMotion), value: viewModel.showsProjectList)
        .frame(width: Self.width)
        .coordinateSpace(.named("panel"))
        .background { GlassBackground(style: material, cornerRadius: Tokens.Radius.panel) }
        .overlay(alignment: .topLeading) { drain }
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.panel, style: .continuous))
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { presentation.reportContentHeight($0) }
        .opacity(presentation.isAppeared ? 1 : 0)
        .scaleEffect(scaleWhileHidden, anchor: .top)
        .offset(y: presentation.isAppeared ? 0 : -6)
    }

    private var hasTodayList: Bool { !viewModel.todayRows.isEmpty || viewModel.isTracking }

    private var dropdownHeight: CGFloat { ProjectList.height(rows: viewModel.matches.count) }

    /// How far the buttons have to move so an open dropdown does not cover them. Zero whenever
    /// the content below the field is already taller than the list, which is the usual case.
    private var dropdownClearance: CGFloat {
        guard viewModel.showsProjectList, presentation.buttonsTop > 0 else { return 0 }
        let dropdownBottom = presentation.listTop + dropdownHeight + Tokens.Space.s3
        return max(0, dropdownBottom - presentation.buttonsTop)
    }

    /// Focused popups scale in from 0.98; passive ones only fade and slide.
    private var scaleWhileHidden: CGFloat {
        guard !presentation.isAppeared, presentation.mode == .focused, !reduceMotion else { return 1 }
        return 0.98
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Tokens.Space.s2) {
            Text("What are you working on?")
                .font(Tokens.Typography.heading)
                .foregroundStyle(Tokens.Palette.textSecondary.color)

            Spacer(minLength: Tokens.Space.s2)

            HStack(spacing: Tokens.Space.s1) {
                indicator
                Text(stateLine)
                    .font(Tokens.Typography.heading)
                    .foregroundStyle(Tokens.Palette.textSecondary.color)
                    .lineLimit(1)
            }

            Button {
                viewModel.toggleTracking()
            } label: {
                // Play whenever time is not running — paused or idle. Idle is where the popup
                // starts after a launch, and it needs a way to begin tracking.
                Image(systemName: viewModel.isTracking ? Tokens.Icons.pause : Tokens.Icons.resume)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Tokens.Palette.textSecondary.color)
                    .frame(width: Tokens.Size.iconButton, height: Tokens.Size.iconButton)
                    .background {
                        RoundedRectangle(cornerRadius: Tokens.Radius.cell, style: .continuous)
                            .fill(Tokens.Palette.rowHover.color)
                    }
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canToggleTracking)
            .opacity(viewModel.canToggleTracking ? 1 : 0.4)
            .help(viewModel.trackingToggleHelp)
        }
        .frame(height: Tokens.Size.headerHeight)
    }

    @ViewBuilder
    private var indicator: some View {
        if viewModel.isPaused {
            // Paused reads as an amber square, so it is distinguishable without colour alone.
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(Tokens.Palette.pausedIndicator.color)
                .frame(width: Tokens.Size.indicatorDot, height: Tokens.Size.indicatorDot)
        } else {
            Circle()
                .fill(viewModel.isTracking ? Tokens.Palette.trackingIndicator.color : Tokens.Palette.idleIndicator.color)
                .frame(width: Tokens.Size.indicatorDot, height: Tokens.Size.indicatorDot)
        }
    }

    private var stateLine: String {
        if viewModel.isPaused { return viewModel.statusLine }
        guard viewModel.isTracking else { return "Not tracking" }
        return "Tracking · " + (viewModel.currentProjectName ?? "—")
    }

    // MARK: - Buttons

    private var buttons: some View {
        HStack(spacing: Tokens.Space.s2) {
            Button { viewModel.discard() } label: {
                HStack(spacing: Tokens.Space.s1) {
                    Text("Discard")
                    KeyboardHint(text: "⌘⌫")
                }
            }
            .hypertimeButton(.destructiveGhost)
            .disabled(viewModel.pendingSeconds == 0)
            .help("Throw away the time accumulated since the last check-in")

            Spacer(minLength: 0)

            Button { viewModel.close() } label: {
                HStack(spacing: Tokens.Space.s1) {
                    Text("Close")
                    KeyboardHint(text: "esc")
                }
            }
            .hypertimeButton(.secondary)

            Button { viewModel.commit() } label: {
                HStack(spacing: Tokens.Space.s1) {
                    Text("Confirm")
                    KeyboardHint(text: "↩")
                }
            }
            .hypertimeButton(.primary, isFocused: viewModel.focus == .confirm)
        }
        .frame(height: Tokens.Size.buttonHeight)
    }

    // MARK: - Auto-hide drain (D-14)

    @ViewBuilder
    private var drain: some View {
        if presentation.isDraining {
            GeometryReader { proxy in
                Rectangle()
                    .fill(Tokens.Palette.autoHideDrain.color)
                    .frame(width: reduceMotion ? proxy.size.width : proxy.size.width * presentation.drainProgress,
                           height: Tokens.Size.autoHideDrainHeight)
            }
            .frame(height: Tokens.Size.autoHideDrainHeight)
            .allowsHitTesting(false)
        }
    }
}
