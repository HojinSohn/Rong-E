import SwiftUI
import Combine

struct ContentView: View {
    // --- State ---
    @State private var isHovering = false
    @State private var inputMode = false
    @State private var inputText = ""
    @State private var aiResponse = "System Idle."
    
    @State private var currentMode = "mode1"
    
    @State private var shouldAnimateResponse = true 
    
    @EnvironmentObject var context: AppContext
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var coordinator: WindowCoordinator
    @EnvironmentObject var googleAuthManager: GoogleAuthManager
    @EnvironmentObject var client: SocketClient

    @State private var isListening = false
    @State private var isProcessing = false
    @State private var activeTool: String? = nil
    
    @State private var fullTextViewMode = false
    
    var isExpanded: Bool {
        return isHovering || inputMode || isListening || isProcessing
    }

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            ZStack(alignment: .top) { // Align content to top
                // 1. Dynamic Background
                RoundedRectangle(cornerRadius: isExpanded ? 18 : 25)
                    .fill(themeManager.current.background)
                    .overlay(
                        RoundedRectangle(cornerRadius: isExpanded ? 18 : 25)
                            .strokeBorder(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        themeManager.current.secondary.opacity(0.1),
                                        themeManager.current.secondary.opacity(0.5),
                                        themeManager.current.secondary.opacity(0.1)
                                    ]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: 5)
                    .frame(width: calculateWindowSize().width, height: calculateWindowSize().height, alignment: .top) // Anchor top

                // 2. Content Switcher
                if isExpanded {
                    FullDashboardView(
                        inputMode: $inputMode,
                        inputText: $inputText,
                        isListening: $isListening,
                        isProcessing: $isProcessing,
                        activeTool: $activeTool,
                        shouldAnimate: $shouldAnimateResponse,
                        currentMode: $currentMode,
                        fullTextViewMode: $fullTextViewMode,
                        toggleListening: toggleListening,
                        submitQuery: submitQuery,
                        setUpConnection: setUpConnection
                    )
                    .environmentObject(context)
                    .environmentObject(themeManager)
                    .environmentObject(coordinator)
                    .environmentObject(googleAuthManager)
                    .environmentObject(client)
                    .transition(.opacity.combined(with: .scale))
                } else {
                    CompactStatusView(isProcessing: isProcessing)
                        .transition(.opacity.combined(with: .scale))
                }
            }
        }
        .onHover { hovering in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                self.isHovering = hovering
            }
        }
        .frame(width: Constants.UI.windowWidth, height: Constants.UI.windowHeight, alignment: .top) // Anchor top in outer frame
        .onAppear {
            setUpConnection()
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isExpanded)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: inputMode)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: fullTextViewMode)
    }

    
    // MARK: - Logic
    private func setUpConnection() {
        setupSocketListeners()
        setUpAuthManager()
    }

    private func calculateWindowSize() -> CGSize {
        if !isExpanded {
            return CGSize(width: Constants.UI.overlayWindow.compactWidth, height: Constants.UI.overlayWindow.compactHeight)
        }
        
        if !inputMode {
            return CGSize(width: Constants.UI.overlayWindow.expandedWidth, height: Constants.UI.overlayWindow.expandedHeight)
        }
        
        let height = fullTextViewMode ? Constants.UI.windowHeight : Constants.UI.overlayWindow.inputModeHeight
        
        return CGSize(width: Constants.UI.windowWidth, height: height)
    }

    private func setUpAuthManager() {
        googleAuthManager.startupCheck()
    }

    private func setupSocketListeners() {
        print("🔌 Setting up Socket Listeners")

        client.onReceiveThought = { thoughtText in
            withAnimation {
                self.isProcessing = true
                self.aiResponse = "" 
                self.activeTool = thoughtText.uppercased() 
            }
        }
        
        client.onReceiveResponse = { responseText in
            finishProcessing(response: responseText)
        }

        client.onReceiveImages = { imageDatas in
            for imageData in imageDatas {
                let randomX = CGFloat.random(in: 100...800)
                let randomY = CGFloat.random(in: 100...500)
                coordinator.openDynamicWindow(id: imageData.url, view: AnyView(
                    ImageView(imageData: imageData, windowID: imageData.url) // For simplicity, show first image
                    .environmentObject(themeManager)
                    .environmentObject(coordinator)
                    .frame(width: 600, height: 400)
                    .padding()
                    .background(themeManager.current.background)
                    .cornerRadius(12)
                    .shadow(radius: 10)
                ), size: CGSize(width: 600, height: 400), location: CGPoint(x: randomX, y: randomY))
            }
        }
        
        client.onDisconnect = { errorText in
            finishProcessing(response: "Error: \(errorText)")
        }
    }

    func submitQuery() {
        guard !inputText.isEmpty else { return }
        
        // 1. Capture State
        let query = inputText
        let selectedMode = currentMode.lowercased()
        inputText = ""
        isProcessing = true
        aiResponse = ""
        context.response = ""
        
        // 2. Run Async Work
        Task { @MainActor in
            var base64Image: String? = nil
            
            do {
                base64Image = try await ScreenshotManager.captureMainScreen()
                print("✅ Screenshot captured. Size: \(base64Image?.count ?? 0)")
                
            } catch {
                // --- FIX START ---
                let nsError = error as NSError
                
                // Check for the specific "User Declined" error code (-3801)
                // The domain string is "com.apple.ScreenCaptureKit.SCStreamErrorDomain"
                if nsError.code == -3801 {
                    print("⚠️ Permission Denied. Opening Settings...")
                    openPrivacySettings()
                } else {
                    print("❌ Screenshot Error: \(nsError.localizedDescription)")
                }
                // --- FIX END ---
            }

            // 3. Send message (with or without image)
            client.sendMessageWithImage(query, mode: selectedMode, base64Image: base64Image)
            
            self.activeTool = "WS_STREAM"
        }
    }

    // Helper to open the exact Settings page
    func openPrivacySettings() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
    
    func finishProcessing(response: String) {
        withAnimation {
            isProcessing = false
            activeTool = nil
            shouldAnimateResponse = true
            aiResponse = response
            context.response = response
        }
    }
    
    func toggleListening() {
        withAnimation {
            if isListening {
                isListening = false
                isProcessing = true
                aiResponse = ""
                context.response = ""
                client.sendMessage("Hello (Voice Input)", mode: currentMode.lowercased()) 
            } else {
                isListening = true
                isProcessing = false
                inputMode = false
                // NEW: Text Changed, so we MUST animate
                shouldAnimateResponse = true
                aiResponse = "Listening..."
                context.response = "Listening..."
            }
        }
    }
}

