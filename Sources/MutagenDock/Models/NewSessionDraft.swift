import Foundation

/// Screens available in the menu panel.
enum PanelRoute { case list, newSession, settings }

/// A reusable fixed layout so the menu-bar window never needs to resize.
enum Layout {
    static let panelWidth: CGFloat = 380
    static let panelHeight: CGFloat = 520
}

/// Editable state for the New/Edit Session form. It lives in `AppStore` (not in
/// the view) so that a folder-picker interaction — which briefly dismisses the
/// menu-bar window — does not lose what you were typing.
struct NewSessionDraft: Codable, Equatable {
    enum BetaMode: String, Codable, CaseIterable, Identifiable {
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

    var name: String = ""
    var alpha: String = ""
    var betaMode: BetaMode = .remote
    var betaLocal: String = ""
    var sshUser: String = "admin"
    var sshHost: String = ""
    var sshPort: String = ""
    var sshPath: String = ""
    var customBeta: String = ""
    var mode: String = SyncMode.twoWaySafe.rawValue
    var ignoreText: String = ""
    var ignoreVCS: Bool = true
    var ignoreBuildArtifacts: Bool = false

    /// The directories blocked by Mutagen's `--ignore-vcs` group.
    static let vcsIgnores = [".git/", ".svn/", ".hg/", ".bzr/", "_darcs/", "CVS/"]
    /// Common build output directories/artifacts.
    static let buildIgnores = ["target/", "build/", "bin/", "*.o"]

    init() {}

    init(from definition: SavedSession) {
        name = definition.name
        alpha = definition.alpha
        mode = definition.mode
        ignoreVCS = definition.ignoreVCS

        let vcs = Set(Self.vcsIgnores)
        let build = Set(Self.buildIgnores)
        ignoreText = definition.ignorePaths
            .filter { !vcs.contains($0) && !build.contains($0) }
            .joined(separator: "\n")
        if definition.ignorePaths.contains(where: { vcs.contains($0) }) {
            ignoreVCS = true
        }
        if definition.ignorePaths.contains(where: { build.contains($0) }) {
            ignoreBuildArtifacts = true
        }

        let beta = definition.beta
        if beta.hasPrefix("/") || beta.hasPrefix("~") {
            betaMode = .local
            betaLocal = beta
        } else if beta.hasPrefix("ssh://") || beta.contains("@") {
            if !parseSSH(beta) {
                betaMode = .custom
                customBeta = beta
            }
        } else {
            betaMode = .custom
            customBeta = beta
        }
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

    var resolvedBeta: String {
        switch betaMode {
        case .local:
            return PathUtil.expand(betaLocal)
        case .custom:
            return customBeta.trimmingCharacters(in: .whitespacesAndNewlines)
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

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !PathUtil.expand(alpha).isEmpty
            && !resolvedBeta.isEmpty
    }

    func toSavedSession() -> SavedSession {
        var ignores = customIgnorePaths
        if ignoreBuildArtifacts { ignores += Self.buildIgnores }
        var seen = Set<String>()
        ignores = ignores.filter { seen.insert($0).inserted }
        return SavedSession(
            name: name.trimmingCharacters(in: .whitespaces),
            alpha: PathUtil.expand(alpha),
            beta: resolvedBeta,
            mode: mode,
            ignorePaths: ignores,
            ignoreVCS: ignoreVCS
        )
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
