import XCTest
import AppKit
@testable import Symplast

final class AppMenuTests: XCTestCase {
    @MainActor
    func testEditMenuProvidesStandardEditingKeyEquivalents() throws {
        let menu = AppMenu.build()
        let edit = try XCTUnwrap(menu.items.compactMap(\.submenu).first { $0.title == "Edit" })

        let undo = try XCTUnwrap(edit.items.first { $0.title == "Undo" })
        XCTAssertEqual(undo.keyEquivalent, "z")
        XCTAssertEqual(undo.keyEquivalentModifierMask, .command)
        XCTAssertEqual(undo.action, Selector(("undo:")))

        let redo = try XCTUnwrap(edit.items.first { $0.title == "Redo" })
        XCTAssertEqual(redo.keyEquivalent, "z")
        XCTAssertEqual(redo.keyEquivalentModifierMask, [.command, .shift])
        XCTAssertEqual(redo.action, Selector(("redo:")))

        let cut = try XCTUnwrap(edit.items.first { $0.title == "Cut" })
        XCTAssertEqual(cut.keyEquivalent, "x")
        XCTAssertEqual(cut.action, #selector(NSText.cut(_:)))

        let copy = try XCTUnwrap(edit.items.first { $0.title == "Copy" })
        XCTAssertEqual(copy.keyEquivalent, "c")
        XCTAssertEqual(copy.action, #selector(NSText.copy(_:)))

        let paste = try XCTUnwrap(edit.items.first { $0.title == "Paste" })
        XCTAssertEqual(paste.keyEquivalent, "v")
        XCTAssertEqual(paste.action, #selector(NSText.paste(_:)))

        let selectAll = try XCTUnwrap(edit.items.first { $0.title == "Select All" })
        XCTAssertEqual(selectAll.keyEquivalent, "a")
        XCTAssertEqual(selectAll.action, #selector(NSText.selectAll(_:)))
    }

    @MainActor
    func testEditingItemsHaveNoTargetSoTheyFollowTheResponderChain() throws {
        let menu = AppMenu.build()
        let edit = try XCTUnwrap(menu.items.compactMap(\.submenu).first { $0.title == "Edit" })
        for item in edit.items where item.action != nil {
            XCTAssertNil(item.target, "\(item.title) must reach the focused text field")
        }
    }

    @MainActor
    func testQuitKeepsItsKeyboardShortcut() throws {
        let menu = AppMenu.build()
        let app = try XCTUnwrap(menu.items.first?.submenu)
        let quit = try XCTUnwrap(app.items.first { $0.title == "Quit Symplast" })
        XCTAssertEqual(quit.keyEquivalent, "q")
        XCTAssertEqual(quit.action, #selector(NSApplication.terminate(_:)))
    }

    /// The reported bug: ⌘V in the session form's path fields did nothing,
    /// because no menu claimed the keystroke. This checks both halves of the
    /// fix — the menu claims ⌘V, and the action it carries pastes into the
    /// focused field editor. (The test host cannot make its window key, so the
    /// action is dispatched to the same first responder the menu would reach.)
    @MainActor
    func testCommandVPastesIntoFocusedTextField() throws {
        let app = NSApplication.shared
        app.mainMenu = AppMenu.build()

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 220, height: 40),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let field = NSTextField(frame: NSRect(x: 8, y: 8, width: 200, height: 24))
        window.contentView?.addSubview(field)
        window.makeKeyAndOrderFront(nil)
        XCTAssertTrue(window.makeFirstResponder(field), "the field must be focused")
        let editor = try XCTUnwrap(window.firstResponder as? NSText)
        field.stringValue = "old"

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("/Users/me/project", forType: .string)

        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: 0, windowNumber: window.windowNumber, context: nil,
            characters: "v", charactersIgnoringModifiers: "v",
            isARepeat: false, keyCode: 9))
        XCTAssertTrue(app.mainMenu?.performKeyEquivalent(with: event) == true,
                      "⌘V must be claimed by the Paste menu item")

        editor.selectAll(nil)
        XCTAssertTrue(app.sendAction(#selector(NSText.paste(_:)), to: editor, from: nil),
                      "the Paste action must reach the focused field editor")
        XCTAssertEqual(field.stringValue, "/Users/me/project")
        window.orderOut(nil)
    }
}
