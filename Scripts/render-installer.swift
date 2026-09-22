import AppKit

// Finder background in points; a 2x bitmap keeps labels and the arrow sharp.
let width: CGFloat = 520, height: CGFloat = 580
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1040, pixelsHigh: 1160,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
bitmap.size = NSSize(width: width, height: height)
let context = NSGraphicsContext(bitmapImageRep: bitmap)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
NSColor.white.setFill()
NSRect(x: 0, y: 0, width: width, height: height).fill()
func text(_ value: String, top: CGFloat, size: CGFloat, color: NSColor, weight: NSFont.Weight) {
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    (value as NSString).draw(in: NSRect(x: 24, y: height - top - 40, width: width - 48, height: 40),
        withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: style])
}
text("Install ClearDisk", top: 32, size: 26, color: .black, weight: .semibold)
text("A little more room for what matters.", top: 74, size: 14,
     color: NSColor(white: 0.38, alpha: 1), weight: .regular)
NSColor(red: 0.94, green: 0.92, blue: 0.99, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 145, y: height - 495, width: 230, height: 160), xRadius: 20, yRadius: 20).fill()
NSColor(red: 0.48, green: 0.32, blue: 0.79, alpha: 1).setFill()
let arrow = NSBezierPath()
for (i, point) in [(250.0, 266.0), (270, 266), (270, 296), (286, 296), (260, 324), (234, 296), (250, 296)].enumerated() {
    let p = NSPoint(x: point.0, y: height - point.1)
    if i == 0 { arrow.move(to: p) } else { arrow.line(to: p) }
}
arrow.close(); arrow.fill()
text("Drag ClearDisk into Applications to install.", top: 531, size: 14,
     color: NSColor(white: 0.30, alpha: 1), weight: .medium)
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .tiff, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
