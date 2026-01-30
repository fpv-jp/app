// SPDX-License-Identifier: MPL-2.0

use axum::extract::ws::{Message, WebSocket};
use serde_json::{json, Value};
use std::collections::HashMap;
use std::sync::Arc;
use std::time::Instant;
use tokio::sync::{mpsc, RwLock};
use tracing::{error, info, warn};

// Message types matching server.js protocol
const SENDER_SESSION_ID: u32 = 100;
const SENDER_RECEIVER_CLOSE: u32 = 108;
const SENDER_ERROR: u32 = 109;
const RECEIVER_SESSION_ID: u32 = 200;
const RECEIVER_SENDER_LIST: u32 = 201;
const RECEIVER_SENDER_CLOSE: u32 = 208;
const RECEIVER_ERROR: u32 = 209;

const INACTIVE_TIMEOUT_SECS: u64 = 60 * 60; // 1 hour

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ClientType {
    Sender,
    Receiver,
}

impl ClientType {
    pub fn from_protocol(protocol: &str) -> Option<Self> {
        match protocol.to_lowercase().as_str() {
            "sender" => Some(ClientType::Sender),
            "receiver" => Some(ClientType::Receiver),
            _ => None,
        }
    }

    pub fn as_str(&self) -> &'static str {
        match self {
            ClientType::Sender => "sender",
            ClientType::Receiver => "receiver",
        }
    }
}

struct Client {
    session_id: String,
    protocol: ClientType,
    last_active: Instant,
    sender: mpsc::UnboundedSender<String>,
}

pub struct AppState {
    clients: HashMap<String, Client>,
    pair_map: HashMap<String, String>,
    pub debug: bool,
    pub keep_alive: bool,
}

pub type SharedState = Arc<RwLock<AppState>>;

pub fn new_shared_state(debug: bool, keep_alive: bool) -> SharedState {
    Arc::new(RwLock::new(AppState {
        clients: HashMap::new(),
        pair_map: HashMap::new(),
        debug,
        keep_alive,
    }))
}

fn get_senders(state: &AppState) -> Vec<String> {
    state
        .clients
        .values()
        .filter(|c| c.protocol == ClientType::Sender)
        .map(|c| c.session_id.clone())
        .collect()
}

fn notify_sender_list(state: &AppState) {
    let senders = get_senders(state);
    let msg = json!({
        "type": RECEIVER_SENDER_LIST,
        "senders": senders,
    })
    .to_string();

    for client in state.clients.values() {
        if client.protocol == ClientType::Receiver {
            let _ = client.sender.send(msg.clone());
        }
    }
}

fn find_client_sender(
    state: &AppState,
    protocol: ClientType,
    session_id: &str,
) -> Option<mpsc::UnboundedSender<String>> {
    state
        .clients
        .values()
        .find(|c| c.protocol == protocol && c.session_id == session_id)
        .map(|c| c.sender.clone())
}

fn get_target_protocol(current: ClientType) -> ClientType {
    match current {
        ClientType::Receiver => ClientType::Sender,
        ClientType::Sender => ClientType::Receiver,
    }
}

fn get_target_session_id(data: &Value, current_protocol: ClientType) -> Option<String> {
    let key = match current_protocol {
        ClientType::Receiver => "ws1Id",
        ClientType::Sender => "ws2Id",
    };
    data.get(key).and_then(|v| v.as_str()).map(String::from)
}

fn send_error(state: &AppState, session_id: &str, protocol: ClientType, message: &str) {
    let error_type = match protocol {
        ClientType::Sender => SENDER_ERROR,
        ClientType::Receiver => RECEIVER_ERROR,
    };
    let msg = json!({
        "type": error_type,
        "message": message,
    })
    .to_string();

    if let Some(client) = state.clients.get(session_id) {
        let _ = client.sender.send(msg);
    }
}

