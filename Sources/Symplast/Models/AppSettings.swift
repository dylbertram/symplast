import Foundation

struct AppSettings: Codable, Equatable {
    /// Optional override for the `mutagen` executable path.
    var mutagenPath: String = ""
    /// How often (seconds) to poll `mutagen sync list`.
    var pollInterval: Double = 2.0
    /// Show the number of sessions next to the menu bar icon.
    var showCount: Bool = true
    /// Launch a session automatically when the app starts.
    var autoEnsureDaemon: Bool = true
}
