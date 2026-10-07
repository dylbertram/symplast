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
        popover.contentSize = NSSize(width: Layout.panelWidth, height: Layout.panelHeight)
        popover.contentViewController = NSHostingController(rootView: MenuContentView(store: store))
    }

    private func observeStore() {
        store.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.updateStatusItem() }
            }
            .store(in: &cancellables)
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }

        if let image = BrandAssets.menuBarImage(height: 18) {
            button.image = image
        } else if let fallback = NSImage(systemSymbolName: store.worstState.menuBarSymbol,
                                         accessibilityDescription: "MutagenDock") {
            fallback.isTemplate = true
            button.image = fallback
        }

        // The logo is a template image, so tint it to signal state.
        switch store.worstState {
        case .disconnected, .error:
            button.contentTintColor = .systemRed
        case .paused:
            button.contentTintColor = .systemOrange
        default:
            button.contentTintColor = nil
        }

        if store.settings.showCount, !store.sessions.isEmpty {
            button.title = " \(store.sessions.count)"
        } else {
            button.title = ""
        }
        button.toolTip = tooltip
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
