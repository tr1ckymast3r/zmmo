# Xóa Info v2.9 — Full Reverse Engineering

> Source: `XoaInfo_2.9_ReleaseLimitPUBLIC.deb` from `https://xoainfo.com/cydia`
> Author: Nguyễn Quang Vũ (ienthach) — ienthach87@gmail.com
> Target: iOS 7.0–16.x (Jailbreak + TrollStore via `xoainfo_hook.tipa`)
> Note: "ReleaseLimitPUBLIC" = bản public bị giới hạn tính năng so với bản trả phí

---

## Architecture: 4-Layer System

```
┌──────────────────────────────────────────────────────────┐
│ Layer 1: XoaInfo.app (GUI)                               │
│ 21 NIB ViewControllers — Vietnamese UI                   │
│ CPDistributedMessagingCenter → IPC to daemon + plugs     │
├──────────────────────────────────────────────────────────┤
│ Layer 2: XoaInfoD (/usr/libexec) — Daemon                │
│ Runs as mobile user, RocketBootstrap                     │
│ GCDAsyncSocket for local network communication           │
│ deviceFullInfo, reset, randomSerial, randomIMEID         │
├──────────────────────────────────────────────────────────┤
│ Layer 3: 4 MobileSubstrate dylibs                        │
│ Plug1: UIDevice + WebView + Locale/Cookie spoofing       │
│ Plug2: SpringBoard IPC + GCDAsyncSocket server           │
│ Plug3: profiled + MobileGestalt + IMEI/Serial hook       │
│ Plug4: SpringBoard+UIKit + CLLocation GPS hook           │
├──────────────────────────────────────────────────────────┤
│ Layer 4: iOS System Frameworks                           │
│ MobileGestalt, CoreTelephony, IOKit, AdSupport           │
│ Keychain, NSLocale, NSTimeZone, UIDevice, UIScreen       │
└──────────────────────────────────────────────────────────┘
```

## IPC Protocol

All communication uses **CPDistributedMessagingCenter** (RocketBootstrap):

```
App ──sendMessageName:userInfo:──▶ Daemon
App ◀──sendReply──                 Daemon

Daemon ──sendMessageName:userInfo:──▶ Plugs (cross-process)
```

Message names are **obfuscated** in the app binary:
- `l2qhWlRs:userInfo:` — unknown (likely device info request)
- `n3YyM9j0:userInfo:` — unknown (likely reset command)
- `r5FKDauh:userInfo:` — unknown (likely RRS backup)
- `r93ipORh:userInfo:` — unknown (likely RRS restore)
- `v64n5B8y:userInfo:` — unknown (likely kill/reset apps)
- `z9tyOcE1:userInfo:` — unknown (likely proxy/SSH)

Daemon message handlers (not obfuscated):
- `checkIP:withUserInfo:` — Check current IP address
- `killAppName:withUserInfo:` — Kill app by name
- `killOneApp:withUserInfo:` — Kill single app
- `openAppName:withUserInfo:` — Open app by bundle ID
- `runCommand:withUserInfo:` — Execute shell command
- `sendEmail:withUserInfo:type:` — Send email notification
- `changePermission:` — Change file permissions

---

## Device Change Flow (Fake Info)

### Step-by-step

```
1. User taps fake button in app (e.g. btnFakeModel)
2. App reads model database (Model-iPhone.plist — 26 models)
3. User selects target model from picker (PickerFake.nib)
4. App sends obfuscated IPC message to daemon
5. Daemon calls deviceFullInfo → gets current real device state
6. Daemon calls randomSerial, randomIMEID → generates new values
7. Daemon writes to config plist:
   /private/var/mobile/Library/Preferences/com.ienthach.XoaInfoConfig.plist
8. Daemon calls killAllAppOpenXoaInfo → kills daemon proxies/services:
   killall -9 accountsd akd AppStore appstored itunesstored itunescloudd
   killall -9 mDNSResponder networkd nsurlsessiond pkd configd
   killall -9 Preference Preferences wifid wirelessproxd mobileassetd
9. Plugs detect config change → begin returning fake values
```

### Fake Options (from app properties)

