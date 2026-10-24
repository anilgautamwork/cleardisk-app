import AppKit
import Foundation

public enum BrowserError: Error, Equatable, Sendable {
    case notPermitted, notRunning, failed(String)
}

public protocol ScriptRunner: Sendable {
    func run(_ source: String) async throws -> String
}

/// Runs AppleScript through `/usr/bin/osascript`, off the main thread.
public struct OSAScriptRunner: ScriptRunner {
    public init() {}

    public func run(_ source: String) async throws -> String {
        let out = try await Task.detached { try Shell.run("/usr/bin/osascript", ["-e", source]) }.value
        guard out.status == 0 else { throw Self.error(fromStderr: out.stderr) }
        return out.stdout.trimmingCharacters(in: .newlines)
    }

    static func error(fromStderr stderr: String) -> BrowserError {
        if stderr.contains("(-1743)") { return .notPermitted }
        if stderr.contains("(-600)") { return .notRunning }
        return .failed(stderr.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

public struct BrowserController: Sendable {
    private let runner: ScriptRunner
    private let isRunning: @Sendable (String) -> Bool

    public init(runner: ScriptRunner = OSAScriptRunner(),
                isRunning: @escaping @Sendable (String) -> Bool = { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty }) {
        self.runner = runner
        self.isRunning = isRunning
    }

    public func windows(_ b: ChromiumBrowser) async throws -> [BrowserWindow] {
        try ensureRunning(b)
        return TabScript.parse(try await runner.run(TabScript.list(b)), appName: b.appName)
    }

    public func close(_ tabs: [BrowserTab], _ b: ChromiumBrowser) async throws {
        guard !tabs.isEmpty else { return }
        try ensureRunning(b)
        _ = try await runner.run(TabScript.close(tabs, b))
    }

    public func merge(_ plan: MergePlan, _ b: ChromiumBrowser) async throws {
        try ensureRunning(b)
        _ = try await runner.run(TabScript.merge(plan, b))
    }

    public func openMemorySaver(_ b: ChromiumBrowser) async throws {
        try ensureRunning(b)
        _ = try await runner.run(TabScript.openMemorySaver(b))
    }

    /// `tell application` would launch a quit browser; never do that.
    private func ensureRunning(_ b: ChromiumBrowser) throws {
        guard isRunning(b.rawValue) else { throw BrowserError.notRunning }
    }
}
