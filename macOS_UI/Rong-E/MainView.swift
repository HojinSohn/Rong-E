import SwiftUI

struct MainView: View {
    // 1. Animation States
    @State private var showWaveform = false
    @State private var showColumns = false // New state to stagger the inside content
    @State private var showGreeting = false
    @State private var minimizedMode = true
    @State private var showMinimizedButtons = false
    @State private var fullChatViewMode = false
    @State private var showMinimizedMessageView = false
    @State private var onCoreHover = false

    // 3. Permission & Screenshot State
    @State private var waitingForPermission = false
    @State private var pendingQuery: String? = nil
    @State private var pendingMode: String? = nil
    @State private var permissionCheckTimer: Timer? = nil

    // 4. Input & Response State
    @State private var inputMode = false
    @State private var inputText = ""
    @State private var currentMode = "mode1"
    @State private var shouldAnimateResponse = true

    // 5. Processing State
    @State private var isListening = false
    @State private var isProcessing = false
    @State private var activeTool: String? = nil
    @State private var expandedStepIds: Set<UUID> = []
    @State private var pendingWidgets: [ChatWidgetData] = []

    // 6. Environment Objects
    @EnvironmentObject var appContext: AppContext
    @EnvironmentObject var windowCoordinator: WindowCoordinator
    @EnvironmentObject var workflowManager: WorkflowManager
    @EnvironmentObject var googleAuthManager: GoogleAuthManager
    @EnvironmentObject var socketClient: SocketClient
    @EnvironmentObject var themeManager: ThemeManager

    func toggleMinimized() {
        print("🔽 Toggling Minimized Mode")
        print("Current minimizedMode: \(minimizedMode)")
        let isMinimizing = !minimizedMode

        if isMinimizing {
            // Phase A: Content exits immediately
            withAnimation(.easeOut(duration: 0.25)) {
                showColumns = false
                showWaveform = false
                showGreeting = false
            }

            // Phase B: Container morph
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.spring(response: 0.7, dampingFraction: 0.85)) {
                    minimizedMode = true
                }
            }

