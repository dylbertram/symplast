import Foundation
import SwiftUI

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var sessions: [MutagenSession] = []
    @Published private(set) var saved: [SavedSession] = []
    @Published private(set) var daemonAvailable = true
    @Published private(set) var isRefreshing = false
    @Published private(set) var isManualRefreshing = false
    @Published private(set) var versionCheckStatus: VersionCheckStatus = .notChecked
    @Published private(set) var busySessionIDs: Set<String> = []
    @Published private(set) var startingDefinitionNames: Set<String> = []
    /// Retain the reason after pausing: Mutagen omits lastError for paused sessions.
    @Published private(set) var connectionErrors: [String: String] = [:]
    @Published var lastError: String?
    @Published var route: PanelRoute = .list
    @Published var draft = NewSessionDraft()
    @Published private(set) var editingOriginalName: String?
    @Published var settings: AppSettings {
        didSet { persistSettings() }
    }

    private var client: MutagenClient?
    private var pollTask: Task<Void, Never>?
    private let defaults: UserDefaults

    private let savedKey = "symplast.savedSessions"
    private let settingsKey = "symplast.settings"

    /// True when `lastError` came from a user action (create/start/pause/…)
    /// rather than a background poll. Action errors stay on screen until the
    /// user dismisses them, so they don't flash away on the next refresh.
    private var lastErrorIsAction = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.settings = Self.loadSettings(key: settingsKey, defaults: defaults)
        self.saved = Self.loadSaved(key: savedKey, defaults: defaults)
        self.client = Self.makeClient(settings: settings)
    }

    // MARK: - Lifecycle

    func start() {
        guard pollTask == nil else { return }
        Task { await checkForUpdates() }
        pollTask = Task { [weak self] in
            guard let self else { return }
            if self.settings.autoEnsureDaemon {
                try? await self.client?.ensureDaemon()
            }
            await self.pollLoop()
        }
    }

    func checkForUpdates() async {
        guard versionCheckStatus != .checking else { return }
        versionCheckStatus = .checking
        do {
            if let update = try await VersionChecker.check(currentVersion: appVersionNumber) {
                versionCheckStatus = .updateAvailable(update)
            } else {
                versionCheckStatus = .upToDate
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            versionCheckStatus = .failed(message)
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func pollLoop() async {
        while !Task.isCancelled {
            await refresh()
            let interval = max(0.5, settings.pollInterval)
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
    }

    // MARK: - Derived state

    /// When each unconnected session was first seen unconnected, so the UI can
    /// stop reporting "Connecting" once a connection attempt has clearly failed.
    private var notConnectedSince: [String: Date] = [:]

    /// How long a session may stay unconnected before it is reported as
    /// disconnected. A connection/auth error short-circuits this grace.
    private let connectGrace: TimeInterval = 10

    /// Mutagen's own status, adjusted for sessions stuck retrying a connection.
    func state(for session: MutagenSession) -> SyncState {
        if connectionErrors[session.id] != nil { return .disconnected }
        return session.state.afterStall(notConnectedSince: notConnectedSince[session.id],
                                 grace: connectGrace)
    }

    /// The most "alerting" state across all sessions, for the menu bar icon.
    var worstState: SyncState {
        if !daemonAvailable { return .error }
        if lastErrorIsAction, let lastError, ErrorSummary.isConnectionFailure(lastError) { return .error }
        if sessions.isEmpty { return .idle }
        let states = sessions.map(state(for:))
        if states.contains(where: { $0 == .error || $0 == .disconnected }) {
            return .disconnected
        }
        if states.contains(.connecting) { return .connecting }
        if states.contains(where: { $0 == .syncing || $0 == .scanning }) {
            return .syncing
        }
        if states.allSatisfy({ $0 == .paused }) { return .paused }
        if states.contains(.watching) { return .watching }
        return .idle
    }

    /// Saved definitions that do not currently have a live session.
    var stoppedDefinitions: [SavedSession] {
        let liveNames = Set(sessions.map(\.name))
        return saved.filter { !liveNames.contains($0.name) }
    }

    var disconnectedCount: Int {
        sessions.filter {
            let state = state(for: $0)
            return state == .disconnected || state == .error
        }.count
    }

    var detectedExecutablePath: String {
        client?.executableURL.path ?? "not found"
    }

    /// The SSH agent socket Mutagen will use, for the Settings readout.
    var sshAgentSocket: String {
        MutagenClient.childEnvironment["SSH_AUTH_SOCK"] ?? "none"
    }

    /// Whether the resolved `mutagen` binary came from inside this app bundle
    /// (a self-contained build) rather than a system-wide installation.
    var isUsingBundledExecutable: Bool {
        guard let client else { return false }
        return MutagenClient.isBundled(client.executableURL)
    }

    /// Marketing version from the bundle, for the About section.
    var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = info?["CFBundleVersion"] as? String
        if let build, build != short { return "\(short) (\(build))" }
        return short
    }

    private var appVersionNumber: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }

    func isBusy(_ session: MutagenSession) -> Bool {
        busySessionIDs.contains(session.id)
    }

    #if DEBUG
    /// Test/preview hook: inject sessions without touching the daemon.
    func setPreviewSessions(_ value: [MutagenSession], saved: [SavedSession] = [],
                            daemonAvailable: Bool = true, executableMissing: Bool = false) {
        sessions = value
        self.saved = saved
        self.daemonAvailable = daemonAvailable
        if executableMissing { client = nil }
    }
    #endif

    // MARK: - Refresh

    /// Refresh on behalf of a user action. Only this path shows a spinner, so
    /// the background poll does not flash the header every few seconds.
    func refreshNow() async {
        isManualRefreshing = true
        defer { isManualRefreshing = false }
        await refresh()
    }

    func refresh() async {
        guard let client else {
            daemonAvailable = false
            reportError(MutagenError.executableNotFound.errorDescription ?? "Mutagen not found", isAction: false)
            return
        }
        if isRefreshing { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let list = try await client.listSessions()
            sessions = list.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            daemonAvailable = true
            updateNotConnectedSince(list)
            connectionErrors = connectionErrors.filter { id, _ in
                list.contains { $0.id == id && !$0.isConnected }
            }
            // Keep an action error visible until the user dismisses it; only
            // clear errors that the poll itself raised.
            if !lastErrorIsAction { lastError = nil }
            syncSavedDefinitions(from: list)
            await stopFailedAuthentication(in: list, client: client)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            let lower = message.lowercased()
            if lower.contains("daemon") || lower.contains("connect") || lower.contains("unable") {
                daemonAvailable = false
            }
            reportError(message, isAction: false)
        }
    }

    // MARK: - Error reporting

    func dismissError() {
        lastError = nil
        lastErrorIsAction = false
    }

    /// Track how long each unconnected session has been unconnected. Reset when
    /// a session connects, so a healthy reconnect clears the stall.
    private func updateNotConnectedSince(_ list: [MutagenSession]) {
        let now = Date()
        var updated: [String: Date] = [:]
        for session in list where !session.isConnected && !session.isPaused {
            updated[session.id] = notConnectedSince[session.id] ?? now
        }
        notConnectedSince = updated
    }

    private func reportError(_ message: String?, isAction: Bool) {
        // A poll must not overwrite a useful action error or clear its sticky flag.
        guard isAction || !lastErrorIsAction else { return }
        lastError = message
        lastErrorIsAction = isAction
    }

    /// Unlike a transient network outage, failed credentials need user attention,
    /// not indefinite retries by the daemon. Pause only the affected sessions.
    private func stopFailedAuthentication(in list: [MutagenSession], client: MutagenClient) async {
        let failed = list.filter {
            !$0.isPaused && !$0.isConnected
                && ($0.alpha.protocolName == "ssh" || $0.beta.protocolName == "ssh")
                && !busySessionIDs.contains($0.id) && !startingDefinitionNames.contains($0.name)
                && $0.lastError.map(ErrorSummary.isAuthenticationFailure) == true
        }
        guard !failed.isEmpty else { return }
        for session in failed {
            let message = session.lastError ?? "SSH authentication failed."
            if connectionErrors[session.id] == nil {
                reportError(message, isAction: true)
            }
            connectionErrors[session.id] = message
        }
        do {
            try await client.pause(failed.map(\.id))
            sessions = try await client.listSessions().sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        } catch {
            reportError("\(failed[0].lastError ?? "SSH authentication failed.")\nCould not stop the session: \(errorMessage(error))",
                        isAction: true)
        }
    }

    /// Automatically remember any live session we have not seen before, so it
    /// can always be restarted after being terminated.
    private func syncSavedDefinitions(from list: [MutagenSession]) {
        var changed = false
        for session in list where !saved.contains(where: { $0.name == session.name }) {
            saved.append(SavedSession(from: session))
            changed = true
        }
        if changed { persistSaved() }
    }

    // MARK: - Session actions

    func togglePause(_ session: MutagenSession) {
        guard !busySessionIDs.contains(session.id) else { return }
        let verb = session.isPaused ? "resume" : "pause"
        connectionErrors.removeValue(forKey: session.id)
        perform(on: session) { client in
            if verb == "resume" {
                self.dismissError()
                try await client.resume([session.name])
            } else {
                try await client.pause([session.name])
            }
        }
    }

    func flush(_ session: MutagenSession) {
        perform(on: session) { client in
            try await client.flush([session.name])
        }
    }

    func terminate(_ session: MutagenSession) {
        perform(on: session) { client in
            try await client.terminate([session.name])
        }
    }

    func reset(_ session: MutagenSession) {
        perform(on: session) { client in
            try await client.reset([session.name])
        }
    }

    private func perform(
        on session: MutagenSession,
        _ body: @escaping (MutagenClient) async throws -> Void
    ) {
        guard !busySessionIDs.contains(session.id) else { return }
        guard let client else {
            reportError(MutagenError.executableNotFound.errorDescription, isAction: true)
            return
        }
        busySessionIDs.insert(session.id)
        Task {
            defer { busySessionIDs.remove(session.id) }
            do {
                try await body(client)
                await refresh()
            } catch {
                let message = errorMessage(error)
                reportError(message, isAction: true)
                if ErrorSummary.isConnectionFailure(message) {
                    connectionErrors[session.id] = message
                    // resume/reset can leave a registered session reconnecting
                    // even after their CLI prompt host has exited.
                    do {
                        try await client.pause([session.id])
                    } catch {
                        reportError("\(message)\nCould not stop the session: \(errorMessage(error))", isAction: true)
                    }
                }
                await refresh()
            }
        }
    }

    // MARK: - Create / start / edit / remove definitions

    /// Create (and start) a new Mutagen session, remembering the definition.
    func createSession(_ definition: SavedSession) async -> Bool {
        do {
            try await create(definition)
            return true
        } catch {
            reportError(errorMessage(error), isAction: true)
            return false
        }
    }

    private func create(_ definition: SavedSession) async throws {
        guard let client else { throw MutagenError.executableNotFound }
        dismissError()
        let previousIDs = Set(try await client.listSessions().map(\.id))
        do {
            try await client.create(definition)
        } catch {
            reportError(errorMessage(error), isAction: true)
            var failure: Error = error
            // Mutagen can register the session before the initial connection
            // fails. Make sure a failed create doesn't leave it retrying in the
            // background, which otherwise looks like the app "keeps trying".
            // Never terminate an existing session just because its name matches
            // a failed create (e.g. a duplicate-name error).
            do {
                let list = try await client.listSessions()
                let createdIDs = list.filter { $0.name == definition.name && !previousIDs.contains($0.id) }.map(\.id)
                if !createdIDs.isEmpty { try await client.terminate(createdIDs) }
            } catch let cleanupError {
                failure = MutagenError.commandFailed(command: "sync create",
                    message: "\(errorMessage(error))\nCould not verify or stop the failed session: \(errorMessage(cleanupError))")
                reportError(errorMessage(failure), isAction: true)
            }
            await refresh()
            throw failure
        }
        if let index = saved.firstIndex(where: { $0.name == definition.name }) {
            saved[index] = definition
        } else {
            saved.append(definition)
        }
        persistSaved()
        await refresh()
    }

    /// Start a saved definition that has no live session by re-creating it.
    func start(_ definition: SavedSession) {
        guard !startingDefinitionNames.contains(definition.name) else { return }
        startingDefinitionNames.insert(definition.name)
        Task {
            defer { startingDefinitionNames.remove(definition.name) }
            _ = await createSession(definition)
        }
    }

    func forget(_ definition: SavedSession) {
        saved.removeAll { $0.name == definition.name }
        persistSaved()
    }

    // MARK: - New / edit form

    func beginNewSession() {
        draft = NewSessionDraft()
        editingOriginalName = nil
        route = .newSession
    }

    func beginEdit(_ definition: SavedSession) {
        draft = NewSessionDraft(from: definition)
        editingOriginalName = definition.name
        route = .newSession
    }

    func beginEdit(_ session: MutagenSession) {
        let definition = saved.first { $0.name == session.name } ?? SavedSession(from: session)
        beginEdit(definition)
    }

    func cancelForm() {
        editingOriginalName = nil
        route = .list
    }

    /// Create or update the session described by `draft`.
    func saveDraft() async -> Bool {
        let definition = draft.toSavedSession()
        guard let client else {
            reportError(MutagenError.executableNotFound.errorDescription, isAction: true)
            return false
        }
        do {
            if let original = editingOriginalName {
                let renamed = original != definition.name
                // Mutagen has no in-place edit: terminate the existing session
                // (same name or renamed) before recreating it.
                if sessions.contains(where: { $0.name == original }) {
                    try await client.terminate([original])
                }
                if renamed {
                    saved.removeAll { $0.name == original }
                    persistSaved()
                }
            }
            try await create(definition)
            editingOriginalName = nil
            route = .list
            return true
        } catch {
            reportError(errorMessage(error), isAction: true)
            return false
        }
    }

    private func errorMessage(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }

    // MARK: - Daemon

    func startDaemon() {
        Task {
            do {
                try await client?.ensureDaemon()
                await refresh()
            } catch {
                reportError(errorMessage(error), isAction: true)
            }
        }
    }

    // MARK: - Settings

    func applySettingsChange() {
        client = Self.makeClient(settings: settings)
        Task { await refresh() }
    }

    // MARK: - Persistence helpers

    private func persistSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: settingsKey)
        }
    }

    private func persistSaved() {
        let sorted = saved.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if let data = try? JSONEncoder().encode(sorted) {
            defaults.set(data, forKey: savedKey)
        }
    }

    private static func loadSettings(key: String, defaults: UserDefaults) -> AppSettings {
        guard let data = defaults.data(forKey: key),
              let value = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return value
    }

    private static func loadSaved(key: String, defaults: UserDefaults) -> [SavedSession] {
        guard let data = defaults.data(forKey: key),
              let value = try? JSONDecoder().decode([SavedSession].self, from: data) else {
            return []
        }
        return value
    }

    private static func makeClient(settings: AppSettings) -> MutagenClient? {
        guard let url = MutagenClient.resolveExecutable(override: settings.mutagenPath) else {
            return nil
        }
        return MutagenClient(executableURL: url)
    }
}
