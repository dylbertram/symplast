import SwiftUI

/// Merge-like preview of what the first sync would do to both sides, shown
/// before a session is created: which files are added, which are overwritten,
/// which — in replica mode — are deleted, and which are left alone.
struct SyncPreviewView: View {
    @ObservedObject var store: AppStore

    @State private var isCreating = false
    @State private var error: String?

    private struct PreviewGroup: Identifiable {
        var title: String
        var color: Color
        var outcomes: [PreviewOutcome]
        var id: String { title }
    }

    private let groups: [PreviewGroup] = [
        PreviewGroup(title: "Overwritten in the target", color: PanelColors.warning,
                     outcomes: [.overwritten(.target)]),
        PreviewGroup(title: "Overwritten in the local folder", color: PanelColors.warning,
                     outcomes: [.overwritten(.local)]),
        PreviewGroup(title: "Deleted from the target", color: PanelColors.critical,
                     outcomes: [.deleted(.target)]),
        PreviewGroup(title: "Deleted from the local folder", color: PanelColors.critical,
                     outcomes: [.deleted(.local)]),
        PreviewGroup(title: "Added to the target", color: PanelColors.success,
                     outcomes: [.created(.target)]),
        PreviewGroup(title: "Added to the local folder", color: PanelColors.success,
                     outcomes: [.created(.local)]),
        PreviewGroup(title: "Left untouched", color: .secondary,
                     outcomes: [.kept(.local), .kept(.target)]),
        PreviewGroup(title: "Possible conflicts", color: PanelColors.critical,
                     outcomes: [.conflict])
    ]

    private let rowCap = 15
    /// How many additional rows each "… and N more" click reveals.
    private let revealStep = 50
    /// Rows currently revealed per group; groups start at `rowCap`.
    @State private var revealed: [String: Int] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelHeader(title: "Preview changes") { store.finishSyncPreview() }
                .disabled(isCreating)
            Divider()
            if let error {
                InlineError(message: error)
                    .padding(.horizontal, 12)
            }
            if store.isPreparingPreview {
                loading
            } else {
                content
            }
            Divider()
            footer
        }
    }

    private var loading: some View {
        VStack(spacing: 6) {
            ProgressView()
                .controlSize(.small)
            Text("Comparing folders…")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        if let report = store.syncPreview {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    summary(report)
                    if let notice = report.notice {
                        Text(notice)
                            .font(.system(size: 11))
                            .foregroundStyle(PanelColors.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(groups) { group in
                        let entries = entries(for: group, in: report)
                        if !entries.isEmpty {
                            section(group, entries: entries)
                        }
                    }
                }
                .padding(12)
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func summary(_ report: SyncPreviewReport) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("What the first sync would change")
                .font(.system(size: 12, weight: .semibold))
            Text("Local: \(report.localPath)")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(report.localPath)
            Text("Target: \(report.targetPath)")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(report.targetPath)
            Text(countLine(report))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Text("Estimate from names, sizes and modification times.")
                .font(.system(size: 9))
                .foregroundStyle(.secondary.opacity(0.85))
        }
    }

    private func countLine(_ report: SyncPreviewReport) -> String {
        var parts = ["\(Format.number(report.changedCount)) changed",
                     "\(Format.number(report.unchangedCount)) unchanged"]
        if report.truncated { parts.append("scan limited to \(Format.number(SyncPreviewService.fileLimit)) files per side") }
        return parts.joined(separator: " · ")
    }

    private func section(_ group: PreviewGroup, entries: [SyncPreview.Entry]) -> some View {
        let shown = min(revealed[group.title] ?? rowCap, entries.count)
        let isFullyShown = shown >= entries.count
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Circle()
                    .fill(group.color)
                    .frame(width: 6, height: 6)
                Text(group.title)
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Text("\(Format.number(entries.count))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            ForEach(Array(entries.prefix(shown).enumerated()), id: \.offset) { _, entry in
                HStack(spacing: 8) {
                    Text(entry.path)
                        .font(.system(size: 10, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(entry.path)
                    Spacer()
                    Text(Format.bytes(entry.size))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            if entries.count > rowCap {
                Button {
                    revealed[group.title] = isFullyShown
                        ? rowCap
                        : min(shown + revealStep, entries.count)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isFullyShown ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8, weight: .medium))
                        Text(isFullyShown
                             ? "Show less"
                             : "… and \(Format.number(entries.count - shown)) more")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isFullyShown
                      ? "Collapse back to the first \(rowCap)"
                      : "Show \(min(revealStep, entries.count - shown)) more")
                .accessibilityLabel(isFullyShown
                                    ? "Show less"
                                    : "Show \(min(revealStep, entries.count - shown)) more")
            }
        }
    }

    private func entries(for group: PreviewGroup, in report: SyncPreviewReport) -> [SyncPreview.Entry] {
        report.entries.filter { group.outcomes.contains($0.outcome) }
    }

    private var footer: some View {
        HStack {
            if isCreating {
                ProgressView()
                    .controlSize(.small)
                Text("Creating…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Back to form") { store.finishSyncPreview() }
                .keyboardShortcut(.cancelAction)
                .disabled(isCreating)
            Button(store.editingOriginalName == nil ? "Create session" : "Save changes") { create() }
                .buttonStyle(.bordered)
                .keyboardShortcut(.defaultAction)
                .disabled(isCreating || store.isPreparingPreview)
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .frame(height: Layout.footerHeight)
    }

    private func create() {
        error = nil
        let localPath = PathUtil.expand(store.draft.localPath)
        guard PathUtil.isExistingDirectory(store.draft.localPath) else {
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
}
