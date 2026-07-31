# iOSAutomate Remote v1.0.5 — Reverse Engineering

> Source: `https://iosautomate.com/repo` — Author: Franky Nouva (nvfrk)
> Package: `com.nvfrk.rh.Remote` (380KB deb)

## What It Is

**Remote** is a full **VNC-style remote desktop** for iPhone with screen mirroring, touch control, and audio streaming — all accessible from any browser. It's the companion tool to iOSAutomate that provides the visual interface for remote device control.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Web Browser (any device)                                     │
│ ├── Screen mirror (live stream via WebSocket)               │
│ ├── Touch controls (swipe, home, power, volume)             │
│ ├── Clipboard (get/set)                                      │
│ ├── Microphone audio streaming                               │
│ ├── Media import/export                                      │
│ ├── Screenshot capture                                       │
│ └── Farm View (multi-device dashboard)                      │
│ ↓ WebSocket (port 8000) / HTTP (port 8888)                  │
├─────────────────────────────────────────────────────────────┤
│ Remote dylib (injected into SpringBoard)                    │
│ ├── Screen capture: CARenderServerRenderDisplay (GPU)       │
│ ├── Input injection: autotouch + gesture APIs                │
│ ├── Audio capture: AVAudioEngine + WebSocket stream         │
│ ├── WebSocket server: custom WebSocket implementation       │
│ └── Watchdog: wswatch LaunchDaemon (auto-reboot)            │
└─────────────────────────────────────────────────────────────┘
```

## Components

### 1. Main Dylib (05070de4bwst6c9e6499.dylib)

**Obfuscated name** like iOSAutomate's dylib — anti-detection pattern.
**Target**: SpringBoard (not Bundles — hooks at executable level)
**Architectures**: arm64 + arm64e

#### Screen Capture (GPU-level)
```
CARenderServerRenderDisplay   — GPU framebuffer capture (lowest latency)
CARenderServerGetDirtyFrameCount — Only capture changed frames
CADisplayLink                — Synchronize with display refresh
cachedScreenBounds           — Screen dimensions cache
broadcastFrame:phoneID:      — Send frame to connected clients
captureFrameNow               — Force immediate capture
```

#### Input Injection
```
autotouch inputText <text>           — Type text via AutoTouch
autotouch play start <script>.ate    — Run AutoTouch scripts
autotouch play start setClipboard.ate — Set clipboard via AutoTouch
```

#### Audio Streaming
```
AVAudioEngine         — Audio capture engine
AVAudioConverter      — Audio format conversion
AVAudioSession        — Audio session management
AVAudioPCMBuffer      — Raw audio buffer
Audio polling loop    — Send audio chunks via WebSocket
```

#### WebSocket Server
```
Active connections tracking
Frame broadcasting to multiple clients
Binary frame encoding (likely JPEG/MJPEG)
Touch event → gesture translation
```

### 2. Watchdog (wswatch LaunchDaemon)

A self-healing watchdog that runs every 30 seconds:

```bash
# Check if Remote ports are alive
F=/tmp/wswatch_fail
if (echo>/dev/tcp/127.0.0.1/8000)2>/dev/null && 
   (echo>/dev/tcp/127.0.0.1/8888)2>/dev/null; then
    rm -f $F; sleep 500          # Ports alive → all good
else
    n=$(cat $F 2>/dev/null || echo 0)
    n=$((n+1)); echo $n>$F
    [ $n -eq 2 ] && uialert -b "optimize system, reboot after 60s" -p "OK" "Warning"
    [ $n -ge 3 ] && rm -f $F && launchctl reboot userspace  # Force reboot!
