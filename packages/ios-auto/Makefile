# ZMMO ios-auto — iOSAutomate clone: Lua scripting + app farming + MCP + Web IDE
ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:12.0
include $(THEOS)/makefiles/common.mk

# ── Daemon (WSDaemon clone) ──
TOOL_NAME = zmmo-autod
zmmo-autod_FILES = daemon/main.mm daemon/WSDaemon.mm daemon/LuaEngine.mm \
                   daemon/AppFarming.mm daemon/DeviceControl.mm \
                   daemon/OCRHelper.mm daemon/MCPServer.mm
zmmo-autod_FRAMEWORKS = Foundation CoreFoundation IOKit Security UIKit \
                         JavaScriptCore CoreLocation CoreTelephony CFNetwork
zmmo-autod_PRIVATE_FRAMEWORKS = MobileGestalt AppSupport SpringBoardServices
zmmo-autod_LIBRARIES = rocketbootstrap
zmmo-autod_INSTALL_PATH = /usr/libexec
zmmo-autod_CODESIGN_FLAGS = -Sentitlements.plist

# ── Tweak (OCR + Touch + Screen hooks) ──
TWEAK_NAME = ZAGMain
ZAGMain_FILES = tweak/ZAGMain/Tweak.x
ZAGMain_FRAMEWORKS = Foundation UIKit Vision ImageIO Accelerate
ZAGMain_PRIVATE_FRAMEWORKS = MobileGestalt
ZAGMain_INSTALL_PATH = /Library/MobileSubstrate/DynamicLibraries

include $(THEOS_MAKE_PATH)/tool.mk
include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install -d $(THEOS_STAGING_DIR)/DEBIAN
	cp scripts/postinst $(THEOS_STAGING_DIR)/DEBIAN/postinst 2>/dev/null || true
	cp scripts/prerm $(THEOS_STAGING_DIR)/DEBIAN/prerm 2>/dev/null || true
	# Copy Web IDE files
	install -d $(THEOS_STAGING_DIR)/var/mobile/Library/ZMMO/ios-auto/webide
	cp webide/* $(THEOS_STAGING_DIR)/var/mobile/Library/ZMMO/ios-auto/webide/ 2>/dev/null || true