            // Phase C: Window system sync
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                windowCoordinator.minimizeMainOverlay()
            }

        } else {
            // Phase B (reverse): Container expands
            windowCoordinator.expandMainOverlay()

            withAnimation(.spring(response: 0.7, dampingFraction: 0.85)) {
                minimizedMode = false
            }

            // Phase A (reverse): Content re-enters
            withAnimation(.easeOut(duration: 0.4).delay(0.25)) {
                showGreeting = true
            }

            // Phase A (reverse): Content re-enters
            withAnimation(.easeOut(duration: 0.4).delay(0.5)) {
                showColumns = true
                showWaveform = true
            }

            // Ensure minimized message view is hidden
            setShowMinimizedMessageView(false)
            setShowMinimizedButtons(false)
        }
        print("New minimizedMode: \(minimizedMode)")
    }

    func toggleFullChatView() {
        withAnimation(.easeInOut(duration: 0.4)) {
            fullChatViewMode.toggle()
        }
    }

    func setShowMinimizedMessageView(_ val: Bool) {
        withAnimation(.easeInOut(duration: 0.4)) {
            showMinimizedMessageView = val
        }
    }

    func setShowMinimizedButtons(_ val: Bool) {
        withAnimation(.easeInOut(duration: 0.4)) {
            showMinimizedButtons = val
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) { // Align bottom to help with positioning
            // --- CLOCK LAYER ---
            // Fades out when minimized
            VStack(spacing: 0) { // 1. Remove spacing between Time and Greeting
                Spacer().frame(height: 80) // Top Spacer for better vertical alignment
                
                // Time Display (Dynamic)
                Text(Date(), style: .time)
                    .font(.system(size: 42, weight: .semibold, design: .default))
                    .foregroundStyle(.white)
                    .shadow(color: .white, radius: 10)

                Text("Good \(getGreeting()), Hojin!") // Good Morning/Afternoon/Evening Greeting
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                
                Spacer()
            }
            .frame(width: 800, height: 520)
            .zIndex(1)
            .opacity(minimizedMode ? 0 : 1)
            // Adjust offset to keep it visually balanced with the new smaller size
            .offset(y: fullChatViewMode ? 0 : 40) 
            .opacity(fullChatViewMode ? 0 : 1)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: fullChatViewMode)
            .allowsHitTesting(false)

            // Keep the HUD visible when minimized without laying out the large content
            if showMinimizedButtons {
                MinimizedControlsView(
                    isListening: isListening,
                    minimizedMode: minimizedMode,
                    toggleMinimized: toggleMinimized,
                    toggleListening: toggleListening,
                    toggleMessages: { setShowMinimizedMessageView(!showMinimizedMessageView) },
                    onHoverChange: setShowMinimizedButtons
                )
            }

            // --- MAIN GLASS CONTAINER ---
            ZStack(alignment: .bottom) {
                // Content Layer (Header + Columns) — removed from layout when minimized
                if !minimizedMode {
                    VStack(spacing: 0) {
                        HeaderView(toggleMinimized: toggleMinimized)
                            .padding(.top, 20)
                            .padding(.horizontal, 24)
                            .opacity(showColumns ? 1 : 0) // Stagger entry
                        
                        HStack(alignment: .top, spacing: 16) {
                            LeftColumnView()
                                .offset(x: showColumns ? 0 : -100)
                                .opacity(showColumns ? 1 : 0)
                            
                            MainColumnView(
                                inputText: $inputText,
                                fullChatViewMode: $fullChatViewMode,
                                onSubmit: submitQuery // This links to your existing submitQuery function
                            )
                            .offset(y: showColumns ? 0 : 30)
                            .opacity(showColumns ? 1 : 0)
                        }
                        .padding(24)
                        .background(
                            
                            RongERing()
                                .scaleEffect(2.5)
                                .blur(radius: 10)
                                .environmentObject(themeManager)
                                .allowsHitTesting(false)
                        )
                    }
                    .transition(.opacity)
                } else {
                    RongERing()
                        .scaleEffect(0.6)
                        .environmentObject(themeManager)
                }
            }
            // MARK: - Frame Animation Logic
            .frame(
                width: minimizedMode ? 80 : 800,
                height: minimizedMode ? 80 : 520
            )
            .background(
                ZStack {
                    if !minimizedMode {
                        // 1. Base Tint (Very Low Opacity for "See-Through")
                        RoundedRectangle(cornerRadius: 40)
                            .fill(Color.black.opacity(0.5))

                        // 2. High-Tech Border (Keeps layout defined without solid background)
                        RoundedRectangle(cornerRadius: 40)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        appContext.currentMode.isScreenshotEnabled ? Color.cyan.opacity(0.8) : Color.cyan.opacity(0.4),
                                        Color.cyan.opacity(0.05)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    } else {
                        // Minimized Mode Background
                        RoundedRectangle(cornerRadius: 40) // Half of 80 to make a perfect circle
                            .fill(Color.black.opacity(0.6))
                            .shadow(color: Color.cyan.opacity(0.4), radius: 10)
                    }
                }
            )
            // Corner radius becomes 40 (half of 80) to make a perfect circle
            .cornerRadius(40)
            
            // Restore on Tap
            .onTapGesture {
                if minimizedMode {
                    toggleMinimized()
                }
            }
            // Hover Effect on minimized mode
            .onHover { hovering in
                if minimizedMode {
                    onCoreHover = hovering
                    withAnimation(.easeInOut(duration: 0.3)) {
                        setShowMinimizedButtons(hovering)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if showMinimizedMessageView {
                    MinimizedMessageView(inputText: $inputText, showMinimizedMessageView: $showMinimizedMessageView, onSubmit: submitQuery)
                        .environmentObject(appContext)
                        .offset(y: -110)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .onAppear {
            // Initialize connections and auth
            setUpConnection()
            
            toggleMinimized() // Use this to trigger the initial animations
        }
    }

    // MARK: - Logic Methods
    private func getGreeting() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:
            return "Morning"
        case 12..<17:
            return "Afternoon"
        default:
            return "Evening"
        }
    }

    private func setUpConnection() {
        setupSocketListeners()
        setUpAuthManager()
    }

    private func setupSocketListeners() {
        print("🔌 Setting up Socket Listeners")

        socketClient.onReceiveThought = { thoughtText in
            withAnimation {
                self.isProcessing = true
                self.activeTool = thoughtText.uppercased()

                self.appContext.reasoningSteps.append(
                    ReasoningStep(description: thoughtText, status: .active)
                )
            }
        }

        socketClient.onReceiveToolCall = { toolCallContent in
            // Format tool arguments as details string
            let argsDetails = toolCallContent.toolArgs.map { "\($0.key): \($0.value.description)" }.joined(separator: "\n")
            appContext.reasoningSteps.append(
                ReasoningStep(description: toolCallContent.toolName, details: argsDetails.isEmpty ? nil : argsDetails, status: .active)
            )
        }

        socketClient.onReceiveToolOutput = { toolResultContent in
            // Mark the last reasoning step as completed and add result details
            if let lastIndex = appContext.reasoningSteps.lastIndex(where: { $0.status == .active }) {
                appContext.reasoningSteps[lastIndex].status = .completed
                // Append result to existing details or set as new details
                let resultPreview = String(toolResultContent.result.prefix(500))
                if let existingDetails = appContext.reasoningSteps[lastIndex].details {
                    appContext.reasoningSteps[lastIndex].details = existingDetails + "\n\n--- Result ---\n" + resultPreview
                } else {
                    appContext.reasoningSteps[lastIndex].details = resultPreview
                }
            }
        }
        
        socketClient.onReceiveResponse = { responseText in
            finishProcessing(response: responseText)
        }

        socketClient.onReceiveImages = { imageDatas in
            for imageData in imageDatas {
                let randomX = CGFloat.random(in: 100...800)
                let randomY = CGFloat.random(in: 100...500)
                windowCoordinator.openDynamicWindow(id: imageData.url, view: AnyView(
                    ImageView(imageData: imageData, windowID: imageData.url)
                    .environmentObject(themeManager)
                    .environmentObject(windowCoordinator)
                    .frame(width: 600, height: 400)
                    .padding()
                    .background(themeManager.current.background)
                    .cornerRadius(12)
                    .shadow(radius: 10)
                ), size: CGSize(width: 600, height: 400), location: CGPoint(x: randomX, y: randomY))
            }
        }

        socketClient.onReceiveWidgets = { widgets in
            pendingWidgets = widgets
        }

        socketClient.onMCPServerStatus = { statusInfos in
            MCPConfigManager.shared.updateStatuses(from: statusInfos)
        }

        socketClient.onDisconnect = { errorText in
            finishProcessing(response: "Error: \(errorText)")
        }
    }

    private func setUpAuthManager() {
        googleAuthManager.startupCheck()
    }

    private func onBeforeCaptureScreenshot() {
        // Decrease main window opacity to avoid capturing UI elements
        windowCoordinator.setMainWindowOpacity(opacity: 0.1)
    }

    private func onAfterCaptureScreenshot() {
        // Restore main window opacity
        windowCoordinator.setMainWindowOpacity(opacity: 1.0)
    }

    private func captureAndSendWithScreenshot(query: String, selectedMode: String) {
        Task { @MainActor in
            var base64Image: String? = nil

            onBeforeCaptureScreenshot()
            
            do {
                base64Image = try await ScreenshotManager.captureMainScreen()
                print("✅ Screenshot captured. Size: \(base64Image?.count ?? 0)")
                
            } catch {
                let nsError = error as NSError
                
                if nsError.code == -3801 {
                    print("⚠️ Permission Denied. Opening Settings...")
                    
                    pendingQuery = query
                    pendingMode = selectedMode
                    waitingForPermission = true
                    
                    showPermissionWaitingOverlay()
                    
                    onAfterCaptureScreenshot()

                    return
                } else {
                    print("❌ Screenshot Error: \(nsError.localizedDescription)")
                }
            }

            socketClient.sendMessageWithImage(query, mode: selectedMode, base64Image: base64Image)
            
            self.activeTool = "WS_STREAM"

            onAfterCaptureScreenshot()
        }
    }

    private func showPermissionWaitingOverlay() {
        windowCoordinator.openPermissionWaitingOverlay(
            onRetry: {
                Task { @MainActor in
                    do {
                        let _ = try await ScreenshotManager.captureMainScreen()
                        
                        // Success! Permission granted
                        print("✅ Manual retry successful!")
                        
                        if let query = pendingQuery, let mode = pendingMode {
                            pendingQuery = nil
                            pendingMode = nil
                            waitingForPermission = false

                            // close overlay
                            windowCoordinator.closePermissionWaitingOverlay()

                            captureAndSendWithScreenshot(query: query, selectedMode: mode)
                        }
                    } catch {
                        print("❌ Still no permission on manual retry")
                    }
                }
            },
            onCancel: {
                // Send query without screenshot
                if let query = pendingQuery, let mode = pendingMode {
                    pendingQuery = nil
                    pendingMode = nil
                    waitingForPermission = false
                    socketClient.sendMessage(query, mode: mode)

                    // close overlay
                    windowCoordinator.closePermissionWaitingOverlay()

                    activeTool = "WS_STREAM"
                }
            }
        )
    }

    private func finishProcessing(response: String) {
        withAnimation {
            isProcessing = false
            activeTool = nil
            shouldAnimateResponse = true

            // Include any pending widgets in the message
            let messageWidgets = pendingWidgets.isEmpty ? nil : pendingWidgets
            appContext.currentSessionChatMessages.append(
                ChatMessage(role: "assistant", content: response, widgets: messageWidgets)
            )
            pendingWidgets = [] // Clear pending widgets

            appContext.response = response
            inputMode = false
            fullChatViewMode = true
        }
    }

    private func submitQuery() {
        guard !inputText.isEmpty else { return }
        
        let query = inputText
        let selectedMode = currentMode.lowercased()
        inputText = ""
        isProcessing = true
        inputMode = false
        appContext.response = ""

        // append user message to chat history
        appContext.currentSessionChatMessages.append(ChatMessage(role: "user", content: query))

        if appContext.modes.first(where: { $0.name == appContext.modes.first(where: { $0.id == Int(currentMode.suffix(1)) })?.name })?.isScreenshotEnabled == true {
            print("📸 Screenshot tool is enabled for this mode. Capturing screenshot...")
            captureAndSendWithScreenshot(query: query, selectedMode: selectedMode)
        } else {
            print("ℹ️ Screenshot tool is NOT enabled for this mode. Sending query without screenshot.")
            socketClient.sendMessage(query, mode: selectedMode)
            self.activeTool = "WS_STREAM"
        }
    }

    private func toggleListening() {
        withAnimation {
            if isListening {
                isListening = false
                isProcessing = true
                appContext.response = ""
                socketClient.sendMessage("Hello (Voice Input)", mode: currentMode.lowercased())
            } else {
                isListening = true
                isProcessing = false
                inputMode = false
                shouldAnimateResponse = true
                appContext.response = "Listening..."
            }
        }
    }
}

// MARK: - Helper for Glass Tint
extension View {
    func backgroundColor(_ color: Color) -> some View {
        self.background(color)
    }
}

struct MinimizedControlsView: View {
    let isListening: Bool
    let minimizedMode: Bool
    let toggleMinimized: () -> Void
    let toggleListening: () -> Void
    let toggleMessages: () -> Void
    let onHoverChange: (Bool) -> Void
    
    // Configuration
    private let radius: CGFloat = 70 
    private let hudCyan = Color(red: 0.0, green: 0.9, blue: 1.0)
    
    var body: some View {
        ZStack {
            // Left: Messages (-45°)
            OrbiterButton(
                icon: "message.fill",
                action: toggleMessages,
                angle: -45,
                radius: radius,
                hudCyan: hudCyan
            )

            // Center: Mic (0°)
            OrbiterButton(
                icon: isListening ? "mic.fill" : "mic.slash.fill",
                action: toggleListening,
                isActive: isListening,
                angle: 0,
                radius: radius,
                hudCyan: hudCyan
            )

            // Right: Minimize (+45°)
            OrbiterButton(
                icon: minimizedMode ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left",
                action: toggleMinimized,
                angle: 45,
                radius: radius,
                hudCyan: hudCyan
            )
        }
        .frame(height: 100)
        .onHover { hovering in onHoverChange(hovering) }
    }
}

struct OrbiterButton: View {
    var icon: String
    var action: () -> Void
    var isActive: Bool = false
    var angle: Double
    var radius: CGFloat
    var hudCyan: Color

    // Track Hover State locally
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                // 1. EXPANDED HIT AREA (Invisible)
                // This circle is invisible but captures clicks 
                // in a larger radius (60pt) than the visual button (40pt).
                Circle()
                    .fill(Color.white.opacity(0.001)) 
                    .frame(width: 60, height: 60)
                
                // 2. VISUAL BUTTON
                ZStack {
                    // Background
                    Circle()
                        .fill(Color.black.opacity(0.8))
                    
                    // Stroke (Reacts to Hover)
                    Circle()
                        .stroke(
                            isActive || isHovering ? hudCyan : Color.white.opacity(0.2),
                            lineWidth: isHovering ? 2 : 1
                        )
                    
                    // Icon
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(isActive || isHovering ? hudCyan : .white)
                }
                .frame(width: 40, height: 40)
                // 3. HOVER EFFECTS
                .shadow(
                    color: (isActive || isHovering) ? hudCyan.opacity(0.8) : .clear,
                    radius: isHovering ? 15 : 8
                )
                .scaleEffect(isHovering ? 1.2 : 1.0)
            }
        }
        .buttonStyle(.plain)
        .onHover { hover in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                isHovering = hover
            }
        }
        // Positioning Math
        .offset(
            x: radius * CGFloat(sin(angle * .pi / 180)),
            y: -radius * CGFloat(cos(angle * .pi / 180))
        )
    }
}

