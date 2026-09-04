import XCTest
@testable import Core

final class TreemapLayoutTests: XCTestCase {
    func testNestedGeometryKeepsIdentityAndStaysInsideParent() throws {
        let input = [TreemapLayout.Entry(id: 7, size: 100, children: [.init(id: 9, size: 60), .init(id: 10, size: 40)])]
        let result = try TreemapLayout.layout(entries: input, in: CGRect(x: 0, y: 0, width: 800, height: 500))
        let parent = try XCTUnwrap(result.first { $0.id == 7 })
        XCTAssertEqual(Set(result.map(\.id)), [7, 9, 10])
        for child in result where child.depth == 1 {
            XCTAssertTrue(parent.rect.contains(child.rect))
            XCTAssertGreaterThanOrEqual(child.rect.minY, parent.rect.minY + 40)
        }
    }

    func testEmptyAndNonPositiveInputsProduceNoTiles() throws {
        XCTAssertTrue(try TreemapLayout.layout(entries: [], in: .zero).isEmpty)
        XCTAssertTrue(try TreemapLayout.layout(entries: [.init(id: 1, size: 0)], in: CGRect(x: 0, y: 0, width: 500, height: 400)).isEmpty)
    }

    func testCancellationStopsLayout() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try TreemapLayout.layout(entries: [.init(id: 1, size: 100)], in: CGRect(x: 0, y: 0, width: 800, height: 500))
        }
        do { _ = try await task.value; XCTFail("Cancelled layout published a result") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    func testLargestChildrenAreBoundedStableAndExcludeEmptyNodes() {
        let root = FileNode(name: "root", isDirectory: true, size: 0, modTime: 0)
        root.children = [5, 100, 100, 0, 40].enumerated().map { index, size in
            FileNode(name: "\(index)", isDirectory: false, size: Int64(size), modTime: 0)
        }
        XCTAssertEqual(root.largestChildren(limit: 3).map(\.name), ["1", "2", "4"])
        XCTAssertTrue(root.largestChildren(limit: 0).isEmpty)
    }
}
