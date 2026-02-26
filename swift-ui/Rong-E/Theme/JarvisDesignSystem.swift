import SwiftUI

// MARK: - Jarvis Design System

// MARK: Color Palette
extension Color {
    // Primary
    static let jarvisBlue = Color(red: 0/255, green: 240/255, blue: 255/255)   // Electric Cyan (primary accent)
    static let jarvisDark = Color(red: 10/255, green: 20/255, blue: 30/255)    // Deep Navy/Black
    static let jarvisDim = Color.gray.opacity(0.3)

    // Semantic Accents
    static let jarvisCyan   = Color(red: 0.0, green: 0.9, blue: 1.0)          // HUD Cyan (≈ jarvisBlue)
    static let jarvisGreen  = Color(red: 0.0, green: 1.0, blue: 0.6)          // Success / Launch
    static let jarvisAmber  = Color(red: 1.0, green: 0.8, blue: 0.0)          // Warning / Files
    static let jarvisPurple = Color(red: 0.7, green: 0.4, blue: 1.0)          // Images / Special
    static let jarvisRed    = Color(red: 1.0, green: 0.4, blue: 0.4)          // Error / Destructive
    static let jarvisOrange = Color(red: 1.0, green: 0.6, blue: 0.2)          // User accent

    // Glow variants (for RongERing)
    static let jarvisLightBlue = Color(red: 0.2, green: 0.85, blue: 1.0)      // Cyan glow
    static let jarvisDeepBlue  = Color(red: 0.0, green: 0.5, blue: 1.0)       // Deep blue edge

    // Surface / Background
    static let jarvisSurface       = Color.black.opacity(0.4)
    static let jarvisSurfaceLight  = Color.black.opacity(0.3)
    static let jarvisSurfaceDark   = Color.black.opacity(0.6)
    static let jarvisSurfaceDeep   = Color.black.opacity(0.8)

    // Text
    static let jarvisTextPrimary   = Color.white
    static let jarvisTextSecondary = Color.white.opacity(0.7)
    static let jarvisTextTertiary  = Color.white.opacity(0.5)
    static let jarvisTextDim       = Color.white.opacity(0.3)

    // Borders
    static let jarvisBorder        = Color.white.opacity(0.05)
    static let jarvisBorderActive  = Color.jarvisBlue.opacity(0.3)
}

// MARK: Font Tokens
enum JarvisFont {
    /// Large display (clock) — 42pt semibold
    static let display  = Font.system(size: 42, weight: .semibold)
    /// Section titles — 14pt semibold
    static let title    = Font.system(size: 14, weight: .semibold)
    /// Section subtitles — 12pt medium
    static let subtitle = Font.system(size: 12, weight: .medium)
    /// Body text — 14pt regular
    static let body     = Font.system(size: 14, weight: .regular)
    /// Monospaced body (input fields, code) — 14pt medium monospaced
    static let mono     = Font.system(size: 14, weight: .medium, design: .monospaced)
    /// Small monospaced labels (mode bar, badges) — 12pt medium monospaced
    static let monoSmall = Font.system(size: 12, weight: .medium, design: .monospaced)
    /// Caption — 11pt regular
    static let caption  = Font.system(size: 11, weight: .regular)
    /// Caption bold monospaced — 10pt bold monospaced
    static let captionMono = Font.system(size: 10, weight: .bold, design: .monospaced)
    /// Tiny label — 9pt bold monospaced
    static let label    = Font.system(size: 9, weight: .bold, design: .monospaced)
    /// Extra small tag — 8pt bold monospaced
    static let tag      = Font.system(size: 8, weight: .bold, design: .monospaced)
    /// Code block — 12pt monospaced
    static let code     = Font.system(size: 12, design: .monospaced)
    /// System header — subheadline monospaced bold
    static let header   = Font.system(.subheadline, design: .monospaced)
    /// Widget label — 13pt medium
    static let widgetLabel = Font.system(size: 13, weight: .medium)
    /// Widget caption — 10pt monospaced
    static let widgetCaption = Font.system(size: 10, design: .monospaced)
    /// Icon — 12pt bold
    static let icon     = Font.system(size: 12, weight: .bold)
}

// MARK: Spacing Tokens
enum JarvisSpacing {
    static let xs:  CGFloat = 4
    static let sm:  CGFloat = 8
    static let md:  CGFloat = 12
    static let lg:  CGFloat = 16
    static let xl:  CGFloat = 20
    static let xxl: CGFloat = 24
}

// MARK: Corner Radius Tokens
enum JarvisRadius {
    static let small:     CGFloat = 4
    static let medium:    CGFloat = 8
    static let large:     CGFloat = 12
    static let card:      CGFloat = 16
    static let container: CGFloat = 24
    static let pill:      CGFloat = 40
}

// MARK: Dimension Tokens
enum JarvisDimension {
    static let headerButtonSize: CGFloat = 32
    static let iconCircleSize:   CGFloat = 32
    static let expandedWidth:    CGFloat = 800
    static let expandedHeight:   CGFloat = 520
    static let minimizedSize:    CGFloat = 80
    static let leftColumnWidth:  CGFloat = 240
}

// MARK: - View Modifiers

struct JarvisPanel: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .background(Color.jarvisSurface)
            .cornerRadius(JarvisRadius.small)
            .overlay(
                RoundedRectangle(cornerRadius: JarvisRadius.small)
                    .stroke(Color.jarvisBorderActive, lineWidth: 1)
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

/// A card-style panel with translucent background and accent border
struct JarvisCard: ViewModifier {
    var accent: Color = .jarvisBlue

    func body(content: Content) -> some View {
        content
            .background(Color.jarvisSurfaceLight)
            .cornerRadius(JarvisRadius.card)
            .overlay(
                RoundedRectangle(cornerRadius: JarvisRadius.card)
                    .stroke(Color.jarvisBorder, lineWidth: 1)
            )
    }
}

/// HUD-style header button background
struct JarvisHeaderButton: ViewModifier {
    var isHovered: Bool = false

    func body(content: Content) -> some View {
        content
            .frame(width: JarvisDimension.headerButtonSize, height: JarvisDimension.headerButtonSize)
            .background(Color.white.opacity(isHovered ? 0.25 : 0.15).cornerRadius(JarvisRadius.medium))
            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
    }
}

/// Widget card background with gradient
struct JarvisWidgetBackground: ViewModifier {
    var accent: Color
    var isHovered: Bool = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: JarvisRadius.large)
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(isHovered ? 0.15 : 0.08), Color.black.opacity(0.4)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .background(.ultraThinMaterial.opacity(0.3))
            )
            .overlay(
                RoundedRectangle(cornerRadius: JarvisRadius.large)
                    .stroke(
                        LinearGradient(
                            colors: [accent.opacity(isHovered ? 0.8 : 0.4), accent.opacity(isHovered ? 0.4 : 0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .cornerRadius(JarvisRadius.large)
    }
}

/// Full-screen Jarvis window background (dark + grid + blur)
struct JarvisWindowBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    Color.black.ignoresSafeArea()
                    TechGridBackground()
                    VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                        .opacity(0.8)
                        .ignoresSafeArea()
                }
            )
    }
}

/// Section header text style
struct JarvisSectionHeader: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.jarvisTextTertiary)
            .textCase(.uppercase)
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
