# ZMMO ROM Patcher

**Bottom layer of ZMMO Device Changer** — patches LineageOS framework to enable device identity spoofing at the Android OS level.

## Compatibility Matrix

| Device Family | LineageOS | Android | Status | Notes |
|--------------|-----------|---------|--------|-------|
| **Pixel 2-5** (Snapdragon) | 18.1–21 | 11–14 | ✅ Full | Closest to AOSP, patches apply cleanly |
| **Pixel 6-9** (Tensor) | 20–22 | 13–15 | ✅ Full | VDEX-only, CarrierConfig bypass needed |
| **Samsung S8** (Exynos) | 18.1–20 | 10–13 | ✅ Full | `dreamlte`, SamsungRIL hooks |
| **Samsung S8** (Snapdragon) | 18.1–20 | 10–13 | ✅ Full | `dreamqlte`, common AOSP patches only |
| **Samsung S9** (Exynos) | 19.1–21 | 10–14 | ✅ Full | `starlte`, SamsungRIL hooks |
| **Samsung S9** (Snapdragon) | 19.1–21 | 10–14 | ✅ Full | `starqlte`, common AOSP patches only |
| **Samsung S10** (Exynos) | 20–21 | 12–14 | ✅ Full | `beyond0lte`, SamsungRIL hooks |
| **Samsung S10** (Snapdragon) | 20–21 | 12–14 | ✅ Full | `beyond0qlte`, common AOSP patches only |
| **Samsung S20** (Exynos) | 21 | 13–14 | ⚠️ Partial | `x1q`, RIL changes in Android 13+ |
| **Samsung S20** (Snapdragon) | 21 | 13–14 | ✅ Full | `x1q` US, common AOSP patches |
| **Samsung A/M series** (Mediatek) | Any | 10–14 | ❌ Untested | Mediatek RIL differs from AOSP |
| **Generic AOSP** | Any | 10–14 | ✅ Full | Common patches target AOSP classes |
| **Xiaomi/OnePlus** | Any | 10–14 | ⚠️ Untested | Should work if AOSP RILJ is used |
| **MIUI/HyperOS** | N/A | 10–14 | ❌ Not supported | Uses MIUI-specific telephony framework |

### Samsung Chip Detection

| Chip | `ro.board.platform` | Region | RIL | Extra Hooks |
|------|---------------------|--------|-----|-------------|
| **Exynos** | `universal9810`, `exynos9820`, ... | EU/Asia | SamsungRIL + AOSP | ✅ SamsungRIL.smali |
| **Snapdragon** | `sdm845`, `sm8150`, `kona`, ... | US/CN/HK | Qualcomm → AOSP | ❌ None needed |
| **MediaTek** | `mt6765`, `mt6833`, ... | Budget models | Mediatek RIL | ❌ Not supported |

### Feature Support Per Device

| Feature | Pixel | Samsung Exynos | Samsung Snapdragon | Generic |
|---------|-------|---------------|-------------------|---------|
| IMEI spoof (both slots) | ✅ | ✅ | ✅ | ✅ |
| IMSI spoof | ✅ | ✅ | ✅ | ✅ |
| ICCID spoof | ✅ | ✅ | ✅ | ✅ |
| Phone number spoof | ✅ | ✅ | ✅ | ✅ |
| Build.prop spoof (19 fields) | ✅ | ✅ | ✅ | ✅ |
| SIM operator spoof | ✅ | ⚠️ * | ✅ | ✅ |
| CarrierConfig bypass | ⚠️ ** | N/A | N/A | N/A |
| SamsungRIL hooks | N/A | ✅ | N/A | N/A |
| SafetyNet/Play Integrity | ❌ | ❌ | ❌ |

\* Samsung ServiceMode (*#0011#) may still show real operator  
\*\* Pixel Adaptive Connectivity may override — disable via `pm disable com.google.android.apps.connectivity`

## Architecture

```
Modem → RIL native daemon → RILJ.java (HOOKED!) → TelephonyManager → App
                                    ↑
                            IccCardProxy, UiccCardApplication
                            PhoneBase, ServiceStateTracker
                    ┌─────── SamsungRIL (Exynos only)
                    │
Pixel: CarrierConfigManager → Adaptive Connectivity (disable)
```

## Quick Start

```bash
# Auto-detect device + Android version
./build.sh ~/Downloads/lineage-21.0-star2lte.zip --magisk

# Force device family
./build.sh lineage-panther.zip --magisk --device=pixel

# See auto-detection
./scripts/detect-device.sh lineage-star2lte.zip
```

Output: `out/zmmo-rom-patcher-magisk-<family>-a<ver>-YYMMDD.zip`

## Install

```bash
# Push to device
adb push out/zmmo-rom-patcher-magisk-*.zip /sdcard/Download/

# Install via Magisk
adb shell su -c "magisk --install-module /sdcard/Download/zmmo-rom-patcher-magisk-*.zip"
adb reboot
```

## Patch Structure (Multi-Device)

```
patches/
├── common/any/              ← Generic AOSP (works on all devices)
│   ├── framework/
│   │   ├── Build.smali.patch
│   │   ├── TelephonyManager.smali.patch
│   │   ├── ZmmoProps.smali
│   │   └── ZmmoTelephony.smali
│   └── telephony-common/
│       ├── IccCardProxy.smali.patch
│       ├── UiccCardApplication.smali.patch
│       ├── PhoneBase.smali.patch
│       └── ServiceStateTracker.smali.patch
├── pixel/13/                ← Pixel Tensor G2 (Android 13)
├── samsung-exynos/12/       ← Samsung S10 (Android 12)
│   └── README.md            ← SamsungRIL hook docs
```

**Priority:** `device/version` > `device/any` > `common/version` > `common/any`

## Spoof Properties

All set via `persist.zmmo.*` at runtime by manager-agent:

| Property | What |
|----------|------|
| `persist.zmmo.imei_slot1` | IMEI slot 1 (15 digits) |
| `persist.zmmo.imei_slot2` | IMEI slot 2 |
| `persist.zmmo.imsi` | IMSI |
| `persist.zmmo.iccid` | ICCID (19-20 digits) |
| `persist.zmmo.phone_number` | Phone number |
| `persist.zmmo.sim_operator` | MCC+MNC (e.g. 45204) |
| `persist.zmmo.brand` | Brand |
| `persist.zmmo.model` | Model |
| `persist.zmmo.fingerprint` | Build fingerprint |
| ... | (see config/default-props.json) |

## Limitations

- **SafetyNet/Play Integrity** — needs separate PIF module
- **Modem-level IMEI** — `*#06#` may show real IMEI on some devices
- **MIUI/HyperOS** — custom RILJ, not supported
- **Samsung stock ROM** — Knox protects framework; use LineageOS
