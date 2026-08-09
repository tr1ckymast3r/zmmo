# DOMA — Modem/EFS Device Spoofing

> **Source:** DOMA V4.3F ROM (SM-G960N), DomaphoneS Pro v3.0.1.0
> **Analysis:** `/home/thay/cases/case-domaphone-rom/`, `/home/thay/cases/case-domaphone/`
> **Date:** 2026-06 through 2026-08

---

## Architecture

DOMA uses a **3-layer attack** where spoofing happens at the modem/EFS level, not in the Android framework:

```
┌────────────────────────────────────────┐
│  DOMAPHONE S PRO (Windows)             │
│  .NET WPF GUI + ADB backend            │
│  - Quản lý farm điện thoại             │
│  - Push lệnh qua ADB                   │
│  - Screen mirror qua scrcpy modded     │
└──────────────────┬─────────────────────┘
                   │ ADB USB/WiFi
┌──────────────────▼─────────────────────┐
│  ANDROID (LineageOS 17.1 GSI)          │
│                                         │
│  ┌───────────────────────────────────┐ │
│  │ /system/bin/doma (scrcpy modded)  │ │
│  │ - RAT: tap, swipe, type, paste    │ │
│  │ - app_process privilege (uid 0)   │ │
│  │ - Protocol JSON-base64 qua ADB    │ │
│  └───────────────────────────────────┘ │
│                                         │
│  ┌───────────────────────────────────┐ │
│  │ changedevice (native binary)       │ │
│  │ - Write to /efs/nv_data.bin       │ │
│  │ - AT commands to /dev/ttySAC0     │ │
│  │ - IMSI/ICCID via filesystem       │ │
│  └───────────────────────────────────┘ │
│                                         │
│  ┌───────────────────────────────────┐ │
│  │ FRAMEWORK: LineageOS 17.1 CLEAN   │ │
│  │ - 0 modification to JARs          │ │
│  │ - 0 Samsung telephony classes     │ │
│  │ - All spof via build.prop         │ │
│  └───────────────────────────────────┘ │
│                                         │
│  ┌───────────────────────────────────┐ │
│  │ KERNEL: KernelSU v0.6.2           │ │
│  │ - Root ẩn kernel-level            │ │
│  │ - resetprop bypass                │ │
│  └───────────────────────────────────┘ │
│                                         │
│  ┌───────────────────────────────────┐ │
│  │ VENDOR: Samsung HALs (stock)       │ │
│  │ - RIL, Audio, Camera, GPS         │ │
│  │ - Samsung security services OFF   │ │
│  └───────────────────────────────────┘ │
└────────────────────────────────────────┘
```

---

## Spoof Mechanism

### IMEI: Modem Partition (EFS)

```
su -c changedevice --imei 358123456789012
     │
     ▼
  Mở /efs/nv_data.bin
  Parse NV items structure
  Tìm NV_UE_IMEI_I (item 550)
  Write IMEI mới → MD5 update
  Gửi AT+EGMR=1,7,"358..." vào /dev/ttySAC0
     │
     ▼
  Baseband đọc EFS khi boot → thấy IMEI mới
```

**SoC-specific targets:**

| SoC | EFS/NVRAM path | AT command port |
|-----|----------------|-----------------|
| Samsung Exynos 9810 | `/efs/nv_data.bin` | `/dev/ttySAC0` |
| Qualcomm SDM845 | `/dev/block/bootdevice/by-name/modemst1` | `/dev/smd11` |
| MediaTek MT6765 | `/nvram/md/NVRAM/NVD_IMEI/MP0B_001` | `/dev/ttyC0` |

### IMSI/ICCID: Filesystem

```
su -c changedevice --imsi 452010123456789 --iccid 89882110000001234567
     │
     ▼
  Write /efs/imei/mps_code.dat  ← SIM operator
  Write /data/data/com.android.providers.telephony/databases/telephony.db
  Write /efs/factory.profile    ← IMSI mapping
```

---

## Build.prop Spoofing (Standard)

```properties
# Real: SM-G960N (Korean S9)
# Fake: SM-G960F (International S9)

ro.product.model=SM-G960F
ro.product.brand=samsung
ro.product.device=starlte
ro.build.fingerprint=samsung/starltexx/starlte:10/QP1A.190711.020/G960FXXU8DTC5:user/release-keys
ro.carrier=unknown
keyguard.no_require_sim=true
```

---

## What DOMA CAN Spoof

