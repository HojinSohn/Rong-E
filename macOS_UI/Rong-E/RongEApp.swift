import SwiftUI
import AppKit
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {
    // The Delegate references the shared coordinator
    var coordinator = WindowCoordinator.shared
    let pythonManager = PythonProcessManager.shared
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. Start the Rong-E agent server
        print("🚀 Starting Rong-E agent server...")
        pythonManager.startServer()

        // 2. Safe to show window now that AppKit is ready
        coordinator.showMainOverlay()

        // 3. Connect WebSocket after server has time to start (with retry)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            print("🔌 Auto-connecting WebSocket...")
            self.coordinator.client.connect()
        }

        // 4. Auto-sync MCP config when WebSocket first connects
        coordinator.client.$isConnected
            .removeDuplicates()
            .filter { $0 == true }
            .first()
            .sink { _ in
                print("🔧 Auto-syncing MCP config on connection...")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    MCPConfigManager.shared.sendConfigToPython()
                }
            }
            .store(in: &cancellables)

        // 5. Run startup workflow after MCP servers are synced
        coordinator.client.onMCPSyncResult = { [weak self] success, message in
            print("🔧 MCP Sync Result: success=\(success), message=\(message ?? "nil")")
            self?.runStartupWorkflowIfNeeded()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Stop the server when app quits
        print("🛑 Stopping Rong-E agent server...")
        pythonManager.stopServer()
    }
    
    private func runStartupWorkflowIfNeeded() {
        let appContext = AppContext.shared

        // For testing purposes, reset the startup workflow status
        appContext.startUpWorkFinished = false
        
        // Check if startup workflow has already run
        if appContext.startUpWorkFinished {
            print("✅ Startup workflow already completed")
            return
        }
        
        // Run the startup workflow
        runStartupWorkflow()
    }
    
    private func runStartupWorkflow() {
        let appContext = AppContext.shared
        let coordinator = WindowCoordinator.shared
        
        print("🚀 Running startup workflow...")
        
        // Get enabled startup tasks
        let workflowManager = WorkflowManager.shared
        let enabledTasks = workflowManager.tasks.filter { $0.isEnabled }
        
        guard !enabledTasks.isEmpty else {
            print("ℹ️ No startup tasks enabled")
            appContext.markStartupWorkflowCompleted()
            return
        }
        
        // Combine all tasks into one mega prompt
        let taskPrompts = enabledTasks.map { "• \($0.prompt)" }.joined(separator: "\n")
        let megaPrompt = """
        Morning Briefing - Please perform these tasks:
        
        \(taskPrompts)
        
        Provide a structured summary with bullet points and emojis.
        """

        print("📝 Mega Prompt:\n\(megaPrompt)")
        
        // Send to the agent
        print("📤 Sending startup workflow prompt to agent...")
        coordinator.client.sendMessage(megaPrompt, mode: "mode1")
        
        // Mark as completed
        appContext.markStartupWorkflowCompleted()
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
