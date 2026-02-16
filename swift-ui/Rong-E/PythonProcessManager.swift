import Foundation
import Combine

/// Manages the Python backend server process lifecycle.
/// Production-ready and portable - no hardcoded paths.
class PythonProcessManager: ObservableObject {
    static let shared = PythonProcessManager()

    // MARK: - Published State

    @Published private(set) var isRunning: Bool = false
    @Published private(set) var lastOutput: String = ""
    @Published private(set) var lastError: String = ""
    @Published private(set) var serverStatus: ServerStatus = .stopped

    enum ServerStatus: Equatable {
        case stopped
        case starting
        case running
        case stopping
        case error(String)

        var description: String {
            switch self {
            case .stopped: return "OFFLINE"
            case .starting: return "STARTING"
            case .running: return "ONLINE"
            case .stopping: return "STOPPING"
            case .error(let msg): return "ERROR: \(msg)"
            }
        }
    }

    // MARK: - Configuration

    enum ExecutionMode {
        /// Run a Python module (e.g., "agent.server") using Python interpreter
        case pythonModule(pythonPath: String?, module: String)

        /// Run a pre-built executable directly
        case executable(path: String)
    }

    struct Configuration {
        /// How to run the server - either Python module or built executable
        var executionMode: ExecutionMode = .executable(path: "")

        /// Working directory for the process. If nil, attempts to find it dynamically.
        var workingDirectory: URL?

        /// Timeout in seconds before force-killing the process on stop
        var terminationTimeout: TimeInterval = 3.0

        /// Server host for health checks
        var serverHost: String = "localhost"

        /// Server port for health checks
        var serverPort: Int = 8000

        static let `default` = Configuration()
    }

    private(set) var configuration: Configuration

    // MARK: - Private Properties

    private var process: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var terminationWorkItem: DispatchWorkItem?

    // MARK: - Initialization

    // private init(configuration: Configuration = .default) {
    //     self.configuration = configuration
    // }

    private init() {
        // ---------------------------------------------------------
        // 🔧 CONFIGURATION - Uses built executable by default
        // ---------------------------------------------------------

        // Try to find the built executable
        let executablePath = Self.findExecutable()

        if let path = executablePath {
            self.configuration = Configuration(
                executionMode: .executable(path: path),
                workingDirectory: URL(fileURLWithPath: path).deletingLastPathComponent()
            )
            print("🔧 PythonProcessManager initialized with EXECUTABLE mode")
            print("   Executable: \(path)")
        } else {
            // Fallback to Python module mode for development
            let myPythonPath = "/opt/miniconda3/envs/py3env/bin/python"
            let myProjectRoot = "/Users/hojinsohn/Echo/agent"

            self.configuration = Configuration(
                executionMode: .pythonModule(pythonPath: myPythonPath, module: "agent.server"),
                workingDirectory: URL(fileURLWithPath: myProjectRoot)
            )
            print("🔧 PythonProcessManager initialized in PYTHON MODULE mode (dev fallback)")
            print("   Python: \(myPythonPath)")
            print("   Root: \(myProjectRoot)")
        }
    }

    /// Searches for the built executable in common locations
    private static func findExecutable() -> String? {
        let fm = FileManager.default

        // Possible executable locations
        var searchPaths: [String] = []

        // 1. Check in app bundle Resources
        if let resourcePath = Bundle.main.resourcePath {
            searchPaths.append("\(resourcePath)/ronge_agent/ronge_agent")
            searchPaths.append("\(resourcePath)/ronge_agent")
        }

        // 2. Check relative to app bundle (for development)
        if let bundlePath = Bundle.main.bundlePath as String? {
            // Go up from .app to find project root
            var url = URL(fileURLWithPath: bundlePath)
            for _ in 0..<5 {
                url = url.deletingLastPathComponent()
                searchPaths.append(url.appendingPathComponent("agent/dist/ronge_agent/ronge_agent").path)
                searchPaths.append(url.appendingPathComponent("agent/dist/ronge_agent").path)
            }
        }

        // Find first existing executable
        for path in searchPaths {
            print("🔍 Checking for executable at: \(path)")
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: path, isDirectory: &isDir) && !isDir.boolValue {
                // Verify it's executable
                if fm.isExecutableFile(atPath: path) {
                    print("🔍 Found executable at: \(path)")
                    return path
                }
            }
        }

