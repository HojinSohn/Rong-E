import SwiftUI

struct ToolDetailWindowView: View {
    @EnvironmentObject var coordinator: WindowCoordinator
    @EnvironmentObject var context: AppContext

    let windowID: String
    let initialTool: ActiveToolInfo?

    @State private var selectedTool: ActiveToolInfo?
    @State private var hoveredTool: String?
    @State private var searchText: String = ""

    private var tools: [ActiveToolInfo] {
        context.activeTools
    }

    private var filteredTools: [ActiveToolInfo] {
        if searchText.isEmpty { return tools }
        return tools.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.source.localizedCaseInsensitiveContains(searchText) ||
            $0.resolvedDescription.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var grouped: [(key: String, tools: [ActiveToolInfo])] {
        let dict = Dictionary(grouping: filteredTools, by: { $0.source })
        return dict.keys.sorted { a, b in
            if a == "base" || a == "built-in" { return true }
            if b == "base" || b == "built-in" { return false }
            if a == "google" { return true }
            if b == "google" { return false }
            return a < b
        }.map { (key: $0, tools: dict[$0] ?? []) }
    }

    private func accentColor(for source: String) -> Color {
        if source == "base" || source == "built-in" { return Color.jarvisCyan }
        if source == "google" { return Color.jarvisGreen }
        return Color.jarvisOrange
    }

    private func sourceIcon(for source: String) -> String {
        if source == "base" || source == "built-in" { return "wrench.and.screwdriver.fill" }
        if source == "google" { return "globe" }
        return "hammer.fill"
    }

    private func toolIcon(for name: String) -> String {
        switch name {
        case "calculator": return "function"
        case "open_application": return "macwindow"
        case "open_chrome_tab": return "safari"
        case "read_memory", "save_to_memory", "append_to_memory": return "brain.head.profile"
        case "google_agent": return "envelope"
        case "web_search": return "magnifyingglass"
        case "get_current_date_time": return "clock"
        case "list_directory": return "folder"
        case "read_file", "collect_files": return "doc.text"
        case "search_knowledge_base": return "books.vertical"
        default: return "gearshape"
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Background with brackets
            TechGridBackground()
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                .opacity(0.8)
                .ignoresSafeArea()

            // Bracket corners
            VStack {
                HStack {
                    CornerBracket(topLeft: true)
                    Spacer()
                    CornerBracket(topLeft: false)
                }
                Spacer()
                HStack {
                    CornerBracket(topLeft: false, rotate: true)
                    Spacer()
                    CornerBracket(topLeft: true, rotate: true)
                }
            }
            .padding(10)
            .allowsHitTesting(false)

            // 4. Content
            VStack(spacing: 0) {
                // Header 
                HStack {
                    Circle()
                        .fill(context.themeAccentColor)
                        .frame(width: 8, height: 8)
                        .modifier(JarvisGlow(active: true))

                    Text("SYSTEM // TOOLS")
                        .font(.system(.subheadline, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundColor(context.themeAccentColor)
                        .tracking(2)

                    Spacer()

                    Text("\(tools.count) LOADED")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.jarvisTextSecondary)

                    Button(action: {
                        coordinator.closeWindow(id: windowID)
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.jarvisTextDim)
                            .modifier(JarvisGlow(active: false))
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 15)
                .background(context.themeAccentColor.opacity(0.05))
                .overlay(Rectangle().frame(height: 1).foregroundColor(context.themeAccentColor.opacity(0.3)), alignment: .bottom)

                // Split pane content
                HStack(spacing: 0) {
                    // Left: Tool list
                    toolListPane
                        .frame(width: 190)

                    // Divider
                    Rectangle()
                        .fill(context.themeAccentColor.opacity(0.15))
                        .frame(width: 1)

                    // Right: Detail
                    detailPane
                }
            }
        }
        .frame(width: 500, height: 500)
        .preferredColorScheme(.dark)
        .onAppear {
            selectedTool = initialTool ?? tools.first
        }
    }

    // MARK: - Tool List Pane

    private var toolListPane: some View {
        VStack(spacing: 0) {
            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.jarvisTextDim)

                TextField("Filter tools…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.jarvisTextPrimary)

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.jarvisTextDim)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.03))
            .overlay(Rectangle().frame(height: 1).foregroundColor(Color.jarvisBorder), alignment: .bottom)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(grouped, id: \.key) { group in
                        let accent = accentColor(for: group.key)

                        // Source header
                        HStack(spacing: 5) {
                            Image(systemName: sourceIcon(for: group.key))
                                .font(.system(size: 8))
                                .foregroundStyle(accent.opacity(0.7))

                            Text(group.key == "base" || group.key == "built-in" ? "BUILT-IN" : group.key.uppercased())
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundStyle(accent.opacity(0.8))

                            Text("·\(group.tools.count)")
                                .font(.system(size: 8, weight: .medium, design: .monospaced))
                                .foregroundStyle(accent.opacity(0.4))

                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.top, 10)
                        .padding(.bottom, 4)

                        // Tools in group
                        ForEach(group.tools, id: \.name) { tool in
                            toolListRow(tool: tool, accent: accent)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .background(Color.black.opacity(0.15))
    }

    private func toolListRow(tool: ActiveToolInfo, accent: Color) -> some View {
        let isSelected = selectedTool?.name == tool.name
        let isHovered = hoveredTool == tool.name

        return HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 1)
                .fill(accent.opacity(isSelected ? 1.0 : isHovered ? 0.7 : 0.3))
                .frame(width: 2, height: 16)

            Image(systemName: toolIcon(for: tool.name))
                .font(.system(size: 9))
                .foregroundStyle(isSelected ? accent : Color.jarvisTextDim)
                .frame(width: 14)

            Text(tool.name)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(isSelected ? accent : isHovered ? Color.jarvisTextPrimary : Color.jarvisTextSecondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(isSelected ? accent.opacity(0.1) : isHovered ? accent.opacity(0.04) : Color.clear)
        .cornerRadius(4)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.15)) {
                selectedTool = tool
            }
        }
        .onHover { h in
            withAnimation(.easeOut(duration: 0.1)) {
                hoveredTool = h ? tool.name : nil
            }
        }
    }

