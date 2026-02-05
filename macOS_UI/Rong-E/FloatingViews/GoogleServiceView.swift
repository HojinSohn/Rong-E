import SwiftUI
import UniformTypeIdentifiers

// --- Models ---
struct SpreadsheetConfig: Identifiable, Codable {
    let id = UUID()
    var alias: String
    var url: String
    var sheetID: String
    var selectedTab: String
    var description: String
}

struct GoogleServiceView: View {
    @EnvironmentObject var context: AppContext
    @EnvironmentObject var coordinator: WindowCoordinator
    @EnvironmentObject var googleAuthManager: GoogleAuthManager
    
    let windowID: String
    
    @State private var isShowingFilePicker = false
    @State private var isShowingAddSheet = false
    @State private var savedSheets: [SpreadsheetConfig] = []
    @State private var currentSelectedFileName: String = "NO_DATA"

    var connectionStatus: ConnectionStatus {
        context.isGoogleConnected ? .connected : .disconnected
    }

    enum ConnectionStatus {
        case disconnected, connecting, connected
        var color: Color {
            switch self {
            case .disconnected: return .red
            case .connecting: return .yellow
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
            
            // 3. Content Frame
            VStack(spacing: 0) {
                // Header
                HStack {
                    Circle()
                        .fill(Color.jarvisBlue)
                        .frame(width: 8, height: 8)
                        .modifier(JarvisGlow(active: true))
                    
                    Text("SYSTEM // GOOGLE_SERVICES")
                        .font(.system(.subheadline, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundColor(.jarvisBlue)
                        .tracking(2)
                    
                    Spacer()
                    
                    // Status Badge
                    HStack(spacing: 6) {
                        Text("STATUS:")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.gray)
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
                            .foregroundColor(.jarvisBlue.opacity(0.8))
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .contentShape(Rectangle())
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 15)
                .background(Color.jarvisBlue.opacity(0.05))
                .overlay(Rectangle().frame(height: 1).foregroundColor(.jarvisBlue.opacity(0.3)), alignment: .bottom)
                
                // Main Content
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        authSection
                        
                        // Section Divider
                        HStack {
                            Rectangle().frame(height: 1).foregroundColor(.jarvisBlue.opacity(0.3))
                            Text("RESOURCES")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.jarvisBlue.opacity(0.7))
                            Rectangle().frame(height: 1).foregroundColor(.jarvisBlue.opacity(0.3))
                        }
                        .padding(.vertical, 5)
                        
                        resourcesSection
                    }
                    .padding(20)
                }
            }
        }
        .frame(width: 500, height: 500)
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .stroke(Color.jarvisBlue.opacity(0.3), lineWidth: 1)
        )
        // File Importer
        .fileImporter(
            isPresented: $isShowingFilePicker,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                self.currentSelectedFileName = url.lastPathComponent.uppercased()
                googleAuthManager.importCredentials(from: url)
            case .failure(let error):
                print("Import failed: \(error)")
            }
        }
        .sheet(isPresented: $isShowingAddSheet) {
            AddSheetModal(isPresented: $isShowingAddSheet) { newSheet in
                savedSheets.append(newSheet)
            }
        }
    }
    
    // --- Sub-Views ---
    
    var authSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AUTHENTICATION PROTOCOL")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.jarvisBlue.opacity(0.7))
                .tracking(1)
            
            HStack(spacing: 12) {
                // File Picker
                Button(action: { isShowingFilePicker = true }) {
                    HStack {
                        Image(systemName: "doc.plaintext.fill")
                            .font(.title2)
                            .foregroundColor(!googleAuthManager.credentialsFileExists ? .gray : .jarvisBlue)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(googleAuthManager.credentialsFileExists ? "CREDENTIALS LOADED" : "LOAD CREDENTIALS")
                                .font(.system(size: 11, design: .monospaced))
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            
                            Text(googleAuthManager.credentialsFileExists ? currentSelectedFileName : "SELECT .JSON FILE")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.gray)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.jarvisBlue.opacity(0.05))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.jarvisBlue.opacity(0.3), lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(BorderlessButtonStyle())
                .disabled(context.isGoogleConnected)
                
                // Connect / Revoke Buttons
                if !context.isGoogleConnected {
                    Button(action: { googleAuthManager.connect() }) {
                        Text("INITIATE LINK")
                            .font(.system(size: 11, design: .monospaced))
                            .fontWeight(.bold)
                            .frame(maxHeight: .infinity)
                            .padding(.horizontal, 15)
                            .background(Color.jarvisBlue.opacity(0.2))
                            .foregroundColor(.jarvisBlue)
                            .overlay(Rectangle().stroke(Color.jarvisBlue, lineWidth: 1))
                            .modifier(JarvisGlow(active: true))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .frame(height: 54) // Match height roughly
                } else {
                    Button(action: { googleAuthManager.revoke() }) {
                        Text("TERMINATE")
                            .font(.system(size: 11, design: .monospaced))
                            .fontWeight(.bold)
                            .frame(maxHeight: .infinity)
                            .padding(.horizontal, 15)
                            .background(Color.red.opacity(0.2))
                            .foregroundColor(.red)
                            .overlay(Rectangle().stroke(Color.red, lineWidth: 1))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .frame(height: 54)
                }
            }
        }
        .modifier(JarvisPanel())
    }
    
    var resourcesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("MANAGED SPREADSHEETS")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.jarvisBlue.opacity(0.7))
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
                    .background(Color.jarvisBlue.opacity(0.1))
                    .overlay(Rectangle().stroke(Color.jarvisBlue.opacity(0.5), lineWidth: 1))
                    .foregroundColor(.jarvisBlue)
                    .contentShape(Rectangle())
                }
                .buttonStyle(BorderlessButtonStyle())
                .disabled(connectionStatus != .connected)
                .opacity(connectionStatus != .connected ? 0.5 : 1.0)
            }
            
            if connectionStatus != .connected {
                Text("WARNING: AUTHENTICATION REQUIRED FOR DATA ACCESS.")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.red.opacity(0.8))
                    .padding(.top, 10)
            } else if savedSheets.isEmpty {
                VStack(spacing: 5) {
                    Text("NO DATA STREAMS FOUND")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.gray)
                    Text("INITIATE NEW RESOURCE CONNECTION")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.gray.opacity(0.5))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
                .background(Color.black.opacity(0.3))
                .border(Color.white.opacity(0.05), width: 1)
            } else {
                VStack(spacing: 8) {
                    ForEach(savedSheets) { sheet in
                        ResourceRow(sheet: sheet)
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
    
    var body: some View {
        HStack {
            // Icon Block
            ZStack {
                Rectangle()
                    .fill(Color.green.opacity(0.1))
                    .frame(width: 40, height: 40)
                    .border(Color.green.opacity(0.3), width: 1)
                
                Image(systemName: "tablecells.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 16))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(sheet.alias.uppercased())
                        .font(.system(size: 12, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Text("// \(sheet.selectedTab.uppercased())")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.green.opacity(0.7))
                }
                Text(sheet.description.uppercased())
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
            Spacer()
            
            // Status light
            Circle()
                .fill(Color.green)
                .frame(width: 4, height: 4)
                .shadow(color: .green, radius: 4)
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
    
    @State private var urlInput = ""
    @State private var aliasInput = ""
    @State private var descriptionInput = ""
    @State private var selectedTab = ""
    
    @State private var isVerifying = false
    @State private var foundTabs: [String] = []
    @State private var extractedID: String? = nil
    
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
                        .foregroundColor(.jarvisBlue)
                    Spacer()
                }
                .padding()
                .background(Color.jarvisBlue.opacity(0.1))
                .overlay(Rectangle().frame(height: 1).foregroundColor(.jarvisBlue.opacity(0.3)), alignment: .bottom)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        
                        // 1. URL Input
                        VStack(alignment: .leading, spacing: 8) {
                            Text("TARGET URL (G-SHEETS)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.gray)
                            
                            HStack {
                                JarvisTextField(text: $urlInput)
                                
                                Button(action: { simulateVerify() }) {
                                    Text(isVerifying ? "SCANNING..." : "VERIFY")
                                        .font(.system(size: 10, design: .monospaced))
                                        .fontWeight(.bold)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                        .background(urlInput.isEmpty ? Color.gray.opacity(0.2) : Color.jarvisBlue.opacity(0.2))
                                        .foregroundColor(urlInput.isEmpty ? .gray : .jarvisBlue)
                                        .overlay(Rectangle().stroke(urlInput.isEmpty ? Color.gray : Color.jarvisBlue, lineWidth: 1))
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(BorderlessButtonStyle())
                                .disabled(urlInput.isEmpty || isVerifying)
                            }
                        }
                        
                        if isVerifying {
                             HStack {
                                 Text("ESTABLISHING LINK...")
                                     .font(.system(size: 10, design: .monospaced))
                                     .foregroundColor(.jarvisBlue)
                                 Spacer()
                                 // Simple text animation placeholder
                                 Text(">>>")
                                     .font(.system(size: 10, design: .monospaced))
                                     .foregroundColor(.jarvisBlue)
                             }
                        }
                        
                        // 2. Details (Hidden until verified)
                        if let _ = extractedID {
                            VStack(alignment: .leading, spacing: 15) {
                                
                                // Tab Selector
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("SELECT DATA WORKSHEET")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.gray)
                                    
                                    Picker("", selection: $selectedTab) {
                                        ForEach(foundTabs, id: \.self) { tab in
                                            Text(tab).tag(tab)
                                        }
                                    }
                                    .labelsHidden()
                                    .pickerStyle(MenuPickerStyle())
                                    .frame(maxWidth: .infinity)
                                    .background(Color.black.opacity(0.4))
                                    .overlay(Rectangle().stroke(Color.jarvisBlue.opacity(0.3), lineWidth: 1))
                                }
                                
                                // Alias
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("SYSTEM ALIAS")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.gray)
                                    JarvisTextField(text: $aliasInput)
                                }
                                
                                // Description
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("CONTEXTUAL USAGE")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.gray)
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
                        .foregroundColor(.gray)
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
                            .background((extractedID == nil || aliasInput.isEmpty) ? Color.gray.opacity(0.2) : Color.jarvisBlue.opacity(0.2))
                            .foregroundColor((extractedID == nil || aliasInput.isEmpty) ? .gray : .jarvisBlue)
                            .overlay(Rectangle().stroke((extractedID == nil || aliasInput.isEmpty) ? Color.gray : Color.jarvisBlue, lineWidth: 1))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .disabled(extractedID == nil || aliasInput.isEmpty)
                }
                .padding(20)
                .background(Color.jarvisBlue.opacity(0.05))
                .overlay(Rectangle().frame(height: 1).foregroundColor(.jarvisBlue.opacity(0.3)), alignment: .top)
            }
        }
        .frame(width: 450, height: 550)
        .border(Color.jarvisBlue.opacity(0.5))
    }
    
    func simulateVerify() {
        withAnimation { isVerifying = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation {
                self.extractedID = "1BxiMWs_MOCK_ID_12345"
                self.foundTabs = ["SUMMARY", "DATA_Q1", "DATA_Q2", "LOGS"]
                self.selectedTab = "SUMMARY"
                self.aliasInput = "PROJECT_BUDGET_ALPHA"
                self.isVerifying = false
            }
        }
    }
}
