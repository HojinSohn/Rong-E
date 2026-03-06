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
            if appContext.themeAnimationsDisabled {
                showColumns = false
                showWaveform = false
                showGreeting = false
                minimizedMode = true
                windowCoordinator.minimizeMainOverlay()
            } else {
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
            }

        } else {
            if appContext.themeAnimationsDisabled {
                windowCoordinator.expandMainOverlay()
                minimizedMode = false
                showGreeting = true
                showColumns = true
                showWaveform = true
                setShowMinimizedMessageView(false)
                setShowMinimizedButtons(false)
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
                    },
                    onRestart: {
                        serverManager.stopServer()
                        socketClient.disconnect()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            serverManager.startServer()
                            setUpConnection()
                        }
                    },
                    onQuit: {
                        NSApplication.shared.terminate(nil)
                    }
                )
            }
        }
        .onAppear {
            // Initialize connections and auth
            setUpConnection()

            // Check screen capture permission on launch
            appContext.recheckScreenCapturePermission()

            // Only toggle minimized when server is ready
            if isServerReady {
                toggleMinimized()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Re-check screen capture permission when user returns to the app (e.g. from System Settings)
            if appContext.currentMode.isScreenshotEnabled {
                appContext.recheckScreenCapturePermission()
            }
        }
        .onChange(of: socketClient.isConnected) { _, isConnected in
            // Trigger main content animations when WebSocket connects (and server is running)
            if isConnected && serverManager.status == .running {
                toggleMinimized()
                // Transition from "Starting up" to "Await input"
                let now = Date()
                for i in appContext.reasoningSteps.indices {
                    if appContext.reasoningSteps[i].status == .active {
                        appContext.reasoningSteps[i].status = .completed
                        appContext.reasoningSteps[i].completedAt = now
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
                        // 1. Base Tint (Opacity from theme setting)
                        RoundedRectangle(cornerRadius: JarvisRadius.pill)
                            .fill(Color.black.opacity(appContext.themeSurfaceOpacity))

                        // 2. High-Tech Border (Keeps layout defined without solid background)
                        RoundedRectangle(cornerRadius: JarvisRadius.pill)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        appContext.currentMode.isScreenshotEnabled ? appContext.themeAccentColor.opacity(0.8) : appContext.themeAccentColor.opacity(0.4),
                                        appContext.themeAccentColor.opacity(0.05)
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
                            .shadow(color: appContext.themeAccentColor.opacity(0.4), radius: 10)
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
                appContext.reasoningSteps[lastIndex].completedAt = Date()
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
                // Permission confirmed — update status
                appContext.screenCapturePermissionGranted = true
                
            } catch {
                let nsError = error as NSError
                
                if nsError.code == -3801 {
                    print("⚠️ Permission Denied. Opening Settings...")
                    appContext.screenCapturePermissionGranted = false

                    // Open System Settings directly to Screen Recording pane
                    ScreenshotManager.openScreenRecordingSettings()

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

            // Append user message to chat history with attached screenshot
            appContext.currentSessionChatMessages.append(
                ChatMessage(role: "user", content: query, screenshotBase64: base64Image)
            )

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
                        appContext.screenCapturePermissionGranted = true
                        
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
                        appContext.screenCapturePermissionGranted = false
                    }
                }
            },
            onCancel: {
                // Send query without screenshot
                if let query = pendingQuery, let mode = pendingMode {
                    pendingQuery = nil
                    pendingMode = nil
                    waitingForPermission = false

                    // Append user message to chat history (no screenshot)
                    appContext.currentSessionChatMessages.append(ChatMessage(role: "user", content: query))

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
            let finishTime = Date()
            for i in appContext.reasoningSteps.indices {
                if appContext.reasoningSteps[i].status == .active {
                    appContext.reasoningSteps[i].status = .completed
                    appContext.reasoningSteps[i].completedAt = finishTime
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
        let submitTime = Date()
        for i in appContext.reasoningSteps.indices {
            if appContext.reasoningSteps[i].status == .active {
                appContext.reasoningSteps[i].status = .completed
                appContext.reasoningSteps[i].completedAt = submitTime
            }
        }
        appContext.reasoningSteps.append(ReasoningStep(description: "Processing query", status: .active))

        let modeSystemPrompt = appContext.currentMode.systemPrompt.isEmpty ? nil : appContext.currentMode.systemPrompt
        let userName = appContext.userName.isEmpty ? nil : appContext.userName

        if appContext.modes.first(where: { $0.name == appContext.modes.first(where: { $0.id == Int(currentMode.suffix(1)) })?.name })?.isScreenshotEnabled == true {
            print("📸 Screenshot tool is enabled for this mode. Capturing screenshot...")
            captureAndSendWithScreenshot(query: query, selectedMode: selectedMode)
        } else {
            // append user message to chat history (no screenshot)
            appContext.currentSessionChatMessages.append(ChatMessage(role: "user", content: query))
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
    @ObservedObject private var _theme = AppContext.shared

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
                HStack(spacing: 6) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.jarvisCyan.opacity(0.7))

                    Text("Reasoning Trace")
                        .modifier(JarvisSectionHeader())

                    Spacer()

                    // Step count badge
                    let completedCount = appContext.reasoningSteps.filter { $0.status == .completed }.count
                    HStack(spacing: 2) {
                        Text("\(completedCount)")
                            .foregroundStyle(Color.jarvisGreen)
                        Text("/")
                            .foregroundStyle(Color.jarvisTextDim)
                        Text("\(appContext.reasoningSteps.count)")
                            .foregroundStyle(Color.jarvisCyan)
                    }
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.05))
                    )

                    // Clear trace button
                    Button(action: {
                        withAnimation(.easeOut(duration: 0.2)) {
                            appContext.reasoningSteps = [ReasoningStep(description: "Await input", status: .active)]
                            expandedStepIds.removeAll()
                        }
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.jarvisTextDim)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.jarvisSurfaceLight)

                // Scrollable Content
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(appContext.reasoningSteps.enumerated()), id: \.element.id) { index, step in
                                ReasoningStepRow(
                                    step: step,
                                    isExpanded: expandedStepIds.contains(step.id),
                                    onTap: { toggleExpansion(for: step.id) },
                                    isLast: index == appContext.reasoningSteps.count - 1
                                )
                                .id(step.id)
                            }
                        }
                        .padding(10)
                    }
                    // Auto-scroll to bottom when new steps arrive
                    .onChange(of: appContext.reasoningSteps.count) {
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
            
            // 2. Agent Environment Dashboard
            EnvironmentDashboard()
                .environmentObject(appContext)
                .environmentObject(socketClient)

            // 3. Active Tools
            ActiveToolsPanel(tools: appContext.activeTools)
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

// MARK: - Active Tools Panel
struct ActiveToolsPanel: View {
    let tools: [ActiveToolInfo]
    @State private var collapsedSources: Set<String> = []
    @State private var hoveredTool: String? = nil
    @State private var selectedTool: ActiveToolInfo? = nil

    private var grouped: [(key: String, tools: [ActiveToolInfo])] {
        let dict = Dictionary(grouping: tools, by: { $0.source })
        return dict.keys.sorted { a, b in
            if a == "base" { return true }
            if b == "base" { return false }
            return a < b
        }.map { (key: $0, tools: dict[$0] ?? []) }
    }

    private func accentColor(for source: String) -> Color {
        if source == "base" || source == "built-in" { return Color.jarvisCyan }
        if source == "google" { return Color.jarvisGreen }
        return Color.jarvisOrange
    }

    private func icon(for source: String) -> String {
        if source == "base" || source == "built-in" { return "wrench.and.screwdriver.fill" }
        if source == "google" { return "globe" }
        return "hammer.fill"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.jarvisCyan.opacity(0.7))

                Text("Active Tools")
                    .modifier(JarvisSectionHeader())

                Spacer()

                // Open detail window button
                Button(action: {
                    WindowCoordinator.shared.openToolDetail()
                }) {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.jarvisTextDim)
                }
                .buttonStyle(.plain)
                .help("Open tools panel")

                // Total count badge
                Text("\(tools.count)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(tools.isEmpty ? Color.jarvisTextDim : Color.jarvisCyan)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(tools.isEmpty ? Color.white.opacity(0.05) : Color.jarvisCyan.opacity(0.12))
                    )
                    .overlay(
                        Capsule()
                            .stroke(tools.isEmpty ? Color.clear : Color.jarvisCyan.opacity(0.2), lineWidth: 0.5)
                    )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            // Content
            if tools.isEmpty {
                // Empty state
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.jarvisTextDim.opacity(0.5))
                    Text("No tools loaded")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.jarvisTextDim)
                    Text("Tools load when the server connects")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.jarvisTextDim.opacity(0.6))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else {
                // Thin separator
                Rectangle()
                    .fill(Color.jarvisBorder)
                    .frame(height: 1)
                    .padding(.horizontal, 10)

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(grouped, id: \.key) { group in
                            let accent = accentColor(for: group.key)
                            let isCollapsed = collapsedSources.contains(group.key)

                            // Source group header — tappable to collapse
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    if isCollapsed {
                                        collapsedSources.remove(group.key)
                                    } else {
                                        collapsedSources.insert(group.key)
                                    }
                                }
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: icon(for: group.key))
                                        .font(.system(size: 8))
                                        .foregroundStyle(accent.opacity(0.8))

                                    Text(group.key == "base" || group.key == "built-in" ? "BUILT-IN" : group.key.uppercased())
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundStyle(accent.opacity(0.9))

                                    // Tool count per source
                                    Text("×\(group.tools.count)")
                                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                                        .foregroundStyle(accent.opacity(0.5))

                                    Spacer()

                                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                                        .font(.system(size: 7, weight: .bold))
                                        .foregroundStyle(Color.jarvisTextDim)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(accent.opacity(0.04))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            // Tool rows (collapsible)
                            if !isCollapsed {
                                ForEach(group.tools, id: \.name) { tool in
                                    ToolRow(
                                        tool: tool,
                                        accent: accent,
                                        isHovered: hoveredTool == tool.name,
                                        isSelected: selectedTool?.name == tool.name,
                                        onHover: { h in
                                            withAnimation(.easeOut(duration: 0.15)) {
                                                hoveredTool = h ? tool.name : nil
                                            }
                                        },
                                        onTap: {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                                if selectedTool?.name == tool.name {
                                                    selectedTool = nil
                                                } else {
                                                    selectedTool = tool
                                                }
                                            }
                                        }
                                    )
                                }
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }

            // Tool detail panel (slides in at bottom when a tool is selected)
            if let tool = selectedTool {
                ToolDetailCard(tool: tool, accent: accentColor(for: tool.source)) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        selectedTool = nil
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .opacity
                ))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: selectedTool != nil ? 240 : 160)
        .background(Color.jarvisSurfaceLight)
        .cornerRadius(JarvisRadius.card)
        .overlay(
            RoundedRectangle(cornerRadius: JarvisRadius.card)
                .stroke(Color.jarvisBorder, lineWidth: 1)
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedTool?.name)
    }
}

