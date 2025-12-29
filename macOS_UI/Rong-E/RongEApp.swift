import SwiftUI
import AppKit
import Combine

// 1. Create a Delegate to own the Coordinator and handle lifecycle
class AppDelegate: NSObject, NSApplicationDelegate {
    // The Delegate "owns" the coordinator, keeping it alive
    var coordinator = WindowCoordinator()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 2. Safe to show window now that AppKit is ready
        coordinator.showMainOverlay()
    }
}

@main
struct RongEApp: App {
    // 3. Connect the Delegate to the SwiftUI App
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // We use Settings to allow a standard Preferences window if needed,
        // but since you manage windows manually, we can leave this empty or minimal.
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
