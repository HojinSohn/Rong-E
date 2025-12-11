import SwiftUI
import AppKit

class OverlayWindow: NSPanel {
    init(contentRect: NSRect, backing: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: [.nonactivatingPanel], backing: backing, defer: flag)
        
        // 1. Allow this window to sit over full-screen apps
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        // 2. Set the highest practical level (ScreenSaver is usually too aggressive, Floating is standard)
        self.level = .floating 
        
        // 3. Visual transparency settings
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        
        self.isFloatingPanel = true
    }

    override var canBecomeKey: Bool {
        return true
    }
    
    override var canBecomeMain: Bool {
        return true
    }
}

class WindowManager: NSObject, ObservableObject {
    var window: OverlayWindow?

    func showOverlay() {
        if window == nil {
            // Create the hosting controller with your SwiftUI View
            let contentView = ContentView() // Your view here
            let hostingController = NSHostingController(rootView: contentView)
            
            // Calculate screen size
            let screenRect = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
            let width: CGFloat = 600
            let height: CGFloat = 160
            let xPos = screenRect.midX - (width / 2)
            let yPos = screenRect.maxY - height // Stick to top
            
            let frame = NSRect(x: xPos, y: yPos, width: width, height: height)
            
            // Initialize the custom NSPanel
            window = OverlayWindow(contentRect: frame, backing: .buffered, defer: false)
            window?.contentViewController = hostingController
            
            // Show it without activating the app (keeps focus on your other work)
            window?.orderFrontRegardless()
        }
    }
}