import AppKit

// Pure AppKit entry point: the app is status-bar only, so no SwiftUI scene is
// used and no window is ever created on launch.
let application = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
