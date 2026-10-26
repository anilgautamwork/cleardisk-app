import XCTest
@testable import PerformanceUI

final class PerformanceIntegrationTests: XCTestCase {
    @MainActor
    func testClearDiskEntitlementIsReadAtActionTime() {
        let coordinator = PerformanceCoordinator()
        var licensed = true
        var unlocks = 0
        var operationActive = false
        coordinator.configure(isLicensed: { licensed }, requestUnlock: { unlocks += 1 },
                              openStorage: {}, openPerformance: {}, fileOperationActive: { operationActive })
        XCTAssertTrue(coordinator.actions.mayRunPaidAction())
        licensed = false
        XCTAssertFalse(coordinator.actions.mayRunPaidAction())
        XCTAssertEqual(unlocks, 1)
        licensed = true
        operationActive = true
        XCTAssertFalse(coordinator.actions.mayRunPaidAction())
        XCTAssertEqual(unlocks, 1)
    }

    @MainActor
    func testProcessShortcutOnlyNavigatesAndClearsOldSelection() {
        let coordinator = PerformanceCoordinator()
        coordinator.router.screen = .usage
        coordinator.router.expandedID = "old-process"
        coordinator.showProcesses()
        XCTAssertEqual(coordinator.router.screen, .processes)
        XCTAssertNil(coordinator.router.expandedID)
        XCTAssertNil(coordinator.actions.confirmation)
        XCTAssertFalse(coordinator.isOperating)
        XCTAssertFalse(coordinator.monitor.enabled)
        coordinator.showProcesses()
        XCTAssertEqual(coordinator.router.screen, .processes)
    }

    @MainActor
    func testStorageActionRoutesInsideClearDisk() {
        let coordinator = PerformanceCoordinator()
        var navigations = 0
        coordinator.configure(isLicensed: { false }, requestUnlock: {}, openStorage: { navigations += 1 },
                              openPerformance: {}, fileOperationActive: { false })
        coordinator.actions.perform(.openClearDisk, group: nil)
        XCTAssertEqual(navigations, 1)
        XCTAssertFalse(coordinator.isOperating)
    }

    @MainActor
    func testMonitoringStopsWhenWindowAndMenuBarAreClosed() {
        let coordinator = PerformanceCoordinator()
        XCTAssertFalse(coordinator.monitor.enabled)
        coordinator.setMonitoring(visible: true, menuBar: false)
        XCTAssertTrue(coordinator.monitor.enabled)
        coordinator.setMonitoring(visible: false, menuBar: true)
        XCTAssertTrue(coordinator.monitor.enabled)
        coordinator.setMonitoring(visible: false, menuBar: false)
        XCTAssertFalse(coordinator.monitor.enabled)
        XCTAssertFalse(coordinator.monitor.windowVisible)
    }

    @MainActor
    func testLockedActionDoesNotReplayAfterLicenseChanges() {
        let coordinator = PerformanceCoordinator()
        var licensed = false
        var ran = false
        coordinator.configure(isLicensed: { licensed }, requestUnlock: {}, openStorage: {},
                              openPerformance: {}, fileOperationActive: { false })
        coordinator.actions.requireLicense { ran = true }
        licensed = true
        XCTAssertFalse(ran)
    }

    @MainActor
    func testLicenseSheetWaitsForChildSheetDismissal() {
        let coordinator = PerformanceCoordinator()
        var unlocks = 0
        coordinator.configure(isLicensed: { false }, requestUnlock: { unlocks += 1 }, openStorage: {},
                              openPerformance: {}, fileOperationActive: { false })
        coordinator.license.pendingUnlock = true
        XCTAssertEqual(unlocks, 0)
        coordinator.license.presentPendingUnlock()
        coordinator.license.presentPendingUnlock()
        XCTAssertEqual(unlocks, 1)
    }
}