/// Individual tool row with info button
struct ToolRow: View {
    let tool: ActiveToolInfo
    let accent: Color
    let isHovered: Bool
    let isSelected: Bool
    let onHover: (Bool) -> Void
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 1)
                .fill(accent.opacity(isSelected ? 1.0 : isHovered ? 0.9 : 0.45))
                .frame(width: 2, height: 12)

            Text(tool.name)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(isSelected ? accent : isHovered ? Color.jarvisTextPrimary : Color.jarvisTextSecondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 2)

            // Info button
            Image(systemName: isSelected ? "info.circle.fill" : "info.circle")
                .font(.system(size: 10))
                .foregroundStyle(isSelected ? accent : isHovered ? Color.jarvisTextTertiary : Color.clear)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? accent.opacity(0.1) : isHovered ? accent.opacity(0.06) : Color.clear)
        .cornerRadius(4)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onHover { h in onHover(h) }
    }
}

/// Detail card shown when a tool is selected
struct ToolDetailCard: View {
    let tool: ActiveToolInfo
    let accent: Color
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Separator
            Rectangle()
                .fill(accent.opacity(0.3))
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 8) {
                // Header with name + close
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(accent)

                    Text(tool.name)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.jarvisTextPrimary)
                        .lineLimit(1)

                    Spacer()

                    // Open in window button
                    Button(action: {
                        WindowCoordinator.shared.openToolDetail(tool: tool)
                    }) {
                        Image(systemName: "arrow.up.forward.square")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.jarvisTextDim)
                            .padding(4)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Open in detail window")

                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color.jarvisTextDim)
                            .padding(4)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                // Source badge
                HStack(spacing: 4) {
                    Text("SOURCE")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.jarvisTextDim)

                    Text(tool.source.uppercased())
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(accent.opacity(0.12))
                        .cornerRadius(3)
                }

                // Description (uses fallback)
                Text(tool.resolvedDescription)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.jarvisTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
        }
        .background(accent.opacity(0.04))
    }
}

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

// MARK: - Environment Dashboard
struct EnvironmentDashboard: View {
    @EnvironmentObject var appContext: AppContext
    @EnvironmentObject var socketClient: SocketClient
    @ObservedObject var serverManager = ServerManager.shared
    @ObservedObject var mcpConfigManager = MCPConfigManager.shared
    @State private var uptimeSeconds: Int = 0
    @State private var uptimeTimer: Timer?
    @State private var isExpanded: Bool = false

    private var serverStatusColor: Color {
        switch serverManager.status {
        case .running: return Color.jarvisGreen
        case .starting: return Color.jarvisAmber
        case .stopped, .stopping: return .gray
        case .error: return Color.jarvisRed
        }
    }

