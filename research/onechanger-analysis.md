# OneChanger v4.1.0b — Complete Reverse Engineering

> **File:** `OneChangerSetup.v4.1.0b.exe` (189MB)
> **Location:** `/mnt/data/Downloads/`
> **Extracted:** `/tmp/onechanger/`
> **Date:** 2026-08-09

---

## 1. EXTRACTION

```bash
# Same innoextract 1.10-dev used for MiChanger
mkdir /tmp/onechanger && cd /tmp/onechanger
/tmp/innoextract/build/innoextract /mnt/data/Downloads/OneChangerSetup.v4.1.0b.exe
```

---

## 2. ARCHITECTURE OVERVIEW

```
┌────────────────────────────────────────────────────────────────┐
│                    OneChanger.exe (.NET Core, 57MB)              │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  API Layer (HTTP localhost:8000)                         │   │
│  │  APIChangeDeviceInfo, APIChangeSimInfo, APIBackupDevice  │   │
│  └──────────────────────┬──────────────────────────────────┘   │
│                         │                                        │
│  ┌──────────────────────▼──────────────────────────────────┐   │
│  │  Change Engine                                           │   │
│  │  ChangeInfoAsync → ApplyChanges → PropertySetters        │   │
│  │  set_Imei, set_IMSI, set_ICCID, set_DeviceId...         │   │
│  └──────────────────────┬──────────────────────────────────┘   │
│                         │                                        │
│  ┌──────────────────────▼──────────────────────────────────┐   │
│  │  Hook Engine (native hooks)                              │   │
│  │  Nhook, Trthook, rthook, rfishhook, epsilon hook...     │   │
│  └──────────────────────┬──────────────────────────────────┘   │
│                         │                                        │
│  ┌──────────────────────▼──────────────────────────────────┐   │
│  │  UI Automation                                           │   │
│  │  OpenCV + SkiaSharp + Tesseract OCR + xml-processor     │   │
│  │  ExecuteScript, ExecuteGmailLogin, ExecuteReadText       │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Screen Mirroring (3 engines)                             │   │
│  │  - BasicScrcpy (SDL2 scrcpy)                              │   │
│  │  - QtScrcpy (Qt5 fork with gaming keymaps)                │   │
│  │  - ws-scrcpy (WebSocket scrcpy via Node.js)               │   │
│  └─────────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────────┘
                                │
                      ADB / USB / WiFi
                                │
┌───────────────────────────────▼────────────────────────────────┐
│                       ANDROID DEVICE                            │
│                                                                  │
│  ┌────────────────────┐  ┌──────────────────────┐              │
│  │ info.apk (21MB)    │  │ com.mi.utility.apk   │              │
│  │ "OneService"       │  │ VPN/SOCKS tunnel     │              │
│  │ Overlay UI (Jetpack │  │ tun2socks + pdnsd    │              │
│  │  Compose)           │  │ + dnssocks           │              │
│  └────────────────────┘  └──────────────────────┘              │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Zygisk Next Module (zygisksu.zip)                       │   │
│  │  - libzygisk.so (985KB): Zygisk hook framework           │   │
│  │  - libpayload.so (3KB): Custom hook payload              │   │
│  │  - zygiskd: Zygisk daemon                                │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  ┌────────────────────┐                                        │
│  │ KernelSU v1.0.1    │  Root manager                           │
│  └────────────────────┘                                        │
│                                                                  │
│  ┌────────────────────┐                                        │
│  │ Tricky Store OSS   │  Play Integrity bypass (TEE spoof)     │
│  └────────────────────┘                                        │
└────────────────────────────────────────────────────────────────┘
```

---

## 3. COMPONENT BREAKDOWN

### 3.1 OneChanger.exe (57MB) — .NET Core Application

**Tech Stack:**
- .NET Core (aspnetcore v2 in-process hosting)
- SkiaSharp (2D graphics)
- HarfBuzz (text shaping)
- OpenCV (computer vision — opencv_videoio_ffmpeg, OpenCvSharpExtern)
- AdvancedSharpAdbClient (ADB .NET library — SAME as MiChanger/DOMA!)

