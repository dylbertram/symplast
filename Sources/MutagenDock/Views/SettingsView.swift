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
                        Text("Detected: \(store.detectedExecutablePath)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
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
