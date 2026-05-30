# MCP Integration — Composio + Built-in Servers — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Composio (HTTP/SSE transport) and four built-in local MCP servers (filesystem, fetch, shell, memory) to Rong-E's existing MCP pipeline, with Swift UI toggles and a Composio settings card.

**Architecture:** Extend `logic.rs` with an HTTP/SSE MCP transport branch and two new message handlers (`set_builtin_servers`, `set_composio`). Extend `state.rs` with a separate `builtin_servers` map so built-ins survive custom server resyncs. On the Swift side, add `KeychainHelper`, update models, add three WebSocket send methods, and split `MCPConfigView` into three sections.

**Tech Stack:** Rust/Axum/rmcp (SSE client transport), Swift/SwiftUI, Security framework (Keychain), UserDefaults

---

## File Map

| File | Change |
|---|---|
| `agent_server/Cargo.toml` | Add `transport-sse-client` feature to rmcp |
| `agent_server/src/state.rs` | Add `builtin_servers`, `composio_api_key`; update `all_mcp_tools()` |
| `agent_server/src/logic.rs` | HTTP branch in `mcp_config`; `set_composio`; `set_builtin_servers`; collision prefix |
| `swift-ui/Rong-E/Services/KeychainHelper.swift` | **New** — Keychain read/write/delete |
| `swift-ui/Rong-E/Models/MCPConfig.swift` | Add `transport`/`url`/`apiKey` to `MCPServerConfig`; add `BuiltinServerConfig` + `BuiltinServerManager` |
| `swift-ui/Rong-E/Services/RongESocketClient.swift` | Add `sendBuiltinServersConfig`, `sendComposioKey`, `disconnectComposio`; handle `builtin_warning` |
| `swift-ui/Rong-E/App/AppContext.swift` | Restore built-in + Composio config on startup |
| `swift-ui/Rong-E/Views/Settings/MCPConfigView.swift` | Three-section layout (Built-in / Composio / Custom) |

---

## Task 1: Enable SSE Client Transport in Cargo.toml

**Files:**
- Modify: `agent_server/Cargo.toml`

- [ ] **Step 1: Add the SSE client transport feature to rmcp**

Open `agent_server/Cargo.toml`. Change the rmcp line from:
```toml
rmcp = { version = "0.13", features = ["client", "server", "transport-child-process"] }
```
to:
```toml
rmcp = { version = "0.13", features = ["client", "server", "transport-child-process", "transport-sse-client"] }
```

- [ ] **Step 2: Verify the project still compiles**

```bash
cd agent_server && cargo build 2>&1 | tail -5
```
Expected: `Finished` with no errors. If `transport-sse-client` is not a valid feature name for your rmcp version, run `cargo doc --open` and look under `rmcp::transport` for the correct SSE client type and its feature flag, then update the feature name accordingly.

- [ ] **Step 3: Commit**

```bash
git add agent_server/Cargo.toml agent_server/Cargo.lock
git commit -m "chore: enable rmcp SSE client transport feature"
```

---

## Task 2: Extend AppState in state.rs

**Files:**
- Modify: `agent_server/src/state.rs`

- [ ] **Step 1: Add two fields to `AppState` and update `all_mcp_tools()`**

Replace the entire contents of `agent_server/src/state.rs` with:

```rust
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::Mutex;

/// A live MCP server connection.
pub struct McpConnection {
    pub tools: Vec<rmcp::model::Tool>,
    pub peer: rmcp::service::ServerSink,
    /// Must stay alive to keep the peer valid.
    pub _service: rmcp::service::RunningService<rmcp::RoleClient, ()>,
}

pub struct AppState {
    pub current_model: String,
    pub current_provider: String,
    pub api_keys: HashMap<String, String>,
    /// JWT issued by the backend/ Google proxy server (restored on startup).
    pub google_session_token: Option<String>,
    /// URL of the backend/ proxy server (set by the Swift app on startup).
    pub backend_url: String,
    /// User-configured external MCP servers.
    pub mcp_connections: HashMap<String, McpConnection>,
    /// Built-in local MCP servers (filesystem, fetch, shell, memory).
    /// Kept separate so a custom server resync never shuts these down.
    pub builtin_servers: HashMap<String, McpConnection>,
    /// Composio API key — stored here after `set_composio` so it can be
    /// re-used on reconnect without Swift sending it again.
    pub composio_api_key: Option<String>,
}

pub type SharedState = Arc<Mutex<AppState>>;

impl AppState {
    pub fn new() -> Self {
        Self {
            current_model: "gemini-2.5-flash".to_string(),
            current_provider: "gemini".to_string(),
            api_keys: HashMap::new(),
            google_session_token: None,
            backend_url: "https://api.rong-e.app".to_string(),
            mcp_connections: HashMap::new(),
            builtin_servers: HashMap::new(),
            composio_api_key: None,
        }
    }

    /// Collect all MCP tools + peers for agent building.
    /// Includes both user-configured and built-in servers.
    pub fn all_mcp_tools(&self) -> Vec<(Vec<rmcp::model::Tool>, rmcp::service::ServerSink)> {
        self.mcp_connections
            .values()
            .chain(self.builtin_servers.values())
            .map(|c| (c.tools.clone(), c.peer.clone()))
            .collect()
    }
}
```

- [ ] **Step 2: Verify the project compiles**

```bash
cd agent_server && cargo build 2>&1 | tail -5
```
Expected: `Finished` with no errors.

- [ ] **Step 3: Commit**

```bash
git add agent_server/src/state.rs
git commit -m "feat(rust): add builtin_servers and composio_api_key to AppState"
```

---

## Task 3: HTTP Transport Branch in mcp_config Handler

**Files:**
- Modify: `agent_server/src/logic.rs`

This task adds a shared `connect_http_mcp_server` helper and extends the existing `mcp_config` handler to use it when `transport == "http"`.

- [ ] **Step 1: Add the `connect_http_mcp_server` helper near the top of `logic.rs`**

Add this function after the existing `use` imports and before `process_message`. It encapsulates the HTTP/SSE MCP connection so both `mcp_config` and `set_composio` can reuse it.

```rust
use rmcp::transport::SseClientTransport;
use reqwest::header::{HeaderMap, HeaderValue, AUTHORIZATION};
```

Add this function (place it before `process_message`):

