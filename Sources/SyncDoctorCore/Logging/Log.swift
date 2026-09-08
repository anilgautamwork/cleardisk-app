import Foundation
import os

/// Structured logging for SyncDoctor.
///
/// Rules (see README "Logging"):
///  * Never log file contents. Nothing in this module reads file contents anyway.
///  * Paths / filenames are personally sensitive. By default they are redacted
///    to a stable hash + length so log lines from the same file can still be
///    correlated without revealing the name.
///  * `LogSettings.shared.verbosePaths` can be switched on in DEBUG builds
///    (Settings → Developer) to log full paths.
///
/// `os.Logger` requires the privacy modifier to be a literal, so we do the
/// redaction ourselves before interpolating.
public enum Log {
    public static let subsystem = "com.syncdoctor.app"

    public static let app = Logger(subsystem: subsystem, category: "app")
    public static let locator = Logger(subsystem: subsystem, category: "locator")
    public static let scanner = Logger(subsystem: subsystem, category: "scanner")
    public static let inspector = Logger(subsystem: subsystem, category: "inspector")
    public static let actions = Logger(subsystem: subsystem, category: "actions")
    public static let history = Logger(subsystem: subsystem, category: "history")

    /// Returns a loggable representation of a path honouring the redaction setting.
    public static func path(_ path: String) -> String {
        if LogSettings.shared.verbosePaths { return path }
        return "<path \(stableHash(path)) len=\(path.count)>"
    }

    public static func path(_ url: URL) -> String {
        path(url.path)
    }

    /// Small, stable, non-cryptographic hash (FNV-1a) used only to correlate
    /// redacted log lines. Not used for anything security-relevant.
    static func stableHash(_ s: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in s.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return String(hash, radix: 16).prefix(8).description
    }
}

/// Mutable logging settings, safe to touch from any thread.
public final class LogSettings: @unchecked Sendable {
    public static let shared = LogSettings()

    private let lock = NSLock()
    private var _verbosePaths = false

    private init() {}

    /// When true, full paths are written to the unified log.
    /// Only honoured in DEBUG builds; release builds always redact.
    public var verbosePaths: Bool {
        get {
            lock.lock(); defer { lock.unlock() }
            return _verbosePaths
        }
        set {
            #if DEBUG
            lock.lock(); _verbosePaths = newValue; lock.unlock()
            #else
            // Intentionally ignored in release builds.
            _ = newValue
            #endif
        }
    }
}
