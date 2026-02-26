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
        VStack(alignment: .leading, spacing: JarvisSpacing.lg) {
            // Header
            HStack {
                Text("MCP Servers")
                    .font(JarvisFont.title)
                    .foregroundStyle(Color.jarvisTextPrimary)
                Spacer()
                syncStatusIndicator
            }

            // Error display
            if let error = configManager.lastError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.jarvisOrange)
                    Text(error)
                        .font(JarvisFont.caption)
                        .foregroundStyle(Color.jarvisTextSecondary)
                    Spacer()
                    Button("Dismiss") {
                        configManager.lastError = nil
                    }
                    .buttonStyle(.plain)
                    .font(JarvisFont.caption)
                    .foregroundStyle(Color.jarvisCyan)
                }
                .padding(JarvisSpacing.sm)
                .background(Color.jarvisOrange.opacity(0.1))
                .cornerRadius(JarvisRadius.small)
            }

            // Server list
            if configManager.servers.isEmpty {
                emptyStateView
            } else {
                serverListView
            }

            Divider()

            // Action buttons
            HStack(spacing: JarvisSpacing.md) {
                Button(action: { showFileImporter = true }) {
                    Label("Import File", systemImage: "doc.badge.plus")
                        .font(JarvisFont.label)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.jarvisCyan)
                .padding(.horizontal, JarvisSpacing.md)
                .padding(.vertical, JarvisSpacing.sm)
                .background(Color.jarvisCyan.opacity(0.15))
                .cornerRadius(JarvisRadius.medium)
                .overlay(RoundedRectangle(cornerRadius: JarvisRadius.medium).stroke(Color.jarvisCyan.opacity(0.3), lineWidth: 1))

                Button(action: { showJSONPasteSheet = true }) {
                    Label("Paste JSON", systemImage: "doc.on.clipboard")
                        .font(JarvisFont.label)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.jarvisCyan)
                .padding(.horizontal, JarvisSpacing.md)
                .padding(.vertical, JarvisSpacing.sm)
                .background(Color.jarvisCyan.opacity(0.15))
                .cornerRadius(JarvisRadius.medium)
                .overlay(RoundedRectangle(cornerRadius: JarvisRadius.medium).stroke(Color.jarvisCyan.opacity(0.3), lineWidth: 1))

                Button(action: { showAddServerSheet = true }) {
                    Label("Add Server", systemImage: "plus.circle")
                        .font(JarvisFont.label)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.jarvisGreen)
                .padding(.horizontal, JarvisSpacing.md)
                .padding(.vertical, JarvisSpacing.sm)
                .background(Color.jarvisGreen.opacity(0.15))
                .cornerRadius(JarvisRadius.medium)
                .overlay(RoundedRectangle(cornerRadius: JarvisRadius.medium).stroke(Color.jarvisGreen.opacity(0.3), lineWidth: 1))

                Spacer()

                if !configManager.servers.isEmpty {
                    Button(action: { configManager.sendConfigToPython() }) {
                        Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                            .font(JarvisFont.label)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.jarvisTextPrimary)
                    .padding(.horizontal, JarvisSpacing.lg)
                    .padding(.vertical, JarvisSpacing.sm)
                    .background(Color.jarvisBlue)
                    .cornerRadius(JarvisRadius.medium)
                }
            }
        }
        .padding()
        .frame(minWidth: 400, minHeight: 300)
        .background(Color.jarvisSurfaceDark)
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
                        .font(JarvisFont.captionMono)
                        .foregroundStyle(Color.jarvisTextSecondary)
                }
            case .success:
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.jarvisGreen)
                    Text("Synced")
                        .font(JarvisFont.captionMono)
                        .foregroundStyle(Color.jarvisTextSecondary)
                }
            case .error(let msg):
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.jarvisRed)
                    Text(msg)
                        .font(JarvisFont.captionMono)
                        .foregroundStyle(Color.jarvisTextSecondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: JarvisSpacing.md) {
            Image(systemName: "server.rack")
                .font(.system(size: 40))
                .foregroundStyle(Color.jarvisTextDim)
            Text("No MCP Servers Configured")
                .font(JarvisFont.subtitle)
                .foregroundStyle(Color.jarvisTextSecondary)
            Text("Import a config file or add servers manually")
                .font(JarvisFont.caption)
                .foregroundStyle(Color.jarvisTextDim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var serverListView: some View {
        ScrollView {
            LazyVStack(spacing: JarvisSpacing.sm) {
                ForEach(configManager.servers) { server in
                    ServerRowView(
                        server: server,
                        status: configManager.serverStatuses[server.name] ?? .idle,
                        onDelete: {
                            configManager.removeServer(server)
                        }
                    )
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
    let status: MCPServerConnectionStatus
    let onDelete: () -> Void
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: JarvisSpacing.xs) {
            HStack {
                statusIndicator

                VStack(alignment: .leading, spacing: 2) {
                    Text(server.name)
                        .font(JarvisFont.label)
                        .foregroundStyle(Color.jarvisTextPrimary)
                    Text(server.command)
                        .font(JarvisFont.captionMono)
                        .foregroundStyle(Color.jarvisTextSecondary)
                }

                Spacer()

                Button(action: { isExpanded.toggle() }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(Color.jarvisTextDim)
                }
                .buttonStyle(.plain)

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(Color.jarvisRed)
                }
                .buttonStyle(.plain)
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: JarvisSpacing.xs) {
                    if !server.args.isEmpty {
                        Text("Args: \(server.args.joined(separator: " "))")
                            .font(JarvisFont.captionMono)
                            .foregroundStyle(Color.jarvisTextDim)
                    }
                    if let env = server.env, !env.isEmpty {
                        Text("Env: \(env.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))")
                            .font(JarvisFont.captionMono)
                            .foregroundStyle(Color.jarvisTextDim)
                    }
                }
                .padding(.leading, JarvisSpacing.xxl)
            }
        }
        .padding(10)
        .background(Color.jarvisSurfaceLight)
        .cornerRadius(JarvisRadius.medium)
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch status {
        case .idle:
            Image(systemName: "server.rack")
                .foregroundStyle(Color.jarvisTextDim)
        case .connecting:
            ProgressView()
                .controlSize(.small)
        case .connected:
            Image(systemName: "server.rack")
                .foregroundStyle(Color.jarvisGreen)
        case .connectedPermissionDenied:
            Image(systemName: "server.rack")
                .foregroundStyle(Color.jarvisOrange)
                .help("Connected, but macOS permission was denied. Grant access in System Settings > Privacy & Security.")
        case .error(let msg):
            Image(systemName: "server.rack")
                .foregroundStyle(Color.jarvisRed)
                .help(msg)
        }
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
        VStack(alignment: .leading, spacing: JarvisSpacing.lg) {
            Text("Add MCP Server")
                .font(JarvisFont.title)
                .foregroundStyle(Color.jarvisTextPrimary)

            VStack(alignment: .leading, spacing: JarvisSpacing.sm) {
                TextField("Server Name", text: $name)
                    .textFieldStyle(.plain)
                    .font(JarvisFont.mono)
                    .padding(JarvisSpacing.sm)
                    .background(Color.jarvisSurfaceDeep)
                    .overlay(RoundedRectangle(cornerRadius: JarvisRadius.small).stroke(Color.jarvisBorder, lineWidth: 1))
                    .cornerRadius(JarvisRadius.small)

                TextField("Command (e.g., npx, node, python)", text: $command)
                    .textFieldStyle(.plain)
                    .font(JarvisFont.mono)
                    .padding(JarvisSpacing.sm)
                    .background(Color.jarvisSurfaceDeep)
                    .overlay(RoundedRectangle(cornerRadius: JarvisRadius.small).stroke(Color.jarvisBorder, lineWidth: 1))
                    .cornerRadius(JarvisRadius.small)

                TextField("Arguments (space-separated)", text: $argsText)
                    .textFieldStyle(.plain)
                    .font(JarvisFont.mono)
                    .padding(JarvisSpacing.sm)
                    .background(Color.jarvisSurfaceDeep)
                    .overlay(RoundedRectangle(cornerRadius: JarvisRadius.small).stroke(Color.jarvisBorder, lineWidth: 1))
                    .cornerRadius(JarvisRadius.small)

                TextField("Environment (KEY=value, comma-separated)", text: $envText)
                    .textFieldStyle(.plain)
                    .font(JarvisFont.mono)
                    .padding(JarvisSpacing.sm)
                    .background(Color.jarvisSurfaceDeep)
                    .overlay(RoundedRectangle(cornerRadius: JarvisRadius.small).stroke(Color.jarvisBorder, lineWidth: 1))
                    .cornerRadius(JarvisRadius.small)
            }

            if let error = validationError {
                Text(error)
                    .font(JarvisFont.caption)
                    .foregroundStyle(Color.jarvisRed)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.jarvisTextSecondary)
                    .padding(.horizontal, JarvisSpacing.lg)
                    .padding(.vertical, JarvisSpacing.sm)
                    .background(Color.jarvisSurfaceLight)
                    .cornerRadius(JarvisRadius.medium)
                Button("Add") { addServer() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.jarvisTextPrimary)
                    .padding(.horizontal, JarvisSpacing.lg)
                    .padding(.vertical, JarvisSpacing.sm)
                    .background(Color.jarvisBlue)
                    .cornerRadius(JarvisRadius.medium)
                    .disabled(name.isEmpty || command.isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
        .background(Color.jarvisSurfaceDark)
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
        VStack(alignment: .leading, spacing: JarvisSpacing.lg) {
            Text("Paste MCP Config JSON")
                .font(JarvisFont.title)
                .foregroundStyle(Color.jarvisTextPrimary)

            Text("Paste a valid MCP config JSON below:")
                .font(JarvisFont.caption)
                .foregroundStyle(Color.jarvisTextSecondary)

            TextEditor(text: $jsonText)
                .font(JarvisFont.code)
                .frame(minHeight: 200)
                .background(Color.jarvisSurfaceDeep)
                .overlay(RoundedRectangle(cornerRadius: JarvisRadius.small).stroke(Color.jarvisBorder, lineWidth: 1))
                .cornerRadius(JarvisRadius.small)

            Text("Example format:")
                .font(JarvisFont.caption)
                .foregroundStyle(Color.jarvisTextSecondary)

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
            .font(JarvisFont.captionMono)
            .foregroundStyle(Color.jarvisTextDim)
            .padding(JarvisSpacing.sm)
            .background(Color.jarvisSurfaceDeep)
            .cornerRadius(JarvisRadius.small)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.jarvisTextSecondary)
                    .padding(.horizontal, JarvisSpacing.lg)
                    .padding(.vertical, JarvisSpacing.sm)
                    .background(Color.jarvisSurfaceLight)
                    .cornerRadius(JarvisRadius.medium)
                Button("Import") {
                    onSubmit()
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.jarvisTextPrimary)
                .padding(.horizontal, JarvisSpacing.lg)
                .padding(.vertical, JarvisSpacing.sm)
                .background(Color.jarvisBlue)
                .cornerRadius(JarvisRadius.medium)
                .disabled(jsonText.isEmpty)
            }
        }
        .padding()
        .frame(width: 500, height: 450)
        .background(Color.jarvisSurfaceDark)
    }
}

#Preview {
    MCPConfigView()
}
