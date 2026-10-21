import XCTest
import AppKit
import SwiftUI
@testable import Symplast

/// SwiftUI's update graph aborts the process ("AttributeGraph: cycle
/// detected") when a view body does process work — shelling out for the SSH
/// agent in Settings did exactly that. These smoke tests render the screens
/// headlessly: such a regression traps the suite instead of passing quietly.
final class ViewRenderTests: XCTestCase {
    @MainActor
    func testSettingsViewRenders() throws {
        let suite = "Symplast.RenderTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppStore(defaults: defaults)
        store.route = .settings
        XCTAssertNotNil(render(MenuContentView(store: store),
                               width: Layout.panelWidth, height: Layout.settingsHeight))
    }

    @MainActor
    func testSyncPreviewViewRenders() throws {
        let suite = "Symplast.RenderTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppStore(defaults: defaults)
        store.setPreviewReport(SyncPreviewReport(
            localPath: "/tmp/source", targetPath: "deploy@host:/srv/target",
            entries: (1...25).map {
                SyncPreview.Entry(path: "file-\($0).txt", outcome: .overwritten(.target), size: Int64($0))
            },
            unchangedCount: 3, truncated: false, notice: nil))
        XCTAssertNotNil(render(MenuContentView(store: store),
                               width: Layout.panelWidth, height: Layout.previewHeight))
    }

    @MainActor
    private func render<V: View>(_ view: V, width: CGFloat, height: CGFloat) -> NSBitmapImageRep? {
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        window.orderOut(nil)
        return bitmap
    }
}
