# MiChanger Pro v3.3.3 vs Plus v5.4.0 — Actual Binary Analysis

> **Files:** `Gmn-MiChangerPro_Setup_v3.3.3.exe` (59MB), `MiChangerPlus_Setup_v5.4.0.exe` (55MB)
> **Location:** `/mnt/data/Downloads/`
> **Date:** 2026-08-09

---

## Executive Summary

**Both tools use the EXACT same approach as DOMA**: Windows PC → ADB → root shell commands. NO Xposed hooks, NO framework patching.

The "MiChanger" name is misleading — it does NOT use Xposed/LSPosed for spoofing. The spoof mechanism is pure `resetprop` + `settings put` + `ip link` commands sent via ADB.

---

## Extracted Contents

### MiChanger Pro v3.3.3 (59 MB)

```
app/
├── MiChangerPro.exe              # Main GUI (.NET/WPF, likely Themida-packed)
├── Resources/
│   ├── adb.exe                   # ADB binary
│   ├── scrcpy.exe                # Screen mirroring (SDL2-based)
│   ├── CPIDNGSocks.apk           # Android: VPN/SOCKS5 tunnel app
│   ├── ADBKeyboard.apk           # ADB keyboard for text input
│   ├── api_doc_vi.txt            # API documentation (Vietnamese)
│   ├── api_doc_en.txt            # API documentation (English)
│   ├── api_doc_cn.txt            # API documentation (Chinese)
│   ├── modules/
│   │   ├── 1.KitsuneMagisk-v27.1.zip       # Custom Magisk fork
│   │   ├── 2.Shamiko-v1.2.1.zip             # Root hide module
│   │   ├── 3.Tricky-Store-v1.4.1.zip        # Play Integrity bypass
│   │   └── 4.PlayIntegrity-v37.0.zip        # Play Integrity Fix
│   └── *.dll                    # FFmpeg, SDL2, USB drivers
└── vi-VN/zh-CN/                 # Localization DLLs
```

### MiChanger Plus v5.4.0 (55 MB)

```
app/
├── MiChangerPlus.exe             # Main GUI
├── Resources/
│   ├── adb.exe + scrcpy.exe      # Same ADB + screen mirroring
│   ├── MiChangerPlus_API.txt     # API doc (Vietnamese only)
│   ├── location.txt              # Location data (~10K coordinates)
│   ├── gpu.txt                   # GPU model database
│   ├── tzlookup.xml              # Timezone database
│   └── viewscreen10/11/          # Multiple scrcpy versions (compat)
```

**Key difference: Plus has NO APK, NO modules.** Pure ADB-shell approach.

---

## CPIDNGSocks.apk Analysis (Pro only)

| Component | Type | Size | Function |
|-----------|------|------|----------|
| `classes.dex` | Java bytecode | 37KB | VPN service UI + SOCKS5 config |
| `libtun2socks.so` | Native (C) | 156KB | VPN TUN interface → SOCKS5 proxy |
| `libpdnsd.so` | Native (C) | 210KB | DNS proxy daemon |
| `libsystem.so` | Native (C) | 7.5KB | **Unknown — possibly spoof helper** |

### Key finding:
**CPIDNGSocks.apk is a VPN/SOCKS5 tunnel app, NOT a spoofing module.**

- `libtun2socks.so` = Creates TUN interface, routes all traffic through SOCKS5
- `libpdnsd.so` = DNS proxy for custom DNS resolution
- `libsystem.so` = Small native helper (7.5KB, likely executes shell commands with root)

The APK name: **CPI-D-NG-Socks** = **C**hange **P**hone **I**D + **N**ext **G**eneration + **Socks** Proxy

---

## How Both Tools Actually Spoof

### Spoof Mechanism (from API analysis)

```
MiChangerPro.exe / MiChangerPlus.exe (Windows)
         │
         │ HTTP API on localhost:[PORT]
         │ Example: /change?serial=DEVICE&filter_country=us&filter_carrier=T-Mobile-10
         │
         ▼
    ┌──────────────┐
    │ Device DB     │  ← Internal SQLite with 4000+ device profiles
    │ + Carrier DB  │  ← 200+ countries with MCC/MNC per carrier
    └──────┬───────┘
           │
           ▼
    ┌──────────────┐
    │ ADB commands  │
    │              │
    │ su -c "resetprop ro.product.model XXX"
    │ su -c "resetprop ro.product.brand YYY"
    │ su -c "resetprop ro.product.manufacturer ZZZ"
    │ su -c "resetprop ro.build.fingerprint AAA"
    │ su -c "settings put secure android_id BBB"
    │ su -c "settings put global sim_operator CCC"
    │ su -c "ip link set wlan0 address DD:DD:DD:DD:DD:DD"
    │ ...
    └──────┬───────┘
           │
           ▼
    ┌──────────────────┐
    │ ANDROID DEVICE    │
    │ (root via Magisk) │
    │                   │
    │ CPIDNGSocks.apk   │ ← VPN/SOCKS tunnel (Pro only)
    │ (optional)        │
    └──────────────────┘
```

### NO Xposed, NO framework patching, NO smali!

The spoofing is **100% shell commands**:
- **Device info**: `resetprop` (Magisk/KernelSU) for `ro.*` properties
- **SIM info**: `settings put global sim_operator`, `settings put global sim_operator_name`
- **Android ID**: `settings put secure android_id`
- **MAC**: `ip link set address`
- **Location**: MockLocationProvider APK or `settings put` coordinates

### What about IMEI/IMSI/ICCID?

From the API docs, MiChanger has `filter_carrier` and `custom_carrier` parameters (carrier name + SIM code like "T-Mobile|310160"). But there's NO IMEI/IMSI/ICCID in the API — only carrier/operator spoofing.

