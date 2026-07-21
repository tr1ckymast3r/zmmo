#!/bin/bash
# Detect device family and Android version from ROM ZIP
# Output: JSON with device info

set -euo pipefail

ROM_ZIP="$1"
WORK_DIR="${2:-/tmp/zmmo-detect}"

mkdir -p "$WORK_DIR"

# --- Extract build.prop ---
unzip -o "$ROM_ZIP" "system/build.prop" -d "$WORK_DIR/" 2>/dev/null || \
unzip -o "$ROM_ZIP" "system/system/build.prop" -d "$WORK_DIR/" 2>/dev/null || true

BUILD_PROP=""
for f in "$WORK_DIR/system/build.prop" "$WORK_DIR/system/system/build.prop"; do
    [ -f "$f" ] && BUILD_PROP="$f" && break
done

if [ -z "$BUILD_PROP" ]; then
    echo '{"error": "build.prop not found in ROM"}'
    exit 1
fi

# --- Parse build.prop ---
ro_build_fingerprint=$(grep "^ro.build.fingerprint=" "$BUILD_PROP" | cut -d= -f2- || echo "unknown")
ro_product_brand=$(grep "^ro.product.brand=" "$BUILD_PROP" | cut -d= -f2- || echo "unknown")
ro_product_model=$(grep "^ro.product.model=" "$BUILD_PROP" | cut -d= -f2- || echo "unknown")
ro_product_device=$(grep "^ro.product.device=" "$BUILD_PROP" | cut -d= -f2- || echo "unknown")
ro_product_board=$(grep "^ro.product.board=" "$BUILD_PROP" | cut -d= -f2- || echo "unknown")
ro_product_cpu_abi=$(grep "^ro.product.cpu.abi=" "$BUILD_PROP" | cut -d= -f2- || echo "unknown")
ro_build_version_sdk=$(grep "^ro.build.version.sdk=" "$BUILD_PROP" | cut -d= -f2- || echo "0")
ro_build_version_release=$(grep "^ro.build.version.release=" "$BUILD_PROP" | cut -d= -f2- || echo "unknown")
ro_build_version_incremental=$(grep "^ro.build.version.incremental=" "$BUILD_PROP" | cut -d= -f2- || echo "unknown")
ro_build_description=$(grep "^ro.build.description=" "$BUILD_PROP" | cut -d= -f2- || echo "unknown")
ro_lineage_version=$(grep "^ro.lineage.version=" "$BUILD_PROP" | cut -d= -f2- || echo "")
ro_cm_version=$(grep "^ro.cm.version=" "$BUILD_PROP" | cut -d= -f2- || echo "")
ro_board_platform=$(grep "^ro.board.platform=" "$BUILD_PROP" | cut -d= -f2- || echo "")
ro_hardware=$(grep "^ro.hardware=" "$BUILD_PROP" | cut -d= -f2- || echo "")

# --- Detect device family and chip variant ---
DEVICE_FAMILY="generic"
CHIP_VARIANT=""

# Pixel detection (brand=google)
if echo "$ro_build_fingerprint" | grep -qiE "google/(sailfish|marlin|taimen|walleye|crosshatch|blueline|bonito|sargo|coral|flame|sunfish|bramble|redfin|barbet|oriole|raven|bluejay|panther|cheetah|lynx|tangorpro|felix|shiba|husky|akita|tokay|caiman|komodo)" ; then
    DEVICE_FAMILY="pixel"
fi

# Google Tensor detection (Pixel 6+) — overrides pixel to pixel-tensor
if echo "$ro_board_platform" | grep -qiE "gs101|gs201|gs301|gs401|tensor" ; then
    DEVICE_FAMILY="pixel"
fi

