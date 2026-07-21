# ZMMO Device Changer

Monorepo Android device identity management — web panel + Go agent.

## Cấu trúc
```
/home/thay/zmmo/
├── packages/
│   ├── panel/           # Next.js 16 web dashboard (port 3013)
│   └── manager-agent/   # Go binary agent (REST API port 55555-55556)
└── assets/              # Old binaries (legacy)
```

## Panel (Next.js 16)

- **Port:** 3013 (serve: `npx next start -p 3013 -H 0.0.0.0`)
- **UI:** shadcn/ui, dark zinc-950, mobile-responsive
- **Framework:** Next.js 16 App Router, TypeScript
- **Key pages:**
  - `/` — Dashboard (device grid, status overview)
  - `/downloads` — Download agent binaries + setup instructions
  - `/device/[id]` — Device detail (Info Summary + 5-tab Edit Form 46 fields)
- **Features:** hamburger sidebar, card layouts, viewport meta (mobile-first)
- **API endpoints:** `/agent-binaries/*` — serves Go binaries
- **Version display:** badge `v1.1.1` on downloads page
- **Cache buster:** download URLs use `?v=1.1.1` query param

### Build & Deploy
```bash
cd packages/panel
npm run build
# Kill old process: fuser -k 3013/tcp
npx next start -p 3013 -H 0.0.0.0
```

## Manager-Agent (Go 1.25)

- **Language:** Go 1.25, Pure Go, Zero CGO
- **Systray:** gogpu/systray v0.1.2 (Pure Go, cross-compile from Linux to Win/Mac)
- **Icon:** React logo PNG 64×64 embed
- **Port:** 55555 (fallback 55556)
- **Log:** `~/.zmmo/system.log`
- **Meta cache:** `~/.zmmo/devices/<serial>/meta.json`

### Platform Behavior
| Platform | Mode | Systray |
|----------|------|---------|
| Linux | Headless (default) | ❌ |
| Windows | Systray | ✅ (Shell_NotifyIconW) |
| macOS | Systray | ✅ |

### CLI Flags
- `--headless` — Force headless mode (no systray)
- `--verbose` — Show console (Windows: AllocConsole), log to stderr

### API Endpoints
- `GET /status` — Agent status
- `GET /devices` — List ADB devices
- `GET /devices/:id` — Device detail
- `GET /devices/:id/meta` — Read cached meta
- `POST /devices/:serial/refresh-meta` — ADB collect 50+ props → meta.json
- `PUT /devices/:id/props` — Update editable properties
- `POST /devices/:id/apply` — Apply changes
- `POST /tasks` — Run tasks (adb shell, reboot, backup, restore)
- `GET /backups` — List backups
- `POST /backups/:id/restore` — Restore backup
- `POST /adb/:deviceId` — Execute ADB command
- `POST /license/activate` — License activation

### Edit Form (Device Detail)
5 tabs with 46 editable fields:
- **SIM (11):** IMEI1, IMEI2, IMSI, ICCID, phone number, SIM operator, network type...
- **Device (19):** Android ID, GSF ID, device model, manufacturer, brand, build fingerprint, build ID, SDK, OS version, radio, incremental, security patch...
- **Network (5):** WiFi MAC, Bluetooth MAC, IP, gateway, DNS
- **Geo (3):** Latitude, longitude, timezone
- **Other (8):** Display density, resolution, RAM, storage...

Each field: `label | current value | ☐ checkbox` — only checked fields get submitted.

### Anti-Windows-Bugs
- `cmdHide()` wrapper cho mọi `exec.Command("adb", ...)` → `SysProcAttr.HideWindow = true`
- Stderr redirect to log file, no console flash
- `log.Fatal` → MessageBox trên Windows
- `.zmmo` dir: `%APPDATA%` → `%LOCALAPPDATA%` → `~/` fallback

### Build & Cross-Compile
```bash
cd packages/manager-agent

# Windows (systray + hide console)
GOOS=windows GOARCH=amd64 go build -ldflags="-H windowsgui -s -w" -o assets/zmmo-agent-windows-amd64.exe .

# macOS Intel
GOOS=darwin GOARCH=amd64 go build -ldflags="-s -w" -o assets/zmmo-agent-darwin-amd64 .

# macOS Apple Silicon
GOOS=darwin GOARCH=arm64 go build -ldflags="-s -w" -o assets/zmmo-agent-darwin-arm64 .

# Linux
GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" -o assets/zmmo-agent-linux-amd64 .

# Copy to panel public dir
cp assets/zmmo-agent-* ../panel/public/agent-binaries/
```

### Post-Build Checklist
1. Bump version in `server.go` (`const version = "1.1.x"`)
2. Bump version in `panel/src/app/downloads/page.tsx` (`const VERSION = "1.1.x"`)
3. Build + copy binaries (above)
4. `cd packages/panel && npm run build`
5. Restart panel: `fuser -k 3013/tcp && npx next start -p 3013 -H 0.0.0.0`

## Current Version
**v1.1.1** — binaries at `http://100.87.34.74:3013/downloads`
