import Foundation

/// Screens available in the menu panel.
enum PanelRoute { case list, newSession, settings, remoteBrowser }

/// Editable state for the New/Edit Session form. It lives in `AppStore` (not in
/// the view) so that a folder-picker interaction — which briefly dismisses the
/// menu-bar window — does not lose what you were typing.
struct NewSessionDraft: Codable, Equatable {
    /// What kind of target the other endpoint is.
    enum TargetKind: String, Codable, CaseIterable, Identifiable {
        case remote
        case local
        case custom
        var id: String { rawValue }
        var title: String {
            switch self {
            case .remote: return "Remote (SSH)"
            case .local: return "Local folder"
            case .custom: return "Custom URL"
            }
        }
    }

    /// User-facing sync modes. Mutagen always propagates from the first-listed
    /// endpoint (alpha) to the second (beta) and only offers "local wins"
    /// conflict resolution, so both "remote wins" and one-way direction are
    /// expressed by swapping the endpoint order when the session is created.
    enum ModeChoice: String, Codable, CaseIterable, Identifiable {
        case twoWaySafe
        case twoWayLocalWins
        case twoWayRemoteWins
        case oneWayLocalToRemote
        case oneWayRemoteToLocal

        var id: String { rawValue }

        var title: String {
            switch self {
            case .twoWaySafe: return "Two-way (safe)"
            case .twoWayLocalWins: return "Two-way (local wins)"
            case .twoWayRemoteWins: return "Two-way (remote wins)"
            case .oneWayLocalToRemote: return "One-way (local → remote)"
            case .oneWayRemoteToLocal: return "One-way (remote → local)"
            }
        }

        var isOneWay: Bool { self == .oneWayLocalToRemote || self == .oneWayRemoteToLocal }

        /// Explanation shown under the picker. One-way modes also reflect the
        /// Safe checkbox, so the text clarifies exactly which choice is active.
        func detail(oneWaySafe: Bool) -> String {
            switch self {
            case .twoWaySafe:
                return "Changes flow in both directions. If the same file is edited on both sides, it is left as a conflict for you to resolve."
            case .twoWayLocalWins:
                return "Changes flow in both directions, but conflicts are resolved automatically in favour of the local side."
            case .twoWayRemoteWins:
                return "Changes flow in both directions, but conflicts are resolved automatically in favour of the remote side."
            case .oneWayLocalToRemote:
                return oneWaySafe
                    ? "Changes flow only from the local folder to the remote. Remote-only files are left untouched and can become conflicts."
                    : "Replica: the remote is forced to match the local folder exactly. Remote-only files are overwritten or deleted — use with care."
            case .oneWayRemoteToLocal:
                return oneWaySafe
                    ? "Changes flow only from the remote to the local folder. Local-only files are left untouched and can become conflicts."
                    : "Replica: the local folder is forced to match the remote exactly. Local-only files are overwritten or deleted — use with care."
            }
        }

        /// Mutagen only knows the propagation mode; the direction lives in the
        /// endpoint order.
        func mutagenMode(oneWaySafe: Bool) -> String {
            switch self {
            case .twoWaySafe: return "two-way-safe"
            case .twoWayLocalWins, .twoWayRemoteWins: return "two-way-resolved"
            case .oneWayLocalToRemote, .oneWayRemoteToLocal:
                return oneWaySafe ? "one-way-safe" : "one-way-replica"
            }
        }

        /// "Remote wins" and "remote → local" are implemented by listing the
        /// remote endpoint first.
        var swapsEndpoints: Bool { self == .twoWayRemoteWins || self == .oneWayRemoteToLocal }
    }

    var name: String = ""
    var localPath: String = ""
    var targetKind: TargetKind = .remote
    var localTargetPath: String = ""
    var sshUser: String = "admin"
    var sshHost: String = ""
    var sshPort: String = ""
    var sshPath: String = ""
    var customTarget: String = ""
    var modeChoice: ModeChoice = .twoWaySafe
    /// One-way modes run "safe" by default; unchecking turns them into replica.
    var oneWaySafe: Bool = true
    var ignoreText: String = ""
    var ignoreVCS: Bool = true
    var ignoreBuildArtifacts: Bool = false

    /// The directories blocked by Mutagen's `--ignore-vcs` group.
    static let vcsIgnores = [".git/", ".svn/", ".hg/", ".bzr/", "_darcs/", "CVS/"]
    /// Common build output directories/artifacts.
    static let buildIgnores = ["node_modules/", "target/", "build/", "bin/", "*.o"]

    init() {}

