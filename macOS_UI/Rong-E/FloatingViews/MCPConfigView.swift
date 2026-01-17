import SwiftUI
import UniformTypeIdentifiers

struct MCPConfigView: View {
    @ObservedObject var configManager = MCPConfigManager.shared
    @State private var showFileImporter = false
    @State private var showAddServerSheet = false
    @State private var showJSONPasteSheet = false
    @State private var jsonPasteText = ""
    @State private var syncStatus: SyncStatus = .idle

    enum SyncStatus: Equatable {
        case idle
        case syncing
        case success
        case error(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("MCP Servers")
                    .font(.headline)
                Spacer()
                syncStatusIndicator
            }

            // Error display
            if let error = configManager.lastError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Dismiss") {
                        configManager.lastError = nil
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(6)
            }

            // Server list
            if configManager.servers.isEmpty {
                emptyStateView
            } else {
                serverListView
            }

            Divider()

            // Action buttons
            HStack(spacing: 12) {
                Button(action: { showFileImporter = true }) {
                    Label("Import File", systemImage: "doc.badge.plus")
                }
                .buttonStyle(.bordered)

                Button(action: { showJSONPasteSheet = true }) {
                    Label("Paste JSON", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.bordered)

                Button(action: { showAddServerSheet = true }) {
                    Label("Add Server", systemImage: "plus.circle")
                }
                .buttonStyle(.bordered)

                Spacer()

                if !configManager.servers.isEmpty {
                    Button(action: { configManager.sendConfigToPython() }) {
                        Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
        .frame(minWidth: 400, minHeight: 300)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .sheet(isPresented: $showAddServerSheet) {
            AddServerSheet(onAdd: { server in
                configManager.addServer(server)
            })
        }
        .sheet(isPresented: $showJSONPasteSheet) {
            JSONPasteSheet(jsonText: $jsonPasteText, onSubmit: {
                configManager.loadConfig(from: jsonPasteText)
                jsonPasteText = ""
            })
        }
        .onAppear {
            setupSyncCallback()
        }
    }

    private var syncStatusIndicator: some View {
        Group {
            switch syncStatus {
            case .idle:
                EmptyView()
            case .syncing:
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Syncing...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            case .success:
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Synced")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            case .error(let msg):
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "server.rack")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("No MCP Servers Configured")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("Import a config file or add servers manually")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var serverListView: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(configManager.servers) { server in
                    ServerRowView(server: server, onDelete: {
                        configManager.removeServer(server)
                    })
                }
            }
        }
        .frame(maxHeight: 200)
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            // Start accessing security-scoped resource
            guard url.startAccessingSecurityScopedResource() else {
                configManager.lastError = "Permission denied to access file"
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            configManager.loadConfig(from: url)

        case .failure(let error):
            configManager.lastError = error.localizedDescription
        }
    }

    private func setupSyncCallback() {
        SocketClient.shared.onMCPSyncResult = { success, message in
            DispatchQueue.main.async {
                if success {
                    self.syncStatus = .success
                    // Auto-hide success after 3 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        if case .success = self.syncStatus {
                            self.syncStatus = .idle
                        }
                    }
                } else {
                    self.syncStatus = .error(message ?? "Sync failed")
                }
            }
        }
    }
}

// MARK: - Server Row View

struct ServerRowView: View {
    let server: MCPServerConfig
    let onDelete: () -> Void
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "server.rack")
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(server.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(server.command)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: { isExpanded.toggle() }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    if !server.args.isEmpty {
                        Text("Args: \(server.args.joined(separator: " "))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    if let env = server.env, !env.isEmpty {
                        Text("Env: \(env.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.leading, 24)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Add Server Sheet

struct AddServerSheet: View {
    @Environment(\.dismiss) var dismiss
    let onAdd: (MCPServerConfig) -> Void

    @State private var name = ""
    @State private var command = ""
    @State private var argsText = ""
    @State private var envText = ""
    @State private var validationError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add MCP Server")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                TextField("Server Name", text: $name)
                    .textFieldStyle(.roundedBorder)

                TextField("Command (e.g., npx, node, python)", text: $command)
                    .textFieldStyle(.roundedBorder)

                TextField("Arguments (space-separated)", text: $argsText)
                    .textFieldStyle(.roundedBorder)

                TextField("Environment (KEY=value, comma-separated)", text: $envText)
                    .textFieldStyle(.roundedBorder)
            }

            if let error = validationError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Button("Add") { addServer() }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.isEmpty || command.isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
    }

    private func addServer() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedCommand = command.trimmingCharacters(in: .whitespaces)

        guard !trimmedName.isEmpty else {
            validationError = "Server name is required"
            return
        }
        guard !trimmedCommand.isEmpty else {
            validationError = "Command is required"
            return
        }

        let args = argsText
            .split(separator: " ")
            .map { String($0) }
            .filter { !$0.isEmpty }

        var env: [String: String]? = nil
        if !envText.isEmpty {
            env = [:]
            for pair in envText.split(separator: ",") {
                let parts = pair.split(separator: "=", maxSplits: 1)
                if parts.count == 2 {
                    env?[String(parts[0]).trimmingCharacters(in: .whitespaces)] =
                        String(parts[1]).trimmingCharacters(in: .whitespaces)
                }
            }
        }

        let server = MCPServerConfig(
            name: trimmedName,
            command: trimmedCommand,
            args: args,
            env: env
        )
        onAdd(server)
        dismiss()
    }
}

// MARK: - JSON Paste Sheet

struct JSONPasteSheet: View {
    @Environment(\.dismiss) var dismiss
    @Binding var jsonText: String
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Paste MCP Config JSON")
                .font(.headline)

            Text("Paste a valid MCP config JSON below:")
                .font(.caption)
                .foregroundColor(.secondary)

            TextEditor(text: $jsonText)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 200)
                .border(Color.secondary.opacity(0.3))

            Text("Example format:")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("""
            {
              "mcpServers": {
                "filesystem": {
                  "command": "npx",
                  "args": ["-y", "@modelcontextprotocol/server-filesystem", "/path"]
                }
              }
            }
            """)
            .font(.system(.caption, design: .monospaced))
            .foregroundColor(.secondary)
            .padding(8)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(4)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Button("Import") {
                    onSubmit()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(jsonText.isEmpty)
            }
        }
        .padding()
        .frame(width: 500, height: 450)
    }
}

#Preview {
    MCPConfigView()
}
