import SwiftUI

struct MainView: View {
    // 1. Animation States
    @State private var showWaveform = false
    @State private var showColumns = false // New state to stagger the inside content
    @State private var showGreeting = false
    @State private var minimizedMode = true

    // 2. Opacity State
    @State private var opacity: Double = 0.7

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
    @State private var fullChatViewMode = false

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
        }
        print("New minimizedMode: \(minimizedMode)")
    }

    func toggleFullChatView() {
        withAnimation(.easeInOut(duration: 0.4)) {
            fullChatViewMode.toggle()
        }
    }


    var body: some View {
        ZStack(alignment: .bottom) { // Align bottom to help with positioning
            // --- CLOCK LAYER ---
            // Fades out when minimized
            VStack(spacing: 0) { // 1. Remove spacing between Time and Greeting
                Spacer().frame(height: 50)
                
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
            .animation(.easeInOut(duration: 0.3), value: fullChatViewMode)
            .allowsHitTesting(false)

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
                            .offset(x: showColumns ? 0 : 100)
                            .opacity(showColumns ? 1 : 0)
                        }
                        .padding(24)
                        .background(
                            JarvisHUDView()
                                .blur(radius: 10)
                                .allowsHitTesting(false)
                        )
                    }
                    .transition(.opacity)
                } else {
                    // Keep the HUD visible when minimized without laying out the large content
                    JarvisHUDView()
                        .blur(radius: 0)
                        .allowsHitTesting(false)
                        .scaleEffect(0.2)
                }
            }
            // MARK: - Frame Animation Logic
            .frame(
                width: minimizedMode ? 80 : 800,
                height: minimizedMode ? 80 : 520
            )
            .background(minimizedMode ? Color.black.opacity(0.6) : Color.clear) // Add dark tint when minimized
            .backgroundColor(Color.black.opacity(0.1))
            // Corner radius becomes 40 (half of 80) to make a perfect circle
            .cornerRadius(40)
            .overlay(
                RoundedRectangle(cornerRadius: 40)
                    .stroke(LinearGradient(colors: [.white.opacity(0.7), .white.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.4), radius: 30, x: 0, y: 15)
            
            // Restore on Tap
            .onTapGesture {
                if minimizedMode {
                    toggleMinimized()
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
        
        socketClient.onDisconnect = { errorText in
            finishProcessing(response: "Error: \(errorText)")
        }
    }

    private func setUpAuthManager() {
        googleAuthManager.startupCheck()
    }

    private func captureAndSendWithScreenshot(query: String, selectedMode: String) {
        Task { @MainActor in
            var base64Image: String? = nil
            
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
                    
                    return
                } else {
                    print("❌ Screenshot Error: \(nsError.localizedDescription)")
                }
            }

            socketClient.sendMessageWithImage(query, mode: selectedMode, base64Image: base64Image)
            
            self.activeTool = "WS_STREAM"
        }
    }

    private func showPermissionWaitingOverlay() {
        windowCoordinator.openPermissionWaitingOverlay(
            onRetry: {
                Task { @MainActor in
                    do {
                    } catch {}
                }
            },
            onCancel: {
                if let query = pendingQuery, let mode = pendingMode {
                    pendingQuery = nil
                    pendingMode = nil
                    waitingForPermission = false
                    socketClient.sendMessage(query, mode: mode)

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
            appContext.currentSessionChatMessages.append(ChatMessage(role: "assistant", content: response))
            appContext.response = response
            inputMode = false // Check this
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

// MARK: - Left Column (Widgets)
struct LeftColumnView: View {
    var body: some View {
        VStack(spacing: 12) {
            
            // 1. Connection Status Widget (Large)
            VStack(alignment: .leading) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Image(systemName: "server.rack")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white)
                            .font(.system(size: 24))
                        Text("Backend")
                            .font(.caption2.bold())
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer()
                    Circle()
                        .fill(Color.cyan)
                        .frame(width: 8, height: 8)
                        .shadow(color: .cyan, radius: 4)
                }
                Spacer()
                Text("Python Core")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Port: 8080 • Active")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(16)
            .frame(height: 130)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(colors: [Color(red: 0.2, green: 0.2, blue: 0.3).opacity(0.7), Color.black.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .cornerRadius(24)
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.1), lineWidth: 1))

            // 2. Model Info Widget (Medium)
            HStack {
                VStack(alignment: .leading) {
                    Text("Active Model")
                        .font(.caption2)
                        .foregroundStyle(.gray)
                    Text("Gemini 2.5 Flash Lite")
                        .font(.title3.bold())
                        .foregroundStyle(.cyan)
                }
                Spacer()
                Image(systemName: "bolt.fill")
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(16)
            .frame(height: 70)
            .frame(maxWidth: .infinity)
            .background(Color.black.opacity(0.2))
            .cornerRadius(24)

            // 3. Next Task (Tall)
            VStack(alignment: .leading) {
                HStack {
                    Text("Up Next")
                        .font(.caption.bold())
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Image(systemName: "calendar.badge.clock")
                        .font(.caption2)
                        .foregroundStyle(.gray)
                }
                
                Spacer()
                
                // 3D Shape
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(LinearGradient(colors: [.orange, .pink], startPoint: .top, endPoint: .bottom))
                    .shadow(color: .orange.opacity(0.5), radius: 10)
                
                Spacer()
                
                HStack {
                    Text("CS536 Lab")
                        .font(.caption2)
                        .foregroundStyle(.gray)
                    Spacer()
                    Text("13:30")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                }
            }
            .padding(16)
            .frame(maxHeight: .infinity)
            .frame(maxWidth: .infinity)
            .background(Color.black.opacity(0.2))
            .cornerRadius(24)
        }
        .frame(width: 190)
    }
}

// MARK: - Main Column (Chat & Response)
struct MainColumnView: View {
    // Pass state from MainView
    @Binding var inputText: String
    @Binding var fullChatViewMode: Bool

    @EnvironmentObject var appContext: AppContext
    var onSubmit: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            
            Spacer()
                .frame(height: fullChatViewMode ? 10 : 140)

            ChatView(fullChatViewMode: $fullChatViewMode)
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .opacity
                ))
            Spacer()
            
            // 4. Input Field (Bottom)
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                    
                    TextField("Enter command...", text: $inputText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                        .accentColor(.cyan)
                        .onSubmit {
                            onSubmit()
                        }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(Color.black.opacity(0.3))
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
                
                // Submit / Mic Button
                Button(action: onSubmit) {
                    Circle()
                        .fill(inputText.isEmpty ? Color.white.opacity(0.1) : Color.cyan)
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: inputText.isEmpty ? "mic.fill" : "arrow.up")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(inputText.isEmpty ? .white : .black)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 10)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.35), value: fullChatViewMode)
    }
}