| Button | Property | Target | Data Source |
|--------|----------|--------|-------------|
| `btnFakeModel` | `fakeModel` | Model-iPhone.plist | 26 models (iPhone 4S→X) |
| `btnFakeVersion` | `fakeVersion` | SystemVersion.plist | iOS version |
| `btnFakeName` | `fakeName` | name.txt | 1930 random names |
| `btnFakeScreen` | `fakeScreen` | Model database | Resolution + scale |
| `btnFakeFullScreen` | `fakeFullScreen` | UIScreen hook | Custom resolution |
| `btnFakeCarrier` | `fakeCarrier*` | CarrierList | 1008 carriers |
| `btFakeLocation` | GPS coordinates | Plug4 CLLocation | lat/lng from picker |
| `btnFakeTimeZone` | Timezone | NSTimeZone hook | Selected timezone |
| `btOldIDFA` | Custom IDFA | AdSupport hook | Manual or API server |

### Carrier Database Format (CarrierList — 1008 entries)

```
Country|CarrierName|MCC|MNC|ISO|NetworkType
Afghanistan|AWCC|412|1|AF|GSM
```

App properties for carrier:
```
fakeCarrierName           → "AWCC"
fakeCarrierCountry        → "Afghanistan"
fakeCarrierISO            → "AF"
fakeCarriermobileCountryCode → "412"
fakeCarriermobileNetworkCode → "01"
fakeCarrierNetwork        → "GSM"
```

### Model Database Format (Model-iPhone.plist — 26 entries)

```
ModelID|Name|Resolution|Scale|RAM_GB
iPhone10,1|17 iPhone 8|D20AP|375x667|2|2
iPhone10,2|18 iPhone 8 Plus|D21AP|414x736|3|3
iPhone10,3|21 iPhone X|D22AP|375x812|3|3
```

---

## Plug Dylibs — Hook Details

### Plug1 (abcxyz — placeholder filter)

**Target**: Generic (all processes with `abcxyz` bundle — none by default)
**Hooks**:
- `UIDevice.model` → fake model
- `UIDevice.systemVersion` → fake version
- `UIDevice.name` → fake name
- `NSLocale.currentLocale` → fake locale
- `NSLocale.preferredLanguages` → fake language
- `NSTimeZone.localTimeZone` → fake timezone
- `NSHTTPCookieStorage` → cookie manipulation
- `NSURLCredentialStorage` → credential storage
- `UIWebView` → web view customization
- `NSUserDefaults` → preferences override

**IPC**: CPDistributedMessagingCenter
**Frameworks**: UIKit, WebKit, Foundation

### Plug2 (com.apple.springboard)

**Target**: SpringBoard
**Capabilities**:
- **GCDAsyncSocket** — local TCP socket server
- **ASIHTTPRequest** — HTTP client for API calls  
- **MBProgressHUD** — loading indicators in SpringBoard
- **RocketBootstrap** — cross-process IPC
- **RNCryptor** — AES-256 encryption for data

**Frameworks**: UIKit, CFNetwork, SystemConfiguration, Security

### Plug3 (com.apple.managedconfiguration.profiled)

**Target**: `profiled` (configuration profile daemon)
**This is the KEY device spoof plug**:

```
MSHookFunction hooks:
  ├── MGCopyAnswer (libMobileGestalt.dylib)
  │   ├── HWModelStr        → fake model
  │   ├── ProductVersion    → fake iOS version
  │   ├── UniqueDeviceID    → fake UDID
  │   ├── SerialNumber      → random serial
  │   └── DeviceClass       → iPhone/iPad
  │
  ├── CTServerConnectionCopyMobileEquipmentInfo (CoreTelephony)
  │   ├── IMEI             → random IMEI
  │   └── IMEISV           → random IMEI SV
  │
  └── IOSerialString       → random serial

Runtime manipulation:
  ├── class_addMethod      → add methods to system classes
  ├── class_addProperty    → add properties at runtime
  └── class_addProtocol    → add protocol conformance
```

**Frameworks**: MobileGestalt, CoreTelephony, IOKit
**Key entitlements**:
- `com.apple.coretelephony.Identity.get`
- `keychain-access-groups`
- `proc_info-allow`

### Plug4 (com.apple.springboard + com.apple.UIKit)

**Target**: SpringBoard AND UIKit (dual filter)
**Hooks**:
- **CLLocation.coordinate** → GPS spoof coordinate
- **CLLocation.altitude** → GPS altitude
- **CLLocation.horizontalAccuracy** → GPS accuracy
- **CLLocationManager** → location manager override
- **UIDevice** → device info
- **UIScreen** → screen resolution
- **AppleLanguages** → language override

**OTRHook System** (On-The-Run App Hooking):
```
OTRAppObject    → Per-app configuration
OTRAppService   → App service management  
OTRHook         → Runtime hook injection
appTweakHelper  → App-level tweaking
```

