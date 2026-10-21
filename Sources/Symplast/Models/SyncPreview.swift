import Foundation

/// A file on one side of a preview comparison.
struct PreviewFile: Equatable {
    /// Path relative to the synchronized root.
    var path: String
    var size: Int64
    /// Modification time in whole seconds since 1970.
    var modified: Int64
}

/// The two sides of a session as the form labels them.
enum PreviewSide: String, Equatable {
    case local
    case target

    var label: String { self == .local ? "local folder" : "target" }
}

/// What will happen to one file once the session starts. The associated value
/// names the side the change lands on.
enum PreviewOutcome: Hashable {
    case created(PreviewSide)
    case overwritten(PreviewSide)
    case deleted(PreviewSide)
    /// Left untouched even though it differs (one-way safe).
    case kept(PreviewSide)
    case conflict
    case unchanged
}

/// A before-the-fact comparison of the two sides of a session: which files the
/// first sync would create, replace, delete or leave alone. It is an estimate —
/// Mutagen compares content and history, this compares names, sizes and
/// modification times — but it is enough to see where an overwrite would land.
enum SyncPreview {
    struct Entry: Equatable {
        var path: String
        var outcome: PreviewOutcome
        /// Size of the file the sync would propagate, for the summary rows.
        var size: Int64
    }

    /// Compare the two inventories into per-file outcomes.
    ///
    /// - `oneWaySource` names the side that propagates; `nil` means two-way.
    /// - `replica` replaces the "left alone" outcomes of one-way safe with
    ///   overwrites and deletions.
    static func classify(
        local: [PreviewFile],
        remote: [PreviewFile],
        oneWaySource: PreviewSide?,
        replica: Bool
    ) -> [Entry] {
        var localByPath: [String: PreviewFile] = [:]
        for file in local { localByPath[file.path] = file }
        var remoteByPath: [String: PreviewFile] = [:]
        for file in remote { remoteByPath[file.path] = file }

        var entries: [Entry] = []
        for path in Set(localByPath.keys).union(remoteByPath.keys) {
            let localFile = localByPath[path]
            let remoteFile = remoteByPath[path]
            entries.append(Entry(path: path,
                                 outcome: outcome(local: localFile, remote: remoteFile,
                                                  oneWaySource: oneWaySource, replica: replica),
                                 size: (localFile ?? remoteFile)?.size ?? 0))
        }
        return entries.sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }
    }

    private static func outcome(
        local: PreviewFile?,
        remote: PreviewFile?,
        oneWaySource: PreviewSide?,
        replica: Bool
    ) -> PreviewOutcome {
        switch (local, remote) {
        case (nil, nil):
            return .unchanged
        case (_?, nil):
            guard let source = oneWaySource else { return .created(.target) }
            if source == .local { return .created(.target) }
            return replica ? .deleted(.local) : .kept(.local)
        case (nil, _?):
            guard let source = oneWaySource else { return .created(.local) }
            if source == .target { return .created(.local) }
            return replica ? .deleted(.target) : .kept(.target)
        case let (local?, remote?):
            if local.size == remote.size && local.modified == remote.modified { return .unchanged }
            switch oneWaySource {
            case .local:
                if local.modified > remote.modified { return .overwritten(.target) }
                if local.modified < remote.modified { return replica ? .overwritten(.target) : .kept(.target) }
                return replica ? .overwritten(.target) : .conflict
            case .target:
                if remote.modified > local.modified { return .overwritten(.local) }
                if remote.modified < local.modified { return replica ? .overwritten(.local) : .kept(.local) }
                return replica ? .overwritten(.local) : .conflict
            case nil:
                if local.modified > remote.modified { return .overwritten(.target) }
                if remote.modified > local.modified { return .overwritten(.local) }
                return .conflict
            }
        }
    }
}

/// Approximates the ignore patterns the app offers (the practical subset of
/// Mutagen's syntax): a pattern with no slash matches a file or folder name at
/// any depth, a pattern with a slash matches from the root, `*` and `?` are
/// wildcards, and a trailing `/` restricts the match to folders — which also
/// covers everything inside them.
struct IgnoreMatcher {
    private let rules: [Rule]

    init(patterns: [String]) {
        rules = patterns.compactMap { raw in
            var pattern = raw.trimmingCharacters(in: .whitespaces)
            guard !pattern.isEmpty else { return nil }
            let folderOnly = pattern.hasSuffix("/")
            if folderOnly { pattern.removeLast() }
            if pattern.hasPrefix("/") { pattern.removeFirst() }
            guard !pattern.isEmpty, let regex = Self.regex(for: pattern) else { return nil }
            return Rule(regex: regex, anchored: pattern.contains("/"), folderOnly: folderOnly)
        }
    }

    /// Whether a file at this relative path is excluded from the sync.
    func ignores(_ relativePath: String) -> Bool {
        let components = relativePath.split(separator: "/").map(String.init)
        guard !components.isEmpty else { return false }
        let parents = components.dropLast()
        return rules.contains { rule in
            if rule.anchored {
                let prefixes = components.indices.map { components[0...$0].joined(separator: "/") }
                let candidates = rule.folderOnly ? prefixes.dropLast() : prefixes[...]
                return candidates.contains { rule.regex.matches($0) }
            }
            let candidates = rule.folderOnly ? parents : components[...]
            return candidates.contains { rule.regex.matches($0) }
        }
    }

    /// Whether a directory at this relative path is excluded, along with
    /// everything inside it. Used to prune the local scan instead of walking
    /// large ignored trees.
    func ignoresDirectory(_ relativePath: String) -> Bool {
        if ignores(relativePath) { return true }
        let components = relativePath.split(separator: "/").map(String.init)
        guard !components.isEmpty else { return false }
        return rules.contains { rule in
            guard rule.folderOnly else { return false }
            let candidate = rule.anchored
                ? components.joined(separator: "/")
                : components[components.count - 1]
            return rule.regex.matches(candidate)
        }
    }

    private struct Rule {
        var regex: NSRegularExpression
        var anchored: Bool
        var folderOnly: Bool
    }

    /// Compile a glob into an anchored regular expression. `*` stops at `/`,
    /// `**` crosses directory boundaries.
    private static func regex(for pattern: String) -> NSRegularExpression? {
        var result = "^"
        let characters = Array(pattern)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            switch character {
            case "*":
                if index + 1 < characters.count, characters[index + 1] == "*" {
                    result += ".*"
                    index += 1
                } else {
                    result += "[^/]*"
                }
            case "?":
                result += "[^/]"
            default:
                if "\\.[]{}()+-^$|".contains(character) {
                    result += "\\\(character)"
                } else {
                    result.append(character)
                }
            }
            index += 1
        }
        result += "$"
        return try? NSRegularExpression(pattern: result)
    }
}

private extension NSRegularExpression {
    func matches(_ value: String) -> Bool {
        firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil
    }
}
