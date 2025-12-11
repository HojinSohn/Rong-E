import SwiftUI
import Combine

// MARK: - Monochrome Style
extension Color {
    static let themeAccent = Color.white
    static let themeBackground = Color.black.opacity(0.6)
    static let themeGray = Color.white.opacity(0.3)
}

struct ContentView: View {
    // --- State ---
    @State private var isHovering = false
    @State private var inputMode = false
    @State private var inputText = ""
    @State private var aiResponse = "System Idle."
    
    @State private var shouldAnimateResponse = true 
    
    @StateObject private var client = EchoSocketClient()

    @State private var isListening = false
    @State private var isProcessing = false
    @State private var activeTool: String? = nil
    
    @FocusState private var isInputFocused: Bool
    
    var isExpanded: Bool {
        return isHovering || inputMode || isListening || isProcessing
    }
    
    var body: some View {
        ZStack {
            // 1. Dynamic Background
            RoundedRectangle(cornerRadius: isExpanded ? 18 : 25)
                .fill(Color.themeBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: isExpanded ? 18 : 25)
                        .strokeBorder(
                            LinearGradient(
                                gradient: Gradient(colors: [.themeGray.opacity(0.1), .themeGray.opacity(0.5), .themeGray.opacity(0.1)]),
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: 5)
                .frame(width: isExpanded ? 600 : 140, height: isExpanded ? 160 : 50)
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isExpanded)

            // 2. Content Switcher
            if isExpanded {
                FullDashboardView(
                    inputMode: $inputMode,
                    inputText: $inputText,
                    aiResponse: $aiResponse,
                    isListening: $isListening,
                    isProcessing: $isProcessing,
                    activeTool: $activeTool,
                    shouldAnimate: $shouldAnimateResponse, // Pass the binding
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
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                self.isHovering = hovering
            }
        }
        .frame(width: 600, height: 160)
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
        }
    }
    
    func toggleListening() {
        withAnimation {
            if isListening {
                isListening = false
                isProcessing = true
                aiResponse = ""
                client.sendMessage("Hello (Voice Input)") 
            } else {
                isListening = true
                isProcessing = false
                inputMode = false
                // NEW: Text Changed, so we MUST animate
                shouldAnimateResponse = true
                aiResponse = "Listening..."
            }
        }
    }
}

// MARK: - Subviews

struct CompactStatusView: View {
    var isProcessing: Bool
    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.white)
                .frame(width: 8, height: 8)
                .shadow(color: .white.opacity(0.8), radius: 5)
            
            Text("ECHO")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .tracking(2)
        }
        .padding(.horizontal, 20)
        .frame(width: 140, height: 50)
    }
}

struct FullDashboardView: View {
    @Binding var inputMode: Bool
    @Binding var inputText: String
    @Binding var aiResponse: String
    @Binding var isListening: Bool
    @Binding var isProcessing: Bool
    @Binding var activeTool: String?
    @Binding var shouldAnimate: Bool // Received from Parent
    
    var isInputFocused: FocusState<Bool>.Binding
    
    var toggleListening: () -> Void
    var submitQuery: () -> Void
    
    var body: some View {
        HStack(spacing: 0) {
            // CENTER: Core
            ZStack {
                Circle().stroke(Color.themeGray.opacity(0.3), lineWidth: 1).frame(width: 80, height: 80)
                if isProcessing {
                    Circle().trim(from: 0, to: 0.75)
                        .stroke(Color.themeAccent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 88, height: 88)
                        .rotationEffect(.degrees(isProcessing ? 360 : 0))
                        .animation(.linear(duration: 1.5).repeatForever(autoreverses: false), value: isProcessing)
                }
                Button(action: toggleListening) {
                    Circle().fill(isListening ? Color.white : Color.black.opacity(0.3))
                        .frame(width: 50, height: 50)
                        .overlay(Image(systemName: isListening ? "mic.fill" : (isProcessing ? "cpu" : "waveform")).font(.system(size: 20)).foregroundColor(isListening ? .black : .white))
                        .shadow(color: isListening ? Color.white.opacity(0.6) : .clear, radius: 15)
                }.buttonStyle(.plain)
            }
            .frame(width: 110).padding(.leading, 20)
            
            // RIGHT: Chat
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    if let tool = activeTool {
                        Label(tool, systemImage: "network").font(.system(size: 9, weight: .bold, design: .monospaced)).padding(4).background(Color.white.opacity(0.2)).cornerRadius(4).foregroundColor(.white)
                    } else {
                        Text("READY").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(Color.gray)
                    }
                    Spacer()
                    Text(inputMode ? "TYPING" : "VOICE").font(.system(size: 9, design: .monospaced)).foregroundColor(inputMode ? .white : .gray)
                }
                .padding(.bottom, 8).padding(.top, 25)
                
                ZStack(alignment: .topLeading) {
                    if inputMode {
                        HStack {
                            Image(systemName: "chevron.right").foregroundColor(.white).font(.system(size: 14, weight: .bold))
                            TextField("", text: $inputText).font(.system(size: 16, design: .monospaced)).foregroundColor(.white).textFieldStyle(.plain).focused(isInputFocused).onSubmit { submitQuery() }.onAppear { isInputFocused.wrappedValue = true }.submitLabel(.send)
                        }
                        .padding(8).background(Color.white.opacity(0.1)).cornerRadius(8).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.2), lineWidth: 1))
                    } else {
                        // Pass the binding here
                        TypewriterView(text: aiResponse, shouldAnimate: $shouldAnimate)
                            .onTapGesture {
                                withAnimation {
                                    inputMode = true
                                    NSApplication.shared.activate(ignoringOtherApps: true)
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

// MARK: - Smart Typewriter View
struct TypewriterView: View {
    let text: String
    @Binding var shouldAnimate: Bool // Controls whether to type or show instantly
    
    @State private var displayedText = ""
    @State private var timer: AnyCancellable?
    @State private var isTyping = false

    var body: some View {
        ScrollView {
            Text(displayedText)
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.9))
                .lineSpacing(4)
                .shadow(color: .black.opacity(0.5), radius: 1, x: 1, y: 1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .bottomTrailing) {
                    if isTyping {
                        Rectangle().fill(Color.white).frame(width: 8, height: 16).opacity(0.8)
                    }
                }
        }
        .onChange(of: text) { newValue in
            // Text changed! We must animate this new text.
            startTyping(newValue, forceAnimate: true)
        }
        .onAppear {
            // View appeared (e.g. expanded from hover). 
            // Check if we should animate or show instantly.
            if shouldAnimate {
                startTyping(text, forceAnimate: true)
            } else {
                // RESTORE STATE: Show full text immediately
                displayedText = text
                isTyping = false
            }
        }
    }
    
    func startTyping(_ fullText: String, forceAnimate: Bool) {
        timer?.cancel()
        
        if !forceAnimate {
            displayedText = fullText
            return
        }
        
        displayedText = ""
        isTyping = true
        var currentIndex = 0
        
        timer = Timer.publish(every: 0.03, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                if currentIndex < fullText.count {
                    let index = fullText.index(fullText.startIndex, offsetBy: currentIndex)
                    displayedText.append(fullText[index])
                    currentIndex += 1
                } else {
                    timer?.cancel()
                    isTyping = false
                    // Mark as complete so we don't re-animate on hover
                    shouldAnimate = false
                }
            }
    }
}