# ZMMO ios-rmt — Remote clone: VNC screen mirroring + touch + audio
ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:12.0
include $(THEOS)/makefiles/common.mk

# ── Daemon (screen/audio streaming) ──
TOOL_NAME = zmmo-rmtd
zmmo-rmtd_FILES = daemon/main.mm daemon/RMTDaemon.mm daemon/ScreenCapture.mm \
                  daemon/AudioStream.mm daemon/TouchInject.mm daemon/WebSocket.mm \
                  daemon/ZMMOTouch.mm
zmmo-rmtd_FRAMEWORKS = Foundation CoreFoundation IOKit Security UIKit \
                        CoreGraphics CoreVideo AVFoundation Accelerate
zmmo-rmtd_PRIVATE_FRAMEWORKS = AppSupport SpringBoardServices
zmmo-rmtd_LIBRARIES = rocketbootstrap
zmmo-rmtd_INSTALL_PATH = /usr/libexec
zmmo-rmtd_CODESIGN_FLAGS = -Sentitlements.plist

# ── Tweak (floating button + hooks) ──
TWEAK_NAME = ZRMRemote
ZRMRemote_FILES = tweak/ZRMRemote/Tweak.x
ZRMRemote_FRAMEWORKS = Foundation UIKit CoreGraphics
ZRMRemote_INSTALL_PATH = /Library/MobileSubstrate/DynamicLibraries

include $(THEOS_MAKE_PATH)/tool.mk
include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install -d $(THEOS_STAGING_DIR)/DEBIAN
	cp scripts/postinst $(THEOS_STAGING_DIR)/DEBIAN/postinst 2>/dev/null || true
	cp scripts/prerm $(THEOS_STAGING_DIR)/DEBIAN/prerm 2>/dev/null || true
	# Copy web client
	install -d $(THEOS_STAGING_DIR)/var/mobile/Library/ZMMO/ios-rmt/web
	cp webclient/* $(THEOS_STAGING_DIR)/var/mobile/Library/ZMMO/ios-rmt/web/ 2>/dev/null || true