fi
```

**Logic**: 
- Port 8000 = screen streaming | Port 8888 = control/API
- 2 consecutive failures → user alert
- 3 consecutive failures → TrollStore userspace reboot (auto-recovery)

### 3. Floating Button UI

The dylib renders a native floating button on the device screen:
- **SwipeU/SwipeD/SwipeRight/SwipeLeft** — direction swipes
- **Home** — go home
- **Clear/Clean** — clear screen
- **VolU/VolD** — volume control
- **Power** — lock screen
- **Network** — network toggle
- **Notifications** — notification panel
- **Clipboard** — clipboard access
- **Microphone** — audio streaming toggle
- **Media** — import/export files
- **Farm View** — multi-device farming dashboard

### 4. Web Interface (Obfuscated JS)

The entire web control panel is embedded as obfuscated JavaScript strings inside the dylib:

```
WebSocket connection handler: /bjbEfConnect
Screen stream: WebSocket binary frames (MJPEG/raw)
Touch → gesture protocol: JSON over WebSocket
Audio: bidirectional WebSocket stream
Phone mockup overlay: /images/iPhone.png
Author branding: "Author: Franky Nouva" + zalo.me/0933998772
```

## Port Map

| Port | Protocol | Purpose |
|------|----------|---------|
| **8000** | WebSocket | Screen streaming + bidirectional control |
| **8888** | HTTP + WebSocket | Control API + file transfer |

## Features

### Screen Mirroring
- GPU-level capture via `CARenderServerRenderDisplay` (fastest possible)
- Dirty frame detection → only send changed regions
- Adjustable quality/compression
- Phone mockup overlay

### Remote Touch
- Tap, swipe, long press via gesture APIs
- Home, power, volume buttons
- Multi-touch support (`com.apple.hid.multitouch.user-access`)

### Clipboard
- Get clipboard content
- Set clipboard content (via AutoTouch)
- Real-time sync

### Audio Streaming
- Device microphone → browser
- Toggle on/off
- Auto-off timer (60s after import)

### Media Management
- Import files to device
- Export files from device
- Clean up (delete transferred files)
- Progress bar with file count

### Screenshot
- Capture current screen
- Download as image

### Farm View
- Multi-device dashboard
- YouTube tutorial link
- Designed for phone farm management

### AutoTouch Integration
- Execute .ate scripts remotely
- Type text via AutoTouch
- Clipboard management via AutoTouch

## Security & Anti-Detection

1. **Obfuscated dylib name** — `05070de4bwst6c9e6499.dylib` (truncated hash)
2. **Obfuscated JS** — All web UI code is obfuscator.io style
3. **Whitespace-padded filenames** — `    05070de4bwst6c9e6499.dylib` (4 leading spaces)
4. **Hooks at executable level** — not Bundle filter, harder to detect
5. **Self-healing watchdog** — Auto-reboots if service fails
6. **User-warning on 2nd failure** — "optimize system" cover story

## Comparison: Remote vs Other VNC Solutions

| Feature | iOSAutomate Remote | Veency (classic) | AnyDesk (App Store) |
|---------|-------------------|------------------|---------------------|
| **Jailbreak** | Required | Required | Not required |
| **Capture method** | GPU render server | IOMobileFramebuffer | ReplayKit |
| **Audio** | Yes | No | Yes |
| **Web browser** | Yes (WebSocket) | No (VNC client) | Yes |
| **Auto-reboot** | Yes (watchdog) | No | No |
| **Farm view** | Yes | No | No |
| **Clipboard** | Yes | No | Yes |
| **Price** | Free (with iOSAutomate) | Free | Free |
| **Obfuscation** | Heavy | None | None |

## Integration with iOSAutomate Ecosystem

```
iOSAutomate          — Scripting engine + app farming
Remote               — Visual remote desktop
iOSAutomateEcosystem — Bridge plugin (SpringBoard integration)

Combined flow:
1. iOSAutomate runs Lua automation scripts
2. Remote provides visual screen + touch control
3. Ecosystem dylib hooks SpringBoard for deep integration
4. All controlled from a single web dashboard
5. Phone farm scenario: 1 browser = N devices
```
