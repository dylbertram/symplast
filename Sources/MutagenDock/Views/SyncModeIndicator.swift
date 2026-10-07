import SwiftUI

/// The sync-direction indicator shown between the two endpoints.
///
/// - Two-way (safe): the bidirectional arrow.
/// - Two-way (resolved): the same bidirectional arrow plus a trophy on the side
///   that wins conflicts. Mutagen resolves in favour of the *alpha* side, which
///   is always the left-hand endpoint here (a "remote wins" session is stored
///   with the remote listed first).
/// - One-way (safe): a single arrow from alpha to beta.
/// - One-way (replica): a single, bolder orange arrow (beta is overwritten).
struct SyncModeIndicator: View {
    let mode: String?
    let alphaIsLocal: Bool
    var vertical = false

    var body: some View {
        Group {
            switch mode {
            case "two-way-safe":
                bidirectional
            case "two-way-resolved":
                if vertical {
                    VStack(spacing: 2) {
                        trophy
                        bidirectional
                    }
                } else {
                    HStack(spacing: 2) {
                        trophy
                        bidirectional
                    }
                }
            case "one-way-safe":
                Image(systemName: vertical ? "arrow.down" : "arrow.right")
            case "one-way-replica":
                Image(systemName: vertical ? "arrow.down" : "arrow.right")
                    .fontWeight(.bold)
                    .foregroundStyle(PanelColors.warning)
            default:
                bidirectional
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .help(helpText)
        .accessibilityLabel(helpText)
    }

    private var bidirectional: some View {
        Image(systemName: vertical ? "arrow.up.arrow.down" : "arrow.left.arrow.right")
    }

    private var trophy: some View {
        Image(systemName: "trophy.fill")
            .foregroundStyle(PanelColors.warning)
    }

    private var alphaSideName: String { alphaIsLocal ? "local" : "remote" }
    private var betaSideName: String { alphaIsLocal ? "remote" : "local" }

    private var helpText: String {
        switch mode {
        case "two-way-safe":
            return "Two-way sync: changes flow both ways; conflicts are left for you to resolve."
        case "two-way-resolved":
            return "Two-way sync: conflicts are resolved in favour of the \(alphaSideName) side (trophy)."
        case "one-way-safe":
            return "One-way sync: only the \(alphaSideName) side propagates; the \(betaSideName) side is left alone."
        case "one-way-replica":
            return "One-way sync (replica): the \(betaSideName) side is overwritten to match the \(alphaSideName) side."
        default:
            return "Sync mode unknown."
        }
    }
}
