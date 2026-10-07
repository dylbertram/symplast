import SwiftUI

struct NewSessionView: View {
    @ObservedObject var store: AppStore
    var onDone: () -> Void

    enum BetaMode: String, CaseIterable, Identifiable {
        case remote = "Remote (SSH)"
        case local = "Local folder"
        case custom = "Custom URL"
        var id: String { rawValue }
    }

    @State private var name = ""
    @State private var alpha = ""
    @State private var betaMode: BetaMode = .remote
    @State private var betaLocal = ""
    @State private var sshUser = NSUserName()
    @State private var sshHost = ""
    @State private var sshPort = ""
    @State private var sshPath = ""
    @State private var customBeta = ""
    @State private var mode: SyncMode = .twoWaySafe
    @State private var ignoreText = ""
    @State private var ignoreVCS = true
    @State private var isCreating = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    field("Session name") {
                        TextField("e.g. myproject-sync", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }

                    field("Local folder (alpha)") {
                        HStack(spacing: 6) {
                            TextField("/Users/you/project", text: $alpha)
                                .textFieldStyle(.roundedBorder)
                            Button("Choose…") {
                                if let chosen = FolderPicker.choose(initialPath: alpha) {
                                    alpha = chosen
                                    if name.isEmpty {
                                        name = URL(fileURLWithPath: chosen).lastPathComponent + "-sync"
                                    }
                                }
                            }
                            .controlSize(.small)
                        }
                    }

                    field("Remote / target (beta)") {
                        VStack(alignment: .leading, spacing: 6) {
                            Picker("", selection: $betaMode) {
                                ForEach(BetaMode.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()

                            betaFields
                        }
                    }

                    field("Sync mode") {
                        Picker("", selection: $mode) {
                            ForEach(SyncMode.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                    }

                    field("Ignore paths (optional, one per line)") {
                        VStack(alignment: .leading, spacing: 4) {
                            TextEditor(text: $ignoreText)
                                .font(.system(size: 11, design: .monospaced))
                                .frame(height: 52)
                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.25)))
                            Toggle("Ignore VCS directories (.git, .svn…)", isOn: $ignoreVCS)
                                .font(.system(size: 11))
                        }
                    }

                    if let error {
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                    }
                }
                .padding(12)
            }
            .frame(height: 430)
            Divider()
            footer
        }
    }

    @ViewBuilder
    private var betaFields: some View {
        switch betaMode {
        case .remote:
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    TextField("user", text: $sshUser)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 92)
                    Text("@").foregroundStyle(.secondary)
                    TextField("host", text: $sshHost)
                        .textFieldStyle(.roundedBorder)
                }
                HStack(spacing: 6) {
                    TextField("port (optional)", text: $sshPort)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 92)
                    TextField("/remote/path", text: $sshPath)
                        .textFieldStyle(.roundedBorder)
                }
            }
        case .local:
            HStack(spacing: 6) {
                TextField("/path/to/other/folder", text: $betaLocal)
                    .textFieldStyle(.roundedBorder)
                Button("Choose…") {
                    if let chosen = FolderPicker.choose(initialPath: betaLocal) {
                        betaLocal = chosen
                    }
                }
                .controlSize(.small)
            }
        case .custom:
            TextField("user@host:/path or ssh://user@host:22/path", text: $customBeta)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var header: some View {
        HStack {
            Button {
                onDone()
            } label: {
                Label("Back", systemImage: "chevron.left")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            Spacer()
            Text("New session")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            // Balances the header.
            Label("Back", systemImage: "chevron.left")
                .font(.system(size: 11))
                .opacity(0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var footer: some View {
        HStack {
            if isCreating {
                ProgressView().controlSize(.small).scaleEffect(0.7)
            }
            Spacer()
            Button("Cancel") { onDone() }
                .keyboardShortcut(.cancelAction)
            Button("Create & save") { create() }
                .keyboardShortcut(.defaultAction)
                .disabled(isCreating || !isValid)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !PathUtil.expand(alpha).isEmpty
            && !resolvedBeta.isEmpty
    }

    private var resolvedBeta: String {
        switch betaMode {
        case .local:
            return PathUtil.expand(betaLocal)
        case .custom:
            return customBeta.trimmingCharacters(in: .whitespacesAndNewlines)
        case .remote:
            let host = sshHost.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !host.isEmpty else { return "" }
            let user = sshUser.trimmingCharacters(in: .whitespacesAndNewlines)
            let prefix = user.isEmpty ? "" : "\(user)@"
            var path = sshPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty && !path.hasPrefix("/") { path = "/" + path }
            let port = sshPort.trimmingCharacters(in: .whitespacesAndNewlines)
            if port.isEmpty {
                return "\(prefix)\(host):\(path)"
            }
            return "ssh://\(prefix)\(host):\(port)\(path)"
        }
    }

    private func create() {
        error = nil
        let alphaPath = PathUtil.expand(alpha)
        guard FileManager.default.fileExists(atPath: alphaPath) else {
            error = "The local folder doesn’t exist: \(alphaPath)"
            return
        }
        let ignorePaths = ignoreText
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let definition = SavedSession(
            name: name.trimmingCharacters(in: .whitespaces),
            alpha: alphaPath,
            beta: resolvedBeta,
            mode: mode.rawValue,
            ignorePaths: ignorePaths,
            ignoreVCS: ignoreVCS
        )

        isCreating = true
        Task {
            let success = await store.createSession(definition)
            isCreating = false
            if success {
                onDone()
            } else {
                error = store.lastError ?? "Could not create the session."
            }
        }
    }

    private func field<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            content()
        }
    }
}
