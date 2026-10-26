import XCTest
import PerformanceCore
@testable import PerformanceUI

final class StatusBarTests: XCTestCase {
    func testUnavailablePausedAndStaleSamplesAreNeverShownAsLive() {
        let now = Date(timeIntervalSince1970: 1000)
        func status(enabled: Bool = true, paused: Bool = false, available: Bool = true,
                    error: Bool = false, date: Date? = nil) -> String? {
            PerformanceReadout.status(enabled: enabled, paused: paused, available: available,
                                      hasError: error, lastChecked: date, now: now)
        }
        XCTAssertEqual(status(enabled: false, date: now), "Not monitoring")
        XCTAssertEqual(status(paused: true, date: now), "Paused")
        XCTAssertEqual(status(available: false, date: now), "Unavailable")
        XCTAssertEqual(status(error: true, date: now), "Unavailable")
        XCTAssertEqual(status(), "Checking…")
        XCTAssertEqual(status(date: now.addingTimeInterval(-61)), "Waiting for update")
        XCTAssertNil(status(date: now))
    }

    func testRunningAppsAreSortedByMemoryAndHelpersStayGrouped() {
        let a = group("Editor", memory: 100, cpu: 80)
        let b = group("Browser", memory: 300, cpu: 10)
        let daemon = ProcessGroup(id: "pid:9", displayName: "daemon", appPath: nil,
                                  members: a.members, cpuPercent: 200, memoryBytes: 900, quittable: false)
        XCTAssertEqual(PerformanceReadout.apps([a, daemon, b], byMemory: true).map(\.id), [b.id, a.id])
        XCTAssertEqual(PerformanceReadout.apps([a, daemon, b], byMemory: false, limit: 1).map(\.id), [a.id])
        XCTAssertTrue(PerformanceReadout.apps([a], byMemory: true, limit: 0).isEmpty)
    }

    @MainActor
    func testMenuQuitWaitsForDestinationAndOnlyPresentsConfirmationOnce() {
        let coordinator = PerformanceCoordinator()
        var opened = 0
        coordinator.configure(isLicensed: { true }, requestUnlock: {}, openStorage: {},
                              openPerformance: { opened += 1 }, fileOperationActive: { false })
        let now = Date()
        coordinator.requestMenuAction(.quitApp, group: group("Editor"), now: now)
        XCTAssertEqual(opened, 1)
        XCTAssertNil(coordinator.actions.confirmation)
        XCTAssertFalse(coordinator.isOperating)
        coordinator.presentPendingMenuAction(now: now)
        let confirmation = coordinator.actions.confirmation?.id
        XCTAssertNotNil(confirmation)
        XCTAssertNil(coordinator.pendingMenuAction)
        coordinator.presentPendingMenuAction(now: now)
        XCTAssertEqual(coordinator.actions.confirmation?.id, confirmation)
        XCTAssertFalse(coordinator.isOperating) // No quit has been executed.
    }

    @MainActor
    func testMenuQuitRejectsProtectedAppsBusyStateExpiredAndCancelledRequests() {
        let coordinator = PerformanceCoordinator()
        var busy = false
        coordinator.configure(isLicensed: { true }, requestUnlock: {}, openStorage: {},
                              openPerformance: {}, fileOperationActive: { busy })
        coordinator.requestMenuAction(.quitApp, group: group("Protected", quittable: false))
        XCTAssertNil(coordinator.pendingMenuAction)
        busy = true
        coordinator.requestMenuAction(.quitApp, group: group("Editor"))
        XCTAssertNil(coordinator.pendingMenuAction)
        busy = false
        let now = Date()
        coordinator.requestMenuAction(.quitApp, group: group("Editor"), now: now)
        coordinator.presentPendingMenuAction(now: now.addingTimeInterval(6))
        XCTAssertNil(coordinator.actions.confirmation)
        XCTAssertNil(coordinator.pendingMenuAction)
        coordinator.requestMenuAction(.quitApp, group: group("Editor"))
        coordinator.cancelPendingMenuAction()
        coordinator.presentPendingMenuAction()
        XCTAssertNil(coordinator.actions.confirmation)
        coordinator.requestMenuAction(.quitApp, group: group("Editor"))
        busy = true
        coordinator.presentPendingMenuAction()
        XCTAssertNil(coordinator.actions.confirmation)
    }

    @MainActor
    func testMenuQuitRechecksLicenseAtPresentationAndDoesNotReplay() {
        let coordinator = PerformanceCoordinator()
        var licensed = true
        var unlocks = 0
        coordinator.configure(isLicensed: { licensed }, requestUnlock: { unlocks += 1 }, openStorage: {},
                              openPerformance: {}, fileOperationActive: { false })
        coordinator.requestMenuAction(.quitApp, group: group("Editor"))
        licensed = false
        coordinator.presentPendingMenuAction()
        XCTAssertEqual(unlocks, 1)
        XCTAssertNil(coordinator.actions.confirmation)
        licensed = true
        coordinator.presentPendingMenuAction()
        XCTAssertNil(coordinator.actions.confirmation)
    }

    private func group(_ name: String, memory: Int64 = 100, cpu: Double = 10, quittable: Bool = true) -> ProcessGroup {
        let path = "/Applications/\(name).app"
        return ProcessGroup(id: path, displayName: name, appPath: path,
                            members: [ProcessUsage(pid: 12345, ppid: 1, uid: 501, user: "fixture",
                                                   path: path + "/Contents/MacOS/" + name, name: name,
                                                   cpuPercent: cpu, memoryBytes: memory)],
                            cpuPercent: cpu, memoryBytes: memory, quittable: quittable)
    }
}