    private var serverStatusText: String {
        switch serverManager.status {
        case .running: return "Online"
        case .starting: return "Starting"
        case .stopped: return "Offline"
        case .stopping: return "Stopping"
        case .error(let msg): return "Error"
        }
    }

    private var serverStatusIcon: String {
        switch serverManager.status {
        case .running: return "checkmark.circle.fill"
        case .starting: return "arrow.triangle.2.circlepath"
        case .stopped, .stopping: return "moon.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    private var formattedUptime: String {
        let h = uptimeSeconds / 3600
        let m = (uptimeSeconds % 3600) / 60
        let s = uptimeSeconds % 60
        if h > 0 {
            return String(format: "%dh %02dm", h, m)
        } else if m > 0 {
            return String(format: "%dm %02ds", m, s)
        } else {
            return "\(s)s"
        }
    }

    private var hasApiKey: Bool {
        !appContext.llmProvider.requiresAPIKey || !appContext.aiApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Entire top section is tappable to expand/collapse
            VStack(alignment: .leading, spacing: 0) {
                // Header row
                HStack(spacing: 8) {
                    // Pulsing status dot
                    Circle()
                        .fill(serverStatusColor)
                        .frame(width: 6, height: 6)
                        .shadow(color: serverStatusColor.opacity(0.8), radius: 4)

                    Text("SYSTEM")
                        .font(JarvisFont.captionMono)
                        .foregroundStyle(Color.jarvisTextDim)

                    Spacer()

                    // API key warning badge
                    if !hasApiKey {
                        HStack(spacing: 3) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 7))
                            Text("NO KEY")
                                .font(.system(size: 7, weight: .bold, design: .monospaced))
                        }
                        .foregroundStyle(Color.jarvisRed)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.jarvisRed.opacity(0.15))
                        .cornerRadius(JarvisRadius.small)
                    }

                    // Quick status pill
                    Text(serverStatusText)
                        .font(JarvisFont.tag)
                        .foregroundStyle(serverStatusColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(serverStatusColor.opacity(0.15))
                        .cornerRadius(JarvisRadius.small)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.jarvisTextDim)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                // Compact row: always visible — LLM + Connection
                HStack(spacing: 6) {
                    // LLM Provider icon
                    Image(systemName: "sparkles")
                        .font(.system(size: 9))
                        .foregroundStyle(hasApiKey ? Color.jarvisAmber : Color.jarvisRed)

                    Text(appContext.llmModel)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(hasApiKey ? Color.jarvisTextSecondary : Color.jarvisRed.opacity(0.8))
                        .lineLimit(1)

                    Spacer()

                    // WebSocket indicator
                    HStack(spacing: 3) {
                        Circle()
                            .fill(socketClient.isConnected ? Color.jarvisGreen : Color.jarvisRed)
                            .frame(width: 5, height: 5)
                        Text("WS")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(socketClient.isConnected ? Color.jarvisGreen.opacity(0.8) : Color.jarvisRed.opacity(0.8))
                    }

                    // MCP indicator
                    HStack(spacing: 3) {
                        Image(systemName: "hammer.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(mcpConfigManager.connectedServerCount > 0 ? Color.jarvisOrange : Color.jarvisTextDim)
                        Text("\(mcpConfigManager.connectedServerCount)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(mcpConfigManager.connectedServerCount > 0 ? Color.jarvisOrange : Color.jarvisTextDim)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, isExpanded ? 6 : 8)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            }

            // Expanded details
            if isExpanded {
                VStack(spacing: 1) {
                    // Divider line
                    Rectangle()
                        .fill(Color.jarvisBorder)
                        .frame(height: 1)
                        .padding(.horizontal, 8)

                    VStack(alignment: .leading, spacing: 8) {

                        // LLM Provider Row
                        EnvRow(icon: "cpu", iconColor: Color.jarvisAmber, label: "Provider", value: appContext.llmProvider.displayName)

                        // API Key status
                        EnvRow(
                            icon: hasApiKey ? "key.fill" : "key",
                            iconColor: hasApiKey ? Color.jarvisGreen : Color.jarvisRed,
                            label: "API Key",
                            value: hasApiKey ? "Configured" : "Missing",
                            valueColor: hasApiKey ? Color.jarvisGreen : Color.jarvisRed
                        )

                        // Server Uptime
                        EnvRow(icon: "clock", iconColor: Color.jarvisCyan, label: "Uptime", value: serverManager.isRunning ? formattedUptime : "—")

                        // Current Mode
                        EnvRow(icon: "slider.horizontal.3", iconColor: Color.jarvisPurple, label: "Mode", value: appContext.currentMode.name)

                        // Session Messages
                        EnvRow(icon: "text.bubble", iconColor: Color.jarvisGreen, label: "Messages", value: "\(appContext.currentSessionChatMessages.count)")

                        // Google Auth
                        EnvRow(
                            icon: appContext.isGoogleConnected ? "checkmark.shield.fill" : "xmark.shield",
                            iconColor: appContext.isGoogleConnected ? Color.jarvisGreen : Color.jarvisTextDim,
                            label: "Google",
                            value: appContext.isGoogleConnected ? "Connected" : "Not connected"
                        )

                        // Active Tools Count
                        EnvRow(icon: "wrench.and.screwdriver", iconColor: Color.jarvisOrange, label: "Tools", value: "\(appContext.activeTools.count) loaded")

                        // Connected MCP Servers (names)
                        if !mcpConfigManager.connectedServerNames.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 5) {
                                    Image(systemName: "server.rack")
                                        .font(.system(size: 9))
                                        .foregroundStyle(Color.jarvisOrange)
                                        .frame(width: 14, alignment: .center)
                                    Text("MCP Servers")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Color.jarvisTextDim)
                                }
                                ForEach(mcpConfigManager.connectedServerNames, id: \.self) { name in
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(Color.jarvisGreen)
                                            .frame(width: 4, height: 4)
                                        Text(name)
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundStyle(Color.jarvisTextSecondary)
                                    }
                                    .padding(.leading, 19)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color.jarvisSurfaceLight)
        .cornerRadius(JarvisRadius.card)
        .overlay(
            RoundedRectangle(cornerRadius: JarvisRadius.card)
                .stroke(Color.jarvisBorder, lineWidth: 1)
        )
        .onAppear { startUptimeTimer() }
        .onDisappear { stopUptimeTimer() }
    }

    private func startUptimeTimer() {
        uptimeSeconds = 0
        uptimeTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if serverManager.isRunning {
                uptimeSeconds += 1
            }
        }
    }

    private func stopUptimeTimer() {
        uptimeTimer?.invalidate()
        uptimeTimer = nil
    }
}

/// A single key-value row in the environment dashboard
struct EnvRow: View {
    let icon: String
    let iconColor: Color
    let label: String
    let value: String
    var valueColor: Color? = nil

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(iconColor)
                .frame(width: 14, alignment: .center)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Color.jarvisTextDim)
            Spacer()
            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(valueColor ?? Color.jarvisTextSecondary)
                .lineLimit(1)
        }
    }
}

