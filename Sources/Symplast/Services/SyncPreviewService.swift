import Foundation

/// The result of comparing the two sides of a draft session.
struct SyncPreviewReport: Equatable {
    var localPath: String
    var targetPath: String
    /// Files the sync would change. Unchanged files are only counted.
    var entries: [SyncPreview.Entry]
    var unchangedCount: Int
    /// True when a side had more files than the scan limit.
    var truncated: Bool
    /// Set when the comparison could not be made (missing folder, custom
    /// target, unreachable server).
    var notice: String?

    var changedCount: Int { entries.count }

    func entries(for outcome: PreviewOutcome) -> [SyncPreview.Entry] {
        entries.filter { $0.outcome == outcome }
    }
}

/// Builds the before-the-fact comparison shown before a session is created:
/// scans both sides (the local folder with Foundation, the remote with one
/// non-interactive SSH command), applies the draft's ignore patterns, and
/// classifies every file the first sync would touch.
enum SyncPreviewService {
    /// Upper bound of files scanned per side. The preview is an estimate and
    /// stays responsive on large trees.
    static let fileLimit = 20_000

    static func report(for draft: NewSessionDraft) async -> SyncPreviewReport {
        let localRoot = PathUtil.expand(draft.localPath)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: localRoot, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return report(localRoot, targetDescription(from: draft),
                          notice: "Choose an existing local folder: \(localRoot)")
        }

        do {
            let localScan = localInventory(at: localRoot, ignores: ignores(for: draft))
            let target = try await targetInventory(for: draft, ignores: ignores(for: draft))
            let entries = SyncPreview.classify(local: localScan.files,
                                               remote: target.files,
                                               oneWaySource: oneWaySource(for: draft),
                                               replica: isReplica(for: draft))
            let changed = entries.filter { $0.outcome != .unchanged }
            return SyncPreviewReport(
                localPath: localRoot,
                targetPath: target.description,
                entries: changed,
                unchangedCount: entries.count - changed.count,
                truncated: localScan.truncated || target.truncated,
                notice: nil)
        } catch {
            return report(localRoot, targetDescription(from: draft),
                          notice: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private static func report(_ local: String, _ target: String, notice: String) -> SyncPreviewReport {
        SyncPreviewReport(localPath: local, targetPath: target,
                          entries: [], unchangedCount: 0, truncated: false, notice: notice)
    }

    // MARK: - Draft interpretation

    private static func ignores(for draft: NewSessionDraft) -> IgnoreMatcher {
        IgnoreMatcher(patterns: draft.effectiveIgnores)
    }

    /// The side that propagates in a one-way session; `nil` for two-way.
    private static func oneWaySource(for draft: NewSessionDraft) -> PreviewSide? {
        guard draft.modeChoice.isOneWay else { return nil }
        return draft.modeChoice == .oneWayLocalToRemote ? .local : .target
    }

    private static func isReplica(for draft: NewSessionDraft) -> Bool {
        draft.modeChoice.isOneWay && !draft.oneWaySafe
    }

    private static func targetDescription(from draft: NewSessionDraft) -> String {
        let target = draft.resolvedTarget
        return target.isEmpty ? "the target" : target
    }

    // MARK: - Inventories

    private struct Inventory {
        var files: [PreviewFile]
        var description: String
        var truncated: Bool
    }

    private static func targetInventory(for draft: NewSessionDraft,
                                        ignores: IgnoreMatcher) async throws -> Inventory {
        switch draft.targetKind {
        case .local:
            let root = PathUtil.expand(draft.localTargetPath)
            let scan = localInventory(at: root, ignores: ignores)
            return Inventory(files: scan.files, description: root, truncated: scan.truncated)
        case .remote:
            let client = SSHRemoteClient(user: draft.sshUser, host: draft.sshHost, port: draft.sshPort)
            let files = try await client.inventory(at: draft.sshPath)
            return capped(files, description: draft.resolvedTarget)
        case .custom:
            let target = draft.customTarget.trimmingCharacters(in: .whitespacesAndNewlines)
            if let ssh = NewSessionDraft.parseSSHEndpoint(target) {
                let client = SSHRemoteClient(user: ssh.user, host: ssh.host, port: ssh.port)
                let files = try await client.inventory(at: ssh.path)
                return capped(files, description: target)
            }
            if NewSessionDraft.looksLocal(target) {
                let root = PathUtil.expand(target)
                let scan = localInventory(at: root, ignores: ignores)
                return Inventory(files: scan.files, description: root, truncated: scan.truncated)
            }
            throw RemoteBrowseError.commandFailed(
                "Preview isn’t available for this target type. Only local folders and SSH targets can be compared.")
        }
    }

    private static func capped(_ files: [PreviewFile], description: String) -> Inventory {
        guard files.count > fileLimit else {
            return Inventory(files: files, description: description, truncated: false)
        }
        return Inventory(files: Array(files.prefix(fileLimit)),
                         description: description, truncated: true)
    }

    /// Scan a local folder tree, skipping ignored paths and pruning ignored
    /// directories so huge trees like node_modules are not walked at all.
    static func localInventory(at root: String, ignores: IgnoreMatcher,
                               limit: Int = fileLimit) -> (files: [PreviewFile], truncated: Bool) {
        let rootURL = URL(fileURLWithPath: root)
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey,
                                         .fileSizeKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL, includingPropertiesForKeys: Array(keys),
            options: [], errorHandler: { _, _ in true }) else {
            return ([], false)
        }

        var files: [PreviewFile] = []
        var truncated = false
        for case let url as URL in enumerator {
            let relative = relativePath(of: url, root: rootURL)
            guard !relative.isEmpty else { continue }
            let values = try? url.resourceValues(forKeys: keys)
            if values?.isDirectory == true {
                if ignores.ignoresDirectory(relative) { enumerator.skipDescendants() }
                continue
            }
            guard values?.isRegularFile == true, !ignores.ignores(relative) else { continue }
            if files.count >= limit {
                truncated = true
                break
            }
            files.append(PreviewFile(
                path: relative,
                size: Int64(values?.fileSize ?? 0),
                modified: Int64((values?.contentModificationDate ?? Date(timeIntervalSince1970: 0))
                    .timeIntervalSince1970)))
        }
        return (files, truncated)
    }

    private static func relativePath(of url: URL, root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath) else { return "" }
        var relative = String(path.dropFirst(rootPath.count))
        if relative.hasPrefix("/") { relative.removeFirst() }
        return relative
    }
}
