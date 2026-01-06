import SwiftUI

// Have to have function to pull data from local db for settings
class AppContext: ObservableObject {
    // Singleton instance
    static let shared = AppContext()
    
    // Private initializer to enforce singleton
    private init() {
        loadSettings()
        setupAppTerminationObserver()
    }
    
    // Setup observer to save settings when app terminates
    private func setupAppTerminationObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
    }
    
    @objc private func appWillTerminate() {
        saveSettings()
    }

    // Dynamic Data
    @Published var response: String = ""
    @Published var isLoading: Bool = false
    @Published var shouldAnimate: Bool = false
    @Published var isGoogleConnected: Bool = false
    @Published var hasRunStartupWorkflow: Bool = false  // Track if startup workflow ran

    // Constant UI Settings
    @Published var overlayWidth: CGFloat = 300
    @Published var overlayHeight: CGFloat = 160

    // Static Settings
    @Published var aiApiKey: String = ""
    @Published var credentialsDirectory: URL = {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupportDir = paths[0].appendingPathComponent("Rong-E").appendingPathComponent("Credentials")
        return appSupportDir
    }()

    @Published var startUpWorkFinished: Bool = false

    // Add this inside AppContext.swift or a separate file
    struct ModeConfiguration: Identifiable, Codable, Hashable {
        var id: Int // 1 to 5
        var name: String
        var systemPrompt: String
        var enabledTools: Set<String>
        var isScreenshotEnabled: Bool
    }

    // Inside AppContext class
    @Published var modes: [ModeConfiguration] = [
        ModeConfiguration(id: 1, name: "General Assistant", systemPrompt: "You are a helpful assistant.", enabledTools: ["web_search", "search_knowledge_base"], isScreenshotEnabled: false),
        ModeConfiguration(id: 2, name: "Coder", systemPrompt: "You are an expert Swift developer.", enabledTools: ["email"], isScreenshotEnabled: false),
        ModeConfiguration(id: 3, name: "Researcher", systemPrompt: "Deep dive into topics using academic sources.", enabledTools: ["web_search", "calendar"], isScreenshotEnabled: false),
        ModeConfiguration(id: 4, name: "Writer", systemPrompt: "Creative writing mode.", enabledTools: [], isScreenshotEnabled: false),
        ModeConfiguration(id: 5, name: "Data Analyst", systemPrompt: "Analyze data structures.", enabledTools: ["search_knowledge_base"], isScreenshotEnabled: false)
    ]

    // List of all available tools in your system
    let availableTools = Constants.Tools.availableTools

    // save and load methods for all the variables
    func saveSettings() {
        print("💾 Saving settings...")
        let encoder = JSONEncoder()
        if let encodedModes = try? encoder.encode(modes) {
            UserDefaults.standard.set(encodedModes, forKey: "modes")
        }
        UserDefaults.standard.set(aiApiKey, forKey: "aiApiKey")
        UserDefaults.standard.set(startUpWorkFinished, forKey: "startUpWorkFinished")
    }

    // load settings
    func loadSettings() {
        print("📂 Loading settings...")
        let decoder = JSONDecoder()
        if let savedModesData = UserDefaults.standard.data(forKey: "modes"),
           let decodedModes = try? decoder.decode([ModeConfiguration].self, from: savedModesData) {
            modes = decodedModes
        }
        if let savedApiKey = UserDefaults.standard.string(forKey: "aiApiKey") {
            aiApiKey = savedApiKey
        }
        if UserDefaults.standard.object(forKey: "startUpWorkFinished") != nil {
            startUpWorkFinished = UserDefaults.standard.bool(forKey: "startUpWorkFinished")
        }
    }
    
    // Mark startup workflow as completed
    func markStartupWorkflowCompleted() {
        startUpWorkFinished = true
        saveSettings()
    }
}