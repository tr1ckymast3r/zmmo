#!/bin/bash
# ZMMO ROM Patcher — Toolchain Entry Point (Multi-Device)
# Usage: ./build.sh <rom-zip> [--magisk|--direct] [--device=auto|pixel|samsung-exynos|generic]
#
# Modes:
#   --magisk   → Build a Magisk module (recommended, safer)
#   --direct   → Patch system directly via ADB (device must be rooted, rw)
#   --device   → Override auto-detection: auto (default), pixel, samsung-exynos, generic
#
# Auto-detects:
#   - Device family (Pixel, Samsung Exynos, generic)
#   - Android version (10-14)
#   - Partition layout (A-only, A/B)
#   - ODEX/VDEX format
#
# Output:
#   out/zmmo-rom-patcher-magisk-<device>-<android>-YYMMDD.zip

set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: $0 <rom-zip> [--magisk|--direct] [--device=auto|pixel|samsung-exynos|generic]"
    echo ""
    echo "Examples:"
    echo "  $0 lineage-20-star2lte.zip --magisk                          # Auto-detect S9"
    echo "  $0 lineage-21-panther.zip --magisk --device=pixel            # Force Pixel"
    echo "  $0 lineage-19.1-dreamlte.zip --direct                        # ADB direct patch"
    exit 1
fi

ROM_ZIP="$1"
MODE="${2:---magisk}"
DEVICE_OVERRIDE="auto"

# Parse optional --device= flag
for arg in "$@"; do
    case "$arg" in
        --device=*) DEVICE_OVERRIDE="${arg#--device=}" ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PATCHER_DIR="$(dirname "$SCRIPT_DIR")"
WORK_DIR="$PATCHER_DIR/.work"
OUT_DIR="$PATCHER_DIR/out"
DATE_TAG=$(date +%y%m%d_%H%M)

echo "=== ZMMO ROM Patcher (Multi-Device) ==="
echo "ROM:    $(basename "$ROM_ZIP")"
echo "Mode:   $MODE"

# --- Step 0: Detect device & Android version ---
echo ""
echo "--- [0/6] Detecting device ---"
DETECT_JSON=$("$SCRIPT_DIR/detect-device.sh" "$ROM_ZIP" 2>/dev/null || echo '{"error":"detection failed"}')
DEVICE_FAMILY=$(echo "$DETECT_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('device_family','generic'))" 2>/dev/null || echo "generic")
ANDROID_VER=$(echo "$DETECT_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('android_version','unknown'))" 2>/dev/null || echo "unknown")
ANDROID_SDK=$(echo "$DETECT_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('android_sdk','0'))" 2>/dev/null || echo "0")
IS_LINEAGE=$(echo "$DETECT_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(str(d.get('is_lineageos','false')).lower())" 2>/dev/null || echo "false")
HAS_VDEX=$(echo "$DETECT_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(str(d.get('has_vdex','false')).lower())" 2>/dev/null || echo "false")
PARTITION=$(echo "$DETECT_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('partition_layout','unknown'))" 2>/dev/null || echo "unknown")
DEVICE_MODEL=$(echo "$DETECT_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('model','unknown'))" 2>/dev/null || echo "unknown")
DEVICE_CODENAME=$(echo "$DETECT_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('device','unknown'))" 2>/dev/null || echo "unknown")

# Apply override if set
if [ "$DEVICE_OVERRIDE" != "auto" ]; then
    echo "  ⚠ Device override: $DEVICE_FAMILY → $DEVICE_OVERRIDE"
    DEVICE_FAMILY="$DEVICE_OVERRIDE"
fi

echo "  Device:     $DEVICE_MODEL ($DEVICE_CODENAME)"
echo "  Family:     $DEVICE_FAMILY"
echo "  Android:    $ANDROID_VER (SDK $ANDROID_SDK)"
echo "  LineageOS:  $IS_LINEAGE"
echo "  Partition:  $PARTITION"
echo "  VDEX:       $HAS_VDEX"

# --- Step 1: Setup ---
mkdir -p "$WORK_DIR" "$OUT_DIR"

# Save detection info for later use
echo "$DETECT_JSON" > "$WORK_DIR/device-info.json"

# --- Step 2: Extract framework jars ---
echo ""
echo "--- [2/6] Extracting framework ---"
"$SCRIPT_DIR/extract-framework.sh" "$ROM_ZIP" "$WORK_DIR" "$PARTITION"

# --- Step 3: Deodex ---
echo ""
echo "--- [3/6] Deodexing ($([ "$HAS_VDEX" = "true" ] && echo "VDEX" || echo "ODEX")) ---"
"$SCRIPT_DIR/deodex.sh" "$WORK_DIR"

# --- Step 4: Apply patches ---
echo ""
echo "--- [4/6] Applying patches ($DEVICE_FAMILY / Android $ANDROID_VER) ---"
"$SCRIPT_DIR/patch.sh" "$WORK_DIR" "$PATCHER_DIR/patches" "$DEVICE_FAMILY" "$ANDROID_VER"

# --- Step 5: Repack ---
echo ""
echo "--- [5/6] Repacking ---"
MODULE_TAG="${DEVICE_FAMILY}-a${ANDROID_VER}"
if [ "$MODE" = "--magisk" ]; then
    "$SCRIPT_DIR/repack-magisk.sh" "$WORK_DIR" "$PATCHER_DIR/magisk" "$OUT_DIR" "${MODULE_TAG}-${DATE_TAG}"
elif [ "$MODE" = "--direct" ]; then
    echo "ERROR: --direct mode not yet implemented"
    exit 1
else
    echo "Unknown mode: $MODE"
    exit 1
fi

# --- Step 6: Done ---
echo ""
echo "=== DONE ==="
echo "Device:  $DEVICE_MODEL ($DEVICE_FAMILY)"
echo "Android: $ANDROID_VER (SDK $ANDROID_SDK)"
echo "Output:  $OUT_DIR/"
ls -lh "$OUT_DIR/"
