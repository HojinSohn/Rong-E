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

enum LLMProvider: String, CaseIterable, Codable {
    case gemini = "gemini"
    case openai = "openai"
    case ollama = "ollama"
    case anthropic = "anthropic"

    var displayName: String {
        switch self {
        case .gemini: return "Google Gemini"
        case .openai: return "OpenAI"
        case .ollama: return "Ollama"
        case .anthropic: return "Anthropic"
        }
    }

    var requiresAPIKey: Bool {
        switch self {
        case .ollama: return false
        default: return true
        }
    }

    var defaultModel: String {
        switch self {
        case .gemini: return "gemini-2.5-flash-lite"
        case .openai: return "gpt-4o-mini"
        case .ollama: return "llama3"
        case .anthropic: return "claude-sonnet-4-20250514"
        }
    }

    var apiKeyPlaceholder: String {
        switch self {
        case .gemini: return "Enter Google AI API key..."
        case .openai: return "Enter OpenAI API key..."
        case .ollama: return "No API key required"
        case .anthropic: return "Enter Anthropic API key..."
        }
    }

    var suggestedModels: [String] {
        switch self {
        case .gemini:
            return [
                "gemini-2.5-flash-lite",
                "gemini-2.5-flash",
                "gemini-2.5-pro",
                "gemini-2.0-flash",
                "gemini-1.5-pro"
            ]
        case .openai:
            return [
                "gpt-4o-mini",
                "gpt-4o",
                "gpt-4-turbo",
                "gpt-3.5-turbo",
                "o1-mini",
                "o1"
            ]
        case .ollama:
            return [
                "llama3",
                "llama3.1",
                "llama3.2",
                "mistral",
                "codellama",
                "gemma2",
                "phi3",
                "qwen2"
            ]
        case .anthropic:
            return [
                "claude-sonnet-4-20250514",
                "claude-haiku-4-20250414",
                "claude-3-5-sonnet-20241022",
                "claude-3-5-haiku-20241022",
                "claude-3-opus-20240229"
            ]
        }
    }
}

class AppContext: ObservableObject {
    static let shared = AppContext()
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
    @Published var llmProvider: LLMProvider = .gemini
    @Published var llmModel: String = "gemini-2.5-flash-lite"
    
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
        var isScreenshotEnabled: Bool
    }

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
    

    // Helper to get the actual object
    var currentMode: ModeConfiguration {
        modes.first { $0.id == currentModeId } ?? (modes.first ?? ModeConfiguration(id: 0, name: "Fallback", systemPrompt: "", isScreenshotEnabled: false))
    }

    // Helper to toggle the setting for the ACTIVE mode
    func toggleCurrentModeVision() {
        if let index = modes.firstIndex(where: { $0.id == currentModeId }) {
            modes[index].isScreenshotEnabled.toggle()
            saveSettings() // Persist the change
        }
    }

    func addMode(_ mode: ModeConfiguration) {
        modes.append(mode)
        saveSettings()
    }

    func createNewMode() -> ModeConfiguration {
        let nextId = (modes.map { $0.id }.max() ?? 0) + 1
        let newMode = ModeConfiguration(
            id: nextId,
            name: "New Mode",
            systemPrompt: "",
            isScreenshotEnabled: false
        )
        modes.append(newMode)
        saveSettings()
        return newMode
    }

    func deleteMode(id: Int) {
        // Don't delete if it's the last mode
        guard modes.count > 1 else { return }
        modes.removeAll { $0.id == id }
        // If we deleted the current mode, switch to the first available
        if currentModeId == id {
            currentModeId = modes.first?.id ?? 1
        }
        saveSettings()
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
        // Save API key for the current provider
        saveApiKeyForProvider(llmProvider, apiKey: aiApiKey)
        UserDefaults.standard.set(llmProvider.rawValue, forKey: "llmProvider")
        UserDefaults.standard.set(llmModel, forKey: "llmModel")
        UserDefaults.standard.set(startUpWorkFinished, forKey: "startUpWorkFinished")
    }

    /// Save API key for a specific provider
    func saveApiKeyForProvider(_ provider: LLMProvider, apiKey: String) {
        let key = "apiKey_\(provider.rawValue)"
        UserDefaults.standard.set(apiKey, forKey: key)
        print("💾 Saved API key for \(provider.displayName)")
    }

    /// Load API key for a specific provider
    func loadApiKeyForProvider(_ provider: LLMProvider) -> String {
        let key = "apiKey_\(provider.rawValue)"
        return UserDefaults.standard.string(forKey: key) ?? ""
    }

    /// Switch to a new provider and load its saved API key
    func switchProvider(to provider: LLMProvider) {
        // Save current API key for the current provider before switching
        saveApiKeyForProvider(llmProvider, apiKey: aiApiKey)

        // Switch provider
        llmProvider = provider
        llmModel = provider.defaultModel

        // Load the API key for the new provider
        aiApiKey = loadApiKeyForProvider(provider)

        saveSettings()
    }

    func loadSettings() {
        print("📂 Loading settings...")
        let decoder = JSONDecoder()
        if let savedModesData: Data = UserDefaults.standard.data(forKey: "modes"),
           let decodedModes = try? decoder.decode([ModeConfiguration].self, from: savedModesData),
           !decodedModes.isEmpty {
            self.modes = decodedModes
        } else {
            // Initialize with default modes
            self.modes = [
                ModeConfiguration(id: 1, name: "General", systemPrompt: "You are a helpful general-purpose AI assistant. Assist with a wide range of tasks including answering questions, brainstorming, writing, and problem-solving.", isScreenshotEnabled: false),
                ModeConfiguration(id: 2, name: "Coding", systemPrompt: "You are a coding assistant. Help with programming tasks.", isScreenshotEnabled: false),
                ModeConfiguration(id: 3, name: "Research", systemPrompt: "You are a research assistant. Help find and summarize information.", isScreenshotEnabled: false)
            ]
        }
        // Load provider first, then load API key for that provider
        if let savedProvider = UserDefaults.standard.string(forKey: "llmProvider"),
           let provider = LLMProvider(rawValue: savedProvider) {
            self.llmProvider = provider
        }
        // Load API key for the current provider
        self.aiApiKey = loadApiKeyForProvider(llmProvider)

        if let savedModel = UserDefaults.standard.string(forKey: "llmModel") {
            self.llmModel = savedModel
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