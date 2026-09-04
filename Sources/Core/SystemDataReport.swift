import Foundation

/// The hero feature: opens up "System Data" into measured, explained rows,
/// each labeled Safe / Review / Leave it. Sizes come from the scanned tree —
/// nothing is guessed.
public struct SystemDataReport: Sendable {
    public struct Row: Identifiable, Sendable {
        public enum Safety: Sendable {
            case safe, review, leaveIt
        }
        public let id: String
        public let title: String
        public let explanation: String
        /// nil = informational row with no measurable size (snapshots).
        public let bytes: Int64?
        public let detail: String?
        public let safety: Safety
        /// Absolute paths whose CONTENTS get trashed on clean (safe rows only).
        public let cleanRoots: [String]
        /// Application-cache measurements exclude browser directories. Carry
        /// that same boundary into contents-only cleanup, even if those
        /// browser directories changed after the scan.
        public var cleanExcludingNames: [String] {
            id == "app-caches" ? SystemDataScan.browserCacheDirNames.sorted() : []
        }
        /// Where "Reveal in Finder" points for this row.
        public var revealPath: String? {
            if let first = cleanRoots.first { return first }
            return reviewPath
        }
        let reviewPath: String?
    }

    public let rows: [Row]
    public let totalBytes: Int64
    public let safeBytes: Int64
}

public enum SystemDataScan {

    static let browserCacheDirNames: Set<String> = [
        "Google", "com.apple.Safari", "Firefox", "Mozilla", "com.microsoft.edgemac",
        "Arc", "company.thebrowser.Browser", "BraveSoftware", "com.operasoftware.Opera",
    ]

    /// Build the report from a scan rooted at the home folder.
    public static func build(homeRoot: FileNode, homePath: String) -> SystemDataReport {
        func lib(_ components: String...) -> FileNode? {
            var node: FileNode? = homeRoot.child("Library")
            for c in components { node = node?.child(c) }
            return node
        }
        func path(_ components: String...) -> String {
            homePath + "/Library/" + components.joined(separator: "/")
        }

        var rows: [SystemDataReport.Row] = []

        let caches = lib("Caches")
        let browserBytes = (caches?.children ?? [])
            .filter { browserCacheDirNames.contains($0.name) }
            .reduce(Int64(0)) { $0 + $1.size }
        let appCacheBytes = (caches?.size ?? 0) - browserBytes

        rows.append(.init(
            id: "app-caches", title: "Application caches",
            explanation: "Temporary files your apps rebuild automatically.",
            bytes: appCacheBytes, detail: nil, safety: .safe,
            cleanRoots: caches == nil ? [] : [path("Caches")], reviewPath: nil))

        rows.append(.init(
            id: "browser-caches", title: "Browser caches",
            explanation: "Safari, Chrome and friends rebuild these as you browse.",
            bytes: browserBytes, detail: nil, safety: .safe,
            cleanRoots: (caches?.children ?? [])
                .filter { browserCacheDirNames.contains($0.name) }
                .map { path("Caches", $0.name) }, reviewPath: nil))

        let logs = lib("Logs")
        rows.append(.init(
            id: "logs", title: "Logs",
            explanation: "Diagnostic text files. Your Mac won't miss them.",
            bytes: logs?.size ?? 0, detail: nil, safety: .safe,
            cleanRoots: logs == nil ? [] : [path("Logs")], reviewPath: nil))

        let developer = lib("Developer")
        rows.append(.init(
            id: "xcode", title: "Xcode & simulator files",
            explanation: "Left over from Apple's developer tools. They rebuild themselves if ever needed.",
            bytes: developer?.size ?? 0, detail: nil, safety: .safe,
            cleanRoots: developer == nil ? [] : [path("Developer")], reviewPath: nil))

        let backups = lib("Application Support", "MobileSync", "Backup")
        rows.append(.init(
            id: "ios-backups", title: "iPhone & iPad backups",
            explanation: "Old device backups. Keep the latest, trash the rest.",
            bytes: backups?.size ?? 0, detail: nil, safety: .review,
            cleanRoots: [], reviewPath: path("Application Support", "MobileSync", "Backup")))

        let hiddenTools = (homeRoot.children ?? [])
            .filter { Categorizer.hiddenToolDirNames.contains($0.name) }
        rows.append(.init(
            id: "hidden-tools", title: "Hidden tool caches",
            explanation: "Caches and downloads from command-line tools, hidden from Finder.",
            bytes: hiddenTools.reduce(0) { $0 + $1.size },
            detail: hiddenTools.map(\.name).sorted().joined(separator: "  "),
            safety: .review, cleanRoots: [], reviewPath: homePath))

        let containers = (lib("Containers")?.size ?? 0) + (lib("Group Containers")?.size ?? 0)
        rows.append(.init(
            id: "containers", title: "App containers",
            explanation: "Private data apps keep for themselves — Docker's virtual disk and WhatsApp media live here.",
            bytes: containers, detail: nil, safety: .review, cleanRoots: [], reviewPath: path("Containers")))

        let snapshots = localSnapshotCount()
        rows.append(.init(
            id: "snapshots", title: "Time Machine snapshots",
            explanation: "Hourly local backups. macOS purges them on its own when space runs low.",
            bytes: nil,
            detail: snapshots.map { "\($0) snapshot\($0 == 1 ? "" : "s") on this Mac" },
            safety: .leaveIt, cleanRoots: [], reviewPath: nil))

        let accounted = rows.reduce(Int64(0)) { $0 + ($1.bytes ?? 0) }
            - hiddenTools.reduce(0) { $0 + $1.size }
        let libraryRest = max(0, (homeRoot.child("Library")?.size ?? 0) - accounted)
        rows.append(.init(
            id: "library-rest", title: "Everything else in Library",
            explanation: "App settings, fonts and support files your Mac needs. ClearDisk leaves these alone.",
            bytes: libraryRest, detail: nil, safety: .leaveIt, cleanRoots: [], reviewPath: nil))

        let total = rows.reduce(Int64(0)) { $0 + ($1.bytes ?? 0) }
        let safe = rows.filter { $0.safety == .safe }.reduce(Int64(0)) { $0 + ($1.bytes ?? 0) }
        return SystemDataReport(rows: rows, totalBytes: total, safeBytes: safe)
    }

    /// Count of APFS local Time Machine snapshots, via tmutil. nil if tmutil
    /// fails (sandboxed builds don't get to run it).
    static func localSnapshotCount() -> Int? {
        let tmutil = Process()
        tmutil.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
        tmutil.arguments = ["listlocalsnapshots", "/"]
        let pipe = Pipe()
        tmutil.standardOutput = pipe
        tmutil.standardError = Pipe()
        do {
            try tmutil.run()
        } catch {
            return nil
        }
        tmutil.waitUntilExit()
        guard tmutil.terminationStatus == 0 else { return nil }
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return out.split(separator: "\n").filter { $0.contains("com.apple.TimeMachine") }.count
    }
}

extension FileNode {
    public func child(_ name: String) -> FileNode? {
        children?.first { $0.name == name }
    }
}