// MARK: - Subviews

struct CompactStatusView: View {
    var isProcessing: Bool
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(themeManager.current.accent)
                .frame(width: 8, height: 8)
                .shadow(color: themeManager.current.accent.opacity(0.8), radius: 5)
            
            Text("RONG-E")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(themeManager.current.text)
                .tracking(2)
        }
        .padding(.horizontal, 20)
        .frame(width: 140, height: 50)
    }
}

struct SpinningRing: View {
    let diameter: CGFloat
    let lineWidth: CGFloat
    let color: Color
    let duration: Double
    
    @State private var rotate = false
    
    var body: some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .frame(width: diameter, height: diameter)
            .rotationEffect(.degrees(rotate ? 360 : 0))
            .animation(.linear(duration: duration).repeatForever(autoreverses: false), value: rotate)
            .onAppear { rotate = true }
    }
}

// Helper: Pulsing Ring
struct PulsingRing: View {
    let diameter: CGFloat
    let lineWidth: CGFloat
    let color: Color
    let duration: Double
    let delay: Double
    
    @State private var pulse = false
    
    var body: some View {
        Circle()
            .stroke(color, lineWidth: lineWidth)
            .frame(width: diameter, height: diameter)
            .opacity(pulse ? 0.2 : 0.8)
            .scaleEffect(pulse ? 1.1 : 1.0)
            .animation(
                .easeInOut(duration: duration)
                    .repeatForever(autoreverses: true)
                    .delay(delay),
                value: pulse
            )
            .onAppear { pulse = true }
    }
}

// Main Energy Core
struct EnergyCore: View {
    @Binding var isListening: Bool
    @Binding var isProcessing: Bool
    let toggleListening: () -> Void

    @EnvironmentObject var context: AppContext
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var socketClient: SocketClient

