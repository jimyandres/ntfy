# Setup runbook: iPhone push for Claude Code + Stratus/Ona

This file is written for **Claude Code running on Jimy's Mac**. Work through the steps in order. At each **🧍 HUMAN** checkpoint, stop and wait for Jimy before you continue.

## What you're building

```
Stratus agents in Ona ──(stratus agent wait, runs on this Mac)──┐
Claude Code on this Mac ──(hooks: Notification, Stop)────────────┤→ server 127.0.0.1:3000 → Apple Web Push → iPhone app
iPhone ⇄ Cloudflare quick tunnel  (only while installing/pairing the app)
```

Nothing changes inside the Ona environments, and the server never accepts connections from the network. The tunnel stays open only for the few minutes it takes Jimy to pair his phone.

## Rules for the agent running this

- **Never print secrets.** `VAPID_PRIVATE_KEY` and `NOTIFY_TOKEN` live in the macOS Keychain (service `ntfy-avisos`). Never run `security find-generic-password … -w` yourself, and never cat, echo or log those values. The scripts read them internally. `.env` holds no secrets.
- **Ask Jimy before** each of these: `brew install` (system-wide install), starting the Cloudflare tunnel (it exposes the local server to the internet while it runs), installing the LaunchAgents, editing `~/.claude/settings.json` (the script backs it up first), and sending any work to a Stratus agent.
- If a step fails, read `scripts/service.sh logs`, fix the cause, and tell Jimy what you changed. The Rust changes were written without a compiler available. If `cargo build` fails, make the smallest fix in `src/`, then report it.
- Don't commit or push to GitHub unless Jimy asks.

---

## Step 0: Copy the project

```bash
SRC="/Users/howdy/Library/Application Support/Claude/local-agent-mode-sessions/8572ae5c-5814-44b6-8f08-2d2d0829dd54/cfe7ad56-00c5-41c0-a195-7c65f1d9e431/14a0d449/outputs/ntfy"
[ -e ~/ntfy ] && echo "~/ntfy already exists, ask Jimy before overwriting" || cp -R "$SRC" ~/ntfy
cd ~/ntfy && git log --oneline -3 && git status --short
```

Run every command after this from `~/ntfy`.

## Step 1: Prerequisites (ask before installing)

```bash
command -v cargo || echo "need: brew install rust"
command -v cloudflared || echo "need: brew install cloudflared"
jq --version            # ships with macOS 15+; otherwise brew install jq
stratus doctor          # Stratus CLI (open the Stratus app once if missing)
```

After Jimy approves, install whatever is missing, e.g. `brew install rust cloudflared`. If Jimy wants a QR code in the terminal, `brew install qrencode` is optional.

## Step 2: Build and create keys

```bash
scripts/setup.sh
```

Expected output: the build succeeds, the VAPID private key and `NOTIFY_TOKEN` go to the Keychain, and `.env` gets the public key. To verify without revealing anything:

```bash
security find-generic-password -s ntfy-avisos -a NOTIFY_TOKEN >/dev/null && echo token-ok
security find-generic-password -s ntfy-avisos -a VAPID_PRIVATE_KEY >/dev/null && echo vapid-ok
grep -c '^VAPID_PUBLIC_KEY=.' .env
```

## Step 3: Start the server (ask first: LaunchAgent)

```bash
scripts/service.sh install server
scripts/test.sh server
```

Every line should show ✓, including "historial sin token → 401" and "escucha solo en 127.0.0.1".

## Step 4: 🧍 HUMAN: install and pair the iPhone app (ask first: tunnel)

Tell Jimy the tunnel will be public for a few minutes and that every `/api` route requires a token. Then start it as a **background** command and read its output:

```bash
scripts/tunnel.sh
```

Show Jimy the **URL** and the **8-digit code** from the output. The URL is also on the Mac clipboard, and Universal Clipboard can paste it on the iPhone. On the iPhone, Jimy will:

1. Open the URL in Safari.
2. Tap Share, then "Añadir a pantalla de inicio", then Añadir.
3. Open **Avisos from the home-screen icon**, not from Safari.
4. Enter the code, tap Vincular, then Activar notificaciones, then Permitir.

If the code expires (10 minutes), run `scripts/pair-code.sh` for a new one. Wait for Jimy to say he's paired, then run:

```bash
scripts/test.sh phone
```

🧍 Ask Jimy to confirm he got **"Prueba desde el Mac"** on the phone.

## Step 5: 🧍 HUMAN: confirm pushes work without the tunnel

Stop the background `tunnel.sh` process (Ctrl-C or kill it), then run:

```bash
scripts/notify.sh "Sin túnel" "Este aviso llegó con el túnel cerrado"
```

🧍 Jimy confirms it arrived. This shows the tunnel isn't needed day to day. Note that every tunnel run gets a new URL. To see the in-app history later, reinstall the app from the new URL. Notifications keep working either way.

## Step 6: Claude Code hooks on this Mac (ask first: edits ~/.claude/settings.json)

```bash
scripts/install-claude-hooks.sh
scripts/test.sh claude
```

