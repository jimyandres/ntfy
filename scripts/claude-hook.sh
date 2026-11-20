#!/bin/bash
# Hook de Claude Code en este Mac: Notification / Stop → aviso en el iPhone.
# Claude Code pasa el evento como JSON por stdin. Este script nunca falla ni bloquea a Claude Code.
# Desactívalo temporalmente con NTFY_HOOK_DISABLE=1 (p. ej. al lanzar `claude -p` en scripts).
[ "${NTFY_HOOK_DISABLE:-0}" = 1 ] && exit 0
DIR="$(cd "$(dirname "$0")" && pwd)"
command -v jq >/dev/null 2>&1 || exit 0

input="$(cat)"
field() { jq -r "$1" <<<"$input" 2>/dev/null; }

event="$(field '.hook_event_name // empty')"
project="$(field '(.cwd // "") | split("/") | map(select(. != "")) | last // "local"')"
session="$(field '(.session_id // "") | .[0:8]')"

case "$event" in
  Notification) body="$(field '.message // "Necesita tu atención"')" ;;
  Stop) body="Terminó y espera tu siguiente mensaje" ;;
  *) exit 0 ;;
esac

"$DIR/notify.sh" "Claude Code · $project" "$body" "claude-$session" >/dev/null 2>&1 || true
exit 0
