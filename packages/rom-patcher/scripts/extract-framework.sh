#!/bin/bash
# Extract framework jars from ROM ZIP — handles A-only, A/B, and Pixel partitions
# Usage: extract-framework.sh <rom.zip> <work_dir> [partition_layout]

set -euo pipefail

ROM_ZIP="$1"
WORK_DIR="$2"
PARTITION="${3:-ab_double_system}"

if [ ! -f "$ROM_ZIP" ]; then
    echo "ERROR: ROM zip not found: $ROM_ZIP"
    exit 1
fi

FRAMEWORK_DIR="$WORK_DIR/system/framework"
mkdir -p "$FRAMEWORK_DIR"

echo "ROM: $(basename "$ROM_ZIP")"
echo "Partition layout: $PARTITION"

# --- Resolve prefix path ---
# A/B double-system: system/system/build.prop → prefix = "system/system/"
# A-only: system/build.prop → prefix = "system/"
resolve_prefix() {
    if unzip -l "$ROM_ZIP" "system/system/build.prop" 2>/dev/null | grep -q "build.prop"; then
        echo "system/system/"
    elif unzip -l "$ROM_ZIP" "system/build.prop" 2>/dev/null | grep -q "build.prop"; then
        echo "system/"
    else
        # payload.bin ROM — try payload dumper
        echo ""
    fi
}

PREFIX=$(resolve_prefix)
echo "Path prefix: ${PREFIX:-<payload.bin>}"

if [ -z "$PREFIX" ]; then
    echo "⚠ ROM uses payload.bin format — extract with payload_dumper first"
    echo "  python3 payload_dumper.py payload.bin --out $WORK_DIR/extracted"
    exit 1
fi

# --- Framework jars to extract ---
JARS=(
    "framework.jar"
    "telephony-common.jar"
    "ext.jar"
    "services.jar"
    "core-oj.jar"
    "core-libart.jar"
)

echo ""
echo "Extracting framework jars..."

for jar_name in "${JARS[@]}"; do
    jar_path="${PREFIX}framework/${jar_name}"
    
    if unzip -l "$ROM_ZIP" "$jar_path" 2>/dev/null | grep -q "$jar_path"; then
        unzip -o "$ROM_ZIP" "$jar_path" -d "$WORK_DIR/" 2>/dev/null
        echo "  ✓ $jar_name"
    else
        echo "  ⚠ $jar_name — not found"
    fi
done

# --- Also check system_ext/framework (Pixel 13+) ---
echo ""
echo "Checking system_ext/framework..."

SYSTEM_EXT_JARS=(
    "framework-ext.jar"
    "telephony-ext.jar"
)

for jar_name in "${SYSTEM_EXT_JARS[@]}"; do
    jar_path="${PREFIX}system_ext/framework/${jar_name}"
    
    if unzip -l "$ROM_ZIP" "$jar_path" 2>/dev/null | grep -q "$jar_path"; then
        unzip -o "$ROM_ZIP" "$jar_path" -d "$WORK_DIR/system/system_ext/framework/" 2>/dev/null
        echo "  ✓ system_ext: $jar_name"
    fi
done

# --- Extract ODEX/VDEX ---
echo ""
echo "Checking ODEX/VDEX..."

for fmt in "oat/arm64" "arm64"; do
    odex_path="${PREFIX}framework/${fmt}"
    if unzip -l "$ROM_ZIP" "${odex_path}/*.odex" 2>/dev/null | grep -q ".odex"; then
        unzip -o "$ROM_ZIP" "${odex_path}/*.odex" -d "$WORK_DIR/" 2>/dev/null
        echo "  ✓ ODEX: $fmt"
    fi
done

# VDEX files (Android 10+)
vdex_path="${PREFIX}framework"
if unzip -l "$ROM_ZIP" "${vdex_path}/*.vdex" 2>/dev/null | grep -q ".vdex"; then
    unzip -o "$ROM_ZIP" "${vdex_path}/boot-*.vdex" -d "$WORK_DIR/" 2>/dev/null || true
    echo "  ✓ VDEX files extracted"
fi

# --- Summary ---
echo ""
echo "Extracted framework:"
find "$WORK_DIR" -name "*.jar" -type f 2>/dev/null | while read f; do
    size=$(du -h "$f" | cut -f1)
    echo "  $(basename "$f") ($size)"
done

# Copy to standard location so downstream scripts find them
if [ -d "$WORK_DIR/system/system/framework" ]; then
    cp "$WORK_DIR/system/system/framework"/*.jar "$FRAMEWORK_DIR/" 2>/dev/null || true
fi