    private var clientConnectionStatus: Bool {
        socketClient.isConnected
    }

    private let darkRed = Color(red: 0.35, green: 0.02, blue: 0.02)

    private var currentStyle: CoreStyle {
        if !clientConnectionStatus {
            // DISCONNECTED — Dull, lifeless
            return CoreStyle(
                speed: 0.3,
                pulseColor: .gray.opacity(0.4),
                spinColor: .gray.opacity(0.5),
                coreColor: .gray.opacity(0.2),
                glowColors: [.black.opacity(0.4), .gray.opacity(0.3)],
                textColor: themeManager.current.text.opacity(0.5),
                textShadow: .clear
            )
        } else {
            if isListening {
                return CoreStyle(
                    speed: 1.5,
                    pulseColor: .blue.opacity(0.75),
                    spinColor: .cyan.opacity(0.6),
                    coreColor: .blue,
                    glowColors: [.white, .blue.opacity(0.85)],
                    textColor: themeManager.current.text.opacity(0.85),
                    textShadow: .clear
                )

            } else if isProcessing {
                return CoreStyle(
                    speed: 2.0, // Slightly faster to feel "busy"
                    pulseColor: darkRed.opacity(0.9), // More opaque
                    spinColor: darkRed.opacity(0.8),
                    coreColor: darkRed,
                    glowColors: [Color.black.opacity(0.6), darkRed.opacity(0.9)],
                    textColor: .white.opacity(0.9),
                    textShadow: .red.opacity(0.5)
                )

            } else {
                // IDLE — Alive, breathing presence
                return CoreStyle(
                    speed: 0.6,
                    pulseColor: .blue.opacity(0.6),
                    spinColor: .blue.opacity(0.7),
                    coreColor: .gray.opacity(0.3),
                    glowColors: [.gray.opacity(0.5), .black.opacity(0.3)],
                    textColor: themeManager.current.text.opacity(0.75),
                    textShadow: .clear
                )
            }
        }
        
    }

    private var animationKey: String {
        "\(isListening)-\(isProcessing)"
    }

    var body: some View {
        ZStack {

            SpinningRing(
                diameter: 110,
                lineWidth: 2,
                color: currentStyle.spinColor.opacity(0.4),
                duration: 8 / currentStyle.speed
            )
            .id("ring1-\(animationKey)")

            SpinningRing(
                diameter: 90,
                lineWidth: 3,
                color: currentStyle.spinColor.opacity(0.5),
                duration: 5 / currentStyle.speed
            )
            .rotationEffect(.degrees(180))
            .id("ring2-\(animationKey)")

            Group {
                PulsingRing(
                    diameter: 70,
                    lineWidth: 2.5,
                    color: currentStyle.pulseColor,
                    duration: 1.6,
                    delay: 0
                )

                PulsingRing(
                    diameter: 70,
                    lineWidth: 2.5,
                    color: currentStyle.pulseColor,
                    duration: 1.6,
                    delay: 0.8
                )
            }

            Circle()
                .stroke(currentStyle.coreColor.opacity(0.3), lineWidth: 2)
                .frame(width: 60, height: 60)

            Button(action: toggleListening) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: currentStyle.glowColors,
                                center: .center,
                                startRadius: 2,
                                endRadius: 30
                            )
                        )
                        .frame(width: 50, height: 50)

                    Text("RONG-E")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(3)
                        .foregroundColor(currentStyle.textColor)
                        .shadow(color: currentStyle.textShadow, radius: 2)
                        .offset(x: 1.5)
                }
                .shadow(
                    color: isListening
                        ? Color.blue.opacity(0.8)
                        : isProcessing
                            ? darkRed
                            : .clear,
                    radius: isProcessing ? 25 : 22
                )
                .shadow(color: .white.opacity(isProcessing ? 0.1 : 0.8), radius: 10)
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .accessibilityLabel(isListening ? "Stop Listening" : "Start Listening")
            .disabled(!clientConnectionStatus)
        }
        .frame(width: 130, height: 130)
        .padding(.leading, 20)
        .animation(.easeInOut(duration: 0.45), value: animationKey)
    }
}


private struct CoreStyle {
    let speed: Double
    let pulseColor: Color
    let spinColor: Color
    let coreColor: Color
    let glowColors: [Color]
    let textColor: Color
    let textShadow: Color
}

