# cloudflare-dns

Runs a Cloudflare Tunnel (`cloudflared`) hidden in the background on a Windows PC, with a tray icon that shows whether it's connected. A Cloudflare Worker reaches a service on this PC through the tunnel, using a **Workers VPC service**.

**Step-by-step installation guide:** [docs/setup.html](docs/setup.html) (open it in a browser).

## Quick setup

1. Download `cloudflared.exe` into this folder.
2. `copy .env.example .env`, then fill it in.
3. `npx wrangler login`, then `.\cloudflare\setup.ps1`. This creates the tunnel and the VPC service, and writes their IDs to `.env`.
4. Put the tunnel token in `.env` (`TUNNEL_TOKEN`).
5. `.\build-tray.ps1`, then run `cloudflared-tray.exe`. In the tray menu, tick **Start at login**.

## Files

| File | Purpose |
|---|---|
| `.env.example` | Template for `.env`, which holds every setting: token, account, tunnel and VPC IDs, ports. `.env` is git-ignored. |
| `cloudflared-tray.ps1` | The tray app: starts `cloudflared`, restarts it if it dies, shows its status. |
| `build-tray.ps1` | Compiles `cloudflared-tray.exe`, a small host that runs the tray script with no console window. |
| `cloudflared-tray.ico` | The app's artwork, used for the exe and the tray icon. |
| `cloudflare/setup.ps1` | Creates the tunnel and the Workers VPC service with wrangler. Re-runnable. |
| `cloudflare/status.ps1` | Shows the tunnel and VPC service as Cloudflare sees them. |
| `docs/setup.html` | Detailed installation guide. |

Not in git: `cloudflared.exe` (download it), `cloudflared-tray.exe` (build it), `.env`, logs.

## How it works

- The tray app runs `cloudflared.exe tunnel --protocol <TUNNEL_PROTOCOL> --metrics 127.0.0.1:<METRICS_PORT> --logfile cloudflared.log run`, passing `TUNNEL_TOKEN` from `.env`.
- Every 5 s it checks `http://127.0.0.1:<METRICS_PORT>/ready`. The tray icon is the full artwork when connected, and faded gray while connecting or stopped. A dead `cloudflared` is restarted, at most once every 30 s.
- Only one copy of the tray app runs at a time. **Start at login** writes `HKCU\Software\Microsoft\Windows\CurrentVersion\Run\CloudflareTunnel`.
- `cloudflared.log` is rotated to `cloudflared.log.old` when it passes 5 MB.

## Changing things

- **Other settings** (`.env`) or **tray behavior** (`cloudflared-tray.ps1`): restart the tray app (menu → Exit, then run the exe).
- **`APP_PUBLISHER`, exe name or icon**: run `.\build-tray.ps1`. It stops the running tray app, builds, and starts it again.
- **Throwaway tunnel to a local port**, no account needed: `.\cloudflared.exe tunnel --url http://127.0.0.1:8050`.
