#!/bin/bash
# Emite un código de vinculación nuevo (8 dígitos, 10 minutos, un solo uso).
set -euo pipefail
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
need jq ""
api_curl POST /api/pair/new | jq -r '"Código: \(.code)  (vence en \(.expiresIn / 60 | floor) min)"'
