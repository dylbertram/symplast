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

    /// The logo natively sized for the menu bar. With no tint it is a template
    /// image (auto-tinted by the system); with a tint the colour is baked in,
    /// which is more reliable than `contentTintColor` for status items.
    static func menuBarImage(height: CGFloat = 18, tint: NSColor? = nil) -> NSImage? {
        guard let base = logo() else { return nil }
        let aspect = base.size.height > 0 ? base.size.width / base.size.height : 1
        let pointSize = NSSize(width: (height * aspect).rounded(), height: height)

        guard let tint else {
            let image = (base.copy() as? NSImage) ?? base
            image.isTemplate = true
            image.size = pointSize
            return image
        }

        let scale: CGFloat = 2
        let pixelSize = NSSize(width: pointSize.width * scale, height: pointSize.height * scale)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(pixelSize.width),
            pixelsHigh: Int(pixelSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        base.draw(in: NSRect(origin: .zero, size: pixelSize))
        tint.set()
        NSRect(origin: .zero, size: pixelSize).fill(using: .sourceAtop)
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: pointSize)
        image.addRepresentation(rep)
        return image
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
