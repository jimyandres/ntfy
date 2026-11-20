#!/bin/bash
# Arranca el servidor con los secretos del Llavero (lo usa launchd; también sirve a mano).
set -euo pipefail
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
cd "$NTFY_DIR"

VAPID_PRIVATE_KEY="$(kc_get VAPID_PRIVATE_KEY)" || { echo "No hay VAPID_PRIVATE_KEY en el Llavero. Ejecuta scripts/setup.sh" >&2; exit 1; }
NOTIFY_TOKEN="$(kc_get NOTIFY_TOKEN)" || { echo "No hay NOTIFY_TOKEN en el Llavero. Ejecuta scripts/setup.sh" >&2; exit 1; }
export VAPID_PRIVATE_KEY NOTIFY_TOKEN

[ -x ./target/release/ntfy ] || { echo "Falta compilar: scripts/setup.sh" >&2; exit 1; }
exec ./target/release/ntfy