struct FullDashboardView: View {
    @Binding var inputMode: Bool
    @Binding var inputText: String
    @Binding var isListening: Bool
    @Binding var isProcessing: Bool
    @Binding var activeTool: String?
    @Binding var shouldAnimate: Bool
    @Binding var currentMode: String
    @Binding var fullTextViewMode: Bool

    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var context: AppContext
    @EnvironmentObject var coordinator: WindowCoordinator
    @EnvironmentObject var googleAuthManager: GoogleAuthManager
    @EnvironmentObject var socketClient: SocketClient
    
    var toggleListening: () -> Void
    var submitQuery: () -> Void
    var setUpConnection: () -> Void

    func openSettings() {
        coordinator.openSettings()
    }

    func openGoogleService() {
        coordinator.openGoogleService()
    }

    func openWebWindow(query: String) {
        let escapedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "https://www.google.com/search?q=\(escapedQuery)"
        if let url = URL(string: urlString) {
            coordinator.openWebWindow(url: url, size: CGSize(width: 800, height: 600))
        }
    }

    private func calculateWindowSize() -> CGSize {
        if !inputMode {
            return CGSize(width: Constants.UI.overlayWindow.expandedWidth, height: Constants.UI.overlayWindow.expandedHeight)
        }
        
        let height = fullTextViewMode ? Constants.UI.windowHeight : Constants.UI.overlayWindow.inputModeHeight
        
        return CGSize(width: Constants.UI.windowWidth, height: height)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            
            // MARK: - 1. Top Control Row (Fixed Height)
            HStack(spacing: 0) {
                // Left Column
                VStack(alignment: .leading, spacing: 15) {
                    MenuLinkButton(title: "GOOGLE", image: Image(systemName: "globe")) { 
                        print("Google clicked") 
                        openGoogleService()
                    }
                    MenuLinkButton(title: "SETTINGS", image: Image(systemName: "gearshape")) {
                        print("Settings clicked") 
                        openSettings()
                    }
                }
                .padding(.leading, 15)
                .frame(width: 80)

                // Center Core
                ZStack {
                    EnergyCore(
                        isListening: $isListening,
                        isProcessing: $isProcessing,
                        toggleListening: toggleListening
                    )
                    .zIndex(1)
                    .environmentObject(context)
                    .environmentObject(themeManager)
                    .environmentObject(socketClient)

                    // Show radial menu only when typing or thinking
                    if inputMode {
                        Group {
                            // --- RIGHT SIDE ---
                            CircularMenuItem(title: "Shrink", subtitle: "", angle: -30, radius: 90, selected: false) {
                                withAnimation { inputMode.toggle() }
                            }
                            CircularMenuItem(title: "Mode 4", subtitle: context.modes.first(where: { $0.id == 4 })?.name ?? "Mode 4", angle: 0, radius: 90, selected: currentMode == "mode4") {
                                withAnimation { currentMode = "mode4" }
                            }
                            CircularMenuItem(title: "Mode 5", subtitle: context.modes.first(where: { $0.id == 5 })?.name ?? "Mode 5", angle: 30, radius: 90, selected: currentMode == "mode5") {
                                withAnimation { currentMode = "mode5" }
                            }

                            // --- LEFT SIDE ---
                            CircularMenuItem(title: "Mode 1", subtitle: context.modes.first(where: { $0.id == 1 })?.name ?? "Mode 1", angle: -150, radius: 80, selected: currentMode == "mode1") {
                                withAnimation { currentMode = "mode1" }
                            }
                            CircularMenuItem(title: "Mode 2", subtitle: context.modes.first(where: { $0.id == 2 })?.name ?? "Mode 2", angle: -180, radius: 80, selected: currentMode == "mode2") {
                                withAnimation { currentMode = "mode2" }
                            }
                            CircularMenuItem(title: "Mode 3", subtitle: context.modes.first(where: { $0.id == 3 })?.name ?? "Mode 3", angle: 150, radius: 80, selected: currentMode == "mode3") {
                                withAnimation { currentMode = "mode3" }
                            }
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

                // Right Column
                VStack(alignment: .trailing, spacing: 15) {
                    MenuLinkButton(title: "TYPE", image: Image(systemName: "keyboard")) {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            inputMode.toggle()
                        }
                    }
                    MenuLinkButton(title: socketClient.isConnected ? "WORKFLOW" : "CONNECT", image: Image(systemName: "bolt.horizontal")) {
                        print("Reconnect clicked") 
                        if !socketClient.isConnected {
                            socketClient.connect()
                            setUpConnection()
                        } else {
                            print(context.isGoogleConnected ? "Google is connected." : "Google is NOT connected.")
                        }
                    }
                }
                .padding(.trailing, 15)
                .frame(width: 80)
            }
            .frame(height: 140) // Fixed height for top section
            .padding(.top, 10)

            // MARK: - 2. Bottom Content (Flexible Height)
            // We show this section if we are typing OR if there is a response to read
            if inputMode {
                Divider()
                    .background(themeManager.current.secondary.opacity(0.3))
                    .padding(.horizontal, 20)
                    
                // 1. Mode Label (The new display)
                HStack(spacing: 6) {
                    Circle()
                        .fill(themeManager.current.text)
                        .frame(width: 4, height: 4)
                        .opacity(0.8)
                    
                    Text("MODE: \(context.modes.first(where: { $0.id == Int(currentMode.replacingOccurrences(of: "mode", with: "")) })?.name.uppercased() ?? "UNKNOWN")")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1.5) // Spacing for that "Sci-Fi" look
                        .foregroundColor(themeManager.current.text.opacity(0.6))
                    
                    Circle()
                        .fill(themeManager.current.text)
                        .frame(width: 4, height: 4)
                        .opacity(0.8)
                }
                .padding(.vertical, 4)
                
                // The Main Text Input
                TextView (
                    inputText: $inputText,
                    isProcessing: $isProcessing,
                    shouldAnimate: $shouldAnimate,
                    fullTextViewMode: $fullTextViewMode,
                    submitQuery: submitQuery
                )
                .environmentObject(context)
                .environmentObject(themeManager)
                
                // --- NEW: Mode Indicator & Handle ---
                VStack(spacing: 5) {
                    
                    // 2. Resize Handle (Existing Logic)
                    Button(action: { 
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            fullTextViewMode.toggle() 
                        }
                    }) {
                        Capsule()
                            .fill(themeManager.current.text.opacity(0.2)) // Slightly lowered opacity
                            .frame(width: 40, height: 4)
                            .padding(.bottom, 15) // Adjust padding to fit the new label
                            .padding(.horizontal, 20)   
                            .contentShape(Rectangle()) 
                    }
                    .buttonStyle(.plain)
                }
                .background(Color.black.opacity(0.01)) // Expands hit area slightly
            }
        }
        // Main Window Frame Logic
        .frame(
            width: calculateWindowSize().width,
            height: calculateWindowSize().height,
            alignment: .top
        )
    }
}

