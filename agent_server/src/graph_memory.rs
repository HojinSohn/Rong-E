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
        if path == db_path() {
            gm.maybe_migrate();
        }
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
