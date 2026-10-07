import SwiftUI

struct MenuContentView: View {
    @ObservedObject var store: AppStore
    @State private var route: Route = .list

    enum Route { case list, newSession, settings }

    var body: some View {
        Group {
            switch route {
            case .list:
                listView
            case .newSession:
                NewSessionView(store: store) { route = .list }
            case .settings:
                SettingsView(store: store) { route = .list }
            }
        }
        .frame(width: 380)
    }

    // MARK: - List

    private var listView: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if !store.daemonAvailable {
                daemonBanner
            }

            if let error = store.lastError, store.daemonAvailable {
                errorBanner(error)
            }

            content

            Divider()
            footer
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.sessions.isEmpty && store.stoppedDefinitions.isEmpty {
            emptyState
                .frame(height: Self.scrollHeight(rowCount: 0))
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !store.sessions.isEmpty {
                        sectionHeader("Sessions")
                        ForEach(store.sessions) { session in
                            SessionRowView(store: store, session: session)
                            if session.id != store.sessions.last?.id || !store.stoppedDefinitions.isEmpty {
                                Divider().padding(.leading, 10)
                            }
                        }
                    }

                    if !store.stoppedDefinitions.isEmpty {
                        sectionHeader("Saved · not running")
                        ForEach(store.stoppedDefinitions) { definition in
                            StoppedRowView(store: store, definition: definition)
                        }
                    }
                }
            }
            .frame(height: Self.scrollHeight(rowCount: store.sessions.count + store.stoppedDefinitions.count))
        }
    }

    /// `MenuBarExtra` gives a `ScrollView` no intrinsic height, so the content
    /// area is sized explicitly: grows with the number of rows, clamped so it
    /// never collapses to a sliver or overflows the screen.
    static func scrollHeight(rowCount: Int) -> CGFloat {
        let estimated = CGFloat(rowCount) * 68 + 48
        return min(460, max(170, estimated))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(store.worstState.color)
            VStack(alignment: .leading, spacing: 0) {
                Text("MutagenDock")
                    .font(.system(size: 13, weight: .semibold))
                Text(headerSubtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if store.isRefreshing {
                ProgressView().controlSize(.small).scaleEffect(0.7)
            }
            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh now")

            Button { route = .settings } label: {
                Image(systemName: "gear")
            }
            .buttonStyle(.borderless)
            .help("Settings")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var headerSubtitle: String {
        if !store.daemonAvailable { return "Daemon not running" }
        if store.sessions.isEmpty { return "No active sessions" }
        let connected = store.sessions.count - store.disconnectedCount
        if store.disconnectedCount > 0 {
            return "\(connected) connected · \(store.disconnectedCount) disconnected"
        }
        return "\(store.sessions.count) session\(store.sessions.count == 1 ? "" : "s")"
    }

    private var daemonBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Mutagen daemon isn’t running", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.orange)
            Text("Start it to sync your folders. MutagenDock normally starts it automatically.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Button("Start daemon") { store.startDaemon() }
                .controlSize(.small)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08))
    }

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 11))
            .foregroundStyle(.red)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.08))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
            Text("No synchronized folders yet")
                .font(.system(size: 12, weight: .medium))
            Text("Add a local folder and a remote target to start syncing.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("New session…") { route = .newSession }
                .controlSize(.small)
                .padding(.top, 2)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }

    private var footer: some View {
        HStack {
            Button {
                route = .newSession
            } label: {
                Label("New session", systemImage: "plus")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)

            Spacer()

            Button("Quit") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// A saved definition whose session is not currently live.
struct StoppedRowView: View {
    @ObservedObject var store: AppStore
    let definition: SavedSession

    var body: some View {
        HStack(spacing: 10) {
            StatusDot(state: .idle)
            VStack(alignment: .leading, spacing: 2) {
                Text(definition.name)
                    .font(.system(size: 12, weight: .medium))
                Text(definition.summary)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 4)
            Button("Start") { store.start(definition) }
                .controlSize(.small)
            Menu {
                Button("Forget definition", role: .destructive) {
                    store.forget(definition)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
    }
}
