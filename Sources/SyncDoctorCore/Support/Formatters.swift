import Foundation

public enum Format {
    public static func bytes(_ value: Int64?) -> String {
        guard let value else { return "Unknown" }
        return ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    public static func count(_ value: Int) -> String {
        value.formatted(.number)
    }

    public static func date(_ value: Date?) -> String {
        guard let value else { return "Unknown" }
        return value.formatted(date: .abbreviated, time: .shortened)
    }

    public static func relative(_ value: Date?) -> String {
        guard let value else { return "Unknown" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: value, relativeTo: Date())
    }

    public static func triState(_ value: Bool?) -> String {
        switch value {
        case .some(true): return "Yes"
        case .some(false): return "No"
        case .none: return "Unknown"
        }
    }

    public static func percent(_ value: Double?) -> String {
        guard let value else { return "Unknown" }
        return String(format: "%.0f%%", value)
    }

    /// Replace the home directory with `~` for display.
    public static func abbreviatedPath(_ path: String) -> String {
        let home = ICloudDriveLocator.realHomeDirectory().path
        if path.hasPrefix(home) { return "~" + path.dropFirst(home.count) }
        return path
    }
}
