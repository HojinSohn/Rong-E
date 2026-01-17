# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Echo is a macOS AI assistant with a Python FastAPI/LangChain backend and a native SwiftUI frontend. The assistant ("Rong-E") runs as a floating overlay window and communicates with the backend via WebSocket.

## Commands

### Python Backend
```bash
# Install dependencies
python -m pip install -r agent/requirements.txt

# Run WebSocket server (main deployment)
python -m agent.server
# Server runs on localhost:8000, WebSocket at ws://0.0.0.0:8000/ws

# Run CLI agent for testing (no WebSocket)
python -m agent.main
```

### macOS UI
```bash
# Open Xcode project
open macOS_UI/Rong-E.xcodeproj
# Build and run with Cmd+R in Xcode
```

## Architecture

### Data Flow
```
User Input (macOS UI)
    ↓
RongESocketClient (WebSocket)
    ↓
FastAPI Server (server.py)
    ↓
EchoAgent (LangChain orchestrator)
    ├── Gemini 2.5 Flash (LLM)
    ├── Base Tools (web_search, file_ops, KB search)
    ├── GoogleAgent (Gmail, Calendar, Sheets sub-agent)
    └── MCP Servers (Filesystem, etc.)
    ↓
Streaming callbacks → WebSocket → UI
```

### Python Backend (`agent/`)

- **`server.py`**: FastAPI WebSocket server. Accepts `{text, mode, base64_image}`, streams responses as `{type: "thought"|"tool_call"|"tool_result"|"response", content}`.

- **`agent/agent.py`**: Main EchoAgent orchestrator using LangChain. Max 15 iterations per task.

- **`agent/google_agent.py`**: Specialized sub-agent for Google APIs (Gmail read-only, Calendar, Sheets). Max 10 iterations.

- **`tools.py`**: Base tool definitions - `web_search`, `get_current_date_time`, `list_directory`, `read_file`, `collect_files`, `search_knowledge_base`, `open_application`, `open_chrome_tab`.

- **`services/google_service.py`**: Google OAuth management and toolkit factory.

- **`services/rag.py`**: RAG retriever using Ollama embeddings (`nomic-embed-text`) + Chroma vector store.

- **`prompts/`**: System prompts. Main persona in `system_prompt.txt`, Google specialist in `google_agent_prompt.txt`.

- **`config/`**: Google OAuth credentials (`credentials.json`, `token.json`).

### macOS UI (`macOS_UI/Rong-E/`)

- **`RongEApp.swift`**: Entry point. Triggers startup workflow after launch.

- **`AppContext.swift`**: Singleton global state (auth status, modes, settings). Persists to UserDefaults.

- **`RongESocketClient.swift`**: Singleton WebSocket client. Connects to backend, decodes streaming messages.

- **`MainView.swift`**: Primary overlay UI - input field, response display, tool visualization.

- **`WindowCoordinator.swift`**: NSPanel window management, minimize/expand animations.

- **`WorkflowManager.swift`**: Startup task orchestration ("Morning Briefing").

- **`FloatingViews/`**: Settings panels (Google OAuth, mode config, workflow settings).

### External Dependencies

- **RAG Storage**: `/Users/hojinsohn/Echo_RAG/chroma_db` (Chroma vector DB)
- **RAG Documents**: `/Users/hojinsohn/Echo_RAG/Echo_documents`
- **Ollama**: Required for embeddings (`nomic-embed-text` model)
- **Piper + SoX**: Required for TTS (`play` command)

## Key Patterns

### Adding New Tools
1. Define tool in `tools.py` with `@tool` decorator
2. Register in `get_tool_map()` function
3. Tool will be automatically available to EchoAgent

### Modifying Agent Behavior
- Prompts: Edit files in `agent/prompts/`
- Agent logic: Modify `agent/agent/agent.py` or `google_agent.py`
- Iteration limits: Hardcoded in agent classes (EchoAgent: 15, GoogleAgent: 10)

### WebSocket Message Protocol
```python
# Client → Server
{"text": str, "mode": str, "base64_image": Optional[str]}

# Server → Client (streaming)
{"type": "thought"|"tool_call"|"tool_result"|"response", "content": str}
```

### MCP Integration
MCP servers are dynamically started/stopped. Currently configured for `@modelcontextprotocol/server-filesystem`. Tools from MCP servers are aggregated with base tools in the agent.
