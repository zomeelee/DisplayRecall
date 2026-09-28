import AppKit

extension Notification.Name {
    static let displayRecallCommandURLReceived = Notification.Name(
        "com.zomeelee.DisplayRecall.commandURLReceived"
    )
}

final class DisplayRecallAppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            NotificationCenter.default.post(
                name: .displayRecallCommandURLReceived,
                object: url
            )
        }
    }
}