// MARK: - Left Column (Agentic Dashboard)
struct LeftColumnView: View {
    @EnvironmentObject var appContext: AppContext
    @ObservedObject var mcpConfigManager = MCPConfigManager.shared
    @State private var expandedStepIds: Set<UUID> = []

    var body: some View {
        VStack(spacing: 12) {
            
            // 1. Reasoning Trace (EXPANDED SECTION)
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    Text("Reasoning Trace")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                        .textCase(.uppercase)
                    Spacer()
                    Image(systemName: "lines.measurement.horizontal")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.3))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.2))

                // Scrollable Content
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(appContext.reasoningSteps) { step in
                                ReasoningStepRow(
                                    step: step,
                                    isExpanded: expandedStepIds.contains(step.id)
                                ) {
                                    toggleExpansion(for: step.id)
                                }
                                .id(step.id)
                            }
                        }
                        .padding(10)
                    }
                    // Auto-scroll to bottom when new steps arrive
                    .onChange(of: appContext.reasoningSteps.count) { _ in
                        if let lastId = appContext.reasoningSteps.last?.id {
                            withAnimation { proxy.scrollTo(lastId, anchor: .bottom) }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity) // Fills remaining space
            .background(Color.black.opacity(0.3))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(.white.opacity(0.05), lineWidth: 1)
            )
            
            // 2. Agent Environment (New Useful Widget)
            VStack(alignment: .leading, spacing: 10) {
                Text("Environment")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
                    .textCase(.uppercase)
                
                // Model Info
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.yellow)
                    Text("Gemini 2.5 Flash")
                        .foregroundStyle(.white.opacity(0.9))
                    Spacer()
                    Text("PRO")
                        .font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(4)
                }
                .font(.caption)
                
                Divider().overlay(.white.opacity(0.1))
                
                // Workspace / Context
                HStack {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(.blue)
                    Text("~/Projects/Rong-E")
                        .truncationMode(.middle)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .font(.caption)
                
                // Active MCP Servers Count
                HStack {
                    Image(systemName: "hammer.fill")
                        .foregroundStyle(.orange)
                    Text("MCP Servers")
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Text("\(mcpConfigManager.connectedServerCount) Active")
                        .foregroundStyle(mcpConfigManager.connectedServerCount > 0 ? .green : .gray)
                        .fontWeight(.medium)
                }
                .font(.caption)
            }
            .padding(14)
            .background(Color.black.opacity(0.3))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(.white.opacity(0.05), lineWidth: 1)
            )
        }
        .frame(width: 240) // Slightly widened for better reading
        .padding(.vertical, 12)
        .padding(.leading, 12)
    }

    private func toggleExpansion(for id: UUID) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            if expandedStepIds.contains(id) {
                expandedStepIds.remove(id)
            } else {
                expandedStepIds.insert(id)
            }
        }
    }
}

