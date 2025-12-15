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
    
    @StateObject private var client = EchoSocketClient()
    
    @EnvironmentObject var context: AppContext
    @EnvironmentObject var themeManager: ThemeManager

    @State private var isListening = false
    @State private var isProcessing = false
    @State private var activeTool: String? = nil
    
    var isExpanded: Bool {
        return isHovering || inputMode || isListening || isProcessing
    }

    private func updateOverlayWidth() {
        let newWidth: CGFloat = isExpanded ? (inputMode ? 500 : 300) : 140
        
        // Only update if the value actually changed to prevent infinite loops
        if context.overlayWidth != newWidth {
            context.overlayWidth = newWidth
            print("Updated overlay width to: \(context.overlayWidth)")
        }
        print("Overlay width updated to: \(newWidth)")
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
                    .frame(width: isExpanded ? (inputMode ? 500 : 300) : 140, height: isExpanded ? (inputMode ? 300 : 160) : 50, alignment: .top) // Anchor top

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
                        toggleListening: toggleListening,
                        submitQuery: submitQuery
                    )
                    .environmentObject(context)
                    .environmentObject(themeManager)
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
        .frame(width: 500, height: 300, alignment: .top) // Anchor top in outer frame
        .onAppear {
            setupSocketListeners()
        }
        .onChange(of: inputMode) { _ in
            updateOverlayWidth()
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isExpanded)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: inputMode)
    }

    
    // MARK: - Logic
    func setupSocketListeners() {
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
        
        client.onDisconnect = { errorText in
            finishProcessing(response: "Error: \(errorText)")
        }
    }

    func submitQuery() {
        guard !inputText.isEmpty else { 
            return 
        }
        let query = inputText
        let selectedMode = currentMode.lowercased()
        inputText = ""
        isProcessing = true
        aiResponse = "" 
        // update context with query
        context.response = ""

        client.sendMessage(query, mode: selectedMode)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.activeTool = "WS_STREAM"
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
            
            Text("ECHO")
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
struct EchoEnergyCore: View {
    @Binding var isListening: Bool
    @Binding var isProcessing: Bool
    let toggleListening: () -> Void
    
    var body: some View {
        ZStack {
            // Outermost Ring - Slow rotation
            SpinningRing(diameter: 110, lineWidth: 1.5, color: .cyan.opacity(0.4), duration: 8)
            
            // Second Ring - Medium rotation (opposite direction)
            SpinningRing(diameter: 90, lineWidth: 2, color: .blue.opacity(0.5), duration: 5)
                .rotationEffect(.degrees(180))
            
            // Third Ring - Pulsing
            PulsingRing(diameter: 70, lineWidth: 2.5, color: .blue.opacity(0.6), duration: 1.5, delay: 0)
            
            // Fourth Ring - Pulsing (offset timing)
            PulsingRing(diameter: 70, lineWidth: 2.5, color: .white.opacity(0.4), duration: 1.5, delay: 0.75)
            
            // Static Ring - Always visible
            Circle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                .frame(width: 60, height: 60)
            
            // Core Button
            Button(action: toggleListening) {
                ZStack {
                    // Core Glow
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: isListening ? 
                                    [.white, .blue.opacity(0.8)] : 
                                    [.gray.opacity(0.5), .black.opacity(0.3)],
                                center: .center,
                                startRadius: 5,
                                endRadius: 25
                            )
                        )
                        .frame(width: 50, height: 50)
                    
                    // --- UPDATED TEXT STYLE ---
                    Text("ECHO")
                        // Size 10 (Small), Heavy Weight (Bold), Default Design (Cleanest)
                        .font(.system(size: 10, weight: .heavy, design: .default))
                        // Dynamic color based on state
                        .foregroundColor(isListening ? .black.opacity(0.8) : .white.opacity(0.9))
                        // Wide spacing makes it look "Techy"
                        .tracking(3)
                        // Tiny shadow to make it readable over the glow
                        .shadow(color: isListening ? .clear : .black.opacity(0.5), radius: 1, x: 0, y: 1)
                }
                .shadow(color: isListening ? Color.blue.opacity(0.8) : .clear, radius: 20)
                .shadow(color: isListening ? Color.white.opacity(0.6) : .clear, radius: 10)
            }
            .buttonStyle(.plain)
        }
        .frame(width: 130, height: 130)
        .padding(.leading, 20)
    }
}
struct FullDashboardView: View {
    @Binding var inputMode: Bool
    @Binding var inputText: String
    @Binding var isListening: Bool
    @Binding var isProcessing: Bool
    @Binding var activeTool: String?
    @Binding var shouldAnimate: Bool
    @Binding var currentMode: String
    
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var context: AppContext
    
