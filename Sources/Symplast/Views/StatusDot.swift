import SwiftUI

struct StatusDot: View {
    let state: SyncState
    var diameter: CGFloat = 9

    var body: some View {
        Circle()
            .fill(state.color)
            .frame(width: diameter, height: diameter)
            .overlay(
                Circle().stroke(Color.black.opacity(0.12), lineWidth: 0.5)
            )
            .accessibilityHidden(true)
    }
}
