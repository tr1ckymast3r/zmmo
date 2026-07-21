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

# --- Detect device family ---
DEVICE_FAMILY="generic"

# Pixel detection
if echo "$ro_build_fingerprint" | grep -qiE "google/(sailfish|marlin|taimen|walleye|crosshatch|blueline|bonito|sargo|coral|flame|sunfish|bramble|redfin|barbet|oriole|raven|bluejay|panther|cheetah|lynx|tangorpro|felix|shiba|husky|akita|tokay|caiman|komodo)" ; then
    DEVICE_FAMILY="pixel"
fi

# Samsung Exynos detection
if echo "$ro_build_fingerprint" | grep -qiE "samsung/(dreamlte|dream2lte|greatlte|starqlte|star2qlte|crownqlte|beyond0qlte|beyond1qlte|beyond2qlte|beyondx|d1|d2s|d2x|r8q|x1q|y2q|z3q)" ; then
    DEVICE_FAMILY="samsung-exynos"
fi
# Samsung codenames sometimes differ
if echo "$ro_product_device" | grep -qiE "^(dreamlte|dream2lte|greatlte|starqlte|star2qlte|crownqlte|beyond0qlte|beyond1qlte|beyond2qlte|beyondx|d1|d2s|d2x|r8q|x1q|y2q|z3q)$" ; then
    DEVICE_FAMILY="samsung-exynos"
fi
# Check board/platform for Exynos
if echo "$ro_product_board" | grep -qiE "universal[0-9]+|exynos[0-9]+" ; then
    DEVICE_FAMILY="samsung-exynos"
fi

# Google Tensor detection (Pixel 6+)
if echo "$ro_product_board" | grep -qiE "gs101|gs201|gs301|tensor" ; then
    DEVICE_FAMILY="pixel"
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
  "fingerprint": "$ro_build_fingerprint",
  "build_id": "$ro_build_version_incremental",
  "lineage_version": "$ro_lineage_version"
}
JSON
