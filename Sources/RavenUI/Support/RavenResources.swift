import Foundation
import AppKit

/// Finds the bundled design files (strings, tokens, word list, logo).
///
/// SwiftPM's generated `Bundle.module` only looks next to the executable and in the build folder.
/// Inside Raven.app the resource bundle lives in Contents/Resources, so look there first.
public enum RavenResources {
    static let bundleName = "Raven_RavenUI.bundle"

    public static let bundle: Bundle = {
        let candidates: [URL?] = [
            Bundle.main.resourceURL,
            Bundle.main.bundleURL,
            Bundle.main.executableURL?.deletingLastPathComponent(),
        ]
        for base in candidates.compactMap({ $0 }) {
            if let found = Bundle(url: base.appendingPathComponent(bundleName)) { return found }
        }
        return Bundle.module
    }()

    /// URL of a bundled file, e.g. `url("strings.en", "json")`.
    public static func url(_ name: String, _ ext: String) -> URL? {
        bundle.url(forResource: name, withExtension: ext, subdirectory: "Resources")
            ?? bundle.url(forResource: name, withExtension: ext)
    }

    public static func data(_ name: String, _ ext: String) -> Data? {
        guard let url = url(name, ext) else { return nil }
        return try? Data(contentsOf: url)
    }

    /// The mark made solid (the design file draws it as a 40% grey): every drawn pixel at full
    /// strength, for the Calm sidebar, the Network page and About, where it is tinted by the text colour.
    public static func solidMark(size: CGFloat) -> NSImage {
        let key = Int(size.rounded())
        solidLock.lock()
        defer { solidLock.unlock() }
        if let cached = solidCache[key] { return cached }
        let source = mark(size: max(size, 64))
        var rect = CGRect(origin: .zero, size: source.size)
        guard let cg = source.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return mark(size: size, template: true) }
        let w = cg.width, h = cg.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let made: NSImage? = pixels.withUnsafeMutableBytes { buffer -> NSImage? in
            guard let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            // The design file's strength (a 40% grey): the 98th percentile of the drawn pixels' alpha.
            let drawn = stride(from: 3, to: buffer.count, by: 4).map { buffer[$0] }.filter { $0 > 8 }.sorted()
            let peak = drawn.isEmpty ? 255 : drawn[min(drawn.count - 1, drawn.count * 98 / 100)]
            let gain = peak > 0 ? 255.0 / Double(peak) : 1
            for i in stride(from: 0, to: buffer.count, by: 4) {
                let a = UInt8(min(255, Double(buffer[i + 3]) * gain))
                buffer[i] = 0; buffer[i + 1] = 0; buffer[i + 2] = 0; buffer[i + 3] = a
            }
            guard let out = ctx.makeImage() else { return nil }
            let image = NSImage(cgImage: out, size: NSSize(width: size, height: size))
            image.isTemplate = true
            return image
        }
        let result = made ?? mark(size: size, template: true)
        solidCache[key] = result
        return result
    }

    private static let solidLock = NSLock()
    nonisolated(unsafe) private static var solidCache: [Int: NSImage] = [:]

    /// The Raven mark (grey on transparent). `template` makes it follow the menu bar's colour.
    public static func mark(size: CGFloat, template: Bool = false) -> NSImage {
        let file = size <= 24 ? "raven-mark-64" : "raven-mark-1024"
        let image = url(file, "png").flatMap { NSImage(contentsOf: $0) } ?? NSImage(size: NSSize(width: size, height: size))
        let copy = image.copy() as? NSImage ?? image
        copy.size = NSSize(width: size, height: size)
        copy.isTemplate = template
        return copy
    }
}
