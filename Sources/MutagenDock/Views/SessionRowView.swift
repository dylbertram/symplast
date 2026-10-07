import SwiftUI

struct SessionRowView: View {
    @ObservedObject var store: AppStore
    let session: MutagenSession

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                StatusDot(state: session.state)
                Text(session.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .layoutPriority(1)
                Text(session.state.label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(session.state.color)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(session.state.color.opacity(0.14), in: Capsule())
                    .fixedSize()
                Spacer(minLength: 0)
            }

            HStack(spacing: 4) {
                Image(systemName: session.alpha.isLocal ? "laptopcomputer" : "cloud")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Text(session.alpha.shortDisplayName)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(session.alpha.displayName)
                SyncModeIndicator(mode: session.mode, alphaIsLocal: session.alpha.isLocal)
                Text(session.beta.shortDisplayName)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(session.beta.displayName)
            }

            if !session.isPaused && !session.isConnected {
                Text(disconnectedDetail)
                    .font(.system(size: 10))
                    .foregroundStyle(.red.opacity(0.85))
                    .lineLimit(1)
            } else {
                let summary = Format.contents(
                    directories: session.alpha.directories,
                    files: session.alpha.files,
                    size: session.alpha.totalFileSize
                )
                if !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        // The text fills the full width, and the controls are pinned to the
        // trailing edge with an intrinsic-size overlay so their position never
        // depends on how the stack distributes space.
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.leading, 10)
        .padding(.trailing, 84)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topTrailing) {
            trailingControls
                .fixedSize()
                .padding(.top, 7)
                .padding(.trailing, 10)
        }
        .contentShape(Rectangle())
    }

    private var disconnectedDetail: String {
        var sides: [String] = []
        if !session.alpha.isConnected { sides.append("local") }
        if !session.beta.isConnected { sides.append(session.beta.isLocal ? "target" : "remote") }
        return "Cannot reach \(sides.joined(separator: " and "))"
    }

    private var trailingControls: some View {
        HStack(spacing: 4) {
            if store.isBusy(session) {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.6)
                    .frame(width: 20, height: 20)
            } else {
                IconControl(
                    symbol: session.isPaused ? "play.fill" : "pause.fill",
                    help: session.isPaused ? "Resume session" : "Pause session"
                ) {
                    store.togglePause(session)
                }

                IconControl(
                    symbol: "arrow.clockwise",
                    help: "Force a sync cycle",
                    disabled: session.isPaused
                ) {
                    store.flush(session)
                }
            }

            Menu {
                Button("Edit…") { store.beginEdit(session) }
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
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 13))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("More actions")
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
        alert.informativeText = "The session will be removed from Mutagen. Its saved definition stays in MutagenDock so you can start it again."
        alert.addButton(withTitle: "Terminate")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            store.terminate(session)
        }
    }
}

/// A borderless icon button with a consistent 20×20 hit area so the row's
/// controls line up evenly.
private struct IconControl: View {
    let symbol: String
    let help: String
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .disabled(disabled)
        .help(help)
    }
}
