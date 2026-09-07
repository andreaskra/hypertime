import AppKit
import SwiftUI
import HypertimeCore
import UniformTypeIdentifiers

/// Reports window (§6.10).
@MainActor
final class ReportsWindowController {
    private let model: AppModel
    private let activation: ActivationController
    let viewModel: ReportsViewModel
    private var window: NSWindow?
    var onExport: ((Period) -> Void)?

    init(model: AppModel, activation: ActivationController) {
        self.model = model
        self.activation = activation
        viewModel = ReportsViewModel(model: model)
    }

    func show() {
        viewModel.reload()
        if window == nil {
            let root = ReportsView(viewModel: viewModel) { [weak self] in
                guard let self else { return }
                self.onExport?(self.viewModel.period)
            }
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 480),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                  backing: .buffered,
                                  defer: false)
            window.title = "Hypertime Reports"
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: root)
            window.center()
            window.setFrameAutosaveName("HypertimeReports")
            self.window = window
        }
        activation.activate {
            window?.makeKeyAndOrderFront(nil)
        }
    }

    func refresh() {
        guard window?.isVisible == true else { return }
        viewModel.reload()
    }
}

/// Settings window (§6.12).
@MainActor
final class SettingsWindowController {
    private let model: AppModel
    private let activation: ActivationController
    let viewModel: SettingsViewModel
    private var window: NSWindow?

    init(model: AppModel, activation: ActivationController) {
        self.model = model
        self.activation = activation
        viewModel = SettingsViewModel(model: model)
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
                                  styleMask: [.titled, .closable, .fullSizeContentView],
                                  backing: .buffered,
                                  defer: false)
            window.title = "Hypertime Settings"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(viewModel: viewModel))
            window.center()
            self.window = window
        }
        activation.activate {
            window?.makeKeyAndOrderFront(nil)
        }
    }
}

/// Export options window plus the save panel (R-19, §6.11).
@MainActor
final class ExportController {
    private let model: AppModel
    private let activation: ActivationController
    private var window: NSWindow?
    private var viewModel: ExportViewModel?

    init(model: AppModel, activation: ActivationController) {
        self.model = model
        self.activation = activation
    }

    /// `scope` nil opens the sheet on the custom-range tab.
    func show(period: Period?) {
        let viewModel = ExportViewModel(model: model, initialPeriod: period)
        if period == nil { viewModel.scopeKind = .range }
        self.viewModel = viewModel

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 360),
                              styleMask: [.titled, .closable],
                              backing: .buffered,
                              defer: false)
        window.title = "Export CSV"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ExportView(
            viewModel: viewModel,
            onExport: { [weak self] in self?.runSavePanel() },
            onCancel: { [weak self] in self?.close() }
        ))
        window.center()
        self.window = window
        activation.activate { window.makeKeyAndOrderFront(nil) }
    }

    /// Direct export without the options sheet (status item shortcuts).
    func exportDirectly(scope: ExportScope) {
        let panel = savePanel(filename: CSVExporter.suggestedFilename(scope: scope))
        activation.activate {
            panel.begin { [weak self] response in
                MainActor.assumeIsolated {
                    guard response == .OK, let url = panel.url, let self else { return }
                    self.write(scope: scope, options: self.model.settings.csvOptions, to: url)
                }
            }
        }
    }

    private func runSavePanel() {
        guard let viewModel else { return }
        let panel = savePanel(filename: viewModel.suggestedFilename)
        let scope = viewModel.scope
        let options = viewModel.options
        panel.begin { [weak self] response in
            MainActor.assumeIsolated {
                guard response == .OK, let url = panel.url, let self else { return }
                self.write(scope: scope, options: options, to: url)
                self.close()
            }
        }
    }

    private func savePanel(filename: String) -> NSSavePanel {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = filename
        panel.allowedContentTypes = [UTType.commaSeparatedText]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        return panel
    }

    private func write(scope: ExportScope, options: CSVOptions, to url: URL) {
        do {
            let csv = try model.exporter.csv(scope: scope, options: options)
            try Data(csv.utf8).write(to: url, options: .atomic)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            viewModel?.message = error.localizedDescription
            Log.app.error("Export failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func close() {
        window?.close()
        window = nil
        viewModel = nil
    }
}
