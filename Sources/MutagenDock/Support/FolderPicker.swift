import AppKit

enum FolderPicker {
    /// Show a modal folder chooser and return the selected absolute path.
    @MainActor
    static func choose(initialPath: String? = nil) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Select a folder to synchronize"
        if let initialPath, !initialPath.isEmpty {
            let expanded = (initialPath as NSString).expandingTildeInPath
            panel.directoryURL = URL(fileURLWithPath: expanded)
        }
        NSApp.activate(ignoringOtherApps: true)
        // A MenuBarExtra window closes when it stops being key, and opening the
        // panel makes it resign key. Temporarily becoming a regular app keeps
        // the panel interaction feeling modal so the widget isn't lost.
        let previousPolicy = NSApp.activationPolicy()
        if previousPolicy != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        defer {
            if previousPolicy != .regular {
                NSApp.setActivationPolicy(previousPolicy)
            }
        }
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}

extension NSWorkspace {
    func reveal(_ path: String) {
        let expanded = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        guard FileManager.default.fileExists(atPath: expanded) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
