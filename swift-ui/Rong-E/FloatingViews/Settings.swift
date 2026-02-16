import SwiftUI

// MARK: - Jarvis Design System

extension Color {
    static let jarvisBlue = Color(red: 0/255, green: 240/255, blue: 255/255) // Electric Cyan
    static let jarvisDark = Color(red: 10/255, green: 20/255, blue: 30/255)  // Deep Navy/Black
    static let jarvisDim = Color.gray.opacity(0.3)
}

struct JarvisPanel: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .background(Color.black.opacity(0.4))
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.jarvisBlue.opacity(0.3), lineWidth: 1)
            )
    }
}

struct JarvisGlow: ViewModifier {
    var active: Bool
    func body(content: Content) -> some View {
        content
            .shadow(color: active ? .jarvisBlue : .clear, radius: 8, x: 0, y: 0)
    }
}

// A technical background grid pattern
struct TechGridBackground: View {
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let width = geometry.size.width
                let height = geometry.size.height
                let spacing: CGFloat = 40
                
                for i in 0...Int(width/spacing) {
                    path.move(to: CGPoint(x: CGFloat(i)*spacing, y: 0))
                    path.addLine(to: CGPoint(x: CGFloat(i)*spacing, y: height))
                }
                for i in 0...Int(height/spacing) {
                    path.move(to: CGPoint(x: 0, y: CGFloat(i)*spacing))
                    path.addLine(to: CGPoint(x: width, y: CGFloat(i)*spacing))
                }
            }
            .stroke(Color.jarvisBlue.opacity(0.05), lineWidth: 1)
        }
    }
}

struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct SettingsView: View {
    @EnvironmentObject var coordinator: WindowCoordinator
    @EnvironmentObject var context: AppContext

    let windowID: String
    
    // Custom Tab Selection
    @State private var selectedTab: Int = 0
    
    var body: some View {
        ZStack {
            // 1. Deep Background
            Color.black.ignoresSafeArea()
            
            // 2. Tech Grid & Blur
            TechGridBackground()
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                .opacity(0.8)
                .ignoresSafeArea()
            
            // 3. Decorative HUD Corners
            VStack {
                HStack {
                    CornerBracket(topLeft: true)
                    Spacer()
                    CornerBracket(topLeft: false)
                }
                Spacer()
                HStack {
                    CornerBracket(topLeft: false, rotate: true)
                    Spacer()
                    CornerBracket(topLeft: true, rotate: true)
                }
            }
            .padding(10)
            .allowsHitTesting(false) // Let clicks pass through decoration

            // 4. Content
            VStack(spacing: 0) {
                // Custom Header
                HStack {
                    Circle()
                        .fill(Color.jarvisBlue)
                        .frame(width: 8, height: 8)
                        .modifier(JarvisGlow(active: true))
                    
                    Text("SYSTEM // SETTINGS")
                        .font(.system(.subheadline, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundColor(.jarvisBlue)
                        .tracking(2)
                    
                    Spacer()
                    
                    // Inside SettingsView -> VStack -> HStack (Header)
                    Button(action: {
                        coordinator.closeWindow(id: windowID)
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.gray)
                            .modifier(JarvisGlow(active: false))
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 15)
                .background(Color.jarvisBlue.opacity(0.05))
                .overlay(Rectangle().frame(height: 1).foregroundColor(.jarvisBlue.opacity(0.3)), alignment: .bottom)
                
                // Custom Tab Bar (Replacing standard TabView for styling control)
                HStack(spacing: 0) {
                    JarvisTabButton(icon: "gearshape", title: "SYS", isSelected: selectedTab == 0) { selectedTab = 0 }
                    JarvisTabButton(icon: "slider.horizontal.3", title: "MOD", isSelected: selectedTab == 1) { selectedTab = 1 }
                    JarvisTabButton(icon: "server.rack", title: "MCP", isSelected: selectedTab == 2) { selectedTab = 2 }
                    JarvisTabButton(icon: "brain", title: "MEM", isSelected: selectedTab == 3) { selectedTab = 3 }
                    JarvisTabButton(icon: "info.circle", title: "DAT", isSelected: selectedTab == 4) { selectedTab = 4 }
                }
                .padding(.vertical, 10)

                // View Switcher
                Group {
                    switch selectedTab {
                    case 0: GeneralSettingsView()
                    case 1: ModesSettingsView()
                    case 2: MCPSettingsView()
                    case 3: MemorySettingsView()
                    case 4: AboutSettingsView()
                    default: GeneralSettingsView()
                    }
                }
                .padding(20)
                .transition(.opacity)
            }
        }
        .frame(width: 500, height: 500)
        .preferredColorScheme(.dark)
    }
}

// Helper: Decorative Corner Brackets
struct CornerBracket: View {
    var topLeft: Bool
    var rotate: Bool = false
    
    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 20))
            path.addLine(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 20, y: 0))
        }
        .stroke(Color.jarvisBlue.opacity(0.6), lineWidth: 2)
        .frame(width: 20, height: 20)
        .rotationEffect(rotate ? .degrees(180) : .degrees(0))
        .scaleEffect(x: topLeft ? 1 : -1, y: 1)
    }
}

