# Framework Smali-Patch — ROM-Level Device Spoofing

> **Source:** DOMA Device Changer Plan (2026-07-14)
> **Type:** AOSP/LineageOS ROM modification — smali patching + ConfigHook injection
> **Target:** Permanent device identity spoofing without Xposed

---

## Core Concept

Instead of using Xposed (which requires runtime hooks), **modify the ROM's framework JARs directly** so spoofing is built into the system from boot. A ConfigHook class is injected into each framework JAR, reading spoof values from a JSON file.

```
                    /data/local/device_config.json
                              │
         ┌────────────────────┼────────────────────┐
         ▼                    ▼                     ▼
telephony-common.jar    framework.jar        services.jar
  ┌─ConfigHook────────┐ ┌─ConfigHook──────┐ ┌─ConfigHook──────┐
  │ getFakeIccId()   │ │ getFakeBrand()  │ │ getFakeWifiMac()│
  │ getFakeImsi()    │ │ getFakeModel()  │ │ getFakeBtMac()  │
  │ getFakePhone()   │ │ getFakeSerial() │ │ getFakeGPS()    │
  │ getFakeSimOp()   │ │ getFakeFinger() │ │                 │
  │ getFakeCarrier() │ │ getFakeSdkVer() │ │                 │
  └──────────────────┘ └─────────────────┘ └─────────────────┘
         │                    │                     │
         ▼                    ▼                     ▼
  ICCID/IMSI/IMEI       Build.* static          Wifi/BT/GPS
  /Phone/Carrier        fields, Settings        addresses
```

---

## How It Works

### Step 1: Decompile framework JARs

```bash
# Pull JARs from device or AOSP build
adb pull /system/framework/telephony-common.jar
adb pull /system/framework/framework.jar
adb pull /system/framework/services.jar

# Decompile to smali
baksmali d telephony-common.jar -o telephony-common-smali/
baksmali d framework.jar -o framework-smali/
baksmali d services.jar -o services-smali/
```

### Step 2: Inject ConfigHook.class

```bash
# Convert ConfigHook.java → smali
javac ConfigHook.java
dx --dex --output=ConfigHook.dex ConfigHook.class
baksmali d ConfigHook.dex -o ConfigHook-smali/

# Copy into each framework directory
cp -r ConfigHook-smali/com/devicechanger/ telephony-common-smali/com/devicechanger/
cp -r ConfigHook-smali/com/devicechanger/ framework-smali/com/devicechanger/
cp -r ConfigHook-smali/com/devicechanger/ services-smali/com/devicechanger/
```

### Step 3: Smali-patch target methods

Each original method gets a guard clause checking ConfigHook:

#### Example: ICCID Hook (IccCardProxy)

```smali
# ── ORIGINAL ──
.method public getIccId()Ljava/lang/String;
    .locals 1
    
    iget-object v0, p0, Lcom/android/internal/telephony/IccCardProxy;->mIccId:Ljava/lang/String;
    return-object v0
.end method

# ── PATCHED ──
.method public getIccId()Ljava/lang/String;
    .locals 1
    
    invoke-static {}, Lcom/devicechanger/ConfigHook;->getFakeIccId()Ljava/lang/String;
    move-result-object v0
    if-eqz v0, :cond_real
    return-object v0              # ← Trả về fake ICCID
    
    :cond_real
    iget-object v0, p0, Lcom/android/internal/telephony/IccCardProxy;->mIccId:Ljava/lang/String;
    return-object v0              # ← Real ICCID
.end method
```

#### Example: IMSI Hook (UiccCardApplication)

```smali
# ── ORIGINAL ──
.method public getImsi()Ljava/lang/String;
    .locals 1
    iget-object v0, p0, ...;->mImsi:Ljava/lang/String;
    return-object v0
.end method

# ── PATCHED ──
.method public getImsi()Ljava/lang/String;
    .locals 1
    invoke-static {}, Lcom/devicechanger/ConfigHook;->getFakeImsi()Ljava/lang/String;
    move-result-object v0
    if-eqz v0, :cond_real
    return-object v0
    :cond_real
    iget-object v0, p0, ...;->mImsi:Ljava/lang/String;
    return-object v0
.end method
```

#### Example: Phone Number Hook (PhoneBase)

```smali
# ── ORIGINAL ──  
.method public getLine1Number()Ljava/lang/String;
    .locals 1
    iget-object v0, p0, ...;->mLine1Number:Ljava/lang/String;
    return-object v0
.end method

# ── PATCHED ──
.method public getLine1Number()Ljava/lang/String;
    .locals 1
    invoke-static {}, Lcom/devicechanger/ConfigHook;->getFakePhone()Ljava/lang/String;
    move-result-object v0
    if-eqz v0, :cond_real
    return-object v0
    :cond_real
    iget-object v0, p0, ...;->mLine1Number:Ljava/lang/String;
    return-object v0
.end method
```

### Step 4: Rebuild JARs