This merges two async hooks into your user settings and leaves your other hooks alone:

- `Stop`: Claude finished and is waiting for you. The phone shows "Claude Code · <project> — Terminó y espera tu siguiente mensaje".
- `Notification` (`permission_prompt|elicitation_dialog|agent_needs_input`): Claude needs a permission or an answer.

🧍 Jimy confirms the simulated "Prueba de hook (simulada)" arrived.

**Real event:** Claude Code loads hooks when a session starts. Ask Jimy to open `/hooks` in this session to apply them, or start a new `claude` session. The end of the next reply should then send a real "Terminó" push. 🧍 Jimy confirms.

To silence the hooks for scripted `claude -p` runs, set `NTFY_HOOK_DISABLE=1` for that command.

## Step 7: Stratus agents in Ona

**7a. Check the real JSON shapes.** This is read-only and sends no notifications. The watcher was written from the Stratus CLI README, so confirm the field names:

```bash
stratus agent list --json | head -c 1500; echo
stratus agent status <some-thread-id> --json | head -c 1500; echo
stratus agent wait --event completed --timeout 5 --json | head -c 1500; echo
```

Check these fields:

- The wait result has `source`, which is `"event"` for live events, and `events[]` with `kind`, `threadId` and `turnId`.
- The thread status has a readable name, by default `.title // .name // .thread.title // .thread.name // .threadName`.

If the name lives somewhere else, add `STRATUS_NAME_JQ='<jq filter>'` to `.env`. If the event fields differ, adjust `handle()` in `scripts/stratus-watch.sh`. Then rerun the self-test with a real-shaped sample:

```bash
echo '<one real wait result JSON>' | scripts/stratus-watch.sh --self-test
```

**7b. Prime the watcher and start it (ask first: LaunchAgent).**

```bash
scripts/stratus-watch.sh --prime      # records current state without notifying, so no burst of old events
scripts/service.sh install watch
scripts/test.sh stratus
```

**7c. 🧍 HUMAN: real Stratus event.** Ask Jimy which existing, idle thread to use, or whether he'd rather trigger work himself. With his OK:

```bash
stratus agent send <thread-id> "Reply with the single word OK and stop."
```

When it finishes, the phone should show **"Ona · <thread name> — Terminó"**. 🧍 Jimy confirms. If he agrees, also try a case that needs input. Agent questions show up as **"Necesita tu respuesta"**.

By default the watcher notifies on `attention`, `completed` and `failed`. To change that, set `STRATUS_EVENTS` in `.env`. To include a 200-character preview of the agent's question, set `STRATUS_PREVIEW=1`. It's off by default so no task content leaves the Mac. Run `scripts/service.sh restart watch` after any change.

## Step 8: Final check

```bash
scripts/test.sh all
scripts/service.sh status
```

Report the results to Jimy.

---

## Day to day

| Need | Command |
|---|---|
| Send a manual push | `scripts/notify.sh "Title" "Text"` |
| Logs | `scripts/service.sh logs` |
| Restart | `scripts/service.sh restart all` |
| Pair a new phone / reinstall the app | `scripts/tunnel.sh` |
| After `git pull` / code changes | `cargo build --release && scripts/service.sh restart server` |

## Troubleshooting

- **The test says `sent ≥ 1` but nothing shows up:** check iPhone Settings → Notifications → Avisos, check Focus mode, and make sure the app was opened from the icon, not from Safari.
- **`failed ≥ 1` and the log shows 403 / BadJwtToken:** Apple rejected `VAPID_SUBJECT`. With Jimy's OK (it sends his address to Apple), set `VAPID_SUBJECT=mailto:<his email>` in `.env`, then run `scripts/service.sh restart server`.
- **404/410 from Apple:** that subscription is gone and gets removed automatically. Pair again with `scripts/tunnel.sh`.
- **`cloudflared` can't connect** (corporate network or proxy): stop and tell Jimy. Don't try other tunnel services without asking.
- **Hooks don't fire:** run `/hooks` in Claude Code to check the hooks are listed, then `scripts/test.sh claude`.
- **Stratus watcher is quiet:** check `scripts/service.sh logs` and `stratus doctor`. To start fresh, delete `~/.local/state/ntfy/stratus-initialized`, then run `scripts/stratus-watch.sh --prime` and `scripts/service.sh restart watch`.

## Uninstall

```bash
scripts/service.sh uninstall all
scripts/install-claude-hooks.sh --uninstall
security delete-generic-password -s ntfy-avisos -a NOTIFY_TOKEN
security delete-generic-password -s ntfy-avisos -a VAPID_PRIVATE_KEY
rm -rf ~/.local/state/ntfy ~/Library/Logs/ntfy
```

## What leaves the Mac

- **Push notifications** go to Apple's push service, encrypted end to end with the iPhone's keys. Apple can't read them. Their content is the project or thread name plus the event type, and the agent's question only if `STRATUS_PREVIEW=1`.
- **The app page and history** go through Cloudflare, but only while `tunnel.sh` is running.
