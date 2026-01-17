import SwiftUI
import Combine

class OverlayWindow: NSPanel {
    private var keyEventMonitor: Any?

    init(contentRect: NSRect, backing: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect,
           styleMask: [.borderless, .nonactivatingPanel],
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

        // Enable keyboard events for window movement
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleKeyboardMovement(event: event) == true {
                return nil // Consume the event
            }
            return event
        }
    }

    deinit {
        if let monitor = keyEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    override var canBecomeKey: Bool {
        return true
    }

    override var canBecomeMain: Bool {
        return true
    }

    override var acceptsFirstResponder: Bool {
        return true
    }

    /// Handles Command + Arrow key movement. Returns true if the event was handled.
    private func handleKeyboardMovement(event: NSEvent) -> Bool {
        // Only handle if window is visible and Command is held
        guard self.isVisible, event.modifierFlags.contains(.command) else {
            return false
        }

        let moveDistance: CGFloat = 20
        var newOrigin = self.frame.origin

        switch event.keyCode {
        case 123: // Left Arrow
            newOrigin.x -= moveDistance
        case 124: // Right Arrow
            newOrigin.x += moveDistance
        case 125: // Down Arrow
            newOrigin.y -= moveDistance
        case 126: // Up Arrow
            newOrigin.y += moveDistance
        default:
            return false
        }

        // Clamp to screen bounds
        if let screen = self.screen ?? NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowFrame = self.frame

            newOrigin.x = max(screenFrame.minX, min(newOrigin.x, screenFrame.maxX - windowFrame.width))
            newOrigin.y = max(screenFrame.minY, min(newOrigin.y, screenFrame.maxY - windowFrame.height))
        }

        // Move the window
        self.setFrameOrigin(newOrigin)

        print("Moved window to \(newOrigin)")

        return true
    }
}

class WindowCoordinator: ObservableObject {
    let appContext: AppContext
    let client: SocketClient
    let themeManager: ThemeManager
    let googleAuthManager: GoogleAuthManager
    let workflowManager: WorkflowManager
    
    static let shared = WindowCoordinator()

    private init() {
        self.appContext = AppContext.shared
        self.client = SocketClient.shared
        self.themeManager = ThemeManager.shared
        self.googleAuthManager = GoogleAuthManager.shared
        self.workflowManager = WorkflowManager.shared
    }

    // Track active controllers to keep them in memory
    private var controllers: [String: NSWindowController] = [:]
    
    func showMainOverlay() {
        if controllers["main"] == nil {
            let controller = MainWindowController()
            controllers["main"] = controller
        }
        controllers["main"]?.showWindow(nil)
        controllers["main"]?.window?.orderFrontRegardless()
    }

    func setMainWindowOpacity(opacity: Double) {
        if controllers["main"] == nil {
            let controller = MainWindowController()
            controllers["main"] = controller
        }
        controllers["main"]?.window?.alphaValue = CGFloat(opacity)
    }

    func minimizeMainOverlay() {
        if controllers["main"] == nil {
            let controller = MainWindowController()
            controllers["main"] = controller
        }
        // move the window to bottom center of the screen
        let screen = NSScreen.main?.frame ?? .zero
        let width: CGFloat = Constants.UI.windowWidth
        let height: CGFloat = Constants.UI.windowHeight
        let newOrigin = NSPoint(
            x: screen.midX - (width / 2),
            y: 100 // 100 points from bottom
        )
        controllers["main"]?.window?.setFrameOrigin(newOrigin)
        // disable window dragging when minimized
        controllers["main"]?.window?.isMovableByWindowBackground = false
        controllers["main"]?.showWindow(nil)
        controllers["main"]?.window?.orderFrontRegardless()
    }

    func expandMainOverlay() {
        if controllers["main"] == nil {
            let controller = MainWindowController()
            controllers["main"] = controller
        }
        // enable window dragging when expanded
        controllers["main"]?.window?.isMovableByWindowBackground = true
        controllers["main"]?.showWindow(nil)
        controllers["main"]?.window?.orderFrontRegardless()
    }

