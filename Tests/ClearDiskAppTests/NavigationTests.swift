import XCTest
@testable import ClearDiskApp

final class NavigationTests: XCTestCase {
    @MainActor
    func testEveryWorkspaceCanReturnToScanWithoutAResult() {
        for workspace in [AppState.Workspace.iCloud, .macChecks, .performance] {
            let state = AppState()
            state.openWorkspace(workspace)
            state.openWorkspace(.storage)
            XCTAssertEqual(state.phase, .welcome)
            XCTAssertFalse(state.showPermissions)
            XCTAssertFalse(state.showICloudDoctor)
            XCTAssertFalse(state.showMacChecks)
            XCTAssertFalse(state.showPerformance)
        }
    }

    @MainActor
    func testPermissionsBackRetainsOriginAndDoesNotStartScan() {
        for workspace in [AppState.Workspace.storage, .iCloud, .macChecks, .performance] {
            let state = AppState()
            state.openWorkspace(workspace)
            state.showDiskAccess()
            XCTAssertTrue(state.showPermissions)
            XCTAssertEqual(state.phase, .welcome)
            state.leaveDiskAccess()
            XCTAssertFalse(state.showPermissions)
            XCTAssertEqual(state.showMacChecks, workspace == .macChecks)
            XCTAssertEqual(state.showPerformance, workspace == .performance)
            XCTAssertEqual(state.showICloudDoctor, workspace == .iCloud)
            XCTAssertEqual(state.phase, .welcome)
        }
    }

    @MainActor
    func testPermissionsCannotOverwriteScanProgressOrCompletion() {
        let state = AppState()
        state.phase = .scanning
        state.showDiskAccess()
        XCTAssertEqual(state.phase, .scanning)
        state.phase = .done // A scan completes while permission help is open.
        state.leaveDiskAccess()
        XCTAssertEqual(state.phase, .done)
        XCTAssertEqual(state.diskNavigationTitle, "Scan results")
    }

    @MainActor
    func testExplicitNavigationDismissesPermissionsWithoutChangingResults() {
        let state = AppState()
        state.phase = .done
        state.section = .largeFiles
        state.showDiskAccess()
        state.openWorkspace(.macChecks)
        XCTAssertFalse(state.showPermissions)
        XCTAssertTrue(state.showMacChecks)
        state.openWorkspace(.storage)
        XCTAssertEqual(state.phase, .done)
        XCTAssertEqual(state.section, .largeFiles)
    }
}
