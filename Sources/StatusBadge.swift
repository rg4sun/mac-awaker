import AppKit

/// Draws a compact, text-free status icon. Both its shape and colour identify
/// the state, so the result stays recognisable on light and dark menu bars.
enum StatusBadge {
    // Keep a small native-sized slot in both states, regardless of the timer.
    // The three-point margins leave room around the eighteen-point artwork.
    static let imageSize = NSSize(width: 18, height: 18)
    static let statusItemLength: CGFloat = 24

    static func image(active: Bool) -> NSImage {
        let background = active
            ? NSColor(srgbRed: 1.0, green: 0.80, blue: 0.30, alpha: 1)
            : NSColor(srgbRed: 0.08, green: 0.32, blue: 0.76, alpha: 1)
        let foreground = active
            ? NSColor(srgbRed: 0.10, green: 0.11, blue: 0.13, alpha: 1)
            : NSColor.white
        let size = imageSize

        let image = NSImage(size: size, flipped: false) { bounds in
            let disc = NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5))
            background.setFill()
            disc.fill()

            // The light rim separates the blue disc from a dark menu bar. Its
            // solid fill also keeps it visible against a bright background.
            NSColor.white.withAlphaComponent(0.75).setStroke()
            disc.lineWidth = 0.65
            disc.stroke()

            let iconFrame = NSRect(x: 2, y: 2, width: 14, height: 14)
            if active {
                drawSun(in: iconFrame, colour: foreground)
            } else {
                drawMoon(in: iconFrame, colour: foreground, background: background)
            }

            return true
        }

        // Template images are recoloured by AppKit. Preserve the badge's own
        // colours, including when the system appearance changes at runtime.
        image.isTemplate = false
        image.accessibilityDescription = active ? "Mac Awaker is on" : "Mac Awaker is off"
        return image
    }

    private static func drawSun(in frame: NSRect, colour: NSColor) {
        colour.setFill()
        colour.setStroke()
        let centre = NSPoint(x: frame.midX, y: frame.midY)
        NSBezierPath(ovalIn: NSRect(x: centre.x - 2.6, y: centre.y - 2.6, width: 5.2, height: 5.2)).fill()

        let rays = NSBezierPath()
        rays.lineWidth = 1.4
        rays.lineCapStyle = .round
        for index in 0..<8 {
            let angle = CGFloat(index) * .pi / 4
            rays.move(to: NSPoint(x: centre.x + cos(angle) * 4.4, y: centre.y + sin(angle) * 4.4))
            rays.line(to: NSPoint(x: centre.x + cos(angle) * 6.2, y: centre.y + sin(angle) * 6.2))
        }
        rays.stroke()
    }

    private static func drawMoon(in frame: NSRect, colour: NSColor, background: NSColor) {
        // Subtract a slightly shifted disc using the solid badge colour. This
        // produces a crisp crescent without an appearance-dependent SF Symbol.
        // Clip the subtraction to the moon so it cannot paint blue pixels
        // outside the circular status icon's otherwise transparent corners.
        NSGraphicsContext.saveGraphicsState()
        let moon = NSBezierPath(ovalIn: frame.insetBy(dx: 1.5, dy: 1.5))
        moon.addClip()
        colour.setFill()
        moon.fill()
        background.setFill()
        NSBezierPath(ovalIn: NSRect(x: frame.minX + 5, y: frame.minY + 4, width: 10, height: 10)).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}
