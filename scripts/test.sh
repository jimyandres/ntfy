#!/bin/bash
# Pruebas de punta a punta.
#   scripts/test.sh server   servidor arriba, rutas protegidas, token correcto
#   scripts/test.sh phone    hay un iPhone suscrito y le llega un aviso (confírmalo en el teléfono)
#   scripts/test.sh claude   hooks instalados + aviso simulado de Claude Code
#   scripts/test.sh stratus  CLI de Stratus, watcher activo y traducción de eventos
#   scripts/test.sh all
set -uo pipefail
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

fails=0
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*"; fails=$((fails + 1)); }
code_of() { curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$@"; }

t_server() {
  echo "Servidor ($NOTIFY_URL)"
  if [ "$(code_of "$NOTIFY_URL/api/health")" = 200 ]; then pass "responde /api/health"; else fail "no responde: scripts/service.sh install server; scripts/service.sh logs"; return; fi
  [ "$(code_of "$NOTIFY_URL/api/notifications")" = 401 ] && pass "historial sin token → 401" || fail "historial accesible sin token"
  [ "$(code_of -X POST "$NOTIFY_URL/api/subscribe" -H 'Content-Type: application/json' -d '{}')" != 201 ] && pass "suscribirse sin token → rechazado" || fail "suscripción sin token aceptada"
  [ "$(code_of -X POST "$NOTIFY_URL/api/notify" -H 'Authorization: Bearer nope' -H 'Content-Type: application/json' -d '{"title":"x"}')" = 401 ] && pass "token incorrecto → 401" || fail "token incorrecto aceptado"
  [ "$(code_of -X POST "$NOTIFY_URL/api/pair" -H 'Content-Type: application/json' -d '{"code":"00000000"}')" = 401 ] && pass "código de vinculación inventado → 401" || fail "vinculación sin código válido aceptada"
  if s="$(api_curl GET /api/status)"; then pass "token del Llavero válido ($s)"; else fail "el token del Llavero no funciona"; fi
  if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN 2>/dev/null | grep -q "127.0.0.1:$PORT"; then pass "escucha solo en 127.0.0.1"; else echo "  · no pude confirmar BIND=127.0.0.1 (revisa con: lsof -nP -iTCP:$PORT)"; fi
}

t_phone() {
  echo "iPhone"
  local subs r
  subs="$(api_curl GET /api/status | jq -r '.subscriptions' 2>/dev/null)"
  if [ "${subs:-0}" -ge 1 ] 2>/dev/null; then pass "$subs suscripción(es) registradas"; else fail "ningún iPhone suscrito: scripts/tunnel.sh y sigue los pasos"; return; fi
  r="$("$NTFY_DIR/scripts/notify.sh" "Prueba desde el Mac" "Si ves esto, funciona ✓ $(date +%H:%M:%S)" "ntfy-test")"
  if [ "$(jq -r '.sent' <<<"$r" 2>/dev/null)" -ge 1 ] 2>/dev/null; then
    pass "Apple aceptó el aviso ($r) → mira el iPhone"
  else
    fail "Apple no aceptó el aviso ($r). Revisa scripts/service.sh logs"
  fi
}

t_claude() {
  echo "Claude Code (local)"
  local settings="$HOME/.claude/settings.json" cmd="'$NTFY_DIR/scripts/claude-hook.sh'" last
  for ev in Stop Notification; do
    if jq -e --arg c "$cmd" --arg e "$ev" 'any(.hooks[$e][]?.hooks[]?; .command == $c)' "$settings" >/dev/null 2>&1; then
      pass "hook $ev instalado"
    else
      fail "hook $ev no está en $settings: scripts/install-claude-hooks.sh"
    fi
  done
  printf '%s' '{"hook_event_name":"Notification","cwd":"/tmp/ntfy-test","session_id":"test1234","message":"Prueba de hook (simulada)"}' \
    | "$NTFY_DIR/scripts/claude-hook.sh"
  last="$(api_curl GET /api/notifications | jq -r '.[0].title + " — " + .[0].body' 2>/dev/null)"
  [ "$last" = "Claude Code · ntfy-test — Prueba de hook (simulada)" ] && pass "hook simulado → aviso enviado ($last)" || fail "el hook simulado no llegó al servidor (último: $last)"
}

t_stratus() {
  echo "Stratus"
  if command -v stratus >/dev/null 2>&1; then pass "stratus en PATH ($(command -v stratus))"; else fail "stratus no está en PATH (abre la app Stratus una vez)"; return; fi
  stratus doctor >/dev/null 2>&1 && pass "stratus doctor OK" || fail "stratus doctor falló: ejecútalo para ver el detalle"
  local sample out
  sample='{"cursor":"c:1","source":"event","events":[{"kind":"attention","environmentId":"env-1","threadId":"thread-selftest-1","turnId":"t1","payload":{"type":"run_finished","status":"completed"}}]}'
  out="$(NTFY_STATE_DIR="$(mktemp -d)" "$NTFY_DIR/scripts/stratus-watch.sh" --self-test <<<"$sample")"
  case "$out" in *"Necesita tu respuesta"*) pass "traducción de eventos OK ($out)" ;; *) fail "traducción de eventos: '$out'" ;; esac
  if launchctl print "gui/$(id -u)/com.ntfy-avisos.stratus-watch" >/dev/null 2>&1; then pass "watcher activo (launchd)"; else fail "watcher no instalado: scripts/service.sh install watch"; fi
}

case "${1:-all}" in
  server) t_server ;;
  phone) t_phone ;;
  claude) t_claude ;;
  stratus) t_stratus ;;
  all) t_server; t_phone; t_claude; t_stratus ;;
  *) echo "Uso: $0 server|phone|claude|stratus|all" >&2; exit 2 ;;
esac
echo
[ "$fails" -eq 0 ] && echo "Todo OK" || echo "$fails fallo(s)"
exit "$fails"