```bash
# Rebuild smali → dex
smali a telephony-common-smali/ -o classes.dex

# Repack JAR
zip -r telephony-common-patched.jar classes.dex
# Keep META-INF, resources, etc.

# Sign if needed (system JARs are resigned with AOSP key)
```

### Step 5: Flash to device

```bash
adb root
adb remount
adb push telephony-common-patched.jar /system/framework/telephony-common.jar
adb push framework-patched.jar /system/framework/framework.jar
adb push services-patched.jar /system/framework/services.jar
adb reboot
```

---

## ConfigHook.java (Injected Class)

```java
package com.devicechanger;

import org.json.JSONObject;
import java.nio.file.Files;
import java.nio.file.Paths;

public class ConfigHook {
    private static JSONObject sConfig;
    private static final String CONFIG_PATH = "/data/local/device_config.json";
    private static long sLastModified = 0;
    
    static {
        loadConfig();
    }
    
    // ── Hot-reload: check file mtime ──
    public static void ensureConfig() {
        try {
            long mtime = Files.getLastModifiedTime(
                Paths.get(CONFIG_PATH)).toMillis();
            if (mtime > sLastModified) {
                loadConfig();
            }
        } catch (Exception e) {
        }
    }
    
    public static void loadConfig() {
        try {
            String json = new String(Files.readAllBytes(
                Paths.get(CONFIG_PATH)));
            sConfig = new JSONObject(json);
            sLastModified = Files.getLastModifiedTime(
                Paths.get(CONFIG_PATH)).toMillis();
        } catch (Exception e) {
        }
    }
    
    // ── SIM / Telephony ──
    public static String getFakeIccId()    { return getProp("iccid_slot1"); }
    public static String getFakeImsi()     { return getProp("imsi_slot1"); }
    public static String getFakeImeiSlot1(){ return getProp("imei_slot1"); }
    public static String getFakeImeiSlot2(){ return getProp("imei_slot2"); }
    public static String getFakePhone()    { return getProp("phone_number"); }
    public static String getFakeSimOp()    { return getProp("sim_operator"); }
    public static String getFakeCarrier()  { return getProp("carrier_name"); }
    public static String getFakeCountry()  { return getProp("country_iso"); }
    
    // ── Build / Device ──
    public static String getFakeBrand()    { return getProp("brand"); }
    public static String getFakeModel()    { return getProp("model"); }
    public static String getFakeManuf()    { return getProp("manufacturer"); }
    public static String getFakeDevice()   { return getProp("device"); }
    public static String getFakeHardware() { return getProp("hardware"); }
    public static String getFakeFinger()   { return getProp("fingerprint"); }
    public static String getFakeSerial()   { return getProp("serial"); }
    public static String getFakeBuildId()  { return getProp("build_id"); }
    
    // ── Network ──
    public static String getFakeWifiMac()  { return getProp("wifi_mac"); }
    public static String getFakeBtMac()    { return getProp("bt_mac"); }
    
    // ── IDs ──
    public static String getFakeAndroidId(){ return getProp("android_id"); }
    public static String getFakeGsfId()    { return getProp("gsf_id"); }
    
    // ── Helper ──
    private static String getProp(String key) {
        try {
            ensureConfig();
            if (sConfig == null) return null;
            JSONObject props = sConfig.optJSONObject("props");
            if (props == null) return null;
            JSONObject prop = props.optJSONObject(key);
            if (prop == null) return null;
            return prop.optBoolean("enabled", false) 
                ? prop.optString("value", null) : null;
        } catch (Exception e) {
            return null;
        }
    }
}
```

---

## Complete Patch Target List

### telephony-common.jar

| File | Method | Property | Priority |
|------|--------|----------|----------|
| IccCardProxy.smali | getIccId() | ICCID | 🔴 CRITICAL |
| UiccCardApplication.smali | getImsi() | IMSI | 🔴 CRITICAL |
| PhoneBase.smali | getLine1Number() | Phone # | 🔴 CRITICAL |
| ServiceStateTracker.smali | getOperatorNumeric() | MCC+MNC | 🔴 CRITICAL |
| IccRecords.smali | getServiceProviderName() | Carrier name | 🔴 CRITICAL |
| TelephonyManager.smali | getDeviceId(int) | IMEI | 🔴 CRITICAL |
| TelephonyManager.smali | getNetworkCountryIso() | Country ISO | 🟡 HIGH |
| TelephonyManager.smali | getGroupIdLevel1() | GID1 | 🟢 MEDIUM |
| TelephonyRegistry.smali | broadcast* | Notify changes | 🟡 HIGH |

### framework.jar

| File | Method | Property | Priority |
|------|--------|----------|----------|
| Build.smali | static fields | BRAND, MODEL, etc | 🟡 HIGH |
| SystemProperties.smali | get() | Filter ro.* props | 🟡 HIGH |
| Settings.Secure.smali | getString() | Android ID | 🟡 HIGH |

### services.jar

| File | Method | Property | Priority |
|------|--------|----------|----------|
| WifiService.smali | getConnectionInfo() | MAC, SSID | 🟡 HIGH |
| BluetoothService.smali | getAddress() | BT MAC | 🟡 HIGH |
| LocationManagerService.smali | getLastLocation() | GPS coords | 🟡 HIGH |

