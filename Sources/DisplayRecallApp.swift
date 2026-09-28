import SwiftUI

@main
struct DisplayRecallApp: App {
    @NSApplicationDelegateAdaptor(DisplayRecallAppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(model)
        } label: {
            Image(systemName: menuBarIcon)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }

    private var menuBarIcon: String {
        switch model.phase {
        case .settling:
            return "display.and.arrow.down"
        case .saving:
            return "square.and.arrow.down"
        case .restoring:
            return "rectangle.2.swap"
        case .cooldown:
            return "checkmark.rectangle.stack"
        case .idle:
            return model.hasExternalDisplay ? "rectangle.on.rectangle.angled" : "rectangle"
        }
    }
}