**Frameworks**: UIKit, CoreLocation, CoreGraphics

---

## RRS (Retention / Restore / Save) System

### Data Flow

```
1. SAVE (Retention):
   App calls retention: with app list
   → Daemon copies app container data:
     /var/mobile/Containers/Data/Application/<UUID>/
   → Device state snapshot (com.ienthach.XoaInfoConfig.plist)
   → Encrypted with RNCryptor (AES-256)
   → Stored in app-specific backup directory

2. RESET:
   App calls reset
   → Daemon:
     chmod -R 600 /private/var/Keychains/keychain-2.*
     chown -R _securityd:wheel /private/var/Keychains/keychain-2.*
     killall services (AppStore, accountsd, akd, itunesstored, etc.)
     clearAdvertisingIdentifier (IDFA reset)
   → Plugs generate new fake values (randomSerial, randomIMEID)

3. RESTORE:
   App calls restore with retention ID
   → Daemon copies back saved container data
   → Restores device state config
   → killall SpringBoard to reload
```

### RRS Settings (from app properties)

| Setting | Property | Description |
|---------|----------|-------------|
| Auto Save | `btAutoSaveRRS`, `autoSaveRRS` | Auto-save RRS on exit |
| Auto Remove | `btAutoRemoveApp`, `autoRemoveApp` | Auto-remove app after |
| Ghi Đè RRS | `ghiDeRRS` | Overwrite existing RRS |
| Note IP RRS | `noteIPRRS` | Record IP in RRS |
| Reset Apps | `resetApps` | Apps to wipe on reset |
| Reset Sys | `resetSys` | System components to wipe |
| Clear RRS | `clearRRS` | Clear RRS post-reset |
| Delay Open App | `delayOpenApp` | Delay before reopening |
| Select RRS | `btnSelectRRS` | Choose RRS to restore |

### App State Resources

```
ListAppReset       → Apps to reset (clear data)
ListAppRetention   → Apps to retain (backup data)
ListFakeBundlePath → Bundle paths to fake
ListFakeDataPath   → Data paths to fake
SaveRRS            → Save RRS now
ClearRRS           → Clear RRS data
```

---

## Config & Data Files

| Path | Purpose |
|------|---------|
| `/private/var/mobile/Library/Preferences/com.ienthach.XoaInfoConfig.plist` | Main config |
| `/private/var/mobile/Library/Preferences/com.ienthach.password.plist` | Auth password |
| `/private/var/mobile/Library/Preferences/proxy.conf` | SOCKS5 proxy |
| `/private/var/mobile/Library/Preferences/proxy.pac` | Auto proxy config |
| `/private/var/mobile/Library/Preferences/byPassDomains.txt` | Bypass domains |
| `/private/var/mobile/Library/Preferences/otrlocation.app.85819.net.plist` | OTR location config |
| `/private/var/Keychains/keychain-2.*` | Keychain database (reset target) |
| `/System/Library/CoreServices/SystemVersion.plist` | System version (read) |

## Bundled Databases

| File | Size | Format |
|------|------|--------|
| `Model-iPhone.plist` | 26 entries | `ModelID|Name|BoardID|WxH|Scale|RAM` |
| `Model-iPad.plist` | iPad models | Same format |
| `Model-iPod.plist` | iPod models | Same format |
| `CarrierList` | 1008 lines | `Country|Carrier|MCC|MNC|ISO|Network` |
| `name.txt` | 1930 names | First names for random device name |
| `MACVendor.txt` | 1798 OUIs | MAC address prefixes |
| `Agent-iPhone.plist` | User-Agent DB | Per-model User-Agent strings |
| `MenuMain.plist` | Main menu config | UI layout definition |
| `paths-deny` | 70+ paths | Jailbreak detection bypass list |

## Jailbreak Detection Bypass

`paths-deny` file lists 70+ file paths to hide from apps:

```
/Applications/Cydia.app
/usr/bin/sshd
/usr/bin/ssh
/etc/apt/
/Library/MobileSubstrate/
/usr/libexec/sftp-server
/private/var/lib/cydia
/private/var/lib/apt
/bin/bash
/var/log/syslog
/evasi0n7
/usr/lib/pangu_xpcd.dylib
cydia:// (URL scheme)
...70+ more
```

## Proxy System

```
proxy.conf:
  socks5 127.0.0.1 1081
  (local networks whitelisted: 127.0.0.0/8, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16)

proxy.pac:
  Auto proxy configuration script

Integrated with:
  /NetworkServices/<service>/Proxies (SystemConfiguration)
```

