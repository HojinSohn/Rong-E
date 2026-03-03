import SwiftUI

// MARK: - Theme Settings View
struct ThemeSettingsView: View {
    @EnvironmentObject var context: AppContext

    private let accentOptions: [(name: String, label: String, color: Color)] = [
        ("cyan",   "CYAN",   .jarvisCyanFixed),
        ("green",  "GREEN",  Color(red: 0.0, green: 1.0, blue: 0.6)),
        ("purple", "PURPLE", Color(red: 0.7, green: 0.4, blue: 1.0)),
        ("amber",  "AMBER",  Color(red: 1.0, green: 0.8, blue: 0.0)),
        ("orange", "ORANGE", Color(red: 1.0, green: 0.6, blue: 0.2)),
        ("red",    "RED",    Color(red: 1.0, green: 0.4, blue: 0.4)),
    ]

    private let chatFontOptions: [(name: String, label: String, color: Color)] = [
        ("white",  "WHITE",  .white),
        ("accent", "ACCENT", .gray),  // placeholder – real color shown dynamically
        ("green",  "GREEN",  Color(red: 0.0, green: 1.0, blue: 0.6)),
        ("amber",  "AMBER",  Color(red: 1.0, green: 0.8, blue: 0.0)),
        ("purple", "PURPLE", Color(red: 0.7, green: 0.4, blue: 1.0)),
        ("orange", "ORANGE", Color(red: 1.0, green: 0.6, blue: 0.2)),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {

                // MARK: Section 1 – Accent Color
                VStack(alignment: .leading, spacing: 10) {
                    Text("ACCENT COLOR")
                        .font(.caption)
                        .foregroundColor(context.themeAccentColor.opacity(0.7))
                        .tracking(1)

                    Text("Choose the primary HUD accent used across the interface.")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.jarvisTextDim)

                    // Color grid
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(accentOptions, id: \.name) { option in
                            AccentColorButton(
                                label: option.label,
                                color: option.color,
                                isSelected: context.themeAccentColorName == option.name
                            ) {
                                context.themeAccentColorName = option.name
                                context.saveSettings()
                            }
                        }
                    }
                }
                .modifier(JarvisPanel())

                // MARK: Section 2 – Chat Font Color
                VStack(alignment: .leading, spacing: 10) {
                    Text("CHAT FONT COLOR")
                        .font(.caption)
                        .foregroundColor(context.themeAccentColor.opacity(0.7))
                        .tracking(1)

                    Text("Choose the text color for chat messages and UI labels.")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.jarvisTextDim)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(chatFontOptions, id: \.name) { option in
                            let displayColor = option.name == "accent" ? context.themeAccentColor : option.color
                            AccentColorButton(
                                label: option.label,
                                color: displayColor,
                                isSelected: context.themeChatFontColorName == option.name
                            ) {
                                context.themeChatFontColorName = option.name
                                context.saveSettings()
                            }
                        }
                    }

                    // Live preview
                    HStack(spacing: 8) {
                        Text("PREVIEW:")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.jarvisTextDim)
                        Text("The quick fox jumps over the lazy dog.")
                            .font(JarvisFont.body)
                            .foregroundColor(context.themeChatFontColor)
                    }
                    .padding(8)
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(JarvisRadius.small)
                }
                .modifier(JarvisPanel())

                // MARK: Section 3 – Background Opacity
                VStack(alignment: .leading, spacing: 10) {
                    Text("BACKGROUND")
                        .font(.caption)
                        .foregroundColor(context.themeAccentColor.opacity(0.7))
                        .tracking(1)

                    Text("Make the overlay background solid instead of translucent glass.")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.jarvisTextDim)

                    JarvisToggle(title: "Opaque Background", isOn: $context.themeOpaqueBackground)
                        .onChange(of: context.themeOpaqueBackground) {
                            context.saveSettings()
                        }
                }
                .modifier(JarvisPanel())

                // MARK: Section 4 – Animations
                VStack(alignment: .leading, spacing: 10) {
                    Text("ANIMATIONS")
                        .font(.caption)
                        .foregroundColor(context.themeAccentColor.opacity(0.7))
                        .tracking(1)

                    Text("Disable UI animations for a static, low-motion experience.")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.jarvisTextDim)

                    JarvisToggle(title: "Disable Animations", isOn: $context.themeAnimationsDisabled)
                        .onChange(of: context.themeAnimationsDisabled) {
                            context.saveSettings()
                        }
                }
                .modifier(JarvisPanel())
            }
        }
    }
}

// MARK: - Accent Color Button
private struct AccentColorButton: View {
    let label: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)
                    .shadow(color: isSelected ? color.opacity(0.6) : .clear, radius: 4)

                Text(label)
                    .font(.system(size: 9, design: .monospaced))
                    .fontWeight(isSelected ? .bold : .regular)
                    .foregroundColor(isSelected ? .jarvisTextPrimary : .jarvisTextDim)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(isSelected ? color.opacity(0.15) : Color.black.opacity(0.3))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isSelected ? color.opacity(0.6) : Color.jarvisBorder, lineWidth: 1)
            )
            .cornerRadius(4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
