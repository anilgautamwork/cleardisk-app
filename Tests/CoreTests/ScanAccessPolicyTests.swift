import XCTest
@testable import Core

final class ScanAccessPolicyTests: XCTestCase {
    func testDiskScanWaitsForConfirmedAccess() {
        XCTAssertEqual(ScanAccessPolicy.decision(path: "/", diskAccessConfirmed: false), .requestDiskAccess)
        XCTAssertEqual(ScanAccessPolicy.decision(path: "/", diskAccessConfirmed: true), .scan(path: "/"))
    }

    func testRootAliasesCannotBypassAccessGate() {
        for path in ["/", "//", "/./", "/Users/..", "/Users/../"] {
            XCTAssertEqual(ScanAccessPolicy.decision(path: path, diskAccessConfirmed: false), .requestDiskAccess, path)
        }
    }

    func testDeliberateFolderSelectionDoesNotProbeUnrelatedProtectedPaths() {
        var checkedAccess = false
        func probe() -> Bool { checkedAccess = true; return false }
        XCTAssertEqual(ScanAccessPolicy.decision(path: "/Users/tester/Documents", diskAccessConfirmed: probe()), .scan(path: "/Users/tester/Documents"))
        XCTAssertFalse(checkedAccess)
    }

    func testRescanRechecksAccessRatherThanTrustingEarlierGrant() {
        XCTAssertEqual(ScanAccessPolicy.decision(path: "/", diskAccessConfirmed: true), .scan(path: "/"))
        XCTAssertEqual(ScanAccessPolicy.decision(path: "/", diskAccessConfirmed: false), .requestDiskAccess)
    }
}
