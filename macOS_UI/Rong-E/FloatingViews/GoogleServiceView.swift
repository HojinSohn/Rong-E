import SwiftUI
import UniformTypeIdentifiers

// Settings page for Google Service Integration
// Have Field to add credential.json file from GCP for OAuth2
// Status of connection (Red / Green)
// Page to add sheets to be managed (name, url, dropdown to select tab)

// --- Models ---
struct SpreadsheetConfig: Identifiable, Codable {
    let id = UUID()
    var alias: String        // "Project Budget"
    var url: String          // Full Google URL
    var sheetID: String      // Extracted ID
    var selectedTab: String  // "Sheet1"
    var description: String  // "Use for tracking expenses"
}

struct GoogleServiceView: View {
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var context: AppContext
    @EnvironmentObject var coordinator: WindowCoordinator
    
    // Grab the Global Manager
    @EnvironmentObject var googleAuthManager: GoogleAuthManager
    
    let windowID: String
    
    @State private var isShowingFilePicker = false
    @State private var isShowingAddSheet = false
    @State private var savedSheets: [SpreadsheetConfig] = []
    @State private var currentSelectedFileName: String = "No file selected"

    var connectionStatus: ConnectionStatus {
        context.isGoogleConnected ? .connected : .disconnected
    }

    enum ConnectionStatus {
        case disconnected, connecting, connected
        var color: Color {
            switch self {
            case .disconnected: return .red
            case .connecting: return .yellow
            case .connected: return .green
            }
        }
        var label: String {
            switch self {
            case .disconnected: return "Disconnected"
            case .connecting: return "Connecting..."
            case .connected: return "Active"
            }
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            
            VStack(spacing: 0) {
                headerView
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        authSection
                        Divider().background(Color.white.opacity(0.2))
                        resourcesSection
                    }
                    .padding(24)
                }
            }
        }
        .frame(width: 500, height: 600)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))
        
        // --- CLEAN FILE IMPORTER ---
        .fileImporter(
            isPresented: $isShowingFilePicker,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                self.currentSelectedFileName = url.lastPathComponent
                
                // DELEGATE TO MANAGER
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
    
    var headerView: some View {
        HStack {
            Image(systemName: "server.rack").foregroundColor(.blue)
            Text("Google Services Integration").font(.headline).foregroundColor(.white)
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(connectionStatus.color).frame(width: 8, height: 8)
                Text(connectionStatus.label).font(.caption).foregroundColor(.white)
            }
            .padding(6).background(Color.black.opacity(0.4)).cornerRadius(8)
            
            Button(action: { coordinator.closeWindow(id: windowID) }) {
                Image(systemName: "xmark").foregroundColor(.gray)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color.black.opacity(0.3))
    }
    
    var authSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Authentication").font(.headline).foregroundColor(.white)
            Text("Import 'credentials.json' from GCP.").font(.caption).foregroundColor(.gray)
            
            HStack(spacing: 12) {
                // Picker Button
                Button(action: { isShowingFilePicker = true }) {
                    HStack {
                        Image(systemName: "doc.text.fill")
                            .foregroundColor(!googleAuthManager.credentialsFileExists ? .gray : .green)
                        VStack(alignment: .leading) {
                            Text(!googleAuthManager.credentialsFileExists ? "Select credentials.json" : (currentSelectedFileName == "No file selected" ? "credentials.json" : currentSelectedFileName))
                                .foregroundColor(.primary)
                            if !googleAuthManager.credentialsFileExists {
                                Text("Click").font(.caption2).foregroundColor(.gray)
                            }
                        }
                        Spacer()
                    }
                    .padding()
                    .frame(height: 60)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(context.isGoogleConnected)
                
                // Connect / Revoke Buttons
                if !context.isGoogleConnected {
                    Button(action: { googleAuthManager.connect() }) { // USE MANAGER
                        Text("Connect").fontWeight(.semibold)
                            .frame(maxHeight: .infinity).padding(.horizontal, 20)
                            .background(Color.blue).foregroundColor(.white).cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .frame(height: 60)
                } else {
                    Button(action: { googleAuthManager.revoke() }) { // USE MANAGER
                        Text("Revoke").fontWeight(.semibold)
                            .frame(maxHeight: .infinity).padding(.horizontal, 20)
                            .background(Color.red).foregroundColor(.white).cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .frame(height: 60)
                }
            }
        }
    }
    
    
    var resourcesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Managed Spreadsheets")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Button(action: { isShowingAddSheet = true }) {
                    Label("Add Sheet", systemImage: "plus")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(6)
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                .disabled(connectionStatus != .connected) // Only add if connected
            }
            
            if connectionStatus != .connected {
                Text("Connect credentials to add resources.")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.top, 4)
            } else if savedSheets.isEmpty {
                Text("No spreadsheets added yet.")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ForEach(savedSheets) { sheet in
                    ResourceRow(sheet: sheet)
                }
            }
        }
    }
}



