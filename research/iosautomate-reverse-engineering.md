# iOSAutomate v1.0.5 — Reverse Engineering

> Source: `https://iosautomate.com/repo` — Author: nvfrk
> Package: `com.nvfrk.rh.iOSAutomate` (1.4MB deb)
> Variants: roothide (ellekit) + rootless

## What It Is

**iOSAutomate** is a full-featured **iOS automation farm framework** — essentially an open-source CloudiPhone competitor. It provides:
- Lua scripting engine for iOS automation
- Web IDE accessible from any browser
- MCP (Model Context Protocol) server for AI agent control
- App farming: bulk account creation, management, feeding
- Device control: touch, OCR, image recognition, proxy, location spoof

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Web IDE (browser) or MCP Client (AI agent)                 │
│ ↓ WebSocket / HTTP SSE                                      │
├─────────────────────────────────────────────────────────────┤
│ WSDaemon (/usr/bin) — WebSocket Server                      │
│ • Unix socket: /var/tmp/wsd.sock (launchd-managed)         │
│ • Lua 5.3/5.4 engine embedded                               │
│ • Script execution: .ate, .lua, .fna files                  │
│ • 60+ built-in functions                                     │
├─────────────────────────────────────────────────────────────┤
│ i4d68...dylib — System-level hooks                          │
│ • Injected via MobileSubstrate (arm64 + arm64e)             │
│ • GCDWebServer: embedded HTTP server for file/images        │
│ • Vision framework: OCR (VNRecognizeTextRequest)            │
│ • Photos framework: screenshot capture/management           │
│ • UI overlays: dialogs, pickers, floating button            │
│ • Audio feedback: AVAudioPlayer                             │
├─────────────────────────────────────────────────────────────┤
│ wsfkl (/usr/bin) — Helper binary (arm64)                    │
│ • Fast key lookup / crypto helper?                          │
└─────────────────────────────────────────────────────────────┘
```

## Daemon (WSDaemon)

### LaunchDaemon Configuration
```
User: root (wheel group)
Priority: Nice -5 (high), JetsamPriority 21
Socket: /var/tmp/wsd.sock (Unix domain, mode 777)
Environment: DISABLE_TWEAKS=1, PATH=/var/jb/usr/bin:...
Working Dir: /var/jb/var/mobile/Library/iOSAutomate
Log: /var/log/wsdaemon.log

Anti-competition: kills duetexpertd every 30 seconds
  (duetexpertd = Siri/Duet heuristic daemon, consumes CPU)
