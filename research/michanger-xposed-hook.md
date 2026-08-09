# MiChanger — Xposed Framework-Level Device Spoofing

> **Type:** Xposed/LSPosed module (Java)
> **Source:** MiChanger APK analysis, DomaPhoneS Device Changer plan
> **Date:** 2026-08-09

---

## Overview

MiChanger is an Xposed module that hooks Android framework at the Java level to fake device identity. Unlike DOMA (which modifies modem/EFS directly), MiChanger intercepts API calls and returns spoofed values without touching hardware.

```
App → TelephonyManager.getDeviceId()
       │
       ▼
  [Xposed Hook Interception]
       │
  ┌────▼─────────────────────┐
  │ Is spoof enabled?        │
  │  YES → return fake IMEI  │
  │  NO  → call original     │
  └──────────────────────────┘
```

---

## 4-Layer Hook Architecture

```
┌─────────────────────────────────────────────┐
│  LAYER 1: Java Framework (Xposed hooks)      │
│                                              │
│  Hook target classes:                        │
│  • android.telephony.TelephonyManager        │
│  • android.os.Build                          │
│  • android.net.wifi.WifiManager              │
│  • android.bluetooth.BluetoothAdapter        │
│  • android.provider.Settings.Secure          │
│  • android.location.LocationManager          │
│                                              │
│  Method: XposedHelpers.findAndHookMethod()   │
└────────────┬────────────────────────────────┘
             │
┌────────────▼────────────────────────────────┐
│  LAYER 2: RILJ Hook (SIM properties)         │
│                                              │
│  Hook internal telephony classes:            │
│  • com.android.internal.telephony.           │
│    IccCardProxy.getIccId()         → ICCID   │
│  • UiccCardApplication.getImsi()   → IMSI    │
│  • PhoneBase.getLine1Number()      → Phone # │
│  • ServiceStateTracker.                       │
│    getOperatorNumeric()            → MCC+MNC │
│  • IccRecords.                                │
│    getServiceProviderName()        → Carrier  │
│                                              │
│  These are NOT public API — they are          │
│  internal framework classes that feed data   │
│  to the public TelephonyManager API.         │
└────────────┬────────────────────────────────┘
             │
┌────────────▼────────────────────────────────┐
│  LAYER 3: Native ART Hook (JVMTI optional)   │
│                                              │
│  For apps that bypass Java framework:        │
│  • SystemProperties.get()     → ro.* props   │
│  • Build static fields         → mirror      │
│  • WifiService                 → MAC/SSID    │
│                                              │
│  C++ agent loaded via -agentlib at boot      │
└────────────┬────────────────────────────────┘
             │
┌────────────▼────────────────────────────────┐
│  LAYER 4: HAL/Location Spoof                 │
│                                              │
│  • MockLocationProvider                      │
│  • GNSS HAL hook                             │
│  • WifiManager.getScanResults()              │
└─────────────────────────────────────────────┘
```

---

## Key Hook Signatures

### IMEI Hook
```java
XposedHelpers.findAndHookMethod(
    "android.telephony.TelephonyManager",
    lpparam.classLoader,
    "getDeviceId",
    int.class,  // slotIndex
    new XC_MethodHook() {
        @Override
        protected void beforeHookedMethod(MethodHookParam param) {
            int slot = (int) param.args[0];
            String imei = ConfigHook.getFakeImei(slot);
            if (imei != null) {
                param.setResult(imei);  // ← Return fake IMEI
            }
            // else: continue to original method → returns real IMEI
        }
    }
);
```

### ICCID Hook (Internal Framework)
```java
XposedHelpers.findAndHookMethod(
    "com.android.internal.telephony.IccCardProxy",
    lpparam.classLoader,
    "getIccId",
    new XC_MethodHook() {
        @Override
        protected void beforeHookedMethod(MethodHookParam param) {
            String iccid = ConfigHook.getProp("iccid_slot1");
            if (iccid != null) param.setResult(iccid);
        }
    }
);
```

### IMSI Hook (Internal Framework)
```java
XposedHelpers.findAndHookMethod(
    "com.android.internal.telephony.uicc.UiccCardApplication",
    lpparam.classLoader,
    "getImsi",
    new XC_MethodHook() {
        @Override
        protected void beforeHookedMethod(MethodHookParam param) {
            String imsi = ConfigHook.getProp("imsi_slot1");
            if (imsi != null) param.setResult(imsi);
        }
    }
);
```

---

## Hook Point Map (RIL Data Flow)

