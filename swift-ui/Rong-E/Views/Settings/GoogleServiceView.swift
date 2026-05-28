import SwiftUI
import UniformTypeIdentifiers

struct GoogleServiceView: View {
    @EnvironmentObject var context: AppContext
    @EnvironmentObject var coordinator: WindowCoordinator
    @EnvironmentObject var googleAuthManager: GoogleAuthManager

    let windowID: String

    @State private var isShowingAddSheet = false
    @StateObject var sheetManager = SpreadsheetConfigManager.shared

    var connectionStatus: ConnectionStatus {
        context.isGoogleConnected ? .connected : .disconnected
    }

    enum ConnectionStatus {
        case disconnected, connecting, connected
        var color: Color {
            switch self {
            case .disconnected: return .jarvisRed
            case .connecting: return .jarvisAmber
            case .connected: return .jarvisBlue
            }
        }
        var label: String {
            switch self {
            case .disconnected: return "OFFLINE"
            case .connecting: return "ESTABLISHING..."
            case .connected: return "ONLINE"
            }
        }
    }

    var body: some View {
        ZStack {
            // 1. Deep Background
            Color.black.ignoresSafeArea()
            
            // 2. Tech Grid & Blur
            TechGridBackground()
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                .opacity(0.8)
                .ignoresSafeArea()
            
            // 3. Decorative HUD Corners
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

            // 4. Content Frame
            VStack(spacing: 0) {
                // Header
                HStack {
                    Circle()
                        .fill(context.themeAccentColor)
                        .frame(width: 8, height: 8)
                        .modifier(JarvisGlow(active: true))
                    
                    Text("SYSTEM // GOOGLE_SERVICES")
                        .font(.system(.subheadline, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundColor(context.themeAccentColor)
                        .tracking(2)
                    
                    Spacer()
                    
                    // Status Badge
                    HStack(spacing: 6) {
                        Text("STATUS:")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.jarvisTextDim)
                        Text(connectionStatus.label)
                            .font(.system(size: 10, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundColor(connectionStatus.color)
                            .shadow(color: connectionStatus.color.opacity(0.8), radius: 5)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(4)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(connectionStatus.color.opacity(0.3), lineWidth: 1))

                    Spacer().frame(width: 10)
                    
                    Button(action: { coordinator.closeWindow(id: windowID) }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.jarvisTextDim)
                            .modifier(JarvisGlow(active: false))
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .contentShape(Rectangle())
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 15)
                .background(context.themeAccentColor.opacity(0.05))
                .overlay(Rectangle().frame(height: 1).foregroundColor(context.themeAccentColor.opacity(0.3)), alignment: .bottom)
                
                // Main Content
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        backendSection

                        // Section Divider
                        HStack {
                            Rectangle().frame(height: 1).foregroundColor(context.themeAccentColor.opacity(0.3))
                            Text("AUTH")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(context.themeAccentColor.opacity(0.7))
                            Rectangle().frame(height: 1).foregroundColor(context.themeAccentColor.opacity(0.3))
                        }
                        .padding(.vertical, 5)

                        authSection

                        // Section Divider
                        HStack {
                            Rectangle().frame(height: 1).foregroundColor(context.themeAccentColor.opacity(0.3))
                            Text("RESOURCES")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(context.themeAccentColor.opacity(0.7))
                            Rectangle().frame(height: 1).foregroundColor(context.themeAccentColor.opacity(0.3))
                        }
                        .padding(.vertical, 5)

                        resourcesSection
                    }
                    .padding(20)
                }
            }
        }
        .frame(width: 500, height: 500)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $isShowingAddSheet) {
            AddSheetModal(isPresented: $isShowingAddSheet) { newSheet in
                sheetManager.addConfig(newSheet)
            }
        }
    }
    
    // --- Sub-Views ---

    var backendSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("BACKEND ENDPOINT")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(context.themeAccentColor.opacity(0.7))
                .tracking(1)

            HStack(spacing: 8) {
                TextField("https://api.rong-e.app", text: $context.backendUrl)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.jarvisTextPrimary)
                    .textFieldStyle(PlainTextFieldStyle())
                    .padding(8)
                    .background(Color.black.opacity(0.4))
                    .overlay(Rectangle().stroke(context.themeAccentColor.opacity(0.3), lineWidth: 1))
                    .onSubmit { applyBackendUrl() }

