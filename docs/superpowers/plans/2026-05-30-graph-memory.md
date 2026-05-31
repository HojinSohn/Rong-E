# Graph Memory Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the flat `memory.md` file with a SQLite graph database, automated pre-turn memory injection, and five graph-aware LLM tools.

**Architecture:** A new `graph_memory.rs` module owns the SQLite connection (nodes + edges + tag index tables). Before each LLM call, relevant nodes are queried by keyword and injected into the system prompt. After each call, a mandatory check-in instruction prompts the LLM to save anything worth remembering.

**Tech Stack:** `rusqlite 0.31` (bundled SQLite), `uuid 1` (v4 node IDs), `chrono 0.4` (already in Cargo.toml), existing `rig-core`, `tokio::task::spawn_blocking` for async↔sync bridge.

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `agent_server/Cargo.toml` | Modify | Add rusqlite (bundled), uuid deps |
| `agent_server/src/main.rs` | Modify | Register `graph_memory` module; init `GraphMemory` in `async_main` |
| `agent_server/src/graph_memory.rs` | **Create** | SQLite engine: schema, CRUD, keyword query, migration, retrieval helper |
| `agent_server/src/state.rs` | Modify | Add `graph_memory: Arc<GraphMemory>` field to `AppState` |
| `agent_server/src/tools.rs` | Modify | Remove 3 flat-file tools; add 5 graph tools |
| `agent_server/src/llm.rs` | Modify | Add `graph_memory` param; pre-turn retrieval; check-in prompt; wire new tools |
| `agent_server/src/logic.rs` | Modify | Update `get_memory`/`save_memory` handlers; update `tools_request`; pass graph to `call_llm` |
| `agent_server/prompts/system_prompt.txt` | Modify | Replace memory section to describe graph tools |

---

## Task 1: Add Dependencies and Register Module

**Files:**
- Modify: `agent_server/Cargo.toml`
- Modify: `agent_server/src/main.rs`

- [ ] **Step 1: Add rusqlite and uuid to Cargo.toml**

In `agent_server/Cargo.toml`, add after the `rand` line:

```toml
rusqlite = { version = "0.31", features = ["bundled"] }
uuid = { version = "1", features = ["v4"] }
```

- [ ] **Step 2: Register the new module in main.rs**

In `agent_server/src/main.rs`, add after `mod tools;` (line 13):

```rust
mod graph_memory;
```

- [ ] **Step 3: Verify the project compiles**

```bash
cd agent_server && cargo build 2>&1 | head -30
```

