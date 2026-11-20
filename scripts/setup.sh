#!/bin/bash
# Configuración única: compila, genera claves VAPID y el token, y los guarda en el Llavero.
# Es seguro volver a ejecutarlo: no regenera nada que ya exista.
set -euo pipefail
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
cd "$NTFY_DIR"

need cargo "Instálalo con: brew install rust"
need jq "Viene con macOS 15+; si no: brew install jq"
need security "Este script es para macOS."

echo "→ Compilando (cargo build --release)…"
cargo build --release

if kc_has VAPID_PRIVATE_KEY && grep -q '^VAPID_PUBLIC_KEY=.' .env 2>/dev/null; then
  echo "→ Claves VAPID ya existen (Llavero + .env)."
else
  echo "→ Generando claves VAPID nuevas…"
  keys="$(./target/release/gen_keys)"
  pub="$(printf '%s\n' "$keys" | sed -n 's/^VAPID_PUBLIC_KEY=//p')"
  printf '%s\n' "$keys" | sed -n 's/^VAPID_PRIVATE_KEY=//p' | kc_set VAPID_PRIVATE_KEY
  unset keys
  # Apple exige un "subject" mailto: o https:. Por defecto la URL del repo, para no enviar tu email.
  cat > .env <<EOF
VAPID_PUBLIC_KEY=$pub
VAPID_SUBJECT=${VAPID_SUBJECT:-https://github.com/jeancarlo12/ntfy}
PORT=${PORT:-3000}
BIND=127.0.0.1
EOF
  echo "   Clave privada → Llavero (servicio $KC_SERVICE). Clave pública → .env"
  if [ -f data.json ]; then
    echo "   Aviso: las suscripciones anteriores dejan de valer con claves nuevas; vuelve a vincular el iPhone."
  fi
fi

if kc_has NOTIFY_TOKEN; then
  echo "→ NOTIFY_TOKEN ya existe en el Llavero."
else
  openssl rand -base64 32 | tr '+/' '-_' | tr -d '=\n' | kc_set NOTIFY_TOKEN
  echo "→ NOTIFY_TOKEN generado → Llavero."
fi

echo "Listo. Siguiente: scripts/service.sh install server"