# === Samsung detection (brand=samsung) ===
if echo "$ro_product_brand" | grep -qi "samsung" || echo "$ro_build_fingerprint" | grep -qi "samsung/" ; then
    
    # --- Determine Samsung chip variant ---
    # Priority: ro.board.platform > ro.hardware > codename pattern > model
    
    # Exynos — board platform contains "universal" or "exynos"
    if echo "$ro_board_platform" | grep -qiE "universal[0-9]+|exynos[0-9]+" ; then
        DEVICE_FAMILY="samsung-exynos"
    
    # Snapdragon — board platform contains "sdm" "msm" "sm" "qcom" "kona" "lahaina" "taro" "kalama" "pineapple"
    elif echo "$ro_board_platform" | grep -qiE "^(sdm|msm|sm|apq|qcom)|kona|lahaina|taro|kalama|pineapple|waipio|palima|monaco" ; then
        DEVICE_FAMILY="samsung-snapdragon"
    
    # MediaTek — board platform starts with "mt"
    elif echo "$ro_board_platform" | grep -qiE "^mt[0-9]+" ; then
        DEVICE_FAMILY="samsung-mediatek"
    
    # Fallback: codename pattern — "qlte" suffix = Qualcomm/Snapdragon
    elif echo "$ro_product_device" | grep -qiE "q(lte|w)" ; then
        # starqlte, beyond0qlte, d1q, d2q, etc.
        if echo "$ro_board_platform" | grep -qiE "universal|exynos" 2>/dev/null; then
            DEVICE_FAMILY="samsung-exynos"  # some codenames use q for quad not qualcomm
        else
            DEVICE_FAMILY="samsung-snapdragon"
        fi
    
    # Fallback: check ro.hardware for chip hints
    elif echo "$ro_hardware" | grep -qiE "qcom|sdm|msm|kona|lahaina|taro|kalama" ; then
        DEVICE_FAMILY="samsung-snapdragon"
    elif echo "$ro_hardware" | grep -qiE "exynos|universal|samsungexynos" ; then
        DEVICE_FAMILY="samsung-exynos"
    elif echo "$ro_hardware" | grep -qiE "^mt[0-9]+" ; then
        DEVICE_FAMILY="samsung-mediatek"
    
    # Last resort: known Exynos codenames (no 'q' before 'lte')
    elif echo "$ro_product_device" | grep -qiE "^(dreamlte|dream2lte|greatlte|crownlte|starlte|star2lte|beyond0lte|beyond1lte|beyond2lte|d1|d2s|d2x)$" ; then
        DEVICE_FAMILY="samsung-exynos"
    
    # Known Snapdragon codenames (has 'q' before 'lte')
    elif echo "$ro_product_device" | grep -qiE "^(dreamqlte|starqlte|star2qlte|crownqlte|beyond0qlte|beyond1qlte|beyond2qlte|d1q|d2q|winner|winners)$" ; then
        DEVICE_FAMILY="samsung-snapdragon"
    
    # Newer models (S20+): x1q/x1s = S20, y2q/y2s = S20+, z3q = S20 Ultra
    elif echo "$ro_product_device" | grep -qiE "^(x1q|x1s|y2q|y2s|z3q|r8q|r8s)$" ; then
        # These can be either Exynos or Snapdragon depending on region
        # Check model number: SM-G98* = Exynos, SM-G98*U = Snapdragon
        if echo "$ro_product_model" | grep -qiE "SM-G[0-9]+U|SM-G[0-9]+W|SCG[0-9]+|SC-[0-9]+" ; then
            DEVICE_FAMILY="samsung-snapdragon"
        else
            DEVICE_FAMILY="samsung-exynos"
        fi
    
    else
        # Unknown Samsung — default to generic but log the board
        echo "  ⚠ Unknown Samsung variant: device=$ro_product_device board=$ro_board_platform hardware=$ro_hardware" >&2
        DEVICE_FAMILY="samsung-unknown"
    fi
fi

# --- Detect Android version ---
SDK=$(echo "$ro_build_version_sdk" | tr -d '[:space:]')
case "$SDK" in
    29) ANDROID_VER="10" ;;
    30) ANDROID_VER="11" ;;
    31) ANDROID_VER="12" ;;
    32) ANDROID_VER="12L" ;;
    33) ANDROID_VER="13" ;;
    34) ANDROID_VER="14" ;;
    35) ANDROID_VER="15" ;;
    *)  ANDROID_VER="$ro_build_version_release" ;;
esac

# --- Detect partition layout ---
PARTITION_LAYOUT="ab"  # default
if unzip -l "$ROM_ZIP" "system/system/build.prop" 2>/dev/null | grep -q "build.prop"; then
    PARTITION_LAYOUT="ab_double_system"
elif unzip -l "$ROM_ZIP" "system/build.prop" 2>/dev/null | grep -q "build.prop"; then
    PARTITION_LAYOUT="a_only"
fi

# --- Detect if ODEX/VDEX ---
HAS_ODEX=false
HAS_VDEX=false
if unzip -l "$ROM_ZIP" "system/framework/oat/arm64/*.odex" 2>/dev/null | grep -q ".odex"; then
    HAS_ODEX=true
fi
if unzip -l "$ROM_ZIP" "system/framework/*.vdex" 2>/dev/null | grep -q ".vdex"; then
    HAS_VDEX=true
fi

# --- Detect if LineageOS ---
IS_LINEAGE=false
if [ -n "$ro_lineage_version" ] || [ -n "$ro_cm_version" ]; then
    IS_LINEAGE=true
fi
if echo "$ro_build_description" | grep -qi "lineage" ; then
    IS_LINEAGE=true
fi

# --- Output JSON ---
cat << JSON
{
  "device_family": "$DEVICE_FAMILY",
  "android_version": "$ANDROID_VER",
  "android_sdk": $SDK,
  "is_lineageos": $IS_LINEAGE,
  "partition_layout": "$PARTITION_LAYOUT",
  "has_odex": $HAS_ODEX,
  "has_vdex": $HAS_VDEX,
  "brand": "$ro_product_brand",
  "model": "$ro_product_model",
  "device": "$ro_product_device",
  "board": "$ro_product_board",
  "cpu_abi": "$ro_product_cpu_abi",
  "platform": "$ro_board_platform",
  "hardware": "$ro_hardware",
  "fingerprint": "$ro_build_fingerprint",
  "build_id": "$ro_build_version_incremental",
  "lineage_version": "$ro_lineage_version"
}
JSON
