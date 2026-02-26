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

    // 2. Server Loading State
    @ObservedObject private var serverManager = ServerManager.shared

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

    // Computed property to check if server is ready (process running AND WebSocket connected)
    private var isServerReady: Bool {
        serverManager.status == .running && socketClient.isConnected
    }

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

    func toggleMessageView() {
        if minimizedMode {
            // Already minimized - expand back (toggleMinimized will hide the message view)
            toggleMinimized()
        } else {
            // Currently expanded - minimize first, then show message view after animation
            toggleMinimized()
            self.setShowMinimizedMessageView(true)
        }
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
        Group {
            if isServerReady {
                mainContent
            } else {
                AgentLoadingView(
                    serverStatus: serverManager.status,
                    isConnected: socketClient.isConnected,
                    connectionFailed: socketClient.connectionFailed,
                    onRetry: {
                        socketClient.retryConnection()
                    }
                )
            }
        }
        .onAppear {
            // Initialize connections and auth
            setUpConnection()

            // Only toggle minimized when server is ready
            if isServerReady {
                toggleMinimized()
            }
        }
        .onChange(of: socketClient.isConnected) { isConnected in
            // Trigger main content animations when WebSocket connects (and server is running)
            if isConnected && serverManager.status == .running {
                toggleMinimized()
                // Transition from "Starting up" to "Await input"
                for i in appContext.reasoningSteps.indices {
                    if appContext.reasoningSteps[i].status == .active {
                        appContext.reasoningSteps[i].status = .completed
                    }
                }
                appContext.reasoningSteps.append(ReasoningStep(description: "Await input", status: .active))
            }
        }
    }

    // MARK: - Main Content View
    private var mainContent: some View {
        ZStack(alignment: .bottom) { // Align bottom to help with positioning
            // --- CLOCK LAYER ---
            // Fades out when minimized
            VStack(spacing: 0) { // 1. Remove spacing between Time and Greeting
                Spacer().frame(height: 80) // Top Spacer for better vertical alignment

                // Time Display (Dynamic)
                Text(Date(), style: .time)
                    .font(JarvisFont.display)
                    .foregroundStyle(Color.jarvisTextPrimary)
                    .shadow(color: .white, radius: 10)

                Text("Good \(getGreeting()), \(appContext.userName.components(separatedBy: " ").first ?? appContext.userName)!") // Good Morning/Afternoon/Evening Greeting
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.jarvisTextSecondary)

                Spacer()
            }
            .frame(width: JarvisDimension.expandedWidth, height: JarvisDimension.expandedHeight)
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
                    minimizedMode: minimizedMode,
                    toggleMinimized: toggleMinimized,
                    toggleMessages: { setShowMinimizedMessageView(!showMinimizedMessageView) },
                    onHoverChange: setShowMinimizedButtons
                )
            }

            // --- MAIN GLASS CONTAINER ---
            ZStack(alignment: .bottom) {
                // Content Layer (Header + Columns) — removed from layout when minimized
                if !minimizedMode {
                    VStack(spacing: 0) {
                        HeaderView(toggleMinimized: toggleMinimized, toggleMessageView: toggleMessageView)
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
                                .allowsHitTesting(false)
                        )
                    }
                    .transition(.opacity)
                } else {
                    RongERing()
                        .scaleEffect(0.6)
                }
            }
            // MARK: - Frame Animation Logic
            .frame(
                width: minimizedMode ? JarvisDimension.minimizedSize : JarvisDimension.expandedWidth,
                height: minimizedMode ? JarvisDimension.minimizedSize : JarvisDimension.expandedHeight
            )
            .background(
                ZStack {
                    if !minimizedMode {
                        // 1. Base Tint (Very Low Opacity for "See-Through")
                        RoundedRectangle(cornerRadius: JarvisRadius.pill)
                            .fill(Color.jarvisSurface)

                        // 2. High-Tech Border (Keeps layout defined without solid background)
                        RoundedRectangle(cornerRadius: JarvisRadius.pill)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        appContext.currentMode.isScreenshotEnabled ? Color.jarvisCyan.opacity(0.8) : Color.jarvisCyan.opacity(0.4),
                                        Color.jarvisCyan.opacity(0.05)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    } else {
                        // Minimized Mode Background
                        RoundedRectangle(cornerRadius: JarvisRadius.pill)
                            .fill(Color.jarvisSurfaceDark)
                            .shadow(color: Color.jarvisCyan.opacity(0.4), radius: 10)
                    }
                }
            )
            // Corner radius becomes pill to make a perfect circle
            .cornerRadius(JarvisRadius.pill)

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
                    MinimizedMessageView(inputText: $inputText, showMinimizedMessageView: $showMinimizedMessageView, onSubmit: submitQuery, toggleMessageView: toggleMessageView)
                        .environmentObject(appContext)
                        .offset(y: -110)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
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
            self.isProcessing = true
            self.activeTool = thoughtText.uppercased()

            self.appContext.reasoningSteps.append(
                ReasoningStep(description: thoughtText, status: .active)
            )
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
                    .environmentObject(windowCoordinator)
                    .frame(width: 600, height: 400)
                    .padding()
                    .background(Color.black.opacity(0.6))
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
            // Refresh active tools list after MCP status changes
            socketClient.sendToolsRequest()
        }

        socketClient.onReceiveActiveTools = { tools in
            appContext.activeTools = tools
        }

        socketClient.onDisconnect = { errorText in
            withAnimation {
                self.isProcessing = false
                self.activeTool = nil
            }
            print("⚠️ Socket disconnected: \(errorText)")
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

            let modeSystemPrompt = appContext.currentMode.systemPrompt.isEmpty ? nil : appContext.currentMode.systemPrompt
            let userName = appContext.userName.isEmpty ? nil : appContext.userName
            socketClient.sendMessageWithImage(query, mode: selectedMode, base64Image: base64Image, systemPrompt: modeSystemPrompt, userName: userName)
            
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
                    let modeSystemPrompt = appContext.currentMode.systemPrompt.isEmpty ? nil : appContext.currentMode.systemPrompt
                    let userName = appContext.userName.isEmpty ? nil : appContext.userName
                    socketClient.sendMessage(query, mode: mode, systemPrompt: modeSystemPrompt, userName: userName)

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

            // Mark active steps completed, append await input
            for i in appContext.reasoningSteps.indices {
                if appContext.reasoningSteps[i].status == .active {
                    appContext.reasoningSteps[i].status = .completed
                }
            }
            appContext.reasoningSteps.append(ReasoningStep(description: "Await input", status: .active))
        }
    }

    private func submitQuery() {
        guard !inputText.isEmpty else { return }

        let query = inputText
        let selectedMode = appContext.currentMode.name.lowercased()
        inputText = ""
        isProcessing = true
        inputMode = false
        appContext.response = ""

        // Mark previous active steps as completed, keep history
        for i in appContext.reasoningSteps.indices {
            if appContext.reasoningSteps[i].status == .active {
                appContext.reasoningSteps[i].status = .completed
            }
        }
        appContext.reasoningSteps.append(ReasoningStep(description: "Processing query", status: .active))

        // append user message to chat history
        appContext.currentSessionChatMessages.append(ChatMessage(role: "user", content: query))

        let modeSystemPrompt = appContext.currentMode.systemPrompt.isEmpty ? nil : appContext.currentMode.systemPrompt
        let userName = appContext.userName.isEmpty ? nil : appContext.userName

        if appContext.modes.first(where: { $0.name == appContext.modes.first(where: { $0.id == Int(currentMode.suffix(1)) })?.name })?.isScreenshotEnabled == true {
            print("📸 Screenshot tool is enabled for this mode. Capturing screenshot...")
            captureAndSendWithScreenshot(query: query, selectedMode: selectedMode)
        } else {
            print("ℹ️ Screenshot tool is NOT enabled for this mode. Sending query without screenshot.")
            socketClient.sendMessage(query, mode: selectedMode, systemPrompt: modeSystemPrompt, userName: userName)
            self.activeTool = "WS_STREAM"
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
    let minimizedMode: Bool
    let toggleMinimized: () -> Void
    let toggleMessages: () -> Void
    let onHoverChange: (Bool) -> Void

    // Configuration
    private let radius: CGFloat = 70

    var body: some View {
        ZStack {
            // Left: Messages (-45°)
            OrbiterButton(
                icon: "message.fill",
                action: toggleMessages,
                angle: -45,
                radius: radius,
                hudCyan: .jarvisCyan
            )

            // Center: Minimize (0°)
            OrbiterButton(
                icon: minimizedMode ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left",
                action: toggleMinimized,
                angle: 0,
                radius: radius,
                hudCyan: .jarvisCyan
            )

            // Right: Quit (+45°)
            OrbiterButton(
                icon: "xmark",
                action: { NSApplication.shared.terminate(nil) },
                angle: 45,
                radius: radius,
                hudCyan: .jarvisRed
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
                        .fill(Color.jarvisSurfaceDeep)
                    
                    // Stroke (Reacts to Hover)
                    Circle()
                        .stroke(
                            isActive || isHovering ? hudCyan : Color.jarvisTextDim,
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
    @EnvironmentObject var socketClient: SocketClient
    @ObservedObject var mcpConfigManager = MCPConfigManager.shared
    @State private var expandedStepIds: Set<UUID> = []

    var body: some View {
        VStack(spacing: 12) {
            
            // 1. Reasoning Trace (EXPANDED SECTION)
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    Text("Reasoning Trace")
                        .modifier(JarvisSectionHeader())
                    Spacer()
                    Image(systemName: "lines.measurement.horizontal")
                        .font(.caption2)
                        .foregroundStyle(Color.jarvisTextDim)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.jarvisSurfaceLight)

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
            .background(Color.jarvisSurfaceLight)
            .cornerRadius(JarvisRadius.card)
            .overlay(
                RoundedRectangle(cornerRadius: JarvisRadius.card)
                    .stroke(Color.jarvisBorder, lineWidth: 1)
            )
            
            // 2. Agent Environment (New Useful Widget)
            VStack(alignment: .leading, spacing: 10) {
                Text("Environment")
                    .font(JarvisFont.captionMono)
                    .foregroundStyle(Color.jarvisTextDim)
                    .textCase(.uppercase)
                
                // Model Info
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.yellow)
                    Text(appContext.llmProvider.displayName)
                        .foregroundStyle(Color.jarvisTextSecondary)
                    Spacer()
                    Text(appContext.llmModel)
                        .font(JarvisFont.tag)
                        .padding(.horizontal, JarvisSpacing.xs)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(JarvisRadius.small)
                }
                .font(.caption)
                
                Divider().overlay(Color.jarvisBorder)
                
                // Active MCP Servers Count
                HStack {
                    Image(systemName: "hammer.fill")
                        .foregroundStyle(Color.jarvisOrange)
                    Text("MCP Servers")
                        .foregroundStyle(Color.jarvisTextSecondary)
                    Spacer()
                    Text("\(mcpConfigManager.connectedServerCount) Active")
                        .foregroundStyle(mcpConfigManager.connectedServerCount > 0 ? Color.jarvisGreen : .gray)
                        .fontWeight(.medium)
                }
                .font(.caption)
            }
            .padding(14)
            .background(Color.jarvisSurfaceLight)
            .cornerRadius(JarvisRadius.card)
            .overlay(
                RoundedRectangle(cornerRadius: JarvisRadius.card)
                    .stroke(Color.jarvisBorder, lineWidth: 1)
            )

            // 3. Active Tools
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Active Tools")
                        .modifier(JarvisSectionHeader())
                    Spacer()
                    Text("\(appContext.activeTools.count)")
                        .font(JarvisFont.captionMono)
                        .foregroundStyle(Color.jarvisCyan.opacity(0.7))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.jarvisSurfaceLight)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        if appContext.activeTools.isEmpty {
                            Text("No tools loaded")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.jarvisTextDim)
                                .padding(.horizontal, 10)
                        } else {
                            // Group tools by source
                            let grouped = Dictionary(grouping: appContext.activeTools, by: { $0.source })
                            let sortedKeys = grouped.keys.sorted { a, b in
                                if a == "base" { return true }
                                if b == "base" { return false }
                                return a < b
                            }
                            ForEach(sortedKeys, id: \.self) { source in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(source == "base" ? "BASE" : source.uppercased())
                                        .font(JarvisFont.tag)
                                        .foregroundStyle(source == "base" ? Color.jarvisCyan.opacity(0.5) : Color.jarvisOrange.opacity(0.5))
                                        .padding(.top, JarvisSpacing.xs)

                                    ForEach(grouped[source] ?? [], id: \.name) { tool in
                                        HStack(spacing: 6) {
                                            Circle()
                                                .fill(source == "base" ? Color.jarvisCyan : Color.jarvisOrange)
                                                .frame(width: 5, height: 5)
                                            Text(tool.name)
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundStyle(Color.jarvisTextSecondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(10)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: 140)
            .background(Color.jarvisSurfaceLight)
            .cornerRadius(JarvisRadius.card)
            .overlay(
                RoundedRectangle(cornerRadius: JarvisRadius.card)
                    .stroke(Color.jarvisBorder, lineWidth: 1)
            )
        }
        .frame(width: JarvisDimension.leftColumnWidth) // Slightly widened for better reading
        .padding(.vertical, 12)
        .padding(.leading, 12)
        .onAppear {
            socketClient.sendToolsRequest()
        }
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
                    .foregroundStyle(Color.jarvisTextSecondary)

                Spacer()

                // Expand/collapse indicator if details exist
                if step.details != nil {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(Color.jarvisTextTertiary)
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
                    .foregroundStyle(Color.jarvisTextTertiary)
                    .padding(.leading, 20)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(JarvisRadius.medium)
            }
        }
    }

    @ViewBuilder
    private func statusIcon(for status: ReasoningStep.StepStatus) -> some View {
        switch status {
        case .completed:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.jarvisGreen).font(.caption)
        case .active:
            ZStack {
                Circle().stroke(Color.jarvisCyan, lineWidth: 2).frame(width: 10, height: 10)
                Circle().fill(Color.jarvisCyan).frame(width: 4, height: 4)
            }
        case .pending:
            Circle().stroke(Color.jarvisTextDim, lineWidth: 1).frame(width: 10, height: 10)
        }
    }
}

// MARK: - Mode Bar (isolated to avoid re-rendering input on appContext changes)
struct ModeBarView: View {
    @Binding var fullChatViewMode: Bool
    @EnvironmentObject var appContext: AppContext

    var body: some View {
        HStack {
            // Mode Selector
            Menu {
                ForEach(appContext.modes) { mode in
                    Button(action: {
                        appContext.currentModeId = mode.id
                        appContext.saveSettings()
                    }) {
                        if mode.id == appContext.currentModeId {
                            Label(mode.name, systemImage: "checkmark")
                        } else {
                            Text(mode.name)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text("\(appContext.currentMode.name.uppercased()) MODE")
                        .font(JarvisFont.monoSmall)
                        .foregroundStyle(Color.jarvisTextTertiary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8))
                        .foregroundStyle(Color.jarvisTextDim)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Spacer()

            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    appContext.toggleCurrentModeVision()
                }
            }) {
                HStack(spacing: 4) {
                    ZStack {
                        Rectangle()
                            .stroke(appContext.currentMode.isScreenshotEnabled ? Color.jarvisCyan : Color.jarvisTextDim, lineWidth: 0.8)
                            .frame(width: 10, height: 10)

                        if appContext.currentMode.isScreenshotEnabled {
                            Rectangle()
                                .fill(Color.jarvisCyan)
                                .frame(width: 5, height: 5)
                                .shadow(color: Color.jarvisCyan, radius: 3)
                        }
                    }

                    Text(appContext.currentMode.isScreenshotEnabled ? "VISION: ON" : "VISION: OFF")
                        .font(JarvisFont.tag)
                        .foregroundStyle(appContext.currentMode.isScreenshotEnabled ? Color.jarvisCyan : Color.jarvisTextTertiary)

                    Image(systemName: "viewfinder")
                        .font(.system(size: 8))
                        .foregroundStyle(appContext.currentMode.isScreenshotEnabled ? Color.jarvisCyan : Color.jarvisTextDim)
                }
                .padding(.vertical, 3)
                .padding(.horizontal, 6)
                .background(appContext.currentMode.isScreenshotEnabled ? Color.jarvisCyan.opacity(0.1) : Color.clear)
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
                        .stroke(Color.jarvisCyan.opacity(0.5), lineWidth: 0.8)
                        .background(Color.black.opacity(0.1))
                        .frame(width: 26, height: 26)

                    Image(systemName: fullChatViewMode ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.jarvisCyan)
                }
            }
            .buttonStyle(.plain)
        }
        .frame(height: 30)
        .padding(10)
    }
}

// MARK: - Main Column (Chat & Response)
struct MainColumnView: View {
    // Pass state from MainView
    @Binding var inputText: String
    @Binding var fullChatViewMode: Bool

    var onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ModeBarView(fullChatViewMode: $fullChatViewMode)

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
        .backgroundColor(Color.jarvisSurface)
        .cornerRadius(JarvisRadius.container)
    }
}

