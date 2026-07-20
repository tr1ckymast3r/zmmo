# ZMMO — Manager-Agent Backend Plan

## Overview

Manager-agent là binary backend (Go) chạy trên máy khách, expose REST API cho Panel UI.
Nhiệm vụ chính: quản lý thiết bị Android qua ADB, thay đổi identity (IMEI, props...), backup/restore, license.

## Architecture

```
┌─────────────────────┐     REST (CORS)     ┌─────────────────────┐
│   Panel (Next.js)   │ ◄──────────────────► │  Manager-Agent (Go) │
│   port 3013         │   localhost:55555    │  port 55555/55556   │
└─────────────────────┘                      └────────┬────────────┘
                                                      │ ADB
                                                      ▼
                                             ┌─────────────────────┐
                                             │  Android Devices    │
                                             │  (USB / TCP/IP)     │
                                             └─────────────────────┘
```

## API Endpoints (đã implement)

| Method | Path | Description |
|--------|------|-------------|
| GET | `/status` | Agent health + version + license + device count |
| GET | `/devices` | List all connected devices (ADB auto-detect) |
| GET | `/devices/:id` | Device detail + 34 props |
| PUT | `/devices/:id/props` | Update device properties |
| POST | `/devices/:id/apply` | Apply enabled props via `setprop` |
| GET | `/tasks` | List task queue |
| POST | `/tasks` | Create new task (adb/backup/restore/reboot...) |
| GET | `/tasks/:id` | Task status + output |
| POST | `/adb/:deviceId` | Raw ADB shell command |
| GET | `/backups` | List saved backups |
| POST | `/backups` | Create backup (snapshot all props) |
| POST | `/backups/:id/restore` | Restore props from backup |
| POST | `/license/activate` | License key validation |

## Device Properties (34 props, 5 categories)

### SIM (12 props)
`imei_slot1`, `imei_slot2`, `meid`, `imsi_slot1`, `imsi_slot2`, `iccid_slot1`, `iccid_slot2`, `phone_number`, `sim_operator`, `sim_operator_name`, `sim_country_iso`

### Device Identity (14 props)
`brand`, `model`, `manufacturer`, `device_name`, `hardware`, `fingerprint`, `serial_number`, `android_id`, `os_version`, `sdk_version`, `build_id`, `bootloader`, `radio_version`

### Network (4 props)
`mac_wifi`, `mac_bluetooth`, `wifi_ssid`, `wifi_bssid`

### Geo (3 props)
`latitude`, `longitude`, `altitude`

### Other (2 props)
`gsf_id`, `advertising_id`

## Phases to Complete

### Phase 1: IMEI / Baseband Modification ✅
- [x] Read props via `getprop`
- [x] Write props via `setprop`
- [ ] IMEI modification (requires root + engineermode / AT commands)
- [ ] Baseband version spoofing

### Phase 2: MAC / Network Spoofing
- [ ] MAC address change via `ip link set address`
- [ ] WiFi info spoofing
- [ ] Bluetooth MAC change

### Phase 3: Advanced Identity
- [ ] Android ID modification
- [ ] GSF ID + Advertising ID
- [ ] Build fingerprint spoofing
- [ ] Full device profile templates (Samsung S23, iPhone clone, etc.)

### Phase 4: Backup & Restore System
- [x] JSON backup (all props)
- [x] Restore from backup
- [ ] Incremental backup (only changed props)
- [ ] Backup versioning / history
- [ ] Cloud sync (optional)

### Phase 5: Task Queue & Scheduling
- [x] Basic task execution (adb/shell/reboot/backup/restore)
- [ ] Task priority queue
- [ ] Parallel tasks across multiple devices
- [ ] Task scheduling (cron-like)
- [ ] WebSocket push for real-time task updates

### Phase 6: License & Auth
- [x] Basic license validation
- [ ] Hardware ID binding
- [ ] Online activation server
- [ ] Trial / subscription tiers
- [ ] Offline license check

### Phase 7: Packaging & Distribution
- [ ] Cross-compile: Linux (amd64/arm64), Windows, macOS
- [ ] Systemd service / launchd plist
- [ ] Auto-updater
- [ ] Installer script (one-liner curl | bash)
- [ ] Signed binaries (code signing)

### Phase 8: Panel UI Polish
- [x] Dark theme, mobile-responsive
- [x] Device grid + sidebar
- [x] 5-tab property editor
- [x] Task runner
- [ ] Real-time device status (WebSocket)
- [ ] Multi-device batch operations
- [ ] Profile templates library
- [ ] Drag-and-drop profile import/export

## Current Status

| Item | Status |
|------|--------|
| Go backend core | ✅ v1.0.0 running |
| REST API | ✅ 13 endpoints |
| ADB integration | ✅ auto-detect + getprop/setprop |
| Panel UI | ✅ Next.js 16, port 3013 |
| Monorepo | ✅ zmmo/packages/{panel,manager-agent} |
| Git | ✅ initialized |
| Binary build | ✅ `go build -o manager-agent` |
| Cross-compile | ❌ |
| IMEI change | ❌ (needs root + research) |
| WebSocket | ❌ |

## Next Priority

1. **WebSocket real-time updates** — panel auto-refresh on device connect/disconnect
2. **IMEI research** — AT commands / enginemode for rooted devices
3. **Profile templates** — pre-made device profiles (common models)
4. **Cross-compilation** — build for Windows so client machines can run
