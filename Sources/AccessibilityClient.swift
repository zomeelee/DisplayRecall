import AppKit
import ApplicationServices
import CryptoKit
import Foundation
import OSLog

struct LiveWindow {
    var element: AXUIElement
    var pid: pid_t
    var appName: String
    var matchKey: WindowMatchKey
    var frame: CGRect
}

final class AccessibilityClient {
    private struct RuntimeWindowIdentity {
        var id: CGWindowID
        var frame: CGRect
    }

    private let logger = Logger(subsystem: "com.zomeelee.DisplayRecall", category: "Accessibility")

    var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    func requestTrustPrompt() -> Bool {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func enumerateWindows(excludingBundleIdentifier excludedBundleID: String?) -> [LiveWindow] {
        guard isTrusted else {
            return []
        }

        var result: [LiveWindow] = []
        let runtimeWindowsByPID = captureRuntimeWindowIdentities()
        var claimedRuntimeWindowIDs = Set<CGWindowID>()
        let applications = NSWorkspace.shared.runningApplications
            .filter { !$0.isTerminated && !$0.isHidden && $0.activationPolicy == .regular }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }

        logger.debug("Scanning \(applications.count) visible regular applications")

        for application in applications {
            guard let bundleIdentifier = application.bundleIdentifier,
                  bundleIdentifier != excludedBundleID else {
                continue
            }

            let appElement = AXUIElementCreateApplication(application.processIdentifier)
            AXUIElementSetMessagingTimeout(appElement, 0.8)
            var rawWindows: CFTypeRef?
            let windowsResult = AXUIElementCopyAttributeValue(
                appElement,
                kAXWindowsAttribute as CFString,
                &rawWindows
            )
            guard windowsResult == .success,
                  let windows = rawWindows as? [AXUIElement] else {
                logger.debug(
                    "Window query failed for \(bundleIdentifier, privacy: .public), error=\(windowsResult.rawValue)"
                )
                continue
            }

            var ordinal = 0
            for window in windows {
                guard var liveWindow = makeLiveWindow(
                    window,
                    application: application,
                    bundleIdentifier: bundleIdentifier,
                    ordinal: ordinal
                ) else {
                    continue
                }
                if let identity = matchingRuntimeIdentity(
                    for: liveWindow.frame,
                    candidates: runtimeWindowsByPID[application.processIdentifier] ?? [],
                    excluding: claimedRuntimeWindowIDs
                ) {
                    liveWindow.matchKey.runtimeOwnerPID = application.processIdentifier
                    liveWindow.matchKey.runtimeWindowID = identity.id
                    claimedRuntimeWindowIDs.insert(identity.id)
                    logger.debug(
                        "Mapped \(bundleIdentifier, privacy: .public) ordinal=\(ordinal) to CGWindowID=\(identity.id)"
                    )
                }
                result.append(liveWindow)
                ordinal += 1
            }
        }
        logger.debug("Window scan produced \(result.count) restorable windows")
        return result
    }

