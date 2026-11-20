//! Acceso a datos aislado. Hoy: data.json. Para cambiar a Redis, reimplementa estas funciones.
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::sync::Mutex;

const FILE: &str = "data.json";
const MAX_NOTIFICATIONS: usize = 100;

static LOCK: Mutex<()> = Mutex::new(());

#[derive(Serialize, Deserialize, Clone)]
pub struct Subscription {
    pub endpoint: String,
    pub keys: Keys,
}

#[derive(Serialize, Deserialize, Clone)]
pub struct Keys {
    pub p256dh: String,
    pub auth: String,
}

#[derive(Serialize, Deserialize, Clone)]
pub struct Notification {
    pub title: String,
    pub body: String,
    /// Segundos Unix
    pub time: u64,
}

/// A paired device (the iPhone). Only the SHA-256 of its token is stored.
#[derive(Serialize, Deserialize, Clone)]
struct Device {
    token_sha256: String,
}

#[derive(Serialize, Deserialize, Default)]
struct Data {
    #[serde(default)]
    subscriptions: Vec<Subscription>,
    /// Más reciente primero
    #[serde(default)]
    notifications: Vec<Notification>,
    #[serde(default)]
    devices: Vec<Device>,
}

fn load() -> Data {
    let Ok(s) = std::fs::read_to_string(FILE) else {
        return Data::default();
    };
    match serde_json::from_str(&s) {
        Ok(d) => d,
        Err(e) => {
            // No sobrescribir en silencio: guarda una copia del archivo dañado.
            let backup = format!("{FILE}.corrupt");
            eprintln!("{FILE} no se pudo leer ({e}); copia en {backup}");
            let _ = std::fs::write(&backup, &s);
            Data::default()
        }
    }
}

/// Escritura atómica: archivo temporal + rename, para no dejar data.json a medias.
fn save(d: &Data) {
    let tmp = format!("{FILE}.tmp");
    let result = std::fs::write(&tmp, serde_json::to_string_pretty(d).unwrap())
        .and_then(|_| std::fs::rename(&tmp, FILE));
    if let Err(e) = result {
        eprintln!("no se pudo escribir {FILE}: {e}");
    }
}

fn sha256_hex(s: &str) -> String {
    Sha256::digest(s.as_bytes()).iter().map(|b| format!("{b:02x}")).collect()
}

pub fn add_subscription(s: Subscription) {
    let _g = LOCK.lock().unwrap();
    let mut d = load();
    if !d.subscriptions.iter().any(|x| x.endpoint == s.endpoint) {
        d.subscriptions.push(s);
        save(&d);
    }
}

pub fn remove_subscription(endpoint: &str) {
    let _g = LOCK.lock().unwrap();
    let mut d = load();
    d.subscriptions.retain(|x| x.endpoint != endpoint);
    save(&d);
}

pub fn list_subscriptions() -> Vec<Subscription> {
    let _g = LOCK.lock().unwrap();
    load().subscriptions
}

pub fn add_notification(n: Notification) {
    let _g = LOCK.lock().unwrap();
    let mut d = load();
    d.notifications.insert(0, n);
    d.notifications.truncate(MAX_NOTIFICATIONS);
    save(&d);
}

pub fn list_notifications() -> Vec<Notification> {
    let _g = LOCK.lock().unwrap();
    load().notifications
}

pub fn add_device(token: &str) {
    let _g = LOCK.lock().unwrap();
    let mut d = load();
    d.devices.push(Device { token_sha256: sha256_hex(token) });
    save(&d);
}

pub fn has_device(token: &str) -> bool {
    let h = sha256_hex(token);
    let _g = LOCK.lock().unwrap();
    load().devices.iter().any(|x| x.token_sha256 == h)
}

pub fn device_count() -> usize {
    let _g = LOCK.lock().unwrap();
    load().devices.len()
}
