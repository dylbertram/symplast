// Builds an app-icon PNG from the white Mutagen mark: a rounded "squircle"
// tile with a subtle dark gradient and the mark centred on it.
//   swift scripts/make-icon.swift Resources/MutagenLogo.png Resources/AppIcon-1024.png 1024
import AppKit
import CoreGraphics
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("error: " + message + "\n").utf8))
    exit(1)
}

let args = CommandLine.arguments
guard args.count >= 3 else { fail("usage: make-icon.swift <mark.png> <out.png> [size]") }
let markPath = args[1]
let outPath = args[2]
let size = args.count >= 4 ? (Int(args[3]) ?? 1024) : 1024

guard let markImage = NSImage(contentsOfFile: markPath) else { fail("could not read \(markPath)") }
var proposed = NSRect(x: 0, y: 0, width: markImage.size.width, height: markImage.size.height)
guard let markCG = markImage.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else {
    fail("could not get CGImage for mark")
}

let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fail("could not create context") }

let dim = CGFloat(size)
ctx.clear(CGRect(x: 0, y: 0, width: dim, height: dim))

// Rounded tile (macOS icon grid: ~82% with a large corner radius).
let inset = dim * 0.098
let tile = CGRect(x: inset, y: inset, width: dim - inset * 2, height: dim - inset * 2)
let radius = tile.width * 0.2237
let tilePath = CGPath(roundedRect: tile, cornerWidth: radius, cornerHeight: radius, transform: nil)

let colors = [
    CGColor(red: 0.16, green: 0.18, blue: 0.22, alpha: 1),
    CGColor(red: 0.06, green: 0.07, blue: 0.09, alpha: 1)
] as CFArray
if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 1]) {
    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: dim),
        end: CGPoint(x: 0, y: 0),
        options: []
    )
    ctx.restoreGState()
}

// White mark centred on the tile.
let markSide = tile.width * 0.70
let markRect = CGRect(
    x: (dim - markSide) / 2,
    y: (dim - markSide) / 2,
    width: markSide,
    height: markSide
)
ctx.draw(markCG, in: markRect)

guard let image = ctx.makeImage() else { fail("could not rasterize") }
let rep = NSBitmapImageRep(cgImage: image)
guard let data = rep.representation(using: .png, properties: [:]) else { fail("could not encode PNG") }
try data.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath) (\(size)x\(size))")