    private func captureRuntimeWindowIdentities() -> [pid_t: [RuntimeWindowIdentity]] {
        let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        guard let rawWindows = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
            as? [[String: Any]] else {
            return [:]
        }

        var result: [pid_t: [RuntimeWindowIdentity]] = [:]
        for rawWindow in rawWindows {
            guard let ownerPID = rawWindow[kCGWindowOwnerPID as String] as? Int,
                  let windowNumber = rawWindow[kCGWindowNumber as String] as? Int,
                  let layer = rawWindow[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let rawBounds = rawWindow[kCGWindowBounds as String],
                  let bounds = CGRect(
                      dictionaryRepresentation: rawBounds as! CFDictionary
                  ),
                  bounds.width >= 80,
                  bounds.height >= 60 else {
                continue
            }

            let pid = pid_t(ownerPID)
            result[pid, default: []].append(
                RuntimeWindowIdentity(id: CGWindowID(windowNumber), frame: bounds)
            )
        }
        return result
    }

    private func matchingRuntimeIdentity(
        for frame: CGRect,
        candidates: [RuntimeWindowIdentity],
        excluding claimedIDs: Set<CGWindowID>
    ) -> RuntimeWindowIdentity? {
        var bestIdentity: RuntimeWindowIdentity?
        var bestDistance = CGFloat.greatestFiniteMagnitude

        for identity in candidates where !claimedIDs.contains(identity.id) {
            let xDistance = abs(identity.frame.minX - frame.minX)
            let yDistance = abs(identity.frame.minY - frame.minY)
            let widthDistance = abs(identity.frame.width - frame.width)
            let heightDistance = abs(identity.frame.height - frame.height)
            let distance = xDistance + yDistance + widthDistance + heightDistance
            guard distance <= 8 else { continue }

            if distance < bestDistance ||
                (distance == bestDistance && identity.id < (bestIdentity?.id ?? .max)) {
                bestIdentity = identity
                bestDistance = distance
            }
        }
        return bestIdentity
    }

    func frame(of element: AXUIElement) -> CGRect? {
        guard let position = pointAttribute(element, kAXPositionAttribute as CFString),
              let size = sizeAttribute(element, kAXSizeAttribute as CFString) else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    @discardableResult
    func unzoomIfNeeded(_ element: AXUIElement) -> Bool {
        let attribute = "AXZoomed" as CFString
        guard copyBooleanAttribute(element, attribute) == true else {
            return true
        }
        guard isSettable(element, attribute) else {
            return false
        }
        return AXUIElementSetAttributeValue(element, attribute, kCFBooleanFalse) == .success
    }

    @discardableResult
    func setFrame(_ frame: CGRect, for element: AXUIElement, alternateOrder: Bool = false) -> Bool {
        let canSetPosition = isSettable(element, kAXPositionAttribute as CFString)
        let canSetSize = isSettable(element, kAXSizeAttribute as CFString)
        guard canSetPosition, canSetSize else {
            return false
        }

        if !alternateOrder,
           let atomicResult = setRectIfSupported(frame, element: element) {
            logger.debug("Atomic AXFrame write result: \(atomicResult)")
            if atomicResult {
                return true
            }
        }

        if alternateOrder {
            let positionResult = setPosition(frame.origin, for: element)
            let sizeResult = setSize(frame.size, for: element)
            let finalPositionResult = setPosition(frame.origin, for: element)
            return positionResult && sizeResult && finalPositionResult
        }

        let sizeResult = setSize(frame.size, for: element)
        let positionResult = setPosition(frame.origin, for: element)
        return sizeResult && positionResult
    }

    @discardableResult
    func setPosition(_ point: CGPoint, for element: AXUIElement) -> Bool {
        let attribute = kAXPositionAttribute as CFString
        guard isSettable(element, attribute) else {
            return false
        }
        return setPoint(point, element: element, attribute: attribute)
    }

    @discardableResult
    func setSize(_ size: CGSize, for element: AXUIElement) -> Bool {
        let attribute = kAXSizeAttribute as CFString
        guard isSettable(element, attribute) else {
            return false
        }
        return setSizeValue(size, element: element, attribute: attribute)
    }

    @discardableResult
    func refreshSizeConstraintByZooming(_ element: AXUIElement) -> Bool {
        var rawButton: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            "AXZoomButton" as CFString,
            &rawButton
        ) == .success,
        let rawButton,
        CFGetTypeID(rawButton) == AXUIElementGetTypeID() else {
            return false
        }

        let zoomButton = unsafeBitCast(rawButton, to: AXUIElement.self)
        var rawActions: CFArray?
        guard AXUIElementCopyActionNames(zoomButton, &rawActions) == .success,
              let actions = rawActions as? [String],
              actions.contains("AXZoomWindow") else {
            return false
        }

        // Chromium currently performs this advertised action but may still report
        // kAXErrorActionUnsupported, so availability is the reliable signal here.
        let result = AXUIElementPerformAction(zoomButton, "AXZoomWindow" as CFString)
        logger.debug("AXZoomWindow refresh result: \(result.rawValue)")
        return true
    }

    private func makeLiveWindow(
        _ window: AXUIElement,
        application: NSRunningApplication,
        bundleIdentifier: String,
        ordinal: Int
    ) -> LiveWindow? {
        let role: String = copyAttribute(window, kAXRoleAttribute as CFString) ?? ""
        guard role == (kAXWindowRole as String) else {
            return nil
        }

        let subrole: String? = copyAttribute(window, kAXSubroleAttribute as CFString)
        if let subrole, subrole != (kAXStandardWindowSubrole as String) {
            return nil
        }

        let minimized: Bool = copyBooleanAttribute(window, kAXMinimizedAttribute as CFString) ?? false
        let fullScreen: Bool = copyBooleanAttribute(window, "AXFullScreen" as CFString) ?? false
        if fullScreen {
            logger.debug(
                "Skipping full-screen window for \(bundleIdentifier, privacy: .public) ordinal=\(ordinal)"
            )
        }
        guard !minimized, !fullScreen, let frame = frame(of: window) else {
            return nil
        }
        guard frame.width >= 80, frame.height >= 60,
              frame.origin.x.isFinite, frame.origin.y.isFinite,
              frame.width.isFinite, frame.height.isFinite else {
            return nil
        }

        let identifier: String? = copyAttribute(window, "AXIdentifier" as CFString)
        let title: String? = copyAttribute(window, kAXTitleAttribute as CFString)
        let document: String? = copyAttribute(window, kAXDocumentAttribute as CFString)

        let matchKey = WindowMatchKey(
            bundleIdentifier: bundleIdentifier,
            identifier: identifier,
            titleHash: PrivacyHasher.digest(title),
            documentHash: PrivacyHasher.digest(document),
            role: role,
            subrole: subrole,
            ordinal: ordinal
        )

        return LiveWindow(
            element: window,
            pid: application.processIdentifier,
            appName: application.localizedName ?? bundleIdentifier,
            matchKey: matchKey,
            frame: frame
        )
    }

    private func isSettable(_ element: AXUIElement, _ attribute: CFString) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, attribute, &settable) == .success && settable.boolValue
    }

    private func copyAttribute<T>(_ element: AXUIElement, _ attribute: CFString) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value as? T
    }

    private func copyBooleanAttribute(_ element: AXUIElement, _ attribute: CFString) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let number = value as? NSNumber else {
            return nil
        }
        return number.boolValue
    }

    private func pointAttribute(_ element: AXUIElement, _ attribute: CFString) -> CGPoint? {
        var rawValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &rawValue) == .success,
              let rawValue,
              CFGetTypeID(rawValue) == AXValueGetTypeID() else {
            return nil
        }
        let value = unsafeBitCast(rawValue, to: AXValue.self)
        var point = CGPoint.zero
        guard AXValueGetValue(value, .cgPoint, &point) else {
            return nil
        }
        return point
    }

    private func sizeAttribute(_ element: AXUIElement, _ attribute: CFString) -> CGSize? {
        var rawValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &rawValue) == .success,
              let rawValue,
              CFGetTypeID(rawValue) == AXValueGetTypeID() else {
            return nil
        }
        let value = unsafeBitCast(rawValue, to: AXValue.self)
        var size = CGSize.zero
        guard AXValueGetValue(value, .cgSize, &size) else {
            return nil
        }
        return size
    }

    private func setPoint(_ point: CGPoint, element: AXUIElement, attribute: CFString) -> Bool {
        var mutablePoint = point
        guard let value = AXValueCreate(.cgPoint, &mutablePoint) else {
            return false
        }
        return AXUIElementSetAttributeValue(element, attribute, value) == .success
    }

    private func setSizeValue(_ size: CGSize, element: AXUIElement, attribute: CFString) -> Bool {
        var mutableSize = size
        guard let value = AXValueCreate(.cgSize, &mutableSize) else {
            return false
        }
        return AXUIElementSetAttributeValue(element, attribute, value) == .success
    }

    private func setRectIfSupported(_ rect: CGRect, element: AXUIElement) -> Bool? {
        let attribute = "AXFrame" as CFString
        guard isSettable(element, attribute) else {
            return nil
        }

        var mutableRect = rect
        guard let value = AXValueCreate(.cgRect, &mutableRect) else {
            return false
        }
        return AXUIElementSetAttributeValue(element, attribute, value) == .success
    }
}

enum PrivacyHasher {
    static func digest(_ value: String?) -> String? {
        guard let value, !value.isEmpty else {
            return nil
        }
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
