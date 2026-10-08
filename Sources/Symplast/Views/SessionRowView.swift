import SwiftUI

struct SessionRowView: View {
    @ObservedObject var store: AppStore
    let session: MutagenSession
    var showsSeparator = true
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(session.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .help(session.name)
                    .layoutPriority(1)
                Spacer(minLength: 4)
                trailingControls.fixedSize()
            }

            HStack(spacing: 6) {
                // Alpha stays above beta, including remote-first sessions.
                SyncModeIndicator(mode: session.mode, alphaIsLocal: session.alpha.isLocal, vertical: true)
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 2) {
                    endpoint(session.alpha)
                    endpoint(session.beta)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                StatusLabel(state: state)
                if !detail.isEmpty {
                    Text("·").foregroundStyle(.tertiary)
                    Text(detail)
                        .font(.system(size: hasProblem ? 10 : 9))
                        .foregroundStyle(hasProblem ? PanelColors.critical : Color.secondary.opacity(0.85))
                        .lineLimit(1)
                        .help(detail)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Layout.sessionRowHeight)
        .background(isHovered ? Color.primary.opacity(0.025) : .clear)
        .overlay(alignment: .bottom) {
            if showsSeparator { Divider().padding(.horizontal, 12) }
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }

    private func endpoint(_ endpoint: MutagenEndpoint) -> some View {
        Text(endpoint.shortDisplayName)
            .font(.system(size: 11))
            .foregroundStyle(.primary.opacity(0.8))
            .lineLimit(1)
            .truncationMode(.middle)
            .help(endpoint.displayName)
            .accessibilityLabel("\(endpoint.isLocal ? "Local folder" : "Remote endpoint"): \(endpoint.displayName)")
    }

    private var state: SyncState { store.state(for: session) }

    private var hasProblem: Bool { state == .disconnected || state == .error }

    private var detail: String {
        if let error = store.connectionErrors[session.id] ?? session.lastError,
           hasProblem { return ErrorSummary.short(error) }
        if state == .disconnected { return disconnectedDetail }
        if state == .error { return session.status }
        if session.isPaused || state == .connecting { return "" }
        return Format.contents(directories: session.alpha.directories,
                               files: session.alpha.files, size: session.alpha.totalFileSize)
    }

    private var disconnectedDetail: String {
        var sides: [String] = []
        if !session.alpha.isConnected { sides.append(session.alpha.isLocal ? "local" : "remote") }
        if !session.beta.isConnected { sides.append(session.beta.isLocal ? "target" : "remote") }
        return "Cannot reach \(sides.joined(separator: " and "))"
    }

    private var trailingControls: some View {
        HStack(spacing: 0) {
            if store.isBusy(session) {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 24, height: 24)
                    .accessibilityLabel("Updating session")
            } else {
                PanelIconButton(
                    symbol: session.isPaused ? "play.fill" : "pause.fill",
                    label: session.isPaused ? "Resume session" : "Pause session"
                ) {
                    store.togglePause(session)
                }
            }

            Menu {
                Button("Edit…") { store.beginEdit(session) }
                Button("Force sync cycle") { store.flush(session) }
                    .disabled(session.isPaused || !session.isConnected)
                Divider()
                Button("Reveal local folder") {
                    NSWorkspace.shared.reveal(session.alpha.isLocal ? session.alpha.path ?? "" : session.beta.path ?? "")
                }
                Button("Copy local path") {
                    copyToPasteboard(session.alpha.isLocal ? session.alpha.displayName : session.beta.displayName)
                }
                Button("Copy remote path") {
                    copyToPasteboard(session.alpha.isLocal ? session.beta.displayName : session.alpha.displayName)
                }
                Divider()
                Button("Reset history") {
                    store.reset(session)
                }
                Button(role: .destructive) {
                    confirmTerminate()
                } label: {
                    Text("Terminate session…")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("More actions")
            .accessibilityLabel("Actions for \(session.name)")
            .disabled(store.isBusy(session))
        }
        .foregroundStyle(.secondary)
    }

    private func copyToPasteboard(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }

    private func confirmTerminate() {
        let alert = NSAlert()
        alert.messageText = "Terminate “\(session.name)”?"
        alert.informativeText = "The session will be removed from Mutagen. Its saved definition stays in Symplast so you can start it again."
        alert.addButton(withTitle: "Terminate")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            store.terminate(session)
        }
    }
}