```rust
/// Connect to a remote MCP server via HTTP/SSE transport.
/// Returns an `McpConnection` on success or an error string on failure.
async fn connect_http_mcp_server(
    url: &str,
    api_key: &str,
    tx: crate::tools::ToolEventSender,
) -> Result<crate::state::McpConnection, String> {
    // Build a reqwest client with the Authorization header pre-set.
    let mut headers = HeaderMap::new();
    let auth_value = HeaderValue::from_str(&format!("Bearer {}", api_key))
        .map_err(|e| format!("Invalid API key characters: {e}"))?;
    headers.insert(AUTHORIZATION, auth_value);

    let http_client = reqwest::Client::builder()
        .default_headers(headers)
        .build()
        .map_err(|e| format!("Failed to build HTTP client: {e}"))?;

    let transport = SseClientTransport::start_with_client(url, http_client)
        .await
        .map_err(|e| format!("SSE transport error: {e}"))?;

    let service = ().serve(transport)
        .await
        .map_err(|e| format!("MCP handshake failed: {:?}", e))?;

    let tool_list = service
        .list_tools(Default::default())
        .await
        .map_err(|e| format!("list_tools failed: {:?}", e))?;

    let (sanitized_tools, proxy_peer, _guard) =
        crate::mcp_proxy::create_notifying_proxy(tool_list.tools, service.peer().clone(), tx)
            .await
            .map_err(|e| format!("Proxy setup failed: {e}"))?;

    Ok(crate::state::McpConnection {
        tools: sanitized_tools,
        peer: proxy_peer,
        _service: service,
    })
}
```

> **Note:** If the rmcp `SseClientTransport::start_with_client` signature differs in your version, run `cargo doc --open` in `agent_server/` and look up `SseClientTransport`. Adjust the call to match the actual API — the pattern (build an HTTP client with auth headers, pass it to the transport constructor) remains the same.

- [ ] **Step 2: Extend the `mcp_config` handler to branch on `transport`**

Inside the `"mcp_config"` match arm in `handle_config`, find the inner loop that iterates over `servers`. The existing code looks like:

```rust
let command = match server_config["command"].as_str() {
    Some(c) => c,
    None => {
        statuses.push(
            json!({"name": name, "status": "error", "error": "Missing command"}),
        );
        continue;
    }
};
```

Replace the entire per-server block (from `let command = match ...` through `state.lock().await.mcp_connections.insert(name.clone(), conn);`) with:

```rust
let transport_type = server_config["transport"].as_str().unwrap_or("stdio");

if transport_type == "http" {
    let url = match server_config["url"].as_str() {
        Some(u) if !u.is_empty() => u.to_string(),
        _ => {
            statuses.push(json!({"name": name, "status": "error", "error": "Missing url for HTTP transport"}));
            continue;
        }
    };
    let api_key = server_config["api_key"].as_str().unwrap_or("").to_string();

    println!("🌐 Connecting to HTTP MCP server '{}': {}", name, url);

    // Retrieve or create a tool event sender for notifications.
    // We use a dummy channel here — the agent loop creates its own per-call.
    let (dummy_tx, _) = tokio::sync::mpsc::channel(1);

    match connect_http_mcp_server(&url, &api_key, dummy_tx).await {
        Ok(conn) => {
            println!("✅ HTTP MCP '{}' connected with {} tools", name, conn.tools.len());
            statuses.push(json!({"name": name, "status": "connected", "error": null}));
            state.lock().await.mcp_connections.insert(name.clone(), conn);
        }
        Err(e) => {
            println!("❌ HTTP MCP '{}' failed: {}", name, e);
            statuses.push(json!({"name": name, "status": "error", "error": e}));
        }
    }
    continue;
}

// --- stdio (existing path, unchanged below) ---
let command = match server_config["command"].as_str() {
    Some(c) => c,
    None => {
        statuses.push(
            json!({"name": name, "status": "error", "error": "Missing command"}),
        );
        continue;
    }
};

let args: Vec<String> = server_config["args"]
    .as_array()
    .map(|a| {
        a.iter()
            .filter_map(|v| v.as_str().map(|s| s.to_string()))
            .collect()
    })
    .unwrap_or_default();

println!("🔗 Starting MCP server '{}': {} {:?}", name, command, args);

let expanded_path = build_expanded_path();
let resolved_command = resolve_command(command, &expanded_path);
println!("   Resolved command: {}", resolved_command);

let mut cmd = tokio::process::Command::new(&resolved_command);
cmd.args(&args);
cmd.env("PATH", &expanded_path);

if let Some(env) = server_config["env"].as_object() {
    for (k, v) in env {
        if let Some(val) = v.as_str() {
            cmd.env(k, val);
        }
    }
}

let transport = match TokioChildProcess::new(cmd) {
    Ok(t) => t,
    Err(e) => {
        println!("❌ Failed to spawn '{}': {}", name, e);
        statuses.push(
            json!({"name": name, "status": "error", "error": e.to_string()}),
        );
        continue;
    }
};

let service = match ().serve(transport).await {
    Ok(s) => s,
    Err(e) => {
        println!("❌ Failed to connect to '{}': {:?}", name, e);
        statuses.push(
            json!({"name": name, "status": "error", "error": format!("{:?}", e)}),
        );
        continue;
    }
};

let tool_list = match service.list_tools(Default::default()).await {
    Ok(t) => t,
    Err(e) => {
        println!("❌ Failed to list tools from '{}': {:?}", name, e);
        statuses.push(
            json!({"name": name, "status": "error", "error": format!("{:?}", e)}),
        );
        continue;
    }
};

println!(
    "✅ MCP '{}' connected with {} tools",
    name,
    tool_list.tools.len()
);

let conn = crate::state::McpConnection {
    tools: tool_list.tools,
    peer: service.peer().clone(),
    _service: service,
};

statuses.push(json!({"name": name, "status": "connected", "error": null}));
state.lock().await.mcp_connections.insert(name.clone(), conn);
```

- [ ] **Step 3: Also add name-collision prefix for reserved names in the custom server loop**

At the start of the for-loop over `servers` (right after `for (name, server_config) in servers {`), add:

```rust
// Prevent user-configured servers from shadowing built-in names.
let reserved = ["filesystem", "fetch", "shell", "memory"];
let name = if reserved.contains(&name.as_str()) {
    format!("custom:{}", name)
} else {
    name.clone()
};
let name = name.as_str();
```

- [ ] **Step 4: Verify compile**

