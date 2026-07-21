# ZMMO ROM Patcher

**Bottom layer of ZMMO Device Changer** — patches LineageOS framework to enable device identity spoofing at the Android OS level.

```
┌─ Web Panel (Next.js) ────────────────────────┐
│ packages/panel/              port 3013        │
└──────────────────┬────────────────────────────┘
                   │ HTTP REST API
┌──────────────────▼────────────────────────────┐
│ Manager-Agent (Go)                            │
│ packages/manager-agent/      port 55555       │
└──────────────────┬────────────────────────────┘
                   │ ADB (USB/WiFi)
┌──────────────────▼────────────────────────────┐
│ ROM Patcher ← YOU ARE HERE                    │
│ packages/rom-patcher/                         │
│ Patches: telephony-common.jar, framework.jar   │
└───────────────────────────────────────────────┘
```

## Architecture

```
Modem → RIL native daemon → RILJ.java (HOOKED!) → TelephonyManager → App
                                    ↑
                            IccCardProxy, UiccCardApplication
                            PhoneBase, ServiceStateTracker
```

Hooks are applied at the **RILJ/framework level** — no modem patching required, no brick risk.

## What Gets Patched

### telephony-common.jar (SIM properties)
| Class | Method | Property |
|-------|--------|----------|
| `IccCardProxy` | `getIccId()` | ICCID |
| `UiccCardApplication` | `getImsi()` | IMSI |
| `PhoneBase` / `GsmCdmaPhone` | `getLine1Number()` | Phone Number |
| `ServiceStateTracker` | `getOperatorNumeric()` | SIM Operator (MCC+MNC) |

### framework.jar (Device identity)
| Class | What | Fields |
|-------|------|--------|
| `Build` | Static device identity | BRAND, MODEL, MANUFACTURER, DEVICE, PRODUCT, FINGERPRINT, ID, BOARD, HARDWARE, BOOTLOADER, RADIO, SERIAL, TAGS, TYPE |
| `TelephonyManager` | IMEI/MEID access | `getDeviceId()`, `getImei()`, `getMeid()` |

### New helper classes (added to framework.jar)
- `zmmo/ZmmoProps` — reads `persist.zmmo.*` override props, falls back to real values
- `zmmo/ZmmoTelephony` — direct ITelephony binder calls (bypass hooks for real values)

## Quick Start

### Requirements
- LineageOS ROM ZIP (18.1–21, any device)
- Java 11+
- ADB (for --direct mode)
- Rooted device with Magisk (for --magisk mode)

### Build Magisk Module
```bash
./build.sh ~/Downloads/lineage-20.0-20250101-UNOFFICIAL-star2lte.zip --magisk
```

Output: `out/zmmo-rom-patcher-magisk-YYMMDD_HHMM.zip`

### Install
```bash
# Push Magisk module to device
adb push out/zmmo-rom-patcher-magisk-*.zip /sdcard/Download/

# Install via Magisk Manager → Modules → Install from storage
# OR:
adb shell su -c "magisk --install-module /sdcard/Download/zmmo-rom-patcher-magisk-*.zip"

# Reboot
adb reboot
```

### Direct Patch (ADB, device must be rooted + rw system)
```bash
./build.sh ~/Downloads/lineage-20.0-20250101-UNOFFICIAL-star2lte.zip --direct
adb push out/zmmo-rom-patcher-direct-*.tar.gz /data/local/tmp/
adb shell su -c "cd /data/local/tmp && tar xzf zmmo-rom-patcher-direct-*.tar.gz && ./install.sh"
adb reboot
```

## How It Works

1. **extract-framework.sh** — pulls `framework.jar`, `telephony-common.jar` from ROM ZIP
2. **deodex.sh** — converts `.odex` → smali using baksmali, reassembles into `.jar`
3. **patch.sh** — applies ZMMO smali patches to intercept identity methods
4. **repack-magisk.sh** — bundles patched jars + init script into Magisk module

At boot, `zmmo-init.rc` initializes `persist.zmmo.*` properties. The ZMMO Manager-Agent then sets actual spoof values via `setprop` at runtime.

## Property Reference

All spoof values are set via `persist.zmmo.*` system properties:

| Property | Type | Example |
|----------|------|---------|
| `persist.zmmo.imei_slot1` | String (15 digits) | `359404080608491` |
| `persist.zmmo.imei_slot2` | String (15 digits) | `359404080608509` |
| `persist.zmmo.imsi` | String | `452040123456789` |
| `persist.zmmo.iccid` | String (19-20 digits) | `8984040000012345678` |
| `persist.zmmo.phone_number` | String | `+84123456789` |
| `persist.zmmo.sim_operator` | String (MCC+MNC) | `45204` |
| `persist.zmmo.brand` | String | `samsung` |
| `persist.zmmo.model` | String | `SM-G991B` |
| `persist.zmmo.fingerprint` | String | `samsung/x1qxxx/x1q:12/SP1A...` |
| ... | ... | ... |

See `config/default-props.json` for full list.

## Limitations

- **SafetyNet / Play Integrity will fail** — needs separate PIF module (not included). ZMMO only handles device identity, not attestation.
- **Modem-level IMEI unchanged** — apps reading directly from modem (engineering mode, `*#06#` on some devices) will see real IMEI. Most apps go through TelephonyManager → RILJ and are caught.
- **Android 13+ changes** — some classes moved to APEX modules; may need different hook points.
- **Device-specific builds** — Exynos vs Snapdragon ROMs have different framework layouts. Test on target device.
- **VDEX/OAT format changes** — Android 10+ uses VDEX; baksmali 3.x handles most cases.

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| Bootloop after install | Corrupt framework.jar | Restore backup from `/data/local/tmp/zmmo-backup-*` via TWRP |
| Props not applying | `zmmo-init.rc` not running | Check `adb logcat \| grep zmmo`, verify Magisk module active |
| IMEI still shows real | Property name mismatch | Check `adb shell getprop \| grep persist.zmmo` |
| No SIM detected | RILJ hook breaking RIL | Restore original `telephony-common.jar`, retry with newer baksmali |
| `persist.*` not persisting | Needs `persist` partition support | Fall back to `setprop` at boot via init.rc |

## File Structure

```
packages/rom-patcher/
├── build.sh                      # Main entry point
├── README.md
├── config/
│   └── default-props.json        # Default spoof values
├── patches/
│   ├── telephony-common/         # RILJ hooks
│   │   ├── IccCardProxy.smali.patch
│   │   ├── UiccCardApplication.smali.patch
│   │   ├── PhoneBase.smali.patch
│   │   └── ServiceStateTracker.smali.patch
│   └── framework/                # Framework hooks
│       ├── Build.smali.patch
│       ├── TelephonyManager.smali.patch
│       ├── ZmmoProps.smali       # NEW helper class
│       └── ZmmoTelephony.smali   # NEW helper class
├── magisk/                       # Magisk module template
│   └── module.prop
└── scripts/                      # Toolchain
    ├── extract-framework.sh
    ├── deodex.sh
    ├── patch.sh
    └── repack-magisk.sh
```
