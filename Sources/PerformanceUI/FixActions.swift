import PerformanceCore
import Foundation
import Observation
import os

enum Screen: Hashable, CaseIterable {
    case overview, processes, backgroundItems, internet, usage

    var title: String {
        switch self {
        case .overview: "Overview"
        case .processes: "Processes"
        case .backgroundItems: "Background Items"
        case .internet: "Internet"
        case .usage: "Usage"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .processes: "waveform.path.ecg"
        case .backgroundItems: "square.stack.3d.up"
        case .internet: "wifi"
        case .usage: "chart.xyaxis.line"
        }
    }
}

@MainActor
@Observable
final class Router {
    var screen: Screen = .overview
    var expandedID: String?
    var browser: ChromiumBrowser?
    /// Bumped by ⌘F; the Processes screen focuses its search field.
    var focusSearch = 0

    init() {
        #if DEBUG
        // QA: CLEARDISK_PERFORMANCE_SCREEN=processes CLEARDISK_PERFORMANCE_EXPAND=pid:405 opens straight to a screen.
        let env = ProcessInfo.processInfo.environment
        if let s = env["CLEARDISK_PERFORMANCE_SCREEN"], let screen = Screen.allCases.first(where: { "\($0)" == s }) { self.screen = screen }
        expandedID = env["CLEARDISK_PERFORMANCE_EXPAND"]
        browser = env["CLEARDISK_PERFORMANCE_BROWSER"].flatMap(ChromiumBrowser.init(rawValue:))
        #endif
    }

    func explain(_ groupID: String?) {
        expandedID = groupID
        screen = .processes
    }
}

extension ChromiumBrowser: Identifiable {
    public var id: String { rawValue }
}

/// Every action goes through here: asks first, gates paid fixes behind the
/// license, runs the fix, and reports the outcome in plain words.
@MainActor
@Observable
final class FixActions {
    struct Confirmation: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let confirm: String
        var destructive = false
        let action: @MainActor () async -> Void
    }

    var confirmation: Confirmation?
    var isOperating = false
    var openStorage: () -> Void = {}
    var fileOperationActive: () -> Bool = { false }
    var toast: String?
    /// The app that survived Force Quit, for the "restart?" alert.
    var stuckAlert: String?

    @ObservationIgnored let runner = FixRunner()
    @ObservationIgnored private let license: LicenseStore
    @ObservationIgnored private let monitor: Monitor
    @ObservationIgnored private let router: Router
    @ObservationIgnored private let log = Logger(subsystem: "app.cleardisk.performance.ClearDisk", category: "fixes")

    init(license: LicenseStore, monitor: Monitor, router: Router) {
        self.license = license
        self.monitor = monitor
        self.router = router
    }

    func perform(_ fix: FixID, group: ProcessGroup?) {
        switch fix {
        case .explain: router.explain(group?.id)
        case .openSpotlightSettings: runner.open(.spotlight)
        case .openLoginItemsSettings: runner.open(.loginItems)
        case .openDisplaySettings: runner.open(.displays)
        case .openAccessibilityDisplay: runner.open(.accessibilityDisplay)
        case .openBatterySettings: runner.open(.battery)
        case .openWiFiSettings: runner.open(.wifi)
        case .openClearDisk: openStorage()
        case .reviewTabs:
            if let path = group?.appPath, let b = ChromiumBrowser(appPath: path) { router.browser = b }
        case .quitApp:
            guard let group else { return }
            requireLicense { self.confirmQuit(group) }
        case .rebuildSpotlightIndex:
            requireLicense {
                self.confirmation = Confirmation(
                    title: "Rebuild the Spotlight index?",
                    message: "macOS will ask for your password. Search results may be incomplete for a few hours while it rebuilds.",
                    confirm: "Rebuild") {
                        guard self.mayRunPaidAction() else { return }
                        self.isOperating = true
                        defer { self.isOperating = false }
                        self.report(await self.runner.rebuildSpotlightIndex(), app: nil)
                    }
            }
        case .restartMac: confirmRestart()
        }
    }

    func confirmQuit(_ g: ProcessGroup) {
        confirmation = Confirmation(title: "Quit \(g.displayName)?", message: "\(g.displayName) may ask you to save your work first.",
                                    confirm: "Quit \(g.displayName)") { await self.quit(g, force: false) }
    }

    func confirmRestart() {
        confirmation = Confirmation(title: "Restart your Mac?", message: "Save your work first. macOS will ask you to confirm.",
                                    confirm: "Restart…") {
            guard !self.fileOperationActive(), !self.isOperating else {
                self.toast = "Wait for the current operation to finish before restarting."
                return
            }
            self.isOperating = true
            defer { self.isOperating = false }
            if case .failed = await self.runner.restartMac() { self.toast = "Choose Apple menu > Restart." }
        }
    }

    /// Locked actions must be requested again after activation.
    func requireLicense(_ action: @escaping @MainActor () -> Void) {
        if license.isLicensed {
            action()
        } else {
            license.showUnlock = true
        }
    }

    private func quit(_ g: ProcessGroup, force: Bool) async {
        guard mayRunPaidAction() else { return }
        isOperating = true
        defer { isOperating = false }
        let outcome = await runner.quit(g, force: force)
        log.info("quit outcome: \(String(describing: outcome), privacy: .public)")
        guard outcome == .stillRunning else {
            report(outcome, app: g.displayName)
            monitor.checkNow()
            return
        }
        if force {
            monitor.stuckApp = g.displayName
            monitor.checkNow()
            stuckAlert = g.displayName
        } else {
            confirmation = Confirmation(title: "\(g.displayName) isn't responding.",
                                        message: "Force quit it? Unsaved work in \(g.displayName) will be lost.",
                                        confirm: "Force Quit", destructive: true) { await self.quit(g, force: true) }
        }
    }

    func report(_ outcome: FixOutcome, app: String?) {
        toast = switch outcome {
        case .done: "Done"
        case .alreadyGone: "\(app ?? "It") already quit"
        case .cancelled: "Cancelled"
        case .refused: "\(app ?? "That app") is protected, so ClearDisk won't quit it."
        case .failed(let m): "Couldn't finish: \(m)"
        case .stillRunning: "\(app ?? "It") is still running"
        }
    }

    func mayRunPaidAction() -> Bool {
        guard !isOperating, !fileOperationActive() else {
            toast = "Wait for the current operation to finish."
            return false
        }
        guard license.isLicensed else {
            license.showUnlock = true
            return false
        }
        return true
    }
}
