# KidsAutov4 — Reverse Engineering Notes

> Source: `Public_iOS13_KidsAutov4_26.06.22-12_rootfull_iphoneos-arm.deb`
> App GUI: `iOSKidsChanger_4.0.1_roothide_iphoneos-arm64e.deb`
> Author: KidsDev91 / Cường Trần
> Target: iOS 12.x – 16.x (rootful & rootless/roothide)

---

## Architecture Overview

```
iOSKidsChanger.app (GUI, 465KB, ObjC, arm64+arm64e)
       │ HTTP localhost:16688
       ▼
  kidsdaemon (3.5MB) — HTTP server port 16688
       │ IPC (Mach / CPDistributedMessagingCenter / file)
       ├──▶ KidsInfoHelper (1.1MB) — Device info collector
       ├──▶ DaemonHelper (237KB) — Watchdog / process manager
       ├──▶ libextendc.dylib (187KB) — Extension helpers
       ├──▶ libMessageHelper.dylib (272KB) — IPC messaging
       └──▶ DeviceProof.dylib — MobileSubstrate hooks (12 processes)

  Config file: /var/mobile/Library/Preferences/com.kidsautopro.deviceinfo.plist
               → migrated to /var/jb/kids.MobileTemp/com.kids.DeviceInfor.plist
```

## API Endpoints (kidsdaemon :16688)

| Endpoint | Params | Function |
|----------|--------|----------|
| `/changedevice` | `ios`, `model` | Spoof device model + iOS version |
| `/changeregion` | `host`, `ipaddress` | Change region/proxy IP |
| `/setgps` | `lat`, `lon` | GPS spoof |
| `/backupapps` | `bundleid`, `filename`, `cmt`, `timeout` | Backup app data |
| `/restorerrs` | `filename`, `timeout` | Restore backup |
| `/wipeapps` | `bundleid`, `timeout` | Wipe app data |
| `/backuplist` | — | List backups |
| `/backupremove` | `filename` | Remove backup |
| `/getapplist` | — | List installed apps |
| `/getcurrentip` | — | Get current IP |
| `/license` | `getkey` | License check |
| `/login` | `user` | User authentication |
| `/proofdevice` | — | Device proof check |

## Device Info Collection (KidsInfoHelper)

### 5 Data Sources

1. **IOKit Registry** — `IOPlatformExpertDevice`
   - Serial number (`IOPlatformSerialNumber`)
   - UUID (`IOPlatformUUID`)
   - Board model (`model`)
   - WiFi MAC

2. **MobileGestalt** — Private framework (`libMobileGestalt.dylib`)
   - `HWModelStr` — Board model (N71AP)
   - `ProductType` — Marketing model (iPhone12,1)
   - `ProductVersion` — iOS version
   - `BuildVersion`
   - `UniqueDeviceID` — UDID
   - `DeviceClass`, `DeviceColor`, `EnclosureColor`
   - `DieID`, `ChipID` — Hardware IDs
   - `MainScreenWidth/Height/Scale`
   - `BasebandVersion`

3. **sysctl()** — Kernel info
   - `hw.machine`, `hw.model`
   - `hw.ncpu`, `hw.physmem`, `hw.memsize`
   - `hw.cpufrequency`, `hw.cpufamily`
   - `kern.osversion`, `kern.osproductversion`
   - `kern.boottime`
   - `vm.free_page_count`

4. **SCDynamicStore** — Network/WiFi
   - `State:/Network/Interface/en0/AirPort` → SSID, BSSID
   - `State:/Network/Interface/en0/IPv4` → IP, subnet
   - `State:/Network/Interface/pdp_ip0/IPv4` → Cellular IP
   - `State:/Network/Global/DNS` → DNS servers

5. **LSApplicationWorkspace** — Installed apps
   - `allInstalledApplications` → bundleID, version, path

### Encryption
- Config plist encrypted with **RNCryptor** (AES-256-CBC + HMAC)
- Password-based key derivation (PBKDF2, 10k iterations)
- Random salt per write

## Device Spoofing Mechanism

### `changedevice` Flow

```
1. GUI: GET /changedevice?ios=16.5&model=iPhone15,3
2. kidsdaemon: handleDeviceChangeWithVersion:andRawModel:
3. Generate 5 fake plists:
   ├── MobileGestalt_Fake.plist        ← HWModelStr, ProductVersion
   ├── CoreSuggestionsInternals_Fake.plist ← Device info for Siri
   ├── InfoMobileSafari_Fake.plist     ← User-Agent spoof
   ├── InfoSafariViewServs_Fake.plist  ← Safari View Service
   └── .GlobalPreferences_m.plist      ← AppleLocale, AppleLanguages
4. Post CFNotification "kidsDeviceChanged"
5. DeviceProof.dylib reads config → hooks return fake values
```