struct InputAreaView: View {
    @Binding var inputText: String
    var onSubmit: () -> Void

    @State private var localText: String = "" // Local, fast state

    // Track hasText separately to avoid animation recalculation on every keystroke
    @State private var hasText: Bool = false

    // Aesthetic Constants
    private let hudCyan = Color.jarvisCyan
    private let hudDark = Color.jarvisSurfaceDeep

    var body: some View {
        HStack(spacing: 16) {

            // MARK: - Text Field Container
            HStack(spacing: 10) {
                // Tech decor: Blinking cursor prompt or static icon
                Image(systemName: "terminal.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(hudCyan)
                    .shadow(color: hudCyan, radius: 4)

                TextField("COMMAND...", text: $localText)
                    .textFieldStyle(.plain)
                    .font(JarvisFont.mono)
                    .foregroundStyle(Color.jarvisTextPrimary)
                    .accentColor(hudCyan)
                    .submitLabel(.send)
                    .onSubmit {
                        inputText = localText
                        onSubmit()
                        localText = ""
                    }
                    .onAppear {
                        localText = inputText
                    }
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 20)
            .background(
                ZStack {
                    // 2. Dark Fill
                    RoundedRectangle(cornerRadius: JarvisRadius.large)
                        .fill(Color.jarvisSurfaceDark)

                    // 3. Glowing Border
                    RoundedRectangle(cornerRadius: JarvisRadius.large)
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
            InputActionButton(hasText: hasText, hudCyan: hudCyan, onSubmit: {
                inputText = localText
                onSubmit()
                localText = ""
            })
        }
        .padding(.horizontal)
        .padding(.bottom, 10)
        .onChange(of: localText.isEmpty) { isEmpty in
            // Only update hasText when empty state changes, not on every keystroke
            if hasText == isEmpty {
                hasText = !isEmpty
            }
        }
        .onChange(of: inputText) { newValue in
            // Sync from parent (e.g. when cleared after submit)
            if newValue != localText {
                localText = newValue
            }
        }
    }
}

// Separate button view to isolate animation from text input
struct InputActionButton: View {
    let hasText: Bool
    let hudCyan: Color
    let onSubmit: () -> Void

    var body: some View {
        Button(action: onSubmit) {
            ZStack {
                // Outer Ring
                Circle()
                    .stroke(hudCyan.opacity(0.3), lineWidth: 2)
                    .frame(width: 50, height: 50)

                // Rotating/Active Ring - uses TimelineView for smooth, performant animation
                if hasText {
                    TimelineView(.animation) { timeline in
                        let seconds = timeline.date.timeIntervalSinceReferenceDate
                        let rotation = seconds.truncatingRemainder(dividingBy: 2) * 180 // 180 deg/sec
                        Circle()
                            .trim(from: 0, to: 0.7)
                            .stroke(hudCyan, style: StrokeStyle(lineWidth: 2, lineCap: .butt))
                            .frame(width: 50, height: 50)
                            .rotationEffect(.degrees(rotation))
                    }
                } else {
                    Circle()
                        .trim(from: 0, to: 0.7)
                        .stroke(hudCyan, style: StrokeStyle(lineWidth: 2, lineCap: .butt))
                        .frame(width: 50, height: 50)
                }

                // Inner Core
                Circle()
                    .fill(hasText ? hudCyan.opacity(0.2) : Color.clear)
                    .frame(width: 40, height: 40)

                // Icon
                Image(systemName: "arrow.up")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(hudCyan)
                    .shadow(color: hudCyan, radius: hasText ? 10 : 0)
            }
        }
        .buttonStyle(.plain)
    }
}

struct RongERing: View {
    @State private var pulse = false
    @State private var rotate = false
    
    // Use design system colors
    let lightBlueGlow = Color.jarvisLightBlue
    let deepBlue = Color.jarvisDeepBlue
    
    var body: some View {
        ZStack {
            // 1. Rotating Outer Ring (With Angular Gradient for motion effect)
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

            // 2. Static Thin Ring
            Circle()
                .stroke(lightBlueGlow.opacity(0.3), lineWidth: 1)
                .frame(width: 95, height: 95)

            // 3. Main Button Orb
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

            // 4. Glossy Reflection (Top Left) - Makes it look like glass/button
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            
            // We pass the raw array of messages here.
            // This allows the Equatable check to stop updates if the array hasn't changed.
            EquatabeChatList(
                messages: appContext.currentSessionChatMessages,
                fullChatViewMode: fullChatViewMode
            )
            .environmentObject(appContext) // Pass env object down for assets/theme
            .background(Color.clear)
            .cornerRadius(8)
            
        }
        .scaleEffect(fullChatViewMode ? 1.0 : 0.98)
        .opacity(fullChatViewMode ? 1.0 : 0.95)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: fullChatViewMode)
    }
}

// MARK: - Equatable Chat List (Performance Fix)
struct EquatabeChatList: View, Equatable {
    let messages: [ChatMessage]
    let fullChatViewMode: Bool
    
    // Custom Equality Check
    static func == (lhs: EquatabeChatList, rhs: EquatabeChatList) -> Bool {
        // Only redraw if the message count changes, the last message ID changes, or view mode toggles
        return lhs.messages.count == rhs.messages.count &&
               lhs.messages.last?.id == rhs.messages.last?.id &&
               lhs.fullChatViewMode == rhs.fullChatViewMode
    }
    
    var body: some View {
        MessageListContent(messages: messages, fullChatViewMode: fullChatViewMode)
    }
}
struct MessageListContent: View {
    let messages: [ChatMessage]
    let fullChatViewMode: Bool
    @EnvironmentObject var appContext: AppContext
    
    @State private var systemLogs: [String] = []
    
    var body: some View {
        ZStack {
            RongEBackground()
            
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {

                        // System Logs
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(systemLogs, id: \.self) { log in
                                Text(">> \(log)")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(Color.jarvisCyan.opacity(0.7))
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 10)

                        // Dynamic Chat Stream
                        ForEach(messages) { message in
                            RongEMessageRow(message: message)
                                // The ID is already here, which is perfect
                                .id(message.id) 
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .bottom)),
                                    removal: .opacity
                                ))
                        }
                        
                        // 1. The Anchor Point
                        // A 1-pixel invisible view at the very end of the VStack
                        Color.clear
                            .frame(height: 1)
                            .id("BottomAnchor") 
                    }
                    .padding(.vertical)
                }
                .frame(maxHeight: fullChatViewMode ? 450 : 300)
                
                .onChange(of: messages.last?.content) { _ in 
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: messages.count) { _ in
                    scrollToBottom(proxy: proxy)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: JarvisRadius.card))
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeOut(duration: 0.5)) {
                proxy.scrollTo("BottomAnchor", anchor: .bottom)
            }
        }
    }
}

