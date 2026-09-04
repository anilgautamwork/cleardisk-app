// Compile with AppIcon.swift so packaging uses the app's exact brand drawing:
// swiftc Sources/ClearDiskApp/AppIcon.swift Scripts/render-icon.swift -o /tmp/cleardisk-render-icon
import AppKit

@main
enum RenderIcon {
    static func main() throws {
        let output = CommandLine.arguments.count > 1
            ? CommandLine.arguments[1] : "/tmp/cleardisk_icon_1024.png"
        let image = AppIcon.makeImage(size: 1024)
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "ClearDisk.Icon", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Could not render app icon"])
        }
        try png.write(to: URL(fileURLWithPath: output))
        print("wrote \(output)")
    }
}
