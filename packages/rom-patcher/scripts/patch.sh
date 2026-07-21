#!/bin/bash
# Apply ZMMO smali patches to deodexed framework jars
# Disassembles jars → applies patches → reassembles
#
# Patch format (.smali.patch): full replacement smali file
# New file (.smali): placed into correct path

set -euo pipefail

WORK_DIR="$1"
PATCH_DIR="$2"
PATCHER_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS_DIR="$PATCHER_DIR/.tools"
SMALI_JAR="$TOOLS_DIR/baksmali-3.0.5.jar"
SMALI_ASSEMBLE_JAR="$TOOLS_DIR/smali-3.0.5.jar"

FRAMEWORK_DIR="$WORK_DIR/system/framework"
PATCHED_DIR="$WORK_DIR/patched"
mkdir -p "$PATCHED_DIR"

echo "Applying patches..."

# --- Patch telephony-common.jar ---
JAR="$FRAMEWORK_DIR/telephony-common.jar"
if [ -f "$JAR" ]; then
    echo "--- telephony-common.jar ---"
    
    # Disassemble
    java -jar "$SMALI_JAR" d "$JAR" -o "$PATCHED_DIR/telephony-common" 2>/dev/null
    
    # Apply each patch
    for patch in "$PATCH_DIR/telephony-common"/*.patch; do
        [ -f "$patch" ] || continue
        patch_name=$(basename "$patch" .smali.patch)
        echo "  → $patch_name"
        
        # Find target smali file
        target=$(find "$PATCHED_DIR/telephony-common" -name "${patch_name}.smali" 2>/dev/null | head -1)
        if [ -z "$target" ]; then
            # Try with full class path
            target=$(find "$PATCHED_DIR/telephony-common" -path "*/${patch_name}.smali" 2>/dev/null | head -1)
        fi
        
        if [ -n "$target" ]; then
            # Copy original and replace
            cp "$target" "${target}.orig"
            cp "$patch" "$target"
            echo "    ✓ patched: $(basename "$target")"
        else
            echo "    ⚠ target smali not found: $patch_name — skipping"
        fi
    done
    
    # Reassemble
    java -jar "$SMALI_ASSEMBLE_JAR" a "$PATCHED_DIR/telephony-common" -o "$JAR" 2>/dev/null
    echo "  ✓ telephony-common.jar reassembled"
fi

# --- Patch framework.jar ---
JAR="$FRAMEWORK_DIR/framework.jar"
if [ -f "$JAR" ]; then
    echo "--- framework.jar ---"
    
    # Disassemble
    java -jar "$SMALI_JAR" d "$JAR" -o "$PATCHED_DIR/framework" 2>/dev/null
    
    # Apply Build.smali patch
    PATCH_FILE="$PATCH_DIR/framework/Build.smali.patch"
    if [ -f "$PATCH_FILE" ]; then
        BUILD_TARGET=$(find "$PATCHED_DIR/framework" -name "Build.smali" 2>/dev/null | head -1)
        if [ -n "$BUILD_TARGET" ]; then
            cp "$BUILD_TARGET" "${BUILD_TARGET}.orig"
            cp "$PATCH_FILE" "$BUILD_TARGET"
            echo "  ✓ Build.smali patched"
        fi
    fi
    
    # Apply TelephonyManager.smali patch
    PATCH_FILE="$PATCH_DIR/framework/TelephonyManager.smali.patch"
    if [ -f "$PATCH_FILE" ]; then
        TM_TARGET=$(find "$PATCHED_DIR/framework" -name "TelephonyManager.smali" 2>/dev/null | head -1)
        if [ -n "$TM_TARGET" ]; then
            cp "$TM_TARGET" "${TM_TARGET}.orig"
            cp "$PATCH_FILE" "$TM_TARGET"
            echo "  ✓ TelephonyManager.smali patched"
        fi
    fi
    
    # Add new smali files (ZmmoProps, ZmmoTelephony)
    ZMMO_DIR="$PATCHED_DIR/framework/zmmo"
    mkdir -p "$ZMMO_DIR"
    for new_smali in "$PATCH_DIR/framework"/*.smali; do
        [ -f "$new_smali" ] || continue
        smali_name=$(basename "$new_smali")
        # Only copy .smali files (not .smali.patch)
        if [[ "$smali_name" != *.patch ]]; then
            cp "$new_smali" "$ZMMO_DIR/"
            echo "  ✓ added: $smali_name"
        fi
    done
    
    # Reassemble
    java -jar "$SMALI_ASSEMBLE_JAR" a "$PATCHED_DIR/framework" -o "$JAR" 2>/dev/null
    echo "  ✓ framework.jar reassembled"
fi

echo ""
echo "Patches applied."
