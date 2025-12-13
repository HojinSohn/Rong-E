import SwiftUI
import Combine


struct HoverExpandableBox: View {
    @State private var isHovered = false
    
    var body: some View {
        VStack {
            // Top-aligned box
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(1...20, id: \.self) { i in
                        Text("Test item \(i)")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(5)
                    }
                }
                .padding()
            }
            .frame(width: 150, height: isHovered ? 200 : 50, alignment: .top)
            .background(Color.gray.opacity(0.3))
            .cornerRadius(10)
            .animation(.easeInOut(duration: 0.3), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
            
            Spacer() // Push everything else down
        }
        .frame(width: 300, height: 300) // Container frame
        .padding()
    }
}

struct HoverExpandableBox_Previews: PreviewProvider {
    static var previews: some View {
        TextView()
            .padding()
            .frame(width: 500, height: 500)
            .environmentObject(AppContext())
            .environmentObject(ThemeManager())
    }
}

struct TextView: View {
    @EnvironmentObject var context: AppContext
    @EnvironmentObject var themeManager: ThemeManager
    
    // State
    @State private var displayedText = ""
    @State private var currentFullText = ""
    @State private var cancellables = Set<AnyCancellable>()
    @State private var isTyping = false
    @State private var isHovering = false
    
    // Auto-scroll namespace
    @Namespace private var bottomID
    
    // Configuration constants
    let expandedSize = CGSize(width: 400, height: 400)
    let compactSize = CGSize(width: 400, height: 50)
    
    var body: some View {
        // Main Content Container
        ZStack(alignment: .top) {
            if !context.response.isEmpty {
                contentLayer
            } else {
                // Just empty space
                Spacer()
                .frame(width: expandedSize.width + 40, height: expandedSize.height + 40) // Add padding for the border
            }
        }
        // Apply logic to the container
        .onChange(of: context.response) { newValue in
            handleResponseChange(newValue)
        }
        .onDisappear {
            stopTyping()
        }
    }

    // MARK: - Styles
    private var backgroundStyle: some View {
        RoundedRectangle(cornerRadius: isHovering ? 18 : 25)
            .fill(themeManager.current.background)
            .overlay(
                RoundedRectangle(cornerRadius: isHovering ? 18 : 25)
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
    }

    // MARK: - Expanded Content
    var contentLayer: some View {
        VStack{
            // Main content area
            ScrollView {
                VStack(spacing: 10) {
                    if isHovering {
                        Text(LocalizedStringKey(displayedText + (isTyping ? " ▋" : "")))
                            .font(.system(size: 16, weight: .regular, design: .default))
                            .foregroundColor(themeManager.current.text)
                            .lineSpacing(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .animation(.none, value: displayedText)
                    }
                        
                    // Anchor for auto-scrolling
                    Color.clear
                        .frame(height: 1)
                        .id(bottomID)
                }
                .padding() 
            }
            .frame(width: isHovering ? expandedSize.width : compactSize.width, height: isHovering ? expandedSize.height : compactSize.height, alignment: .top)
            .background(backgroundStyle)
            .cornerRadius(isHovering ? 18 : 25)
            .animation(.easeInOut(duration: 0.3), value: isHovering)
            .onHover { hovering in
                isHovering = hovering
            }

            Spacer() // Push everything else down
        }
        .frame(width: expandedSize.width + 40, height: expandedSize.height + 40) // Add padding for the border
        .padding()
    }
    
    // MARK: - Logic
    private func handleResponseChange(_ newValue: String) {
        stopTyping()
        currentFullText = newValue
        
        if context.shouldAnimate && newValue != displayedText {
            startTyping(newValue)
        } else {
            displayedText = newValue
        }
    }
    
    private func startTyping(_ fullText: String) {
        displayedText = ""
        isTyping = true
        
        let characters = Array(fullText)
        var currentIndex = 0
        
        Timer.publish(every: 0.015, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                if currentIndex < characters.count {
                    displayedText.append(characters[currentIndex])
                    currentIndex += 1
                } else {
                    stopTyping()
                }
            }
            .store(in: &cancellables)
    }
    
    private func stopTyping() {
        cancellables.removeAll()
        isTyping = false
        
        if displayedText != currentFullText {
            displayedText = currentFullText
        }
        
        DispatchQueue.main.async {
            context.shouldAnimate = false
        }
    }
}

// MARK: - Modifiers
extension View {
    func blinkEffect() -> some View {
        self.modifier(BlinkModifier())
    }
}

struct BlinkModifier: ViewModifier {
    @State private var isOn = false
    
    func body(content: Content) -> some View {
        content
            .opacity(isOn ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    isOn = true
                }
            }
    }
}
