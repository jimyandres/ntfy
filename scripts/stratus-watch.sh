#!/bin/bash
# Convierte eventos de los agentes de Stratus (en Ona) en avisos del iPhone.
# Corre en el Mac: usa `stratus agent wait --consumer`, que guarda su cursor, así que
# un reinicio no pierde ni repite eventos. No toca los entornos de Ona ni los mantiene encendidos.
#
# Ajustes (en .env o el entorno):
#   STRATUS_EVENTS   categorías a avisar (por defecto: "attention completed failed")
#   STRATUS_PREVIEW  1 = añade un extracto de la pregunta del agente (por defecto 0: solo el tipo)
#   STRATUS_NAME_JQ  filtro jq para sacar el nombre del hilo de `stratus agent status ID --json`
#
# Prueba sin enviar nada:  scripts/stratus-watch.sh --self-test < evento.json
set -uo pipefail
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

CONSUMER="${STRATUS_CONSUMER:-ntfy-push}"
EVENTS="${STRATUS_EVENTS:-attention completed failed}"
PREVIEW="${STRATUS_PREVIEW:-0}"
NAME_JQ="${STRATUS_NAME_JQ:-.title // .name // .thread.title // .thread.name // .threadName // empty}"
STATE_DIR="${NTFY_STATE_DIR:-$HOME/.local/state/ntfy}"
SEEN="$STATE_DIR/stratus-seen.txt"
INIT="$STATE_DIR/stratus-initialized"
DRY_RUN="${DRY_RUN:-0}"

mkdir -p "$STATE_DIR"
touch "$SEEN"

log() { printf '%s stratus-watch: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }

label_for() {
  case "$1" in
    attention) echo "Necesita tu respuesta" ;;
    completed) echo "Terminó" ;;
    failed) echo "Falló" ;;
    cancelled) echo "Cancelado" ;;
    *) echo "$1" ;;
  esac
}

thread_name() { # nombre legible del hilo; si no se puede, id corto
  local n=""
  if [ "$DRY_RUN" != 1 ]; then
    n="$(stratus agent status "$1" --json 2>/dev/null | jq -r "$NAME_JQ" 2>/dev/null | head -n1)"
  fi
  if [ -n "$n" ] && [ "$n" != "null" ]; then printf '%s' "$n"; else printf '%s' "${1:0:8}"; fi
}

# handle JSON [record_only]: procesa un resultado de `stratus agent wait --json`.
handle() {
  local result="$1" record_only="${2:-0}" source ev kind thread turn key name body q
  source="$(jq -r '.source // "event"' <<<"$result" 2>/dev/null)"
  if [ "$source" != "event" ]; then
    # Instantánea inicial o "reset": son estados actuales, no eventos nuevos.
    record_only=1
  fi
  while IFS= read -r ev; do
    [ -n "$ev" ] || continue
    kind="$(jq -r '.kind // .payload.status // "event"' <<<"$ev")"
    thread="$(jq -r '.threadId // empty' <<<"$ev")"
    turn="$(jq -r '.turnId // ""' <<<"$ev")"
    [ -n "$thread" ] || continue
    key="$thread:$turn:$kind"
    if grep -qxF "$key" "$SEEN"; then continue; fi
    echo "$key" >> "$SEEN"
    if [ "$record_only" = 1 ]; then
      log "registrado sin avisar ($source): $key"
      continue
    fi
    name="$(thread_name "$thread")"
    body="$(label_for "$kind")"
    if [ "$PREVIEW" = 1 ] && [ "$kind" = attention ]; then
      q="$(jq -r '.payload | (.question // .prompt // .message // .text // empty) | tostring | .[0:200]' <<<"$ev" 2>/dev/null)"
      [ -n "$q" ] && body="$body: $q"
    fi
    if [ "$DRY_RUN" = 1 ]; then
      printf 'DRY title="%s" body="%s" tag="%s"\n' "Ona · $name" "$body" "stratus-$thread"
    else
      # El cursor de Stratus ya avanzó, así que reintenta aquí (p. ej. si el servidor se está reiniciando).
      local sent=0 try
      for try in 1 2 3; do
        if "$NTFY_DIR/scripts/notify.sh" "Ona · $name" "$body" "stratus-$thread" >/dev/null; then sent=1; break; fi
        sleep $((try * 5))
      done
      if [ "$sent" = 1 ]; then log "aviso: $kind $thread"; else log "no se pudo enviar el aviso de $key"; fi
    fi
  done < <(jq -c '.events[]?' <<<"$result" 2>/dev/null)
  # Mantener el registro de vistos pequeño.
  tail -n 1000 "$SEEN" > "$SEEN.tmp" && mv "$SEEN.tmp" "$SEEN"
}

if [ "${1:-}" = "--self-test" ]; then
  DRY_RUN=1
  SEEN="$(mktemp "${TMPDIR:-/tmp}/ntfy-seen.XXXXXX")"
  handle "$(cat)"
  rm -f "$SEEN" "$SEEN.tmp"
  exit 0
fi

need jq "Viene con macOS 15+; si no: brew install jq"
need stratus "Instala Stratus (getstratus.vercel.app) y ábrelo una vez: crea ~/.local/bin/stratus."

flags=()
for e in $EVENTS; do flags+=(--event "$e"); done

if [ "${1:-}" = "--prime" ]; then
  # Registra el estado actual (hilos ya terminados o esperando) sin avisar y guarda el cursor.
  out="$(stratus --non-interactive agent wait --consumer "$CONSUMER" ${flags[@]+"${flags[@]}"} --timeout 10 --json)"
  rc=$?
  case "$rc" in
    0) handle "$out" 1 ;;
    124) : ;;
    *) echo "stratus agent wait falló ($rc). Prueba: stratus doctor" >&2; exit 1 ;;
  esac
  touch "$INIT"
  echo "Listo: estado actual registrado; a partir de ahora solo se avisan eventos nuevos."
  exit 0
fi

log "escuchando (consumer=$CONSUMER, eventos=$EVENTS)"
while true; do
  out="$(stratus --non-interactive agent wait --consumer "$CONSUMER" ${flags[@]+"${flags[@]}"} --timeout 1800 --json)"
  rc=$?
  case "$rc" in
    0)
      if [ -f "$INIT" ]; then
        handle "$out"
      else
        # Primera ejecución: registra lo que ya existe sin avisar, para no recibir una ráfaga.
        handle "$out" 1
        touch "$INIT"
      fi
      ;;
    124) : ;; # sin eventos antes del plazo; seguir esperando
    *)
      log "stratus agent wait salió con $rc; reintento en 30 s"
      sleep 30
      ;;
  esac
done
