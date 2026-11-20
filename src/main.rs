mod storage;

use axum::{
    extract::State,
    http::{header::AUTHORIZATION, HeaderMap, StatusCode},
    routing::{get, post},
    Json, Router,
};
use base64::Engine as _;
use rand_core::{OsRng, RngCore};
use serde::Deserialize;
use serde_json::{json, Value};
use std::{
    sync::{Arc, Mutex},
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};
use storage::{Notification, Subscription};
use tower_http::services::ServeDir;
use web_push::{
    ContentEncoding, IsahcWebPushClient, SubscriptionInfo, VapidSignatureBuilder, WebPushClient,
    WebPushError, WebPushMessageBuilder,
};

/// Web Push payloads top out at about 3800 bytes, so long text is cut here.
const MAX_TITLE: usize = 120;
const MAX_BODY: usize = 600;
const PAIR_TTL: Duration = Duration::from_secs(600);
const PAIR_MAX_ATTEMPTS: u32 = 5;

struct Pairing {
    code: String,
    expires: Instant,
    attempts: u32,
}

struct AppState {
    public_key: String,
    private_key: String,
    subject: String,
    /// Admin token: sends notifications and issues pairing codes. Lives only on the Mac.
    token: String,
    pairing: Mutex<Option<Pairing>>,
}

type Shared = Arc<AppState>;

fn env(name: &str) -> String {
    std::env::var(name).unwrap_or_else(|_| panic!("falta la variable {name} (revisa .env y scripts/run-server.sh)"))
}

#[tokio::main]
async fn main() {
    dotenvy::dotenv().ok();
    let state = Arc::new(AppState {
        public_key: env("VAPID_PUBLIC_KEY"),
        private_key: env("VAPID_PRIVATE_KEY"),
        subject: env("VAPID_SUBJECT"),
        token: env("NOTIFY_TOKEN"),
        pairing: Mutex::new(None),
    });
    let port = std::env::var("PORT").unwrap_or_else(|_| "3000".into());
    // Solo localhost por defecto: el túnel (cloudflared) se conecta desde la misma máquina.
    let bind = std::env::var("BIND").unwrap_or_else(|_| "127.0.0.1".into());

    let app = Router::new()
        .route("/api/health", get(|| async { "ok" }))
        .route("/api/vapid-public-key", get(public_key))
        .route("/api/pair/new", post(pair_new))
        .route("/api/pair", post(pair))
        .route("/api/subscribe", post(subscribe))
        .route("/api/notifications", get(notifications))
        .route("/api/status", get(status))
        .route("/api/notify", post(notify))
        .route("/api/test", post(test_push))
        .fallback_service(ServeDir::new("public"))
        .with_state(state);

    let listener = tokio::net::TcpListener::bind(format!("{bind}:{port}")).await.unwrap();
    println!("Escuchando en http://{bind}:{port}");
    axum::serve(listener, app).await.unwrap();
}

// ---------- auth ----------

fn bearer(headers: &HeaderMap) -> Option<&str> {
    headers
        .get(AUTHORIZATION)
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.strip_prefix("Bearer "))
}

fn ct_eq(a: &[u8], b: &[u8]) -> bool {
    a.len() == b.len() && a.iter().zip(b).fold(0u8, |acc, (x, y)| acc | (x ^ y)) == 0
}

fn is_admin(st: &AppState, headers: &HeaderMap) -> bool {
    bearer(headers).map_or(false, |t| ct_eq(t.as_bytes(), st.token.as_bytes()))
}

/// Admin token or a device token issued by pairing (the iPhone).
fn is_member(st: &AppState, headers: &HeaderMap) -> bool {
    is_admin(st, headers) || bearer(headers).map_or(false, storage::has_device)
}

fn random_token() -> String {
    let mut bytes = [0u8; 32];
    OsRng.fill_bytes(&mut bytes);
    base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(bytes)
}

// ---------- handlers ----------

async fn public_key(State(st): State<Shared>) -> String {
    st.public_key.clone()
}

/// Issues a one-time 8-digit code, valid 10 minutes. Called from the Mac (scripts/tunnel.sh).
async fn pair_new(State(st): State<Shared>, headers: HeaderMap) -> Result<Json<Value>, StatusCode> {
    if !is_admin(&st, &headers) {
        return Err(StatusCode::UNAUTHORIZED);
    }
    let code = format!("{:08}", OsRng.next_u32() % 100_000_000);
    *st.pairing.lock().unwrap() = Some(Pairing {
        code: code.clone(),
        expires: Instant::now() + PAIR_TTL,
        attempts: 0,
    });
    Ok(Json(json!({ "code": code, "expiresIn": PAIR_TTL.as_secs() })))
}

#[derive(Deserialize)]
struct PairReq {
    code: String,
}