**Key Methods (from .NET async method names in strings):**

```csharp
// ── API Layer ──
APIChangeDeviceInfo()       // POST /change?serial=X&filter_brand=Y
APIChangeSimInfo()          // POST /changeSimOnly?serial=X
APIBackupDeviceInfo()       // POST /backup?serial=X
APIRestoreDeviceInfo()      // POST /restore?serial=X
APIUpdateIntegrityFix()     // POST /updateIntegrityFix?serial=X
APIGetListBackupFile()      // GET  /getList?type=Pixel3a
APIPublicIP()               // GET  /publicIP?serial=X

// ── Change Engine ──
RandomAndChangeAsync()      // Random device + apply
ChangeDeviceInfoAsync()     // Apply device info
ChangeInfoAsync()           // Apply all changes
ChangeInfoProcessAsync()    // Change workflow
ChangeSimInfo()             // SIM-only change
ApplyChanges()              // Commit property changes
SettingBeforeChange()       // Pre-change setup (clear cache, stop apps)

// ── Backup Engine ──
BackupAndChange()           // Backup then change
BackupAndChangeAll()        // Backup all + change all
BackupOnly()                // Backup only

// ── Module Management ──
InstallModuleManual()              // Install Magisk/KSU modules
DownloadAndInstallFixModuleAsync() // Auto-download + install PIF
EnableSUManagerForMultipleAsync()  // Enable root manager
FixWalletAsync()                   // Fix Google Wallet

// ── SOCKS/Proxy ──
ConfigSOCKS5()             // Setup SOCKS5 proxy
ExecuteConfigSock()        // Apply SOCKS config
ExecuteClearSock()         // Remove SOCKS config

// ── UI Automation ──
ExecuteScript()            // Run automation script
ExecuteGmailLogin()        // Auto Gmail login
ExecuteClickToText()       // OCR + click
ExecuteReadText()          // Read text from screen

// ── Connection ──
ConnectAsync()
DisconnectAsync()
ClearConnectionAsync()
GetOrCreateConnection()
```