```bash
cd agent_server && cargo build 2>&1 | tail -10
```
Expected: `Finished` with no errors.

- [ ] **Step 5: Commit**

```bash
git add agent_server/src/logic.rs
git commit -m "feat(rust): add HTTP/SSE transport branch to mcp_config handler"
```

---

## Task 4: Add set_composio Handler

**Files:**
- Modify: `agent_server/src/logic.rs`

- [ ] **Step 1: Add the `set_composio` match arm inside `handle_config`**

Add this arm to the `match data_type` block, after the `"mcp_config"` arm:

```rust
"set_composio" => {
    let api_key = data["api_key"].as_str().unwrap_or("").trim().to_string();

    if api_key.is_empty() {
        // Disconnect: remove Composio from connections and clear stored key.
        let mut s = state.lock().await;
        s.composio_api_key = None;
        if let Some(conn) = s.mcp_connections.remove("composio") {
            println!("🛑 Disconnecting Composio");
            let _ = conn._service.cancel().await;
        }
        drop(s);
        let _ = sender
            .send(Message::Text(
                json!({"type": "mcp_server_status", "content": {"servers": [
                    {"name": "composio", "status": "disconnected", "error": null}
                ]}})
                .to_string(),
            ))
            .await;
        return;
    }

    println!("🌐 Connecting to Composio...");
    state.lock().await.composio_api_key = Some(api_key.clone());

    // Use a dummy sender — the agent loop creates its own per-call.
    let (dummy_tx, _) = tokio::sync::mpsc::channel(1);
    let composio_url = "https://mcp.composio.dev";

    match connect_http_mcp_server(composio_url, &api_key, dummy_tx).await {
        Ok(conn) => {
            let tool_count = conn.tools.len();
            println!("✅ Composio connected with {} tools", tool_count);
            state.lock().await.mcp_connections.insert("composio".to_string(), conn);
            let _ = sender
                .send(Message::Text(
                    json!({"type": "mcp_server_status", "content": {"servers": [
                        {"name": "composio", "status": "connected", "error": null, "tools_count": tool_count}
                    ]}})
                    .to_string(),
                ))
                .await;
        }
        Err(e) => {
            println!("❌ Composio connection failed: {}", e);
            state.lock().await.composio_api_key = None;
            let _ = sender
                .send(Message::Text(
                    json!({"type": "mcp_server_status", "content": {"servers": [
                        {"name": "composio", "status": "error", "error": e}
                    ]}})
                    .to_string(),
                ))
                .await;
        }
    }
}
```

> **Composio URL note:** The endpoint `https://mcp.composio.dev` is Composio's standard MCP-over-SSE URL as of early 2026. Verify it hasn't changed at `https://docs.composio.dev/mcp` before shipping.

- [ ] **Step 2: Verify compile**

```bash
cd agent_server && cargo build 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add agent_server/src/logic.rs
git commit -m "feat(rust): add set_composio handler with HTTP/SSE MCP connection"
```

---

## Task 5: Add set_builtin_servers Handler

**Files:**
- Modify: `agent_server/src/logic.rs`

- [ ] **Step 1: Define the built-in server registry struct (add near top of file, after imports)**

```rust
struct BuiltinServerDef {
    name: &'static str,
    command: &'static str,
    /// Arguments before any path expansion. Use `{PATHS}` as a placeholder
    /// for filesystem_paths (only relevant for the filesystem server).
    args_template: &'static [&'static str],
}

const BUILTIN_SERVERS: &[BuiltinServerDef] = &[
    BuiltinServerDef {
        name: "filesystem",
        command: "npx",
        args_template: &["-y", "@modelcontextprotocol/server-filesystem"],
        // paths are appended at runtime
    },
    BuiltinServerDef {
        name: "fetch",
        command: "npx",
        args_template: &["-y", "@modelcontextprotocol/server-fetch"],
    },
    BuiltinServerDef {
        name: "shell",
        command: "npx",
        args_template: &["-y", "@modelcontextprotocol/server-shell"],
    },
    BuiltinServerDef {
        name: "memory",
        command: "npx",
        args_template: &["-y", "@modelcontextprotocol/server-memory"],
    },
];
```

- [ ] **Step 2: Add the `set_builtin_servers` match arm inside `handle_config`**

Add this arm after the `"set_composio"` arm:

```rust
"set_builtin_servers" => {
    let enabled: Vec<String> = data["enabled"]
        .as_array()
        .map(|a| a.iter().filter_map(|v| v.as_str().map(String::from)).collect())
        .unwrap_or_default();

    // filesystem_paths defaults to $HOME if not provided.
    let home = std::env::var("HOME").unwrap_or_else(|_| "/".to_string());
    let filesystem_paths: Vec<String> = data["filesystem_paths"]
        .as_array()
        .map(|a| a.iter().filter_map(|v| v.as_str().map(String::from)).collect())
        .unwrap_or_else(|| vec![home]);

    println!("🔧 set_builtin_servers: enabled={:?}", enabled);

    // Shut down built-in servers that are no longer in the enabled list.
    {
        let mut s = state.lock().await;
        let to_stop: Vec<String> = s
            .builtin_servers
            .keys()
            .filter(|k| !enabled.contains(*k))
            .cloned()
            .collect();
        for name in to_stop {
            if let Some(conn) = s.builtin_servers.remove(&name) {
                println!("🛑 Stopping built-in MCP server: {}", name);
                let _ = conn._service.cancel().await;
            }
        }
    }

    let expanded_path = build_expanded_path();
    let mut statuses: Vec<serde_json::Value> = Vec::new();

    for server_name in &enabled {
        // Skip if already running.
        if state.lock().await.builtin_servers.contains_key(server_name.as_str()) {
            statuses.push(json!({"name": server_name, "status": "connected", "error": null}));
            continue;
        }

        let def = match BUILTIN_SERVERS.iter().find(|d| d.name == server_name.as_str()) {
            Some(d) => d,
            None => {
                statuses.push(json!({"name": server_name, "status": "error", "error": "Unknown built-in server"}));
                continue;
            }
        };

        let resolved_command = resolve_command(def.command, &expanded_path);
        if resolved_command == def.command && !std::path::Path::new(def.command).is_absolute() {
            // Command not found on PATH — likely Node.js not installed.
            statuses.push(json!({"name": server_name, "status": "error", "error": "Node.js not installed"}));
            continue;
        }

        let mut args: Vec<String> = def.args_template.iter().map(|s| s.to_string()).collect();
        if def.name == "filesystem" {
            args.extend(filesystem_paths.iter().cloned());
        }

        println!("🔗 Starting built-in MCP server '{}': {} {:?}", server_name, resolved_command, args);

        let mut cmd = tokio::process::Command::new(&resolved_command);
        cmd.args(&args);
        cmd.env("PATH", &expanded_path);

        let transport = match TokioChildProcess::new(cmd) {
            Ok(t) => t,
            Err(e) => {
                println!("❌ Failed to spawn built-in '{}': {}", server_name, e);
                statuses.push(json!({"name": server_name, "status": "error", "error": e.to_string()}));
                continue;
            }
        };

        let service = match ().serve(transport).await {
            Ok(s) => s,
            Err(e) => {
                println!("❌ Failed to connect to built-in '{}': {:?}", server_name, e);
                statuses.push(json!({"name": server_name, "status": "error", "error": format!("{:?}", e)}));
                continue;
            }
        };

        let tool_list = match service.list_tools(Default::default()).await {
            Ok(t) => t,
            Err(e) => {
                println!("❌ Failed to list tools from built-in '{}': {:?}", server_name, e);
                statuses.push(json!({"name": server_name, "status": "error", "error": format!("{:?}", e)}));
                continue;
            }
        };

        println!("✅ Built-in MCP '{}' connected with {} tools", server_name, tool_list.tools.len());

        let conn = crate::state::McpConnection {
            tools: tool_list.tools,
            peer: service.peer().clone(),
            _service: service,
        };

        statuses.push(json!({"name": server_name, "status": "connected", "error": null}));
        state.lock().await.builtin_servers.insert(server_name.clone(), conn);
    }

    let _ = sender
        .send(Message::Text(
            json!({"type": "mcp_server_status", "content": {"servers": statuses}}).to_string(),
        ))
        .await;
}
```