// MARK: - Helper Views

// A compact Ring chart for CPU/Mem
struct MetricRing: View {
    let label: String
    let value: Double // 0.0 to 1.0
    let color: Color
    
    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: value)
                    .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
                Text("\(Int(value * 100))%")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Reasoning Step Row
struct ReasoningStepRow: View {
    let step: ReasoningStep
    let isExpanded: Bool
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                // Status Icon
                statusIcon(for: step.status)
                    .padding(.top, 2)

                // Description
                Text(step.description)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.9))

                Spacer()

                // Expand/collapse indicator if details exist
                if step.details != nil {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if step.details != nil {
                    onTap()
                }
            }

            // Expandable details section
            if isExpanded, let details = step.details {
                Text(details)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.leading, 20)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(8)
            }
        }
    }

    @ViewBuilder
    private func statusIcon(for status: ReasoningStep.StepStatus) -> some View {
        switch status {
        case .completed:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
        case .active:
            ZStack {
                Circle().stroke(Color.cyan, lineWidth: 2).frame(width: 10, height: 10)
                Circle().fill(Color.cyan).frame(width: 4, height: 4)
            }
        case .pending:
            Circle().stroke(Color.white.opacity(0.2), lineWidth: 1).frame(width: 10, height: 10)
        }
    }
}

// MARK: - Main Column (Chat & Response)
struct MainColumnView: View {
    // Pass state from MainView
    @Binding var inputText: String
    @Binding var fullChatViewMode: Bool

    @EnvironmentObject var appContext: AppContext
    var onSubmit: () -> Void
    
