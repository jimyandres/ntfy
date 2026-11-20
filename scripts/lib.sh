# shellcheck shell=bash
# Helpers compartidos. Los demás scripts hacen `. scripts/lib.sh`.
# Regla: los secretos viven en el Llavero de macOS, nunca en archivos ni en la salida.

NTFY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# launchd arranca con un PATH mínimo: añade las rutas habituales (stratus, Homebrew, cargo).
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$HOME/.cargo/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

KC_SERVICE="ntfy-avisos"

# .env solo guarda configuración no secreta (VAPID_PUBLIC_KEY, VAPID_SUBJECT, PORT, BIND, STRATUS_*).
if [ -f "$NTFY_DIR/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "$NTFY_DIR/.env"
  set +a
fi
PORT="${PORT:-3000}"
NOTIFY_URL="${NOTIFY_URL:-http://127.0.0.1:$PORT}"

need() { # need CMD "cómo instalarlo"
  command -v "$1" >/dev/null 2>&1 || { echo "Falta '$1'. ${2:-}" >&2; exit 1; }
}

kc_has() { security find-generic-password -s "$KC_SERVICE" -a "$1" >/dev/null 2>&1; }
kc_get() { security find-generic-password -s "$KC_SERVICE" -a "$1" -w 2>/dev/null; }
kc_set() { # kc_set CUENTA  (valor por stdin; así no aparece en `ps`)
  local v=""
  IFS= read -r v || [ -n "$v" ]
  [ -n "$v" ] || { echo "kc_set: valor vacío para $1" >&2; return 1; }
  printf 'add-generic-password -U -s %s -a %s -w %s\n' "$KC_SERVICE" "$1" "$v" | security -i >/dev/null
}

admin_token() {
  if [ -n "${NOTIFY_TOKEN:-}" ]; then printf '%s' "$NOTIFY_TOKEN"; else kc_get NOTIFY_TOKEN; fi
}

# api_curl MÉTODO RUTA [JSON] — llamada autenticada al servidor local.
# El token va por stdin (-K -), no por argumentos.
api_curl() {
  local tok
  tok="$(admin_token)" || true
  [ -n "$tok" ] || { echo "No hay NOTIFY_TOKEN en el Llavero. Ejecuta scripts/setup.sh" >&2; return 1; }
  if [ -n "${3:-}" ]; then
    curl -fsS --max-time 20 -X "$1" "$NOTIFY_URL$2" -H 'Content-Type: application/json' \
      --data-binary "$3" -K - <<<"header = \"Authorization: Bearer $tok\""
  else
    curl -fsS --max-time 20 -X "$1" "$NOTIFY_URL$2" -K - <<<"header = \"Authorization: Bearer $tok\""
  fi
}
