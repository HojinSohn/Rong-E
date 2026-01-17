import Foundation

// MARK: - MCP Configuration Models

/// Represents a single MCP server configuration
struct MCPServerConfig: Codable, Identifiable, Equatable {
    var id: String { name }
    let name: String
    let command: String
    let args: [String]
    let env: [String: String]?

    init(name: String, command: String, args: [String], env: [String: String]? = nil) {
        self.name = name
        self.command = command
        self.args = args
        self.env = env
    }

    enum CodingKeys: String, CodingKey {
        case command, args, env
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Name is set separately when decoding from dictionary
        self.name = ""
        self.command = try container.decode(String.self, forKey: .command)
        self.args = try container.decodeIfPresent([String].self, forKey: .args) ?? []
        self.env = try container.decodeIfPresent([String: String].self, forKey: .env)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(command, forKey: .command)
        try container.encode(args, forKey: .args)
        if let env = env {
            try container.encode(env, forKey: .env)
        }
    }
}

/// Root MCP configuration containing multiple servers
struct MCPConfig: Codable {
    var mcpServers: [String: MCPServerConfigData]

    struct MCPServerConfigData: Codable {
        let command: String
        let args: [String]?
        let env: [String: String]?
    }

    /// Convert to array of MCPServerConfig for UI display
    func toServerList() -> [MCPServerConfig] {
        return mcpServers.map { (name, data) in
            MCPServerConfig(
                name: name,
                command: data.command,
                args: data.args ?? [],
                env: data.env
            )
        }.sorted { $0.name < $1.name }
    }

    /// Create from array of MCPServerConfig
    static func from(servers: [MCPServerConfig]) -> MCPConfig {
        var mcpServers: [String: MCPServerConfigData] = [:]
        for server in servers {
            mcpServers[server.name] = MCPServerConfigData(
                command: server.command,
                args: server.args.isEmpty ? nil : server.args,
                env: server.env
            )
        }
        return MCPConfig(mcpServers: mcpServers)
    }
}

// MARK: - Validation

enum MCPConfigError: LocalizedError {
    case invalidJSON(String)
    case missingMcpServers
    case emptyServerName
    case missingCommand(serverName: String)
    case invalidCommand(serverName: String, command: String)
    case fileNotFound(path: String)
    case readError(String)

    var errorDescription: String? {
        switch self {
        case .invalidJSON(let detail):
            return "Invalid JSON format: \(detail)"
        case .missingMcpServers:
            return "Config must contain 'mcpServers' key"
        case .emptyServerName:
            return "Server name cannot be empty"
        case .missingCommand(let name):
            return "Server '\(name)' is missing required 'command' field"
        case .invalidCommand(let name, let cmd):
            return "Server '\(name)' has invalid command: '\(cmd)'"
        case .fileNotFound(let path):
            return "Config file not found: \(path)"
        case .readError(let detail):
            return "Failed to read config: \(detail)"
        }
    }
}

struct MCPConfigValidator {

    /// Validate and parse MCP config from file URL
    static func validate(fileURL: URL) throws -> MCPConfig {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw MCPConfigError.fileNotFound(path: fileURL.path)
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw MCPConfigError.readError(error.localizedDescription)
        }