// --- Helper Components ---

struct ResourceRow: View {
    let sheet: SpreadsheetConfig
    
    var body: some View {
        HStack {
            Image(systemName: "tablecells.fill")
                .foregroundColor(.green)
                .font(.title2)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(sheet.alias)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                    Text("• \(sheet.selectedTab)")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                Text(sheet.description)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(10)
        .background(Color.white.opacity(0.05))
        .cornerRadius(8)
    }
}

// --- The "Add Sheet" Modal ---

struct AddSheetModal: View {
    @Binding var isPresented: Bool
    var onSave: (SpreadsheetConfig) -> Void
    
    @State private var urlInput = ""
    @State private var aliasInput = ""
    @State private var descriptionInput = ""
    @State private var selectedTab = ""
    
    // "Smart Paste" State
    @State private var isVerifying = false
    @State private var foundTabs: [String] = []
    @State private var extractedID: String? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Add Spreadsheet")
                .font(.headline)
                .foregroundColor(.white)
            
            // 1. URL Input (The Trigger)
            VStack(alignment: .leading) {
                Text("Google Sheet Link")
                    .font(.caption)
                    .foregroundColor(.gray)
                HStack {
                    TextField("https://docs.google.com/...", text: $urlInput)
                        .textFieldStyle(PlainTextFieldStyle())
                        .padding(8)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(6)
                        .foregroundColor(.white)
                    
                    Button("Verify") {
                        simulateVerify()
                    }
                    .disabled(urlInput.isEmpty)
                }
            }
            
            if isVerifying {
                ProgressView().scaleEffect(0.5)
            }
            
            // 2. Details (Hidden until verified)
            if let _ = extractedID {
                VStack(alignment: .leading, spacing: 12) {
                    
                    // Tab Selector
                    VStack(alignment: .leading) {
                        Text("Select Worksheet (Tab)")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Picker("", selection: $selectedTab) {
                            ForEach(foundTabs, id: \.self) { tab in
                                Text(tab).tag(tab)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(MenuPickerStyle())
                        .frame(maxWidth: .infinity)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(6)
                    }
                    
                    // Alias
                    VStack(alignment: .leading) {
                        Text("Name (Alias)")
                            .font(.caption)
                            .foregroundColor(.gray)
                        TextField("e.g. Budget 2024", text: $aliasInput)
                            .textFieldStyle(PlainTextFieldStyle())
                            .padding(8)
                            .background(Color.black.opacity(0.3))
                            .cornerRadius(6)
                    }
                    
                    // Description
                    VStack(alignment: .leading) {
                        Text("Description for AI")
                            .font(.caption)
                            .foregroundColor(.gray)
                        TextField("When should I use this?", text: $descriptionInput)
                            .textFieldStyle(PlainTextFieldStyle())
                            .padding(8)
                            .background(Color.black.opacity(0.3))
                            .cornerRadius(6)
                    }
                }
                .transition(.opacity)
            }
            
            Spacer()
            
            // 3. Actions
            HStack {
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add Resource") {
                    let newSheet = SpreadsheetConfig(
                        alias: aliasInput,
                        url: urlInput,
                        sheetID: extractedID ?? "",
                        selectedTab: selectedTab,
                        description: descriptionInput
                    )
                    onSave(newSheet)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(extractedID == nil || aliasInput.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400, height: 450)
        .background(Color(NSColor.windowBackgroundColor)) // Dark standard bg
    }
    
    func simulateVerify() {
        isVerifying = true
        // Mock regex extraction and API call
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.extractedID = "1BxiMWs_MOCK_ID_12345"
            self.foundTabs = ["Summary", "Q1 Data", "Q2 Data", "Calculations"]
            self.selectedTab = "Summary"
            self.aliasInput = "Project Budget" // Mock auto-title
            self.isVerifying = false
        }
    }
}
