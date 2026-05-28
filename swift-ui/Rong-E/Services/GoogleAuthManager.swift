import AppKit
import Foundation
import SwiftUI

class GoogleAuthManager: ObservableObject {
    let context: AppContext
    let client: SocketClient

    static let shared = GoogleAuthManager()

    private static let sessionTokenKey = "google_session_token"

    private init() {
        self.context = AppContext.shared
        self.client = SocketClient.shared

        self.client.onReceivedCredentialsSuccess = { [weak self] _ in
            DispatchQueue.main.async {
                withAnimation { self?.context.isGoogleConnected = true }
            }
        }

        self.client.onCredentialsError = { [weak self] _ in
            DispatchQueue.main.async {
                withAnimation { self?.context.isGoogleConnected = false }
            }
        }

        // Open the backend OAuth URL in the default browser
        self.client.onOAuthURL = { urlString in
            print("🌐 Opening OAuth URL in browser")
            if let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
        }

        // Persist the session JWT so we can restore it after restart
        self.client.onSessionToken = { token in
            UserDefaults.standard.set(token, forKey: Self.sessionTokenKey)
            print("💾 Google session token saved to UserDefaults")
        }
    }

    // MARK: - Lifecycle

    func startupCheck() {
        // Always push the configured backend URL into the subprocess first
        client.sendSetBackendUrl(context.backendUrl)

        guard let token = UserDefaults.standard.string(forKey: Self.sessionTokenKey),
              !token.isEmpty else {
            print("ℹ️ No stored Google session found on startup.")
            DispatchQueue.main.async { self.context.isGoogleConnected = false }
            return
        }
        print("🔄 Restoring Google session from UserDefaults...")
        client.sendRestoreSession(token: token)
    }

    // MARK: - Actions

    func startOAuth() {
        print("🔐 Starting Google OAuth via backend...")
        client.sendSetBackendUrl(context.backendUrl)
        client.sendStartOAuth()
    }

    func revoke() {
        UserDefaults.standard.removeObject(forKey: Self.sessionTokenKey)
        client.sendCredentials(CredentialDataType.revoke_credentials, content: "")
        DispatchQueue.main.async {
            withAnimation { self.context.isGoogleConnected = false }
        }
        print("🛑 Google session revoked.")
    }
}