    var toggleListening: () -> Void
    var submitQuery: () -> Void

    
    var body: some View {
        VStack(spacing: 0) {
            
            // MARK: - 1. Top Control Row (Fixed Height)
            HStack(spacing: 0) {
                // Left Column
                VStack(alignment: .leading, spacing: 15) {
                    MenuLinkButton(title: "HISTORY") { print("History clicked") }
                    MenuLinkButton(title: "SETTINGS") { print("Settings clicked") }
                }
                .padding(.leading, 15)
                .frame(width: 80)

                // Center Core
                ZStack {
                    EchoEnergyCore(
                        isListening: $isListening,
                        isProcessing: $isProcessing,
                        toggleListening: toggleListening
                    )
                    .zIndex(1)

                    // Show radial menu only when typing or thinking
                    if inputMode {
                        Group {
                            // --- RIGHT SIDE ---
                            CircularMenuItem(title: "Shrink", angle: -30, radius: 90, selected: false) {
                                withAnimation { inputMode.toggle() }
                            }
                            CircularMenuItem(title: "Mode 4", angle: 0, radius: 90, selected: currentMode == "mode4") {
                                withAnimation { currentMode = "mode4" }
                            }
                            CircularMenuItem(title: "Mode 5", angle: 30, radius: 90, selected: currentMode == "mode5") {
                                withAnimation { currentMode = "mode5" }
                            }

                            // --- LEFT SIDE ---
                            CircularMenuItem(title: "Mode 1", angle: -150, radius: 80, selected: currentMode == "mode1") {
                                withAnimation { currentMode = "mode1" }
                            }
                            CircularMenuItem(title: "Mode 2", angle: -180, radius: 80, selected: currentMode == "mode2") {
                                withAnimation { currentMode = "mode2" }
                            }
                            CircularMenuItem(title: "Mode 3", angle: 150, radius: 80, selected: currentMode == "mode3") {
                                withAnimation { currentMode = "mode3" }
                            }
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

                // Right Column
                VStack(alignment: .trailing, spacing: 15) {
                    MenuLinkButton(title: "TYPE") {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            inputMode.toggle()
                        }
                    }
                    MenuLinkButton(title: "DEBUG") { print("Debug clicked") }
                }
                .padding(.trailing, 15)
                .frame(width: 80)
            }
            .frame(height: 140) // Fixed height for top section
            .padding(.top, 10)

            // MARK: - 2. Bottom Content (Flexible Height)
            // We show this section if we are typing OR if there is a response to read
            if inputMode {
                TextView (
                    inputText: $inputText,
                    isProcessing: $isProcessing,
                    shouldAnimate: $shouldAnimate,
                    submitQuery: submitQuery
                )
                .environmentObject(context)
                .environmentObject(themeManager)
            }
        }
        // Main Window Frame Logic
        .frame(
            width: inputMode ? 500 : 300, 
            height: inputMode ? 300 : 160, 
            alignment: .top
        )
    }
}

struct TextView: View {
    @Binding var inputText: String
    @Binding var isProcessing: Bool
    @Binding var shouldAnimate: Bool
    var submitQuery: () -> Void

    @EnvironmentObject var context: AppContext
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        VStack(spacing: 10) {
            Divider()
                .background(themeManager.current.secondary.opacity(0.3))
                .padding(.horizontal, 20)
            
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
        .padding(.bottom, 15)
        // This frame ensures the bottom section fills the rest of the window
        .frame(maxWidth: .infinity, maxHeight: .infinity) 
    }
}

struct CircularMenuItem: View {
    let title: String
    let angle: Double // In Degrees
    let radius: CGFloat
    let selected: Bool
    let action: () -> Void

    @State private var isHovering = false
    @EnvironmentObject var themeManager: ThemeManager

    // Convert Degrees to Radian for swift math
    private var xOffset: CGFloat {
        radius * CGFloat(cos(angle * .pi / 180))
    }
    
    private var yOffset: CGFloat {
        radius * CGFloat(sin(angle * .pi / 180))
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: isHovering ? .heavy : .medium, design: .monospaced))
                .foregroundColor(selected ? themeManager.current.text : (isHovering ? themeManager.current.text : themeManager.current.secondary))
                .underline(selected, color: themeManager.current.text.opacity(selected ? 1.0 : 0.5))
                .frame(height: 15) 
        }
        .buttonStyle(.plain) // Removes default button background/styling
        .onHover { hovering in
            self.isHovering = hovering
        }
        .offset(x: xOffset, y: yOffset)
    }
}

// MARK: - Custom Hover Button Component
struct MenuLinkButton: View {
    let title: String
    let action: () -> Void
    
    @State private var isHovering = false
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        Button(action: action) {
            Text(title)
                // 1. Change weight on hover
                .font(.system(size: 10, weight: isHovering ? .heavy : .medium, design: .monospaced))
                .foregroundColor(themeManager.current.text)
                // 2. Add Underline
                .underline(isHovering, color: themeManager.current.text.opacity(isHovering ? 1.0 : 0.5))
                // 4. Fixed frame to prevent layout jumping when font gets bold/wider
                .frame(height: 15) 
        }
        .buttonStyle(.plain) // Removes default button background/styling
        .onHover { hovering in
            self.isHovering = hovering
        }
    }
}
