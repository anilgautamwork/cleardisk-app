import AppKit

/// ClearDisk's violet C and sparkle. Shared by the running app and the
/// distribution icon renderer so the welcome screen, Dock and DMG agree.
enum AppIcon {
    static let image = makeImage(size: 512)

    static func makeImage(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
            let transform = NSAffineTransform()
            transform.scale(by: size / 512)
            transform.concat()

            let tile = NSBezierPath(
                roundedRect: NSRect(x: 24, y: 24, width: 464, height: 464),
                xRadius: 116, yRadius: 116)
            let light = NSColor(srgbRed: 199 / 255, green: 183 / 255, blue: 1, alpha: 1)
            let deep = NSColor(srgbRed: 121 / 255, green: 96 / 255, blue: 206 / 255, alpha: 1)
            NSGradient(starting: light, ending: deep)!.draw(in: tile, angle: 45)

            let markTransform = NSAffineTransform()
            markTransform.translateX(by: 56, yBy: 56)
            markTransform.scale(by: 10)
            markTransform.concat()

            let ring = NSBezierPath()
            ring.appendArc(withCenter: NSPoint(x: 20, y: 20), radius: 13,
                           startAngle: -52, endAngle: 38, clockwise: true)
            ring.lineWidth = 5.5
            ring.lineCapStyle = .round
            NSColor.white.setStroke()
            ring.stroke()

            let sparkle = NSBezierPath()
            sparkle.move(to: NSPoint(x: 27, y: 5))
            for point in [(28.8, 10.2), (34.0, 12.0), (28.8, 13.8),
                          (27.0, 19.0), (25.2, 13.8), (20.0, 12.0),
                          (25.2, 10.2)] {
                sparkle.line(to: NSPoint(x: point.0, y: point.1))
            }
            sparkle.close()
            NSColor.white.setFill()
            sparkle.fill()
            return true
        }
    }
}
