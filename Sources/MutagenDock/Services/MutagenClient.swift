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
}

enum MutagenError: LocalizedError {
    case executableNotFound
    case commandFailed(command: String, message: String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            return "Could not find the `mutagen` executable. Install it or set the path in Settings."
        case let .commandFailed(command, message):
            return "mutagen \(command) failed: \(message)"
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

    /// Locate the `mutagen` binary. A GUI app launched from Finder does not
    /// inherit the shell PATH, so common install locations are checked directly.
    static func resolveExecutable(override: String?) -> URL? {
        var candidates: [String] = []
        if let override, !override.trimmingCharacters(in: .whitespaces).isEmpty {
            candidates.append((override as NSString).expandingTildeInPath)
        }
        let home = NSHomeDirectory()
        candidates += [
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

    func run(_ arguments: [String]) async throws -> CommandResult {
        let url = executableURL
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

            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                collector.out = outPipe.fileHandleForReading.readDataToEndOfFile()
                group.leave()
            }
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                collector.err = errPipe.fileHandleForReading.readDataToEndOfFile()
                group.leave()
            }

            process.terminationHandler = { finished in
                group.wait()
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
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Commands

    func listSessions() async throws -> [MutagenSession] {
        let result = try await run(["sync", "list", "--template", "{{json .}}"])
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

        if environment["SSH_AUTH_SOCK"] == nil, let socket = launchctlGetenv("SSH_AUTH_SOCK") {
            environment["SSH_AUTH_SOCK"] = socket
        }
        return environment
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
