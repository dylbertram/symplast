import XCTest
@testable import Symplast

final class ErrorHandlingTests: XCTestCase {
    private let authFailure = "mutagen sync create failed: unable to connect to beta: "
        + "unable to connect to endpoint: unable to dial agent endpoint: unable to handshake "
        + "with agent process: unable to receive server magic number: EOF (error output: "
        + "admin@192.168.20.20: Permission denied (publickey,keyboard-interactive).)"

    func testAuthFailureSummaryIsShort() {
        let summary = ErrorSummary.short(authFailure)
        XCTAssertLessThan(summary.count, 90, "summary should be short, got: \(summary)")
        XCTAssertTrue(summary.contains("authentication failed"))
        XCTAssertTrue(summary.contains("admin@192.168.20.20"))
        XCTAssertFalse(summary.contains("ssh-add"))
    }

    func testConnectionFailureDetection() {
        XCTAssertTrue(ErrorSummary.isConnectionFailure(authFailure))
        XCTAssertTrue(ErrorSummary.isConnectionFailure("unable to connect to beta: dial tcp: connection refused"))
        XCTAssertFalse(ErrorSummary.isConnectionFailure("unknown synchronization mode specification"))
    }

    func testStalledConnectingBecomesDisconnected() {
        let now = Date()
        XCTAssertEqual(SyncState.connecting.afterStall(notConnectedSince: now.addingTimeInterval(-11), now: now), .disconnected)
        XCTAssertEqual(SyncState.connecting.afterStall(notConnectedSince: now.addingTimeInterval(-3), now: now), .connecting)
        XCTAssertEqual(SyncState.connecting.afterStall(notConnectedSince: nil, now: now), .connecting)
        XCTAssertEqual(SyncState.watching.afterStall(notConnectedSince: now.addingTimeInterval(-99), now: now), .watching)
    }

    func testHostKeyFailureSummary() {
        let summary = ErrorSummary.short("unable to connect to beta: Host key verification failed.")
        XCTAssertTrue(summary.contains("host key"))
    }

    func testUnreachableHostSummary() {
        let summary = ErrorSummary.short("unable to dial: connection refused from deploy@host.example:22")
        XCTAssertTrue(summary.lowercased().contains("couldn't reach"))
    }

    func testTimeoutErrorIsShort() {
        let message = MutagenError.timedOut(command: "sync create", seconds: 30).errorDescription ?? ""
        XCTAssertEqual(message, "mutagen sync create timed out after 30s.")
    }

    func testTimeoutSummaryMentionsPassphrase() {
        let summary = ErrorSummary.short("mutagen sync create timed out after 30s.")
        XCTAssertTrue(summary.lowercased().contains("passphrase"))
    }

    func testRunTimesOutInsteadOfHanging() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("symplast-timeout-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let script = directory.appendingPathComponent("slow-mutagen")
        try "#!/bin/sh\nsleep 5\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let client = MutagenClient(executableURL: script)
        do {
            _ = try await client.run([], timeout: 0.5)
            XCTFail("Expected a timeout error")
        } catch let error as MutagenError {
            guard case .timedOut = error else {
                return XCTFail("Expected .timedOut, got \(error)")
            }
        }
    }

    func testAuthenticationPromptsAreRecognizedWithoutANewline() {
        for prompt in ["admin@host's password: ", "Enter passphrase for key '/Users/me/.ssh/id_ed25519': ",
                       "Password: ", "Password for admin@host: "] {
            XCTAssertTrue(ErrorSummary.isAuthenticationPrompt(prompt), prompt)
            XCTAssertTrue(ErrorSummary.isConnectionFailure(prompt), prompt)
            XCTAssertTrue(ErrorSummary.short(prompt).contains("SSH agent"))
        }
        XCTAssertFalse(ErrorSummary.isAuthenticationPrompt("Loading password-manager SSH agent"))
        XCTAssertFalse(ErrorSummary.isAuthenticationFailure("mkdir: Permission denied"))
    }