struct JarvisTabButton: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                Text(title)
                    .font(.system(size: 10, design: .monospaced))
                    .bold()
            }
            // Fix 1: Brighter gray for unselected state so it's visible on black
            .foregroundColor(isSelected ? .jarvisBlue : .white.opacity(0.4))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isSelected ? Color.jarvisBlue.opacity(0.1) : Color.clear)
            .overlay(
                Rectangle()
                    .frame(height: 2)
                    .foregroundColor(isSelected ? .jarvisBlue : .clear),
                alignment: .bottom
            )
            // Fix 2: Makes the entire area clickable even if background is clear
            .contentShape(Rectangle()) 
        }
        .buttonStyle(BorderlessButtonStyle())
    }
}

struct GeneralSettingsView: View {
    @EnvironmentObject var context: AppContext
    @State private var llmStatusMessage: String?
    @State private var llmStatusIsError: Bool = false
    @State private var isVerifying: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {

                // Section 1: System
                VStack(alignment: .leading, spacing: 8) {
                    Text("CORE CONFIGURATION")
                        .font(.caption)
                        .foregroundColor(.jarvisBlue.opacity(0.7))
                        .tracking(1)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("USER NAME")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.gray)

                        TextField("Enter your name...", text: $context.userName)
                            .textFieldStyle(.plain)
                            .padding(6)
                            .font(.system(size: 12, design: .monospaced))
                            .background(Color.black.opacity(0.5))
                            .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.jarvisBlue.opacity(0.5), lineWidth: 1))
                            .foregroundColor(.white)
                            .onChange(of: context.userName) { _ in
                                context.saveSettings()
                            }
                    }
                }
                .modifier(JarvisPanel())

                // Section 2: LLM Configuration
                VStack(alignment: .leading, spacing: 10) {
                    Text("LLM CONFIGURATION")
                        .font(.caption)
                        .foregroundColor(.jarvisBlue.opacity(0.7))
                        .tracking(1)

                    // Provider Selector
                    LLMProviderSelector(selectedProvider: $context.llmProvider, onSelect: { provider in
                        // Use switchProvider to properly save/load API keys per provider
                        context.switchProvider(to: provider)
                        llmStatusMessage = nil
                    })

                    // Model Selector
                    LLMModelSelector(
                        selectedModel: $context.llmModel,
                        suggestedModels: context.llmProvider.suggestedModels
                    )

                    // API Key
                    if context.llmProvider.requiresAPIKey {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("API KEY")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.gray)

                            SecureField(context.llmProvider.apiKeyPlaceholder, text: $context.aiApiKey)
                                .textFieldStyle(.plain)
                                .padding(6)
                                .font(.system(size: 12, design: .monospaced))
                                .background(Color.black.opacity(0.5))
                                .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.jarvisBlue.opacity(0.5), lineWidth: 1))
                                .foregroundColor(.white)
                        }
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 9))
                                .foregroundColor(.jarvisBlue.opacity(0.7))
                            Text("Ollama runs locally — no API key needed.")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.gray)
                        }
                    }

                    // Status Message
                    if let status = llmStatusMessage {
                        HStack(spacing: 5) {
                            if isVerifying {
                                ProgressView()
                                    .controlSize(.mini)
                            } else {
                                Image(systemName: llmStatusIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                                    .foregroundColor(llmStatusIsError ? .red : .green)
                                    .font(.system(size: 9))
                            }
                            Text(status)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(llmStatusIsError ? .red : .green)
                        }
                    }

                    // SET LLM Button
                    HStack {
                        Spacer()
                        Button(action: {
                            applyLLMConfig()
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: "cpu")
                                Text("SET LLM")
                            }
                            .font(.system(size: 10, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundColor(.jarvisBlue)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(Color.jarvisBlue.opacity(0.2))
                            .overlay(Rectangle().stroke(Color.jarvisBlue, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .disabled(isVerifying || (context.llmProvider.requiresAPIKey && context.aiApiKey.isEmpty))
                    }
                }
                .modifier(JarvisPanel())
            }
        }
        .onAppear {
            setupLLMCallbacks()
        }
    }

    private func setupLLMCallbacks() {
        SocketClient.shared.onLLMSetResult = { success, message in
            isVerifying = false
            llmStatusIsError = !success
            llmStatusMessage = message ?? (success ? "LLM configured" : "Failed to set LLM")
        }
    }

    private func applyLLMConfig() {
        // Validate
        if context.llmProvider.requiresAPIKey && context.aiApiKey.trimmingCharacters(in: .whitespaces).isEmpty {
            llmStatusMessage = "API key is required for \(context.llmProvider.displayName)"
            llmStatusIsError = true
            return
        }

        // Show verifying state
        isVerifying = true
        llmStatusMessage = "Verifying \(context.llmProvider.displayName) / \(context.llmModel)..."
        llmStatusIsError = false

        // Send to backend (backend will validate and respond)
        SocketClient.shared.sendLLMConfig(
            provider: context.llmProvider.rawValue,
            model: context.llmModel,
            apiKey: context.llmProvider.requiresAPIKey ? context.aiApiKey : nil
        )

        // Save settings
        context.saveSettings()
    }
}

