import Cocoa
import ScreenCaptureKit // 1. Import the new framework

class ScreenshotManager {
    // Singleton instance
    static let shared = ScreenshotManager()

    private init() {}
    
    /// Async function to capture the main screen
    /// Returns: Base64 JPEG String
    @MainActor
    static func captureMainScreen() async throws -> String? {
        print("📸 Starting main screen capture...")
        
        // 2. Get available content (Displays, Windows, Apps)
        let availableContent = try await SCShareableContent.current
        
        // 3. Find the main display
        // We look for the display that starts at (0,0) which is always the 'main' display in macOS
        guard let mainDisplay = availableContent.displays.first(where: { $0.frame.origin.x == 0 && $0.frame.origin.y == 0 }) else {
            print("❌ No main display found.")
            return nil
        }
        
        // 4. Create a "Filter" (What to capture)
        // capturing the display, including all windows/apps
        let filter = SCContentFilter(display: mainDisplay, excludingApplications: [], exceptingWindows: [])
        
        // 5. Create a "Configuration" (How to capture)
        let config = SCStreamConfiguration()
        config.width = Int(mainDisplay.width)
        config.height = Int(mainDisplay.height)
        config.showsCursor = true // Whether you want the mouse pointer visible
        
        // 6. Capture! (New in macOS 14)
        // If you are on macOS 13 or lower, this specific line won't work, let me know.
        let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        
        // 7. Convert to Base64 (Same as before)
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        guard let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) else {
            return nil
        }
        
        return jpegData.base64EncodedString()
    }
}