    private let hudCyan = Color(red: 0.0, green: 0.9, blue: 1.0)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                // Mode Indicator
                Text("\(appContext.modes.first(where: { $0.id == Int(appContext.currentMode.id) })?.name ?? "Default Mode") MODE")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()

                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        appContext.toggleCurrentModeVision()
                    }
                }) {
                    HStack(spacing: 4) {
                        ZStack {
                            Rectangle()
                                .stroke(appContext.currentMode.isScreenshotEnabled ? hudCyan : Color.white.opacity(0.3), lineWidth: 0.8)
                                .frame(width: 10, height: 10)
                            
                            if appContext.currentMode.isScreenshotEnabled {
                                Rectangle()
                                    .fill(hudCyan)
                                    .frame(width: 5, height: 5)
                                    .shadow(color: hudCyan, radius: 3)
                            }
                        }
                        
                        Text(appContext.currentMode.isScreenshotEnabled ? "VISION: ON" : "VISION: OFF")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(appContext.currentMode.isScreenshotEnabled ? hudCyan : Color.white.opacity(0.5))
                        
                        Image(systemName: "viewfinder")
                            .font(.system(size: 8))
                            .foregroundStyle(appContext.currentMode.isScreenshotEnabled ? hudCyan : Color.white.opacity(0.3))
                    }
                    .padding(.vertical, 3)
                    .padding(.horizontal, 6)
                    .background(appContext.currentMode.isScreenshotEnabled ? hudCyan.opacity(0.1) : Color.clear)
                    .cornerRadius(3)
                }
                .buttonStyle(.plain)

                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        fullChatViewMode.toggle()
                    }
                }) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(hudCyan.opacity(0.5), lineWidth: 0.8)
                            .background(Color.black.opacity(0.1))
                            .frame(width: 26, height: 26)
                        
                        Image(systemName: fullChatViewMode ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(hudCyan)
                    }
                }
                .buttonStyle(.plain)
            }
            .frame(height: 30) // Placeholder for potential header content
            .padding(10)
            
            Spacer()
                .frame(height: fullChatViewMode ? 10 : 80)

            ChatView(fullChatViewMode: $fullChatViewMode)
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .opacity
                ))

            Spacer()
                .frame(height: 5)
            
            // 4. Input Field (Bottom)
            InputAreaView(inputText: $inputText, onSubmit: onSubmit)
                .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.35), value: fullChatViewMode)
        .backgroundColor(Color.black.opacity(0.5))
        .cornerRadius(24)
    }
}

struct InputAreaView: View {
    @Binding var inputText: String
    var onSubmit: () -> Void
    
    // Aesthetic Constants
    private let hudCyan = Color(red: 0.0, green: 0.9, blue: 1.0)
    private let hudDark = Color.black.opacity(0.8)

    var body: some View {
        HStack(spacing: 16) {
            
            // MARK: - Text Field Container
            HStack(spacing: 10) {
                // Tech decor: Blinking cursor prompt or static icon
                Image(systemName: "terminal.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(hudCyan)
                    .shadow(color: hudCyan, radius: 4)
                
                TextField("COMMAND...", text: $inputText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .medium, design: .monospaced)) // Tech font
                    .foregroundStyle(.white)
                    .accentColor(hudCyan)
                    .submitLabel(.send)
                    .onSubmit {
                        onSubmit()
                    }
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 20)
            .background(
                ZStack {
                    // 1. Dark Glass Background
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                        .opacity(0.1)
                    
                    // 2. Dark Fill
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.6))
                    
                    // 3. Glowing Border
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            LinearGradient(
                                colors: [hudCyan.opacity(0.6), hudCyan.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                        .shadow(color: hudCyan.opacity(0.5), radius: 8, x: 0, y: 0)
                }
            )
            
            // MARK: - Action Button (Reactor Core Style)
            Button(action: onSubmit) {
                ZStack {
                    // Outer Ring
                    Circle()
                        .stroke(hudCyan.opacity(0.3), lineWidth: 2)
                        .frame(width: 50, height: 50)
                    
                    // Rotating/Active Ring (Visual flair)
                    Circle()
                        .trim(from: 0, to: 0.7)
                        .stroke(hudCyan, style: StrokeStyle(lineWidth: 2, lineCap: .butt))
                        .frame(width: 50, height: 50)
                        .rotationEffect(.degrees(inputText.isEmpty ? 0 : 360))
                        .animation(inputText.isEmpty ? .default : .linear(duration: 2).repeatForever(autoreverses: false), value: inputText.isEmpty)
                    
                    // Inner Core
                    Circle()
                        .fill(inputText.isEmpty ? Color.clear : hudCyan.opacity(0.2))
                        .frame(width: 40, height: 40)
                    
                    // Icon
                    Image(systemName: inputText.isEmpty ? "mic.fill" : "arrow.up")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundStyle(hudCyan)
                        .shadow(color: hudCyan, radius: inputText.isEmpty ? 0 : 10)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.bottom, 10)
    }
}

struct RongERing: View {
    // We can keep ThemeManager if you need it for other things, 
    // but here we define specific light blue colors for the glow effect.
    @EnvironmentObject var themeManager: ThemeManager 
    
    @State private var pulse = false
    @State private var rotate = false
    
    // Define custom light blue colors
    let lightBlueGlow = Color(red: 0.2, green: 0.85, blue: 1.0) // Cyan-ish
    let deepBlue = Color(red: 0.0, green: 0.5, blue: 1.0)       // Standard Blue
    
    var body: some View {
        ZStack {
            // 1. Outer Ambient Glow (The "Atmosphere")
            Circle()
                .fill(lightBlueGlow.opacity(pulse ? 0.4 : 0.1))
                .frame(width: 130, height: 130)
                .blur(radius: 20)
                .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: pulse)
            
            // 2. Rotating Outer Ring (With Angular Gradient for motion effect)
            Circle()
                .trim(from: 0.0, to: 0.75) // Not a full circle makes rotation visible
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [lightBlueGlow.opacity(0), lightBlueGlow]),
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .frame(width: 110, height: 110)
                .rotationEffect(.degrees(rotate ? 360 : 0))
                .animation(.linear(duration: 3).repeatForever(autoreverses: false), value: rotate)
            
            // 3. Static Thin Ring
            Circle()
                .stroke(lightBlueGlow.opacity(0.3), lineWidth: 1)
                .frame(width: 95, height: 95)
            
            // 4. Main Button Orb
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color.white.opacity(0.8), // Hot center
                            lightBlueGlow,            // Bright Blue body
                            deepBlue                  // Darker edges for 3D depth
                        ]),
                        center: .center,
                        startRadius: 0,
                        endRadius: 50
                    )
                )
                .frame(width: 80, height: 80)
                // Strong Glow Shadow
                .shadow(color: lightBlueGlow.opacity(0.8), radius: pulse ? 25 : 15)
                .shadow(color: deepBlue.opacity(0.5), radius: 5)
                .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: pulse)
            
            // 5. Glossy Reflection (Top Left) - Makes it look like glass/button
            Circle()
                .trim(from: 0.6, to: 0.9)
                .stroke(Color.white.opacity(0.6), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 70, height: 70)
                .blur(radius: 1)
                .rotationEffect(.degrees(-45))
        }
        .onAppear {
            pulse = true
            rotate = true
        }
    }
}