// MARK: - Reasoning Step Row
struct ReasoningStepRow: View {
    let step: ReasoningStep
    let isExpanded: Bool
    let onTap: () -> Void
    let isLast: Bool
    @ObservedObject private var _theme = AppContext.shared
    @State private var liveElapsedMs: Int = 0
    @State private var elapsedTimer: Timer?
    @State private var pulseScale: CGFloat = 1.0

    private var accentColor: Color {
        switch step.status {
        case .completed: return Color.jarvisGreen
        case .active: return Color.jarvisCyan
        case .pending: return Color.jarvisTextDim
        }
    }

    /// Steps that are just waiting for user input — no timer needed
    private static let idleDescriptions: Set<String> = [
        "Await input", "Ready", "Starting up"
    ]

    private var isIdleStep: Bool {
        Self.idleDescriptions.contains(step.description)
    }

    /// Formatted duration string (hidden for idle/waiting steps)
    private var durationText: String? {
        if isIdleStep { return nil }
        if let ms = step.durationMs {
            return formatMs(ms)
        } else if step.status == .active {
            return formatMs(liveElapsedMs)
        }
        return nil
    }

    private func formatMs(_ ms: Int) -> String {
        if ms < 1000 {
            return "\(ms)ms"
        } else if ms < 60_000 {
            let sec = Double(ms) / 1000.0
            return String(format: "%.1fs", sec)
        } else {
            let sec = ms / 1000
            return String(format: "%dm %02ds", sec / 60, sec % 60)
        }
    }