## Automation Features

| Feature | Description |
|---------|-------------|
| `autoSaveRRS` | Auto-save RRS data when closing app |
| `autoRemoveApp` | Auto-delete app after operations |
| `ghiDeRRS` | Overwrite existing RRS without prompt |
| `delayOpenApp` | Configurable delay before reopening apps |
| `killAllAppOpenXoaInfo` | Kill all background apps |
| `runCommand:` | Execute arbitrary shell commands |
| `openAppName:` | Launch app by bundle ID |
| `sendEmail:type:` | Automated email notifications |
| `TS-reboot.lua` | TrollStore userspace reboot script |

## IDFA Management

```
Fields:
  userNameOldIDFA    → Login username for IDFA server
  passOldIDFA        → Password for IDFA server
  customURLOldIDFA   → Custom IDFA API endpoint
  oldIDFASource      → IDFA source selection

API:
  LoginIDFAAPI:      → Authenticate to IDFA provider
  customIDFAServer   → External IDFA server URL
```

## Encryption: RNCryptor

Both daemon AND app use **RNCryptor** for data encryption:
- AES-256-CBC
- HMAC-SHA256 for authentication
- PBKDF2 key derivation (10k iterations)
- Same crypto stack as KidsAutov4
- Keychain for key storage (com.ienthach password)

## TrollStore Support

```
TS-reboot.lua → Lua script for userspace reboot on TrollStore devices
dropbear23.plist → SSH daemon configuration
```

## Comparison: XoaInfo vs KidsAutov4 vs ZMMO ios-agent

| Feature | XoaInfo | KidsAutov4 | ZMMO ios-agent |
|---------|---------|------------|----------------|
| **Language** | ObjC | ObjC | ObjC/C++ |
| **GUI** | 21 screens native | Basic app | Web Panel |
| **Daemon** | GCDAsyncSocket | Custom HTTP | BSD socket |
| **Plugs count** | 4 dylibs | 1 dylib | 1 dylib |
| **Hook targets** | 3 processes | 12 processes | 12 processes |
| **Device spoof** | MGCopyAnswer + CTServer + IOKit | MGCopyAnswer + sysctl | MGCopyAnswer + sysctl |
| **GPS spoof** | ✅ CLLocation hook | ✅ CLLocation hook | ✅ CLLocation hook |
| **Carrier DB** | ✅ 1008 carriers | ❌ | ❌ |
| **Model DB** | ✅ 26 models | ❌ | ❌ |
| **MAC vendor DB** | ✅ 1798 entries | ❌ | ❌ |
| **Name DB** | ✅ 1930 names | ❌ | ❌ |
| **RRS system** | ✅ Full (save/reset/restore) | ✅ Basic (backup/restore) | ✅ Basic (backup/restore) |
| **Auto tools** | ✅ URL schemes + auto | ❌ | ❌ |
| **Proxy** | ✅ SOCKS5 + PAC | ✅ Shadowrocket | ✅ plist only |
| **Jailbreak bypass** | ✅ 70+ paths | ✅ toggle | ❌ |
| **IDFA management** | ✅ API server | ✅ toggle | ❌ |
| **TrollStore** | ✅ TS-reboot.lua | ❌ (jailbreak only) | ❌ |
| **Encryption** | RNCryptor AES-256 | RNCryptor AES-256 | Plain plist |
| **Auth** | Server auth | Server auth | Placeholder |
| **Obfuscation** | ✅ Heavy (method names + data) | ❌ Light (data only) | ❌ None |
| **Price** | Paid (PUBLIC = limited) | Paid | Open source |

## Key Insights for ZMMO

1. **XoaInfo's Plug3 is the most sophisticated** — it hooks `profiled` (configuration profile daemon) which is rarely checked by apps. This is smarter than KidsAutov4's broad UIKit hook.

2. **Database-driven spoofing** — XoaInfo ships 4 databases (models, carriers, names, MAC vendors) making spoofed data look more realistic.

3. **OTRHook system (Plug4)** — Per-app hook injection allows different fake values per app, something neither KidsAutov4 nor ZMMO currently supports.

4. **RRS system is full lifecycle** — Save → Reset (keychain wipe + service kill) → Restore. Much more comprehensive than KidsAutov4's simple backup.

5. **RocketBootstrap IPC** — All communication uses CPDistributedMessagingCenter through RocketBootstrap, which is more reliable on iOS 12+ than raw sockets.
