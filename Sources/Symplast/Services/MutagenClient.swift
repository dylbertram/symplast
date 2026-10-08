import Foundation

struct CommandResult {
    let stdout: String
    let stderr: String
    let exitCode: Int32

    var succeeded: Bool { exitCode == 0 }

    var trimmedOutput: String {
        stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedError: String {
        stderr.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Mutagen sometimes writes human-readable errors to stdout.
    var bestMessage: String {
        if !trimmedError.isEmpty { return trimmedError }
        if !trimmedOutput.isEmpty { return trimmedOutput }
        return "mutagen exited with code \(exitCode)"
    }
}

/// Thread-safe collector for a process's stdout/stderr pipes.
private final class DataCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var _out = Data()
    private var _err = Data()

    var out: Data {
        get { lock.lock(); defer { lock.unlock() }; return _out }
        set { lock.lock(); _out = newValue; lock.unlock() }
    }

    var err: Data {
        get { lock.lock(); defer { lock.unlock() }; return _err }
        set { lock.lock(); _err = newValue; lock.unlock() }
    }

    func append(_ data: Data, isError: Bool, inspectAuthentication: Bool) -> String? {
        lock.lock()
        defer { lock.unlock() }
        if isError {
            _err.append(data)
            return inspectAuthentication ? String(decoding: _err, as: UTF8.self) : nil
        }
        _out.append(data)
        return inspectAuthentication ? String(decoding: _out, as: UTF8.self) : nil
    }
}

/// Record the first reason for stopping, shared by the readers and watchdog.
private final class ProcessStopReason: @unchecked Sendable {
    enum Reason {
        case timeout
        case authentication(String)
    }
    private let lock = NSLock()
    private var reason: Reason?

    var value: Reason? {
        lock.lock(); defer { lock.unlock() }; return reason
    }

    func set(_ value: Reason) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard reason == nil else { return false }
        reason = value
        return true
    }
}

enum MutagenError: LocalizedError {
    case executableNotFound
    case commandFailed(command: String, message: String)
    case timedOut(command: String, seconds: Int)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            return "Could not find the `mutagen` executable. Install it or set the path in Settings."
        case let .commandFailed(command, message):
            return "mutagen \(command) failed: \(message)"
        case let .timedOut(command, seconds):
            return "mutagen \(command) timed out after \(seconds)s."
        case let .decoding(message):
            return "Could not parse mutagen output: \(message)"
        }
    }
}

/// Thin wrapper around the `mutagen` command-line interface.
final class MutagenClient {
    private(set) var executableURL: URL

    init(executableURL: URL) {
        self.executableURL = executableURL
    }

    // MARK: - Executable discovery

    /// Locate the `mutagen` binary, in priority order:
    ///
    /// 1. An explicit user override from Settings.
    /// 2. A copy bundled inside the app (self-contained installs).
    /// 3. Common system install locations. A GUI app launched from Finder does
    ///    not inherit the shell PATH, so these are checked directly.
    /// 4. The login shell's PATH, as a last resort.
    static func resolveExecutable(override: String?) -> URL? {
        if let override, !override.trimmingCharacters(in: .whitespaces).isEmpty {
            let path = (override as NSString).expandingTildeInPath
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }

        if let bundled = bundledExecutableURL {
            return bundled
        }

        let home = NSHomeDirectory()
        let candidates = [
            "/opt/homebrew/bin/mutagen",
            "/usr/local/bin/mutagen",
            "\(home)/.local/bin/mutagen",
            "\(home)/bin/mutagen",
            "/usr/bin/mutagen"
        ]

        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return URL(fileURLWithPath: candidate)
        }

