import Foundation

/// Plain-language buckets — the product differentiator. Rules are evaluated
/// cheapest-first: known top-level dirs, then dir-name matches anywhere, then
/// file extensions.
public enum Category: String, CaseIterable, Sendable {
    case photosVideos = "Photos & Videos"
    case music = "Music & Audio"
    case documents = "Documents"
    case apps = "Apps"
    case downloads = "Downloads"
    case mail = "Mail & Messages"
    case devJunk = "Developer Junk"
    case systemData = "System Data"
    case cloud = "iCloud & Cloud Files"
    case trash = "Trash"
    case other = "Other"
}

public struct CategoryTotal: Identifiable, Sendable {
    public var id: String { category.rawValue }
    public let category: Category
    public let bytes: Int64
}

public enum Categorizer {

    /// Directory names that mark a whole subtree as developer junk, wherever
    /// they appear.
    static let devJunkDirNames: Set<String> = [
        "node_modules", ".git", "DerivedData", "__pycache__", ".venv", "venv",
        ".build", "Pods", ".gradle", ".tox", "target",
    ]

    /// Hidden tool/cache dirs at the top of the home folder.
    static let hiddenToolDirNames: Set<String> = [
        ".cache", ".npm", ".cargo", ".m2", ".ollama", ".docker", ".pnpm-store",
        ".yarn", ".rustup", ".nvm", ".gem", ".cocoapods", ".android", ".unsloth",
        ".local", ".vscode", ".cursor",
    ]

    static let imageExts: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "gif", "tiff", "raw", "cr2", "nef", "webp", "svg", "bmp", "psd"]
    static let videoExts: Set<String> = ["mp4", "mov", "mkv", "avi", "webm", "m4v", "mpg", "wmv"]
    static let audioExts: Set<String> = ["mp3", "wav", "aac", "flac", "m4a", "aiff", "ogg", "mid"]
    static let docExts: Set<String> = ["pdf", "doc", "docx", "txt", "md", "rtf", "pages", "key", "numbers", "xls", "xlsx", "ppt", "pptx", "csv", "epub"]

    /// Totals per category for a scan rooted at the user's home folder.
    public static func homeTotals(root: FileNode) -> [CategoryTotal] {
        var totals: [Category: Int64] = [:]
        for child in root.children ?? [] {
            walkTopLevel(child, into: &totals)
        }
        return Category.allCases.compactMap { cat in
            guard let bytes = totals[cat], bytes > 0 else { return nil }
            return CategoryTotal(category: cat, bytes: bytes)
        }.sorted { $0.bytes > $1.bytes }
    }

    private static func walkTopLevel(_ node: FileNode, into totals: inout [Category: Int64]) {
        switch node.name {
        case "Pictures", "Movies":
            totals[.photosVideos, default: 0] += node.size
        case "Music":
            totals[.music, default: 0] += node.size
        case "Documents", "Desktop":
            totals[.documents, default: 0] += node.size
        case "Downloads":
            totals[.downloads, default: 0] += node.size
        case "Applications":
            totals[.apps, default: 0] += node.size
        case ".Trash":
            totals[.trash, default: 0] += node.size
        case "Library":
            for libChild in node.children ?? [] {
                walkLibrary(libChild, into: &totals)
            }
        default:
            if hiddenToolDirNames.contains(node.name) {
                totals[.devJunk, default: 0] += node.size
            } else {
                walkGeneric(node, into: &totals)
            }
        }
    }

    private static func walkLibrary(_ node: FileNode, into totals: inout [Category: Int64]) {
        switch node.name {
        case "Mail", "Messages":
            totals[.mail, default: 0] += node.size
        case "CloudStorage", "Mobile Documents":
            totals[.cloud, default: 0] += node.size
        case "Developer":
            totals[.devJunk, default: 0] += node.size
        default:
            totals[.systemData, default: 0] += node.size
        }
    }

    private static func walkGeneric(_ node: FileNode, into totals: inout [Category: Int64]) {
        if node.isDirectory {
            if devJunkDirNames.contains(node.name) {
                totals[.devJunk, default: 0] += node.size
                return
            }
            for child in node.children ?? [] {
                walkGeneric(child, into: &totals)
            }
        } else {
            totals[fileCategory(node.name), default: 0] += node.size
        }
    }

    public static func fileCategory(_ name: String) -> Category {
        let ext = (name as NSString).pathExtension.lowercased()
        if imageExts.contains(ext) || videoExts.contains(ext) { return .photosVideos }
        if audioExts.contains(ext) { return .music }
        if docExts.contains(ext) { return .documents }
        return .other
    }

    /// Category used to color a top-level home entry in the treemap.
    public static func displayCategory(forTopLevel name: String) -> Category {
        switch name {
        case "Pictures", "Movies": return .photosVideos
        case "Music": return .music
        case "Documents", "Desktop": return .documents
        case "Downloads": return .downloads
        case "Applications": return .apps
        case ".Trash": return .trash
        case "Library": return .systemData
        default:
            return hiddenToolDirNames.contains(name) ? .devJunk : .other
        }
    }
}
