import Cocoa
import ScreenCaptureKit
import CoreGraphics

class ScreenshotManager {
    // Singleton instance
    static let shared = ScreenshotManager()

    private init() {}

    /// Request screen capture permission (opens System Settings)
    static func requestScreenCapturePermission() {
        CGRequestScreenCaptureAccess()
    }

    /// Async function to capture the main screen
    /// Returns: Base64 JPEG String
    @MainActor
    static func captureMainScreen() async throws -> String? {
        print("📸 Starting main screen capture...")

        // Attempt to get shareable content directly.
        // On macOS 14+, CGPreflightScreenCaptureAccess() is unreliable and can
        // return false even when ScreenCaptureKit permission is granted.
        // Instead, we attempt the call and catch the actual SCK error.
        let availableContent: SCShareableContent
        do {
            availableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            let nsError = error as NSError
            print("❌ SCShareableContent failed: \(nsError.domain) code=\(nsError.code) \(nsError.localizedDescription)")
            // ScreenCaptureKit returns specific errors when permission is denied
            // SCStreamError code 1 = userDeclined, or general content access errors
            throw NSError(
                domain: "ScreenshotManager",
                code: -3801,
                userInfo: [
                    NSLocalizedDescriptionKey: "Screen capture permission not granted",
                    NSUnderlyingErrorKey: error
                ]
            )
        }

        // Find the main display (origin at 0,0)
        guard let mainDisplay = availableContent.displays.first(where: { $0.frame.origin.x == 0 && $0.frame.origin.y == 0 }) else {
            print("❌ No main display found.")
            return nil
        }

        // Create filter and configuration
        let filter = SCContentFilter(display: mainDisplay, excludingApplications: [], exceptingWindows: [])

        let config = SCStreamConfiguration()
        config.width = Int(mainDisplay.width)
        config.height = Int(mainDisplay.height)
        config.showsCursor = true

        // Capture the screen
        let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)

        // Convert to Base64 JPEG
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        guard let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) else {
            return nil
        }

        print("✅ Screen capture successful, base64 size: \(jpegData.count)")
        return jpegData.base64EncodedString()
    }
}