    func testPasswordPromptStopsImmediatelyEvenWhenSplitAcrossReads() async throws {
        let fixture = try makeExecutable("printf 'admin@host pass'; sleep 0.1; printf 'word: '; exec sleep 10")
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let start = Date()
        do {
            _ = try await MutagenClient(executableURL: fixture.script).run(["sync", "create"], timeout: 5)
            XCTFail("Expected authentication failure")
        } catch let error as MutagenError {
            guard case let .commandFailed(_, message) = error else {
                return XCTFail("Expected the prompt, not a timeout: \(error)")
            }
            XCTAssertTrue(message.contains("password:"))
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }

    func testAuthenticationFailureOnStderrStopsBeforeTimeout() async throws {
        let fixture = try makeExecutable("printf 'admin@host: Permission denied (publickey).\\n' >&2; exec sleep 10")
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let start = Date()
        do {
            _ = try await MutagenClient(executableURL: fixture.script).run(["sync", "resume"], timeout: 5)
            XCTFail("Expected authentication failure")
        } catch let error as MutagenError {
            guard case let .commandFailed(_, message) = error else { return XCTFail("Unexpected \(error)") }
            XCTAssertTrue(message.contains("Permission denied"))
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }

    func testWatchdogEscalatesWhenCommandIgnoresTermination() async throws {
        let fixture = try makeExecutable("trap '' TERM; while :; do :; done")
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let start = Date()
        do {
            _ = try await MutagenClient(executableURL: fixture.script).run([], timeout: 0.2)
            XCTFail("Expected timeout")
        } catch let error as MutagenError {
            guard case .timedOut = error else { return XCTFail("Unexpected \(error)") }
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }

    func testPassphrasePromptStopsImmediately() async throws {
        let fixture = try makeExecutable("printf \"Enter passphrase for key '/Users/me/.ssh/id_ed25519': \"; exec sleep 10")
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let start = Date()
        do {
            _ = try await MutagenClient(executableURL: fixture.script).run(["sync", "reset"], timeout: 5)
            XCTFail("Expected authentication failure")
        } catch let error as MutagenError {
            guard case let .commandFailed(_, message) = error else { return XCTFail("Unexpected \(error)") }
            XCTAssertTrue(message.contains("passphrase"))
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }

    func testListDoesNotAbortWhenJSONContainsAnAuthenticationError() async throws {
        let json = try sessionJSON(id: "failed", error: "admin@host: Permission denied (publickey).")
        let fixture = try makeExecutable("echo '[\(json)]'")
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let sessions = try await MutagenClient(executableURL: fixture.script).listSessions()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].state, .disconnected)
    }

    @MainActor
    func testRefreshStopsOnlyFailedAuthenticationAndKeepsAllStatusesInSync() async throws {
        let failed = try sessionJSON(id: "failed", error: "admin@host: Permission denied (publickey).")
        let paused = try sessionJSON(id: "failed", paused: true)
        let healthy = try sessionJSON(id: "healthy", connected: true)
        let connecting = try sessionJSON(id: "connecting")
        let fixture = try makeExecutable("""
        case "$2" in
          list)
            if [ -f "$directory/paused" ]; then
              echo '[\(paused),\(healthy),\(connecting)]'
            else
              echo '[\(failed),\(healthy),\(connecting)]'
            fi ;;
          pause) touch "$directory/paused" ;;
        esac
        """)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let (store, defaults, suite) = try makeStore(script: fixture.script)
        defer { defaults.removePersistentDomain(forName: suite) }

        await store.refreshNow()
        let failedSession = try XCTUnwrap(store.sessions.first { $0.id == "failed" })
        XCTAssertTrue(failedSession.isPaused, "The daemon must actually stop retrying")
        XCTAssertEqual(store.state(for: failedSession), .disconnected)
        XCTAssertEqual(store.disconnectedCount, 1)
        XCTAssertEqual(store.worstState, .error)
        XCTAssertTrue(store.daemonAvailable)
        XCTAssertFalse(store.isRefreshing)
        XCTAssertFalse(store.isManualRefreshing)
        XCTAssertTrue(store.busySessionIDs.isEmpty)
        XCTAssertEqual(store.state(for: try XCTUnwrap(store.sessions.first { $0.id == "healthy" })), .watching)
        XCTAssertEqual(store.state(for: try XCTUnwrap(store.sessions.first { $0.id == "connecting" })), .connecting)
        let error = try XCTUnwrap(store.lastError)
        await store.refresh()
        XCTAssertEqual(store.lastError, error)
        let commands = try String(contentsOf: fixture.directory.appendingPathComponent("commands"))
        XCTAssertEqual(commands.components(separatedBy: "sync pause failed").count - 1, 1)
        store.dismissError()
        XCTAssertEqual(store.worstState, .disconnected, "Dismissing a banner must not hide the session failure")
    }

    @MainActor
    func testFailedCreateCleansUpOnlyNewSessionAndRefreshesImmediately() async throws {
        let existing = try sessionJSON(id: "existing", name: "project", connected: true)
        let created = try sessionJSON(id: "created", name: "project")
        let fixture = try makeExecutable("""
        case "$2" in
          list)
            if [ -f "$directory/created" ]; then echo '[\(existing),\(created)]'; else echo '[\(existing)]'; fi ;;
          create) touch "$directory/created"; printf 'admin@host password: '; exec sleep 10 ;;
          terminate) rm "$directory/created" ;;
        esac
        """)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let (store, defaults, suite) = try makeStore(script: fixture.script)
        defer { defaults.removePersistentDomain(forName: suite) }
        let definition = SavedSession(name: "project", alpha: "/local", beta: "admin@host:/remote",
                                      mode: "two-way-safe", ignorePaths: [], ignoreVCS: true)
        let succeeded = await store.createSession(definition)
        XCTAssertFalse(succeeded)
        XCTAssertEqual(store.sessions.map(\.id), ["existing"])
        XCTAssertEqual(store.worstState, .error)
        XCTAssertNotNil(store.lastError)
        XCTAssertFalse(store.isRefreshing)
        let commands = try String(contentsOf: fixture.directory.appendingPathComponent("commands"))
        XCTAssertTrue(commands.contains("sync terminate created"))
        XCTAssertFalse(commands.contains("sync terminate project"))
        XCTAssertFalse(commands.contains("sync terminate existing"))
    }

    @MainActor
    func testFailedResumeStopsRetriesAndClearsBusyStateThenCanRetry() async throws {
        let paused = try sessionJSON(id: "session", paused: true)
        let connecting = try sessionJSON(id: "session")
        let healthy = try sessionJSON(id: "session", connected: true)
        let fixture = try makeExecutable("""
        case "$2" in
          list)
            if [ -f "$directory/healthy" ]; then echo '[\(healthy)]'
            elif [ -f "$directory/connecting" ]; then echo '[\(connecting)]'
            else echo '[\(paused)]'; fi ;;
          resume)
            if [ -f "$directory/retry" ]; then touch "$directory/healthy"
            else touch "$directory/connecting"; printf 'admin@host password: '; exec sleep 10; fi ;;
          pause) rm -f "$directory/connecting" ;;
        esac
        """)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let (store, defaults, suite) = try makeStore(script: fixture.script)
        defer { defaults.removePersistentDomain(forName: suite) }
        await store.refresh()
        store.togglePause(try XCTUnwrap(store.sessions.first))
        try await waitUntilIdle(store)
        XCTAssertTrue(try XCTUnwrap(store.sessions.first).isPaused)
        XCTAssertEqual(store.state(for: try XCTUnwrap(store.sessions.first)), .disconnected)
        XCTAssertEqual(store.disconnectedCount, 1)
        XCTAssertTrue(store.daemonAvailable)
        XCTAssertNotNil(store.lastError)
        XCTAssertTrue(store.busySessionIDs.isEmpty)
        try Data().write(to: fixture.directory.appendingPathComponent("retry"))
        store.togglePause(try XCTUnwrap(store.sessions.first))
        try await waitUntilIdle(store)
        XCTAssertEqual(store.state(for: try XCTUnwrap(store.sessions.first)), .watching)
        XCTAssertEqual(store.worstState, .watching)
        XCTAssertEqual(store.disconnectedCount, 0)
        XCTAssertTrue(store.connectionErrors.isEmpty)
        XCTAssertNil(store.lastError)
    }

    @MainActor
    func testFailedSavedStartClearsSpinnerAndRetainsDefinition() async throws {
        let fixture = try makeExecutable("""
        case "$2" in
          list) echo '[]' ;;
          create) printf 'admin@host password: '; exec sleep 10 ;;
        esac
        """)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let definition = SavedSession(name: "project", alpha: "/local", beta: "admin@host:/remote",
                                      mode: "two-way-safe", ignorePaths: [], ignoreVCS: true)
        let (store, defaults, suite) = try makeStore(script: fixture.script, saved: [definition])
        defer { defaults.removePersistentDomain(forName: suite) }
        store.start(definition)
        let deadline = Date().addingTimeInterval(3)
        while !store.startingDefinitionNames.isEmpty && Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(store.startingDefinitionNames.isEmpty)
        XCTAssertEqual(store.stoppedDefinitions.map(\.name), ["project"])
        XCTAssertEqual(store.worstState, .error)
        XCTAssertNotNil(store.lastError)
        XCTAssertFalse(store.isRefreshing)
    }

    @MainActor
    private func waitUntilIdle(_ store: AppStore) async throws {
        let deadline = Date().addingTimeInterval(3)
        while !store.busySessionIDs.isEmpty && Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(store.busySessionIDs.isEmpty, "Session action must finish promptly")
    }

    func testSessionLastErrorOverridesConnectingButNotHealthyOrPaused() throws {
        for (connected, paused, expected) in [(false, false, SyncState.disconnected),
                                               (true, false, .watching), (false, true, .paused)] {
            let json = try sessionJSON(id: "test", connected: connected, paused: paused,
                                       error: "unable to connect: Permission denied (publickey).")
            let session = try JSONDecoder().decode(MutagenSession.self, from: Data(json.utf8))
            XCTAssertEqual(session.state, expected)
        }
    }

    private func makeExecutable(_ body: String) throws -> (directory: URL, script: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("opencode/symplast-errors-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let script = directory.appendingPathComponent("mutagen")
        try "#!/bin/sh\ndirectory=\"$(dirname \"$0\")\"\necho \"$*\" >> \"$directory/commands\"\n\(body)\n"
            .write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return (directory, script)
    }

    @MainActor
    private func makeStore(script: URL, saved: [SavedSession] = []) throws -> (AppStore, UserDefaults, String) {
        let suite = "Symplast.ErrorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        var settings = AppSettings()
        settings.mutagenPath = script.path
        defaults.set(try JSONEncoder().encode(settings), forKey: "symplast.settings")
        defaults.set(try JSONEncoder().encode(saved), forKey: "symplast.savedSessions")
        return (AppStore(defaults: defaults), defaults, suite)
    }

    private func sessionJSON(id: String, name: String? = nil, connected: Bool = false,
                             paused: Bool = false, error: String? = nil) throws -> String {
        var value: [String: Any] = [
            "identifier": id, "name": name ?? id, "paused": paused,
            "status": connected ? "Watching for changes" : "Connecting to beta",
            "alpha": ["protocol": "local", "path": "/local", "connected": true],
            "beta": ["protocol": "ssh", "user": "admin", "host": "host", "path": "/remote", "connected": connected],
            "ignore": ["paths": [String]()]
        ]
        if let error { value["lastError"] = error }
        return String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), as: UTF8.self)
    }
}
