import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: AppStore

    @State private var pathDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("mutagen executable")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        TextField("Auto-detect", text: $pathDraft)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11, design: .monospaced))
                        Text("Detected: \(store.detectedExecutablePath)")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(store.detectedExecutablePath)
                        HStack(spacing: 6) {
                            Button("Apply") {
                                store.settings.mutagenPath = pathDraft
                                store.applySettingsChange()
                            }
                            .controlSize(.small)
                            Button("Use detected") {
                                pathDraft = ""
                                store.settings.mutagenPath = ""
                                store.applySettingsChange()
                            }
                            .controlSize(.small)
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Refresh interval")
                                .font(.system(size: 11, weight: .medium))
                            Spacer()
                            Text(String(format: "%.1f s", store.settings.pollInterval))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $store.settings.pollInterval, in: 1...15, step: 0.5)
                    }

                    Toggle("Show session count in menu bar", isOn: $store.settings.showCount)
                        .font(.system(size: 12))

                    Toggle("Start Mutagen daemon on launch", isOn: $store.settings.autoEnsureDaemon)
                        .font(.system(size: 12))

                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Daemon")
                            .font(.system(size: 11, weight: .medium))
                        HStack(spacing: 6) {
                            Button("Start daemon") { store.startDaemon() }
                                .controlSize(.small)
                            Button("Refresh now") {
                                Task { await store.refresh() }
                            }
                            .controlSize(.small)
                        }
                        Text("Status: \(store.daemonAvailable ? "running" : "not running")")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
            }
            .frame(height: Layout.contentHeight)
            Divider()
            HStack {
                Spacer()
                Button("Done") { store.route = .list }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
        }
        .onAppear { pathDraft = store.settings.mutagenPath }
    }

    private var header: some View {
        HStack {
            Button { store.route = .list } label: {
                Label("Back", systemImage: "chevron.left").font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            Spacer()
            Text("Settings").font(.system(size: 13, weight: .semibold))
            Spacer()
            Label("Back", systemImage: "chevron.left").font(.system(size: 11)).opacity(0)
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
    }
}
