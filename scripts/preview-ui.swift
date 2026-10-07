// Compiled by preview-ui.sh alongside the app sources. No daemon is started,
// and a separate preferences suite keeps real sessions/settings untouched.
import AppKit
import SwiftUI

@main
struct UIPreview {
    @MainActor
    static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        NSImage(contentsOf: root.appendingPathComponent("Resources/MutagenLogo.png"))?.setName("MutagenLogo")
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let suite = "MutagenDock.UIPreview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let publicPreview = CommandLine.arguments.contains("--public")
        let disconnectedName = publicPreview ? "client-project" : "a-very-long-session-name-for-the-client-project"

        let fixtures = try JSONDecoder().decode([MutagenSession].self, from: Data("""
        [
          {"identifier":"healthy","name":"website-sync","status":"Watching for changes","mode":"two-way-resolved",
           "alpha":{"protocol":"local","path":"\(NSHomeDirectory())/Developer/website","connected":true,"files":41296,"directories":1688,"totalFileSize":571000000},
           "beta":{"protocol":"ssh","user":"deploy","host":"studio.example.com","path":"/srv/projects/website","connected":true},"ignore":{"paths":[]}},
          {"identifier":"offline","name":"\(disconnectedName)","status":"Disconnected","mode":"one-way-replica",
           "alpha":{"protocol":"local","path":"\(NSHomeDirectory())/Developer/client-project","connected":true},
           "beta":{"protocol":"ssh","user":"deploy","host":"production.example.com","path":"/srv/client-project","connected":false},"ignore":{"paths":[]}},
          {"identifier":"paused","name":"design-assets","paused":true,"status":"Paused","mode":"two-way-safe",
           "alpha":{"protocol":"local","path":"\(NSHomeDirectory())/Documents/Design assets","connected":false},
           "beta":{"protocol":"local","path":"/Volumes/Archive/Design assets","connected":false},"ignore":{"paths":[]}},
          {"identifier":"connecting","name":"remote-first","status":"Connecting to alpha","mode":"two-way-resolved",
           "alpha":{"protocol":"ssh","user":"admin","host":"build.example.com","path":"/srv/workspaces/project","connected":false},
           "beta":{"protocol":"local","path":"\(NSHomeDirectory())/Developer/project","connected":true},"ignore":{"paths":[]}},
          {"identifier":"conflict","name":"conflicted-session","status":"Halted due to conflicts","mode":"two-way-safe",
           "alpha":{"protocol":"local","path":"\(NSHomeDirectory())/Developer/project","connected":true},
           "beta":{"protocol":"ssh","host":"studio.example.com","path":"/srv/project","connected":true},"ignore":{"paths":[]}},
          {"identifier":"scanning","name":"workspace-sync","status":"Scanning files","mode":"two-way-safe",
           "alpha":{"protocol":"local","path":"\(NSHomeDirectory())/Developer/workspace","connected":true},
           "beta":{"protocol":"ssh","host":"studio.example.com","path":"/srv/workspace","connected":true},"ignore":{"paths":[]}}
        ]
        """.utf8))
        let saved = SavedSession(name: "archive-sync", alpha: "~/Documents/Archive",
                                 beta: "backup@nas.local:/volume/backups", mode: "two-way-safe",
                                 ignorePaths: [], ignoreVCS: true)

