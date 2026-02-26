import SwiftUI

// MARK: - Jarvis Design System

extension Color {
    static let jarvisBlue = Color(red: 0/255, green: 240/255, blue: 255/255) // Electric Cyan
    static let jarvisDark = Color(red: 10/255, green: 20/255, blue: 30/255)  // Deep Navy/Black
    static let jarvisDim = Color.gray.opacity(0.3)
}

struct JarvisPanel: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .background(Color.black.opacity(0.4))
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.jarvisBlue.opacity(0.3), lineWidth: 1)
            )
    }
}

struct JarvisGlow: ViewModifier {
    var active: Bool
    func body(content: Content) -> some View {
        content
            .shadow(color: active ? .jarvisBlue : .clear, radius: 8, x: 0, y: 0)
    }
}

// A technical background grid pattern
struct TechGridBackground: View {
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let width = geometry.size.width
                let height = geometry.size.height
                let spacing: CGFloat = 40
                
                for i in 0...Int(width/spacing) {
                    path.move(to: CGPoint(x: CGFloat(i)*spacing, y: 0))
                    path.addLine(to: CGPoint(x: CGFloat(i)*spacing, y: height))
                }
                for i in 0...Int(height/spacing) {
                    path.move(to: CGPoint(x: 0, y: CGFloat(i)*spacing))
                    path.addLine(to: CGPoint(x: width, y: CGFloat(i)*spacing))
                }
            }
            .stroke(Color.jarvisBlue.opacity(0.05), lineWidth: 1)
        }
    }
}

struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// Helper: Decorative Corner Brackets
struct CornerBracket: View {
    var topLeft: Bool
    var rotate: Bool = false
    
    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 20))
            path.addLine(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 20, y: 0))
        }
        .stroke(Color.jarvisBlue.opacity(0.6), lineWidth: 2)
        .frame(width: 20, height: 20)
        .rotationEffect(rotate ? .degrees(180) : .degrees(0))
        .scaleEffect(x: topLeft ? 1 : -1, y: 1)
    }
}

struct JarvisTabButton: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                Text(title)
                    .font(.system(size: 10, design: .monospaced))
                    .bold()
            }
            // Fix 1: Brighter gray for unselected state so it's visible on black
            .foregroundColor(isSelected ? .jarvisBlue : .white.opacity(0.4))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isSelected ? Color.jarvisBlue.opacity(0.1) : Color.clear)
            .overlay(
                Rectangle()
                    .frame(height: 2)
                    .foregroundColor(isSelected ? .jarvisBlue : .clear),
                alignment: .bottom
            )
            // Fix 2: Makes the entire area clickable even if background is clear
            .contentShape(Rectangle()) 
        }
        .buttonStyle(BorderlessButtonStyle())
    }
}
