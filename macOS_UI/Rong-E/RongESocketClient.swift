import Foundation
import Combine

// 1. Define the structure of messages coming from Python
struct AgentMessage: Codable {
    let type: String
    let content: CodableContent
    
    // Helper property to extract text if available
    var text: String? {
        if case .response(let r) = content { return r.text }
        if case .thought(let t) = content { return t.text }
        return nil
    }

    enum CodingKeys: String, CodingKey {
        case type, content
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)

        switch type {
        case "response", "final":
            let val = try container.decode(ResponseContent.self, forKey: .content)
            content = .response(val)
        case "thought":
            let val = try container.decode(ThoughtContent.self, forKey: .content)
            content = .thought(val)
        case "tool_call":
            let val = try container.decode(ToolCallContent.self, forKey: .content)
            content = .toolCall(val)
        case "tool_result":
            let val = try container.decode(ToolResultContent.self, forKey: .content)
            content = .toolResult(val)
        case "credentials_success", "error":
            // Handle simple string content for status messages
            if let stringContent = try? container.decode(String.self, forKey: .content) {
                content = .response(ResponseContent(text: stringContent, images: []))
            } else {
                 let val = try container.decode(ThoughtContent.self, forKey: .content)
                 content = .thought(val)
            }
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown message type: \(type)")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        switch content {
        case .response(let c): try container.encode(c, forKey: .content)
        case .thought(let c): try container.encode(c, forKey: .content)
        case .toolCall(let c): try container.encode(c, forKey: .content)
        case .toolResult(let c): try container.encode(c, forKey: .content)
        }
    }
}

// Wrapper for different content types
enum CodableContent {
    case response(ResponseContent)
    case thought(ThoughtContent)
    case toolCall(ToolCallContent)
    case toolResult(ToolResultContent)
}

struct ResponseContent: Codable {
    let text: String
    let images: [ImageData]
}

struct ThoughtContent: Codable {
    let text: String
}

// MARK: - Tool Call Content (Fixed Keys)
struct ToolCallContent: Codable {
    let toolName: String
    let toolArgs: [String: AnyCodable]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        toolName = try container.decode(String.self, forKey: .toolName)
        // Default to empty dict if args are missing/null
        toolArgs = try container.decodeIfPresent([String: AnyCodable].self, forKey: .toolArgs) ?? [:]
    }

    // Default init for manual creation if needed
    init(toolName: String, toolArgs: [String: AnyCodable]) {
        self.toolName = toolName
        self.toolArgs = toolArgs
    }
}

// MARK: - Tool Result Content (Fixed Keys)
struct ToolResultContent: Codable {
    let toolName: String
    let result: String
}

struct ImageData: Codable {
    let url: String
    let alt: String?
    let author: String?
}

enum CredentialDataType: String {
    case apiKey = "api_key"
    case credentials = "credentials"
    case revoke_credentials = "revoke_credentials"
}

struct ChatPayload: Codable {
    let text: String
    let mode: String
    let base64_image: String?
}

// MARK: - Socket Client
class SocketClient: ObservableObject {
    static let shared = SocketClient()

    private init() {
        connect()
    }

    deinit {
        disconnect()
    }

    private var webSocketTask: URLSessionWebSocketTask?
    private let decoder = JSONDecoder()
    @Published var isConnected: Bool = false
    
    var onReceiveThought: ((String) -> Void)?
    var onReceiveResponse: ((String) -> Void)?
    var onReceiveToolCall: ((ToolCallContent) -> Void)?
    var onReceiveToolOutput: ((ToolResultContent) -> Void)?
    var onReceiveImages: (([ImageData]) -> Void)?
    var onDisconnect: ((String) -> Void)?
    var onReceivedCredentialsSuccess: ((String) -> Void)?

    func checkAndUpdateConnection() -> Bool {
        let active = webSocketTask?.state == .running
        if isConnected != active {
            DispatchQueue.main.async { self.isConnected = active }
        }
        return active
    }