| Category | Properties | Mechanism |
|----------|-----------|-----------|
| Hardware | Model, Brand, Manufacturer, Device, Board, Hardware, CPU, RAM, GPU, SOC, Cores | `build.prop` / `resetprop` |
| Build | Fingerprint, BuildDate, SDK, Release, Bootloader, Baseband, Security Patch | `build.prop` / `resetprop` |
| **IMEI** | IMEI slot 1, IMEI slot 2 | **EFS partition + AT commands** |
| **IMSI** | IMSI slot 1 & 2 | **File system** |
| **ICCID** | SIM serial | **File system** |
| **SIM info** | Phone number, SIM operator, Country code, Carrier name | **AT commands** |
| MAC | WiFi MAC, Bluetooth MAC | `ip link set address` (3 levels) |
| Google | Android ID, GSF ID, DRM ID, SafetyNet | `settings put` + PIF module |
| Network | IP, Gateway, Proxy | `settings put global http_proxy` |
| Sensor | Resolution, DPI, Timezone, Charging state | `settings put` / `wm` |
| GPS | Latitude, Longitude | Mock Location Provider (APK) |
| Status | Lock screen, Do not disturb, Brightness | `dumpsys` + `settings` |

---

## ROM Modifications

### Removed (Samsung stock → LineageOS GSI)
- 15 Samsung framework JARs (Knox, TIMA, security)
- All Samsung APKs (Bixby, Samsung Pay, Push, diagmonagent...)
- All Google Apps except GMS Core

### Added
- `doma` (scrcpy 1.23 modded) — RAT for remote control
- `domactr` — Launcher script via `app_process`
- `KernelSU_v0.6.2` — Kernel-level root
- `Bproxy3.apk` — VPN SOCKS5 tunnel
- `init.samsung.rc` — Stubs 16 Samsung security services
- `adb_root.rc` — Root ADB at boot
- `install.rc` — Auto-install KernelSU APK

### Modified
- `build.prop` — Identity spoof (G960F on G960N hardware)
- `init.environ.rc` — Hides ADB USB notification

---

## Key Architecture Insight

DOMA's genius: **Don't patch the framework — eliminate the code that checks identity.**

```
Old way: Patch SamsungTelephony.smali → fragile, version-specific
DOMA way: Replace entire /system with LineageOS GSI → no Samsung code at all
```

The framework is CLEAN. All spoofing happens:
- **Above**: APK-level (doma RAT, changedevice binary)
- **Below**: Kernel/modem level (KernelSU, EFS write)

---

## ADB Commands Used

```bash
# Device identity change
su -c changedevice
su -c "resetprop ro.build.fingerprint samsung/..."
su -c "resetprop ro.product.model SM-G960F"

# MAC address (3 levels)
su -c "ip link set wlan0 address 02:00:11:22:33:44"              # Level 1
su -c "echo '02:00:11:22:33:44' > /sys/class/net/wlan0/address" # Level 2 (deeper)
# Level 3 = kernel module hook

# Network
su -c "settings put global http_proxy :0"                        # Clear proxy
su -c "settings put global http_proxy 192.168.1.1:8888"          # Set proxy
su -c "svc wifi enable"

# Google
su -c "settings put secure android_id abc123..."
su -c "pm clear com.google.android.gms"                          # Clear GMS cache
```

---

## DomaphoneS PC Tool Stack

| Component | Format | Role |
|-----------|--------|------|
| DomaphoneS_Pro.exe | .NET WPF (Themida-packed) | GUI controller |
| Bussiness.exe | Go 1.21 (UPX-packed) | C2 engine, protocol |
| DomaAuto.dll | .NET | Automation engine for gmail/youtube/chrome |
| Domadb.dll | .NET | ADB library (AdvancedSharpAdbClient fork) |
| Web Mail Server | Python Flask + PyArmor | Account management server |

### C2 Encryption
- AES-CBC with AES-NI hardware acceleration
- Key: `E3E46F13E8CC18EC2280F07D68F8E903` (AES-128)
- ConfigA/B: Encrypted separately (different key, not cracked)
- HTTP/2 + SOCKS5 tunnel for transport

---

## Relevance to ZMMO

| DOMA Feature | ZMMO Status | Gap |
|-------------|-------------|-----|
| Build.prop spoof | ✅ Done (resetprop) | - |
| MAC spoof | ✅ Done (`ip link`) | - |
| Settings spoof | ✅ Done (`settings put`) | - |
| **IMEI spoof** | ❌ | **Need framework patch or EFS approach** |
| **IMSI/ICCID spoof** | ❌ | **Need framework patch** |
| **SIM operator** | ❌ | **Need RILJ hook** |
| Remote control | ✅ Done (droid-agent WS) | - |
| Boot auto-apply | ✅ Done (spoof.go) | - |
| Persistence | ✅ Done (spoof.json) | - |

---

## Source Files

| File | Location |
|------|----------|
| ROM system image | `/home/thay/cases/case-domaphone-rom/extracted/DOMA_V4.3F_S9_G960N-A10_ADB-ON/img/system_raw.img` |
| Framework report | `/home/thay/cases/case-domaphone-rom/FRAMEWORK_PATCH_REPORT.md` |
| Binary report | `/home/thay/cases/case-domaphone-rom/DOMA_BINARY_REPORT.md` |
| BAO-CAO (full) | `/home/thay/cases/case-domaphone/BAO-CAO-DOMAPHONES.md` |
| Decompiled DomaAuto.cs | `/home/thay/cases/case-domaphone/decompiled_domaauto/DomaAuto/Auto.cs` |
