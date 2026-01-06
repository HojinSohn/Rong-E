import Foundation
import Foundation
import Combine

// 1. Define the structure of messages coming from Python
struct AgentMessage: Codable {
    let type: String
    let content: ResponseContent?
    let text: String?
}

// 2. Define the content structure for final responses
struct ResponseContent: Codable {
    let text: String
    let images: [ImageData]
}

// 3. Define image data structure
struct ImageData: Codable {
    let url: String
    let alt: String?
    let author: String?
}

// enum for data types
enum CredentialDataType: String {
    case apiKey = "api_key"
    case credentials = "credentials"
    case revoke_credentials = "revoke_credentials"
}

// Add a struct for the payload
struct ChatPayload: Codable {
    let text: String
    let mode: String
    let base64_image: String? // Base64 string (optional)
}

class SocketClient: ObservableObject {
    // Singleton instance
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
    // MARK: - Callbacks
    var onReceiveThought: ((String) -> Void)?
    var onReceiveResponse: ((String) -> Void)?
    var onReceiveImages: (([ImageData]) -> Void)?
    var onDisconnect: ((String) -> Void)?
    var onReceivedCredentialsSuccess: ((String) -> Void)?

    func checkAndUpdateConnection() -> Bool {
        let active = webSocketTask?.state == .running
        // Sync our published property just in case
        if isConnected != active {
            DispatchQueue.main.async { self.isConnected = active }
        }
        return active
    }

    func connect() {
        let url = URL(string: "ws://127.0.0.1:8000/ws")!
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        
        // start receiving messages
        receiveMessages()
    }
    
    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
    }

    private func updateStatus(connected: Bool) {
        // add buffer time for connection stability
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.isConnected = connected
        }
    }

    private func receiveMessages() {
        Task {
            guard let task = webSocketTask else { return }
            
            while task.state == .running {
                do {
                    // update connection status
                    updateStatus(connected: true)
                    let message = try await task.receive()
                    switch message {
                        case .string(let text):
                            self.handleMessage(text)
                        default: break
                    }
                } catch {
                    print("❌ Socket Error: \(error)")
                    DispatchQueue.main.async {
                        self.onDisconnect?("Connection lost: \(error.localizedDescription)")
                    }
                    // update connection status
                    updateStatus(connected: false)
                    return // Exit the loop
                }
            }
        }
    }

    private func parseTextMessage(_ text: String) -> AgentMessage? {
        guard let data = text.data(using: .utf8),
              let parsedMsg = try? self.decoder.decode(AgentMessage.self, from: data) else { return nil }
        return parsedMsg
    }

    private func respondToParsedMessage(_ parsedMsg: AgentMessage) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if parsedMsg.type == "thought", let text = parsedMsg.text {
                self.onReceiveThought?(text)
            } else if parsedMsg.type == "final", let content = parsedMsg.content {
                self.onReceiveResponse?(content.text)
                if !content.images.isEmpty {
                    self.onReceiveImages?(content.images)
                }
            } else if parsedMsg.type == "credentials_success", let text = parsedMsg.text {
                print("✅ Credentials Success Received: \(text)")
                print("✅ Triggering onReceivedCredentialsSuccess callback")
                print("🎯 Callback exists: \(self.onReceivedCredentialsSuccess != nil)")
                self.onReceivedCredentialsSuccess?(text)
            }
        }
    }
    
    private func handleMessage(_ text: String) {
        guard let parsedMsg = parseTextMessage(text) else {
            print("❌ Failed to parse message: \(text)")
            return
        }

        respondToParsedMessage(parsedMsg)
    }

    func sendMessage(_ text: String, mode: String) {
        let json = ChatPayload(text: text, mode: mode, base64_image: nil)
        if let jsonData = try? JSONEncoder().encode(json), 
           let jsonString = String(data: jsonData, encoding: .utf8) {
            let message = URLSessionWebSocketTask.Message.string(jsonString)
            webSocketTask?.send(message) { error in
                if let error = error { print("❌ Send Error: \(error)") }
            }
        }
    }


    func sendMessageWithImage(_ text: String, mode: String, base64Image: String? = nil) {
        let payload = ChatPayload(text: text, mode: mode, base64_image: base64Image)
        
        // Encode to JSON
        if let jsonData = try? JSONEncoder().encode(payload),
        let jsonString = String(data: jsonData, encoding: .utf8) {
            let message = URLSessionWebSocketTask.Message.string(jsonString)
            webSocketTask?.send(message) { error in
                if let error = error { print("❌ Send Error: \(error)") }
            }
        }
    }


    func sendCredentials(_ dataType: CredentialDataType, content: String) {
        print("🔐 Sending credentials of type: \(dataType.rawValue) with content: \(content)")
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