// Extracted to reduce type-check complexity
struct LLMProviderSelector: View {
    @Binding var selectedProvider: LLMProvider
    var onSelect: (LLMProvider) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(LLMProvider.allCases, id: \.self) { provider in
                LLMProviderButton(
                    provider: provider,
                    isSelected: selectedProvider == provider
                ) {
                    selectedProvider = provider
                    onSelect(provider)
                }
            }
        }
    }
}

struct LLMProviderButton: View {
    let provider: LLMProvider
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(provider.displayName.uppercased())
                .font(.system(size: 8, design: .monospaced))
                .fontWeight(isSelected ? .bold : .regular)
                .foregroundColor(isSelected ? .white : .gray)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(isSelected ? Color.jarvisBlue.opacity(0.2) : Color.black.opacity(0.3))
                .overlay(
                    Rectangle()
                        .stroke(isSelected ? Color.jarvisBlue : Color.white.opacity(0.1), lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct LLMModelSelector: View {
    @Binding var selectedModel: String
    let suggestedModels: [String]
    @State private var isExpanded: Bool = false
    @State private var customModel: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("MODEL")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.gray)

            // Selected model display / dropdown toggle
            Button(action: { withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() } }) {
                HStack {
                    Text(selectedModel.isEmpty ? "Select a model" : selectedModel)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(selectedModel.isEmpty ? .gray : .white)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8))
                        .foregroundColor(.jarvisBlue)
                }
                .padding(6)
                .background(Color.black.opacity(0.5))
                .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.jarvisBlue.opacity(0.5), lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 0) {
                    // Suggested models
                    ForEach(suggestedModels, id: \.self) { model in
                        Button(action: {
                            selectedModel = model
                            withAnimation(.easeInOut(duration: 0.15)) { isExpanded = false }
                        }) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(selectedModel == model ? Color.jarvisBlue : Color.clear)
                                    .overlay(Circle().stroke(Color.jarvisBlue.opacity(0.5), lineWidth: 1))
                                    .frame(width: 6, height: 6)
                                Text(model)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(selectedModel == model ? .white : .gray)
                                Spacer()
                            }
                            .padding(.vertical, 5)
                            .padding(.horizontal, 8)
                            .background(selectedModel == model ? Color.jarvisBlue.opacity(0.1) : Color.clear)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    // Custom model input
                    HStack(spacing: 6) {
                        Image(systemName: "pencil")
                            .font(.system(size: 8))
                            .foregroundColor(.jarvisBlue.opacity(0.6))
                        TextField("Custom model...", text: $customModel, onCommit: {
                            if !customModel.trimmingCharacters(in: .whitespaces).isEmpty {
                                selectedModel = customModel
                                customModel = ""
                                withAnimation(.easeInOut(duration: 0.15)) { isExpanded = false }
                            }
                        })
                        .textFieldStyle(.plain)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white)
                    }
                    .padding(.vertical, 5)
                    .padding(.horizontal, 8)
                    .background(Color.black.opacity(0.3))
                }
                .background(Color.black.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.jarvisBlue.opacity(0.3), lineWidth: 1))
            }
        }
    }
}