pub async fn handle_connection(
    mut socket: WebSocket,
    protocol: ClientType,
    state: SharedState,
) {
    let session_id = nanoid::nanoid!(8);
    let (tx, mut rx) = mpsc::unbounded_channel::<String>();

    info!(
        "Connected {} - sessionId: {}",
        protocol.as_str(),
        session_id
    );

    // Register client and send initial messages
    {
        let mut s = state.write().await;
        s.clients.insert(
            session_id.clone(),
            Client {
                session_id: session_id.clone(),
                protocol,
                last_active: Instant::now(),
                sender: tx.clone(),
            },
        );

        match protocol {
            ClientType::Sender => {
                notify_sender_list(&s);
                let msg = json!({
                    "type": SENDER_SESSION_ID,
                    "sessionId": session_id,
                })
                .to_string();
                let _ = tx.send(msg);
            }
            ClientType::Receiver => {
                let senders = get_senders(&s);
                let msg = json!({
                    "type": RECEIVER_SESSION_ID,
                    "sessionId": session_id,
                    "senders": senders,
                })
                .to_string();
                let _ = tx.send(msg);
            }
        }
    }

    // Main loop: handle both incoming WS messages and outgoing channel messages
    loop {
        tokio::select! {
            Some(msg) = rx.recv() => {
                if socket.send(Message::Text(msg.into())).await.is_err() {
                    break;
                }
            }
            msg = socket.recv() => {
                match msg {
                    Some(Ok(Message::Text(text))) => {
                        handle_message(&session_id, protocol, &text, &state).await;
                    }
                    Some(Ok(Message::Close(_))) | None => {
                        break;
                    }
                    Some(Ok(Message::Ping(data))) => {
                        if socket.send(Message::Pong(data)).await.is_err() {
                            break;
                        }
                    }
                    Some(Ok(_)) => continue,
                    Some(Err(e)) => {
                        warn!(session_id = %session_id, "recv error: {}", e);
                        break;
                    }
                }
            }
        }
    }

    handle_disconnect(&session_id, protocol, &state).await;
}

async fn handle_message(
    session_id: &str,
    protocol: ClientType,
    raw_message: &str,
    state: &SharedState,
) {
    let mut s = state.write().await;

    if let Some(client) = s.clients.get_mut(session_id) {
        client.last_active = Instant::now();
    }

    let data: Value = match serde_json::from_str(raw_message) {
        Ok(v) => v,
        Err(err) => {
            error!("Error: {}\nMessage: {}", err, raw_message);
            send_error(&s, session_id, protocol, &err.to_string());
            return;
        }
    };

    if s.debug {
        info!("Incoming from {}: {}", protocol.as_str(), data);
    }

    let target_protocol = get_target_protocol(protocol);
    let target_session_id = get_target_session_id(&data, protocol);

    if let Some(ref target_id) = target_session_id {
        s.pair_map
            .insert(session_id.to_string(), target_id.clone());
        info!("Pairing updated: {} -> {}", session_id, target_id);
    }

    if let Some(ref target_id) = target_session_id {
        if let Some(target_tx) = find_client_sender(&s, target_protocol, target_id) {
            let _ = target_tx.send(raw_message.to_string());
            info!(
                "Relayed: {} -> {}",
                protocol.as_str(),
                target_protocol.as_str()
            );
            return;
        }
    }

    send_error(&s, session_id, protocol, "Target not found");
}

async fn handle_disconnect(session_id: &str, protocol: ClientType, state: &SharedState) {
    info!(
        "Disconnected {} - sessionId: {}",
        protocol.as_str(),
        session_id
    );

    let mut s = state.write().await;

    if let Some(target_session_id) = s.pair_map.remove(session_id) {
        let target_protocol = get_target_protocol(protocol);
        let close_type = match protocol {
            ClientType::Receiver => SENDER_RECEIVER_CLOSE,
            ClientType::Sender => RECEIVER_SENDER_CLOSE,
        };

        if let Some(target_tx) = find_client_sender(&s, target_protocol, &target_session_id) {
            let msg = json!({ "type": close_type }).to_string();
            let _ = target_tx.send(msg);
            info!("Close notification sent to: {}", target_session_id);
        }

        s.pair_map.remove(&target_session_id);
    }

    s.clients.remove(session_id);

    if protocol == ClientType::Sender {
        notify_sender_list(&s);
    }
}

pub fn spawn_inactive_cleanup(state: SharedState) {
    tokio::spawn(async move {
        let mut interval = tokio::time::interval(std::time::Duration::from_secs(60));
        loop {
            interval.tick().await;
            let mut s = state.write().await;
            let now = Instant::now();
            let inactive: Vec<String> = s
                .clients
                .iter()
                .filter(|(_, c)| {
                    now.duration_since(c.last_active).as_secs() > INACTIVE_TIMEOUT_SECS
                })
                .map(|(id, _)| id.clone())
                .collect();

            for session_id in inactive {
                info!("Session {} removed due to inactivity", session_id);
                if let Some(target_id) = s.pair_map.remove(&session_id) {
                    s.pair_map.remove(&target_id);
                }
                s.clients.remove(&session_id);
            }
        }
    });
}
