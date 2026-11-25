# Setup: Cloudflare Tunnel tray app

Runs a Cloudflare Tunnel (`cloudflared`) hidden on a Windows PC, with a tray icon for its status, and lets a Cloudflare Worker reach a local service on that PC through a Workers VPC service.

This is the plain-text version of [setup.html](setup.html), written for agents and terminals. Both files cover the same steps; keep them in sync.

## Rules for agents

- **Shell:** every command is PowerShell, run from the repository root. Don't run `.ps1` files from bash: it fails on the first line.
- **Steps that need the user:** step 5 (`wrangler login` opens a browser) and step 7 (copying the tunnel token from the dashboard). Ask the user to do these, then continue.
- **Secrets:** `TUNNEL_TOKEN` in `.env` is a secret. Never print it, log it, or commit it. `.env` is git-ignored.
- **Cloudflare changes:** steps 6 and 10 create or change resources in the user's Cloudflare account. Confirm with the user before running them.
- **Re-running is safe:** `cloudflare/setup.ps1` skips any step whose ID is already in `.env`, and `build-tray.ps1` stops and restarts a running tray app.

## Steps at a glance

| # | Step | Command | Who |
|---|------|---------|-----|
| 1 | Check requirements | `node --version` | agent |
| 2 | Get the files | `git clone <repo-url>`, `cd fcd` | agent |
| 3 | Download cloudflared | `Invoke-WebRequest ... -OutFile cloudflared.exe` | agent |
| 4 | Create `.env` | `Copy-Item .env.example .env`, then edit | agent, values from user |
| 5 | Log in to wrangler | `npx wrangler login` | **user** (browser) |
| 6 | Create tunnel and VPC service | `.\cloudflare\setup.ps1` | agent, after confirming |
| 7 | Add the tunnel token | edit `TUNNEL_TOKEN` in `.env` | **user** (dashboard) |
| 8 | Build the tray app | `.\build-tray.ps1` | agent |
| 9 | Run it, start at login | `.\cloudflared-tray.exe`, tray menu | agent, then user ticks the menu item |
| 10 | Connect the Worker | edit the Worker's `wrangler.jsonc` | agent, in the Worker's repo |
| 11 | Verify | `Invoke-RestMethod http://127.0.0.1:20251/ready` | agent |

## 1. Requirements

