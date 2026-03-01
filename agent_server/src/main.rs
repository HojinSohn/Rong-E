use axum::{routing::get, Router};
use std::{net::SocketAddr, sync::Arc};
use tokio::net::TcpListener;
use tokio::sync::Mutex;

// Register modules
mod google_agent;
mod google_auth;
mod google_tools;
mod llm;
mod logic;
mod mcp_proxy;
mod routes;
mod state;
mod tools;

use state::AppState;

/// When the Swift app launches the server as a subprocess, stdio pipes may be
/// set to O_NONBLOCK.  Any `println!` from a tokio worker thread then gets
/// EAGAIN, which Rust's standard library turns into a panic.  Reset the fds
/// to blocking mode before the tokio runtime spins up worker threads.
#[cfg(unix)]
fn fix_stdio_blocking() {
    use std::os::fd::AsRawFd;
    for fd in [
        std::io::stdout().as_raw_fd(),
        std::io::stderr().as_raw_fd(),
    ] {
        unsafe {
            let flags = libc::fcntl(fd, libc::F_GETFL);
            if flags >= 0 {
                libc::fcntl(fd, libc::F_SETFL, flags & !libc::O_NONBLOCK);
            }
        }
    }
}

/// Entry point: fix stdio blocking BEFORE the tokio runtime creates any worker
/// threads, then hand off to the async runtime.
fn main() {
    #[cfg(unix)]
    fix_stdio_blocking();

    // rig's ollama::Client::from_env() panics if OLLAMA_API_BASE_URL is absent.
    // Default to localhost before any threads start (safe single-threaded context).
    if std::env::var("OLLAMA_API_BASE_URL").is_err() {
        unsafe { std::env::set_var("OLLAMA_API_BASE_URL", "http://localhost:11434") };
    }

    tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()
        .expect("Failed to build tokio runtime")
        .block_on(async_main());
}

async fn async_main() {
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