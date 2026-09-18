import AppKit
import Foundation
import OSLog

enum DisplayRecallError: LocalizedError {
    case accessibilityPermissionRequired
    case externalDisplayRequired
    case noWindows
    case noSnapshot
    case incompatibleSnapshot

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionRequired:
            return "请先授予辅助功能权限"
        case .externalDisplayRequired:
            return "请先连接一台外接显示器"
        case .noWindows:
            return "没有找到可保存的普通窗口"
        case .noSnapshot:
            return "还没有保存过布局"
        case .incompatibleSnapshot:
            return "保存的布局版本不受支持"
        }
    }
}

struct RestoreReport: Equatable {
    var savedWindowCount: Int
    var matchedWindowCount: Int
    var restoredWindowCount: Int
    var failedWindowCount: Int
}

enum FullHeightConstraintRefreshPolicy {
    static func shouldRefresh(actual: CGRect, target: CGRect, displayFrame: CGRect) -> Bool {
        target.height >= displayFrame.height - 32 &&
            actual.height < target.height - 32
    }
}

@MainActor
final class RestoreEngine {
    private let accessibility: AccessibilityClient
    private let displays: DisplayInventory
    private let bundleIdentifier: String
    private let logger = Logger(subsystem: "com.zomeelee.DisplayRecall", category: "Restore")

    init(
        accessibility: AccessibilityClient,
        displays: DisplayInventory,
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.zomeelee.DisplayRecall"
    ) {
        self.accessibility = accessibility
        self.displays = displays
        self.bundleIdentifier = bundleIdentifier
    }

    func captureSnapshot() throws -> LayoutSnapshot {
        guard accessibility.isTrusted else {
            throw DisplayRecallError.accessibilityPermissionRequired
        }

        let topology = displays.capture()
        guard topology.hasExternalDisplay else {
            throw DisplayRecallError.externalDisplayRequired
        }

        let liveWindows = accessibility.enumerateWindows(excludingBundleIdentifier: bundleIdentifier)
        var savedWindows: [SavedWindow] = []

        for window in liveWindows {
            guard let display = topology.display(containing: window.frame) else {
                continue
            }
            savedWindows.append(
                SavedWindow(
                    id: UUID(),
                    appName: window.appName,
                    matchKey: window.matchKey,
                    displaySlot: display.slot,
                    normalizedFrame: LayoutMapper.normalize(window.frame, in: display.axVisibleFrame),
                    sourceFrame: RectRecord(window.frame)
                )
            )
        }

        guard !savedWindows.isEmpty else {
            throw DisplayRecallError.noWindows
        }

        let savedDisplays = topology.displays.map {
            SavedDisplay(
                slot: $0.slot,
                name: $0.name,
                visibleFrame: RectRecord($0.axVisibleFrame),
                rotation: $0.rotation
            )
        }

        return LayoutSnapshot(
            schemaVersion: LayoutSnapshot.currentSchemaVersion,
            savedAt: Date(),
            topologySignature: topology.signature,
            displays: savedDisplays,
            windows: savedWindows
        )
    }