struct ChatView: View {
    @EnvironmentObject var appContext: AppContext
    @Binding var fullChatViewMode: Bool
    
    // Theme Colors
    private let hudCyan = Color(red: 0.0, green: 0.9, blue: 1.0)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // MARK: - Logs / Content
            MessageView(fullChatViewMode: $fullChatViewMode)
                .environmentObject(appContext)
                .background(Color.clear) // Completely clear background for messages
                .cornerRadius(8)
            
        }
        .scaleEffect(fullChatViewMode ? 1.0 : 0.98)
        .opacity(fullChatViewMode ? 1.0 : 0.95)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: fullChatViewMode)
        .transition(.scale.combined(with: .opacity))
    }
}

struct MinimizedMessageView: View {
    @Binding var inputText: String
    @Binding var showMinimizedMessageView: Bool
    var onSubmit: () -> Void

    @EnvironmentObject var appContext: AppContext
    
    // Theme Colors
    private let hudCyan = Color(red: 0.0, green: 0.9, blue: 1.0)
    
    var body: some View {
        VStack(spacing: 0) { 
            
            // MARK: - Header
            HStack {
                Rectangle()
                    .fill(hudCyan)
                    .frame(width: 4, height: 14)
                
                Text("RONG-E CHAT") 
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(hudCyan)
                    .shadow(color: hudCyan.opacity(0.5), radius: 5)
                
                Spacer()
                
                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        showMinimizedMessageView = false
                    }
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(hudCyan)
                        .padding(8)
                        .background(Color.black.opacity(0.01)) // Almost invisible tap area
                        .clipShape(Circle())
                        .overlay(Circle().stroke(hudCyan.opacity(0.5), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 12)

            // MARK: - Message Area
            MessageView(fullChatViewMode: .constant(true))
                .environmentObject(appContext)
                .frame(width: 300, height: 200)
                .background(Color.clear) // Clear background for messages
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.05), lineWidth: 0.5)
                )
            
            // MARK: - Mode & Vision Controls
            HStack {
                Text("MODE: \(appContext.currentMode.name.uppercased())")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.5))
                
                Spacer()
                
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        appContext.toggleCurrentModeVision()
                    }
                }) {
                    HStack(spacing: 6) {
                        ZStack {
                            Rectangle()
                                .stroke(appContext.currentMode.isScreenshotEnabled ? hudCyan : Color.white.opacity(0.3), lineWidth: 1)
                                .frame(width: 12, height: 12)
                            
                            if appContext.currentMode.isScreenshotEnabled {
                                Rectangle()
                                    .fill(hudCyan)
                                    .frame(width: 6, height: 6)
                                    .shadow(color: hudCyan, radius: 4)
                            }
                        }
                        
                        Text(appContext.currentMode.isScreenshotEnabled ? "VISION: ON" : "VISION: OFF")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(appContext.currentMode.isScreenshotEnabled ? hudCyan : Color.white.opacity(0.5))
                        
                        Image(systemName: "viewfinder")
                            .font(.system(size: 10))
                            .foregroundStyle(appContext.currentMode.isScreenshotEnabled ? hudCyan : Color.white.opacity(0.3))
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(appContext.currentMode.isScreenshotEnabled ? hudCyan.opacity(0.1) : Color.clear)
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            
            // MARK: - Input Area
            InputAreaView(inputText: $inputText, onSubmit: onSubmit)
        }
        .padding(16)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.black.opacity(0.6)) // Adjust opacity for desired transparency
                
                // 2. High-Tech Border (Keeps layout defined without solid background)
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                appContext.currentMode.isScreenshotEnabled ? hudCyan.opacity(0.8) : hudCyan.opacity(0.4),
                                hudCyan.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        // Removed heavy shadow to feel lighter/transparent
        .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
    }
}

// MARK: - Main Message View
struct MessageView: View {
    @EnvironmentObject var appContext: AppContext
    @Binding var fullChatViewMode: Bool
    
    // State
    @State private var systemLogs: [String] = []
    @State private var hasBootAnimated = false
    
