#!/bin/bash
# Deodex framework jars using baksmali
# Converts *.odex → classes.dex, injects back into jars
# Auto-downloads baksmali.jar if not present

set -euo pipefail

WORK_DIR="$1"
PATCHER_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS_DIR="$PATCHER_DIR/.tools"
FRAMEWORK_DIR="$WORK_DIR/system/framework"
OAT_DIR="$FRAMEWORK_DIR/oat/arm64"

# Download baksmali if needed
BAKSMALI_VERSION="3.0.5"
SMALI_JAR="$TOOLS_DIR/baksmali-${BAKSMALI_VERSION}.jar"
SMALI_ASSEMBLE_JAR="$TOOLS_DIR/smali-${BAKSMALI_VERSION}.jar"

if [ ! -f "$SMALI_JAR" ]; then
    echo "Downloading baksmali ${BAKSMALI_VERSION}..."
    mkdir -p "$TOOLS_DIR"
    curl -sL "https://github.com/google/smali/releases/download/v${BAKSMALI_VERSION}/baksmali-${BAKSMALI_VERSION}.jar" -o "$SMALI_JAR"
fi

if [ ! -f "$SMALI_ASSEMBLE_JAR" ]; then
    echo "Downloading smali ${BAKSMALI_VERSION}..."
    curl -sL "https://github.com/google/smali/releases/download/v${BAKSMALI_VERSION}/smali-${BAKSMALI_VERSION}.jar" -o "$SMALI_ASSEMBLE_JAR"
fi

DEODEX_DIR="$WORK_DIR/deodex"
mkdir -p "$DEODEX_DIR"

echo "Deodexing framework jars..."

# Check if jars are already deodexed (have classes.dex)
for jar in "$FRAMEWORK_DIR"/*.jar; do
    [ -f "$jar" ] || continue
    jar_name=$(basename "$jar" .jar)
    
    # Check if already has classes.dex
    if unzip -l "$jar" classes.dex 2>/dev/null | grep -q "classes.dex"; then
        echo "  ✓ $jar_name — already deodexed (has classes.dex)"
        continue
    fi
    
    # Find matching odex file
    odex_file="$OAT_DIR/${jar_name}.odex"
    if [ ! -f "$odex_file" ]; then
        # Try alternate naming: boot-framework.odex vs framework.odex
        odex_file="$OAT_DIR/${jar_name#boot-}.odex"
    fi
    
    if [ -f "$odex_file" ]; then
        echo "  → $jar_name: deodexing..."
        
        # Disassemble: odex → smali
        java -jar "$SMALI_JAR" d \
            -b "$FRAMEWORK_DIR/boot.art" 2>/dev/null || true \
            -o "$DEODEX_DIR/${jar_name}" \
            "$odex_file" 2>/dev/null || {
            echo "    ⚠ baksmali failed for $jar_name — may be VDEX format"
            continue
        }
        
        # Reassemble: smali → dex
        java -jar "$SMALI_ASSEMBLE_JAR" a \
            "$DEODEX_DIR/${jar_name}" \
            -o "$DEODEX_DIR/${jar_name}/classes.dex" 2>/dev/null
        
        # Inject classes.dex back into jar
        cp "$jar" "$jar.bak"
        cd "$DEODEX_DIR/${jar_name}"
        zip -q "$jar" classes.dex 2>/dev/null || true
        cd - > /dev/null
        
        echo "    ✓ deodexed"
    else
        echo "  ⚠ $jar_name — no odex file found"
    fi
done

echo ""
echo "Deodex complete."
