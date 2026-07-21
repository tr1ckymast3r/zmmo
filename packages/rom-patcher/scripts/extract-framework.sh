#!/bin/bash
# Extract framework jars from LineageOS ZIP
# Input:  lineageos.zip
# Output: work_dir/system/framework/*.jar, work_dir/system/framework/oat/

set -euo pipefail

ROM_ZIP="$1"
WORK_DIR="$2"

if [ ! -f "$ROM_ZIP" ]; then
    echo "ERROR: ROM zip not found: $ROM_ZIP"
    exit 1
fi

FRAMEWORK_DIR="$WORK_DIR/system/framework"
mkdir -p "$FRAMEWORK_DIR"

echo "Extracting framework from $(basename "$ROM_ZIP")..."

# List of framework jars to extract
JARS=(
    "system/framework/framework.jar"
    "system/framework/framework.jar.prof"
    "system/framework/telephony-common.jar"
    "system/framework/telephony-common.jar.prof"
    "system/framework/ext.jar"
    "system/framework/services.jar"
    "system/framework/core-oj.jar"
    "system/framework/core-libart.jar"
    "system/framework/boot.jar"
)

# Extract each jar
for jar in "${JARS[@]}"; do
    if unzip -l "$ROM_ZIP" "$jar" 2>/dev/null | grep -q "$jar"; then
        unzip -o "$ROM_ZIP" "$jar" -d "$WORK_DIR/" 2>/dev/null
        echo "  ✓ $jar"
    else
        echo "  ⚠ $jar — not found in ROM (may be A-only or different partition layout)"
    fi
done

# Also extract oat/arm64/*.odex files for deodexing
unzip -o "$ROM_ZIP" "system/framework/oat/arm64/*.odex" -d "$WORK_DIR/" 2>/dev/null || true
unzip -o "$ROM_ZIP" "system/framework/oat/arm/*.odex" -d "$WORK_DIR/" 2>/dev/null || true
unzip -o "$ROM_ZIP" "system/framework/arm64/*.odex" -d "$WORK_DIR/" 2>/dev/null || true

# Extract boot-framework.vdex if present (Android 10+)
unzip -o "$ROM_ZIP" "system/framework/boot-framework.vdex" -d "$WORK_DIR/" 2>/dev/null || true
unzip -o "$ROM_ZIP" "system/framework/boot-telephony-common.vdex" -d "$WORK_DIR/" 2>/dev/null || true

echo ""
echo "Framework extracted:"
ls -lh "$FRAMEWORK_DIR"/*.jar 2>/dev/null || echo "  (no jars found — may be payload.bin ROM)"
ls -lh "$FRAMEWORK_DIR"/oat/arm64/*.odex 2>/dev/null || echo "  (no odex files)"