```

### Tech Stack
- Built from: `/home/adminn/Downloads/HTTP8888/WSDaemonSub/`
- Uses `launch_activate_socket()` to receive fd from launchd
- Links against: IOKit, CoreFoundation, Security, UIKit

## Dylib (i4d6808657473a2995ee46m7c9c7431.dylib)

### Name Obfuscation
The dylib filename is obfuscated: `i4d6808657473a2995ee46m7c9c7431`
Pattern: `i4d` + 26 hex chars — looks like a truncated SHA-256 or UUID hash.
This is anti-reverse-engineering: prevents tweak conflict detectors from easily identifying it.

### Embedded Web Server (GCDWebServer)
The dylib runs its own **GCDWebServer** instance — a full HTTP server:
```
GCDWebServer
├── GCDWebServerConnection
├── GCDWebServerDataRequest/Response
├── GCDWebServerFileRequest/Response
├── GCDWebServerURLEncodedFormRequest
├── GCDWebServerMultiPart (file uploads)
├── GCDWebServerGZipDecoder/Encoder (compression)
└── GCDWebServerStreamedResponse (SSE for MCP)
```

### OCR Engine (Apple Vision)
```
VNRecognizeTextRequest → OCR text from screen region
VNImageRequestHandler  → Image processing pipeline
```
Used for: `findText()`, `tapText()` — read text on screen and tap it.

### Screenshot Pipeline (Photos)
```
PHPhotoLibrary          → Access photo library
PHAsset                → Image asset management
PHAssetCreationRequest  → Save screenshots
PHFetchOptions         → Filter/search images
```
Used for: `findImage()` — capture screen, search for template image.

### UI Overlays ("Modern Dialog")
The dylib can render native UI elements:
```
UIAlertController      → System alerts
UIPickerView           → Selection pickers
UISegmentedControl     → Tabbed controls
UITableView            → List views
WSDialogRow            → Custom dialog row component
WSRowView              → Custom row view
WSSelectView           → Selection view
```
This is the "modern dialog" / "intelligent tool UI" feature.

### Substrate Hooks
```
MSHookFunction   → C function hooks
MSHookMessageEx  → ObjC method hooks
```
Used for: intercepting touch events, keyboard input, app lifecycle.

## Functions (60+ built-in)

### App Farming (BASIC-Paid tier)
| Function | Description |
|----------|-------------|
| `openAcc(bundleID, accName)` | Open app with specific account profile |
| `backupAcc(bundleID, accName)` | Backup app data for account |
| `restoreAcc(bundleID, accName)` | Restore app data for account |
| `deleteAcc(bundleID, accName)` | Delete account data |
| `CleanAllAcc(bundleID)` | Wipe ALL accounts for app |
| `resetApp(bundleID)` | Full app data reset |

### Device Control
| Function | Description |
|----------|-------------|
| `clearLocation()` | Clear spoofed location |
| `fakeLocation(lat, lon)` | Set fake GPS location |
| `setProxy("ip:port:user:pwd")` | Set HTTP/HTTPS proxy |
| `getCookie()` | Extract auth cookie/token |
| `getCookie(bundleID)` | Get cookie from specific app (EXTRA-Paid) |

### Touch & Input
| Function | Description |
|----------|-------------|
| `coord(x, y)` | Touch at coordinates |
| `findColor(color, region)` | Find color on screen |
| `findImage(template, threshold)` | Image recognition |
| `findText(region)` | OCR text from screen |
| `tapText(text)` | Find + tap text on screen |
| `Zoom(level)` | Control zoom |

### Script Management
| Function | Description |
|----------|-------------|
| `require(module)` | Import Lua modules |
| `async(fn)` | Run async on main thread |
| `stop()` | Stop current script |
| `stopAsync()` | Stop async operations |
| `stopAll()` | Stop all scripts |
| `execute('reboot')` | Reboot device |

### IDE & UI
| Function | Description |
|----------|-------------|
| `OpeniOSAutomate(tab_index)` | Open IDE floating button |
| `CloseiOSAutomate()` | Close floating button |

### Network
| Function | Description |
|----------|-------------|
| `socket.http` | HTTP client |
| `socket.ssl` | HTTPS client |
| `ltn12` | Lua socket library |
| `wget(url)` | Download file |
| `curl(url)` | HTTP request |

### Performance
```
Real-time overlay: RAM, CPU, Storage stats
ZOMBIE MODE: Big Farm optimization (like CloudiPhone)
```

## MCP Server (AI Agent Control)

iOSAutomate implements **Model Context Protocol** (SSE transport):
```
MCP Server URL: http://localIP:port/sse
Exposes: All 60+ functions as MCP tools
AI can: see screen (OCR), tap, type, swipe, read app state
```

This is the "BIG UPDATE: MCP got a brain" feature — an AI agent can control the iPhone through standardized MCP protocol, making it usable with Claude, GPT, or any MCP-compatible agent.

## Access Methods

1. **Web IDE**: Browser-based code editor with syntax highlighting
   - Port forwarded via USB/WiFi
   - Real-time script execution
   - One-click backup (export all scripts as timestamped zip)
   - Dark/Light theme toggle

2. **Floating Button**: On-device control overlay
   - No PC/browser needed
   - Quick access to scripts and controls

3. **MCP API**: AI agent control via SSE
   - Standardized Model Context Protocol
   - Full device automation from AI

4. **20+ Local APIs**: Programmatic control
   - HTTP endpoints for external automation
   - Port-forward support for farm setups

## Storage

```
Working directory: /var/jb/var/mobile/Library/iOSAutomate
  ├── scripts/        # Lua scripts (.ate, .lua, .fna)
  ├── modules/        # Lua modules (require())
  ├── store/          # Store scripts (Free, Paid, Your Scripts)
  ├── backups/        # App data backups (Acc)
  └── temp/           # Screenshots, OCR cache
```

## Proxy Integration

```
Function: setProxy("ip:port:user:pwd")
Applies system-wide proxy via CFNetwork:
  HTTPEnable, HTTPPort, HTTPProxy, HTTPProxyAuthenticated
  HTTPSEnable, HTTPSPort, HTTPSProxy
  HTTPProxyUsername, HTTPProxyPassword
```

## Comparison: iOSAutomate vs CloudiPhone vs XoaInfo

| Feature | iOSAutomate | CloudiPhone | XoaInfo |
|---------|------------|-------------|---------|
| **Price** | Open source (paid tiers) | Enterprise ($1000+) | Paid |
| **Scripting** | Lua 5.3/5.4 | Custom | None |
| **AI Agent** | MCP (standard) | Custom API | None |
| **IDE** | Web-based | Web-based | Native app |
| **Farming** | Acc backup/restore/feed | Full farm mgmt | RRS only |
| **OCR** | Apple Vision | Custom | None |
| **Image find** | Vision + template | Custom | None |
| **Proxy** | System CFNetwork | Per-app VPN | SOCKS5 |
| **GPS** | System location | System location | CLLocation hook |
| **Device spoof** | None | Yes | Yes (model,IMEI) |
| **Size** | ~1.4MB | ~50MB+ | ~5MB |

## Security Concerns

1. **Runs as root** with high priority — full system access
2. **Kills system daemons** (duetexpertd) for CPU
3. **Obfuscated dylib name** — anti-detection
4. **Cookie extraction** (getCookie) — session hijacking
5. **No server-side auth** — anyone with socket access can control device
6. **GCDWebServer embedded** — potential remote exploit surface
