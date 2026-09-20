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

    func testRuntimeWindowIDKeepsIdenticalWindowsInOriginalSlots() {
        let saved = [
            makeSaved(titleHash: "same", ordinal: 0, ownerPID: 42, windowID: 333),
            makeSaved(titleHash: "same", ordinal: 1, ownerPID: 42, windowID: 345)
        ]
        let live = [
            makeKey(titleHash: "same", ordinal: 0, ownerPID: 42, windowID: 345),
            makeKey(titleHash: "same", ordinal: 1, ownerPID: 42, windowID: 333)
        ]

        let pairs = WindowMatcher.match(saved: saved, liveKeys: live)

        XCTAssertEqual(pairs.map(\.liveIndex), [1, 0])
    }

    func testOldSnapshotKeyDecodesWithoutRuntimeIdentity() throws {
        let data = Data(
            #"{"bundleIdentifier":"com.example.app","role":"AXWindow","ordinal":0}"#.utf8
        )

        let key = try JSONDecoder().decode(WindowMatchKey.self, from: data)

        XCTAssertNil(key.runtimeOwnerPID)
        XCTAssertNil(key.runtimeWindowID)
    }

    private func makeSaved(
        titleHash: String,
        ordinal: Int,
        ownerPID: Int32? = nil,
        windowID: UInt32? = nil
    ) -> SavedWindow {
        SavedWindow(
            id: UUID(),
            appName: "Example",
            matchKey: makeKey(
                titleHash: titleHash,
                ordinal: ordinal,
                ownerPID: ownerPID,
                windowID: windowID
            ),
            displaySlot: DisplaySlot(role: .external, index: 0, exactUUID: nil),
            normalizedFrame: NormalizedFrame(x: 0, y: 0, width: 0.5, height: 1),
            sourceFrame: RectRecord(CGRect(x: 0, y: 0, width: 500, height: 800))
        )
    }

    private func makeKey(
        titleHash: String,
        ordinal: Int,
        ownerPID: Int32? = nil,
        windowID: UInt32? = nil
    ) -> WindowMatchKey {
        WindowMatchKey(
            bundleIdentifier: "com.example.app",
            identifier: nil,
            titleHash: titleHash,
            documentHash: nil,
            role: "AXWindow",
            subrole: "AXStandardWindow",
            ordinal: ordinal,
            runtimeOwnerPID: ownerPID,
            runtimeWindowID: windowID
        )
    }
}
