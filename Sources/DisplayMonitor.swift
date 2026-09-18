import AppKit
import CoreGraphics
import Foundation

private let displayReconfigurationCallback: CGDisplayReconfigurationCallBack = { _, flags, userInfo in
    guard !flags.contains(.beginConfigurationFlag), let userInfo else {
        return
    }
    let monitor = Unmanaged<DisplayMonitor>.fromOpaque(userInfo).takeUnretainedValue()
    monitor.deliverChange()
}

final class DisplayMonitor {
    var onConfigurationChanged: (() -> Void)?

    private var started = false
    private var notificationToken: NSObjectProtocol?

    func start() {
        guard !started else {
            return
        }
        started = true
        let context = Unmanaged.passUnretained(self).toOpaque()
        CGDisplayRegisterReconfigurationCallback(displayReconfigurationCallback, context)
        notificationToken = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onConfigurationChanged?()
        }
    }

    func stop() {
        guard started else {
            return
        }
        started = false
        let context = Unmanaged.passUnretained(self).toOpaque()
        CGDisplayRemoveReconfigurationCallback(displayReconfigurationCallback, context)
        if let notificationToken {
            NotificationCenter.default.removeObserver(notificationToken)
        }
        notificationToken = nil
    }

    fileprivate func deliverChange() {
        DispatchQueue.main.async { [weak self] in
            self?.onConfigurationChanged?()
        }
    }

    deinit {
        stop()
    }
}