// MARK: - MCP Settings View
struct MCPSettingsView: View {
    @ObservedObject var configManager = MCPConfigManager.shared
    @State private var showFileImporter = false
    @State private var showAddServerSheet = false
    @State private var showJSONPasteSheet = false
    @State private var jsonPasteText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            // Header with sync status
            HStack {
                Text("MCP SERVER ARRAY")
                    .font(.caption)
                    .foregroundColor(.jarvisBlue.opacity(0.7))
                    .tracking(1)

                Spacer()

                if configManager.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            // Error display
            if let error = configManager.lastError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.orange)
                    Spacer()
                    Button("CLEAR") {
                        configManager.lastError = nil
                    }
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.jarvisBlue)
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
                .overlay(Rectangle().stroke(Color.orange.opacity(0.3), lineWidth: 1))
            }

            // Server list
            if configManager.servers.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 30))
                        .foregroundColor(.jarvisBlue.opacity(0.4))
                    Text("NO SERVERS CONFIGURED")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.gray)
                    Text("Import config or add servers manually")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.gray.opacity(0.6))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(configManager.servers) { server in
                            MCPServerRow(
                                server: server,
                                status: configManager.serverStatuses[server.name] ?? .idle
                            ) {
                                configManager.removeServer(server)
                            }
                        }
                    }
                }
                .frame(maxHeight: 150)
            }

            Spacer()

            // Action buttons
            HStack(spacing: 10) {
                MCPActionButton(icon: "doc.badge.plus", title: "IMPORT") {
                    showFileImporter = true
                }
                MCPActionButton(icon: "doc.on.clipboard", title: "EDIT") {
                    // Pre-populate with current config
                    if let config = configManager.currentConfig {
                        jsonPasteText = config.toJSONString()
                    } else {
                        jsonPasteText = "{\n  \"mcpServers\": {\n    \n  }\n}"
                    }
                    showJSONPasteSheet = true
                }
                MCPActionButton(icon: "plus.circle", title: "ADD") {
                    showAddServerSheet = true
                }

                Spacer()

                if !configManager.servers.isEmpty {
                    Button(action: { configManager.sendConfigToPython() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("SYNC")
                        }
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.jarvisBlue)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.jarvisBlue.opacity(0.2))
                        .overlay(Rectangle().stroke(Color.jarvisBlue, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .modifier(JarvisPanel())
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                guard url.startAccessingSecurityScopedResource() else { return }
                defer { url.stopAccessingSecurityScopedResource() }
                configManager.loadConfig(from: url)
            }
        }
        .sheet(isPresented: $showAddServerSheet) {
            MCPAddServerSheet { server in
                configManager.addServer(server)
            }
        }
        .sheet(isPresented: $showJSONPasteSheet) {
            MCPJSONPasteSheet(jsonText: $jsonPasteText) {
                configManager.loadConfig(from: jsonPasteText)
                jsonPasteText = ""
            }
        }
    }
}

