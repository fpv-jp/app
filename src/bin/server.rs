// SPDX-License-Identifier: MPL-2.0

use anyhow::Error;
use axum::{
    extract::{ws::WebSocketUpgrade, State},
    http::{header, HeaderMap, Method, StatusCode, Uri},
    response::IntoResponse,
    routing::get,
    Router,
};
use clap::Parser;
use fpvjp_app::server::{
    handle_connection, new_shared_state, spawn_inactive_cleanup, ClientType, SharedState,
};
use percent_encoding::percent_decode_str;
use std::net::SocketAddr;
use std::path::PathBuf;
use tower_http::cors::{Any, CorsLayer};
use tracing::info;
use tracing_subscriber::prelude::*;

#[derive(Parser, Debug)]
#[clap(about, version, author)]
struct Args {
    /// Address to listen on
    #[clap(long, default_value = "0.0.0.0")]
    host: String,
    /// Port to listen on
    #[clap(short, long, default_value_t = 8443)]
    port: u16,
    /// TLS certificate to use
    #[clap(short, long)]
    cert: Option<String>,
    /// Private key to use
    #[clap(short, long)]
    key: Option<String>,
    /// Enable debug logging for message traffic
    #[clap(long)]
    debug: bool,
    /// Enable keep-alive (disable inactive session cleanup)
    #[clap(long)]
    keep_alive: bool,
}

fn initialize_logging(envvar_name: &str) -> Result<(), Error> {
    tracing_log::LogTracer::init()?;
    let env_filter = tracing_subscriber::EnvFilter::try_from_env(envvar_name)
        .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new("info"));
    let fmt_layer = tracing_subscriber::fmt::layer()
        .with_thread_ids(true)
        .with_target(true)
        .with_span_events(
            tracing_subscriber::fmt::format::FmtSpan::NEW
                | tracing_subscriber::fmt::format::FmtSpan::CLOSE,
        );
    let subscriber = tracing_subscriber::Registry::default()
        .with(env_filter)
        .with(fmt_layer);
    tracing::subscriber::set_global_default(subscriber)?;

    Ok(())
}

#[tokio::main]
async fn main() -> Result<(), Error> {
    let args = Args::parse();

    initialize_logging("WEBRTCSINK_SIGNALLING_SERVER_LOG")?;

    info!(
        "Debug log  : {}",
        if args.debug { "enabled" } else { "disabled" }
    );
    info!(
        "Keep alive : {}",
        if args.keep_alive {
            "enabled"
        } else {
            "disabled"
        }
    );

    let state = new_shared_state(args.debug, args.keep_alive);

    if !args.keep_alive {
        spawn_inactive_cleanup(state.clone());
    }

    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_methods([Method::GET, Method::POST, Method::OPTIONS])
        .allow_headers([header::CONTENT_TYPE]);

    let app = Router::new()
        .route("/signaling", get(ws_handler))
        .fallback(static_file_handler)
        .layer(cors)
        .with_state(state);

    let addr: SocketAddr = format!("{}:{}", args.host, args.port).parse()?;

    if let (Some(cert), Some(key)) = (args.cert, args.key) {
        info!("TLS mode   : enabled");
        let tls_config =
            axum_server::tls_rustls::RustlsConfig::from_pem_file(&cert, &key).await?;
        info!("Listening on: https://{}", addr);
        axum_server::bind_rustls(addr, tls_config)
            .serve(app.into_make_service())
            .await?;
    } else {
        info!("TLS mode   : disabled");
        info!("Listening on: http://{}", addr);
        let listener = tokio::net::TcpListener::bind(addr).await?;
        axum::serve(listener, app).await?;
    }

    Ok(())
}

async fn ws_handler(
    ws: WebSocketUpgrade,
    headers: HeaderMap,
    State(state): State<SharedState>,
) -> impl IntoResponse {
    let protocol_header = headers
        .get("sec-websocket-protocol")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("");

    let client_type = ClientType::from_protocol(protocol_header);

    match client_type {
        Some(ct) => ws
            .protocols([ct.as_str()])
            .on_upgrade(move |socket| handle_connection(socket, ct, state)),
        None => ws.on_upgrade(|mut socket| async move {
            let _ = socket.send(axum::extract::ws::Message::Close(None)).await;
        }),
    }
}

const VRX_DIR: &str = "vrx";

const VALID_EXTENSIONS: &[(&str, &str)] = &[
    (".html", "text/html"),
    (".ico", "image/x-icon"),
    (".js", "application/javascript"),
    (".css", "text/css"),
    (".jpg", "image/jpeg"),
    (".png", "image/png"),
    (".gif", "image/gif"),
    (".svg", "image/svg+xml"),
    (".wasm", "application/wasm"),
];

fn get_mime_type(ext: &str) -> Option<&'static str> {
    VALID_EXTENSIONS
        .iter()
        .find(|(e, _)| *e == ext)
        .map(|(_, mime)| *mime)
}

async fn static_file_handler(uri: Uri) -> impl IntoResponse {
    let path = uri.path();
    let decoded_path = percent_decode_str(path)
        .decode_utf8_lossy()
        .to_string();

    let mut pathname = decoded_path;
    if pathname.ends_with('/') {
        pathname.push_str("index.html");
    }

    // Normalize and prevent directory traversal
    let sanitized = pathname.replace("../", "");
    let file_path = PathBuf::from(VRX_DIR).join(sanitized.trim_start_matches('/'));

    // Ensure path stays within VRX_DIR
    let canonical_base = match std::fs::canonicalize(VRX_DIR) {
        Ok(p) => p,
        Err(_) => {
            return (StatusCode::INTERNAL_SERVER_ERROR, "Static directory not found")
                .into_response();
        }
    };
    let canonical_file = match std::fs::canonicalize(&file_path) {
        Ok(p) => p,
        Err(_) => {
            return (StatusCode::NOT_FOUND, "Not Found").into_response();
        }
    };
    if !canonical_file.starts_with(&canonical_base) {
        return (StatusCode::FORBIDDEN, "Forbidden").into_response();
    }

    // Validate extension
    let ext = file_path
        .extension()
        .and_then(|e| e.to_str())
        .map(|e| format!(".{}", e.to_lowercase()))
        .unwrap_or_default();

    let mime = match get_mime_type(&ext) {
        Some(m) => m,
        None => {
            return (StatusCode::FORBIDDEN, "Forbidden").into_response();
        }
    };

    // Read and serve file
    match tokio::fs::read(&canonical_file).await {
        Ok(contents) => (StatusCode::OK, [(header::CONTENT_TYPE, mime)], contents).into_response(),
        Err(_) => (StatusCode::INTERNAL_SERVER_ERROR, "Internal Server Error").into_response(),
    }
}
