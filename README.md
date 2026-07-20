# ZMMO — Device Identity Management Suite

## Structure (Monorepo)

```
zmmo/
├── packages/
│   ├── panel/            # Next.js 16 — Web UI (port 3013)
│   └── manager-agent/    # Go binary — Backend API (port 55555/55556)
├── docs/                 # Documentation & plans
└── package.json          # Workspace root
```

## Packages

### panel — Web Dashboard
- **Stack:** Next.js 16 + TypeScript + Tailwind v4 + shadcn/ui
- **Port:** 3013
- **Features:** Device list, property editing (34 props), ADB task runner, backup/restore, license management
- **Mobile-first:** Hamburger sidebar, card layouts, scrollable tabs

### manager-agent — Backend Binary
- **Stack:** Go 1.24
- **Port:** 55555 (fallback 55556)
- **Features:** ADB device detection, property read/write via `getprop`/`setprop`, task queue, backup/restore, license validation
- **API:** REST (see `packages/manager-agent/main.go` for full contract)

## Quick Start

### Panel (Web UI)
```bash
npm install
npm run dev          # → http://localhost:3013
```

### Agent (Backend)
Pre-built binaries in `assets/`:

| Platform | Binary |
|----------|--------|
| **Windows (x64)** | `assets/zmmo-agent-windows-amd64.exe` |
| **macOS (Intel)** | `assets/zmmo-agent-darwin-amd64` |
| **macOS (Apple Silicon)** | `assets/zmmo-agent-darwin-arm64` |
| **Linux (x64)** | `assets/zmmo-agent-linux-amd64` |

Or build from source:
```bash
cd packages/manager-agent
./build.sh
```

Agent listens on **port 55555** (auto-fallback 55556). Panel auto-connects on page load.

## API Contract

See `packages/panel/src/lib/api.ts` for the full TypeScript API client.
Agent endpoints: `GET/POST/PUT` on port 55555.

## License

Proprietary — ZMMO Device Changer
