import SwiftUI

/// Keep the AppKit popover and SwiftUI content on the same sizing grid.
enum Layout {
    static let panelWidth: CGFloat = 396
    static let headerHeight: CGFloat = 44
    static let footerHeight: CGFloat = 36
    static let sessionRowHeight: CGFloat = 88
    static let savedRowHeight: CGFloat = 48
    static let sectionHeight: CGFloat = 22
    static let bannerHeight: CGFloat = 100
    static let errorHeight: CGFloat = 52
    static let formHeight: CGFloat = 460
    static let settingsHeight: CGFloat = 396

    static func listHeight(sessionCount: Int, savedCount: Int, daemonAvailable: Bool, hasError: Bool) -> CGFloat {
        var height = headerHeight + footerHeight + 2
        if sessionCount + savedCount == 0 {
            height += 144
        } else {
            if sessionCount > 0 {
                if savedCount > 0 { height += sectionHeight }
                height += CGFloat(sessionCount) * sessionRowHeight
            }
            if savedCount > 0 {
                height += sectionHeight + CGFloat(savedCount) * savedRowHeight
            }
            height += 4
        }
        if !daemonAvailable { height += bannerHeight }
        if hasError && daemonAvailable { height += errorHeight }
        return min(620, height)
    }
}

struct PanelHeader: View {
    let title: String
    let back: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            PanelIconButton(symbol: "chevron.left", label: "Back", action: back)
            Text(title).font(.system(size: 13, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(height: Layout.headerHeight)
    }
}

struct PanelIconButton: View {
    let symbol: String
    let label: String
    var disabled = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 24, height: 24)
                .background(isHovered && !disabled ? Color.primary.opacity(0.07) : .clear,
                            in: RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
        .onHover { isHovered = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}

struct PanelSection<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8, content: content)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StatusLabel: View {
    let state: SyncState

    var body: some View {
        Label(state.label, systemImage: state.symbol)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(state.color)
            .fixedSize()
    }
}

/// Make the label and surrounding row part of the disclosure's button, rather
/// than limiting the target to the native macOS disclosure triangle.
struct FullWidthDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                configuration.isExpanded.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: configuration.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .frame(width: 10)
                        .accessibilityHidden(true)
                    configuration.label
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(configuration.isExpanded ? "Expanded" : "Collapsed")
            if configuration.isExpanded {
                configuration.content
            }
        }
    }
}

struct InlineError: View {
    let message: String

    var body: some View {
        Label {
            Text(message).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.circle.fill")
        }
        .font(.system(size: 11))
        .foregroundStyle(PanelColors.critical)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }
}