struct MinimizedMessageView: View {
    @Binding var inputText: String
    @Binding var showMinimizedMessageView: Bool
    var onSubmit: () -> Void
    var toggleMessageView: () -> Void

    @EnvironmentObject var appContext: AppContext
    
    // Theme Colors
    private let hudCyan = Color.jarvisCyan
    
    var body: some View {
        VStack(spacing: 0) { 
            
            // MARK: - Header
            HStack {
                Rectangle()
                    .fill(hudCyan)
                    .frame(width: 4, height: 14)
                
                Text("RONG-E CHAT") 
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.jarvisCyan)
                    .shadow(color: Color.jarvisCyan.opacity(0.5), radius: 5)
                
                Spacer()

                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        toggleMessageView()
                    }
                }) {
                    Image(systemName: "rectangle.compress.vertical")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(hudCyan)
                        .padding(8)
                        .background(Color.black.opacity(0.01)) // Almost invisible tap area
                        .clipShape(Circle())
                        .overlay(Circle().stroke(hudCyan.opacity(0.5), lineWidth: 1))
                }
                .buttonStyle(.plain)
                
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
                    RoundedRectangle(cornerRadius: JarvisRadius.large)
                        .stroke(Color.jarvisBorder, lineWidth: 0.5)
                )
            
            // MARK: - Mode & Vision Controls
            HStack {
                Menu {
                    ForEach(appContext.modes) { mode in
                        Button(action: {
                            appContext.currentModeId = mode.id
                            appContext.saveSettings()
                        }) {
                            if mode.id == appContext.currentModeId {
                                Label(mode.name, systemImage: "checkmark")
                            } else {
                                Text(mode.name)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text("MODE: \(appContext.currentMode.name.uppercased())")
                            .font(JarvisFont.label)
                            .foregroundStyle(Color.jarvisTextTertiary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 7))
                            .foregroundStyle(Color.jarvisTextDim)
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                
                Spacer()
                
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        appContext.toggleCurrentModeVision()
                    }
                }) {
                    HStack(spacing: 6) {
                        ZStack {
                            Rectangle()
                                .stroke(appContext.currentMode.isScreenshotEnabled ? Color.jarvisCyan : Color.jarvisTextDim, lineWidth: 1)
                                .frame(width: 12, height: 12)
                            
                            if appContext.currentMode.isScreenshotEnabled {
                                Rectangle()
                                    .fill(Color.jarvisCyan)
                                    .frame(width: 6, height: 6)
                                    .shadow(color: Color.jarvisCyan, radius: 4)
                            }
                        }
                        
                        Text(appContext.currentMode.isScreenshotEnabled ? "VISION: ON" : "VISION: OFF")
                            .font(JarvisFont.captionMono)
                            .foregroundStyle(appContext.currentMode.isScreenshotEnabled ? Color.jarvisCyan : Color.jarvisTextTertiary)
                        
                        Image(systemName: "viewfinder")
                            .font(.system(size: 10))
                            .foregroundStyle(appContext.currentMode.isScreenshotEnabled ? Color.jarvisCyan : Color.jarvisTextDim)
                    }
                    .padding(.vertical, JarvisSpacing.xs)
                    .padding(.horizontal, JarvisSpacing.sm)
                    .background(appContext.currentMode.isScreenshotEnabled ? Color.jarvisCyan.opacity(0.1) : Color.clear)
                    .cornerRadius(JarvisRadius.small)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            
            // MARK: - Input Area
            InputAreaView(inputText: $inputText, onSubmit: onSubmit)
        }
        .padding(JarvisSpacing.lg)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: JarvisRadius.container)
                    .fill(Color.jarvisSurfaceDark)
                
                // 2. High-Tech Border
                RoundedRectangle(cornerRadius: JarvisRadius.container)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                appContext.currentMode.isScreenshotEnabled ? Color.jarvisCyan.opacity(0.8) : Color.jarvisCyan.opacity(0.4),
                                Color.jarvisCyan.opacity(0.05)
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
    @State private var bootAnimationId = UUID() // Used to re-trigger boot animation

    // RongE Themed Boot Sequence (computed to include current model)
    private var bootLogs: [String] {
        [
            "INTERFACE INITIALIZED",
            "LOADING: INTAKE PIPELINE...",
            "LOADING: RETRIEVAL CORE...",
            "LOADING: VISION MODULES...",
            "ESTABLISHING SECURE LINK...",
            "CONNECTION: STABLE",
            "MODEL: \(appContext.llmProvider.displayName.uppercased()) / \(appContext.llmModel.uppercased())",
            "STATUS: ONLINE"
        ]
    }
    
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
                                    .foregroundStyle(Color.jarvisCyan.opacity(0.7))
                                    .shadow(color: Color.jarvisCyan, radius: 2)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 10)
                        
                        // 3. Dynamic Chat Stream (system boot logs excluded — shown above)
                        ForEach(appContext.currentSessionChatMessages.filter { $0.role != "system" }) { message in
                            EquatableView(content: RongEMessageRow(message: message))
                                .id(message.id)
                                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        }

                        // Spacer for bottom scroll
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .padding(.vertical)
                }
                .frame(maxHeight: fullChatViewMode ? 450 : 300)
                // Auto-scroll logic
                .onChange(of: appContext.currentSessionChatMessages.count) { newCount in
                    if newCount == 0 {
                        // Session was cleared - reset and re-animate boot logs
                        Task { @MainActor in
                            systemLogs = []
                            appContext.hasBootAnimated = false
                            bootAnimationId = UUID() // Trigger re-animation
                        }
                    } else {
                        scrollToBottom(proxy, useLastMessage: true)
                    }
                }
                .onChange(of: systemLogs.count) { _ in
                    scrollToBottom(proxy, useLastMessage: false)
                }
                .task(id: bootAnimationId) { await animateBootLogs(proxy: proxy) }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: JarvisRadius.card))
    }

    @MainActor
    private func scrollToBottom(_ proxy: ScrollViewProxy, useLastMessage: Bool = false) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    @MainActor
    private func animateBootLogs(proxy: ScrollViewProxy) async {
        guard !appContext.hasBootAnimated else { return }
        appContext.hasBootAnimated = true

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
struct RongEMessageRow: View, Equatable {
    let message: ChatMessage
    var isUser: Bool   { message.role == "user" }
    var isSystem: Bool { message.role == "system" }

    static func == (lhs: RongEMessageRow, rhs: RongEMessageRow) -> Bool {
        lhs.message.id == rhs.message.id
    }

    var body: some View {
        if isSystem {
            // Terminal-style boot log: >> LOG TEXT
            HStack(spacing: 6) {
                Text(">>")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.jarvisCyan.opacity(0.5))
                Text(message.content)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.jarvisCyan.opacity(0.7))
                    .shadow(color: Color.jarvisCyan, radius: 1)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 1)
        } else {
        HStack(alignment: .top, spacing: 12) {
            // AI Avatar / Decorator
            if !isUser {
                // Rong-E Icon
                Image("RongeIcon")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 50, height: 50)
                    .background(Circle().fill(Color.jarvisCyan.opacity(0.2)))
                    .shadow(color: Color.jarvisCyan.opacity(0.4), radius: 8)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.jarvisCyan, lineWidth: 2)
                    )
            } else {
                Spacer()
            }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 8) {
                // ... (Header Label code remains the same) ...
                // Header Label
                Text(isUser ? "COMMAND INPUT" : "SYSTEM RESPONSE")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(isUser ? Color.jarvisOrange.opacity(0.8) : Color.jarvisCyan.opacity(0.8))


                // USE THE CACHED ATTRIBUTED STRING
                Text(message.attributedContent) 
                    .font(JarvisFont.body)
                    .foregroundStyle(Color.jarvisTextPrimary)
                    .padding(12)
                    .background(HUDGlassPanel(isAccent: isUser))

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
                    .strokeBorder(Color.jarvisOrange.opacity(0.6), lineWidth: 1.5)
                    .frame(width: 8, height: 8)
                    .padding(.top, 24)
            } else {
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        } // end else (non-system message)
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
            RoundedRectangle(cornerRadius: JarvisRadius.large)
                .strokeBorder(
                    LinearGradient(
                        colors: isAccent
                            ? [Color.jarvisOrange.opacity(0.4), Color.jarvisOrange.opacity(0.08)]
                            : [Color.jarvisCyan.opacity(0.4), Color.jarvisCyan.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: JarvisRadius.large))
        .shadow(color: isAccent ? Color.jarvisOrange.opacity(0.08) : Color.jarvisCyan.opacity(0.1), radius: 6)
    }
}

