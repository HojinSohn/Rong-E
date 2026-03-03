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

    enum ServerStatus: Equatable {
        case stopped
        case starting
        case running
        case error(String)
        case stopping
    }

    @Published private(set) var status: ServerStatus = .stopped

    var isRunning: Bool { status == .running }

    private var process: Process?
    private var outputPipe: Pipe?

    // Default URL for your websocket
    let socketURL = URL(string: "ws://127.0.0.1:3000/ws")!

    private init() {}

    deinit {
        stopServer()
    }

    func startServer() {
        guard status != .running, status != .starting else {
            print("⚠️ Rust server is already running or starting")
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
                status = .error("Binary not found in bundle")
                return
            }
        } else {
            print("❌ Could not find 'agent_server' binary.")
            status = .error("Binary not found")
            return
        }

        print("🦀 Starting Rust server from: \(serverPath)")
        status = .starting

        // 2. Configure the process
        let newProcess = Process()
        let newPipe = Pipe()

        newProcess.executableURL = URL(fileURLWithPath: serverPath)
        newProcess.arguments = []
        newProcess.standardOutput = newPipe
        newProcess.standardError = newPipe

        // Ensure OLLAMA_API_BASE_URL is set so rig's ollama client doesn't panic
        var env = ProcessInfo.processInfo.environment
        if env["OLLAMA_API_BASE_URL"] == nil {
            env["OLLAMA_API_BASE_URL"] = "http://localhost:11434"
        }
        newProcess.environment = env

        // 3. Pipe stdout/stderr to Xcode console
        newPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }
            print("[Rust]: \(line.trimmingCharacters(in: .whitespacesAndNewlines))")
        }

        // 4. Handle termination
        newProcess.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                let code = proc.terminationStatus
                if code == 0 || code == 15 /* SIGTERM */ {
                    self?.status = .stopped
                } else {
                    self?.status = .error("Exited with code \(code)")
                }
                print("🦀 Rust server exited (code: \(code))")
            }
        }

        // 5. Run
        do {
            try newProcess.run()
            self.process = newProcess
            self.outputPipe = newPipe
            self.status = .running
            print("✅ Rust server started (PID: \(newProcess.processIdentifier))")
        } catch {
            self.status = .error(error.localizedDescription)
            print("❌ Failed to start Rust server: \(error)")
        }
    }

    func stopServer() {
        guard let process = process, isRunning || status == .starting else { return }
        print("🛑 Stopping Rust server...")
        process.terminate()
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        outputPipe = nil
        self.process = nil
        status = .stopped
    }

    /// Find the compiled binary during development (not in bundle)
    private func findDevBinary() -> String? {
        // Strategy 1: Walk up from the app bundle (works when run from workspace)
        var url = Bundle.main.bundleURL
        for _ in 0..<8 {
            url = url.deletingLastPathComponent()
            let candidate = url.appendingPathComponent("agent_server/target/release/agent_server").path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        // Strategy 2: Look relative to the Xcode project source root
        // The swift-ui dir sits next to agent_server in the workspace
        if let srcRoot = Bundle.main.infoDictionary?["SOURCE_ROOT"] as? String {
            let wsRoot = URL(fileURLWithPath: srcRoot).deletingLastPathComponent()
            let candidate = wsRoot.appendingPathComponent("agent_server/target/release/agent_server").path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        // Strategy 3: Use __FILE__ equivalent — the swift-ui package is a sibling of agent_server
        let thisFile = #filePath
        var dir = URL(fileURLWithPath: thisFile)
        for _ in 0..<6 {
            dir = dir.deletingLastPathComponent()
            let candidate = dir.appendingPathComponent("agent_server/target/release/agent_server").path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        return nil
    }
}