struct MCPServerRow: View {
    let server: MCPServerConfig
    let status: MCPServerConnectionStatus
    let onDelete: () -> Void
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                statusIndicator

                Text(server.name.uppercased())
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white)

                Text("// \(server.command)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.gray)

                Spacer()

                Button(action: { isExpanded.toggle() }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9))
                        .foregroundColor(.jarvisBlue)
                }
                .buttonStyle(.plain)

                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9))
                        .foregroundColor(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    if !server.args.isEmpty {
                        Text("ARGS: \(server.args.joined(separator: " "))")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.gray)
                    }
                    if let env = server.env, !env.isEmpty {
                        Text("ENV: \(env.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.gray)
                    }
                }
                .padding(.leading, 14)
            }
        }
        .padding(8)
        .background(Color.black.opacity(0.3))
        .overlay(Rectangle().stroke(Color.jarvisBlue.opacity(0.2), lineWidth: 1))
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch status {
        case .idle:
            Circle()
                .fill(Color.gray)
                .frame(width: 6, height: 6)
        case .connecting:
            ProgressView()
                .controlSize(.mini)
                .frame(width: 12, height: 12)
        case .connected:
            Circle()
                .fill(Color.green)
                .frame(width: 6, height: 6)
                .shadow(color: .green.opacity(0.6), radius: 3)
        case .connectedPermissionDenied:
            Circle()
                .fill(Color.orange)
                .frame(width: 6, height: 6)
                .shadow(color: .orange.opacity(0.6), radius: 3)
                .help("macOS permission denied. Grant in System Settings > Privacy & Security.")
        case .error(let msg):
            Circle()
                .fill(Color.red)
                .frame(width: 6, height: 6)
                .help(msg)
        }
    }
}

struct MCPActionButton: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.system(size: 9, design: .monospaced))
            .foregroundColor(.jarvisBlue.opacity(0.8))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.3))
            .overlay(Rectangle().stroke(Color.jarvisBlue.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct MCPAddServerSheet: View {
    @Environment(\.dismiss) var dismiss
    let onAdd: (MCPServerConfig) -> Void

    @State private var name = ""
    @State private var command = ""
    @State private var argsText = ""
    @State private var envText = ""
    @State private var validationError: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                .opacity(0.9)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                Text("ADD MCP SERVER")
                    .font(.system(.headline, design: .monospaced))
                    .foregroundColor(.jarvisBlue)
                    .tracking(2)

                VStack(alignment: .leading, spacing: 12) {
                    MCPTextField(label: "SERVER NAME", text: $name, placeholder: "e.g., filesystem")
                    MCPTextField(label: "COMMAND", text: $command, placeholder: "e.g., npx, node, python")
                    MCPTextField(label: "ARGUMENTS", text: $argsText, placeholder: "space-separated args")
                    MCPTextField(label: "ENVIRONMENT", text: $envText, placeholder: "KEY=value, comma-separated")
                }

                if let error = validationError {
                    Text(error)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.red)
                }

                HStack {
                    Spacer()
                    Button("CANCEL") { dismiss() }
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.gray)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .overlay(Rectangle().stroke(Color.gray.opacity(0.5), lineWidth: 1))
                        .buttonStyle(.plain)

                    Button("ADD") { addServer() }
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.jarvisBlue)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.jarvisBlue.opacity(0.2))
                        .overlay(Rectangle().stroke(Color.jarvisBlue, lineWidth: 1))
                        .buttonStyle(.plain)
                        .disabled(name.isEmpty || command.isEmpty)
                }
            }
            .padding(24)
        }
        .frame(width: 400, height: 350)
    }

    private func addServer() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedCommand = command.trimmingCharacters(in: .whitespaces)

        guard !trimmedName.isEmpty else {
            validationError = "Server name is required"
            return
        }
        guard !trimmedCommand.isEmpty else {
            validationError = "Command is required"
            return
        }

        let args = argsText.split(separator: " ").map { String($0) }.filter { !$0.isEmpty }
        var env: [String: String]? = nil
        if !envText.isEmpty {
            env = [:]
            for pair in envText.split(separator: ",") {
                let parts = pair.split(separator: "=", maxSplits: 1)
                if parts.count == 2 {
                    env?[String(parts[0]).trimmingCharacters(in: .whitespaces)] =
                        String(parts[1]).trimmingCharacters(in: .whitespaces)
                }
            }
        }

        let server = MCPServerConfig(name: trimmedName, command: trimmedCommand, args: args, env: env)
        onAdd(server)
        dismiss()
    }
}