    func connect() {
        if webSocketTask?.state == .running { return }

        let url = URL(string: "ws://127.0.0.1:8000/ws")!
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        
        receiveMessages()
        DispatchQueue.main.async { self.isConnected = true }
    }
    
    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        DispatchQueue.main.async { self.isConnected = false }
    }

    private func receiveMessages() {
        Task {
            guard let task = webSocketTask else { return }
            while task.state == .running {
                do {
                    let message = try await task.receive()
                    switch message {
                    case .string(let text):
                        print("📩 Received: \(text)")
                        self.handleMessage(text)
                    default: break
                    }
                } catch {
                    print("❌ Socket Receive Error: \(error)")
                    DispatchQueue.main.async {
                        self.onDisconnect?("Connection lost: \(error.localizedDescription)")
                        self.isConnected = false
                    }
                    return
                }
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        do {
            let parsedMsg = try self.decoder.decode(AgentMessage.self, from: data)
            respondToParsedMessage(parsedMsg)
        } catch {
            print("❌ JSON Decode Error: \(error)")
        }
    }

    private func respondToParsedMessage(_ parsedMsg: AgentMessage) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            switch parsedMsg.type {
            case "thought":
                if case .thought(let content) = parsedMsg.content {
                    self.onReceiveThought?(content.text)
                }
            case "response", "final":
                if case .response(let content) = parsedMsg.content {
                    self.onReceiveResponse?(content.text)
                    self.onReceiveImages?(content.images)
                }
            case "tool_call":
                if case .toolCall(let content) = parsedMsg.content {
                    print("🔧 Tool Call: \(content.toolName)")
                    self.onReceiveToolCall?(content)
                }
            case "tool_result":
                if case .toolResult(let content) = parsedMsg.content {
                    print("🛠 Tool Result: \(content.toolName)")
                    self.onReceiveToolOutput?(content)
                }
            case "credentials_success":
                if case .response(let content) = parsedMsg.content {
                     self.onReceivedCredentialsSuccess?(content.text)
                }
            default:
                print("❓ Unhandled type: \(parsedMsg.type)")
            }
        }
    }

    func sendMessage(_ text: String, mode: String) {
        sendMessageWithImage(text, mode: mode, base64Image: nil)
    }

    func sendMessageWithImage(_ text: String, mode: String, base64Image: String? = nil) {
        let payload = ChatPayload(text: text, mode: mode, base64_image: base64Image)
        if let jsonData = try? JSONEncoder().encode(payload),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            let message = URLSessionWebSocketTask.Message.string(jsonString)
            webSocketTask?.send(message) { error in
                if let error = error {
                    print("❌ Send Error: \(error)")
                    DispatchQueue.main.async { self.isConnected = false }
                }
            }
        }
    }

    func sendCredentials(_ dataType: CredentialDataType, content: String) {
        let json: [String: String] = ["data_type": dataType.rawValue, "content": content]
        if let jsonData = try? JSONEncoder().encode(json), 
           let jsonString = String(data: jsonData, encoding: .utf8) {
            let message = URLSessionWebSocketTask.Message.string(jsonString)
            webSocketTask?.send(message) { error in
                if let error = error { print("❌ Send Error: \(error)") }
            }
        }
    }
}

// MARK: - Helper for decoding dynamic JSON values
enum AnyCodable: Codable, CustomStringConvertible {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([AnyCodable])
    case dict([String: AnyCodable])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let b = try? container.decode(Bool.self) { self = .bool(b) }
        else if let i = try? container.decode(Int.self) { self = .int(i) }
        else if let d = try? container.decode(Double.self) { self = .double(d) }
        else if let s = try? container.decode(String.self) { self = .string(s) }
        else if let a = try? container.decode([AnyCodable].self) { self = .array(a) }
        else if let dict = try? container.decode([String: AnyCodable].self) { self = .dict(dict) }
        else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode AnyCodable") }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let b): try container.encode(b)
        case .int(let i): try container.encode(i)
        case .double(let d): try container.encode(d)
        case .string(let s): try container.encode(s)
        case .array(let a): try container.encode(a)
        case .dict(let d): try container.encode(d)
        }
    }
    
    var description: String {
        switch self {
        case .null: return "null"
        case .bool(let b): return b.description
        case .int(let i): return i.description
        case .double(let d): return d.description
        case .string(let s): return "\"\(s)\""
        case .array(let a): return "\(a)"
        case .dict(let d): return "\(d)"
        }
    }
}