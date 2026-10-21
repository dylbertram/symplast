import AppKit

/// The application main menu.
///
/// Symplast is a menu-bar app and presents no windows of its own, but the
/// standard editing commands must still exist as menu items somewhere:
/// macOS resolves ⌘X, ⌘C, ⌘V and ⌘A through the main menu's key equivalents
/// and forwards the resulting `cut:`/`copy:`/`paste:`/`selectAll:` action down
/// the responder chain to the focused field editor. Without a main menu those
/// keystrokes arrive as plain key events and copy/paste in the session form
/// silently does nothing.
enum AppMenu {
    static func build() -> NSMenu {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu(title: "Symplast")
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "About Symplast",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Symplast",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editItem.submenu = editMenu

        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        return mainMenu
    }
}
