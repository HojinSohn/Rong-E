
use crate::logic;

use crate::state::SharedState;
use axum::{
    extract::{ws::{Message, WebSocket, WebSocketUpgrade}, State},
    response::IntoResponse,
};
use futures::StreamExt; // Only need StreamExt here for receiver.next()
use rig::message::Message as RigMessage;

pub async fn ws_handler(
    ws: WebSocketUpgrade,
    State(state): State<SharedState>,
) -> impl IntoResponse {
    ws.on_upgrade(|socket| handle_socket(socket, state))
}

async fn handle_socket(socket: WebSocket, state: SharedState) {
    // Split socket into sender/receiver
    let (mut sender, mut receiver) = socket.split();
    println!("✅ Client connected");

    // Initialize session history
    let mut chat_history: Vec<RigMessage> = Vec::new();

    // The Main Loop
    while let Some(Ok(msg)) = receiver.next().await {
        if let Message::Text(text) = msg {
            // Delegate all logic to the new module
            logic::process_message(
                &text, 
                &mut sender, 
                &mut chat_history, 
                &state
            ).await;
        }
    }

    println!("🔌 Client disconnected");
}