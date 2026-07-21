# ZMMO Samsung Snapdragon Patch Notes

## Overview

Samsung Snapdragon variants (US, China, HK) use **Qualcomm RIL** instead of SamsungRIL.
The common AOSP patches (IccCardProxy, UiccCardApplication, Build, TelephonyManager)
work directly — no additional SamsungRIL hooks needed.

## Key Differences from Exynos

| Aspect | Exynos | Snapdragon |
|--------|--------|------------|
| RIL layer | SamsungRIL + AOSP RILJ | Qualcomm RIL → AOSP RILJ |
| Modem | Shannon (Samsung) | Snapdragon X-series |
| ServiceMode | `*#0011#` Samsung-specific | `*#0011#` Qualcomm-specific |
| Additional hooks | SamsungRIL.smali | None needed |
| CarrierConfig | Samsung CSC | US carrier-specific CSC |
| Bootloader unlock | Easy (OEM unlock) | Hard (US carrier locked) |

## Snapdragon Model Detection

| Model Pattern | Chip | Region |
|--------------|------|--------|
| `SM-GxxxU`, `SM-GxxxU1` | Snapdragon | US |
| `SM-GxxxW` | Snapdragon | Canada |
| `SM-Gxxx0`, `SM-Gxxx8` | Snapdragon | China/HK |
| `SCGxx`, `SC-xxx` | Snapdragon | Japan |
| `SM-GxxxF`, `SM-GxxxFD` | Exynos | Global |

## Snapdragon Platform Names

| Codename | Chip | Models |
|----------|------|--------|
| `msm8998` | SD835 | S8 (dreamqlte) |
| `sdm845` | SD845 | S9 (starqlte), Note9 (crownqlte) |
| `sm8150` | SD855 | S10 (beyond0qlte/beyond1qlte) |
| `sm8250` | SD865 | S20 FE (r8q), Note20 |
| `sm8350` | SD888 | S21 (o1q) |
| `sm8450` | SD8 Gen 1 | S22 (r0q) |
| `sm8550` | SD8 Gen 2 | S23 (dm1q) |

## What Works (Common AOSP Patches)

All common patches apply cleanly because Samsung Snapdragon uses stock AOSP RILJ:

- ✅ `IccCardProxy.getIccId()` → ICCID
- ✅ `UiccCardApplication.getImsi()` → IMSI  
- ✅ `PhoneBase.getLine1Number()` → Phone Number
- ✅ `ServiceStateTracker.getOperatorNumeric()` → SIM Operator
- ✅ `Build.<clinit>` → All 19 device identity fields
- ✅ `TelephonyManager.getDeviceId/getImei/getMeid` → IMEI/MEID

## What Doesn't Need Extra Hooks

- **No SamsungRIL** — Qualcomm RIL feeds directly into AOSP RILJ
- **No SamsungServiceStateTracker** — Not present on Snapdragon ROMs
- **No SamsungPhoneInterfaceManager** — Uses standard AOSP TelephonyManager

Samsung Snapdragon is the easiest Samsung variant to patch — it's essentially AOSP with Samsung's skin.
