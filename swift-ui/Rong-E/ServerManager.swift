//
//  ServerManager.swift
//  Rong-E
//
//  Created by Hojin Sohn on 2/16/26.
//


import Foundation
import Combine

class ServerManager: ObservableObject {
    static let shared = ServerManager()

    @Published private(set) var isRunning: Bool = false

    private var process: Process?
    private var outputPipe: Pipe?

    // Default URL for your websocket
    let socketURL = URL(string: "ws://127.0.0.1:3000/ws")!

    private init() {}

    deinit {
        stopServer()
    }

    func startServer() {
        guard !isRunning else {
            print("⚠️ Rust server is already running")
            return
        }

        // 1. Find the compiled binary (not the source folder)
        let serverPath: String
        if let path = findDevBinary() {
            // Dev: use the cargo-built binary directly
            serverPath = path
        } else if let bundlePath = Bundle.main.path(forResource: "agent_server", ofType: nil) {
            // Production: check it's a file, not a directory
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: bundlePath, isDirectory: &isDir),
               !isDir.boolValue,
               FileManager.default.isExecutableFile(atPath: bundlePath) {
                serverPath = bundlePath
            } else {
                print("❌ 'agent_server' in bundle is a folder, not the compiled binary.")
                return
            }
        } else {
            print("❌ Could not find 'agent_server' binary.")
            return
        }

        print("🦀 Starting Rust server from: \(serverPath)")

        // 2. Configure the process
        let newProcess = Process()
        let newPipe = Pipe()

        newProcess.executableURL = URL(fileURLWithPath: serverPath)
        newProcess.arguments = []
        newProcess.standardOutput = newPipe
        newProcess.standardError = newPipe

        // 3. Pipe stdout/stderr to Xcode console
        newPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }
            print("[Rust]: \(line.trimmingCharacters(in: .whitespacesAndNewlines))")
        }

        // 4. Handle termination
        newProcess.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                self?.isRunning = false
                print("🦀 Rust server exited (code: \(proc.terminationStatus))")
            }
        }

        // 5. Run
        do {
            try newProcess.run()
            self.process = newProcess
            self.outputPipe = newPipe
            self.isRunning = true
            print("✅ Rust server started (PID: \(newProcess.processIdentifier))")
        } catch {
            print("❌ Failed to start Rust server: \(error)")
        }
    }

    func stopServer() {
        guard let process = process, isRunning else { return }
        print("🛑 Stopping Rust server...")
        process.terminate()
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        outputPipe = nil
        self.process = nil
        isRunning = false
    }

    /// Find the compiled binary during development (not in bundle)
    private func findDevBinary() -> String? {
        // Walk up from the app bundle to find agent_server/target/release/agent_server
        var url = Bundle.main.bundleURL
        for _ in 0..<6 {
            url = url.deletingLastPathComponent()
            let candidate = url.appendingPathComponent("agent_server/target/release/agent_server").path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }
}
