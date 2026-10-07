import SwiftUI

/// The sync-direction indicator shown between the two endpoints.
///
/// - Two-way (safe): both arrows, no priority.
/// - Two-way (resolved): both arrows with the *alpha* side (the left endpoint)
///   bolded, since Mutagen resolves conflicts in favour of alpha. Because a
///   "remote wins" session is stored with the remote listed first, the bolded
///   side is always the winning side.
/// - One-way (safe): a single arrow from alpha to beta.
/// - One-way (replica): a single, bolder arrow (beta is overwritten).
struct SyncModeIndicator: View {
    let mode: String?
    let alphaIsLocal: Bool

    var body: some View {
        Group {
            switch mode {
            case "two-way-safe":
                Image(systemName: "arrow.left.arrow.right")
            case "two-way-resolved":
                HStack(spacing: 1) {
                    Image(systemName: "arrow.left")
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.tertiary)
                }
            case "one-way-safe":
                Image(systemName: "arrow.right")
            case "one-way-replica":
                Image(systemName: "arrow.right")
                    .fontWeight(.bold)
                    .foregroundStyle(.orange)
            default:
                Image(systemName: "arrow.left.arrow.right")
            }
        }
        .font(.system(size: 9))
        .foregroundStyle(.secondary)
        .help(helpText)
        .accessibilityLabel(helpText)
    }

    private var alphaSideName: String { alphaIsLocal ? "local" : "remote" }
    private var betaSideName: String { alphaIsLocal ? "remote" : "local" }

    private var helpText: String {
        switch mode {
        case "two-way-safe":
            return "Two-way sync: changes flow both ways; conflicts are left for you to resolve."
        case "two-way-resolved":
            return "Two-way sync: conflicts are resolved in favour of the \(alphaSideName) side."
        case "one-way-safe":
            return "One-way sync: only the \(alphaSideName) side propagates; the \(betaSideName) side is left alone."
        case "one-way-replica":
            return "One-way sync (replica): the \(betaSideName) side is overwritten to match the \(alphaSideName) side."
        default:
            return "Sync mode unknown."
        }
    }
}
