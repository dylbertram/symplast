import SwiftUI

struct MenuContentView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        Group {
            switch store.route {
            case .list:
                listView
            case .newSession:
                NewSessionView(store: store)
            case .settings:
                SettingsView(store: store)
            }
        }
        .frame(width: Layout.panelWidth)
        .frame(maxHeight: .infinity)
        // Leave the content transparent so AppKit's popover material also
        // supplies the body fill, matching its native arrow and rounded edges.
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !store.sessions.isEmpty {
                        if !store.stoppedDefinitions.isEmpty {
                            sectionHeader("Sessions", count: store.sessions.count)
                        }
                        ForEach(store.sessions) { session in
                            SessionRowView(store: store, session: session,
                                           showsSeparator: session.id != store.sessions.last?.id || !store.stoppedDefinitions.isEmpty)
                        }
                    }

                    if !store.stoppedDefinitions.isEmpty {
                        sectionHeader("Saved · not running", count: store.stoppedDefinitions.count)
                        ForEach(store.stoppedDefinitions) { definition in
                            StoppedRowView(store: store, definition: definition,
                                           showsSeparator: definition.id != store.stoppedDefinitions.last?.id)
                        }
                    }
                }
                .padding(.bottom, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            BrandLogo(size: 17, color: store.worstState.color)
            VStack(alignment: .leading, spacing: 1) {
                Text("Symplast")
                    .font(.system(size: 13, weight: .semibold))
                Text(headerSubtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if store.isManualRefreshing {
                ProgressView().controlSize(.small).frame(width: 24, height: 24)
                    .accessibilityLabel("Refreshing sessions")
            } else {
                PanelIconButton(symbol: "arrow.clockwise", label: "Refresh now") {
                    Task { await store.refreshNow() }
                }
            }
            PanelIconButton(symbol: "gearshape", label: "Settings") {
                store.route = .settings
            }
        }
        .padding(.horizontal, 12)
        .frame(height: Layout.headerHeight)
    }

    private var headerSubtitle: String {
        if executableMissing { return "Mutagen not found" }
        if !store.daemonAvailable { return "Daemon not running" }
        if store.sessions.isEmpty { return "No active sessions" }
        if store.disconnectedCount > 0 {
            return "\(store.disconnectedCount) session\(store.disconnectedCount == 1 ? " needs" : "s need") attention"
        }
        if store.sessions.allSatisfy({ $0.isPaused }) { return "All sessions paused" }
        return "\(store.sessions.count) session\(store.sessions.count == 1 ? "" : "s") · \(store.worstState.label.lowercased())"
    }

    private var daemonBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(executableMissing ? "Mutagen executable not found" : "Mutagen daemon isn’t running",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(PanelColors.warning)
            Text(executableMissing
                 ? "Install with brew install mutagen-io/mutagen/mutagen, or choose an executable in Settings."
                 : "Start the daemon to sync your folders. Existing sessions and files are preserved.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if executableMissing {
                Button("Open Settings") { store.route = .settings }.controlSize(.small)
            } else {
                Button("Start daemon") { store.startDaemon() }.controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Layout.bannerHeight)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var executableMissing: Bool { store.detectedExecutablePath == "not found" }

    private func errorBanner(_ message: String) -> some View {
        InlineError(message: message) { store.dismissError() }
        .padding(.horizontal, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.secondary)
            Text("No synchronized folders yet")
                .font(.system(size: 12, weight: .medium))
            Text("Connect a local folder to another folder\nor an SSH server to get started.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 5) {
            Text(title).font(.system(size: 10, weight: .medium))
            Text("·").font(.system(size: 10))
            Text("\(count)").font(.system(size: 10)).monospacedDigit()
            Spacer()
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: Layout.sectionHeight)
    }

    private var footer: some View {
        HStack {
            Button {
                store.beginNewSession()
            } label: {
                Label("New session", systemImage: "plus")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .keyboardShortcut("n", modifiers: .command)

            Spacer()

            Button("Quit") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .frame(height: Layout.footerHeight)
    }
}

/// A saved definition whose session is not currently live.
struct StoppedRowView: View {
    @ObservedObject var store: AppStore
    let definition: SavedSession
    var showsSeparator = true

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(definition.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .help(definition.name)
                Text(definition.summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help("\(definition.alpha) → \(definition.beta)")
            }
            Spacer(minLength: 4)
            if store.startingDefinitionNames.contains(definition.name) {
                ProgressView().controlSize(.small).frame(width: 40, height: 24)
                    .accessibilityLabel("Starting \(definition.name)")
            } else {
                Button("Start") { store.start(definition) }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Menu {
                Button("Edit…") { store.beginEdit(definition) }
                Button("Forget definition", role: .destructive) {
                    store.forget(definition)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Saved session actions")
            .accessibilityLabel("Actions for \(definition.name)")
            .disabled(store.startingDefinitionNames.contains(definition.name))
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Layout.savedRowHeight)
        .overlay(alignment: .bottom) {
            if showsSeparator { Divider().padding(.horizontal, 12) }
        }
    }
}
