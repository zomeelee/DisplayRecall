import XCTest
@testable import DisplayRecall

final class DisplayRecallCommandTests: XCTestCase {
    func testParsesHostCommandAndRequestID() throws {
        let url = try XCTUnwrap(
            URL(string: "displayrecall://save?request=request-123")
        )
        let request = try XCTUnwrap(DisplayRecallCommandRequest(url: url))

        XCTAssertEqual(request.action, .save)
        XCTAssertEqual(request.requestID, "request-123")
    }

    func testParsesPathCommand() throws {
        let url = try XCTUnwrap(
            URL(string: "displayrecall:///restore?request=request-456")
        )
        let request = try XCTUnwrap(DisplayRecallCommandRequest(url: url))

        XCTAssertEqual(request.action, .restore)
        XCTAssertEqual(request.requestID, "request-456")
    }

    func testGeneratesRequestIDWhenMissing() throws {
        let url = try XCTUnwrap(URL(string: "displayrecall://status"))
        let request = try XCTUnwrap(DisplayRecallCommandRequest(url: url))

        XCTAssertEqual(request.action, .status)
        XCTAssertFalse(request.requestID.isEmpty)
    }

    func testRejectsUnsupportedURLs() throws {
        let wrongScheme = try XCTUnwrap(URL(string: "https://save"))
        let wrongAction = try XCTUnwrap(URL(string: "displayrecall://delete"))

        XCTAssertNil(DisplayRecallCommandRequest(url: wrongScheme))
        XCTAssertNil(DisplayRecallCommandRequest(url: wrongAction))
    }
}
