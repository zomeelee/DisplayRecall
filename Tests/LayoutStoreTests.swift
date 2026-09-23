import XCTest
@testable import DisplayRecall

final class LayoutStoreTests: XCTestCase {
    func testUsesBundleIdentifierForDataDirectory() {
        let store = LayoutStore(bundleIdentifier: "org.example.DisplayRecall")

        XCTAssertEqual(store.directoryURL.lastPathComponent, "org.example.DisplayRecall")
        XCTAssertEqual(store.fileURL.lastPathComponent, "layout-v1.json")
    }
}
