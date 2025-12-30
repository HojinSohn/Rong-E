import SwiftUI
import Combine

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

class WindowCoordinator: ObservableObject {
    // Shared State
    let appContext = AppContext()
    let themeManager = ThemeManager()
    
    // Track active controllers to keep them in memory
    private var controllers: [String: NSWindowController] = [:]
    
    func showMainOverlay() {
        if controllers["main"] == nil {
            let controller = MainWindowController(
                coordinator: self,
                context: appContext,
                theme: themeManager
            )
            controllers["main"] = controller
        }
        controllers["main"]?.showWindow(nil)
        controllers["main"]?.window?.orderFrontRegardless()
    }
    
    func openDynamicWindow(id: String, view: AnyView, size: CGSize, location: CGPoint? = nil) {
        if controllers[id] == nil {
            let controller = DynamicWindowController(
                id: id,
                coordinator: self,
                view: view,
                context: appContext,
                theme: themeManager,
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
            var body = WebWindowView(url: url, windowID: id, size: size)
                .environmentObject(self)
                .environmentObject(appContext)
                .environmentObject(themeManager)
            let anyView = AnyView(body)
            print("opening the webview through controller")
            let controller = DynamicWindowController(
                id: id,
                coordinator: self,
                view: anyView,
                context: appContext,
                theme: themeManager,
                size: size
            )
            controllers[id] = controller
        }
        controllers[id]?.showWindow(nil)
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
            coordinator: self,
            view: AnyView(contentView),
            context: appContext,
            theme: themeManager,
            size: CGSize(width: 450, height: 350)
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
    var coordinator: WindowCoordinator
    
    init(coordinator: WindowCoordinator, rootView: RootView, rect: NSRect) {
        self.coordinator = coordinator
        
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
    
    init(coordinator: WindowCoordinator, context: AppContext, theme: ThemeManager) {
        
        // 2. Create your view with all its modifiers
        let view = ContentView()
            .environmentObject(context)
            .environmentObject(theme)
            .environmentObject(coordinator)
        
        // ... (Your frame calculation logic) ...
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
        super.init(coordinator: coordinator, rootView: AnyView(view), rect: frame)
        
        self.window?.isMovableByWindowBackground = false
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}


class DynamicWindowController: BaseOverlayController<AnyView> {
    let id: String
    
    // Added 'size' parameter so you aren't stuck with 300x200
    init(id: String, 
         coordinator: WindowCoordinator, 
         view: AnyView, 
         context: AppContext, 
         theme: ThemeManager,
         size: CGSize,
         location: CGPoint? = nil
         ) { 
        
        self.id = id
        
        // 1. Inject Environment Objects
        // Even though 'view' is AnyView, we can still apply modifiers.
        // This ensures the dynamic window has access to shared state.
        let wiredView = view
            .environmentObject(coordinator)
            .environmentObject(context)
            .environmentObject(theme)
        
        // 2. Calculate Position (Center Screen)
        let screen = NSScreen.main?.frame ?? .zero
        let frame = NSRect(
            x: location?.x ?? (screen.midX - (size.width / 2)),
            y: location?.y ?? (screen.midY - (size.height / 2)),
            width: size.width,
            height: size.height
        )
        
        // 3. Pass the WIRED view (wrapped in AnyView again) to super
        super.init(coordinator: coordinator, rootView: AnyView(wiredView), rect: frame)
        
        // 4. Window Behavior
        self.window?.isMovableByWindowBackground = true
        self.window?.title = id // Optional: Set title for debugging (hidden by borderless mask usually)
    }
    
    @MainActor required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
