import XCTest
@testable import PerformanceCore

final class BrowserTabsTests: XCTestCase {
    func windows() throws -> [BrowserWindow] {
        TabScript.parse(try fixture("tabs-output.txt"), appName: "Google Chrome")
    }

    func testParseFixture() throws {
        let w = try windows()
        XCTAssertEqual(w.map(\.id), ["1", "2", "3"])
        XCTAssertEqual(w.map(\.isIncognito), [false, false, true])
        XCTAssertEqual(w[0].profile, "Work")
        XCTAssertNil(w[1].profile)
        XCTAssertEqual(w[0].tabs.map(\.isActive), [false, true])
        XCTAssertEqual(w[1].tabs.count, 3)
        XCTAssertEqual(w[1].tabs[0].id, "2/21")
    }

    func testProfileFromTitle() {
        XCTAssertEqual(TabCleanup.profile(fromWindowName: "Inbox - Google Chrome - Work", appName: "Google Chrome"), "Work")
        XCTAssertNil(TabCleanup.profile(fromWindowName: "Inbox - Google Chrome", appName: "Google Chrome"))
    }

    func testNormalize() {
        XCTAssertEqual(TabCleanup.normalize("HTTPS://A.com/x/#frag"), "https://a.com/x")
        XCTAssertEqual(TabCleanup.normalize("https://a.com/x?q=1"), "https://a.com/x?q=1")
        XCTAssertEqual(TabCleanup.normalize("https://a.com/"), "https://a.com")
    }

    func win(_ id: String, _ profile: String?, incognito: Bool = false, _ urls: [String]) -> BrowserWindow {
        BrowserWindow(id: id, isIncognito: incognito, profile: profile,
                      tabs: urls.enumerated().map { i, u in
                          BrowserTab(id: "\(id)/\(i)", windowID: id, tabID: "\(i)", title: u, url: u, isActive: i == 0)
                      })
    }

    func testDuplicatesSkipIncognito() {
        let w = [win("1", nil, ["https://a.com/x"]), win("2", nil, ["https://A.com/x/", "https://b.com"]),
                 win("3", nil, incognito: true, ["https://a.com/x"])]
        XCTAssertEqual(TabCleanup.duplicates(in: w).map(\.id), ["2/0"])
    }

    func testDuplicatesArePerProfile() {
        // Two Gmail accounts in two profiles are not duplicates.
        let w = [win("1", "Work", ["https://mail.google.com/mail/u/0/"]), win("2", "Personal", ["https://mail.google.com/mail/u/0/"])]
        XCTAssertTrue(TabCleanup.duplicates(in: w).isEmpty)
        // The fixture's matching Docs tabs sit in different profiles (Work vs default).
        XCTAssertTrue(TabCleanup.duplicates(in: try! windows()).isEmpty)
    }

    func testMergeSkipsIncognito() throws {
        let w = [win("1", nil, ["https://a.com", "https://b.com"]), win("2", nil, ["https://c.com", "https://d.com", "https://e.com"]),
                 win("3", nil, incognito: true, ["https://secret.com"])]
        let plan = try XCTUnwrap(TabCleanup.mergePlan(w))
        XCTAssertEqual(plan.targetWindowID, "2")
        XCTAssertEqual(plan.urls, ["https://a.com", "https://b.com"])
        XCTAssertEqual(plan.windowsToClose, ["1"])
        XCTAssertNil(TabCleanup.mergePlan(Array(w.dropFirst())))
    }

    func testMergeStaysInsideOneProfile() throws {
        let w = [win("1", "Work", ["https://a.com", "https://b.com"]), win("2", "Personal", ["https://c.com", "https://d.com", "https://e.com"]),
                 win("3", "Work", ["https://f.com"])]
        let plan = try XCTUnwrap(TabCleanup.mergePlan(w))
        XCTAssertEqual(plan.profile, "Work")
        XCTAssertEqual(plan.targetWindowID, "1")
        XCTAssertEqual(plan.urls, ["https://f.com"])
        XCTAssertEqual(plan.windowsToClose, ["3"])
        XCTAssertNil(TabCleanup.mergePlan(try windows()), "Work and default-profile windows must not merge")
    }

