use axum::{routing::get, Router};
use std::{net::SocketAddr, sync::Arc};
use tokio::net::TcpListener;
use tokio::sync::Mutex;

// Register modules
mod llm;
mod routes;
mod state;
mod logic;
mod tools; // <--- ADDED THIS

use state::AppState;

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt::init();

    // Initialize State
    let state = Arc::new(Mutex::new(AppState::new()));

    // Setup Router
    let app = Router::new()
        .route("/ws", get(routes::ws_handler))
        .with_state(state);

    let addr = SocketAddr::from(([127, 0, 0, 1], 3000));
    println!("🚀 Rust Server listening on {}", addr);

    let listener = TcpListener::bind(addr).await.unwrap();
    axum::serve(listener, app).await.unwrap();
}