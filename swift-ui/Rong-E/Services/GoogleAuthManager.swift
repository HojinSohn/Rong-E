import AppKit
import Foundation
import SwiftUI

class GoogleAuthManager: ObservableObject {
    // Dependencies
    let context: AppContext
    let client: SocketClient
    private let fileManager = FileManager.default

    // Singleton instance
    static let shared = GoogleAuthManager()

    private init() {
        self.context = AppContext.shared
        self.client = SocketClient.shared
        
        // Listen for success from Python
        self.client.onReceivedCredentialsSuccess = { [weak self] successText in
            print("✅ Global Auth Manager received success: \(successText)")
            DispatchQueue.main.async {
                withAnimation {
                    self?.context.isGoogleConnected = true
                }
            }
        }

        // Listen for auth errors (e.g. expired token with no refresh token)
        self.client.onCredentialsError = { [weak self] errorText in
            print("❌ Global Auth Manager received credentials error: \(errorText)")
            DispatchQueue.main.async {
                withAnimation {
                    self?.context.isGoogleConnected = false
                }
            }
        }

        // Open the Google consent URL in the default browser
        self.client.onOAuthURL = { urlString in
            print("🌐 Opening OAuth URL in browser")
            if let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    // Computed Path
    var destinationURL: URL {
        context.credentialsDirectory.appendingPathComponent("credentials.json")
    }
    
    var tokenURL: URL {
        context.credentialsDirectory.appendingPathComponent("token.json")
    }
    
    var credentialsFileExists: Bool {
        fileManager.fileExists(atPath: destinationURL.path)
    }

    // MARK: - Lifecycle Methods
    
    /// Called when the App launches
    func startupCheck() {
        // 1. Ensure Directory Exists
        if !fileManager.fileExists(atPath: context.credentialsDirectory.path) {
            do {
                try fileManager.createDirectory(at: context.credentialsDirectory, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print("❌ Error creating credentials directory: \(error)")
                return
            }
        }
        
        // 2. Check for existing credentials and auto-connect
        if credentialsFileExists {
            print("🔄 Found existing credentials on startup. Connecting...")
            connect()
        } else {
            print("ℹ️ No credentials found on startup.")
            DispatchQueue.main.async {
                self.context.isGoogleConnected = false
            }
        }
    }

    // MARK: - Actions
    
    /// Triggers the full browser-based OAuth2 flow to get a fresh token with refresh_token.
    /// Call this when `connect()` fails with a credentials_error.
    func startOAuth() {
        guard credentialsFileExists else {
            print("❌ Cannot start OAuth: No credentials.json found.")
            return
        }
        print("🔐 Starting OAuth re-authentication flow...")
        client.sendStartOAuth(dirPath: context.credentialsDirectory.path)
    }

    func connect() {
        print("🔗 Attempting to connect Google Services...")
        guard credentialsFileExists else {
            print("❌ Cannot connect: No credentials file.")
            return
        }
        
        // Send the DIRECTORY path to Python (as per your previous code)
        // Python will look for 'credentials.json' and 'token.json' inside this folder
        print("🚀 Sending credential path to Python: \(context.credentialsDirectory.path)")
        client.sendCredentials(CredentialDataType.credentials, content: context.credentialsDirectory.path)
    }
    
    func importCredentials(from sourceURL: URL) {
        do {
            // 1. Unlock Security Scope
            let accessGranted = sourceURL.startAccessingSecurityScopedResource()
            defer { if accessGranted { sourceURL.stopAccessingSecurityScopedResource() } }
            
            guard accessGranted else {
                print("❌ Permission denied for selected file")
                return
            }
            
            // 2. Copy to App Support
            if credentialsFileExists {
                try fileManager.removeItem(at: destinationURL)
            }
            
            let data = try Data(contentsOf: sourceURL)
            try data.write(to: destinationURL)
            print("✅ Credentials imported to: \(destinationURL.path)")
            
            // 3. Auto-trigger connection
            connect()
            
        } catch {
            print("❌ Error importing credentials: \(error)")
        }
    }
    
    func revoke() {
        do {
            // 1. Delete Files
            if credentialsFileExists {
                try fileManager.removeItem(at: destinationURL)
            }
            if fileManager.fileExists(atPath: tokenURL.path) {
                try fileManager.removeItem(at: tokenURL)
            }
            
            // 2. Notify Python
            client.sendCredentials(CredentialDataType.revoke_credentials, content: "")
            
            // 3. Update UI
            DispatchQueue.main.async {
                withAnimation {
                    self.context.isGoogleConnected = false
                }
            }
            print("🛑 Credentials revoked and files deleted.")
            
        } catch {
            print("❌ Error revoking credentials: \(error)")
        }
    }
}