    // RongE Themed Boot Sequence
    private let bootLogs: [String] = [
        "INTERFACE INITIALIZED",
        "LOADING: INTAKE PIPELINE...",
        "LOADING: RETRIEVAL CORE...",
        "LOADING: VISION MODULES...",
        "ESTABLISHING SECURE LINK...",
        "CONNECTION: STABLE",
        "MODEL: GEMINI 2.5 FLASH LITE",
        "STATUS: ONLINE"
    ]
    
    var body: some View {
        ZStack {
            // 1. Futuristic Background
            RongEBackground()
            
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        
                        // 2. HUD Initialization Logs (Styled as System Alerts)
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(systemLogs, id: \.self) { log in
                                Text(">> \(log)")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.cyan.opacity(0.7))
                                    .shadow(color: .cyan, radius: 2)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 10)
                        
                        // 3. Dynamic Chat Stream
                        ForEach(appContext.currentSessionChatMessages) { message in
                            RongEMessageRow(message: message)
                                .id(message.id)
                                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        }

                        // Spacer for bottom scroll
                        Color.clear
                            .frame(height: 20)
                            .id("bottom")
                    }
                    .padding(.vertical)
                }
                .frame(maxHeight: fullChatViewMode ? 450 : 300)
                // Auto-scroll logic
                .onChange(of: appContext.currentSessionChatMessages.count) { _ in
                    scrollToBottom(proxy, useLastMessage: true)
                }
                .onChange(of: systemLogs.count) { _ in
                    scrollToBottom(proxy, useLastMessage: false)
                }
                .task { await animateBootLogs(proxy: proxy) }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @MainActor
    private func scrollToBottom(_ proxy: ScrollViewProxy, useLastMessage: Bool = false) {
        // Delay slightly to ensure layout is complete before scrolling
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeOut(duration: 0.3)) {
                if useLastMessage, let lastMessage = appContext.currentSessionChatMessages.last {
                    // Scroll to last message first, then to bottom for extra padding
                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                }
                // Always scroll to the bottom spacer to ensure we're at the very end
                proxy.scrollTo("bottom", anchor: .top)
            }
        }
    }

    @MainActor
    private func animateBootLogs(proxy: ScrollViewProxy) async {
        guard !hasBootAnimated else { return }
        hasBootAnimated = true

        for (index, log) in bootLogs.enumerated() {
            let delay = 0.12 + (Double(index) * 0.04) // Faster, tech-like typing
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                systemLogs.append(log)
            }
            scrollToBottom(proxy, useLastMessage: false)
        }
    }
}

// MARK: - RongE Message Row
struct RongEMessageRow: View {
    let message: ChatMessage
    var isUser: Bool { message.role == "user" }

    private func parseMarkdown(_ text: String) -> AttributedString {
        // Replace single newlines with double spaces + newline for markdown
        let markdownText = text.replacingOccurrences(of: "\n", with: "  \n")
        
        // Try to parse as markdown, fallback to plain text if it fails
        if let attributed = try? AttributedString(markdown: markdownText) {
            return attributed
        } else {
            return AttributedString(text)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            
            // AI Avatar / Decorator
            if !isUser {
                // Rong-E Icon
                Image("RongeIcon")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 50, height: 50)
                    .background(Circle().fill(Color.cyan.opacity(0.2)))
                    .shadow(color: Color.cyan.opacity(0.4), radius: 8)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.cyan, lineWidth: 2)
                    )
            } else {
                Spacer()
            }
            
            // Message Bubble
            VStack(alignment: isUser ? .trailing : .leading, spacing: 8) {
                // Header Label
                Text(isUser ? "COMMAND INPUT" : "SYSTEM RESPONSE")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(isUser ? Color.orange.opacity(0.8) : Color.cyan.opacity(0.8))

                // Content
                VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                    ForEach(message.content.components(separatedBy: "\n"), id: \.self) { line in
                        if let attributed = try? AttributedString(markdown: line.isEmpty ? " " : line) {
                            Text(attributed)
                                .font(.system(size: 14, weight: .regular, design: .default))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .padding(12)
                .background(
                    HUDGlassPanel(isAccent: isUser)
                )

                // Widgets (if present)
                if let widgets = message.widgets, !widgets.isEmpty {
                    ChatWidgetsContainer(widgets: widgets)
                        .frame(maxWidth: 280)
                }
            }
            .frame(maxWidth: 280, alignment: isUser ? .trailing : .leading)
            
            // User Decorator (Right side)
            if isUser {
                Circle()
                    .strokeBorder(Color.orange.opacity(0.6), lineWidth: 1.5)
                    .frame(width: 8, height: 8)
                    .padding(.top, 24)
            } else {
                Spacer()
            }
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - UI Components

/// The "Glass" background for bubbles
struct HUDGlassPanel: View {
    var isAccent: Bool

    var body: some View {
        ZStack {
            // Translucent filling
            Color.black.opacity(0.2)

            // Tech Borders
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    LinearGradient(
                        colors: isAccent
                            ? [.orange.opacity(0.4), .orange.opacity(0.08)]
                            : [.cyan.opacity(0.4), .cyan.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: isAccent ? .orange.opacity(0.08) : .cyan.opacity(0.1), radius: 6)
    }
}

/// The spinning arc icon for the AI
struct RongEAvatarIcon: View {
    @State private var rotate = false
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.cyan.opacity(0.3), lineWidth: 1)
                .frame(width: 24, height: 24)
            
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(Color.cyan, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .frame(width: 18, height: 18)
                .rotationEffect(.degrees(rotate ? 360 : 0))
                .animation(.linear(duration: 4).repeatForever(autoreverses: false), value: rotate)
            
            Circle()
                .fill(Color.white)
                .frame(width: 3, height: 3)
                .shadow(color: .white, radius: 2)
        }
        .onAppear { rotate = true }
    }
}

/// Background Mesh/Grid
struct RongEBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.08, green: 0.10, blue: 0.14) // Lighter sci-fi blue

            // Grid Lines
            GeometryReader { geo in
                Path { path in
                    let step: CGFloat = 40
                    for y in stride(from: 0, to: geo.size.height, by: step) {
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geo.size.width, y: y))
                    }
                }
                .stroke(Color.cyan.opacity(0.03), lineWidth: 1)
            }

            // Vignette
            RadialGradient(
                colors: [.clear, .black.opacity(0.4)],
                center: .center,
                startRadius: 100,
                endRadius: 400
            )
        }
        .ignoresSafeArea()
        .opacity(0.5)
    }
}

