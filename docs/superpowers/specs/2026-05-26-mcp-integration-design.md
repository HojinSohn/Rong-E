# MCP Integration — Composio + Built-in Servers

**Date:** 2026-05-26  
**Status:** Approved  
**Scope:** Approach A — extend existing MCP pipeline with HTTP/SSE transport and a built-in server registry

---

## Overview

This spec covers two additions to Rong-E's MCP integration:

1. **Composio** — an OAuth-like onboarding flow (API key) that connects the agent to 250+ third-party integrations via Composio's MCP-over-HTTP endpoint.
2. **Built-in local MCP servers** — four hardcoded servers (filesystem, fetch, shell, memory) that are always available as toggleable defaults, requiring no user configuration beyond an on/off switch.

Custom MCP server development (user-authored servers) is out of scope for this session.

---

## Architecture

The existing MCP pipeline is unchanged. Two new tool sources feed into it:

```
┌─────────────────────────────────────────────────────────┐
│                   MCP Tool Sources                      │
│                                                         │
│  [Built-in]    [Composio]    [Custom (existing)]        │
│  filesystem    HTTP/SSE MCP  stdio subprocess           │
│  fetch         endpoint      (unchanged)                │
│  shell                                                  │
│  memory                                                 │
└──────────┬──────────────┬──────────────────────────────┘
           │              │
           ▼              ▼
    ┌──────────────────────────┐
    │  NotifyingMcpProxy       │  ← unchanged
    │  (tool_call/tool_result) │
    └──────────────────────────┘
           │
           ▼
    ┌──────────────┐
    │  rig-core    │  ← unchanged
    │  agent       │
    └──────────────┘
```

**Everything downstream of NotifyingMcpProxy is untouched** — llm.rs, tools.rs, routes.rs, and the WebSocket tool event protocol all stay the same.

---

## WebSocket Protocol Changes

Two new client→server message types:

```json
// Toggle built-in servers
{
  "data_type": "set_builtin_servers",
  "enabled": ["filesystem", "fetch", "shell", "memory"],
  "filesystem_paths": ["/Users/hojin"]
}

// Connect Composio
{ "data_type": "set_composio", "api_key": "sk-..." }

// Disconnect Composio
{ "data_type": "set_composio", "api_key": "" }
```

The existing `mcp_config` message gains an optional `transport` field for HTTP-transport servers:

```json
{
  "data_type": "mcp_config",
  "config": {
    "mcpServers": {
      "composio": {
        "transport": "http",
        "url": "https://mcp.composio.dev",
        "api_key": "sk-..."
      }
    }
  }
}
```

Servers without `transport` default to `"stdio"` (existing behavior, fully backward-compatible).

Existing server→client responses (`mcp_server_status`, `mcp_sync_success`, `mcp_sync_error`) are reused unchanged. Built-in servers and Composio appear as named entries in the `mcp_server_status` servers array.

A new server→client message warns before enabling the shell server:

```json
{ "type": "builtin_warning", "content": { "server": "shell" } }
```

---

## Rust Backend

### `state.rs`

Add two fields to `AppState`:

```rust
pub struct AppState {
    // ... existing fields unchanged ...
    /// Built-in servers tracked separately so they survive custom server resyncs.
    pub builtin_servers: HashMap<String, McpConnection>,
    pub composio_api_key: Option<String>,
}
```

`all_mcp_tools()` is updated to collect from both `mcp_connections` and `builtin_servers`.

### `logic.rs` — new handlers

**`set_builtin_servers`**
- Receives `enabled: Vec<String>` and `filesystem_paths: Vec<String>` (defaults to `[env::var("HOME")]`)
- Shuts down any currently-running built-in servers not in the new `enabled` list
- Starts servers in `enabled` that aren't already running
- Uses the same `build_expanded_path()` / `resolve_command()` / `TokioChildProcess` helpers as the existing `mcp_config` handler
- Sends `mcp_server_status` with results

**`set_composio`**
- Stores the API key in `state.composio_api_key`
- If non-empty: connects to Composio's MCP endpoint via HTTP transport (see below) and stores in `mcp_connections` under key `"composio"`
- If empty: cancels and removes the `"composio"` entry from `mcp_connections`
- Sends `mcp_server_status` with the result

### `logic.rs` — extended `mcp_config` handler

When a server entry contains `"transport": "http"`:

```rust
use rmcp::transport::SseClientTransport;

let transport = SseClientTransport::start_with_headers(
    url,
    [("Authorization", format!("Bearer {}", api_key))]
).await?;
let service = ().serve(transport).await?;
```

After this point, the flow is identical to stdio servers: list tools, wrap in `NotifyingMcpProxy`, store in `mcp_connections`.

When `transport` is absent or `"stdio"`, existing behavior is unchanged.

### Built-in Server Registry

Hardcoded definitions in `logic.rs`:

| Name | Command | Args | Default paths |
|---|---|---|---|
| `filesystem` | `npx` | `-y @modelcontextprotocol/server-filesystem <paths>` | `$HOME` |
| `fetch` | `npx` | `-y @modelcontextprotocol/server-fetch` | — |
| `shell` | `npx` | `-y @modelcontextprotocol/server-shell` | — |
| `memory` | `npx` | `-y @modelcontextprotocol/server-memory` | — |