    func openPermissionWaitingOverlay(onRetry: @escaping () -> Void, onCancel: @escaping () -> Void) {
        print("Opening Permission Waiting Overlay")
        let id = "permission_waiting_overlay"
        if controllers[id] == nil {
            let contentView = PermissionWaitingView(onRetry: onRetry, onCancel: onCancel, windowID: id, size: CGSize(width: 320, height: 200))
            
            let controller = DynamicWindowController(
                id: id,
                view: AnyView(contentView),
                size: CGSize(width: 320, height: 200)
            )
            controllers[id] = controller
        }
        controllers[id]?.showWindow(nil)
    }

    func closePermissionWaitingOverlay() {
        let id = "permission_waiting_overlay"
        controllers[id]?.close()
        controllers[id] = nil // Release memory
    }
    
    func openDynamicWindow(id: String, view: AnyView, size: CGSize, location: CGPoint? = nil) {
        if controllers[id] == nil {
            let controller = DynamicWindowController(
                id: id,
                view: view,
                size: size,
                location: location
            )
            controllers[id] = controller
        }
        controllers[id]?.showWindow(nil)
    }

    func openWebWindow(url: URL, size: CGSize) {
        let id = "web_\(url.absoluteString)"
        print("Opening web window with ID: \(id)")
        if controllers[id] == nil {
            let body = WebWindowView(url: url, windowID: id, size: size)
            let anyView = AnyView(body)
            print("opening the webview through controller")
            let controller = DynamicWindowController(
                id: id,
                view: anyView,
                size: size
            )
            controllers[id] = controller
        }
        controllers[id]?.showWindow(nil)
    }

    func openGoogleService() {
        let id = "google_service_window"
        
        // 1. Check if already open (singleton behavior for Google Service)
        if let existing = controllers[id] {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }
        
        // 2. Configure View
        let contentView = GoogleServiceView(windowID: id)
        
        // 3. Configure Controller
        let controller = DynamicWindowController(
            id: id,
            view: AnyView(contentView),
            size: CGSize(width: 500, height: 400),
            location: nil
        )
        
        // 4. Store and Show
        controllers[id] = controller
        controller.showWindow(self)
        
        // 5. Cleanup Hook
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, 
            object: controller.window, 
            queue: .main
        ) { [weak self] _ in
            self?.controllers.removeValue(forKey: id)
        }
    }

    func openSettings() {
        let id = "settings_window"
        
        // 1. Check if already open (singleton behavior for settings)
        if let existing = controllers[id] {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }
        
        // 2. Configure View
        let contentView = SettingsView(windowID: id)
        
        // 3. Configure Controller
        let controller = DynamicWindowController(
            id: id,
            view: AnyView(contentView),
            size: CGSize(width: 500, height: 500),
            location: nil
        )
        
        // 4. Store and Show
        controllers[id] = controller
        controller.showWindow(nil)
        
        // 5. Cleanup Hook
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, 
            object: controller.window, 
            queue: .main
        ) { [weak self] _ in
            self?.controllers.removeValue(forKey: id)
        }
    }

    func openWorkflowSettings() {
        let id = "workflow_settings_window"
        
        // 1. Check if already open (singleton behavior for workflow settings)
        if let existing = controllers[id] {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }
        
        // 2. Configure View
        let contentView = WorkflowSettingsView(windowID: id)
        
        // 3. Configure Controller
        let controller = DynamicWindowController(
            id: id,
            view: AnyView(contentView),
            size: CGSize(width: 400, height: 500),
            location: nil
        )
        
        // 4. Store and Show
        controllers[id] = controller
        controller.showWindow(nil)
        
        // 5. Cleanup Hook
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, 
            object: controller.window, 
            queue: .main
        ) { [weak self] _ in
            self?.controllers.removeValue(forKey: id)
        }
    }
    
    func closeWindow(id: String) {
        controllers[id]?.close()
        controllers[id] = nil // Release memory
    }
}