    /// Timestamp label (HH:mm:ss)
    private var timeLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: step.timestamp)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Timeline connector
            VStack(spacing: 0) {
                // Status node
                ZStack {
                    statusNode
                }
                .frame(width: 18, height: 18)

                // Vertical line to next step
                if !isLast {
                    Rectangle()
                        .fill(accentColor.opacity(0.2))
                        .frame(width: 1.5)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 18)
            .padding(.trailing, 8)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                // Main row: description + timing
                HStack(alignment: .top, spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.description)
                            .font(.system(size: 11.5, weight: step.status == .active ? .medium : .regular))
                            .foregroundStyle(step.status == .active ? Color.jarvisTextPrimary : Color.jarvisTextSecondary)
                            .lineLimit(2)

                        // Timestamp
                        Text(timeLabel)
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(Color.jarvisTextDim.opacity(0.7))
                    }

                    Spacer(minLength: 4)

                    // Duration badge
                    if let duration = durationText {
                        HStack(spacing: 3) {
                            if step.status == .active {
                                Circle()
                                    .fill(Color.jarvisCyan)
                                    .frame(width: 4, height: 4)
                                    .scaleEffect(pulseScale)
                            }
                            Text(duration)
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(step.status == .active ? Color.jarvisCyan : durationColor(for: step.durationMs ?? 0))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(step.status == .active ? Color.jarvisCyan.opacity(0.1) : Color.white.opacity(0.05))
                        )
                    }

                    // Expand/collapse chevron
                    if step.details != nil {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color.jarvisTextDim)
                            .padding(.top, 2)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if step.details != nil { onTap() }
                }

                // Expandable details
                if isExpanded, let details = step.details {
                    Text(details)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.jarvisTextTertiary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white.opacity(0.03))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(accentColor.opacity(0.1), lineWidth: 0.5)
                                )
                        )
                }
            }
            .padding(.bottom, isLast ? 0 : 6)
        }
        .onAppear {
            if step.status == .active {
                if !isIdleStep { startLiveTimer() }
                startPulse()
            }
        }
        .onDisappear { stopLiveTimer() }
        .onChange(of: step.status) {
            if step.status == .active {
                if !isIdleStep { startLiveTimer() }
                startPulse()
            } else {
                stopLiveTimer()
            }
        }
    }

    @ViewBuilder
    private var statusNode: some View {
        switch step.status {
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(Color.jarvisGreen)
        case .active:
            ZStack {
                Circle()
                    .fill(Color.jarvisCyan.opacity(0.15))
                    .frame(width: 16, height: 16)
                Circle()
                    .stroke(Color.jarvisCyan, lineWidth: 1.5)
                    .frame(width: 12, height: 12)
                Circle()
                    .fill(Color.jarvisCyan)
                    .frame(width: 5, height: 5)
                    .scaleEffect(pulseScale)
            }
        case .pending:
            Circle()
                .stroke(Color.jarvisTextDim.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                .frame(width: 10, height: 10)
        }
    }

    /// Color ramp for uration badge based on how long it took
    private func durationColor(for ms: Int) -> Color {
        if ms < 500 { return Color.jarvisGreen.opacity(0.8) }
        if ms < 2000 { return Color.jarvisAmber.opacity(0.8) }
        return Color.jarvisOrange.opacity(0.8)
    }

    private func startLiveTimer() {
        liveElapsedMs = Int(Date().timeIntervalSince(step.timestamp) * 1000)
        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            liveElapsedMs = Int(Date().timeIntervalSince(step.timestamp) * 1000)
        }
    }

    private func stopLiveTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }

    private func startPulse() {
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
            pulseScale = 1.4
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
                HStack(spacing: 5) {
                    Image(systemName: appContext.currentMode.isScreenshotEnabled ? "eye.fill" : "eye.slash")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(appContext.currentMode.isScreenshotEnabled ? Color.jarvisCyan : Color.jarvisTextDim)

                    Text(appContext.currentMode.isScreenshotEnabled ? "SCREEN CAPTURE: ON" : "SCREEN CAPTURE: OFF")
                        .font(JarvisFont.tag)
                        .foregroundStyle(appContext.currentMode.isScreenshotEnabled ? Color.jarvisCyan : Color.jarvisTextTertiary)

                    // Status dot — orange/warning when enabled but no permission
                    if appContext.currentMode.isScreenshotEnabled && !appContext.screenCapturePermissionGranted {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(Color.jarvisAmber)
                            .shadow(color: Color.jarvisAmber, radius: 3)
                    } else {
                        Circle()
                            .fill(appContext.currentMode.isScreenshotEnabled ? Color.jarvisGreen : Color.jarvisTextDim.opacity(0.5))
                            .frame(width: 5, height: 5)
                            .shadow(color: appContext.currentMode.isScreenshotEnabled ? Color.jarvisGreen : Color.clear, radius: 3)
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(appContext.currentMode.isScreenshotEnabled
                              ? (appContext.screenCapturePermissionGranted ? Color.jarvisCyan.opacity(0.1) : Color.jarvisAmber.opacity(0.1))
                              : Color.white.opacity(0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(appContext.currentMode.isScreenshotEnabled
                                ? (appContext.screenCapturePermissionGranted ? Color.jarvisCyan.opacity(0.3) : Color.jarvisAmber.opacity(0.3))
                                : Color.jarvisTextDim.opacity(0.2), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .help(appContext.currentMode.isScreenshotEnabled && !appContext.screenCapturePermissionGranted
                  ? "Screen Recording permission required. Click to open System Settings."
                  : "When enabled, Rong-E captures your screen and sends it with your message so the AI can see what you see.")
            .onAppear {
                appContext.recheckScreenCapturePermission()
            }

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
    @ObservedObject private var _theme = AppContext.shared

    @State private var localText: String = "" // Local, fast state

    // Track hasText separately to avoid animation recalculation on every keystroke
    @State private var hasText: Bool = false

    // Aesthetic Constants
    private var hudCyan: Color { Color.jarvisCyan }
    private var hudDark: Color { Color.jarvisSurfaceDeep }

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
        .onChange(of: localText.isEmpty) { _, isEmpty in
            // Only update hasText when empty state changes, not on every keystroke
            if hasText == isEmpty {
                hasText = !isEmpty
            }
        }
        .onChange(of: inputText) { _, newValue in
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
        let animationsOff = AppContext.shared.themeAnimationsDisabled
        Button(action: onSubmit) {
            ZStack {
                // Outer Ring
                Circle()
                    .stroke(hudCyan.opacity(0.3), lineWidth: 2)
                    .frame(width: 50, height: 50)

                // Rotating/Active Ring - uses TimelineView for smooth, performant animation
                if hasText && !animationsOff {
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
    @EnvironmentObject var appContext: AppContext
    @State private var pulse = false
    @State private var rotate = false
    
    var body: some View {
        let accent = appContext.themeAccentColor
        let lightGlow = accent.opacity(0.85)
        let deepColor = accent.opacity(0.5)
        let animationsOff = appContext.themeAnimationsDisabled
        
        ZStack {
            // 1. Rotating Outer Ring (With Angular Gradient for motion effect)
            Circle()
                .trim(from: 0.0, to: 0.75) // Not a full circle makes rotation visible
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [lightGlow.opacity(0), lightGlow]),
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .frame(width: 110, height: 110)
                .rotationEffect(.degrees(animationsOff ? 0 : (rotate ? 360 : 0)))
                .animation(animationsOff ? nil : .linear(duration: 3).repeatForever(autoreverses: false), value: rotate)

            // 2. Static Thin Ring
            Circle()
                .stroke(lightGlow.opacity(0.3), lineWidth: 1)
                .frame(width: 95, height: 95)

            // 3. Main Button Orb
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color.white.opacity(0.8), // Hot center
                            accent,                    // Accent color body
                            accent.opacity(0.4)        // Darker edges for 3D depth
                        ]),
                        center: .center,
                        startRadius: 0,
                        endRadius: 50
                    )
                )
                .frame(width: 80, height: 80)
                // Strong Glow Shadow
                .shadow(color: lightGlow.opacity(0.8), radius: animationsOff ? 15 : (pulse ? 25 : 15))
                .shadow(color: deepColor, radius: 5)
                .animation(animationsOff ? nil : .easeInOut(duration: 2).repeatForever(autoreverses: true), value: pulse)

            // 4. Glossy Reflection (Top Left) - Makes it look like glass/button
            Circle()
                .trim(from: 0.6, to: 0.9)
                .stroke(Color.white.opacity(0.6), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 70, height: 70)
                .blur(radius: 1)
                .rotationEffect(.degrees(-45))
        }
        .onAppear {
            if !animationsOff {
                pulse = true
                rotate = true
            }
        }
        .onChange(of: appContext.themeAnimationsDisabled) { _, disabled in
            if disabled {
                pulse = false
                rotate = false
            } else {
                pulse = true
                rotate = true
            }
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
                fullChatViewMode: fullChatViewMode,
                themeKey: appContext.themeKey
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
    let themeKey: String
    
    // Custom Equality Check
    static func == (lhs: EquatabeChatList, rhs: EquatabeChatList) -> Bool {
        // Only redraw if the message count changes, the last message ID changes, view mode toggles, or theme changes
        return lhs.messages.count == rhs.messages.count &&
               lhs.messages.last?.id == rhs.messages.last?.id &&
               lhs.fullChatViewMode == rhs.fullChatViewMode &&
               lhs.themeKey == rhs.themeKey
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
                            RongEMessageRow(message: message, themeKey: appContext.themeKey)
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
                
                .onChange(of: messages.last?.content) {
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: messages.count) {
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
    private var hudCyan: Color { Color.jarvisCyan }
    
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
                        Image(systemName: appContext.currentMode.isScreenshotEnabled ? "eye.fill" : "eye.slash")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(appContext.currentMode.isScreenshotEnabled ? Color.jarvisCyan : Color.jarvisTextDim)
                        
                        Text(appContext.currentMode.isScreenshotEnabled ? "SCREEN CAPTURE: ON" : "SCREEN CAPTURE: OFF")
                            .font(JarvisFont.captionMono)
                            .foregroundStyle(appContext.currentMode.isScreenshotEnabled ? Color.jarvisCyan : Color.jarvisTextTertiary)
                        
                        // Status indicator — warning when enabled but no permission
                        if appContext.currentMode.isScreenshotEnabled && !appContext.screenCapturePermissionGranted {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(Color.jarvisAmber)
                                .shadow(color: Color.jarvisAmber, radius: 3)
                        } else {
                            Circle()
                                .fill(appContext.currentMode.isScreenshotEnabled ? Color.jarvisGreen : Color.jarvisTextDim.opacity(0.5))
                                .frame(width: 6, height: 6)
                                .shadow(color: appContext.currentMode.isScreenshotEnabled ? Color.jarvisGreen : Color.clear, radius: 3)
                        }
                    }
                    .padding(.vertical, JarvisSpacing.xs)
                    .padding(.horizontal, JarvisSpacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: JarvisRadius.small)
                            .fill(appContext.currentMode.isScreenshotEnabled
                                  ? (appContext.screenCapturePermissionGranted ? Color.jarvisCyan.opacity(0.1) : Color.jarvisAmber.opacity(0.1))
                                  : Color.white.opacity(0.03))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: JarvisRadius.small)
                            .stroke(appContext.currentMode.isScreenshotEnabled
                                    ? (appContext.screenCapturePermissionGranted ? Color.jarvisCyan.opacity(0.3) : Color.jarvisAmber.opacity(0.3))
                                    : Color.jarvisTextDim.opacity(0.2), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                .help(appContext.currentMode.isScreenshotEnabled && !appContext.screenCapturePermissionGranted
                      ? "Screen Recording permission required. Click to open System Settings."
                      : "When enabled, Rong-E captures your screen and sends it with your message so the AI can see what you see.")
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
                            EquatableView(content: RongEMessageRow(message: message, themeKey: appContext.themeKey))
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
                .onChange(of: appContext.currentSessionChatMessages.count) { _, newCount in
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
                .onChange(of: systemLogs.count) {
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
    var themeKey: String = AppContext.shared.themeKey
    var isUser: Bool   { message.role == "user" }
    var isSystem: Bool { message.role == "system" }

    static func == (lhs: RongEMessageRow, rhs: RongEMessageRow) -> Bool {
        lhs.message.id == rhs.message.id && lhs.themeKey == rhs.themeKey
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


                // Message bubble with text and optional screenshot
                VStack(alignment: isUser ? .trailing : .leading, spacing: 0) {
                    // Attached screenshot inside the bubble (user messages only)
                    if isUser, let screenshotBase64 = message.screenshotBase64,
                       let data = Data(base64Encoded: screenshotBase64),
                       let nsImage = NSImage(data: data) {
                        ScreenshotThumbnailView(nsImage: nsImage)
                            .padding(.horizontal, 8)
                            .padding(.top, 8)
                            .padding(.bottom, 4)
                    }

                    // USE THE CACHED ATTRIBUTED STRING
                    Text(message.attributedContent) 
                        .font(JarvisFont.body)
                        .foregroundStyle(Color.jarvisTextPrimary)
                        .padding(12)
                }
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

// MARK: - Screenshot Thumbnail (clickable, opens detail window)
struct ScreenshotThumbnailView: View {
    let nsImage: NSImage

    var body: some View {
        Image(nsImage: nsImage)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(maxWidth: 250, maxHeight: 120)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.jarvisOrange.opacity(0.3), lineWidth: 0.8)
            )
    }
}

// MARK: - UI Components

/// The "Glass" background for bubbles
struct HUDGlassPanel: View {
    var isAccent: Bool
    @ObservedObject private var _theme = AppContext.shared

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
    @EnvironmentObject var appContext: AppContext
    @State private var rotate = false
    
    var body: some View {
        let accent = appContext.themeAccentColor
        let animationsOff = appContext.themeAnimationsDisabled
        ZStack {
            Circle()
                .stroke(accent.opacity(0.3), lineWidth: 1)
                .frame(width: 24, height: 24)
            
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(accent, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .frame(width: 18, height: 18)
                .rotationEffect(.degrees(animationsOff ? 0 : (rotate ? 360 : 0)))
                .animation(animationsOff ? nil : .linear(duration: 4).repeatForever(autoreverses: false), value: rotate)
            
            Circle()
                .fill(Color.white)
                .frame(width: 3, height: 3)
                .shadow(color: .white, radius: 2)
        }
        .onAppear {
            if !animationsOff { rotate = true }
        }
        .onChange(of: appContext.themeAnimationsDisabled) { _, disabled in
            rotate = !disabled
        }
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

    var body: some View {
        HStack(spacing: 0) {
            // --- Left: Brand ---
            HStack(spacing: 8) {
                // Accent dot with glow
                Circle()
                    .fill(appContext.themeAccentColor)
                    .frame(width: 7, height: 7)
                    .shadow(color: appContext.themeAccentColor.opacity(0.8), radius: 6)

                VStack(alignment: .leading, spacing: 1) {
                    Text("RONG-E")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(appContext.themeAccentColor)
                        .tracking(2)

                    Text("v1.0.0 BETA")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundColor(.jarvisTextDim)
                        .tracking(1)
                }
            }

            Spacer()

            // --- Center: Action Buttons ---
            HStack(spacing: 3) {
                HeaderButton(
                    icon: "icloud.fill",
                    label: "Google",
                    action: { windowCoordinator.openGoogleService() }
                )

                HeaderButton(
                    icon: "bolt.horizontal.fill",
                    label: "Startup",
                    action: { windowCoordinator.openWorkflowSettings() }
                )

                HeaderButton(
                    icon: "slider.horizontal.3",
                    label: "Settings",
                    action: { windowCoordinator.openSettings() }
                )

                HeaderButton(
                    icon: "arrow.triangle.2.circlepath",
                    label: "Reset",
                    accentOnHover: .jarvisAmber,
                    action: {
                        appContext.clearSession()
                        socketClient.sendResetSession()
                        configManager.sendConfigToPython()
                    }
                )

                HeaderButton(
                    icon: "bubble.left.and.text.bubble.right",
                    label: "Chat",
                    action: { toggleMessageView() }
                )
            }

            Spacer()

            // --- Right: Window Controls ---
            HStack(spacing: 4) {
                HeaderButton(
                    icon: "chevron.down",
                    label: "Hide",
                    style: .minimize,
                    action: { toggleMinimized() }
                )

                HeaderButton(
                    icon: "power",
                    label: "Quit",
                    style: .quit,
                    action: { NSApplication.shared.terminate(nil) }
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

// MARK: - Header Button Component
private struct HeaderButton: View {
    enum Style { case normal, minimize, quit }

    let icon: String
    var label: String = ""
    var accentOnHover: Color? = nil
    var style: Style = .normal
    let action: () -> Void

    @State private var isHovering = false
    @ObservedObject private var context = AppContext.shared

    private var accentColor: Color {
        accentOnHover ?? context.themeAccentColor
    }

    private var bgColor: Color {
        switch style {
        case .normal:
            return isHovering ? accentColor.opacity(0.18) : Color.white.opacity(0.05)
        case .minimize:
            return isHovering ? Color.white.opacity(0.85) : Color.white.opacity(0.12)
        case .quit:
            return Color.jarvisRed.opacity(isHovering ? 0.6 : 0.15)
        }
    }

    private var fgColor: Color {
        switch style {
        case .normal:
            return isHovering ? accentColor : Color.jarvisTextTertiary
        case .minimize:
            return isHovering ? .black : Color.jarvisTextTertiary
        case .quit:
            return isHovering ? .white : Color.jarvisTextTertiary
        }
    }

    private var borderColor: Color {
        switch style {
        case .normal:
            return isHovering ? accentColor.opacity(0.4) : Color.white.opacity(0.06)
        case .minimize:
            return isHovering ? Color.white.opacity(0.4) : Color.white.opacity(0.1)
        case .quit:
            return isHovering ? Color.jarvisRed.opacity(0.6) : Color.jarvisRed.opacity(0.1)
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(bgColor)

                    RoundedRectangle(cornerRadius: 6)
                        .stroke(borderColor, lineWidth: 0.6)

                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(fgColor)
                }
                .frame(width: 28, height: 26)
                .shadow(color: isHovering && style == .normal ? accentColor.opacity(0.3) : .clear, radius: 4, x: 0, y: 1)

                Text(label.uppercased())
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(isHovering ? fgColor : Color.jarvisTextDim.opacity(0.6))
                    .lineLimit(1)
            }
            .scaleEffect(isHovering ? 1.06 : 1.0)
            .animation(.easeOut(duration: 0.12), value: isHovering)
        }
        .buttonStyle(.plain)
        .frame(width: 38)
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Waveform Animation
struct WaveformBar: View {
    @State private var phase: CGFloat = 0
    @ObservedObject private var _theme = AppContext.shared
    
    var body: some View {
        let animationsOff = _theme.themeAnimationsDisabled
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
            if !animationsOff {
                // Start continuous animation with timer
                Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
                    phase += 0.5
                }
            }
        }
    }
}

// Helper view to break down complex expression
struct WaveformBarItem: View {
    let index: Int
    let phase: CGFloat
    @ObservedObject private var _theme = AppContext.shared
    
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
    var onRestart: (() -> Void)?
    var onQuit: (() -> Void)?
    @ObservedObject private var _theme = AppContext.shared

    // MARK: - Animation State
    @State private var bootLogs: [String] = []
    @State private var bootPhase: Int = 0
    @State private var scanlineOffset: CGFloat = -1.0
    @State private var showContent: Bool = false
    @State private var showOrb: Bool = false
    @State private var showTitle: Bool = false
    @State private var showControls: Bool = false
    @State private var progressValue: CGFloat = 0
    @State private var orbPulse: Bool = false
    @State private var glitchOffset: CGFloat = 0
    @State private var hasStartedSequence = false

    // MARK: - Computed Styles
    var accent: Color { _theme.themeAccentColor }

    var statusColor: Color {
        if connectionFailed { return Color.jarvisRed }
        switch serverStatus {
        case .running: return isConnected ? Color.jarvisGreen : accent
        case .error: return Color.jarvisRed
        case .stopping: return Color.jarvisAmber
        default: return accent
        }
    }

    var statusMessage: String {
        if connectionFailed { return "CONNECTION FAILED" }
        switch serverStatus {
        case .stopped: return "INITIALIZING"
        case .starting: return "BOOTING CORE"
        case .running: return isConnected ? "ONLINE" : "CONNECTING"
        case .stopping: return "SHUTTING DOWN"
        case .error(let msg): return "ERR: \(msg.prefix(20))"
        }
    }

    var isAnimating: Bool {
        if connectionFailed { return false }
        return serverStatus == .starting || serverStatus == .stopped || (serverStatus == .running && !isConnected)
    }

    // MARK: - Boot Sequence Lines
    private let bootSequence: [(String, TimeInterval)] = [
        ("RONG-E AGENT v1.0.0", 0.0),
        ("LOADING KERNEL MODULES...", 0.3),
        ("CORE: RUST RUNTIME OK", 0.6),
        ("NET: BINDING PORT 3000", 0.9),
        ("ENGINE: AWAITING LLM HANDSHAKE", 1.2),
        ("TOOLS: SCANNING MCP REGISTRY", 1.5),
        ("SOCKET: ESTABLISHING LINK", 1.8),
    ]

    var body: some View {
        ZStack {
            // MARK: - Background (matches main theme: opaque or transparent)
            RoundedRectangle(cornerRadius: JarvisRadius.pill)
                .fill(Color.black.opacity(_theme.themeSurfaceOpacity))

            // Tech grid (same as main window TechGridBackground)
            BootTechGrid(accent: accent)
                .opacity(showContent ? 0.6 : 0)
                .clipShape(RoundedRectangle(cornerRadius: JarvisRadius.pill))

            // Scanline sweep
            if !_theme.themeAnimationsDisabled {
                BootScanline(accent: accent, offset: scanlineOffset)
                    .opacity(0.15)
                    .clipShape(RoundedRectangle(cornerRadius: JarvisRadius.pill))
            }

            // MARK: - Border (matches main window accent gradient border)
            RoundedRectangle(cornerRadius: JarvisRadius.pill)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            accent.opacity(showContent ? 0.4 : 0),
                            accent.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )

            // Corner brackets
            VStack {
                HStack {
                    BootCornerBracket(accent: accent, rotation: 0)
                    Spacer()
                    BootCornerBracket(accent: accent, rotation: 90)
                }
                Spacer()
                HStack {
                    BootCornerBracket(accent: accent, rotation: 270)
                    Spacer()
                    BootCornerBracket(accent: accent, rotation: 180)
                }
            }
            .padding(16)
            .opacity(showContent ? 1 : 0)

            // MARK: - Content
            VStack(spacing: 0) {
                Spacer().frame(height: 20)

                // Top: Title bar
                HStack(spacing: 6) {
                    Circle()
                        .fill(accent)
                        .frame(width: 6, height: 6)
                        .shadow(color: accent.opacity(0.8), radius: 4)
                    Text("RONG-E")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(accent)
                        .tracking(3)
                    Spacer()
                    Text("BOOT")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(accent.opacity(0.5))
                        .tracking(2)
                }
                .padding(.horizontal, 20)
                .opacity(showTitle ? 1 : 0)
                .offset(y: showTitle ? 0 : -8)

                Spacer().frame(height: 12)

                // Thin accent divider
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0), accent.opacity(0.4), accent.opacity(0)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 0.5)
                    .padding(.horizontal, 16)
                    .opacity(showTitle ? 1 : 0)

                Spacer().frame(height: 16)

                // Center: Orb + Status
                ZStack {
                    // Outer glow ring
                    Circle()
                        .stroke(accent.opacity(orbPulse ? 0.3 : 0.1), lineWidth: 1.5)
                        .frame(width: 120, height: 120)
                        .scaleEffect(orbPulse ? 1.05 : 1.0)

                    RongERing()
                        .frame(width: 90, height: 90)
                        .shadow(color: statusColor.opacity(0.6), radius: orbPulse ? 40 : 20)
                }
                .opacity(showOrb ? 1 : 0)
                .scaleEffect(showOrb ? 1 : 0.6)

                Spacer().frame(height: 14)

                // Status badge
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 5, height: 5)
                        .shadow(color: statusColor, radius: 3)

                    Text(statusMessage)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(statusColor)
                        .tracking(1.5)

                    if isAnimating {
                        ModernLoadingDots(color: statusColor)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(statusColor.opacity(0.08))
                        .overlay(Capsule().stroke(statusColor.opacity(0.2), lineWidth: 0.5))
                )
                .opacity(showOrb ? 1 : 0)

                Spacer().frame(height: 14)

                // MARK: - Boot Log Terminal
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(bootLogs.enumerated()), id: \.offset) { index, log in
                        HStack(spacing: 4) {
                            Text("›")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(accent.opacity(0.5))
                            Text(log)
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(
                                    index == bootLogs.count - 1
                                        ? accent.opacity(0.9)
                                        : Color.jarvisTextSecondary.opacity(0.5)
                                )
                        }
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(x: glitchOffset)),
                            removal: .opacity
                        ))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 22)
                .frame(height: 70, alignment: .bottom)
                .clipped()

                Spacer().frame(height: 10)

                // Progress Bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // Track
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.jarvisDim)
                            .frame(height: 3)

                        // Fill
                        RoundedRectangle(cornerRadius: 2)
                            .fill(
                                LinearGradient(
                                    colors: [accent.opacity(0.4), accent],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * progressValue, height: 3)
                            .shadow(color: accent.opacity(0.5), radius: 4)
                    }
                }
                .frame(height: 3)
                .padding(.horizontal, 22)
                .opacity(showContent ? 1 : 0)

                Spacer().frame(height: 14)

                // MARK: - Action Buttons
                if connectionFailed {
                    Button(action: { onRetry?() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10, weight: .semibold))
                            Text("RETRY CONNECTION")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .tracking(1)
                        }
                        .foregroundStyle(Color.jarvisTextPrimary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(accent.opacity(0.2))
                                .overlay(Capsule().stroke(accent.opacity(0.5), lineWidth: 1))
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 4)
                }

                // Restart / Quit Row
                HStack(spacing: 10) {
                    Button(action: { onRestart?() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 8, weight: .semibold))
                            Text("RESTART")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .tracking(1)
                        }
                        .foregroundStyle(Color.jarvisTextSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.jarvisSurface)
                                .overlay(Capsule().stroke(Color.jarvisBorder, lineWidth: 0.5))
                        )
                    }
                    .buttonStyle(.plain)

                    Button(action: { onQuit?() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "power")
                                .font(.system(size: 8, weight: .semibold))
                            Text("QUIT")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .tracking(1)
                        }
                        .foregroundStyle(Color.jarvisRed.opacity(0.8))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.jarvisRed.opacity(0.08))
                                .overlay(Capsule().stroke(Color.jarvisRed.opacity(0.2), lineWidth: 0.5))
                        )
                    }
                    .buttonStyle(.plain)
                }
                .opacity(showControls ? 1 : 0)

                Spacer().frame(height: 16)
            }
        }
        .frame(width: 280, height: 420)
        .clipShape(RoundedRectangle(cornerRadius: JarvisRadius.pill))
        .background(
            RoundedRectangle(cornerRadius: JarvisRadius.pill)
                .fill(Color.clear)
                .shadow(color: accent.opacity(0.3), radius: 20, x: 0, y: 0)
        )
        .onAppear {
            startBootSequence()
        }
        .onChange(of: serverStatus) { _, _ in updateProgress() }
        .onChange(of: isConnected) { _, _ in updateProgress() }
        .onChange(of: connectionFailed) { _, connected in
            if connected {
                withAnimation { bootLogs.append("ERR: HANDSHAKE TIMEOUT") }
            }
        }
    }

    // MARK: - Boot Animation Logic
    private func startBootSequence() {
        guard !hasStartedSequence else { return }
        hasStartedSequence = true

        let animationsOff = _theme.themeAnimationsDisabled

        // Phase 1: Fade in container
        withAnimation(animationsOff ? nil : .easeOut(duration: 0.4)) {
            showContent = true
        }

        // Phase 2: Title
        withAnimation(animationsOff ? nil : .easeOut(duration: 0.3).delay(0.2)) {
            showTitle = true
        }

        // Phase 3: Orb scales in
        withAnimation(animationsOff ? nil : .spring(response: 0.6, dampingFraction: 0.7).delay(0.4)) {
            showOrb = true
        }

        // Phase 4: Boot logs appear one by one
        for (index, entry) in bootSequence.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6 + entry.1) {
                // Tiny glitch effect
                if !animationsOff {
                    glitchOffset = CGFloat.random(in: -3...3)
                }
                withAnimation(.easeOut(duration: 0.2)) {
                    bootLogs.append(entry.0)
                    progressValue = min(CGFloat(index + 1) / CGFloat(bootSequence.count + 2), 0.85)
                }
                if !animationsOff {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                        withAnimation(.easeOut(duration: 0.1)) { glitchOffset = 0 }
                    }
                }
            }
        }

        // Phase 5: Controls appear
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(animationsOff ? nil : .easeOut(duration: 0.3)) {
                showControls = true
            }
        }

        // Orb pulse animation
        if !animationsOff {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                    orbPulse = true
                }
            }

            // Scanline sweep
            withAnimation(.linear(duration: 3.0).repeatForever(autoreverses: false)) {
                scanlineOffset = 1.0
            }
        }
    }

    private func updateProgress() {
        let animationsOff = _theme.themeAnimationsDisabled
        if isConnected {
            withAnimation(animationsOff ? nil : .easeOut(duration: 0.5)) {
                progressValue = 1.0
                bootLogs.append("STATUS: ALL SYSTEMS NOMINAL")
            }
        } else if connectionFailed {
            withAnimation(animationsOff ? nil : .easeOut(duration: 0.3)) {
                progressValue = max(progressValue, 0.6)
            }
        } else if serverStatus == .running {
            withAnimation(animationsOff ? nil : .easeOut(duration: 0.3)) {
                progressValue = max(progressValue, 0.9)
                if !bootLogs.contains("SOCKET: HANDSHAKE IN PROGRESS") {
                    bootLogs.append("SOCKET: HANDSHAKE IN PROGRESS")
                }
            }
        }
    }
}

