import SwiftUI
import Combine

struct ContentView: View {
    // --- State ---
    @State private var isHovering = false
    @State private var inputMode = false
    @State private var inputText = ""
    @State private var aiResponse = "System Idle."
    
    @State private var shouldAnimateResponse = true 
    
    @StateObject private var client = EchoSocketClient()
    
    @EnvironmentObject var context: AppContext
    @EnvironmentObject var themeManager: ThemeManager

    @State private var isListening = false
    @State private var isProcessing = false
    @State private var activeTool: String? = nil
    
    @FocusState private var isInputFocused: Bool
    
    var isExpanded: Bool {
        return isHovering || inputMode || isListening || isProcessing
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
                    .frame(width: isExpanded ? 600 : 140, height: isExpanded ? 160 : 50, alignment: .top) // Anchor top
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isExpanded)

                // 2. Content Switcher
                if isExpanded {
                    FullDashboardView(
                        inputMode: $inputMode,
                        inputText: $inputText,
                        isListening: $isListening,
                        isProcessing: $isProcessing,
                        activeTool: $activeTool,
                        shouldAnimate: $shouldAnimateResponse,
                        isInputFocused: $isInputFocused,
                        toggleListening: toggleListening,
                        submitQuery: submitQuery
                    )
                    .transition(.opacity.combined(with: .scale))
                } else {
                    CompactStatusView(isProcessing: isProcessing)
                        .transition(.opacity.combined(with: .scale))
                }
            }
            Spacer() // push other content down
        }
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                self.isHovering = hovering
            }
        }
        .frame(width: 600, height: 160, alignment: .top) // Anchor top in outer frame
        .onAppear {
            setupSocketListeners()
        }
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
            inputMode = false
            return 
        }
        let query = inputText
        inputText = ""
        inputMode = false
        isProcessing = true
        aiResponse = "" 
        // update context with query
        context.response = ""

        client.sendMessage(query)
        
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
                client.sendMessage("Hello (Voice Input)") 
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

struct SpinningLoader: View {
    @State private var isSpinning = false
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        Circle()
            .trim(from: 0, to: 0.75)
            .stroke(themeManager.current.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .frame(width: 88, height: 88)
            .rotationEffect(.degrees(isSpinning ? 360 : 0))
            .animation(.linear(duration: 1.5).repeatForever(autoreverses: false), value: isSpinning)
            .onAppear {
                isSpinning = true
            }
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
    @Binding var shouldAnimate: Bool // Received from Parent
    
    @EnvironmentObject var themeManager: ThemeManager
    
    var isInputFocused: FocusState<Bool>.Binding
    
    var toggleListening: () -> Void
    var submitQuery: () -> Void
    
    var body: some View {
        @State var isSpinning = false
        HStack(spacing: 0) {
            // CENTER: Core
            EchoEnergyCore(isListening: $isListening, isProcessing: $isProcessing, toggleListening: toggleListening)
            
            // RIGHT: Chat
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    if let tool = activeTool {
                        Label(tool, systemImage: "network").font(.system(size: 9, weight: .bold, design: .monospaced)).padding(4).background(themeManager.current.secondary.opacity(0.2)).cornerRadius(4).foregroundColor(themeManager.current.text)
                    } else {
                        Text("READY").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(themeManager.current.secondary)
                    }
                    Spacer()
                    Text(inputMode ? "TYPING" : "VOICE").font(.system(size: 9, design: .monospaced)).foregroundColor(inputMode ? themeManager.current.text : themeManager.current.secondary)
                }
                .padding(.bottom, 8).padding(.top, 25)
                
                ZStack(alignment: .topLeading) {
                    if inputMode {
                        HStack {
                            Image(systemName: "chevron.right").foregroundColor(themeManager.current.text).font(.system(size: 14, weight: .bold))
                            TextField("", text: $inputText).font(.system(size: 16, design: .monospaced)).foregroundColor(themeManager.current.text).textFieldStyle(.plain).focused(isInputFocused).onSubmit { submitQuery() }.onAppear { isInputFocused.wrappedValue = true }.submitLabel(.send)
                        }
                        .padding(8).background(themeManager.current.secondary.opacity(0.1)).cornerRadius(8).overlay(RoundedRectangle(cornerRadius: 8).stroke(themeManager.current.secondary.opacity(0.2), lineWidth: 1))
                    } else {
                        HStack {
                            Image(systemName: "chevron.right").foregroundColor(themeManager.current.text).font(.system(size: 14, weight: .bold))
                        }
                        .padding(8).background(themeManager.current.secondary.opacity(0.1)).cornerRadius(8).overlay(RoundedRectangle(cornerRadius: 8).stroke(themeManager.current.secondary.opacity(0.2), lineWidth: 1))
                        .onTapGesture {
                            withAnimation {
                                inputMode = true
                            }
                        }
                    }
                }
                .frame(height: 70, alignment: .topLeading)
                Spacer()
            }
            .padding(.horizontal, 20)
        }
        .frame(width: 600, height: 160)
    }
}
