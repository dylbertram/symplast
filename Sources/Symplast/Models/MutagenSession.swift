import Foundation
import SwiftUI

/// One side (alpha or beta) of a Mutagen synchronization session.
struct MutagenEndpoint: Decodable {
    let protocolName: String?
    let user: String?
    let host: String?
    let path: String?
    let connected: Bool?
    let scanned: Bool?
    let directories: Int?
    let files: Int?
    let symbolicLinks: Int?
    let totalFileSize: Int?

    enum CodingKeys: String, CodingKey {
        case protocolName = "protocol"
        case user, host, path, connected, scanned
        case directories, files, symbolicLinks, totalFileSize
    }

    var isConnected: Bool { connected ?? false }

    var isLocal: Bool { protocolName == nil || protocolName == "local" }

    /// Full human-readable form, e.g. `admin@192.168.20.20:/opt/openchamber/workspaces`.
    var displayName: String {
        if isLocal { return path ?? "?" }
        let prefix = user.map { "\($0)@" } ?? ""
        let hostPart = host ?? "?"
        let portPart: String = ""
        return "\(prefix)\(portPart)\(hostPart):\(path ?? "")"
    }

    /// Full form with the home directory shortened, letting the UI truncate the
    /// middle only if there genuinely isn't room.
    var shortDisplayName: String {
        if isLocal {
            return Self.homeAbbreviated(path ?? "?")
        }
        let prefix = user.map { "\($0)@" } ?? ""
        return "\(prefix)\(host ?? "?"):\(path ?? "")"
    }

    static func homeAbbreviated(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    /// Lossless-ish URL suitable for re-creating a session.
    var urlString: String {
        if isLocal { return path ?? "" }
        let prefix = user.map { "\($0)@" } ?? ""
        return "\(prefix)\(host ?? ""):\(path ?? "")"
    }

    static func abbreviate(_ path: String, keepLast: Int) -> String {
        var value = path
        let home = NSHomeDirectory()
        if value.hasPrefix(home) {
            value = "~" + value.dropFirst(home.count)
        }
        let components = value.split(separator: "/").map(String.init)
        guard components.count > keepLast + 1 else { return value }
        return "…/" + components.suffix(keepLast).joined(separator: "/")
    }
}

/// A Mutagen synchronization session as returned by
/// `mutagen sync list --template '{{json .}}'`.
struct MutagenSession: Decodable, Identifiable {
    let identifier: String
    let name: String
    let alpha: MutagenEndpoint
    let beta: MutagenEndpoint
    let successfulCycles: Int?
    let creationTime: String?
    let creatingVersion: String?
    /// Sync mode (e.g. `two-way-resolved`). Only present in `mutagen sync list -l`.
    let mode: String?
    let lastError: String?

    private let pausedValue: Bool?
    private let statusValue: String?
    private let ignoreSpec: IgnoreSpec

    struct IgnoreSpec: Decodable { let paths: [String]? }

    enum CodingKeys: String, CodingKey {
        case identifier, name, alpha, beta
        case successfulCycles, creationTime, creatingVersion, mode, lastError
        case pausedValue = "paused"
        case statusValue = "status"
        case ignoreSpec = "ignore"
    }

    var id: String { identifier }
    var isPaused: Bool { pausedValue ?? false }
    var status: String { statusValue ?? "" }
    var ignorePaths: [String] { ignoreSpec.paths ?? [] }

    var isConnected: Bool { alpha.isConnected && beta.isConnected }

    /// Best-effort reconstruction of the beta URL used to create the session.
    var betaURLString: String { beta.urlString }
    var alphaURLString: String { alpha.urlString }

    var state: SyncState {
        if isPaused { return .paused }
        if !isConnected, let lastError, ErrorSummary.isConnectionFailure(lastError) { return .disconnected }
        if !isConnected {
            let s = status.lowercased()
            if s.hasPrefix("connecting") { return .connecting }
            return .disconnected
        }
        let s = status.lowercased()
        if s.hasPrefix("connecting") { return .connecting }
        if s.contains("scan") || s.contains("rescan") { return .scanning }
        if s.hasPrefix("staging") || s.hasPrefix("reconcil") || s.hasPrefix("transition")
            || s.hasPrefix("saving") || s.hasPrefix("flush") { return .syncing }
        if s.hasPrefix("watching") { return .watching }
        if s.contains("halted") || s.contains("error") || s.contains("conflict") { return .error }
        if s.contains("paused") { return .paused }
        return .idle
    }
}

/// Aggregate status used for the menu bar icon.
enum SyncState: Equatable {
    case paused
    case disconnected
    case connecting
    case scanning
    case syncing
    case watching
    case idle
    case error

    var label: String {
        switch self {
        case .paused: return "Paused"
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting"
        case .scanning: return "Scanning"
        case .syncing: return "Syncing"
        case .watching: return "Watching"
        case .idle: return "Idle"
        case .error: return "Error"
        }
    }

    var color: Color {
        switch self {
        case .paused: return .secondary
        case .disconnected: return PanelColors.critical
        case .connecting: return PanelColors.warning
        case .scanning: return PanelColors.warning
        case .syncing: return .blue
        case .watching: return PanelColors.success
        case .idle: return Color.secondary
        case .error: return PanelColors.critical
        }
    }

    var symbol: String {
        switch self {
        case .paused: return "pause.circle.fill"
        case .disconnected: return "bolt.horizontal.circle.fill"
        case .connecting: return "ellipsis.circle.fill"
        case .scanning: return "magnifyingglass.circle.fill"
        case .syncing: return "arrow.triangle.2.circlepath"
        case .watching: return "checkmark.circle.fill"
        case .idle: return "circle.dashed"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    /// Symbol shown in the macOS menu bar (no color, shape conveys state).
    var menuBarSymbol: String {
        switch self {
        case .paused: return "pause.circle"
        case .disconnected: return "bolt.horizontal.circle"
        case .connecting: return "ellipsis.circle"
        case .scanning: return "magnifyingglass.circle"
        case .syncing: return "arrow.triangle.2.circlepath"
        case .watching: return "arrow.triangle.2.circlepath"
        case .idle: return "externaldrive"
        case .error: return "exclamationmark.triangle"
        }
    }

    /// Mutagen retries a failing connection indefinitely and keeps reporting a
    /// `connecting-*` status, so a session that stays unconnected past a grace
    /// period is reported as disconnected rather than "Connecting" forever.
    func afterStall(notConnectedSince: Date?, now: Date = Date(), grace: TimeInterval = 10) -> SyncState {
        guard self == .connecting, let since = notConnectedSince,
              now.timeIntervalSince(since) >= grace else { return self }
        return .disconnected
    }
}