- [ ] **Step 3: Verify compile**

```bash
cd agent_server && cargo build 2>&1 | tail -5
```
Expected: `Finished` with no errors.

- [ ] **Step 4: Smoke-test built-in server startup manually**

```bash
cd agent_server && cargo run --release
```

In a separate terminal, send a WebSocket message:
```bash
wscat -c ws://127.0.0.1:3000/ws -x '{"data_type":"set_builtin_servers","enabled":["fetch"],"filesystem_paths":[]}'
```
Expected in server output: `🔗 Starting built-in MCP server 'fetch'` followed by `✅ Built-in MCP 'fetch' connected`.
If `wscat` isn't available: `npm install -g wscat`.

- [ ] **Step 5: Commit**

```bash
git add agent_server/src/logic.rs
git commit -m "feat(rust): add set_builtin_servers handler with built-in server registry"
```

---

## Task 6: Create KeychainHelper.swift

**Files:**
- Create: `swift-ui/Rong-E/Services/KeychainHelper.swift`

The Composio API key is a credential and must be stored in Keychain, not UserDefaults.

- [ ] **Step 1: Create the file**

```swift
// swift-ui/Rong-E/Services/KeychainHelper.swift
import Foundation
import Security

/// Minimal Keychain wrapper for storing a single string per key.
enum KeychainHelper {

    private static let service = "dev.ronge.app"

    /// Store or update a string value for `key`. Returns `true` on success.
    @discardableResult
    static func save(_ value: String, forKey key: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
        ]

        // Try update first.
        let updateAttributes: [CFString: Any] = [kSecValueData: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)

        if updateStatus == errSecItemNotFound {
            // Item doesn't exist yet — add it.
            var addQuery = query
            addQuery[kSecValueData] = data
            return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
        }

        return updateStatus == errSecSuccess
    }

    /// Read the stored string for `key`, or `nil` if not found.
    static func load(forKey key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      service,
            kSecAttrAccount:      key,
            kSecReturnData:       true,
            kSecMatchLimit:       kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else { return nil }
        return string
    }

    /// Delete the stored item for `key`. Returns `true` on success or if item didn't exist.
    @discardableResult
    static func delete(forKey key: String) -> Bool {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
```

- [ ] **Step 2: Add the file to the Xcode project**

Open Xcode → right-click `Services/` group → Add Files → select `KeychainHelper.swift`. Make sure it's added to the `Rong-E` target.

- [ ] **Step 3: Build in Xcode (Cmd+B)**

Expected: Build succeeds with no errors.

- [ ] **Step 4: Commit**

```bash
git add swift-ui/Rong-E/Services/KeychainHelper.swift swift-ui/Rong-E.xcodeproj/project.pbxproj
git commit -m "feat(swift): add KeychainHelper for Composio API key storage"
```

---

## Task 7: Update MCPConfig.swift — Models

**Files:**
- Modify: `swift-ui/Rong-E/Models/MCPConfig.swift`

- [ ] **Step 1: Add transport/url/apiKey fields to `MCPServerConfig`**

Find `MCPServerConfig` and add three optional fields. The full struct becomes:

```swift
struct MCPServerConfig: Codable, Identifiable, Equatable {
    var id: String { name }
    let name: String
    let command: String
    let args: [String]
    let env: [String: String]?
    let transport: String?   // "stdio" (default/nil) or "http"
    let url: String?         // only for transport == "http"
    let apiKey: String?      // only for transport == "http"

    init(name: String, command: String, args: [String], env: [String: String]? = nil,
         transport: String? = nil, url: String? = nil, apiKey: String? = nil) {
        self.name = name
        self.command = command
        self.args = args
        self.env = env
        self.transport = transport
        self.url = url
        self.apiKey = apiKey
    }

    enum CodingKeys: String, CodingKey {
        case command, args, env, transport, url, apiKey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = ""
        self.command = try container.decode(String.self, forKey: .command)
        self.args = try container.decodeIfPresent([String].self, forKey: .args) ?? []
        self.env = try container.decodeIfPresent([String: String].self, forKey: .env)
        self.transport = try container.decodeIfPresent(String.self, forKey: .transport)
        self.url = try container.decodeIfPresent(String.self, forKey: .url)
        self.apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(command, forKey: .command)
        try container.encode(args, forKey: .args)
        if let env = env { try container.encode(env, forKey: .env) }
        if let transport = transport { try container.encode(transport, forKey: .transport) }
        if let url = url { try container.encode(url, forKey: .url) }
        if let apiKey = apiKey { try container.encode(apiKey, forKey: .apiKey) }
    }
}
```