```
Modem (baseband processor)
  │
  │ AT commands / shared memory
  ▼
rild (Radio Interface Layer Daemon) — native C
  │
  │ Unix socket (/dev/socket/rild)
  ▼
RILJ (Radio Interface Layer Java) — telephony-common.jar
  │
  ├──► IccCardProxy.getIccId()           ── [HOOK] ──► ICCID fake
  ├──► UiccCardApplication.getImsi()     ── [HOOK] ──► IMSI fake
  ├──► PhoneBase.getLine1Number()        ── [HOOK] ──► Phone fake
  ├──► ServiceStateTracker.              
  │     getOperatorNumeric()             ── [HOOK] ──► MCC+MNC fake
  └──► IccRecords.getServiceProviderName()── [HOOK] ──► Carrier fake
  │
  ▼
TelephonyManager (public API)
  │
  ├──► getDeviceId()           ── [HOOK] ──► IMEI fake
  ├──► getSubscriberId()       ── delegates to IMSI hook above
  ├──► getSimSerialNumber()    ── delegates to ICCID hook above
  ├──► getLine1Number()        ── delegates to Phone hook above
  ├──► getNetworkOperator()    ── delegates to MCC+MNC hook above
  └──► getNetworkOperatorName()── delegates to Carrier hook above
  │
  ▼
App (Facebook, Google, Banking, etc.)
```

---

## Config File Format

MiChanger reads from a JSON config, typically at `/data/local/device_config.json`:

```json
{
  "version": 1,
  "props": {
    "imei_slot1":    {"value": "358123456789012", "enabled": true},
    "imei_slot2":    {"value": "358123456789013", "enabled": false},
    "imsi_slot1":    {"value": "452010123456789", "enabled": true},
    "iccid_slot1":   {"value": "89882110000001234567", "enabled": true},
    "phone_number":  {"value": "+84123456789", "enabled": true},
    "sim_operator":  {"value": "45201", "enabled": true},
    "carrier_name":  {"value": "Viettel", "enabled": true},
    "country_iso":   {"value": "vn", "enabled": true},
    
    "brand":         {"value": "samsung", "enabled": true},
    "model":         {"value": "SM-G960F", "enabled": true},
    "manufacturer":  {"value": "samsung", "enabled": true},
    "fingerprint":   {"value": "samsung/starltexx/starlte:10/...", "enabled": true},
    "serial":        {"value": "R58M89ABCDE", "enabled": true},
    
    "wifi_mac":      {"value": "02:00:11:22:33:44", "enabled": true},
    "bt_mac":        {"value": "02:00:AA:BB:CC:DD", "enabled": true},
    
    "android_id":    {"value": "a1b2c3d4e5f6g7h8", "enabled": true},
    "gsf_id":        {"value": "1234567890123456789", "enabled": true}
  }
}
```

---

## MiChanger vs Alternative Approaches

| | MiChanger (Xposed) | Framework Smali-Patch | DOMA (Modem/EFS) |
|---|---|---|---|
| **Cần root?** | Có (Magisk + LSPosed) | Không (prebuilt ROM) | Có |
| **Cần flash ROM?** | Không | Có | Có |
| **Phụ thuộc SoC** | Không | Không | Có |
| **Update process** | Update APK | Re-patch + re-flash | Re-flash ROM |
| **Risk** | Thấp (disable module) | Medium (OTA breaks) | Cao (brick modem) |
| **Detection** | Có (Xposed detect) | Khó hơn | Không |
| **SIM data fake** | ✅ Full | ✅ Full | ✅ Full |
| **GPS fake** | ✅ | ✅ | ✅ |
| **DRM fake** | ✅ | ✅ | ❌ |
| **1 module all devices** | ✅ | ✅ | ❌ |

---

## Detection & Anti-Detection

### How apps detect Xposed:
1. **XposedBridge class** — Check if `de.robv.android.xposed.XposedBridge` exists in classpath
2. **Stack trace inspection** — Xposed hooks leave traces in call stack
3. **Method flags** — Check if method is native and flags modified
4. **File checks** — `/system/framework/XposedBridge.jar`, `/data/data/de.robv.android.xposed.*`

### Mitigations:
- **LSPosed** — Scoped framework (only load hooks for target apps)
- **Hide My Applist** — Hide all Xposed-related packages
- **Magisk DenyList** — Block app from seeing root/Xposed
- **Shamiko** — Bypass root detection without modifying system

---

## For ZMMO Implementation

### MiChanger approach with droid-agent:

```go
// droid-agent writes config that MiChanger reads
func applySpoofProfile(sp *SpoofProfile) {
    // 1. Write build props (resetprop) — already done
    applyResetprop(sp.Props)
    
    // 2. Write spoof.json — already done
    saveSpoofProfile(sp)
    
    // 3. Write MiChanger-compatible config
    writeMiChangerConfig(sp)  // → /data/local/device_config.json
    
    // 4. Signal MiChanger to reload
    am broadcast -a com.michanger.RELOAD_CONFIG
    
    // 5. Kill apps to force re-read
    am force-stop com.google.android.gms
}
```

### Pros:
- No ROM recompilation needed
- Works on any rooted device with LSPosed
- Hot-reload config without reboot
- Agent (droid-agent) already handles JSON config

### Cons:
- Requires LSPosed installation (extra step per device)
- Xposed framework adds detection surface
- LSPosed might conflict with SafetyNet

---

## References

- MiChanger APK: Not available offline (Xposed repo / web analysis)
- Device Changer Plan: `/home/thay/cases/case-domaphone/extracted/.../2026-07-14_device-changer-plan.md`
- DOMA Analysis: `./domaphones-spoofing.md`
- Android Telephony Internals: AOSP `frameworks/opt/telephony/`