Expected: compiles successfully (no new source files yet, just deps + module declaration which will error on missing file — that's fine, fix in Task 2).

---

## Task 2: Create graph_memory.rs — Types, Schema, and Migration

**Files:**
- Create: `agent_server/src/graph_memory.rs`

- [ ] **Step 1: Write the failing schema test**

Create `agent_server/src/graph_memory.rs` with this content (tests only, no impl yet):

```rust
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use rusqlite::{Connection, params};

pub fn db_path() -> PathBuf {
    dirs::home_dir()
        .unwrap_or_else(|| PathBuf::from("/tmp"))
        .join(".ronge")
        .join("memory")
        .join("graph.db")
}

pub fn legacy_md_path() -> PathBuf {
    dirs::home_dir()
        .unwrap_or_else(|| PathBuf::from("/tmp"))
        .join(".ronge")
        .join("memory")
        .join("memory.md")
}

#[derive(Debug, Clone)]
pub struct MemoryNode {
    pub id: String,
    pub node_type: String,
    pub content: String,
    pub tags: Vec<String>,
    pub created_at: i64,
    pub updated_at: i64,
}

pub struct GraphMemory {
    conn: Arc<Mutex<Connection>>,
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_graph() -> GraphMemory {
        let path = std::env::temp_dir().join(format!(
            "ronge_test_{}.db",
            uuid::Uuid::new_v4()
        ));
        GraphMemory::open(path).expect("Failed to open test graph")
    }

    #[test]
    fn test_schema_init_creates_tables() {
        let g = temp_graph();
        let conn = g.conn.lock().unwrap();
        let count: i64 = conn
            .query_row("SELECT COUNT(*) FROM sqlite_master WHERE type='table'", [], |r| r.get(0))
            .unwrap();
        assert_eq!(count, 3, "Expected nodes, edges, node_tags tables");
    }

    #[test]
    fn test_migration_from_empty_markdown() {
        let g = temp_graph();
        g.migrate_from_markdown("");
        let nodes = g.all_nodes().unwrap();
        assert!(nodes.is_empty());
    }

    #[test]
    fn test_migration_parses_sections() {
        let g = temp_graph();
        let md = "## Preferences\nLikes dark mode\n\n## Projects\nBuilding Rong-E";
        g.migrate_from_markdown(md);
        let nodes = g.all_nodes().unwrap();
        assert_eq!(nodes.len(), 2);
        assert!(nodes.iter().all(|n| n.tags.contains(&"legacy".to_string())));
    }
}
```

- [ ] **Step 2: Run the tests to confirm they fail**

```bash
cd agent_server && cargo test graph_memory 2>&1 | tail -20
```

Expected: compile error — `GraphMemory::open`, `migrate_from_markdown`, `all_nodes` not yet defined.

- [ ] **Step 3: Implement GraphMemory::open, init_schema, migrate_from_markdown, and all_nodes**

Add these impls to `agent_server/src/graph_memory.rs` after the struct definition:

```rust
impl GraphMemory {
    pub fn open(path: PathBuf) -> rusqlite::Result<Self> {
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent).ok();
        }
        let conn = Connection::open(&path)?;
        let gm = GraphMemory {
            conn: Arc::new(Mutex::new(conn)),
        };
        gm.init_schema()?;
        gm.maybe_migrate();
        Ok(gm)
    }

    fn conn(&self) -> std::sync::MutexGuard<Connection> {
        self.conn.lock().unwrap()
    }

    fn init_schema(&self) -> rusqlite::Result<()> {
        self.conn().execute_batch(
            "PRAGMA foreign_keys = ON;
             CREATE TABLE IF NOT EXISTS nodes (
                 id TEXT PRIMARY KEY,
                 node_type TEXT NOT NULL,
                 content TEXT NOT NULL,
                 tags TEXT NOT NULL DEFAULT '[]',
                 created_at INTEGER NOT NULL,
                 updated_at INTEGER NOT NULL
             );
             CREATE TABLE IF NOT EXISTS edges (
                 from_id TEXT NOT NULL,
                 to_id TEXT NOT NULL,
                 relationship TEXT NOT NULL,
                 PRIMARY KEY (from_id, to_id, relationship),
                 FOREIGN KEY (from_id) REFERENCES nodes(id) ON DELETE CASCADE,
                 FOREIGN KEY (to_id) REFERENCES nodes(id) ON DELETE CASCADE
             );
             CREATE TABLE IF NOT EXISTS node_tags (
                 node_id TEXT NOT NULL,
                 tag TEXT NOT NULL,
                 FOREIGN KEY (node_id) REFERENCES nodes(id) ON DELETE CASCADE
             );
             CREATE INDEX IF NOT EXISTS idx_node_tags_tag ON node_tags(tag);
             CREATE INDEX IF NOT EXISTS idx_edges_from ON edges(from_id);
             CREATE INDEX IF NOT EXISTS idx_edges_to ON edges(to_id);",
        )
    }

    fn maybe_migrate(&self) {
        let md_path = legacy_md_path();
        if !md_path.exists() {
            return;
        }
        let count: i64 = self
            .conn()
            .query_row("SELECT COUNT(*) FROM nodes", [], |r| r.get(0))
            .unwrap_or(0);
        if count > 0 {
            return;
        }
        if let Ok(content) = std::fs::read_to_string(&md_path) {
            self.migrate_from_markdown(&content);
        }
    }

    pub fn migrate_from_markdown(&self, content: &str) {
        if content.trim().is_empty() {
            return;
        }
        let now = chrono::Utc::now().timestamp();
        let conn = self.conn();
        for section in content.split("\n## ") {
            let trimmed = section.trim_start_matches('#').trim();
            if trimmed.is_empty() {
                continue;
            }
            let id = uuid::Uuid::new_v4().to_string();
            let _ = conn.execute(
                "INSERT OR IGNORE INTO nodes (id, node_type, content, tags, created_at, updated_at)
                 VALUES (?1, 'fact', ?2, '[\"legacy\"]', ?3, ?4)",
                params![id, trimmed, now, now],
            );
            let _ = conn.execute(
                "INSERT INTO node_tags (node_id, tag) VALUES (?1, 'legacy')",
                params![id],
            );
        }
    }

    pub fn all_nodes(&self) -> rusqlite::Result<Vec<MemoryNode>> {
        let conn = self.conn();
        let mut stmt = conn.prepare(
            "SELECT id, node_type, content, tags, created_at, updated_at
             FROM nodes ORDER BY updated_at DESC",
        )?;
        let nodes = stmt
            .query_map([], |row| {
                let tags_json: String = row.get(3)?;
                let tags: Vec<String> = serde_json::from_str(&tags_json).unwrap_or_default();
                Ok(MemoryNode {
                    id: row.get(0)?,
                    node_type: row.get(1)?,
                    content: row.get(2)?,
                    tags,
                    created_at: row.get(4)?,
                    updated_at: row.get(5)?,
                })
            })?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        Ok(nodes)
    }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

```bash
cd agent_server && cargo test graph_memory::tests::test_schema 2>&1
cd agent_server && cargo test graph_memory::tests::test_migration 2>&1
```

Expected: all 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add agent_server/Cargo.toml agent_server/Cargo.lock agent_server/src/main.rs agent_server/src/graph_memory.rs
git commit -m "feat: add graph_memory module with SQLite schema and migration"
```

---

## Task 3: Add CRUD Operations to graph_memory.rs

**Files:**
- Modify: `agent_server/src/graph_memory.rs`

- [ ] **Step 1: Write failing CRUD tests**

Add to the `#[cfg(test)]` block in `graph_memory.rs`:

```rust
    #[test]
    fn test_add_node_returns_id() {
        let g = temp_graph();
        let id = g.add_node("preference", "Likes dark mode", &["ui".to_string()]).unwrap();
        assert!(!id.is_empty());
        let nodes = g.all_nodes().unwrap();
        assert_eq!(nodes.len(), 1);
        assert_eq!(nodes[0].content, "Likes dark mode");
        assert_eq!(nodes[0].tags, vec!["ui"]);
    }

    #[test]
    fn test_update_node_content() {
        let g = temp_graph();
        let id = g.add_node("fact", "Old content", &["tag1".to_string()]).unwrap();
        g.update_node(&id, Some("New content"), None, None).unwrap();
        let nodes = g.all_nodes().unwrap();
        assert_eq!(nodes[0].content, "New content");
    }

    #[test]
    fn test_delete_node_removes_tags() {
        let g = temp_graph();
        let id = g.add_node("fact", "Will be deleted", &["tmp".to_string()]).unwrap();
        g.delete_node(&id).unwrap();
        assert!(g.all_nodes().unwrap().is_empty());
        let conn = g.conn.lock().unwrap();
        let tag_count: i64 = conn
            .query_row("SELECT COUNT(*) FROM node_tags WHERE node_id = ?1", params![id], |r| r.get(0))
            .unwrap();
        assert_eq!(tag_count, 0);
    }

    #[test]
    fn test_link_nodes_creates_edge() {
        let g = temp_graph();
        let a = g.add_node("project", "Rong-E", &["rust".to_string()]).unwrap();
        let b = g.add_node("event", "Deadline 2026-06-01", &["deadline".to_string()]).unwrap();
        g.link_nodes(&a, &b, "depends_on").unwrap();
        let conn = g.conn.lock().unwrap();
        let count: i64 = conn
            .query_row("SELECT COUNT(*) FROM edges WHERE from_id = ?1 AND to_id = ?2", params![a, b], |r| r.get(0))
            .unwrap();
        assert_eq!(count, 1);
    }
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
cd agent_server && cargo test graph_memory::tests::test_add 2>&1 | tail -5
```

Expected: compile error — `add_node`, `update_node`, `delete_node`, `link_nodes` not yet defined.

- [ ] **Step 3: Implement add_node, update_node, delete_node, link_nodes**

Add to the `impl GraphMemory` block in `graph_memory.rs`:

```rust
    pub fn add_node(
        &self,
        node_type: &str,
        content: &str,
        tags: &[String],
    ) -> rusqlite::Result<String> {
        let id = uuid::Uuid::new_v4().to_string();
        let now = chrono::Utc::now().timestamp();
        let tags_json = serde_json::to_string(tags).unwrap_or_else(|_| "[]".to_string());
        let conn = self.conn();
        conn.execute(
            "INSERT INTO nodes (id, node_type, content, tags, created_at, updated_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
            params![id, node_type, content, tags_json, now, now],
        )?;
        for tag in tags {
            conn.execute(
                "INSERT INTO node_tags (node_id, tag) VALUES (?1, ?2)",
                params![id, tag.to_lowercase()],
            )?;
        }
        Ok(id)
    }

    pub fn update_node(
        &self,
        id: &str,
        content: Option<&str>,
        tags: Option<&[String]>,
        node_type: Option<&str>,
    ) -> rusqlite::Result<()> {
        let now = chrono::Utc::now().timestamp();
        let conn = self.conn();
        if let Some(c) = content {
            conn.execute(
                "UPDATE nodes SET content = ?1, updated_at = ?2 WHERE id = ?3",
                params![c, now, id],
            )?;
        }
        if let Some(nt) = node_type {
            conn.execute(
                "UPDATE nodes SET node_type = ?1, updated_at = ?2 WHERE id = ?3",
                params![nt, now, id],
            )?;
        }
        if let Some(t) = tags {
            let tags_json = serde_json::to_string(t).unwrap_or_else(|_| "[]".to_string());
            conn.execute(
                "UPDATE nodes SET tags = ?1, updated_at = ?2 WHERE id = ?3",
                params![tags_json, now, id],
            )?;
            conn.execute("DELETE FROM node_tags WHERE node_id = ?1", params![id])?;
            for tag in t {
                conn.execute(
                    "INSERT INTO node_tags (node_id, tag) VALUES (?1, ?2)",
                    params![id, tag.to_lowercase()],
                )?;
            }
        }
        Ok(())
    }

    pub fn delete_node(&self, id: &str) -> rusqlite::Result<()> {
        let conn = self.conn();
        conn.execute("PRAGMA foreign_keys = ON", [])?;
        conn.execute("DELETE FROM nodes WHERE id = ?1", params![id])?;
        conn.execute("DELETE FROM node_tags WHERE node_id = ?1", params![id])?;
        conn.execute("DELETE FROM edges WHERE from_id = ?1 OR to_id = ?1", params![id])?;
        Ok(())
    }

    pub fn link_nodes(
        &self,
        from_id: &str,
        to_id: &str,
        relationship: &str,
    ) -> rusqlite::Result<()> {
        self.conn().execute(
            "INSERT OR IGNORE INTO edges (from_id, to_id, relationship) VALUES (?1, ?2, ?3)",
            params![from_id, to_id, relationship],
        )?;
        Ok(())
    }
```

- [ ] **Step 4: Run CRUD tests and confirm they pass**

```bash
cd agent_server && cargo test graph_memory 2>&1 | tail -15
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add agent_server/src/graph_memory.rs
git commit -m "feat: add CRUD operations to GraphMemory"
```

---

## Task 4: Add Keyword Extraction, Query, and Format Helpers

**Files:**
- Modify: `agent_server/src/graph_memory.rs`

- [ ] **Step 1: Write failing query and format tests**

Add to the `#[cfg(test)]` block:

```rust
    #[test]
    fn test_query_by_keywords_finds_matching_node() {
        let g = temp_graph();
        g.add_node("project", "Working on Rong-E in Rust", &["rust".to_string(), "project".to_string()]).unwrap();
        g.add_node("preference", "Likes dark mode", &["ui".to_string()]).unwrap();
        let results = g.query_by_keywords(&["rust".to_string()], None, 10).unwrap();
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].node_type, "project");
    }

    #[test]
    fn test_query_ranks_by_match_count() {
        let g = temp_graph();
        g.add_node("fact", "Node with one tag", &["rust".to_string()]).unwrap();
        g.add_node("fact", "Node with two tags", &["rust".to_string(), "project".to_string()]).unwrap();
        let results = g.query_by_keywords(
            &["rust".to_string(), "project".to_string()], None, 10
        ).unwrap();
        assert_eq!(results[0].content, "Node with two tags");
    }

    #[test]
    fn test_extract_keywords_drops_stop_words() {
        let kw = extract_keywords("what is the best way to build this");
        assert!(!kw.contains(&"the".to_string()));
        assert!(!kw.contains(&"is".to_string()));
        assert!(kw.contains(&"best".to_string()) || kw.contains(&"build".to_string()));
    }

    #[test]
    fn test_format_for_prompt_empty_returns_empty() {
        assert_eq!(format_for_prompt(&[]), String::new());
    }

    #[test]
    fn test_retrieve_returns_empty_on_no_match() {
        let g = temp_graph();
        let result = retrieve_relevant_memories("hello world", &g);
        assert_eq!(result, String::new());
    }
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
cd agent_server && cargo test graph_memory::tests::test_query 2>&1 | tail -5
```

Expected: compile errors.

- [ ] **Step 3: Implement extract_keywords, query_by_keywords, format_for_prompt, retrieve_relevant_memories**

Add these free functions and the `query_by_keywords` method to `graph_memory.rs`:

```rust
const STOP_WORDS: &[&str] = &[
    "a", "an", "the", "is", "are", "was", "were", "be", "been", "being",
    "have", "has", "had", "do", "does", "did", "will", "would", "could",
    "should", "may", "might", "can", "to", "of", "in", "on", "at", "by",
    "for", "with", "about", "and", "but", "or", "not", "no", "i", "me",
    "my", "we", "our", "you", "your", "he", "she", "it", "its", "they",
    "what", "which", "who", "how", "when", "where", "why", "this", "that",
    "there", "here", "just", "also", "so", "if", "as", "up", "out",
];

pub fn extract_keywords(text: &str) -> Vec<String> {
    use std::collections::HashSet;
    text.to_lowercase()
        .split(|c: char| !c.is_alphanumeric())
        .filter(|w| w.len() > 2 && !STOP_WORDS.contains(w))
        .map(|w| w.to_string())
        .collect::<HashSet<_>>()
        .into_iter()
        .collect()
}

pub fn format_for_prompt(nodes: &[MemoryNode]) -> String {
    if nodes.is_empty() {
        return String::new();
    }
    nodes
        .iter()
        .map(|n| {
            format!(
                "[{}] {} — Tags: {} — ID: {}",
                n.node_type,
                n.content,
                n.tags.join(", "),
                n.id
            )
        })
        .collect::<Vec<_>>()
        .join("\n")
}

pub fn retrieve_relevant_memories(query: &str, graph: &GraphMemory) -> String {
    let keywords = extract_keywords(query);
    if keywords.is_empty() {
        return String::new();
    }
    match graph.query_by_keywords(&keywords, None, 15) {
        Ok(nodes) if nodes.is_empty() => String::new(),
        Ok(nodes) => format!("### Relevant Memories\n\n{}", format_for_prompt(&nodes)),
        Err(e) => {
            eprintln!("⚠️ Memory retrieval error: {}", e);
            String::new()
        }
    }
}
```

Add `query_by_keywords` to `impl GraphMemory`:

```rust
    pub fn query_by_keywords(
        &self,
        keywords: &[String],
        node_type_filter: Option<&str>,
        limit: usize,
    ) -> rusqlite::Result<Vec<MemoryNode>> {
        if keywords.is_empty() {
            return Ok(vec![]);
        }
        let conn = self.conn();
        let placeholders: Vec<String> = keywords.iter().map(|_| "?".to_string()).collect();
        let in_clause = placeholders.join(",");
        let type_filter_clause = if node_type_filter.is_some() {
            "AND n.node_type = ?"
        } else {
            ""
        };
        let sql = format!(
            "SELECT n.id, n.node_type, n.content, n.tags, n.created_at, n.updated_at,
                    COUNT(*) as cnt
             FROM nodes n
             JOIN node_tags nt ON nt.node_id = n.id
             WHERE nt.tag IN ({}) {}
             GROUP BY n.id
             ORDER BY cnt DESC
             LIMIT ?",
            in_clause, type_filter_clause
        );
        let mut params_vec: Vec<&dyn rusqlite::ToSql> =
            keywords.iter().map(|k| k as &dyn rusqlite::ToSql).collect();
        let limit_val = limit as i64;
        if let Some(nt) = node_type_filter {
            params_vec.push(nt);
        }
        params_vec.push(&limit_val);
        let mut stmt = conn.prepare(&sql)?;
        let nodes = stmt
            .query_map(params_vec.as_slice(), |row| {
                let tags_json: String = row.get(3)?;
                let tags: Vec<String> = serde_json::from_str(&tags_json).unwrap_or_default();
                Ok(MemoryNode {
                    id: row.get(0)?,
                    node_type: row.get(1)?,
                    content: row.get(2)?,
                    tags,
                    created_at: row.get(4)?,
                    updated_at: row.get(5)?,
                })
            })?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        Ok(nodes)
    }
```

- [ ] **Step 4: Run all graph_memory tests and confirm they pass**

```bash
cd agent_server && cargo test graph_memory 2>&1 | tail -20
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add agent_server/src/graph_memory.rs
git commit -m "feat: add keyword extraction, graph query, and retrieval helpers"
```

---

## Task 5: Replace Memory Tools in tools.rs

**Files:**
- Modify: `agent_server/src/tools.rs`

- [ ] **Step 1: Remove the three flat-file tools**

In `agent_server/src/tools.rs`, delete everything from line 254 to end of file:
- The `default_memory_path()` function
- The entire `ReadMemory` struct + impl
- The entire `SaveToMemory` struct + impl  
- The entire `AppendToMemory` struct + impl
- The `SaveToMemoryArgs` and `AppendToMemoryArgs` structs

Keep lines 1–253 (the `NotifyingTool`, `EmptyArgs`, `Calculator`, `OpenApplication`, `OpenChromeTab` sections).

- [ ] **Step 2: Add Other variant to ToolError**

In `agent_server/src/tools.rs`, find the `ToolError` enum (around line 86) and add the `Other` variant:

```rust
#[derive(Debug, Error)]
pub enum ToolError {
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),
    #[error("Command failed: {0}")]
    CommandFailed(String),
    #[error("{0}")]
    Other(String),
}
```

- [ ] **Step 3: Add the five graph tools**

Append to `agent_server/src/tools.rs`:

```rust
use std::sync::Arc;
use crate::graph_memory::GraphMemory;

// ── Graph Memory Tools ──

// AddMemoryNode

#[derive(Clone)]
pub struct AddMemoryNode {
    pub graph: Arc<GraphMemory>,
}

impl AddMemoryNode {
    pub fn new(graph: Arc<GraphMemory>) -> Self {
        Self { graph }
    }
}

#[derive(Deserialize, Serialize)]
pub struct AddMemoryNodeArgs {
    pub node_type: String,
    pub content: String,
    pub tags: Vec<String>,
    pub related_to: Option<Vec<String>>,
}

impl Tool for AddMemoryNode {
    const NAME: &'static str = "add_memory_node";
    type Args = AddMemoryNodeArgs;
    type Output = String;
    type Error = ToolError;

    async fn definition(&self, _prompt: String) -> ToolDefinition {
        ToolDefinition {
            name: "add_memory_node".to_string(),
            description: "Store a new piece of information as a typed, tagged graph node. Returns the node ID.".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "node_type": {
                        "type": "string",
                        "enum": ["preference", "person", "project", "event", "fact", "context"],
                        "description": "Category of this memory"
                    },
                    "content": { "type": "string", "description": "The memory text to store" },
                    "tags": {
                        "type": "array",
                        "items": { "type": "string" },
                        "description": "Keywords for retrieval, e.g. [\"rust\", \"deadline\", \"work\"]"
                    },
                    "related_to": {
                        "type": "array",
                        "items": { "type": "string" },
                        "description": "Optional IDs of existing nodes to link with related_to edges"
                    }
                },
                "required": ["node_type", "content", "tags"]
            }),
        }
    }

    async fn call(&self, args: Self::Args) -> Result<Self::Output, Self::Error> {
        let graph = Arc::clone(&self.graph);
        let node_type = args.node_type.clone();
        let content = args.content.clone();
        let tags = args.tags.clone();
        let related_to = args.related_to.clone();
        let id = tokio::task::spawn_blocking(move || {
            graph.add_node(&node_type, &content, &tags)
        })
        .await
        .map_err(|e| ToolError::Other(e.to_string()))?
        .map_err(|e| ToolError::Other(e.to_string()))?;

        if let Some(related_ids) = related_to {
            let graph2 = Arc::clone(&self.graph);
            let id2 = id.clone();
            tokio::task::spawn_blocking(move || {
                for rel_id in &related_ids {
                    let _ = graph2.link_nodes(&id2, rel_id, "related_to");
                }
            })
            .await
            .ok();
        }
        Ok(format!("Saved. Node ID: {}", id))
    }
}

// QueryMemories

#[derive(Clone)]
pub struct QueryMemories {
    pub graph: Arc<GraphMemory>,
}

impl QueryMemories {
    pub fn new(graph: Arc<GraphMemory>) -> Self {
        Self { graph }
    }
}

#[derive(Deserialize, Serialize)]
pub struct QueryMemoriesArgs {
    pub keywords: Vec<String>,
    pub node_type: Option<String>,
    pub limit: Option<usize>,
}

impl Tool for QueryMemories {
    const NAME: &'static str = "query_memories";
    type Args = QueryMemoriesArgs;
    type Output = String;
    type Error = ToolError;

    async fn definition(&self, _prompt: String) -> ToolDefinition {
        ToolDefinition {
            name: "query_memories".to_string(),
            description: "Search memory nodes by keyword tags. Returns matching nodes with their IDs.".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "keywords": {
                        "type": "array",
                        "items": { "type": "string" },
                        "description": "Tags to search for"
                    },
                    "node_type": {
                        "type": "string",
                        "description": "Optional filter by type"
                    },
                    "limit": {
                        "type": "integer",
                        "description": "Max results (default 10)"
                    }
                },
                "required": ["keywords"]
            }),
        }
    }

    async fn call(&self, args: Self::Args) -> Result<Self::Output, Self::Error> {
        let graph = Arc::clone(&self.graph);
        let keywords = args.keywords;
        let node_type = args.node_type.clone();
        let limit = args.limit.unwrap_or(10);
        let nodes = tokio::task::spawn_blocking(move || {
            graph.query_by_keywords(&keywords, node_type.as_deref(), limit)
        })
        .await
        .map_err(|e| ToolError::Other(e.to_string()))?
        .map_err(|e| ToolError::Other(e.to_string()))?;

        if nodes.is_empty() {
            return Ok("No matching memories found.".to_string());
        }
        Ok(crate::graph_memory::format_for_prompt(&nodes))
    }
}

// UpdateMemoryNode

#[derive(Clone)]
pub struct UpdateMemoryNode {
    pub graph: Arc<GraphMemory>,
}

impl UpdateMemoryNode {
    pub fn new(graph: Arc<GraphMemory>) -> Self {
        Self { graph }
    }
}

#[derive(Deserialize, Serialize)]
pub struct UpdateMemoryNodeArgs {
    pub id: String,
    pub content: Option<String>,
    pub tags: Option<Vec<String>>,
    pub node_type: Option<String>,
}

impl Tool for UpdateMemoryNode {
    const NAME: &'static str = "update_memory_node";
    type Args = UpdateMemoryNodeArgs;
    type Output = String;
    type Error = ToolError;

    async fn definition(&self, _prompt: String) -> ToolDefinition {
        ToolDefinition {
            name: "update_memory_node".to_string(),
            description: "Patch an existing memory node by ID. Use instead of creating duplicates.".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "id": { "type": "string", "description": "Node ID to update" },
                    "content": { "type": "string" },
                    "tags": { "type": "array", "items": { "type": "string" } },
                    "node_type": { "type": "string" }
                },
                "required": ["id"]
            }),
        }
    }

    async fn call(&self, args: Self::Args) -> Result<Self::Output, Self::Error> {
        let graph = Arc::clone(&self.graph);
        let id = args.id.clone();
        let content = args.content.clone();
        let tags = args.tags.clone();
        let node_type = args.node_type.clone();
        tokio::task::spawn_blocking(move || {
            graph.update_node(
                &id,
                content.as_deref(),
                tags.as_deref(),
                node_type.as_deref(),
            )
        })
        .await
        .map_err(|e| ToolError::Other(e.to_string()))?
        .map_err(|e| ToolError::Other(e.to_string()))?;
        Ok("Memory node updated.".to_string())
    }
}

// LinkMemories

#[derive(Clone)]
pub struct LinkMemories {
    pub graph: Arc<GraphMemory>,
}

impl LinkMemories {
    pub fn new(graph: Arc<GraphMemory>) -> Self {
        Self { graph }
    }
}

#[derive(Deserialize, Serialize)]
pub struct LinkMemoriesArgs {
    pub from_id: String,
    pub to_id: String,
    pub relationship: String,
}

impl Tool for LinkMemories {
    const NAME: &'static str = "link_memories";
    type Args = LinkMemoriesArgs;
    type Output = String;
    type Error = ToolError;

    async fn definition(&self, _prompt: String) -> ToolDefinition {
        ToolDefinition {
            name: "link_memories".to_string(),
            description: "Create a directed relationship edge between two memory nodes.".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "from_id": { "type": "string" },
                    "to_id": { "type": "string" },
                    "relationship": {
                        "type": "string",
                        "description": "e.g. related_to, part_of, depends_on, contradicts"
                    }
                },
                "required": ["from_id", "to_id", "relationship"]
            }),
        }
    }

    async fn call(&self, args: Self::Args) -> Result<Self::Output, Self::Error> {
        let graph = Arc::clone(&self.graph);
        let from_id = args.from_id.clone();
        let to_id = args.to_id.clone();
        let relationship = args.relationship.clone();
        tokio::task::spawn_blocking(move || {
            graph.link_nodes(&from_id, &to_id, &relationship)
        })
        .await
        .map_err(|e| ToolError::Other(e.to_string()))?
        .map_err(|e| ToolError::Other(e.to_string()))?;
        Ok(format!("Linked {} → {} as {}.", args.from_id, args.to_id, args.relationship))
    }
}

// DeleteMemoryNode

#[derive(Clone)]
pub struct DeleteMemoryNode {
    pub graph: Arc<GraphMemory>,
}

impl DeleteMemoryNode {
    pub fn new(graph: Arc<GraphMemory>) -> Self {
        Self { graph }
    }
}

#[derive(Deserialize, Serialize)]
pub struct DeleteMemoryNodeArgs {
    pub id: String,
}

impl Tool for DeleteMemoryNode {
    const NAME: &'static str = "delete_memory_node";
    type Args = DeleteMemoryNodeArgs;
    type Output = String;
    type Error = ToolError;

    async fn definition(&self, _prompt: String) -> ToolDefinition {
        ToolDefinition {
            name: "delete_memory_node".to_string(),
            description: "Remove a memory node and all its edges.".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "id": { "type": "string", "description": "Node ID to delete" }
                },
                "required": ["id"]
            }),
        }
    }

    async fn call(&self, args: Self::Args) -> Result<Self::Output, Self::Error> {
        let graph = Arc::clone(&self.graph);
        let id = args.id.clone();
        tokio::task::spawn_blocking(move || graph.delete_node(&id))
            .await
            .map_err(|e| ToolError::Other(e.to_string()))?
            .map_err(|e| ToolError::Other(e.to_string()))?;
        Ok("Memory node deleted.".to_string())
    }
}
```

Also update the `ToolError` enum if it doesn't already have an `Other` variant. Check the current definition and add if missing:

```rust
#[derive(Error, Debug)]
pub enum ToolError {
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),
    #[error("{0}")]
    Other(String),
}
```

- [ ] **Step 4: Build to verify tools compile**

```bash
cd agent_server && cargo build 2>&1 | grep -E "^error" | head -20
```

Expected: no errors (there will be unused-import warnings from `llm.rs` referencing removed types — fix in Task 7).

- [ ] **Step 5: Commit**

```bash
git add agent_server/src/tools.rs
git commit -m "feat: replace flat-file memory tools with five graph-aware tools"
```

---

## Task 6: Wire GraphMemory into AppState and main.rs

**Files:**
- Modify: `agent_server/src/state.rs`
- Modify: `agent_server/src/main.rs`

- [ ] **Step 1: Add graph_memory field to AppState**

In `agent_server/src/state.rs`, replace the entire file with:

```rust
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::Mutex;

pub struct McpConnection {
    pub tools: Vec<rmcp::model::Tool>,
    pub peer: rmcp::service::ServerSink,
    pub _service: rmcp::service::RunningService<rmcp::RoleClient, ()>,
}

pub struct AppState {
    pub current_model: String,
    pub current_provider: String,
    pub api_keys: HashMap<String, String>,
    pub mcp_connections: HashMap<String, McpConnection>,
    pub builtin_servers: HashMap<String, McpConnection>,
    pub composio_api_key: Option<String>,
    pub graph_memory: Arc<crate::graph_memory::GraphMemory>,
}

pub type SharedState = Arc<Mutex<AppState>>;

impl AppState {
    pub fn new(graph_memory: Arc<crate::graph_memory::GraphMemory>) -> Self {
        Self {
            current_model: "gemini-2.5-flash".to_string(),
            current_provider: "gemini".to_string(),
            api_keys: HashMap::new(),
            mcp_connections: HashMap::new(),
            builtin_servers: HashMap::new(),
            composio_api_key: None,
            graph_memory,
        }
    }

    pub fn all_mcp_tools(&self) -> Vec<(Vec<rmcp::model::Tool>, rmcp::service::ServerSink)> {
        self.mcp_connections
            .values()
            .chain(self.builtin_servers.values())
            .map(|c| (c.tools.clone(), c.peer.clone()))
            .collect()
    }
}
```

- [ ] **Step 2: Update async_main in main.rs to initialize GraphMemory**

In `agent_server/src/main.rs`, replace the `async fn async_main()` body:

```rust
async fn async_main() {
    tracing_subscriber::fmt::init();

    let graph_memory = Arc::new(
        graph_memory::GraphMemory::open(graph_memory::db_path())
            .expect("Failed to initialize memory graph"),
    );

    let state = Arc::new(Mutex::new(AppState::new(graph_memory)));

    let app = Router::new()
        .route("/ws", get(routes::ws_handler))
        .with_state(state);

    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    println!("PORT={}", port);
    println!("🚀 Rust Server listening on 127.0.0.1:{}", port);

    axum::serve(listener, app).await.unwrap();
}
```

- [ ] **Step 3: Build to verify**

```bash
cd agent_server && cargo build 2>&1 | grep "^error" | head -20
```

Expected: errors only in `llm.rs` (still imports removed types) — fix in next task.

- [ ] **Step 4: Commit**

```bash
git add agent_server/src/state.rs agent_server/src/main.rs
git commit -m "feat: initialize GraphMemory in AppState at server startup"
```

---

## Task 7: Update llm.rs — Pre-turn Retrieval, Check-In Prompt, New Tools

**Files:**
- Modify: `agent_server/src/llm.rs`

- [ ] **Step 1: Update imports and add check-in constant**

Replace lines 1–4 in `agent_server/src/llm.rs`:

```rust
use crate::tools::{
    AddMemoryNode, Calculator, DeleteMemoryNode, LinkMemories, NotifyingTool,
    OpenApplication, OpenChromeTab, QueryMemories, ToolEventSender, UpdateMemoryNode,
};
```

Add after the imports (after line 12):

```rust
const MEMORY_CHECK_IN: &str = "\
### Memory Check-In (required)
After responding, review this conversation turn. If the user shared anything worth \
remembering (preferences, facts, project context, people, dates, decisions), call \
add_memory_node immediately. If an existing memory is now outdated, call \
update_memory_node. If nothing new was shared, do nothing.";
```

- [ ] **Step 2: Add graph_memory parameter to call_llm signature**

Replace the `call_llm` signature (lines 17–28):

```rust
pub async fn call_llm(
    provider: String,
    api_key: String,
    model: String,
    query: String,
    chat_history: Vec<RigMessage>,
    mcp_tool_sets: Vec<(Vec<rmcp::model::Tool>, rmcp::service::ServerSink)>,
    system_prompt: Option<String>,
    base64_image: Option<String>,
    tool_tx: ToolEventSender,
    user_name: Option<String>,
    graph_memory: std::sync::Arc<crate::graph_memory::GraphMemory>,
) -> Result<String, String> {
```

- [ ] **Step 3: Remove old memory_path line and add pre-turn retrieval**

Remove line 29 (`let memory_path = crate::tools::default_memory_path();`).

After the existing `let final_prompt = ...` block (after line 46, before `println!("🧠...")`) insert the following. The second `let final_prompt` shadows (replaces) the first — this is intentional and valid Rust:

```rust
    let memory_context = {
        let g = std::sync::Arc::clone(&graph_memory);
        let q = query.clone();
        tokio::task::spawn_blocking(move || {
            crate::graph_memory::retrieve_relevant_memories(&q, &g)
        })
        .await
        .unwrap_or_default()
    };

    // Shadow final_prompt to append memory context and mandatory check-in instruction
    let final_prompt = if memory_context.is_empty() {
        format!("{}\n\n{}", final_prompt, MEMORY_CHECK_IN)
    } else {
        format!("{}\n\n{}\n\n{}", final_prompt, memory_context, MEMORY_CHECK_IN)
    };
```

- [ ] **Step 4: Replace old memory tools in build_agent! macro**

Replace lines 74–76 (the three old memory tool lines) with:

```rust
                .tool(NotifyingTool { inner: AddMemoryNode::new(std::sync::Arc::clone(&graph_memory)), tx: tx.clone() })
                .tool(NotifyingTool { inner: QueryMemories::new(std::sync::Arc::clone(&graph_memory)), tx: tx.clone() })
                .tool(NotifyingTool { inner: UpdateMemoryNode::new(std::sync::Arc::clone(&graph_memory)), tx: tx.clone() })
                .tool(NotifyingTool { inner: LinkMemories::new(std::sync::Arc::clone(&graph_memory)), tx: tx.clone() })
                .tool(NotifyingTool { inner: DeleteMemoryNode::new(std::sync::Arc::clone(&graph_memory)), tx: tx.clone() })
```

- [ ] **Step 5: Build and fix any remaining errors**

```bash
cd agent_server && cargo build 2>&1 | grep "^error" | head -30
```

Expected: errors in `logic.rs` — `call_llm` call site doesn't pass `graph_memory` yet. Fix in Task 8.

- [ ] **Step 6: Commit**

```bash
git add agent_server/src/llm.rs
git commit -m "feat: add graph memory injection and check-in prompt to LLM call"
```

---

## Task 8: Update logic.rs Handlers and call_llm Call Site

**Files:**
- Modify: `agent_server/src/logic.rs`

- [ ] **Step 1: Update get_memory handler**

Replace lines 289–297 (the `"get_memory"` match arm):

```rust
        "get_memory" => {
            let graph_memory = {
                let s = state.lock().await;
                std::sync::Arc::clone(&s.graph_memory)
            };
            let content = tokio::task::spawn_blocking(move || {
                let nodes = graph_memory.all_nodes().unwrap_or_default();
                crate::graph_memory::format_for_prompt(&nodes)
            })
            .await
            .unwrap_or_default();
            let _ = sender
                .send(Message::Text(
                    json!({"type": "memory_content", "content": content}).to_string(),
                ))
                .await;
        }
```

- [ ] **Step 2: Update save_memory handler**

Replace lines 299–328 (the `"save_memory"` match arm):

```rust
        "save_memory" => {
            let _ = sender
                .send(Message::Text(
                    json!({"type": "memory_saved", "content": "Memory is now graph-managed. Use the AI assistant to add, update, or delete memories."})
                        .to_string(),
                ))
                .await;
        }
```

- [ ] **Step 3: Update tools_request handler**

Replace the three old memory entries in the `tools_list` vec (lines 544–546) with:

```rust
                json!({"name": "add_memory_node", "source": "built-in", "description": "Store a new memory node in the knowledge graph"}),
                json!({"name": "query_memories", "source": "built-in", "description": "Search memory nodes by keyword"}),
                json!({"name": "update_memory_node", "source": "built-in", "description": "Update an existing memory node"}),
                json!({"name": "link_memories", "source": "built-in", "description": "Create a relationship between two memory nodes"}),
                json!({"name": "delete_memory_node", "source": "built-in", "description": "Remove a memory node"}),
```

- [ ] **Step 4: Pass graph_memory to call_llm in handle_chat**

In `handle_chat` (around line 866), replace:

```rust
    let (api_key, model, provider, mcp_tool_sets) = {
        let s = state.lock().await;
        let key = s.api_keys.get(&s.current_provider).cloned();
        (
            key,
            s.current_model.clone(),
            s.current_provider.clone(),
            s.all_mcp_tools(),
        )
    };
```

With:

```rust
    let (api_key, model, provider, mcp_tool_sets, graph_memory) = {
        let s = state.lock().await;
        let key = s.api_keys.get(&s.current_provider).cloned();
        (
            key,
            s.current_model.clone(),
            s.current_provider.clone(),
            s.all_mcp_tools(),
            std::sync::Arc::clone(&s.graph_memory),
        )
    };
```

Then in the `tokio::spawn(llm::call_llm(...))` call (around line 898), add `graph_memory` as the last argument:

```rust
    let mut llm_task = tokio::spawn(llm::call_llm(
        provider,
        api_key.unwrap_or_default(),
        model,
        query.clone(),
        history_clone,
        mcp_tool_sets,
        system_prompt,
        base64_image,
        tool_tx,
        user_name,
        graph_memory,
    ));
```

- [ ] **Step 5: Full build — must be clean**

```bash
cd agent_server && cargo build 2>&1 | grep "^error"
```

Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add agent_server/src/logic.rs
git commit -m "feat: update logic.rs to use graph memory handlers and pass graph to call_llm"
```

---

## Task 9: Update system_prompt.txt and Full Verification

**Files:**
- Modify: `agent_server/prompts/system_prompt.txt`

- [ ] **Step 1: Replace the Memory Management section**

In `agent_server/prompts/system_prompt.txt`, find the `### Memory Management` section and replace it entirely with:

```
### Memory Management
You have access to a persistent graph-based memory system. Relevant memories are automatically injected into your context before each response under "### Relevant Memories" — check those IDs before creating new nodes to avoid duplicates.

- **Node Types**: `preference`, `person`, `project`, `event`, `fact`, `context`
- **Tools**:
  - `add_memory_node`: Store new information as a typed, tagged node. Returns the ID.
  - `query_memories`: Search nodes by keyword when you need to recall something not in the injected context.
  - `update_memory_node`: Patch an existing node (use instead of creating duplicates — use the ID from injected context).
  - `link_memories`: Create a named relationship between two nodes (e.g. `depends_on`, `part_of`).
  - `delete_memory_node`: Remove a node that is stale or wrong.
- **Tagging**: Be specific — `["rust", "project", "deadline"]` not just `["work"]`. Tags drive retrieval.
```

- [ ] **Step 2: Run the full test suite**

```bash
cd agent_server && cargo test 2>&1 | tail -20
```

Expected: all tests pass.

- [ ] **Step 3: Build the release binary**

```bash
cd agent_server && cargo build --release 2>&1 | tail -10
```

Expected: `Finished release [optimized]` with no errors.

- [ ] **Step 4: Smoke-test the server starts and graph initializes**

```bash
cd agent_server && timeout 3 cargo run --release 2>&1 | head -5
```

Expected output includes:
```
PORT=<some_port>
🚀 Rust Server listening on 127.0.0.1:<port>
```
(No panic about graph initialization.)

- [ ] **Step 5: Final commit**

```bash
git add agent_server/prompts/system_prompt.txt
git commit -m "feat: update system prompt for graph memory tools"
```