struct MCPJSONPasteSheet: View {
    @Environment(\.dismiss) var dismiss
    @Binding var jsonText: String
    let onSubmit: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                .opacity(0.9)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                Text("EDIT MCP CONFIG")
                    .font(.system(.headline, design: .monospaced))
                    .foregroundColor(.jarvisBlue)
                    .tracking(2)

                Text("Edit the JSON below to add or modify MCP servers")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.gray)

                TextEditor(text: $jsonText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white)
                    .scrollContentBackground(.hidden)
                    .background(Color.black.opacity(0.5))
                    .overlay(Rectangle().stroke(Color.jarvisBlue.opacity(0.3), lineWidth: 1))
                    .frame(minHeight: 200)

                Text("FORMAT: {\"mcpServers\": {\"name\": {\"command\": \"...\", \"args\": [...]}}}")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.gray.opacity(0.7))

                HStack {
                    Spacer()
                    Button("CANCEL") { dismiss() }
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.gray)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .overlay(Rectangle().stroke(Color.gray.opacity(0.5), lineWidth: 1))
                        .buttonStyle(.plain)

                    Button("APPLY") {
                        onSubmit()
                        dismiss()
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.jarvisBlue)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.jarvisBlue.opacity(0.2))
                    .overlay(Rectangle().stroke(Color.jarvisBlue, lineWidth: 1))
                    .buttonStyle(.plain)
                    .disabled(jsonText.isEmpty)
                }
            }
            .padding(24)
        }
        .frame(width: 550, height: 420)
    }
}

struct MCPTextField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.jarvisBlue.opacity(0.7))

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.white)
                .padding(8)
                .background(Color.black.opacity(0.5))
                .overlay(Rectangle().stroke(Color.jarvisBlue.opacity(0.3), lineWidth: 1))
        }
    }
}

// MARK: - Memory Settings View
struct MemorySettingsView: View {
    @State private var memoryContent: String = ""
    @State private var isLoading: Bool = true
    @State private var isSaving: Bool = false
    @State private var statusMessage: String?
    @State private var statusIsError: Bool = false
    @State private var hasChanges: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            // Header
            HStack {
                Text("PERSISTENT MEMORY")
                    .font(.caption)
                    .foregroundColor(.jarvisBlue.opacity(0.7))
                    .tracking(1)

                Spacer()

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }

