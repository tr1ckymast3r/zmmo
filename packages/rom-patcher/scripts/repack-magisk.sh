#!/bin/bash
# Repack patched framework into a Magisk module
# Output: out/zmmo-rom-patcher-magisk-YYMMDD_HHMM.zip

set -euo pipefail

WORK_DIR="$1"
MAGISK_TEMPLATE="$2"
OUT_DIR="$3"
DATE_TAG="$4"

PATCHER_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MODULE_DIR="$WORK_DIR/magisk-module"
MODULE_NAME="zmmo-rom-patcher-magisk-${DATE_TAG}"
OUTPUT_ZIP="$OUT_DIR/${MODULE_NAME}.zip"

echo "Building Magisk module..."

# Clean
rm -rf "$MODULE_DIR"
mkdir -p "$MODULE_DIR"

# Copy Magisk module template
if [ -d "$MAGISK_TEMPLATE" ]; then
    cp -r "$MAGISK_TEMPLATE"/* "$MODULE_DIR/"
fi

# Create module.prop
VERSION=$(date +%Y.%m.%d)
cat > "$MODULE_DIR/module.prop" << EOF
id=zmmo-rom-patcher
name=ZMMO ROM Patcher
version=${VERSION}
versionCode=$(date +%Y%m%d)
author=tr1ckymast3r
description=Device identity spoofing framework patches for LineageOS.
  Hooks RILJ, TelephonyManager, and Build for IMEI/IMSI/ICCID/device property spoofing.
  Managed by ZMMO Device Changer panel.
EOF

# Create customize.sh (runs during Magisk install)
cat > "$MODULE_DIR/customize.sh" << 'SCRIPT'
#!/sbin/sh
# ZMMO ROM Patcher — Magisk module install script

MODDIR=${0%/*}

# Mount system framework
mount -o rw,remount /system 2>/dev/null || true

# Backup original files
BACKUP_DIR="/data/local/tmp/zmmo-backup-$(date +%Y%m%d)"
mkdir -p "$BACKUP_DIR"

echo "=== ZMMO ROM Patcher Install ==="
echo "Backing up original framework to $BACKUP_DIR"

FRAMEWORK_DIR="$MODDIR/system/framework"

for jar in "$FRAMEWORK_DIR"/*.jar; do
    [ -f "$jar" ] || continue
    jar_name=$(basename "$jar")
    ORIG="/system/framework/$jar_name"
    
    if [ -f "$ORIG" ]; then
        cp "$ORIG" "$BACKUP_DIR/"
        echo "  Backed up: $jar_name"
    fi
done

echo "Install complete. Reboot to apply patches."
SCRIPT

# Copy patched framework jars
mkdir -p "$MODULE_DIR/system/framework"
for jar in "$WORK_DIR/system/framework"/*.jar; do
    [ -f "$jar" ] || continue
    jar_name=$(basename "$jar")
    
    # Only include patched jars
    case "$jar_name" in
        framework.jar|telephony-common.jar|ext.jar)
            cp "$jar" "$MODULE_DIR/system/framework/"
            echo "  + $jar_name"
            ;;
    esac
done

# Copy ZMMO config init script (sets system props at boot)
mkdir -p "$MODULE_DIR/system/etc/init"
cat > "$MODULE_DIR/system/etc/init/zmmo-init.rc" << 'INIT'
# ZMMO Device Changer — init script
# Sets spoof props at boot (overridden by manager-agent later)

on property:sys.boot_completed=1
    # SIM spoof props
    setprop persist.zmmo.imei_slot1 ""
    setprop persist.zmmo.imei_slot2 ""
    setprop persist.zmmo.meid ""
    setprop persist.zmmo.imsi ""
    setprop persist.zmmo.iccid ""
    setprop persist.zmmo.phone_number ""
    setprop persist.zmmo.sim_operator ""
    setprop persist.zmmo.sim_carrier ""
    
    # Device identity props
    setprop persist.zmmo.brand ""
    setprop persist.zmmo.model ""
    setprop persist.zmmo.manufacturer ""
    setprop persist.zmmo.device ""
    setprop persist.zmmo.product ""
    setprop persist.zmmo.board ""
    setprop persist.zmmo.hardware ""
    setprop persist.zmmo.fingerprint ""
    setprop persist.zmmo.build_id ""
    setprop persist.zmmo.bootloader ""
    setprop persist.zmmo.baseband ""
    setprop persist.zmmo.serialno ""
INIT

# Ensure directory permissions
chmod +x "$MODULE_DIR/customize.sh"
chmod 644 "$MODULE_DIR/system/etc/init/zmmo-init.rc"
chmod 644 "$MODULE_DIR/system/framework"/*.jar

# Create zip
cd "$MODULE_DIR"
zip -qr "$OUTPUT_ZIP" . 
cd - > /dev/null

echo ""
echo "✓ Magisk module: $OUTPUT_ZIP ($(du -h "$OUTPUT_ZIP" | cut -f1))"
