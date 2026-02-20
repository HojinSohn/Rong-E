use crate::google_tools::{
    CreateCalendarEvent, DeleteCalendarEvent, GetGmailMessage, GetGmailThread,
    ListCalendarEvents, ManageSpreadsheet, SearchGmail, UpdateCalendarEvent,
};
use rig::completion::Chat;
use rig::client::{CompletionClient, ProviderClient};
use rig::message::{Message as RigMessage, UserContent};
use rig::completion::ToolDefinition;
use rig::tool::Tool;
use rig::{providers::{anthropic, gemini, ollama, openai}, OneOrMany};
use serde::{Deserialize, Serialize};
use thiserror::Error;

// ─────────────────────────────────────────────
// Error
// ─────────────────────────────────────────────

#[derive(Debug, Error)]
#[error("{0}")]
pub struct GoogleAgentError(pub String);

// ─────────────────────────────────────────────
// System prompt for the Google sub-agent
// ─────────────────────────────────────────────

const SYSTEM_PROMPT: &str =
    include_str!("../prompts/google_agent_prompt.txt");

// ─────────────────────────────────────────────
// Tool struct
// ─────────────────────────────────────────────

/// A single tool that the main agent uses to delegate all Google Workspace
/// tasks (Gmail, Calendar, Sheets) to a dedicated sub-agent.
#[derive(Deserialize, Serialize, Clone)]
pub struct GoogleSubAgent {
    #[serde(skip)]
    pub access_token: String,
    /// LLM API key – same provider the main agent is using.
    #[serde(skip)]
    pub api_key: String,
    #[serde(skip)]
    pub provider: String,
    #[serde(skip)]
    pub model: String,
}

impl GoogleSubAgent {
    pub fn new(
        access_token: String,
        api_key: String,
        provider: String,
        model: String,
    ) -> Self {
        Self {
            access_token,
            api_key,
            provider,
            model,
        }
    }
}

#[derive(Deserialize, Serialize)]
pub struct GoogleSubAgentArgs {
    task: String,
}

impl Tool for GoogleSubAgent {
    const NAME: &'static str = "google_agent";
    type Args = GoogleSubAgentArgs;
    type Output = String;
    type Error = GoogleAgentError;

    async fn definition(&self, _prompt: String) -> ToolDefinition {
        ToolDefinition {
            name: "google_agent".to_string(),
            description: "\
Delegate any Gmail, Google Calendar, or Google Sheets task to a specialized sub-agent. \
Describe the full task in natural language. The sub-agent will use multiple tool calls as needed.\n\
Capabilities:\n\
- Gmail: search messages, read full message/thread content (read-only)\n\
- Google Calendar: list, create, update, or delete events\n\
- Google Sheets: read, append, update data, or create new spreadsheets\n\
\n\
Examples:\n\
- 'Search Gmail for unread emails from alice@example.com and summarize them'\n\
- 'List my calendar events for the next 3 days'\n\
- 'Create a calendar event: Team Standup on 2024-02-01 at 9am for 30 minutes'\n\
- 'Read range A1:D20 from spreadsheet ID 1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgVE2upms'"
                .to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "task": {
                        "type": "string",
                        "description": "The complete Google Workspace task. Be specific: include email addresses, date ranges, spreadsheet IDs, ranges, etc."
                    }
                },
                "required": ["task"]
            }),
        }
    }

    async fn call(&self, args: Self::Args) -> Result<Self::Output, Self::Error> {
        run_google_agent(
            &self.provider,
            &self.api_key,
            &self.model,
            &self.access_token,
            &args.task,
        )
        .await
        .map_err(GoogleAgentError)
    }
}

// ─────────────────────────────────────────────
// Internal: build and run the sub-agent
// ─────────────────────────────────────────────

async fn run_google_agent(
    provider: &str,
    api_key: &str,
    model: &str,
    access_token: &str,
    task: &str,
) -> Result<String, String> {
    let t = access_token.to_string();
    let user_msg = RigMessage::User {
        content: OneOrMany::one(UserContent::text(task)),
    };

    match provider {
        "gemini" => {
            let client = gemini::Client::new(api_key).map_err(|e| e.to_string())?;
            let agent = client
                .agent(model)
                .preamble(SYSTEM_PROMPT)
                .tool(SearchGmail::new(t.clone()))
                .tool(GetGmailMessage::new(t.clone()))
                .tool(GetGmailThread::new(t.clone()))
                .tool(ListCalendarEvents::new(t.clone()))
                .tool(CreateCalendarEvent::new(t.clone()))
                .tool(UpdateCalendarEvent::new(t.clone()))
                .tool(DeleteCalendarEvent::new(t.clone()))
                .tool(ManageSpreadsheet::new(t.clone()))
                .build();
            agent.chat(user_msg, vec![]).await.map_err(|e| e.to_string())
        }

        "openai" => {
            let client: openai::Client =
                openai::Client::new(api_key).map_err(|e| e.to_string())?;
            let agent = client
                .agent(model)
                .preamble(SYSTEM_PROMPT)
                .tool(SearchGmail::new(t.clone()))
                .tool(GetGmailMessage::new(t.clone()))
                .tool(GetGmailThread::new(t.clone()))
                .tool(ListCalendarEvents::new(t.clone()))
                .tool(CreateCalendarEvent::new(t.clone()))
                .tool(UpdateCalendarEvent::new(t.clone()))
                .tool(DeleteCalendarEvent::new(t.clone()))
                .tool(ManageSpreadsheet::new(t.clone()))
                .build();
            agent.chat(user_msg, vec![]).await.map_err(|e| e.to_string())
        }

        "anthropic" => {
            let client: anthropic::Client =
                anthropic::Client::new(api_key).map_err(|e| e.to_string())?;
            let agent = client
                .agent(model)
                .preamble(SYSTEM_PROMPT)
                .tool(SearchGmail::new(t.clone()))
                .tool(GetGmailMessage::new(t.clone()))
                .tool(GetGmailThread::new(t.clone()))
                .tool(ListCalendarEvents::new(t.clone()))
                .tool(CreateCalendarEvent::new(t.clone()))
                .tool(UpdateCalendarEvent::new(t.clone()))
                .tool(DeleteCalendarEvent::new(t.clone()))
                .tool(ManageSpreadsheet::new(t.clone()))
                .build();
            agent.chat(user_msg, vec![]).await.map_err(|e| e.to_string())
        }

        "ollama" => {
            let client = ollama::Client::from_env();
            let agent = client
                .agent(model)
                .preamble(SYSTEM_PROMPT)
                .tool(SearchGmail::new(t.clone()))
                .tool(GetGmailMessage::new(t.clone()))
                .tool(GetGmailThread::new(t.clone()))
                .tool(ListCalendarEvents::new(t.clone()))
                .tool(CreateCalendarEvent::new(t.clone()))
                .tool(UpdateCalendarEvent::new(t.clone()))
                .tool(DeleteCalendarEvent::new(t.clone()))
                .tool(ManageSpreadsheet::new(t.clone()))
                .build();
            let res = agent.chat(user_msg, vec![]).await;
            res.map_err(|e| e.to_string())
        }

        p => Err(format!("Unsupported provider for Google sub-agent: {}", p)),
    }
}
