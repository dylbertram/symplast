import AppKit
import SwiftUI

/// System colours in dark mode, with deeper light-mode variants so small status
/// text remains legible on pale badges and banners.
enum PanelColors {
    static let success = adaptive(light: NSColor(calibratedRed: 0.10, green: 0.43, blue: 0.24, alpha: 1), dark: .systemGreen)
    static let warning = adaptive(light: NSColor(calibratedRed: 0.58, green: 0.31, blue: 0.02, alpha: 1), dark: .systemOrange)
    static let critical = adaptive(light: NSColor(calibratedRed: 0.74, green: 0.18, blue: 0.15, alpha: 1), dark: .systemRed)

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}
