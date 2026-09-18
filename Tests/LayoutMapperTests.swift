import XCTest
@testable import DisplayRecall

final class LayoutMapperTests: XCTestCase {
    func testMapsLayoutProportionallyToDifferentDisplaySize() {
        let sourceDisplay = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let sourceWindow = CGRect(x: 500, y: 0, width: 500, height: 800)
        let normalized = LayoutMapper.normalize(sourceWindow, in: sourceDisplay)

        let target = LayoutMapper.map(
            normalized,
            to: CGRect(x: 1500, y: 120, width: 2000, height: 1000)
        )

        XCTAssertEqual(target.origin.x, 2500, accuracy: 0.001)
        XCTAssertEqual(target.origin.y, 120, accuracy: 0.001)
        XCTAssertEqual(target.size.width, 1000, accuracy: 0.001)
        XCTAssertEqual(target.size.height, 1000, accuracy: 0.001)
    }

    func testClampsWindowToVisibleFrame() {
        let result = LayoutMapper.map(
            NormalizedFrame(x: -0.4, y: 0.9, width: 2.0, height: 0.5),
            to: CGRect(x: 100, y: 200, width: 800, height: 600)
        )

        XCTAssertEqual(result.minX, 100, accuracy: 0.001)
        XCTAssertEqual(result.width, 800, accuracy: 0.001)
        XCTAssertLessThanOrEqual(result.maxY, 800.001)
    }
}
