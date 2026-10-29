// Draws Raven's macOS app icon as an .iconset folder (turn it into Raven.icns with `iconutil`).
//
//   swift scripts/make-icon.swift <raven-mark-1024.png> <tokens.json> <out.iconset>
//
// The Raven mark on a rounded tile that follows the macOS icon grid: on the 1024 px canvas the tile
// is 824 x 824 px, centred, with continuous ("squircle") corners and a soft drop shadow in the
// margin. Colours come from tokens.json (light scheme): the tile runs from `surface` at the top to
// `background` at the bottom, and the mark is drawn in `textPrimary`. Every size is drawn from the
// 1024 px mark (no upscaling, no re-scaling of a finished icon).
//
// Built-in frameworks only (CoreGraphics, ImageIO, Foundation): runs with the Command Line Tools.
import CoreGraphics
import Foundation
import ImageIO

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(("make-icon: " + message + "\n").data(using: .utf8)!)
    exit(1)
}

let args = CommandLine.arguments
guard args.count == 4 else { fail("usage: make-icon.swift <mark.png> <tokens.json> <out.iconset>") }
let markURL = URL(fileURLWithPath: args[1])
let tokensURL = URL(fileURLWithPath: args[2])
let outURL = URL(fileURLWithPath: args[3])

// MARK: Tokens

func lightColour(_ name: String, in tokens: [String: Any]) -> CGColor {
    guard let colours = tokens["color"] as? [String: Any],
          let entry = colours[name] as? [String: Any],
          let hex = entry["light"] as? String else { fail("tokens.json has no color.\(name).light") }
    var digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    if digits.count == 6 { digits += "FF" }
    guard digits.count == 8, let value = UInt32(digits, radix: 16) else { fail("bad colour \(hex)") }
    let c = { (shift: UInt32) in CGFloat((value >> shift) & 0xFF) / 255 }
    return CGColor(srgbRed: c(24), green: c(16), blue: c(8), alpha: c(0))
}

guard let tokensData = try? Data(contentsOf: tokensURL),
      let tokens = (try? JSONSerialization.jsonObject(with: tokensData)) as? [String: Any] else {
    fail("cannot read \(tokensURL.path)")
}
let tileTop = lightColour("surface", in: tokens)
let tileBottom = lightColour("background", in: tokens)
let markColour = lightColour("textPrimary", in: tokens)
let edgeColour = lightColour("border", in: tokens)

// MARK: The mark

guard let source = CGImageSourceCreateWithURL(markURL as CFURL, nil),
      let mark = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fail("cannot read \(markURL.path)") }

let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

func context(_ size: Int) -> CGContext {
    guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                              space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fail("cannot make a \(size) px bitmap")
    }
    ctx.interpolationQuality = .high
    ctx.setShouldAntialias(true)
    return ctx
}

