import AppKit
import ColorSync
import CoreGraphics
import Foundation

struct DisplayDescriptor: Equatable {
    var runtimeID: CGDirectDisplayID
    var uuid: String?
    var name: String
    var role: DisplayRole
    var slotIndex: Int
    var isMain: Bool
    var vendorID: UInt32
    var modelID: UInt32
    var serialNumber: UInt32
    var rotation: Double
    var frame: CGRect
    var visibleFrame: CGRect
    var axFrame: CGRect
    var axVisibleFrame: CGRect

    var slot: DisplaySlot {
        DisplaySlot(role: role, index: slotIndex, exactUUID: uuid)
    }
}

struct DisplayTopology: Equatable {
    var displays: [DisplayDescriptor]
    var signature: String

    var hasExternalDisplay: Bool {
        displays.contains { $0.role == .external }
    }

    var summary: String {
        let builtInCount = displays.filter { $0.role == .builtIn }.count
        let externalCount = displays.filter { $0.role == .external }.count
        if externalCount == 0 {
            return builtInCount > 0 ? "仅 Mac 屏幕" : "未检测到可用显示器"
        }
        return "\(builtInCount) 个内置屏，\(externalCount) 个外接屏"
    }

    func usesReplacementExternalDisplay(comparedTo savedDisplays: [SavedDisplay]) -> Bool {
        let savedUUIDs = Set(
            savedDisplays.compactMap { display in
                display.slot.role == .external ? display.slot.exactUUID : nil
            }
        )
        let currentUUIDs = Set(
            displays.compactMap { display in
                display.role == .external ? display.uuid : nil
            }
        )

        guard !savedUUIDs.isEmpty, !currentUUIDs.isEmpty else {
            return false
        }
        return savedUUIDs.isDisjoint(with: currentUUIDs)
    }

    func targetDisplay(for slot: DisplaySlot) -> DisplayDescriptor? {
        if let exactUUID = slot.exactUUID,
           let exact = displays.first(where: { $0.uuid == exactUUID && $0.role == slot.role }) {
            return exact
        }

        if let sameSlot = displays.first(where: {
            $0.role == slot.role && $0.slotIndex == slot.index
        }) {
            return sameSlot
        }

        if let sameRole = displays.first(where: { $0.role == slot.role }) {
            return sameRole
        }

        return displays.first(where: { $0.isMain }) ?? displays.first
    }

    func display(containing windowFrame: CGRect) -> DisplayDescriptor? {
        let best = displays
            .map { descriptor -> (DisplayDescriptor, CGFloat) in
                let intersection = descriptor.axFrame.intersection(windowFrame)
                let area = intersection.isNull ? 0 : intersection.width * intersection.height
                return (descriptor, area)
            }
            .max { $0.1 < $1.1 }

        if let best, best.1 > 0 {
            return best.0
        }

        let center = CGPoint(x: windowFrame.midX, y: windowFrame.midY)
        return displays.min { lhs, rhs in
            distanceSquared(from: center, to: lhs.axFrame) < distanceSquared(from: center, to: rhs.axFrame)
        }
    }

    private func distanceSquared(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let nearestX = min(max(point.x, rect.minX), rect.maxX)
        let nearestY = min(max(point.y, rect.minY), rect.maxY)
        let dx = point.x - nearestX
        let dy = point.y - nearestY
        return dx * dx + dy * dy
    }
}

enum DisplayFramePolicy {
    static func safeVisibleFrame(
        role: DisplayRole,
        frame: CGRect,
        visibleFrame: CGRect,
        minimumTopInset: CGFloat
    ) -> CGRect {
        guard role == .external, minimumTopInset > 0 else {
            return visibleFrame
        }

        let safeTop = frame.minY + minimumTopInset
        guard visibleFrame.minY < safeTop else {
            return visibleFrame
        }

        let adjustment = safeTop - visibleFrame.minY
        return CGRect(
            x: visibleFrame.minX,
            y: safeTop,
            width: visibleFrame.width,
            height: max(0, visibleFrame.height - adjustment)
        )
    }
}

final class DisplayInventory {
    func capture() -> DisplayTopology {
        let screens = NSScreen.screens
        let mainScreenTop = screens.first?.frame.maxY ?? 0
        let minimumTopInset = screens.first.map {
            max(0, $0.frame.maxY - $0.visibleFrame.maxY)
        } ?? 0

        var draft = screens.compactMap { screen -> DisplayDescriptor? in
            let key = NSDeviceDescriptionKey("NSScreenNumber")
            guard let number = screen.deviceDescription[key] as? NSNumber else {
                return nil
            }

            let displayID = CGDirectDisplayID(number.uint32Value)
            let role: DisplayRole = CGDisplayIsBuiltin(displayID) != 0 ? .builtIn : .external
            let uuid = displayUUID(for: displayID)
            let frame = screen.frame
            let visibleFrame = screen.visibleFrame
            let axFrame = convertToAX(frame, mainScreenTop: mainScreenTop)
            let reportedAXVisibleFrame = convertToAX(
                visibleFrame,
                mainScreenTop: mainScreenTop
            )
            let axVisibleFrame = DisplayFramePolicy.safeVisibleFrame(
                role: role,
                frame: axFrame,
                visibleFrame: reportedAXVisibleFrame,
                minimumTopInset: minimumTopInset
            )

            return DisplayDescriptor(
                runtimeID: displayID,
                uuid: uuid,
                name: screen.localizedName,
                role: role,
                slotIndex: 0,
                isMain: CGDisplayIsMain(displayID) != 0,
                vendorID: CGDisplayVendorNumber(displayID),
                modelID: CGDisplayModelNumber(displayID),
                serialNumber: CGDisplaySerialNumber(displayID),
                rotation: CGDisplayRotation(displayID),
                frame: frame,
                visibleFrame: visibleFrame,
                axFrame: axFrame,
                axVisibleFrame: axVisibleFrame
            )
        }

        draft.sort {
            if $0.role != $1.role {
                return $0.role == .builtIn
            }
            if $0.frame.minX != $1.frame.minX {
                return $0.frame.minX < $1.frame.minX
            }
            return $0.frame.minY > $1.frame.minY
        }

        var roleCounts: [DisplayRole: Int] = [:]
        for index in draft.indices {
            let role = draft[index].role
            draft[index].slotIndex = roleCounts[role, default: 0]
            roleCounts[role, default: 0] += 1
        }

        let signature = draft.map {
            let frame = $0.frame
            return [
                String($0.runtimeID),
                $0.uuid ?? "none",
                $0.role.rawValue,
                String(format: "%.0f,%.0f,%.0f,%.0f", frame.minX, frame.minY, frame.width, frame.height),
                String(format: "%.0f", $0.rotation)
            ].joined(separator: ":")
        }.joined(separator: "|")

        return DisplayTopology(displays: draft, signature: signature)
    }

    private func displayUUID(for displayID: CGDirectDisplayID) -> String? {
        guard let unmanaged = CGDisplayCreateUUIDFromDisplayID(displayID) else {
            return nil
        }
        let uuid = unmanaged.takeRetainedValue()
        return CFUUIDCreateString(nil, uuid) as String
    }

    private func convertToAX(_ rect: CGRect, mainScreenTop: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX,
            y: mainScreenTop - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}
