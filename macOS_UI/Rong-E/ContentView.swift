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
    
    @StateObject private var client = SocketClient()
    
    @EnvironmentObject var context: AppContext
    @EnvironmentObject var themeManager: ThemeManager

    @State private var isListening = false
    @State private var isProcessing = false
    @State private var activeTool: String? = nil
    
    @State private var fullTextViewMode = false
    
    var isExpanded: Bool {
        return isHovering || inputMode || isListening || isProcessing
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
                        toggleListening: toggleListening,
                        submitQuery: submitQuery,
                        fullTextViewMode: $fullTextViewMode
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
        .frame(width: Constants.UI.windowWidth, height: Constants.UI.windowHeight, alignment: .top) // Anchor top in outer frame
        .onAppear {
            setupSocketListeners()
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isExpanded)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: inputMode)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: fullTextViewMode)
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
struct EchoEnergyCore: View {
    @Binding var isListening: Bool
    @Binding var isProcessing: Bool
    let toggleListening: () -> Void

    private let darkRed = Color(red: 0.35, green: 0.02, blue: 0.02)

    private var currentStyle: CoreStyle {
        if isListening {
            return CoreStyle(
                speed: 1.5,
                pulseColor: .blue.opacity(0.75),
                spinColor: .cyan.opacity(0.6),
                coreColor: .blue,
                glowColors: [.white, .blue.opacity(0.85)],
                textColor: .black.opacity(0.85),
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
                textColor: .white.opacity(0.75),
                textShadow: .clear
            )
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
    
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var context: AppContext
    
    var toggleListening: () -> Void
    var submitQuery: () -> Void

    @Binding var fullTextViewMode: Bool

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
                    fullTextViewMode: $fullTextViewMode,
                    submitQuery: submitQuery,
                )
                .environmentObject(context)
                .environmentObject(themeManager)
                Button(action: { 
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        fullTextViewMode.toggle() 
                    }
                }) {
                    Capsule()
                        .fill(themeManager.current.text.opacity(0.3))
                        .frame(width: 40, height: 4)
                        .padding(.vertical, 15)     
                        .padding(.horizontal, 20)   
                        .contentShape(Rectangle()) 
                }
                .buttonStyle(.plain)
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