/// The bounding box of the mark's visible pixels (alpha above a small threshold), in image pixels
/// with the origin at the bottom left, so the glyph (not its padding) is centred on the tile.
func visibleBounds(of image: CGImage) -> CGRect {
    let w = image.width, h = image.height
    let ctx = context(max(w, h))
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    guard let data = ctx.data else { return CGRect(x: 0, y: 0, width: w, height: h) }
    let bytes = data.bindMemory(to: UInt8.self, capacity: ctx.bytesPerRow * ctx.height)
    var minX = w, minY = h, maxX = -1, maxY = -1
    for row in 0..<h {
        for x in 0..<w where bytes[row * ctx.bytesPerRow + x * 4 + 3] > 24 {
            // Bitmap rows run top to bottom; flip to bottom-left coordinates.
            let y = ctx.height - 1 - row
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    guard maxX >= minX, maxY >= minY else { return CGRect(x: 0, y: 0, width: w, height: h) }
    return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
}

/// The mark recoloured in `markColour` and made solid. The design file draws the mark as a soft
/// grey (black at about 40% opacity, with some grain), so its alpha is stretched: everything from the
/// 10th percentile of the visible pixels' alpha up becomes fully opaque (solid strokes), the
/// anti-aliased edges scale with it, and faint specks below a quarter of that disappear.
func tintedMark() -> CGImage {
    let w = mark.width, h = mark.height
    let ctx = context(max(w, h))
    ctx.draw(mark, in: CGRect(x: 0, y: 0, width: w, height: h))
    guard let data = ctx.data else { fail("cannot read the mark") }
    let bytes = data.bindMemory(to: UInt8.self, capacity: ctx.bytesPerRow * ctx.height)
    var histogram = [Int](repeating: 0, count: 256)
    for row in 0..<ctx.height {
        for x in 0..<ctx.width { histogram[Int(bytes[row * ctx.bytesPerRow + x * 4 + 3])] += 1 }
    }
    let visible = histogram.enumerated().filter { $0.offset > 24 }
    let total = visible.reduce(0) { $0 + $1.element }
    var seen = 0
    var full = 255
    for (alpha, count) in visible {
        seen += count
        if seen * 10 >= total { full = alpha; break }
    }
    let rgba = markColour.converted(to: srgb, intent: .defaultIntent, options: nil)?.components ?? [0, 0, 0, 1]
    for row in 0..<ctx.height {
        for x in 0..<ctx.width {
            let o = row * ctx.bytesPerRow + x * 4
            let floor = CGFloat(full) / 4
            let a = min(1, max(0, (CGFloat(bytes[o + 3]) - floor) / max(CGFloat(full) - floor, 1))) * rgba[3]
            // Premultiplied RGBA.
            bytes[o] = UInt8((rgba[0] * a * 255).rounded())
            bytes[o + 1] = UInt8((rgba[1] * a * 255).rounded())
            bytes[o + 2] = UInt8((rgba[2] * a * 255).rounded())
            bytes[o + 3] = UInt8((a * 255).rounded())
        }
    }
    guard let image = ctx.makeImage() else { fail("cannot tint the mark") }
    return image
}

// MARK: The tile

/// A superellipse (|x|^5 + |y|^5 = 1): continuous corners close to the macOS icon shape.
func squircle(in rect: CGRect, exponent: CGFloat = 5) -> CGPath {
    let path = CGMutablePath()
    let steps = 720
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = pow(abs(c), 2 / exponent) * (c < 0 ? -1 : 1)
        let y = pow(abs(s), 2 / exponent) * (s < 0 ? -1 : 1)
        let p = CGPoint(x: rect.midX + x * rect.width / 2, y: rect.midY + y * rect.height / 2)
        if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
    }
    path.closeSubpath()
    return path
}

let tinted = tintedMark()
let glyph = visibleBounds(of: mark)

func icon(_ size: Int) -> CGImage {
    let ctx = context(size)
    let s = CGFloat(size) / 1024
    // macOS grid: an 824 px tile on the 1024 px canvas (100 px margin), shadow below it.
    let tile = CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let shape = squircle(in: tile)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * s), blur: 24 * s,
                  color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.28))
    ctx.addPath(shape)
    ctx.setFillColor(tileBottom)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: srgb, colors: [tileTop, tileBottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.minY), options: [])
    ctx.restoreGState()

    // A hairline edge so the light tile holds its shape on a light Dock or desktop.
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.setStrokeColor(edgeColour)
    ctx.setLineWidth(max(1, 2 * s))
    ctx.strokePath()
    ctx.restoreGState()

    // The glyph's longer side takes 66% of the tile, centred on it.
    let target = 824 * s * 0.66
    let scale = target / max(glyph.width, glyph.height)
    let drawn = CGRect(x: tile.midX - (glyph.midX * scale), y: tile.midY - (glyph.midY * scale),
                       width: CGFloat(mark.width) * scale, height: CGFloat(mark.height) * scale)
    ctx.draw(tinted, in: drawn)

    guard let image = ctx.makeImage() else { fail("cannot draw the \(size) px icon") }
    return image
}

// MARK: The iconset

try? FileManager.default.removeItem(at: outURL)
do {
    try FileManager.default.createDirectory(at: outURL, withIntermediateDirectories: true)
} catch {
    fail("cannot create \(outURL.path)")
}
for base in [16, 32, 128, 256, 512] {
    for (scale, suffix) in [(1, ""), (2, "@2x")] {
        let px = base * scale
        let file = outURL.appendingPathComponent("icon_\(base)x\(base)\(suffix).png")
        guard let dest = CGImageDestinationCreateWithURL(file as CFURL, "public.png" as CFString, 1, nil) else {
            fail("cannot write \(file.path)")
        }
        CGImageDestinationAddImage(dest, icon(px), [kCGImagePropertyDPIWidth: 72 * scale,
                                                   kCGImagePropertyDPIHeight: 72 * scale] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { fail("cannot write \(file.path)") }
    }
}
print("make-icon: \(outURL.path)")
