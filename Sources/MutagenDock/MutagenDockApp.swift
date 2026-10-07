import SwiftUI
import AppKit
import Combine

@main
struct MutagenDockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // The app is status-bar only; the AppDelegate owns the NSStatusItem and
        // popover. A Settings scene satisfies the App protocol without opening
        // any window on launch.
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = AppStore()

    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        store.start()
        configureStatusItem()
        observeStore()
        updateStatusItem()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stop()
    }

    // MARK: - Status item

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        if let button = item.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
        }

        popover.behavior = .transient
        popover.animates = false
        let controller = NSHostingController(rootView: MenuContentView(store: store))
        // We drive the popover size ourselves; stop the hosting controller from
        // reporting a (collapsed) intrinsic height for the scroll content.
        controller.sizingOptions = []
        popover.contentViewController = controller
        popover.contentSize = currentPopoverSize()
    }

    private func observeStore() {
        store.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateStatusItem()
                    self?.updatePopoverSize()
                }
            }
            .store(in: &cancellables)
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }

        let tint: NSColor?
        switch store.worstState {
        case .disconnected, .error: tint = .systemRed
        case .paused: tint = .systemGray
        default: tint = nil
        }

        if let image = BrandAssets.menuBarImage(height: 18, tint: tint) {
            button.image = image
            button.contentTintColor = nil
        } else if let fallback = NSImage(systemSymbolName: store.worstState.menuBarSymbol,
                                         accessibilityDescription: "MutagenDock") {
            fallback.isTemplate = true
            button.image = fallback
            button.contentTintColor = tint
        }

        if store.settings.showCount, !store.sessions.isEmpty {
            button.title = " \(store.sessions.count)"
        } else {
            button.title = ""
        }
        button.toolTip = tooltip
    }

    // MARK: - Popover sizing

    private func updatePopoverSize() {
        let size = currentPopoverSize()
        if popover.contentSize != size {
            popover.contentSize = size
        }
    }

    private func currentPopoverSize() -> NSSize {
        NSSize(width: Layout.panelWidth, height: currentPopoverHeight())
    }

    /// A snug, content-hugging height for the list, and roomier fixed heights
    /// for the forms. Assigned explicitly so the popover both grows and shrinks.
    private func currentPopoverHeight() -> CGFloat {
        switch store.route {
        case .newSession, .settings:
            return 540
        case .list:
            let sessionCount = store.sessions.count
            let savedCount = store.stoppedDefinitions.count
            if sessionCount + savedCount == 0 { return 240 }

            var height: CGFloat = 40 + 40 + 2 // header + footer + dividers
            if sessionCount > 0 { height += 24 }
            if savedCount > 0 { height += 24 }
            height += CGFloat(sessionCount) * 70
            height += CGFloat(savedCount) * 58
            if !store.daemonAvailable { height += 96 }
            if store.lastError != nil && store.daemonAvailable { height += 34 }
            return min(600, max(180, height))
        }
    }

    private var tooltip: String {
        if !store.daemonAvailable { return "MutagenDock — daemon not running" }
        if store.sessions.isEmpty { return "MutagenDock — no sessions" }
        if store.disconnectedCount > 0 {
            return "MutagenDock — \(store.disconnectedCount) disconnected"
        }
        return "MutagenDock — \(store.sessions.count) session(s), \(store.worstState.label)"
    }

    // MARK: - Mouse interaction

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        let isRightClick = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true
        if isRightClick {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        guard let button = statusItem?.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func showContextMenu() {
        guard let item = statusItem, let button = item.button else { return }
        if popover.isShown { popover.performClose(nil) }

        let menu = NSMenu()

        let newItem = NSMenuItem(title: "New session…", action: #selector(menuNewSession), keyEquivalent: "")
        newItem.target = self
        menu.addItem(newItem)

        let openItem = NSMenuItem(title: "Open MutagenDock", action: #selector(menuOpenPanel), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit MutagenDock", action: #selector(menuQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: button.bounds.height + 4),
            in: button
        )
    }

    @objc private func menuNewSession() {
        store.beginNewSession()
        presentPopover()
    }

    @objc private func menuOpenPanel() {
        store.route = .list
        presentPopover()
    }

    private func presentPopover() {
        guard !popover.isShown else { return }
        togglePopover()
    }

    @objc private func menuQuit() {
        NSApp.terminate(nil)
    }
}
