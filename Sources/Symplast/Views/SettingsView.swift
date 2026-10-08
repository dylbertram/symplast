import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: AppStore

    @State private var pathDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    PanelSection {
                        Text("General").font(.system(size: 12, weight: .semibold))
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Refresh interval")
                                Spacer()
                                Text(String(format: "%.1f s", store.settings.pollInterval))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $store.settings.pollInterval, in: 1...15, step: 0.5)
                                .accessibilityLabel("Refresh interval in seconds")
                        }
                        Toggle(isOn: $store.settings.showCount) {
                            Text("Session count in menu bar").frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Toggle(isOn: $store.settings.autoEnsureDaemon) {
                            Text("Start daemon on launch").frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    Divider()
                    PanelSection {
                        Text("Mutagen executable").font(.system(size: 12, weight: .semibold))
                        TextField("Auto-detect", text: $pathDraft)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11, design: .monospaced))
                            .accessibilityLabel("Mutagen executable override path")
                        HStack(spacing: 4) {
                            if store.isUsingBundledExecutable {
                                Image(systemName: "shippingbox")
                                Text("Bundled with Symplast")
                            } else {
                                Text("Detected: \(store.detectedExecutablePath)")
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .help(store.detectedExecutablePath)
                        HStack(spacing: 6) {
                            Button("Apply") {
                                pathDraft = pathDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                                store.settings.mutagenPath = pathDraft
                                store.applySettingsChange()
                            }
                            .controlSize(.small)
                            .disabled(pathDraft == store.settings.mutagenPath)
                            Button("Auto-detect") {
                                pathDraft = ""
                                store.settings.mutagenPath = ""
                                store.applySettingsChange()
                            }
                            .controlSize(.small)
                            .disabled(pathDraft.isEmpty && store.settings.mutagenPath.isEmpty)
                        }
                    }

                    Divider()
                    PanelSection {
                        Text("SSH authentication").font(.system(size: 12, weight: .semibold))
                        HStack {
                            Text("Agent").foregroundStyle(.secondary)
                            Spacer()
                            Text(store.sshAgentSocket)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(store.sshAgentSocket)
                        }
                        .font(.system(size: 11))
                        Text("Mutagen uses your SSH agent and ~/.ssh/config. Load passphrase-protected keys with `ssh-add`.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Divider()
                    PanelSection {
                        HStack {
                            Text("Daemon").font(.system(size: 12, weight: .semibold))
                            Spacer()
                            Label(store.daemonAvailable ? "Running" : "Not running",
                                  systemImage: store.daemonAvailable ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(store.daemonAvailable ? PanelColors.success : PanelColors.warning)
                        }
                        HStack(spacing: 6) {
                            Button("Start daemon") { store.startDaemon() }
                                .controlSize(.small)
                                .disabled(store.daemonAvailable || store.detectedExecutablePath == "not found")
                            Button("Refresh now") {
                                Task { await store.refreshNow() }
                            }
                            .controlSize(.small)
                            .disabled(store.isManualRefreshing)
                            if store.isManualRefreshing {
                                ProgressView().controlSize(.small)
                            }
                        }
                    }

                    Divider()
                    PanelSection {
                        HStack {
                            Text("About").font(.system(size: 12, weight: .semibold))
                            Spacer()
                            Text(store.appVersion).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Text("A menu-bar companion for Mutagen. Synchronization is performed by the mutagen CLI.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Not affiliated with or endorsed by Mutagen or Docker, Inc.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Link("mutagen.io", destination: URL(string: "https://mutagen.io")!)
                            .font(.system(size: 11))
                        HStack(spacing: 6) {
                            Button("Check for Updates") {
                                Task { await store.checkForUpdates() }
                            }
                            .controlSize(.small)
                            .disabled(store.versionCheckStatus == .checking)
                            if store.versionCheckStatus == .checking {
                                ProgressView().controlSize(.small)
                            }
                        }
                        switch store.versionCheckStatus {
                        case .notChecked, .checking:
                            EmptyView()
                        case .upToDate:
                            Text("You're up to date.")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        case let .updateAvailable(update):
                            Link("Symplast \(update.version) is available — View release ↗", destination: update.releaseURL)
                                .font(.system(size: 11))
                        case let .failed(message):
                            Text(message)
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if let error = store.lastError {
                        InlineError(message: error)
                    }
                }
                .padding(12)
                .font(.system(size: 12))
                .toggleStyle(.checkbox)
                .controlSize(.small)
            }
            .frame(maxHeight: .infinity)
            Divider()
            HStack {
                Spacer()
                Button("Done") { store.route = .list }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 12)
            .frame(height: Layout.footerHeight)
        }
        .onAppear { pathDraft = store.settings.mutagenPath }
        .onExitCommand { store.route = .list }
    }

    private var header: some View {
        PanelHeader(title: "Settings") {
            store.route = .list
        }
    }
}
