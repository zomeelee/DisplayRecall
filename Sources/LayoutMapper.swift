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

    static func map(_ normalized: NormalizedFrame, to visibleFrame: CGRect) -> CGRect {
        let requested = CGRect(
            x: visibleFrame.minX + normalized.x * visibleFrame.width,
            y: visibleFrame.minY + normalized.y * visibleFrame.height,
            width: normalized.width * visibleFrame.width,
            height: normalized.height * visibleFrame.height
        )
        return clamp(requested, to: visibleFrame)
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
