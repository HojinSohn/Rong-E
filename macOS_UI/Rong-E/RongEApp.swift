import SwiftUI
import AppKit
@main
struct RongEApp: App {
    // Keep a reference to the manager
    @StateObject var windowManager = WindowManager()
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
    
    init() {
        DispatchQueue.main.async {
            WindowManager().showOverlay()
        }
    }
}