struct TextView: View {
    @Binding var inputText: String
    @Binding var isProcessing: Bool
    @Binding var shouldAnimate: Bool
    @Binding var fullTextViewMode: Bool
    var submitQuery: () -> Void

    @EnvironmentObject var context: AppContext
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        VStack(spacing: 10) {
            // A. RESPONSE AREA (Scrollable)
            ScrollView {
                if !context.response.isEmpty {
                    Text(context.response)
                        .font(.system(size: 13, weight: .regular, design: .default))
                        .foregroundColor(themeManager.current.text)
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 5)
                } else if isProcessing {
                    Text("Processing...")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(themeManager.current.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 5)
                }
            }
            .frame(maxWidth: .infinity) // Fills available width
            // Takes up all remaining vertical space, pushing Input down
            
            // B. INPUT FIELD (Anchored Bottom)
            HStack {
                TextField(">_", text: $inputText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundColor(themeManager.current.text)
                    .padding(10)
                    .background(themeManager.current.secondary.opacity(0.1))
                    .cornerRadius(8)
                    .onSubmit(submitQuery)
            }
        }
        .padding(.horizontal, 20)
        // This frame ensures the bottom section fills the rest of the window
        .frame(maxWidth: .infinity, maxHeight: .infinity) 
    }
}

struct CircularMenuItem: View {
    let title: String
    let subtitle: String
    let angle: Double // In Degrees
    let radius: CGFloat
    let selected: Bool
    let action: () -> Void