                Button(action: { applyBackendUrl() }) {
                    Text("APPLY")
                        .font(.system(size: 10, design: .monospaced))
                        .fontWeight(.bold)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(context.themeAccentColor.opacity(0.15))
                        .foregroundColor(context.themeAccentColor)
                        .overlay(Rectangle().stroke(context.themeAccentColor.opacity(0.5), lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(BorderlessButtonStyle())
            }

            Text("USE http://localhost:8080 FOR LOCAL DEVELOPMENT")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.jarvisTextDim)
        }
        .modifier(JarvisPanel())
    }

    private func applyBackendUrl() {
        context.saveSettings()
        SocketClient.shared.sendSetBackendUrl(context.backendUrl)
    }

    var authSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AUTHENTICATION PROTOCOL")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(context.themeAccentColor.opacity(0.7))
                .tracking(1)

            if context.isGoogleConnected {
                HStack {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.jarvisGreen)
                    Text("GOOGLE ACCOUNT CONNECTED")
                        .font(.system(size: 11, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundColor(.jarvisTextPrimary)
                    Spacer()
                    Button(action: { googleAuthManager.revoke() }) {
                        Text("TERMINATE")
                            .font(.system(size: 11, design: .monospaced))
                            .fontWeight(.bold)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 10)
                            .background(Color.jarvisRed.opacity(0.2))
                            .foregroundColor(.jarvisRed)
                            .overlay(Rectangle().stroke(Color.jarvisRed, lineWidth: 1))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
                .padding(12)
                .background(Color.jarvisGreen.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.jarvisGreen.opacity(0.3), lineWidth: 1))
            } else {
                Button(action: { googleAuthManager.startOAuth() }) {
                    HStack {
                        Image(systemName: "person.badge.key.fill")
                            .font(.title2)
                            .foregroundColor(context.themeAccentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("SIGN IN WITH GOOGLE")
                                .font(.system(size: 11, design: .monospaced))
                                .fontWeight(.bold)
                                .foregroundColor(.jarvisTextPrimary)
                            Text("OPENS BROWSER · NO API KEY REQUIRED")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.jarvisTextDim)
                        }
                        Spacer()
                        Image(systemName: "arrow.right")
                            .foregroundColor(context.themeAccentColor)
                    }
                    .padding(12)
                    .background(context.themeAccentColor.opacity(0.05))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(context.themeAccentColor.opacity(0.3), lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(BorderlessButtonStyle())
                .modifier(JarvisGlow(active: true))
            }
        }
        .modifier(JarvisPanel())
    }
    
    var resourcesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("MANAGED SPREADSHEETS")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(context.themeAccentColor.opacity(0.7))
                    .tracking(1)
                Spacer()
                
                Button(action: { isShowingAddSheet = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("ADD RESOURCE")
                    }
                    .font(.system(size: 10, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(context.themeAccentColor.opacity(0.1))
                    .overlay(Rectangle().stroke(context.themeAccentColor.opacity(0.5), lineWidth: 1))
                    .foregroundColor(context.themeAccentColor)
                    .contentShape(Rectangle())
                }
                .buttonStyle(BorderlessButtonStyle())
                .disabled(connectionStatus != .connected)
                .opacity(connectionStatus != .connected ? 0.5 : 1.0)
            }
            
            if connectionStatus != .connected {
                Text("WARNING: AUTHENTICATION REQUIRED FOR DATA ACCESS.")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.jarvisRed.opacity(0.8))
                    .padding(.top, 10)
            } else if sheetManager.configs.isEmpty {
                VStack(spacing: 5) {
                    Text("NO DATA STREAMS FOUND")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.jarvisTextDim)
                    Text("INITIATE NEW RESOURCE CONNECTION")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.jarvisTextDim.opacity(0.5))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
                .background(Color.black.opacity(0.3))
                .border(Color.white.opacity(0.05), width: 1)
            } else {
                VStack(spacing: 8) {
                    ForEach(sheetManager.configs) { sheet in
                        ResourceRow(sheet: sheet, onDelete: {
                            sheetManager.removeConfig(sheet)
                        })
                    }
                }
            }
        }
        .modifier(JarvisPanel())
    }
}

// --- Helper Components ---

struct ResourceRow: View {
    let sheet: SpreadsheetConfig
    var onDelete: (() -> Void)?
    @ObservedObject private var _theme = AppContext.shared