class BaseOverlayController<RootView: View>: NSWindowController {
    init(rootView: RootView, rect: NSRect) {        
        // 1. Create the Window (Using your existing OverlayWindow class)
        let overlayWindow = OverlayWindow(
            contentRect: rect,
            backing: .buffered,
            defer: false
        )
        
        // 2. Setup Hosting
        let hostingController = NSHostingController(rootView: rootView)
        overlayWindow.contentViewController = hostingController
        
        super.init(window: overlayWindow)
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

// 1. Change the generic type from <ContentView> to <AnyView>
class MainWindowController: BaseOverlayController<AnyView> {
    
    init() {
        // 2. Create your view with all its modifiers and inject environment objects
        let coordinator = WindowCoordinator.shared
        let view = MainView()
            .environmentObject(coordinator.appContext)
            .environmentObject(coordinator.client)
            .environmentObject(coordinator.themeManager)
            .environmentObject(coordinator.googleAuthManager)
            .environmentObject(coordinator)
        
        let width: CGFloat = Constants.UI.windowWidth
        let height: CGFloat = Constants.UI.windowHeight
        let screen = NSScreen.main?.frame ?? .zero
        let frame = NSRect(
            x: screen.midX - (width/2),
            y: screen.maxY - height,
            width: width,
            height: height
        )
        
        // 3. Wrap the view in AnyView() when passing it to super
        super.init(rootView: AnyView(view), rect: frame)
        
        self.window?.isMovableByWindowBackground = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}


class CompactWindowController: BaseOverlayController<AnyView> {
    init() {
        // 2. Create your view with all its modifiers and inject environment objects
        let coordinator = WindowCoordinator.shared
        let view = ContentView()
            .environmentObject(coordinator.appContext)
            .environmentObject(coordinator.client)
            .environmentObject(coordinator.themeManager)
            .environmentObject(coordinator.googleAuthManager)
            .environmentObject(coordinator)
        
        let width: CGFloat = Constants.UI.overlayWindow.compactWidth
        let height: CGFloat = Constants.UI.overlayWindow.compactHeight
        let screen = NSScreen.main?.frame ?? .zero
        let frame = NSRect(
            x: screen.midX - (width/2),
            y: screen.maxY - height,
            width: width,
            height: height
        )
        
        // 3. Wrap the view in AnyView() when passing it to super
        super.init(rootView: AnyView(view), rect: frame)
        
        self.window?.isMovableByWindowBackground = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}


class DynamicWindowController: BaseOverlayController<AnyView> {
    let id: String
    
    // Added 'size' parameter so you aren't stuck with 300x200
    init(id: String, 
         view: AnyView, 
         size: CGSize,
         location: CGPoint? = nil
         ) { 
        
        self.id = id
        
        // 1. Inject Environment Objects from shared coordinator
        let coordinator = WindowCoordinator.shared
        let wiredView = view
            .environmentObject(coordinator.appContext)
            .environmentObject(coordinator.client)
            .environmentObject(coordinator.themeManager)
            .environmentObject(coordinator.googleAuthManager)
            .environmentObject(coordinator)
        
        // 2. Calculate Position (Center Screen)
        let screen = NSScreen.main?.frame ?? .zero
        let frame = NSRect(
            x: location?.x ?? (screen.midX - (size.width / 2)),
            y: location?.y ?? (screen.midY - (size.height / 2)),
            width: size.width,
            height: size.height
        )
        
        // 3. Pass the WIRED view (wrapped in AnyView again) to super
        super.init(rootView: AnyView(wiredView), rect: frame)
        
        // 4. Window Behavior
        self.window?.isMovableByWindowBackground = true
        self.window?.title = id // Optional: Set title for debugging (hidden by borderless mask usually)
    }
    
    @MainActor required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
