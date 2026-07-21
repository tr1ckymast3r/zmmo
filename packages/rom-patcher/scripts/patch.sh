#!/bin/bash
# Apply ZMMO smali patches — Multi-Device + Multi-Version routing
# Priority: device/version > device/any > common/version > common/any
#
# Usage: patch.sh <work_dir> <patch_dir> <device_family> <android_ver>

set -euo pipefail

WORK_DIR="$1"
PATCH_DIR="$2"
DEVICE_FAMILY="${3:-generic}"
ANDROID_VER="${4:-14}"

PATCHER_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS_DIR="$PATCHER_DIR/.tools"
SMALI_JAR="$TOOLS_DIR/baksmali-3.0.5.jar"
SMALI_ASSEMBLE_JAR="$TOOLS_DIR/smali-3.0.5.jar"

FRAMEWORK_DIR="$WORK_DIR/system/framework"
PATCHED_DIR="$WORK_DIR/patched"
mkdir -p "$PATCHED_DIR"

echo "Patches: device=$DEVICE_FAMILY android=$ANDROID_VER"

# --- Resolve patch path for a given target ---
# Returns the best matching patch directory ($PATCH_DIR/<variant>) or empty
resolve_patch() {
    local target="$1"    # e.g. "framework" or "telephony-common"
    local candidates=(
        "$PATCH_DIR/$DEVICE_FAMILY/$ANDROID_VER/$target"   # pixel/13/framework
        "$PATCH_DIR/$DEVICE_FAMILY/any/$target"             # pixel/any/framework
        "$PATCH_DIR/common/$ANDROID_VER/$target"            # common/13/framework
        "$PATCH_DIR/common/any/$target"                     # common/any/framework
    )
    
    for cand in "${candidates[@]}"; do
        if [ -d "$cand" ] && [ "$(ls -A "$cand" 2>/dev/null)" ]; then
            echo "$cand"
            return 0
        fi
    done
    return 1
}

# --- Apply patches to a jar ---
apply_jar_patches() {
    local jar_name="$1"          # "telephony-common" or "framework"
    local jar_path="$FRAMEWORK_DIR/$jar_name.jar"
    local smali_dir="$PATCHED_DIR/$jar_name"
    
    if [ ! -f "$jar_path" ]; then
        echo "  ⚠ $jar_name.jar not found — skipping"
        return
    fi
    
    local patch_source
    patch_source=$(resolve_patch "$jar_name") || {
        echo "  ⚠ No patches for $jar_name ($DEVICE_FAMILY/a$ANDROID_VER) — skipping"
        return
    }
    
    echo "  → $jar_name.jar ← $patch_source"
    
    # Disassemble
    echo -n "    disassembling..."
    java -jar "$SMALI_JAR" d "$jar_path" -o "$smali_dir" 2>/dev/null
    echo " done ($(find "$smali_dir" -name '*.smali' | wc -l) smali files)"
    
    local patched_count=0
    
    # Apply .smali.patch (full replacement)
    for patch in "$patch_source"/*.smali.patch; do
        [ -f "$patch" ] || continue
        local patch_name=$(basename "$patch" .smali.patch)
        
        # Find target smali file (search recursively)
        local target=$(find "$smali_dir" -name "${patch_name}.smali" 2>/dev/null | head -1)
        
        if [ -n "$target" ]; then
            cp "$target" "${target}.orig"
            cp "$patch" "$target"
            echo "    ✓ patched: $patch_name"
            ((patched_count++)) || true
        else
            echo "    ⚠ not found: $patch_name — skipping (may be version-specific)"
        fi
    done
    
    # Add new .smali files (helpers like ZmmoProps, ZmmoTelephony)
    for new_smali in "$patch_source"/*.smali; do
        [ -f "$new_smali" ] || continue
        local smali_name=$(basename "$new_smali")
        # Skip .smali.patch files
        [[ "$smali_name" == *.patch ]] && continue
        
        # Destination: match the package path in the smali file
        local pkg=$(grep "^\.class public" "$new_smali" | sed 's/.*L\(.*\);/\1/' | tr '/' '.' 2>/dev/null || echo "")
        if [ -n "$pkg" ]; then
            local pkg_path=$(echo "$pkg" | tr '.' '/')
            local dest_dir="$smali_dir/$(dirname "$pkg_path")"
            mkdir -p "$dest_dir"
            cp "$new_smali" "$dest_dir/$smali_name"
            echo "    ✓ added: $pkg"
            ((patched_count++)) || true
        fi
    done
    
    # Reassemble
    echo -n "    reassembling..."
    java -jar "$SMALI_ASSEMBLE_JAR" a "$smali_dir" -o "$jar_path" 2>/dev/null
    echo " done ($patched_count patches applied)"
}

# --- Main ---
echo ""

# Patch telephony-common.jar (RILJ hooks)
echo "--- telephony-common.jar ---"
apply_jar_patches "telephony-common"

# Patch framework.jar (Build, TelephonyManager hooks)
echo "--- framework.jar ---"
apply_jar_patches "framework"

echo ""
echo "Patch complete. Device: $DEVICE_FAMILY, Android: $ANDROID_VER"