    func restore(_ snapshot: LayoutSnapshot) async throws -> RestoreReport {
        guard accessibility.isTrusted else {
            throw DisplayRecallError.accessibilityPermissionRequired
        }
        guard snapshot.schemaVersion == LayoutSnapshot.currentSchemaVersion else {
            throw DisplayRecallError.incompatibleSnapshot
        }

        let topology = displays.capture()
        guard topology.hasExternalDisplay else {
            throw DisplayRecallError.externalDisplayRequired
        }

        let liveWindows = accessibility.enumerateWindows(excludingBundleIdentifier: bundleIdentifier)
        let pairs = WindowMatcher.match(
            saved: snapshot.windows,
            liveKeys: liveWindows.map(\.matchKey)
        )

        struct PendingVerification {
            var element: AXUIElement
            var target: CGRect
            var targetDisplayFrame: CGRect
            var bundleIdentifier: String
            var ordinal: Int
        }
        var pending: [PendingVerification] = []
        var failed = 0

        for pair in pairs {
            let savedWindow = snapshot.windows[pair.savedIndex]
            let liveWindow = liveWindows[pair.liveIndex]
            guard let targetDisplay = topology.targetDisplay(for: savedWindow.displaySlot) else {
                failed += 1
                continue
            }

            let targetFrame = LayoutMapper.map(
                savedWindow.normalizedFrame,
                to: targetDisplay.axVisibleFrame
            )
            if !accessibility.unzoomIfNeeded(liveWindow.element) {
                logger.notice(
                    "Unable to clear zoom state for \(savedWindow.matchKey.bundleIdentifier, privacy: .public) ordinal=\(savedWindow.matchKey.ordinal); continuing with direct frame restore"
                )
            }
            if accessibility.setFrame(targetFrame, for: liveWindow.element) {
                pending.append(
                    PendingVerification(
                        element: liveWindow.element,
                        target: targetFrame,
                        targetDisplayFrame: targetDisplay.axVisibleFrame,
                        bundleIdentifier: savedWindow.matchKey.bundleIdentifier,
                        ordinal: savedWindow.matchKey.ordinal
                    )
                )
            } else {
                logger.error(
                    "Initial frame write rejected by \(savedWindow.matchKey.bundleIdentifier, privacy: .public) ordinal=\(savedWindow.matchKey.ordinal)"
                )
                failed += 1
            }
        }

        try? await Task.sleep(nanoseconds: 250_000_000)

        var restored = 0
        for item in pending {
            if let actual = accessibility.frame(of: item.element), approximatelyEqual(actual, item.target) {
                restored += 1
                continue
            }

            // A size write made while WindowServer still associates the window with the
            // previous display is capped to that display's visible height. Move first,
            // wait for screen reassociation, then resize and pin the origin again.
            let movedToTargetDisplay = accessibility.setPosition(item.target.origin, for: item.element)
            if movedToTargetDisplay {
                try? await Task.sleep(nanoseconds: 350_000_000)
            }
            let resizedOnTargetDisplay = accessibility.setSize(item.target.size, for: item.element)
            let finalPositionSucceeded = accessibility.setPosition(item.target.origin, for: item.element)
            let retrySucceeded = movedToTargetDisplay && resizedOnTargetDisplay && finalPositionSucceeded
            if retrySucceeded {
                try? await Task.sleep(nanoseconds: 180_000_000)
            }

            if retrySucceeded,
               let actual = accessibility.frame(of: item.element),
               approximatelyEqual(actual, item.target, tolerance: 32) {
                restored += 1
                continue
            }

            if let actual = accessibility.frame(of: item.element),
               FullHeightConstraintRefreshPolicy.shouldRefresh(
                   actual: actual,
                   target: item.target,
                   displayFrame: item.targetDisplayFrame
               ),
               accessibility.refreshSizeConstraintByZooming(item.element) {
                logger.notice(
                    "Refreshing target-display size constraint for \(item.bundleIdentifier, privacy: .public) ordinal=\(item.ordinal)"
                )
                try? await Task.sleep(nanoseconds: 900_000_000)
                let resizedAfterZoom = accessibility.setSize(item.target.size, for: item.element)
                let positionedAfterZoom = accessibility.setPosition(item.target.origin, for: item.element)
                if resizedAfterZoom, positionedAfterZoom {
                    try? await Task.sleep(nanoseconds: 180_000_000)
                }

                if resizedAfterZoom,
                   positionedAfterZoom,
                   let refreshedFrame = accessibility.frame(of: item.element),
                   approximatelyEqual(refreshedFrame, item.target, tolerance: 32) {
                    restored += 1
                    continue
                }
            }

            let actualDescription = accessibility.frame(of: item.element)
                .map { String(describing: $0) } ?? "unavailable"
            logger.error(
                "Frame verification failed for \(item.bundleIdentifier, privacy: .public) ordinal=\(item.ordinal); target=\(String(describing: item.target), privacy: .public); actual=\(actualDescription, privacy: .public)"
            )
            failed += 1
        }

        return RestoreReport(
            savedWindowCount: snapshot.windows.count,
            matchedWindowCount: pairs.count,
            restoredWindowCount: restored,
            failedWindowCount: failed
        )
    }

    private func approximatelyEqual(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat = 5) -> Bool {
        abs(lhs.minX - rhs.minX) <= tolerance &&
            abs(lhs.minY - rhs.minY) <= tolerance &&
            abs(lhs.width - rhs.width) <= tolerance &&
            abs(lhs.height - rhs.height) <= tolerance
    }

}
