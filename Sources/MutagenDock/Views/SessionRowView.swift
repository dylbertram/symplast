import SwiftUI

struct SessionRowView: View {
    @ObservedObject var store: AppStore
    let session: MutagenSession

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            StatusDot(state: session.state)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(session.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(session.state.label)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(session.state.color)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(session.state.color.opacity(0.14), in: Capsule())
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
                    Image(systemName: "arrow.right")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                    Text(session.beta.shortDisplayName)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(session.beta.displayName)
                }

                if session.isConnected {
                    let summary = Format.contents(
                        directories: session.alpha.directories,
                        files: session.alpha.files,
                        size: session.alpha.totalFileSize
                    )
                    if !summary.isEmpty {
                        Text(summary)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                } else if !session.alpha.isConnected || !session.beta.isConnected {
                    Text(disconnectedDetail)
                        .font(.system(size: 10))
                        .foregroundStyle(.red.opacity(0.85))
                }
            }

            Spacer(minLength: 4)

            trailingControls
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .contentShape(Rectangle())
    }

    private var disconnectedDetail: String {
        var sides: [String] = []
        if !session.alpha.isConnected { sides.append("local") }
        if !session.beta.isConnected { sides.append(session.beta.isLocal ? "target" : "remote") }
        return "Cannot reach \(sides.joined(separator: " and "))"
    }

    private var trailingControls: some View {
        HStack(spacing: 2) {
            if store.isBusy(session) {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
                    .frame(width: 22, height: 22)
            } else {
                Button {
                    store.togglePause(session)
                } label: {
                    Image(systemName: session.isPaused ? "play.fill" : "pause.fill")
                }
                .buttonStyle(.borderless)
                .help(session.isPaused ? "Resume session" : "Pause session")

                Button {
                    store.flush(session)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Force a sync cycle")
                .disabled(session.isPaused)
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
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .font(.system(size: 12))
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
