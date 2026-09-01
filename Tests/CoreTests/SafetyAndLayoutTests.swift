import Foundation
import XCTest
@testable import Core

final class SafetyAndLayoutTests: XCTestCase {

    // MARK: - TrashService blocklist

    func testProtectedPathsRefused() {
        let home = NSHomeDirectory()
        let refused = [
            home,
            home + "/Library",
            home + "/Library/Preferences",
            home + "/Library/Keychains",
            home + "/Library/Preferences/com.apple.dock.plist",
            home + "/Library/Mail/V10",
            home + "/Library/Mobile Documents/com~apple~CloudDocs",
            home + "/Library/Application Support/AddressBook",
            "/System/Library",
            "/usr/bin",
            "/tmp/whatever",
        ]
        for path in refused {
            if case .allowed = TrashService.verdict(forTrashing: path) {
                XCTFail("should refuse: \(path)")
            }
        }
    }

    func testCleanablePathsAllowed() {
        let home = NSHomeDirectory()
        let allowed = [
            home + "/Library/Caches/com.example.app",
            home + "/Library/Logs/old.log",
            home + "/Library/Developer/Xcode/DerivedData",
            home + "/Library/Application Support/MobileSync/Backup/abc123",
            home + "/Downloads/old-installer.dmg",
            home + "/Documents/junk.txt",
        ]
        for path in allowed {
            XCTAssertEqual(TrashService.verdict(forTrashing: path), .allowed, path)
        }
    }

    func testTrashRoundTrip() throws {
        let dir = NSHomeDirectory() + "/.macclear-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: false)
        let file = dir + "/victim.txt"
        try "bye".write(toFile: file, atomically: true, encoding: .utf8)

        let trashedTo = try TrashService.trash(file)
        XCTAssertNotNil(trashedTo)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file))

        // Clean up: put it back (the undo path), then remove the fixture dir.
        try FileManager.default.moveItem(at: trashedTo!, to: URL(fileURLWithPath: file))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file))
        _ = try TrashService.trash(dir)
    }

    func testTrashContentsAndRestore() throws {
        let dir = NSHomeDirectory() + "/.cleardisk-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: false)
        try "a".write(toFile: dir + "/a.txt", atomically: true, encoding: .utf8)
        try "b".write(toFile: dir + "/b.txt", atomically: true, encoding: .utf8)

        let result = TrashService.trashContents(of: dir)
        XCTAssertEqual(result.trashed.count, 2)
        XCTAssertEqual(result.failed, 0)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: dir).isEmpty)

        // Undo brings both back.
        XCTAssertEqual(TrashService.restore(result.trashed), 2)
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: dir)),
                       ["a.txt", "b.txt"])
        _ = try TrashService.trash(dir)
    }

    // MARK: - Squarify

    func testSquarifyCoversAreaExactly() {
        let sizes: [Double] = [6, 6, 4, 3, 2, 2, 1]
        let rect = CGRect(x: 0, y: 0, width: 600, height: 400)
        let items = Squarify.layout(sizes: sizes, in: rect)

        XCTAssertEqual(items.count, sizes.count)
        let area = items.reduce(0.0) { $0 + Double($1.rect.width * $1.rect.height) }
        XCTAssertEqual(area, Double(rect.width * rect.height), accuracy: 1.0)

        // Every rect stays inside the frame.
        for item in items {
            XCTAssertTrue(rect.insetBy(dx: -0.01, dy: -0.01).contains(item.rect), "\(item.rect)")
        }
        // All input indexes appear exactly once.
        XCTAssertEqual(Set(items.map(\.index)), Set(sizes.indices))
    }

    func testSquarifyAreasProportionalToSizes() {
        let sizes: [Double] = [8, 4, 2, 1]
        let rect = CGRect(x: 0, y: 0, width: 300, height: 200)
        let items = Squarify.layout(sizes: sizes, in: rect)
        let total = sizes.reduce(0, +)
        for item in items {
            let expected = sizes[item.index] / total * Double(rect.width * rect.height)
            XCTAssertEqual(Double(item.rect.width * item.rect.height), expected, accuracy: 0.5)
        }
    }

    func testSquarifyDegenerateInputs() {
        XCTAssertTrue(Squarify.layout(sizes: [], in: CGRect(x: 0, y: 0, width: 100, height: 100)).isEmpty)
        XCTAssertTrue(Squarify.layout(sizes: [0, 0], in: CGRect(x: 0, y: 0, width: 100, height: 100)).isEmpty)
        XCTAssertTrue(Squarify.layout(sizes: [5], in: .zero).isEmpty)
    }

    // MARK: - Categorizer

    func testCategorizerBucketsKnownTopLevels() {
        func dir(_ name: String, size: Int64, children: [FileNode] = []) -> FileNode {
            let node = FileNode(name: name, isDirectory: true, size: size, modTime: 0)
            node.children = children
            return node
        }
        let root = dir("home", size: 1000, children: [
            dir("Pictures", size: 400),
            dir("Downloads", size: 100),
            dir(".npm", size: 50),
            dir("Library", size: 300, children: [
                dir("Caches", size: 200),
                dir("Mail", size: 60),
                dir("CloudStorage", size: 40),
            ]),
        ])
        let totals = Dictionary(uniqueKeysWithValues: Categorizer.homeTotals(root: root)
            .map { ($0.category, $0.bytes) })
        XCTAssertEqual(totals[.photosVideos], 400)
        XCTAssertEqual(totals[.downloads], 100)
        XCTAssertEqual(totals[.devJunk], 50)
        XCTAssertEqual(totals[.systemData], 200)
        XCTAssertEqual(totals[.mail], 60)
        XCTAssertEqual(totals[.cloud], 40)
    }
}