        if let found = findViaLoginShell() {
            return URL(fileURLWithPath: found)
        }
        return nil
    }

    /// A `mutagen` binary embedded in the app bundle, if this is a bundled
    /// build. Checked in `Contents/Resources` (where the build script puts it)
    /// and next to the executable for convenience.
    static var bundledExecutableURL: URL? {
        var candidates: [URL] = []
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent("mutagen"))
        }
        if let executable = Bundle.main.executableURL {
            candidates.append(executable.deletingLastPathComponent().appendingPathComponent("mutagen"))
        }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// Whether `url` is the copy bundled inside the app, rather than a
    /// system-wide installation.
    static func isBundled(_ url: URL) -> Bool {
        guard let bundled = bundledExecutableURL else { return false }
        return url.resolvingSymlinksInPath().path == bundled.resolvingSymlinksInPath().path
    }

    private static func findViaLoginShell() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "command -v mutagen"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let value = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    // MARK: - Process execution

    /// Stop interactive authentication as soon as it appears, rather than
    /// waiting for the watchdog while Mutagen retries an empty password.
    func run(_ arguments: [String], timeout: TimeInterval = 30) async throws -> CommandResult {
        let url = executableURL
        let commandLabel = arguments.prefix(2).joined(separator: " ")
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = url
            process.arguments = arguments
            process.environment = Self.childEnvironment

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe
            process.standardInput = FileHandle.nullDevice

            let collector = DataCollector()
            let group = DispatchGroup()
            let stopReason = ProcessStopReason()
            let handlesAuthentication = arguments.first == "sync"
                && arguments.dropFirst().first.map { ["create", "resume", "reset"].contains($0) } == true

            @Sendable func stopProcess(_ reason: ProcessStopReason.Reason) {
                guard process.isRunning, stopReason.set(reason) else { return }
                process.terminate()
                // A stuck CLI may ignore SIGTERM. Never leave its spinner up.
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5) {
                    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                }
            }

            for (pipe, isError) in [(outPipe, false), (errPipe, true)] {
                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    defer { group.leave() }
                    while true {
                        let data = pipe.fileHandleForReading.availableData
                        if data.isEmpty { break }
                        if let output = collector.append(data, isError: isError, inspectAuthentication: handlesAuthentication),
                           ErrorSummary.isAuthenticationFailure(output) {
                            stopProcess(.authentication(output))
                        }
                    }
                }
            }

            let watchdog = DispatchWorkItem {
                stopProcess(.timeout)
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: watchdog)

            process.terminationHandler = { finished in
                watchdog.cancel()
                // Descendants can inherit a pipe; they must not delay reporting
                // a failure after the CLI itself has already stopped.
                _ = group.wait(timeout: .now() + 0.5)
                switch stopReason.value {
                case .timeout:
                    continuation.resume(throwing: MutagenError.timedOut(
                        command: commandLabel, seconds: Int(timeout)))
                    return
                case let .authentication(message):
                    continuation.resume(throwing: MutagenError.commandFailed(
                        command: commandLabel, message: message.trimmingCharacters(in: .whitespacesAndNewlines)))
                    return
                case nil:
                    break
                }
                let result = CommandResult(
                    stdout: String(decoding: collector.out, as: UTF8.self),
                    stderr: String(decoding: collector.err, as: UTF8.self),
                    exitCode: finished.terminationStatus
                )
                continuation.resume(returning: result)
            }

            do {
                try process.run()
            } catch {
                watchdog.cancel()
                try? outPipe.fileHandleForWriting.close()
                try? errPipe.fileHandleForWriting.close()
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Commands

    func listSessions() async throws -> [MutagenSession] {
        let result = try await run(["sync", "list", "-l", "--template", "{{json .}}"])
        guard result.succeeded else {
            throw MutagenError.commandFailed(command: "sync list", message: result.bestMessage)
        }
        // An empty result may be a bare newline; normalize it.
        let normalized = result.trimmedOutput.isEmpty ? "[]" : result.stdout
        do {
            return try JSONDecoder().decode([MutagenSession].self, from: Data(normalized.utf8))
        } catch {
            throw MutagenError.decoding(String(describing: error))
        }
    }

    func ensureDaemon() async throws {
        _ = try await run(["daemon", "start"])
    }

    func pause(_ names: [String]) async throws { try await simple("pause", names) }
    func resume(_ names: [String]) async throws { try await simple("resume", names) }
    func terminate(_ names: [String]) async throws { try await simple("terminate", names) }
    func reset(_ names: [String]) async throws { try await simple("reset", names) }
    func flush(_ names: [String]) async throws {
        _ = try await run(["sync", "flush", "--skip-wait"] + names)
    }

    private func simple(_ verb: String, _ names: [String]) async throws {
        let result = try await run(["sync", verb] + names)
        guard result.succeeded else {
            throw MutagenError.commandFailed(command: "sync \(verb)", message: result.bestMessage)
        }
    }

    func create(_ definition: SavedSession) async throws {
        var arguments = ["sync", "create", definition.alpha, definition.beta]
        arguments += ["--name", definition.name, "--mode", definition.mode]
        if definition.ignoreVCS { arguments.append("--ignore-vcs") }
        for path in definition.ignorePaths {
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            arguments += ["--ignore", trimmed]
        }
        let result = try await run(arguments)
        guard result.succeeded else {
            throw MutagenError.commandFailed(command: "sync create", message: result.bestMessage)
        }
    }

    // MARK: - Environment

    /// Environment handed to Mutagen. Finder-launched apps have a minimal
    /// environment, so PATH, HOME and the SSH agent socket are set explicitly.
    static let childEnvironment: [String: String] = buildChildEnvironment()

    private static func buildChildEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let home = environment["HOME"] ?? NSHomeDirectory()
        environment["HOME"] = home

        let preferred = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(home)/.local/bin",
            "\(home)/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]
        let existing = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        var seen = Set<String>()
        var ordered: [String] = []
        for entry in preferred + existing where !seen.contains(entry) {
            seen.insert(entry)
            ordered.append(entry)
        }
        environment["PATH"] = ordered.joined(separator: ":")

        if environment["SSH_AUTH_SOCK"] == nil {
            // A Finder/Spotlight-launched app inherits launchd's system agent,
            // which usually holds no identities. The user's real agent (e.g.
            // Bitwarden, 1Password) is configured in their login shell, so ask
            // that first; fall back to launchd only if it has nothing usable.
            if let socket = loginShellEnvironmentVariable("SSH_AUTH_SOCK"),
               FileManager.default.fileExists(atPath: (socket as NSString).expandingTildeInPath) {
                environment["SSH_AUTH_SOCK"] = (socket as NSString).expandingTildeInPath
            } else if let socket = launchctlGetenv("SSH_AUTH_SOCK") {
                environment["SSH_AUTH_SOCK"] = socket
            }
        }
        return environment
    }

    /// Read an environment variable as the user's login shell sees it. GUI apps
    /// launched outside a terminal do not inherit these. Returns nil on failure.
    private static func loginShellEnvironmentVariable(_ key: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "printf %s \"$\(key)\""]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let value = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func launchctlGetenv(_ key: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["getenv", key]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let value = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