        return try validate(data: data)
    }

    /// Validate and parse MCP config from JSON data
    static func validate(data: Data) throws -> MCPConfig {
        let config: MCPConfig
        do {
            config = try JSONDecoder().decode(MCPConfig.self, from: data)
        } catch let error as DecodingError {
            throw MCPConfigError.invalidJSON(describeDecodingError(error))
        } catch {
            throw MCPConfigError.invalidJSON(error.localizedDescription)
        }

        // Validate structure
        try validateServers(config)

        return config
    }

    /// Validate and parse MCP config from JSON string
    static func validate(jsonString: String) throws -> MCPConfig {
        guard let data = jsonString.data(using: .utf8) else {
            throw MCPConfigError.invalidJSON("Failed to encode string as UTF-8")
        }
        return try validate(data: data)
    }

    private static func validateServers(_ config: MCPConfig) throws {
        if config.mcpServers.isEmpty {
            throw MCPConfigError.missingMcpServers
        }

        for (name, serverData) in config.mcpServers {
            if name.trimmingCharacters(in: .whitespaces).isEmpty {
                throw MCPConfigError.emptyServerName
            }

            if serverData.command.trimmingCharacters(in: .whitespaces).isEmpty {
                throw MCPConfigError.missingCommand(serverName: name)
            }

            // Basic command validation (no path traversal, reasonable characters)
            let cmd = serverData.command
            if cmd.contains("..") || cmd.hasPrefix("/") && !FileManager.default.fileExists(atPath: cmd) {
                // Allow common commands that might not exist at validation time
                let allowedCommands = ["npx", "node", "python", "python3", "uvx", "cargo"]
                if !allowedCommands.contains(cmd) {
                    throw MCPConfigError.invalidCommand(serverName: name, command: cmd)
                }
            }
        }
    }

    private static func describeDecodingError(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, _):
            return "Missing key: '\(key.stringValue)'"
        case .typeMismatch(let type, let context):
            return "Type mismatch for '\(context.codingPath.map { $0.stringValue }.joined(separator: "."))': expected \(type)"
        case .valueNotFound(let type, let context):
            return "Missing value for '\(context.codingPath.map { $0.stringValue }.joined(separator: "."))': expected \(type)"
        case .dataCorrupted(let context):
            return "Corrupted data: \(context.debugDescription)"
        @unknown default:
            return error.localizedDescription
        }
    }
}

// MARK: - Persistence

class MCPConfigManager: ObservableObject {
    static let shared = MCPConfigManager()

    @Published var currentConfig: MCPConfig?
    @Published var servers: [MCPServerConfig] = []
    @Published var lastError: String?
    @Published var isLoading: Bool = false

    private let configKey = "mcp_config"

    private init() {
        loadFromDefaults()
    }

    /// Load config from a file URL
    func loadConfig(from url: URL) {
        isLoading = true
        lastError = nil

        do {
            let config = try MCPConfigValidator.validate(fileURL: url)
            self.currentConfig = config
            self.servers = config.toServerList()
            saveToDefaults()

            // Send to Python backend
            sendConfigToPython()
        } catch {
            lastError = error.localizedDescription
        }

        isLoading = false
    }

    /// Load config from JSON string (e.g., pasted content)
    func loadConfig(from jsonString: String) {
        isLoading = true
        lastError = nil

        do {
            let config = try MCPConfigValidator.validate(jsonString: jsonString)
            self.currentConfig = config
            self.servers = config.toServerList()
            saveToDefaults()

            // Send to Python backend
            sendConfigToPython()
        } catch {
            lastError = error.localizedDescription
        }

        isLoading = false
    }

    /// Add a new server to the config
    func addServer(_ server: MCPServerConfig) {
        servers.append(server)
        currentConfig = MCPConfig.from(servers: servers)
        saveToDefaults()
        sendConfigToPython()
    }

    /// Remove a server from the config
    func removeServer(_ server: MCPServerConfig) {
        servers.removeAll { $0.name == server.name }
        currentConfig = MCPConfig.from(servers: servers)
        saveToDefaults()
        sendConfigToPython()
    }

    /// Clear all servers
    func clearConfig() {
        servers = []
        currentConfig = nil
        UserDefaults.standard.removeObject(forKey: configKey)
        sendConfigToPython()
    }

    /// Send current config to Python backend via WebSocket
    func sendConfigToPython() {
        guard let config = currentConfig else {
            // Send empty config to clear servers
            SocketClient.shared.sendMCPConfig(MCPConfig(mcpServers: [:]))
            return
        }
        SocketClient.shared.sendMCPConfig(config)
    }

    private func saveToDefaults() {
        guard let config = currentConfig,
              let data = try? JSONEncoder().encode(config) else { return }
        UserDefaults.standard.set(data, forKey: configKey)
    }

    private func loadFromDefaults() {
        guard let data = UserDefaults.standard.data(forKey: configKey),
              let config = try? JSONDecoder().decode(MCPConfig.self, from: data) else { return }
        self.currentConfig = config
        self.servers = config.toServerList()
    }
}
