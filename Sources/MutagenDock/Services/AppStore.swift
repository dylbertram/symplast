import Foundation
import SwiftUI

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var sessions: [MutagenSession] = []
    @Published private(set) var saved: [SavedSession] = []
    @Published private(set) var daemonAvailable = true
    @Published private(set) var isRefreshing = false
    @Published private(set) var busySessionIDs: Set<String> = []
    @Published var lastError: String?
    @Published var route: PanelRoute = .list
    @Published var draft = NewSessionDraft()
    @Published private(set) var editingOriginalName: String?
    @Published var settings: AppSettings {
        didSet { persistSettings() }
    }

    private var client: MutagenClient?
    private var pollTask: Task<Void, Never>?

    private let savedKey = "mutagenDock.savedSessions"
    private let settingsKey = "mutagenDock.settings"

    init() {
        self.settings = Self.loadSettings(key: settingsKey)
        self.saved = Self.loadSaved(key: savedKey)
        self.client = Self.makeClient(settings: settings)
    }

    // MARK: - Lifecycle

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            guard let self else { return }
            if self.settings.autoEnsureDaemon {
                try? await self.client?.ensureDaemon()
            }
            await self.pollLoop()
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

    /// The most "alerting" state across all sessions, for the menu bar icon.
    var worstState: SyncState {
        if !daemonAvailable { return .error }
        if sessions.isEmpty { return .idle }
        if sessions.contains(where: { $0.state == .error || $0.state == .disconnected }) {
            return .disconnected
        }
        if sessions.contains(where: { $0.state == .connecting }) { return .connecting }
        if sessions.contains(where: { $0.state == .syncing || $0.state == .scanning }) {
            return .syncing
        }
        if sessions.allSatisfy({ $0.state == .paused }) { return .paused }
        if sessions.contains(where: { $0.state == .watching }) { return .watching }
        return .idle
    }

    /// Saved definitions that do not currently have a live session.
    var stoppedDefinitions: [SavedSession] {
        let liveNames = Set(sessions.map(\.name))
        return saved.filter { !liveNames.contains($0.name) }
    }

    var disconnectedCount: Int {
        sessions.filter { $0.state == .disconnected || $0.state == .error }.count
    }

    var detectedExecutablePath: String {
        client?.executableURL.path ?? "not found"
    }

    func isBusy(_ session: MutagenSession) -> Bool {
        busySessionIDs.contains(session.id)
    }

    // MARK: - Refresh

    func refresh() async {
        guard let client else {
            daemonAvailable = false
            lastError = MutagenError.executableNotFound.errorDescription
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
            lastError = nil
            syncSavedDefinitions(from: list)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            let lower = message.lowercased()
            if lower.contains("daemon") || lower.contains("connect") || lower.contains("unable") {
                daemonAvailable = false
            }
            lastError = message
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
        let verb = session.isPaused ? "resume" : "pause"
        perform(on: session) { client in
            if verb == "resume" {
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
        guard let client else {
            lastError = MutagenError.executableNotFound.errorDescription
            return
        }
        busySessionIDs.insert(session.id)
        Task {
            defer { busySessionIDs.remove(session.id) }
            do {
                try await body(client)
                await refresh()
            } catch {
                lastError = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
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
            lastError = errorMessage(error)
            return false
        }
    }

    private func create(_ definition: SavedSession) async throws {
        guard let client else { throw MutagenError.executableNotFound }
        try await client.create(definition)
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
        Task { _ = await createSession(definition) }
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
            lastError = MutagenError.executableNotFound.errorDescription
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
            lastError = errorMessage(error)
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
                lastError = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
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
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
    }

    private func persistSaved() {
        let sorted = saved.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if let data = try? JSONEncoder().encode(sorted) {
            UserDefaults.standard.set(data, forKey: savedKey)
        }
    }

    private static func loadSettings(key: String) -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let value = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return value
    }

    private static func loadSaved(key: String) -> [SavedSession] {
        guard let data = UserDefaults.standard.data(forKey: key),
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
