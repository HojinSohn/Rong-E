use rig::completion::ToolDefinition;
use rig::tool::Tool;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use thiserror::Error;

// ── Error Types ──

#[derive(Debug, Error)]
pub enum ToolError {
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),
    #[error("Command failed: {0}")]
    CommandFailed(String),
}

// ── Calculator ──

#[derive(Deserialize)]
pub struct CalcArgs {
    x: f64,
    y: f64,
    operation: String,
}

#[derive(Debug, Error)]
#[error("Math error")]
pub struct MathError;

#[derive(Deserialize, Serialize)]
pub struct Calculator;

impl Tool for Calculator {
    const NAME: &'static str = "calculator";
    type Args = CalcArgs;
    type Output = f64;
    type Error = MathError;

    async fn definition(&self, _prompt: String) -> ToolDefinition {
        ToolDefinition {
            name: "calculator".to_string(),
            description: "Performs basic math operations (add, subtract, multiply, divide)".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "x": { "type": "number", "description": "First number" },
                    "y": { "type": "number", "description": "Second number" },
                    "operation": { "type": "string", "enum": ["add", "subtract", "multiply", "divide"] }
                },
                "required": ["x", "y", "operation"]
            }),
        }
    }

    async fn call(&self, args: Self::Args) -> Result<Self::Output, Self::Error> {
        match args.operation.as_str() {
            "add" => Ok(args.x + args.y),
            "subtract" => Ok(args.x - args.y),
            "multiply" => Ok(args.x * args.y),
            "divide" => Ok(args.x / args.y),
            _ => Ok(0.0),
        }
    }
}

// ── GetCurrentDateTime ──

#[derive(Deserialize, Serialize)]
pub struct GetCurrentDateTime;

#[derive(Deserialize)]
pub struct EmptyArgs {}

impl Tool for GetCurrentDateTime {
    const NAME: &'static str = "get_current_date_time";
    type Args = EmptyArgs;
    type Output = String;
    type Error = ToolError;

    async fn definition(&self, _prompt: String) -> ToolDefinition {
        ToolDefinition {
            name: "get_current_date_time".to_string(),
            description: "Returns the current local date and time in YYYY-MM-DD HH:MM:SS format.".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {},
                "required": []
            }),
        }
    }

    async fn call(&self, _args: Self::Args) -> Result<Self::Output, Self::Error> {
        Ok(chrono::Local::now().format("%Y-%m-%d %H:%M:%S").to_string())
    }
}

// ── OpenApplication ──

#[derive(Deserialize, Serialize)]
pub struct OpenApplication;

#[derive(Deserialize)]
pub struct OpenApplicationArgs {
    app_name: String,
}

impl Tool for OpenApplication {
    const NAME: &'static str = "open_application";
    type Args = OpenApplicationArgs;
    type Output = String;
    type Error = ToolError;

    async fn definition(&self, _prompt: String) -> ToolDefinition {
        ToolDefinition {
            name: "open_application".to_string(),
            description: "Opens a specified application on macOS (e.g. Safari, Spotify, Terminal).".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "app_name": { "type": "string", "description": "Name of the application to open" }
                },
                "required": ["app_name"]
            }),
        }
    }

    async fn call(&self, args: Self::Args) -> Result<Self::Output, Self::Error> {
        let status = tokio::process::Command::new("open")
            .arg("-a")
            .arg(&args.app_name)
            .status()
            .await?;

        if !status.success() {
            return Err(ToolError::CommandFailed(format!("Failed to open {}", args.app_name)));
        }

        let _ = tokio::process::Command::new("osascript")
            .arg("-e")
            .arg(format!("activate application \"{}\"", args.app_name))
            .status()
            .await;

        Ok(format!("Opened {}", args.app_name))
    }
}

// ── OpenChromeTab ──

#[derive(Deserialize, Serialize)]
pub struct OpenChromeTab;

#[derive(Deserialize)]
pub struct OpenChromeTabArgs {
    url: String,
}

impl Tool for OpenChromeTab {
    const NAME: &'static str = "open_chrome_tab";
    type Args = OpenChromeTabArgs;
    type Output = String;
    type Error = ToolError;

    async fn definition(&self, _prompt: String) -> ToolDefinition {
        ToolDefinition {
            name: "open_chrome_tab".to_string(),
            description: "Opens a URL in a new tab in Google Chrome.".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "url": { "type": "string", "description": "The URL to open" }
                },
                "required": ["url"]
            }),
        }
    }

    async fn call(&self, args: Self::Args) -> Result<Self::Output, Self::Error> {
        let script = format!(
            r#"tell application "Google Chrome"
    activate
    if (count every window) = 0 then
        make new window
    end if
    tell window 1
        make new tab with properties {{URL:"{}"}}
    end tell
end tell"#,
            args.url
        );

        let status = tokio::process::Command::new("osascript")
            .arg("-e")
            .arg(&script)
            .status()
            .await?;

        if !status.success() {
            return Err(ToolError::CommandFailed("Failed to open Chrome tab".into()));
        }

        Ok(format!("Opened {} in Chrome", args.url))
    }
}

