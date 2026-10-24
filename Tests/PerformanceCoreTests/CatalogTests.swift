import XCTest
@testable import PerformanceCore

final class CatalogTests: XCTestCase {
    let c = try! ProcessCatalog.bundled()

    func testSizeAndUniqueness() {
        XCTAssertGreaterThanOrEqual(c.entries.count, 80)
        XCTAssertEqual(Set(c.entries.map(\.id)).count, c.entries.count)
    }

    func testLeaveEntriesNeverQuit() {
        for e in c.entries where e.verdict == .leave {
            XCTAssertFalse(e.fixes.contains(.quitApp), e.id)
        }
    }

    func testGuideSlugs() {
        for e in c.entries {
            XCTAssertNotNil(e.guide.range(of: #"^[a-z0-9]+(-[a-z0-9]+)*$"#, options: .regularExpression), e.id)
        }
    }

    func testCopyLengths() {
        for e in c.entries {
            XCTAssertLessThanOrEqual(e.summary.count, 90, e.id)
            XCTAssertLessThanOrEqual(e.whyHigh.count, 160, e.id)
            XCTAssertFalse(e.summary.contains("!") || e.whyHigh.contains("!"), e.id)
        }
    }

    func testMatching() {
        XCTAssertEqual(c.explain(name: "mds_stores", path: "/System/Library/Frameworks/CoreServices.framework/mds_stores", appName: nil).title,
                       "Spotlight file indexing")
        XCTAssertEqual(c.explain(name: "com.apple.Virtualization.VirtualMachine",
                                 path: "/System/Library/Frameworks/Virtualization.framework/Versions/A/XPCServices/x.xpc/Contents/MacOS/com.apple.Virtualization.VirtualMachine",
                                 appName: nil).title, "Virtual machine")
        XCTAssertEqual(c.explain(launchdLabel: "com.google.keystone.agent", ownerApp: nil).title, "Google Software Update")
    }

    func testFallbacks() {
        let sys = c.explain(name: "zzz", path: "/usr/libexec/zzz", appName: nil)
        XCTAssertEqual(sys.title, "Part of macOS")
        XCTAssertEqual(sys.verdict, .leave)
        XCTAssertTrue(sys.isFallback)
        let app = c.explain(name: "Notion", path: "/Applications/Notion.app/Contents/MacOS/Notion", appName: "Notion")
        XCTAssertEqual(app.title, "Part of Notion")
        XCTAssertEqual(app.verdict, .safe)
        XCTAssertEqual(app.fixes, [.quitApp])
        let unk = c.explain(name: "node-x", path: "/opt/homebrew/bin/node-x", appName: nil)
        XCTAssertEqual(unk.title, "Not in our list yet")
        XCTAssertEqual(unk.verdict, .review)
        // Spec §10: background items fall back to "Added by ⟨App⟩" / "Unknown developer".
        XCTAssertEqual(c.explain(launchdLabel: "org.unknown.thing", ownerApp: "Thing").title, "Added by Thing")
        XCTAssertEqual(c.explain(launchdLabel: "org.unknown.thing", ownerApp: nil).title, "Unknown developer")
    }

    func testClearDiskExplainsItself() {
        let e = c.explain(name: "ClearDisk", path: "/Applications/ClearDisk.app/Contents/MacOS/ClearDisk", appName: "ClearDisk")
        XCTAssertEqual(e.title, "ClearDisk (this app)")
        XCTAssertEqual(e.verdict, .leave)
        XCTAssertEqual(c.explain(name: "ClearDiskApp", path: "/x/.build/debug/ClearDiskApp", appName: nil).title, "ClearDisk (this app)")
    }

    func testVerdictLabels() {
        XCTAssertEqual(Verdict.safe.label, "Safe to quit")
        XCTAssertEqual(Verdict.review.label, "Review")
        XCTAssertEqual(Verdict.leave.label, "Leave it")
    }
}