struct JarvisHUDView: View {
    @State private var isAnimating = false
    
    // Color Palette (Yellow removed)
    let neonBlue = Color(red: 0.2, green: 0.8, blue: 1.0)
    let deepBlue = Color(red: 0.05, green: 0.1, blue: 0.3)
    // Removed electricGold definition
    
    var body: some View {
        ZStack {
            // Background Glow (Ambient) - removed solid black background
            RadialGradient(gradient: Gradient(colors: [deepBlue.opacity(0.3), Color.clear]), center: .center, startRadius: 10, endRadius: 350)
                .scaleEffect(1.5)
            
            ZStack {
                // MARK: - Layer 1: Outer Metallic Shell (Static/Slow)
                Group {
                    Circle()
                        .trim(from: 0.1, to: 0.4)
                        .stroke(
                            LinearGradient(gradient: Gradient(colors: [Color.gray, neonBlue, Color.gray]), startPoint: .topLeading, endPoint: .bottomTrailing),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .rotationEffect(.degrees(180))
                    
                    Circle()
                        .trim(from: 0.1, to: 0.4)
                        .stroke(
                            LinearGradient(gradient: Gradient(colors: [Color.gray, neonBlue, Color.gray]), startPoint: .topLeading, endPoint: .bottomTrailing),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                }
                .frame(width: 350, height: 350)
                .rotationEffect(.degrees(isAnimating ? 360 : 0))
                .animation(.linear(duration: 60).repeatForever(autoreverses: false), value: isAnimating)
                
                // MARK: - Layer 3: Dashed Data Rings (Blue)
                Group {
                    Circle()
                        .stroke(neonBlue.opacity(0.5), style: StrokeStyle(lineWidth: 2, lineCap: .butt, dash: [5, 10]))
                        .frame(width: 300, height: 300)
                        .rotationEffect(.degrees(isAnimating ? -360 : 0))
                        .animation(.linear(duration: 20).repeatForever(autoreverses: false), value: isAnimating)
                    
                    Circle()
                        .trim(from: 0, to: 0.8)
                        .stroke(neonBlue, style: StrokeStyle(lineWidth: 4, lineCap: .butt, dash: [2, 15]))
                        .frame(width: 260, height: 260)
                        .rotationEffect(.degrees(isAnimating ? 360 : 0))
                        .animation(.linear(duration: 15).repeatForever(autoreverses: false), value: isAnimating)
                }
                
                // MARK: - Layer 4: Inner Accents (Formerly Gold, now White/Blue)
                Group {
                    // Formerly gold solid ring -> Now White for contrast
                    Circle()
                        .stroke(Color.white.opacity(0.8), lineWidth: 1)
                        .frame(width: 220, height: 220)
                    
                    // Formerly gold trimming -> Now Neon Blue
                    Circle()
                        .trim(from: 0, to: 0.6)
                        .stroke(neonBlue, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [20, 20]))
                        .frame(width: 210, height: 210)
                        .rotationEffect(.degrees(isAnimating ? -360 : 0))
                        .animation(.linear(duration: 8).repeatForever(autoreverses: false), value: isAnimating)
                }

                // MARK: - Layer 5: Inner Tech Complexity
                Group {
                    Circle()
                        .stroke(Color.white.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [1, 2]))
                        .frame(width: 150, height: 150)
                    
                    Circle()
                        .trim(from: 0.4, to: 0.9)
                        .stroke(neonBlue, style: StrokeStyle(lineWidth: 8, lineCap: .butt))
                        .frame(width: 120, height: 120)
                        .rotationEffect(.degrees(isAnimating ? 360 : 0))
                        .animation(.easeInOut(duration: 4).repeatForever(autoreverses: true), value: isAnimating)
                }
                
                // MARK: - Layer 6: The Core (Glowing Center)
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 20, height: 20)
                        .blur(radius: 3)
                        .shadow(color: .white, radius: 10, x: 0, y: 0)
                    
                    // Ring around core (Formerly gold -> Now White)
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                        .frame(width: 40, height: 40)
                    
                    Rectangle()
                        .fill(neonBlue)
                        .frame(width: 100, height: 1)
                    Rectangle()
                        .fill(neonBlue)
                        .frame(width: 1, height: 100)
                }
                .opacity(0.9)
                .scaleEffect(isAnimating ? 1.05 : 0.95)
                .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: isAnimating)

            }
            .shadow(color: neonBlue.opacity(0.6), radius: 20, x: 0, y: 0)
        }
        .onAppear {
            isAnimating = true
        }
    }
}