- [ ] **Step 2: Add `BuiltinServerConfig` model and `BuiltinServerManager` class**

Append to the end of `MCPConfig.swift` (before the `#Preview` if present):

```swift
// MARK: - Built-in Server Configuration

struct BuiltinServerConfig: Codable {
    var enabledServers: Set<String>
    var filesystemPaths: [String]

    init(enabledServers: Set<String> = [], filesystemPaths: [String] = [NSHomeDirectory()]) {
        self.enabledServers = enabledServers
        self.filesystemPaths = filesystemPaths
    }
}

class BuiltinServerManager: ObservableObject {
    static let shared = BuiltinServerManager()
    private let configKey = "builtin_server_config"

    @Published var config: BuiltinServerConfig = BuiltinServerConfig()

    private init() {
        load()
    }

    func isEnabled(_ name: String) -> Bool {
        config.enabledServers.contains(name)
    }

    func setEnabled(_ name: String, _ enabled: Bool) {
        if enabled {
            config.enabledServers.insert(name)
        } else {
            config.enabledServers.remove(name)
        }
        save()
        sync()
    }

    func setFilesystemPaths(_ paths: [String]) {
        config.filesystemPaths = paths
        save()
        if config.enabledServers.contains("filesystem") {
            sync()
        }
    }

    /// Send the current config to the Rust backend.
    func sync() {
        SocketClient.shared.sendBuiltinServersConfig(config)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: configKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: configKey),
              let decoded = try? JSONDecoder().decode(BuiltinServerConfig.self, from: data) else { return }
        self.config = decoded
    }
}
```

- [ ] **Step 3: Build in Xcode (Cmd+B)**

Expected: No errors.

- [ ] **Step 4: Commit**

```bash
git add swift-ui/Rong-E/Models/MCPConfig.swift
git commit -m "feat(swift): add transport fields to MCPServerConfig and BuiltinServerManager"
```

---

## Task 8: Add WebSocket Send Methods and Message Handling

**Files:**
- Modify: `swift-ui/Rong-E/Services/RongESocketClient.swift`

- [ ] **Step 1: Add three new send methods at the bottom of `SocketClient`**

Add before the closing `}` of the `SocketClient` class (after `sendStartOpenRouterOAuth`):

```swift
// MARK: - Built-in MCP Servers

func sendBuiltinServersConfig(_ config: BuiltinServerConfig) {
    let enabledArray = Array(config.enabledServers)
    let json: [String: Any] = [
        "data_type": "set_builtin_servers",
        "enabled": enabledArray,
        "filesystem_paths": config.filesystemPaths
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: json),
          let text = String(data: data, encoding: .utf8) else { return }
    print("📤 Sending built-in servers config: enabled=\(enabledArray)")
    webSocketTask?.send(.string(text)) { error in
        if let error = error { print("❌ Built-in servers send error: \(error)") }
    }
}

// MARK: - Composio

func sendComposioKey(_ apiKey: String) {
    let json: [String: Any] = ["data_type": "set_composio", "api_key": apiKey]
    guard let data = try? JSONSerialization.data(withJSONObject: json),
          let text = String(data: data, encoding: .utf8) else { return }
    print("📤 Sending Composio API key")
    webSocketTask?.send(.string(text)) { error in
        if let error = error { print("❌ Composio key send error: \(error)") }
    }
}

func disconnectComposio() {
    let json: [String: Any] = ["data_type": "set_composio", "api_key": ""]
    guard let data = try? JSONSerialization.data(withJSONObject: json),
          let text = String(data: data, encoding: .utf8) else { return }
    print("📤 Disconnecting Composio")
    webSocketTask?.send(.string(text)) { error in
        if let error = error { print("❌ Composio disconnect send error: \(error)") }
    }
}
```

- [ ] **Step 2: Add callback property and handling for `builtin_warning`**

After the existing callback properties (near `var onOpenRouterOAuthResult`), add:

```swift
var onBuiltinWarning: ((String) -> Void)?  // server name
```

In `handleMessage`, add a new early-return block alongside the other special-case handlers (before the `do { let parsedMsg = ...` block):

```swift
// Handle builtin_warning (content is an object with "server" key)
if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
   let type = json["type"] as? String,
   type == "builtin_warning",
   let contentObj = json["content"] as? [String: Any],
   let serverName = contentObj["server"] as? String {
    DispatchQueue.main.async { [weak self] in
        self?.onBuiltinWarning?(serverName)
    }
    return
}
```

Also add `"builtin_warning"` to the list of known types in the `AgentMessage` decoder switch so it doesn't throw a decode error if it ever arrives via the standard path:

In the `init(from decoder:)` of `AgentMessage`, find the `case "credentials_success", ...` line and add `"builtin_warning"` to it.

- [ ] **Step 3: Build in Xcode (Cmd+B)**

Expected: No errors.

- [ ] **Step 4: Commit**

```bash
git add swift-ui/Rong-E/Services/RongESocketClient.swift
git commit -m "feat(swift): add sendBuiltinServersConfig, sendComposioKey, disconnectComposio"
```

---

## Task 9: Update App Startup Sequence in AppContext.swift

**Files:**
- Modify: `swift-ui/Rong-E/App/AppContext.swift`

The startup sequence fires after the WebSocket connects. Currently Google session restore and MCP config are sent from somewhere in the app startup flow (look for calls to `sendRestoreSession` and `sendMCPConfig` to find the exact call site — likely `ServerManager` or the `onAppear` of a root view). Add built-in and Composio restores to the same location.

- [ ] **Step 1: Find the startup send site**

Search the project for `sendRestoreSession` to find where it's called after WebSocket connection. It will be in one of: `AppContext.swift`, `ServerManager.swift`, or a root view's `onAppear`.

- [ ] **Step 2: Add built-in and Composio sends to the startup sequence**

At the same call site, after the existing `sendRestoreSession` / `sendMCPConfig` calls, add:

```swift
// Restore built-in server config
let builtinManager = BuiltinServerManager.shared
if !builtinManager.config.enabledServers.isEmpty {
    SocketClient.shared.sendBuiltinServersConfig(builtinManager.config)
}

// Restore Composio connection
if let composioKey = KeychainHelper.load(forKey: "composio_api_key"), !composioKey.isEmpty {
    SocketClient.shared.sendComposioKey(composioKey)
}
```

