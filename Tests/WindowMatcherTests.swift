import XCTest
@testable import DisplayRecall

final class WindowMatcherTests: XCTestCase {
    func testPrefersTitleMatchOverOrdinalFallback() {
        let saved = [
            makeSaved(titleHash: "alpha", ordinal: 0),
            makeSaved(titleHash: "beta", ordinal: 1)
        ]
        let live = [
            makeKey(titleHash: "beta", ordinal: 0),
            makeKey(titleHash: "alpha", ordinal: 1)
        ]

        let pairs = WindowMatcher.match(saved: saved, liveKeys: live)

        XCTAssertEqual(pairs.map(\.liveIndex), [1, 0])
    }

    func testDoesNotMatchDifferentApplications() {
        let saved = [makeSaved(titleHash: "alpha", ordinal: 0)]
        let live = [
            WindowMatchKey(
                bundleIdentifier: "com.example.other",
                identifier: nil,
                titleHash: "alpha",
                documentHash: nil,
                role: "AXWindow",
                subrole: "AXStandardWindow",
                ordinal: 0
            )
        ]

        XCTAssertTrue(WindowMatcher.match(saved: saved, liveKeys: live).isEmpty)
    }

    private func makeSaved(titleHash: String, ordinal: Int) -> SavedWindow {
        SavedWindow(
            id: UUID(),
            appName: "Example",
            matchKey: makeKey(titleHash: titleHash, ordinal: ordinal),
            displaySlot: DisplaySlot(role: .external, index: 0, exactUUID: nil),
            normalizedFrame: NormalizedFrame(x: 0, y: 0, width: 0.5, height: 1),
            sourceFrame: RectRecord(CGRect(x: 0, y: 0, width: 500, height: 800))
        )
    }

    private func makeKey(titleHash: String, ordinal: Int) -> WindowMatchKey {
        WindowMatchKey(
            bundleIdentifier: "com.example.app",
            identifier: nil,
            titleHash: titleHash,
            documentHash: nil,
            role: "AXWindow",
            subrole: "AXStandardWindow",
            ordinal: ordinal
        )
    }
}
