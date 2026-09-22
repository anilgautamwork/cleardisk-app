import AppKit
import Combine
import Sparkle

/// Sparkle verifies signed updates and owns download, installation and relaunch.
@MainActor final class AppUpdater: ObservableObject {
    private let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
    @Published private(set) var canCheckForUpdates = false
    private var started = false

    init() {
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func start() {
        guard !started, NSClassFromString("XCTestCase") == nil else { return }
        started = true
        controller.startUpdater()
    }

    func checkForUpdates() { controller.checkForUpdates(nil) }
}

@MainActor final class UpdateAppDelegate: NSObject, NSApplicationDelegate {
    weak var state: AppState?
    weak var iCloudDoctor: ICloudDoctorState?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard (state?.activeRemovals ?? 0) > 0 || iCloudDoctor?.isOperating == true else {
            return .terminateNow
        }
        let alert = NSAlert()
        alert.messageText = "Wait for your file operation to finish"
        alert.informativeText = "ClearDisk can restart once cleanup or the iCloud operation is complete."
        alert.addButton(withTitle: "Return to ClearDisk")
        alert.runModal()
        return .terminateCancel
    }
}
