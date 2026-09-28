import XCTest
@testable import DisplayRecall

final class CommandStatusStoreTests: XCTestCase {
    func testRoundTripsCommandStatus() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = CommandStatusStore(directoryURL: directory)
        let status = DisplayRecallCommandStatus(
            requestID: "request-123",
            command: .restore,
            state: .completed,
            message: "已恢复 2 个窗口",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            permissionGranted: true,
            hasExternalDisplay: true,
            savedWindowCount: 2,
            savedAt: Date(timeIntervalSince1970: 1_699_999_000),
            externalDisplayName: "External Display",
            matchedWindowCount: 2,
            restoredWindowCount: 2,
            failedWindowCount: 0
        )

        try store.save(status)

        XCTAssertEqual(try store.load(), status)
        XCTAssertEqual(store.fileURL.lastPathComponent, "command-status-v1.json")
    }
}
