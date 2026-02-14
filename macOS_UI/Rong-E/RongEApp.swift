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

        // 4. Auto-sync configs when WebSocket first connects
        coordinator.client.$isConnected
            .removeDuplicates()
            .filter { $0 == true }
            .first()
            .sink { [weak self] _ in
                print("🔧 Auto-syncing configs on connection...")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    // Set up Google Auth first (checks for existing credentials)
                    GoogleAuthManager.shared.startupCheck()

                    // Sync MCP config
                    MCPConfigManager.shared.sendConfigToPython()

                    // Sync LLM config with saved provider/model/API key
                    self?.sendSavedLLMConfig()

                    // Sync saved spreadsheet configs
                    SpreadsheetConfigManager.shared.syncToPython()
                }
            }
            .store(in: &cancellables)

        // 5. Run startup workflow after MCP servers are synced (one-time only)
        coordinator.client.onMCPSyncResult = { [weak self] success, message in
            print("🔧 MCP Sync Result: success=\(success), message=\(message ?? "nil")")
            // Clear callback after first run so manual syncs don't re-trigger startup
            self?.coordinator.client.onMCPSyncResult = nil
            self?.runStartupWorkflowIfNeeded()
        }
    }


    func applicationWillTerminate(_ notification: Notification) {
        // Save settings before quitting
        AppContext.shared.saveSettings()

        // Stop the server when app quits
        print("🛑 Stopping Rong-E agent server...")
        pythonManager.stopServer()
    }

    /// Send the saved LLM configuration to the Python backend
    private func sendSavedLLMConfig() {
        let context = AppContext.shared
        let provider = context.llmProvider
        let model = context.llmModel
        let apiKey = context.aiApiKey

        // Only send if we have a valid API key (or provider doesn't require one)
        if provider.requiresAPIKey && apiKey.isEmpty {
            print("⚠️ Skipping LLM config sync - no API key saved for \(provider.displayName)")
            return
        }

        print("🤖 Sending saved LLM config: \(provider.displayName) / \(model)")
        coordinator.client.sendLLMConfig(
            provider: provider.rawValue,
            model: model,
            apiKey: provider.requiresAPIKey ? apiKey : nil
        )
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
        You are a startup briefing agent. Perform the tasks below and produce one concise briefing.
        Tasks:
        \(taskPrompts)
        
        Output:
        - Short, spoken-style sections
        - Bullet points
        - Light, relevant emojis
        - Do not mention the tasks
        - Only show the final briefing
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
