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
        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
            header

            ProjectField(viewModel: viewModel)
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("panel")).maxY } action: {
                    presentation.reportFieldBottom($0)
                }
                .overlay(alignment: .topLeading) {
                    if viewModel.showsProjectList {
                        let list = ProjectList(viewModel: viewModel)
                        list
                            .frame(width: Self.width - 2 * Tokens.Space.s4)
                            .offset(y: Tokens.Size.fieldHeight + Tokens.Space.s1)
                            .transition(.opacity)
                            .onAppear { presentation.reportDropdownHeight(list.height) }
                            .onDisappear { presentation.reportDropdownHeight(0) }
                            .onChange(of: viewModel.matches.count) { presentation.reportDropdownHeight(list.height) }
                    }
                }
                .zIndex(2)

            AmountField(viewModel: viewModel, presentation: presentation)

            if !viewModel.todayRows.isEmpty || viewModel.isTracking {
                Hairline()
                TodayListView(viewModel: viewModel)
                    // The dropdown owns the keyboard while it is open; the list steps back.
                    .opacity(viewModel.showsProjectList ? 0.45 : 1)
                    .allowsHitTesting(!viewModel.showsProjectList)
            }

            buttons
        }
        .animation(Tokens.Motion.listOpen.animation(reduceMotion: reduceMotion), value: viewModel.showsProjectList)
        .padding(Tokens.Space.s4)
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
                viewModel.isPaused ? viewModel.resume() : viewModel.requestPause()
            } label: {
                Image(systemName: viewModel.isPaused ? Tokens.Icons.resume : Tokens.Icons.pause)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Tokens.Palette.textSecondary.color)
                    .frame(width: Tokens.Size.iconButton, height: Tokens.Size.iconButton)
                    .background {
                        RoundedRectangle(cornerRadius: Tokens.Radius.cell, style: .continuous)
                            .fill(Tokens.Palette.rowHover.color)
                    }
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.isTracking && !viewModel.isPaused)
            .opacity(viewModel.isTracking || viewModel.isPaused ? 1 : 0.4)
            .help(viewModel.isPaused ? "Resume tracking" : "Pause tracking")
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
