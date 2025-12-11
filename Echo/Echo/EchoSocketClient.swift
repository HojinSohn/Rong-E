import Foundation

// 1. Define the structure of messages coming from Python
struct AgentMessage: Codable {
    let type: String    // "thought" or "response"
    let content: String // The actual text
}

class EchoSocketClient: ObservableObject {
    private var webSocketTask: URLSessionWebSocketTask?
    private let url = URL(string: "ws://127.0.0.1:8000/ws")!
    
    // 2. Separate callbacks for thoughts vs final answers
    var onReceiveThought: ((String) -> Void)?  // Updates the small "Thinking..." text
    var onReceiveResponse: ((String) -> Void)? // Updates the main typewriter text
    var onDisconnect: ((String) -> Void)?

    init() { connect() }

    func connect() {
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        print("🔌 WebSocket Connected")
        listen()
    }
    
    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
    }

    func sendMessage(_ text: String) {
        let message = URLSessionWebSocketTask.Message.string(text)
        webSocketTask?.send(message) { error in
            if let error = error { print("❌ Send Error: \(error)") }
        }
    }

    private func listen() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    // 3. Parse JSON
                    if let data = text.data(using: .utf8),
                       let parsedMsg = try? JSONDecoder().decode(AgentMessage.self, from: data) {
                        
                        DispatchQueue.main.async {
                            if parsedMsg.type == "thought" {
                                // It's a thought! Update small status text
                                self.onReceiveThought?(parsedMsg.content)
                            } else {
                                // It's the answer! Update main text
                                self.onReceiveResponse?(parsedMsg.content)
                            }
                        }
                    }
                default: break
                }
                self.listen() // Keep listening
                
            case .failure(let error):
                print("Socket Error: \(error)")
                self.listen() // Try to reconnect/listen again
            }
        }
    }
}