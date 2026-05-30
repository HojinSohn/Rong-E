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
        let keywords_owned: Vec<String> = keywords.to_vec();
        let limit_val = limit as i64;
        let mut stmt = conn.prepare(&sql)?;
        let nodes = stmt
            .query_map(
                rusqlite::params_from_iter(
                    keywords_owned
                        .iter()
                        .map(|k| k as &dyn rusqlite::ToSql)
                        .chain(
                            node_type_filter
                                .iter()
                                .map(|nt| nt as &dyn rusqlite::ToSql),
                        )
                        .chain(std::iter::once(&limit_val as &dyn rusqlite::ToSql)),
                ),
                |row| {
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
                },
            )?
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
}