Make sure these come **after** `sendRestoreSession` (Google) and **before** `sendMCPConfig` (custom servers), matching the spec order:
1. Restore Google session
2. Send built-in servers config
3. Send Composio key
4. Send MCP config (custom servers)

- [ ] **Step 3: Build in Xcode (Cmd+B)**

Expected: No errors.

- [ ] **Step 4: Commit**

```bash
git add swift-ui/Rong-E/App/AppContext.swift
# include any other files that changed (ServerManager.swift etc)
git commit -m "feat(swift): restore built-in servers and Composio config on startup"
```

---

## Task 10: Rewrite MCPConfigView.swift with Three Sections

**Files:**
- Modify: `swift-ui/Rong-E/Views/Settings/MCPConfigView.swift`

- [ ] **Step 1: Add `BuiltinServersSection` subview**

Add this view to the file (before `#Preview`):

```swift
// MARK: - Built-in Servers Section

struct BuiltinServersSection: View {
    @ObservedObject var manager = BuiltinServerManager.shared
    @ObservedObject var configManager = MCPConfigManager.shared
    @ObservedObject private var _theme = AppContext.shared

    @State private var showShellWarning = false
    @State private var pendingShellEnable = false

    private let shellWarningKey = "shell_server_warning_acknowledged"

    private let servers: [(id: String, label: String, icon: String)] = [
        ("filesystem", "Filesystem", "folder"),
        ("fetch", "Web Fetch", "globe"),
        ("shell", "Shell", "terminal"),
        ("memory", "Memory Store", "memorychip"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: JarvisSpacing.sm) {
            Text("Built-in Servers")
                .font(JarvisFont.subtitle)
                .foregroundStyle(Color.jarvisTextPrimary)

            Text("Always-available tools — no configuration needed.")
                .font(JarvisFont.caption)
                .foregroundStyle(Color.jarvisTextSecondary)

            // Node.js not installed banner
            if hasNodeError {
                HStack(spacing: JarvisSpacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.jarvisOrange)
                    Text("Node.js is required for built-in servers.")
                        .font(JarvisFont.caption)
                        .foregroundStyle(Color.jarvisTextSecondary)
                    Spacer()
                    Link("Install →", destination: URL(string: "https://nodejs.org")!)
                        .font(JarvisFont.caption)
                        .foregroundStyle(Color.jarvisCyan)
                }
                .padding(JarvisSpacing.sm)
                .background(Color.jarvisOrange.opacity(0.1))
                .cornerRadius(JarvisRadius.small)
            }

            ForEach(servers, id: \.id) { server in
                VStack(alignment: .leading, spacing: JarvisSpacing.xs) {
                    HStack {
                        Image(systemName: server.icon)
                            .foregroundStyle(statusColor(for: server.id))
                            .frame(width: 20)
                        Text(server.label)
                            .font(JarvisFont.label)
                            .foregroundStyle(Color.jarvisTextPrimary)
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { manager.isEnabled(server.id) },
                            set: { newValue in handleToggle(server.id, newValue) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }

                    // Filesystem path picker
                    if server.id == "filesystem" && manager.isEnabled("filesystem") {
                        FilesystemPathsView(manager: manager)
                            .padding(.leading, 28)
                    }
                }
                .padding(JarvisSpacing.sm)
                .background(Color.jarvisSurfaceLight)
                .cornerRadius(JarvisRadius.medium)
            }
        }
        .alert("Shell Server Warning", isPresented: $showShellWarning) {
            Button("Enable", role: .destructive) {
                UserDefaults.standard.set(true, forKey: shellWarningKey)
                manager.setEnabled("shell", true)
            }
            Button("Cancel", role: .cancel) {
                // Do nothing — toggle stays off
            }
        } message: {
            Text("The shell server lets Rong-E run terminal commands on your Mac. Only enable this if you trust your prompts.")
        }
    }

    private var hasNodeError: Bool {
        servers.contains { server in
            if let status = configManager.serverStatuses[server.id],
               case .error(let msg) = status,
               msg.contains("Node.js not installed") { return true }
            return false
        }
    }

    private func statusColor(for name: String) -> Color {
        switch configManager.serverStatuses[name] {
        case .connected: return Color.jarvisGreen
        case .error: return Color.jarvisRed
        case .connecting: return Color.jarvisOrange
        default: return Color.jarvisTextDim
        }
    }

    private func handleToggle(_ name: String, _ enabled: Bool) {
        if name == "shell" && enabled {
            let acknowledged = UserDefaults.standard.bool(forKey: shellWarningKey)
            if !acknowledged {
                showShellWarning = true
                return
            }
        }
        manager.setEnabled(name, enabled)
    }
}

// MARK: - Filesystem Path Picker

struct FilesystemPathsView: View {
    @ObservedObject var manager: BuiltinServerManager
    @ObservedObject private var _theme = AppContext.shared

    var body: some View {
        VStack(alignment: .leading, spacing: JarvisSpacing.xs) {
            ForEach(manager.config.filesystemPaths, id: \.self) { path in
                HStack {
                    Text(path)
                        .font(JarvisFont.captionMono)
                        .foregroundStyle(Color.jarvisTextSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button {
                        manager.setFilesystemPaths(
                            manager.config.filesystemPaths.filter { $0 != path }
                        )
                    } label: {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(Color.jarvisRed)
                    }
                    .buttonStyle(.plain)
                }
            }
            Button {
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.allowsMultipleSelection = false
                if panel.runModal() == .OK, let url = panel.url {
                    var paths = manager.config.filesystemPaths
                    if !paths.contains(url.path) { paths.append(url.path) }
                    manager.setFilesystemPaths(paths)
                }
            } label: {
                Label("Add Path", systemImage: "plus.circle")
                    .font(JarvisFont.caption)
                    .foregroundStyle(Color.jarvisCyan)
            }
            .buttonStyle(.plain)
        }
    }
}
```

- [ ] **Step 2: Add `ComposioSection` subview**

