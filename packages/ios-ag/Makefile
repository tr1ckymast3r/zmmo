# ZMMO ios-ag — XoaInfo-based device change agent
# Build: THEOS=/opt/theos make package
# Uses: RocketBootstrap + CPDistributedMessagingCenter IPC
#       4 Targeted hook plugs (profiled, springboard, UIKit)

ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:12.0

include $(THEOS)/makefiles/common.mk

# ── Agent daemon ──
TOOL_NAME = zmmo-ag
zmmo-ag_FILES = agent/main.mm agent/XAGDaemon.mm agent/XAGDeviceInfo.mm agent/XAGSpoofer.mm agent/XAGRRS.mm
zmmo-ag_FRAMEWORKS = Foundation CoreFoundation IOKit Security UIKit
zmmo-ag_PRIVATE_FRAMEWORKS = MobileGestalt AppSupport SpringBoardServices CoreTelephony
zmmo-ag_LIBRARIES = rocketbootstrap
zmmo-ag_INSTALL_PATH = /usr/libexec
zmmo-ag_CODESIGN_FLAGS = -Sentitlements.plist

# ── Tweak Plug3 (profiled hook — MobileGestalt + IMEI) ──
TWEAK_NAME = XAGPlug3
XAGPlug3_FILES = tweak/XAGPlug3/Tweak.x
XAGPlug3_FRAMEWORKS = Foundation CoreTelephony
XAGPlug3_PRIVATE_FRAMEWORKS = MobileGestalt
XAGPlug3_INSTALL_PATH = /Library/MobileSubstrate/DynamicLibraries

# ── Tweak Plug4 (SpringBoard+UIKit — GPS + per-app) ──
TWEAK_NAME_2 = XAGPlug4
XAGPlug4_FILES = tweak/XAGPlug4/Tweak.x
XAGPlug4_FRAMEWORKS = Foundation UIKit CoreLocation
XAGPlug4_PRIVATE_FRAMEWORKS = MobileGestalt
XAGPlug4_INSTALL_PATH = /Library/MobileSubstrate/DynamicLibraries

include $(THEOS_MAKE_PATH)/tool.mk
include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install -d $(THEOS_STAGING_DIR)/DEBIAN
	cp scripts/postinst $(THEOS_STAGING_DIR)/DEBIAN/postinst 2>/dev/null || true
	cp scripts/prerm $(THEOS_STAGING_DIR)/DEBIAN/prerm 2>/dev/null || true
	# Copy bundled databases
	install -d $(THEOS_STAGING_DIR)/Applications/XAG.app/data
	cp data/Model-iPhone.plist data/CarrierList data/MACVendor.txt $(THEOS_STAGING_DIR)/Applications/XAG.app/data/ 2>/dev/null || true

.PHONY: all clean
