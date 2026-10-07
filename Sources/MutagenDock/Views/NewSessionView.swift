import SwiftUI

struct NewSessionView: View {
    @ObservedObject var store: AppStore

    @State private var isCreating = false
    @State private var error: String?

    private var isEditing: Bool { store.editingOriginalName != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    field("Session name") {
                        TextField("e.g. myproject-sync", text: $store.draft.name)
                            .textFieldStyle(.roundedBorder)
                    }

                    field("Local folder") {
                        HStack(spacing: 6) {
                            TextField("/Users/you/project", text: $store.draft.localPath)
                                .textFieldStyle(.roundedBorder)
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

                    field("Remote") {
                        VStack(alignment: .leading, spacing: 6) {
                            Picker("", selection: $store.draft.targetKind) {
                                ForEach(NewSessionDraft.TargetKind.allCases) { Text($0.title).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()

                            targetFields
                        }
                    }

                    field("Sync mode") {
                        VStack(alignment: .leading, spacing: 5) {
                            Picker("", selection: $store.draft.modeChoice) {
                                ForEach(NewSessionDraft.ModeChoice.allCases) { Text($0.title).tag($0) }
                            }
                            .labelsHidden()
                            Text(store.draft.modeChoice.detail)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    field("Ignore paths (optional, one per line)") {
                        VStack(alignment: .leading, spacing: 4) {
                            TextEditor(text: $store.draft.ignoreText)
                                .font(.system(size: 11, design: .monospaced))
                                .frame(height: 52)
                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.25)))
                            Toggle("Ignore VCS directories", isOn: $store.draft.ignoreVCS)
                                .font(.system(size: 11))
                            Toggle("Ignore build output (target/, build/, bin/, *.o)", isOn: $store.draft.ignoreBuildArtifacts)
                                .font(.system(size: 11))
                            Text(blockedSummary)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if let error {
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12)
            }
            .frame(maxHeight: .infinity)
            Divider()
            footer
        }
    }

    @ViewBuilder
    private var targetFields: some View {
        switch store.draft.targetKind {
        case .remote:
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    TextField("user", text: $store.draft.sshUser)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 82)
                    Text("@").foregroundStyle(.secondary)
                    TextField("host", text: $store.draft.sshHost)
                        .textFieldStyle(.roundedBorder)
                    Text(":").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        TextField("port", text: $store.draft.sshPort)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 48)
                        Text("optional")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
                TextField("/remote/path", text: $store.draft.sshPath)
                    .textFieldStyle(.roundedBorder)
            }
        case .local:
            HStack(spacing: 6) {
                TextField("/path/to/other/folder", text: $store.draft.localTargetPath)
                    .textFieldStyle(.roundedBorder)
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
        }
    }

    private var header: some View {
        HStack {
            Button {
                store.cancelForm()
            } label: {
                Label("Back", systemImage: "chevron.left")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            Spacer()
            Text(isEditing ? "Edit session" : "New session")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Label("Back", systemImage: "chevron.left")
                .font(.system(size: 11))
                .opacity(0)
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
    }

    private var footer: some View {
        HStack {
            if isCreating {
                ProgressView().controlSize(.small).scaleEffect(0.7)
            }
            Spacer()
            Button("Cancel") { store.cancelForm() }
                .keyboardShortcut(.cancelAction)
            Button(isEditing ? "Save changes" : "Create & save") { create() }
                .keyboardShortcut(.defaultAction)
                .disabled(isCreating || !store.draft.isValid)
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
    }

    private var blockedSummary: String {
        let ignores = store.draft.effectiveIgnores
        if ignores.isEmpty { return "Nothing is currently blocked." }
        return "Blocks: " + ignores.joined(separator: ", ")
    }

    private func create() {
        error = nil
        let localPath = PathUtil.expand(store.draft.localPath)
        guard FileManager.default.fileExists(atPath: localPath) else {
            error = "The local folder doesn’t exist: \(localPath)"
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
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            content()
        }
    }
}
