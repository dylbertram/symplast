import SwiftUI

struct NewSessionView: View {
    @ObservedObject var store: AppStore

    @State private var isCreating = false
    @State private var error: String?
    @State private var showIgnorePatterns = false

    private var isEditing: Bool { store.editingOriginalName != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if let error {
                ScrollView {
                    InlineError(message: error)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .frame(height: Layout.errorHeight)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if isEditing && store.sessions.contains(where: { $0.name == store.editingOriginalName }) {
                        Label("Saving recreates this session. Your files stay in place.", systemImage: "info.circle")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.secondary.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)
                    }

                    PanelSection {
                        inlineField("Name") {
                            TextField("e.g. myproject-sync", text: $store.draft.name)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel("Session name")
                        }

                        inlineField("Local folder") {
                            HStack(spacing: 8) {
                                TextField("/Users/you/project", text: $store.draft.localPath)
                                    .textFieldStyle(.roundedBorder)
                                    .accessibilityLabel("Local folder path")
                                Button("Choose…") {
                                    if let chosen = FolderPicker.choose(initialPath: store.draft.localPath) {
                                        store.draft.localPath = chosen
                                        if store.draft.name.isEmpty {
                                            store.draft.name = URL(fileURLWithPath: chosen).lastPathComponent + "-sync"
                                        }
                                    }
                                }
                                .controlSize(.small)
                            }
                        }
                    }

                    Divider()
                    PanelSection {
                        inlineField("Target", sectionTitle: true) {
                            Picker("Target type", selection: $store.draft.targetKind) {
                                ForEach(NewSessionDraft.TargetKind.allCases) { Text($0.title).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(maxWidth: .infinity)
                        }
                        targetFields
                    }

                    Divider()
                    PanelSection {
                        inlineField("Sync mode", sectionTitle: true) {
                            Picker("Sync mode", selection: $store.draft.modeChoice) {
                                ForEach(NewSessionDraft.ModeChoice.allCases) { Text($0.title).tag($0) }
                            }
                            .labelsHidden()
                        }
                        Text(store.draft.modeChoice.detail)
                            .font(.system(size: 10))
                            .foregroundStyle(store.draft.modeChoice == .oneWayReplica ? PanelColors.warning : Color.secondary.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Divider()
                    PanelSection {
                        Text("Exclude from sync")
                            .font(.system(size: 12, weight: .semibold))
                        HStack(spacing: 16) {
                            Toggle("Version-control folders", isOn: $store.draft.ignoreVCS)
                                .fixedSize()
                            Toggle("Build output", isOn: $store.draft.ignoreBuildArtifacts)
                                .fixedSize()
                                .help("Excludes target/, build/, bin/ and *.o.")
                        }
                        .font(.system(size: 11))
                        DisclosureGroup("Additional ignore patterns", isExpanded: $showIgnorePatterns) {
                            VStack(alignment: .leading, spacing: 4) {
                                TextEditor(text: $store.draft.ignoreText)
                                    .font(.system(size: 11, design: .monospaced))
                                    .scrollContentBackground(.hidden)
                                    .padding(4)
                                    .frame(height: 56)
                                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.1)))
                                    .accessibilityLabel("Additional ignore patterns, one per line")
                                Text("Optional · one pattern per line")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.secondary.opacity(0.85))
                                Text(blockedSummary)
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.secondary.opacity(0.85))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)
                            }
                        }
                        .disclosureGroupStyle(FullWidthDisclosureStyle())
                        .font(.system(size: 11))
                    }
                }
                .padding(12)
                .font(.system(size: 12))
                .controlSize(.small)
                .disabled(isCreating)
            }
            .frame(maxHeight: .infinity)
            Divider()
            footer
        }
        .onAppear { showIgnorePatterns = !store.draft.customIgnorePaths.isEmpty }
    }

    @ViewBuilder
    private var targetFields: some View {
        switch store.draft.targetKind {
        case .remote:
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    field("User") {
                        TextField("user", text: $store.draft.sshUser)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("SSH user")
                    }
                    .frame(width: 72)
                    field("Host") {
                        TextField("server.example.com", text: $store.draft.sshHost)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("SSH host")
                    }
                    field("Port") {
                        TextField("22", text: $store.draft.sshPort)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("SSH port, optional, defaults to 22")
                    }
                    .frame(width: 52)
                }
                inlineField("Remote path") {
                    TextField("/remote/path", text: $store.draft.sshPath)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Remote folder path")
                }
                Text("Leave the port blank to use your SSH configuration.")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.secondary.opacity(0.85))
            }
        case .local:
            HStack(spacing: 6) {
                TextField("/path/to/other/folder", text: $store.draft.localTargetPath)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Target folder path")
                Button("Choose…") {
                    if let chosen = FolderPicker.choose(initialPath: store.draft.localTargetPath) {
                        store.draft.localTargetPath = chosen
                    }
                }
                .controlSize(.small)
            }
        case .custom:
            TextField("user@host:/path or ssh://user@host:22/path", text: $store.draft.customTarget)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Custom target URL")
        }
    }

    private var header: some View {
        PanelHeader(title: isEditing ? "Edit session" : "New session") {
            store.cancelForm()
        }
        .disabled(isCreating)
    }

    private var footer: some View {
        HStack {
            if isCreating {
                ProgressView().controlSize(.small)
                Text(isEditing ? "Saving…" : "Creating…")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cancel") { store.cancelForm() }
                .keyboardShortcut(.cancelAction)
                .disabled(isCreating)
            Button(isEditing ? "Save changes" : "Create session") { create() }
                .buttonStyle(.bordered)
                .keyboardShortcut(.defaultAction)
                .disabled(isCreating || !store.draft.isValid)
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .frame(height: Layout.footerHeight)
    }

    private var blockedSummary: String {
        let ignores = store.draft.effectiveIgnores
        if ignores.isEmpty { return "Nothing is currently blocked." }
        return "Blocks: " + ignores.joined(separator: ", ")
    }

    private func create() {
        error = nil
        let localPath = PathUtil.expand(store.draft.localPath)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: localPath, isDirectory: &isDirectory), isDirectory.boolValue else {
            error = "Choose an existing local folder: \(localPath)"
            return
        }

        isCreating = true
        Task {
            let success = await store.saveDraft()
            isCreating = false
            if !success {
                error = store.lastError ?? "Could not save the session."
            }
        }
    }

    private func field<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func inlineField<Content: View>(
        _ label: String,
        sectionTitle: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: sectionTitle ? 12 : 11, weight: sectionTitle ? .semibold : .regular))
                .foregroundStyle(sectionTitle ? .primary : .secondary)
                .frame(width: 72, alignment: .leading)
            content().frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
