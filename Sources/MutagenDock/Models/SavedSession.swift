import Foundation

/// A session definition that MutagenDock remembers locally, independent of
/// whether Mutagen currently has a live session for it. This is what makes
/// "save them" work: even after terminating a session you can start it again.
struct SavedSession: Codable, Identifiable, Hashable {
    var name: String
    var alpha: String
    var beta: String
    var mode: String
    var ignorePaths: [String]
    var ignoreVCS: Bool
    var createdAt: Date

    var id: String { name }

    init(
        name: String,
        alpha: String,
        beta: String,
        mode: String = "two-way-safe",
        ignorePaths: [String] = [],
        ignoreVCS: Bool = true,
        createdAt: Date = Date()
    ) {
        self.name = name
        self.alpha = alpha
        self.beta = beta
        self.mode = mode
        self.ignorePaths = ignorePaths
        self.ignoreVCS = ignoreVCS
        self.createdAt = createdAt
    }

    /// Build a saved definition from a live session so it can be re-created.
    init(from session: MutagenSession) {
        self.name = session.name
        self.alpha = session.alphaURLString
        self.beta = session.betaURLString
        self.mode = "two-way-safe"
        self.ignorePaths = session.ignorePaths.filter { $0 != ".git/" }
        self.ignoreVCS = session.ignorePaths.contains(".git/")
        self.createdAt = Date()
    }

    /// Friendly relative summary, e.g. `~/Dev/app → admin@host:/srv/app`.
    var summary: String {
        "\(MutagenEndpoint.abbreviate(alpha, keepLast: 2)) → \(beta)"
    }
}
