import SwiftUI

/// The small icon shown in the macOS menu bar.
struct MenuBarLabel: View {
    @ObservedObject var store: AppStore

    var body: some View {
        // Menu bar labels are rendered as templates, so rely on the symbol
        // shape (and the count) rather than color to convey state.
        HStack(spacing: 3) {
            Image(systemName: store.worstState.menuBarSymbol)
            if store.settings.showCount, !store.sessions.isEmpty {
                Text("\(store.sessions.count)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
        }
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        if !store.daemonAvailable { return "Mutagen daemon unavailable" }
        if store.sessions.isEmpty { return "Mutagen: no sessions" }
        if store.disconnectedCount > 0 {
            return "Mutagen: \(store.disconnectedCount) disconnected"
        }
        return "Mutagen: \(store.sessions.count) sessions, \(store.worstState.label)"
    }
}
