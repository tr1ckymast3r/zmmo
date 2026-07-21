#!/bin/bash
# ZMMO ROM Patcher — Toolchain Entry Point
# Usage: ./build.sh <lineageos-zip> [--magisk] [--direct]
#
# Modes:
#   --magisk   → Build a Magisk module (recommended, safer)
#   --direct   → Patch system directly via ADB (device must be rooted, rw)
#
# Requirements:
#   - Java (JRE 11+)
#   - baksmali/smali.jar (auto-downloaded if missing)
#   - zip/unzip
#   - adb (for --direct mode)
#
# Output:
#   out/zmmo-rom-patcher-magisk-YYMMDD.zip

set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: $0 <lineageos-zip> [--magisk|--direct]"
    echo "Example: $0 lineage-20.0-20250101-UNOFFICIAL-star2lte.zip --magisk"
    exit 1
fi

ROM_ZIP="$1"
MODE="${2:---magisk}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PATCHER_DIR="$(dirname "$SCRIPT_DIR")"
WORK_DIR="$PATCHER_DIR/.work"
OUT_DIR="$PATCHER_DIR/out"
DATE_TAG=$(date +%y%m%d_%H%M)

echo "=== ZMMO ROM Patcher ==="
echo "ROM:    $ROM_ZIP"
echo "Mode:   $MODE"
echo "Patcher: $PATCHER_DIR"

# --- Step 0: Setup ---
mkdir -p "$WORK_DIR" "$OUT_DIR"

# --- Step 1: Extract framework jars from ROM ---
echo ""
echo "--- [1/5] Extracting framework from ROM ---"
"$SCRIPT_DIR/extract-framework.sh" "$ROM_ZIP" "$WORK_DIR"

# --- Step 2: Deodex (if needed) ---
echo ""
echo "--- [2/5] Deodexing framework jars ---"
"$SCRIPT_DIR/deodex.sh" "$WORK_DIR"

# --- Step 3: Apply smali patches ---
echo ""
echo "--- [3/5] Applying ZMMO patches ---"
"$SCRIPT_DIR/patch.sh" "$WORK_DIR" "$PATCHER_DIR/patches"

# --- Step 4: Repack ---
echo ""
echo "--- [4/5] Repacking ---"
if [ "$MODE" = "--magisk" ]; then
    "$SCRIPT_DIR/repack-magisk.sh" "$WORK_DIR" "$PATCHER_DIR/magisk" "$OUT_DIR" "$DATE_TAG"
elif [ "$MODE" = "--direct" ]; then
    "$SCRIPT_DIR/repack-direct.sh" "$WORK_DIR" "$OUT_DIR" "$DATE_TAG"
else
    echo "Unknown mode: $MODE"
    exit 1
fi

# --- Step 5: Done ---
echo ""
echo "=== DONE ==="
echo "Output: $OUT_DIR/"
ls -lh "$OUT_DIR/"