```swift
// MARK: - Composio Section

struct ComposioSection: View {
    @ObservedObject var configManager = MCPConfigManager.shared
    @ObservedObject private var _theme = AppContext.shared

    @State private var apiKeyInput: String = ""
    @State private var isConnected: Bool = false
    @State private var toolCount: Int = 0
    @State private var errorMessage: String? = nil

    private let keychainKey = "composio_api_key"

    var body: some View {
        VStack(alignment: .leading, spacing: JarvisSpacing.sm) {
            HStack {
                Text("Composio")
                    .font(JarvisFont.subtitle)
                    .foregroundStyle(Color.jarvisTextPrimary)
                Spacer()
                statusIndicator
            }

            Text("Connect 250+ integrations (GitHub, Slack, Linear, …) via a single API key.")
                .font(JarvisFont.caption)
                .foregroundStyle(Color.jarvisTextSecondary)

            if let error = errorMessage {
                Text(error)
                    .font(JarvisFont.caption)
                    .foregroundStyle(Color.jarvisRed)
            }

            HStack(spacing: JarvisSpacing.sm) {
                SecureField("Composio API key…", text: $apiKeyInput)
                    .textFieldStyle(.plain)
                    .font(JarvisFont.mono)
                    .padding(JarvisSpacing.sm)
                    .background(Color.jarvisSurfaceDeep)
                    .overlay(
                        RoundedRectangle(cornerRadius: JarvisRadius.small)
                            .stroke(Color.jarvisBorder, lineWidth: 1)
                    )
                    .cornerRadius(JarvisRadius.small)

                Button(isConnected ? "Disconnect" : "Connect") {
                    if isConnected {
                        disconnect()
                    } else {
                        connect()
                    }
                }
                .buttonStyle(.plain)
                .font(JarvisFont.label)
                .foregroundStyle(Color.jarvisTextPrimary)
                .padding(.horizontal, JarvisSpacing.md)
                .padding(.vertical, JarvisSpacing.sm)
                .background(isConnected ? Color.jarvisRed.opacity(0.7) : Color.jarvisBlue)
                .cornerRadius(JarvisRadius.medium)
                .disabled(apiKeyInput.isEmpty && !isConnected)
            }

            Link("Get your API key →", destination: URL(string: "https://app.composio.dev/settings")!)
                .font(JarvisFont.caption)
                .foregroundStyle(Color.jarvisCyan)
        }
        .padding(JarvisSpacing.md)
        .background(Color.jarvisSurfaceLight)
        .cornerRadius(JarvisRadius.medium)
        .onAppear {
            // Restore key from Keychain for display (masked by SecureField)
            if let saved = KeychainHelper.load(forKey: keychainKey) {
                apiKeyInput = saved
            }
            refreshConnectionState()
        }
        .onReceive(configManager.$serverStatuses) { _ in
            refreshConnectionState()
        }
    }

    private var statusIndicator: some View {
        Group {
            if isConnected {
                HStack(spacing: 4) {
                    Circle().fill(Color.jarvisGreen).frame(width: 8, height: 8)
                    Text("\(toolCount) tools")
                        .font(JarvisFont.captionMono)
                        .foregroundStyle(Color.jarvisTextSecondary)
                }
            } else if let _ = errorMessage {
                Circle().fill(Color.jarvisRed).frame(width: 8, height: 8)
            } else {
                EmptyView()
            }
        }
    }

    private func connect() {
        let key = apiKeyInput.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }
        KeychainHelper.save(key, forKey: keychainKey)
        errorMessage = nil
        SocketClient.shared.sendComposioKey(key)
    }

    private func disconnect() {
        KeychainHelper.delete(forKey: keychainKey)
        apiKeyInput = ""
        isConnected = false
        toolCount = 0
        errorMessage = nil
        SocketClient.shared.disconnectComposio()
    }

    private func refreshConnectionState() {
        switch configManager.serverStatuses["composio"] {
        case .connected:
            isConnected = true
            errorMessage = nil
            // Tool count comes from the tools list
            let composioTools = MCPConfigManager.shared.servers
                .filter { $0.name == "composio" }
                .count
            toolCount = composioTools
        case .error(let msg):
            isConnected = false
            errorMessage = msg
        default:
            isConnected = false
        }
    }
}
```

- [ ] **Step 3: Update `MCPConfigView.body` to use three sections**

Replace the existing `var body: some View` in `MCPConfigView` with:

```swift
var body: some View {
    ScrollView {
        VStack(alignment: .leading, spacing: JarvisSpacing.xl) {

            // Section 1 — Built-in Servers
            BuiltinServersSection()

            Divider()

            // Section 2 — Composio
            ComposioSection()

            Divider()

            // Section 3 — Custom Servers (existing UI, unchanged)
            VStack(alignment: .leading, spacing: JarvisSpacing.lg) {
                HStack {
                    Text("Custom MCP Servers")
                        .font(JarvisFont.subtitle)
                        .foregroundStyle(Color.jarvisTextPrimary)
                    Spacer()
                    syncStatusIndicator
                }

                if let error = configManager.lastError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.jarvisOrange)
                        Text(error)
                            .font(JarvisFont.caption)
                            .foregroundStyle(Color.jarvisTextSecondary)
                        Spacer()
                        Button("Dismiss") { configManager.lastError = nil }
                            .buttonStyle(.plain)
                            .font(JarvisFont.caption)
                            .foregroundStyle(Color.jarvisCyan)
                    }
                    .padding(JarvisSpacing.sm)
                    .background(Color.jarvisOrange.opacity(0.1))
                    .cornerRadius(JarvisRadius.small)
                }

                if configManager.servers.isEmpty {
                    emptyStateView
                } else {
                    serverListView
                }

                Divider()

                HStack(spacing: JarvisSpacing.md) {
                    Button(action: { showFileImporter = true }) {
                        Label("Import File", systemImage: "doc.badge.plus")
                            .font(JarvisFont.label)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.jarvisCyan)
                    .padding(.horizontal, JarvisSpacing.md)
                    .padding(.vertical, JarvisSpacing.sm)
                    .background(Color.jarvisCyan.opacity(0.15))
                    .cornerRadius(JarvisRadius.medium)
                    .overlay(RoundedRectangle(cornerRadius: JarvisRadius.medium).stroke(Color.jarvisCyan.opacity(0.3), lineWidth: 1))

                    Button(action: { showJSONPasteSheet = true }) {
                        Label("Paste JSON", systemImage: "doc.on.clipboard")
                            .font(JarvisFont.label)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.jarvisCyan)
                    .padding(.horizontal, JarvisSpacing.md)
                    .padding(.vertical, JarvisSpacing.sm)
                    .background(Color.jarvisCyan.opacity(0.15))
                    .cornerRadius(JarvisRadius.medium)
                    .overlay(RoundedRectangle(cornerRadius: JarvisRadius.medium).stroke(Color.jarvisCyan.opacity(0.3), lineWidth: 1))

                    Button(action: { showAddServerSheet = true }) {
                        Label("Add Server", systemImage: "plus.circle")
                            .font(JarvisFont.label)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.jarvisGreen)
                    .padding(.horizontal, JarvisSpacing.md)
                    .padding(.vertical, JarvisSpacing.sm)
                    .background(Color.jarvisGreen.opacity(0.15))
                    .cornerRadius(JarvisRadius.medium)
                    .overlay(RoundedRectangle(cornerRadius: JarvisRadius.medium).stroke(Color.jarvisGreen.opacity(0.3), lineWidth: 1))

                    Spacer()

                    if !configManager.servers.isEmpty {
                        Button(action: { configManager.sendConfigToPython() }) {
                            Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                                .font(JarvisFont.label)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.jarvisTextPrimary)
                        .padding(.horizontal, JarvisSpacing.lg)
                        .padding(.vertical, JarvisSpacing.sm)
                        .background(Color.jarvisBlue)
                        .cornerRadius(JarvisRadius.medium)
                    }
                }
            }
        }
        .padding()
    }
    .frame(minWidth: 420, minHeight: 400)
    .background(Color.jarvisSurfaceDark)
    .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
        handleFileImport(result)
    }
    .sheet(isPresented: $showAddServerSheet) {
        AddServerSheet(onAdd: { server in configManager.addServer(server) })
    }
    .sheet(isPresented: $showJSONPasteSheet) {
        JSONPasteSheet(jsonText: $jsonPasteText, onSubmit: {
            configManager.loadConfig(from: jsonPasteText)
            jsonPasteText = ""
        })
    }
    .onAppear { setupSyncCallback() }
}
```