struct ChatView: View {
    @EnvironmentObject var appContext: AppContext
    @Binding var fullChatViewMode: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            
            // MARK: Header
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color.blue, Color.cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 36, height: 36)
                        .shadow(color: Color.cyan.opacity(0.5), radius: 6, x: 0, y: 2)
                    
                    // Jarvis-style icon
                    Image(systemName: "bolt.fill") // you can replace with custom SF Symbol or asset
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Runtime Logs")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    Text("Session ID: #A9-2044")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.6))
                }
                
                Spacer()
                
                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        fullChatViewMode.toggle()
                    }
                }) {
                    Image(systemName: fullChatViewMode ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .font(.caption2.bold())
                        .foregroundColor(.white.opacity(0.7))
                        .padding(6)
                        .background(Color.black.opacity(0.3), in: Circle())
                        .shadow(color: Color.white.opacity(0.1), radius: 4, x: 0, y: 1)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // MARK: Divider
            Rectangle()
                .fill(LinearGradient(colors: [Color.white.opacity(0.3), Color.clear], startPoint: .leading, endPoint: .trailing))
                .frame(height: 1)
                .shadow(color: Color.blue.opacity(0.2), radius: 2, x: 0, y: 0)
            
            // MARK: Logs
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        
                        // Static System Logs
                        Group {
                            LogLine(text: "> System Initialized.")
                            LogLine(text: "> Connecting to Backend...")
                            LogLine(text: "> Connection Established.")
                            LogLine(text: "> Active Model: Gemini 2.5 Flash Lite")
                        }
                        
                        // Dynamic Chat Logs
                        ForEach(appContext.currentSessionChatMessages) { message in
                            MessageLogRow(message: message)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                                .animation(.easeOut(duration: 0.25), value: appContext.currentSessionChatMessages.count)
                        }
                        
                        // Invisible view for auto-scroll
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .padding(.top, 6)
                }
                .frame(maxHeight: fullChatViewMode ? 420 : 220)
                .onChange(of: appContext.currentSessionChatMessages.count) { _ in
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
            
        }
        .padding(20)
        .background(Color.black.opacity(0.5)) // solid dark background for HUD feel
        .cornerRadius(24)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.blue.opacity(0.25), radius: 12, x: 0, y: 4)
        .scaleEffect(fullChatViewMode ? 1.0 : 0.98)
        .opacity(fullChatViewMode ? 1.0 : 0.95)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: fullChatViewMode)
        .transition(.scale.combined(with: .opacity))
    }
}


// MARK: - Helper View for efficient rendering
struct MessageLogRow: View {
    let message: ChatMessage
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if message.role == "user" {
                // Corrected parameter name from 'user' to 'isUser'
                LogLine(text: "> User: \(message.content)", isUser: true)
            } else {
                // Assistant messages
                ForEach(message.content.components(separatedBy: "\n"), id: \.self) { line in
                    if !line.isEmpty { 
                        LogLine(text: "> \(line)") 
                    }
                }
            }
        }
    }
}

struct LogLine: View {
    let text: String
    var isUser: Bool = false
    
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .regular, design: .monospaced))
            .foregroundStyle(isUser ? Color.green : Color.cyan)
            .multilineTextAlignment(.leading) // 1. Align wrapped lines to the left
            .frame(maxWidth: .infinity, alignment: .leading) // 2. Force it to fill width but not exceed it
            .fixedSize(horizontal: false, vertical: true) // 3. Grow vertically, respect horizontal constraints
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