### MobileSubstrate Hooks (DeviceProof.dylib)

Filter: Bundles for 12 processes
```
com.apple.UIKit, accountsd, appstored, itunesstored,
WebKit.WebContent, WebKit.Networking, MobileGestaltHelper,
springboard, locationd, assistantd, Preferences
```

Hooked functions:
| Framework | Functions | Spoofed Value |
|-----------|-----------|---------------|
| UIDevice | `model`, `systemVersion`, `name` | Config plist |
| MobileGestalt | `MGCopyAnswer`, `MGGetBoolAnswer` | HWModelStr, ProductType, etc. |
| sysctl | `sysctlbyname("hw.model")` | fake_model |
| sysctl | `sysctlbyname("kern.osproductversion")` | fake_version |
| NSLocale | `preferredLanguages` | fake_locale |
| NSTimeZone | `localTimeZone` | config timezone |
| CLLocation | `coordinate` | GPS fake |

### Entitlements (daemon + dylib)
```
platform-application: false
get-task-allow: true
run-unsigned-code: true
dynamic-codesigning: true
com.apple.private.MobileGestalt.AllowedProtectedKeys: true
com.apple.developer.networking.vpn.api: allow-vpn
com.apple.developer.networking.networkextension:
  - app-proxy-provider
  - content-filter-provider
  - dns-proxy
  - packet-tunnel-provider
com.apple.locationd.effective_bundle: true
com.apple.private.MobileContainerManager.allowed: true
com.apple.private.wifi.manager: true
com.apple.private.skip-library-validation: true
```

## Toggle Features (App GUI)

| Toggle | Function | Target Framework |
|--------|----------|-----------------|
| Enable_IDFA | Fake advertising ID | ASIdentifierManager |
| Enable_LTE | Fake carrier | CTCarrier / CoreTelephony |
| Enable_Screen | Fake resolution | UIScreen, MobileGestalt |
| Enable_Lang | Fake language | NSLocale |
| Enable_TZ | Fake timezone | NSTimeZone |
| Bypass_Appstore | Hide jailbreak from App Store | LSApplicationWorkspace |
| Bypass_JB | Hide jailbreak from apps | stat(), fopen() hooks |
| Enable Proof Device | Prove device is "legitimate" | Check all props pass |

## Backup/Restore (RRS)

- Backup: copies `/var/mobile/Containers/Data/Application/<UUID>/` → `~/KidsAutoRRS/`
- Also backs up App Groups: `/var/mobile/Containers/Shared/AppGroup/`
- One-click auto RRS (Auto Save mode)
- Stored on-device, no cloud dependency

## Files & Paths

| Path | Purpose |
|------|---------|
| `/usr/bin/kidsdaemon` | Main HTTP server daemon |
| `/usr/bin/KidsInfoHelper` | Device info collector |
| `/usr/local/bin/DaemonHelper` | Watchdog / lifecycle |
| `/usr/lib/libextendc.dylib` | Extensions |
| `/usr/lib/libMessageHelper.dylib` | IPC messaging |
| `/Library/MobileSubstrate/DynamicLibraries/DeviceProof.dylib` | System hooks |
| `/Library/LaunchDaemons/com.kidsautopro.kidsdaemon.plist` | Auto-start |
| `/var/mobile/Library/Preferences/com.kidsautopro.deviceinfo.plist` | Config |
| `/var/jb/kids.MobileTemp/` | Rootless config dir |

## Comparison with ZMMO ios-agent

| Aspect | KidsAutov4 | ZMMO ios-agent |
|--------|-----------|-----------------|
| Language | ObjC | ObjC/C++ |
| HTTP Server | Custom | Custom (BSD sockets) |
| Collector | 5 sources | 5 sources (same API) |
| Spoofer | 5 fake plists | 4 fake plists |
| Tweak | DeviceProof.dylib | ZMMODeviceProof.dylib |
| Hook count | 6 frameworks | 5 frameworks + sysctl C hooks |
| Port | 16688 | 15555 |
| License | KidsAutov4 auth | Placeholder (TBD) |
| GPS | via CLLocation hook | via CLLocation hook |
| Proxy | Shadowrocket integration | .GlobalPreferences_m.plist |
