import Foundation

/// A routing decision, not an operating-system permission grant. All disk
/// scans (including rescans and a selected root folder) pass through this gate.
public enum ScanAccessPolicy {
    public enum Decision: Equatable, Sendable {
        case requestDiskAccess
        case scan(path: String)
    }

    public static func decision(path: String, diskAccessConfirmed: @autoclosure () -> Bool) -> Decision {
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
        if normalized == "/", !diskAccessConfirmed() { return .requestDiskAccess }
        return .scan(path: normalized)
    }
}
