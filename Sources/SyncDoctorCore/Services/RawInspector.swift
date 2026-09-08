import Foundation
import CoreServices
import UniformTypeIdentifiers

/// One key/value pair as macOS returned it, with the API it came from.
public struct RawField: Identifiable, Sendable, Hashable {
    public enum Source: String, Sendable { case urlResourceValues, lstat, xattr, spotlight, metadataQuery, fileManager }
    public var id: String { "\(source.rawValue):\(key)" }
    public let source: Source
    public let key: String
    /// Rendered value. `"<nil>"` means macOS returned nothing for the key.
    public let value: String
    /// Error thrown while asking for this specific key, if any.
    public let error: String?

    public init(source: Source, key: String, value: String, error: String? = nil) {
        self.source = source; self.key = key; self.value = value; self.error = error
    }
}

/// The full raw dump for one path. This is the heart of milestone 1: it shows
/// exactly what macOS is willing to tell a non-entitled, non-sandboxed app
/// about an iCloud Drive item.
public struct RawInspection: Sendable {
    public let url: URL
    public let inspectedAt: Date
    public let item: ICloudItem
    public let resourceValues: [RawField]
    public let posix: POSIXFileInfo?
    public let posixError: ItemError?
    public let posixFields: [RawField]
    public let xattrNames: [String]
    public let xattrError: ItemError?
    public let spotlight: [RawField]
    public let spotlightAvailable: Bool
    public let fileManagerFields: [RawField]

    /// Plain-text report suitable for copying into a bug report. Paths are
    /// included on purpose — the user explicitly asked to inspect this file.
    public func reportText() -> String {
        var out: [String] = []
        out.append("ClearDisk iCloud Inspector report")
        out.append("Inspected: \(ISO8601DateFormatter().string(from: inspectedAt))")
        out.append("Path: \(url.path)")
        out.append("")
        out.append("== Derived (ICloudItem) ==")
        out.append("kind=\(item.kind.rawValue) locality=\(item.locality.rawValue) downloadStatus=\(item.downloadStatus.rawValue) healthy=\(item.isHealthy)")
        out.append("logicalSize=\(item.logicalSize.map(String.init) ?? "nil") allocatedSize=\(item.allocatedSize.map(String.init) ?? "nil") dataless=\(item.isDataless.map(String.init) ?? "nil")")
        out.append("")
        out.append("== URL resource values ==")
        for f in resourceValues { out.append("\(f.key) = \(f.value)\(f.error.map { "   [error: \($0)]" } ?? "")") }
        out.append("")
        out.append("== lstat ==")
        if let posixError { out.append("error: \(posixError.description)") }
        for f in posixFields { out.append("\(f.key) = \(f.value)") }
        out.append("")
        out.append("== xattr names ==")
        if let xattrError { out.append("error: \(xattrError.description)") }
        out.append(xattrNames.isEmpty ? "(none)" : xattrNames.joined(separator: "\n"))
        out.append("")
        out.append("== Spotlight (MDItem) ==")
        if !spotlightAvailable { out.append("(MDItemCreateWithURL returned nil — item not indexed or Spotlight unavailable)") }
        for f in spotlight { out.append("\(f.key) = \(f.value)") }
        out.append("")
        out.append("== FileManager ==")
        for f in fileManagerFields { out.append("\(f.key) = \(f.value)") }
        return out.joined(separator: "\n")
    }
}

public enum RawInspector {

