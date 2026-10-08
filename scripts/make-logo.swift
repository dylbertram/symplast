// Renders a brand-mark SVG to a transparent PNG using AppKit's native SVG
// support, so curves, transforms and colours are preserved. Run via:
//   swift scripts/make-logo.swift logo.svg Resources/AppLogo.png [size]
//
// The mark is centred and aspect-fitted into a square canvas of `size` pixels.
// Keep the SVG's background transparent: the menu bar treats the PNG as a
// template image (the system tints its alpha channel), and the app icon draws
// it over a tile.
import AppKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("error: " + message + "\n").utf8))
    exit(1)
}

let args = CommandLine.arguments
guard args.count >= 3 else { fail("usage: make-logo.swift <input.svg> <output.png> [size]") }
let inputPath = args[1]
let outputPath = args[2]
let size = args.count >= 4 ? (Int(args[3]) ?? 1024) : 1024

guard let image = NSImage(contentsOfFile: inputPath) else {
    fail("could not read \(inputPath)")
}
guard image.size.width > 0, image.size.height > 0 else {
    fail("\(inputPath) has no drawable size")
}

let dim = CGFloat(size)
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size,
    pixelsHigh: size,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else { fail("could not create bitmap context") }

// Aspect-fit the mark into the square canvas, centred.
let imageAspect = image.size.width / image.size.height
var drawRect = NSRect(x: 0, y: 0, width: dim, height: dim)
if imageAspect > 1 {
    drawRect.size.height = dim / imageAspect
    drawRect.origin.y = (dim - drawRect.size.height) / 2
} else if imageAspect < 1 {
    drawRect.size.width = dim * imageAspect
    drawRect.origin.x = (dim - drawRect.size.width) / 2
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
image.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1)
NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else {
    fail("could not encode PNG")
}
try data.write(to: URL(fileURLWithPath: outputPath))
print("wrote \(outputPath) (\(size)x\(size))")
