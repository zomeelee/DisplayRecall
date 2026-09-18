import CoreGraphics
import XCTest
@testable import DisplayRecall

final class DisplayTopologyTests: XCTestCase {
    func testMapsSavedExternalSlotToReplacementExternalDisplay() {
        let builtIn = makeDisplay(
            id: 1,
            uuid: "built-in-current",
            role: .builtIn,
            slotIndex: 0,
            isMain: true
        )
        let replacement = makeDisplay(
            id: 2,
            uuid: "external-new",
            role: .external,
            slotIndex: 0,
            isMain: false
        )
        let topology = DisplayTopology(displays: [builtIn, replacement], signature: "test")

        let target = topology.targetDisplay(
            for: DisplaySlot(role: .external, index: 0, exactUUID: "external-old")
        )

        XCTAssertEqual(target?.uuid, "external-new")
        XCTAssertEqual(target?.role, .external)
    }

    func testPrefersExactDisplayWhenItIsStillConnected() {
        let firstExternal = makeDisplay(
            id: 2,
            uuid: "external-first",
            role: .external,
            slotIndex: 0,
            isMain: false
        )
        let exactExternal = makeDisplay(
            id: 3,
            uuid: "external-exact",
            role: .external,
            slotIndex: 1,
            isMain: false
        )
        let topology = DisplayTopology(
            displays: [firstExternal, exactExternal],
            signature: "test"
        )

        let target = topology.targetDisplay(
            for: DisplaySlot(role: .external, index: 0, exactUUID: "external-exact")
        )

        XCTAssertEqual(target?.runtimeID, 3)
    }

    func testDetectsReplacementExternalDisplay() {
        let replacement = makeDisplay(
            id: 2,
            uuid: "external-new",
            role: .external,
            slotIndex: 0,
            isMain: false
        )
        let topology = DisplayTopology(displays: [replacement], signature: "test")
        let savedDisplays = [
            SavedDisplay(
                slot: DisplaySlot(role: .external, index: 0, exactUUID: "external-old"),
                name: "Old display",
                visibleFrame: RectRecord(CGRect(x: 0, y: 0, width: 1920, height: 1080)),
                rotation: 0
            )
        ]

        XCTAssertTrue(topology.usesReplacementExternalDisplay(comparedTo: savedDisplays))
    }

    func testDoesNotTreatSameExternalDisplayAsReplacement() {
        let external = makeDisplay(
            id: 2,
            uuid: "external-same",
            role: .external,
            slotIndex: 0,
            isMain: false
        )
        let topology = DisplayTopology(displays: [external], signature: "test")
        let savedDisplays = [
            SavedDisplay(
                slot: DisplaySlot(role: .external, index: 0, exactUUID: "external-same"),
                name: "Same display",
                visibleFrame: RectRecord(CGRect(x: 0, y: 0, width: 1920, height: 1080)),
                rotation: 0
            )
        ]

        XCTAssertFalse(topology.usesReplacementExternalDisplay(comparedTo: savedDisplays))
    }

    func testAddsMenuBarSafeInsetWhenExternalVisibleFrameReportsFullFrame() {
        let result = DisplayFramePolicy.safeVisibleFrame(
            role: .external,
            frame: CGRect(x: 1440, y: -127, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 1440, y: -127, width: 1876, height: 1080),
            minimumTopInset: 30
        )

        XCTAssertEqual(result.minY, -97, accuracy: 0.001)
        XCTAssertEqual(result.height, 1050, accuracy: 0.001)
    }

    func testKeepsExistingExternalTopInset() {
        let visibleFrame = CGRect(x: 1440, y: -97, width: 1876, height: 1050)
        let result = DisplayFramePolicy.safeVisibleFrame(
            role: .external,
            frame: CGRect(x: 1440, y: -127, width: 1920, height: 1080),
            visibleFrame: visibleFrame,
            minimumTopInset: 30
        )

        XCTAssertEqual(result, visibleFrame)
    }

    func testAutomaticRestoreRetryPolicyCoversLateWindowAvailability() {
        let delays = AutomaticRestoreRetryPolicy.delaysInSeconds

        XCTAssertLessThanOrEqual(delays.first ?? .max, 5)
        XCTAssertGreaterThanOrEqual(delays.reduce(0, +), 120)
        XCTAssertTrue(zip(delays, delays.dropFirst()).allSatisfy { pair in
            pair.0 < pair.1
        })
    }

    func testRefreshesConstraintWhenFullHeightTargetRemainsTooShort() {
        XCTAssertTrue(
            FullHeightConstraintRefreshPolicy.shouldRefresh(
                actual: CGRect(x: 1440, y: -209, width: 937, height: 870),
                target: CGRect(x: 1440, y: -389, width: 937.5, height: 1050),
                displayFrame: CGRect(x: 1440, y: -389, width: 1875, height: 1050)
            )
        )
    }

    func testDoesNotZoomRefreshOrdinaryWindowHeight() {
        XCTAssertFalse(
            FullHeightConstraintRefreshPolicy.shouldRefresh(
                actual: CGRect(x: 1440, y: -120, width: 900, height: 650),
                target: CGRect(x: 1440, y: -150, width: 900, height: 700),
                displayFrame: CGRect(x: 1440, y: -389, width: 1875, height: 1050)
            )
        )
    }

    private func makeDisplay(
        id: CGDirectDisplayID,
        uuid: String,
        role: DisplayRole,
        slotIndex: Int,
        isMain: Bool
    ) -> DisplayDescriptor {
        let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        return DisplayDescriptor(
            runtimeID: id,
            uuid: uuid,
            name: uuid,
            role: role,
            slotIndex: slotIndex,
            isMain: isMain,
            vendorID: 0,
            modelID: 0,
            serialNumber: 0,
            rotation: 0,
            frame: frame,
            visibleFrame: frame,
            axFrame: frame,
            axVisibleFrame: frame
        )
    }
}
