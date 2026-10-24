import AppKit
import Foundation

public enum SettingsPane: String, CaseIterable, Sendable {
    case spotlight = "x-apple.systempreferences:com.apple.Spotlight-Settings.extension"
    case loginItems = "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
    case displays = "x-apple.systempreferences:com.apple.Displays-Settings.extension"
    case accessibilityDisplay = "x-apple.systempreferences:com.apple.Accessibility-Settings.extension?Display"
    case automation = "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
    case battery = "x-apple.systempreferences:com.apple.Battery-Settings.extension"
    case wifi = "x-apple.systempreferences:com.apple.wifi-settings-extension"
}

public enum FixOutcome: Sendable, Equatable {
    case done, alreadyGone, stillRunning, cancelled, refused, failed(String)

    public init(appleScriptErrorNumber n: Int) {
        self = n == -128 ? .cancelled : .failed("\(n)")
    }
}

/// The only place ClearDisk changes anything on the Mac. Every quit is
/// re-checked against `SafetyGate` with the live `NSRunningApplication`.
@MainActor
public final class FixRunner {
    public nonisolated static let rebuildScript = "do shell script \"/usr/bin/mdutil -E /\" with administrator privileges"
    public nonisolated static let restartScript = "tell application \"loginwindow\" to «event aevtrrst»"

    private let currentUID: UInt32

    public init(currentUID: UInt32 = getuid()) {
        self.currentUID = currentUID
    }

    public func quit(_ group: ProcessGroup, force: Bool = false, timeout: Duration = .seconds(10)) async -> FixOutcome {
        guard let appPath = group.appPath else { return .refused }
        let apps = NSWorkspace.shared.runningApplications.filter { $0.bundleURL?.path == appPath }
        guard !apps.isEmpty else { return .alreadyGone }
        for app in apps {
            guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                  group.members.contains(where: { $0.pid == app.processIdentifier }) else { return .refused }
            guard SafetyGate.canQuit(uid: group.primary.uid, currentUID: currentUID,
                                     path: app.executableURL?.path ?? appPath, name: group.displayName,
                                     isRegularApp: Self.isUserApp(app.activationPolicy))
            else { return .refused }
        }
        for app in apps {
            _ = force ? app.forceTerminate() : app.terminate()
        }
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if Task.isCancelled { return .cancelled }
            if apps.allSatisfy(\.isTerminated) { return .done }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return apps.allSatisfy(\.isTerminated) ? .done : .stillRunning
    }

    /// Dock apps and menu-bar apps (LSUIElement, like Docker) are user apps;
    /// only `.prohibited` background agents are not.
    public nonisolated static func isUserApp(_ policy: NSApplication.ActivationPolicy) -> Bool {
        policy != .prohibited
    }

    public func open(_ pane: SettingsPane) {
        if let url = URL(string: pane.rawValue) { NSWorkspace.shared.open(url) }
    }

    /// Asks for an admin password (macOS's own prompt), then rebuilds the index.
    public func rebuildSpotlightIndex() async -> FixOutcome {
        await Self.osascript(Self.rebuildScript)
    }

    /// Hands off to macOS's standard restart dialog; the user confirms there.
    public func restartMac() async -> FixOutcome {
        await Self.osascript(Self.restartScript)
    }

    public func openClearDisk() {
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "app.cleardisk.ClearDisk") {
            NSWorkspace.shared.openApplication(at: app, configuration: .init())
        } else if let url = URL(string: "https://cleardisk.app/?ref=whyslow") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Runs off the main thread so a password dialog never freezes the UI.
    nonisolated static func osascript(_ source: String) async -> FixOutcome {
        await Task.detached {
            guard let out = try? Shell.run("/usr/bin/osascript", ["-e", source], timeout: 120) else {
                return .failed("The system command did not finish within two minutes. Check its status before trying again.")
            }
            return outcome(status: out.status, stderr: out.stderr)
        }.value
    }

    /// osascript reports errors as "... (-128)" on stderr.
    nonisolated static func outcome(status: Int32, stderr: String) -> FixOutcome {
        guard status != 0 else { return .done }
        if let r = stderr.range(of: #"\((-?\d+)\)"#, options: .regularExpression),
           let n = Int(stderr[r].dropFirst().dropLast()) {
            return FixOutcome(appleScriptErrorNumber: n)
        }
        return .failed(stderr.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