- [ ] **Step 4: Build in Xcode (Cmd+B)**

Expected: No errors. Fix any `statusColor` or import errors if `JarvisFont`/`JarvisSpacing` constants differ from what's used.

- [ ] **Step 5: Run the app and verify the settings panel**

Open Xcode → Cmd+R → open Settings → MCP tab. You should see:
- Three sections: Built-in Servers / Composio / Custom Servers
- Toggles for filesystem, fetch, shell, memory in Section 1
- Composio API key field + Connect button in Section 2
- Existing custom server list in Section 3

- [ ] **Step 6: Commit**

```bash
git add swift-ui/Rong-E/Views/Settings/MCPConfigView.swift
git commit -m "feat(swift): three-section MCPConfigView with built-in servers and Composio"
```

---

## Task 11: Wire MCPConfigManager to Update Composio + Built-in Status

**Files:**
- Modify: `swift-ui/Rong-E/Models/MCPConfig.swift`

The `MCPConfigManager.updateStatuses(from:)` is called when `mcp_server_status` arrives. It currently only manages user-configured servers. It needs to also update statuses for `composio` and built-in server names.

- [ ] **Step 1: Update `updateStatuses` to handle any server name**

The existing implementation already does this — it iterates `serverInfos` and updates `serverStatuses[info.name]`. No change is needed as long as the Rust backend sends built-in server names in the same `mcp_server_status` format. Confirm by reading `updateStatuses` — it should already handle `"filesystem"`, `"composio"`, etc. as plain string keys.

If `serverStatuses` is only keyed by user-configured server names in some other part of the code, ensure `ComposioSection.refreshConnectionState()` reads from `MCPConfigManager.shared.serverStatuses["composio"]` (which it does per Task 10).

- [ ] **Step 2: Wire `onMCPServerStatus` in the app root to call `BuiltinServerManager` sync if needed**

In the existing `onMCPServerStatus` handler (search for `SocketClient.shared.onMCPServerStatus`), confirm that `configManager.updateStatuses(from:)` is called. The status updates will then flow through `@Published var serverStatuses` to both `BuiltinServersSection` and `ComposioSection` via `@ObservedObject`.

No code change is needed if it's already wired. Just verify.

- [ ] **Step 3: Final end-to-end test**

1. Launch the app (Cmd+R)
2. Open Settings → MCP tab
3. Toggle **Fetch** on → Rust logs should show `🔗 Starting built-in MCP server 'fetch'`
4. Toggle **Filesystem** on → add a custom path via the path picker → Rust logs should show the path in the args
5. Toggle **Shell** on → confirm the warning sheet appears; click Enable → server starts
6. Enter a Composio API key and click Connect → status should turn green with tool count
7. Click Disconnect → status clears
8. Restart the app → built-in servers and Composio reconnect automatically

- [ ] **Step 4: Final commit**

```bash
git add .
git commit -m "feat: MCP integration — Composio + built-in servers complete"
```

---

## Self-Review

**Spec coverage check:**
- ✅ HTTP/SSE transport branch in `mcp_config` → Task 3
- ✅ `set_composio` handler → Task 4
- ✅ `set_builtin_servers` handler with registry → Task 5
- ✅ `builtin_servers` separate from `mcp_connections` in state → Task 2
- ✅ `all_mcp_tools()` collects both → Task 2
- ✅ Name collision prefix `custom:` → Task 3
- ✅ `KeychainHelper` for Composio key → Task 6
- ✅ `BuiltinServerConfig` + `BuiltinServerManager` → Task 7
- ✅ Three WebSocket send methods → Task 8
- ✅ `builtin_warning` handling → Task 8
- ✅ Startup sequence: built-ins + Composio + custom → Task 9
- ✅ Three-section `MCPConfigView` → Task 10
- ✅ Shell warning sheet (one-time, `UserDefaults` gated) → Task 10
- ✅ Filesystem path picker → Task 10
- ✅ Node.js not installed banner → Task 10
- ✅ Composio connect/disconnect card with Keychain → Task 10

**Placeholder scan:** No TBDs. Composio URL and SSE API caveat both noted inline with verification instructions.

**Type consistency:** `BuiltinServerConfig` defined in Task 7, used in Task 7 (`BuiltinServerManager`), Task 8 (`sendBuiltinServersConfig`), Task 9 (startup). All match. `KeychainHelper` defined in Task 6, used in Task 9 and Task 10 — key string `"composio_api_key"` is consistent across both uses.