**Property Model (C# get/set):**

```
Hardware Identity:
├── set_Imei / set_Imei1              IMEI slot 0/1
├── set_DeviceId / get_DeviceId        Device unique ID
├── set_Baseband                       Baseband version
├── set_RadioVersion                   Radio firmware version
├── set_Brand / set_Model / etc.       Build properties

SIM Identity:
├── set_IMSI                           Subscriber ID
├── set_ICCID                          SIM serial number
├── set_SimPhoneNumber                 MSISDN (phone number)
├── set_SimOperatorNumeric             MCC+MNC
├── set_SimOperatorCountry             Country ISO
├── set_SimOperatorName                Carrier name
├── set_SimOperatorCode                SIM operator code
├── set_SubScriberId                   Subscriber ID (alt)

Network:
├── set_WifiMacAddress                 WiFi MAC
├── set_BlueToothMacAddress            Bluetooth MAC

Location:
├── set_Latitude / set_Longitude / set_Altitude

Google:
├── set_AndroidId                      Android ID
├── set_Gaid                           Google Advertising ID
├── set_Gsf                            GSF ID

Other:
├── set_Timezone
├── set_SafetyNet
```

### 3.2 stream-phonefarm (Node.js) — Web Panel

**Actually: ws-scrcpy v0.9.0 (open source!)**

```json
{
  "name": "ws-scrcpy-server",
  "version": "0.9.0-dev",
  "dependencies": {
    "@dead50f7/adbkit": "2.11.5",   // ADB client fork
    "express": "4.22.1",            // HTTP server
    "portfinder": "1.0.38",         // Port discovery
    "ws": "8.18.3",                 // WebSocket
    "yaml": "2.8.2"                 // YAML parser
  }
}
```

**API Routes:**

```
Device Management:
  POST /api/devices/connect              Connect to device via ADB
  POST /api/device/keep-awake            Keep screen on

File Transfer:
  POST /api/sync                         ADB sync (push/pull)
  POST /api/sync/set                     Set sync config
  POST /api/sync/clear                   Clear sync state

Remote Shell:
  POST /api/goog/device/shell            Execute shell command
  POST /api/goog/device/pid              Get process PID
  POST /api/goog/device/restart          Restart device

App Install:
  POST /api/goog/device/install-apk      Install APK
  POST /api/goog/device/install-apk-binary  Install binary
  POST /api/goog/device/send-binary      Push binary to device

Screen Recording:
  POST /api/recordings/start|stop|pause|resume
  POST /api/recordings/delete|run|update-name

Streaming:
  GET  /api/stream-stats                 Stream statistics

Health:
  GET  /api/ping                         Health check
```

**Role:** Web-based scrcpy + ADB control panel. Provides screen mirroring + device management from browser. Does NOT contain spoof logic.

### 3.3 info.apk (21MB) — OneService Overlay

**Package:** `com.android.info`
**Label:** "OneService"
**Type:** Jetpack Compose UI app (20MB DEX total: 12MB classes.dex + 7MB classes2.dex)

**Manifest:**
```xml
<manifest package="com.android.info" compileSdkVersion="34">
  <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
  <uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW"/>
  <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>
  <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"/>
  <application label="OneService">
    <service android:name="com.android.info.OverlayService" exported="true"/>
  </application>
</manifest>
```

**Smali analysis:** All 872 non-framework classes are standard Kotlin/Compose/library code. Only custom classes:
- `com.android.info.R` — Resources (auto-generated)
- `com.android.info.OverlayService` — Foreground overlay service

**Role:** Overlay UI for the device. Shows device info/status on screen. Does NOT contain spoof/hook logic. NO native .so libraries. NO Xposed/LSPosed integration.

### 3.4 zygisksu.zip (3.4MB) — Zygisk Next + Custom Payload

```
zygisksu.zip/
├── bin/arm64-v8a/zygiskd        [840KB]  Zygisk daemon
├── lib/arm64-v8a/libzygisk.so   [985KB]  Zygisk hook framework
├── lib/arm64-v8a/libzn_loader.so [59KB]  Zygisk Next loader
├── lib/arm64-v8a/libpayload.so   [3KB]   ** CUSTOM HOOK PAYLOAD **
└── *.sha256                               Integrity checks
```

**Key:** `libpayload.so` (3KB) is a small custom native library. This is likely:
- The actual IMEI/IMSI hook implementation
- Small size (3KB) suggests it hooks a single method and reads from a config file
- Loaded by Zygisk at boot into the zygote process
- Injected into every app that uses TelephonyManager

### 3.5 com.mi.utility.apk (1.5MB) — VPN/SOCKS Tunnel

```
com.mi.utility.apk/
├── classes.dex              [30KB]   Java UI
├── libtun2socks.so          [170KB]  TUN→SOCKS5
├── libpdnsd.so              [209KB]  DNS proxy
├── libdnssocks.so           [379KB]  DNS→SOCKS5
└── libsystem.so              [13KB]  System helper
```

**Role:** VPN app that routes ALL device traffic through SOCKS5 proxy. Same pattern as MiChanger's CPIDNGSocks.apk and DOMA's Bproxy3.apk.

### 3.6 KernelSU_v1.0.1.apk (8.1MB)

Standard KernelSU root manager. Newer version than DOMA's v0.6.2.

### 3.7 Tricky Store OSS (via modules.json)

Open-source Play Integrity bypass. Spoofs the TEE (Trusted Execution Environment) keystore to pass Play Integrity checks.

### 3.8 Tesseract OCR + Leptonica

Full OCR stack:
- `libtesseract-5.dll` (3.2MB)
- `leptonica-1.82.0.dll` (4.0MB) + `leptonica-1.83.0.dll` (2.6MB)
- `libicudt73.dll` (31MB) + `libicudt75.dll` (30MB) — ICU data for text processing

**Role:** Screen text recognition for automation — read captcha, recognize buttons, read Google 2FA codes.

---

## 4. SPOOF MECHANISM

### Confirmed: Zygisk Hook (NOT Frida!)

OneChanger uses **Zygisk Next** as the hook framework instead of Frida:

```
Boot sequence:
  1. KernelSU loads at boot → grants root
  2. Zygisk Next (zygisksu.zip) loads as Magisk module
  3. Zygisk injects into zygote process
  4. libpayload.so hooks into system_server

Change sequence (via OneChanger.exe):
  1. User clicks "Change" → OneChanger.exe sends commands
  2. ADB shell: resetprop ro.product.model XXX
  3. ADB shell: settings put secure android_id YYY
  4. ADB shell: ip link set wlan0 address ZZ:ZZ
  5. libpayload.so: updates shared memory / config file
  6. Next app call to getDeviceId() → hooks intercept → return fake
```

### Frida vs Zygisk Comparison

| | Frida (MiChanger Pro) | Zygisk (OneChanger) |
|---|---|---|
| **Runtime** | Dynamic injection | Static boot injection |
| **Lifetime** | Until process/kill | Permanent (until reflash) |
| **Persistence** | Restart after reboot | Auto-loaded after reboot |
| **Detection** | Process + port visible | No extra process (in zygote) |
| **Maintenance** | Replace JS script | Replace module ZIP |
| **Setup** | Push binary + start | Flash once, works forever |
| **Specificity** | Per-app injection | System-wide (all apps) |

---

## 5. COMPLETE ONE CHANGER API

```bash
# ── Device Info Change ──
POST http://localhost:8000/change?serial={SERIAL}
    &filter_brand=samsung
    &filter_model=SM-G960F
    &filter_os=10
    &filter_country=us
    &filter_carrier=T-Mobile-10
    &custom_carrier=T-Mobile|310160
    &lat=37.7749&long=-122.4194
    &factory_reset=True|False

# ── SIM Only Change ──
POST http://localhost:8000/changeSimOnly?serial={SERIAL}
    &filter_country=us
    &filter_carrier=T-Mobile-10
    &wipe=True|False

# ── Backup ──
POST http://localhost:8000/backup?serial={SERIAL}
    &note=Auto_backup
    &filename=backup_file
    &full=True|False

# ── Restore ──
POST http://localhost:8000/restore?serial={SERIAL}
    &filename=BACKUP_NAME
    &gmail=user@gmail.com

# ── List Backups ──
GET http://localhost:8000/getList?type=SamsungS9v10

# ── SOCKS5 Config ──
POST http://localhost:8000/configSock?serial={SERIAL}
    &sock=192.168.5.248:40000

# ── Clear SOCKS ──
POST http://localhost:8000/clearSock?serial={SERIAL}

# ── Install APK ──
POST http://localhost:8000/installApk?serial={SERIAL}
    &file=D:\Apps\telegram.apk

# ── Update Play Integrity Fix ──
POST http://localhost:8000/updateIntegrityFix?serial={SERIAL}

# ── Public IP ──
GET http://localhost:8000/publicIP?serial={SERIAL}

# ── Google Offer Redirect ──
POST http://localhost:8000/redirectOfferLink?serial={SERIAL}
    &open=true|false
```

### Automation Scripts

```
AutoScripts/
├── change_info.js      → Api("http://localhost:8000/change?...")
├── autobackup.js       → Api("http://localhost:8000/backup?...")
├── config_sock.js      → Api("http://localhost:8000/configSock?...")
├── login_google.js     → Api("http://localhost:8000/loginGoogle?...")
├── install_apk.js      → Api("http://localhost:8000/installApk?...")
├── image_to_text.js    → OCR + ADB shell uiautomator
└── copy_file_to_sdcard.js → ADB push
```

---

## 6. SUPPORTED DEVICE ROMs

From `modules.json`:
```
SamsungS9v10            Samsung Galaxy S9, Android 10
SamsungS9v12            Samsung Galaxy S9, Android 12
SamsungS9v13            Samsung Galaxy S9, Android 13
SamsungS9v16            Samsung Galaxy S9, Android 14+ (GSI?)
SamsungS9Plusv10        Samsung Galaxy S9+, Android 10
SamsungS9Plusv12        Samsung Galaxy S9+, Android 12
Pixel3av12              Google Pixel 3a, Android 12
Pixel3av13              Google Pixel 3a, Android 13
Pixel4XLv12             Google Pixel 4 XL, Android 12
```

---

## 7. COMPARISON: ALL TOOLS

| | DOMA | MiChanger Pro | MiChanger Plus | OneChanger |
|---|---|---|---|---|
| **Size** | ~200MB ROM | 59MB | 55MB | 189MB |
| **Hook method** | changedevice (EFS) | **Frida** (JS inject) | ❌ resetprop only | **Zygisk** (libpayload.so) |
| **IMEI spoof** | ✅ EFS write | ✅ Frida hook | ❌ | ✅ Zygisk hook |
| **IMSI spoof** | ✅ filesystem | ✅ Frida hook | ❌ | ✅ Zygisk hook |
| **ICCID spoof** | ✅ filesystem | ✅ Frida hook | ❌ | ✅ Zygisk hook |
| **Screen mirror** | scrcpy modded | scrcpy (SDL2) | scrcpy x3 | scrcpy + QtScrcpy + ws-scrcpy |
| **OCR/Automation** | ❌ | ❌ | ❌ | ✅ OpenCV + Tesseract |
| **Web panel** | ❌ | ❌ | ❌ | ✅ stream-phonefarm |
| **Gaming** | ❌ | ❌ | ❌ | ✅ Keymaps (TikTok, PUBG) |
| **API** | ADB direct | 13 endpoints | 9 endpoints | 13+ endpoints |
| **Stealth** | Very high | Low | High | High |
| **Root** | KernelSU 0.6.2 | Magisk Kitsune | Magisk | KernelSU 1.0.1 |

---

## 8. KEY INSIGHTS FOR ZMMO

### OneChanger is the most complete tool

It has everything:
- Zygisk hooks (permanent, no Frida detection risk)
- Full OCR automation (captcha, 2FA, form filling)
- Web-based control panel (stream-phonefarm)
- 3 different screen mirroring engines
- Gaming keymaps
- Custom automation scripts in JS
- Node.js runtime for scripting

### Zygisk approach > Frida for ZMMO

| | Why Zygisk wins |
|---|---|
| **Persistence** | Survive reboot, no need to restart |
| **Detection** | No extra process, no open port |
| **Integration** | droid-agent manages config → libpayload.so reads it |
| **Size** | libpayload.so = 3KB (vs Frida 51MB) |
| **License** | Zygisk is open source (no Frida commercial license) |

### Architecture for ZMMO Zygisk module

```go
// droid-agent writes spoof.json
// libpayload.so (3KB C code) at boot:
//   1. Reads /data/local/tmp/zmmo/spoof.json
//   2. Hooks TelephonyManager.getDeviceId() via Zygisk API
//   3. Returns fake IMEI/IMSI/ICCID from config
//   4. Listens for SIGUSR1 → reload config
```

---

## 9. FILES ARCHIVE

| File | Location |
|------|----------|
| OneChanger extracted | `/tmp/onechanger/` |
| OneChanger.exe | `/tmp/onechanger/app/OneChanger.exe` |
| info.apk (OneService) | `/tmp/onechanger/app/Resources/info.apk` |
| info.apk smali | `/tmp/onechanger/info-apk-smali/` |
| zygisksu.zip (Zygisk + payload) | `/tmp/onechanger/app/Resources/modules/zygisksu.zip` |
| com.mi.utility.apk (VPN) | `/tmp/onechanger/app/Resources/com.mi.utility.apk` |
| stream-phonefarm (ws-scrcpy) | `/tmp/onechanger/app/Resources/stream-phonefarm/` |
| AutoScripts | `/tmp/onechanger/app/Resources/AutoScripts/` |
| modules.json | `/tmp/onechanger/app/Resources/modules/modules.json` |
| KernelSU | `/tmp/onechanger/app/Resources/KernelSU_v1.0.1_11928-release.apk` |
