import SwiftUI

struct ModesSettingsView: View {
    @EnvironmentObject var context: AppContext
    @State private var selectedModeID: Int = 1
    
    // Define the available tools in your system
    let allTools = Constants.Tools.availableTools
    
    var body: some View {
        HStack(spacing: 0) {
            // MARK: - Left Sidebar (Mode Selector)
            ScrollView {
                Text("Modes")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.top, 10)
                
                ForEach(context.modes, id: \.id) { mode in
                    ModeSidebarButton(
                        title: "Mode \(mode.id)",
                        subtitle: mode.name,
                        isSelected: selectedModeID == mode.id
                    ) {
                        selectedModeID = mode.id
                    }
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.2))
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            // MARK: - Right Detail Area
            ScrollView {
                if let index = context.modes.firstIndex(where: { $0.id == selectedModeID }) {
                    VStack(alignment: .leading, spacing: 20) {
                        
                        // Section 1: Identity
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Identity Name")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("Name", text: $context.modes[index].name)
                                .textFieldStyle(PlainTextFieldStyle())
                                .padding(8)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(6)
                        }
                        
                        // Section 2: Workflow / System Prompt
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Workflow & System Instructions")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            TextEditor(text: $context.modes[index].systemPrompt)
                                .font(.system(.body, design: .monospaced))
                                .frame(height: 100)
                                .scrollContentBackground(.hidden)
                                .padding(4)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(6)
                        }
                        
                        // Section 3: Tools Selection
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Allowed Tools")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 10) {
                                ForEach(allTools, id: \.self) { tool in
                                    ToolToggle(
                                        toolName: tool,
                                        isSelected: context.modes[index].enabledTools.contains(tool)
                                    ) {
                                        toggleTool(tool, for: index)
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                } else {
                    Text("Select a mode")
                        .foregroundColor(.gray)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    // Helper Logic
    func toggleTool(_ tool: String, for index: Int) {
        if context.modes[index].enabledTools.contains(tool) {
            context.modes[index].enabledTools.remove(tool)
        } else {
            context.modes[index].enabledTools.insert(tool)
        }
    }
}

// MARK: - Components

struct ModeSidebarButton: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(isSelected ? .white : .gray)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(isSelected ? .white.opacity(0.8) : .gray.opacity(0.5))
                        .lineLimit(1)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(isSelected ? Color.blue.opacity(0.3) : Color.clear)
            .cornerRadius(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 5)
    }
}

struct ToolToggle: View {
    let toolName: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .green : .gray)
                Text(toolName)
                    .font(.caption)
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(8)
            .background(isSelected ? Color.green.opacity(0.2) : Color.white.opacity(0.05))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.green.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}