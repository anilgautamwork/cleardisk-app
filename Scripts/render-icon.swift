// Renders the ClearDisk icon to a 1024px PNG (same drawing as
// Sources/ClearDiskApp/AppIcon.swift, scaled 2x). Usage:
//   swift Scripts/render-icon.swift /tmp/cleardisk_icon_1024.png
import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/cleardisk_icon_1024.png"

let image = NSImage(size: NSSize(width: 1024, height: 1024), flipped: false) { rect in
    let scale = NSAffineTransform()
    scale.scale(by: 2)
    scale.concat()
    let base = NSRect(x: 0, y: 0, width: 512, height: 512)

    let blue = NSColor(red: 0, green: 0.443, blue: 0.89, alpha: 1)
    let bg = NSBezierPath(roundedRect: base.insetBy(dx: 24, dy: 24), xRadius: 116, yRadius: 116)
    blue.setFill()
    bg.fill()

    NSColor.white.setStroke()
    let stroke: CGFloat = 22

    let top = NSBezierPath(ovalIn: NSRect(x: 130, y: 306, width: 252, height: 96))
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

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fputs("failed to render icon\n", stderr)
    exit(1)
}
try png.write(to: URL(fileURLWithPath: output))
print("wrote \(output)")