If `npx` is not resolvable via `resolve_command()`, the server's status is set to `error` with message `"Node.js not installed"`. No crash; remaining servers continue starting.

### Name collision prevention

If a user-configured custom server uses a reserved name (`filesystem`, `fetch`, `shell`, `memory`), the Rust backend stores it in `mcp_connections` prefixed as `custom:filesystem` etc. Tool names are sanitized as before.

---

## Swift UI

### `MCPConfig.swift` — model additions

`MCPServerConfig` gains optional HTTP transport fields:

```swift
struct MCPServerConfig: Codable, Identifiable, Equatable {
    // ... existing fields ...
    let transport: String?   // "stdio" (default/nil) or "http"
    let url: String?
    let apiKey: String?
}
```

New model for built-in server state, persisted to UserDefaults under `builtin_server_config`:

```swift
struct BuiltinServerConfig: Codable {
    var enabledServers: Set<String>
    var filesystemPaths: [String]   // defaults to [NSHomeDirectory()]
}
```

### `MCPConfigView.swift` — three sections

**Section 1 — Built-in Servers**
- Toggle row per server: Filesystem, Fetch, Shell, Memory
- Filesystem toggle row shows a `+` path button opening `NSOpenPanel` (folder picker); selected paths shown as chips below the toggle
- Shell toggle shows a confirmation sheet on first enable (gated by `shell_server_warning_acknowledged` UserDefaults flag). Sheet text: *"The shell server lets Rong-E run terminal commands on your Mac. Only enable this if you trust your prompts."* with "Enable" and "Cancel" actions
- Any change calls `sendBuiltinServersConfig()` immediately
- If a server's status is `error` with "Node.js not installed", an inline banner appears: *"Node.js is required — [Install →]"* linking to `https://nodejs.org`

**Section 2 — Composio**
- Card with: secure `TextField` for API key, "Connect" / "Disconnect" button, status indicator (green dot + tool count when connected, red dot + error message when failed)
- "Get your API key →" link opens `https://app.composio.dev/settings` in the browser
- API key stored in **Keychain** (not UserDefaults) via a new `KeychainHelper` utility
- Connect action calls `sendComposioKey()`; Disconnect calls `disconnectComposio()`

**Section 3 — Custom Servers** *(unchanged)*
Existing import / paste JSON / add server UI exactly as today.

### `RongESocketClient.swift` — new send methods

```swift
func sendBuiltinServersConfig(_ config: BuiltinServerConfig)
func sendComposioKey(_ apiKey: String)
func disconnectComposio()
```

### App startup sequence

After WebSocket connects:
1. Restore Google session token (existing)
2. Send `set_builtin_servers` if `builtin_server_config` exists in UserDefaults
3. Send `set_composio` if Composio API key exists in Keychain
4. Send `mcp_config` for custom servers if config exists in UserDefaults (existing)

---

## Error Handling

| Scenario | Rust behavior | Swift UI behavior |
|---|---|---|
| `npx` not found | `error` status: "Node.js not installed" | Inline banner with install link; toggle stays on |
| Composio invalid API key | MCP handshake fails → `error` status | Red status dot, message: "Invalid API key" |
| Composio network unreachable | Same error path | Red status dot, message: "Could not reach Composio" |
| Composio goes offline mid-session | Tool calls return errors | Surfaced as normal tool_result errors in chat |
| Filesystem path outside sandbox | Tool calls fail at runtime | `connectedPermissionDenied` status (already modeled) |
| Shell server: user declines warning | Not sent to Rust | Toggle returns to off; flag not set |
| Custom server name collides with built-in | Stored as `custom:<name>` | Visible in tools list with `custom:` prefix |

---

## Files Changed

**Rust (`agent_server/src/`)**
- `state.rs` — add `builtin_servers`, `composio_api_key` fields
- `logic.rs` — add `set_builtin_servers`, `set_composio` handlers; extend `mcp_config` with HTTP transport branch; update `all_mcp_tools()` call
- `mcp_proxy.rs` — no changes (HTTP transport connection happens in `logic.rs` before proxy wrapping)
- `Cargo.toml` — verify rmcp's `SseClientTransport` feature is enabled

**Swift (`swift-ui/Rong-E/`)**
- `Models/MCPConfig.swift` — `MCPServerConfig` transport fields; `BuiltinServerConfig` model
- `Views/Settings/MCPConfigView.swift` — three-section layout; Composio card; built-in toggles; shell warning sheet
- `Services/RongESocketClient.swift` — `sendBuiltinServersConfig()`, `sendComposioKey()`, `disconnectComposio()`
- `App/AppContext.swift` — startup sequence additions
- `Services/KeychainHelper.swift` — new utility for Composio API key storage

---

## Out of Scope (this session)

- Custom MCP server development workflow (template scaffolding, user-authored servers)
- Generic OAuth per-server (non-Composio remote MCP servers)
- Bundling Node.js or npx into the app bundle