    var body: some View {
        HStack {
            // Icon Block
            ZStack {
                Rectangle()
                    .fill(Color.jarvisGreen.opacity(0.1))
                    .frame(width: 40, height: 40)
                    .border(Color.jarvisGreen.opacity(0.3), width: 1)

                Image(systemName: "tablecells.fill")
                    .foregroundColor(.jarvisGreen)
                    .font(.system(size: 16))
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(sheet.alias.uppercased())
                        .font(.system(size: 12, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundColor(.jarvisTextPrimary)

                    Text("// \(sheet.selectedTab.uppercased())")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.jarvisGreen.opacity(0.7))
                }
                Text(sheet.description.uppercased())
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.jarvisTextDim)
                    .lineLimit(1)
            }
            Spacer()

            // Delete button
            if let onDelete = onDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.jarvisRed.opacity(0.7))
                        .font(.system(size: 12))
                }
                .buttonStyle(BorderlessButtonStyle())
            }

            // Status light
            Circle()
                .fill(Color.jarvisGreen)
                .frame(width: 4, height: 4)
                .shadow(color: .jarvisGreen, radius: 4)
        }
        .padding(8)
        .background(Color.black.opacity(0.3))
        .overlay(Rectangle().stroke(Color.white.opacity(0.05), lineWidth: 1))
    }
}

// --- The "Add Sheet" Modal (Jarvis Style) ---

struct AddSheetModal: View {
    @Binding var isPresented: Bool
    var onSave: (SpreadsheetConfig) -> Void
    @ObservedObject private var _theme = AppContext.shared

    @State private var urlInput = ""
    @State private var aliasInput = ""
    @State private var descriptionInput = ""
    @State private var selectedTab = ""

    @State private var isVerifying = false
    @State private var foundTabs: [String] = []
    @State private var extractedID: String? = nil
    @State private var sheetTitle: String? = nil
    @State private var errorMessage: String? = nil

