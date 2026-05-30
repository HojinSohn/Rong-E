# Graph-Based Memory System — Design Spec

**Date:** 2026-05-30  
**Status:** Approved  
**Scope:** Rust backend (`agent_server/`) only — no SwiftUI changes required

---

## Overview

Replace the current flat-file memory system (`memory.md` + three read/save/append tools) with a graph-based memory engine backed by SQLite. Memory nodes are typed and tagged; edges express relationships between them. Retrieval is automated (runs before every LLM turn using keyword matching + LLM reranking). Saving is LLM-driven but always triggered via a required check-in instruction in the system prompt.

---

## Data Model

The graph lives at `~/.ronge/memory/graph.db` (SQLite). Three tables:

### `nodes`

| Column | Type | Notes |
|---|---|---|
| `id` | TEXT (UUID v4) | Primary key |
| `node_type` | TEXT | One of: `preference`, `person`, `project`, `event`, `fact`, `context` |
| `content` | TEXT | The memory text |
| `tags` | TEXT | JSON array of strings, e.g. `["rust","deadline","work"]` |
| `created_at` | INTEGER | Unix timestamp |
| `updated_at` | INTEGER | Unix timestamp |

### `edges`

| Column | Type | Notes |
|---|---|---|
| `from_id` | TEXT | FK → nodes.id |
| `to_id` | TEXT | FK → nodes.id |
| `relationship` | TEXT | e.g. `related_to`, `part_of`, `depends_on`, `contradicts` |

### `node_tags` (index table)

| Column | Type |
|---|---|
| `node_id` | TEXT |
| `tag` | TEXT |

Indexed on `node_tags(tag)` for O(log n) tag lookups. Both `from_id` and `to_id` in `edges` are indexed for bidirectional traversal.

---

## Tools

The three existing flat-file tools (`read_memory`, `save_to_memory`, `append_to_memory`) are removed and replaced with five graph-aware tools. All are wrapped with `NotifyingTool` so tool-step events appear in the SwiftUI UI.

### `add_memory_node`
**Args:** `node_type: string`, `content: string`, `tags: string[]`, `related_to?: string[]`  
Inserts a new node. If `related_to` is provided, creates `related_to` edges from the new node to each listed ID. Returns the new node's UUID.

### `query_memories`
**Args:** `keywords: string[]`, `node_type?: string`, `limit?: number` (default 10)  
Queries `node_tags` for nodes whose tags intersect with `keywords`. Returns up to `limit` nodes ranked by tag-match count, formatted as a compact list. Callable by the LLM on demand during a turn. Note: the automated pre-turn retrieval (below) calls the same underlying SQL logic directly in Rust — not through this tool — so it doesn't consume a tool-call slot.

### `update_memory_node`
**Args:** `id: string`, `content?: string`, `tags?: string[]`, `node_type?: string`  
Patches an existing node in place. Used to correct outdated information or enrich an existing memory rather than creating a duplicate.

### `link_memories`
**Args:** `from_id: string`, `to_id: string`, `relationship: string`  
Creates a directed edge between two existing nodes with a named relationship type.

### `delete_memory_node`
**Args:** `id: string`  
Removes a node and all its associated edges (both incoming and outgoing).

---

## Automated Injection Flow

### Pre-turn retrieval (automatic, in `llm.rs`)

Before building the rig agent and calling the LLM, a `retrieve_relevant_memories()` function runs:

1. Extract keywords from the user's message — lowercase, strip punctuation, drop common stop words.
2. Query `node_tags WHERE tag IN (keywords)`, group by `node_id`, order by match count descending.
3. Fetch up to 15 candidate nodes.
4. Format as a compact block and inject into the system prompt under `### Relevant Memories`.

If zero nodes match, the section is omitted — no noise added to the prompt.

### Post-turn save prompt (always-on, in system prompt)

The system prompt always ends with:

```
### Memory Check-In (required)
After responding, review this conversation turn. If the user shared anything worth remembering
(preferences, facts, project context, people, dates, decisions), call add_memory_node immediately.
If an existing memory is now outdated, call update_memory_node. If nothing new was shared, do nothing.
```

This makes memory saving a required step in every agent turn. The LLM still makes the judgment call on what to save, but it is always prompted to make it.

---

## Migration

On first run, `graph_memory.rs` checks whether `graph.db` exists:
- If yes: skip migration.
- If no, and `memory.md` exists: parse each `##`-headed section as a separate `fact` node with a `legacy` tag. Write all nodes to the new graph. Leave `memory.md` untouched.
- If no `memory.md` either: initialize an empty graph.

The old `memory.md` is never deleted by the migration.

---

## Files Changed

| File | Change |
|---|---|
| `agent_server/src/graph_memory.rs` | **New** — SQLite graph engine: schema init, CRUD operations, tag-based query, migration from flat file |
| `agent_server/src/tools.rs` | **Replace** `ReadMemory`, `SaveToMemory`, `AppendToMemory` with `AddMemoryNode`, `QueryMemories`, `UpdateMemoryNode`, `LinkMemories`, `DeleteMemoryNode` |
| `agent_server/src/llm.rs` | **Add** pre-turn `retrieve_relevant_memories()` call; inject `### Relevant Memories` block; append memory check-in instruction to system prompt |
| `agent_server/src/logic.rs` | **Update** `get_memory` handler to return a formatted text dump of all graph nodes (so the SwiftUI settings panel still shows memory content). `save_memory` becomes a no-op that returns a message indicating memory is now graph-managed via the agent. Update `active_tools` list. |
| `agent_server/Cargo.toml` | **Add** `rusqlite = { version = "0.31", features = ["bundled"] }`, `uuid = { version = "1", features = ["v4"] }` |
| `agent_server/prompts/system_prompt.txt` | **Update** memory section to describe graph tools and the always-on check-in protocol |

---

## What Does Not Change

- WebSocket protocol: `memory_content`, `memory_saved`, `memory_error` message types remain identical. The Swift client needs no changes.
- `ServerManager.swift`, `RongESocketClient.swift`, all SwiftUI views — untouched.
- The `default_memory_path()` function: kept for the migration path, pointing to the legacy `memory.md`.

---

## Out of Scope

- Embedding-based (vector) semantic retrieval — excluded by design decision (hybrid tag+LLM chosen instead).
- Graph visualization in SwiftUI.
- Multi-user memory separation.
- Memory encryption at rest.
