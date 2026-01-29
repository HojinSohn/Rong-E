import SwiftUI
import Combine

struct ChatMessage: Identifiable, Hashable {
    var id = UUID()
    let role: String
    let content: String
    var widgets: [ChatWidgetData]?

    init(role: String, content: String, widgets: [ChatWidgetData]? = nil) {
        self.role = role
        self.content = content
        self.widgets = widgets
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id
    }
}

enum AgentActivityType: Equatable {
    case idle
    case coding(filename: String)
    case browsing(url: String)
}

struct ReasoningStep: Identifiable {
    let id = UUID()
    let description: String
    var details: String?
    var status: StepStatus

    enum StepStatus {
        case completed, active, pending
    }

    init(description: String, details: String? = nil, status: StepStatus) {
        self.description = description
        self.details = details
        self.status = status
    }
}

class AppContext: ObservableObject {
    static let shared = AppContext()

    // Helper to get the actual object
    var currentMode: ModeConfiguration {
        modes.first { $0.id == currentModeId } ?? (modes.first ?? ModeConfiguration(id: 0, name: "Fallback", systemPrompt: "", enabledTools: [], isScreenshotEnabled: false))
    }

    // Helper to toggle the setting for the ACTIVE mode
    func toggleCurrentModeVision() {
        if let index = modes.firstIndex(where: { $0.id == currentModeId }) {
            modes[index].isScreenshotEnabled.toggle()
            saveSettings() // Persist the change
        }
    }
    @Published var currentModeId: Int = 1
    @Published var response: String = ""
    @Published var isLoading: Bool = false
    @Published var shouldAnimate: Bool = false
    @Published var isGoogleConnected: Bool = false
    @Published var hasRunStartupWorkflow: Bool = false
    @Published var startUpWorkFinished: Bool = false
    @Published var hasBootAnimated: Bool = false
    
    @Published var currentSessionChatMessages: [ChatMessage] = []
    @Published var activeTools: [ActiveToolInfo] = []
    
    // We initialize these with placeholders, they get updated in init()
    @Published var overlayWidth: CGFloat = 0
    @Published var overlayHeight: CGFloat = 0
    @Published var aiApiKey: String = ""
    @Published var credentialsDirectory: URL = FileManager.default.temporaryDirectory // Placeholder

    // --- Agent State ---
    @Published var reasoningSteps: [ReasoningStep] = [
        ReasoningStep(description: "Await input", status: .active)
    ]
    
    // 3. Agent Activity / Hands (Drives the Handoff Widget)
    @Published var currentActivity: AgentActivityType = .idle
    
    func setIdle() {
        withAnimation {
            self.currentActivity = .idle
            self.reasoningSteps = [ReasoningStep(description: "Ready", status: .active)]
        }
    }

    func clearSession() {
        withAnimation {
            self.currentSessionChatMessages = []
            self.reasoningSteps = [ReasoningStep(description: "Await input", status: .active)]
            self.currentActivity = .idle
            self.response = ""
            self.isLoading = false
        }
    }
    struct ModeConfiguration: Identifiable, Codable, Hashable {
        var id: Int
        var name: String
        var systemPrompt: String
        var enabledTools: Set<String>
        var isScreenshotEnabled: Bool
    }

    // Initialize as empty to keep compile time fast
    @Published var modes: [ModeConfiguration] = []

    private init() {
        self.overlayWidth = 300 // Replace with Constants.UI.overlayWindow.compactWidth
        self.overlayHeight = 160 // Replace with Constants.UI.overlayWindow.compactHeight
        self.aiApiKey = "YOUR_API_KEY" // Replace with Constants.apiKey
        
        if let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
             self.credentialsDirectory = supportDir
        }
        
        loadSettings()
        setupAppTerminationObserver()
    }
    
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

    func saveSettings() {
        print("💾 Saving settings...")
        let encoder = JSONEncoder()
        if let encodedModes = try? encoder.encode(modes) {
            UserDefaults.standard.set(encodedModes, forKey: "modes")
        }
        UserDefaults.standard.set(aiApiKey, forKey: "aiApiKey")
        UserDefaults.standard.set(startUpWorkFinished, forKey: "startUpWorkFinished")
    }

    func loadSettings() {
        print("📂 Loading settings...")
        let decoder = JSONDecoder()
        if let savedModesData = UserDefaults.standard.data(forKey: "modes"),
           let decodedModes = try? decoder.decode([ModeConfiguration].self, from: savedModesData) {
            self.modes = decodedModes
        }
        if let savedApiKey = UserDefaults.standard.string(forKey: "aiApiKey") {
            self.aiApiKey = savedApiKey
        }
        if UserDefaults.standard.object(forKey: "startUpWorkFinished") != nil {
            self.startUpWorkFinished = UserDefaults.standard.bool(forKey: "startUpWorkFinished")
        }
    }
    
    func markStartupWorkflowCompleted() {
        startUpWorkFinished = true
        saveSettings()
    }
}