    // MARK: - Detail Pane

    private var detailPane: some View {
        Group {
            if let tool = selectedTool {
                toolDetail(for: tool)
            } else {
                emptyDetail
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyDetail: some View {
        VStack(spacing: 10) {
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 28))
                .foregroundStyle(Color.jarvisTextDim.opacity(0.3))
            Text("Select a tool to view details")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.jarvisTextDim)
        }
    }

    private func toolDetail(for tool: ActiveToolInfo) -> some View {
        let accent = accentColor(for: tool.source)

        return ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                // Tool header
                HStack(spacing: 12) {
                    // Icon circle
                    ZStack {
                        Circle()
                            .fill(accent.opacity(0.15))
                            .frame(width: 40, height: 40)
                        Circle()
                            .stroke(accent.opacity(0.3), lineWidth: 1)
                            .frame(width: 40, height: 40)
                        Image(systemName: toolIcon(for: tool.name))
                            .font(.system(size: 16))
                            .foregroundStyle(accent)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(tool.name)
                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.jarvisTextPrimary)

                        HStack(spacing: 6) {
                            // Source badge
                            Text(tool.source == "base" || tool.source == "built-in" ? "BUILT-IN" : tool.source.uppercased())
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundStyle(accent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(accent.opacity(0.12))
                                .cornerRadius(3)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3)
                                        .stroke(accent.opacity(0.2), lineWidth: 0.5)
                                )

                            // Status dot
                            Circle()
                                .fill(Color.jarvisGreen)
                                .frame(width: 5, height: 5)
                            Text("ACTIVE")
                                .font(.system(size: 7, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.jarvisGreen.opacity(0.8))
                        }
                    }
                }

                // Separator
                Rectangle()
                    .fill(accent.opacity(0.12))
                    .frame(height: 1)

                // Description section
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 5) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 9))
                            .foregroundStyle(accent.opacity(0.6))
                        Text("DESCRIPTION")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(accent.opacity(0.6))
                    }

                    Text(tool.resolvedDescription)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.jarvisTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(4)
                }

                // Metadata section
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 5) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 9))
                            .foregroundStyle(accent.opacity(0.6))
                        Text("METADATA")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(accent.opacity(0.6))
                    }

                    metaRow(label: "Name", value: tool.name, accent: accent)
                    metaRow(label: "Source", value: tool.source, accent: accent)
                    metaRow(label: "Type", value: toolType(for: tool), accent: accent)
                }
            }
            .padding(20)
        }
    }

    private func metaRow(label: String, value: String, accent: Color) -> some View {
        HStack(spacing: 10) {
            Text(label.uppercased())
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.jarvisTextDim)
                .frame(width: 50, alignment: .leading)

            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.jarvisTextPrimary)
                .textSelection(.enabled)

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.03))
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.jarvisBorder.opacity(0.5), lineWidth: 0.5)
        )
    }

    private func toolType(for tool: ActiveToolInfo) -> String {
        if tool.source == "base" || tool.source == "built-in" { return "Built-in function" }
        if tool.source == "google" { return "Google sub-agent" }
        if tool.source.hasPrefix("mcp:") { return "MCP server tool" }
        return "External tool"
    }
}