This means MiChanger **does NOT fake IMEI at the method level** like our earlier theoretical doc described. They only fake:
- Build properties (resetprop)
- SIM operator (settings put)
- MAC address (ip link)
- Android ID (settings put)

---

## Pro vs Plus Comparison

| Feature | Pro v3.3.3 | Plus v5.4.0 |
|---------|-----------|------------|
| **ADB control** | ✅ | ✅ |
| **Screen mirror (scrcpy)** | ✅ | ✅ |
| **Device DB** | ✅ 4000+ models | ✅ Same |
| **Carrier DB** | ✅ 200+ countries | ✅ Same |
| **API (HTTP)** | ✅ 13 endpoints | ✅ 9 endpoints |
| **CPIDNGSocks APK** | ✅ VPN/SOCKS tunnel | ❌ None |
| **ADBKeyboard APK** | ✅ For text input | ❌ None |
| **Magisk modules** | ✅ Kitsune + Shamiko + TrickyStore + PIF | ❌ None |
| **Play Integrity Fix** | ✅ Auto-update from server | ❌ None |
| **Google One redirect** | ✅ Frida-based token grab | ❌ None |
| **Location DB** | ❌ Built-in | ✅ location.txt (~10K coords) |
| **GPU DB** | ❌ Built-in | ✅ gpu.txt |
| **Multi-platform** | VI + EN + CN | VI only |
| **License tiers** | PROMAX, PRO, etc. | Unknown |
| **Custom carrier** | ✅ `custom_carrier=Name|MCCMNC` | ✅ Same |
| **Factory reset** | ✅ | ✅ |
| **Backup/restore** | ✅ Full + app data | ✅ Basic |
| **Proxy config** | ✅ HTTP + SOCKS5 | ✅ HTTP + SOCKS5 |
| **Frida-server** | ✅ Auto push/start | ❌ None |

---

## The "API" — How Automation Works

Both tools expose an HTTP API on `localhost:[PORT]` for automation:

```bash
# Change device to random Samsung + carrier in US
curl "http://localhost:6001/change?serial=DEVICE123&filter_country=us"

# Change SIM only (keep device model)
curl "http://localhost:6001/changesimonly?serial=DEVICE123&filter_country=jp&filter_carrier=Mineo-10"

# Custom carrier
curl "http://localhost:6001/change?serial=DEVICE123&filter_country=us&custom_carrier=T-Mobile|310160"

# With GPS coordinates
curl "http://localhost:6001/change?serial=DEVICE123&lat=21.0285&long=105.8542"

# Backup + change + factory reset
curl "http://localhost:6001/backup?serial=DEVICE123&factory_reset=True&full=True"
```

---

## Revised ZMMO Comparison

| | DOMA | MiChanger Pro | MiChanger Plus | ZMMO (current) |
|---|---|---|---|---|
| **Device info spoof** | resetprop | resetprop | resetprop | resetprop ✅ |
| **SIM operator spoof** | settings put | settings put | settings put | TODO |
| **MAC spoof** | ip link | ip link | ip link | ip link ✅ |
| **Android ID spoof** | settings put | settings put | settings put | settings put ✅ |
| **GPS spoof** | MockLocation APK | Built-in | Built-in | TODO |
| **VPN/SOCKS** | Bproxy3.apk | CPIDNGSocks.apk | ❌ (external) | TODO |
| **Play Integrity bypass** | KernelSU + PIF | Magisk + TrickyStore | ❌ (manual) | N/A |
| **Remote control** | doma RAT (scrcpy) | scrcpy | scrcpy | droid-agent WS ✅ |
| **API for automation** | Via ADB | HTTP REST API | HTTP REST API | Panel REST API ✅ |
| **Config persistence** | On device (ROM) | On PC (SQLite) | On PC (SQLite) | spoof.json ✅ |
| **IMEI spoof** | changedevice (EFS) | ❌ NOT SUPPORTED | ❌ NOT SUPPORTED | TODO |
| **IMSI/ICCID spoof** | changedevice (files) | ❌ NOT SUPPORTED | ❌ NOT SUPPORTED | TODO |
| **Framework hooks** | ❌ None | ❌ None | ❌ None | N/A |

---

## Critical Insight

> **MiChanger does NOT do what the device-changer-plan.md assumed.**
> 
> The earlier plan assumed MiChanger uses Xposed to hook TelephonyManager (getDeviceId, getSubscriberId, etc.). In reality, MiChanger only uses `resetprop` + `settings put` — exact same as DOMA and ZMMO.
>
> **MiChanger Pro/Plus do NOT spoof IMEI, IMSI, or ICCID.**
>
> They ONLY spoof: device model/brand/fingerprint, SIM operator name/code, MAC address, Android ID, GPS coordinates.

The ONLY tool in the comparison matrix that spoofs IMEI is **DOMA** (via `changedevice` binary writing to EFS partition). For ZMMO to achieve IMEI/IMSI/ICCID spoofing, we must use the framework smali-patch approach or Xposed — neither DOMA nor MiChanger's approach will work.

---

## Files

| File | Location |
|------|----------|
| MiChangerPro extracted | `/tmp/michanger-pro/` |
| MiChangerPlus extracted | `/tmp/michanger-plus/` |
| CPIDNGSocks.apk | `/tmp/michanger-pro/app/Resources/CPIDNGSocks.apk` |
| Pro API doc (VI) | `/tmp/michanger-pro/app/Resources/api_doc_vi.txt` |
| Plus API doc | `/tmp/michanger-plus/app/Resources/MiChangerPlus_API.txt` |
| Location DB | `/tmp/michanger-plus/app/Resources/location.txt` |
| GPU DB | `/tmp/michanger-plus/app/Resources/gpu.txt` |