/// The spinning arc icon for the AI
struct RongEAvatarIcon: View {
    @State private var rotate = false
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.jarvisCyan.opacity(0.3), lineWidth: 1)
                .frame(width: 24, height: 24)
            
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(Color.jarvisCyan, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
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

/// Background
struct RongEBackground: View {
    var body: some View {
        Color.gray.opacity(0.06)
    }
}

// MARK: - Top Header
struct HeaderView: View {
    @EnvironmentObject var appContext: AppContext
    @EnvironmentObject var windowCoordinator: WindowCoordinator
    @EnvironmentObject var workflowManager: WorkflowManager
    @EnvironmentObject var googleAuthManager: GoogleAuthManager
    @EnvironmentObject var socketClient: SocketClient

    @ObservedObject var configManager = MCPConfigManager.shared

    let toggleMinimized: () -> Void

    let toggleMessageView: () -> Void
    
    @State private var googleHovering = false
    @State private var workflowHovering = false
    @State private var settingsHovering = false
    @State private var refreshHovering = false
    @State private var shrinkHovering = false
    @State private var chatMinimizeHovering = false
    @State private var quitHovering = false

    var body: some View {
        HStack {
            Text("Rong-E System")
                .font(JarvisFont.title)
                .foregroundStyle(Color.jarvisTextPrimary)
                .shadow(color: .black.opacity(0.6), radius: 3, x: 0, y: 2)
            
            Spacer()
            
            Text("v1.0.0 Beta")
                .font(JarvisFont.subtitle)
                .foregroundStyle(Color.jarvisTextPrimary)
                .shadow(color: .black.opacity(0.6), radius: 3, x: 0, y: 2)
            
            Spacer()

            // Google Service Button
            Button(action: {
                windowCoordinator.openGoogleService()
            }) {
                ZStack {
                    Color.white.opacity(googleHovering ? 0.25 : 0.15)
                        .cornerRadius(JarvisRadius.medium)
                    
                    Image(systemName: "cloud.fill")
                        .font(JarvisFont.icon)
                        .foregroundStyle(Color.jarvisTextPrimary)
                }
                .modifier(JarvisHeaderButton(isHovered: googleHovering))
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
                        .cornerRadius(JarvisRadius.medium)

                    Image(systemName: "list.bullet.clipboard.fill")
                        .font(JarvisFont.icon)
                        .foregroundStyle(Color.jarvisTextPrimary)
                }
                .modifier(JarvisHeaderButton(isHovered: workflowHovering))
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
                        .cornerRadius(JarvisRadius.medium)
                    
                    Image(systemName: "gearshape.fill")
                        .font(JarvisFont.icon)
                        .foregroundStyle(Color.jarvisTextPrimary)
                }
                .modifier(JarvisHeaderButton(isHovered: settingsHovering))
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

            // Refresh Session Button
            Button(action: {
                appContext.clearSession()
                socketClient.sendResetSession()
                configManager.sendConfigToPython()
            }) {
                ZStack {
                    Color.white.opacity(refreshHovering ? 0.25 : 0.15)
                        .cornerRadius(JarvisRadius.medium)

                    Image(systemName: "arrow.counterclockwise")
                        .font(JarvisFont.icon)
                        .foregroundStyle(Color.jarvisTextPrimary)
                }
                .modifier(JarvisHeaderButton(isHovered: refreshHovering))
                .scaleEffect(refreshHovering ? 1.1 : 1.0)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) {
                    refreshHovering = hovering
                }
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .contentShape(Rectangle())
            .zIndex(10)

            // Minimized Chat View Button
            Button(action: {
                toggleMessageView()
            }) {
                ZStack {
                    Color.white.opacity(chatMinimizeHovering ? 0.25 : 0.15)
                        .cornerRadius(JarvisRadius.medium)
                    
                    Image(systemName: "rectangle.compress.vertical")
                        .font(JarvisFont.icon)
                        .foregroundStyle(Color.jarvisTextPrimary)
                }
                .modifier(JarvisHeaderButton(isHovered: chatMinimizeHovering))
                .scaleEffect(chatMinimizeHovering ? 1.1 : 1.0)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) {
                    chatMinimizeHovering = hovering
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
                        .cornerRadius(JarvisRadius.medium)
                    
                    Image(systemName: "minus")
                        .font(JarvisFont.icon)
                        .foregroundStyle(shrinkHovering ? .black : .black)
                }
                .modifier(JarvisHeaderButton(isHovered: shrinkHovering))
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

            // Quit Button
            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                ZStack {
                    Color.jarvisRed.opacity(quitHovering ? 0.6 : 0.4)
                        .cornerRadius(JarvisRadius.medium)

                    Image(systemName: "xmark")
                        .font(JarvisFont.icon)
                        .foregroundStyle(Color.jarvisTextPrimary)
                }
                .modifier(JarvisHeaderButton(isHovered: quitHovering))
                .scaleEffect(quitHovering ? 1.1 : 1.0)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) {
                    quitHovering = hovering
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
                .fill(LinearGradient(colors: [.clear, .jarvisCyan, .clear], startPoint: .leading, endPoint: .trailing))
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
            .fill(LinearGradient(colors: [.jarvisCyan, .white], startPoint: .bottom, endPoint: .top))
            .frame(width: 3, height: getHeight())
            .opacity(0.35 + Darwin.sin(Double(phase) + Double(index) * 0.3) * 0.2)
            .shadow(color: Color.jarvisCyan.opacity(0.2), radius: 4, x: 0, y: 0)
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

// MARK: - Server Loading View
struct AgentLoadingView: View {
    let serverStatus: ServerManager.ServerStatus
    let isConnected: Bool
    let connectionFailed: Bool
    var onRetry: (() -> Void)?

    // MARK: - Computed Styles

    // Logic to determine the color of the Orb based on state
    var statusColor: Color {
        if connectionFailed {
            return Color.jarvisRed
        }
        switch serverStatus {
        case .running: return isConnected ? Color.jarvisGreen : Color.jarvisLightBlue
        case .error: return Color.jarvisRed
        case .stopping: return Color.jarvisAmber
        default: return Color.jarvisLightBlue
        }
    }

    var statusMessage: String {
        if connectionFailed {
            return "CONNECTION FAILED"
        }
        switch serverStatus {
        case .stopped: return "SYSTEM INITIALIZING"
        case .starting: return "BOOTING CORE"
        case .running: return isConnected ? "SYSTEM ONLINE" : "CONNECTING"
        case .stopping: return "SHUTTING DOWN"
        case .error(let msg): return "ERR: \(msg.prefix(12))"
        }
    }

    // Stop the outer rotation if we are just sitting in "Online" or "Error" state
    var isAnimating: Bool {
        if connectionFailed { return false }
        return serverStatus == .starting || serverStatus == .stopped || (serverStatus == .running && !isConnected)
    }

    var body: some View {
        ZStack {
            // MARK: - Dark Transparent Glass Container
            RoundedRectangle(cornerRadius: 30)
                .fill(Color.black.opacity(0.2))
                .background(.ultraThinMaterial.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 30))
                .shadow(color: .black.opacity(0.2), radius: 15, x: 0, y: 10)
                .overlay(
                    RoundedRectangle(cornerRadius: 30)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    statusColor.opacity(0.3),
                                    statusColor.opacity(0.05),
                                    statusColor.opacity(0.0)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )

            VStack(spacing: 25) {
                // 1. The Glossy Orb
                RongERing()
                    .frame(width: 110, height: 110)
                    .shadow(color: statusColor.opacity(0.8), radius: 80)
                    

                // 2. Status Information
                VStack(spacing: 8) {
                    Text("RONG-E AGENT")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundStyle(Color.jarvisTextSecondary)

                    // Status Line with Dots
                    HStack(spacing: 8) {
                        Text(statusMessage)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(statusColor)
                            .shadow(color: statusColor.opacity(0.5), radius: 6)

                        if isAnimating {
                            ModernLoadingDots(color: statusColor)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(statusColor.opacity(0.1))
                            .overlay(Capsule().stroke(statusColor.opacity(0.2), lineWidth: 0.5))
                    )

                    // Retry button when connection fails
                    if connectionFailed {
                        Button(action: {
                            onRetry?()
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 10, weight: .semibold))
                                Text("RETRY")
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .tracking(1)
                            }
                            .foregroundStyle(Color.jarvisTextPrimary)
                            .padding(.horizontal, JarvisSpacing.lg)
                            .padding(.vertical, JarvisSpacing.sm)
                            .background(
                                Capsule()
                                    .fill(Color.jarvisLightBlue.opacity(0.3))
                                    .overlay(Capsule().stroke(Color.jarvisLightBlue.opacity(0.5), lineWidth: 1))
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 8)
                    }
                }
            }
            .padding(.vertical, 30)
        }
        .frame(width: 240, height: 300)
    }
}

// MARK: - Helper Components
struct ModernLoadingDots: View {
    let color: Color
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(color)
                    .frame(width: 3, height: 3)
                    .scaleEffect(isAnimating ? 1.0 : 0.5)
                    .opacity(isAnimating ? 1.0 : 0.3)
                    .animation(
                        .easeInOut(duration: 0.6)
                        .repeatForever()
                        .delay(Double(index) * 0.2),
                        value: isAnimating
                    )
            }
        }
        .onAppear {
            isAnimating = true
        }
    }
}