- Windows 10 or 11. The build uses the .NET Framework compiler and Windows PowerShell 5.1, which ship with Windows.
- [Node.js](https://nodejs.org) 18 or newer, for `npx wrangler`. Only needed during setup.
- A Cloudflare account with access to Zero Trust (the free plan is enough).
- The local service the Worker should reach, for example a web app on `http://127.0.0.1:8050`.

If PowerShell refuses to run `.ps1` scripts, allow local scripts for the current user once:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

## 2. Get the files

Clone to a permanent location. The tray app runs from this folder, and **Start at login** stores its path.

```powershell
git clone <repo-url>
cd fcd
```

Every later command runs from this folder and uses paths relative to it.

## 3. Download cloudflared

`cloudflared.exe` (about 55 MB) is not in git. Download it into the repository root:

```powershell
Invoke-WebRequest https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe -OutFile cloudflared.exe
.\cloudflared.exe --version
```

To update it later, exit the tray app first (it runs `cloudflared.exe`), then download again.

## 4. Create .env

All settings live in `.env` (format: `KEY=VALUE`, `#` comments). Start from the template:

```powershell
Copy-Item .env.example .env
```

Set the keys marked **required now**. The setup script fills in the IDs; the token comes in step 7.

| Key | Required now | Meaning |
|-----|--------------|---------|
| `TUNNEL_TOKEN` | no (step 7) | Secret connector token for the tunnel. |
| `CLOUDFLARE_ACCOUNT_ID` | no | Account ID. The setup script fills it in from the wrangler login. |
| `TUNNEL_NAME` | **yes** | Tunnel name, e.g. `my-tunnel`. |
| `TUNNEL_ID` | no | Filled in by the setup script. If the tunnel already exists, set it here and the script reuses it. |
| `VPC_SERVICE_NAME` | **yes** | Workers VPC service name, e.g. `tasks`. |
| `VPC_SERVICE_HOSTNAME` | **yes** | Where the local service listens, as seen from this PC. Default `127.0.0.1`. Prefer it to `localhost`, which can resolve to IPv6 (`::1`) first. An IP address is sent to wrangler as `--ipv4`/`--ipv6`, a name as `--hostname`. |
| `VPC_SERVICE_HTTP_PORT` | **yes** | The local service's port, e.g. `8050`. |
| `VPC_SERVICE_ID` | no | Filled in by the setup script. |
| `WORKER_URL` | no | The Worker that uses the service. Reference only. |
| `APP_NAME` | no | Name in the tray tooltip and notifications. |
| `APP_PUBLISHER` | no | Publisher stamped into `cloudflared-tray.exe` (Task Manager, file properties). Default `Cloudflared Tray`. Rebuild (step 8) after changing it. |
| `TUNNEL_PROTOCOL` | no | `http2` (works through most firewalls) or `quic`. |
| `METRICS_PORT` | no | Local port where cloudflared reports its status. Default `20251`. |

## 5. Log in to wrangler (user)

Opens a browser to approve access. An agent can't complete this; ask the user to run it.

```powershell
npx wrangler login
npx wrangler whoami
```

The login expires after a while. "Not logged in" or "auth token has expired" from any later step means: repeat this step.

## 6. Create the tunnel and VPC service

```powershell
.\cloudflare\setup.ps1
```

The script:

1. checks the wrangler login and writes `CLOUDFLARE_ACCOUNT_ID` to `.env`;
2. creates the tunnel `TUNNEL_NAME` (or reuses an existing one) and writes `TUNNEL_ID` to `.env`;
3. creates a Workers VPC service pointing at `http://VPC_SERVICE_HOSTNAME:VPC_SERVICE_HTTP_PORT` through the tunnel, and writes `VPC_SERVICE_ID` to `.env`.

Steps whose ID is already in `.env` are skipped. Equivalent wrangler commands:

```powershell
npx wrangler tunnel create <TUNNEL_NAME>
npx wrangler vpc service create <VPC_SERVICE_NAME> --type http --tunnel-id <TUNNEL_ID> --ipv4 <HOST> --http-port <PORT>
# use --hostname <HOST> instead of --ipv4 when HOST is a DNS name
```

`wrangler tunnel` is experimental. If it fails, the user can create the tunnel in the dashboard (Zero Trust → Networks → Tunnels → Create a tunnel → Cloudflared); then put its ID in `TUNNEL_ID` and run the script again.

To inspect or change an existing VPC service:

```powershell
npx wrangler vpc service get <VPC_SERVICE_ID>
npx wrangler vpc service update --help
```

## 7. Add the tunnel token (user)

The token lets `cloudflared` run as this tunnel. The user gets it from the dashboard:

1. [Cloudflare Zero Trust](https://one.dash.cloudflare.com) → **Networks** → **Tunnels**.
2. Open the tunnel → **Configure**.
3. Under the install commands, copy the long string after `--token`.
4. Paste it into `.env` as `TUNNEL_TOKEN=...`.

Anyone with the token can run the tunnel. If it leaks, rotate it from the tunnel's page in the dashboard.

## 8. Build the tray app

```powershell
.\build-tray.ps1
```

Compiles `cloudflared-tray.exe`: a small host that runs `cloudflared-tray.ps1` with no console window, using `cloudflared-tray.ico` as its icon and `APP_PUBLISHER` as its publisher. If this folder's tray app is running, the script stops it, builds, and starts it again.

Rebuild only after changing `APP_PUBLISHER`, the exe name, or the icon. Other `.env` changes and edits to `cloudflared-tray.ps1` only need a restart of the tray app.

## 9. Run it and start at login

```powershell
Start-Process .\cloudflared-tray.exe
```

- The tray icon is the full artwork when connected, and faded gray while connecting or stopped.
- The user right-clicks it and ticks **Start at login**. This writes `HKCU\Software\Microsoft\Windows\CurrentVersion\Run\CloudflareTunnel`.
- The menu also has Stop/Start, Restart, Open log, and Open Cloudflare dashboard.
- Only one copy runs at a time.

Windows may put new icons in the `^` overflow menu. The user can drag it onto the taskbar, or turn it on under Settings → Personalization → Taskbar → Other system tray icons.

## 10. Connect the Worker

In the Worker's own project, bind the VPC service in `wrangler.jsonc`, using `VPC_SERVICE_ID` from `.env`:

```jsonc
{
  "vpc_services": [
    { "binding": "TASKS", "service_id": "<VPC_SERVICE_ID>" }
  ]
}
```

Call the local service through the binding:

```js
const res = await env.TASKS.fetch("http://localhost/api/health");
```

The hostname in this URL is a placeholder: requests go through the tunnel to the host and port saved on the VPC service. Deploy with `npx wrangler deploy`.

## 11. Verify

```powershell
# Tray app and cloudflared are running
Get-Process cloudflared-tray, cloudflared

# cloudflared is connected: expect HTTP 200
(Invoke-WebRequest http://127.0.0.1:20251/ready -UseBasicParsing).StatusCode

# The tunnel and VPC service as Cloudflare sees them (needs the wrangler login)
.\cloudflare\status.ps1
```

In the dashboard, the tunnel shows as **Healthy** under Zero Trust → Networks → Tunnels. Use the `METRICS_PORT` from `.env` if it isn't `20251`.

## Troubleshooting

| Symptom | Cause and fix |
|---------|---------------|
| ".env not found" or "TUNNEL_TOKEN is empty" | Steps 4 and 7. `.env` must be next to `cloudflared-tray.exe`. |
| Tray icon stays gray | Read the end of `cloudflared.log`. A bad token shows as an authentication error. If `http2` is blocked, try `TUNNEL_PROTOCOL=quic`, or the other way round, then restart the tray app. |
| No tray icon | Probably in the `^` overflow menu (step 9). Check `Get-Process cloudflared-tray`. |
| `build-tray.ps1` fails with "file in use" | The script already stops this folder's tray app, so another program has the exe open (its Properties window, a security scan). Close it and build again. |
| "Not logged in" / "auth token has expired" from wrangler | Repeat step 5. |
| The Worker gets errors from the binding | Check the local service answers at `http://VPC_SERVICE_HOSTNAME:VPC_SERVICE_HTTP_PORT` on this PC, the tunnel is ready (step 11), and `service_id` matches `VPC_SERVICE_ID`. |

## Files

| File | Purpose |
|------|---------|
| `.env.example` | Template for `.env`, which holds every setting. `.env` is git-ignored. |
| `cloudflared-tray.ps1` | The tray app: starts `cloudflared`, restarts it if it dies, shows its status. |
| `build-tray.ps1` | Compiles `cloudflared-tray.exe`, the no-console host for the tray script. |
| `cloudflared-tray.ico` | The app's artwork, used for the exe and the tray icon. |
| `cloudflare/env.ps1` | Shared helpers for the setup scripts: reads and writes `.env`, wraps `npx wrangler`. |
| `cloudflare/setup.ps1` | Creates the tunnel and the Workers VPC service. Re-runnable. |
| `cloudflare/status.ps1` | Shows the tunnel and VPC service as Cloudflare sees them. |

Not in git: `cloudflared.exe` (step 3), `cloudflared-tray.exe` (step 8), `.env` (step 4), `cloudflared.log`.
