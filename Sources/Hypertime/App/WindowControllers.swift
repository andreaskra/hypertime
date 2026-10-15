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
    private(set) var window: NSWindow?
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
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: Tokens.Size.reportsDefault),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                  backing: .buffered,
                                  defer: false)
            window.title = "Hypertime Reports"
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.backgroundColor = .clear
            window.contentView = NSHostingView(rootView: root)
            window.center()
            // A frame saved before the toolbar grew must not keep the window too small for it.
            window.contentMinSize = Tokens.Size.reportsMinimum
            window.setFrameAutosaveName("HypertimeReports")
            if window.frame.width < Tokens.Size.reportsDefault.width {
                window.setContentSize(Tokens.Size.reportsDefault)
                window.center()
            }
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
    private(set) var window: NSWindow?

    init(model: AppModel, activation: ActivationController) {
        self.model = model
        self.activation = activation
        viewModel = SettingsViewModel(model: model)
    }

    func show() {
        if window == nil {
            // A plain titled window (artboard A-settings). It previously drew its content
            // through the titlebar with `fullSizeContentView` and a clear background, which put
            // the form over the traffic lights and left nothing to close the window with.
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: Tokens.Size.settingsWidth, height: 560),
                                  styleMask: [.titled, .closable, .miniaturizable],
                                  backing: .buffered,
                                  defer: false)
            window.title = "Settings"
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
    /// The window the sheet attaches to, when one is open.
    var hostWindowProvider: (() -> NSWindow?)?

    init(model: AppModel, activation: ActivationController) {
        self.model = model
        self.activation = activation
    }

    /// `scope` nil opens the sheet on the custom-range tab.
    func show(period: Period?) {
        let viewModel = ExportViewModel(model: model, initialPeriod: period)
        if period == nil { viewModel.scopeKind = .range }
        self.viewModel = viewModel

        let hosting = NSHostingView(rootView: ExportView(
            viewModel: viewModel,
            onExport: { [weak self] in self?.runSavePanel() },
            onCancel: { [weak self] in self?.close() }
        ))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
                              styleMask: [.titled, .closable, .fullSizeContentView],
                              backing: .buffered,
                              defer: false)
        window.title = "Export CSV"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.contentView = hosting
        self.window = window

        // Presented as a sheet on Reports when it is open, otherwise as its own window.
        if let host = hostWindowProvider?(), host.isVisible {
            activation.activate { host.beginSheet(window) { _ in } }
        } else {
            window.center()
            activation.activate { window.makeKeyAndOrderFront(nil) }
        }
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
        if let window, let host = window.sheetParent {
            host.endSheet(window)
        } else {
            window?.close()
        }
        window = nil
        viewModel = nil
    }
}