                if hasChanges {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 6, height: 6)
                        .help("Unsaved changes")
                }
            }

            Text("Store important information that persists across conversations. The agent will use this context automatically.")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.gray)

            // Memory Editor
            TextEditor(text: $memoryContent)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white)
                .scrollContentBackground(.hidden)
                .background(Color.black.opacity(0.5))
                .overlay(Rectangle().stroke(Color.jarvisBlue.opacity(0.3), lineWidth: 1))
                .frame(minHeight: 200)
                .onChange(of: memoryContent) { _ in
                    hasChanges = true
                }

            // Status Message
            if let status = statusMessage {
                HStack(spacing: 5) {
                    if isSaving {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: statusIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                            .foregroundColor(statusIsError ? .red : .green)
                            .font(.system(size: 9))
                    }
                    Text(status)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(statusIsError ? .red : .green)
                }
            }

            // Action Buttons
            HStack {
                Button(action: loadMemory) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text("RELOAD")
                    }
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.jarvisBlue.opacity(0.8))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.3))
                    .overlay(Rectangle().stroke(Color.jarvisBlue.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(isLoading)

                Button(action: clearMemory) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text("CLEAR")
                    }
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.red.opacity(0.8))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.3))
                    .overlay(Rectangle().stroke(Color.red.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(memoryContent.isEmpty)

                Spacer()

                Button(action: saveMemory) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.down")
                        Text("SAVE")
                    }
                    .font(.system(size: 10, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(.jarvisBlue)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Color.jarvisBlue.opacity(0.2))
                    .overlay(Rectangle().stroke(Color.jarvisBlue, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(isSaving || !hasChanges)
            }
        }
        .modifier(JarvisPanel())
        .onAppear {
            setupCallbacks()
            loadMemory()
        }
    }

    private func setupCallbacks() {
        SocketClient.shared.onMemoryContent = { content in
            isLoading = false
            memoryContent = content
            hasChanges = false
            statusMessage = nil
        }

        SocketClient.shared.onMemorySaved = { success, message in
            isSaving = false
            statusIsError = !success
            statusMessage = message
            if success {
                hasChanges = false
            }
        }
    }

    private func loadMemory() {
        isLoading = true
        statusMessage = nil
        SocketClient.shared.requestMemory()
    }

    private func saveMemory() {
        isSaving = true
        statusMessage = "Saving memory..."
        statusIsError = false
        SocketClient.shared.saveMemory(content: memoryContent)
    }

    private func clearMemory() {
        memoryContent = ""
        hasChanges = true
    }
}

struct AboutSettingsView: View {
    @State private var rotation: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                // Arc Reactor / Core Animation
                Circle()
                    .stroke(lineWidth: 3)
                    .foregroundColor(.jarvisBlue.opacity(0.3))
                    .frame(width: 80, height: 80)
                
                Circle()
                    .trim(from: 0, to: 0.8)
                    .stroke(style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .foregroundColor(.jarvisBlue)
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(rotation))
                    .onAppear {
                        withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                            rotation = 360
                        }
                    }
                
                Image(systemName: "cpu")
                    .font(.largeTitle)
                    .foregroundColor(.white)
            }
            .padding(.bottom, 20)
            
            Text("PROJECT: RONG-E")
                .font(.system(.title2, design: .monospaced))
                .fontWeight(.bold)
                .foregroundColor(.white)
                .tracking(2)
            
            Text("BUILD: V.1.0.0-BETA")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.jarvisBlue)
                .padding(.top, 2)
            
            Spacer()
            
            Text("CREATED BY HOJIN SOHN")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.gray)
                .padding(.bottom, 5)
                
            Text("INTELLIGENT AGENT SYSTEM ONLINE")
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(.jarvisBlue.opacity(0.6))
        }
        .padding()
    }
}

// A Custom Toggle that looks like a technical switch
struct JarvisToggle: View {
    let title: String
    @Binding var isOn: Bool
    
    var body: some View {
        // Wrap in a button to make the text clickable too
        Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isOn.toggle() } }) {
            HStack {
                Text(title.uppercased())
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
                Spacer()
                
                // Visual Switch
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isOn ? Color.jarvisBlue.opacity(0.2) : Color.black)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(isOn ? Color.jarvisBlue : Color.gray, lineWidth: 1)
                        )
                        .frame(width: 40, height: 20)
                    
                    Circle()
                        .fill(isOn ? Color.jarvisBlue : Color.gray)
                        .frame(width: 14, height: 14)
                        .offset(x: isOn ? 10 : -10)
                        .modifier(JarvisGlow(active: isOn))
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle()) // Makes the spacer area clickable
        }
        .buttonStyle(.plain) // Removes standard button click flash
    }
}