// MARK: - Top Header
struct HeaderView: View {
    @EnvironmentObject var appContext: AppContext
    @EnvironmentObject var windowCoordinator: WindowCoordinator
    @EnvironmentObject var workflowManager: WorkflowManager
    @EnvironmentObject var googleAuthManager: GoogleAuthManager
    @EnvironmentObject var socketClient: SocketClient
    @EnvironmentObject var themeManager: ThemeManager

    let toggleMinimized: () -> Void
    
    @State private var googleHovering = false
    @State private var workflowHovering = false
    @State private var settingsHovering = false
    @State private var shrinkHovering = false

    var body: some View {
        HStack {
            Text("Rong-E System")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 3, x: 0, y: 2)
            
            Spacer()
            
            Text("v1.0.0 Beta")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 3, x: 0, y: 2)
            
            Spacer()

            // Google Service Button
            Button(action: {
                windowCoordinator.openGoogleService()
            }) {
                ZStack {
                    Color.white.opacity(googleHovering ? 0.25 : 0.15)
                        .cornerRadius(8)
                    
                    Image(systemName: "cloud.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 32, height: 32)
                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                .scaleEffect(googleHovering ? 1.1 : 1.0)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) {
                    googleHovering = hovering
                }
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .contentShape(Rectangle())
            .zIndex(10)

            // Workflow Settings Button
            Button(action: {
                windowCoordinator.openWorkflowSettings()
            }) {
                ZStack {
                    Color.white.opacity(workflowHovering ? 0.25 : 0.15)
                        .cornerRadius(8)

                    Image(systemName: "list.bullet.clipboard.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 32, height: 32)
                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                .scaleEffect(workflowHovering ? 1.1 : 1.0)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) {
                    workflowHovering = hovering
                }
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .contentShape(Rectangle())
            .zIndex(10)

            // Settings Button
            Button(action: {
                windowCoordinator.openSettings()
            }) {
                ZStack {
                    Color.white.opacity(settingsHovering ? 0.25 : 0.15)
                        .cornerRadius(8)
                    
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 32, height: 32)
                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                .scaleEffect(settingsHovering ? 1.1 : 1.0)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) {
                    settingsHovering = hovering
                }
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .contentShape(Rectangle())
            .zIndex(10)
            
            // Shrink Button
            Button(action: {
                toggleMinimized()
            }) {
                ZStack {
                    Color.white.opacity(shrinkHovering ? 0.9 : 1.0)
                        .cornerRadius(8)
                    
                    Image(systemName: "minus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(shrinkHovering ? .black : .black)
                }
                .frame(width: 32, height: 32)
                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                .scaleEffect(shrinkHovering ? 1.1 : 1.0)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) {
                    shrinkHovering = hovering
                }
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .contentShape(Rectangle())
            .zIndex(10)
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - Waveform Animation
struct WaveformBar: View {
    @State private var phase: CGFloat = 0
    
    var body: some View {
        ZStack {
            // Main white glowing line
            Capsule()
                .fill(LinearGradient(colors: [.clear, .cyan, .clear], startPoint: .leading, endPoint: .trailing))
                .frame(height: 2)
                .padding(.horizontal, 20)
                .blur(radius: 2)
                .opacity(0.3)
            
            // Vertical Bars
            HStack(spacing: 5) {
                ForEach(0..<45, id: \.self) { i in
                    WaveformBarItem(index: i, phase: phase)
                }
            }
        }
        .frame(height: 60)
        .onAppear {
            // Start continuous animation with timer
            Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
                phase += 0.5
            }
        }
    }
}

// Helper view to break down complex expression
struct WaveformBarItem: View {
    let index: Int
    let phase: CGFloat
    
    var body: some View {
        Capsule()
            .fill(LinearGradient(colors: [.cyan, .white], startPoint: .bottom, endPoint: .top))
            .frame(width: 3, height: getHeight())
            .opacity(0.35 + Darwin.sin(Double(phase) + Double(index) * 0.3) * 0.2)
            .shadow(color: .cyan.opacity(0.2), radius: 4, x: 0, y: 0)
    }
    
    private func getHeight() -> CGFloat {
        let center = 22.0
        let dist = abs(Double(index) - center)
        
        // Bell curve base
        let baseHeight = max(8.0, 50.0 - (dist * 1.8))
        
        // Animated waves using Darwin math functions
        let wave1 = Darwin.sin(Double(phase) * 0.8 + Double(index) * 0.4) * 12.0
        let wave2 = Darwin.cos(Double(phase) * 1.2 + Double(index) * 0.2) * 8.0
        let wave3 = Darwin.sin(Double(phase) * 0.5 + Double(index) * 0.15) * 15.0
        
        return CGFloat(max(4.0, baseHeight + wave1 + wave2 + wave3))
    }
}

extension NSTextField {
    open override var focusRingType: NSFocusRingType {
        get { .none }
        set { }
    }
}
