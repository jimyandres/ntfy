#!/bin/bash
# Añade (o quita con --uninstall) los hooks de avisos en ~/.claude/settings.json.
# Fusiona con lo que ya tengas: no toca otros hooks ni ajustes. Guarda una copia antes.
set -euo pipefail
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
need jq "Viene con macOS 15+; si no: brew install jq"

SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"
CMD="'$NTFY_DIR/scripts/claude-hook.sh'"
# Avisos que importan desde el móvil: permisos, preguntas y agentes que piden input.
MATCHER="permission_prompt|elicitation_dialog|agent_needs_input"

mkdir -p "$(dirname "$SETTINGS")"
[ -s "$SETTINGS" ] || echo '{}' > "$SETTINGS"
jq empty "$SETTINGS" >/dev/null || { echo "$SETTINGS no es JSON válido; no lo toco." >&2; exit 1; }
backup="$SETTINGS.bak.$(date +%Y%m%d%H%M%S).$$"
cp "$SETTINGS" "$backup"

if [ "${1:-}" = "--uninstall" ]; then
  filter='
    .hooks |= (if . == null then . else
      with_entries(.value |= (map(.hooks |= map(select(.command != $cmd))) | map(select((.hooks | length) > 0))))
      | with_entries(select((.value | length) > 0))
    end)'
else
  filter='
    def add($ev; $m):
      .hooks[$ev] = ((.hooks[$ev] // []) as $cur
        | if any($cur[]?; any(.hooks[]?; .command == $cmd)) then $cur
          else $cur + [({hooks: [{type: "command", command: $cmd, async: true}]}
                        + (if $m == "" then {} else {matcher: $m} end))]
          end);
    .hooks = (.hooks // {}) | add("Stop"; "") | add("Notification"; $matcher)'
fi

tmp="$SETTINGS.tmp.$$"
jq --arg cmd "$CMD" --arg matcher "$MATCHER" "$filter" "$SETTINGS" > "$tmp"
mv "$tmp" "$SETTINGS"
echo "Actualizado $SETTINGS (copia: $backup)"
jq --arg cmd "$CMD" '[.hooks // {} | to_entries[] | select(any(.value[]?.hooks[]?; .command == $cmd)) | .key]' "$SETTINGS"
