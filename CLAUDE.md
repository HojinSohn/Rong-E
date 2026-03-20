# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Rong-E is a macOS AI assistant with a Rust/Axum backend and a native SwiftUI frontend. The assistant runs as a floating overlay window and communicates with the backend via WebSocket. The Swift app launches the Rust binary as a subprocess on startup.

## Commands

### Rust Backend
```bash
# Build (from agent_server/)
cargo build --release

# Run manually (for testing)
cargo run --release
# Server runs on ws://127.0.0.1:3000/ws
```

### macOS UI
```bash
# Open Xcode project
open swift-ui/Rong-E.xcodeproj
# Build and run with Cmd+R in Xcode
```

## Architecture

### Data Flow
```
User Input (SwiftUI)
    ↓
RongESocketClient (WebSocket)
    ↓
Axum WebSocket Server (routes.rs → logic.rs)
    ↓
LLM Agent (llm.rs, via rig-core)
    ├── Gemini / OpenAI / Anthropic / Ollama (configurable)
    ├── Built-in Tools (calculator, open_application, open_chrome_tab, memory)
    ├── GoogleSubAgent (Gmail, Calendar, Sheets)
    └── MCP Servers (dynamically started/stopped)
    ↓
tool_call / tool_result events + final response → WebSocket → UI
```

### Rust Backend (`agent_server/src/`)

- **`main.rs`**: Entry point. Fixes stdio blocking (Swift subprocess pipes), sets `OLLAMA_API_BASE_URL`, starts Tokio runtime and Axum server on port 3000.

- **`routes.rs`**: WebSocket upgrade handler. Maintains per-connection `chat_history` and dispatches each message to `logic.rs`.

- **`logic.rs`**: Core message dispatcher. Routes on `data_type` field for config messages (api key, LLM config, credentials, MCP, memory, spreadsheets) or falls through to `handle_chat`. Spawns the LLM task and forwards tool events concurrently.

- **`state.rs`**: `AppState` — holds `current_provider`, `current_model`, `api_key`, Google OAuth tokens, MCP connections, and spreadsheet configs.

- **`llm.rs`**: Builds the rig-core agent for the configured provider (gemini/openai/anthropic/ollama), injects system prompt with user name + current datetime, attaches all tools, and runs the agent loop.

- **`tools.rs`**: Built-in tool definitions (`Calculator`, `OpenApplication`, `OpenChromeTab`, `ReadMemory`, `SaveToMemory`, `AppendToMemory`) plus `NotifyingTool` wrapper that emits `tool_call`/`tool_result` WebSocket events.

- **`google_agent.rs`**: `GoogleSubAgent` — a rig-core tool that delegates to a specialized sub-agent for Gmail, Calendar, and Sheets.

- **`google_auth.rs`**: Google OAuth2 flow (token refresh + browser-based consent).

- **`google_tools.rs`**: Individual Google API tool implementations.

- **`mcp_proxy.rs`**: Proxies tool calls to dynamically-spawned MCP child processes via `rmcp`.

- **`prompts/`**: System prompts embedded at compile time. `system_prompt.txt` (main persona), `google_agent_prompt.txt` (Google sub-agent).

### macOS UI (`swift-ui/Rong-E/`)

- **`App/RongEApp.swift`**: Entry point. Launches server subprocess and triggers startup workflow.

- **`App/AppContext.swift`**: Singleton global state — modes, LLM provider/model/API keys (stored per-provider in UserDefaults), theme, user name.

- **`App/Constants.swift`**: Shared constants.

- **`Services/ServerManager.swift`**: Starts/stops the Rust binary as a subprocess. Locates the binary from the cargo release build or app bundle.

- **`Services/RongESocketClient.swift`**: Singleton WebSocket client. Connects to `ws://127.0.0.1:3000/ws`, encodes outgoing messages, decodes streaming responses.

- **`Services/GoogleAuthManager.swift`**: Handles Google OAuth credential path management from the Swift side.

