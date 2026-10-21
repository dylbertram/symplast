import Foundation

/// The folders directly inside one directory on an SSH remote.
struct RemoteListing: Equatable {
    /// Absolute path of the listed directory, as the remote reported it.
    var path: String
    /// Absolute paths of the folders directly inside it, sorted by name.
    var directories: [String]

    /// Folder names, in the same order as `directories`.
    var names: [String] { directories.map { ($0 as NSString).lastPathComponent } }

    /// Parse the output of `listScript(for:)`: the first line is the absolute
    /// path of the listed directory, the rest are `find` results relative to it.
    static func parse(_ output: String) -> RemoteListing? {
        var lines = output.split(whereSeparator: \.isNewline).map(String.init)
        guard !lines.isEmpty else { return nil }
        let base = lines.removeFirst().trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty else { return nil }
        var directories: [String] = []
        for line in lines {
            var name = line.trimmingCharacters(in: .whitespaces)
            // `find . …` prints the root as "." and each folder as "./name".
            guard name.hasPrefix("./") else { continue }
            name.removeFirst(2)
            guard !name.isEmpty, !name.contains("/") else { continue }
            directories.append((base as NSString).appendingPathComponent(name))
        }
        directories.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return RemoteListing(path: base, directories: directories)
    }

    /// The remote shell snippet that prints the listing: the absolute path of
    /// the directory first, then its subdirectories. `find` prunes every
    /// directory it prints, so only the top level is listed, and it works the
    /// same on BSD and GNU find.
    static func listScript(for path: String) -> String {
        let quoted = shellQuote(path)
        return "p=\(quoted); "
            + "case \"$p\" in \"~\") p=\"$HOME\";; \"~/\"*) p=\"$HOME${p#\\~}\";; esac; "
            + "[ -n \"$p\" ] || p=\"$HOME\"; "
            + "p=\"${p%/}\"; [ -n \"$p\" ] || p=\"/\"; "
            + "cd \"$p\" 2>/dev/null || { printf 'symplast: cannot access %s\\n' \"$p\" >&2; exit 2; }; "
            + "pwd; find . -type d -prune -print 2>/dev/null | LC_ALL=C sort"
    }

    /// Quote a value for the remote shell. Paths are only ever quoted into the
    /// script, never concatenated unescaped.
    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// The files inside one directory tree on an SSH remote, for the sync preview.
enum RemoteInventory {
    /// Parse the output of `script(for:)`: one `relative path\tsize\tmtime`
    /// line per file.
    static func parse(_ output: String) -> [PreviewFile] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 3,
                  let size = Int64(fields[1]),
                  let modified = Double(fields[2]) else { return nil }
            var path = fields[0]
            if path.hasPrefix("./") { path.removeFirst(2) }
            guard !path.isEmpty else { return nil }
            return PreviewFile(path: path, size: size, modified: Int64(modified))
        }
    }

    /// The remote shell snippet that prints the inventory. `stat` differs
    /// between GNU and BSD systems, so both spellings are supported; `%T@`
    /// prints fractional seconds and BSD's `%m` whole seconds, and comparison
    /// happens in whole seconds either way.
    static func script(for path: String) -> String {
        let quoted = RemoteListing.shellQuote(path)
        return "p=\(quoted); "
            + "case \"$p\" in \"~\") p=\"$HOME\";; \"~/\"*) p=\"$HOME${p#\\~}\";; esac; "
            + "[ -n \"$p\" ] || p=\"$HOME\"; "
            + "p=\"${p%/}\"; [ -n \"$p\" ] || p=\"/\"; "
            + "cd \"$p\" 2>/dev/null || { printf 'symplast: cannot access %s\\n' \"$p\" >&2; exit 2; }; "
            + "if stat -c '%s' . >/dev/null 2>&1; then "
            + "find . -type f -printf '%P\\t%s\\t%T@\\n' 2>/dev/null; "
            + "else find . -type f -exec stat -f '%N\\t%z\\t%m' {} + 2>/dev/null; fi"
    }
}