// ── Memory Tools ──

pub fn default_memory_path() -> PathBuf {
    dirs::home_dir()
        .unwrap_or_else(|| PathBuf::from("/tmp"))
        .join(".ronge")
        .join("memory")
        .join("memory.md")
}

// ReadMemory

#[derive(Deserialize, Serialize, Clone)]
pub struct ReadMemory {
    #[serde(skip)]
    pub path: PathBuf,
}

impl ReadMemory {
    pub fn new(path: PathBuf) -> Self {
        Self { path }
    }
}

impl Tool for ReadMemory {
    const NAME: &'static str = "read_memory";
    type Args = EmptyArgs;
    type Output = String;
    type Error = ToolError;

    async fn definition(&self, _prompt: String) -> ToolDefinition {
        ToolDefinition {
            name: "read_memory".to_string(),
            description: "Read the persistent memory file. Use to recall stored information about the user.".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {},
                "required": []
            }),
        }
    }

    async fn call(&self, _args: Self::Args) -> Result<Self::Output, Self::Error> {
        match tokio::fs::read_to_string(&self.path).await {
            Ok(content) if content.trim().is_empty() => Ok("Memory is empty.".to_string()),
            Ok(content) => Ok(content),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
                Ok("Memory file does not exist yet. Use save_to_memory to create it.".to_string())
            }
            Err(e) => Err(ToolError::Io(e)),
        }
    }
}

// SaveToMemory

#[derive(Deserialize, Serialize, Clone)]
pub struct SaveToMemory {
    #[serde(skip)]
    pub path: PathBuf,
}

impl SaveToMemory {
    pub fn new(path: PathBuf) -> Self {
        Self { path }
    }
}

#[derive(Deserialize)]
pub struct SaveToMemoryArgs {
    content: String,
}

impl Tool for SaveToMemory {
    const NAME: &'static str = "save_to_memory";
    type Args = SaveToMemoryArgs;
    type Output = String;
    type Error = ToolError;

    async fn definition(&self, _prompt: String) -> ToolDefinition {
        ToolDefinition {
            name: "save_to_memory".to_string(),
            description: "Replace the entire memory file with new content. Use to reorganize or rewrite memory.".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "content": { "type": "string", "description": "Full markdown content to save (replaces existing)" }
                },
                "required": ["content"]
            }),
        }
    }

    async fn call(&self, args: Self::Args) -> Result<Self::Output, Self::Error> {
        if let Some(parent) = self.path.parent() {
            tokio::fs::create_dir_all(parent).await?;
        }
        tokio::fs::write(&self.path, &args.content).await?;
        Ok(format!("Memory saved ({} characters)", args.content.len()))
    }
}

// AppendToMemory

#[derive(Deserialize, Serialize, Clone)]
pub struct AppendToMemory {
    #[serde(skip)]
    pub path: PathBuf,
}

impl AppendToMemory {
    pub fn new(path: PathBuf) -> Self {
        Self { path }
    }
}

#[derive(Deserialize)]
pub struct AppendToMemoryArgs {
    content: String,
}

impl Tool for AppendToMemory {
    const NAME: &'static str = "append_to_memory";
    type Args = AppendToMemoryArgs;
    type Output = String;
    type Error = ToolError;

    async fn definition(&self, _prompt: String) -> ToolDefinition {
        ToolDefinition {
            name: "append_to_memory".to_string(),
            description: "Append new content to the memory file without overwriting existing content.".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "content": { "type": "string", "description": "Content to append to memory" }
                },
                "required": ["content"]
            }),
        }
    }

    async fn call(&self, args: Self::Args) -> Result<Self::Output, Self::Error> {
        if let Some(parent) = self.path.parent() {
            tokio::fs::create_dir_all(parent).await?;
        }

        let existing = match tokio::fs::read_to_string(&self.path).await {
            Ok(c) => c,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => String::new(),
            Err(e) => return Err(ToolError::Io(e)),
        };

        let new_content = if existing.is_empty() {
            args.content.clone()
        } else {
            format!("{}\n\n{}", existing, args.content)
        };

        tokio::fs::write(&self.path, &new_content).await?;
        Ok(format!("Appended to memory ({} characters added)", args.content.len()))
    }
}
