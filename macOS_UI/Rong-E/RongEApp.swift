import SwiftUI
import AppKit
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {
    // The Delegate references the shared coordinator
    var coordinator = WindowCoordinator.shared
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 2. Safe to show window now that AppKit is ready
        coordinator.showMainOverlay()
        
        // 3. Run startup workflow after a brief delay to ensure everything is initialized
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.runStartupWorkflowIfNeeded()
        }
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
        
        // Check if Google is connected
        if !appContext.isGoogleConnected {
            print("⚠️ Google not connected yet, startup workflow will run after connection")
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
