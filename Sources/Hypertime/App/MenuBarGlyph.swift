import AppKit

import Foundation

/// Menu bar glyphs drawn from `docs/design-handoff/handoff/assets/menubar-*.svg` (18×18 template,
/// optically ~14 pt). Drawn with Core Graphics so they stay crisp at every scale factor without
/// shipping raster assets.
enum MenuBarGlyph {
    enum State {
        case idle, tracking, paused
    }

    static func image(_ state: State) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()

            // Crown: M7.8 1.5h2.4
            let crown = NSBezierPath()
            crown.move(to: NSPoint(x: 7.8, y: 1.5))
            crown.line(to: NSPoint(x: 10.2, y: 1.5))
            crown.lineWidth = 1.5
            crown.lineCapStyle = .round
            crown.stroke()

            // Dial: circle cx 9 cy 10 r 6
            let dial = NSBezierPath(ovalIn: NSRect(x: 3, y: 4, width: 12, height: 12))
            dial.lineWidth = 1.5
            dial.stroke()

            switch state {
            case .idle:
                break
            case .tracking:
                // circle cx 9 cy 10 r 2.4
                NSBezierPath(ovalIn: NSRect(x: 6.6, y: 7.6, width: 4.8, height: 4.8)).fill()
            case .paused:
                // M7.5 8v4 M10.5 8v4
                let bars = NSBezierPath()
                bars.move(to: NSPoint(x: 7.5, y: 8));  bars.line(to: NSPoint(x: 7.5, y: 12))
                bars.move(to: NSPoint(x: 10.5, y: 8)); bars.line(to: NSPoint(x: 10.5, y: 12))
                bars.lineWidth = 1.5
                bars.lineCapStyle = .round
                bars.stroke()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    /// The app icon, from `assets/appicon.svg`: gradient rounded rect plus the tracking glyph.
    /// `size` is the pixel size of the square icon.
    static func appIcon(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            let scale = size / 1024

            let corner = 232 * scale
            let path = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)
            path.addClip()

            let background = NSGradient(colorsAndLocations:
                (NSColor(hex: "#3E4D7D"), 0),
                (NSColor(hex: "#1D2340"), 0.58),
                (NSColor(hex: "#111524"), 1))
            // The drawing context is flipped, so positive angles run downward.
            background?.draw(in: rect, angle: 61)

            let highlight = NSGradient(colorsAndLocations:
                (NSColor(white: 1, alpha: 0.28), 0),
                (NSColor(white: 1, alpha: 0), 0.25))
            highlight?.draw(in: rect, angle: 90)

            // translate(512,512) scale(56.9) translate(-9,-9)
            let glyphScale = 56.9 * scale
            let transform = NSAffineTransform()
            transform.translateX(by: size / 2, yBy: size / 2)
            transform.scale(by: glyphScale)
            transform.translateX(by: -9, yBy: -9)
            transform.concat()

            NSColor(white: 1, alpha: 0.92).setStroke()
            let crown = NSBezierPath()
            crown.move(to: NSPoint(x: 7.8, y: 1.5))
            crown.line(to: NSPoint(x: 10.2, y: 1.5))
            crown.lineWidth = 1.3
            crown.lineCapStyle = .round
            crown.stroke()

            let dial = NSBezierPath(ovalIn: NSRect(x: 3, y: 4, width: 12, height: 12))
            dial.lineWidth = 1.3
            dial.stroke()

            NSColor(hex: "#0A84FF").setFill()
            NSBezierPath(ovalIn: NSRect(x: 6.8, y: 7.8, width: 4.4, height: 4.4)).fill()
            return true
        }
    }
}

/// `--render-icon <dir>`: writes `AppIcon.iconset` from the vector definition above so the
/// build script can run `iconutil` without shipping raster sources.
@MainActor
enum IconRenderer {
    static func run(directory: String) -> Bool {
        let iconset = URL(fileURLWithPath: directory, isDirectory: true).appendingPathComponent("AppIcon.iconset")
        try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

        let variants: [(name: String, size: CGFloat)] = [
            ("icon_16x16", 16), ("icon_16x16@2x", 32),
            ("icon_32x32", 32), ("icon_32x32@2x", 64),
            ("icon_128x128", 128), ("icon_128x128@2x", 256),
            ("icon_256x256", 256), ("icon_256x256@2x", 512),
            ("icon_512x512", 512), ("icon_512x512@2x", 1024),
        ]

        for variant in variants {
            let image = MenuBarGlyph.appIcon(size: variant.size)
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:])
            else { return false }
            do {
                try png.write(to: iconset.appendingPathComponent(variant.name + ".png"))
            } catch {
                return false
            }
        }
        return true
    }
}
