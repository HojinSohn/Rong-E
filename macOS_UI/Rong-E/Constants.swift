// Constants.swift

import CoreFoundation
import CoreGraphics
import Foundation


enum Constants {
    static let apiKey = "sk-123456789"
    static let baseURL = "https://api.anthropic.com"
    
    // You can also nest them for better organization
    enum UI {
        static let windowWidth: CGFloat = 800
        static let windowHeight: CGFloat = 600
        static let cornerRadius: CGFloat = 12.0
        enum overlayWindow {
            static let compactWidth: CGFloat = 140.0
            static let compactHeight: CGFloat = 50.0
            static let expandedWidth: CGFloat = 300.0
            static let expandedHeight: CGFloat = 160.0
            static let inputModeHeight: CGFloat = 300.0
            static let animationDuration: TimeInterval = 0.3

            static let padding: CGFloat = 16.0
        }
    }
    
    enum System {
        static let maxRetries = 3
        static let timeout: TimeInterval = 30.0
    }

    enum Tools {
        static let availableTools = ["web_search", "search_knowledge_base", "email", "calendar"]
    }
}