---

## Integration with ZMMO

### Config file reuse

ZMMO's existing `spoof.json` mirrors the device_config.json structure:

```json
// ZMMO spoof.json (already exists)
{
  "name": "Samsung S22 Ultra",
  "props": {
    "ro.product.model": "SM-S9080",
    ...
  },
  "settings": {
    "android_id": "abc123...",
    "sim_operator": "45201"
  },
  "mac_wifi": "02:00:11:22:33:44",
  "imei": "358..."
}

// → droid-agent translates to device_config.json
{
  "props": {
    "model":           {"value": "SM-S9080", "enabled": true},
    "brand":           {"value": "samsung", "enabled": true},
    "android_id":      {"value": "abc123...", "enabled": true},
    "sim_operator":    {"value": "45201", "enabled": true},
    "wifi_mac":        {"value": "02:00:11:22:33:44", "enabled": true},
    "imei_slot1":      {"value": "358...", "enabled": true}
  }
}
```

### droid-agent integration

```go
// spoof.go — add framework config sync
func syncFrameworkConfig(sp *SpoofProfile) error {
    fw := map[string]map[string]string{
        "imei_slot1":    {"value": sp.IMEI, "enabled": toB(sp.IMEI)},
        "imsi_slot1":    {"value": sp.MCCMNC, "enabled": toB(sp.MCCMNC)},
        "iccid_slot1":   {"value": sp.SIMSerial, "enabled": toB(sp.SIMSerial)},
        "phone_number":  {"value": sp.Phone, "enabled": toB(sp.Phone)},
        "sim_operator":  {"value": sp.Operator, "enabled": toB(sp.Operator)},
        "carrier_name":  {"value": sp.Carrier, "enabled": toB(sp.Carrier)},
        "wifi_mac":      {"value": sp.MacWifi, "enabled": toB(sp.MacWifi)},
        "android_id":    {"value": sp.GSFID, "enabled": toB(sp.GSFID)},
    }
    
    config := map[string]interface{}{
        "version": 1,
        "props":   fw,
    }
    
    data, _ := json.MarshalIndent(config, "", "  ")
    return os.WriteFile("/data/local/device_config.json", data, 0644)
}
```

---

## Pros & Cons

### Advantages
- **No Xposed needed** — works on clean ROM
- **Boot-time spoofing** — applied before any app starts
- **Hard to bypass** — no Xposed traces for detection
- **1 patch → all devices** — same ConfigHook for any AOSP-based ROM
- **Hot-reload** — change config file, hooks re-read on next call

### Disadvantages
- **Must flash modified ROM** — overwrites system partition
- **OTA breaks patches** — need to re-patch after system update
- **Signature mismatch** — modified JARs differ from stock checksums
- **Deodex requirement** — stock odexed ROMs need deodexing first
- **Android version specific** — hooks may need adjustment per Android version

---

## Build Script Template

```bash
#!/bin/bash
# patch_framework.sh — applies ConfigHook to AOSP framework JARs

set -e

CONFIG_HOOK_JAVA="ConfigHook.java"
TARGET_JARS=(
    "telephony-common"
    "framework"
    "services"
)

# 1. Compile ConfigHook
javac -cp android.jar $CONFIG_HOOK_JAVA
dx --dex --output=ConfigHook.dex ConfigHook.class
baksmali d ConfigHook.dex -o ConfigHook-smali/

for jar in "${TARGET_JARS[@]}"; do
    echo "Patching $jar.jar..."
    
    # Decompile
    baksmali d ${jar}.jar -o ${jar}-smali/
    
    # Inject ConfigHook
    cp -r ConfigHook-smali/com ${jar}-smali/com/
    
    # Apply patches (custom scripts per JAR)
    case $jar in
        telephony-common)
            patch_iccproxy.sh ${jar}-smali/
            patch_uiccapp.sh ${jar}-smali/
            patch_phonebase.sh ${jar}-smali/
            ;;
        framework)
            patch_build.sh ${jar}-smali/
            patch_sysprops.sh ${jar}-smali/
            ;;
        services)
            patch_wifi.sh ${jar}-smali/
            patch_bt.sh ${jar}-smali/
            ;;
    esac
    
    # Rebuild
    smali a ${jar}-smali/ -o classes.dex
    zip -ur ${jar}.jar classes.dex
    
    echo "  Done: ${jar}.jar"
done

echo "All JARs patched. Flash with:"
echo "  adb root && adb remount && adb push *.jar /system/framework/ && adb reboot"
```

---

## References

- AOSP Source: `frameworks/opt/telephony/` (RILJ internals)
- Smali/Baksmali: https://github.com/JesusFreke/smali
- Device Changer Plan: `/home/thay/zmmo/research/` (original plan)
- DOMA Framework Report: `/home/thay/cases/case-domaphone-rom/FRAMEWORK_PATCH_REPORT.md`