    func testUnknownWindowModeFailsClosed() {
        let out = ["W", "5", "guest", "1", "Guest - Google Chrome"].joined(separator: "\u{1F}") + "\u{1E}"
        XCTAssertEqual(TabScript.parse(out, appName: "Google Chrome").first?.isIncognito, true)
    }

    func testScriptsRequireNormalMode() {
        let tab = BrowserTab(id: "1/7", windowID: "1", tabID: "7", title: "x", url: "u", isActive: false)
        XCTAssertTrue(TabScript.close([tab], .chrome).contains("(first window whose id is 1 and mode is \"normal\")"))
        let merge = TabScript.merge(MergePlan(targetWindowID: "2", urls: ["https://a.com"], windowsToClose: ["1"], profile: nil), .chrome)
        XCTAssertTrue(merge.contains("(first window whose id is 2 and mode is \"normal\")"), merge)
        XCTAssertTrue(merge.contains("close (first window whose id is 1 and mode is \"normal\")"), merge)
    }

    func testOnlyASCIIDigitsStayBare() {
        XCTAssertEqual(TabScript.literal("12"), "12")
        XCTAssertEqual(TabScript.literal("١٢"), "\"١٢\"")
    }

    func testExtensionsFromArgs() throws {
        let u = TabCleanup.extensions(fromPSArgs: try fixture("ps-args.txt"), appPath: "/Applications/Google Chrome.app")
        XCTAssertEqual(u.count, 3)
        XCTAssertEqual(u.memoryBytes, (446944 + 230272 + 251920) * 1024)
    }

    func testScriptsEscapeAndTarget() {
        let tab = BrowserTab(id: "a\"b/7", windowID: "a\"b", tabID: "7", title: "x", url: "u", isActive: false)
        let src = TabScript.close([tab], .chrome)
        XCTAssertTrue(src.contains("tell application id \"com.google.Chrome\""))
        XCTAssertTrue(src.contains("(first window whose id is \"a\\\"b\" and mode is \"normal\") whose id is 7"), src)
        let merge = TabScript.merge(MergePlan(targetWindowID: "2", urls: ["https://a.com/\"x"], windowsToClose: ["1"], profile: nil), .brave)
        XCTAssertTrue(merge.contains("tell application id \"com.brave.Browser\""))
        XCTAssertTrue(merge.contains("{URL:\"https://a.com/\\\"x\"}"), merge)
        XCTAssertTrue(merge.contains("close (first window whose id is 1 and mode is \"normal\")"), merge)
        XCTAssertTrue(TabScript.openMemorySaver(.edge).contains("edge://settings/system/managePerformance"))
    }

    func testStderrMapping() {
        XCTAssertEqual(OSAScriptRunner.error(fromStderr: "execution error: Not authorized to send Apple events to Google Chrome. (-1743)"), .notPermitted)
        XCTAssertEqual(OSAScriptRunner.error(fromStderr: "execution error: Application isn't running. (-600)"), .notRunning)
        XCTAssertEqual(OSAScriptRunner.error(fromStderr: "boom\n"), .failed("boom"))
    }

    struct FakeRunner: ScriptRunner {
        let result: Result<String, BrowserError>
        func run(_ source: String) async throws -> String { try result.get() }
    }

    func testErrorMapping() async throws {
        let denied = BrowserController(runner: FakeRunner(result: .failure(.notPermitted)), isRunning: { _ in true })
        do {
            _ = try await denied.windows(.chrome)
            XCTFail("expected notPermitted")
        } catch let e as BrowserError {
            XCTAssertEqual(e, .notPermitted)
        }
        let ok = BrowserController(runner: FakeRunner(result: .success(try fixture("tabs-output.txt"))), isRunning: { _ in true })
        let w = try await ok.windows(.chrome)
        XCTAssertEqual(w.count, 3)
    }

    func testNotRunningNeverLaunchesBrowser() async {
        let c = BrowserController(runner: FakeRunner(result: .success("")), isRunning: { _ in false })
        do {
            _ = try await c.windows(.chrome)
            XCTFail("expected notRunning")
        } catch {
            XCTAssertEqual(error as? BrowserError, .notRunning)
        }
    }
}