/// The iPhone trades the code for its own device token. Codes die after one use,
/// after 10 minutes, or after 5 wrong guesses.
async fn pair(State(st): State<Shared>, Json(req): Json<PairReq>) -> Result<Json<Value>, StatusCode> {
    let mut guard = st.pairing.lock().unwrap();
    let Some(p) = guard.as_mut() else {
        return Err(StatusCode::UNAUTHORIZED);
    };
    if Instant::now() > p.expires || p.attempts >= PAIR_MAX_ATTEMPTS {
        *guard = None;
        return Err(StatusCode::UNAUTHORIZED);
    }
    if !ct_eq(req.code.trim().as_bytes(), p.code.as_bytes()) {
        p.attempts += 1;
        return Err(StatusCode::UNAUTHORIZED);
    }
    *guard = None;
    drop(guard);
    let token = random_token();
    storage::add_device(&token);
    Ok(Json(json!({ "token": token })))
}

async fn subscribe(
    State(st): State<Shared>,
    headers: HeaderMap,
    Json(sub): Json<Subscription>,
) -> StatusCode {
    if !is_member(&st, &headers) {
        return StatusCode::UNAUTHORIZED;
    }
    storage::add_subscription(sub);
    StatusCode::CREATED
}

async fn notifications(
    State(st): State<Shared>,
    headers: HeaderMap,
) -> Result<Json<Vec<Notification>>, StatusCode> {
    if !is_member(&st, &headers) {
        return Err(StatusCode::UNAUTHORIZED);
    }
    Ok(Json(storage::list_notifications()))
}

async fn status(State(st): State<Shared>, headers: HeaderMap) -> Result<Json<Value>, StatusCode> {
    if !is_admin(&st, &headers) {
        return Err(StatusCode::UNAUTHORIZED);
    }
    Ok(Json(json!({
        "subscriptions": storage::list_subscriptions().len(),
        "devices": storage::device_count(),
        "notifications": storage::list_notifications().len(),
    })))
}

#[derive(Deserialize)]
struct NotifyReq {
    title: String,
    #[serde(default)]
    body: String,
    /// Same tag = the new notification replaces the old one (e.g. one per agent thread).
    #[serde(default)]
    tag: Option<String>,
}

async fn notify(
    State(st): State<Shared>,
    headers: HeaderMap,
    Json(req): Json<NotifyReq>,
) -> Result<Json<Value>, StatusCode> {
    if !is_admin(&st, &headers) {
        return Err(StatusCode::UNAUTHORIZED);
    }
    let (sent, failed) = dispatch_push(&st, req.title, req.body, req.tag).await;
    Ok(Json(json!({ "sent": sent, "failed": failed })))
}

async fn test_push(State(st): State<Shared>, headers: HeaderMap) -> StatusCode {
    if !is_member(&st, &headers) {
        return StatusCode::UNAUTHORIZED;
    }
    tokio::spawn(async move {
        tokio::time::sleep(Duration::from_secs(5)).await;
        dispatch_push(&st, "Prueba".into(), "Notificación de prueba".into(), None).await;
    });
    StatusCode::ACCEPTED
}

// ---------- push ----------

fn truncate(s: &str, max: usize) -> String {
    if s.chars().count() <= max {
        return s.to_string();
    }
    let mut out: String = s.chars().take(max - 1).collect();
    out.push('…');
    out
}

/// Returns (sent, failed).
async fn dispatch_push(st: &AppState, title: String, body: String, tag: Option<String>) -> (usize, usize) {
    let title = truncate(title.trim(), MAX_TITLE);
    let body = truncate(body.trim(), MAX_BODY);
    let tag = tag.map(|t| truncate(&t, 64));
    let time = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_secs();
    storage::add_notification(Notification { title: title.clone(), body: body.clone(), time });

    let payload = json!({ "title": title, "body": body, "tag": tag }).to_string();
    let client = match IsahcWebPushClient::new() {
        Ok(c) => c,
        Err(e) => {
            eprintln!("no se pudo crear el cliente push: {e}");
            return (0, 0);
        }
    };
    let (mut sent, mut failed) = (0, 0);
    for sub in storage::list_subscriptions() {
        match send(&client, st, &sub, payload.as_bytes()).await {
            Ok(()) => sent += 1,
            Err(WebPushError::EndpointNotValid) | Err(WebPushError::EndpointNotFound) => {
                // El iPhone ya no acepta esta suscripción (app borrada o permisos quitados).
                storage::remove_subscription(&sub.endpoint);
                failed += 1;
            }
            Err(e) => {
                eprintln!("error enviando push: {e}");
                failed += 1;
            }
        }
    }
    (sent, failed)
}

async fn send(
    client: &IsahcWebPushClient,
    st: &AppState,
    sub: &Subscription,
    payload: &[u8],
) -> Result<(), WebPushError> {
    let info = SubscriptionInfo::new(&sub.endpoint, &sub.keys.p256dh, &sub.keys.auth);
    let mut sig = VapidSignatureBuilder::from_base64(&st.private_key, web_push::URL_SAFE_NO_PAD, &info)?;
    sig.add_claim("sub", st.subject.as_str());
    let mut msg = WebPushMessageBuilder::new(&info);
    msg.set_payload(ContentEncoding::Aes128Gcm, payload);
    // Una hora: si el iPhone está apagado más tiempo, el aviso ya no importa.
    msg.set_ttl(3600);
    msg.set_vapid_signature(sig.build()?);
    client.send(msg.build()?).await
}