    // Extract spreadsheet ID from Google Sheets URL
    // Format: https://docs.google.com/spreadsheets/d/{SPREADSHEET_ID}/...
    private func extractSpreadsheetId(from url: String) -> String? {
        let pattern = #"spreadsheets/d/([a-zA-Z0-9-_]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)),
              let range = Range(match.range(at: 1), in: url) else {
            return nil
        }
        return String(url[range])
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TechGridBackground()

            VStack(spacing: 0) {
                // Modal Header
                HStack {
                    Text("NEW RESOURCE ALLOCATION")
                        .font(.system(size: 12, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundColor(_theme.themeAccentColor)
                    Spacer()
                }
                .padding()
                .background(_theme.themeAccentColor.opacity(0.1))
                .overlay(Rectangle().frame(height: 1).foregroundColor(_theme.themeAccentColor.opacity(0.3)), alignment: .bottom)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {

                        // 1. URL Input
                        VStack(alignment: .leading, spacing: 8) {
                            Text("TARGET URL (G-SHEETS)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.jarvisTextDim)

                            HStack {
                                JarvisTextField(text: $urlInput)

                                Button(action: { verifySheet() }) {
                                    Text(isVerifying ? "SCANNING..." : "VERIFY")
                                        .font(.system(size: 10, design: .monospaced))
                                        .fontWeight(.bold)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                        .background(urlInput.isEmpty ? Color.jarvisTextDim.opacity(0.2) : _theme.themeAccentColor.opacity(0.2))
                                        .foregroundColor(urlInput.isEmpty ? .jarvisTextDim : _theme.themeAccentColor)
                                        .overlay(Rectangle().stroke(urlInput.isEmpty ? Color.jarvisTextDim : _theme.themeAccentColor, lineWidth: 1))
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(BorderlessButtonStyle())
                                .disabled(urlInput.isEmpty || isVerifying)
                            }
                        }

                        // Status messages
                        if isVerifying {
                            HStack {
                                Text("ESTABLISHING LINK...")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(_theme.themeAccentColor)
                                Spacer()
                                Text(">>>")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(_theme.themeAccentColor)
                            }
                        }

                        if let error = errorMessage {
                            Text("ERROR: \(error.uppercased())")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.jarvisRed)
                        }

                        // 2. Details (Hidden until verified)
                        if let _ = extractedID {
                            VStack(alignment: .leading, spacing: 15) {

                                // Show sheet title
                                if let title = sheetTitle {
                                    HStack {
                                        Text("LINKED TO:")
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(.jarvisTextDim)
                                        Text(title.uppercased())
                                            .font(.system(size: 10, design: .monospaced))
                                            .fontWeight(.bold)
                                            .foregroundColor(.jarvisGreen)
                                    }
                                }

                                // Tab Selector
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("SELECT DATA WORKSHEET (\(foundTabs.count) FOUND)")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.jarvisTextDim)

                                    Picker("", selection: $selectedTab) {
                                        ForEach(foundTabs, id: \.self) { tab in
                                            Text(tab).tag(tab)
                                        }
                                    }
                                    .labelsHidden()
                                    .pickerStyle(MenuPickerStyle())
                                    .frame(maxWidth: .infinity)
                                    .background(Color.black.opacity(0.4))
                                    .overlay(Rectangle().stroke(_theme.themeAccentColor.opacity(0.3), lineWidth: 1))
                                }

                                // Alias
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("SYSTEM ALIAS")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.jarvisTextDim)
                                    JarvisTextField(text: $aliasInput)
                                }

                                // Description
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("CONTEXTUAL USAGE")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.jarvisTextDim)
                                    JarvisTextField(text: $descriptionInput)
                                }
                            }
                            .transition(.opacity)
                        }
                    }
                    .padding(20)
                }

                // 3. Actions (Fixed at bottom)
                HStack {
                    Button("CANCEL") { isPresented = false }
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.jarvisTextDim)
                        .buttonStyle(BorderlessButtonStyle())
                        .keyboardShortcut(.cancelAction)

                    Spacer()

                    Button(action: {
                        let newSheet = SpreadsheetConfig(
                            alias: aliasInput,
                            url: urlInput,
                            sheetID: extractedID ?? "",
                            selectedTab: selectedTab,
                            description: descriptionInput
                        )
                        onSave(newSheet)
                        isPresented = false
                    }) {
                        Text("INITIALIZE RESOURCE")
                            .font(.system(size: 11, design: .monospaced))
                            .fontWeight(.bold)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background((extractedID == nil || aliasInput.isEmpty) ? Color.jarvisTextDim.opacity(0.2) : _theme.themeAccentColor.opacity(0.2))
                            .foregroundColor((extractedID == nil || aliasInput.isEmpty) ? .jarvisTextDim : _theme.themeAccentColor)
                            .overlay(Rectangle().stroke((extractedID == nil || aliasInput.isEmpty) ? Color.jarvisTextDim : _theme.themeAccentColor, lineWidth: 1))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .disabled(extractedID == nil || aliasInput.isEmpty)
                }
                .padding(20)
                .background(_theme.themeAccentColor.opacity(0.05))
                .overlay(Rectangle().frame(height: 1).foregroundColor(_theme.themeAccentColor.opacity(0.3)), alignment: .top)
            }
        }
        .frame(width: 450, height: 550)
        .border(_theme.themeAccentColor.opacity(0.5))
        .onAppear {
            setupSheetTabsCallback()
        }
    }

    private func setupSheetTabsCallback() {
        SocketClient.shared.onSheetTabsResult = { success, titleOrError, tabs in
            withAnimation {
                self.isVerifying = false
                if success {
                    self.sheetTitle = titleOrError
                    self.foundTabs = tabs ?? []
                    self.selectedTab = tabs?.first ?? ""
                    // Use sheet title as default alias (sanitized)
                    if let title = titleOrError {
                        self.aliasInput = title
                            .uppercased()
                            .replacingOccurrences(of: " ", with: "_")
                            .prefix(30)
                            .description
                    }
                    self.errorMessage = nil
                } else {
                    self.errorMessage = titleOrError ?? "Unknown error"
                    self.extractedID = nil
                    self.foundTabs = []
                }
            }
        }
    }

    private func verifySheet() {
        errorMessage = nil

        // Extract ID from URL
        guard let spreadsheetId = extractSpreadsheetId(from: urlInput) else {
            errorMessage = "Invalid Google Sheets URL"
            return
        }

        withAnimation { isVerifying = true }
        extractedID = spreadsheetId

        // Send request to Python backend
        SocketClient.shared.sendGetSheetTabs(spreadsheetId: spreadsheetId)
    }
}
