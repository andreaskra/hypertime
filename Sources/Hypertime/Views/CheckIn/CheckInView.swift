import AppKit
import SwiftUI
import HypertimeCore

/// The check-in popup (R-02). Phase 1: functional, deliberately unstyled.
struct CheckInView: View {
    @Bindable var viewModel: CheckInViewModel

    static let width: CGFloat = 360

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            ProjectField(viewModel: viewModel)
                .overlay(alignment: .topLeading) {
                    if viewModel.showsProjectList {
                        ProjectList(viewModel: viewModel)
                            .frame(width: Self.width - 24)
                            .offset(y: 26)
                    }
                }
                .zIndex(2)

            HStack {
                Text("Add")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                TimeField(viewModel: viewModel)
            }

            Divider()

            TodayListView(viewModel: viewModel)

            Divider()

            buttons
        }
        .padding(12)
        .frame(width: Self.width)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: statusSymbol)
                .foregroundStyle(viewModel.isTracking ? Color.accentColor : .secondary)
            Text(viewModel.statusLine)
                .font(.callout.monospacedDigit())
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private var statusSymbol: String {
        if viewModel.isPaused { return "pause.circle" }
        return viewModel.isTracking ? "record.circle" : "circle.dashed"
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            if viewModel.isPaused {
                Button("Resume") { viewModel.resume() }
            } else {
                Button("Pause…") { viewModel.requestPause() }
            }
            Spacer()
            Button("Discard") { viewModel.discard() }
                .keyboardShortcut(.delete, modifiers: .command)
                .help("Throw away the unattributed time (⌘⌫)")
            Button("Close") { viewModel.close() }
                .keyboardShortcut(.cancelAction)
            Button("Confirm") { viewModel.commit() }
                .keyboardShortcut(.defaultAction)
        }
    }
}
