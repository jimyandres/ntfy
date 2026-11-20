#!/bin/bash
# Servidor y watcher de Stratus como LaunchAgents de tu usuario (arrancan solos y se reinician si caen).
# Uso: scripts/service.sh install [server|watch|all] | uninstall [..] | restart [..] | status | logs
set -euo pipefail
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

LA="$HOME/Library/LaunchAgents"
LOGS="$HOME/Library/Logs/ntfy"
DOMAIN="gui/$(id -u)"

label() { case "$1" in server) echo "com.ntfy-avisos.server" ;; watch) echo "com.ntfy-avisos.stratus-watch" ;; esac; }
script() { case "$1" in server) echo "run-server.sh" ;; watch) echo "stratus-watch.sh" ;; esac; }
targets() {
  case "${1:-all}" in
    server) echo server ;;
    watch) echo watch ;;
    all) echo "server watch" ;;
    *) echo "Destino desconocido: $1 (server|watch|all)" >&2; exit 1 ;;
  esac
}

plist() { # plist NOMBRE
  local l s
  l="$(label "$1")"; s="$(script "$1")"
  cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$l</string>
  <key>ProgramArguments</key>
  <array><string>/bin/bash</string><string>$NTFY_DIR/scripts/$s</string></array>
  <key>WorkingDirectory</key><string>$NTFY_DIR</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>15</integer>
  <key>StandardOutPath</key><string>$LOGS/$1.log</string>
  <key>StandardErrorPath</key><string>$LOGS/$1.log</string>
</dict>
</plist>
EOF
}

cmd="${1:-status}"
case "$cmd" in
  install)
    mkdir -p "$LA" "$LOGS"
    for t in $(targets "${2:-all}"); do
      f="$LA/$(label "$t").plist"
      plist "$t" > "$f"
      plutil -lint "$f" >/dev/null
      launchctl bootout "$DOMAIN/$(label "$t")" 2>/dev/null || true
      launchctl bootstrap "$DOMAIN" "$f"
      echo "✓ $(label "$t") instalado (log: $LOGS/$t.log)"
    done
    ;;
  uninstall)
    for t in $(targets "${2:-all}"); do
      launchctl bootout "$DOMAIN/$(label "$t")" 2>/dev/null || true
      rm -f "$LA/$(label "$t").plist"
      echo "✓ $(label "$t") eliminado"
    done
    ;;
  restart)
    for t in $(targets "${2:-all}"); do launchctl kickstart -k "$DOMAIN/$(label "$t")"; done
    ;;
  status)
    for t in server watch; do
      if launchctl print "$DOMAIN/$(label "$t")" >/dev/null 2>&1; then
        state="$(launchctl print "$DOMAIN/$(label "$t")" | awk -F'= ' '/^\tstate =/ {print $2; exit}')"
        echo "$(label "$t"): ${state:-cargado}"
      else
        echo "$(label "$t"): no instalado"
      fi
    done
    ;;
  logs)
    for t in server watch; do
      [ -f "$LOGS/$t.log" ] && { echo "== $t"; tail -n "${2:-30}" "$LOGS/$t.log"; }
    done
    ;;
  *)
    echo "Uso: $0 install|uninstall|restart [server|watch|all] | status | logs [N]" >&2
    exit 1
    ;;
esac
