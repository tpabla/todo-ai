mod rpc;

use clap::Parser;
use rpc::{Handler, RpcRequest, RpcResponse};
use std::path::PathBuf;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::UnixListener;

#[derive(Parser)]
#[command(name = "todo-ai-backend")]
struct Args {
    #[arg(long)]
    socket: PathBuf,
}

#[tokio::main]
async fn main() {
    let args = Args::parse();
    let socket_path = &args.socket;

    // Clean up stale socket file
    if socket_path.exists() {
        std::fs::remove_file(socket_path).expect("Failed to remove stale socket");
    }

    let listener = UnixListener::bind(socket_path).expect("Failed to bind Unix socket");

    // Signal readiness to parent process via stdout
    println!("{}", socket_path.display());

    // Accept one connection
    let (stream, _) = listener
        .accept()
        .await
        .expect("Failed to accept connection");

    let (reader, mut writer) = stream.into_split();
    let mut lines = BufReader::new(reader).lines();
    let handler = Handler::new();

    loop {
        let line = match lines.next_line().await {
            Ok(Some(line)) => line,
            Ok(None) => break, // EOF — client disconnected
            Err(e) => {
                eprintln!("Read error: {e}");
                break;
            }
        };

        if line.trim().is_empty() {
            continue;
        }

        let request: RpcRequest = match serde_json::from_str(&line) {
            Ok(r) => r,
            Err(e) => {
                let error_response = RpcResponse::error(
                    None,
                    -32700,
                    format!("Parse error: {e}"),
                );
                let mut out = serde_json::to_string(&error_response).unwrap();
                out.push('\n');
                let _ = writer.write_all(out.as_bytes()).await;
                continue;
            }
        };

        let is_shutdown = request.method == "shutdown";

        // Notifications (no id) don't get a response
        let is_notification = request.id.is_none();
        let response = handler.dispatch(request);

        if !is_notification {
            let mut out = serde_json::to_string(&response).unwrap();
            out.push('\n');
            if let Err(e) = writer.write_all(out.as_bytes()).await {
                eprintln!("Write error: {e}");
                break;
            }
        }

        if is_shutdown {
            break;
        }
    }

    // Clean up socket file
    let _ = std::fs::remove_file(socket_path);
}
