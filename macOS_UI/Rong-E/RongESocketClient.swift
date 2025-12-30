import Foundation

// 1. Define the structure of messages coming from Python
struct AgentMessage: Codable {
    let type: String    // "thought", "response", or "final"
    let content: ResponseContent? // For "final" type with text + images
    let text: String?   // For simple "thought" or "response" types
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
import Foundation
import Combine

class SocketClient: ObservableObject {
    private var webSocketTask: URLSessionWebSocketTask?
    private let decoder = JSONDecoder()
    @Published var isConnected: Bool = false
    // MARK: - Callbacks
    var onReceiveThought: ((String) -> Void)?
    var onReceiveResponse: ((String) -> Void)?
    var onReceiveImages: (([ImageData]) -> Void)?
    var onDisconnect: ((String) -> Void)?
    
    init() { connect() }

    deinit {
        disconnect()
    }

    func checkConnection() -> Bool {
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
        
        receiveMessages()
    }
    
    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
    }

    private func receiveMessages() {
        Task {
            guard let task = webSocketTask else { return }
            
            while task.state == .running {
                do {
                    // update connection status
                    DispatchQueue.main.async { 
                        // add buffer time for connection stability
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            self.isConnected = true 
                        }
                    }
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
                    DispatchQueue.main.async {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            self.isConnected = false 
                        }
                    }
                    return // Exit the loop
                }
            }
        }
    }
    
    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let parsedMsg = try? self.decoder.decode(AgentMessage.self, from: data) else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if parsedMsg.type == "thought", let text = parsedMsg.text {
                self.onReceiveThought?(text)
            } else if parsedMsg.type == "final", let content = parsedMsg.content {
                self.onReceiveResponse?(content.text)
                if !content.images.isEmpty {
                    self.onReceiveImages?(content.images)
                }
            }
        }
    }

    func sendMessage(_ text: String, mode: String) {
        let json: [String: String] = ["mode": mode, "message": text]
        if let jsonData = try? JSONEncoder().encode(json), 
           let jsonString = String(data: jsonData, encoding: .utf8) {
            let message = URLSessionWebSocketTask.Message.string(jsonString)
            webSocketTask?.send(message) { error in
                if let error = error { print("❌ Send Error: \(error)") }
            }
        }
    }
}