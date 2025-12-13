import SwiftUI
import AppKit

class OverlayWindow: NSPanel {
    init(contentRect: NSRect, backing: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, 
           styleMask: [.borderless, .nonactivatingPanel], // Add .borderless
           backing: backing, 
           defer: flag)
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
    var textWindow: OverlayWindow?

    var context = AppContext()
    var themeManager = ThemeManager() // Initialize ThemeManager

    func showOverlay() {
        if window == nil {
            // Create the hosting controller with your SwiftUI View
            // Inject ThemeManager
            let contentView = ContentView()
                .environmentObject(context)
                .environmentObject(themeManager)
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

        if textWindow == nil {
            // If textWindow is nil, create and show it
            let textView = TextView()
                            .environmentObject(context)
                            .environmentObject(themeManager)
            let textHostingController = NSHostingController(rootView: textView)

            let screenRect = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
            let width: CGFloat = 400
            let height: CGFloat = 400
            // put it on left side of screen
            
            let xPos = screenRect.minX + 40
            let yPos = screenRect.maxY - height // Stick to top
            let textFrame = NSRect(x: xPos, y: yPos, width: width, height: height)
            textWindow = OverlayWindow(contentRect: textFrame, backing: .buffered, defer: false)
            textWindow?.contentViewController = textHostingController
            textWindow?.orderFrontRegardless()
            // print
            print("Text window created and shown.")
        }
    }
}
