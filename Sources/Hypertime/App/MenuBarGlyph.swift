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
}
