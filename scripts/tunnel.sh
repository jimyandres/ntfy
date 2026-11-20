#!/bin/bash
# Abre un túnel HTTPS temporal (Cloudflare quick tunnel) para instalar y vincular la app en el iPhone.
# Ciérralo con Ctrl-C al terminar: los avisos siguen llegando sin túnel (van Mac → Apple → iPhone).
# Mientras está abierto, todas las rutas /api exigen token; el código de vinculación dura 10 min.
set -euo pipefail
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
need cloudflared "Instálalo con: brew install cloudflared"
need jq ""

curl -fsS --max-time 3 "$NOTIFY_URL/api/health" >/dev/null 2>&1 || {
  echo "El servidor no responde en $NOTIFY_URL. Arráncalo: scripts/service.sh install server" >&2
  exit 1
}

log="$(mktemp "${TMPDIR:-/tmp}/ntfy-tunnel.XXXXXX")"
cloudflared tunnel --no-autoupdate --url "$NOTIFY_URL" >"$log" 2>&1 &
pid=$!
cleanup() { kill "$pid" 2>/dev/null || true; rm -f "$log" "$NTFY_DIR/.tunnel-url"; }
trap cleanup EXIT
trap 'echo; echo "Túnel cerrado."; exit 0' INT TERM

url=""
for _ in $(seq 1 60); do
  url="$(grep -Eo 'https://[a-z0-9-]+\.trycloudflare\.com' "$log" | grep -v '^https://api\.' | head -n1 || true)"
  [ -n "$url" ] && break
  kill -0 "$pid" 2>/dev/null || { echo "cloudflared terminó:" >&2; tail -n 20 "$log" >&2; exit 1; }
  sleep 1
done
[ -n "$url" ] || { echo "cloudflared no dio una URL en 60 s:" >&2; tail -n 20 "$log" >&2; exit 1; }

printf '→ Esperando a que %s responda' "$url"
ok=0
for _ in $(seq 1 30); do
  if curl -fsS --max-time 5 "$url/api/health" >/dev/null 2>&1; then ok=1; break; fi
  printf '.'; sleep 2
done
echo
[ "$ok" = 1 ] || echo "Aviso: la URL aún no responde (DNS nuevo). Prueba en el iPhone en un minuto."

code="$(api_curl POST /api/pair/new | jq -r .code)"
printf '%s\n' "$url" > "$NTFY_DIR/.tunnel-url"
printf '%s' "$url" | pbcopy 2>/dev/null || true

cat <<EOF

================================================================
URL:     $url   (copiada al portapapeles)
Código:  $code   (un solo uso, 10 minutos)

En el iPhone:
 1. Abre la URL en Safari.
 2. Compartir → "Añadir a pantalla de inicio" → Añadir.
 3. Abre "Avisos" DESDE EL ICONO (no desde Safari).
 4. Escribe el código → Vincular → Activar notificaciones → Permitir.
 5. Toca "Probar notificación (5s)" y bloquea la pantalla.

¿Código vencido? En otra terminal: scripts/pair-code.sh
Ctrl-C para cerrar el túnel cuando termines.
================================================================
EOF
if command -v qrencode >/dev/null 2>&1; then qrencode -t ansiutf8 "$url"; fi

wait "$pid"