        print("🔍 No built executable found")
        return nil
    }

    /// Updates the configuration (useful for switching between executable and Python module modes)
    func updateConfiguration(_ configure: (inout Configuration) -> Void) {
        configure(&configuration)
        print("🔧 PythonProcessManager configuration updated")
    }

    // MARK: - Public Methods

    // Development helper to simulate running state
    func devPythonRun() {
        DispatchQueue.main.async {
            self.isRunning = true
            self.serverStatus = .running
        }
    } //  

    // Starts the Python backend server
    func startServer() {
        // devPythonRun()
        // return
        
        guard !isRunning else {
            print("⚠️ Python server is already running")
            return
        }

        DispatchQueue.main.async {
            self.serverStatus = .starting
        }

        print("🐍 Starting Python backend server...")

        // Resolve working directory
        let workingDir: URL
        do {
            workingDir = try resolveWorkingDirectory()
        } catch {
            let errorMsg = "Failed to resolve working directory: \(error.localizedDescription)"
            print("❌ \(errorMsg)")
            DispatchQueue.main.async {
                self.serverStatus = .error(errorMsg)
            }
            return
        }

        // Create process and pipes
        let newProcess = Process()
        let newOutputPipe = Pipe()
        let newErrorPipe = Pipe()

        process = newProcess
        outputPipe = newOutputPipe
        errorPipe = newErrorPipe

        // Configure executable and arguments based on execution mode
        switch configuration.executionMode {
        case .executable(let path):
            // Run the built executable directly
            newProcess.executableURL = URL(fileURLWithPath: path)
            newProcess.arguments = []
            print("🔧 Running executable: \(path)")

        case .pythonModule(let pythonPath, let module):
            if let customPython = pythonPath {
                // Use custom Python path directly
                newProcess.executableURL = URL(fileURLWithPath: customPython)
                newProcess.arguments = ["-m", module]
            } else {
                // Use /usr/bin/env to find python3 in PATH
                newProcess.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                newProcess.arguments = ["python3", "-m", module]
            }
            print("🔧 Running Python module: \(module)")
        }

        newProcess.currentDirectoryURL = workingDir

        // Set up environment
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONUNBUFFERED"] = "1" // Real-time output
        environment["PYTHONDONTWRITEBYTECODE"] = "1" // Don't create .pyc files

        // Expand PATH to include common Node.js/npm locations (needed for MCP servers)
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        var extraPaths: [String] = []

        // nvm - find all installed node versions
        let nvmVersionsDir = "\(homeDir)/.nvm/versions/node"
        if let nvmContents = try? FileManager.default.contentsOfDirectory(atPath: nvmVersionsDir) {
            for version in nvmContents {
                let binPath = "\(nvmVersionsDir)/\(version)/bin"
                if FileManager.default.fileExists(atPath: binPath) {
                    extraPaths.append(binPath)
                }
            }
        }

        // Other common paths
        let commonPaths = [
            "/opt/homebrew/bin",      // Homebrew Apple Silicon
            "/usr/local/bin",         // Homebrew Intel / standard
            "\(homeDir)/.local/bin",  // pipx, etc.
            "/opt/local/bin"          // MacPorts
        ]
        for path in commonPaths {
            if FileManager.default.fileExists(atPath: path) {
                extraPaths.append(path)
            }
        }

        if !extraPaths.isEmpty {
            let currentPath = environment["PATH"] ?? ""
            environment["PATH"] = extraPaths.joined(separator: ":") + ":" + currentPath
        }

        newProcess.environment = environment

        // Connect pipes
        newProcess.standardOutput = newOutputPipe
        newProcess.standardError = newErrorPipe

        // Handle stdout (non-blocking)
        newOutputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else { return }

            DispatchQueue.main.async {
                self?.lastOutput = output
            }
            print("🐍 [stdout]: \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
        }

        // Handle stderr (non-blocking)
        newErrorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let error = String(data: data, encoding: .utf8) else { return }

            DispatchQueue.main.async {
                self?.lastError = error
            }
            // Note: Python often outputs normal logs to stderr
            print("🐍 [stderr]: \(error.trimmingCharacters(in: .whitespacesAndNewlines))")
        }

        // Handle process termination
        newProcess.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                self?.cleanupAfterTermination(exitCode: process.terminationStatus)
            }
        }

        // Start the process
        do {
            try newProcess.run()
            DispatchQueue.main.async {
                self.isRunning = true
                self.serverStatus = .running
            }
            print("✅ Rong-E agent server started")
            print("   PID: \(newProcess.processIdentifier)")
            print("   Working directory: \(workingDir.path)")
            switch configuration.executionMode {
            case .executable(let path):
                print("   Executable: \(path)")
            case .pythonModule(_, let module):
                print("   Module: \(module)")
            }
        } catch {
            let errorMsg = "Failed to start: \(error.localizedDescription)"
            print("❌ \(errorMsg)")
            DispatchQueue.main.async {
                self.isRunning = false
                self.serverStatus = .error(errorMsg)
            }
            cleanupPipes()
        }
    }

    /// Stops the Python backend server gracefully, force-kills if necessary
    func stopServer() {
        guard let process = process, isRunning else {
            print("⚠️ Python server is not running")
            return
        }

        print("🛑 Stopping Python backend server...")

        DispatchQueue.main.async {
            self.serverStatus = .stopping
        }

        // Cancel any existing termination work item
        terminationWorkItem?.cancel()

        // Send SIGTERM for graceful shutdown
        process.terminate()

        // Schedule force kill if process doesn't terminate in time
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self,
                  let proc = self.process,
                  proc.isRunning else {
                return
            }

            print("⚠️ Process didn't terminate gracefully, sending SIGKILL...")
            // SIGKILL (9) - Force kill, cannot be caught or ignored
            kill(proc.processIdentifier, SIGKILL)
        }

        terminationWorkItem = workItem
        DispatchQueue.global().asyncAfter(
            deadline: .now() + configuration.terminationTimeout,
            execute: workItem
        )
    }

    /// Restarts the Python backend server
    func restartServer() {
        print("🔄 Restarting Python backend server...")
        stopServer()

        // Wait for process to fully stop before restarting
        DispatchQueue.main.asyncAfter(deadline: .now() + configuration.terminationTimeout + 0.5) { [weak self] in
            self?.startServer()
        }
    }

    /// Checks if the server is responding to health checks
    func checkServerHealth(completion: @escaping (Bool) -> Void) {
        let urlString = "http://\(configuration.serverHost):\(configuration.serverPort)/health"
        guard let url = URL(string: urlString) else {
            completion(false)
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        request.httpMethod = "GET"

        URLSession.shared.dataTask(with: request) { _, response, error in
            if let httpResponse = response as? HTTPURLResponse {
                completion(httpResponse.statusCode == 200)
            } else {
                completion(false)
            }
        }.resume()
    }

    /// Async version of health check
    @available(macOS 12.0, *)
    func checkServerHealth() async -> Bool {
        await withCheckedContinuation { continuation in
            checkServerHealth { isHealthy in
                continuation.resume(returning: isHealthy)
            }
        }
    }

    // MARK: - Private Methods

    /// Resolves the working directory for the process
    private func resolveWorkingDirectory() throws -> URL {
        // 1. If explicitly configured, use that
        if let configuredDir = configuration.workingDirectory {
            guard FileManager.default.fileExists(atPath: configuredDir.path) else {
                throw PythonProcessError.workingDirectoryNotFound(configuredDir.path)
            }
            return configuredDir
        }

        // 2. For executable mode, use the executable's directory
        if case .executable(let path) = configuration.executionMode {
            let execURL = URL(fileURLWithPath: path)
            let execDir = execURL.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: execDir.path) {
                return execDir
            }
        }

        // 3. Try to find "agent" folder in app bundle resources (for Python module mode)
        if let bundleResourceURL = Bundle.main.resourceURL {
            let agentInBundle = bundleResourceURL.appendingPathComponent("agent")
            if FileManager.default.fileExists(atPath: agentInBundle.path) {
                return bundleResourceURL
            }
        }

        // 4. Try relative to the app bundle (for development)
        if let bundleURL = Bundle.main.bundleURL.deletingLastPathComponent() as URL? {
            var searchURL = bundleURL

            for _ in 0..<5 {
                let agentPath = searchURL.appendingPathComponent("agent")
                if FileManager.default.fileExists(atPath: agentPath.path) {
                    return searchURL
                }
                searchURL = searchURL.deletingLastPathComponent()
            }
        }

        // 5. Try current working directory
        let currentDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let agentInCurrent = currentDir.appendingPathComponent("agent")
        if FileManager.default.fileExists(atPath: agentInCurrent.path) {
            return currentDir
        }

        // 6. Check common development paths
        if let homeDir = ProcessInfo.processInfo.environment["HOME"] {
            let commonPaths = [
                "\(homeDir)/Echo/agent",
                "\(homeDir)/Echo",
                "\(homeDir)/Projects/Echo",
                "\(homeDir)/Developer/Echo"
            ]

            for path in commonPaths {
                let url = URL(fileURLWithPath: path)
                if FileManager.default.fileExists(atPath: url.path) {
                    return url
                }
            }
        }

        throw PythonProcessError.agentModuleNotFound
    }

    private func cleanupAfterTermination(exitCode: Int32) {
        isRunning = false
        terminationWorkItem?.cancel()
        terminationWorkItem = nil

        cleanupPipes()

        if exitCode == 0 {
            serverStatus = .stopped
            print("🐍 Python server stopped normally")
        } else if exitCode == 9 {
            serverStatus = .stopped
            print("🐍 Python server was force killed (SIGKILL)")
        } else if exitCode == 15 {
            serverStatus = .stopped
            print("🐍 Python server terminated (SIGTERM)")
        } else {
            serverStatus = .error("Exit code: \(exitCode)")
            print("🐍 Python server terminated with exit code: \(exitCode)")
        }

        process = nil
    }

    private func cleanupPipes() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        outputPipe = nil
        errorPipe = nil
    }
}

// MARK: - Errors

enum PythonProcessError: LocalizedError {
    case workingDirectoryNotFound(String)
    case agentModuleNotFound
    case pythonNotFound

    var errorDescription: String? {
        switch self {
        case .workingDirectoryNotFound(let path):
            return "Working directory not found: \(path)"
        case .agentModuleNotFound:
            return "Could not find 'agent' module. Ensure it exists in the app bundle or project directory."
        case .pythonNotFound:
            return "Python 3 executable not found. Please install Python 3."
        }
    }
}