    @State private var isHovering = false
    @EnvironmentObject var themeManager: ThemeManager

    private var xOffset: CGFloat {
        radius * CGFloat(cos(angle * .pi / 180))
    }
    
    private var yOffset: CGFloat {
        radius * CGFloat(sin(angle * .pi / 180))
    }

    var body: some View {
        Button(action: action) {
            // 1. The Anchor: This View defines the geometric center
            Text(title)
                .font(.system(size: 11, weight: selected ? .bold : (isHovering ? .semibold : .medium), design: .monospaced))
                .foregroundColor(selected ? themeManager.current.text : themeManager.current.secondary)
                .shadow(color: selected ? themeManager.current.text.opacity(0.6) : .clear, radius: 4, x: 0, y: 0)
                
                // 2. The Subtitle: Hangs off the title without moving it
                .overlay(alignment: .top) {
                    if !subtitle.isEmpty && (isHovering || selected) {
                        Text(subtitle)
                            .font(.system(size: 8, weight: .light, design: .monospaced))
                            .foregroundColor(themeManager.current.text)
                            .fixedSize() // Prevents subtitle from wrapping weirdly
                            .offset(y: 14) // Push it down below the title
                            
                            // Animation: Slide up from bottom
                            .transition(
                                .asymmetric(
                                    insertion: .opacity.combined(with: .offset(y: 5)),
                                    removal: .opacity.combined(with: .offset(y: 5))
                                )
                            )
                    }
                }
                
                // 3. Hit Area Expansion
                .padding(.vertical, 15) 
                .padding(.horizontal, 12)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                self.isHovering = hovering
            }
        }
        .scaleEffect(isHovering ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isHovering)
        .animation(.easeInOut(duration: 0.2), value: selected)
        .offset(x: xOffset, y: yOffset)
    }
}

// MARK: - Custom Hover Button Component
struct MenuLinkButton: View {
    let title: String
    let image: Image
    let action: () -> Void
    
    @State private var isHovering = false
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        Button(action: action) {
            ZStack {
                image
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
                    .foregroundColor(isHovering ? themeManager.current.accent : themeManager.current.text.opacity(0.7))
                
                Text(title)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(isHovering ? themeManager.current.accent : themeManager.current.text.opacity(0.7))
                    .fixedSize()
                    .offset(y: 15) // Float text below without affecting layout
                    .transition(.opacity)
            }
            .frame(width: 35, height: 35) // Fixed width prevents layout shifts
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain) // Removes default button background/styling
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                self.isHovering = hovering
            }
        }
    }
}
//
//#Preview {
//    struct CorePreviewWrapper: View {
//        @State private var isListening = false
//        @State private var isProcessing = false
//        
//        var body: some View {
//            ZStack {
//                // 1. Dark Background (Essential for glowing effects)
//                Color.black.edgesIgnoringSafeArea(.all)
//                
//                VStack(spacing: 40) {
//                    // 2. The Component
//                    EchoEnergyCore(
//                        isListening: $isListening,
//                        isProcessing: $isProcessing,
//                        toggleListening: {
//                            // Simulate a realistic interaction flow
//                            withAnimation {
//                                if isListening {
//                                    // Stop listening -> Start processing
//                                    isListening = false
//                                    isProcessing = true
//                                    
//                                    // Simulate processing delay (2 seconds)
//                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
//                                        withAnimation {
//                                            isProcessing = false
//                                        }
//                                    }
//                                } else {
//                                    // Start listening
//                                    isListening = true
//                                    isProcessing = false
//                                }
//                            }
//                        }
//                    )
//                    
//                    // 3. Manual Debug Controls
//                    VStack(alignment: .leading, spacing: 10) {
//                        Text("Debug Controls").font(.caption).foregroundColor(.gray)
//                        
//                        Toggle("State: Listening", isOn: $isListening)
//                        Toggle("State: Processing", isOn: $isProcessing)
//                    }
//                    .padding()
//                    .frame(width: 250)
//                    .background(Color.white.opacity(0.1))
//                    .cornerRadius(12)
//                    .foregroundColor(.white)
//                }
//            }
//        }
//    }
//    
//    return CorePreviewWrapper()
//}
