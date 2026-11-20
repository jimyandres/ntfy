# Avisos push (Rust + Web Push)

Recibe avisos por `POST` y los envía como push a tu iPhone (PWA en la pantalla de inicio).
Fuentes incluidas: hooks de **Claude Code** en este Mac y agentes de **Stratus/Ona** (`stratus agent wait`).

```
Agentes Stratus (Ona) ──stratus agent wait──┐
Claude Code (este Mac) ──hooks──────────────┤→ servidor 127.0.0.1:3000 → Apple Web Push → iPhone
iPhone ⇄ túnel Cloudflare temporal (solo para instalar/vincular la app)
```

Guía paso a paso (pensada para que la ejecute Claude Code): **[SETUP.md](SETUP.md)**.

## Resumen

| Paso | Comando |
|---|---|
| Compilar + claves (secretos al Llavero) | `scripts/setup.sh` |
| Servidor como servicio (launchd) | `scripts/service.sh install server` |
| Instalar/vincular el iPhone | `scripts/tunnel.sh` (Ctrl-C al terminar) |
| Hooks de Claude Code | `scripts/install-claude-hooks.sh` |
| Watcher de Stratus | `scripts/stratus-watch.sh --prime` y `scripts/service.sh install watch` |
| Probar | `scripts/test.sh all` |
| Enviar un aviso a mano | `scripts/notify.sh "Título" "Texto"` |

## Seguridad

- Los secretos (`VAPID_PRIVATE_KEY`, `NOTIFY_TOKEN`) viven en el Llavero de macOS (servicio `ntfy-avisos`); `.env` solo tiene configuración pública.
- El servidor escucha en `127.0.0.1`. Todas las rutas `/api` piden token, salvo `health`, la clave pública y el canje del código de vinculación.
- El iPhone se vincula con un código de 8 dígitos (un uso, 10 minutos, 5 intentos) y recibe su propio token; en `data.json` solo se guarda su hash.
- El túnel solo hace falta para instalar la app y ver el historial. Los avisos van del Mac a Apple y de Apple al iPhone, cifrados de punta a punta.

## Datos

Se guardan en `data.json` (máx. 100 avisos). Todo el acceso está en `src/storage.rs`, para poder cambiarlo a Redis.
