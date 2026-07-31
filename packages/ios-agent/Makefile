# ZMMO ios-agent — Theos Build System
# ====================================
# Build:
#   export THEOS=/opt/theos
#   make package
#
# Prerequisites:
#   - Theos installed (https://github.com/theos/theos)
#   - iOS SDK 12.0+ in $THEOS/sdks/
#   - clang for arm64-apple-darwin

# Skip SDK version check (works with newer SDKs)
THEOS_PACKAGE_SCHEME = rootless
ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:12.0

# ── Build both tool and tweak ──
include $(THEOS)/makefiles/common.mk

# === Agent Binary (LaunchDaemon) ===
TOOL_NAME = zmmo-agent
zmmo-agent_FILES = agent/main.mm agent/ZMMOHTTPServer.mm agent/ZMMOCollector.mm agent/ZMMOSpoofer.mm agent/ZMMOBackup.mm
zmmo-agent_FRAMEWORKS = Foundation CoreFoundation IOKit Security
zmmo-agent_PRIVATE_FRAMEWORKS = MobileGestalt
zmmo-agent_INSTALL_PATH = /usr/bin
zmmo-agent_CODESIGN_FLAGS = -Sentitlements.plist

# === Tweak (MobileSubstrate dylib) ===
TWEAK_NAME = ZMMODeviceProof
ZMMODeviceProof_FILES = tweak/Tweak.x
ZMMODeviceProof_FRAMEWORKS = Foundation UIKit CoreLocation
ZMMODeviceProof_PRIVATE_FRAMEWORKS = MobileGestalt
ZMMODeviceProof_INSTALL_PATH = /Library/MobileSubstrate/DynamicLibraries

# === Extra files ===
# Copy the filter plist alongside the tweak
ZMMODeviceProof_FILTER_PLIST = tweak/ZMMODeviceProof.plist

include $(THEOS_MAKE_PATH)/tool.mk
include $(THEOS_MAKE_PATH)/tweak.mk

# ── Layout (LaunchDaemon plist, scripts) ──
# Theos automatically includes layout/ directory in the package

internal-stage::
	@echo "[ZMMO] Stage complete — creating package..."
	@echo "  Agent: /usr/bin/zmmo-agent"
	@echo "  Tweak: /Library/MobileSubstrate/DynamicLibraries/ZMMODeviceProof.dylib"
	@echo "  Config: com.zmmo.deviceinfo.plist"

after-install::
	install -d $(THEOS_STAGING_DIR)/DEBIAN
	cp scripts/postinst $(THEOS_STAGING_DIR)/DEBIAN/postinst 2>/dev/null || true
	cp scripts/prerm $(THEOS_STAGING_DIR)/DEBIAN/prerm 2>/dev/null || true

.PHONY: install-test clean

# Quick test: build and install to local device (requires SSH)
install-test: package
	scp packages/*.deb root@localhost:/tmp/zmmo-iosagent.deb
	ssh root@localhost "dpkg -i /tmp/zmmo-iosagent.deb && rm /tmp/zmmo-iosagent.deb"
