# ZMMO Pixel Patch: Tensor-specific RILJ hooks
# Target: Pixel 6/7/8 with Google Tensor SoC
# Android 12-14
#
# Pixel ROMs are close to AOSP, so common patches work fine.
# This file documents Pixel-specific differences and edge cases.
#
# Key differences vs generic AOSP:
# 1. Google RIL HAL (radio@1.6) — more modern, but RILJ layer unchanged
# 2. Tensor modem — uses Exynos modem + Google firmware, RILJ is still AOSP
# 3. CarrierConfig changes — Pixel may override operator via CarrierConfigManager
# 4. Adaptive Connectivity Services — can override network info
#
# For Android 13+ on Pixel:
# - framework.jar may be split: framework.jar + framework-ext.jar
# - telephony-common.jar location may vary: /system/framework/ or /system_ext/framework/
# - VDEX-only format (no .odex) — requires vdexExtractor + compact_dex_converter

# === Pixel-specific: CarrierConfigManager bypass ===
# On Pixel, some carrier info comes from CarrierConfig, not RILJ directly.
# This may cause spoofed operator/sim values to be overridden.
#
# Workaround: Set these additional props:
#   persist.zmmo.carrier_config_override=true
#   persist.zmmo.disable_adaptive_connectivity=true
#
# Or patch: com/android/telephony/CarrierConfigManager.smali
#   → intercept getConfigForSubId() to inject spoofed values

# === Pixel-specific: Adaptive Connectivity Services ===  
# Pixel 5+ has Adaptive Connectivity (com.google.android.apps.connectivity)
# which can override network info from RILJ.
#
# Disable with:
#   adb shell pm disable com.google.android.apps.connectivity
# Or add to Magisk module's service.sh:
#   pm disable com.google.android.apps.connectivity

# === Pixel build.prop detection patterns ===
# Tensor G1 (Pixel 6):  gs101,  oriole/raven
# Tensor G2 (Pixel 7):  gs201,  panther/cheetah/lynx
# Tensor G3 (Pixel 8):  gs301/zuma, shiba/husky/akita
# Tensor G4 (Pixel 9):  gs401,  tokay/caiman/komodo
