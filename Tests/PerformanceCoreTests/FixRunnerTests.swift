import XCTest
@testable import PerformanceCore

final class FixRunnerTests: XCTestCase {
    func testMenuBarAppsCountAsUserApps() {
        // Docker is LSUIElement (.accessory): it must still be quittable.
        XCTAssertTrue(FixRunner.isUserApp(.regular))
        XCTAssertTrue(FixRunner.isUserApp(.accessory))
        XCTAssertFalse(FixRunner.isUserApp(.prohibited))
    }

    func testSettingsURLsValid() {
        for pane in SettingsPane.allCases {
            XCTAssertNotNil(URL(string: pane.rawValue), "\(pane)")
        }
    }

    func testRebuildScript() {
        XCTAssertEqual(FixRunner.rebuildScript, "do shell script \"/usr/bin/mdutil -E /\" with administrator privileges")
    }

    func testRestartScript() {
        XCTAssertEqual(FixRunner.restartScript, "tell application \"loginwindow\" to «event aevtrrst»")
    }

    func testErrorMapping() {
        XCTAssertEqual(FixOutcome(appleScriptErrorNumber: -128), .cancelled)
        XCTAssertEqual(FixOutcome(appleScriptErrorNumber: -1), .failed("-1"))
    }

    func testOsascriptOutcomeParsing() {
        XCTAssertEqual(FixRunner.outcome(status: 0, stderr: ""), .done)
        XCTAssertEqual(FixRunner.outcome(status: 1, stderr: "0:5: execution error: User canceled. (-128)\n"), .cancelled)
        XCTAssertEqual(FixRunner.outcome(status: 1, stderr: "execution error: Not authorized to send Apple events to loginwindow. (-1743)"), .failed("-1743"))
        XCTAssertEqual(FixRunner.outcome(status: 1, stderr: "boom"), .failed("boom"))
    }

    @MainActor
    func testQuitRefusesSystemPath() async {
        let notes = ProcessGroup.fixture(id: "/System/Applications/Notes.app", cpu: 1, name: "Notes",
                                         appPath: "/System/Applications/Notes.app", quittable: true,
                                         path: "/System/Applications/Notes.app/Contents/MacOS/Notes")
        let outcome = await FixRunner().quit(notes)
        XCTAssertTrue(outcome == .refused || outcome == .alreadyGone, "\(outcome)")
    }

    @MainActor
    func testQuitMissingAppIsAlreadyGone() async {
        let ghost = ProcessGroup.fixture(id: "/Applications/Definitely Not Installed.app", cpu: 1, name: "Definitely Not Installed",
                                         appPath: "/Applications/Definitely Not Installed.app", quittable: true)
        let outcome = await FixRunner().quit(ghost)
        XCTAssertEqual(outcome, .alreadyGone)
    }
}
