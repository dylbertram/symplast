import AppKit
import SwiftUI

/// Loads bundled brand assets (the Mutagen logo).
enum BrandAssets {
    /// The logo as shipped in the app bundle, if available.
    static func logo() -> NSImage? {
        if let image = NSImage(named: "MutagenLogo") {
            return image
        }
        if let url = Bundle.main.url(forResource: "MutagenLogo", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return nil
    }

    /// A template copy sized for the menu bar (auto-tinted by the system).
    static func menuBarImage(height: CGFloat = 18) -> NSImage? {
        guard let base = logo()?.copy() as? NSImage else { return nil }
        base.isTemplate = true
        let aspect = base.size.height > 0 ? base.size.width / base.size.height : 1
        base.size = NSSize(width: (height * aspect).rounded(), height: height)
        return base
    }
}

/// The Mutagen logo, tinted like the surrounding content. Falls back to an SF
/// Symbol if the asset is missing (e.g. when run outside the app bundle).
struct BrandLogo: View {
    var size: CGFloat = 16
    var color: Color?

    var body: some View {
        Group {
            if let image = BrandAssets.logo() {
                Image(nsImage: image)
                    .renderingMode(.template)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }
        .frame(width: size, height: size)
        .foregroundStyle(color ?? .primary)
    }
}