    init(from definition: SavedSession) {
        // Sessions can be stored local-first (normal) or remote-first (remote
        // wins), so work out the orientation before filling the fields.
        let alphaIsLocal = Self.looksLocal(definition.alpha)
        let betaIsLocal = Self.looksLocal(definition.beta)
        var local = definition.alpha
        var target = definition.beta
        var remoteFirst = false
        if !alphaIsLocal && betaIsLocal {
            local = definition.beta
            target = definition.alpha
            remoteFirst = true
        }

        name = definition.name
        localPath = local

        if Self.looksLocal(target) {
            targetKind = .local
            localTargetPath = target
        } else if target.hasPrefix("ssh://") || target.contains("@") {
            if parseSSH(target) {
                targetKind = .remote
            } else {
                targetKind = .custom
                customTarget = target
            }
        } else {
            targetKind = .custom
            customTarget = target
        }

        switch definition.mode {
        case "two-way-resolved":
            modeChoice = remoteFirst ? .twoWayRemoteWins : .twoWayLocalWins
        case "one-way-safe", "one-way-replica":
            oneWaySafe = definition.mode == "one-way-safe"
            modeChoice = remoteFirst ? .oneWayRemoteToLocal : .oneWayLocalToRemote
        default:
            modeChoice = .twoWaySafe
        }

        let vcs = Set(Self.vcsIgnores)
        let build = Set(Self.buildIgnores)
        ignoreText = definition.ignorePaths
            .filter { !vcs.contains($0) && !build.contains($0) }
            .joined(separator: "\n")
        ignoreVCS = definition.ignoreVCS || definition.ignorePaths.contains { vcs.contains($0) }
        ignoreBuildArtifacts = definition.ignorePaths.contains { build.contains($0) }
    }

    // MARK: - Derived values

    var customIgnorePaths: [String] {
        ignoreText
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Every pattern that will actually be blocked, for display next to the
    /// ignore toggles.
    var effectiveIgnores: [String] {
        var patterns: [String] = []
        if ignoreVCS { patterns += Self.vcsIgnores }
        if ignoreBuildArtifacts { patterns += Self.buildIgnores }
        patterns += customIgnorePaths
        var seen = Set<String>()
        return patterns.filter { seen.insert($0).inserted }
    }

    /// The other endpoint, as a URL.
    var resolvedTarget: String {
        switch targetKind {
        case .local:
            return PathUtil.expand(localTargetPath)
        case .custom:
            return customTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        case .remote:
            let host = sshHost.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !host.isEmpty else { return "" }
            let user = sshUser.trimmingCharacters(in: .whitespacesAndNewlines)
            let prefix = user.isEmpty ? "" : "\(user)@"
            var path = sshPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty && !path.hasPrefix("/") { path = "/" + path }
            let port = sshPort.trimmingCharacters(in: .whitespacesAndNewlines)
            if port.isEmpty {
                return "\(prefix)\(host):\(path)"
            }
            return "ssh://\(prefix)\(host):\(port)\(path)"
        }
    }

    /// True when the chosen mode should list the target endpoint first.
    var swapsEndpoints: Bool {
        guard !resolvedTarget.isEmpty else { return false }
        switch modeChoice {
        case .twoWayRemoteWins:
            // With a local folder on both sides there is no "remote" side to
            // favour, and the orientation cannot be recovered when editing.
            return !Self.looksLocal(resolvedTarget)
        case .oneWayRemoteToLocal:
            return true
        default:
            return false
        }
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !PathUtil.expand(localPath).isEmpty
            && !resolvedTarget.isEmpty
    }

    func toSavedSession() -> SavedSession {
        let local = PathUtil.expand(localPath)
        let target = resolvedTarget

        var ignores = customIgnorePaths
        if ignoreBuildArtifacts { ignores += Self.buildIgnores }
        var seen = Set<String>()
        ignores = ignores.filter { seen.insert($0).inserted }

        return SavedSession(
            name: name.trimmingCharacters(in: .whitespaces),
            alpha: swapsEndpoints ? target : local,
            beta: swapsEndpoints ? local : target,
            mode: modeChoice.mutagenMode(oneWaySafe: oneWaySafe),
            ignorePaths: ignores,
            ignoreVCS: ignoreVCS
        )
    }

    static func looksLocal(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        return trimmed.hasPrefix("/") || trimmed.hasPrefix("~") || trimmed.hasPrefix(".")
    }

    // MARK: - SSH parsing

    private mutating func parseSSH(_ value: String) -> Bool {
        if value.hasPrefix("ssh://") {
            let rest = String(value.dropFirst("ssh://".count))
            guard let slash = rest.firstIndex(of: "/") else { return false }
            let authority = String(rest[..<slash])
            let path = String(rest[slash...])
            guard !authority.isEmpty else { return false }
            let (user, hostPort) = Self.splitUser(authority)
            let (host, port) = Self.splitPort(hostPort)
            guard let host, !host.isEmpty else { return false }
            sshUser = user ?? "admin"
            sshHost = host
            sshPort = port ?? ""
            sshPath = path
            return true
        }

        guard let colon = value.firstIndex(of: ":") else { return false }
        let prefix = String(value[..<colon])
        var path = String(value[value.index(after: colon)...])
        let (user, hostPort) = Self.splitUser(prefix)
        let (host, port) = Self.splitPort(hostPort)
        guard let host, !host.isEmpty else { return false }
        sshUser = user ?? "admin"
        sshHost = host
        sshPort = port ?? ""
        if !path.isEmpty && !path.hasPrefix("/") { path = "/" + path }
        sshPath = path
        return true
    }

    private static func splitUser(_ value: String) -> (String?, String) {
        if let at = value.lastIndex(of: "@") {
            return (String(value[..<at]), String(value[value.index(after: at)...]))
        }
        return (nil, value)
    }

    private static func splitPort(_ value: String) -> (String?, String?) {
        if let colon = value.lastIndex(of: ":") {
            let host = String(value[..<colon])
            let port = String(value[value.index(after: colon)...])
            return (host, port.isEmpty ? nil : port)
        }
        return (value, nil)
    }
}
