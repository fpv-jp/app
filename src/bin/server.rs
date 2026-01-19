// SPDX-License-Identifier: MPL-2.0

use anyhow::Error;
use axum::{
    extract::{ws::WebSocketUpgrade, Path, State},
    http::{header, HeaderMap, Method, StatusCode, Uri},
    response::IntoResponse,
    routing::get,
    Router,
};
use clap::Parser;
use fpvjp_app::server::{
    handle_connection, new_shared_state, spawn_inactive_cleanup, AuthInfo, ClientType, SharedState,
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
    /// Enable PIN-based access control for receivers
    #[clap(long)]
    pin_auth: bool,
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
    // musl ビルドで aws-lc-rs と ring が両方 dependency tree に入るため明示的に ring を選択
    rustls::crypto::ring::default_provider()
        .install_default()
        .ok();

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
    info!(
        "PIN auth   : {}",
        if args.pin_auth { "enabled" } else { "disabled" }
    );

    let state = new_shared_state(args.debug, args.keep_alive, args.pin_auth);

    if !args.keep_alive {
        spawn_inactive_cleanup(state.clone());
    }

    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_methods([Method::GET, Method::POST, Method::OPTIONS])
        .allow_headers([header::CONTENT_TYPE, header::RANGE])
        .expose_headers([header::CONTENT_RANGE, header::ACCEPT_RANGES]);

    let app = Router::new()
        .route("/signaling", get(ws_handler))
        .route("/tiles/{filename}", get(gcs_proxy_handler))
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

    let auth = AuthInfo {
        sub: headers.get("x-auth-sub").and_then(|v| v.to_str().ok()).map(String::from),
        email: headers.get("x-auth-email").and_then(|v| v.to_str().ok()).map(String::from),
        name: headers.get("x-auth-name").and_then(|v| v.to_str().ok()).map(String::from),
    };

    match client_type {
        Some(ct) => ws
            .protocols([ct.as_str()])
            .on_upgrade(move |socket| handle_connection(socket, ct, auth, state)),
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
    (".jpeg", "image/jpeg"),
    (".png", "image/png"),
    (".gif", "image/gif"),
    (".webp", "image/webp"),
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

    // Extensionless paths are SPA routes — serve index.html
    let ext = file_path
        .extension()
        .and_then(|e| e.to_str())
        .map(|e| format!(".{}", e.to_lowercase()))
        .unwrap_or_default();

    let (resolved_path, mime) = if ext.is_empty() {
        (PathBuf::from(VRX_DIR).join("index.html"), "text/html")
    } else {
        let m = match get_mime_type(&ext) {
            Some(m) => m,
            None => return (StatusCode::FORBIDDEN, "Forbidden").into_response(),
        };
        (file_path, m)
    };

    // Ensure path stays within VRX_DIR
    let canonical_base = match std::fs::canonicalize(VRX_DIR) {
        Ok(p) => p,
        Err(_) => {
            return (StatusCode::INTERNAL_SERVER_ERROR, "Static directory not found")
                .into_response();
        }
    };
    let canonical_file = match std::fs::canonicalize(&resolved_path) {
        Ok(p) => p,
        Err(_) => {
            return (StatusCode::NOT_FOUND, "Not Found").into_response();
        }
    };
    if !canonical_file.starts_with(&canonical_base) {
        return (StatusCode::FORBIDDEN, "Forbidden").into_response();
    }

    // Read and serve file
    match tokio::fs::read(&canonical_file).await {
        Ok(contents) => (StatusCode::OK, [(header::CONTENT_TYPE, mime)], contents).into_response(),
        Err(_) => (StatusCode::INTERNAL_SERVER_ERROR, "Internal Server Error").into_response(),
    }
}

const GCS_BUCKET: &str = "fpv-japan-pmtiles";
const GCS_METADATA_TOKEN_URL: &str =
    "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token";

async fn fetch_gcs_token() -> Option<String> {
    // ローカル開発時: GCS_TOKEN 環境変数から直接取得
    if let Ok(token) = std::env::var("GCS_TOKEN") {
        if !token.is_empty() {
            return Some(token);
        }
    }
    // 本番 (GCE): メタデータサーバーから取得
    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(2))
        .build()
        .ok()?;
    let resp = client
        .get(GCS_METADATA_TOKEN_URL)
        .header("Metadata-Flavor", "Google")
        .send()
        .await
        .ok()?;
    let json: serde_json::Value = resp.json().await.ok()?;
    json["access_token"].as_str().map(|s| s.to_string())
}

async fn gcs_proxy_handler(Path(filename): Path<String>, req_headers: HeaderMap) -> impl IntoResponse {
    // ファイル名にパストラバーサルが含まれていないか確認
    if filename.contains("..") || filename.contains('/') {
        return (StatusCode::BAD_REQUEST, "Invalid filename").into_response();
    }

    let gcs_url = format!("https://storage.googleapis.com/{GCS_BUCKET}/{filename}");

    let client = match reqwest::Client::builder().build() {
        Ok(c) => c,
        Err(_) => return (StatusCode::INTERNAL_SERVER_ERROR, "Client error").into_response(),
    };

    let mut builder = client.get(&gcs_url);

    // GCE メタデータサーバーからトークン取得（ローカル開発時は失敗してもスキップ）
    if let Some(token) = fetch_gcs_token().await {
        builder = builder.header(reqwest::header::AUTHORIZATION, format!("Bearer {token}"));
    }

    // Range ヘッダーを透過
    if let Some(range) = req_headers.get(header::RANGE) {
        if let Ok(v) = range.to_str() {
            builder = builder.header(reqwest::header::RANGE, v);
        }
    }

    let gcs_resp = match builder.send().await {
        Ok(r) => r,
        Err(_) => return (StatusCode::BAD_GATEWAY, "GCS request failed").into_response(),
    };

    let status = StatusCode::from_u16(gcs_resp.status().as_u16()).unwrap_or(StatusCode::OK);

    let mut resp_headers = HeaderMap::new();
    for key in &[header::CONTENT_TYPE, header::CONTENT_RANGE, header::ACCEPT_RANGES, header::CONTENT_LENGTH] {
        if let Some(v) = gcs_resp.headers().get(key) {
            resp_headers.insert(key.clone(), v.clone());
        }
    }

    let body = match gcs_resp.bytes().await {
        Ok(b) => b,
        Err(_) => return (StatusCode::BAD_GATEWAY, "GCS read failed").into_response(),
    };

    (status, resp_headers, body).into_response()
}
