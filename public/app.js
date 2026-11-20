const $ = id => document.getElementById(id);
const btn = $('enable');
const testBtn = $('test');
const statusEl = $('status');
const list = $('list');
const TOKEN_KEY = 'avisos_token';

// La app instalada en la pantalla de inicio tiene su propio almacenamiento (separado de Safari),
// así que la vinculación se hace dentro de la app instalada.
function getToken() {
  try { return localStorage.getItem(TOKEN_KEY); } catch (_) { return null; }
}
function setToken(t) {
  try { t ? localStorage.setItem(TOKEN_KEY, t) : localStorage.removeItem(TOKEN_KEY); } catch (_) {}
}

async function api(path, opts = {}) {
  const headers = Object.assign({}, opts.headers || {});
  const t = getToken();
  if (t) headers.Authorization = 'Bearer ' + t;
  const res = await fetch(path, Object.assign({}, opts, { headers }));
  if (res.status === 401) {
    setToken(null);
    showPairing();
    throw new Error('Esta app ya no está vinculada. Pide un código nuevo en el Mac.');
  }
  return res;
}

function showPairing() {
  $('pair').hidden = false;
  $('main').hidden = true;
}

function showMain() {
  $('pair').hidden = true;
  $('main').hidden = false;
}

function b64ToBytes(s) {
  const pad = '='.repeat((4 - (s.length % 4)) % 4);
  const raw = atob((s + pad).replace(/-/g, '+').replace(/_/g, '/'));
  return Uint8Array.from(raw, c => c.charCodeAt(0));
}

async function loadList() {
  if (!getToken()) return;
  let items;
  try {
    items = await (await api('/api/notifications')).json();
  } catch (_) {
    // Túnel apagado: los avisos siguen llegando, solo el historial no está disponible.
    if (!statusEl.textContent) statusEl.textContent = 'Sin conexión con el Mac (el historial no está disponible).';
    return;
  }
  list.innerHTML = '';
  for (const n of items) {
    const li = document.createElement('li');
    for (const [cls, text] of [
      ['title', n.title],
      ['body', n.body],
      ['time', new Date(n.time * 1000).toLocaleString()],
    ]) {
      const div = document.createElement('div');
      div.className = cls;
      div.textContent = text;
      li.appendChild(div);
    }
    list.appendChild(li);
  }
}

async function pair() {
  const code = $('code').value.trim();
  if (!/^\d{8}$/.test(code)) { statusEl.textContent = 'El código tiene 8 dígitos.'; return; }
  try {
    const res = await fetch('/api/pair', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ code }),
    });
    if (!res.ok) { statusEl.textContent = 'Código incorrecto o vencido. Pide otro en el Mac.'; return; }
    setToken((await res.json()).token);
    showMain();
    statusEl.textContent = 'Vinculado ✓ Ahora activa las notificaciones.';
    loadList();
  } catch (e) {
    statusEl.textContent = 'Error: ' + e.message;
  }
}

async function enable() {
  try {
    if (!('serviceWorker' in navigator) || !('PushManager' in window)) {
      statusEl.textContent = 'Instala la app en la pantalla de inicio (Compartir → Añadir) y ábrela desde ahí.';
      return;
    }
    const perm = await Notification.requestPermission();
    if (perm !== 'granted') { statusEl.textContent = 'Permiso denegado.'; return; }
    const reg = await navigator.serviceWorker.ready;
    let sub = await reg.pushManager.getSubscription();
    if (!sub) {
      const key = (await (await fetch('/api/vapid-public-key')).text()).trim();
      sub = await reg.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: b64ToBytes(key),
      });
    }
    const res = await api('/api/subscribe', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(sub),
    });
    if (!res.ok) throw new Error('HTTP ' + res.status);
    btn.hidden = true;
    statusEl.textContent = 'Notificaciones activadas ✓';
  } catch (e) {
    statusEl.textContent = 'Error: ' + e.message;
  }
}

async function sendTest() {
  try {
    statusEl.textContent = 'Enviando prueba en 5s...';
    await api('/api/test', { method: 'POST' });
    setTimeout(loadList, 5500);
  } catch (e) {
    statusEl.textContent = 'Error: ' + e.message;
  }
}

if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register('/sw.js').then(async () => {
    if ('PushManager' in window && Notification.permission === 'granted') {
      const reg = await navigator.serviceWorker.ready;
      if (await reg.pushManager.getSubscription()) btn.hidden = true;
    }
  });
}
$('pairBtn').addEventListener('click', pair);
btn.addEventListener('click', enable);
testBtn.addEventListener('click', sendTest);
if (getToken()) { showMain(); loadList(); } else { showPairing(); }
setInterval(loadList, 10000);
