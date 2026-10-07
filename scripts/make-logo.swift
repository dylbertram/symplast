// Rasterizes a simple polygon-only SVG (the Mutagen logo) to a transparent PNG
// so it can be used as a macOS template image. Run via:
//   swift scripts/make-logo.swift logo_light.svg Resources/MutagenLogo.png
import AppKit
import CoreGraphics
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

guard let svg = try? String(contentsOfFile: inputPath, encoding: .utf8) else {
    fail("could not read \(inputPath)")
}

// Extract each path's "d" attribute.
var pathData: [String] = []
if let regex = try? NSRegularExpression(pattern: "(?<!i)d=\"([^\"]+)\"") {
    let range = NSRange(svg.startIndex..., in: svg)
    regex.enumerateMatches(in: svg, range: range) { match, _, _ in
        if let match, let r = Range(match.range(at: 1), in: svg) {
            pathData.append(String(svg[r]))
        }
    }
}
guard !pathData.isEmpty else { fail("no <path d> found in \(inputPath)") }

enum Token { case command(Character); case number(CGFloat) }

func tokenize(_ d: String) -> [Token] {
    var tokens: [Token] = []
    var buffer = ""
    func flush() {
        if !buffer.isEmpty, let value = Double(buffer) { tokens.append(.number(CGFloat(value))) }
        buffer = ""
    }
    for ch in d {
        if ch.isLetter {
            flush()
            tokens.append(.command(ch))
        } else if ch == "," || ch == " " || ch == "\n" || ch == "\t" || ch == "\r" {
            flush()
        } else if ch == "-" || ch == "+" {
            flush()
            buffer.append(ch)
        } else {
            buffer.append(ch)
        }
    }
    flush()
    return tokens
}

func cgPath(_ d: String) -> CGPath {
    let path = CGMutablePath()
    var current = CGPoint.zero
    var subpathStart = CGPoint.zero
    var command: Character = "M"
    var numbers: [CGFloat] = []

    func apply() {
        switch command {
        case "M", "L", "m", "l":
            var i = 0
            while i + 1 < numbers.count {
                var x = numbers[i], y = numbers[i + 1]
                if command == "m" || command == "l" {
                    x += current.x; y += current.y
                }
                let point = CGPoint(x: x, y: y)
                if i == 0 && (command == "M" || command == "m") {
                    path.move(to: point)
                    subpathStart = point
                } else {
                    path.addLine(to: point)
                }
                current = point
                i += 2
            }
        case "Z", "z":
            path.closeSubpath()
            current = subpathStart
        default:
            break
        }
        numbers.removeAll()
    }

    for token in tokenize(d) {
        switch token {
        case .command(let c):
            apply()
            command = c
        case .number(let n):
            numbers.append(n)
        }
    }
    apply()
    return path
}

let paths = pathData.map(cgPath)

let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let context = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fail("could not create bitmap context") }

context.clear(CGRect(x: 0, y: 0, width: size, height: size))

// SVG coordinates are 0..1024 with y pointing down; flip to CoreGraphics.
let scale = CGFloat(size) / 1024.0
context.translateBy(x: 0, y: CGFloat(size))
context.scaleBy(x: scale, y: -scale)
context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
for path in paths {
    context.addPath(path)
    context.fillPath(using: .evenOdd)
}

guard let image = context.makeImage() else { fail("could not rasterize") }

let rep = NSBitmapImageRep(cgImage: image)
guard let data = rep.representation(using: .png, properties: [:]) else {
    fail("could not encode PNG")
}
try data.write(to: URL(fileURLWithPath: outputPath))
print("wrote \(outputPath) (\(size)x\(size), \(paths.count) paths)")