        for dark in [false, true] {
            let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
            app.appearance = appearance
            let store = AppStore(defaults: defaults)
            let suffix = dark ? "dark" : "light"

            func capture(_ name: String, height: CGFloat? = nil) throws {
                let panelHeight = height ?? Layout.listHeight(
                    sessionCount: store.sessions.count, savedCount: store.stoppedDefinitions.count,
                    daemonAvailable: store.daemonAvailable, hasError: store.lastError != nil)
                let rect = NSRect(x: 0, y: 0, width: Layout.panelWidth, height: panelHeight)
                let view = NSHostingView(rootView: MenuContentView(store: store)
                    .environment(\.colorScheme, dark ? .dark : .light)
                    .environment(\.controlActiveState, .active)
                    // A standalone snapshot window has no popover material.
                    // Supply a backdrop here only; the actual panel stays clear.
                    .background(Color(nsColor: .windowBackgroundColor)))
                let window = NSWindow(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
                window.appearance = appearance
                window.contentView = view
                window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
                window.orderFrontRegardless()
                RunLoop.main.run(until: Date().addingTimeInterval(0.15))
                view.layoutSubtreeIfNeeded()
                view.displayIfNeeded()
                guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                    throw NSError(domain: "UIPreview", code: 1)
                }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                guard let data = bitmap.representation(using: .png, properties: [:]) else {
                    throw NSError(domain: "UIPreview", code: 2)
                }
                try data.write(to: output.appendingPathComponent("\(name)-\(suffix).png"))
                window.orderOut(nil)
            }

            // Opt-in, window-only screen capture verifies the real AppKit arrow
            // and material, which an offscreen hosting-view bitmap cannot show.
            func captureNativePopover() throws {
                guard CommandLine.arguments.contains("--native"), let screen = NSScreen.main else { return }
                let anchor = NSView(frame: NSRect(x: 0, y: 0, width: 20, height: 10))
                let anchorWindow = NSWindow(contentRect: anchor.bounds, styleMask: [.borderless],
                                            backing: .buffered, defer: false)
                anchorWindow.appearance = appearance
                anchorWindow.contentView = anchor
                anchorWindow.alphaValue = 0.01
                anchorWindow.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.maxY - 20))
                anchorWindow.orderFrontRegardless()
                let controller = NSHostingController(rootView: MenuContentView(store: store)
                    .environment(\.colorScheme, dark ? .dark : .light)
                    .environment(\.controlActiveState, .active))
                controller.sizingOptions = []
                let popover = NSPopover()
                popover.appearance = appearance
                popover.behavior = .applicationDefined
                popover.animates = false
                popover.contentViewController = controller
                popover.contentSize = NSSize(width: Layout.panelWidth, height: Layout.listHeight(
                    sessionCount: store.sessions.count, savedCount: store.stoppedDefinitions.count,
                    daemonAvailable: store.daemonAvailable, hasError: store.lastError != nil))
                popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
                defer {
                    popover.close()
                    anchorWindow.orderOut(nil)
                }
                RunLoop.main.run(until: Date().addingTimeInterval(0.25))
                guard let window = controller.view.window else { throw NSError(domain: "UIPreview", code: 3) }
                let capture = Process()
                capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                capture.arguments = ["-x", "-o", "-l", String(window.windowNumber),
                                     output.appendingPathComponent("native-popover-\(suffix).png").path]
                try capture.run()
                capture.waitUntilExit()
                guard capture.terminationStatus == 0 else { throw NSError(domain: "UIPreview", code: 4) }
            }

            store.setPreviewSessions(Array(fixtures.prefix(2)), saved: [saved])
            try capture("sessions")
            try captureNativePopover()
            store.setPreviewSessions([fixtures[0]])
            try capture("single-session")
            store.setPreviewSessions(Array(fixtures[2...4]))
            try capture("statuses")
            store.setPreviewSessions(fixtures, saved: [saved])
            try capture("scrolling")
            store.setPreviewSessions([])
            try capture("empty")
            store.setPreviewSessions([], saved: [saved])
            try capture("saved")
            store.setPreviewSessions([], daemonAvailable: false)
            try capture("daemon-unavailable")
            store.setPreviewSessions([fixtures[0]])
            store.lastError = "Could not complete the sync cycle. Check your SSH connection and try again."
            try capture("error")
            store.lastError = nil
            store.beginNewSession()
            if publicPreview {
                store.draft.name = "website-sync"
                store.draft.localPath = "~/Developer/website"
                store.draft.sshUser = "deploy"
                store.draft.sshHost = "studio.example.com"
                store.draft.sshPath = "/srv/projects/website"
            }
            try capture("new-session", height: Layout.formHeight)
            store.draft.ignoreText = "node_modules/\n.cache/"
            try capture("ignore-patterns", height: 600)
            store.draft.ignoreText = ""
            store.draft.targetKind = .local
            try capture("local-target", height: Layout.formHeight)
            store.draft.targetKind = .custom
            store.draft.modeChoice = .oneWayReplica
            try capture("custom-target", height: Layout.formHeight)
            store.beginEdit(fixtures[0])
            try capture("edit-session", height: Layout.formHeight)
            store.route = .settings
            try capture("settings", height: Layout.settingsHeight)
            store.route = .list
            store.setPreviewSessions([], daemonAvailable: false, executableMissing: true)
            try capture("executable-missing")
        }
        print("UI previews written to \(output.path)")
    }
}
