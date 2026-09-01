import AppKit

/// Programmatic Dock icon matching the design canvas (blue rounded square,
/// white disk cylinder, sparkle). A real .icns asset comes with the Xcode
/// bundle at distribution time.
enum AppIcon {
    static let image: NSImage = {
        NSImage(size: NSSize(width: 512, height: 512), flipped: false) { rect in
            let blue = NSColor(red: 0, green: 0.443, blue: 0.89, alpha: 1)
            let bg = NSBezierPath(roundedRect: rect.insetBy(dx: 24, dy: 24),
                                  xRadius: 116, yRadius: 116)
            blue.setFill()
            bg.fill()

            NSColor.white.setStroke()
            let stroke: CGFloat = 22

            // Disk cylinder: top ellipse, sides, two belly arcs.
            let topRect = NSRect(x: 130, y: 306, width: 252, height: 96)
            let top = NSBezierPath(ovalIn: topRect)
            top.lineWidth = stroke
            top.stroke()

            let sides = NSBezierPath()
            sides.move(to: NSPoint(x: 130, y: 354))
            sides.line(to: NSPoint(x: 130, y: 170))
            sides.move(to: NSPoint(x: 382, y: 354))
            sides.line(to: NSPoint(x: 382, y: 170))
            sides.lineWidth = stroke
            sides.lineCapStyle = .round
            sides.stroke()

            for bottomY in [230.0, 170.0] {
                let belly = NSBezierPath()
                belly.move(to: NSPoint(x: 130, y: bottomY))
                belly.curve(to: NSPoint(x: 382, y: bottomY),
                            controlPoint1: NSPoint(x: 170, y: bottomY - 52),
                            controlPoint2: NSPoint(x: 342, y: bottomY - 52))
                belly.lineWidth = stroke
                belly.lineCapStyle = .round
                belly.stroke()
            }

            // Sparkle, bottom right.
            let sparkle = NSBezierPath()
            let cx = 400.0, cy = 118.0, r = 46.0, inner = 13.0
            sparkle.move(to: NSPoint(x: cx, y: cy + r))
            sparkle.curve(to: NSPoint(x: cx + r, y: cy),
                          controlPoint1: NSPoint(x: cx + inner, y: cy + inner),
                          controlPoint2: NSPoint(x: cx + inner, y: cy + inner))
            sparkle.curve(to: NSPoint(x: cx, y: cy - r),
                          controlPoint1: NSPoint(x: cx + inner, y: cy - inner),
                          controlPoint2: NSPoint(x: cx + inner, y: cy - inner))
            sparkle.curve(to: NSPoint(x: cx - r, y: cy),
                          controlPoint1: NSPoint(x: cx - inner, y: cy - inner),
                          controlPoint2: NSPoint(x: cx - inner, y: cy - inner))
            sparkle.curve(to: NSPoint(x: cx, y: cy + r),
                          controlPoint1: NSPoint(x: cx - inner, y: cy + inner),
                          controlPoint2: NSPoint(x: cx - inner, y: cy + inner))
            sparkle.close()
            NSColor.white.setFill()
            sparkle.fill()

            return true
        }
    }()
}