- **`Services/ScreenshotManager.swift`**: Screen capture utilities.

- **`Services/WorkflowManager.swift`**: Startup task orchestration ("Morning Briefing").

- **`Views/Main/MainView.swift`**: Primary overlay UI — input field, response display, tool step visualization.

- **`Views/Settings/Settings.swift`**: LLM config (provider/model/API key), permissions.

- **`Views/Settings/GoogleServiceView.swift`**: Google OAuth settings panel.

- **`Views/Settings/ThemeSettingsView.swift`**: Theme customization.

- **`Views/Settings/MCPConfigView.swift`**: MCP server configuration.

- **`Views/Settings/ModeSettings.swift`**: Mode (system prompt) configuration.

- **`Views/Settings/WorkflowSettingView.swift`**: Morning briefing workflow settings.

- **`Views/Components/`**: `ChatWidgetView`, `ToolDetailWindowView`, `ToolFormatter`, `PermissionWaitingView`, `ImageView`.

- **`Overlay/OverlayManager.swift`**: NSPanel window management and animations.

- **`Theme/JarvisDesignSystem.swift`**: Design tokens (colors, modifiers).

- **`Models/`**: `SpreadsheetConfig.swift`, `MCPConfig.swift`.

## Key Patterns

### Adding New Built-in Tools
1. Define a struct in `tools.rs` implementing `rig::tool::Tool`
2. Wrap it with `NotifyingTool` in `llm.rs` when building the agent
3. Add to the `tools_list` in the `tools_request` handler in `logic.rs`

### Modifying Agent Behavior
- Prompts: Edit `agent_server/prompts/system_prompt.txt` (embedded at compile time — requires rebuild)
- LLM logic: `agent_server/src/llm.rs`
- Google sub-agent: `agent_server/src/google_agent.rs` + `google_agent_prompt.txt`

### WebSocket Message Protocol
```json
// Client → Server (chat)
{"text": "...", "system_prompt": "...", "base64_image": "...", "user_name": "..."}

// Client → Server (config, keyed by data_type)
{"data_type": "set_llm", "provider": "gemini", "model": "gemini-2.5-flash", "api_key": "..."}
{"data_type": "credentials", "content": "/path/to/google/creds/folder"}
{"data_type": "start_oauth", "dir_path": "/path/to/google/creds/folder"}
{"data_type": "revoke_credentials"}
{"data_type": "mcp_config", "config": {"mcpServers": {...}}}
{"data_type": "sync_spreadsheets", "configs": [...]}
{"data_type": "get_memory"} / {"data_type": "save_memory", "content": "..."}
{"data_type": "reset_session"}

// Server → Client
{"type": "response", "content": {"text": "...", "images": [], "widgets": []}}
{"type": "tool_call", "content": {"toolName": "...", "toolArgs": {...}}}
{"type": "tool_result", "content": {"toolName": "...", "result": "..."}}
{"type": "llm_set_success"|"llm_set_error", "content": "..."}
{"type": "credentials_success"|"credentials_error"|"credentials_revoked", "content": "..."}
{"type": "mcp_sync_success"|"mcp_sync_error"|"mcp_server_status", "content": {...}}
{"type": "memory_content"|"memory_saved"|"memory_error", "content": "..."}
{"type": "session_reset"|"oauth_url"|"active_tools"|"spreadsheets_synced", "content": "..."}
```

### LLM Providers
Supported: `gemini`, `openai`, `anthropic`, `ollama`. Provider and model are set at runtime via `set_llm`. Ollama requires no API key. API keys are stored per-provider in UserDefaults (`apiKey_<provider>`).

### MCP Integration
MCP servers are spawned as child processes when the Swift app sends `mcp_config`. The Rust backend resolves `npx`/`node`/`python` by building an expanded PATH (including nvm, Homebrew, cargo, etc.). Tools from all connected MCP servers are aggregated with built-in tools.
