import AppKit
import HypertimeCore

/// Small AppKit prompts for the destructive/naming project actions in Reports (§6.10).
@MainActor
enum RenamePrompt {
    static func show(project: Project, viewModel: ReportsViewModel) {
        let alert = NSAlert()
        alert.messageText = "Rename project"
        alert.informativeText = "Choose a new name for “\(project.name)”."
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(string: project.name)
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        if alert.runModal() == .alertFirstButtonReturn {
            viewModel.rename(project, to: field.stringValue)
        }
    }
}

@MainActor
enum DeletePrompt {
    static func show(project: Project, viewModel: ReportsViewModel) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete “\(project.name)”?"
        alert.informativeText = "All tracked time for this project is deleted. This cannot be undone."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            viewModel.delete(project)
        }
    }
}
