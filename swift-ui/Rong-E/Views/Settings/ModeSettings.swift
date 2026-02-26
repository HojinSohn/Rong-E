import SwiftUI

struct ModesSettingsView: View {
    @EnvironmentObject var context: AppContext
    @State private var selectedModeID: Int = 1
    
    var body: some View {
        HStack(spacing: 0) {
            // MARK: - Left Sidebar (Mode Selector)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("AVAILABLE MODES")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.jarvisBlue.opacity(0.6))
                    Spacer()
                    Button(action: {
                        let newMode = context.createNewMode()
                        selectedModeID = newMode.id
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 10))
                            .foregroundColor(.jarvisBlue)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 15)
                .padding(.top, 15)
                .padding(.bottom, 10)

                ScrollView {
                    VStack(spacing: 5) {
                        ForEach(context.modes, id: \.id) { mode in
                            ModeSidebarButton(
                                id: mode.id,
                                name: mode.name,
                                isSelected: selectedModeID == mode.id
                            ) {
                                selectedModeID = mode.id
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                }
            }
            .frame(width: 160)
            .background(Color.black.opacity(0.3))
            .overlay(
                Rectangle()
                    .frame(width: 1)
                    .foregroundColor(Color.jarvisBlue.opacity(0.2)),
                alignment: .trailing
            )
            
            // MARK: - Right Detail Area
            ScrollView {
                if let index = context.modes.firstIndex(where: { $0.id == selectedModeID }) {
                    VStack(alignment: .leading, spacing: 25) {
                        
                        // Header
                        HStack {
                            Text("CONFIG // MODE_\(String(format: "%02d", context.modes[index].id))")
                                .font(.system(size: 14, design: .monospaced))
                                .bold()
                                .foregroundColor(.jarvisBlue)
                            Spacer()

                            // Delete button (only show if more than 1 mode)
                            if context.modes.count > 1 {
                                Button(action: {
                                    let modeId = context.modes[index].id
                                    // Select another mode before deleting
                                    if let nextMode = context.modes.first(where: { $0.id != modeId }) {
                                        selectedModeID = nextMode.id
                                    }
                                    context.deleteMode(id: modeId)
                                }) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 12))
                                        .foregroundColor(.red.opacity(0.7))
                                }
                                .buttonStyle(.plain)
                            }

                            Image(systemName: "slider.horizontal.3")
                                .foregroundColor(.jarvisBlue.opacity(0.5))
                        }
                        .padding(.bottom, 5)
                        .overlay(Rectangle().frame(height: 1).foregroundColor(.jarvisBlue.opacity(0.2)), alignment: .bottom)
                        
                        // Section 1: Identity
                        VStack(alignment: .leading, spacing: 8) {
                            Text("IDENTITY DESIGNATION")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.gray)
                            
                            JarvisTextField(text: $context.modes[index].name)
                        }
                        
                        // Section 2: Workflow
                        VStack(alignment: .leading, spacing: 8) {
                            Text("SYSTEM DIRECTIVES (PROMPT)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.gray)
                            
                            JarvisTextEditor(text: $context.modes[index].systemPrompt)
                                .frame(height: 120)
                        }

                        // Section 3: Capabilities
                        VStack(alignment: .leading, spacing: 8) {
                            Text("HARDWARE INTEGRATION")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.gray)
                            
                            JarvisToggle(title: "SCREENSHOT CAPABILITY", isOn: $context.modes[index].isScreenshotEnabled)
                                .padding(10)
                                .background(Color.jarvisBlue.opacity(0.05))
                                .cornerRadius(4)
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.jarvisBlue.opacity(0.2), lineWidth: 1))
                        }
                        

                    }
                    .padding(20)
                } else {
                    // Empty State
                    VStack {
                        Spacer()
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.gray.opacity(0.3))
                        Text("NO DATA SELECTED")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.gray.opacity(0.5))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
    
}

// MARK: - Components

struct ModeSidebarButton: View {
    let id: Int
    let name: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Text(String(format: "%02d", id))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(isSelected ? .jarvisBlue : .gray.opacity(0.5))
                
                Rectangle()
                    .frame(width: 1, height: 12)
                    .foregroundColor(isSelected ? .jarvisBlue : .gray.opacity(0.3))
                
                Text(name.uppercased())
                    .font(.system(size: 11, design: .monospaced))
                    .fontWeight(isSelected ? .bold : .regular)
                    .foregroundColor(isSelected ? .white : .gray)
                    .lineLimit(1)
                
                Spacer()
                
                if isSelected {
                    Circle()
                        .fill(Color.jarvisBlue)
                        .frame(width: 4, height: 4)
                        .modifier(JarvisGlow(active: true))
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 10)
            .background(isSelected ? Color.jarvisBlue.opacity(0.1) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isSelected ? Color.jarvisBlue.opacity(0.5) : Color.clear, lineWidth: 1)
            )
            .cornerRadius(4)
            .contentShape(Rectangle()) // Ensures clickability
        }
        .buttonStyle(.plain)
    }
}

struct JarvisTextField: View {
    @Binding var text: String
    
    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 12, design: .monospaced))
            .padding(10)
            .background(Color.black.opacity(0.4))
            .foregroundColor(.white)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.jarvisBlue.opacity(0.3), lineWidth: 1)
            )
    }
}

struct JarvisTextEditor: View {
    @Binding var text: String
    
    var body: some View {
        TextEditor(text: $text)
            .font(.system(size: 12, design: .monospaced))
            .scrollContentBackground(.hidden) // Removes default white bg
            .padding(5)
            .background(Color.black.opacity(0.4))
            .foregroundColor(.white.opacity(0.9))
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.jarvisBlue.opacity(0.3), lineWidth: 1)
            )
    }
}

