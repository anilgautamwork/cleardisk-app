import XCTest
@testable import PerformanceCore

final class BackgroundItemsTests: XCTestCase {
    func plist(_ name: String) throws -> Data { try Data(contentsOf: fixtureURL(name)) }

    func testParseProgram() throws {
        let i = try XCTUnwrap(BackgroundItemsReader.parse(plist: plist("agent-program.plist"), source: "/x.plist", scope: .userAgent))
        XCTAssertEqual(i.label, "com.example.updater")
        XCTAssertEqual(i.program, "/Library/Example/updater")
        XCTAssertTrue(i.runAtLoad)
        XCTAssertTrue(i.keepAlive)
    }

    func testParseProgramArgumentsFallback() throws {
        let i = try XCTUnwrap(BackgroundItemsReader.parse(plist: plist("agent-args.plist"), source: "/x.plist", scope: .systemDaemon))
        XCTAssertEqual(i.program, "/usr/local/bin/helper")
        XCTAssertFalse(i.runAtLoad)
        XCTAssertFalse(i.keepAlive)
    }

    func testNoLabelIsNil() throws {
        XCTAssertNil(BackgroundItemsReader.parse(plist: try plist("agent-nolabel.plist"), source: "/x.plist", scope: .userAgent))
        XCTAssertNil(BackgroundItemsReader.parse(plist: Data("garbage".utf8), source: "/x.plist", scope: .userAgent))
    }

    func testLaunchctlList() {
        XCTAssertEqual(BackgroundItemsReader.parseLaunchctlList("PID\tStatus\tLabel\n4225\t0\tcom.apple.progressd\n-\t0\tcom.x\n"),
                       ["com.apple.progressd": 4225])
    }

    func testOwnerFromAppPath() {
        XCTAssertEqual(BackgroundItemsReader.ownerApp(program: "/Applications/Google Chrome.app/Contents/Helpers/x", label: "z", installed: [:]),
                       "Google Chrome")
    }

    func testOwnerFromLabelPrefix() {
        XCTAssertEqual(BackgroundItemsReader.ownerApp(program: "/Library/Application Support/Google/GoogleUpdater/x",
                                                      label: "com.google.GoogleUpdater.wake",
                                                      installed: ["com.google.Chrome": "Google Chrome"]), "Google Chrome")
        XCTAssertNil(BackgroundItemsReader.ownerApp(program: nil, label: "org.nobody.x", installed: ["com.google.Chrome": "Google Chrome"]))
    }

    func testHelperAppOutsideApplicationsUsesLabel() {
        XCTAssertEqual(BackgroundItemsReader.ownerApp(
            program: "/Library/Application Support/Google/GoogleUpdater/Current/GoogleUpdater.app/Contents/MacOS/GoogleUpdater",
            label: "com.google.GoogleUpdater.wake", installed: ["com.google.Chrome": "Google Chrome"]), "Google Chrome")
        XCTAssertEqual(BackgroundItemsReader.ownerApp(program: "/Library/Helpers/Thing.app/Contents/MacOS/Thing",
                                                      label: "org.nobody.thing", installed: [:]), "Thing")
    }

    func testScanTempTree() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home")
        let agents = home.appendingPathComponent("Library/LaunchAgents")
        try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
        try plist("agent-program.plist").write(to: agents.appendingPathComponent("a.plist"))
        let bar = root.appendingPathComponent("Applications/Foo.app/Contents/Library/LoginItems/Bar.app/Contents")
        try FileManager.default.createDirectory(at: bar.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": "com.foo.bar", "CFBundleExecutable": "Bar"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: bar.appendingPathComponent("Info.plist"))

        let items = BackgroundItemsReader.scan(home: home, root: root).sorted { $0.label < $1.label }
        XCTAssertEqual(items.map(\.label), ["com.example.updater", "com.foo.bar"])
        XCTAssertEqual(items.map(\.scope), [.userAgent, .appBundled])
        XCTAssertEqual(items[1].ownerApp, "Foo")
        XCTAssertTrue(items[1].program?.hasSuffix("Bar.app/Contents/MacOS/Bar") ?? false)
    }

    func testMarkRunning() {
        let a = BackgroundItem(label: "com.a", program: "/opt/a", source: "/a.plist", scope: .userAgent, ownerApp: nil, runAtLoad: true, keepAlive: false, pid: nil)
        let b = BackgroundItem(label: "com.b", program: "/opt/b", source: "/b.plist", scope: .systemDaemon, ownerApp: nil, runAtLoad: true, keepAlive: false, pid: nil)
        let c = BackgroundItem(label: "com.c", program: "/opt/c", source: "/c.plist", scope: .systemDaemon, ownerApp: nil, runAtLoad: true, keepAlive: false, pid: nil)
        let p = ProcessSample(pid: 77, ppid: 1, uid: 0, user: "root", cpuTime: 0, rssBytes: 0, psCPU: 0, path: "/opt/b")
        let marked = BackgroundItemsReader.markRunning([a, b, c], launchctl: ["com.a": 12], processes: [p])
        XCTAssertEqual(marked.map(\.pid), [12, 77, nil])
    }
}
