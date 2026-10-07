import Foundation

enum Format {
    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter
    }()

    static func bytes(_ count: Int) -> String {
        byteFormatter.string(fromByteCount: Int64(count))
    }

    static func number(_ value: Int) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
    }

    /// One-line summary like `41,296 files · 571 MB`.
    static func contents(directories: Int?, files: Int?, size: Int?) -> String {
        var parts: [String] = []
        if let files, files > 0 { parts.append("\(number(files)) files") }
        if let directories, directories > 0 { parts.append("\(number(directories)) dirs") }
        if let size, size > 0 { parts.append(bytes(size)) }
        return parts.joined(separator: " · ")
    }
}

enum PathUtil {
    /// Expand `~` and standardize a user-entered path.
    static func expand(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        let expanded = (trimmed as NSString).expandingTildeInPath
        return expanded
    }

    static func abbreviate(_ path: String) -> String {
        MutagenEndpoint.abbreviate(path, keepLast: 2)
    }
}
