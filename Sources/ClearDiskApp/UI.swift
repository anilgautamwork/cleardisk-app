import Core
import SwiftUI

/// Palette lifted from the approved design canvas (Apple-native direction).
enum UI {
    static let accent = Color(hex: 0x0071E3)
    static let textPrimary = Color(hex: 0x1D1D1F)
    static let textSecondary = Color(hex: 0x6E6E73)
    static let sidebar = Color(hex: 0xF5F5F7)
    static let cardBorder = Color(hex: 0xE8E8ED)
    static let safeText = Color(hex: 0x1D7A3E)
    static let safeBG = Color(hex: 0xE5F6EC)
    static let reviewText = Color(hex: 0xB25E09)
    static let reviewBG = Color(hex: 0xFFF4E5)
    static let leaveText = Color(hex: 0x6E6E73)
    static let leaveBG = Color(hex: 0xF0F0F2)
    static let selectedRowBG = Color(hex: 0xF0F7FF)
    static let selectedRowBorder = Color(hex: 0xCFE5FF)

    static func color(for category: Core.Category) -> Color {
        switch category {
        case .photosVideos: Color(hex: 0xAF52DE)
        case .music: Color(hex: 0xFF2D55)
        case .documents: Color(hex: 0x32ADE6)
        case .apps: Color(hex: 0x007AFF)
        case .downloads: Color(hex: 0x34C759)
        case .mail: Color(hex: 0x5856D6)
        case .devJunk: Color(hex: 0xFF9F0A)
        case .systemData: Color(hex: 0x8E8E93)
        case .cloud: Color(hex: 0x5AC8FA)
        case .trash: Color(hex: 0x98989D)
        case .other: Color(hex: 0xC7C7CC)
        }
    }

    /// Friendly one-liner per category card.
    static func blurb(for category: Core.Category) -> String {
        switch category {
        case .photosVideos: "Your memories. We never suggest deleting these."
        case .music: "Local music and audio files."
        case .documents: "Your files and folders — yours to manage."
        case .apps: "Applications installed in your user folder."
        case .downloads: "Old downloads you probably forgot about."
        case .mail: "Local mail and message archives."
        case .devJunk: "Rebuildable caches and build files from coding tools."
        case .systemData: "The mystery number, opened up in the System Data tab."
        case .cloud: "Synced from iCloud and cloud drives — deleting removes it everywhere."
        case .trash: "Already in the Trash. Empty it from Finder when ready."
        case .other: "Everything that fits nowhere else."
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

func fmtBytes(_ bytes: Int64) -> String {
    let gb = Double(bytes) / 1_000_000_000
    if gb >= 100 { return String(format: "%.0f GB", gb) }
    if gb >= 1 { return String(format: "%.2f GB", gb) }
    let mb = Double(bytes) / 1_000_000
    if mb >= 1 { return String(format: "%.1f MB", mb) }
    return String(format: "%.0f KB", Double(bytes) / 1_000)
}

struct SafetyPill: View {
    let safety: SystemDataReport.Row.Safety

    var body: some View {
        let (label, fg, bg): (String, Color, Color) = switch safety {
        case .safe: ("Safe", UI.safeText, UI.safeBG)
        case .review: ("Review", UI.reviewText, UI.reviewBG)
        case .leaveIt: ("Leave it", UI.leaveText, UI.leaveBG)
        }
        Text(label)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(fg)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(bg, in: Capsule())
    }
}

func revealInFinder(_ path: String) {
    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
}

/// The design canvas's blue CTA: 10pt radius, weighty label, subtle press.
struct PrimaryButtonStyle: ButtonStyle {
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 13 : 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, compact ? 16 : 22)
            .padding(.vertical, compact ? 8 : 11)
            .background(UI.accent.opacity(configuration.isPressed ? 0.75 : 1),
                        in: RoundedRectangle(cornerRadius: 10))
            .shadow(color: UI.accent.opacity(0.28), radius: 6, y: 2)
    }
}

extension View {
    /// White card with hairline border and soft shadow — the design's base
    /// surface.
    func card(radius: CGFloat = 12) -> some View {
        self
            .background(.white, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(UI.cardBorder))
            .shadow(color: .black.opacity(0.045), radius: 5, y: 1)
    }
}

/// Consistent screen header used by every section.
struct ScreenHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 27, weight: .bold))
                .tracking(-0.3)
            Text(subtitle)
                .font(.system(size: 13.5))
                .foregroundStyle(UI.textSecondary)
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// File-type icon chip: recognizable color + symbol per kind.
func fileIcon(name: String, isDirectory: Bool) -> (symbol: String, color: Color) {
    if isDirectory { return ("folder.fill", Color(hex: 0x0A84FF)) }
    let ext = (name as NSString).pathExtension.lowercased()
    switch ext {
    case "jpg", "jpeg", "png", "heic", "gif", "webp", "tiff", "raw", "psd":
        return ("photo.fill", Color(hex: 0xAF52DE))
    case "mp4", "mov", "mkv", "avi", "webm", "m4v":
        return ("film.fill", Color(hex: 0xFF375F))
    case "mp3", "wav", "aac", "flac", "m4a", "aiff":
        return ("music.note", Color(hex: 0xFF2D55))
    case "zip", "tar", "gz", "7z", "rar", "xz":
        return ("archivebox.fill", Color(hex: 0xA2845E))
    case "dmg", "iso", "img", "raw":
        return ("opticaldiscdrive.fill", Color(hex: 0x8E8E93))
    case "safetensors", "gguf", "ckpt", "pt", "onnx", "mlmodel", "bin":
        return ("cpu.fill", Color(hex: 0x5E5CE6))
    case "pdf", "doc", "docx", "pages", "txt", "md":
        return ("doc.text.fill", Color(hex: 0x32ADE6))
    case "app", "pkg", "ipa":
        return ("app.gift.fill", Color(hex: 0x34C759))
    default:
        return ("doc.fill", Color(hex: 0x98989D))
    }
}

struct FileIconChip: View {
    let name: String
    let isDirectory: Bool

    var body: some View {
        let info = fileIcon(name: name, isDirectory: isDirectory)
        Image(systemName: info.symbol)
            .font(.system(size: 13))
            .foregroundStyle(info.color)
            .frame(width: 30, height: 30)
            .background(info.color.opacity(0.13), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Wraps a row and paints a hover tint — table rows feel alive.
struct HoverRow<Content: View>: View {
    @ViewBuilder var content: Content
    @State private var hovering = false

    var body: some View {
        content
            .background(hovering ? Color(hex: 0xF4F8FE) : .white,
                        in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(hovering ? UI.selectedRowBorder : UI.cardBorder))
            .onHover { hovering = $0 }
    }
}
