import Foundation

enum LayoutMapper {
    static func normalize(_ windowFrame: CGRect, in visibleFrame: CGRect) -> NormalizedFrame {
        guard visibleFrame.width > 0, visibleFrame.height > 0 else {
            return NormalizedFrame(x: 0, y: 0, width: 1, height: 1)
        }

        return NormalizedFrame(
            x: (windowFrame.minX - visibleFrame.minX) / visibleFrame.width,
            y: (windowFrame.minY - visibleFrame.minY) / visibleFrame.height,
            width: windowFrame.width / visibleFrame.width,
            height: windowFrame.height / visibleFrame.height
        )
    }

    static func map(
        _ normalized: NormalizedFrame,
        from sourceVisibleFrame: CGRect? = nil,
        to visibleFrame: CGRect
    ) -> CGRect {
        let mapped = orientationAdjusted(
            normalized,
            from: sourceVisibleFrame,
            to: visibleFrame
        )
        let requested = CGRect(
            x: visibleFrame.minX + mapped.x * visibleFrame.width,
            y: visibleFrame.minY + mapped.y * visibleFrame.height,
            width: mapped.width * visibleFrame.width,
            height: mapped.height * visibleFrame.height
        )
        return clamp(requested, to: visibleFrame)
    }

    private static func orientationAdjusted(
        _ normalized: NormalizedFrame,
        from sourceVisibleFrame: CGRect?,
        to targetVisibleFrame: CGRect
    ) -> NormalizedFrame {
        guard requiresAxisSwap(
            from: sourceVisibleFrame,
            to: targetVisibleFrame
        ) else {
            return normalized
        }

        // Swap the layout axes when moving between landscape and portrait.
        // This maps landscape left/right regions to portrait top/bottom regions,
        // and performs the inverse mapping when returning to landscape.
        return NormalizedFrame(
            x: normalized.y,
            y: normalized.x,
            width: normalized.height,
            height: normalized.width
        )
    }

    static func requiresAxisSwap(
        from sourceVisibleFrame: CGRect?,
        to targetVisibleFrame: CGRect
    ) -> Bool {
        guard let sourceVisibleFrame,
              let sourceOrientation = orientation(of: sourceVisibleFrame),
              let targetOrientation = orientation(of: targetVisibleFrame) else {
            return false
        }
        return sourceOrientation != targetOrientation
    }

    private static func orientation(of frame: CGRect) -> DisplayAxisOrientation? {
        guard frame.width > 0,
              frame.height > 0,
              abs(frame.width - frame.height) > 1 else {
            return nil
        }
        return frame.width > frame.height ? .landscape : .portrait
    }

    static func clamp(_ frame: CGRect, to visibleFrame: CGRect) -> CGRect {
        guard visibleFrame.width > 0, visibleFrame.height > 0 else {
            return frame
        }

        let width = min(max(frame.width, 160), visibleFrame.width)
        let height = min(max(frame.height, 100), visibleFrame.height)
        let x = min(max(frame.minX, visibleFrame.minX), visibleFrame.maxX - width)
        let y = min(max(frame.minY, visibleFrame.minY), visibleFrame.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

private enum DisplayAxisOrientation {
    case landscape
    case portrait
}
