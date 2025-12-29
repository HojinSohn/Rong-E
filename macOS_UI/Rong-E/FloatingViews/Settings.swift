import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var coordinator: WindowCoordinator
    @EnvironmentObject var context: AppContext
    @EnvironmentObject var themeManager: ThemeManager
    
    // Pass the ID so we can close this specific window
    let windowID: String
    
    var body: some View {
        ZStack {
            // 1. Unified Background
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                .opacity(0.9)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // 2. Custom Title Bar
                HStack {
                    Text("Settings")
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer()
                    Button(action: {
                        coordinator.closeWindow(id: windowID)
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)
                }
                .padding()
                .background(Color.black.opacity(0.2))
                
                // 3. Tabbed Content
                TabView {
                    GeneralSettingsView()
                        .tabItem {
                            Label("General", systemImage: "gearshape")
                        }
                    
                    AppearanceSettingsView()
                        .tabItem {
                            Label("Appearance", systemImage: "paintbrush")
                        }

                    ModesSettingsView()
                        .tabItem {
                            Label("Modes", systemImage: "slider.horizontal.3")
                        }
                    
                    AboutSettingsView()
                        .tabItem {
                            Label("About", systemImage: "info.circle")
                        }
                }
                .padding()
            }
        }
        .frame(width: 450, height: 350) // Fixed size for settings looks best
        .colorScheme(.dark) // Forces dark mode for the HUD look
    }
}

// MARK: - Sub-Views for Tabs

struct GeneralSettingsView: View {
    @EnvironmentObject var context: AppContext
    
    var body: some View {
        Form {
            Section {
                // Note: You will need a binding for these, or use @AppStorage for persistence
                Toggle("Launch at Login", isOn: .constant(true))
                Toggle("Play Sound Effects", isOn: .constant(false))
            } header: {
                Text("System")
            }
            
            Section {
                // ✅ FIX: Use $context to create a binding
                TextField("AI API Key", text: $context.aiApiKey)
                    .textFieldStyle(.roundedBorder) // Added style for better visibility
            } header: {
                Text("Integrations")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden) // Makes form transparent to see blur
    }
}

struct AppearanceSettingsView: View {
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Select Theme:")
                .font(.headline)
            
            HStack(spacing: 15) {
                // Theme Button: Dark
                ThemeButton(
                    title: "Dark",
                    isSelected: themeManager.current.name == "Dark", 
                    action: { themeManager.switchToDark() }
                )
                
                // Theme Button: Light
                ThemeButton(
                    title: "Light",
                    isSelected: themeManager.current.name == "Light",
                    action: { themeManager.switchToLight() }
                )
                
                // Theme Button: Cyberpunk
                ThemeButton(
                    title: "Cyberpunk",
                    isSelected: themeManager.current.name == "Cyberpunk",
                    action: { themeManager.switchToCyberpunk() }
                )
            }
            Spacer()
        }
        .padding()
    }
}

// Helper view to clean up the Appearance code
struct ThemeButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(title) {
            action()
        }
        .padding()
        .background(isSelected ? Color.blue.opacity(0.7) : Color.gray.opacity(0.3))
        .foregroundColor(.white)
        .cornerRadius(8)
        .buttonStyle(.plain) // Important for custom background buttons
    }
}

struct AboutSettingsView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var context: AppContext

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "app.dashed")
                .resizable()
                .frame(width: 60, height: 60)
                .foregroundColor(.white)
            
            Text("RongE App")
                .font(.title2.bold())
            
            Text("Version 1.0.0 (Beta)")
                .foregroundColor(.gray)
            
            Spacer()
            
            Text("© 2025 Hojin Sohn")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("RongE is an AI-powered macOS application designed to enhance your productivity and creativity.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 5)
        }
        .padding()
    }
}

// Helper for Blur Background (macOS Standard)
struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
        visualEffectView.state = .active
        return visualEffectView
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
