#!/bin/bash
# Uso: scripts/notify.sh "Título" ["Descripción"] [tag]
# Mismo tag = el aviso nuevo reemplaza al anterior en el iPhone.
# Lee NOTIFY_TOKEN del Llavero (o del entorno). NOTIFY_URL para un servidor remoto.
set -euo pipefail
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
need jq "Viene con macOS 15+; si no: brew install jq"

TITLE="${1:?Falta el título}"
BODY="${2:-}"
TAG="${3:-}"

payload="$(jq -nc --arg t "$TITLE" --arg b "$BODY" --arg g "$TAG" \
  '{title: $t, body: $b} + (if $g == "" then {} else {tag: $g} end)')"
api_curl POST /api/notify "$payload"
echo