enum RemoteBrowseError: LocalizedError {
    case timedOut
    case inaccessible(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .timedOut:
            return "Timed out reaching the server. Check the host and SSH configuration."
        case let .inaccessible(path):
            return "The server can’t open \(path.isEmpty ? "that folder" : path). Check the path and permissions."
        case let .commandFailed(message):
            return ErrorSummary.short(message)
        }
    }
}

/// Non-interactive SSH helper for browsing folders on a remote. Every request
/// runs one short command in batch mode, so it can never stall on a password or
/// host-key prompt — it fails fast and the UI explains what is missing (key in
/// the SSH agent, trusted host key, reachable host).
struct SSHRemoteClient {
    var executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
    var user: String
    var host: String
    var port: String = ""
    var timeout: TimeInterval = 20

    /// Destination in `user@host` form, or just `host` when no user is set.
    var destination: String {
        let user = user.trimmingCharacters(in: .whitespaces)
        let host = host.trimmingCharacters(in: .whitespaces)
        return user.isEmpty ? host : "\(user)@\(host)"
    }

    /// List the folders inside `path` on the remote. An empty path means the
    /// remote home directory.
    func list(at path: String) async throws -> RemoteListing {
        let result = try await execute(script: RemoteListing.listScript(for: path), inaccessiblePath: path)
        guard let listing = RemoteListing.parse(result.stdout) else {
            throw RemoteBrowseError.commandFailed("The server returned no folder listing.")
        }
        return listing
    }

    /// Inventory the files under `path` on the remote, for the sync preview.
    func inventory(at path: String) async throws -> [PreviewFile] {
        let result = try await execute(script: RemoteInventory.script(for: path), inaccessiblePath: path)
        return RemoteInventory.parse(result.stdout)
    }

    private func execute(script: String, inaccessiblePath: String) async throws -> CommandResult {
        var arguments = ["-o", "BatchMode=yes", "-o", "ConnectTimeout=8",
                         "-o", "StrictHostKeyChecking=accept-new"]
        let port = port.trimmingCharacters(in: .whitespaces)
        if !port.isEmpty { arguments += ["-p", port] }
        arguments.append(destination)
        arguments.append(script)

        let result = try await run(arguments)
        if result.succeeded { return result }
        let message = result.trimmedError.isEmpty ? result.trimmedOutput : result.trimmedError
        if message.contains("symplast: cannot access") {
            throw RemoteBrowseError.inaccessible(inaccessiblePath.trimmingCharacters(in: .whitespaces))
        }
        throw RemoteBrowseError.commandFailed(message)
    }

    // MARK: - Process execution

    private func run(_ arguments: [String]) async throws -> CommandResult {
        let url = executableURL
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = url
            process.arguments = arguments
            process.environment = MutagenClient.childEnvironment
            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe
            process.standardInput = FileHandle.nullDevice

            let collector = DataCollector()
            let group = DispatchGroup()
            for (pipe, isError) in [(outPipe, false), (errPipe, true)] {
                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    defer { group.leave() }
                    while true {
                        let data = pipe.fileHandleForReading.availableData
                        if data.isEmpty { break }
                        _ = collector.append(data, isError: isError, inspectAuthentication: false)
                    }
                }
            }

            let timedOut = TimeoutFlag()
            let watchdog = DispatchWorkItem {
                if timedOut.set(), process.isRunning { process.terminate() }
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: watchdog)

            process.terminationHandler = { finished in
                watchdog.cancel()
                _ = group.wait(timeout: .now() + 1)
                if timedOut.isSet {
                    continuation.resume(throwing: RemoteBrowseError.timedOut)
                    return
                }
                continuation.resume(returning: CommandResult(
                    stdout: String(decoding: collector.out, as: UTF8.self),
                    stderr: String(decoding: collector.err, as: UTF8.self),
                    exitCode: finished.terminationStatus))
            }

            do {
                try process.run()
            } catch {
                watchdog.cancel()
                try? outPipe.fileHandleForWriting.close()
                try? errPipe.fileHandleForWriting.close()
                continuation.resume(throwing: RemoteBrowseError.commandFailed(error.localizedDescription))
            }
        }
    }
}

/// Records that the watchdog fired, shared with the termination handler.
private final class TimeoutFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    /// Returns true the first time it is set.
    func set() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !value else { return false }
        value = true
        return true
    }
}