    /// Inspect one path. Safe: never reads contents, never triggers a download.
    public static func inspect(url: URL) -> RawInspection {
        do { return try DatalessMaterializationPolicy.withoutMaterialization { inspectProtected(url: url) } }
        catch {
            let failure = ItemError(error)
            return RawInspection(url: url, inspectedAt: Date(), item: ICloudMetadataReader.build(url: url, values: [:], posix: nil, root: nil, accessError: failure), resourceValues: [], posix: nil, posixError: failure, posixFields: [], xattrNames: [], xattrError: nil, spotlight: [], spotlightAvailable: false, fileManagerFields: [])
        }
    }
    private static func inspectProtected(url: URL) -> RawInspection {
        Log.inspector.info("Inspecting \(Log.path(url))")

        let (values, errors) = ICloudMetadataReader.rawValues(at: url)

        var fields: [RawField] = []
        for key in ICloudMetadataReader.fileSystemKeys + ICloudMetadataReader.ubiquityKeys {
            let rendered = values[key].map(render) ?? "<nil>"
            fields.append(RawField(source: .urlResourceValues, key: key.rawValue, value: rendered, error: errors[key]?.description))
        }

        let posixResult = POSIXFileInfo.lstat(path: url.path)
        let posix = try? posixResult.get()
        var posixError: ItemError?
        if case .failure(let e) = posixResult { posixError = e }
        var posixFields: [RawField] = []
        if let posix {
            posixFields = [
                RawField(source: .lstat, key: "st_size", value: "\(posix.size)"),
                RawField(source: .lstat, key: "st_blocks (×512 bytes)", value: "\(posix.blocks) (\(posix.blocks * 512) bytes)"),
                RawField(source: .lstat, key: "st_mode", value: posix.modeString),
                RawField(source: .lstat, key: "st_flags", value: String(format: "0x%08x", posix.flags) + (posix.flagNames.isEmpty ? "" : " [\(posix.flagNames.joined(separator: ", "))]")),
                RawField(source: .lstat, key: "SF_DATALESS", value: posix.isDataless ? "SET (cloud-only placeholder)" : "not set"),
                RawField(source: .lstat, key: "st_nlink", value: "\(posix.linkCount)"),
                RawField(source: .lstat, key: "st_ino", value: "\(posix.inode)"),
                RawField(source: .lstat, key: "st_mtime", value: render(posix.modified)),
                RawField(source: .lstat, key: "st_ctime", value: render(posix.changed)),
                RawField(source: .lstat, key: "st_birthtime", value: render(posix.created)),
            ]
        }

        let xattrResult = POSIXFileInfo.xattrNames(path: url.path)
        let xattrs = (try? xattrResult.get()) ?? []
        var xattrError: ItemError?
        if case .failure(let e) = xattrResult { xattrError = e }

        let (spotlight, spotlightAvailable) = spotlightAttributes(url: url)

        let fm = FileManager.default
        var fmFields: [RawField] = [
            RawField(source: .fileManager, key: "isUbiquitousItem(at:)", value: "\(fm.isUbiquitousItem(at: url))"),
            RawField(source: .fileManager, key: "ubiquityIdentityToken != nil", value: "\(fm.ubiquityIdentityToken != nil)"),
            RawField(source: .fileManager, key: "process dataless materialization policy", value: policyName(DatalessMaterializationPolicy.currentProcessPolicy())),
        ]
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            fmFields.append(RawField(source: .fileManager, key: "contentType", value: type.identifier))
        }

        let item = ICloudMetadataReader.build(url: url, values: values, posix: posix, root: nil, accessError: posixError)

        return RawInspection(
            url: url, inspectedAt: Date(), item: item,
            resourceValues: fields,
            posix: posix, posixError: posixError, posixFields: posixFields,
            xattrNames: xattrs, xattrError: xattrError,
            spotlight: spotlight, spotlightAvailable: spotlightAvailable,
            fileManagerFields: fmFields
        )
    }

    // MARK: Spotlight

    /// Everything Spotlight has indexed about the item, via the public
    /// `MDItem` C API (CoreServices/Metadata). Spotlight indexes iCloud Drive
    /// and — on some macOS versions — carries `NSMetadataUbiquitousItem*`
    /// attributes for files. We dump all attributes so we can see for
    /// ourselves which ones are present on this Mac.
    ///
    /// Values are rendered but *content*-bearing attributes (text content,
    /// authors, etc.) are elided to keep the report free of user data.
    public static func spotlightAttributes(url: URL) -> ([RawField], Bool) {
        guard let mdItem = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL) else {
            return ([], false)
        }
        guard let names = (MDItemCopyAttributeNames(mdItem) as NSArray?) as? [String] else {
            return ([], true)
        }
        let elided: Set<String> = ["kMDItemTextContent", "kMDItemAuthors", "kMDItemRecipients", "kMDItemComment", "kMDItemFinderComment", "kMDItemTitle", "kMDItemDescription", "kMDItemHeadline", "kMDItemKeywords"]
        var fields: [RawField] = []
        let attrs = ((MDItemCopyAttributes(mdItem, names as CFArray) as NSDictionary?) as? [String: Any]) ?? [:]
        for name in names.sorted() {
            let value: String
            if elided.contains(name) { value = "<elided: user content>" }
            else if let v = attrs[name] { value = render(v) }
            else { value = "<nil>" }
            fields.append(RawField(source: .spotlight, key: name, value: value))
        }
        return (fields, true)
    }

    // MARK: Rendering

    static func render(_ value: Any) -> String {
        switch value {
        case let n as NSNumber:
            // Distinguish Bool from numeric NSNumbers.
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue ? "true" : "false" }
            return n.stringValue
        case let d as Date:
            return ISO8601DateFormatter().string(from: d)
        case let s as String:
            return s
        case let e as NSError:
            return "NSError domain=\(e.domain) code=\(e.code) \"\(e.localizedDescription)\"" + (e.localizedFailureReason.map { " reason=\"\($0)\"" } ?? "")
        case let u as URL:
            return u.path
        case let arr as [Any]:
            return "[" + arr.map(render).joined(separator: ", ") + "]"
        case let dict as [String: Any]:
            return "{" + dict.keys.sorted().map { "\($0): \(render(dict[$0]!))" }.joined(separator: ", ") + "}"
        case let pnc as PersonNameComponents:
            return PersonNameComponentsFormatter().string(from: pnc)
        default:
            return String(describing: value)
        }
    }

    static func policyName(_ v: Int32) -> String {
        switch v {
        case 0: return "DEFAULT (0) — implicit downloads allowed"
        case 1: return "OFF (1) — implicit downloads blocked"
        case 2: return "ON (2)"
        default: return "\(v)"
        }
    }
}
