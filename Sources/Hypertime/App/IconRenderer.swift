import AppKit
import SwiftUI

/// `--render-icon <out-dir> <appiconset-dir>`: turns the handoff's full-bleed PNGs into an
/// `AppIcon.iconset` that `iconutil` can pack, applying the macOS icon mask on the way.
///
/// `APPICON.md` says not to pre-round or pre-shadow, because macOS 26 masks app icons itself.
/// macOS 15 — this app's deployment target — does not: it draws the file as it is, so a
/// full-bleed square renders as a square in a Dock full of squircles. Apple's own icons on 15
/// have the shape baked in (measured on Calculator.app: art inset to 80.47 % of the canvas with
/// a soft shadow below), so that is what is reproduced here. The full-bleed originals stay in
/// `Resources/AppIcon.appiconset/` untouched, ready for the day the mask comes from the system.
@MainActor
enum IconRenderer {

    /// Apple's macOS icon grid: 824 pt of art on a 1024 pt canvas, corner radius 185.4 pt.
    private static let artRatio: CGFloat = 824.0 / 1024.0
    private static let cornerRatio: CGFloat = 185.4 / 824.0
    private static let shadowAlpha: CGFloat = 0.28
    private static let shadowBlurRatio: CGFloat = 0.035
    private static let shadowOffsetRatio: CGFloat = 0.015

    /// Canvas pixel sizes an `.icns` needs, named the way `iconutil` expects.
    private static let slots: [(name: String, canvas: Int)] = [
        ("icon_16x16", 16), ("icon_16x16@2x", 32),
        ("icon_32x32", 32), ("icon_32x32@2x", 64),
        ("icon_128x128", 128), ("icon_128x128@2x", 256),
        ("icon_256x256", 256), ("icon_256x256@2x", 512),
        ("icon_512x512", 512), ("icon_512x512@2x", 1024),
    ]

    /// The handoff ships a simplified glyph for the small slots (no crown tick, heavier stroke,
    /// white dot). Both variants are resampled from their largest rendition.
    private static let masterSource = "icon_512x512-2x.png"      // 1024 px
    private static let smallSource = "icon_32x32-2x.png"         //   64 px
    private static let smallVariantMaxCanvas = 64

    static func run(source: String, into directory: String) -> Bool {
        let sourceURL = URL(fileURLWithPath: source, isDirectory: true)
        guard let master = NSImage(contentsOf: sourceURL.appendingPathComponent(masterSource)),
              let small = NSImage(contentsOf: sourceURL.appendingPathComponent(smallSource))
        else {
            FileHandle.standardError.write(Data("render-icon: no source PNGs in \(source)\n".utf8))
            return false
        }

        let iconset = URL(fileURLWithPath: directory, isDirectory: true).appendingPathComponent("AppIcon.iconset")
        try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

        for slot in slots {
            let artwork = slot.canvas <= smallVariantMaxCanvas ? small : master
            guard let png = maskedIcon(artwork, canvas: slot.canvas) else { return false }
            do {
                try png.write(to: iconset.appendingPathComponent(slot.name + ".png"))
            } catch {
                return false
            }
        }
        return true
    }

    /// Draws the full-bleed artwork into the macOS icon shape at an exact pixel size.
    static func maskedIcon(_ artwork: NSImage, canvas: Int) -> Data? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: canvas, pixelsHigh: canvas,
                                         bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep)
        else { return nil }
        rep.size = NSSize(width: canvas, height: canvas)          // one point per pixel

        let size = CGFloat(canvas)
        let art = NSRect(x: 0, y: 0, width: size, height: size)
            .insetBy(dx: size * (1 - artRatio) / 2, dy: size * (1 - artRatio) / 2)
        let shape = NSBezierPath(cgPath: Path(roundedRect: art,
                                              cornerRadius: art.width * cornerRatio,
                                              style: .continuous).cgPath)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high

        // The shadow is cast by the shape itself, then the artwork is clipped inside it.
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(white: 0, alpha: shadowAlpha)
        shadow.shadowBlurRadius = art.width * shadowBlurRatio
        shadow.shadowOffset = NSSize(width: 0, height: -art.width * shadowOffsetRatio)
        shadow.set()
        NSColor.black.setFill()
        shape.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        artwork.draw(in: art, from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()

        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        return rep.representation(using: .png, properties: [:])
    }
}