// MARK: - Boot Screen Sub-Components

/// Decorative corner bracket for the boot screen HUD frame
private struct BootCornerBracket: View {
    let accent: Color
    let rotation: Double

    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 14))
            path.addLine(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 14, y: 0))
        }
        .stroke(accent.opacity(0.4), lineWidth: 1.5)
        .frame(width: 14, height: 14)
        .rotationEffect(.degrees(rotation))
    }
}

/// Tech-grid background for boot screen (lighter version of TechGridBackground)
private struct BootTechGrid: View {
    let accent: Color

    var body: some View {
        GeometryReader { geo in
            Path { path in
                let w = geo.size.width
                let h = geo.size.height
                let spacing: CGFloat = 30
                for i in 0...Int(w / spacing) {
                    path.move(to: CGPoint(x: CGFloat(i) * spacing, y: 0))
                    path.addLine(to: CGPoint(x: CGFloat(i) * spacing, y: h))
                }
                for i in 0...Int(h / spacing) {
                    path.move(to: CGPoint(x: 0, y: CGFloat(i) * spacing))
                    path.addLine(to: CGPoint(x: w, y: CGFloat(i) * spacing))
                }
            }
            .stroke(accent.opacity(0.04), lineWidth: 0.5)
        }
    }
}

/// Horizontal scanline that sweeps vertically across the boot screen
private struct BootScanline: View {
    let accent: Color
    let offset: CGFloat

    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [accent.opacity(0), accent.opacity(0.15), accent.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 60)
                .offset(y: offset * geo.size.height)
        }
        .clipped()
    }
}

// MARK: - Helper Components
struct ModernLoadingDots: View {
    let color: Color
    @State private var isAnimating = false

    var body: some View {
        let animationsOff = AppContext.shared.themeAnimationsDisabled
        HStack(spacing: 3) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(color)
                    .frame(width: 3, height: 3)
                    .scaleEffect(animationsOff ? 1.0 : (isAnimating ? 1.0 : 0.5))
                    .opacity(animationsOff ? 1.0 : (isAnimating ? 1.0 : 0.3))
                    .animation(
                        animationsOff ? nil :
                        .easeInOut(duration: 0.6)
                        .repeatForever()
                        .delay(Double(index) * 0.2),
                        value: isAnimating
                    )
            }
        }
        .onAppear {
            if !animationsOff {
                isAnimating = true
            }
        }
    }
}