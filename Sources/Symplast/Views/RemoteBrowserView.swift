import SwiftUI

/// Folder browser for an SSH target, shown inside the panel. It connects over
/// SSH (non-interactive, key-based) and lists the remote folders so a path can
/// be picked instead of looked up on the server and typed by hand.
struct RemoteBrowserView: View {
    @ObservedObject var store: AppStore
    let target: AppStore.RemoteBrowseTarget

    @State private var currentPath: String
    @State private var entries: [String] = []
    @State private var isLoading = false
    @State private var error: String?

    init(store: AppStore, target: AppStore.RemoteBrowseTarget) {
        self.store = store
        self.target = target
        _currentPath = State(initialValue: target.path.trimmingCharacters(in: .whitespaces))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelHeader(title: "Remote folder") { store.finishRemoteBrowse() }
                .disabled(isLoading)
            Divider()
            if let error {
                InlineError(message: error)
                    .padding(.horizontal, 12)
            }
            connectionRow
            Divider()
            pathRow
            Divider()
            listing
            Divider()
            footer
        }
        .onAppear { Task { await load() } }
    }

    // MARK: - Header rows

    private var connectionRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "server.rack")
                .font(.system(size: 11))
            Text(connectionName)
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.middle)
                .help(connectionName)
            Spacer()
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Loading folders")
            }
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: Layout.sectionHeight)
    }

    private var pathRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(currentPath.isEmpty ? "Home folder" : currentPath)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .help(currentPath.isEmpty ? "The home folder on the server" : currentPath)
            Spacer()
            PanelIconButton(symbol: "arrow.up", label: "Go to parent folder",
                            disabled: isLoading || isAtRoot) {
                goUp()
            }
        }
        .padding(.horizontal, 12)
        .frame(height: Layout.sectionHeight)
    }

    // MARK: - Listing

    private var listing: some View {
        Group {
            if isLoading && entries.isEmpty {
                VStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Connecting…")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if entries.isEmpty {
                Text("No folders here.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(entries, id: \.self, content: row)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
        .opacity(isLoading ? 0.5 : 1)
        .disabled(isLoading)
    }

    private func row(_ entry: String) -> some View {
        Button {
            open(entry)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text((entry as NSString).lastPathComponent)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(entry)
        .overlay(alignment: .bottom) { Divider().padding(.horizontal, 12) }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Cancel") { store.finishRemoteBrowse() }
                .keyboardShortcut(.cancelAction)
                .disabled(isLoading)
            Spacer()
            Button("Use this folder") { store.finishRemoteBrowse(selecting: currentPath) }
                .buttonStyle(.bordered)
                .keyboardShortcut(.defaultAction)
                .disabled(isLoading || currentPath.isEmpty)
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .frame(height: Layout.footerHeight)
    }

    // MARK: - Navigation

    private var connectionName: String {
        let user = target.user.trimmingCharacters(in: .whitespaces)
        return user.isEmpty ? target.host : "\(user)@\(target.host)"
    }

    private var isAtRoot: Bool {
        currentPath.isEmpty || currentPath == "/"
    }

    private func open(_ entry: String) {
        currentPath = entry
        Task { await load() }
    }

    private func goUp() {
        let parent = (currentPath as NSString).deletingLastPathComponent
        currentPath = parent.isEmpty ? "/" : parent
        Task { await load() }
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let client = SSHRemoteClient(user: target.user, host: target.host, port: target.port)
            let listing = try await client.list(at: currentPath)
            if !listing.path.isEmpty, listing.path != currentPath {
                currentPath = listing.path
            }
            entries = listing.directories
        } catch {
            entries = []
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
